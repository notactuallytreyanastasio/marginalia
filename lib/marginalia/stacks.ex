defmodule Marginalia.Stacks do
  @moduledoc """
  Reading an ordered folder forwards, as the method it embodies.

  A stack is documents that build one thing, in the order they were written:
  fifty-five pull requests that add up to a compiler backend, a course, an
  argument made across twelve essays. Read backwards, each document says what
  happened. Read *forwards* — each one told only what the ones before it
  established — each says what somebody building the same thing must now do.
  That second reading is the method, and no single document contains it.

  Three fields carry it, and the third is the valuable one.

  `capability` is what the thing can do afterwards that it could not before.
  The chain of those is the spine, and it is the only part that has to be
  read in order.

  `requires` is which earlier documents this one stands on. It is what makes
  the order load-bearing rather than incidental, and it is what the guide
  links backwards along.

  `pitfall` is the obvious approach that is wrong here. It is almost never in
  the diff and almost always the sentence a reader needed, so it is taken
  only when the document says it outright, and the sentence that says so is
  stored beside it.

  Every model call is a forced DeepSeek tool call rather than prose asked to
  look like JSON, and every quote is located in the document it claims to
  come from before it is kept.
  """

  import Ecto.Query

  alias Marginalia.{Cuts, Folders, LLM, Reading, Repo, Works}
  alias Marginalia.Stacks.{Step, Story}
  alias Marginalia.Works.Work

  @body_cap 14_000

  # ==========================================================================
  # What a stack is
  # ==========================================================================

  @doc """
  The works of a folder, in the order they should be read.

  A leading number in the title wins when every document has one — that is
  the author saying the order out loud, and it survives being re-imported.
  Otherwise insertion order, which is the only other thing that is true.
  """
  def order(works) do
    numbers = Enum.map(works, &leading_number/1)

    if Enum.all?(numbers, &is_integer/1) and length(Enum.uniq(numbers)) == length(numbers) do
      works |> Enum.zip(numbers) |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
    else
      Enum.sort_by(works, & &1.id)
    end
  end

  defp leading_number(%Work{title: title}) do
    case Regex.run(~r/^\s*(\d+)\s*[.):-]/, title || "") do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  @doc "The works of a folder, ordered. Subfolders are not a stack."
  def documents(user_id, folder_id) do
    Work
    |> where([w], w.user_id == ^user_id and w.folder_id == ^folder_id)
    |> Repo.all()
    |> order()
  end

  def list_steps(folder_id) do
    Step
    |> where([s], s.folder_id == ^folder_id)
    |> order_by([s], asc: s.ordinal)
    |> preload(:work)
    |> Repo.all()
  end

  def get_step(folder_id, ordinal) do
    Step
    |> where([s], s.folder_id == ^folder_id and s.ordinal == ^ordinal)
    |> preload(:work)
    |> Repo.one()
  end

  @doc "Whether a step was read from the document as it now stands."
  def current?(%Step{} = step, %Work{} = work), do: step.fingerprint == fingerprint(work)

  defp fingerprint(%Work{} = work) do
    :sha256 |> :crypto.hash(text_of(work)) |> Base.encode16(case: :lower)
  end

  defp text_of(%Work{} = work) do
    work.id
    |> Works.list_sections()
    |> Enum.map_join("\n\n", & &1.body)
    |> String.slice(0, @body_cap)
  end

  # ==========================================================================
  # Reading one document forwards
  # ==========================================================================

  @tool %{
    "type" => "function",
    "function" => %{
      "name" => "report_step",
      "description" =>
        "Report what this document contributes to building the thing the series builds.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "capability" => %{
            "type" => "string",
            "description" =>
              "One line, present tense, naming what the thing can do after this document " <>
                "that it could not before. A property of the thing being built (\"a class " <>
                "becomes an actor\"), never an event (\"added actor support\")."
          },
          "requires" => %{
            "type" => "array",
            "items" => %{"type" => "integer"},
            "description" =>
              "Numbers of earlier documents this one could not have been done without. " <>
                "Empty if it stands alone."
          },
          "lesson" => %{
            "type" => "string",
            "description" =>
              "Two or three sentences telling someone building this themselves what to do " <>
                "at this point. Imperative. No project history, no \"we\"."
          },
          "pitfall" => %{
            "type" => "string",
            "description" =>
              "The obvious approach that is wrong here and why, in one or two sentences. " <>
                "Empty string if the document does not say."
          },
          "pitfall_quote" => %{
            "type" => "string",
            "description" =>
              "The exact sentence from the document establishing the pitfall, copied " <>
                "character for character. Empty string if there is no pitfall."
          },
          "excerpts" => %{
            "type" => "array",
            "maxItems" => 2,
            "description" =>
              "Passages worth showing a learner. Quote a line that is already in the " <>
                "document; the passage around it is fetched for you. Never write one.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "quote" => %{"type" => "string"},
                "caption" => %{"type" => "string"}
              },
              "required" => ["quote", "caption"]
            }
          }
        },
        "required" => ["capability", "requires", "lesson", "pitfall", "pitfall_quote", "excerpts"]
      }
    }
  }

  @prompt """
  You read one document out of an ordered series that together build one \
  thing, and report what it contributes to *building that thing* — not what \
  happened to the project that produced it.

  The reader you are writing for intends to build the same thing themselves, \
  in this order, and has seen none of the other documents.

  Quotes must be copied character for character. A program checks each one \
  against the document and drops what it cannot find, so an approximate \
  quote is a discarded field. Never write an excerpt yourself.

  Report by calling report_step.
  """

  @doc """
  Read one document, knowing only what came before it.

  `prior` is the steps already read, in order. They are handed over as their
  capabilities alone: the model needs to know what it may rely on, not how
  any of it was argued.
  """
  def read_step(user_id, folder_id, %Work{} = work, ordinal, prior, opts \\ []) do
    body = text_of(work)

    case LLM.call_tool(
           tool: @tool,
           model: LLM.default_model(),
           effort: :high,
           temperature: 0.2,
           max_tokens: 3_000,
           messages: [
             %{"role" => "system", "content" => @prompt},
             %{"role" => "user", "content" => user_message(work, ordinal, prior, body, opts)}
           ]
         ) do
      {:ok, raw} ->
        {attrs, dropped} = validate(raw, body, ordinal)

        %Step{}
        |> Step.changeset(
          Map.merge(attrs, %{
            folder_id: folder_id,
            work_id: work.id,
            ordinal: ordinal,
            fingerprint: fingerprint(work),
            dropped: dropped
          })
        )
        |> Repo.insert(
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:folder_id, :work_id]
        )

      {:error, reason} ->
        {:error, reason}
    end
    |> tap(fn _ -> user_id end)
  end

  defp user_message(work, ordinal, prior, body, opts) do
    established =
      case prior do
        [] ->
          "  (nothing — this is the first document)"

        steps ->
          steps
          |> Enum.take(-25)
          |> Enum.map_join("\n", fn s -> "  #{s.ordinal}. #{s.capability}" end)
      end

    building =
      case opts[:building] do
        b when is_binary(b) and b != "" -> "The series builds: #{b}\n\n"
        _ -> ""
      end

    """
    #{building}# Document #{ordinal}: #{work.title}

    What the earlier documents established, in order:
    #{established}

    ## The document

    #{body}
    """
  end

  # --- validation -----------------------------------------------------------

  @doc """
  Keep what can be checked against the document, and name what was thrown out.

  Public for the same reason `Cuts.validate/2` is: the prompt and the schema
  can be re-tuned freely, but a change that lets an unlocatable quote through
  makes every step untrustworthy, and nothing else in the system would notice.
  """
  def validate(raw, body, ordinal) do
    dropped = []

    {requires, dropped} =
      Enum.reduce(raw["requires"] || [], {[], dropped}, fn r, {keep, bad} ->
        case as_int(r) do
          n when is_integer(n) and n >= 1 and n < ordinal -> {[n | keep], bad}
          n when is_integer(n) -> {keep, bad ++ ["requires #{n}: not an earlier document"]}
          _ -> {keep, bad ++ ["requires #{inspect(r)}: not a number"]}
        end
      end)

    pitfall = trimmed(raw["pitfall"])
    quote = trimmed(raw["pitfall_quote"])
    found = if quote != "", do: Cuts.locate(quote, body), else: nil

    {pitfall, dropped} =
      cond do
        pitfall == "" -> {nil, dropped}
        found -> {pitfall, dropped}
        true -> {nil, dropped ++ ["pitfall: quote is not in the document"]}
      end

    {excerpts, dropped} =
      Enum.reduce(raw["excerpts"] || [], {[], dropped}, fn e, {keep, bad} ->
        q = trimmed(is_map(e) && e["quote"])

        case q != "" && passage_around(body, q) do
          nil ->
            {keep,
             bad ++ ["excerpt: #{String.slice(q, 0, 50) |> inspect()} is not in the document"]}

          false ->
            {keep, bad ++ ["excerpt: no quote"]}

          passage ->
            {keep ++ [%{"caption" => trimmed(e["caption"]), "text" => passage}], bad}
        end
      end)

    {%{
       capability: trimmed(raw["capability"]),
       requires: requires |> Enum.uniq() |> Enum.sort(),
       lesson: trimmed(raw["lesson"]),
       pitfall: pitfall,
       pitfall_quote: found,
       excerpts: Enum.take(excerpts, 2)
     }, dropped}
  end

  @doc """
  The block a quote sits in, or nil.

  A located line alone is usually too little to learn from and the whole
  document is far too much, so the unit is the paragraph — the same unit a
  reader would have highlighted, and the one `Reading.split/1` already uses
  everywhere else in the app.
  """
  def passage_around(body, quote) do
    case Cuts.locate(quote, body) do
      nil ->
        nil

      found ->
        body
        |> Reading.split()
        |> Enum.find(&String.contains?(&1, found))
        |> case do
          nil -> found
          block -> block
        end
    end
  end

  defp trimmed(v) when is_binary(v), do: String.trim(v)
  defp trimmed(_), do: ""

  defp as_int(v) when is_integer(v), do: v

  defp as_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp as_int(_), do: nil

  # ==========================================================================
  # The second pass
  # ==========================================================================

  @deep_tool %{
    "type" => "function",
    "function" => %{
      "name" => "deepen_step",
      "description" =>
        "Report what can only be said about this step with the whole series in hand.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "mechanism" => %{
            "type" => "string",
            "description" =>
              "How this actually works, three or four sentences, below the level of what to " <>
                "do. Name the moving parts and how they fit. Concrete, from the document."
          },
          "watch_for" => %{
            "type" => "string",
            "description" =>
              "What to get right at this step because a later step leans on it, naming which. " <>
                "Empty string if nothing later depends on the details here."
          },
          "revised_by" => %{
            "type" => "integer",
            "description" =>
              "The number of a LATER step that corrects, replaces or materially changes what " <>
                "this one established. 0 if none does."
          },
          "revision" => %{
            "type" => "string",
            "description" =>
              "What that later step changes about this one, in one or two sentences. Empty " <>
                "string if nothing revises it."
          },
          "revision_quote" => %{
            "type" => "string",
            "description" =>
              "The exact sentence from the LATER step's own summary establishing the revision, " <>
                "copied character for character. Empty string if there is no revision."
          }
        },
        "required" => ["mechanism", "watch_for", "revised_by", "revision", "revision_quote"]
      }
    }
  }

  @deep_prompt """
  You are reading one step of a series a second time, and this time you have \
  the whole series in front of you — including everything that comes after it.

  The first reading could not see forwards. It was told only what came before \
  each step, which is the reading a learner follows, and it means nothing it \
  said could account for what a later step changes. Your job is the part it \
  could not do.

  Do not restate the first reading. Say what only the whole chain reveals: how \
  the thing actually works underneath, what must be got right here because \
  something later leans on it, and whether a later step walks this back.

  Quotes must be copied character for character. A program checks each one and \
  drops what it cannot find.

  Report by calling deepen_step.
  """

  @doc """
  Read one step again, with the whole chain in hand.

  The chain is given as every step's capability, before and after. `later` is
  the summaries a revision may be quoted from — a revision claim has to point
  at a real later step and quote it, or it is somebody's theory about the code.
  """
  def deepen_step(%Step{} = step, chain, opts \\ []) do
    work = Repo.preload(step, :work).work
    body = text_of(work)
    later = Enum.filter(chain, &(&1.ordinal > step.ordinal))

    case LLM.call_tool(
           tool: @deep_tool,
           model: LLM.default_model(),
           effort: :high,
           temperature: 0.2,
           max_tokens: 3_000,
           messages: [
             %{"role" => "system", "content" => @deep_prompt},
             %{"role" => "user", "content" => deep_message(step, work, body, chain, opts)}
           ]
         ) do
      {:ok, raw} ->
        {attrs, dropped} = validate_deep(raw, later)

        step
        |> Step.deep_changeset(
          Map.merge(attrs, %{
            deep_dropped: dropped,
            deepened_at: DateTime.utc_now() |> DateTime.truncate(:second)
          })
        )
        |> Repo.update()

      {:error, reason} ->
        # A step that failed the second pass must not look like one nobody
        # asked to deepen. Fifty-six of a hundred failed once — rate limited
        # — and the only sign was a flash message that went away.
        step
        |> Step.deep_changeset(%{
          deep_dropped: ["the second pass failed: #{inspect(reason)}"],
          deepened_at: nil
        })
        |> Repo.update()

        {:error, reason}
    end
  end

  defp deep_message(step, work, body, chain, opts) do
    line = fn s ->
      mark =
        cond do
          s.ordinal < step.ordinal -> "   "
          s.ordinal == step.ordinal -> ">> "
          true -> "   "
        end

      "#{mark}#{s.ordinal}. #{s.capability}"
    end

    later_detail =
      chain
      |> Enum.filter(&(&1.ordinal > step.ordinal))
      |> Enum.map_join("\n\n", fn s ->
        "### Step #{s.ordinal}: #{s.capability}\n#{s.lesson}" <>
          if(s.pitfall, do: "\nPitfall: #{s.pitfall}", else: "")
      end)

    building =
      if is_binary(opts[:building]), do: "The series builds: #{opts[:building]}\n\n", else: ""

    """
    #{building}# The whole series (>> marks the step you are re-reading)

    #{Enum.map_join(chain, "\n", line)}

    # Step #{step.ordinal}: #{work.title}

    What the first reading said it establishes: #{step.capability}
    What it said to do: #{step.lesson}
    #{if step.pitfall, do: "The pitfall it named: " <> step.pitfall <> "\n", else: ""}
    ## The document itself

    #{body}

    ## Everything that comes after it

    #{if later_detail == "", do: "(nothing — this is the last step)", else: later_detail}
    """
  end

  @doc """
  Keep what can be checked. Public for the same reason the first pass's is.

  A revision claim is the one here that can do damage: "step 14 walks this
  back" sends a reader off to read something that may not say that at all. So
  it has to name a later step and quote that step's own summary.
  """
  def validate_deep(raw, later) do
    dropped = []
    by_ordinal = Map.new(later, &{&1.ordinal, &1})

    mechanism = trimmed(raw["mechanism"])
    watch_for = trimmed(raw["watch_for"])

    n = as_int(raw["revised_by"])
    revision = trimmed(raw["revision"])
    quote = trimmed(raw["revision_quote"])
    target = n && Map.get(by_ordinal, n)

    haystack =
      case target do
        nil -> ""
        s -> Enum.join([s.capability, s.lesson, s.pitfall || ""], "\n")
      end

    found = if quote != "" and haystack != "", do: Cuts.locate(quote, haystack), else: nil

    {revised_by, revision, revision_quote, dropped} =
      cond do
        is_nil(n) or n == 0 or revision == "" ->
          {nil, nil, nil, dropped}

        is_nil(target) ->
          {nil, nil, nil, dropped ++ ["revision: step #{n} is not a later step"]}

        is_nil(found) ->
          {nil, nil, nil, dropped ++ ["revision: quote is not in step #{n}'s summary"]}

        true ->
          {n, revision, found, dropped}
      end

    # the mechanism is prose about the document, so it is not quote-checked —
    # but it must not be the first pass's lesson handed back with new words
    {mechanism, dropped} =
      if mechanism == "" do
        {nil, dropped ++ ["mechanism: empty"]}
      else
        {mechanism, dropped}
      end

    {%{
       mechanism: mechanism,
       watch_for: if(watch_for == "", do: nil, else: watch_for),
       revised_by: revised_by,
       revision: revision,
       revision_quote: revision_quote
     }, dropped}
  end

  @doc """
  Second pass over every step of a folder.

  Order does not matter here — each call already holds the whole chain — so
  unlike the forward pass this one could be run in parallel. It is not,
  because the provider's prefix cache covers the chain that every call
  repeats, and sequential calls hit it.
  """
  def deepen_stack(folder_id, opts \\ []) do
    chain = list_steps(folder_id)

    # Only what has not been deepened, unless asked for all of it. A pass
    # that half-finished should be finishable without paying for the half
    # that worked.
    todo = if opts[:force], do: chain, else: Enum.filter(chain, &is_nil(&1.deepened_at))

    todo
    |> Enum.reduce({[], []}, fn step, {done, errors} ->
      case deepen_step(step, chain, opts) do
        {:ok, updated} ->
          if is_function(opts[:on_step]),
            do: opts[:on_step].(updated, length(done) + 1, length(chain))

          {done ++ [updated], errors}

        {:error, reason} ->
          {done, errors ++ [{step.ordinal, reason}]}
      end
    end)
  end

  # ==========================================================================
  # Reading the whole stack
  # ==========================================================================

  @doc """
  Read every document of a folder in order.

  Sequential, and not for want of trying: each document is told what the ones
  before it established, so the call for step N cannot be made until N-1 has
  come back. That is the cost of reading forwards, and it is the reason the
  output is a method instead of a pile of summaries.
  """
  def read_stack(user_id, folder_id, opts \\ []) do
    docs = documents(user_id, folder_id)
    building = opts[:building] || building_from(user_id, folder_id)

    docs
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {work, i}, {steps, errors} ->
      case read_step(user_id, folder_id, work, i, Enum.reverse(steps), building: building) do
        {:ok, step} ->
          if is_function(opts[:on_step]), do: opts[:on_step].(step, i, length(docs))
          {[step | steps], errors}

        {:error, reason} ->
          {steps, errors ++ [{i, work.title, reason}]}
      end
    end)
    |> then(fn {steps, errors} -> {Enum.reverse(steps), errors} end)
  end

  defp building_from(user_id, folder_id) do
    case Folders.get_folder(user_id, folder_id) do
      nil -> nil
      folder -> folder.name
    end
  end

  # ==========================================================================
  # The composition
  # ==========================================================================

  @outline_tool %{
    "type" => "function",
    "function" => %{
      "name" => "outline_story",
      "description" => "Divide the series into the parts the telling will be written in.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "title" => %{
            "type" => "string",
            "description" => "A title for the whole telling. A claim, not a label."
          },
          "opening" => %{
            "type" => "string",
            "description" =>
              "Two or three paragraphs. What is being built, what makes it hard, and what " <>
                "the reader will have at the end. Lead with the load-bearing or surprising " <>
                "fact, never with \"this guide covers\"."
          },
          "closing" => %{
            "type" => "string",
            "description" =>
              "One or two paragraphs. What the reader has at the end, and what is honestly " <>
                "still undone."
          },
          "parts" => %{
            "type" => "array",
            "description" =>
              "The telling in parts, in the order the work is done. Every step must appear " <>
                "in exactly one part. Aim for parts of five to fifteen steps.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "heading" => %{"type" => "string", "description" => "A claim, not a label."},
                "steps" => %{"type" => "array", "items" => %{"type" => "integer"}}
              },
              "required" => ["heading", "steps"]
            }
          }
        },
        "required" => ["title", "opening", "closing", "parts"]
      }
    }
  }

  @part_tool %{
    "type" => "function",
    "function" => %{
      "name" => "write_part",
      "description" => "Write one part of the telling.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "prose" => %{
            "type" => "string",
            "description" =>
              "Three to six paragraphs telling this stretch as continuous prose. Say what " <>
                "gets built and in what order, and name the pitfalls where they bite. Do " <>
                "not enumerate the steps one by one — the reader already has that list."
          },
          "turn" => %{
            "type" => "string",
            "description" =>
              "The thing in this stretch a reader would not have guessed — a pitfall, or a " <>
                "place a later step walks an earlier one back. One or two sentences. Empty " <>
                "string if this stretch has none."
          }
        },
        "required" => ["prose", "turn"]
      }
    }
  }

  @compose_prompt """
  You are writing the long-form telling of how a thing gets built, from notes \
  already checked line by line against the documents they came from. Your job \
  is composition, not extraction: everything you need is in front of you, and \
  anything not in front of you is something you do not know.

  Write for someone about to build the same thing. They want the shape of the \
  work and the order of it, and above all the places where the obvious move is \
  wrong.

  Lead with the load-bearing or surprising fact, never with "this guide will". \
  Explain why the obvious version is wrong wherever the notes say so — that is \
  usually the most valuable sentence available to you. Say plainly what is \
  still undone. No marketing language, no bullet padding, no emoji.
  """

  @doc """
  Compose the longform telling of a stack.

  Two stages, because one will not fit. A hundred steps of capability,
  lesson, mechanism, pitfall and revision is about fifty thousand tokens of
  input, and asking for sixteen thousand of output on top of that exceeds
  the context — which is exactly what happened: the single call hung for an
  hour and produced nothing. So the outline is drawn from the capabilities
  alone, which is small, and each part's prose is written from only the steps
  in that part. Every call is bounded by the size of a part rather than by
  the size of the stack.

  It is also the better composition. A part is written by something looking
  at that stretch of work, not at everything at once.
  """
  def compose(folder_id, opts \\ []) do
    steps = list_steps(folder_id)

    if steps == [] do
      {:error, :not_read}
    else
      with {:ok, outline} <- outline(steps, opts) do
        movements = Enum.map(outline["parts"] || [], &write_part(&1, steps, outline, opts))
        store_story(folder_id, steps, Map.put(outline, "movements", movements))
      end
    end
  end

  # Stage one: the spine only. One line per step, so a stack of any length
  # fits in a prompt that does not grow with the detail of its steps.
  defp outline(steps, opts) do
    spine =
      Enum.map_join(steps, "\n", fn s ->
        marks =
          [s.pitfall && "pitfall", s.revised_by && "revised by #{s.revised_by}"]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        "#{s.ordinal}. #{s.capability}" <> if(marks == "", do: "", else: "   [#{marks}]")
      end)

    LLM.call_tool(
      tool: @outline_tool,
      model: LLM.default_model(),
      effort: :high,
      temperature: 0.4,
      max_tokens: 6_000,
      messages: [
        %{"role" => "system", "content" => @compose_prompt},
        %{
          "role" => "user",
          "content" => """
          What is being built: #{opts[:building] || "the thing this series builds"}
          #{length(steps)} steps, in order. Divide them into parts.

          #{spine}
          """
        }
      ]
    )
  end

  # Stage two: one part, and only the steps in it.
  defp write_part(part, steps, outline, opts) do
    ordinals = (part["steps"] || []) |> Enum.map(&as_int/1) |> Enum.reject(&is_nil/1)
    mine = Enum.filter(steps, &(&1.ordinal in ordinals))

    detail =
      Enum.map_join(mine, "\n\n", fn s ->
        [
          "## Step #{s.ordinal}: #{s.capability}",
          s.requires != [] && "Stands on: #{Enum.join(s.requires, ", ")}",
          "What to do: #{s.lesson}",
          s.mechanism && "How it works: #{s.mechanism}",
          s.pitfall && "The obvious version is wrong: #{s.pitfall}",
          s.watch_for && "Get right now: #{s.watch_for}",
          s.revised_by && "Walked back by step #{s.revised_by}: #{s.revision}"
        ]
        |> Enum.reject(&(&1 in [nil, false]))
        |> Enum.join("\n")
      end)

    written =
      LLM.call_tool(
        tool: @part_tool,
        model: LLM.default_model(),
        effort: :high,
        temperature: 0.4,
        max_tokens: 4_000,
        messages: [
          %{"role" => "system", "content" => @compose_prompt},
          %{
            "role" => "user",
            "content" => """
            What is being built: #{opts[:building] || "the thing this series builds"}
            The telling is called: #{outline["title"]}

            You are writing one part of it: **#{part["heading"]}**
            It covers steps #{Enum.join(ordinals, ", ")} and nothing else.

            #{detail}
            """
          }
        ]
      )

    case written do
      {:ok, %{"prose" => prose} = w} ->
        %{
          "heading" => part["heading"],
          "steps" => ordinals,
          "prose" => prose,
          "turn" => w["turn"]
        }

      _ ->
        # a part that would not write is dropped by the validator, and the
        # coverage check then names every step it was carrying
        %{"heading" => part["heading"], "steps" => ordinals, "prose" => "", "turn" => ""}
    end
  end

  defp store_story(folder_id, steps, raw) do
    {attrs, dropped, uncovered} = validate_story(raw, steps)

    %Story{}
    |> Story.changeset(
      Map.merge(attrs, %{
        folder_id: folder_id,
        dropped: dropped,
        uncovered: uncovered,
        fingerprint: story_fingerprint(steps)
      })
    )
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :folder_id
    )
  end

  @doc """
  Keep the telling only if it accounts for the whole stack.

  The coverage check is the point. Prose is not quote-checkable the way a
  claim is, so the thing that can be checked is whether the composition
  actually carries every step — and a story covering four of ten is the
  failure this is most likely to produce and least likely to look like one.
  """
  def validate_story(raw, steps) do
    ordinals = MapSet.new(steps, & &1.ordinal)
    dropped = []

    {movements, dropped, seen} =
      (raw["movements"] || [])
      |> Enum.reduce({[], dropped, MapSet.new()}, fn m, {keep, bad, seen} ->
        heading = trimmed(is_map(m) && m["heading"])
        prose = trimmed(is_map(m) && m["prose"])

        {mine, bad} =
          Enum.reduce(List.wrap(is_map(m) && m["steps"]), {[], bad}, fn n, {acc, b} ->
            case as_int(n) do
              i when is_integer(i) ->
                cond do
                  not MapSet.member?(ordinals, i) ->
                    {acc, b ++ ["part #{inspect(heading)}: step #{i} is not in this stack"]}

                  MapSet.member?(seen, i) ->
                    {acc, b ++ ["part #{inspect(heading)}: step #{i} is told twice"]}

                  true ->
                    {acc ++ [i], b}
                end

              _ ->
                {acc, b ++ ["part #{inspect(heading)}: #{inspect(n)} is not a step number"]}
            end
          end)

        cond do
          heading == "" or prose == "" ->
            {keep, bad ++ ["a part with no #{if heading == "", do: "heading", else: "prose"}"],
             seen}

          true ->
            {keep ++
               [
                 %{
                   "heading" => heading,
                   "prose" => prose,
                   "steps" => mine,
                   "turn" => trimmed(m["turn"])
                 }
               ], bad, MapSet.union(seen, MapSet.new(mine))}
        end
      end)

    uncovered = ordinals |> MapSet.difference(seen) |> MapSet.to_list() |> Enum.sort()

    dropped =
      if uncovered == [],
        do: dropped,
        else:
          dropped ++
            ["#{length(uncovered)} step(s) appear in no part: #{Enum.join(uncovered, ", ")}"]

    # parts are told in the order the work is done, so they sort by their
    # first step rather than by whatever order they came back in
    movements = Enum.sort_by(movements, fn m -> List.first(m["steps"]) || 9_999 end)

    {%{
       title: trimmed(raw["title"]),
       opening: trimmed(raw["opening"]),
       movements: movements,
       closing: trimmed(raw["closing"])
     }, dropped, uncovered}
  end

  def get_story(folder_id), do: Repo.get_by(Story, folder_id: folder_id)

  @doc "Whether the telling was composed from the steps as they now stand."
  def story_current?(%Story{} = story, folder_id),
    do: story.fingerprint == story_fingerprint(list_steps(folder_id))

  defp story_fingerprint(steps) do
    steps
    |> Enum.map_join("\n", fn s ->
      "#{s.ordinal}|#{s.capability}|#{s.lesson}|#{s.mechanism}|#{s.pitfall}|#{s.revised_by}"
    end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # ==========================================================================
  # The guide
  # ==========================================================================

  @doc """
  The stack as a reading path: each step, what it needs, and what needs it.

  Derived rather than asked for. The steps already carry the order, the
  dependencies and the excerpts; a second model pass over them would only be
  a chance to contradict what was already checked.
  """
  def guide(folder_id) do
    steps = list_steps(folder_id)
    by_ordinal = Map.new(steps, &{&1.ordinal, &1})

    Enum.map(steps, fn step ->
      %{
        step: step,
        requires: step.requires |> Enum.map(&Map.get(by_ordinal, &1)) |> Enum.reject(&is_nil/1),
        required_by:
          steps
          |> Enum.filter(&(step.ordinal in (&1.requires || [])))
          |> Enum.sort_by(& &1.ordinal),
        previous: Map.get(by_ordinal, step.ordinal - 1),
        next: Map.get(by_ordinal, step.ordinal + 1)
      }
    end)
  end

  @doc "How much of a folder has been read forwards, and how sound it is."
  def stats(user_id, folder_id) do
    docs = documents(user_id, folder_id)
    steps = list_steps(folder_id)
    by_work = Map.new(steps, &{&1.work_id, &1})

    %{
      documents: length(docs),
      read: length(steps),
      stale: Enum.count(docs, fn w -> (s = by_work[w.id]) && not current?(s, w) end),
      pitfalls: Enum.count(steps, &(&1.pitfall not in [nil, ""])),
      excerpts: steps |> Enum.map(&length(&1.excerpts || [])) |> Enum.sum(),
      links: steps |> Enum.map(&length(&1.requires || [])) |> Enum.sum(),
      dropped: steps |> Enum.map(&length(&1.dropped || [])) |> Enum.sum(),
      deepened: Enum.count(steps, &(&1.deepened_at != nil)),
      deep_failed:
        Enum.count(steps, fn s ->
          is_nil(s.deepened_at) and
            Enum.any?(s.deep_dropped || [], &String.starts_with?(&1, "the second pass failed"))
        end),
      revisions: Enum.count(steps, &(&1.revised_by != nil)),
      deep_dropped: steps |> Enum.map(&length(&1.deep_dropped || [])) |> Enum.sum()
    }
  end

  # ==========================================================================
  # Back into the reader as a draft
  # ==========================================================================

  @doc """
  Turn the composed telling into an ordinary draft, so it can be read.

  The telling is prose somebody wrote — by machine, out of other documents,
  but prose — and the thing this application does to prose is read it
  closely and argue with it in the margin. Until now the one document here
  nobody could do that to was the one this application produced.

  Each movement becomes a `##` heading, which is what `Segmenter.split/1`
  divides on, so the parts of the telling become the sections of the draft
  and a note lands on the movement it is about.

  Deliberately **not** filed into the stack's own folder. A folder is the
  unit a stack is read from, and a draft sitting in it would become document
  112 of 111 — re-read as a chapter of the series it is a summary of, with
  its ordinal shifting everything after it.
  """
  def to_draft(user_id, folder_id) do
    with %Story{} = story <- get_story(folder_id),
         steps <- list_steps(folder_id) do
      Works.create_work(user_id, %{
        "title" => story.title || "A reading",
        "intent" => intent_for(story, steps),
        "body" => draft_body(story)
      })
    else
      nil -> {:error, :not_composed}
    end
  end

  defp intent_for(story, steps) do
    "The method read out of #{length(steps)} documents, in #{length(story.movements)} parts. " <>
      "It is meant to tell somebody building the same thing what to do and in what order, " <>
      "so the test of any paragraph is whether it could be acted on."
  end

  defp draft_body(%Story{} = story) do
    parts =
      story.movements
      |> Enum.with_index(1)
      |> Enum.map(fn {m, i} ->
        [
          "## #{i}. #{m["heading"]}",
          "",
          m["prose"] || "",
          turn_of(m)
        ]
        |> Enum.reject(&(&1 == nil))
        |> Enum.join("\n")
      end)

    ([story.opening || ""] ++ parts ++ ["## Closing", "", story.closing || ""])
    |> Enum.join("\n\n")
    |> String.trim()
  end

  defp turn_of(%{"turn" => t}) when is_binary(t) and t != "", do: "\n> #{t}"
  defp turn_of(_), do: nil
end
