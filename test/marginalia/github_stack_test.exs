defmodule Marginalia.GitHubStackTest do
  @moduledoc """
  A stack is each pull request based on the one before it. Anything else is
  refused by name, because a silently mis-ordered import produces a method
  whose steps are in the wrong order and nothing downstream can tell.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Import.GitHub

  defp pr(number, head, base, title \\ nil) do
    %{
      "number" => number,
      "title" => title || "PR #{number}",
      "body" => "body #{number}",
      "html_url" => "https://example.invalid/pull/#{number}",
      "head" => %{"ref" => head},
      "base" => %{"ref" => base}
    }
  end

  test "the order comes from the chain, not from the listing" do
    pulls = [pr(3, "c", "b"), pr(1, "a", "main"), pr(2, "b", "a")]

    assert {:ok, items} = GitHub.order(pulls, "main")
    assert Enum.map(items, & &1.number) == [1, 2, 3]
    assert Enum.map(items, & &1.ordinal) == [1, 2, 3]
  end

  test "the numbers do not have to agree with the order" do
    # renumbered, reordered: the chain is still a: -> b: -> c:
    pulls = [pr(90, "b", "a"), pr(12, "a", "main"), pr(7, "c", "b")]

    assert {:ok, items} = GitHub.order(pulls, "main")
    assert Enum.map(items, & &1.number) == [12, 90, 7]
  end

  test "two pull requests on the default branch are two stacks, and it says so" do
    pulls = [pr(1, "a", "main"), pr(2, "b", "main")]

    assert {:error, {:many_roots, roots}} = GitHub.order(pulls, "main")
    assert Enum.sort(roots) == [1, 2]
    assert GitHub.explain({:many_roots, roots}) =~ "more than one stack"
  end

  test "a pull request off the chain is named, not dropped" do
    pulls = [pr(1, "a", "main"), pr(2, "b", "a"), pr(9, "stray", "somewhere-else")]

    assert {:error, {:off_chain, [9]}} = GitHub.order(pulls, "main")
    assert GitHub.explain({:off_chain, [9]}) =~ "#9"
  end

  test "nothing based on the default branch is no start to the chain" do
    assert {:error, {:no_root, "main"}} = GitHub.order([pr(1, "a", "zzz")], "main")
    assert GitHub.explain({:no_root, "main"}) =~ "no start"
  end

  test "an empty repository is refused rather than imported as nothing" do
    assert {:error, :no_pull_requests} = GitHub.order([], "main")
  end

  test "two pull requests from one branch is not a stack" do
    # the shape that gets through everything else: the walk terminates, the
    # count comes out right, and the order it produces is a guess
    pulls = [pr(1, "a", "main"), pr(2, "b", "a"), pr(3, "a", "b")]

    assert {:error, {:duplicate_branches, ["a"]}} = GitHub.order(pulls, "main")
    assert GitHub.explain({:duplicate_branches, ["a"]}) =~ "one pull request per branch"
  end

  test "a chain that loops terminates rather than hanging" do
    # distinct branches, but c is based on b and b on c
    pulls = [pr(1, "a", "main"), pr(2, "b", "c"), pr(3, "c", "b")]
    assert {:error, _} = GitHub.order(pulls, "main")
  end

  test "every error explains itself in words someone can act on" do
    for e <- [
          :unauthorized,
          :forbidden,
          :not_found,
          :bad_name,
          :no_pull_requests,
          {:http, 500},
          {:transport, "x"},
          {:no_root, "main"},
          {:duplicate_branches, ["a"]},
          {:off_chain, [1]},
          {:many_roots, [1, 2]}
        ] do
      assert is_binary(GitHub.explain(e))
      refute GitHub.explain(e) == ""
    end
  end
end
