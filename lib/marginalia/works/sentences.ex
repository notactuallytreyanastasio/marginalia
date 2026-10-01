defmodule Marginalia.Works.Sentences do
  @moduledoc """
  Prose stored one sentence per line.

  A paragraph is still a paragraph: blank lines separate them, exactly as
  before, and everything that reads or anchors into a draft keeps working
  on paragraphs. Inside a paragraph, though, each sentence gets its own
  line. Two reasons.

  The first is diffing. The revisions table holds a paragraph before and
  after each edit, and the Changes view diffs words inside a changed
  paragraph, so the app itself was never the problem. Everything outside
  it is: a `git diff`, a pasted diff in a chat, a side-by-side in any
  editor. Those diff by line, and a line that holds a whole 300-word
  paragraph is marked changed because a comma moved. A line that holds one
  sentence is marked changed because that sentence changed.

  The second is what arrives. Text pasted from a terminal or a text editor
  comes hard-wrapped at 72 or 80 columns, with a newline every dozen words
  mid-sentence. Those newlines carry no meaning, and any renderer that
  honours them breaks sentences in the wrong places. Reflowing on arrival
  throws them away and puts the only meaningful breaks back: paragraph
  ends and sentence ends.

  ## What is left alone

  Anything that is not a prose paragraph: headings, fenced code, indented
  code, tables, list items, HTML. A blockquote is prose with a `>` on each
  line, so it is reflowed and re-prefixed. The rule for leaving a block
  alone is conservative on purpose. A poem reflowed into sentences is a
  poem destroyed, and a list item split across two unindented lines is no
  longer a list item, so the cost of a wrong guess is high and the cost of
  leaving a block as it came is nothing.

  ## Where it runs

  On arrival, from the segmenter, so a draft is in this form before its
  sections and its baseline are captured. And on every edit, in
  `Works.replace_block/4`, so the form survives the writer's own changes.
  Nothing rewrites drafts already stored; the baseline-plus-patches replay
  the diff view depends on would not survive that, and the renderer joins
  lines inside a paragraph either way.

  Idempotent: reflowing reflowed text changes nothing.
  """

  # The rules (sentence ends, abbreviations, what counts as prose) are
  # written in Temper, temper/marginalia-core/src/sentences.temper.md, and
  # generated into Temper.MarginaliaCore. The three Unicode classes its
  # regexes used (\s, \d and \p{Lu} under the `u` flag) are answered by PCRE
  # itself, in temper/marginalia-core/src/_connected.ex.

  @doc "Every prose paragraph in `text` reflowed to one sentence per line."
  def reflow(nil), do: nil
  def reflow(text) when is_binary(text), do: Temper.MarginaliaCore.reflow(text)

  @doc "One paragraph's sentences, each on its own line. Non-prose blocks come back as they were."
  def reflow_block(block), do: Temper.MarginaliaCore.reflowBlock(block)
end
