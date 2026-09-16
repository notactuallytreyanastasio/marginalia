defmodule MarginaliaWeb.WorkTraceTest do
  @moduledoc """
  The Trace tab. A build that cannot be inspected has to be taken on faith,
  which is the opposite of what this product sells.
  """
  use MarginaliaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    # the trace is owner-only now
    user = owner_fixture()
    body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)
    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")

    %{conn: log_in_user(conn, user), work: work, user: user}
  end

  test "shows each tool call and flags the refusals", %{conn: conn, work: work} do
    Works.record_event(%{
      work_id: work.id,
      narrative: "The Window",
      seq: 0,
      tool: "add_node",
      args: ~s({"type":"goal","title":"Establish the watcher"}),
      result: ~s({"id":1}),
      ok: true
    })

    Works.record_event(%{
      work_id: work.id,
      narrative: "The Window",
      seq: 1,
      tool: "link",
      args: ~s({"from":1,"to":2}),
      result: ~s({"error":"goal -> decision is the flow rule"}),
      ok: false
    })

    {:ok, view, _html} = live(conn, ~p"/works/#{work.slug}?view=trace")
    html = render(view)

    assert html =~ "Establish the watcher"
    assert html =~ "The Window"
    assert html =~ "2 tool calls"
    assert html =~ "1 refused"
    # the reason is shown, not just the fact of a refusal
    assert html =~ "flow rule"
  end

  test "says so plainly when nothing has been built yet", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=trace")
    assert html =~ "Nothing recorded yet"
  end

  test "the trace is the owner's alone, unlike the graph", %{conn: conn, work: work} do
    # the link carries permission to read the draft, not to see how it was built
    other = log_in_user(build_conn(), user_fixture())
    assert text_response(get(other, ~p"/works/#{work.slug}/trace.json"), 404)

    assert json_response_body(get(conn, ~p"/works/#{work.slug}/trace.json")) =~ "\"events\""
    assert text_response(get(conn, ~p"/works/#{work.id}/trace.json"), 404)
  end

  # the same bug the trace tab had: a tab reached by URL rather than by click
  test "the graph tab fills in when reached by a direct link", %{conn: conn, work: work} do
    {:ok, node} =
      Works.insert_node(%{
        work_id: work.id,
        node_type: "goal",
        title: "The watcher at the window",
        narrative: "n"
      })

    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=graph")
    assert html =~ "data-graph"
    assert html =~ "The watcher at the window"
    assert html =~ "1 nodes"
    assert node.id
  end

  describe "a read that produced nothing" do
    test "offers a retry, and the retry starts from clean", %{conn: conn, work: work} do
      {:ok, work} = Works.set_status(work, "read")

      {:ok, view, html} = live(conn, ~p"/works/#{work.slug}")
      assert html =~ "Read again"

      # leftovers from the failed run must not survive into the retry
      {:ok, _} =
        Works.insert_node(%{work_id: work.id, node_type: "beat", title: "half-written", narrative: "n"})

      Works.record_event(%{work_id: work.id, tool: "add_node", ok: true})

      render_click(view, "start_read")

      assert Works.list_nodes(work.id) == []
      assert Works.list_events(work.id) == []
    end

    test "a read with beats in it offers no retry", %{conn: conn, work: work} do
      {:ok, work} = Works.set_status(work, "read")

      {:ok, _} =
        Works.insert_node(%{work_id: work.id, node_type: "beat", title: "a real beat", narrative: "n"})

      {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}")
      refute html =~ "Read again"
    end
  end

  defp json_response_body(conn), do: conn.resp_body
end
