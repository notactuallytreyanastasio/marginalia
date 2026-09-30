defmodule MarginaliaWeb.CutShowTest do
  @moduledoc """
  A reading that has not started yet starts when somebody is actually
  there to watch it — and only then.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Marginalia.AccountsFixtures

  alias Marginalia.{Cuts, Folders, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    user = user_fixture()
    {:ok, folder} = Folders.create_folder(user.id, %{name: "A case"})

    {:ok, w} =
      Works.create_work(user.id, %{"title" => "One", "body" => "# One\n\nSome prose here."})

    {:ok, _} = Folders.move_work(user.id, w.id, folder.id)
    {:ok, cut} = Cuts.open_folder_reading(user.id, folder.id)

    %{conn: log_in_user(conn, user), user: user, cut: cut}
  end

  test "the page served before the socket connects leaves the cut alone",
       %{conn: conn, user: user, cut: cut} do
    # the dead render cannot run a task, so it must not claim one is running
    conn = get(conn, ~p"/cuts/#{cut.id}")
    assert html_response(conn, 200)

    assert Cuts.get_cut(user.id, cut.id).status == "draft"
  end

  test "the members are on the page while the read has not finished",
       %{conn: conn, cut: cut} do
    conn = get(conn, ~p"/cuts/#{cut.id}")
    html = html_response(conn, 200)

    # nothing has been read yet, but who is in the folder is already known
    assert html =~ ~s(class="cut-members")
    assert html =~ "One"
  end
end
