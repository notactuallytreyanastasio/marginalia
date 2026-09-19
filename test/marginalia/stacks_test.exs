defmodule Marginalia.StacksTest do
  @moduledoc """
  Ordering a stack, and keeping only what the document actually says.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Stacks, Works}

  setup do
    user = user_fixture()
    {:ok, folder} = Folders.create_folder(user.id, %{name: "A backend"})
    %{user: user, folder: folder}
  end

  defp draft(user, title, body \\ nil) do
    body =
      body ||
        "# #{title}\n\nThe first paragraph of #{title}, long enough to stand alone.\n\n" <>
          "A second paragraph with something quotable in it.\n\n" <>
          String.duplicate("word ", 120)

    {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
    w
  end

  describe "the order a stack is read in" do
    test "a leading number in every title is the author saying the order", %{user: user} do
      works = [draft(user, "3. Third"), draft(user, "1. First"), draft(user, "2. Second")]
      assert Enum.map(Stacks.order(works), & &1.title) == ["1. First", "2. Second", "3. Third"]
    end

    test "numbers well past ten still sort as numbers", %{user: user} do
      works = [draft(user, "10. Tenth"), draft(user, "9. Ninth"), draft(user, "1. First")]
      assert Enum.map(Stacks.order(works), &String.slice(&1.title, 0, 2)) == ["1.", "9.", "10"]
    end

    test "without numbers it is insertion order, which is the only other true thing",
         %{user: user} do
      a = draft(user, "Alpha")
      b = draft(user, "Beta")
      assert Enum.map(Stacks.order([b, a]), & &1.id) == [a.id, b.id]
    end

    test "a half-numbered stack falls back rather than guessing", %{user: user} do
      a = draft(user, "1. First")
      b = draft(user, "Untitled")
      assert Enum.map(Stacks.order([b, a]), & &1.id) == [a.id, b.id]
    end

    test "duplicate numbers fall back too", %{user: user} do
      a = draft(user, "1. First")
      b = draft(user, "1. Also first")
      assert Enum.map(Stacks.order([b, a]), & &1.id) == [a.id, b.id]
    end
  end

  describe "keeping only what the document says" do
    @body "Blimp has no variadic call.\n\nSo the fix has to be a list, packed at the call site\nand unpacked in the handler."

    test "a locatable pitfall quote is kept, with the document's own wording" do
      raw = %{
        "capability" => "a rest formal becomes one parameter holding a list",
        "requires" => [1],
        "lesson" => "Pack at the call site.",
        "pitfall" => "Do not try a variadic call.",
        "pitfall_quote" => "the fix has to be a list, packed at the call site and unpacked",
        "excerpts" => []
      }

      {attrs, dropped} = Stacks.validate(raw, @body, 5)

      assert dropped == []
      assert attrs.pitfall == "Do not try a variadic call."
      # re-wrapped on the way in, stored as the document has it
      assert String.contains?(attrs.pitfall_quote, "\n")
    end

    test "a pitfall the document does not state is dropped, not softened" do
      raw = %{
        "pitfall" => "Blimp secretly supports varargs.",
        "pitfall_quote" => "Blimp secretly supports varargs.",
        "requires" => [],
        "excerpts" => []
      }

      {attrs, dropped} = Stacks.validate(raw, @body, 5)

      assert attrs.pitfall == nil
      assert Enum.any?(dropped, &String.contains?(&1, "quote is not in the document"))
    end

    test "requires must name an earlier document" do
      raw = %{"requires" => [2, 5, 9, "x"], "excerpts" => []}
      {attrs, dropped} = Stacks.validate(raw, @body, 5)

      assert attrs.requires == [2]
      assert Enum.any?(dropped, &String.contains?(&1, "requires 5"))
      assert Enum.any?(dropped, &String.contains?(&1, "requires 9"))
      assert Enum.any?(dropped, &String.contains?(&1, "not a number"))
    end

    test "an excerpt is the paragraph around the quote, from the document" do
      raw = %{
        "requires" => [],
        "excerpts" => [%{"quote" => "packed at the call site", "caption" => "the shape"}]
      }

      {attrs, []} = Stacks.validate(raw, @body, 5)

      assert [%{"caption" => "the shape", "text" => text}] = attrs.excerpts
      assert String.contains?(text, "unpacked in the handler")
      assert String.contains?(@body, text)
    end

    test "an invented excerpt is dropped" do
      raw = %{
        "requires" => [],
        "excerpts" => [%{"quote" => "fn apply(args: List)", "caption" => "x"}]
      }

      {attrs, dropped} = Stacks.validate(raw, @body, 5)

      assert attrs.excerpts == []
      assert Enum.any?(dropped, &String.contains?(&1, "is not in the document"))
    end

    test "at most two excerpts survive" do
      raw = %{
        "requires" => [],
        "excerpts" =>
          for(
            q <- ["Blimp has no variadic", "packed at the call site", "unpacked in the handler"],
            do: %{"quote" => q, "caption" => "c"}
          )
      }

      {attrs, []} = Stacks.validate(raw, @body, 5)
      assert length(attrs.excerpts) == 2
    end
  end

  describe "the second pass, which can see forwards" do
    # The forward pass is told only what came before each step, so it cannot
    # say "step 9 walks this back". That claim is the one the second pass can
    # make and the one that can do damage — it sends a reader off to read
    # something that may not say that at all — so it has to name a later step
    # and quote that step's own summary.
    setup do
      later = [
        %{
          ordinal: 8,
          capability: "holes type-check",
          lesson: "Emit a hole operator.",
          pitfall: nil
        },
        %{
          ordinal: 9,
          capability: "casts are checked",
          lesson: "Replace the unchecked cast with a real test.",
          pitfall: "The earlier cast compiled to nothing at all."
        }
      ]

      %{later: later}
    end

    test "a revision naming a later step and quoting it is kept", %{later: later} do
      raw = %{
        "mechanism" => "It splits the body at the first exit and lifts the tail.",
        "watch_for" => "Step 9 leans on the cast being a real test.",
        "revised_by" => 9,
        "revision" => "Step 9 replaces the unchecked cast.",
        "revision_quote" => "Replace the unchecked cast with a real test."
      }

      {attrs, dropped} = Stacks.validate_deep(raw, later)

      assert dropped == []
      assert attrs.revised_by == 9
      assert attrs.revision_quote == "Replace the unchecked cast with a real test."
      assert attrs.watch_for =~ "Step 9"
    end

    test "a revision pointing at a step that is not later is refused", %{later: later} do
      raw = %{
        "mechanism" => "x",
        "revised_by" => 3,
        "revision" => "Step 3 changed it.",
        "revision_quote" => "anything"
      }

      {attrs, dropped} = Stacks.validate_deep(raw, later)

      assert attrs.revised_by == nil
      assert Enum.any?(dropped, &String.contains?(&1, "step 3 is not a later step"))
    end

    test "a revision whose quote is not in that step's summary is refused", %{later: later} do
      raw = %{
        "mechanism" => "x",
        "revised_by" => 9,
        "revision" => "Step 9 deletes the whole translator.",
        "revision_quote" => "Step 9 deletes the whole translator."
      }

      {attrs, dropped} = Stacks.validate_deep(raw, later)

      assert attrs.revised_by == nil
      assert attrs.revision == nil
      assert Enum.any?(dropped, &String.contains?(&1, "quote is not in step 9"))
    end

    test "no revision is a normal answer", %{later: later} do
      raw = %{
        "mechanism" => "x",
        "watch_for" => "",
        "revised_by" => 0,
        "revision" => "",
        "revision_quote" => ""
      }

      {attrs, dropped} = Stacks.validate_deep(raw, later)

      assert attrs.revised_by == nil
      assert attrs.watch_for == nil
      assert dropped == []
    end

    test "an empty mechanism is the one thing this pass must not return", %{later: later} do
      {attrs, dropped} = Stacks.validate_deep(%{"revised_by" => 0}, later)

      assert attrs.mechanism == nil
      assert Enum.any?(dropped, &String.contains?(&1, "mechanism"))
    end

    test "the last step has nothing after it and that is fine" do
      raw = %{
        "mechanism" => "x",
        "revised_by" => 4,
        "revision" => "later",
        "revision_quote" => "q"
      }

      {attrs, dropped} = Stacks.validate_deep(raw, [])

      assert attrs.revised_by == nil
      assert Enum.any?(dropped, &String.contains?(&1, "not a later step"))
    end
  end

  describe "composing the telling" do
    # Prose is not quote-checkable the way a claim is, so the thing that can
    # be checked is whether the composition actually carries every step. A
    # telling that covers four of ten has thrown the method away, and it is
    # the failure least likely to look like one.
    setup do
      steps = for n <- 1..4, do: %Marginalia.Stacks.Step{ordinal: n, capability: "does #{n}"}
      %{steps: steps}
    end

    defp part(heading, steps),
      do: %{"heading" => heading, "prose" => "Some prose.", "steps" => steps, "turn" => ""}

    test "a telling covering every step keeps all of it", %{steps: steps} do
      raw = %{
        "title" => "How it is built",
        "opening" => "op",
        "closing" => "cl",
        "movements" => [part("Groundwork", [1, 2]), part("The hard part", [3, 4])]
      }

      {attrs, dropped, uncovered} = Stacks.validate_story(raw, steps)

      assert dropped == []
      assert uncovered == []
      assert Enum.map(attrs.movements, & &1["heading"]) == ["Groundwork", "The hard part"]
    end

    test "a step left out of every part is named, not waved through", %{steps: steps} do
      raw = %{"movements" => [part("Only the start", [1, 2])]}

      {_attrs, dropped, uncovered} = Stacks.validate_story(raw, steps)

      assert uncovered == [3, 4]
      assert Enum.any?(dropped, &String.contains?(&1, "appear in no part: 3, 4"))
    end

    test "a step told twice is refused the second time", %{steps: steps} do
      raw = %{"movements" => [part("A", [1, 2]), part("B", [2, 3, 4])]}

      {attrs, dropped, uncovered} = Stacks.validate_story(raw, steps)

      assert uncovered == []
      assert Enum.any?(dropped, &String.contains?(&1, "step 2 is told twice"))
      assert Enum.map(attrs.movements, & &1["steps"]) == [[1, 2], [3, 4]]
    end

    test "a step that is not in this stack is refused", %{steps: steps} do
      raw = %{"movements" => [part("A", [1, 2, 3, 4, 9])]}

      {_attrs, dropped, _} = Stacks.validate_story(raw, steps)
      assert Enum.any?(dropped, &String.contains?(&1, "step 9 is not in this stack"))
    end

    test "parts are ordered by the work, not by what came back", %{steps: steps} do
      raw = %{"movements" => [part("Later", [3, 4]), part("Earlier", [1, 2])]}

      {attrs, [], []} = Stacks.validate_story(raw, steps)
      assert Enum.map(attrs.movements, & &1["heading"]) == ["Earlier", "Later"]
    end

    test "a part with no prose is not a part", %{steps: steps} do
      raw = %{
        "movements" => [
          %{"heading" => "Empty", "prose" => "  ", "steps" => [1, 2]},
          part("Real", [3, 4])
        ]
      }

      {attrs, dropped, uncovered} = Stacks.validate_story(raw, steps)

      assert length(attrs.movements) == 1
      assert uncovered == [1, 2]
      assert Enum.any?(dropped, &String.contains?(&1, "no prose"))
    end

    test "completeness is a property the story carries" do
      refute Marginalia.Stacks.Story.complete?(%Marginalia.Stacks.Story{uncovered: [3]})
      assert Marginalia.Stacks.Story.complete?(%Marginalia.Stacks.Story{uncovered: []})
    end
  end

  describe "the guide" do
    test "links run both ways, and the ends know they are ends", %{user: user, folder: folder} do
      for {title, ord, req} <- [{"1. One", 1, []}, {"2. Two", 2, [1]}, {"3. Three", 3, [1, 2]}] do
        w = draft(user, title)
        {:ok, _} = Folders.move_work(user.id, w.id, folder.id)

        {:ok, _} =
          %Marginalia.Stacks.Step{}
          |> Marginalia.Stacks.Step.changeset(%{
            folder_id: folder.id,
            work_id: w.id,
            ordinal: ord,
            capability: "does thing #{ord}",
            requires: req
          })
          |> Marginalia.Repo.insert()
      end

      [one, two, three] = Stacks.guide(folder.id)

      assert one.previous == nil
      assert one.requires == []
      assert Enum.map(one.required_by, & &1.ordinal) == [2, 3]

      assert two.previous.ordinal == 1
      assert Enum.map(two.requires, & &1.ordinal) == [1]

      assert three.next == nil
      assert Enum.map(three.requires, & &1.ordinal) == [1, 2]
      assert three.required_by == []
    end

    test "stats count what is there", %{user: user, folder: folder} do
      w = draft(user, "1. One")
      {:ok, _} = Folders.move_work(user.id, w.id, folder.id)

      assert %{documents: 1, read: 0} = Stacks.stats(user.id, folder.id)
    end
  end
end
