defmodule MarginaliaWeb.WorkUploadFallbackTest do
  @moduledoc """
  Uploading a draft when the live socket is not there.

  A writer had `/works/new` open in a tab. A deploy restarted the container
  at 19:23:18Z, their websocket died, and the longpoll fallback got
  `connection refused` from the proxy. Forty-five minutes later they pasted a
  draft and pressed Continue, and the browser did the only thing the markup
  told it to: a plain `POST /works/new`. Nothing answered that, so Phoenix
  raised NoRouteError and they got a 404 with the text gone. They tried four
  times.

  These are about that path working, and about the two things it needs to
  keep working: a route for the POST, and a CSRF token in the form that
  makes it.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    :ok
  end

  @draft """
  # One

  #{String.duplicate("word ", 200)}

  # Two

  #{String.duplicate("word ", 200)}
  """

  describe "the form the browser submits on its own" do
    test "carries an action and a CSRF token", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/works/new")

      [form] = Regex.run(~r{<form[^>]*phx-submit="save".*?</form>}s, html)

      assert form =~ ~s(action="/works/new"),
             "without an action the browser posts to whatever page it is on"

      assert form =~ ~s(name="_csrf_token"),
             "form/1 only emits the token when there is an action, and the " <>
               "POST is rejected without it"
    end
  end

  describe "POST /works/new" do
    test "saves the draft and goes to it, rather than 404ing", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = post(conn, ~p"/works/new", work: %{title: "Pasted", body: @draft, intent: ""})

      assert %{slug: slug} = Works.list_works(user.id) |> List.first()
      assert redirected_to(conn) == ~p"/works/#{slug}"

      # and the page it sends them to is really there
      assert conn |> recycle() |> get(~p"/works/#{slug}") |> html_response(200) =~ "Pasted"
    end

    test "a visitor with no account at all gets one on the way in", %{conn: conn} do
      conn = post(conn, ~p"/works/new", work: %{title: "Anon", body: @draft})

      assert %{id: slug} = redirected_params(conn)
      assert Works.get_by_slug(slug).title == "Anon"
    end

    test "an untitled draft still saves", %{conn: conn} do
      conn = post(conn, ~p"/works/new", work: %{title: "   ", body: @draft})

      assert Works.get_by_slug(redirected_params(conn).id).title == "Untitled draft"
    end
  end

  describe "when the plain POST cannot be saved" do
    test "an empty draft says so and says why a file did not arrive", %{conn: conn} do
      conn = post(conn, ~p"/works/new", work: %{title: "Nothing", body: "   "})

      html = html_response(conn, 422)
      assert html =~ "There&#39;s no text there yet"
      assert html =~ "Attaching a file needs JavaScript"
      refute html =~ "404"
    end

    test "the writer's text is still in the box", %{conn: conn} do
      long = String.duplicate("word ", Works.Upload.max_words() + 1)

      conn = post(conn, ~p"/works/new", work: %{title: "Too big", body: long, intent: "a test"})

      html = html_response(conn, 422)
      assert html =~ "and the limit is 120,000 for now"

      # the whole reason this path exists instead of a redirect
      assert html =~ ~s(value="Too big")
      assert html =~ "a test"
      assert String.contains?(html, String.duplicate("word ", 50))
    end

    test "nothing is written when the draft is rejected", %{conn: conn} do
      user = user_fixture()

      conn
      |> log_in_user(user)
      |> post(~p"/works/new", work: %{title: "Nope", body: ""})

      assert Works.list_works(user.id) == []
    end
  end

  describe "the two paths agree" do
    test "the LiveView and the plain POST reject the same draft", %{conn: conn} do
      over = String.duplicate("word ", Works.Upload.max_words() + 1)

      {:ok, view, _html} = live(conn, ~p"/works/new")

      live_error =
        view
        |> form("form[phx-submit=save]", work: %{title: "x", body: over})
        |> render_submit()

      posted = html_response(post(conn, ~p"/works/new", work: %{title: "x", body: over}), 422)

      assert live_error =~ "and the limit is 120,000 for now"
      assert posted =~ "and the limit is 120,000 for now"
    end
  end
end
