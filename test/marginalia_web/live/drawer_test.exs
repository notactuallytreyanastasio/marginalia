defmodule MarginaliaWeb.DrawerTest do
  @moduledoc """
  The chat as a drawer: many threads, and passages pulled out of the page and
  carried into the next question.
  """
  # not async: the composer only renders when a key is configured, and that
  # is global config
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
    %{conn: log_in_user(conn, user), work: work, user: user}
  end

  describe "many threads" do
    test "a new thread starts empty and becomes the one you are in", %{conn: conn, work: work} do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")
      {:ok, first} = Chat.get_or_create_conversation(work.id)
      Chat.append(first.id, "user", "the first question I asked")

      html = render_click(view, "new_chat", %{})

      # the transcript is empty, but the old thread is still on the strip,
      # named after the question that started it
      assert html =~ ~s(class="mg-thread on")
      assert html =~ "the first question I asked"
      assert html =~ "What is actually on the page"
      assert length(Chat.list_conversations(work.id)) == 2
    end

    test "switching back brings its history with it", %{conn: conn, work: work} do
      {:ok, a} = Chat.get_or_create_conversation(work.id)
      Chat.append(a.id, "user", "about the kettle")
      Chat.append(a.id, "assistant", "the kettle is doing a lot of work")

      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")
      render_click(view, "new_chat", %{})
      # gone from the transcript; the strip still lists the thread it is in
      refute render(view) =~ "the kettle is doing a lot of work"

      html = render_click(view, "switch_chat", %{"id" => a.id})
      assert html =~ "the kettle is doing a lot of work"
    end

    test "a thread is named after the question that started it", %{work: work} do
      {:ok, a} = Chat.get_or_create_conversation(work.id)
      Chat.append(a.id, "user", "why does the prologue exist")

      assert [%{title: "why does the prologue exist", messages: 1}] =
               Chat.conversation_summaries(work.id)
    end

    test "deleting the thread you are in lands you in another", %{conn: conn, work: work} do
      {:ok, a} = Chat.get_or_create_conversation(work.id)
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")
      render_click(view, "new_chat", %{})
      assert length(Chat.list_conversations(work.id)) == 2

      [newest | _] = Chat.list_conversations(work.id)
      render_click(view, "delete_chat", %{"id" => newest.id})

      assert [remaining] = Chat.list_conversations(work.id)
      assert remaining.id == a.id
    end

    test "a thread from another draft cannot be switched to", %{conn: conn, work: work, user: user} do
      {:ok, other} = Works.create_work(user.id, %{"title" => "Other", "body" => String.duplicate("w ", 300)})
      {:ok, theirs} = Chat.get_or_create_conversation(other.id)

      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")
      render_click(view, "switch_chat", %{"id" => theirs.id})

      refute Chat.get_conversation(work.id, theirs.id)
    end
  end

  describe "carrying a passage into the question" do
    test "a real selection is kept, verbatim from the draft", %{conn: conn, work: work} do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")

      html = render_click(view, "add_context", %{"text" => "  The kettle went cold on the counter "})

      assert html =~ "Carrying 1 passage"
      assert html =~ "The kettle went cold on the counter"
    end

    test "a selection that is not in the draft is refused", %{conn: conn, work: work} do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")

      html = render_click(view, "add_context", %{"text" => "a sentence the writer never wrote"})
      refute html =~ "Carrying"
    end

    test "a stray click adds nothing", %{conn: conn, work: work} do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")
      refute render_click(view, "add_context", %{"text" => "the"}) =~ "Carrying"
    end

    test "the same passage twice is carried once", %{conn: conn, work: work} do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")
      render_click(view, "add_context", %{"text" => "The kettle went cold on the counter"})
      html = render_click(view, "add_context", %{"text" => "The kettle went cold on the counter"})

      assert html =~ "Carrying 1 passage"
    end

    test "it can be dropped again", %{conn: conn, work: work} do
      {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?chat=1")
      render_click(view, "add_context", %{"text" => "The kettle went cold on the counter"})

      html = render_click(view, "drop_context", %{"i" => "0"})
      refute html =~ "Carrying"
    end
  end
end
