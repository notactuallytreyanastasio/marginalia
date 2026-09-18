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

  # a line this much under the usual measure is the end of a paragraph
  @short 0.78

  # page furniture: the running head and foot of a slip opinion
  @furniture [
    ~r/^Cite as:/,
    ~r/^Opinion of the Court$/,
    ~r/^Syllabus$/,
    ~r/^Per Curiam$/,
    # "GORSUCH, J., dissenting" / "ROBERTS, C. J., concurring in part"
    ~r/^(?:[A-Z]+, )+(?:C\. )?J\.,\s+(?:concurring|dissenting)/,
    ~r/^\d{1,3}$/
  ]

  @doc """
  True when `text` looks like it came off a page rather than out of an
  editor: many lines, almost no blank ones.

  Text that already has paragraphs is left alone, which is what should
  happen to an argument transcript — its turns are already separated.
  """
  def wrapped?(text) when is_binary(text) do
    lines = text |> String.split("\n") |> Enum.reject(&(String.trim(&1) == ""))
    blanks = length(String.split(text, ~r/\n\s*\n/)) - 1

    length(lines) >= 12 and blanks <= div(length(lines), 12)
  end

  def wrapped?(_), do: false

  @doc "Reflow `text`, or hand it back untouched if it does not need it."
  def reflow(text) when is_binary(text) do
    if wrapped?(text), do: do_reflow(text), else: text
  end

  def reflow(text), do: text

  defp do_reflow(text) do
    keep = intact_hyphens(text)

    lines =
      text
      |> String.replace("\r\n", "\n")
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&furniture?/1)
      |> Enum.reject(&(&1 == ""))

    measure = measure(lines)

    lines
    |> chunk_paragraphs(measure)
    |> Enum.map(&join(&1, keep))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  # The usual line length on the page. The median, not the mean: a handful
  # of one-word lines would drag a mean down and take the threshold with
  # it, and then nothing would look short.
  defp measure(lines) do
    lengths = lines |> Enum.map(&String.length/1) |> Enum.sort()

    case lengths do
      [] -> 0
      _ -> Enum.at(lengths, div(length(lengths) * 2, 3))
    end
  end

  defp furniture?(line), do: Enum.any?(@furniture, &Regex.match?(&1, line)) or caption?(line)

  # The running head is the case caption in capitals, with the page number
  # on whichever side the page is: "2 LANDOR v. LOUISIANA DEPT. OF
  # CORRECTIONS AND", then "PUBLIC SAFETY" on the line below. It is not
  # quite all capitals -- the "v." never is -- so this counts rather than
  # matches, which also keeps it from eating a sentence that merely opens
  # with a number.
  defp caption?(line) do
    body = String.replace(line, ~r/^\d{1,3}\s+|\s+\d{1,3}$/, "")
    letters = Regex.scan(~r/\p{L}/u, body) |> List.flatten()
    upper = Enum.count(letters, &(&1 == String.upcase(&1)))

    length(letters) >= 8 and upper / length(letters) >= 0.75
  end

  # A paragraph runs until a line that does not reach the measure, or a
  # heading, either of which stands alone.
  defp chunk_paragraphs(lines, measure) do
    {done, current} =
      Enum.reduce(lines, {[], []}, fn line, {done, current} ->
        cond do
          heading?(line) ->
            {[[line], Enum.reverse(current) | done], []}

          String.length(line) < measure * @short ->
            {[Enum.reverse([line | current]) | done], []}

          true ->
            {done, [line | current]}
        end
      end)

    [Enum.reverse(current) | done]
    |> Enum.reverse()
    |> Enum.reject(&(&1 == []))
  end

  # a markdown heading, or the bare roman numeral an opinion divides on
  defp heading?(line) do
    Regex.match?(~r/^\#{1,6}\s+\S/, line) or Regex.match?(~r/^[IVXL]{1,5}$/, line) or
      Regex.match?(~r/^[A-Z]$/, line)
  end

  @doc """
  A quote, put through the same joining as the text it is anchored to.

  `reflow/1` declines to touch anything that is not page text, and a quote
  is two or three lines — so a quote spanning a mended hyphen would keep
  its `capaci-` while the section it came from now reads `capacities`, and
  it would never verify again. Hyphens are decided against `source`, the
  whole document, because one quote is far too little evidence.
  """
  def align(quote, source) when is_binary(quote) and is_binary(source) do
    quote
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> join(intact_hyphens(source))
  end

  def align(quote, _source), do: quote

  defp join(lines, keep) do
    lines
    |> Enum.reduce("", fn line, acc ->
      cond do
        acc == "" -> line
        String.ends_with?(acc, "-") -> mend(acc, line, keep)
        true -> acc <> " " <> line
      end
    end)
    |> String.trim()
  end

  # `capaci-` + `ties` — one word or two?
  defp mend(acc, line, keep) do
    stem = acc |> String.trim_trailing("-") |> String.split(~r/\s/) |> List.last()
    [head | _] = String.split(line, ~r/\s/, parts: 2)
    word = String.downcase("#{stem}-#{strip_punct(head)}")

    if MapSet.member?(keep, word) do
      acc <> line
    else
      String.trim_trailing(acc, "-") <> line
    end
  end

  defp strip_punct(word), do: String.replace(word, ~r/[^\p{L}\p{N}'’-]+$/u, "")

  # every hyphenated word the document uses within a line, which is the
  # only evidence available that a hyphen is the author's and not the
  # typesetter's
  defp intact_hyphens(text) do
    ~r/[\p{L}\p{N}’']+-[\p{L}\p{N}’']+/u
    |> Regex.scan(text)
    |> Enum.map(fn [w] -> String.downcase(w) end)
    |> MapSet.new()
  end
end
