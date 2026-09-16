defmodule MarginaliaWeb.ReadViewTest do
  @moduledoc """
  The page view, and the thing it exists for: clicking a note opens the chat
  already holding that note and the sections it touches.
  """
  # not async: the composer, and so the holding card, only render when a key
  # is configured, and that is global config
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    previous = Application.get_env(:marginalia, :deepseek_api_key)
    Application.put_env(:marginalia, :deepseek_api_key, "test-key")
    on_exit(fn -> Application.put_env(:marginalia, :deepseek_api_key, previous) end)

    user = user_fixture()

    body =
      "# A draft\n\nShe had been standing at the window for an hour before anyone noticed.\n\n" <>
        "The kettle went cold on the counter, and nobody moved to fill it again.\n\n" <>
        String.duplicate("word ", 260)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")
    s = hd(Works.list_sections(work.id))

    {:ok, beat} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: s.id,
        node_type: "beat",
        title: "The kettle goes cold",
        body: "Nothing moves and the reader feels it.",
        quote: "The kettle went cold on the counter"
      })

    %{conn: log_in_user(conn, user), work: work, beat: beat, section: s}
  end

  test "the draft is shown with the note beside its own paragraph", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")

    assert html =~ "The kettle went cold on the counter"
    assert html =~ "The kettle goes cold"
    # the anchored span is marked, and carries the id its margin note points at
    assert html =~ ~s(id="anchor-s1p)
    assert html =~ "The kettle went cold on the counter</mark>"
  end

  test "clicking a note opens the chat holding it — and it stays open",
       %{conn: conn, work: work, beat: beat} do
    {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}?view=read")

    html = render_click(view, "discuss", %{"key" => "beat:#{beat.id}"})

    assert html =~ "holding"
    assert html =~ "The kettle goes cold"
    # the patch must carry chat=1, or handle_params closes it again
    assert_patch(view) =~ "chat=1"
    assert render(view) =~ "holding"
  end

  test "dropping the focus leaves the chat open", %{conn: conn, work: work, beat: beat} do
    {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}?view=read")
    render_click(view, "discuss", %{"key" => "beat:#{beat.id}"})

    html = render_click(view, "clear_focus", %{})
    refute html =~ "holding"
    assert html =~ "Talk about it"
  end

  test "it opens on everything, with no filter applied", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")

    # Everything is the tab lit on arrival
    assert html =~ ~s(class="mg-tab on" phx-click="set_only" phx-value-only="all")
    refute html =~ ~s(class="mg-tab on" phx-click="set_only" phx-value-only="beats")

    # and the margin carries both passes at once, not just the beats
    assert html =~ "The kettle goes cold"
    assert html =~ "tension"
  end

  test "trimming to tensions hides the beats", %{conn: conn, work: work} do
    {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}?view=read")

    html = render_click(view, "set_only", %{"only" => "tensions"})
    refute html =~ "The kettle goes cold"
    # the prose is still there; only the notes were trimmed
    assert html =~ "The kettle went cold on the counter"
  end

  test "a bad key is ignored rather than crashing", %{conn: conn, work: work} do
    {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}?view=read")
    assert render_click(view, "discuss", %{"key" => "beat:0"})
  end
end
