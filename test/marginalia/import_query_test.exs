defmodule Marginalia.ImportQueryTest do
  @moduledoc """
  The query box on the choosing step, which runs over rows already fetched.

  Two things here are worth more than the rest. An unknown qualifier has to
  be an error — a typo that silently means nothing lets somebody import a
  hundred and forty-seven pull requests believing they filtered to nine. And
  a missing date has to fail a comparison rather than sort before everything,
  or `merged:>2020-01-01` quietly sweeps in every pull request that was never
  merged at all.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Import.Query

  defp pr(attrs) do
    Map.merge(
      %{
        repo: "phoenixframework/phoenix",
        number: 100,
        title: "A change",
        state: "merged",
        draft: false,
        base: "main",
        head: "topic",
        created_at: "2025-01-01T00:00:00Z",
        updated_at: "2025-02-01T00:00:00Z",
        merged_at: "2025-02-01T00:00:00Z"
      },
      attrs
    )
  end

  defp keep(rows, q) do
    assert {:ok, kept} = Query.filter(rows, q)
    Enum.map(kept, & &1.number)
  end

  describe "the shape people actually type" do
    setup do
      today = Date.utc_today()
      recent = today |> Date.add(-3) |> Date.to_iso8601()
      old = today |> Date.add(-200) |> Date.to_iso8601()

      %{
        rows: [
          pr(%{number: 1, state: "closed", created_at: recent, title: "Fix the parser"}),
          pr(%{number: 2, state: "open", created_at: recent, title: "Bump eslint"}),
          pr(%{number: 3, state: "closed", created_at: old, title: "Old and closed"}),
          pr(%{number: 4, state: "merged", created_at: recent, title: "Merged lately"})
        ]
      }
    end

    test "is:pr state:closed created:>@today-30d", %{rows: rows} do
      assert keep(rows, "is:pr state:closed created:>@today-30d") == [1]
    end

    test "a bare word is the title, and a minus takes it away", %{rows: rows} do
      assert keep(rows, "fix") == [1]
      assert keep(rows, "-bump") == [1, 3, 4]
    end

    test "terms are joined with and", %{rows: rows} do
      assert keep(rows, "state:closed created:>@today-30d -fix") == []
    end

    test "an empty query keeps everything", %{rows: rows} do
      assert keep(rows, "") == [1, 2, 3, 4]
      assert keep(rows, "   ") == [1, 2, 3, 4]
    end
  end

  describe "an unknown qualifier" do
    test "is refused by name rather than ignored" do
      assert {:error, why} = Query.filter([pr(%{})], "stat:closed")
      assert why =~ "stat"
      assert why =~ "do not know"
    end

    test "the message lists what it does know" do
      {:error, why} = Query.filter([], "author:me")
      assert why =~ "created"
      assert why =~ "merged"
    end

    test "a bad value for a known qualifier says what the values are" do
      {:error, why} = Query.filter([], "state:draft")
      assert why =~ "open, closed or merged"
    end

    test "is:issue is refused, because there are none here" do
      assert {:error, why} = Query.filter([], "is:issue")
      assert why =~ "only pull requests"
    end

    test "is:pr is accepted and does nothing" do
      rows = [pr(%{number: 7})]
      assert keep(rows, "is:pr") == [7]
    end
  end

  describe "dates" do
    test "@today and its offsets" do
      today = Date.utc_today()

      assert Query.date("@today") == {:ok, today}
      assert Query.date("@today-30d") == {:ok, Date.add(today, -30)}
      assert Query.date("@today-2w") == {:ok, Date.add(today, -14)}
      assert Query.date("@today+7d") == {:ok, Date.add(today, 7)}
    end

    test "a month offset is calendar months, clamped to a real day" do
      assert Query.date("@today-1m", ~D[2025-03-31]) == {:ok, ~D[2025-02-28]}
      assert Query.date("@today-6m", ~D[2025-08-05]) == {:ok, ~D[2025-02-05]}
      assert Query.date("@today-1y", ~D[2025-08-05]) == {:ok, ~D[2024-08-05]}
    end

    test "an absolute date, and something that is not one" do
      assert Query.date("2025-08-05") == {:ok, ~D[2025-08-05]}
      assert Query.date("last tuesday") == :error
      assert Query.date("@today-3fortnights") == :error
    end

    test "a date that will not parse is named in the error" do
      assert {:error, why} = Query.filter([], "created:>yesterday")
      assert why =~ "yesterday"
      assert why =~ "@today-30d"
    end

    test "ranges, open at either end" do
      rows = [
        pr(%{number: 1, merged_at: "2025-03-01T00:00:00Z"}),
        pr(%{number: 2, merged_at: "2025-06-01T00:00:00Z"}),
        pr(%{number: 3, merged_at: "2025-09-01T00:00:00Z"})
      ]

      assert keep(rows, "merged:2025-04-01..2025-08-01") == [2]
      assert keep(rows, "merged:2025-04-01..*") == [2, 3]
      assert keep(rows, "merged:*..2025-04-01") == [1]
      assert keep(rows, "merged:2025-06-01") == [2]
    end

    test "a pull request that was never merged fails every merged comparison" do
      rows = [
        pr(%{number: 1, state: "open", merged_at: nil}),
        pr(%{number: 2, merged_at: "2025-06-01T00:00:00Z"})
      ]

      # the trap: nil is "not a date", not "before everything"
      assert keep(rows, "merged:>2020-01-01") == [2]
      assert keep(rows, "merged:<2030-01-01") == [2]
      assert keep(rows, "-merged:>2020-01-01") == [1]
    end
  end

  describe "the other qualifiers" do
    test "state and is agree with each other" do
      rows = [pr(%{number: 1, state: "open"}), pr(%{number: 2, state: "merged"})]

      assert keep(rows, "is:open") == [1]
      assert keep(rows, "state:open") == [1]
      assert keep(rows, "is:merged") == [2]
    end

    test "draft, both ways round" do
      rows = [pr(%{number: 1, draft: true}), pr(%{number: 2, draft: false})]

      assert keep(rows, "is:draft") == [1]
      assert keep(rows, "draft:true") == [1]
      assert keep(rows, "draft:false") == [2]
      assert keep(rows, "-is:draft") == [2]
    end

    test "repo, base and head are exact and case insensitive" do
      rows = [
        pr(%{number: 1, repo: "phoenixframework/phoenix", base: "main"}),
        pr(%{number: 2, repo: "elixir-lang/elixir", base: "v1.19"})
      ]

      assert keep(rows, "repo:PhoenixFramework/Phoenix") == [1]
      assert keep(rows, "base:v1.19") == [2]
      assert keep(rows, "repo:phoenix") == [], "a partial repo is not a repo"
    end

    test "number compares as a number, not as a string" do
      rows = [pr(%{number: 9}), pr(%{number: 100}), pr(%{number: 1000})]

      assert keep(rows, "number:>90") == [100, 1000]
      assert keep(rows, "number:9..100") == [9, 100]
      assert keep(rows, "number:1000") == [1000]
    end
  end

  test "a quoted phrase is one term" do
    rows = [
      pr(%{number: 1, title: "add a precommit alias"}),
      # both words, not the phrase
      pr(%{number: 2, title: "alias the precommit hook"}),
      pr(%{number: 3, title: "add a guide"})
    ]

    assert keep(rows, ~s("precommit alias")) == [1], "quoted, they have to be adjacent"
    assert keep(rows, "precommit alias") == [1, 2], "unquoted, both words anywhere"
  end

  describe "expanding @today for GitHub" do
    test "the query from the report, which GitHub answers 422" do
      today = Date.utc_today()
      want = today |> Date.add(-30) |> Date.to_iso8601()

      assert Query.expand("repo:phoenixframework/phoenix state:closed created:>@today-30d") ==
               "repo:phoenixframework/phoenix state:closed created:>#{want}"
    end

    test "every unit, and more than one in a query" do
      today = Date.utc_today()
      d = fn n -> today |> Date.add(n) |> Date.to_iso8601() end

      assert Query.expand("created:>@today-7d merged:<@today") ==
               "created:>#{d.(-7)} merged:<#{d.(0)}"

      assert Query.expand("@today-2w") == d.(-14)
      assert Query.expand("@today+1d") == d.(1)
    end

    test "a range with both ends relative" do
      today = Date.utc_today()
      from = today |> Date.add(-60) |> Date.to_iso8601()
      to = today |> Date.add(-30) |> Date.to_iso8601()

      assert Query.expand("merged:@today-60d..@today-30d") == "merged:#{from}..#{to}"
    end

    test "everything else is left exactly as it was" do
      for q <- [
            "repo:phoenixframework/phoenix is:pr",
            "created:>2025-08-05",
            "label:\"needs review\" -Bump",
            ""
          ] do
        assert Query.expand(q) == q
      end
    end

    test "something that looks like @today but is not is left alone" do
      # not a unit this understands; better to let GitHub say so than to
      # mangle it into a date nobody asked for
      assert Query.expand("@today-3fortnights") =~ "@today-3fortnights"
      assert Query.expand("@todays") =~ "@today"
    end
  end
end
