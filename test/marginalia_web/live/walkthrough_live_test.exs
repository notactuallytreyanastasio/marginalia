defmodule MarginaliaWeb.WalkthroughLiveTest do
  @moduledoc """
  The walkthrough presses the real controls, so it goes through the real
  handlers. These are the guards that make that safe on somebody's actual
  manuscript: no row written, no model called, and the draft byte-identical
  at the end.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures
  import Ecto.Query

  alias Marginalia.{Works, Repo}
  alias Marginalia.Chat.{Conversation, Message}

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

  # `mount` creates the chat drawer's own conversation for every visit, which
  # has nothing to do with the walkthrough — so what is counted here is
  # threads pinned to a paragraph, which is the only kind the tour opens.
  defp threads(work),
    do:
      Repo.aggregate(
        from(c in Conversation, where: c.work_id == ^work.id and not is_nil(c.block_ref)),
        :count
      )

  defp counts(work),
    do: %{
      threads: threads(work),
      messages: Repo.aggregate(from(m in Message), :count),
      body: Repo.reload!(work).body
    }

  defp first_ref(view) do
    [_, ref] = Regex.run(~r/id="block-([^"]+)"/, render(view))
    ref
  end

  test "the walkthrough writes nothing at all", %{conn: conn, work: work, section: section} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    render_click(view, "start_walk", %{})
    ref = first_ref(view)

    before = counts(work)

    # every step of the read walkthrough that touches a write path
    render_click(view, "open_thread", %{"ref" => ref, "section" => to_string(section.id)})
    render_submit(view, "thread_send", %{"message" => "What is this paragraph doing?"})
    render_click(view, "suggest_rewrite", %{"text" => "The kettle went cold on the counter"})
    render_click(view, "edit_block", %{"ref" => ref})
    render_submit(view, "save_block", %{"text" => "A completely different paragraph."})

    assert counts(work) == before
  end

  test "the thread it opens is never inserted", %{conn: conn, work: work, section: section} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    render_click(view, "start_walk", %{})
    ref = first_ref(view)

    html = render_click(view, "open_thread", %{"ref" => ref, "section" => to_string(section.id)})

    # it really is on screen — the point is that it works, not that it is skipped
    assert html =~ "mg-thread-panel"
    assert threads(work) == 0
  end

  test "the answer is the fixture, and it arrives", %{conn: conn, work: work, section: section} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    render_click(view, "start_walk", %{})
    ref = first_ref(view)

    render_click(view, "open_thread", %{"ref" => ref, "section" => to_string(section.id)})
    render_submit(view, "thread_send", %{"message" => "What is this paragraph doing?"})

    # the delay is real, so wait for the message the same way the browser does
    assert render(view) =~ "What is this paragraph doing?"
    Process.sleep(1_400)
    html = render(view)

    assert html =~ "never calls the model"
    assert Repo.aggregate(from(m in Message), :count) == 0
  end

  test "saving during the tour says so instead of doing it", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    render_click(view, "start_walk", %{})
    ref = first_ref(view)

    render_click(view, "edit_block", %{"ref" => ref})
    html = render_submit(view, "save_block", %{"text" => "Replaced."})

    assert html =~ "Nothing was saved"
    refute Repo.reload!(work).body =~ "Replaced."
  end

  test "outside the tour the same events still write", %{conn: conn, work: work, section: section} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    ref = first_ref(view)

    # no start_walk: this is the ordinary path, and it must be untouched
    render_click(view, "open_thread", %{"ref" => ref, "section" => to_string(section.id)})
    assert threads(work) == 1

    render_click(view, "edit_block", %{"ref" => ref})
    render_submit(view, "save_block", %{"text" => "Genuinely replaced."})
    assert Repo.reload!(work).body =~ "Genuinely replaced."
  end

  test "ending it clears everything the tour put on the page", %{
    conn: conn,
    work: work,
    section: section
  } do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    render_click(view, "start_walk", %{})
    ref = first_ref(view)

    render_click(view, "open_thread", %{"ref" => ref, "section" => to_string(section.id)})
    render_click(view, "edit_block", %{"ref" => ref})
    assert render(view) =~ "mg-thread-panel"

    html = render_click(view, "end_walk", %{})

    refute html =~ "mg-thread-panel"
    refute html =~ "mg-rewrite"
    refute html =~ ~s(class="mg-edit")
    refute html =~ ~s(id="walk")
  end

  test "demo mode never grants a permission the reader does not have", %{
    work: work,
    section: section
  } do
    # a guest on someone else's draft: the walkthrough stubs the model, it
    # does not turn a reader into an editor
    other = log_in_user(Phoenix.ConnTest.build_conn(), user_fixture())
    {:ok, view, _} = live(other, ~p"/works/#{work.slug}?view=read")
    render_click(view, "start_walk", %{})
    ref = first_ref(view)

    render_click(view, "open_thread", %{"ref" => ref, "section" => to_string(section.id)})
    render_click(view, "suggest_rewrite", %{"text" => "The kettle went cold on the counter"})
    html = render(view)

    refute html =~ "mg-rewrite"
    assert html =~ "someone else"

    render_click(view, "edit_block", %{"ref" => ref})
    refute render(view) =~ ~s(class="mg-edit")
  end

  test "a guest's walkthrough leaves out the steps they cannot use", %{work: work} do
    other = log_in_user(Phoenix.ConnTest.build_conn(), user_fixture())
    {:ok, view, _} = live(other, ~p"/works/#{work.slug}?view=read")
    html = render_click(view, "start_walk", %{})

    assert html =~ "A thread pinned to one paragraph"
    refute html =~ "Then answer it in your own words"
  end

  test "the overlay carries the steps, and says it is safe", %{conn: conn, work: work} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")
    html = render_click(view, "start_walk", %{})

    assert html =~ ~s(id="walk")
    assert html =~ "Nothing here is saved"
    assert html =~ "The notes sit beside the line"
  end
end
