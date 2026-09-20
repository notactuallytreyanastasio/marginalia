defmodule Marginalia.ImportBulkTest do
  @moduledoc """
  Landing a pile of documents in a folder.

  The behaviour worth pinning down is what happens to the batch when one of
  it is bad, and what counts as already having something. A bulk import that
  rolls back thirty-nine good documents because the fortieth was empty is an
  import nobody uses twice, and one that has no idea it already ran doubles
  the folder every time somebody presses the button again.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Works}
  alias Marginalia.Import.Bulk

  setup do
    %{user: user_fixture()}
  end

  defp doc(title, body \\ nil) do
    %{title: title, body: body || "# #{title}\n\n" <> String.duplicate("word ", 80), source_url: nil}
  end

  test "each document becomes a draft in the folder", %{user: user} do
    out = Bulk.land(user.id, [doc("One"), doc("Two")], folder: "Pile")

    assert length(out.created) == 2
    assert out.failed == []
    assert out.skipped == []
    assert out.folder.name == "Pile"

    titles = user.id |> Works.list_works() |> Enum.map(& &1.title) |> Enum.sort()
    assert titles == ["One", "Two"]
    assert Enum.all?(Works.list_works(user.id), &(&1.folder_id == out.folder.id))
  end

  test "running it twice does not double the folder", %{user: user} do
    Bulk.land(user.id, [doc("One"), doc("Two")], folder: "Pile")
    again = Bulk.land(user.id, [doc("One"), doc("Two"), doc("Three")], folder: "Pile")

    assert length(again.created) == 1
    assert Enum.sort(again.skipped) == ["One", "Two"]
    assert length(Works.list_works(user.id)) == 3
  end

  test "the same title in a different folder is a different document", %{user: user} do
    Bulk.land(user.id, [doc("One")], folder: "Pile")
    other = Bulk.land(user.id, [doc("One")], folder: "Other pile")

    assert length(other.created) == 1
    assert length(Works.list_works(user.id)) == 2
  end

  test "one bad document does not take the batch with it", %{user: user} do
    docs = [doc("Good"), doc("Empty", "   "), doc("Also good")]

    out = Bulk.land(user.id, docs, folder: "Pile")

    assert length(out.created) == 2
    assert [{"Empty", reason}] = out.failed
    assert Bulk.explain(reason) =~ "no text"
  end

  test "an over-long document is named rather than swallowed", %{user: user} do
    huge = doc("Huge", String.duplicate("word ", 130_000))

    out = Bulk.land(user.id, [doc("Fine"), huge], folder: "Pile")

    assert length(out.created) == 1
    assert [{"Huge", reason}] = out.failed
    assert Bulk.explain(reason) =~ "over the limit"
  end

  test "titles are not numbered unless asked", %{user: user} do
    Bulk.land(user.id, [doc("Alpha"), doc("Beta")], folder: "Plain")
    assert Enum.sort(Enum.map(Works.list_works(user.id), & &1.title)) == ["Alpha", "Beta"]
  end

  test "numbering follows the order given, and leaves an existing number alone", %{user: user} do
    out = Bulk.land(user.id, [doc("Alpha"), doc("2. Beta"), doc("Gamma")], number: true)

    assert Enum.map(out.created, & &1.title) == ["1. Alpha", "2. Beta", "3. Gamma"]
  end

  test "with no folder the drafts land loose", %{user: user} do
    out = Bulk.land(user.id, [doc("Loose")])

    assert out.folder == nil
    assert [work] = Works.list_works(user.id)
    assert work.folder_id == nil
  end

  test "an existing folder is reused, not duplicated", %{user: user} do
    {:ok, folder} = Folders.create_folder(user.id, %{name: "Mine"})

    out = Bulk.land(user.id, [doc("One")], folder: "Mine")

    assert out.folder.id == folder.id
    assert length(Folders.list_folders(user.id)) == 1
  end

  test "progress is reported per document as it goes", %{user: user} do
    me = self()

    Bulk.land(user.id, [doc("One"), doc("Two")],
      folder: "Pile",
      on_item: fn title, i, total -> send(me, {:landed, title, i, total}) end
    )

    assert_received {:landed, "One", 1, 2}
    assert_received {:landed, "Two", 2, 2}
  end

  describe "filtering by title" do
    defp cand(title), do: %{repo: "a/b", number: 1, title: title}

    test "an empty pattern keeps everything" do
      all = [cand("one"), cand("two")]
      assert Bulk.by_title(all, "") == {:ok, all}
      assert Bulk.by_title(all, nil) == {:ok, all}
    end

    test "it matches anywhere in the title, ignoring case" do
      all = [cand("Fix the parser"), cand("Revert the fix"), cand("Add a test")]

      assert {:ok, kept} = Bulk.by_title(all, "fix")
      assert Enum.map(kept, & &1.title) == ["Fix the parser", "Revert the fix"]
    end

    test "it is a real regex" do
      all = [cand("1. First"), cand("Later"), cand("2. Second")]

      assert {:ok, kept} = Bulk.by_title(all, ~S"^\d+\.")
      assert Enum.map(kept, & &1.title) == ["1. First", "2. Second"]
    end

    test "a pattern that will not compile says so rather than raising" do
      assert {:error, why} = Bulk.by_title([cand("x")], "(unclosed")
      assert is_binary(why)
      assert why != ""
    end

    test "a very long title cannot make the match run away" do
      # the subject is truncated, so a pattern that backtracks has 200
      # characters to do it in rather than a megabyte
      long = cand(String.duplicate("a", 100_000) <> "needle")

      assert {:ok, []} = Bulk.by_title([long], "needle")
    end
  end
end
