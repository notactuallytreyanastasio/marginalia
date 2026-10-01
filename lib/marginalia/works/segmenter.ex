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

  # The three strategies, the thresholds (1,800-word windows, 250-word
  # runts, 4,000-word subdivision) and the titles are written in Temper,
  # temper/marginalia-core/src/segmenter.temper.md, and generated into
  # Temper.MarginaliaCore. Its marker test reproduces the original regex
  # byte for byte, including that a "———" line is never a marker; see the
  # notes there.

  @doc "Split raw manuscript text into `[%{title: String.t(), body: String.t()}]`."
  def split(text) when is_binary(text) do
    text
    |> Temper.MarginaliaCore.segment()
    |> Enum.map(fn %Temper.MarginaliaCore.Section{title: title, body: body} ->
      %{title: title, body: body}
    end)
  end

  def split(_), do: []
end
