defmodule MarginaliaWeb.WorkTabsTest do
  @moduledoc "Every tab must render its own pane, by click and by direct link."
  use MarginaliaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  # one distinctive string per pane, taken from that pane and no other
  # what anyone holding the link can reach
  @panes [
    {"read", "The page"},
    {"graph", "Knowledge graph"},
    {"spine", "spine"},
    {"threads", "thread"}
  ]

  # how the thing works rather than what it found: the deploy owner only
  @owner_panes [
    {"trace", "Build trace"},
    {"prompts", "How the graph was built"}
  ]

  setup %{conn: conn} do
    user = user_fixture()
    body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)
    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")

    {:ok, _} =
      Works.insert_node(%{work_id: work.id, node_type: "beat", title: "a beat here", narrative: "n"})

    %{conn: log_in_user(conn, user), work: work}
  end

  test "an unknown view lands on the page, not on a report about it", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=nonsense")
    assert html =~ "The page"
  end

  test "the default view is the draft itself", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")
    assert html =~ "The page"
    refute html =~ "Receipt"
  end

  test "the tabs read in the order the work happens", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")

    order =
      Regex.scan(~r/phx-value-view="(\w+)"/, html) |> Enum.map(&List.last/1) |> Enum.uniq()

    assert order == ["read", "graph", "spine", "threads"]
  end

  describe "trace and prompts" do
    setup do
      owner = owner_fixture()
      body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)
      {:ok, work} = Works.create_work(owner.id, %{"title" => "Theirs", "body" => body})
      {:ok, work} = Works.set_status(work, "read")

      %{conn: log_in_user(build_conn(), owner), work: work}
    end

    test "the owner gets them", %{conn: conn, work: work} do
      {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")
      assert html =~ "Trace"
      assert html =~ "Prompts"

      for {v, marker} <- @owner_panes do
        {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=#{v}")
        assert html =~ marker, "?view=#{v} did not render #{inspect(marker)}"
      end
    end
  end

  test "nobody else gets them, by tab or by url", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")
    refute html =~ ">Trace<"
    refute html =~ ">Prompts<"

    # hiding a tab is not closing a door
    for v <- ["trace", "prompts"] do
      {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=#{v}")
      assert html =~ "The page"
      refute html =~ "Build trace"
    end
  end

  test "every tab switches to its own pane when clicked", %{conn: conn, work: work} do
    {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}")

    for {v, marker} <- @panes do
      html = render_click(view, "set_view", %{"view" => v})
      assert html =~ marker, "clicking #{v} did not render #{inspect(marker)}"
    end
  end

  test "every tab renders when reached by direct link", %{conn: conn, work: work} do
    for {v, marker} <- @panes do
      {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=#{v}")
      assert html =~ marker, "?view=#{v} did not render #{inspect(marker)}"
    end
  end
end
