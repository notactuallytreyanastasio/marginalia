defmodule Marginalia.Works.Segmenter do
  @moduledoc """
  Splits a manuscript into analysable sections, deterministically.

  No model is involved. Segmentation mistakes made by a heuristic are obvious
  and cheap for the writer to see; segmentation mistakes made by an LLM are
  neither, and every downstream quote depends on getting this right.

  Three strategies, in order of how much they can be trusted:

  1. **Markdown headings** — the writer told us where the breaks are.
  2. **Marker lines** — `Chapter 7`, `PART TWO`, `VII.`, a bare `* * *`.
  3. **Paragraph windows** — no structure to find, so pack paragraphs into
     units of roughly `@target_words` without ever splitting a paragraph.

  Whichever strategy wins, an oversized result is then windowed. Trusting the
  writer's headings is right about *where* the breaks go and says nothing about
  how far apart they are: an oral argument transcript with a title and a single
  `## Rebuttal` has two headings and twelve thousand words between them, and
  came back as one section the model could not read closely and the reader
  could not navigate. A heading is a boundary, not a promise of brevity.

  A short piece (a blog post, an essay) legitimately comes back as one section.
  """

  # big enough that a section carries real context, small enough that the model
  # reads it properly and a failed section is cheap to retry
  @target_words 1_800
  @min_words 250
  # past this a section stops being read closely, so it is windowed even when
  # a heading put it there
  @max_words 4_000

  @marker ~r/^\s*(?:(?:chapter|part|book|act|section)\s+(?:[0-9]+|[ivxlc]+|[a-z]+)|[ivxlc]{1,7}\.|\*\s*\*\s*\*|—{3,}|-{3,})\s*[:.\-—]?\s*(.{0,80})$/i

  @doc "Split raw manuscript text into `[%{title: String.t(), body: String.t()}]`."
  def split(text) when is_binary(text) do
    text = normalize(text)

    chunks =
      cond do
        text == "" -> []
        chunks = by_markdown(text) -> chunks
        chunks = by_marker(text) -> chunks
        true -> by_windows(text)
      end

    # One sentence per line inside every prose paragraph, so a draft is in
    # that form before its sections and its baseline are captured. After the
    # split, not before: a chapter marker sits on the line above its first
    # sentence with no blank line between, and reflowing first would fold
    # "Chapter 2" into the paragraph and lose the boundary it marks. See
    # `Marginalia.Works.Sentences` for why, and for what it leaves alone.
    Enum.map(chunks, fn c -> %{c | body: Marginalia.Works.Sentences.reflow(c.body)} end)
  end

  def split(_), do: []

  # Normalise line endings and collapse runs of blank lines, so paragraph
  # detection behaves the same on text pasted from Word, Docs or a terminal.
  defp normalize(text) do
    text
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # --- 1. markdown headings ------------------------------------------------

  defp by_markdown(text) do
    lines = String.split(text, "\n")
    heads = Enum.count(lines, &Regex.match?(~r/^\#{1,3}\s+\S/, &1))

    if heads >= 2 do
      lines
      |> chunk_on(fn line -> Regex.match?(~r/^\#{1,3}\s+\S/, line) end, fn line ->
        line |> String.replace(~r/^#+\s*/, "") |> String.trim()
      end)
      |> finish()
    end
  end

  # --- 2. marker lines -----------------------------------------------------

  defp by_marker(text) do
    lines = String.split(text, "\n")

    markers =
      Enum.count(lines, fn l ->
        String.length(String.trim(l)) < 90 and Regex.match?(@marker, l)
      end)

    if markers >= 2 do
      lines
      |> chunk_on(
        fn l -> String.length(String.trim(l)) < 90 and Regex.match?(@marker, l) end,
        &String.trim/1
      )
      |> finish()
    end
  end

  defp chunk_on(lines, is_head?, title_of) do
    {chunks, current} =
      Enum.reduce(lines, {[], nil}, fn line, {acc, cur} ->
        if is_head?.(line) do
          acc = if cur, do: [cur | acc], else: acc
          {acc, %{title: title_of.(line), lines: []}}
        else
          case cur do
            nil ->
              # prose before the first marker is its own opening section
              {acc, %{title: "Opening", lines: [line]}}

            cur ->
              {acc, %{cur | lines: [line | cur.lines]}}
          end
        end
      end)

    if(current, do: [current | chunks], else: chunks)
    |> Enum.reverse()
    |> Enum.map(fn c ->
      %{
        title: blank_to_untitled(c.title),
        body: c.lines |> Enum.reverse() |> Enum.join("\n") |> String.trim()
      }
    end)
  end

  # --- 3. paragraph windows ------------------------------------------------

  # Reflowed before the title is derived: the title is the first line, and
  # as the text arrived the first line could be two words of a wrapped
  # sentence, too short to be a title, so the section was "Section 1".
  defp by_windows(text) do
    text
    |> window()
    |> Enum.with_index(1)
    |> Enum.map(fn {body, i} ->
      body = Marginalia.Works.Sentences.reflow(body)
      %{title: derive_title(body, i), body: body}
    end)
    |> finish()
  end

  # Pack paragraphs into bodies of roughly @target_words, never splitting a
  # paragraph. A single paragraph longer than the target is its own window --
  # too big, but the alternative is cutting a sentence in half, and every
  # downstream quote is anchored against this text.
  defp window(text) do
    text
    |> String.split(~r/\n\s*\n/, trim: true)
    |> Enum.reduce([], fn para, acc ->
      para = String.trim(para)
      words = word_count(para)

      case acc do
        [%{words: w} = head | rest] when w < @target_words ->
          [%{head | paras: [para | head.paras], words: w + words} | rest]

        _ ->
          [%{paras: [para], words: words} | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn c -> c.paras |> Enum.reverse() |> Enum.join("\n\n") end)
  end

  # --- shared --------------------------------------------------------------

  # Drop empties, then fold any runt section into its predecessor: a 40-word
  # "section" produces a worthless read and still costs a call.
  defp finish(chunks) do
    chunks
    |> Enum.reject(&(String.trim(&1.body) == ""))
    |> Enum.reduce([], fn chunk, acc ->
      case acc do
        [prev | rest] when :erlang.map_get(:body, prev) != nil ->
          if word_count(chunk.body) < @min_words and word_count(prev.body) < @target_words do
            [%{prev | body: prev.body <> "\n\n" <> chunk.body} | rest]
          else
            [chunk | acc]
          end

        _ ->
          [chunk | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.flat_map(&subdivide/1)
    |> case do
      [] -> nil
      chunks -> chunks
    end
  end

  # An over-long section, windowed, keeping the heading the writer gave it so
  # the pieces are still findable as parts of the same thing.
  defp subdivide(%{title: title, body: body} = chunk) do
    if word_count(body) <= @max_words do
      [chunk]
    else
      parts = window(body)
      n = length(parts)

      if n < 2 do
        [chunk]
      else
        parts
        |> Enum.with_index(1)
        |> Enum.map(fn {body, i} -> %{title: "#{title} (#{i}/#{n})", body: body} end)
      end
    end
  end

  # The first line of the window, as a label. Markdown is stripped rather
  # than rendered: these titles go in a contents list, a minimap and a
  # breadcrumb, none of which parse markdown, and "**JUSTICE GORSUCH:**
  # Counsel --" was appearing with its asterisks in all three.
  defp derive_title(body, i) do
    first =
      body
      |> String.split("\n", parts: 2)
      |> hd()
      |> String.replace(~r/^\#{1,6}\s+/, "")
      |> String.replace(~r/[*_`]+/, "")
      |> String.trim()
      |> String.slice(0, 60)

    if String.length(first) > 12, do: "#{i}. #{first}…", else: "Section #{i}"
  end

  defp blank_to_untitled(""), do: "Untitled"
  defp blank_to_untitled(t), do: String.slice(t, 0, 120)

  defp word_count(s), do: length(String.split(s, ~r/\s+/, trim: true))
end
