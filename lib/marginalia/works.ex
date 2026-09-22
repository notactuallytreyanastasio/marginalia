defmodule Marginalia.Works do
  @moduledoc """
  Manuscripts, their sections, and the map built from them.

  Everything here is scoped by `user_id`. A writer's draft is theirs; there is
  no path in this module that returns a work without checking who is asking.
  """

  import Ecto.Query
  alias Marginalia.Repo
  alias Marginalia.Works.{Work, Section, Node, Edge, GraphEvent, Correction, Revision}

  # ==========================================================================
  # Works
  # ==========================================================================

  def list_works(user_id) do
    Work
    |> where([w], w.user_id == ^user_id)
    |> order_by([w], desc: w.id)
    |> Repo.all()
  end

  @doc "Fetch a work the given user owns, or nil. Ownership is checked here, once."
  def get_work(user_id, id) do
    Work
    |> where([w], w.user_id == ^user_id and w.id == ^id)
    |> Repo.one()
  end

  @doc """
  Fetch a work by its slug, with no ownership check.

  This is the sharing model: a draft is unlisted rather than numbered, and the
  slug is 128 bits, so holding the link *is* the permission to read it. It is
  deliberately a separate function from `get_work/2` — every caller has to
  choose which one it wants, and anything that spends money or changes the
  draft must use the owner-scoped one.
  """
  def get_by_slug(slug) when is_binary(slug), do: Repo.get_by(Work, slug: slug)
  def get_by_slug(_), do: nil

  @doc """
  Every draft on the public face of this deploy, newest first.

  The drafts of the account this deploy belongs to, and nobody else's. A
  visitor's own uploads stay private to their link, which is what
  `get_by_slug/1` has always given them; this is only the owner choosing to
  put their own work out.
  """
  def public_drafts do
    case Marginalia.Accounts.owner() do
      nil ->
        []

      owner ->
        Work
        |> where([w], w.user_id == ^owner.id)
        |> order_by([w], desc: w.inserted_at)
        |> Repo.all()
    end
  end

  @doc """
  A public draft by slug, or nil.

  Scoped to the owner's account on purpose. Without that check this would
  serve any draft anybody had ever uploaded, which is the opposite of what
  the link-is-the-permission model promises everyone else.
  """
  def public_draft(slug) when is_binary(slug) do
    case Marginalia.Accounts.owner() do
      nil -> nil
      owner -> Repo.one(from w in Work, where: w.slug == ^slug and w.user_id == ^owner.id)
    end
  end

  def public_draft(_), do: nil

  @doc "Whether this user owns this work. `nil` user owns nothing."
  def owner?(%Work{user_id: uid}, %{id: uid}) when not is_nil(uid), do: true
  def owner?(_work, _user), do: false

  def get_work!(user_id, id) do
    case get_work(user_id, id) do
      nil -> raise Ecto.NoResultsError, queryable: Work
      work -> work
    end
  end

  def change_work(work \\ %Work{}, attrs \\ %{}), do: Work.changeset(work, attrs)

  @doc """
  Create a work and split it into sections in one transaction.

  The split is deterministic and never involves a model — segmentation
  mistakes are cheap to fix by hand and expensive to debug when an LLM made
  them for reasons it cannot explain.
  """
  def create_work(user_id, attrs) do
    changeset =
      %Work{user_id: user_id}
      |> Work.changeset(attrs)

    Repo.transaction(fn ->
      with {:ok, work} <- Repo.insert(changeset),
           {:ok, _n} <- insert_sections(work) do
        # The body is maintained as the join of its sections — `rebuild_work_body`
        # does that after every edit — but on arrival it was still the raw
        # upload, which the segmenter has since normalised. Those differ by
        # whitespace, so a draft's body silently changed shape the first time
        # anyone edited it, and a baseline captured from the raw text could
        # never be replayed into the body exactly.
        #
        # Settling both here means baseline + patches == body from the first
        # moment, which is the property the diff view rests on.
        joined = work.id |> list_sections() |> Enum.map_join("\n\n", & &1.body)

        {:ok, work} =
          work
          |> Ecto.Changeset.change(baseline_body: joined, body: joined)
          |> Repo.update()

        work
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_sections(work) do
    rows =
      work.body
      |> Marginalia.Works.Segmenter.split()
      |> Enum.with_index(1)
      |> Enum.map(fn {%{title: title, body: body}, i} ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        %{
          work_id: work.id,
          ordinal: i,
          title: title,
          body: body,
          word_count: length(String.split(body, ~r/\s+/, trim: true)),
          status: "pending",
          inserted_at: now,
          updated_at: now
        }
      end)

    case rows do
      [] -> {:error, :no_sections}
      rows -> {:ok, Repo.insert_all(Section, rows)}
    end
  end

  @doc """
  The summary drafted from this one, if there is one.

  A title match would have done until somebody renames the draft, which is
  the first thing anybody does to one they mean to keep.
  """
  def condensation_of(work_id) do
    Repo.one(
      from w in Work, where: w.derived_from_id == ^work_id, order_by: [desc: w.id], limit: 1
    )
  end

  def update_work(%Work{} = work, attrs) do
    work |> Work.changeset(attrs) |> Repo.update()
  end

  def set_status(%Work{} = work, status, detail \\ nil) do
    work
    |> Ecto.Changeset.change(status: status, status_detail: detail)
    |> Repo.update()
  end

  def delete_work(%Work{} = work), do: Repo.delete(work)

  # ==========================================================================
  # Sections
  # ==========================================================================

  def list_sections(work_id) do
    Section
    |> where([s], s.work_id == ^work_id)
    |> order_by([s], asc: s.ordinal)
    |> Repo.all()
  end

  def get_section(work_id, ordinal) do
    Repo.get_by(Section, work_id: work_id, ordinal: ordinal)
  end

  def set_section_status(%Section{} = section, status) do
    section |> Ecto.Changeset.change(status: status) |> Repo.update()
  end

  # ==========================================================================
  # Nodes and edges
  # ==========================================================================

  def list_nodes(work_id, opts \\ []) do
    Node
    |> where([n], n.work_id == ^work_id)
    |> maybe_type(opts[:type])
    |> maybe_section(opts[:section_id])
    |> order_by([n], asc: n.ordinal, asc: n.id)
    |> Repo.all()
  end

  defp maybe_type(q, nil), do: q
  defp maybe_type(q, type), do: where(q, [n], n.node_type == ^type)
  defp maybe_section(q, nil), do: q
  defp maybe_section(q, id), do: where(q, [n], n.section_id == ^id)

  def get_node(work_id, id) do
    Node |> where([n], n.work_id == ^work_id and n.id == ^id) |> Repo.one()
  end

  @doc "Insert one node. Returns the changeset error rather than swallowing it."
  def insert_node(attrs) do
    %Node{} |> Node.changeset(attrs) |> Repo.insert()
  end

  @doc "Mark an option chosen/rejected, or a node superseded. Scoped to the work."
  def set_node_status(work_id, node_id, status) do
    case get_node(work_id, node_id) do
      nil ->
        {:error, :not_found}

      node ->
        node
        |> Node.changeset(%{
          work_id: work_id,
          node_type: node.node_type,
          title: node.title,
          status: status
        })
        |> Repo.update()
    end
  end

  def insert_nodes(work_id, section_id, attrs_list) do
    attrs_list
    |> Enum.with_index()
    |> Enum.reduce([], fn {attrs, i}, acc ->
      attrs =
        attrs
        |> Map.put(:work_id, work_id)
        |> Map.put(:section_id, section_id)
        |> Map.put_new(:ordinal, i)

      case %Node{} |> Node.changeset(attrs) |> Repo.insert() do
        {:ok, node} ->
          [node | acc]

        {:error, changeset} ->
          require Logger

          Logger.warning(
            "marginalia: node rejected: #{inspect(Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end))}"
          )

          acc
      end
    end)
    |> Enum.reverse()
  end

  def link(work_id, from_id, to_id, type \\ "leads_to", ordinal \\ 0, rationale \\ nil) do
    %Edge{}
    |> Edge.changeset(%{
      work_id: work_id,
      from_id: from_id,
      to_id: to_id,
      edge_type: type,
      ordinal: ordinal,
      rationale: rationale
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  def list_edges(work_id) do
    Edge
    |> where([e], e.work_id == ^work_id)
    |> order_by([e], asc: e.ordinal, asc: e.id)
    |> Repo.all()
  end

  def counts(work_id) do
    types =
      Node
      |> where([n], n.work_id == ^work_id)
      |> group_by([n], n.node_type)
      |> select([n], {n.node_type, count(n.id)})
      |> Repo.all()
      |> Map.new()

    %{
      beats: Map.get(types, "beat", 0),
      spine: Map.get(types, "spine", 0),
      notes: Map.get(types, "note", 0),
      questions: Map.get(types, "question", 0),
      threads: Map.get(types, "thread", 0),
      total: types |> Map.values() |> Enum.sum()
    }
  end

  @doc """
  Token-scored search across this work's nodes and its raw section text.

  Searching the source as well as the map is what lets the chat answer "where
  do I actually say that?" without ever loading the manuscript into context.
  """
  def search(work_id, query, limit \\ 12) do
    terms =
      (query || "")
      |> String.downcase()
      |> String.split(~r/[^a-z0-9']+/, trim: true)
      |> Enum.reject(&(String.length(&1) < 3))

    if terms == [] do
      []
    else
      work_id
      |> list_nodes()
      |> Enum.map(fn n ->
        text = String.downcase("#{n.title} #{n.body} #{n.quote}")
        {n, Enum.count(terms, &String.contains?(text, &1))}
      end)
      |> Enum.filter(fn {_n, s} -> s > 0 end)
      |> Enum.sort_by(fn {n, s} -> {-s, n.id} end)
      |> Enum.take(limit)
      |> Enum.map(&elem(&1, 0))
    end
  end

  @doc "Exact-ish lookup in the writer's own text. Returns short windows around each hit."
  def find_in_source(work_id, phrase, limit \\ 5) do
    needle = phrase |> String.downcase() |> String.trim()

    if needle == "" do
      []
    else
      work_id
      |> list_sections()
      |> Enum.flat_map(fn s ->
        hay = String.downcase(s.body)

        case :binary.match(hay, needle) do
          {pos, len} ->
            start = max(pos - 160, 0)
            window = String.slice(s.body, start, len + 320)
            [%{section: s.title, ordinal: s.ordinal, window: window}]

          :nomatch ->
            []
        end
      end)
      |> Enum.take(limit)
    end
  end

  # ==========================================================================
  # Graph build trace
  # ==========================================================================

  @doc """
  Record one tool call and its answer.

  Never raises and never blocks the build: a trace that fails to write is a
  lost line in a log, not a reason to abandon a graph that is half-built.
  """
  def record_event(attrs) do
    %GraphEvent{}
    |> GraphEvent.changeset(attrs)
    |> Repo.insert()
  rescue
    error ->
      require Logger
      Logger.warning("marginalia: graph event not recorded: #{inspect(error)}")
      {:error, :not_recorded}
  end

  def list_events(work_id) do
    GraphEvent
    |> where([e], e.work_id == ^work_id)
    |> order_by([e], asc: e.id)
    |> Repo.all()
  end

  @doc """
  Throw away everything a read produced, so it can be run again from clean.

  A read that failed part-way leaves nodes behind; without this a retry stacks
  a second set on top and the receipt double-counts.
  """
  def reset_read(work_id) do
    Repo.transaction(fn ->
      ids = Node |> where([n], n.work_id == ^work_id) |> select([n], n.id) |> Repo.all()
      Repo.delete_all(from e in Edge, where: e.from_id in ^ids or e.to_id in ^ids)
      Repo.delete_all(from n in Node, where: n.work_id == ^work_id)
      clear_events(work_id)

      Section
      |> where([s], s.work_id == ^work_id)
      |> Repo.update_all(set: [status: "pending"])

      :ok
    end)
  end

  @doc """
  Throw away the decision-graph layer, leaving the read intact.

  Rebuilding used to stack a second graph on top of the first: two sets of
  goals, two chains per narrative, and every node from the previous run still
  hanging there with edges pointing into a graph that had been superseded.
  That is what a "disjointed graph with orphans" looks like from the inside.
  The beats, spine and threads are the read and are not touched.
  """
  @decision_types ~w(goal option decision action outcome observation revisit)

  def reset_decision_graph(work_id) do
    Repo.transaction(fn ->
      ids =
        Node
        |> where([n], n.work_id == ^work_id and n.node_type in ^@decision_types)
        |> select([n], n.id)
        |> Repo.all()

      Repo.delete_all(from e in Edge, where: e.from_id in ^ids or e.to_id in ^ids)
      Repo.delete_all(from n in Node, where: n.id in ^ids)
      clear_events(work_id)
      length(ids)
    end)
  end

  @doc "Clear the trace for a work, so a rebuild's log is not read as one run."
  def clear_events(work_id) do
    GraphEvent |> where([e], e.work_id == ^work_id) |> Repo.delete_all()
  end

  @doc """
  What the run refused, and why — the summary that makes a build auditable.
  """
  def event_stats(work_id) do
    events = list_events(work_id)

    %{
      calls: length(events),
      refused: Enum.count(events, &(&1.ok == false)),
      by_tool: Enum.frequencies_by(events, & &1.tool),
      refusals:
        events
        |> Enum.reject(& &1.ok)
        |> Enum.frequencies_by(&refusal_kind/1)
    }
  end

  defp refusal_kind(%GraphEvent{result: result}) do
    cond do
      result == nil -> "unknown"
      String.contains?(result, "character for character") -> "quote not in draft"
      String.contains?(result, "flow rule") -> "flow rule"
      String.contains?(result, "not a step in") -> "flow rule"
      String.contains?(result, "unknown node id") -> "unknown node id"
      true -> "other"
    end
  end

  # ==========================================================================
  # --- revisions -------------------------------------------------------------

  defp record_revision(%Section{} = section, before, aft, opts) do
    seq =
      Revision
      |> where([r], r.work_id == ^section.work_id)
      |> select([r], coalesce(max(r.seq), 0))
      |> Repo.one()

    %Revision{}
    |> Revision.changeset(%{
      work_id: section.work_id,
      section_id: section.id,
      section_ordinal: section.ordinal,
      seq: seq + 1,
      before: before,
      after: aft,
      origin: to_string(opts[:origin] || "edit"),
      note: opts[:note]
    })
    |> Repo.insert()
  end

  @doc "Every change to a draft's prose, oldest first."
  def revisions(work_id) do
    Revision
    |> where([r], r.work_id == ^work_id)
    |> order_by([r], asc: r.seq)
    |> Repo.all()
  end

  @doc "How many changes a draft has had."
  def revision_count(work_id),
    do: Repo.one(from r in Revision, where: r.work_id == ^work_id, select: count(r.id))

  @doc """
  The prose as it arrived.

  Falls back to the current body for a draft that predates any history: it
  has no recorded changes, so "as it arrived" and "as it is" are the same
  thing, and that is the truth rather than a placeholder.
  """
  def baseline(%Work{baseline_body: b}) when is_binary(b) and b != "", do: b

  # No stored baseline: the draft predates the column. Falling back to the
  # current body was wrong in the one case that matters — a draft with
  # revisions diffs against itself and the Changes view reports that nothing
  # has happened, while the history plainly says otherwise.
  #
  # Every revision holds the text before and after it, so the baseline is
  # recoverable: take the body and un-apply them newest first. A revision
  # whose `after` is no longer present is skipped rather than guessed at, so
  # the worst case is a baseline that is too recent, never one that is
  # invented.
  def baseline(%Work{} = work) do
    work.id
    |> revisions()
    |> Enum.reverse()
    |> Enum.reduce(work.body, fn rev, body ->
      if String.contains?(body, rev.after),
        do: String.replace(body, rev.after, rev.before, global: false),
        else: body
    end)
  end

  @doc """
  Replay every revision over the baseline.

  The property the diff view rests on: patches applied in order reproduce the
  body. Returns `{:ok, body}`, or `{:error, seq}` naming the first revision
  whose `before` is no longer present — which means the history and the draft
  have parted company, and is worth knowing rather than papering over.
  """
  def replay(work_id) do
    work = Repo.get!(Work, work_id)

    Enum.reduce_while(revisions(work_id), {:ok, baseline(work)}, fn rev, {:ok, body} ->
      if String.contains?(body, rev.before) do
        {:cont, {:ok, String.replace(body, rev.before, rev.after, global: false)}}
      else
        {:halt, {:error, rev.seq}}
      end
    end)
  end

  # Corrections — what the writer has already told us
  # ==========================================================================

  def record_correction(attrs) do
    %Correction{} |> Correction.changeset(attrs) |> Repo.insert()
  end

  def list_corrections(work_id) do
    Correction
    |> where([c], c.work_id == ^work_id)
    |> order_by([c], desc: c.id)
    |> Repo.all()
  end

  @doc """
  Edges of the kinds Pass 3 draws, with the node on the other end.

  Returns `{outgoing, incoming}` so a caller can say both "this leads to" and
  "this follows from" without two queries and two joins at the call site.
  """
  def connections(work_id, node_id) do
    kinds = Marginalia.Analysis.Weave.types()
    nodes = work_id |> list_nodes() |> Map.new(&{&1.id, &1})

    edges =
      work_id
      |> list_edges()
      |> Enum.filter(&(&1.edge_type in kinds))

    out =
      edges
      |> Enum.filter(&(&1.from_id == node_id))
      |> Enum.map(&%{type: &1.edge_type, why: &1.rationale, node: nodes[&1.to_id]})
      |> Enum.reject(&is_nil(&1.node))

    into =
      edges
      |> Enum.filter(&(&1.to_id == node_id))
      |> Enum.map(&%{type: &1.edge_type, why: &1.rationale, node: nodes[&1.from_id]})
      |> Enum.reject(&is_nil(&1.node))

    {out, into}
  end

  @doc "Every cross-section connection in the work, for a whole-draft view."
  def all_connections(work_id) do
    kinds = Marginalia.Analysis.Weave.types()
    nodes = work_id |> list_nodes() |> Map.new(&{&1.id, &1})

    work_id
    |> list_edges()
    |> Enum.filter(&(&1.edge_type in kinds))
    |> Enum.map(fn e ->
      %{type: e.edge_type, why: e.rationale, from: nodes[e.from_id], to: nodes[e.to_id]}
    end)
    |> Enum.reject(&(is_nil(&1.from) or is_nil(&1.to)))
  end

  # ==========================================================================
  # Editing the draft
  # ==========================================================================

  @doc """
  Replace one block of a section with new text.

  Everything in this app is anchored: a beat, a connection, a thread quote is
  a literal substring of the draft. Editing a paragraph can therefore leave
  notes pointing at a sentence that no longer exists. Those are marked
  `superseded` rather than deleted — the observation may still be true, and
  throwing away a reader's work because a comma moved is worse than showing
  it greyed with a note that the line changed.

  The section keeps its boundaries. Re-splitting the draft would renumber
  every section and detach every note in the work, which is not what
  "I fixed a sentence" should cost.

  Returns `{:ok, %{section:, superseded:}}`.
  """
  def replace_block(%Section{} = section, old_block, new_text, opts \\ []) do
    old_block = to_string(old_block)

    # The draft arrived one sentence per line (see `Works.Sentences`), and
    # an edit is the one way that form could drift: a paragraph typed or
    # pasted into the editor comes back as one line, or hard-wrapped. It is
    # reflowed here, before the comparison below, so the revision records
    # exactly what was stored and the replay still reproduces the body.
    new_text =
      new_text |> to_string() |> String.trim_trailing() |> Marginalia.Works.Sentences.reflow()

    cond do
      String.trim(new_text) == "" ->
        {:error, :empty}

      new_text == old_block ->
        {:ok, %{section: section, superseded: 0}}

      not String.contains?(section.body, old_block) ->
        {:error, :moved}

      true ->
        Repo.transaction(fn ->
          body = String.replace(section.body, old_block, new_text, global: false)

          {:ok, section} =
            section
            |> Ecto.Changeset.change(
              body: body,
              word_count: length(String.split(body, ~r/\s+/, trim: true))
            )
            |> Repo.update()

          n = supersede_unanchored(section)

          # Inside the same transaction as the write. A history kept beside
          # the thing it describes drifts from it the first time one of the
          # two fails; here they commit together or neither does.
          {:ok, revision} = record_revision(section, old_block, new_text, opts)

          rebuild_work_body(section.work_id)

          %{section: section, superseded: n, revision: revision}
        end)
    end
  end

  # A note whose quote is no longer in the section is marked, not removed.
  defp supersede_unanchored(%Section{} = section) do
    section.work_id
    |> list_nodes(section_id: section.id)
    |> Enum.filter(fn n ->
      n.quote not in [nil, ""] and n.status != "superseded" and
        Marginalia.Analysis.Anchor.verify(n.quote, section.body) == :error
    end)
    |> Enum.reduce(0, fn n, acc ->
      case set_node_status(section.work_id, n.id, "superseded") do
        {:ok, _} -> acc + 1
        _ -> acc
      end
    end)
  end

  # the work's body is the sections joined back up, so an export or a re-read
  # sees what the writer sees
  defp rebuild_work_body(work_id) do
    body =
      work_id
      |> list_sections()
      |> Enum.map_join("\n\n", & &1.body)

    Work
    |> where([w], w.id == ^work_id)
    |> Repo.update_all(
      set: [
        body: body,
        word_count: length(String.split(body, ~r/\s+/, trim: true)),
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end

  @doc "Notes in this work whose line has changed under them."
  def superseded_count(work_id) do
    Node
    |> where([n], n.work_id == ^work_id and n.status == "superseded")
    |> Repo.aggregate(:count)
  end
end
