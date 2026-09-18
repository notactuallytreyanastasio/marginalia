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

      # both maps and the pairs being tried between them
      assert html =~ ~s(id="wiring")
      assert html =~ "possible pairs"
      # and it is honest that the arcs are attempts, not findings
      assert html =~ "The nodes are yours."
      refute html =~ ~s(id="split")
    end

    test "the follow view says so too, and subscribes", %{conn: conn, link: link, a: a} do
      {:ok, view, html} = live(conn, ~p"/links/#{link.id}/read?lead=#{a.slug}")
      assert html =~ ~s(id="wiring")

      # when the pass lands, the page fills in without a reload
      {:ok, _} = Links.set_status(link, "linked", %{summary: "They are related."})
      send(view.pid, {:link, :done})

      html = render(view)
      refute html =~ ~s(id="wiring")
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

  describe "the tour on the follow view" do
    setup %{a: a, b: b} do
      {:ok, link} = Links.get_or_create(a.id, b.id)
      {:ok, link} = Links.set_status(link, "linked", %{summary: "They talk."})
      %{link: link}
    end

    test "a first visit is told how to work the page", %{conn: conn, link: link} do
      {:ok, _view, html} = live(conn, ~p"/links/#{link.id}/read")

      assert html =~ "Two documents, read as one"
      assert html =~ "The left is what you are reading"
    end

    test "it is marked seen on sight, so it does not come back", %{
      conn: conn,
      link: link,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/links/#{link.id}/read")
      assert "follow" in Marginalia.Repo.reload!(user).seen_tours

      refute render_click(view, "dismiss_tour", %{}) =~ "Two documents, read as one"

      {:ok, _view, html} = live(conn, ~p"/links/#{link.id}/read")
      refute html =~ "Two documents, read as one"
    end

    test "the ? in the bar brings it back", %{conn: conn, link: link} do
      {:ok, view, _html} = live(conn, ~p"/links/#{link.id}/read")
      render_click(view, "dismiss_tour", %{})

      assert view |> element("button.fl-help") |> render_click() =~ "Two documents, read as one"
    end
  end

  describe "the split view is gone" do
    test "its module no longer exists" do
      refute Code.ensure_loaded?(MarginaliaWeb.LinkLive.Show)
    end

    test "/links/:id serves the follow view, and /read still works", %{conn: conn, a: a, b: b} do
      {:ok, link} = Links.get_or_create(a.id, b.id)
      {:ok, _} = Links.set_status(link, "linked", %{summary: "Related."})

      for path <- ["/links/#{link.id}", "/links/#{link.id}/read"] do
        {:ok, _view, html} = live(conn, path)
        assert html =~ ~s(id="follow"), "#{path} did not render the follow view"
        refute html =~ ~s(id="split")
      end
    end

    test "nothing offers a Split tab any more", %{conn: conn, a: a, b: b} do
      {:ok, link} = Links.get_or_create(a.id, b.id)
      {:ok, _} = Links.set_status(link, "linked", %{summary: "Related."})

      {:ok, _view, html} = live(conn, ~p"/links/#{link.id}")
      refute html =~ ">Split<"
    end
  end

  describe "one draft, several references" do
    setup %{conn: conn, a: a, b: b, user: user} do
      {:ok, c} =
        Works.create_work(user.id, %{
          "title" => "Third draft",
          "body" =>
            "# Third\n\nA sentence that is long enough.\n\n" <> String.duplicate("word ", 200)
        })

      {:ok, c} = Works.set_status(c, "read")
      {:ok, one} = Links.get_or_create(a.id, b.id)
      {:ok, one} = Links.set_status(one, "linked", %{summary: "B answers A."})
      {:ok, two} = Links.get_or_create(a.id, c.id)
      {:ok, two} = Links.set_status(two, "linked", %{summary: "C develops A."})

      %{conn: conn, a: a, b: b, c: c, one: one, two: two}
    end

    test "the draft lists every one of them", %{conn: conn, a: a} do
      {:ok, _view, html} = live(conn, ~p"/works/#{a.slug}?view=read")

      assert html =~ "read alongside"
      assert html =~ "Second draft"
      assert html =~ "Third draft"
    end

    test "the reference can be swapped without leaving the page", %{
      conn: conn,
      a: a,
      one: one,
      two: two
    } do
      {:ok, view, html} = live(conn, ~p"/links/#{one.id}?lead=#{a.slug}")

      # the other one is offered
      assert html =~ "Third draft"

      # and patching to it actually swaps the pair. `@link` was only set in
      # mount, so a patch to another :id would have kept the old pair and
      # shown the wrong document under the right title.
      assert html =~ ~s(<span class="t">Second draft</span>)

      html = render_patch(view, ~p"/links/#{two.id}?lead=#{a.slug}")
      assert html =~ ~s(<span class="t">Third draft</span>)
      # the account of the relationship swapped with it
      assert html =~ "C develops A."
      refute html =~ "B answers A."
    end

    test "a draft with one link gets no switcher", %{conn: conn, b: b, one: one} do
      {:ok, _view, html} = live(conn, ~p"/links/#{one.id}?lead=#{b.slug}")
      refute html =~ "fl-pick"
    end
  end
end
