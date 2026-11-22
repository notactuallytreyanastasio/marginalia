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
      long = String.duplicate("word ", 3_000)
      assert {:error, {:span_too_long, words, max}} = Rewrite.propose(work, long)
      assert words > max
      assert max == 2_500
    end

    test "a long passage is not a redraft any more", %{work: work} do
      # 400 words used to be refused outright. At a median paragraph of 248
      # words that is barely a paragraph and a half.
      sel = String.duplicate("a sentence that is not in this draft. ", 60)

      assert {:error, :not_in_draft} = Rewrite.propose(work, sel),
             "it must get past the length check and go looking for the span"
    end

    test "the largest request stays inside what the provider accepts" do
      # deepseek-flash was probed at 27_000, 41_500 and 65_536: all 200.
      # LLM adds reasoning headroom on top of the answer budget, so this is
      # what actually goes out for the biggest span the check allows.
      biggest = String.duplicate("word ", 2_500)
      total = Rewrite.answer_budget(biggest) + Marginalia.LLM.reasoning_headroom(:deepseek)

      assert total <= 65_536,
             "a span at the ceiling must not ask the provider for more than it takes"
    end

    test "the answer budget grows with the span, or the reply comes back truncated" do
      short = String.duplicate("word ", 40)
      long = String.duplicate("word ", 2_500)

      assert Rewrite.answer_budget(short) == 3_000, "a floor for short spans"

      # three candidates at ~1.4 tokens a word, and the two labels each
      assert Rewrite.answer_budget(long) >= 2_500 * 3 * 1.4
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

    test "each side's whitespace, newlines included, comes back with its words" do
      a = "One sentence.\nAnother  sentence.\nA third."
      b = "One sentence.\nA different sentence.\nA third."
      d = Rewrite.diff(a, b)

      assert d |> Enum.reject(&(elem(&1, 0) == :ins)) |> Enum.map_join(&elem(&1, 1)) == a
      assert d |> Enum.reject(&(elem(&1, 0) == :del)) |> Enum.map_join(&elem(&1, 1)) == b
      assert Enum.any?(d, fn {k, t} -> k == :same and t =~ "A third." end)
    end

    test "a shared word that ends one side does not swallow the next word on the other" do
      a = "the cheese knows and waits"
      b = "nobody knows"
      d = Rewrite.diff(a, b)
      old_side = d |> Enum.reject(&(elem(&1, 0) == :ins)) |> Enum.map_join(&elem(&1, 1))
      assert String.split(old_side) == String.split(a)

      assert d
             |> Enum.reject(&(elem(&1, 0) == :del))
             |> Enum.map_join(&elem(&1, 1))
             |> String.split() == String.split(b)
    end

    test "a word is the same word whatever whitespace followed it" do
      d = Rewrite.diff("a b\nc", "a b c")
      assert Enum.all?(d, &match?({:same, _}, &1))
    end

    test "two whole sections with nothing in common are one deletion and one insertion, at once" do
      a = Enum.map_join(1..2000, " ", &"before#{&1}")
      b = Enum.map_join(1..2000, " ", &"after#{&1}")
      {micros, d} = :timer.tc(fn -> Rewrite.diff(a, b) end)

      assert micros < 100_000
      assert [{:del, ^a}, {:ins, ^b}] = d
    end

    test "two whole sections that share their vocabulary get a real diff, quickly" do
      # forty words of shared vocabulary, used a lot, among a few hundred that
      # differ: the shape of a section and its rewrite, not of two strangers
      common = Enum.map(1..800, &"word#{rem(&1, 40)}")
      a = Enum.map_join(Enum.shuffle(common ++ Enum.map(1..300, &"only#{&1}")), " ", & &1)
      b = Enum.map_join(Enum.shuffle(common ++ Enum.map(1..300, &"other#{&1}")), " ", & &1)
      {micros, d} = :timer.tc(fn -> Rewrite.diff(a, b) end)

      assert micros < 1_500_000
      assert Enum.any?(d, &match?({:same, _}, &1))

      # word for word: a word the two sides share carries the right side's
      # whitespace, so the last word of one can gain a space from the other
      words = fn parts -> parts |> Enum.map_join(&elem(&1, 1)) |> String.split() end
      assert words.(Enum.reject(d, &(elem(&1, 0) == :ins))) == String.split(a)
      assert words.(Enum.reject(d, &(elem(&1, 0) == :del))) == String.split(b)
    end

    test "a section edited in one place is mostly the same, and fast" do
      a = Enum.map_join(1..2000, " ", &"word#{&1}")
      b = String.replace(a, "word1000 ", "word1000 inserted ")
      {micros, d} = :timer.tc(fn -> Rewrite.diff(a, b) end)

      assert micros < 200_000
      assert [{:same, _}, {:ins, "inserted "}, {:same, _}] = d
    end
  end

  describe "the writer's optional steer" do
    test "no steer adds nothing to the prompt" do
      assert Rewrite.steer_block(nil) == ""
      assert Rewrite.steer_block("") == ""

      assert Rewrite.steer_block("   ") == "",
             "whitespace is not an instruction"
    end

    test "what they typed goes in, in their words" do
      block = Rewrite.steer_block("lead with the finding, drop the hedging")

      assert block =~ "lead with the finding, drop the hedging"
      assert block =~ "WHAT THE WRITER ASKED FOR"
    end

    test "every candidate must obey it, but they still have to differ" do
      block = Rewrite.steer_block("make it shorter")

      assert block =~ "Every candidate must do this"

      assert block =~ "differ",
             "three candidates that all obey identically is one suggestion printed three times"
    end

    test "a brief is cut to a note" do
      long = String.duplicate("please do the thing. ", 200)
      block = Rewrite.steer_block(long)

      assert String.length(block) < Rewrite.max_steer_chars() + 300
      assert Rewrite.max_steer_chars() == 400
    end
  end

  describe "what the panel says it is replacing" do
    test "a short selection is still one line" do
      assert Rewrite.span_label("a handful of words here") == "Rewrites of one line"
    end

    test "four paragraphs are not one line" do
      four = String.duplicate("word ", 1_050)
      assert Rewrite.span_label(four) == "Rewrites of 1050 words"
    end

    test "nothing selected claims nothing" do
      assert Rewrite.span_label(nil) == "Rewrites"
      assert Rewrite.span_label("") == "Rewrites"
    end

    test "a short span needs no extent line — it is all on screen" do
      assert Rewrite.span_extent("a short selection") == nil
      assert Rewrite.span_extent(nil) == nil
    end

    test "a long span shows its head and its tail, because the rest runs off below" do
      span =
        "The beginning of the selection. " <> String.duplicate("middle ", 200) <> "the very end."

      extent = Rewrite.span_extent(span)

      assert extent =~ "The beginning of the selection"
      assert extent =~ "the very end."
      assert extent =~ "…"
      assert String.length(extent) < 200, "it is a label, not the span itself"
    end

    test "newlines in a multi-paragraph selection are flattened" do
      extent =
        Rewrite.span_extent(
          "First para.\n\n" <> String.duplicate("word ", 60) <> "\n\nLast para."
        )

      refute extent =~ "\n"
      assert extent =~ "First para."
    end
  end

  describe "putting a candidate back" do
    test "it replaces the span inside the paragraph that holds it" do
      block = "First sentence. The span to replace. Last sentence."

      assert {:ok, out} = Rewrite.place(block, "The span to replace.", "A better span.")
      assert out == "First sentence. A better span. Last sentence."
    end

    test "only the first occurrence, so a repeated phrase is not rewritten everywhere" do
      block = "same. same. same."
      assert {:ok, out} = Rewrite.place(block, "same.", "CHANGED.")
      assert out == "CHANGED. same. same."
    end

    test "a paragraph that does not hold the span is refused, not overwritten" do
      block = "BRAVO the second paragraph, which has nothing to do with it."

      assert Rewrite.place(block, "ALPHA the first paragraph.", "A rewrite of alpha.") ==
               :not_here
    end

    test "the refusal is the whole point: it used to replace the paragraph" do
      block = "A paragraph worth keeping."

      # the old behaviour returned the candidate here, so one click destroyed
      # a paragraph the writer had not selected
      refute match?(
               {:ok, "Some rewrite of other text."},
               Rewrite.place(block, "not in here", "Some rewrite of other text.")
             )
    end
  end

  describe "which paragraphs a span covers" do
    setup %{work: work} do
      %{section: hd(Works.list_sections(work.id))}
    end

    test "a span inside one paragraph covers only it", %{section: section} do
      para = section.body |> Marginalia.Reading.split() |> Enum.at(1)
      bit = String.slice(para, 10, 40)

      assert [ref] = Rewrite.covered_refs(section, bit)
      assert ref == "s#{section.ordinal}p1"
    end

    test "a span across three paragraphs covers all three", %{section: section} do
      [a, b, c | _] = Marginalia.Reading.split(section.body)
      span = a <> "\n\n" <> b <> "\n\n" <> c

      refs = Rewrite.covered_refs(section, span)

      assert length(refs) == 3
      assert refs == ["s#{section.ordinal}p0", "s#{section.ordinal}p1", "s#{section.ordinal}p2"]
    end

    test "a span starting mid-paragraph still covers that paragraph", %{section: section} do
      [a, b | _] = Marginalia.Reading.split(section.body)
      span = String.slice(a, -60, 60) <> "\n\n" <> b

      refs = Rewrite.covered_refs(section, span)

      assert "s#{section.ordinal}p0" in refs,
             "the paragraph does not contain the span, but the span covers it"

      assert "s#{section.ordinal}p1" in refs
    end

    test "a span that is not in the section covers nothing", %{section: section} do
      assert Rewrite.covered_refs(section, "a sentence nobody wrote") == []
    end

    test "the refs are the ones the page builds", %{work: work, section: section} do
      page_refs =
        Marginalia.Reading.page(work)
        |> Enum.flat_map(& &1.blocks)
        |> Enum.map(& &1.ref)

      [a, b | _] = Marginalia.Reading.split(section.body)

      for ref <- Rewrite.covered_refs(section, a <> "\n\n" <> b) do
        assert ref in page_refs, "a ref the page never renders dims nothing"
      end
    end
  end
end
