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
  alias Marginalia.Stacks.Step
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
            {keep, bad ++ ["excerpt: #{String.slice(q, 0, 50) |> inspect()} is not in the document"]}

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
      dropped: steps |> Enum.map(&length(&1.dropped || [])) |> Enum.sum()
    }
  end
end
