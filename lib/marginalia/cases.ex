defmodule Marginalia.Cases do
  @moduledoc """
  A collection: several drafts that are one thing.

  A Supreme Court case arrives as three or four separate documents — the
  opinion of the Court, each dissent, the argument that produced them — and
  every one of them is a draft in its own right with its own map. What the
  reader wants is neither one document nor a flat list of twelve: it is the
  case, with its pieces in the order you would read them and the
  relationships between them already drawn.

  `collection` names the group and `collection_role` orders it. Both are
  plain fields rather than a table, because a collection has no properties
  of its own — it is a name several drafts agree on.
  """

  import Ecto.Query, warn: false

  alias Marginalia.{Links, Repo}
  alias Marginalia.Works.Work

  # the order a case is read in, which is not the order it was written in
  @order ["opinion", "concurrence", "dissent", "argument"]

  @doc """
  The collections on the front of the site, whoever is looking.

  A draft is private to whoever holds its link. A *collection* is the
  exception, and deliberately so: the point of gathering an opinion, its
  dissent and the argument that produced them is to publish the reading of
  them, and these particular documents are public records of the United
  States courts. Nothing is published by accident — a draft has to be put
  in a named collection by the person who owns it before it appears here.
  """
  def published do
    case Marginalia.Accounts.owner() do
      nil -> []
      owner -> list(owner.id)
    end
  end

  @doc "Every collection this writer has, with its drafts and their links."
  def list(user_id) do
    works =
      Work
      |> where([w], w.user_id == ^user_id and not is_nil(w.collection))
      |> order_by([w], asc: w.collection, asc: w.id)
      |> Repo.all()

    # Cross-collection links, for every collection at once. Asking per
    # document meant eighty-two round trips to render one contents page.
    kin = kinships(works)

    # And the same again for the links inside each collection. `assemble/3`
    # used to call Links.for_work/1 per document and Links.edges/1 per link,
    # which is the very thing the comment above says was fixed — it was fixed
    # for the kinships and left alone here. Eighty-two documents and their
    # links were most of the 700ms this page took.
    {links, edges} = links_and_edges(works)

    works
    |> Enum.group_by(& &1.collection)
    |> Enum.map(fn {name, ws} ->
      Map.put(assemble(name, ws, {links, edges}), :kin, Map.get(kin, name, []))
    end)
    |> Enum.sort_by(& &1.name)
  end

  # Every link that leaves a collection, grouped by the collection it
  # leaves, with its edge count — three queries for the whole page.
  # Every link touching any of these documents, and every edge belonging to
  # those links, in two queries rather than one per document and one per link.
  defp links_and_edges(works) do
    ids = Enum.map(works, & &1.id)

    links =
      Links.Link
      |> where([l], l.a_work_id in ^ids or l.b_work_id in ^ids)
      |> preload([:a_work, :b_work])
      |> Repo.all()

    link_ids = Enum.map(links, & &1.id)

    edges =
      Links.LinkEdge
      |> where([e], e.link_id in ^link_ids)
      |> order_by([e], asc: e.ordinal, asc: e.id)
      |> preload([:from, :to])
      |> Repo.all()
      |> Enum.group_by(& &1.link_id)

    {links, edges}
  end

  defp kinships(works) do
    by_id = Map.new(works, &{&1.id, &1})
    ids = Map.keys(by_id)

    links =
      Repo.all(
        from l in Links.Link,
          where:
            l.status == "linked" and (l.a_work_id in ^ids or l.b_work_id in ^ids),
          select: {l.id, l.a_work_id, l.b_work_id}
      )

    counts =
      Repo.all(
        from e in Links.LinkEdge,
          group_by: e.link_id,
          select: {e.link_id, count(e.id)}
      )
      |> Map.new()

    links
    |> Enum.flat_map(fn {id, a_id, b_id} ->
      a = Map.get(by_id, a_id)
      b = Map.get(by_id, b_id)
      n = Map.get(counts, id, 0)

      if a && b && a.collection != b.collection and n > 0 do
        [
          {a.collection, %{link_id: id, lead: a, other: b, case: b.collection, edges: n}},
          {b.collection, %{link_id: id, lead: b, other: a, case: a.collection, edges: n}}
        ]
      else
        []
      end
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, k} -> k end)
    |> Map.new(fn {name, list} -> {name, Enum.sort_by(list, &(-&1.edges))} end)
  end

  @doc "One collection by its slug, or nil."
  def get(user_id, slug) do
    user_id |> list() |> Enum.find(&(&1.slug == slug))
  end

  # How the Court announces its own holding, in the order the phrasings
  # actually commit to one. "Accordingly, …" is last because it is as
  # often a transition as a conclusion.
  @holds [
    ~r/\b[Ww]e (?:therefore |accordingly |now )?hold that\b[^.]{20,300}\./,
    ~r/\b[Ww]e (?:therefore |accordingly |now )?conclude that\b[^.]{20,300}\./,
    ~r/\b[Ww]e (?:hold|conclude)\b[^.]{20,300}\./,
    ~r/\bWe (?:therefore |accordingly )?(?:reverse|affirm|vacate)\b[^.]{10,300}\./
  ]

  @doc """
  What the Court held, in the Court's own words.

  Not the syllabus. The Reporter's headnote is the obvious place to get
  this and it is the wrong one: it is not part of the opinion, it carries
  no authority, every slip opinion says so on its first page, and a
  lawyer does not read it. Quoting it under the heading "what the Court
  held" would be the one kind of mistake this product cannot make — a
  confident claim about a document, sourced from something the document
  itself disclaims.

  So the holding is lifted from the opinion, verbatim, and shown as a
  quotation. Three of sixteen opinions never say "we hold" or "we
  conclude" in a single sentence, and those get nothing at all, which is
  the same rule the anchoring already follows: a passage that cannot be
  found is not shown.
  """
  def holding(nil), do: nil

  def holding(%Work{body: body}) when is_binary(body) do
    flat = String.replace(body, ~r/\s+/, " ")

    Enum.find_value(@holds, fn pattern ->
      case Regex.run(pattern, flat, return: :index) do
        [{at, len}] -> flat |> from_sentence_start(at, len) |> String.trim()
        _ -> nil
      end
    end)
  end

  # "Because we conclude that Durnell's claim is preempted, we need not
  # consider…" matches at "we conclude", and quoting from there gives a
  # fragment that opens lowercase in the middle of a sentence. A verbatim
  # quote that starts mid-sentence undercuts the one thing it is for, so
  # the match is widened back to where the sentence began.
  defp from_sentence_start(text, at, len) do
    before = binary_part(text, 0, at)

    start =
      case Regex.scan(~r/[.!?][”"]?\s+/u, before, return: :index) do
        [] -> 0
        hits -> hits |> List.last() |> hd() |> then(fn {i, n} -> i + n end)
      end

    text
    |> binary_part(start, at - start + len)
    |> strip_marker()
  end

  # A division heading has no full stop after it, so walking back to the
  # sentence start walks straight past "III" or "* * *" and takes it into
  # the quotation.
  defp strip_marker(text) do
    trimmed = String.replace(text, ~r/^\s*(?:[IVXL]{1,5}|[A-Z]|\d{1,2}|\*(?:\s*\*)*)[\s.]+/, "")

    if trimmed == text or trimmed == "", do: text, else: strip_marker(trimmed)
  end

  defp assemble(name, works, {all_links, all_edges}) do
    works = Enum.sort_by(works, &rank(&1.collection_role))
    ids = MapSet.new(works, & &1.id)

    # only the links that live inside this collection: a document may also
    # be related to something outside it, and that is a different page
    links =
      Enum.filter(
        all_links,
        &(MapSet.member?(ids, &1.a_work_id) and MapSet.member?(ids, &1.b_work_id))
      )

    # loaded once and carried: the contents page asks for the counts, the
    # sharpest collisions and the pairings, and each of those used to go
    # back for the same edges
    by_link = Map.new(links, &{&1.id, Map.get(all_edges, &1.id, [])})

    %{
      name: name,
      slug: slug(name),
      works: works,
      links: links,
      by_link: by_link,
      holding: works |> Enum.find(&(&1.collection_role == "opinion")) |> holding(),
      read: Enum.count(works, &(&1.status == "read")),
      words: works |> Enum.map(& &1.word_count) |> Enum.sum(),
      edges: by_link |> Map.values() |> Enum.map(&length/1) |> Enum.sum(),
      missing: unlinked(works, links)
    }
  end

  @doc """
  The ways into a case, best first.

  A case is not read as a case; it is read as one document against
  another, following along as you scroll. So the contents page offers the
  actual pairings rather than a door marked "case" — the opinion against
  the dissent, the opinion against the advocate it is answering — each
  with how much the two have to say to each other, because that number is
  the honest signal of which one to open.

  The pair is ordered so the document a reader would lead with is the one
  they land in: the opinion before the dissent, either before an
  advocate.
  """
  def ways(c) do
    by_id = Map.new(c.works, &{&1.id, &1})

    c.links
    |> Enum.filter(&(&1.status == "linked"))
    |> Enum.flat_map(fn l ->
      with %{} = a <- Map.get(by_id, l.a_work_id),
           %{} = b <- Map.get(by_id, l.b_work_id) do
        {lead, other} =
          if rank(a.collection_role) <= rank(b.collection_role), do: {a, b}, else: {b, a}

        [%{link: l, lead: lead, other: other, edges: length(Map.get(c.by_link, l.id, []))}]
      else
        _ -> []
      end
    end)
    |> Enum.reject(&(&1.edges == 0))
    |> Enum.sort_by(&{rank(&1.lead.collection_role), -&1.edges})
  end

  defp unlinked(works, links) do
    have = MapSet.new(links, &{&1.a_work_id, &1.b_work_id})

    for a <- works,
        b <- works,
        a.id < b.id,
        not MapSet.member?(have, {a.id, b.id}),
        do: {a, b}
  end

  defp rank(role) do
    case Enum.find_index(@order, &(&1 == role)) do
      nil -> length(@order)
      i -> i
    end
  end

  @doc """
  What a case looks like on a contents page.

  Not counts — counts tell a reader nothing about whether a case is worth
  opening. What does: the disagreement between the documents, in the words
  the pass used, and a couple of the sharpest places they actually collide.
  """
  def preview(c) do
    edges =
      c.by_link
      |> Map.values()
      |> List.flatten()
      |> Enum.sort_by(&rank_edge(&1.edge_type))

    %{
      summary: Enum.find_value(c.links, &Links.summary/1),
      sharpest: Enum.take(edges, 3),
      kinds: edges |> Enum.frequencies_by(& &1.edge_type) |> Enum.sort_by(fn {_k, n} -> -n end),
      impression: c.works |> Enum.find(&(&1.collection_role == "opinion")) |> impression()
    }
  end

  defp impression(nil), do: nil
  defp impression(%{first_impression: fi}), do: fi

  # a disagreement is the thing worth leading with
  defp rank_edge("tension"), do: 0
  defp rank_edge("answers"), do: 1
  defp rank_edge("requires"), do: 2
  defp rank_edge(_), do: 3

  @doc "A stable url-safe name for a collection."
  def slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end

  @doc """
  Put a draft in a collection.

  `role` is one of the reading-order names — opinion, concurrence, dissent,
  argument — and anything else sorts last rather than being refused, since
  a collection of something other than a court case will want its own
  words.
  """
  def place(%Work{} = work, collection, role) do
    work
    |> Work.changeset(%{collection: collection, collection_role: role})
    |> Repo.update()
  end

  @doc """
  One document of a case, read with every other document in its margin.

  `Links.reading/2` is pairwise: one draft on the left, one in the margin.
  That is the wrong shape for a case. An opinion is not answering one thing
  — it is answering the dissent *and* the advocate who was asked about it
  at the lectern, and the interesting moments are exactly where those two
  land on the same paragraph. Reading the opinion against the dissent, then
  starting again and reading it against the argument, hides that.

  So: every link in the collection that touches `lead_id`, merged into one
  margin, each note stamped with the document it came from. Notes are
  grouped by paragraph and kept in the reading order of their source (the
  dissent before the arguments), so a paragraph with three documents on it
  reads as a conversation rather than a pile.

  Returns `nil` if the lead is not in the collection.
  """
  def reading(c, lead_id) do
    case Enum.find(c.works, &(&1.id == lead_id)) do
      nil ->
        nil

      lead ->
        by_id = Map.new(c.works, &{&1.id, &1})

        inside =
          c.links
          |> Enum.filter(&(&1.a_work_id == lead.id or &1.b_work_id == lead.id))
          |> Enum.map(fn l ->
            other = Map.fetch!(by_id, if(l.a_work_id == lead.id, do: l.b_work_id, else: l.a_work_id))
            %{link: l, work: other, elsewhere: nil}
          end)
          |> Enum.filter(&(&1.link.status == "linked"))
          |> Enum.sort_by(&rank(&1.work.collection_role))

        # Everything this document is related to that is not in this case.
        # A term is one Court reasoning sixteen times, and the places two
        # of those readings touch are not visible from inside either case
        # — they are the reason to have a term rather than a pile of
        # cases. They come last and say where they are from.
        sources = inside ++ elsewhere(lead, c.name)

        notes =
          Enum.flat_map(sources, fn %{link: link, work: other} ->
            link
            |> Links.margin(lead.id)
            |> Enum.map(fn note ->
              note
              |> Map.put(:from_work, other.id)
              |> Map.put(:from_title, other.title)
              |> Map.put(:from_role, other.collection_role)
              |> Map.put(:from_case, other.collection)
              |> Map.put(:link_id, link.id)
            end)
          end)

        %{
          lead: lead,
          sources: sources,
          notes: notes,
          page: Marginalia.Reading.page(lead, notes: notes)
        }
    end
  end

  # The lead's links that reach outside this collection, each stamped with
  # the case it comes from.
  defp elsewhere(lead, name) do
    lead.id
    |> Links.for_work()
    |> Enum.filter(&(&1.status == "linked"))
    |> Enum.map(fn l -> %{link: l, work: Links.other(l, lead.id)} end)
    |> Enum.filter(fn %{work: w} ->
      not is_nil(w) and not is_nil(w.collection) and w.collection != name
    end)
    |> Enum.map(&Map.put(&1, :elsewhere, &1.work.collection))
    |> Enum.sort_by(& &1.work.collection)
  end

  @doc """
  The other cases this one is related to, with a way into each reading.

  Everything else on a case's card is the case arguing with itself. This
  is the term arguing with itself, which is the only thing on the page
  that could not have been produced by reading one case carefully.
  """
  def kin(c), do: Map.get(c, :kin, [])

  @doc """
  The document a case should open on.

  The opinion, if there is one: it is the thing that happened. Failing
  that, whatever sorts first — a case with only an argument on file still
  has something to read.
  """
  def default_lead(c) do
    Enum.find(c.works, &(&1.collection_role == "opinion")) || List.first(c.works)
  end

  @doc "The roles this module knows how to order."
  def roles, do: @order
end
