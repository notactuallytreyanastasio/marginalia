defmodule MarginaliaWeb.LinkChatFlowTest do
  @moduledoc """
  The chat on the pairwise reading: opening it, asking, and what comes
  back. There were tests for `Links.Chat` and none for the page it lives
  on, so "chat is broken" had nothing to fail against.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Works}
  alias Marginalia.Analysis.Linker

  @quote "A sentence long enough"

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    user = user_fixture()

    mk = fn title ->
      body = "# #{title}\n\n#{@quote} to be a section.\n\n" <> String.duplicate("word ", 200)
      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      s = hd(Works.list_sections(w.id))

      {:ok, n} =
        Works.insert_node(%{
          work_id: w.id,
          section_id: s.id,
          node_type: "beat",
          title: "a beat in #{title}",
          quote: @quote
        })

      {w, n}
    end

    {a, a_n} = mk.("First")
    {b, b_n} = mk.("Second")

    {:ok, l} = Links.get_or_create(a.id, b.id)
    {:ok, l} = Links.set_status(l, "linked", %{summary: "They disagree."})

    Links.store_edges(
      l,
      [%{"from" => a_n.id, "to" => b_n.id, "type" => "tension", "why" => "They part."}],
      Linker.types()
    )

    %{conn: log_in_user(conn, user), link: l, a: a}
  end

  # The tour card's veil covers the viewport above the bubble, so the
  # bubble was visible, unclickable, and silent about it.
  test "the bubble is not offered underneath the tour card", %{conn: conn, link: l} do
    {:ok, view, html} = live(conn, ~p"/links/#{l.id}/read")

    assert html =~ "fl-tour-veil", "the one-time card should be up on a first visit"
    refute html =~ "lc-bubble", "the chat bubble is under the veil and cannot be pressed"

    html = render_click(view, "dismiss_tour", %{})

    refute html =~ "fl-tour-veil"
    assert html =~ "lc-bubble"
  end

  test "the bubble is on the page and opens the panel", %{conn: conn, link: l} do
    {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
    html = render_click(view, "dismiss_tour", %{})

    assert html =~ ~s(phx-click="toggle_chat")
    refute html =~ ~s(class="lc-panel")

    html = view |> element("button.lc-bubble") |> render_click()

    assert html =~ ~s(class="lc-panel")
    assert html =~ ~s(phx-submit="chat_send")
  end

  test "asking shows the question and that it is thinking", %{conn: conn, link: l} do
    {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
    render_click(view, "dismiss_tour", %{})
    view |> element("button.lc-bubble") |> render_click()

    html =
      view
      |> form("form[phx-submit=chat_send]", %{"message" => "What is the disagreement?"})
      |> render_submit()

    assert html =~ "What is the disagreement?"
  end

  test "a failed answer says so rather than vanishing", %{conn: conn, link: l} do
    {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
    render_click(view, "dismiss_tour", %{})
    view |> element("button.lc-bubble") |> render_click()

    view
    |> form("form[phx-submit=chat_send]", %{"message" => "anything"})
    |> render_submit()

    # the endpoint in test goes nowhere, so this is the failure path
    html = render_async(view, 5_000)

    assert html =~ "What is the disagreement?" or html =~ "anything"
    refute html =~ "lc-thinking", "it is still claiming to be thinking"
  end

  # On a phone the drawn line is not there to click, so the sheet along
  # the bottom carries the way into the chat instead.
  describe "citing from the phone's sheet" do
    test "the sheet offers it, pointed at whatever it is showing", %{conn: conn, link: l} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      html = render_click(view, "dismiss_tour", %{})

      assert html =~ ~s(class="fl-strip-head")
      assert html =~ ~s(phx-click="cite_current")
    end

    test "it puts that connection into the chat and opens it", %{conn: conn, link: l, a: a} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      render_click(view, "dismiss_tour", %{})

      [edge | _] = Links.edges(hd(Links.for_work(a.id)))
      html = render_click(view, "cite_current", %{"edge" => to_string(edge.id)})

      assert html =~ "lc-panel"
      assert html =~ "They part."
    end

    test "with nothing showing it does nothing rather than crashing", %{conn: conn, link: l} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      render_click(view, "dismiss_tour", %{})

      refute render_click(view, "cite_current", %{}) =~ "lc-panel"
    end
  end

  describe "somewhere to start" do
    test "an empty chat offers questions rather than a blank box", %{conn: conn, link: l} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      render_click(view, "dismiss_tour", %{})
      html = view |> element("button.lc-bubble") |> render_click()

      assert html =~ ~s(class="lc-openers")
      assert html =~ "What does the second document already answer?"
    end

    test "tapping one asks it", %{conn: conn, link: l} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      render_click(view, "dismiss_tour", %{})
      view |> element("button.lc-bubble") |> render_click()

      html =
        view
        |> element(".lc-openers button", "Which connection is doing the most work?")
        |> render_click()

      assert html =~ "Which connection is doing the most work?"
      # and they go away once the conversation has started
      refute html =~ ~s(class="lc-openers")
    end
  end

  # The phone layout is a hook driving markup the server renders. The
  # hook's own behaviour is guarded structurally in hooks_test; what the
  # server owes it is this — every part present, every part wired.
  describe "what the phone's reference sheet ships with" do
    setup %{conn: conn, link: l} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      %{html: render_click(view, "dismiss_tour", %{}), view: view}
    end

    test "the sheet, and the passage it exists to show", %{html: html} do
      assert html =~ ~s(class="fl-mid")
      assert html =~ ~s(class="fl-strip")
      # the far document's own words: on a phone there is no column for
      # them, so the sheet carries them
      assert html =~ ~s(class="far")
    end

    test "a head that says what this is and how to leave", %{html: html} do
      assert html =~ ~s(class="fl-strip-head")
      assert html =~ ~s(class="rel")
      assert html =~ ~s(class="nth")
      assert html =~ ~s(class="shut")
    end

    test "and the way into the chat, since there is no line to click", %{html: html} do
      assert html =~ ~s(phx-click="cite_current")
      assert html =~ "ask about this"
    end

    test "the passages the hook needs to reach are addressable", %{html: html} do
      # the hook copies the far passage out of the reference column by id
      assert html =~ ~s(id="blk-other-)
      assert html =~ ~s(id="blk-lead-)
      # and finds what to show from the note data on each block
      assert html =~ "data-peer-ref="
      assert html =~ "data-edge="
    end

    test "both columns are rendered, even though one is not shown", %{html: html} do
      # the reference column stays in the DOM on a phone: the sheet reads
      # its text out of it. Hiding it with CSS is the point; removing it
      # would take the passage with it.
      assert html =~ ~s(id="fl-lead")
      assert html =~ ~s(id="fl-other")
    end
  end

  test "the panel closes again", %{conn: conn, link: l} do
    {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
    render_click(view, "dismiss_tour", %{})
    view |> element("button.lc-bubble") |> render_click()

    refute view |> element("button.lc-bubble") |> render_click() =~ ~s(class="lc-panel")
  end
end
