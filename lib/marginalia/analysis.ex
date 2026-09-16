defmodule Marginalia.Analysis do
  @moduledoc """
  The Read: the pass that turns a confirmed manuscript into a map.

  Deliberately the cheap half of the design. Each section gets one call from
  the fast model (the beats), then the whole work gets one call from the good
  model (the spine, the first impression, the questions). A 90k-word draft is
  therefore ~N+1 calls, finishes in minutes rather than the half hour the full
  close read would take, and is enough to unlock the chat — which is the thing
  the writer actually came for.

  Progress is broadcast per section over PubSub so the receipt fills in while
  the writer watches, in document order.
  """

  require Logger

  alias Marginalia.{LLM, Works}
  alias Marginalia.Analysis.Anchor

  # Sections read at once. Kept low deliberately: a new OpenAI org will not
  # sustain much more, and a 429 storm costs more wall clock than it saves.
  @concurrency 3

  def topic(work_id), do: "work:#{work_id}"


  defp broadcast(work_id, msg),
    do: Phoenix.PubSub.broadcast(Marginalia.PubSub, topic(work_id), msg)

  @doc "Run The Read in a detached task. Returns immediately."
  def start(work, provider \\ nil) do
    Task.Supervisor.start_child(Marginalia.TaskSupervisor, fn -> run(work, provider) end)
    :ok
  end

  @doc "Run The Read synchronously. Used by tests and by `start/2`."
  def run(work, provider \\ nil) do
    {:ok, work} = Works.set_status(work, "reading")
    broadcast(work.id, {:status, "reading"})

    sections = Works.list_sections(work.id)

    # Stages are broadcast as well as sections, because a writer watching a
    # three-minute read needs to know which of three different things is
    # happening — and the last of them, the weave, produces nothing visible
    # until it finishes.
    broadcast(work.id, {:stage, :sections, :start})

    sections
    |> Task.async_stream(&read_section(work, &1, provider),
      max_concurrency: @concurrency,
      timeout: 180_000,
      on_timeout: :kill_task
    )
    |> Stream.run()

    broadcast(work.id, {:stage, :sections, :done})
    broadcast(work.id, {:stage, :spine, :start})

    case synthesize(work, provider) do
      :ok ->
        weave(work, provider)
        {:ok, work} = Works.set_status(work, "read")
        broadcast(work.id, {:status, "read"})
        {:ok, work}

      {:error, reason} ->
        # The beats are already stored and are useful on their own, so a failed
        # synthesis degrades rather than voiding the run.
        {:ok, work} = Works.set_status(work, "read", "spine unavailable: #{inspect(reason)}")
        broadcast(work.id, {:status, "read"})
        {:ok, work}
    end
  end

  # ==========================================================================
  # Pass 1 — read each section
  # ==========================================================================

  @beats_prompt """
  You are reading one section of a manuscript for a structural map. You are not editing it
  and not rewriting it.

  A BEAT is one move the section makes: a decision, a reveal, a turn in the argument, a
  change in who wants what, an image the section rests on. One move, not one sentence. If
  two of your beats could be joined by "and then he also says", they are one beat and you
  have split a single move in half.

  HOW MANY. You are given a target and a hard limit. The target is roughly how many moves a
  section this long makes; the limit is refused above. Returning twice the target means you
  are listing sentences rather than naming moves. Going under is fine when the section
  genuinely does little. Before you answer, count what you have, and if you are over the
  limit, merge the ones that belong to the same move until you are not.

  EACH BEAT
  - title: one line under 90 characters, naming the move in plain words. Write it as
    something the writer DOES: "He sets June 2020 as the baseline", not "The baseline".
  - note: one or two sentences on what this does TO A READER, and what it sets up or pays
    off if it does either. A later pass uses these to work out what leads to what, so
    "introduces the thermostat metaphor the regulation chapters depend on" is worth ten
    times "discusses self-regulation". No praise, no grading, no advice.
  - quote: a VERBATIM span copied exactly from the section, 8 to 40 words, that shows this
    beat on the page. Character for character. Do not paraphrase, do not tidy the
    punctuation, do not join two separate sentences with an ellipsis. A quote that is not
    in the text causes the whole beat to be discarded, and the server checks every one.
  """

  @beats_tool %{
    "type" => "function",
    "function" => %{
      "name" => "record_beats",
      "description" => "Record the beats of this section, in the order they happen on the page.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "beats" => %{
            "type" => "array",
            "description" => "In document order. Merge beats that belong to the same move.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "title" => %{"type" => "string", "description" => "The move, as something the writer does. Under 90 characters."},
                "note" => %{"type" => "string", "description" => "What it does to a reader, and what it sets up or pays off."},
                "quote" => %{"type" => "string", "description" => "8 to 40 words, verbatim from the section. Verified server-side."}
              },
              "required" => ["title", "note", "quote"]
            }
          }
        },
        "required" => ["beats"]
      }
    }
  }

  @doc "The tool the section pass fills in. Shown in the Prompts view."
  def beats_tool, do: @beats_tool

  # About one move per 220 words, floored and capped so a one-paragraph
  # section is not asked for three moves it does not make and a long one is
  # not flattened into a dozen.
  @doc false
  def beat_target(word_count) do
    word_count |> div(220) |> max(2) |> min(14)
  end

  # Measured, not guessed: the model returns whatever number it is given as a
  # hard limit, and ignores a target on its own — it came back with 8 beats
  # for a 322-word section against a target of 2, and with exactly 2 once a
  # limit was stated. A schema `maxItems` is ignored entirely. So the limit
  # sits a little above the target, leaving room for a genuinely dense
  # section without licensing a sentence-by-sentence list.
  @doc false
  def beat_ceiling(word_count) do
    t = beat_target(word_count)
    t + max(div(t, 2), 1)
  end

  defp read_section(work, section, provider) do
    Works.set_section_status(section, "reading")
    broadcast(work.id, {:section, section.id, "reading"})

    user =
      """
      Manuscript: #{work.title}
      #{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}
      Section #{section.ordinal}: #{section.title}
      #{section.word_count} words. Aim for about #{beat_target(section.word_count)} beats.
      HARD LIMIT: return at most #{beat_ceiling(section.word_count)}. More than that is refused.

      ---
      #{String.slice(section.body, 0, 24_000)}
      """

    result =
      LLM.call_tool(
        tool: @beats_tool,
        provider: provider,
        model: LLM.fast_model(provider),
        # Thinking off, and measured rather than assumed. This pass runs once
        # per section and is therefore most of the calls in a read, and it is
        # extraction rather than reasoning: naming what happens on a page.
        #
        # Across three sections, high effort spent 7,860 reasoning tokens per
        # call and 31s; off spent none and 4.5s — 8x cheaper on completion —
        # and returned MORE beats, with every single one surviving the
        # anchoring check at both settings (36/36 and 44/44). Deliberation was
        # buying nothing here except the bill. `low` is not the lever it looks
        # like: it only cut reasoning by about a fifth.
        effort: :none,
        temperature: 0.3,
        max_tokens: 4_000,
        messages: [
          %{"role" => "system", "content" => @beats_prompt},
          %{"role" => "user", "content" => user}
        ]
      )

    case result do
      {:ok, %{"beats" => beats}} when is_list(beats) ->
        store_beats(work, section, beats)

      {:ok, _} ->
        fail_section(work, section, "no beats returned")

      {:error, reason} ->
        fail_section(work, section, inspect(reason))
    end
  end

  defp store_beats(work, section, beats) do
    candidates =
      beats
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn b ->
        %{
          node_type: "beat",
          title: to_line(b["title"]),
          body: b["note"],
          quote: b["quote"]
        }
      end)
      |> Enum.reject(&(&1.title in [nil, ""]))

    {kept, dropped} = Anchor.filter(candidates, section.body)

    ceiling = beat_ceiling(section.word_count)

    kept = thin(kept, ceiling, section.id)

    if dropped > 0 do
      Logger.info("marginalia: dropped #{dropped}/#{length(candidates)} unanchored beats in section #{section.id}")
    end

    nodes = Works.insert_nodes(work.id, section.id, kept)

    # Chain the beats in document order. This is the one edge we can assert
    # without a model: beat B comes after beat A because it does, on the page.
    # Without it the graph is a bag of disconnected nodes and any tree view
    # renders it as stubs.
    nodes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.each(fn {[a, b], i} -> Works.link(work.id, a.id, b.id, "follows", i) end)

    Works.set_section_status(section, "read")
    broadcast(work.id, {:section, section.id, "read"})
    broadcast(work.id, {:nodes, section.id, length(nodes)})
    :ok
  end

  # A long section still comes back over the limit however plainly it is
  # stated, so the limit is also enforced here. Taking the first N would leave
  # the last third of a long section with nothing on it, which is worse than
  # too many beats — so this keeps an evenly spaced subset, first and last
  # included, and the section stays covered end to end.
  @doc false
  def thin(beats, ceiling, section_id) do
    n = length(beats)

    if n <= ceiling do
      beats
    else
      Logger.info("marginalia: section #{section_id} returned #{n} beats, thinning to #{ceiling}")

      step = (n - 1) / (ceiling - 1)

      0..(ceiling - 1)
      |> Enum.map(&Enum.at(beats, round(&1 * step)))
      |> Enum.uniq()
    end
  end

  defp fail_section(work, section, reason) do
    Logger.warning("marginalia: section #{section.id} failed: #{reason}")
    Works.set_section_status(section, "failed")
    broadcast(work.id, {:section, section.id, "failed"})
    :ok
  end

  # ==========================================================================
  # Pass 2 — the spine, the first impression, the questions
  # ==========================================================================

  @spine_prompt """
  You are given the beat-by-beat map of a whole manuscript, in order. You have not been given
  the full text, and you must not pretend you have.

  Return JSON:
  {
    "first_impression": "...",
    "spine": [{"title": "...", "note": "..."}],
    "threads": [{"title": "...", "note": "...", "status": "carried|dropped|thin"}],
    "questions": ["...", "..."]
  }

  - "first_impression": 3 to 5 sentences on what this draft is actually doing, as a reader
    experiences it. Be specific to THIS manuscript — name its people, its moves, its subject.
    No grading, no encouragement, no "this shows promise". If something is not working, say
    what, plainly.
  - "spine": 6 to 12 nodes, the chain the whole work hangs off, in order. This is the load
    bearing structure, not a summary of every beat.
  - "threads": 3 to 8 threads that run across sections. Mark "dropped" only when a thread
    stops well before the end with nothing closing it; "thin" when it appears once or twice
    and never develops.
  - "questions": 4 to 6 questions for the writer. Each must name something specific from this
    draft. A question that could be asked of any manuscript is worthless — do not include one.
  """

  defp synthesize(work, provider) do
    beats = Works.list_nodes(work.id, type: "beat")
    sections = Works.list_sections(work.id)

    if beats == [] do
      {:error, :no_beats}
    else
      by_section = Enum.group_by(beats, & &1.section_id)

      outline =
        sections
        |> Enum.map(fn s ->
          lines =
            by_section
            |> Map.get(s.id, [])
            |> Enum.map(&"  - #{&1.title}")
            |> Enum.join("\n")

          "## #{s.ordinal}. #{s.title} (#{s.word_count} words)\n#{lines}"
        end)
        |> Enum.join("\n\n")

      user =
        """
        Manuscript: #{work.title}
        #{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}
        #{length(sections)} sections, #{work.word_count} words.

        #{outline}
        """

      case LLM.json(
             provider: provider,
             model: LLM.default_model(provider),
             # the spine is one call that has to hold the whole draft at once
             effort: :high,
             temperature: 0.5,
             max_tokens: 6_000,
             messages: [
               %{"role" => "system", "content" => @spine_prompt},
               %{"role" => "user", "content" => user}
             ]
           ) do
        {:ok, data} -> store_synthesis(work, data)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp store_synthesis(work, data) do
    spine =
      (data["spine"] || [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(&%{node_type: "spine", title: to_line(&1["title"]), body: &1["note"]})
      |> Enum.reject(&(&1.title in [nil, ""]))

    thread_nodes =
      (data["threads"] || [])
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn t ->
        status = t["status"] || "carried"
        %{node_type: "thread", title: to_line(t["title"]), body: "#{status} — #{t["note"]}"}
      end)
      |> Enum.reject(&(&1.title in [nil, ""]))

    questions =
      (data["questions"] || [])
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&%{node_type: "question", title: to_line(&1)})
      |> Enum.reject(&(&1.title in [nil, ""]))

    spine_nodes = Works.insert_nodes(work.id, nil, spine)
    Works.insert_nodes(work.id, nil, thread_nodes)
    Works.insert_nodes(work.id, nil, questions)

    # Chain the spine so the map has a trunk. The ordinal is explicit because
    # the lane renderer picks a node's trunk parent by edge order, and without
    # it a re-run would draw a different shape from the same data.
    spine_nodes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index()
    |> Enum.each(fn {[a, b], i} -> Works.link(work.id, a.id, b.id, "leads_to", i) end)

    Works.update_work(work, %{
      first_impression: data["first_impression"],
      title: work.title,
      body: work.body
    })

    broadcast(work.id, {:synthesis, :done})
    broadcast(work.id, {:stage, :spine, :done})
    :ok
  end

  # Pass 3 runs last and is allowed to fail: the beats and the spine are
  # already stored and useful without the cross-links.
  defp weave(work, provider) do
    broadcast(work.id, {:stage, :weave, :start})

    case Marginalia.Analysis.Weave.run(work, provider) do
      {:ok, n} ->
        broadcast(work.id, {:stage, :weave, :done})
        Logger.info("marginalia: wove #{n} cross-section edges for work #{work.id}")
        broadcast(work.id, {:weave, n})
        :ok

      {:error, reason} ->
        Logger.warning("marginalia: weave failed for work #{work.id}: #{inspect(reason)}")
        broadcast(work.id, {:stage, :weave, :failed})
        :ok
    end
  end

  defp to_line(nil), do: nil

  defp to_line(s) when is_binary(s) do
    s |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 300)
  end

  defp to_line(_), do: nil

  @doc """
  The prompts and models this pipeline actually uses, for the Prompts view.

  Read straight from the module attributes rather than retyped, so the page
  cannot drift from what really ran.
  """
  def passes do
    [
      %{
        id: "beats",
        name: "Pass 1 — read each section",
        model: LLM.fast_model(),
        runs: "once per section, #{@concurrency} at a time",
        produces: "beats, each anchored to a verbatim quote",
        prompt: @beats_prompt
      },
      %{
        id: "spine",
        name: "Pass 2 — the whole draft",
        model: LLM.default_model(),
        runs: "once, after every section is read",
        produces: "first impression, spine, threads, open questions",
        prompt: @spine_prompt
      }
    ] ++ Marginalia.Analysis.Weave.passes()
  end
end
