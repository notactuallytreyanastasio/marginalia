defmodule Marginalia.Analysis.DecisionGraphTest do
  @moduledoc """
  The decision-graph skill, as tool calls. Three of its rules are enforced in
  code rather than asked for in the prompt; these pin them.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.Analysis.DecisionGraph, as: DG
  alias Marginalia.Works
  import Marginalia.AccountsFixtures

  setup do
    user = user_fixture()

    body =
      "Chapter 1\n\n" <>
        "She had been standing at the window for an hour before anyone noticed. " <>
        String.duplicate("word ", 300)

    {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
    %{work: work, section: hd(Works.list_sections(work.id))}
  end

  # the tool loop is private, so drive it the way the model would
  defp call(state, name, args) do
    fun = %{"id" => "x", "function" => %{"name" => name, "arguments" => Jason.encode!(args)}}
    {msg, state} = :erlang.apply(DG, :execute, [fun, state])
    {Jason.decode!(msg["content"]), state}
  end

  defp state(work, section), do: %{work: work, narrative: "n", sections: [section], nodes: %{}}

  describe "the tool surface mirrors the deciduous CLI" do
    test "add_node, link and set_status are the three operations" do
      names = Enum.map(DG.tools(), & &1["function"]["name"]) |> Enum.sort()
      assert names == ["add_node", "link", "set_status"]
    end

    test "add_node offers exactly the decision-graph vocabulary" do
      add = Enum.find(DG.tools(), &(&1["function"]["name"] == "add_node"))
      types = add["function"]["parameters"]["properties"]["type"]["enum"]
      assert Enum.sort(types) == ~w(action decision goal observation option outcome revisit)
    end
  end

  describe "grounding is enforced at the tool boundary" do
    test "a fabricated quote is refused, and the model is told why", %{work: w, section: sec} do
      {result, st} =
        call(state(w, sec), "add_node", %{
          "type" => "observation",
          "title" => "invented",
          "narrative" => "n",
          "quote" => "She turned and left without saying anything at all."
        })

      assert result["error"] =~ "not found in the draft"
      assert result["hint"] =~ "Copy the span exactly"
      assert st.nodes == %{}, "the node must not be stored"
    end

    test "a real quote is accepted and rewritten to the source's wording", %{work: w, section: sec} do
      {result, st} =
        call(state(w, sec), "add_node", %{
          "type" => "observation",
          "title" => "real",
          "narrative" => "n",
          "quote" => "standing at the window for an hour"
        })

      assert result["id"]
      assert map_size(st.nodes) == 1
      node = Works.get_node(w.id, result["id"])
      assert String.contains?(sec.body, node.quote)
    end

    test "a structural node may omit a quote", %{work: w, section: sec} do
      {result, _st} =
        call(state(w, sec), "add_node", %{"type" => "goal", "title" => "the goal", "narrative" => "n"})

      assert result["id"]
    end
  end

  describe "the flow rule is enforced, not requested" do
    setup %{work: w, section: sec} do
      st = state(w, sec)
      {%{"id" => goal}, st} = call(st, "add_node", %{"type" => "goal", "title" => "g", "narrative" => "n"})
      {%{"id" => opt}, st} = call(st, "add_node", %{"type" => "option", "title" => "o", "narrative" => "n"})
      {%{"id" => dec}, st} = call(st, "add_node", %{"type" => "decision", "title" => "d", "narrative" => "n"})
      {%{"id" => act}, st} = call(st, "add_node", %{"type" => "action", "title" => "a", "narrative" => "n"})
      %{st: st, goal: goal, opt: opt, dec: dec, act: act}
    end

    test "goal -> decision is refused with the fix spelled out", %{st: st, goal: g, dec: d} do
      {result, _} = call(st, "link", %{"from" => g, "to" => d})
      assert result["error"] =~ "a goal cannot lead straight to a decision"
      assert result["error"] =~ "options"
    end

    test "goal -> option -> decision -> action is allowed", %{st: st, goal: g, opt: o, dec: d, act: a} do
      for {from, to} <- [{g, o}, {o, d}, {d, a}] do
        {result, _} = call(st, "link", %{"from" => from, "to" => to})
        assert result["linked"], "expected #{from} -> #{to} to be allowed, got #{inspect(result)}"
      end
    end

    test "a step that is not in the flow is refused and the legal ones named", %{st: st, act: a, opt: o} do
      {result, _} = call(st, "link", %{"from" => a, "to" => o})
      assert result["error"] =~ "not a step in goal -> option -> decision"
      assert is_list(result["allowed"])
    end

    test "a node id the model never created cannot be linked", %{st: st, goal: g} do
      {result, _} = call(st, "link", %{"from" => g, "to" => 999_999})
      assert result["error"] =~ "unknown node id"
    end
  end

  test "an option can be marked chosen or rejected", %{work: w, section: sec} do
    st = state(w, sec)
    {%{"id" => opt}, st} = call(st, "add_node", %{"type" => "option", "title" => "o", "narrative" => "n"})

    {result, _} = call(st, "set_status", %{"id" => opt, "status" => "rejected"})
    assert result["ok"]
    assert Works.get_node(w.id, opt).status == "rejected"
  end

  describe "the build trace" do
    setup %{work: work, section: section} do
      %{state: state(work, section)}
    end

    test "records the calls that succeeded", %{work: work, state: state} do
      {%{"id" => id}, state} =
        call(state, "add_node", %{
          "type" => "goal",
          "title" => "A goal",
          "narrative" => "n"
        })

      {_, _state} =
        call(state, "add_node", %{
          "type" => "option",
          "title" => "An option",
          "narrative" => "n",
          "quote" => "standing at the window for an hour"
        })

      events = Works.list_events(work.id)
      assert length(events) == 2
      assert Enum.all?(events, & &1.ok)
      assert Enum.map(events, & &1.tool) == ["add_node", "add_node"]
      assert Enum.map(events, & &1.seq) == [0, 1]
      assert hd(events).node_id == id
    end

    test "records a refused quote as a refusal, not a silent gap", %{work: work, state: state} do
      {%{"error" => _}, _} =
        call(state, "add_node", %{
          "type" => "action",
          "title" => "Invented",
          "narrative" => "n",
          "quote" => "a sentence the writer never wrote at all"
        })

      assert [event] = Works.list_events(work.id)
      refute event.ok
      assert event.result =~ "character for character"

      stats = Works.event_stats(work.id)
      assert stats.calls == 1
      assert stats.refused == 1
      assert stats.refusals["quote not in draft"] == 1
    end

    test "records a refused link and names the flow rule", %{work: work, state: state} do
      {%{"id" => goal}, state} =
        call(state, "add_node", %{"type" => "goal", "title" => "G", "narrative" => "n"})

      {%{"id" => decision}, state} =
        call(state, "add_node", %{"type" => "decision", "title" => "D", "narrative" => "n"})

      {%{"error" => _}, _} = call(state, "link", %{"from" => goal, "to" => decision})

      stats = Works.event_stats(work.id)
      assert stats.calls == 3
      assert stats.refused == 1
      assert stats.refusals["flow rule"] == 1
      assert stats.by_tool == %{"add_node" => 2, "link" => 1}
    end

    test "a rebuild clears the previous run's trace", %{work: work, state: state} do
      {_, _} = call(state, "add_node", %{"type" => "goal", "title" => "G", "narrative" => "n"})
      assert length(Works.list_events(work.id)) == 1

      Works.clear_events(work.id)
      assert Works.list_events(work.id) == []
      assert Works.event_stats(work.id).calls == 0
    end
  end


  describe "malformed tool calls" do
    setup %{work: work, section: section} do
      %{state: state(work, section)}
    end

    # a real run produced this three times: the title written under the node
    # type's own key instead of under "title"
    test "a title written under the type key is recovered", %{state: state} do
      {result, _} =
        call(state, "add_node", %{
          "type" => "action",
          "action" => "Name the method",
          "narrative" => "n"
        })

      assert result["added"] == "Name the method"
      assert result["type"] == "action"
    end

    test "a genuinely titleless node is still refused, and the error says what was sent",
         %{state: state} do
      {result, _} = call(state, "add_node", %{"type" => "action", "narrative" => "n"})

      assert result["error"] =~ "title"
      assert "type" in result["you_sent"]
    end

    test "an empty call does not recover a title from nowhere", %{state: state} do
      {result, _} = call(state, "add_node", %{})
      assert result["error"] =~ "can't be blank"
    end
  end


  describe "refusals are actionable" do
    setup %{work: work, section: section} do
      %{state: state(work, section)}
    end

    # the commonest illegal link in a real run
    test "a refused link names the legal one-hop route", %{state: state} do
      {%{"id" => outcome}, state} =
        call(state, "add_node", %{"type" => "outcome", "title" => "O", "narrative" => "n"})

      {%{"id" => action}, state} =
        call(state, "add_node", %{"type" => "action", "title" => "A", "narrative" => "n"})

      {result, _} = call(state, "link", %{"from" => outcome, "to" => action})

      assert result["error"] =~ "outcome -> action"
      assert result["route"] =~ "observation"
    end

    test "re-sending a refused call verbatim is called out, not re-run", %{state: state} do
      bad = %{"type" => "action", "title" => "X", "narrative" => "n", "quote" => "not in the draft at all"}

      {first, state} = call(state, "add_node", bad)
      assert first["error"] =~ "character for character"

      {second, _} = call(state, "add_node", bad)
      assert second["repeat"] == true
      assert second["error"] =~ "already sent this exact call"
    end

    test "a different call after a refusal still runs", %{work: work, state: state} do
      {_, state} =
        call(state, "add_node", %{"type" => "action", "title" => "X", "narrative" => "n", "quote" => "nope nope nope"})

      {ok, _} =
        call(state, "add_node", %{
          "type" => "action",
          "title" => "Y",
          "narrative" => "n",
          "quote" => "standing at the window for an hour"
        })

      assert ok["added"] == "Y"
      assert Works.event_stats(work.id).refused == 1
    end
  end


  describe "rebuilding replaces rather than stacks" do
    test "the previous decision graph is cleared, the read is not", %{work: work, section: section} do
      st = state(work, section)

      # a read, and a decision graph built on top of it
      {:ok, beat} =
        Works.insert_node(%{work_id: work.id, section_id: section.id, node_type: "beat", title: "a beat"})

      {:ok, spine} = Works.insert_node(%{work_id: work.id, node_type: "spine", title: "the trunk"})
      {%{"id" => goal}, st} = call(st, "add_node", %{"type" => "goal", "title" => "G", "narrative" => "n"})
      {%{"id" => opt}, st} = call(st, "add_node", %{"type" => "option", "title" => "O", "narrative" => "n"})
      {_, _} = call(st, "link", %{"from" => goal, "to" => opt})
      Works.link(work.id, beat.id, spine.id, "realises", 0, "why")

      assert {:ok, 2} = Works.reset_decision_graph(work.id)

      kept = Works.list_nodes(work.id) |> Enum.map(& &1.node_type) |> Enum.sort()
      assert kept == ["beat", "spine"]

      # the edge between two surviving nodes survives with them
      assert [%{edge_type: "realises"}] = Works.list_edges(work.id)
      assert Works.list_events(work.id) == []
    end

    test "clearing an empty graph is not an error", %{work: work} do
      assert {:ok, 0} = Works.reset_decision_graph(work.id)
    end
  end

  describe "narratives are not sealed islands" do
    test "a node from an earlier narrative can be linked to", %{work: work, section: section} do
      # narrative one
      st = state(work, section)
      {%{"id" => first}, st} =
        call(st, "add_node", %{"type" => "outcome", "title" => "Where one ended", "narrative" => "one"})

      carried = st.nodes

      # narrative two starts knowing what one built
      st2 = %{state(work, section) | narrative: "two", nodes: carried}

      {%{"id" => second}, st2} =
        call(st2, "add_node", %{"type" => "observation", "title" => "What two noticed", "narrative" => "two"})

      {result, _} =
        call(st2, "link", %{"from" => first, "to" => second, "rationale" => "one caused two"})

      assert result["linked"] == "#{first} -> #{second}"
    end

    test "an id from no narrative at all is still refused, and says what is known",
         %{work: work, section: section} do
      st = state(work, section)
      {%{"id" => a}, st} = call(st, "add_node", %{"type" => "goal", "title" => "G", "narrative" => "n"})

      {result, _} = call(st, "link", %{"from" => a, "to" => 999_999})
      assert result["error"] =~ "unknown node id"
      assert a in result["known"]
      assert Works.list_edges(work.id) == []
    end
  end

end
