defmodule Marginalia.Analysis.Linker do
  @moduledoc """
  The pass that relates two manuscripts' graphs to each other.

  `Weave` asks what leads to what inside one draft. This asks the same
  question across the boundary between two, using the same six relations, so
  the answer reads as one graph rather than two graphs and a legend.

  What makes the question answerable at all is that both drafts have already
  been read. The model is not handed 8,000 words twice and asked to find
  correspondences — it is handed two catalogues of *nodes*, each with an id,
  a type, a section and the sentence it was anchored to, and asked which of
  those point at each other. That is a small prompt, it caches well, and the
  ids give the answer something to be checked against.

  ## The rule that does the work

  Every proposed edge names two ids. `Marginalia.Links.store_edges/3` keeps
  it only if both are real nodes, in the two manuscripts named by this link,
  **on opposite sides of it**. Three ways to be wrong, all caught in code:

  * an invented id — the model made up a connection to nothing;
  * an id from some third draft — it reached outside the pair;
  * two ids from the same draft — it drew an internal edge and presented it
    as a relationship between the documents, which is the failure that would
    make the whole feature a lie.

  The rejection count is returned and logged. A pass that starts failing
  this has begun inventing, and what it produced should not be read.
  """

  require Logger

  alias Marginalia.{LLM, Links, Works}

  # the same vocabulary as inside a draft, minus `realises` and `asks_about`,
  # which are about a node's relationship to its own document's spine and
  # cannot mean anything across a boundary
  @types ~w(develops pays_off requires tension answers echoes)

  def types, do: @types

  @prompt """
  You are given the maps of TWO manuscripts that have already been read. Not the texts —
  the maps: every beat, the spine, the threads, the open questions, each with a numeric id
  and, where it has one, the sentence from the draft it is anchored to.

  Your job is to say how the two are related, as edges between their nodes.

  This is the only thing you are doing. Do not summarise either document, do not judge which
  is better, do not propose changes to either.

  Return JSON:
  {"summary": "...", "edges": [{"from": <id>, "to": <id>, "type": "...", "why": "..."}]}

  TYPES — the direction matters, and "from" is the node doing the thing
    develops   from builds directly on to — carries the same idea further
    pays_off   from delivers on a promise, setup or question that to made
    requires   from only works if the reader already has to
    tension    the two assert things that sit badly together
    answers    from is a direct response to a question or claim in to
    echoes     the two make the same move independently — the same point, arrived at separately

  RULES
  - EVERY edge must have one end in manuscript A and the other in manuscript B. An edge
    between two nodes of the same manuscript is thrown away — that work is already done, and
    passing one off as a connection between the documents is the worst thing you can do here.
  - Use the numeric ids exactly as given. An id that is not in the lists gets the edge thrown
    away, and you will not be told which.
  - "why" is one concrete sentence naming what actually passes between the two nodes. It is
    shown to the reader beside the edge. "These are both about AI" is useless. "Manuscript A
    proposes embedded evaluators as the mechanism; Manuscript B names the staffing problem
    that would decide whether they work" is the job.
  - Name the documents "Manuscript A" and "Manuscript B" IN FULL, every time, in "why" and in
    "summary" alike. Never a bare "A" or "B". The reader sees these sentences with the real
    titles substituted in, and a lone capital cannot be told apart from the word "A" starting
    a sentence — so a bare letter either survives as a letter or eats an article.
  - `tension` is a real claim, not a way to make the graph interesting. Draw one only where
    the two documents genuinely disagree, and say what about.
  - `echoes` is for genuine independent convergence. If one document is clearly responding to
    the other, that is `answers` or `develops`, not `echoes`.

  COVERAGE — work through it, do not pick highlights
  - Go down manuscript A's beats IN ORDER and ask of each one: does anything in B relate to
    this? Then do the same from B. Most beats will have an answer; a beat with none is a
    real finding, not a gap to hurry past.
  - A reader moves through one document from the top. Every stretch you leave unlinked is a
    stretch where they are reading alone, so do not stop once you have found the interesting
    ones. Thirty true edges spread over the whole of both documents are worth far more than
    fifteen clustered at the front.
  - The limit is truth, not count. Never invent a relation to fill a gap — an edge that is
    not really there costs more than the silence it replaced — but do not skip one that is
    there because you already have enough.

  "summary": two or three sentences on what the relationship between these documents actually
  is — who is answering whom, where they converge, where they part. Written for someone who
  has read both and wants to know what sits between them.
  """

  def prompt, do: @prompt

  def passes do
    [
      %{
        id: "link",
        name: "Linking — how two graphs relate",
        model: LLM.default_model(),
        runs: "once per pair of manuscripts",
        produces: "edges between the nodes of two drafts, plus a summary of the relationship",
        prompt: @prompt
      }
    ]
  end

  @doc "Run the link in a detached task. Returns immediately."
  def start(link, provider \\ nil) do
    Task.Supervisor.start_child(Marginalia.TaskSupervisor, fn -> run(link, provider) end)
    :ok
  end

  @doc """
  Relate the two manuscripts of `link`.

  Returns `{:ok, %{kept: n, dropped: n}}` or `{:error, reason}`. Re-running
  replaces the previous edges rather than adding to them: the second answer
  to the same question is a correction, not more data.
  """
  def run(link, provider \\ nil) do
    {a, b} = Links.works(link)
    {:ok, link} = Links.set_status(link, "linking", %{error: nil})
    broadcast(link, {:link, :start})

    a_nodes = Works.list_nodes(a.id)
    b_nodes = Works.list_nodes(b.id)

    cond do
      a_nodes == [] or b_nodes == [] ->
        fail(link, :not_read)

      true ->
        # One model call, so there is no incremental progress to report —
        # but there are three distinct things happening around it, and a
        # reader waiting ninety seconds deserves to know which one.
        broadcast(link, {:link, :stage, :reading})
        broadcast(link, {:link, :stage, :asking})

        case ask_with_retry(a, b, a_nodes, b_nodes, provider) do
          {:ok, %{"edges" => edges} = out} when is_list(edges) ->
            broadcast(link, {:link, :stage, :checking})
            Links.clear_edges(link)
            {kept, dropped} = Links.store_edges(link, edges, @types)

            Logger.info(
              "marginalia: linked #{a.id}↔#{b.id} — #{kept} edges kept, #{dropped} dropped"
            )

            {:ok, link} =
              Links.set_status(link, "linked", %{summary: out["summary"], error: nil})

            broadcast(link, {:link, :done})
            {:ok, %{kept: kept, dropped: dropped, link: link}}

          {:ok, _} ->
            fail(link, :no_edges)

          {:error, reason} ->
            fail(link, reason)
        end
    end
  end

  defp fail(link, reason) do
    {:ok, link} = Links.set_status(link, "failed", %{error: inspect(reason)})
    Logger.warning("marginalia: link #{link.id} failed: #{inspect(reason)}")
    broadcast(link, {:link, :failed})
    {:error, reason}
  end

  @crowded """

  THIS PAIR IS LARGE AND YOUR LAST ANSWER DID NOT FIT.
  Return AT MOST 45 edges — the strongest ones, spread across both documents rather than
  clustered at the front. Keep every "why" to a single short sentence. Everything else
  above still applies: no invented relations, and every edge still has one end in each
  manuscript.
  """

  # Two large maps can produce more edges than the budget holds, and a
  # truncated answer is not a short answer — it is a cut-off JSON array,
  # which parses as nothing and stores nothing. Raising the ceiling only
  # moves the wall; the fix is to ask for less of the thing that overflowed.
  defp ask_with_retry(a, b, a_nodes, b_nodes, provider) do
    case ask(a, b, a_nodes, b_nodes, provider) do
      {:error, :truncated} ->
        Logger.warning(
          "marginalia: link #{a.id}<->#{b.id} overflowed, asking again for the strongest only"
        )

        ask(a, b, a_nodes, b_nodes, provider, @crowded)

      other ->
        other
    end
  end

  defp ask(a, b, a_nodes, b_nodes, provider, extra \\ "") do
    LLM.json(
      provider: provider,
      model: LLM.default_model(provider),
      # the one call that decides what the relationship is
      effort: :high,
      temperature: 0.4,
      # asking it to sweep both documents instead of picking highlights
      # tripled the answer, and 8k cut it off mid-array — the whole run
      # returned :truncated and stored nothing
      max_tokens: 24_000,
      messages: [
        %{"role" => "system", "content" => @prompt <> extra},
        %{"role" => "user", "content" => catalogue(a, b, a_nodes, b_nodes)}
      ]
    )
  end

  # Both maps, in one message. The stable part — the prompt — is first so the
  # provider's prefix cache covers it across every pair.
  defp catalogue(a, b, a_nodes, b_nodes) do
    """
    # MANUSCRIPT A: #{a.title}
    #{intent(a)}#{side(a, a_nodes)}

    # MANUSCRIPT B: #{b.title}
    #{intent(b)}#{side(b, b_nodes)}
    """
  end

  defp intent(%{intent: i}) when is_binary(i) and i != "",
    do: "Intended effect on a reader: #{i}\n"

  defp intent(_), do: ""

  defp side(work, nodes) do
    sections = Works.list_sections(work.id) |> Map.new(&{&1.id, &1})
    by_type = Enum.group_by(nodes, & &1.node_type)

    ["beat", "spine", "thread", "question"]
    |> Enum.map_join("\n", fn type ->
      case Map.get(by_type, type, []) do
        [] -> ""
        list -> "\n## #{label(type)}\n" <> Enum.map_join(list, "\n", &line(&1, sections))
      end
    end)
  end

  defp label("beat"), do: "Beats, in document order"
  defp label("spine"), do: "Spine"
  defp label("thread"), do: "Threads"
  defp label("question"), do: "Open questions"

  defp line(n, sections) do
    where =
      case n.section_id && Map.get(sections, n.section_id) do
        nil -> ""
        s -> " (§#{s.ordinal})"
      end

    body = if n.body && n.body != "", do: " — #{String.slice(n.body, 0, 150)}", else: ""
    quote = if n.quote && n.quote != "", do: "\n      \"#{one_line(n.quote)}\"", else: ""

    "  [#{n.id}]#{where} #{n.title}#{body}#{quote}"
  end

  defp one_line(q), do: q |> String.replace(~r/\s+/u, " ") |> String.slice(0, 180)

  defp broadcast(link, msg),
    do: Phoenix.PubSub.broadcast(Marginalia.PubSub, "link:#{link.id}", msg)
end
