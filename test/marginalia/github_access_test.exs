defmodule Marginalia.GitHubAccessTest do
  @moduledoc """
  Reading a public repository without a credential, and being told which
  kind of "no" came back.

  Both of these were wrong in a way that only shows up against the real
  API. An empty token was still sent as `Authorization: Bearer `, which
  GitHub answers 401 — so somebody who left the box blank, as they should
  for a public repository, was told their token had been rejected. And
  every 403 was reported as a refusal, when the common one is an allowance:
  60 requests an hour unauthenticated, against three requests per pull
  request.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Import.GitHub

  describe "what a refusal is called" do
    test "a rate limit says when it comes back, not that access was denied" do
      soon = DateTime.utc_now() |> DateTime.add(600, :second) |> DateTime.to_unix()
      said = GitHub.explain({:rate_limited, to_string(soon)})

      assert said =~ "rate limiting"
      assert said =~ "UTC"
      assert said =~ ~r/in \d+m\d+s/
      refute said =~ "may lack access"
    end

    test "a reset already past reads as a wait of nothing, not a negative one" do
      gone = DateTime.utc_now() |> DateTime.add(-60, :second) |> DateTime.to_unix()
      assert GitHub.explain({:rate_limited, to_string(gone)}) =~ "in 0m0s"
    end

    test "a rate limit with no header still says something usable" do
      assert GitHub.explain({:rate_limited, nil}) =~ "few minutes"
    end

    test "a query GitHub will not run is quoted back in its own words" do
      said = GitHub.explain({:rejected, ~s("@today-30d" is not a recognized date/time format)})

      assert said =~ "would not run that search"
      assert said =~ "not a recognized date/time format"
      refute said =~ "422", "the number is what somebody was staring at before"
    end

    test "a refusal with nothing to quote still says what to look at" do
      assert GitHub.explain({:rejected, nil}) =~ "qualifiers and the dates"
    end

    test "a real refusal still names the two reasons it happens" do
      said = GitHub.explain(:forbidden)
      assert said =~ "may lack access"
      assert said =~ "60 requests an hour"
    end

    test "both mention the allowance, since that is what a bulk import hits" do
      soon = DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.to_unix()
      assert GitHub.explain({:rate_limited, to_string(soon)}) =~ "5000"
    end
  end

  describe "against the live API" do
    @describetag :network

    test "a public repository is readable with no token at all" do
      assert {:ok, candidates} =
               GitHub.list("phoenixframework", "phoenix", nil, state: "closed")

      assert length(candidates) > 0
      assert %{repo: "phoenixframework/phoenix", number: n, title: t} = hd(candidates)
      assert is_integer(n)
      assert is_binary(t)
    end

    test "an empty string is the same as no token, not a bad one" do
      assert {:ok, _} = GitHub.list("phoenixframework", "phoenix", "", state: "closed")
    end

    test "a relative date is translated before it goes over the wire" do
      # typed on the page, refused by GitHub as "not a recognized
      # date/time format" until this translated it
      assert {:ok, found} =
               GitHub.search(
                 "repo:phoenixframework/phoenix state:closed created:>@today-30d",
                 nil
               )

      assert found != []
      cutoff = Date.add(Date.utc_today(), -30)

      for c <- found do
        {:ok, made} = c.created_at |> String.slice(0, 10) |> Date.from_iso8601()
        assert Date.compare(made, cutoff) in [:gt, :eq]
      end
    end

    test "a query GitHub refuses comes back with GitHub's reason, not a number" do
      assert {:error, {:rejected, said}} =
               GitHub.search("repo:phoenixframework/phoenix created:>whenever", nil)

      assert said =~ "date"
    end
  end

  describe "the order the documents land in" do
    defp c(number, merged, created \\ nil) do
      %{
        repo: "a/b",
        number: number,
        title: "PR #{number}",
        merged_at: merged,
        created_at: created || "2025-01-01T00:00:00Z"
      }
    end

    test "oldest first, by when it landed" do
      # GitHub answers newest first, and the order these are created in is
      # the order Stacks reads them forwards in
      given = [
        c(9, "2025-08-01T00:00:00Z"),
        c(7, "2025-04-01T00:00:00Z"),
        c(8, "2025-06-01T00:00:00Z")
      ]

      assert Enum.map(GitHub.oldest_first(given), & &1.number) == [7, 8, 9]
    end

    test "merge order, not number order, when they disagree" do
      # opened in January, merged in July: early by number, late by merge,
      # and for "how did this version get out of the door" merge is the
      # order that happened
      january = c(1, "2025-07-01T00:00:00Z", "2025-01-01T00:00:00Z")
      june = c(90, "2025-06-01T00:00:00Z", "2025-06-01T00:00:00Z")

      assert Enum.map(GitHub.oldest_first([january, june]), & &1.number) == [90, 1]
    end

    test "an unmerged one sorts by when it was opened" do
      open = c(5, nil, "2025-05-01T00:00:00Z")
      merged = c(4, "2025-09-01T00:00:00Z", "2025-01-01T00:00:00Z")

      assert Enum.map(GitHub.oldest_first([merged, open]), & &1.number) == [5, 4]
    end

    test "the sort is total, so a re-listing does not shuffle" do
      same = [
        c(3, "2025-04-01T00:00:00Z"),
        c(1, "2025-04-01T00:00:00Z"),
        c(2, "2025-04-01T00:00:00Z")
      ]

      assert Enum.map(GitHub.oldest_first(same), & &1.number) == [1, 2, 3]
      assert GitHub.oldest_first(same) == GitHub.oldest_first(Enum.reverse(same))
    end
  end
end
