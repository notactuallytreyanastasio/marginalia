defmodule Marginalia.Works.Reflow do
  @moduledoc """
  Puts the paragraphs back into text that came out of a PDF.

  `pdftotext` hands back one line per line *of the page*, hyphens and all.
  Stored that way, a Supreme Court opinion has no paragraph breaks
  anywhere in it — which is not merely ugly. The reading view works in
  paragraphs: a paragraph is a block, a block is a row, and a note sits
  beside the block it is anchored to. With no breaks, a whole section is
  one block, and every note the other documents have about any part of it
  piles into a single row eighteen cards deep next to four lines of prose.

  The page indentation that marks a new paragraph is gone by the time the
  text reaches us, so the break is recovered from line *length* instead: a
  page of body text has a consistent measure, and the line that ends a
  paragraph is the short one. That is a heuristic, and it is the right
  kind — when it is wrong it splits a paragraph in two, which a reader
  survives, rather than joining two that should be apart.

  ## What this must not do

  Every node in the graph is anchored to a quote that is a literal
  substring of the section it came from. Whitespace changes are free —
  `Marginalia.Analysis.Anchor` matches on a normalised copy — but
  de-hyphenation genuinely changes characters, so anything reflowed here
  has to have its quotes re-verified against the new text afterwards.

  ## Hyphens

  `capaci-\\nties` should be joined into one word and `for-\\ncause` should
  keep its hyphen, and nothing about the two looks different. So the
  document is asked: if `for-cause` appears somewhere else in it, intact
  and within a line, the hyphen is real and is kept. Otherwise it was the
  typesetter's and it goes.
  """

  # The heuristics (page detection, the measure, furniture, headings,
  # hyphens) are written in Temper, temper/marginalia-core/src/reflow.temper.md,
  # and generated into Temper.MarginaliaCore. Unicode letters, case and
  # grapheme counts come from the host, in src/_connected.ex.
  alias Temper.MarginaliaCore, as: Core

  @doc """
  True when `text` looks like it came off a page rather than out of an
  editor: many lines, almost no blank ones.

  Text that already has paragraphs is left alone, which is what should
  happen to an argument transcript — its turns are already separated.
  """
  def wrapped?(text) when is_binary(text), do: Core.isWrapped(text)
  def wrapped?(_), do: false

  @doc "Reflow `text`, or hand it back untouched if it does not need it."
  def reflow(text) when is_binary(text), do: Core.reflowPage(text)
  def reflow(text), do: text

  @doc """
  A quote, put through the same joining as the text it is anchored to.

  `reflow/1` declines to touch anything that is not page text, and a quote
  is two or three lines — so a quote spanning a mended hyphen would keep
  its `capaci-` while the section it came from now reads `capacities`, and
  it would never verify again. Hyphens are decided against `source`, the
  whole document, because one quote is far too little evidence.
  """
  def align(quote, source) when is_binary(quote) and is_binary(source),
    do: Core.align(quote, source)

  def align(quote, _source), do: quote
end
