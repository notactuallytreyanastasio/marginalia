defmodule Marginalia.Analysis.Anchor do
  @moduledoc """
  Verifies that a model-supplied quote actually appears in the writer's text,
  and replaces it with the span as the writer actually wrote it.

  This is the discipline the product is sold on: a writer will forgive a dull
  observation and will never forgive a confident one about a sentence they did
  not write. A node whose quote cannot be matched is discarded here, before it
  is stored, so nothing unanchored can reach the page.

  The subtlety that matters: drafts are full of hard line wraps and curly
  punctuation, and models hand back quotes with that flattened out. Matching on
  a normalised copy is therefore necessary — but returning the *model's*
  flattened version would store a quote the writer cannot find by searching
  their own manuscript, which is exactly the trust we are trying to buy. So the
  normalised copy carries an index back to the original, and every match
  returns the true source span, newlines and curly quotes intact.

  ## Why there is no fuzzy matching

  There was, and it was wrong in the dangerous direction. It scored set
  membership over a sliding window, which is order-blind: a quote with its
  words rearranged matched, and deleting a negation from a ten-word quote
  scored exactly at the threshold and passed — storing a span that still
  contained the "not" the model had dropped. A matcher that accepts a
  paraphrase is worse than no matcher, because the whole promise is that the
  writer can search their draft for what we showed them.

  Normalisation already absorbs the only differences a faithful quote should
  have: whitespace, line wraps, curly punctuation, case. Anything beyond that
  is the model having reworded, and a reworded quote is exactly what should be
  discarded.
  """

  @min_chars 8

  @doc """
  `{:ok, source_span}` or `:error`.

  The returned string is always a literal substring of `source`.
  """
  def verify(nil, _source), do: :error
  def verify(_quote, nil), do: :error

  def verify(quote, source) when is_binary(quote) and is_binary(source) do
    quote = String.trim(quote)

    if String.length(quote) < @min_chars do
      :error
    else
      {norm_source, index} = normalize_indexed(source)
      norm_quote = normalize(quote)

      case :binary.match(norm_source, norm_quote) do
        {pos, len} ->
          from = char_pos(norm_source, pos)
          to = char_pos(norm_source, pos + len) - 1
          {:ok, span(source, index, from, to)}

        :nomatch ->
          :error
      end
    end
  end

  def verify(_quote, _source), do: :error

  # :binary.match works in bytes; the index map is per grapheme.
  defp char_pos(binary, byte_pos) do
    binary |> binary_part(0, byte_pos) |> String.length()
  end



  defp span(source, index, from_char, to_char) do
    start = Enum.at(index, from_char)
    stop = Enum.at(index, to_char) || start

    if is_integer(start) and is_integer(stop) and stop >= start do
      String.slice(source, start, stop - start + 1)
    else
      ""
    end
  end

  @doc """
  A normalised copy of `text`, plus a list mapping each normalised grapheme
  back to its index in the original.
  """
  def normalize_indexed(text) do
    {chars, idxs, _space} =
      text
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.reduce({[], [], true}, fn {g, i}, {chars, idxs, prev_space?} ->
        cond do
          whitespace?(g) ->
            if prev_space? do
              {chars, idxs, true}
            else
              {[" " | chars], [i | idxs], true}
            end

          true ->
            folded = fold(g)
            n = String.length(folded)
            {[folded | chars], List.duplicate(i, n) ++ idxs, false}
        end
      end)

    {chars |> Enum.reverse() |> Enum.join(), Enum.reverse(idxs)}
  end

  defp normalize(text) do
    {n, _idx} = normalize_indexed(text)
    n
  end

  defp whitespace?(g), do: g in [" ", "\n", "\r", "\t", " ", "​"]


  defp fold("‘"), do: "'"
  defp fold("’"), do: "'"
  defp fold("‛"), do: "'"
  defp fold("“"), do: "\""
  defp fold("”"), do: "\""
  defp fold("–"), do: "-"
  defp fold("—"), do: "-"
  defp fold("…"), do: "..."
  defp fold(g), do: String.downcase(g)

  @doc """
  Keep only nodes whose quote verifies, rewriting each to the source's own
  wording. Returns `{kept, discarded_count}` so the rejection rate can be
  logged — a pass that suddenly starts failing anchoring has gone wrong.
  """
  def filter(nodes, source) do
    {kept, dropped} =
      Enum.reduce(nodes, {[], 0}, fn node, {kept, dropped} ->
        case verify(node[:quote] || node["quote"], source) do
          {:ok, q} when byte_size(q) > 0 -> {[Map.put(node, :quote, q) | kept], dropped}
          _ -> {kept, dropped + 1}
        end
      end)

    {Enum.reverse(kept), dropped}
  end
end
