defmodule Marginalia.Works.ReflowTest do
  @moduledoc """
  Putting the paragraphs back into text that came out of a PDF.

  The sample is the real thing: the opening of the Landor opinion exactly
  as `pdftotext` handed it over, page furniture and all.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Analysis.Anchor
  alias Marginalia.Works.Reflow

  @page """
  JUSTICE GORSUCH delivered the opinion of the Court.
  This case concerns whether the Religious Land Use and
  Institutionalized Persons Act of 2000 permits plaintiffs to
  sue nonconsenting state employees in their private capaci-
  ties for damages.
  I
  Today, Congress offers financial support to all 50 States
  and many other entities. Much of that support comes with
  strings attached. So, for example, Congress has conditioned
  receipt of federal highway funds on a State's agreement to
  maintain laws setting a minimum drinking age of 21. See
  South Dakota v. Dole, 483 U. S. 203 (1987). Likewise, Con-
  gress has conditioned federal Medicaid funds on a State's
  willingness to administer its healthcare programs con-
  sistent with various rules.
  2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND
  PUBLIC SAFETY
  In each of these contexts and many others, the penalty for
  noncompliance is straightforward: Congress may termi-
  nate funds if a recipient fails to abide by the conditions
  associated with its grants.
  """

  describe "recognising page text" do
    test "hard-wrapped text with no blank lines is page text" do
      assert Reflow.wrapped?(@page)
    end

    test "text that already has paragraphs is left alone" do
      prose =
        Enum.map_join(1..8, "\n\n", fn i ->
          "Paragraph #{i}. " <> String.duplicate("word ", 30)
        end)

      refute Reflow.wrapped?(prose)
      assert Reflow.reflow(prose) == prose
    end

    test "a couple of lines is not enough to guess from" do
      refute Reflow.wrapped?("one line\nand another")
    end
  end

  describe "reflowing" do
    setup do: %{out: Reflow.reflow(@page)}

    test "the paragraphs come back", %{out: out} do
      paras = String.split(out, "\n\n")

      assert length(paras) >= 4
      assert Enum.any?(paras, &String.starts_with?(&1, "JUSTICE GORSUCH"))
      assert Enum.any?(paras, &String.starts_with?(&1, "Today, Congress"))
      assert Enum.any?(paras, &String.starts_with?(&1, "In each of these contexts"))
    end

    test "a paragraph is one line, not eight", %{out: out} do
      [first | _] = String.split(out, "\n\n")
      refute String.contains?(first, "\n")
      assert first =~ "private capacities for damages."
    end

    test "the typesetter's hyphens are closed up", %{out: out} do
      assert out =~ "private capacities"
      assert out =~ "Congress has conditioned federal Medicaid"
      assert out =~ "programs consistent with"
      assert out =~ "may terminate funds"
      refute out =~ "capaci-"
      refute out =~ "Con-\n"
    end

    test "a hyphen the document uses elsewhere is kept" do
      page =
        "The statute permits removal only for cause, and the for-cause standard\n" <>
          "is the whole dispute. The parties agree that the ordinary for-\n" <>
          "cause rule governs here and nowhere else in the record.\n" <>
          String.duplicate("A further line of argument follows here at length.\n", 10)

      out = Reflow.reflow(page)
      assert out =~ "the ordinary for-cause rule"
      refute out =~ "forcause"
    end

    test "the running head is dropped", %{out: out} do
      refute out =~ "LANDOR v. LOUISIANA DEPT"
      refute out =~ "PUBLIC SAFETY"
    end

    test "the division numeral stands alone", %{out: out} do
      assert "I" in String.split(out, "\n\n")
    end

    test "no word is lost", %{out: out} do
      words = fn t ->
        t
        |> String.replace("-\n", "")
        |> String.split(~r/\s+/, trim: true)
        |> Enum.reject(&(&1 in ~w(2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND PUBLIC SAFETY)))
      end

      assert length(words.(out)) >= length(words.(@page)) - 12
    end
  end

  describe "the anchoring contract" do
    # Whitespace is free -- Anchor normalises it -- but de-hyphenation
    # changes characters, so a quote has to travel through the same
    # transformation as the text it is anchored to.
    test "a quote spanning a mended hyphen still verifies" do
      out = Reflow.reflow(@page)
      quote = "sue nonconsenting state employees in their private capaci-\nties for damages."

      assert {:ok, span} = Anchor.verify(Reflow.align(quote, @page), out)
      assert span =~ "private capacities for damages."
      assert String.contains?(out, span)
    end

    test "a quote with no hyphen in it verifies untouched" do
      out = Reflow.reflow(@page)
      quote = "Much of that support comes with\nstrings attached."

      assert {:ok, span} = Anchor.verify(Reflow.align(quote, @page), out)
      assert String.contains?(out, span)
    end
  end
end
