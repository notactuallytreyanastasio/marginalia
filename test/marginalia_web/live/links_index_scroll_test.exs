defmodule MarginaliaWeb.LinksIndexScrollTest do
  @moduledoc """
  /links with a real number of links on it.

  The page holds two tools and a diagram per cluster before it reaches the
  list it is named for, and then draws every pair. With four hundred pairs
  that is not a list, it is a wall — and the list starts below the fold
  before a single row is drawn.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Repo, Works}

  @page 40

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    user = user_fixture()
    body = "# H\n\n" <> String.duplicate("word ", 90)

    works =
      for i <- 1..24 do
        {:ok, w} = Works.create_work(user.id, %{"title" => "Draft #{i}", "body" => body})
        {:ok, w} = Works.set_status(w, "read")
        w
      end

    # pairs, chained, so there are more than a page of them
    links =
      for {a, b} <- Enum.zip(works, tl(works)) ++ Enum.zip(works, Enum.drop(works, 2)) do
        {:ok, l} = Links.get_or_create(a.id, b.id)
        Repo.update!(Ecto.Changeset.change(l, status: "linked"))
      end

    %{conn: log_in_user(conn, user), user: user, works: works, links: links}
  end

  test "it draws a page of rows, not all of them", ctx do
    assert length(ctx.links) > @page

    {:ok, _view, html} = live(ctx.conn, ~p"/links")

    rows = length(Regex.scan(~r/class="lx-row"/, html))
    assert rows == @page, "#{rows} rows drawn of #{length(ctx.links)}"
    assert html =~ "Show #{@page} more" or html =~ "more"
  end

  test "asking for more gives more, and eventually all of them", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/links")

    html = render_click(view, "more", %{})

    assert length(Regex.scan(~r/class="lx-row"/, html)) ==
             min(@page * 2, length(ctx.links))

    for _ <- 1..10, do: render_click(view, "more", %{})
    html = render(view)

    assert length(Regex.scan(~r/class="lx-row"/, html)) == length(ctx.links)
    refute html =~ "lx-more"
  end

  test "the filter matches either side of a pair", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/links")

    html = render_change(view, "filter", %{"q" => "Draft 7"})

    # Draft 7 is in pairs on both sides of the ↔
    rows = length(Regex.scan(~r/class="lx-row"/, html))
    assert rows > 0
    assert rows < length(ctx.links)
    assert html =~ "Draft 7"
  end

  test "a filter that matches nothing says so instead of showing everything", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/links")

    html = render_change(view, "filter", %{"q" => "nonesuch"})

    assert html =~ "Nothing matches"
    assert length(Regex.scan(~r/class="lx-row"/, html)) == 0
  end

  test "filtering resets the paging, so the count is not a lie", ctx do
    {:ok, view, _} = live(ctx.conn, ~p"/links")

    render_click(view, "more", %{})
    html = render_change(view, "filter", %{"q" => "Draft 1"})

    shown = length(Regex.scan(~r/class="lx-row"/, html))
    assert shown <= @page, "a narrowed list should start at one page again"
  end

  test "the tools and the diagrams are folded, not gone", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/links")

    assert html =~ "<details"
    assert html =~ "relate a whole folder" or html =~ "relate two drafts"
    assert html =~ ~r/\d+ webs? of three or more/
  end
end
