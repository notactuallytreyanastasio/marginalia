defmodule Marginalia.Reading do
  @moduledoc """
  The draft itself, with the notes in the margin beside the lines that caused
  them.

  Every other view in this app shows the map. This one shows the page. It is
  the view the anchoring discipline was built for and never used: because each
  beat carries a span verified to be a literal substring of the writer's own
  text, we can find the exact paragraph it came from and put the note next to
  it — rather than at the top of a section, which is where a note goes when
  you do not actually know where it belongs.

  A note whose quote cannot be located in any paragraph is not dropped; it is
  attached to the section instead, and says so. Silently losing an observation
  because the layout could not place it would be worse than an imprecise
  margin.
  """

  alias Marginalia.Analysis.Anchor
  alias Marginalia.Works

  @doc """
  The whole draft as sections of paragraphs, each paragraph carrying the notes
  anchored inside it.

  `opts[:only]` trims what is shown — `"beats"`, `"questions"`, `"tensions"`,
  or a section ordinal — because a 90k-word draft with every note attached is
  not a reading experience, it is a wall with a wall beside it.
  """
  def page(work, opts \\ []) do
    sections = Works.list_sections(work.id)

    # `opts[:notes]` supplies the margin from somewhere other than this
    # work's own graph — the linked view builds it out of the edges between
    # two drafts. Placement is the same problem either way: find the quote in
    # the paragraph, mark the span, hang the note off it.
    notes =
      opts[:notes] ||
        collect(Works.list_nodes(work.id), Works.all_connections(work.id), opts[:only])

    by_section = Enum.group_by(notes, & &1.section_id)

    sections
    |> filter_sections(opts[:section])
    |> Enum.map(fn s ->
      section_notes = Map.get(by_section, s.id, [])
      {blocks, placed} = place(s, section_notes)

      %{
        section: s,
        blocks: blocks,
        # anything that could not be located, kept rather than lost
        unplaced: Enum.reject(section_notes, &MapSet.member?(placed, &1.id))
      }
    end)
  end

  defp filter_sections(sections, nil), do: sections
  defp filter_sections(sections, ord), do: Enum.filter(sections, &(&1.ordinal == ord))

  # --------------------------------------------------------------------------
  # What counts as a note
  # --------------------------------------------------------------------------

  defp collect(nodes, conns, only) do
    beats = Enum.filter(nodes, &(&1.node_type == "beat"))
    by_id = Map.new(nodes, &{&1.id, &1})

    beat_notes =
      Enum.map(beats, fn n ->
        %{
          id: {:beat, n.id},
          key: "beat:#{n.id}",
          section_id: n.section_id,
          kind: "beat",
          quote: n.quote,
          title: n.title,
          body: n.body,
          stale: n.status == "superseded"
        }
      end)

    # a connection is shown on the beat it starts from, because that is where
    # the writer is standing when they need to know it goes somewhere
    conn_notes =
      Enum.flat_map(conns, fn c ->
        case by_id[c.from.id] do
          %{node_type: "beat", section_id: sid, quote: q} when not is_nil(sid) ->
            [
              %{
                id: {:conn, c.from.id, c.to.id, c.type},
                key: "conn:#{c.from.id}:#{c.to.id}:#{c.type}",
                section_id: sid,
                kind: c.type,
                quote: q,
                title: label(c.type) <> " " <> c.to.title,
                body: c.why,
                stale: false
              }
            ]

          _ ->
            []
        end
      end)

    case only do
      "beats" -> beat_notes
      "connections" -> conn_notes
      "tensions" -> Enum.filter(conn_notes, &(&1.kind == "tension"))
      _ -> beat_notes ++ conn_notes
    end
  end

  defp label("develops"), do: "develops →"
  defp label("pays_off"), do: "pays off →"
  defp label("requires"), do: "requires ←"
  defp label("tension"), do: "tension with"
  defp label("realises"), do: "realises"
  defp label("asks_about"), do: "asks about"
  defp label(other), do: other

  # --------------------------------------------------------------------------
  # Putting each note beside its paragraph
  # --------------------------------------------------------------------------

  defp place(section, notes) do
    paragraphs = split(section.body)

    {blocks, placed} =
      Enum.map_reduce(paragraphs, MapSet.new(), fn para, placed ->
        mine =
          Enum.filter(notes, fn n -> not MapSet.member?(placed, n.id) and in?(n.quote, para) end)

        placed = Enum.reduce(mine, placed, &MapSet.put(&2, &1.id))

        # one highlight per paragraph: the first quote found in it, so the
        # marks never overlap and the prose stays readable
        span = mine |> Enum.find_value(fn n -> located(n.quote, para) end)

        {%{text: para, mark: span, notes: mine, ref: nil}, placed}
      end)

    # a stable id per paragraph, so a note in the rail can point at its mark
    blocks =
      blocks
      |> Enum.with_index()
      |> Enum.map(fn {b, i} -> %{b | ref: "s#{section.ordinal}p#{i}"} end)

    {blocks, placed}
  end

  # Private-use characters: markdown-inert, and not something a draft
  # contains. They mark the anchored span in the source so it survives being
  # rendered and can be turned into a <mark> afterwards.
  @mark_open "\u{E000}"
  @mark_close "\u{E001}"
  @swap_open "\u{E002}"
  @swap_close "\u{E003}"
  @del_open "\u{E004}"
  @del_close "\u{E005}"

  @doc """
  Top-level markdown blocks.

  Splitting on blank lines alone tore fenced code in half — the opening fence
  and the first few lines became one "paragraph" of prose, the rest another,
  and a draft full of code came out as reflowed serif with stray backticks in
  it. So this tracks fence state: everything between a pair of fences is one
  block however many blank lines it contains.
  """
  def split(nil), do: []

  def split(body) do
    body
    |> String.split("\n")
    |> Enum.reduce({[], [], nil}, fn line, {blocks, current, fence} ->
      cond do
        # inside a fence: only its matching closer ends it
        fence && String.starts_with?(String.trim_leading(line), fence) ->
          {[Enum.reverse([line | current]) | blocks], [], nil}

        fence ->
          {blocks, [line | current], fence}

        opener = fence_opener(line) ->
          # a fence starts a block of its own, so flush whatever came before
          {flush(blocks, current), [line], opener}

        String.trim(line) == "" ->
          {flush(blocks, current), [], nil}

        true ->
          {blocks, [line | current], nil}
      end
    end)
    |> then(fn {blocks, current, _fence} -> flush(blocks, current) end)
    |> Enum.reverse()
    |> Enum.map(&Enum.join(&1, "\n"))
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp flush(blocks, []), do: blocks
  defp flush(blocks, current), do: [Enum.reverse(current) | blocks]

  defp fence_opener(line) do
    case Regex.run(~r/^\s*(`{3,}|~{3,})/, line) do
      [_, ticks] -> ticks
      nil -> nil
    end
  end

  @doc """
  One block, rendered as markdown, with its anchored span marked.

  The highlight is computed against the raw characters, so the span is fenced
  with private-use sentinels in the *source* and swapped for a `<mark>` after
  rendering. Doing it the other way round means either literal asterisks on
  the page or a highlight that no longer matches the draft character for
  character — and the second of those quietly breaks the guarantee the notes
  rest on.
  """
  def render_block(text, mark, ref, preview \\ nil)

  def render_block(text, mark, ref, %{original: original, text: replacement})
      when is_binary(original) and is_binary(replacement) do
    # The change is shown in the paragraph rather than in a panel beside it.
    # A rewrite reads fine on its own and wrong in context, and a panel big
    # enough to hold three of them pushes the draft off the screen — which
    # is the one thing this view exists to keep in front of you.
    case :binary.match(text, original) do
      {pos, len} ->
        diffed =
          Marginalia.Rewrite.diff(original, replacement)
          |> Enum.map_join(fn
            {:same, t} -> t
            {:del, t} -> @del_open <> t <> @del_close
            {:ins, t} -> @swap_open <> t <> @swap_close
          end)

        (binary_part(text, 0, pos) <>
           diffed <> binary_part(text, pos + len, byte_size(text) - pos - len))
        |> render_markdown(nil, ref)
        |> String.replace(@swap_open, ~s(<ins class="mg-swap">))
        |> String.replace(@swap_close, "</ins>")
        |> String.replace(@del_open, ~s(<del class="mg-cut">))
        |> String.replace(@del_close, "</del>")
        |> Phoenix.HTML.raw()

      :nomatch ->
        render_block(text, mark, ref, nil)
    end
  end

  def render_block(text, mark, ref, _preview) do
    text |> render_markdown(mark, ref) |> Phoenix.HTML.raw()
  end

  # Pull the highlight inside any emphasis markers at its edges.
  #
  # A beat is anchored to a literal substring of the draft, and the draft is
  # markdown — so a quote of a bolded sentence carries its `**` along with
  # it. Wrapping that whole thing in the mark sentinel puts the sentinel
  # between the delimiter and the rest of the paragraph, and comrak then
  # fails to pair the run: the reader gets a highlighted sentence with four
  # literal asterisks in it.
  #
  # Trimming the delimiters out of the span fixes it at the only layer that
  # can. The quote has to keep them — that is what makes it findable in the
  # writer's own file — and the renderer is where markdown stops being text
  # and starts being syntax.
  @delims ~c"*_`~"

  defp inside_delimiters(text, pos, len) do
    {pos, len} = trim_left(text, pos, len)
    trim_right(text, pos, len)
  end

  defp trim_left(text, pos, len) when len > 0 do
    case :binary.at(text, pos) do
      c when c in @delims -> trim_left(text, pos + 1, len - 1)
      _ -> {pos, len}
    end
  end

  defp trim_left(_text, pos, len), do: {pos, len}

  defp trim_right(text, pos, len) when len > 0 do
    case :binary.at(text, pos + len - 1) do
      c when c in @delims -> trim_right(text, pos, len - 1)
      _ -> {pos, len}
    end
  end

  defp trim_right(_text, pos, len), do: {pos, len}

  defp render_markdown(text, mark, ref) do
    source =
      case mark && :binary.match(text, mark) do
        {pos, len} ->
          {pos, len} = inside_delimiters(text, pos, len)

          binary_part(text, 0, pos) <>
            @mark_open <>
            binary_part(text, pos, len) <>
            @mark_close <> binary_part(text, pos + len, byte_size(text) - pos - len)

        _ ->
          text
      end

    {:safe, html} = Marginalia.Markdown.to_html(source)

    html
    |> IO.iodata_to_binary()
    |> String.replace(@mark_open, ~s(<mark id="anchor-#{ref}">))
    |> String.replace(@mark_close, "</mark>")
  end

  defp in?(nil, _para), do: false
  defp in?("", _para), do: false
  defp in?(quote, para), do: located(quote, para) != nil

  # Reuses the anchoring matcher, so a quote that verified at read time also
  # locates here — same normalisation, same index back to the real characters.
  defp located(nil, _para), do: nil

  defp located(quote, para) do
    case Anchor.verify(quote, para) do
      {:ok, span} when byte_size(span) > 0 -> span
      _ -> nil
    end
  end

  @doc """
  Everything the chat needs in order to talk about one note.

  Returns the note, the section it sits in, and — for a connection — the
  section at the other end too, both in full. The writer clicked a note about
  a link between chapter two and chapter five; answering that without either
  chapter in front of you is the guessing this product exists to avoid.
  """
  def focus(work, key) do
    nodes = Works.list_nodes(work.id)
    by_id = Map.new(nodes, &{&1.id, &1})
    sections = Map.new(Works.list_sections(work.id), &{&1.id, &1})

    case String.split(key, ":") do
      ["beat", id] ->
        with {id, _} <- Integer.parse(id), %{} = n <- by_id[id] do
          %{
            kind: "beat",
            title: n.title,
            body: n.body,
            quote: n.quote,
            sections: [sections[n.section_id]] |> Enum.reject(&is_nil/1)
          }
        else
          _ -> nil
        end

      ["conn", from, to, type] ->
        with {f, _} <- Integer.parse(from),
             {t, _} <- Integer.parse(to),
             %{} = a <- by_id[f],
             %{} = b <- by_id[t] do
          why =
            work.id
            |> Works.all_connections()
            |> Enum.find(&(&1.from.id == f and &1.to.id == t and &1.type == type))
            |> case do
              nil -> nil
              c -> c.why
            end

          %{
            kind: type,
            title: "#{a.title}  —#{String.replace(type, "_", " ")}→  #{b.title}",
            body: why,
            quote: a.quote,
            sections:
              [sections[a.section_id], sections[b.section_id]]
              |> Enum.reject(&is_nil/1)
              |> Enum.uniq_by(& &1.id)
          }
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Group paragraphs into rail rows.

  One grid row per paragraph looks right until you meet a short paragraph
  carrying three notes: the row grows to the height of the notes and tears a
  hole in the prose. So a row is a run of un-annotated paragraphs plus the one
  annotated paragraph that ends it. The body side is then usually the taller
  of the two and the prose reads continuously, while each note still sits
  level with the sentence that caused it.
  """
  def rows(blocks) do
    {rows, tail} =
      Enum.reduce(blocks, {[], []}, fn b, {rows, run} ->
        if b.notes == [] do
          {rows, [b | run]}
        else
          {[%{blocks: Enum.reverse([b | run]), notes: b.notes} | rows], []}
        end
      end)

    rows = Enum.reverse(rows)
    if tail == [], do: rows, else: rows ++ [%{blocks: Enum.reverse(tail), notes: []}]
  end

  @doc """
  Turn a passage the writer selected into a citation, or nil.

  Verified against the draft with the same matcher the notes use, so what
  reaches the model is the manuscript's own characters — not whitespace and
  stray text picked up by a browser selection dragging across markup. A
  selection that is not in the draft is refused rather than quietly sent.
  """
  def cite(work, text) when is_binary(text) do
    case Marginalia.Selection.locate(work, text) do
      {:ok, %{section: s, span: span}} ->
        %{text: span, section: s.title, ordinal: s.ordinal}

      :error ->
        nil
    end
  end

  def cite(_work, _text), do: nil

  @doc """
  What a spine node, thread or question is grounded in.

  The weave draws `realises` and `asks_about` edges from these to the beats
  where they actually happen, so this walks them back to the sections and
  quotes underneath. Without it a thread is an assertion about the draft with
  nothing under it — the writer has to go and find what it means, which is
  the work they came here to avoid.
  """
  def grounding(work, node_id) do
    nodes = Works.list_nodes(work.id) |> Map.new(&{&1.id, &1})
    sections = Works.list_sections(work.id) |> Map.new(&{&1.id, &1})

    beats =
      work.id
      |> Works.list_edges()
      |> Enum.filter(&(&1.edge_type in ~w(realises asks_about)))
      |> Enum.flat_map(fn e ->
        cond do
          e.from_id == node_id -> [{nodes[e.to_id], e.rationale}]
          e.to_id == node_id -> [{nodes[e.from_id], e.rationale}]
          true -> []
        end
      end)
      |> Enum.reject(fn {n, _} -> is_nil(n) or n.node_type != "beat" end)
      |> Enum.uniq_by(fn {n, _} -> n.id end)
      |> Enum.map(fn {n, why} ->
        %{
          id: n.id,
          title: n.title,
          quote: n.quote,
          why: why,
          section: sections[n.section_id]
        }
      end)
      |> Enum.sort_by(fn g -> {g.section && g.section.ordinal, g.id} end)

    %{
      beats: beats,
      sections: beats |> Enum.map(& &1.section) |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1.id)
    }
  end

  @doc """
  A quote as it reads on the page rather than as it sits in the source.

  Quotes are copied out of the markdown, so a link comes back as
  `[words](url)` and a call as `` `gen_stage` ``. Fine for matching, wrong
  for showing someone their own sentence back.
  """
  def plain(nil), do: ""

  def plain(text) do
    text
    |> String.replace(~r/\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/[`*_~]/, "")
    |> String.replace(~r/^#+\s*/m, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  The draft's headings, in order, for jumping around it.

  Section titles plus any markdown headings inside them. A long draft read
  one paragraph at a time is hard to keep a shape of, and scrolling for a
  section you half remember is the tax on that.
  """
  def outline(page) when is_list(page) do
    Enum.flat_map(page, fn sec ->
      section_entry = %{
        id: "sec-#{sec.section.ordinal}",
        level: 0,
        title: sec.section.title,
        words: sec.section.word_count
      }

      inner =
        sec.blocks
        |> Enum.filter(&heading?(&1.text))
        |> Enum.map(fn b ->
          %{
            id: "block-#{b.ref}",
            level: heading_level(b.text),
            title: heading_text(b.text),
            words: nil
          }
        end)
        # the section's own title is usually its first heading; do not say it twice
        |> Enum.reject(&(String.downcase(&1.title) == String.downcase(sec.section.title)))

      [section_entry | inner]
    end)
  end

  def outline(_), do: []

  @doc "Is this block a markdown heading?"
  def heading?(text), do: Regex.match?(~r/^\#{1,6}\s+\S/, text)

  def heading_level(text) do
    case Regex.run(~r/^(\#{1,6})\s/, text) do
      [_, hashes] -> String.length(hashes)
      nil -> 1
    end
  end

  def heading_text(text), do: text |> String.replace(~r/^\#+\s*/, "") |> String.trim()
end
