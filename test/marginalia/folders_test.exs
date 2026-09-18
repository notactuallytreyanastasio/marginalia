defmodule Marginalia.FoldersTest do
  @moduledoc """
  Buckets of drafts: what may go where, and what survives a delete.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Works}

  setup do
    user = user_fixture()
    %{user: user, other: user_fixture()}
  end

  defp draft(user, title) do
    body =
      "# #{title}\n\nA sentence long enough to be a section.\n\n" <> String.duplicate("word ", 60)

    {:ok, work} = Works.create_work(user.id, %{"title" => title, "body" => body})
    work
  end

  defp folder(user, name, parent \\ nil) do
    {:ok, f} = Folders.create_folder(user.id, %{name: name, parent_id: parent && parent.id})
    f
  end

  test "a draft starts outside every folder and the tree says so", %{user: user} do
    w = draft(user, "Loose page")
    tree = Folders.tree(user.id)

    assert tree.folders == []
    assert [%{id: id}] = tree.works
    assert id == w.id
  end

  test "filing a draft moves it into the folder's node, not a copy of it", %{user: user} do
    w = draft(user, "Loose page")
    f = folder(user, "Case files")

    assert {:ok, _} = Folders.move_work(user.id, w.id, f.id)

    tree = Folders.tree(user.id)
    assert tree.works == []
    assert [node] = tree.folders
    assert node.folder.id == f.id
    assert [%{id: id}] = node.works
    assert id == w.id
  end

  test "a folder's count includes what is buried below it", %{user: user} do
    outer = folder(user, "Outer")
    inner = folder(user, "Inner", outer)

    {:ok, _} = Folders.move_work(user.id, draft(user, "One").id, outer.id)
    {:ok, _} = Folders.move_work(user.id, draft(user, "Two").id, inner.id)
    {:ok, _} = Folders.move_work(user.id, draft(user, "Three").id, inner.id)

    assert [node] = Folders.tree(user.id).folders
    assert node.count == 3
    assert [child] = node.folders
    assert child.count == 2
  end

  test "dropping a draft on the root unfiles it", %{user: user} do
    w = draft(user, "Loose page")
    f = folder(user, "Case files")
    {:ok, _} = Folders.move_work(user.id, w.id, f.id)

    assert {:ok, _} = Folders.move_work(user.id, w.id, nil)
    assert [%{id: id}] = Folders.tree(user.id).works
    assert id == w.id
  end

  test "a folder cannot be dropped into itself", %{user: user} do
    f = folder(user, "Case files")
    assert {:error, :cycle} = Folders.move_folder(user.id, f.id, f.id)
  end

  test "a folder cannot be dropped into its own descendant", %{user: user} do
    outer = folder(user, "Outer")
    inner = folder(user, "Inner", outer)
    deeper = folder(user, "Deeper", inner)

    assert {:error, :cycle} = Folders.move_folder(user.id, outer.id, deeper.id)
    # and the tree is unchanged by the refusal
    assert [node] = Folders.tree(user.id).folders
    assert node.folder.id == outer.id
  end

  test "two siblings may not share a name, but cousins may", %{user: user} do
    outer = folder(user, "Outer")
    _a = folder(user, "Notes", outer)

    assert {:error, changeset} =
             Folders.create_folder(user.id, %{name: "Notes", parent_id: outer.id})

    assert "there is already a folder with that name here" in errors_on(changeset).name

    # same name, different parent: fine
    assert {:ok, _} = Folders.create_folder(user.id, %{name: "Notes"})
  end

  test "deleting a folder keeps the drafts and lifts them one level", %{user: user} do
    outer = folder(user, "Outer")
    inner = folder(user, "Inner", outer)
    w = draft(user, "Buried")
    {:ok, _} = Folders.move_work(user.id, w.id, inner.id)
    grand = folder(user, "Grandchild", inner)

    assert {:ok, _} = Folders.delete_folder(user.id, inner.id)

    assert Works.get_work(user.id, w.id)
    assert [node] = Folders.tree(user.id).folders
    assert node.folder.id == outer.id
    assert [%{id: wid}] = node.works
    assert wid == w.id
    assert [child] = node.folders
    assert child.folder.id == grand.id
  end

  test "deleting a root folder drops its contents to the root", %{user: user} do
    f = folder(user, "Case files")
    w = draft(user, "Filed")
    {:ok, _} = Folders.move_work(user.id, w.id, f.id)

    assert {:ok, _} = Folders.delete_folder(user.id, f.id)

    tree = Folders.tree(user.id)
    assert tree.folders == []
    assert [%{id: id}] = tree.works
    assert id == w.id
  end

  test "another writer's folder is not a place you can put anything", %{user: user, other: other} do
    theirs = folder(other, "Theirs")
    mine = folder(user, "Mine")
    w = draft(user, "Mine too")
    {:ok, _} = Folders.move_work(user.id, w.id, mine.id)

    # a forged parent lands the draft at the root rather than in their folder
    assert {:ok, moved} = Folders.move_work(user.id, w.id, theirs.id)
    assert moved.folder_id == nil

    assert {:ok, moved_folder} = Folders.move_folder(user.id, mine.id, theirs.id)
    assert moved_folder.parent_id == nil

    # and their tree never saw any of it
    assert Folders.tree(other.id).works == []
  end

  describe "backfilling folders from collections" do
    defp placed(user, title, collection, role) do
      w = draft(user, title)
      {:ok, w} = Marginalia.Cases.place(w, collection, role)
      w
    end

    test "each collection becomes a folder under one parent", %{user: user} do
      placed(user, "Opinion", "Miller v. Alabama", "opinion")
      placed(user, "Dissent", "Miller v. Alabama", "dissent")
      placed(user, "Brief", "Dauch", "opinion")
      loose = draft(user, "A loose page")

      assert {:ok, 3} = Folders.backfill_from_collections(user.id)

      tree = Folders.tree(user.id)
      # the uncollected draft is left at the root, not swept into a bucket
      assert [%{id: id}] = tree.works
      assert id == loose.id

      assert [cases] = tree.folders
      assert cases.folder.name == "Cases"
      assert cases.count == 3
      assert Enum.map(cases.folders, & &1.folder.name) == ["Dauch", "Miller v. Alabama"]
      assert Enum.map(cases.folders, & &1.count) == [1, 2]
    end

    test "running it twice files nothing the second time", %{user: user} do
      placed(user, "Opinion", "Miller v. Alabama", "opinion")

      assert {:ok, 1} = Folders.backfill_from_collections(user.id)
      assert {:ok, 0} = Folders.backfill_from_collections(user.id)
      assert length(Folders.list_folders(user.id)) == 2
    end

    test "it reuses folders that are already there rather than failing on the name", %{user: user} do
      {:ok, cases} = Folders.create_folder(user.id, %{name: "Cases"})
      {:ok, _} = Folders.create_folder(user.id, %{name: "Miller v. Alabama", parent_id: cases.id})
      placed(user, "Opinion", "Miller v. Alabama", "opinion")

      assert {:ok, 1} = Folders.backfill_from_collections(user.id)
      assert length(Folders.list_folders(user.id)) == 2
    end

    test "a draft the writer already filed is left where they put it", %{user: user} do
      w = placed(user, "Opinion", "Miller v. Alabama", "opinion")
      {:ok, mine} = Folders.create_folder(user.id, %{name: "Reading pile"})
      {:ok, _} = Folders.move_work(user.id, w.id, mine.id)

      assert {:ok, 0} = Folders.backfill_from_collections(user.id)
      assert Works.get_work(user.id, w.id).folder_id == mine.id
    end

    test "with no collections anywhere it makes no folders at all", %{user: user} do
      draft(user, "A loose page")

      assert {:ok, 0} = Folders.backfill_from_collections(user.id)
      assert Folders.list_folders(user.id) == []
    end

    test "it never reaches into another writer's drafts", %{user: user, other: other} do
      placed(other, "Theirs", "Miller v. Alabama", "opinion")
      placed(user, "Mine", "Miller v. Alabama", "dissent")

      assert {:ok, 1} = Folders.backfill_from_collections(user.id)
      assert Folders.list_folders(other.id) == []
    end
  end

  test "another writer's draft cannot be filed by me", %{user: user, other: other} do
    theirs = draft(other, "Theirs")
    mine = folder(user, "Mine")

    assert {:error, :not_found} = Folders.move_work(user.id, theirs.id, mine.id)
    assert {:error, :not_found} = Folders.delete_folder(user.id, folder(other, "Nope").id)
  end
end
