defmodule MarginaliaWeb.StackRoutesTest do
  @moduledoc """
  The literal routes are reachable, not shadowed by the ones with variables.

  `/stacks/new` sat after `/stacks/:id` and so resolved as a folder called
  "new", which redirected away. Nothing failed: the page rendered, it was
  simply the wrong page. Only clicking it found that, so this is the cheap
  check that clicking it again is not required.
  """
  use MarginaliaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the import page is its own page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/stacks/new")

    assert html =~ "Import a stack"
    assert html =~ ~s(name="repo")
    assert html =~ ~s(name="token")
  end

  test "a folder id still reaches the folder", %{conn: conn, user: _} do
    assert {:error, {:live_redirect, %{to: "/stacks"}}} = live(conn, ~p"/stacks/999999")
  end

  test "the list is reachable", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/stacks")
    assert html =~ "Methods"
  end
end
