defmodule Marginalia.Import.Query do
  @moduledoc """
  A GitHub-shaped query, run over pull requests already fetched.

  The search box on the finding step is GitHub's, and it decides what is
  *fetched*. This is the box on the choosing step, and it decides what is
  *kept* — the same language, over the rows already in hand. Nothing here
  touches the network, which is the whole reason it is a second box: once a
  hundred and forty-seven rows are on the page, narrowing them should be
  instant and should not spend another request, and it should not have to be
  right first time.

      is:pr state:closed created:>@today-30d
      repo:phoenixframework/phoenix base:main -Bump
      merged:2025-04-01..2025-08-05 draft:false

  ## What it knows

  Only the fields a listing actually carries. `state:`, `is:`, `draft:`,
  `repo:`, `base:`, `head:`, `number:`, and the three dates `created:`,
  `updated:` and `merged:`. A bare word is a substring of the title, and a
  leading `-` negates any of it. Terms are joined with AND, which is what
  GitHub does and what people expect.

  ## An unknown qualifier is an error, not a no-op

  `stat:closed` is a typo for `state:closed`, and the tempting thing is to
  ignore what is not understood. Then the query silently means nothing, every
  row matches, and somebody imports a hundred and forty-seven pull requests
  believing they filtered to nine. So anything unrecognised is refused by
  name, and the page says which word it was.

  `is:pr` is the exception: it is accepted and does nothing, because
  everything here is already a pull request and people type it out of habit.

  ## Dates

  `YYYY-MM-DD`, or `@today` with an optional offset — `@today-30d`,
  `@today-2w`, `@today-6m`, `@today-1y`. Comparisons are `>`, `>=`, `<`,
  `<=`, an exact day, or a range `A..B` with `*` for an open end.

  `@today` is not GitHub's syntax. GitHub has no relative dates at all, which
  is why every saved search anybody writes goes stale the week after they
  write it.
  """

  @qualifiers ~w(is state draft repo base head number created updated merged)

  @doc """
  Keep the candidates matching `text`.

  `{:ok, kept}`, or `{:error, message}` for something the reader can fix —
  an unknown qualifier, a date that is not a date. An empty query keeps
  everything.
  """
  def filter(candidates, text) do
    case parse(text) do
      {:ok, []} -> {:ok, candidates}
      {:ok, terms} -> {:ok, Enum.filter(candidates, fn c -> Enum.all?(terms, &hit?(&1, c)) end)}
      {:error, why} -> {:error, why}
    end
  end

  @doc """
  The query as a list of terms, or the first thing wrong with it.

  Public because it is the part worth testing: the filtering itself is one
  `Enum.all?`, and everything that can be wrong is wrong here.
  """
  def parse(text) do
    text
    |> to_string()
    |> tokens()
    |> Enum.reduce_while({:ok, []}, fn token, {:ok, acc} ->
      case term(token) do
        {:ok, nil} -> {:cont, {:ok, acc}}
        {:ok, term} -> {:cont, {:ok, acc ++ [term]}}
        {:error, why} -> {:halt, {:error, why}}
      end
    end)
  end

  # Whitespace, except inside double quotes: a title fragment with a space in
  # it is the ordinary reason to reach for quoting.
  defp tokens(text) do
    ~r/"[^"]*"|\S+/
    |> Regex.scan(text)
    |> Enum.map(fn [t] -> t end)
    |> Enum.reject(&(&1 in ["", "\"\""]))
  end

  defp term("-" <> rest) do
    case term(rest) do
      {:ok, nil} -> {:ok, nil}
      {:ok, t} -> {:ok, {:not, t}}
      other -> other
    end
  end

  defp term(token) do
    case String.split(token, ":", parts: 2) do
      [word] -> {:ok, {:text, unquote_term(word)}}
      ["", _] -> {:ok, {:text, unquote_term(token)}}
      [key, value] -> qualifier(String.downcase(key), unquote_term(value))
    end
  end

  defp unquote_term(v), do: v |> String.trim("\"") |> String.trim()

  # --- the qualifiers -------------------------------------------------------

  defp qualifier("is", "pr"), do: {:ok, nil}
  defp qualifier("is", "issue"), do: {:error, "`is:issue` — there are only pull requests here."}
  defp qualifier("is", "draft"), do: {:ok, {:draft, true}}
  defp qualifier("is", v) when v in ~w(open closed merged), do: {:ok, {:state, v}}

  defp qualifier("is", v),
    do: {:error, "`is:#{v}` — I know is:pr, is:draft, is:open, is:closed and is:merged."}

  defp qualifier("state", v) when v in ~w(open closed merged), do: {:ok, {:state, v}}

  defp qualifier("state", v),
    do: {:error, "`state:#{v}` — a pull request here is open, closed or merged."}

  defp qualifier("draft", v) when v in ~w(true yes), do: {:ok, {:draft, true}}
  defp qualifier("draft", v) when v in ~w(false no), do: {:ok, {:draft, false}}
  defp qualifier("draft", v), do: {:error, "`draft:#{v}` — true or false."}

  defp qualifier("repo", v), do: {:ok, {:field, :repo, String.downcase(v)}}
  defp qualifier("base", v), do: {:ok, {:field, :base, String.downcase(v)}}
  defp qualifier("head", v), do: {:ok, {:field, :head, String.downcase(v)}}

  defp qualifier("number", v) do
    case compare(v, &number/1) do
      {:ok, cmp} -> {:ok, {:number, cmp}}
      {:error, _} -> {:error, "`number:#{v}` — a number, or >100, <100, 10..20."}
    end
  end

  defp qualifier(key, v) when key in ~w(created updated merged) do
    field = String.to_existing_atom(key <> "_at")

    case compare(v, &date/1) do
      {:ok, cmp} ->
        {:ok, {:date, field, cmp}}

      {:error, bad} ->
        {:error,
         "`#{key}:#{v}` — #{bad} is not a date. Write 2025-08-05, or @today, " <>
           "or @today-30d, and compare with > < >= <= or a .. range."}
    end
  end

  defp qualifier(key, v) do
    {:error,
     "`#{key}:#{v}` — I do not know the qualifier `#{key}`. " <>
       "I know #{Enum.join(@qualifiers, ", ")}, and a bare word matches the title."}
  end

  # --- comparisons ----------------------------------------------------------

  defp compare(value, cast) do
    case value do
      ">=" <> v -> one(v, cast, &{:gte, &1})
      "<=" <> v -> one(v, cast, &{:lte, &1})
      ">" <> v -> one(v, cast, &{:gt, &1})
      "<" <> v -> one(v, cast, &{:lt, &1})
      _ -> range_or_exact(value, cast)
    end
  end

  defp range_or_exact(value, cast) do
    case String.split(value, "..", parts: 2) do
      [from, "*"] -> one(from, cast, &{:gte, &1})
      ["*", to] -> one(to, cast, &{:lte, &1})
      [from, to] -> both(from, to, cast)
      [exact] -> one(exact, cast, &{:eq, &1})
    end
  end

  defp one(raw, cast, wrap) do
    case cast.(raw) do
      {:ok, v} -> {:ok, wrap.(v)}
      :error -> {:error, raw}
    end
  end

  defp both(from, to, cast) do
    with {:ok, a} <- as(cast, from),
         {:ok, b} <- as(cast, to) do
      {:ok, {:between, a, b}}
    end
  end

  defp as(cast, raw) do
    case cast.(raw) do
      {:ok, v} -> {:ok, v}
      :error -> {:error, raw}
    end
  end

  defp number(raw) do
    case Integer.parse(String.trim(raw)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  @doc """
  A date, absolute or relative to today.

  Public because `@today-30d` is the part somebody will want to check
  without opening a browser.
  """
  def date(raw), do: date(String.trim(raw), Date.utc_today())

  def date("@today", today), do: {:ok, today}

  def date("@today" <> offset, today) do
    case Regex.run(~r/^([+-])(\d+)([dwmy])$/, offset) do
      [_, sign, n, unit] ->
        n = String.to_integer(n) * if(sign == "-", do: -1, else: 1)

        {:ok,
         case unit do
           "d" -> Date.add(today, n)
           "w" -> Date.add(today, n * 7)
           "m" -> shift_months(today, n)
           "y" -> shift_months(today, n * 12)
         end}

      _ ->
        :error
    end
  end

  def date(raw, _today) do
    case Date.from_iso8601(raw) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> :error
    end
  end

  # Calendar months, clamped: "@today-1m" on the 31st of March is the 28th of
  # February, not an error and not the 3rd of March.
  defp shift_months(date, n) do
    months = date.year * 12 + (date.month - 1) + n
    year = div(months, 12)
    month = rem(months, 12) + 1
    Date.new!(year, month, min(date.day, :calendar.last_day_of_the_month(year, month)))
  end

  # --- matching -------------------------------------------------------------

  defp hit?({:not, term}, c), do: not hit?(term, c)

  defp hit?({:text, word}, c),
    do: String.contains?(String.downcase(c.title || ""), String.downcase(word))

  defp hit?({:state, want}, c), do: (c.state || "open") == want
  defp hit?({:draft, want}, c), do: (c.draft == true) == want

  defp hit?({:field, key, want}, c),
    do: String.downcase(to_string(Map.get(c, key) || "")) == want

  defp hit?({:number, cmp}, c), do: compare?(cmp, c.number)

  defp hit?({:date, field, cmp}, c) do
    case day(Map.get(c, field)) do
      nil -> false
      day -> compare?(cmp, day)
    end
  end

  # An unmerged pull request has no merged_at, and `merged:>x` should not
  # match it. `nil` is not "before everything", it is "not a date".
  defp day(nil), do: nil
  defp day(%Date{} = d), do: d

  defp day(iso) when is_binary(iso) do
    case iso |> String.slice(0, 10) |> Date.from_iso8601() do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp day(_), do: nil

  defp compare?(_cmp, nil), do: false
  defp compare?({:eq, v}, x), do: cmp(x, v) == :eq
  defp compare?({:gt, v}, x), do: cmp(x, v) == :gt
  defp compare?({:lt, v}, x), do: cmp(x, v) == :lt
  defp compare?({:gte, v}, x), do: cmp(x, v) in [:gt, :eq]
  defp compare?({:lte, v}, x), do: cmp(x, v) in [:lt, :eq]
  defp compare?({:between, a, b}, x), do: cmp(x, a) in [:gt, :eq] and cmp(x, b) in [:lt, :eq]

  defp cmp(%Date{} = a, %Date{} = b), do: Date.compare(a, b)
  defp cmp(a, b) when a > b, do: :gt
  defp cmp(a, b) when a < b, do: :lt
  defp cmp(_, _), do: :eq
end
