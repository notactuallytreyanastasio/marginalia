defmodule Marginalia.Links do
  @moduledoc """
  Relationships between the knowledge graphs of two manuscripts.

  A single draft ends up with a graph: beats anchored to lines, a spine,
  threads, questions, and `Weave`'s edges between them. Two drafts that are
  actually about each other — an essay and the reply to it, a chapter and the
  one it was cut from, two posts that turn out to be one argument — have the
  same kind of structure *between* them, and nothing in the product could say
  so.

  This is that graph. The same six relations, pointed across a boundary
  instead of across sections, so nobody has to learn a second vocabulary.

  The discipline that makes it worth trusting is the same one anchoring gives
  a single draft, moved up a level: **an edge whose ends are not both real
  nodes in the two named manuscripts is dropped before it is stored.** The
  model is handed a catalogue of ids and can only point at those. It cannot
  relate a paragraph that is not there, and — checked in code rather than
  asked for — it cannot quietly draw an edge inside one document and pass it
  off as a connection between them.
  """

  import Ecto.Query, warn: false

  alias Marginalia.Repo
  alias Marginalia.Links.{Link, LinkEdge}
  alias Marginalia.Works.Node

  # Two manuscripts have far more possible pairs than one does, so there is a
  # cap — but it is a backstop against a runaway answer, not a target. Set at
  # 60 it was doing the second job: a reader going down one document found
  # long stretches with nothing beside them, because the pass had spent its
  # budget on the opening.
  @max_edges 140

  @doc """
  The link between two works, creating the row if this pair is new.

  The pair is unordered, so it is stored lowest id first and looked up the
  same way — otherwise linking A to B and then B to A makes two rows that
  disagree with each other.
  """
  def get_or_create(work_a_id, work_b_id) when work_a_id != work_b_id do
    {a, b} = pair(work_a_id, work_b_id)

    case Repo.get_by(Link, a_work_id: a, b_work_id: b) do
      nil ->
        # a new pair changes the public list; finding an existing one does not
        Marginalia.Cache.invalidate(:public_links)
        Marginalia.Cache.invalidate(:published_cases)
        %Link{} |> Link.changeset(%{a_work_id: a, b_work_id: b}) |> Repo.insert()

      link ->
        {:ok, link}
    end
  end

  def get_or_create(_same, _same_again), do: {:error, :same_work}

  defp pair(a, b), do: {min(a, b), max(a, b)}

  def get(id), do: Repo.get(Link, id)

  def get_for(work_a_id, work_b_id) do
    {a, b} = pair(work_a_id, work_b_id)
    Repo.get_by(Link, a_work_id: a, b_work_id: b)
  end

  @doc """
  Drafts this one can be linked to: the writer's own, read, and not this one.

  "Read" is the hard requirement rather than a preference — linking relates
  two *graphs*, and a draft that has not been read has no nodes to relate.
  Offering it would produce an empty link and a confusing one.
  """
  def linkable(user_id, work_id) do
    from(w in Marginalia.Works.Work,
      where: w.user_id == ^user_id and w.id != ^work_id and w.status == "read",
      order_by: [desc: w.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Every link this writer has, newest first, both works loaded."
  def for_user(user_id) do
    from(l in Link,
      join: a in assoc(l, :a_work),
      join: b in assoc(l, :b_work),
      where: a.user_id == ^user_id or b.user_id == ^user_id,
      order_by: [desc: l.updated_at],
      preload: [a_work: a, b_work: b]
    )
    |> Repo.all()
  end

  @doc """
  The writer's links, grouped into the constellations they actually form.

  Links are pairs, but pairs chain: relate an opinion to the argument that
  produced it and to the dissents that answer it, and what you have is not
  two unrelated facts, it is one body of documents. A list of pairs hides
  that. This returns the connected components — every group of drafts that
  can be reached from each other through links — so the shape can be drawn.

  Each group also carries the pairs inside it that are *not* linked yet,
  which is the useful part: in a group of three with two links, the third
  pair is the obvious next question, and nothing else in the product would
  ever have raised it.
  """
  def clusters(user_id) do
    links = for_user(user_id)

    works =
      links
      |> Enum.flat_map(&[&1.a_work, &1.b_work])
      |> Enum.uniq_by(& &1.id)
      |> Map.new(&{&1.id, &1})

    links
    |> components()
    |> Enum.map(fn ids ->
      inside = Enum.filter(links, &(&1.a_work_id in ids))
      members = ids |> Enum.map(&works[&1]) |> Enum.sort_by(& &1.title)
      linked = MapSet.new(inside, &{&1.a_work_id, &1.b_work_id})

      %{
        works: members,
        links: inside,
        missing: unlinked_pairs(members, linked)
      }
    end)
    |> Enum.sort_by(&(-length(&1.works)))
  end

  # the pairs inside a group that nobody has related yet
  defp unlinked_pairs(members, linked) do
    for a <- members,
        b <- members,
        a.id < b.id,
        not MapSet.member?(linked, {a.id, b.id}),
        do: {a, b}
  end

  # union-find over the pairs, which is all a connected component is
  defp components(links) do
    parent =
      links
      |> Enum.flat_map(&[&1.a_work_id, &1.b_work_id])
      |> Enum.uniq()
      |> Map.new(&{&1, &1})

    parent =
      Enum.reduce(links, parent, fn l, acc ->
        {ra, acc} = root(acc, l.a_work_id)
        {rb, acc} = root(acc, l.b_work_id)
        if ra == rb, do: acc, else: Map.put(acc, ra, rb)
      end)

    parent
    |> Map.keys()
    |> Enum.group_by(fn id -> elem(root(parent, id), 0) end)
    |> Map.values()
  end

  defp root(parent, id) do
    case parent[id] do
      ^id -> {id, parent}
      up -> root(parent, up)
    end
  end

  @doc "Drafts that could be linked at all: this writer's, and read."
  def linkable(user_id) do
    from(w in Marginalia.Works.Work,
      where: w.user_id == ^user_id and w.status == "read",
      order_by: [desc: w.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  The links on the public face of this deploy: the owner's, and only the ones
  that found something, strongest first.

  A link with no edges is a pass that ran and reported nothing. That is a
  real answer and it is on the writer's own page, but a public index of empty
  comparisons is an index of nothing.

  Counts come back in two grouped queries rather than one per link. The first
  version asked `edge_count/1` inside a filter, which is 393 queries to draw
  one page — invisible on the six pairs it was written against and the whole
  cost of the page at the size it actually reached.
  """
  def public_links, do: Marginalia.Cache.fetch(:public_links, &compute_public_links/0)

  defp compute_public_links do
    case Marginalia.Accounts.owner() do
      nil ->
        []

      owner ->
        links = for_user(owner.id)
        ids = Enum.map(links, & &1.id)

        totals = counts_by_link(ids)
        tensions = counts_by_link(ids, "tension")

        links
        |> Enum.map(fn l ->
          %{link: l, edges: Map.get(totals, l.id, 0), tensions: Map.get(tensions, l.id, 0)}
        end)
        |> Enum.filter(&(&1.edges > 0))
        |> Enum.sort_by(&{-&1.tensions, -&1.edges})
    end
  end

  defp counts_by_link(ids, type \\ nil)

  defp counts_by_link([], _type), do: %{}

  defp counts_by_link(ids, type) do
    LinkEdge
    |> where([e], e.link_id in ^ids)
    |> then(fn q -> if type, do: where(q, [e], e.edge_type == ^type), else: q end)
    |> group_by([e], e.link_id)
    |> select([e], {e.link_id, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  A link anybody may read: the owner's, and only if it found something.

  BOTH works must belong to the owner. This page reads two drafts at once, so
  a check that passes on one of them exposes somebody else's work alongside
  the owner's.
  """
  def public_link(id) do
    with owner when not is_nil(owner) <- Marginalia.Accounts.owner(),
         %Link{} = link <- Repo.get(Link, id) |> Repo.preload([:a_work, :b_work]),
         true <- link.a_work.user_id == owner.id and link.b_work.user_id == owner.id,
         true <- edge_count(link.id) > 0 do
      link
    else
      _ -> nil
    end
  end

  @doc "How many edges a link holds."
  def edge_count(link_id),
    do: Repo.one(from e in LinkEdge, where: e.link_id == ^link_id, select: count(e.id))

  @doc "Every link either side of this work, newest first."
  def for_work(work_id) do
    Link
    |> where([l], l.a_work_id == ^work_id or l.b_work_id == ^work_id)
    # `updated_at` is second-precision, so two links touched in the same
    # second tie and Postgres is free to return them either way round. The id
    # breaks the tie and makes this a total order — which matters for a list
    # a person reads, and mattered for a test that took the head of it and
    # got a different pair about one run in thirty.
    |> order_by([l], desc: l.updated_at, desc: l.id)
    |> preload([:a_work, :b_work])
    |> Repo.all()
  end

  @doc "The other manuscript in a link, from the point of view of this one."
  def other(%Link{a_work_id: a, b_work: b_work}, work_id) when a == work_id, do: b_work
  def other(%Link{a_work: a_work}, _work_id), do: a_work

  def set_status(%Link{} = link, status, attrs \\ %{}) do
    link |> Link.changeset(Map.merge(attrs, %{status: status})) |> Repo.update()
  end

  @doc "Edges of a link, with both ends loaded, in the order they were drawn."
  # Decorated with the documents' names in place of the pass's A and B —
  # here rather than in each view, so nothing that renders a reason has
  # to remember to do it. See `plain/2`.
  def edges(%Link{} = link) do
    link.id
    |> edges()
    |> Enum.map(&%{&1 | rationale: plain(&1.rationale, link)})
  end

  def edges(link_id) do
    LinkEdge
    |> where([e], e.link_id == ^link_id)
    |> order_by([e], asc: e.ordinal, asc: e.id)
    |> preload([:from, :to])
    |> Repo.all()
  end

  def clear_edges(%Link{} = link) do
    Marginalia.Cache.invalidate(:public_links)
    Marginalia.Cache.invalidate(:published_cases)
    do_clear_edges(link)
  end

  defp do_clear_edges(%Link{} = link),
    do: LinkEdge |> where([e], e.link_id == ^link.id) |> Repo.delete_all()

  @doc """
  Store proposed edges, keeping only those whose ends are real nodes in the
  two manuscripts this link is between, and which genuinely cross from one to
  the other.

  Returns `{kept, dropped}`. The rejection count is the number worth
  watching: a pass that suddenly starts failing this check has begun
  inventing ids, and the graph it produced is fiction.
  """
  def store_edges(%Link{} = link, proposed, types, max \\ @max_edges) do
    Marginalia.Cache.invalidate(:public_links)
    Marginalia.Cache.invalidate(:published_cases)
    allowed = node_side(link)

    {rows, dropped} =
      proposed
      |> Enum.filter(&is_map/1)
      |> Enum.map(&normalise(&1, allowed, types))
      |> Enum.reduce({[], 0}, fn
        nil, {rows, dropped} -> {rows, dropped + 1}
        row, {rows, dropped} -> {[row | rows], dropped}
      end)

    rows =
      rows
      |> Enum.reverse()
      |> Enum.uniq_by(fn r -> {r.from_id, r.to_id, r.edge_type} end)
      |> Enum.take(max)
      |> Enum.with_index()
      |> Enum.map(fn {r, i} -> Map.put(r, :ordinal, i) end)

    kept =
      Enum.count(rows, fn attrs ->
        match?(
          {:ok, _},
          %LinkEdge{} |> LinkEdge.changeset(Map.put(attrs, :link_id, link.id)) |> Repo.insert()
        )
      end)

    {kept, dropped}
  end

  # which manuscript each node belongs to, for the two in this link only
  defp node_side(%Link{a_work_id: a, b_work_id: b}) do
    Node
    |> where([n], n.work_id in [^a, ^b])
    |> select([n], {n.id, n.work_id})
    |> Repo.all()
    |> Map.new()
  end

  defp normalise(raw, allowed, types) do
    from = int(raw["from"])
    to = int(raw["to"])
    type = raw["type"]
    why = raw["why"] |> to_string() |> String.trim()

    from_side = from && Map.get(allowed, from)
    to_side = to && Map.get(allowed, to)

    cond do
      # an invented id, or one belonging to some third manuscript
      is_nil(from_side) or is_nil(to_side) -> nil
      # an edge inside one document is Weave's job, not this one
      from_side == to_side -> nil
      type not in types -> nil
      why == "" -> nil
      true -> %{from_id: from, to_id: to, edge_type: type, rationale: why}
    end
  end

  defp int(n) when is_integer(n), do: n

  defp int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp int(_), do: nil

  @doc """
  The paragraph a node sits in, not just the sentence it was anchored to.

  The anchor is one sentence because that is what can be verified. When the
  passage is being handed to a conversation, though, the sentence on its own
  is the thing people misread — the paragraph around it is what makes it
  mean what it means.
  """
  def passage(%Node{quote: q, section_id: sid})
      when is_binary(q) and q != "" and not is_nil(sid) do
    case Repo.get(Marginalia.Works.Section, sid) do
      nil ->
        q

      section ->
        section.body
        |> Marginalia.Reading.split()
        |> Enum.find(&String.contains?(&1, q))
        |> case do
          nil -> q
          para -> para
        end
    end
  end

  def passage(%Node{quote: q}) when is_binary(q) and q != "", do: q
  def passage(%Node{title: t}), do: t

  @doc "Counts for the header of a linked graph."
  def stats(%Link{} = link) do
    edges = edges(link)

    %{
      edges: length(edges),
      by_type: Enum.frequencies_by(edges, & &1.edge_type),
      # how much of each side the link actually touches
      a_nodes:
        edges
        |> Enum.flat_map(&[&1.from, &1.to])
        |> Enum.filter(&(&1.work_id == link.a_work_id))
        |> Enum.uniq_by(& &1.id)
        |> length(),
      b_nodes:
        edges
        |> Enum.flat_map(&[&1.from, &1.to])
        |> Enum.filter(&(&1.work_id == link.b_work_id))
        |> Enum.uniq_by(& &1.id)
        |> length()
    }
  end

  @doc """
  The link's edges as margin notes for one side of it.

  Shaped exactly like the notes `Marginalia.Reading` builds from a work's own
  graph, so the same placement code finds the quote in the paragraph and
  marks the span. What is different is `peer`: the node id on the *other*
  side, which is what lets a click in one column move the other one.

  An edge whose near end is not an anchored beat has nowhere to sit on the
  page, so it is left out here and shown in the list instead. A spine node
  is a claim about the whole draft; there is no one paragraph to pin it to.
  """
  def notes_for(%Link{} = link, work_id) do
    link
    |> edges()
    |> Enum.flat_map(fn e ->
      {near, far} = if e.from.work_id == work_id, do: {e.from, e.to}, else: {e.to, e.from}

      if (near.work_id == work_id and near.section_id) && near.quote not in [nil, ""] do
        [
          %{
            id: {:link, e.id, near.id},
            key: "link:#{e.id}",
            section_id: near.section_id,
            kind: e.edge_type,
            quote: near.quote,
            title: direction(e, near) <> far.title,
            body: plain(e.rationale, link),
            stale: false,
            edge_id: e.id,
            peer: far.id
          }
        ]
      else
        []
      end
    end)
  end

  # the arrow says which way the relation runs, which is half its meaning
  defp direction(%{from_id: from_id}, %{id: id}) when from_id == id, do: "→ "
  defp direction(_edge, _near), do: "← "

  @doc """
  One draft to read, with the other one in its margin.

  The split view puts two documents side by side and makes you click to pair
  them. This is the other way round: you read one straight through, and what
  the other document has to say about the passage in front of you is already
  beside it — the arrangement a single draft's own notes use, with the
  margin sourced from somewhere else.

  Each note carries the far end whole: its relation, the reason, the section
  it came from and the sentence it is anchored to. That last one is the
  point. A note saying "this develops §2 of the other draft" is a reference;
  a note carrying the actual sentence is something you can read.
  """
  def reading(%Link{} = link, lead_id) do
    {a, b} = works(link)
    {lead, other} = if a.id == lead_id, do: {a, b}, else: {b, a}

    %{lead: lead, other: other, page: Marginalia.Reading.page(lead, notes: margin(link, lead_id))}
  end

  @doc """
  A link's summary with the documents called by their names.

  The pass is handed the two drafts as "Manuscript A" and "Manuscript B",
  which is right for the prompt — it stops the model reasoning from a
  title instead of from the text — and wrong for every page that shows the
  answer. "Manuscript A is Kagan's majority opinion" is a sentence a
  reader has to decode before they can read it.

  Substituted here rather than fixed in the prompt, because it also has to
  be true of the summaries already written.
  """
  def summary(%Link{summary: nil}), do: nil

  def summary(%Link{summary: text} = link), do: plain(text, link)

  @doc """
  Any of the pass's prose, with the documents called by their names.

  The pass is handed the two drafts as "Manuscript A" and "Manuscript B"
  and shortens that to a bare "A" and "B" in the reasons it writes. Both
  are right for the prompt — they stop the model reasoning from a title
  instead of from the text — and both are wrong on the page, where "A
  says Congress entrenched the common law; B Jackson charges" is a
  sentence a reader has to decode before they can read it.

  Every reference is resolved in a single left-to-right pass, and that is
  not a tidiness point. Done as one replacement per form, a title
  substituted by an early pass is ordinary English by the time a later one
  reads it, and the later one substitutes *inside* it — which is how "B
  answers A's open question" became a sentence containing the same title
  twice, spliced through itself.

  "Manuscript A" and the possessive "A's" are unambiguous and resolved
  anywhere. A bare letter is resolved only where a sentence starts, which
  is where the convention puts it; "Part A" and "Exhibit B" are why it is
  not a plain word replacement, and the indefinite article is why it can
  never become one. `Linker` now requires the model to write "Manuscript
  A" in full so new prose never depends on the guess.
  """
  def plain(nil, _link), do: nil

  def plain(text, %Link{} = link) when is_binary(text) do
    {a, b} = works(link)
    substitute(text, %{"A" => name(a), "B" => name(b)})
  end

  def plain(text, _link), do: text

  # Every reference to either manuscript, matched once, in one left-to-right
  # pass. The pass count is the load-bearing part.
  #
  # This was six sequential `String.replace/3` calls, and two of them were
  # reading the output of the others. A title substituted early contains
  # ordinary English, so a later pass found its letters and substituted
  # again:
  #
  #     "B answers A's open question."
  #     -> "2. The backend scaffold answers 1. 1. A page with no script on
  #         it, and the server generated too page with no script on it, and
  #         the server generated too's open question."
  #
  # One pass cannot do that: `Regex.replace/3` resumes after the match it
  # just made, in the original string, so replaced text is never rescanned.
  #
  # The replacement is a function rather than a pattern string for the same
  # family of reason. Built as `"\\1" <> title`, a title beginning with a
  # digit — every chapter of a numbered stack — produced `"\\11. The
  # out-grammar"`, which the engine reads as backreference *eleven*, not
  # group one then a literal "1". Group 11 does not exist, so it expanded to
  # nothing and took the chapter number with it. A function replacement is
  # never scanned for backreferences, so no title can be misread as syntax.
  #
  # The four branches, in the order the alternation tries them:
  #
  #   "Manuscript A", "Manuscript A's"  the unambiguous form. `Linker` now
  #                                     requires it, so new prose is only ever
  #                                     this.
  #   "A's"                             safe anywhere: English has no
  #                                     possessive indefinite article, so this
  #                                     is never the word "a".
  #   ". A" / start of text             the convention the older summaries
  #                                     were written to.
  #   " A"                              left alone. "Part A" and "Exhibit B"
  #                                     live here, and so does the indefinite
  #                                     article.
  #
  # That last one is why bare mid-sentence letters are not substituted and
  # cannot be. "A defines the output tree" and "A sentence defines the output
  # tree" share a prefix; telling the label from the article needs to know
  # whether the next word is a verb. Turning "A page with no script on it"
  # into a manuscript title is a worse failure than leaving a letter on the
  # page, so the fix for those went into the prompt instead.
  @ref ~r/(\A|\bManuscripts?\s+|[.;:—-]\s+|\s+)([AB])(['’]s)?(?![\p{L}\p{N}'’])/u

  defp substitute(text, names) do
    Regex.replace(@ref, text, fn _whole, pre, letter, poss ->
      cond do
        # "Manuscript A" — the word goes, the title replaces both
        Regex.match?(~r/\bManuscripts?\s+\z/, pre) -> names[letter] <> poss
        # "A's" — unambiguous wherever it appears
        poss != "" -> pre <> names[letter] <> poss
        # start of the text, or of a sentence
        pre == "" or Regex.match?(~r/[.;:—-]\s+\z/, pre) -> pre <> names[letter]
        # a bare letter mid-sentence: could be "Part A", could be "a"
        true -> pre <> letter <> poss
      end
    end)
  end

  # the case name is repeated on every document in a collection and is
  # already on the page; what distinguishes them is what comes after it
  defp name(work) do
    case String.split(work.title, " — ", parts: 2) do
      [_collection, rest] -> rest
      [whole] -> whole
    end
  end

  @doc """
  The notes one draft gets from one link, each carrying its far end whole.

  Split out of `reading/2` because a draft can be related to more than one
  other, and a collection wants all of those margins at once rather than one
  page per pair — see `Marginalia.Cases.reading/2`. The far end travels with
  the note (its relation, the reason, the section, and the sentence it is
  anchored to) so whoever renders it does not have to go back for the graph.
  """
  def margin(%Link{} = link, lead_id) do
    other = other(link, lead_id)
    far_sections = Marginalia.Works.list_sections(other.id) |> Map.new(&{&1.id, &1.ordinal})

    # the edges once, not once per note
    by_edge = link |> edges() |> Map.new(&{&1.id, &1})

    link
    |> notes_for(lead_id)
    |> Enum.map(fn note ->
      far = far_node(by_edge[note.edge_id], lead_id)

      note
      |> Map.put(:far_title, far && far.title)
      |> Map.put(:far_body, far && far.body)
      |> Map.put(:far_quote, far && far.quote)
      |> Map.put(:far_kind, far && far.node_type)
      |> Map.put(:far_section, far && far_sections[far.section_id])
    end)
  end

  defp far_node(nil, _lead_id), do: nil

  defp far_node(%{from: from, to: to}, lead_id),
    do: if(from.work_id == lead_id, do: to, else: from)

  @doc """
  Both drafts as pages, with every note knowing where its counterpart sits.

  `peer_ref` is the block id of the paragraph on the *other* side that this
  edge points at. It is resolved here, once, rather than in the browser,
  because working it out needs both pages at the same time and the client
  should only have to follow a pointer.
  """
  def pages(%Link{} = link) do
    {a, b} = works(link)

    page_a = Marginalia.Reading.page(a, notes: notes_for(link, a.id))
    page_b = Marginalia.Reading.page(b, notes: notes_for(link, b.id))

    {annotate(page_a, ref_index(page_b)), annotate(page_b, ref_index(page_a))}
  end

  # which paragraph each linked node ended up in, on one side
  defp ref_index(page) do
    for section <- page, block <- section.blocks, note <- block.notes, into: %{} do
      {:link, _edge, near_id} = note.id
      {near_id, block.ref}
    end
  end

  defp annotate(page, peer_refs) do
    Enum.map(page, fn section ->
      blocks =
        Enum.map(section.blocks, fn block ->
          %{block | notes: Enum.map(block.notes, &Map.put(&1, :peer_ref, peer_refs[&1.peer]))}
        end)

      %{section | blocks: blocks}
    end)
  end

  @doc "Both works of a link, loaded."
  def works(%Link{} = link) do
    link = Repo.preload(link, [:a_work, :b_work])
    {link.a_work, link.b_work}
  end
end
