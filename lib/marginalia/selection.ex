defmodule Marginalia.Selection do
  @moduledoc """
  Where a passage the reader selected on the page lives in the draft.

  A selection is made against *rendered* text; the draft is markdown. Those
  two strings differ, and the first three attempts at this encoded the ways
  they differ — strip backticks, blank out link targets, blank out list
  markers. Each fixed one construct and left every other one broken: tables,
  footnotes, images, entities, setext headings, reference links, whatever
  markdown grows next.

  The transformation is not something to guess at. We render the page
  ourselves, so both strings are in hand, and the page's text is very nearly
  a subsequence of the source's. Walking the two together gives a map from
  every rendered character back to the character in the draft it came from —
  with no knowledge of markdown in it anywhere.

  What comes back is a literal substring of the draft, as before. The
  difference is that it now survives constructs nobody has thought about.
  """

  alias Marginalia.{Markdown, Reading, Works}

  @min_chars 12

  @doc """
  Find `text` in the draft.

  `{:ok, %{section:, block:, span:}}` where `span` is the exact source
  substring, or `:error`.
  """
  def locate(work, text) when is_binary(text) do
    if String.length(squash(text)) < @min_chars do
      :error
    else
      work.id
      |> Works.list_sections()
      |> Enum.find_value(:error, fn section ->
        blocks = Reading.split(section.body)

        found =
          Enum.find_value(blocks, nil, fn block ->
            case in_block(block, text) do
              nil -> nil
              span -> %{block: block, span: span}
            end
          end)

        # A selection can run across a paragraph break, out of a paragraph
        # and into a list, or over a heading. Those are separate blocks, so
        # the section is tried whole before giving up on it.
        found = found || section_wide(section, text)

        found && {:ok, Map.put(found, :section, section)}
      end)
    end
  end

  def locate(_work, _text), do: :error

  # A selection can run across several blocks — the reader dragged through a
  # paragraph break, or out of a paragraph and into a list. Those are
  # separate blocks here, so the whole section is tried as one piece too.
  defp section_wide(section, text) do
    case in_block(section.body, text) do
      nil -> nil
      span -> %{block: section.body, span: span}
    end
  end

  @doc false
  def in_block(block, needle) do
    {source_dense, source_at} = dense(block)
    {plain_dense, _} = block |> rendered_text() |> dense()
    {needle_dense, _} = dense(needle)

    case :binary.match(plain_dense, needle_dense) do
      :nomatch ->
        nil

      {pos, len} when len > 0 ->
        map = alignment(source_dense, plain_dense)
        from = Enum.at(map, char_index(plain_dense, pos))
        to = Enum.at(map, char_index(plain_dense, pos + len) - 1)
        span(block, source_at, from, to)

      _ ->
        nil
    end
  end

  @doc """
  The text of one markdown block as the page shows it.

  Rendered with the same renderer the page uses, then stripped to its text,
  so this cannot drift from what the reader actually selected.
  """
  def rendered_text(source) do
    {:safe, html} = Markdown.to_html(source)

    html
    |> IO.iodata_to_binary()
    |> String.replace(~r/<(script|style)\b[^>]*>.*?<\/\1>/s, "")
    |> String.replace(~r/<[^>]+>/, " ")
    |> unescape()
  end

  defp unescape(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end

  # --------------------------------------------------------------------------
  # Aligning the page back to the draft
  # --------------------------------------------------------------------------

  @doc """
  A string with every space removed, and where each remaining character came
  from.

  Whitespace is dropped before anything else is attempted. The renderer
  *invents* it — a `</li>` becomes a line break that is nowhere in the
  source — so trying to line it up sends the alignment to the wrong end of
  the block on the first character. What the reader selected and what the
  draft says agree on the letters; they do not agree on the spaces.
  """
  def dense(text) do
    {chars, idxs} =
      text
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.reject(fn {g, _} -> String.match?(g, ~r/\s/u) end)
      |> Enum.unzip()

    {Enum.join(chars), idxs}
  end

  # The rendered text is a subsequence of the source once the spaces are
  # gone: the renderer removes syntax, it does not reorder. So walk the two
  # together and take, for each rendered character, the next source
  # character that matches. There is no markdown knowledge in here, which is
  # the entire point — it works for tables, footnotes, images and whatever
  # markdown grows next, none of which anyone has to think about.
  @doc false
  def alignment(source_dense, plain_dense) do
    src = String.graphemes(source_dense) |> List.to_tuple()
    n = tuple_size(src)

    {map, _} =
      plain_dense
      |> String.graphemes()
      |> Enum.map_reduce(0, fn g, i ->
        case seek(src, n, i, g) do
          nil -> {min(i, max(n - 1, 0)), i}
          j -> {j, j + 1}
        end
      end)

    map
  end

  # bounded, so one character the renderer invented cannot throw the
  # alignment to the end of a long block and lose everything after it
  @lookahead 400

  defp seek(_src, 0, _from, _g), do: nil

  defp seek(src, n, from, g) do
    Enum.find(from..min(n - 1, from + @lookahead)//1, fn j -> elem(src, j) == g end)
  end

  defp span(_block, _at, nil, _to), do: nil
  defp span(_block, _at, _from, nil), do: nil

  defp span(block, source_at, from, to) do
    with a when is_integer(a) <- Enum.at(source_at, from),
         b when is_integer(b) <- Enum.at(source_at, to),
         true <- b >= a do
      String.slice(block, a, b - a + 1)
    else
      _ -> nil
    end
  end

  @doc false
  def squash(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp char_index(binary, byte_pos) do
    binary |> binary_part(0, byte_pos) |> String.length()
  end
end
