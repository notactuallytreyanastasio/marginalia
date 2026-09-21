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
  end
end
