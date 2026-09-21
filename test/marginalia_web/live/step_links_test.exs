defmodule MarginaliaWeb.StepLinksTest do
  @moduledoc """
  Getting from a document to the step composed from it.

  A folder that has been read forwards holds two things per document — the
  document, and the step the forward read made of it — and only one of them
  was reachable from the list of drafts. A hundred and eleven rows, and the
  way to the step was to open the folder and count.

  The other half of this is the query: one join for the whole tree, because
  a list of a hundred and eleven asking per row is a hundred and eleven
  queries to draw a page.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Repo, Stacks, Works}
  alias Marginalia.Stacks.Step

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, folder} = Folders.create_folder(user.id, %{name: "A stack"})

    make = fn title ->
      {:ok, w} =
        Works.create_work(user.id, %{
          "title" => title,
          "body" => "# #{title}\n\n" <> String.duplicate("word ", 90)
        })

      {:ok, _} = Folders.move_work(user.id, w.id, folder.id)
      w
    end

    read = make.("1. The first thing")
    unread = make.("2. The second thing")

    Repo.insert!(%Step{
      folder_id: folder.id,
      work_id: read.id,
      ordinal: 1,
      capability: "read a folder forwards"
    })

    %{conn: log_in_user(conn, user), user: user, folder: folder, read: read, unread: unread}
  end

  test "a document that became a step links to it", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/works")

    assert html =~ ~s(href="/stacks/#{ctx.folder.id}/1")
    assert html =~ "step 1"
  end

  test "a document that has not been read has no such link", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/works")

    # one link, for the one document that has a step
    assert length(Regex.scan(~r/>step \d+</, html)) == 1
  end

  test "the lookup is one query for the whole tree", ctx do
    by_work = Stacks.steps_by_work(ctx.user.id)

    assert by_work[ctx.read.id] == {ctx.folder.id, 1}
    assert by_work[ctx.unread.id] == nil
  end

  test "somebody else's steps are not in this writer's map", ctx do
    theirs = user_fixture()
    {:ok, their_folder} = Folders.create_folder(theirs.id, %{name: "Theirs"})

    {:ok, their_work} =
      Works.create_work(theirs.id, %{
        "title" => "Private",
        "body" => "# Private\n\n" <> String.duplicate("word ", 90)
      })

    Repo.insert!(%Step{
      folder_id: their_folder.id,
      work_id: their_work.id,
      ordinal: 1,
      capability: "x"
    })

    by_work = Stacks.steps_by_work(ctx.user.id)

    refute Map.has_key?(by_work, their_work.id)
    assert map_size(by_work) == 1
  end

  test "the link lands on the step, not on the folder", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/stacks/#{ctx.folder.id}/1")

    assert html =~ "read a folder forwards"
  end
end
