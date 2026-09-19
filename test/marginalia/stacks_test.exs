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
      raw = %{"requires" => [], "excerpts" => [%{"quote" => "packed at the call site", "caption" => "the shape"}]}
      {attrs, []} = Stacks.validate(raw, @body, 5)

      assert [%{"caption" => "the shape", "text" => text}] = attrs.excerpts
      assert String.contains?(text, "unpacked in the handler")
      assert String.contains?(@body, text)
    end

    test "an invented excerpt is dropped" do
      raw = %{"requires" => [], "excerpts" => [%{"quote" => "fn apply(args: List)", "caption" => "x"}]}
      {attrs, dropped} = Stacks.validate(raw, @body, 5)

      assert attrs.excerpts == []
      assert Enum.any?(dropped, &String.contains?(&1, "is not in the document"))
    end

    test "at most two excerpts survive" do
      raw = %{
        "requires" => [],
        "excerpts" =>
          for(q <- ["Blimp has no variadic", "packed at the call site", "unpacked in the handler"],
            do: %{"quote" => q, "caption" => "c"}
          )
      }

      {attrs, []} = Stacks.validate(raw, @body, 5)
      assert length(attrs.excerpts) == 2
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
