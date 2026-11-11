defmodule MarginaliaWeb.PlayLiveTest do
  use MarginaliaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Marginalia.Accounts.User
  alias Marginalia.Repo

  test "serves the stage the game hook mounts on", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    assert has_element?(view, "#loose-leaf[phx-hook='LooseLeafGame'][phx-update='ignore']")
    assert has_element?(view, "#loose-leaf-canvas")
    assert has_element?(view, "#loose-leaf-hud")
    assert has_element?(view, "#loose-leaf-action")
    assert has_element?(view, "#loose-leaf-mute")
  end

  test "opens on the title card, with a way back out", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")

    assert has_element?(view, "#loose-leaf[data-phase='title']")
    assert has_element?(view, "#loose-leaf-card")
    assert has_element?(view, "#loose-leaf-exit[href='/']")
  end

  test "has something to say where WebGL is missing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/play")
    assert has_element?(view, "#loose-leaf-unsupported")
  end

  test "playing needs no account and creates none", %{conn: conn} do
    before = Repo.aggregate(User, :count)
    {:ok, _view, _html} = live(conn, ~p"/play")
    assert Repo.aggregate(User, :count) == before
  end
end
