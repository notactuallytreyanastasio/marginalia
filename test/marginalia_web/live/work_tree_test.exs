defmodule MarginaliaWeb.WorkTreeTest do
  @moduledoc """
  The drafts page as a file tree: making folders, and the events the drag
  hook pushes when something is dropped.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    user = user_fixture()

    make = fn title ->
      body =
        "# #{title}\n\nA sentence long enough to be its own section.\n\n" <>
          String.duplicate("word ", 120)

      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      w
    end

    %{conn: log_in_user(conn, user), user: user, a: make.("Alpha draft"), b: make.("Beta draft")}
  end

  test "with no folders it still lists the drafts", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/works")

    assert html =~ "Alpha draft"
    assert html =~ "Beta draft"
  end

  test "adding a folder puts an empty bucket on the page", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/works")

    html = render_submit(view, "new_folder", %{"name" => "Case files"})

    assert html =~ "Case files"
    assert html =~ "empty — drag a draft here"
    assert [%{name: "Case files"}] = Folders.list_folders(user.id)
  end

  test "a blank folder name is ignored rather than made", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/works")

    render_submit(view, "new_folder", %{"name" => "   "})

    assert Folders.list_folders(user.id) == []
  end

  test "a duplicate folder name says so instead of appearing twice", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, ~p"/works")
    render_submit(view, "new_folder", %{"name" => "Case files"})

    html = render_submit(view, "new_folder", %{"name" => "Case files"})

    assert html =~ "already a folder with that name"
    assert length(Folders.list_folders(user.id)) == 1
  end

  test "dropping a draft on a folder files it there", %{conn: conn, user: user, a: a} do
    {:ok, f} = Folders.create_folder(user.id, %{name: "Case files"})
    {:ok, view, _} = live(conn, ~p"/works")

    render_hook(view, "move", %{
      "kind" => "work",
      "id" => to_string(a.id),
      "into" => to_string(f.id)
    })

    assert Works.get_work(user.id, a.id).folder_id == f.id
    assert [node] = Folders.tree(user.id).folders
    assert [%{id: id}] = node.works
    assert id == a.id
  end

  test "dropping it back on the root takes it out again", %{conn: conn, user: user, a: a} do
    {:ok, f} = Folders.create_folder(user.id, %{name: "Case files"})
    {:ok, _} = Folders.move_work(user.id, a.id, f.id)
    {:ok, view, _} = live(conn, ~p"/works")

    render_hook(view, "move", %{"kind" => "work", "id" => to_string(a.id), "into" => "root"})

    assert Works.get_work(user.id, a.id).folder_id == nil
  end

  test "dropping a folder on a folder nests it", %{conn: conn, user: user} do
    {:ok, outer} = Folders.create_folder(user.id, %{name: "Outer"})
    {:ok, inner} = Folders.create_folder(user.id, %{name: "Inner"})
    {:ok, view, _} = live(conn, ~p"/works")

    render_hook(view, "move", %{
      "kind" => "folder",
      "id" => to_string(inner.id),
      "into" => to_string(outer.id)
    })

    assert [node] = Folders.tree(user.id).folders
    assert node.folder.id == outer.id
    assert [child] = node.folders
    assert child.folder.id == inner.id
  end

  test "dropping a folder into its own child is refused out loud", %{conn: conn, user: user} do
    {:ok, outer} = Folders.create_folder(user.id, %{name: "Outer"})
    {:ok, inner} = Folders.create_folder(user.id, %{name: "Inner", parent_id: outer.id})
    {:ok, view, _} = live(conn, ~p"/works")

    html =
      render_hook(view, "move", %{
        "kind" => "folder",
        "id" => to_string(outer.id),
        "into" => to_string(inner.id)
      })

    assert html =~ "cannot go inside itself"
    assert Folders.get_folder(user.id, outer.id).parent_id == nil
  end

  test "collapsing a folder hides what is in it without moving anything", %{
    conn: conn,
    user: user,
    a: a
  } do
    {:ok, f} = Folders.create_folder(user.id, %{name: "Case files"})
    {:ok, _} = Folders.move_work(user.id, a.id, f.id)
    {:ok, view, html} = live(conn, ~p"/works")

    assert html =~ "Alpha draft"

    html = render_click(view, "toggle", %{"id" => to_string(f.id)})
    refute html =~ "Alpha draft"

    html = render_click(view, "toggle", %{"id" => to_string(f.id)})
    assert html =~ "Alpha draft"
    assert Works.get_work(user.id, a.id).folder_id == f.id
  end

  test "renaming a folder keeps its contents", %{conn: conn, user: user, a: a} do
    {:ok, f} = Folders.create_folder(user.id, %{name: "Case files"})
    {:ok, _} = Folders.move_work(user.id, a.id, f.id)
    {:ok, view, _} = live(conn, ~p"/works")

    render_click(view, "rename_start", %{"id" => to_string(f.id)})
    html = render_submit(view, "rename", %{"folder_id" => to_string(f.id), "name" => "Briefs"})

    assert html =~ "Briefs"
    refute html =~ "Case files"
    assert Works.get_work(user.id, a.id).folder_id == f.id
  end

  test "deleting a folder from the page leaves the drafts on it", %{conn: conn, user: user, a: a} do
    {:ok, f} = Folders.create_folder(user.id, %{name: "Case files"})
    {:ok, _} = Folders.move_work(user.id, a.id, f.id)
    {:ok, view, _} = live(conn, ~p"/works")

    html = render_click(view, "delete_folder", %{"id" => to_string(f.id)})

    assert html =~ "Alpha draft"
    refute html =~ "Case files"
    assert Works.get_work(user.id, a.id)
  end

  describe "the offer to file drafts by case" do
    setup %{user: user, a: a, b: b} do
      {:ok, a} = Marginalia.Cases.place(a, "Demo v. Example", "opinion")
      {:ok, b} = Marginalia.Cases.place(b, "Demo v. Example", "dissent")
      %{a: a, b: b}
    end

    test "it appears only while there is something to file", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/works")
      assert html =~ "file them by case"
      assert html =~ "2 of these already say which case"

      html = render_click(view, "backfill")

      assert html =~ "Filed 2 drafts by case."
      refute html =~ "file them by case"
    end

    test "it builds Cases / the case name and puts both drafts in it", %{conn: conn, user: user} do
      {:ok, view, _} = live(conn, ~p"/works")
      render_click(view, "backfill")

      assert [cases] = Folders.tree(user.id).folders
      assert cases.folder.name == "Cases"
      assert [%{folder: %{name: "Demo v. Example"}, works: works}] = cases.folders
      assert length(works) == 2
    end

    test "a draft already dragged somewhere is not swept up by it", %{
      conn: conn,
      user: user,
      a: a
    } do
      {:ok, pile} = Folders.create_folder(user.id, %{name: "Reading pile"})
      {:ok, _} = Folders.move_work(user.id, a.id, pile.id)

      {:ok, view, html} = live(conn, ~p"/works")
      assert html =~ "1 of these already say which case"

      render_click(view, "backfill")
      assert Works.get_work(user.id, a.id).folder_id == pile.id
    end
  end

  test "the count in the header is every draft, filed or not", %{conn: conn, user: user, a: a} do
    {:ok, f} = Folders.create_folder(user.id, %{name: "Case files"})
    {:ok, _} = Folders.move_work(user.id, a.id, f.id)
    {:ok, _view, html} = live(conn, ~p"/works")

    # two drafts exist; one is filed, one is not
    assert html =~ ~r/Your drafts\s*<\/h1>\s*<span class="mg-meta">2<\/span>/
  end
end
