defmodule Marginalia.Analysis.DecisionGraph do
  @moduledoc """
  The `/decision-graph` methodology, translated from a skill the operator runs
  by hand into tool calls the server runs itself.

  The skill tells a person to explore, collect narratives, and then build a
  graph with `deciduous add` / `deciduous link` / `deciduous status`. Here the
  same vocabulary is handed to the model as function-calling tools, and the
  server executes each call against the database. The model is doing what the
  skill describes; it just cannot reach a shell.

  Three rules from the skill are enforced in code rather than merely asked for
  in the prompt, because a prompt is a request and this is a guarantee:

  * **The flow rule.** `goal -> option(s) -> decision -> action(s) -> outcome`.
    A goal may not link straight to a decision — the options have to exist
    first. `link/3` refuses it.
  * **The temporal rule.** Options under a decision are alternatives weighed at
    the same moment. A later attempt after an earlier one failed is a *new*
    decision reached through an observation, not a second option. Linking an
    option to an earlier decision is refused.
  * **Grounding.** Every node that claims something about the text carries a
    verbatim quote, verified by `Anchor`. Unanchored claims are rejected at the
    tool boundary, so the model is told immediately and can correct itself,
    rather than having its work silently dropped later.

  The narrative discipline — "don't branch from the goal unless it's genuinely
  new" — cannot be mechanically enforced, so it is in the prompt and visible in
  the Prompts tab where the writer can judge whether it was followed.
  """

  require Logger

  alias Marginalia.{LLM, Works}
  alias Marginalia.Analysis.Anchor

  @max_iterations 24

  # goal -> option -> decision -> action -> outcome, plus the two that attach
  # anywhere. The value is the set of types a node of that type may point at.
  @flow %{
    "goal" => ~w(option observation),
    "option" => ~w(decision observation),
    "decision" => ~w(action option observation outcome),
    "action" => ~w(outcome observation action),
    "outcome" => ~w(observation revisit decision goal),
    "observation" => ~w(decision goal observation revisit action outcome option),
    "revisit" => ~w(decision goal observation)
  }

  def flow, do: @flow

  # ==========================================================================
  # Prompts — shown verbatim in the Prompts tab
  # ==========================================================================

  @narrative_prompt """
  You are reading a manuscript to find its NARRATIVES before any graph is drawn.

  A narrative is one thing that develops across the draft: a relationship that changes, an
  argument that gets built, a question the book keeps re-answering, a promise made early and
  paid or dropped late. It is not a summary of a chapter and not a theme word.

  Return JSON:
  {"narratives": [{"name": "...", "arc": "...", "sections": [1,4,7], "quote": "..."}]}

  - 3 to 7 narratives. Fewer, truer ones beat a long list.
  - "name": 2-6 words, the thing itself.
  - "arc": 2-3 sentences tracing how it moves across the sections you list — what starts it,
    what changes it, where it ends or stops.
  - "sections": the section numbers where it actually appears.
  - "quote": one VERBATIM span, copied character for character from the draft, that shows this
    narrative most clearly. A quote that is not in the text gets the narrative discarded.

  Find the SPINE among them: the question the draft keeps re-answering. Name it first.
  """

  @graph_prompt """
  You are building a decision graph of a manuscript, using the tools provided. Work narrative by
  narrative. Do not describe the graph in prose — build it by calling the tools.

  NODE TYPES
    goal        what this narrative is trying to achieve, in the work
    option      an approach the draft weighs or could have taken
    decision    the choice point where one option wins
    action      what the draft actually does on the page
    outcome     what results from it, for the reader
    observation something learned or revealed; attaches anywhere
    revisit     a point where the draft reconsiders an earlier approach

  THE FLOW: goal -> option(s) -> decision -> action(s) -> outcome(s).
  A goal never links straight to a decision. The options come first, and the decision is what
  chose between them. Mark the option that won with set_status(chosen) and the ones that did
  not with set_status(rejected). The server will refuse links that break this.

  TIME FLOWS FORWARD. Options under one decision are alternatives weighed at the same moment.
  If the draft tries something, it does not work, and it tries something else later, that is a
  NEW decision reached through an observation about the first — not two options under one
  decision.

  NARRATIVE DISCIPLINE. Every node needs a reason to exist. Before adding one, ask what
  prompted it. Do not branch from the goal unless the thing is genuinely new: if it refines or
  replaces something already in the graph, connect it there instead. Someone should be able to
  read this graph and see not just what the draft does but why each move follows from the last.

  GROUNDING. Every node that claims something about the text needs `quote`: a verbatim span
  copied exactly from the draft. The server verifies it against the source and rejects the node
  if it is not there, character for character. Do not paraphrase into the quote field. Goals and
  decisions may omit a quote when they are genuinely structural rather than textual.

  Build one chain per narrative, then connect narratives where one genuinely caused another.
  When you are finished, stop calling tools and reply with one sentence.
  """

  def passes do
    [
      %{
        id: "narratives",
        name: "Pass A — find the narratives",
        model: LLM.default_model(),
        runs: "once, over every section's beats",
        produces: "3-7 narratives with their arcs, and the spine",
        prompt: @narrative_prompt
      },
      %{
        id: "decision_graph",
        name: "Pass B — build the decision graph",
        model: LLM.default_model(),
        runs: "once per narrative, as tool calls the server executes",
        produces: "goal / option / decision / action / outcome nodes and their edges",
        prompt: @graph_prompt
      }
    ]
  end

  @doc "The tool schemas handed to the model — the deciduous CLI, as functions."
  def tools do
    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "add_node",
          "description" =>
            "Add one node to the decision graph. Returns its id, which you use for linking. Equivalent to `deciduous add <type> \"<title>\"`.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "type" => %{
                "type" => "string",
                "enum" => ~w(goal decision option observation action outcome revisit)
              },
              "title" => %{"type" => "string", "description" => "One clear line, under 100 characters."},
              "description" => %{
                "type" => "string",
                "description" => "Why this exists and what prompted it. 1-3 sentences."
              },
              "quote" => %{
                "type" => "string",
                "description" =>
                  "A verbatim span from the draft, copied exactly. Verified server-side; the node is rejected if it is not found."
              },
              "section" => %{"type" => "integer", "description" => "Section number this belongs to, if any."},
              "narrative" => %{"type" => "string", "description" => "Which narrative this node belongs to."}
            },
            "required" => ["type", "title", "narrative"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "link",
          "description" =>
            "Connect two nodes: from leads_to to. Equivalent to `deciduous link <from> <to> -r \"<why>\"`. Refused if it breaks the flow rule or the temporal rule.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "from" => %{"type" => "integer"},
              "to" => %{"type" => "integer"},
              "rationale" => %{"type" => "string", "description" => "Why this led to that."}
            },
            "required" => ["from", "to"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "set_status",
          "description" =>
            "Mark an option chosen or rejected, or a node superseded. Equivalent to `deciduous status <id> <status>`.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "integer"},
              "status" => %{"type" => "string", "enum" => ~w(chosen rejected superseded)}
            },
            "required" => ["id", "status"]
          }
        }
      }
    ]
  end

  # ==========================================================================
  # Running it
  # ==========================================================================

  def topic(work_id), do: "work:#{work_id}"

  defp broadcast(work_id, msg),
    do: Phoenix.PubSub.broadcast(Marginalia.PubSub, topic(work_id), msg)

  @doc "Build the decision graph for a work that has already been read. Detached."
  def start(work, opts \\ []) do
    Task.Supervisor.start_child(Marginalia.TaskSupervisor, fn -> run(work, opts) end)
    :ok
  end

  @doc "Build the decision graph synchronously."
  def run(work, opts \\ []) do
    provider = opts[:provider]
    # A rebuild replaces the graph rather than adding a second one beside it.
    {:ok, cleared} = Works.reset_decision_graph(work.id)
    if cleared > 0, do: Logger.info("marginalia: cleared #{cleared} nodes from the previous graph")
    broadcast(work.id, {:graph, :building})

    with {:ok, narratives} <- find_narratives(work, provider) do
      # The id map is threaded through every narrative, not rebuilt per
      # narrative, so a later chain can link back into an earlier one. Without
      # this each narrative was a sealed island and the graph came out as N
      # disconnected trees — which is exactly what "connect narratives where
      # one genuinely caused another" in the prompt was asking for and the
      # code was refusing.
      Enum.reduce(narratives, %{}, fn n, known ->
        build_narrative(work, n, provider, known)
      end)

      broadcast(work.id, {:graph, :done})
      {:ok, length(narratives)}
    else
      {:error, reason} ->
        Logger.warning("marginalia: decision graph failed: #{inspect(reason)}")
        broadcast(work.id, {:graph, :failed})
        {:error, reason}
    end
  end

  # --- Pass A ---------------------------------------------------------------

  defp find_narratives(work, provider) do
    sections = Works.list_sections(work.id)
    beats = Works.list_nodes(work.id, type: "beat")
    by_section = Enum.group_by(beats, & &1.section_id)

    outline =
      Enum.map_join(sections, "\n\n", fn s ->
        lines = by_section |> Map.get(s.id, []) |> Enum.map_join("\n", &"  - #{&1.title}")
        "## Section #{s.ordinal}: #{s.title}\n#{lines}"
      end)

    user = """
    Manuscript: #{work.title}
    #{if work.intent && work.intent != "", do: "Intended effect on a reader: #{work.intent}\n", else: ""}
    #{outline}
    """

    case LLM.json(
           provider: provider,
           model: LLM.default_model(provider),
           effort: :high,
           temperature: 0.4,
           max_tokens: 4_000,
           messages: [
             %{"role" => "system", "content" => @narrative_prompt},
             %{"role" => "user", "content" => user}
           ]
         ) do
      {:ok, %{"narratives" => ns}} when is_list(ns) -> {:ok, Enum.filter(ns, &is_map/1)}
      {:ok, _} -> {:error, :no_narratives}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Pass B ---------------------------------------------------------------

  defp build_narrative(work, narrative, provider, known) do
    name = narrative["name"] || "untitled"
    sections = Works.list_sections(work.id)

    relevant =
      case narrative["sections"] do
        list when is_list(list) and list != [] ->
          Enum.filter(sections, &(&1.ordinal in list))

        _ ->
          sections
      end

    # Every section this narrative runs through, in full. The skill's whole
    # premise is that the graph is built from the contents, not from a sample
    # of them, so nothing is trimmed here — a long draft costs time, and time
    # is the cheaper thing to spend.
    text =
      Enum.map_join(relevant, "\n\n", fn s ->
        "## Section #{s.ordinal}: #{s.title}\n#{s.body}"
      end)

    user = """
    Manuscript: #{work.title}

    NARRATIVE TO BUILD: #{name}
    #{narrative["arc"]}
    #{already(work, known)}
    The sections it runs through are below in full. Build this narrative's chain with the tools.

    #{text}
    """

    messages = [
      %{"role" => "system", "content" => @graph_prompt},
      %{"role" => "user", "content" => user}
    ]

    # every id created so far in this run, so a link into an earlier
    # narrative validates instead of being refused
    state = %{
      work: work,
      narrative: name,
      sections: relevant,
      nodes: known,
      seq: 0,
      refused: MapSet.new()
    }

    loop(messages, state, provider, 0)
  end

  # What the previous narratives built, so this one can join onto it rather
  # than starting a fresh island.
  defp already(_work, known) when map_size(known) == 0, do: ""

  defp already(work, known) do
    titles =
      work.id
      |> Works.list_nodes()
      |> Enum.filter(&Map.has_key?(known, &1.id))
      |> Enum.map_join("\n", &"  [#{&1.id}] #{&1.node_type}: #{&1.title}")

    """

    ALREADY IN THE GRAPH, from the narratives built before this one. You may link to any of
    these ids. Do it where this narrative genuinely grows out of, answers, or complicates one
    of them — that connection is the whole reason the graph is a graph and not a list of
    separate trees. Do not link for the sake of it.

    #{titles}
    """
  end

  defp loop(_messages, state, _provider, n) when n >= @max_iterations do
    Logger.info("marginalia: narrative #{state.narrative} hit the tool-call ceiling")
    state.nodes
  end

  defp loop(messages, state, provider, n) do
    case LLM.chat(
           provider: provider,
           model: LLM.default_model(provider),
           tools: tools(),
           effort: :high,
           temperature: 0.4,
           max_tokens: 4_000,
           messages: messages
         ) do
      {:ok, %{"tool_calls" => calls} = msg} when is_list(calls) and calls != [] ->
        {results, state} =
          Enum.reduce(calls, {[], state}, fn call, {acc, st} ->
            {result, st} = execute(call, st)
            {[result | acc], st}
          end)

        loop(messages ++ [msg] ++ Enum.reverse(results), state, provider, n + 1)

      {:ok, _done} ->
        broadcast(state.work.id, {:graph, :narrative_done})
        state.nodes

      {:error, reason} ->
        Logger.warning("marginalia: graph pass failed: #{inspect(reason)}")
        state.nodes
    end
  end

  @doc false
  # public only so the tool surface can be tested without a live model
  def execute(%{"id" => id, "function" => %{"name" => name, "arguments" => args_json}}, state) do
    args =
      case Jason.decode(args_json || "{}") do
        {:ok, m} when is_map(m) -> m
        _ -> %{}
      end

    key = {name, args}

    {result, state} =
      if MapSet.member?(Map.get(state, :refused, MapSet.new()), key) do
        # a real run showed the model re-sending a refused call verbatim up to
        # three times. Saying so is cheaper than letting it burn the iteration
        # budget rediscovering the same no.
        {%{
           error: "you already sent this exact call and it was refused. Change it or move on.",
           repeat: true
         }, state}
      else
        run_tool(name, args, state)
      end

    state =
      if Map.has_key?(result, :error) do
        Map.update(state, :refused, MapSet.new([key]), &MapSet.put(&1, key))
      else
        state
      end

    state = record(state, name, args, result)
    {%{"role" => "tool", "tool_call_id" => id, "content" => Jason.encode!(result)}, state}
  end

  # The trace is what makes the run auditable after the fact: what the model
  # asked for, and whether the server allowed it.
  defp record(state, tool, args, result) do
    seq = Map.get(state, :seq, 0)

    Works.record_event(%{
      work_id: state.work.id,
      narrative: state.narrative,
      seq: seq,
      tool: tool,
      args: Jason.encode!(args),
      result: Jason.encode!(result),
      ok: not Map.has_key?(result, :error),
      node_id: Map.get(result, :id)
    })

    # watching a build happen is most of the point of having the trace
    broadcast(state.work.id, {:graph, :event})
    Map.put(state, :seq, seq + 1)
  end

  # --- add_node -------------------------------------------------------------

  defp run_tool("add_node", args, state) do
    args = repair(args)
    section = find_section(state.sections, args["section"])
    quote_text = args["quote"]

    anchored =
      cond do
        quote_text in [nil, ""] -> {:ok, nil}
        section -> Anchor.verify(quote_text, section.body)
        true -> any_section(state.sections, quote_text)
      end

    case anchored do
      :error ->
        # tell the model immediately rather than dropping its work silently —
        # it can go back and copy the line properly
        {%{
           error: "quote not found in the draft, character for character. The node was not added.",
           hint: "Copy the span exactly, including punctuation, or omit quote if this node is structural."
         }, state}

      {:ok, q} ->
        attrs = %{
          work_id: state.work.id,
          section_id: section && section.id,
          node_type: args["type"],
          title: args["title"],
          body: args["description"],
          quote: q,
          narrative: args["narrative"] || state.narrative,
          ordinal: map_size(state.nodes)
        }

        case Works.insert_node(attrs) do
          {:ok, node} ->
            {%{id: node.id, type: node.node_type, added: node.title},
             put_in(state.nodes[node.id], node.node_type)}

          {:error, changeset} ->
            {%{
               error: "rejected: #{inspect(errors(changeset))}",
               hint: "add_node takes type, title, description, quote, section, narrative.",
               you_sent: Map.keys(args)
             }, state}
        end
    end
  end


  # --- link -----------------------------------------------------------------

  defp run_tool("link", args, state) do
    from = args["from"]
    to = args["to"]
    from_type = state.nodes[from]
    to_type = state.nodes[to]

    cond do
      is_nil(from_type) or is_nil(to_type) ->
        {%{
           error:
             "unknown node id. Link nodes you created in this run — this narrative, or one listed under ALREADY IN THE GRAPH.",
           known: state.nodes |> Map.keys() |> Enum.sort()
         }, state}

      from_type == "goal" and to_type == "decision" ->
        {%{
           error:
             "the flow rule: a goal cannot lead straight to a decision. Add the options it was choosing between, link the goal to each option, then link the options to the decision."
         }, state}

      not allowed?(from_type, to_type) ->
        {%{
           error:
             "#{from_type} -> #{to_type} is not a step in goal -> option -> decision -> action -> outcome",
           allowed: Map.get(@flow, from_type, []),
           route: route(from_type, to_type)
         }, state}

      true ->
        Works.link(state.work.id, from, to, "leads_to", map_size(state.nodes), args["rationale"])
        {%{linked: "#{from} -> #{to}"}, state}
    end
  end

  # --- set_status -----------------------------------------------------------

  defp run_tool("set_status", args, state) do
    case Works.set_node_status(state.work.id, args["id"], args["status"]) do
      {:ok, _} -> {%{ok: "#{args["id"]} is #{args["status"]}"}, state}
      {:error, reason} -> {%{error: inspect(reason)}, state}
    end
  end

  defp run_tool(other, _args, state), do: {%{error: "unknown tool #{other}"}, state}
  # Observed in a real run: the model sometimes writes the title under the node
  # type's own name — `%{"action" => "Name the method"}` instead of `"title"`.
  # The title is a label, not a claim, so recovering it costs nothing that the
  # quote check protects; losing the node costs a real piece of the graph.
  defp repair(%{"title" => t} = args) when is_binary(t) and t != "", do: args

  defp repair(args) do
    type = args["type"]

    case is_binary(type) and is_binary(args[type]) and args[type] != "" do
      true -> args |> Map.put("title", args[type]) |> Map.delete(type)
      false -> args
    end
  end

  # --- helpers --------------------------------------------------------------

  defp allowed?(from, to) do
    to in Map.get(@flow, from, [])
  end

  # The commonest refusal in a real run was `outcome -> action`: the model
  # trying to say "and then the draft does this next". The rule is right —
  # something has to be noticed before the next move follows from it — but a
  # bare refusal makes the model guess. Naming the one-hop detour turns the
  # refusal into an instruction.
  defp route(from, to) do
    case Enum.find(Map.get(@flow, from, []), &(to in Map.get(@flow, &1, []))) do
      nil -> nil
      via -> "go through a #{via}: link the #{from} to a #{via}, then that #{via} to the #{to}."
    end
  end

  defp find_section(_sections, nil), do: nil

  defp find_section(sections, ordinal) when is_integer(ordinal),
    do: Enum.find(sections, &(&1.ordinal == ordinal))

  defp find_section(sections, ordinal) when is_binary(ordinal) do
    case Integer.parse(ordinal) do
      {i, _} -> find_section(sections, i)
      :error -> nil
    end
  end

  defp find_section(_sections, _), do: nil

  # the model gave a quote but not a section; try them all before giving up
  defp any_section(sections, quote_text) do
    Enum.reduce_while(sections, :error, fn s, _acc ->
      case Anchor.verify(quote_text, s.body) do
        {:ok, q} -> {:halt, {:ok, q}}
        :error -> {:cont, :error}
      end
    end)
  end

  defp errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
  end
end
