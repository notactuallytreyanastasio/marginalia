defmodule MarginaliaWeb.ProgressTest do
  @moduledoc """
  The read takes minutes across three stages, the last of which produces
  nothing visible until it finishes. The writer has to be able to tell working
  from hung, including after a page reload.
  """
  use MarginaliaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    user = user_fixture()
    body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)
    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    %{conn: log_in_user(conn, user), work: work, section: hd(Works.list_sections(work.id))}
  end

  test "all three stages are named while reading", %{conn: conn, work: work} do
    {:ok, work} = Works.set_status(work, "reading")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")

    assert html =~ "Reading your draft"
    assert html =~ "Sections"
    assert html =~ "The spine"
    assert html =~ "Connections"
    # the weave is the stage that was previously invisible
    assert html =~ "what develops, pays off, requires, or contradicts what"
  end

  test "a reload mid-read recovers which stage is running", %{conn: conn, work: work, section: s} do
    {:ok, work} = Works.set_status(work, "reading")
    Works.set_section_status(s, "read")

    {:ok, _} = Works.insert_node(%{work_id: work.id, node_type: "spine", title: "The trunk"})

    {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}")
    # spine exists, so sections and spine are done and the weave is running
    assert render(view) =~ "1 spine"
  end

  test "the stage broadcast moves the view on", %{conn: conn, work: work} do
    {:ok, work} = Works.set_status(work, "reading")
    {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}")

    send(view.pid, {:stage, :sections, :done})
    send(view.pid, {:stage, :weave, :start})
    assert render(view) =~ "Connections"
  end

  test "a finished read shows the map, not the progress view", %{conn: conn, work: work} do
    {:ok, work} = Works.set_status(work, "read")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")
    refute html =~ "Reading your draft"
  end
end
