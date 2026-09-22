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

  # A period after one of these is not the end of a sentence. Single
  # capitals cover initials ("J. K. Rowling"). The list is short by design:
  # a missed abbreviation costs one wrong line break, a wrong entry costs a
  # missed sentence boundary on every draft.
  @abbrev ~r/(?:^|\s)(?:e\.g|i\.e|vs|etc|cf|viz|ca|Mr|Mrs|Ms|Dr|Prof|St|No|Fig|Jr|Sr|Inc|Ltd|Co|[A-Z])\.["'”’)\]]*$/u

  # Sentence end: terminal punctuation, any closing quotes or brackets,
  # whitespace, then something that starts a sentence: an opening quote or
  # bracket or markdown delimiter, a capital, or a digit.
  @boundary ~r/([.!?]["'”’)\]]*)\s+(?=["'“‘(\[*_`]*(?:\p{Lu}|\d))/u

  @doc "Every prose paragraph in `text` reflowed to one sentence per line."
  def reflow(nil), do: nil
  def reflow(""), do: ""

  def reflow(text) when is_binary(text) do
    text
    |> Marginalia.Reading.split()
    |> Enum.map_join("\n\n", &reflow_block/1)
  end

  @doc "One paragraph's sentences, each on its own line. Non-prose blocks come back as they were."
  def reflow_block(block) do
    cond do
      not prose?(block) ->
        block

      quoted?(block) ->
        block
        |> String.split("\n")
        |> Enum.map_join("\n", &String.replace(&1, ~r/^\s*>\s?/, ""))
        |> reflow_block()
        |> String.split("\n")
        |> Enum.map_join("\n", &("> " <> &1))

      true ->
        block
        |> String.split(~r/\s*\n\s*/)
        |> Enum.join(" ")
        |> String.replace(~r/[ \t]+/, " ")
        |> String.trim()
        |> split_sentences()
    end
  end

  # One line holds one sentence, except where the "sentence" ended on an
  # abbreviation, which is rejoined with the next.
  defp split_sentences(joined) do
    @boundary
    |> Regex.replace(joined, "\\1\n")
    |> String.split("\n")
    |> Enum.reduce([], fn line, acc ->
      case acc do
        [prev | rest] ->
          if Regex.match?(@abbrev, prev), do: [prev <> " " <> line | rest], else: [line | acc]

        [] ->
          [line]
      end
    end)
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp quoted?(block), do: Regex.match?(~r/^\s*>/, block)

  # Prose is what is left after every block shape markdown gives a meaning
  # to line breaks in.
  defp prose?(block) do
    first = block |> String.split("\n", parts: 2) |> hd() |> String.trim_leading()
    lines = String.split(block, "\n")

    cond do
      Regex.match?(~r/^(`{3,}|~{3,})/, first) -> false
      Regex.match?(~r/^\#{1,6}\s/, first) -> false
      Regex.match?(~r/^(\s{4,}|\t)/, block) -> false
      Regex.match?(~r/^[-*+]\s|^\d+[.)]\s/, first) -> false
      Regex.match?(~r/^<[a-zA-Z!\/]/, first) -> false
      Regex.match?(~r/^(-{3,}|\*{3,}|_{3,})\s*$/, first) -> false
      Enum.all?(lines, &String.starts_with?(String.trim_leading(&1), "|")) -> false
      true -> true
    end
  end
end
