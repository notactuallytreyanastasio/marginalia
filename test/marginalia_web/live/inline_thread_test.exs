defmodule MarginaliaWeb.InlineThreadTest do
  @moduledoc """
  A conversation pinned to one paragraph, opened where that paragraph is.
  The property that makes it a margin rather than a text box: come back to
  the same paragraph and the same thread is still there.
  """
  # not async: the composer only renders with a key configured, which is
  # global config
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Chat, Works}

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
    section = hd(Works.list_sections(work.id))

    %{conn: log_in_user(conn, user), work: work, section: section, user: user}
  end

  defp open(view, ref, section), do: render_click(view, "open_thread", %{"ref" => ref, "section" => section.id})

  test "every block offers a thread, silently until you go near it", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")

    assert html =~ ~s(class="mg-tick")
    assert html =~ ~s(phx-click="open_thread")
    # the affordance is per block, so there is one per paragraph
    assert html |> String.split(~s(phx-click="open_thread")) |> length() > 3
  end

  test "opening one shows it under that paragraph and nowhere else",
       %{conn: conn, work: work, section: s} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    html = open(view, "s1p2", s)
    assert html =~ "on this paragraph"
    assert html =~ "What about this paragraph?"
    assert html =~ ~s(id="block-s1p2")

    # exactly one panel is open
    assert html |> String.split("mg-thread-panel") |> length() == 2
  end

  test "coming back to the same paragraph returns to the same thread",
       %{conn: conn, work: work, section: s} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    open(view, "s1p2", s)
    [first] = Chat.threads_by_block(work.id) |> Map.values()

    render_click(view, "close_thread", %{})
    open(view, "s1p2", s)

    threads = Chat.threads_by_block(work.id)
    assert map_size(threads) == 1, "a second thread must not appear beside the first"
    assert threads["s1p2"].id == first.id
  end

  test "a different paragraph gets its own thread", %{conn: conn, work: work, section: s} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    open(view, "s1p1", s)
    open(view, "s1p2", s)

    assert map_size(Chat.threads_by_block(work.id)) == 2
  end

  test "a selection pins the thread to the passage, not just the paragraph",
       %{conn: conn, work: work, section: s} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    html =
      render_click(view, "open_thread", %{
        "ref" => "s1p2",
        "section" => s.id,
        "quote" => "The kettle went cold on the counter"
      })

    assert html =~ "on this passage"
    assert html =~ "The kettle went cold on the counter"
    assert Chat.threads_by_block(work.id)["s1p2"].quote == "The kettle went cold on the counter"
  end

  test "the tick carries the thread's message count", %{conn: conn, work: work, section: s} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    open(view, "s1p2", s)

    thread = Chat.threads_by_block(work.id)["s1p2"]
    Chat.append(thread.id, "user", "what is this doing")
    Chat.append(thread.id, "assistant", "holding the room still")

    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    assert html =~ "2 in this thread"
    assert html =~ "has-thread"
  end

  test "a thread can be settled and reopened", %{conn: conn, work: work, section: s} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    open(view, "s1p2", s)
    thread = Chat.threads_by_block(work.id)["s1p2"]
    Chat.append(thread.id, "user", "said something")
    open(view, "s1p2", s)

    assert render_click(view, "resolve_thread", %{}) =~ "settled"
    assert Chat.threads_by_block(work.id)["s1p2"].resolved

    render_click(view, "resolve_thread", %{})
    refute Chat.threads_by_block(work.id)["s1p2"].resolved
  end

  test "pinned threads stay out of the drawer's strip", %{conn: conn, work: work, section: s} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    open(view, "s1p2", s)

    # the drawer lists whole-draft conversations only
    assert Enum.all?(Chat.list_conversations(work.id), &(&1.anchor_kind == "work"))
    assert Enum.all?(Chat.conversation_summaries(work.id), &is_map/1)
  end

  test "a link-holder can read a thread but not add to it", %{conn: conn, work: work, section: s} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    open(view, "s1p2", s)
    thread = Chat.threads_by_block(work.id)["s1p2"]
    Chat.append(thread.id, "user", "the owner said this")

    visitor = get(build_conn(), ~p"/works")
    {:ok, vview, _} = live(visitor, ~p"/works/#{work.slug}?view=read")
    html = render_click(vview, "open_thread", %{"ref" => "s1p2", "section" => s.id})

    assert html =~ "the owner said this"
    refute html =~ "What about this paragraph?"

    render_click(vview, "thread_send", %{"message" => "let me in"})
    assert Chat.history(thread.id) |> length() == 1
  end
end
