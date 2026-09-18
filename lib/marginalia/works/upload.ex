defmodule Marginalia.Works.Upload do
  @moduledoc """
  What an upload form sent, turned into attributes for `create_work/2`.

  Two forms arrive at the same place. One is the LiveView at `/works/new`.
  The other is that same markup submitted the plain way, by a browser with
  no live socket driving it — and the two have to agree about the word
  limit and about what counts as an empty draft, or a writer gets a
  different answer depending on whether their websocket happened to be up.
  So the rule is here, once, and both call it.
  """

  # Roughly a long novel. Not a technical limit — a read of this costs real
  # money per section, and a draft this size is almost always a paste of
  # something that should have been split.
  @max_words 120_000

  @doc "The ceiling, for anyone who needs to say it out loud."
  def max_words, do: @max_words

  @type problem :: :empty | {:too_long, pos_integer()}

  @doc """
  Check the text and build the attributes, or say what is wrong with it.

  `title` may be nil; the caller has usually already chosen a better
  fallback than this one (an attached file's name, say).
  """
  @spec prepare(String.t() | nil, String.t() | nil, String.t() | nil) ::
          {:ok, map()} | {:error, problem()}
  def prepare(title, body, intent) do
    body = body || ""

    case word_count(body) do
      0 ->
        {:error, :empty}

      n when n > @max_words ->
        {:error, {:too_long, n}}

      _ ->
        {:ok,
         %{
           "title" => blank(title) || "Untitled draft",
           "body" => body,
           "intent" => blank(intent)
         }}
    end
  end

  def word_count(text), do: length(String.split(text, ~r/\s+/, trim: true))

  @doc "The sentence shown for a draft over the limit."
  def too_long_message(words) do
    "That's #{commas(words)} words, and the limit is #{commas(@max_words)} for now. " <>
      "Split it and upload the first part."
  end

  @doc "Trimmed, or nil if there was nothing but whitespace."
  def blank(nil), do: nil

  def blank(s) when is_binary(s) do
    case String.trim(s) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp commas(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
