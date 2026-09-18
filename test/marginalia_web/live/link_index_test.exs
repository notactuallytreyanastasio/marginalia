defmodule MarginaliaWeb.LinkIndexTest do
  @moduledoc """
  The page that lists every linked pair and makes new ones.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    previous = Application.get_env(:marginalia, :deepseek_api_key)
    Application.put_env(:marginalia, :deepseek_api_key, nil)
    on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)

    user = user_fixture()

    make = fn title, status ->
      body =
        "# #{title}\n\nA sentence long enough to be its own section.\n\n" <>
          String.duplicate("word ", 200)

      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, status)
      w
    end

    %{
      conn: log_in_user(conn, user),
      user: user,
      a: make.("Alpha draft", "read"),
      b: make.("Beta draft", "read"),
      unread: make.("Gamma draft", "reading")
    }
  end

  test "it offers the drafts that have been read, and says why not the others", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/links")

    assert html =~ "Alpha draft"
    assert html =~ "Beta draft"
    refute html =~ "Gamma draft"
    assert html =~ "still being read"
  end

  test "picking two and linking them starts the pass and goes to the pair", %{
    conn: conn,
    a: a,
    b: b
  } do
    {:ok, view, _} = live(conn, ~p"/links")

    # one form, both selects, as the browser submits it
    render_change(view, "pick", %{"a" => to_string(a.id), "b" => to_string(b.id)})

    assert {:error, {:live_redirect, %{to: to}}} =
             render_submit(view, "make", %{"a" => to_string(a.id), "b" => to_string(b.id)})

    link = Links.get_for(a.id, b.id)
    assert link
    assert to == "/links/#{link.id}"
  end

  test "the same draft twice is refused", %{conn: conn, a: a} do
    {:ok, view, _} = live(conn, ~p"/links")

    render_change(view, "pick", %{"a" => to_string(a.id), "b" => to_string(a.id)})
    html = render_submit(view, "make", %{"a" => to_string(a.id), "b" => to_string(a.id)})

    assert html =~ "two different drafts"
    assert Links.for_user(a.user_id) == []
  end

  test "existing pairs are listed with what was found", %{conn: conn, a: a, b: b} do
    {:ok, link} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.set_status(link, "linked", %{summary: "Beta answers Alpha."})

    {:ok, _view, html} = live(conn, ~p"/links")

    assert html =~ "Alpha draft"
    assert html =~ "Beta answers Alpha."
    assert html =~ "1 linked"
  end

  test "a pair still being worked on says so", %{conn: conn, a: a, b: b} do
    {:ok, link} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.set_status(link, "linking")

    {:ok, _view, html} = live(conn, ~p"/links")
    assert html =~ "linking"
  end

  test "someone else's links are not listed", %{conn: conn, a: a, b: b} do
    theirs = user_fixture()

    {:ok, x} =
      Works.create_work(theirs.id, %{
        "title" => "Theirs one",
        "body" => String.duplicate("word ", 300)
      })

    {:ok, y} =
      Works.create_work(theirs.id, %{
        "title" => "Theirs two",
        "body" => String.duplicate("word ", 300)
      })

    {:ok, _} = Links.get_or_create(x.id, y.id)
    {:ok, mine} = Links.get_or_create(a.id, b.id)

    {:ok, _view, html} = live(conn, ~p"/links")

    refute html =~ "Theirs one"
    assert html =~ "Alpha draft"
    assert length(Links.for_user(a.user_id)) == 1
    assert hd(Links.for_user(a.user_id)).id == mine.id
  end

  test "changing a pick patches the form instead of growing another one", %{conn: conn, a: a} do
    # it was two forms, one per select, neither with an id — so every change
    # appended a fresh copy and the row filled up with dead dropdowns
    {:ok, view, html} = live(conn, ~p"/links")
    assert count(html, "<select") == 2

    html = render_change(view, "pick", %{"a" => to_string(a.id), "b" => ""})
    assert count(html, "<select") == 2

    html = render_change(view, "pick", %{"a" => "", "b" => to_string(a.id)})
    assert count(html, "<select") == 2
  end

  defp count(html, needle), do: length(String.split(html, needle)) - 1
end
