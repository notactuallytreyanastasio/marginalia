defmodule MarginaliaWeb.TourTest do
  @moduledoc """
  Each tab explains itself once. The affordances it names — a hairline in
  the gutter, a highlight you can hover — are invisible until someone says
  they are there.
  """
  use MarginaliaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Accounts, Tour, Works}

  setup %{conn: conn} do
    user = user_fixture()
    body = "# A draft\n\nShe stood at the window. " <> String.duplicate("word ", 300)
    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")
    %{conn: log_in_user(conn, user), work: work, user: user}
  end

  test "the first visit to a tab explains it", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    assert html =~ "The page, with its notes in the margin"
    assert html =~ "hairline in the gutter" or html =~ "thin line appears"
  end

  test "the second visit does not", %{conn: conn, work: work} do
    {:ok, _view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    refute html =~ "The page, with its notes in the margin"
  end

  test "each tab gets its own, once", %{conn: conn, work: work, user: user} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    html = render_click(view, "set_view", %{"view" => "graph"})
    assert html =~ "What leads to what"

    html = render_click(view, "set_view", %{"view" => "spine"})
    assert html =~ "The whole draft at once"
    refute html =~ "What leads to what"

    # going back does not explain it again
    refute render_click(view, "set_view", %{"view" => "graph"}) =~ "What leads to what"

    seen = Marginalia.Repo.reload!(user).seen_tours
    assert "read" in seen and "graph" in seen and "spine" in seen
  end

  test "help brings it back", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    render_click(view, "dismiss_tour", %{})
    refute render(view) =~ "The page, with its notes in the margin"

    assert render_click(view, "show_help", %{}) =~ "The page, with its notes in the margin"
  end

  test "dismissing it keeps it dismissed for that visit", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    refute render_click(view, "dismiss_tour", %{}) =~ "The page, with its notes"
  end

  test "someone who has seen everything is never shown one", %{conn: conn, work: work, user: user} do
    Enum.each(Tour.views(), &Accounts.mark_tour_seen(Marginalia.Repo.reload!(user), &1))

    for v <- ~w(read graph spine threads) do
      {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=#{v}")
      refute html =~ "mg-tour", "#{v} should not explain itself again"
    end
  end

  test "every tab that exists has something to say" do
    for v <- ~w(read graph spine threads trace prompts) do
      tour = Tour.for_view(String.to_existing_atom(v))
      assert tour, "#{v} has no tour"
      assert tour.title
      assert length(tour.points) >= 3, "#{v} needs more than a sentence"
    end
  end
end
