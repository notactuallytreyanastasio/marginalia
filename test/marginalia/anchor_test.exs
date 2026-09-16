defmodule Marginalia.Analysis.AnchorTest do
  use ExUnit.Case, async: true
  alias Marginalia.Analysis.Anchor

  @source """
  She had been standing at the window for an hour before anyone noticed, and by then the
  light had gone completely. "You can't keep doing this," her brother said, from the doorway.
  He did not come in.
  """

  test "an exact quote verifies" do
    assert {:ok, q} = Anchor.verify("standing at the window for an hour", @source)
    assert q == "standing at the window for an hour"
  end

  test "curly quotes and dashes are normalised away" do
    assert {:ok, _} = Anchor.verify("“You can’t keep doing this,” her brother said", @source)
  end

  test "a fabricated quote is rejected" do
    assert :error = Anchor.verify("She turned and left without saying anything at all", @source)
  end

  test "a too-short quote is rejected rather than trivially matched" do
    assert :error = Anchor.verify("the", @source)
  end

  describe "paraphrase is not verbatim" do
    @para "She kept them in the freezer, which she never explained to anyone, and by then it hardly mattered."

    test "the same words in a different order are rejected" do
      # the old matcher scored set membership over a sliding window, which is
      # order-blind, so a rearranged sentence anchored
      assert :error = Anchor.verify("the freezer she kept them in which she never explained", @para)
    end

    test "a deleted negation is rejected" do
      # the worst case: this used to anchor AND return a span still containing
      # "never", storing the opposite of what the model claimed
      assert :error = Anchor.verify("which she explained to anyone, and by then it hardly mattered", @para)
    end

    test "a dropped word is rejected" do
      assert :error = Anchor.verify("had been standing at window for an hour before anyone noticed", @source)
    end

    test "a substituted word is rejected" do
      assert :error = Anchor.verify("standing at the doorway for an hour", @source)
    end

    test "but typography and line wrapping are still absorbed" do
      wrapped = "She kept them in the\nfreezer, which she never\nexplained to anyone."
      assert {:ok, span} = Anchor.verify("She kept them in the freezer, which she never explained", wrapped)
      assert String.contains?(wrapped, span)
    end
  end

  test "filter keeps anchored nodes and counts the discards" do
    nodes = [
      %{title: "real", quote: "He did not come in."},
      %{title: "invented", quote: "She screamed at the top of her lungs and ran."},
      %{title: "also real", quote: "by then the light had gone completely"}
    ]

    {kept, dropped} = Anchor.filter(nodes, @source)

    assert dropped == 1
    assert Enum.map(kept, & &1.title) == ["real", "also real"]
  end

  test "a node with no quote at all is discarded" do
    assert {[], 1} = Anchor.filter([%{title: "unsourced", quote: nil}], @source)
  end
end
