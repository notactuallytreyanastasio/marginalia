defmodule Marginalia.Mutterings do
  @moduledoc """
  The words in front of the three dots.

  While a model is reading, the page showed three pulsing dots and nothing
  else, in the chat, in the rewrite panel and beside a linked pair. Now it
  shows a line first, then the dots. The lines are written by a model too,
  the cheapest call the provider has, in one character, with one prompt,
  and kept in a table: a hundred are written the first time the app boots
  with a key, and a handful more every half hour after that, so the supply
  grows without anybody shipping a list.

  `one/0` is the only thing a page calls. It is a random row, or nil when
  the table is empty, and nil means the dots stand alone as they did
  before. Nothing on a page waits for a model to be able to show that it is
  waiting for a model.

  The prompt is the one Bobby wrote, verbatim, spelling and all.
  """

  import Ecto.Query

  require Logger

  alias Marginalia.{LLM, Repo}
  alias Marginalia.Mutterings.Mutter

  @prompt "You are Fyordor Dostoyevsky. You live in the modern day. You work a job at a grilled cheese sandwich factory in Menlo Park, CA. Give some words you might utter while working alone at teh sandwich counter. Keep it 240 characters or less."

  # what the table is filled to on boot, and how many a top-up adds
  @seed 100
  @batch 10

  # the prompt asks for 240 characters or less; anything longer is the
  # model explaining itself, and gets dropped
  @max_chars 240

  def prompt, do: @prompt
  def seed_size, do: @seed
  def batch_size, do: @batch

  @doc "A random line, or nil when there are none yet."
  def one do
    case Repo.one(from m in Mutter, order_by: fragment("random()"), limit: 1) do
      nil -> nil
      %Mutter{text: text} -> text
    end
  end

  # how many recently shown lines a process keeps out of its next pick
  @remember 40

  @doc """
  Up to `n` random lines, none of them shown by this process recently.
  `[]` when there are none yet.

  "Recently" lives in the calling process's dictionary. The caller is a
  LiveView, one process per open page, and what it has shown is state
  about that page; the alternative was an assign threaded through ten
  call sites in four modules to reach a query. A page that has seen most
  of the table forgets, rather than getting an empty pick.
  """
  def some(n) when is_integer(n) and n > 0 do
    seen = Process.get(:mutterings_seen, [])

    lines =
      case pick(n, seen) do
        [] when seen != [] ->
          Process.put(:mutterings_seen, [])
          pick(n, [])

        lines ->
          lines
      end

    Process.put(:mutterings_seen, Enum.take(lines ++ seen, @remember))
    lines
  end

  defp pick(n, except) do
    Repo.all(
      from m in Mutter,
        where: m.text not in ^except,
        order_by: fragment("random()"),
        limit: ^n,
        select: m.text
    )
  end

  def count, do: Repo.aggregate(Mutter, :count)

  @doc """
  Fill the table to its seed size, if it is short. `{:ok, how_many_added}`.

  Runs at every boot and is cheap when nothing is missing: one count.
  """
  #
  # The model gives fewer lines than it is asked for, fifty-seven of a
  # hundred the first time, and some of what it gives is already in the
  # table. So this asks again, up to four times in one go, and stops when
  # the table is full or a call fails.
  def seed(opts \\ []), do: seed(opts, 4, 0)

  defp seed(_opts, 0, added), do: {:ok, added}

  defp seed(opts, tries, added) do
    case @seed - count() do
      missing when missing > 0 ->
        case generate(missing, Keyword.put(opts, :source, "seed")) do
          {:ok, n} -> seed(opts, tries - 1, added + n)
          {:error, _} = err when added == 0 -> err
          {:error, _} -> {:ok, added}
        end

      _ ->
        {:ok, added}
    end
  end

  @doc "Add a batch. What the clock calls every half hour."
  def topup(opts \\ []), do: generate(opts[:count] || @batch, Keyword.put(opts, :source, "cron"))

  @doc """
  Ask for `n` lines and store what comes back, up to `n`.

  `:call` replaces the model call with a function of `n` that returns
  `{:ok, text}`, for tests and for anything that already has the words.
  """
  def generate(n, opts \\ []) when is_integer(n) and n > 0 do
    call = opts[:call] || (&ask/1)

    with {:ok, text} <- call.(n) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      source = opts[:source] || "cron"

      rows =
        text
        |> parse()
        |> Enum.take(n)
        |> Enum.map(&%{text: &1, source: source, inserted_at: now, updated_at: now})

      case rows do
        [] ->
          {:error, :nothing_usable}

        rows ->
          # a line the table already has is not an error and not a row
          {count, _} =
            Repo.insert_all(Mutter, rows, on_conflict: :nothing, conflict_target: :text)

          {:ok, count}
      end
    end
  end

  @doc """
  Lines out of a model's reply, one mutter each.

  The reply is asked for as bare lines and rarely arrives that way: numbered,
  bulleted, in quotation marks, with a "Here are ten:" on top. All of that
  is stripped. A line that ends in a colon is the model introducing the
  list, not a line from the list, and a line over the length of a sentence
  or two is the model explaining, so both go.
  """
  def parse(nil), do: []

  def parse(text) when is_binary(text) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map(&clean/1)
    |> Enum.reject(&(&1 == "" or String.ends_with?(&1, ":") or String.length(&1) > @max_chars))
    |> Enum.uniq()
  end

  defp clean(line) do
    line
    |> String.trim()
    |> String.replace(~r/^(?:[-*•]|\d+[.)])\s*/u, "")
    |> String.trim()
    |> String.replace(~r/^["“„'‘]+|["”'’]+$/u, "")
    |> String.trim()
  end

  # The cheapest call the provider has. On DeepSeek that is the same model
  # with thinking switched off, which `deepseek-chat` selects; the bare
  # model id turns reasoning on, and reasoning about grilled cheese is
  # money spent on nothing. Temperature up, because the whole point is
  # that the lines differ from each other.
  defp ask(n) do
    model = if LLM.provider_name() == :deepseek, do: "deepseek-chat", else: LLM.fast_model()

    case LLM.chat(
           model: model,
           effort: :none,
           temperature: 1.2,
           max_tokens: 40 * n + 100,
           timeout: 60_000,
           messages: [
             %{"role" => "system", "content" => @prompt},
             %{
               "role" => "user",
               "content" =>
                 "Give #{n} of them. One per line. No numbering, no quotation marks, " <>
                   "no introduction and no commentary: nothing but the words themselves."
             }
           ]
         ) do
      {:ok, %{"content" => content}} when is_binary(content) -> {:ok, content}
      {:ok, other} -> {:error, {:no_content, other}}
      {:error, reason} -> {:error, reason}
    end
  end
end
