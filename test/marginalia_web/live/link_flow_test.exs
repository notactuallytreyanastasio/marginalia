defmodule MarginaliaWeb.LinkFlowTest do
  @moduledoc """
  Starting a link from a draft: who is offered, what one click does, and the
  page you land on while the pass is still running.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Works}

  setup %{conn: conn} do
    # `link_to` starts the pass in a detached task, so that task needs the
    # sandbox connection too — otherwise it dies mid-update and takes the
    # test's connection with it.
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    # and no key, so the pass fails immediately rather than reaching for the
    # network: what is under test is the flow, not the model
    previous = Application.get_env(:marginalia, :deepseek_api_key)
    Application.put_env(:marginalia, :deepseek_api_key, nil)
    on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)

    user = user_fixture()

    make = fn title, status ->
      body =
        "# #{title}\n\nA sentence long enough to be a section here.\n\n" <>
          String.duplicate("word ", 200)

      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, status)
      w
    end

    %{
      conn: log_in_user(conn, user),
      user: user,
      a: make.("First draft", "read"),
      b: make.("Second draft", "read"),
      unread: make.("Still reading", "reading")
    }
  end

  test "the control offers the other drafts that have been read", %{conn: conn, a: a} do
    {:ok, view, _} = live(conn, ~p"/works/#{a.slug}?view=read")
    html = render_click(view, "toggle_linking", %{})

    assert html =~ "Second draft"
    # a draft with no graph has nothing to relate, so it is not offered
    refute html =~ "Still reading"
    # and neither is this one
    refute html =~ ~s(phx-value-id="#{a.id}")
  end

  test "one click pairs them, starts the pass, and goes to the link", %{conn: conn, a: a, b: b} do
    {:ok, view, _} = live(conn, ~p"/works/#{a.slug}?view=read")
    render_click(view, "toggle_linking", %{})

    assert {:error, {:live_redirect, %{to: to}}} =
             render_click(view, "link_to", %{"id" => to_string(b.id)})

    link = Links.get_for(a.id, b.id)
    assert link, "the pair should have been created"
    assert to == "/links/#{link.id}?lead=#{a.slug}"
  end

  test "linking the same pair twice reuses the one link", %{a: a, b: b} do
    # the pair is unordered, so asking from either side is the same link
    {:ok, one} = Links.get_or_create(a.id, b.id)
    {:ok, two} = Links.get_or_create(b.id, a.id)

    assert one.id == two.id
    assert length(Links.for_work(a.id)) == 1
  end

  test "a draft belonging to someone else cannot be linked in", %{conn: conn, a: a} do
    theirs = user_fixture()

    {:ok, other} =
      Works.create_work(theirs.id, %{
        "title" => "Not yours",
        "body" => String.duplicate("word ", 300)
      })

    {:ok, other} = Works.set_status(other, "read")

    {:ok, view, _} = live(conn, ~p"/works/#{a.slug}?view=read")
    render_click(view, "toggle_linking", %{})
    html = render_click(view, "link_to", %{"id" => to_string(other.id)})

    assert html =~ "can&#39;t be linked" or html =~ "can't be linked"
    assert Links.for_work(a.id) == []
  end

  describe "the page you land on" do
    setup %{a: a, b: b} do
      {:ok, link} = Links.get_or_create(a.id, b.id)
      %{link: link}
    end

    test "says it is working while the pass runs", %{conn: conn, link: link} do
      {:ok, _view, html} = live(conn, ~p"/links/#{link.id}")
      assert html =~ "Relating the two maps"
      refute html =~ ~s(id="split")
    end

    test "the follow view says so too, and subscribes", %{conn: conn, link: link, a: a} do
      {:ok, view, html} = live(conn, ~p"/links/#{link.id}/read?lead=#{a.slug}")
      assert html =~ "Relating the two maps"

      # when the pass lands, the page fills in without a reload
      {:ok, _} = Links.set_status(link, "linked", %{summary: "They are related."})
      send(view.pid, {:link, :done})

      html = render(view)
      refute html =~ "Relating the two maps"
      assert html =~ ~s(id="follow")
    end

    test "a failure is shown with a way to retry", %{conn: conn, link: link} do
      {:ok, _} = Links.set_status(link, "failed", %{error: ":truncated"})
      {:ok, _view, html} = live(conn, ~p"/links/#{link.id}")

      assert html =~ "did not go through"
      assert html =~ ":truncated"
      assert html =~ "Try again"
    end
  end
end
