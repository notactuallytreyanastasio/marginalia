defmodule Marginalia.RewriteTest do
  @moduledoc """
  The one place in the product that writes prose for the manuscript. The
  constraints on it are what stop that swallowing the rest.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.{Rewrite, Works}
  import Marginalia.AccountsFixtures

  setup do
    user = user_fixture()

    body =
      "# A draft\n\nThe kettle went cold on the counter, and nobody moved to fill it again.\n\n" <>
        String.duplicate("word ", 300)

    {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
    %{work: work}
  end

  describe "the span has to be real" do
    test "a selection that is not in the draft gets nothing", %{work: work} do
      assert {:error, :not_in_draft} = Rewrite.propose(work, "a sentence nobody wrote")
    end

    test "a redraft is refused, and says how long it was", %{work: work} do
      long = String.duplicate("word ", 900)
      assert {:error, {:span_too_long, words, max}} = Rewrite.propose(work, long)
      assert words > max
      assert max == 750
    end

    test "a long passage is not a redraft any more", %{work: work} do
      # 400 words used to be refused outright. A composed movement runs about
      # 1,700, and somebody reworking one argument of it selects this much.
      sel = String.duplicate("a sentence that is not in this draft. ", 60)

      assert {:error, :not_in_draft} = Rewrite.propose(work, sel),
             "it must get past the length check and go looking for the span"
    end

    test "the answer budget grows with the span, or the reply comes back truncated" do
      short = String.duplicate("word ", 40)
      long = String.duplicate("word ", 750)

      assert Rewrite.answer_budget(short) == 3_000, "a floor for short spans"

      # three candidates at ~1.4 tokens a word, and the two labels each
      assert Rewrite.answer_budget(long) >= 750 * 3 * 1.4
    end

    test "several paragraphs get past the length check", %{work: work} do
      # 80 words: not a length complaint, it goes on to look for the span
      sel = String.duplicate("a sentence that is not in this draft. ", 10)
      assert {:error, :not_in_draft} = Rewrite.propose(work, sel)
    end
  end

  describe "the tool" do
    test "asks for the move and the cost, not just the words" do
      props = Rewrite.tool()["function"]["parameters"]["properties"]
      item = props["rewrites"]["items"]

      assert Enum.sort(item["required"]) == ["cost", "move", "text"]
      assert props["reading"], "the writer should see what it thought it was changing"
    end
  end

  describe "the word diff" do
    test "both sides reconstruct exactly" do
      a = "The kettle went cold on the counter, and nobody moved to fill it again."
      b = "The kettle went cold, and nobody moved."
      d = Rewrite.diff(a, b)

      assert d |> Enum.reject(&(elem(&1, 0) == :ins)) |> Enum.map_join(&elem(&1, 1)) == a
      assert d |> Enum.reject(&(elem(&1, 0) == :del)) |> Enum.map_join(&elem(&1, 1)) == b
    end

    test "identical spans are all one piece" do
      assert [{:same, "a b c"}] = Rewrite.diff("a b c", "a b c")
    end

    test "it finds the shared middle rather than replacing everything" do
      d = Rewrite.diff("the cat sat on the mat", "the dog sat on the mat")
      assert Enum.any?(d, fn {k, t} -> k == :same and String.contains?(t, "sat on the mat") end)
      assert Enum.any?(d, fn {k, t} -> k == :del and String.contains?(t, "cat") end)
      assert Enum.any?(d, fn {k, t} -> k == :ins and String.contains?(t, "dog") end)
    end

    test "an empty original is all insertion" do
      assert [{:ins, "new text"}] = Rewrite.diff("", "new text")
    end
  end
end
