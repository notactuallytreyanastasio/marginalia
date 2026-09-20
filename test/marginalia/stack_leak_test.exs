defmodule Marginalia.StackLeakTest do
  @moduledoc """
  The model leaking its own markup into the answer.

  From the composed telling of a 111-step stack: one part of eleven wrote
  12,668 good characters, then emitted a tool-call preamble and the literal
  word "placeholder", and stopped. It validated clean, was stored, and went
  out on the public page — where it read as a code block somebody had failed
  to format.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Stacks

  # The real thing, fullwidth pipes and all (U+FF5C).
  @leak "<｜｜DSML｜｜ calls>\n" <>
          "<｜｜DSML｜｜ invoke name=\"write_part\">\n" <>
          "<｜｜DSML｜｜ parameter name=\"prose\" string=\"true\">placeholder"

  describe "scrub/2" do
    test "ordinary prose is left exactly alone" do
      text = "The backend declares Blimp's syntax in one out-grammar file."
      assert Stacks.scrub(text, "part") == {text, nil}
    end

    test "prose that mentions angle brackets or pipes is not a false positive" do
      text = "A generic `List<Int>` and a shell pipe `a | b` are both ordinary prose."
      assert {^text, nil} = Stacks.scrub(text, "part")
    end

    test "the good prose is kept and the leak is cut" do
      {clean, reason} = Stacks.scrub("Real prose here.\n\n" <> @leak, "part \"Five\"")

      assert clean == "Real prose here."
      refute clean =~ "DSML"
      refute clean =~ "placeholder"
      assert reason =~ "leaked its own tool-call markup"
      assert reason =~ "part \"Five\""
    end

    test "twelve thousand good characters are not thrown away over a corrupt tail" do
      long = String.duplicate("real sentence. ", 800)
      {clean, reason} = Stacks.scrub(long <> @leak, "part")

      assert String.length(clean) > 11_000
      assert reason
    end

    test "a leak with nothing before it leaves nothing behind" do
      assert {"", reason} = Stacks.scrub(@leak, "part")
      assert reason
    end
  end

  describe "validate_story/2" do
    test "a leaking part is cut and the cut is reported, not swallowed" do
      steps = [%{ordinal: 1}, %{ordinal: 2}]

      raw = %{
        "title" => "A telling",
        "opening" => "The opening.",
        "closing" => "The closing.",
        "movements" => [
          %{
            "heading" => "One",
            "prose" => "Good prose.\n\n" <> @leak,
            "steps" => [1, 2]
          }
        ]
      }

      {story, dropped, uncovered} = Stacks.validate_story(raw, steps)

      assert uncovered == []
      assert [m] = story.movements
      assert m["prose"] == "Good prose."
      refute m["prose"] =~ "DSML"

      assert Enum.any?(dropped, &(&1 =~ "leaked its own tool-call markup")),
             "the page renders `dropped`, so a silent cut is the one thing this must not do"
    end

    test "a leak in the opening or the closing is caught too" do
      steps = [%{ordinal: 1}]

      raw = %{
        "title" => "A telling",
        "opening" => "Fine so far. " <> @leak,
        "closing" => "Also fine. " <> @leak,
        "movements" => [%{"heading" => "One", "prose" => "Prose.", "steps" => [1]}]
      }

      {story, dropped, _} = Stacks.validate_story(raw, steps)

      refute story.opening =~ "DSML"
      refute story.closing =~ "DSML"
      assert Enum.count(dropped, &(&1 =~ "leaked")) == 2
    end

    test "a clean telling reports nothing" do
      steps = [%{ordinal: 1}]

      raw = %{
        "title" => "A telling",
        "opening" => "The opening.",
        "closing" => "The closing.",
        "movements" => [%{"heading" => "One", "prose" => "Prose.", "steps" => [1]}]
      }

      {_story, dropped, _} = Stacks.validate_story(raw, steps)
      refute Enum.any?(dropped, &(&1 =~ "leaked"))
    end
  end

  describe "validate/3, the step pass" do
    test "a leaking capability or lesson is cut and reported" do
      body = "The document body, which contains the quote."

      raw = %{
        "capability" => "A real capability. " <> @leak,
        "lesson" => "Do the thing. " <> @leak,
        "requires" => [],
        "pitfall" => "",
        "pitfall_quote" => "",
        "excerpts" => []
      }

      {attrs, dropped} = Stacks.validate(raw, body, 2)

      refute attrs.capability =~ "DSML"
      refute attrs.lesson =~ "DSML"
      assert attrs.capability == "A real capability."
      assert Enum.count(dropped, &(&1 =~ "leaked")) == 2
    end
  end
end
