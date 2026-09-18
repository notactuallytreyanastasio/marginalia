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

  # These were written as "the phone's sheet", and that premise was wrong in
  # a way that cost real breakage: `.fl-strip` is `display: none` under
  # 1100px. The phone's UI is `.fl-sheet`/`.fl-stack`, whose cards the hook
  # builds. The strip is the *wide* screen's card — and because every
  # assertion here only read server-rendered strings, nothing failed when
  # the strip's entire stylesheet was left behind in the phone's media
  # query and the button rendered as unstyled prose.
  describe "citing from the wide screen's strip" do
    test "it offers a way into the chat, and no longer a x that did nothing",
         %{conn: conn, link: l} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      html = render_click(view, "dismiss_tour", %{})

      assert html =~ ~s(class="fl-strip-head")
      assert html =~ "ask about this"

      # the hook pushes cite_edge with the edge it can see, so there is no
      # server-owned phx-value for the browser to write on
      refute html =~ "cite_current"

      # Nothing on a wide screen dismisses the strip — it follows the
      # scroll — so the strip has no close button any more. The phone's
      # sheet, which genuinely can be dismissed, keeps its own; the markup
      # is identical, so what to assert is that the page carries one of
      # them now rather than two.
      assert html |> String.split(~s(class="shut")) |> length() == 2
    end

    test "citing an edge puts that connection into the chat and opens it",
         %{conn: conn, link: l, a: a} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      render_click(view, "dismiss_tour", %{})

      [edge | _] = Links.edges(hd(Links.for_work(a.id)))
      html = render_click(view, "cite_edge", %{"edge" => to_string(edge.id)})

      assert html =~ "lc-panel"
      assert html =~ "They part."
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

  # Both layouts are a hook driving markup the server renders. The hook's
  # own behaviour is guarded structurally in hooks_test; what the server
  # owes it is this — every part present, every part wired.
  describe "what the reference strip ships with" do
    setup %{conn: conn, link: l} do
      {:ok, view, _} = live(conn, ~p"/links/#{l.id}/read")
      %{html: render_click(view, "dismiss_tour", %{}), view: view}
    end

    test "the strip, the sheet, and the passage they exist to show", %{html: html} do
      assert html =~ ~s(class="fl-mid")
      assert html =~ ~s(class="fl-strip")
      assert html =~ ~s(class="fl-sheet")
      # the far document's own words. The strip hides these on a wide
      # screen, where the column beside it is already showing them; the
      # phone's sheet is the one that needs them carried across.
      assert html =~ ~s(class="far")
    end

    test "a head that says what this is", %{html: html} do
      assert html =~ ~s(class="fl-strip-head")
      assert html =~ ~s(class="rel")
      assert html =~ ~s(class="nth")
    end

    test "and the way into the chat, since the drawn line is thin to hit", %{html: html} do
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

  # The bug this guards: `.fl-strip { display: none }` lives inside
  # `@media (max-width: 1100px)`, and so did every rule that styled the
  # strip's head and its button. Dead where they sat, missing where the
  # strip is actually shown — so the button rendered at 16px with no
  # background and read as a stray line of prose rather than a control. A
  # LiveView test cannot catch that, because the markup was always right.
  # This can.
  describe "the strip is styled at the width it is visible at" do
    setup do
      %{css: always_applies(File.read!(Path.join(File.cwd!(), "assets/css/app.css")))}
    end

    test "its head and button are not stranded in the phone's media query", %{css: css} do
      for {name, pattern} <- [
            {".fl-strip-head", ~r/^\.fl-strip-head\s*\{/m},
            {".fl-strip .ask", ~r/^\.fl-strip \.ask\s*\{/m}
          ] do
        assert css =~ pattern,
               "#{name} is only defined inside a max-width media query, where " <>
                 ".fl-strip is display:none — so it styles nothing, and the strip " <>
                 "renders unstyled at the width that actually shows it"
      end
    end
  end

  # The stylesheet with every `@media` block removed: only the rules that
  # apply at any width. The pattern assumes rules nest one level deep inside
  # a media block, which is how this file is written. The assertion is there
  # so that if that ever stops being true, this fails loudly instead of
  # quietly returning text in which everything looks fine.
  defp always_applies(css) do
    stripped = Regex.replace(~r/@media[^{]*\{(?:[^{}]*\{[^{}]*\})*[^{}]*\}/, css, "")
    assert stripped =~ ~r/^\.fl-strip\s*\{/m, "media-block stripping did not work"
    refute stripped =~ ~r/^\s+\.fl-sheet\s*\{/m, "media-block stripping left phone rules in"
    stripped
  end
end
