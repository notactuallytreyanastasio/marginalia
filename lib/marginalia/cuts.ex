defmodule Marginalia.Cuts do
  @moduledoc """
  Reading a folder: what a group of drafts says that none of them says alone.

  `Marginalia.Analysis` reads one manuscript into a map. This reads a *folder*
  into one, and the two are the same shape one level apart.

  A folder of drafts is read over the maps its drafts already have — their
  nodes, their quotes — not over their raw text. Eight opinions at ten
  thousand words each do not fit in a prompt, and would not be worth the money
  if they did: the map is the part that was already worth keeping.

  A folder of *folders* is read over its children's readings. That is where
  "higher order" stops being a word and starts being a mechanism — the input
  to a case-law folder is what each case turned out to say, so the answer is
  about the cases rather than about paragraphs. It also means the cost of
  reading the top of a tree does not grow with the size of the tree.

  Whatever the level, the same rule holds: every claim must quote something
  that was actually sent, and name which member it came from. Two citations
  are the floor, because a claim resting on one member is a restatement of
  that member rather than a finding about the group. Anything that cannot be
  located is dropped and counted.
  """

  import Ecto.Query

  alias Marginalia.{Folders, LLM, Repo, Works}
  alias Marginalia.Cuts.Cut

  # ==========================================================================
  # Quoting
  # ==========================================================================

  @doc """
  Find `needle` in `haystack` and return *the haystack's own wording*.

  Quoting has to tolerate re-wrapping and nothing else. Prose here is stored
  with the line breaks it was written with, and a model asked to cite a
  passage reflows it — so a byte-exact test rejects almost every true citation
  for a reason that means nothing about whether the model read the text.

  Collapsing whitespace on both sides costs no strictness that matters: every
  token must still be present, in order, in that passage. What comes back is
  located through an index back into the original, so what gets stored is the
  draft's own characters rather than the model's version of them.
  """
  def locate(needle, haystack)
      when is_binary(needle) and is_binary(haystack) do
    cond do
      String.trim(needle) == "" -> nil
      String.contains?(haystack, needle) -> needle
      true -> locate_loose(needle, haystack)
    end
  end

  def locate(_, _), do: nil

  defp locate_loose(needle, haystack) do
    flat_needle = needle |> String.replace(~r/\s+/, " ") |> String.trim()
    {flat_hay, back} = flatten(haystack)

    case flat_needle != "" and :binary.match(flat_hay, flat_needle) do
      {at, len} ->
        start = Enum.at(back, at)
        stop = Enum.at(back, at + len - 1)
        binary_part(haystack, start, stop - start + 1)

      _ ->
        nil
    end
  end

  # the whitespace-collapsed string, plus each byte's offset in the original
  defp flatten(text) do
    text
    |> :binary.bin_to_list()
    |> Enum.with_index()
    |> Enum.reduce({[], [], false}, fn {byte, i}, {out, back, prev_ws?} ->
      cond do
        byte in [?\s, ?\n, ?\t, ?\r] ->
          if prev_ws? or out == [], do: {out, back, true}, else: {[?\s | out], [i | back], true}

        true ->
          {[byte | out], [i | back], false}
      end
    end)
    |> then(fn {out, back, _} ->
      {out |> Enum.reverse() |> :binary.list_to_bin(), Enum.reverse(back)}
    end)
  end

  # ==========================================================================
  # Who is being read
  # ==========================================================================

  @doc """
  The members of a folder reading, and the text each one contributes.

  Subfolders win over drafts. A folder holding both is read at the level of
  its subfolders, because mixing "what this case held" with "what this
  paragraph says" in one prompt produces an answer that is about neither.
  """
  def members(user_id, folder_id) do
    node = folder_node(user_id, folder_id)

    cond do
      node == nil -> []
      node.folders != [] -> child_members(user_id, node)
      true -> work_members(node.works)
    end
  end

  defp folder_node(user_id, folder_id) do
    user_id
    |> Folders.tree()
    |> find_node(folder_id)
  end

  defp find_node(%{folders: folders}, id) do
    Enum.find_value(folders, fn f ->
      if f.folder.id == id, do: f, else: find_node(f, id)
    end)
  end

  defp child_members(user_id, node) do
    node.folders
    |> Enum.with_index(1)
    |> Enum.map(fn {child, n} ->
      cut = get_folder_cut(user_id, child.folder.id)

      %{
        n: n,
        kind: "folder",
        id: child.folder.id,
        label: child.folder.name,
        read?: cut != nil and cut.status == "read",
        text: child_text(cut, child)
      }
    end)
  end

  # A child that has been read contributes its reading. One that has not
  # contributes the titles of what is in it, and says so — an unread child is
  # a hole in the answer and the reader should be able to see where.
  defp child_text(nil, child), do: "(not read yet) holds: " <> titles(child)

  defp child_text(%Cut{status: "read"} = cut, _child) do
    threads = Enum.map_join(cut.threads, "\n", fn t -> "- " <> t["claim"] end)
    String.trim("#{cut.thesis}\n\n#{threads}")
  end

  defp child_text(_cut, child), do: "(not read yet) holds: " <> titles(child)

  defp titles(child) do
    (Enum.map(child.works, & &1.title) ++ Enum.map(child.folders, & &1.folder.name))
    |> Enum.join(", ")
  end

  defp work_members(works) do
    works
    |> Enum.sort_by(& &1.id)
    |> Enum.with_index(1)
    |> Enum.map(fn {work, n} ->
      %{
        n: n,
        kind: "work",
        id: work.id,
        label: work.title,
        read?: work.status == "read",
        text: work_text(work)
      }
    end)
  end

  # The map, not the manuscript. `quote` is the draft's own words, which is
  # what makes a citation checkable later; the node title is what the read
  # thought it was doing.
  defp work_text(work) do
    nodes = Works.list_nodes(work.id)

    body =
      case nodes do
        [] ->
          work.id
          |> Works.list_sections()
          |> Enum.map_join("\n\n", fn s -> String.slice(s.body, 0, 1200) end)

        nodes ->
          Enum.map_join(nodes, "\n\n", fn nd ->
            q = if nd.quote && nd.quote != "", do: "\n> #{nd.quote}", else: ""
            "#{nd.node_type}: #{nd.title}#{q}"
          end)
      end

    String.trim("#{work.first_impression || ""}\n\n#{body}")
  end

  # ==========================================================================
  # Readings
  # ==========================================================================

  def list_cuts(user_id) do
    Cut
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> preload(:folder)
    |> Repo.all()
  end

  def get_cut(user_id, id) do
    Cut
    |> where([c], c.user_id == ^user_id and c.id == ^id)
    |> preload(:folder)
    |> Repo.one()
  end

  @doc "The one reading a folder has, or nil."
  def get_folder_cut(user_id, folder_id) do
    Cut
    |> where([c], c.user_id == ^user_id and c.folder_id == ^folder_id)
    |> preload(:folder)
    |> Repo.one()
  end

  def delete_cut(%Cut{} = cut), do: Repo.delete(cut)

  def set_status(%Cut{} = cut, status, detail \\ nil) do
    cut |> Ecto.Changeset.change(status: status, status_detail: detail) |> Repo.update()
  end

  @doc """
  Get or make the reading for a folder, and mark it queued.

  One per folder: re-reading replaces what was there. A folder carrying six
  readings is a folder nobody can quote.
  """
  def open_folder_reading(user_id, folder_id, question \\ nil) do
    case Folders.get_folder(user_id, folder_id) do
      nil ->
        {:error, :not_found}

      folder ->
        attrs = %{
          "title" => folder.name,
          "folder_id" => folder.id,
          "scope" => "folder",
          "status" => "draft"
        }

        attrs = if question, do: Map.put(attrs, "question", question), else: attrs

        case get_folder_cut(user_id, folder_id) do
          nil -> %Cut{user_id: user_id} |> Cut.changeset(attrs) |> Repo.insert()
          cut -> cut |> Cut.changeset(attrs) |> Repo.update()
        end
    end
  end

  @doc "A fingerprint of what was read, so a stale answer can say so."
  def content_sha(members) when is_list(members) do
    members
    |> Enum.map_join("\n", fn m -> "#{m.kind}:#{m.id}:#{m.text}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Whether a stored reading is still about what the folder now holds."
  def current?(%Cut{content_sha: nil}), do: false

  def current?(%Cut{} = cut, user_id) do
    cut.folder_id && cut.content_sha == content_sha(members(user_id, cut.folder_id))
  end

  # ==========================================================================
  # The read
  # ==========================================================================

  @system """
  You are given several members of one group — documents, or the readings of \
  sub-groups — and nothing else. Say what they amount to together.

  You have not been shown anything but what is below. Do not reach for context \
  you do not have, and do not summarise the members back one at a time: the \
  reader can already see them. Say what is true across them that no single \
  member states.

  Every piece of evidence must quote one of the members and name it by its \
  number. A program checks each quote against that member's text and drops \
  what it cannot find, so an approximate quote is a discarded claim.

  An empty list is a real answer. If the members have nothing in common, say \
  so in the thesis and return no threads.

  Reply with one JSON object and nothing else.
  """

  @doc """
  Read a folder, and store only what could be checked.

  Slow and synchronous — the caller is a LiveView that has already told the
  reader it is thinking.
  """
  def read(%Cut{} = cut, user_id) do
    members = members(user_id, cut.folder_id)

    if members == [] do
      set_status(cut, "failed", "this folder holds nothing to read")
    else
      do_read(cut, members)
    end
  end

  defp do_read(%Cut{} = cut, members) do
    case LLM.json(
           model: LLM.default_model(),
           effort: :high,
           temperature: 0.3,
           max_tokens: 8_000,
           messages: [
             %{"role" => "system", "content" => @system},
             %{"role" => "user", "content" => prompt(cut, members)}
           ]
         ) do
      {:ok, raw} ->
        {result, dropped} = validate(raw, members)

        cut
        |> Cut.result_changeset(
          Map.merge(result, %{
            dropped: dropped,
            content_sha: content_sha(members),
            status: "read",
            members: Enum.map(members, &Map.take(&1, [:n, :kind, :id, :label, :read?]))
          })
        )
        |> Repo.update()

      {:error, reason} ->
        set_status(cut, "failed", inspect(reason))
    end
  end

  defp prompt(%Cut{} = cut, members) do
    asked =
      if cut.question && String.trim(cut.question) != "",
        do: "The reader asks: #{cut.question}\n\n",
        else: ""

    kind = if Enum.all?(members, &(&1.kind == "folder")), do: "sub-groups", else: "documents"

    body =
      Enum.map_join(members, "\n", fn m ->
        "### Member #{m.n}: #{m.label}\n\n#{m.text}\n"
      end)

    """
    #{asked}Group: #{cut.title}
    Its members are #{kind}.

    #{body}
    ---

    Report:

    - `thesis`: one or two sentences. What these members, together, establish.
      If they establish nothing together, say that.
    - `threads`: things true across two or more members that no single one
      states. Each: `claim` (one sentence) and `evidence` — two or more entries,
      each `{"member": N, "quote": "..."}` quoted from that member.
    - `tensions`: places the members disagree, or where one revises another.
      Same shape. `[]` if there are none.
    - `not_supported`: one sentence naming something a reader might expect this
      group to show but which these members do not support. `""` if none.

    Shape:

    {"thesis": "...",
     "threads": [{"claim": "...", "evidence": [{"member": 1, "quote": "..."}]}],
     "tensions": [],
     "not_supported": "..."}
    """
  end

  # --- validation -----------------------------------------------------------

  @doc """
  Keep only what can be checked, and say what was thrown away.

  Public because it is the half of this module worth testing: the prompt can
  be re-tuned freely, but a change that lets an unlocatable quote through is a
  change that makes every reading untrustworthy. It was private once, nothing
  exercised it, and a rename of `document` to `member` went unnoticed until
  every claim on every folder had been silently dropped.
  """
  def validate(raw, members) do
    by_n = Map.new(members, fn m -> {m.n, m} end)

    {threads, d1} = check_group(raw["threads"], by_n, "thread")
    {tensions, d2} = check_group(raw["tensions"], by_n, "tension")

    {%{
       thesis: text(raw["thesis"]),
       threads: threads,
       tensions: tensions,
       not_supported: text(raw["not_supported"])
     }, d1 ++ d2}
  end

  defp check_group(items, by_n, label) when is_list(items) do
    Enum.reduce(items, {[], []}, fn item, {kept, dropped} ->
      claim = text(item["claim"])

      if claim == "" do
        {kept, dropped ++ ["#{label}: no claim"]}
      else
        {evidence, bad} = check_evidence(item["evidence"], by_n, label, claim)

        if length(evidence) >= 2 do
          {kept ++ [%{"claim" => claim, "evidence" => evidence}], dropped ++ bad}
        else
          {kept,
           dropped ++
             bad ++
             ["#{label} #{short(claim)}: #{length(evidence)} verifiable citation(s), needs 2"]}
        end
      end
    end)
  end

  defp check_group(_items, _by_n, _label), do: {[], []}

  defp check_evidence(evidence, by_n, label, claim) when is_list(evidence) do
    Enum.reduce(evidence, {[], []}, fn ev, {kept, bad} ->
      n = as_int(ev["member"] || ev["document"])
      quoted = text(ev["quote"])
      member = Map.get(by_n, n)
      found = member && quoted != "" && locate(quoted, member.text)

      cond do
        is_nil(member) ->
          {kept,
           bad ++
             ["#{label} #{short(claim)}: member #{inspect(ev["member"])} is not in this group"]}

        found ->
          {kept ++
             [
               %{
                 "member" => n,
                 "kind" => member.kind,
                 "id" => member.id,
                 "label" => member.label,
                 "quote" => found
               }
             ], bad}

        true ->
          {kept, bad ++ ["#{label} #{short(claim)}: quote is not in member #{n}"]}
      end
    end)
  end

  defp check_evidence(_evidence, _by_n, label, claim),
    do: {[], ["#{label} #{short(claim)}: no evidence"]}

  defp text(v) when is_binary(v), do: String.trim(v)
  defp text(_), do: ""

  defp as_int(v) when is_integer(v), do: v

  defp as_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp as_int(_), do: nil

  defp short(s), do: inspect(String.slice(s, 0, 40))
end
