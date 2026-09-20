defmodule Marginalia.Document do
  @moduledoc """
  The whole draft, read two ways at once.

  A document is not the sum of its sections and it is not a single long
  paragraph either, and asking one model call to produce both readings gets
  a blend of the two that is neither. So there are two prongs, they run
  concurrently, and they are given different material on purpose:

  ## Composing, upward

  Built from the section summaries — never from the full text. Twelve
  summaries fit in a prompt that does not grow with section length, which is
  what makes this affordable on a draft of twenty thousand words and
  possible at all on one of a hundred and eleven sections. It answers: what
  does this document do, in what order, and what single thread runs through
  it.

  ## Decomposing, downward

  Given the shape of the document rather than a reading of it: title, intent,
  the section titles, and what each section does. It answers a different
  question — what rules is this working under. Not what it says: what it has
  committed to, which is the thing a writer breaks without noticing and
  which no single section contains.

  It is deliberately NOT handed the other prong's throughline. That would
  have been one line shorter and would have anchored the second reading to
  the first; two prongs that agree because one was told what the other said
  are one prong.

  The two are independent, so they are two tasks awaited together rather than
  a chain. The section summaries they both need are themselves fanned out
  first, bounded, because that stage is one call per section and the only
  part of this whose cost grows with the draft.

  Every ordinal either prong cites is checked against the sections that
  actually exist. A guideline attributed to section 14 of a 12-section draft
  is worse than no guideline: it is a claim a reader cannot check without
  going and looking, which is what this was supposed to save them.
  """

  require Logger

  alias Marginalia.{LLM, Repo, Summary, Works}
  alias Marginalia.Works.{DocumentSummary, Work}

  @concurrency 6
  @section_timeout 180_000

  # --- the composing prong ---------------------------------------------------

  @compose_tool %{
    "type" => "function",
    "function" => %{
      "name" => "report_composition",
      "description" =>
        "Report what the whole document does, built from the summaries of its sections.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "summary" => %{
            "type" => "string",
            "description" =>
              "Four to six sentences: what this document does, in the order it does it. " <>
                "Written for somebody deciding whether to read it and where to start. " <>
                "Concrete nouns from the section summaries, not categories. Do not " <>
                "evaluate it, do not say what is missing."
          },
          "throughline" => %{
            "type" => "string",
            "description" =>
              "One sentence naming the single thread that runs through every part. If " <>
                "the parts do not share one, say what they share instead — do not invent " <>
                "a unity the document does not have."
          },
          "movements" => %{
            "type" => "array",
            "maxItems" => 8,
            "description" =>
              "The document divided into the few stretches it actually falls into. Not " <>
                "one per section: a movement usually spans several, and two movements is " <>
                "a legitimate answer for a short document.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "heading" => %{
                  "type" => "string",
                  "description" =>
                    "A claim about what this stretch does, not a label for it. " <>
                      "\"Nothing runs until the emitter is generated\", not \"Setup\"."
                },
                "sections" => %{
                  "type" => "array",
                  "items" => %{"type" => "integer"},
                  "description" =>
                    "The section ordinals in this movement, from the list you were given. " <>
                      "A program checks these and drops any that do not exist."
                },
                "does" => %{
                  "type" => "string",
                  "description" => "One sentence: what the reader has after this stretch."
                }
              },
              "required" => ["heading", "sections", "does"]
            }
          }
        },
        "required" => ["summary", "throughline", "movements"]
      }
    }
  }

  @compose_prompt """
  You are given the section-by-section summaries of one document and must say what the \
  document as a whole does.

  Work from the summaries, in order. The value here is the shape that no single section \
  contains: where it turns, what it assumes before it turns, what a reader has at the end \
  that they did not have at the start.

  Do not re-list the sections. A movement spanning sections three to seven is one line, \
  not five. This is not a review: do not say whether it works or what is missing.

  Report by calling report_composition.
  """

  # --- the decomposing prong -------------------------------------------------

  @guide_tool %{
    "type" => "function",
    "function" => %{
      "name" => "report_guidelines",
      "description" =>
        "Report the rules this document is working under, read down from the whole.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "guidelines" => %{
            "type" => "array",
            "maxItems" => 7,
            "description" =>
              "The governing rules this document has committed to — the things it does " <>
                "consistently that a reader would notice if it stopped. Not advice, not " <>
                "what it should do: what it IS doing, as a rule.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "guideline" => %{
                  "type" => "string",
                  "description" =>
                    "The rule, in one imperative sentence, as this document practises it. " <>
                      "\"Name the failing case before the fix for it\", not \"clarity\"."
                },
                "because" => %{
                  "type" => "string",
                  "description" =>
                    "One sentence: what this rule buys the reader, or what it prevents."
                },
                "sections" => %{
                  "type" => "array",
                  "items" => %{"type" => "integer"},
                  "description" =>
                    "Two or three section ordinals where this is visibly in force. Checked; " <>
                      "ordinals that do not exist are dropped."
                }
              },
              "required" => ["guideline", "because", "sections"]
            }
          },
          "tensions" => %{
            "type" => "array",
            "maxItems" => 4,
            "description" =>
              "Places two of the rules above pull against each other. Empty if they do " <>
                "not — a document with no tensions is a real answer and inventing one is " <>
                "worse than reporting none.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "tension" => %{
                  "type" => "string",
                  "description" => "One sentence naming the pull, and between which rules."
                },
                "sections" => %{
                  "type" => "array",
                  "items" => %{"type" => "integer"},
                  "description" => "Where it shows. Checked."
                }
              },
              "required" => ["tension", "sections"]
            }
          }
        },
        "required" => ["guidelines", "tensions"]
      }
    }
  }

  @guide_prompt """
  You are given the shape of a document — its title, what it is meant to do, its section \
  titles, and the thread running through it — and must name the rules it is working under.

  A guideline here is something the document does consistently and would be noticed for \
  breaking. It is descriptive, not prescriptive: you are reading the practice off the \
  document, not recommending one. A rule you cannot point at two sections for is not a \
  rule this document has.

  Report by calling report_guidelines.
  """

  # --- running both ----------------------------------------------------------

  @doc """
  Summarise the whole document.

  Fans out the section summaries that are missing or stale, then runs the two
  prongs concurrently. `:force` re-summarises every section rather than only
  the stale ones.
  """
  def run(%Work{} = work, opts \\ []) do
    sections = Works.list_sections(work.id)

    if sections == [] do
      {:error, :no_sections}
    else
      sections = fan_out_sections(sections, opts)
      compose_and_decompose(work, sections, opts)
    end
  end

  # One call per section, and the only stage whose cost grows with the draft.
  # Bounded rather than unbounded: a hundred and eleven sections at once is a
  # rate limit, and `deepen_step`'s own comment records what that cost the
  # last time it was tried.
  defp fan_out_sections(sections, opts) do
    todo =
      if opts[:force],
        do: sections,
        else: Enum.reject(sections, &Summary.current?/1)

    if todo != [] do
      todo
      |> Task.async_stream(&Summary.run(&1, opts),
        max_concurrency: @concurrency,
        timeout: @section_timeout,
        on_timeout: :kill_task
      )
      |> Stream.run()
    end

    Works.list_sections(hd(sections).work_id)
  end

  defp compose_and_decompose(work, sections, opts) do
    summarised = Enum.filter(sections, & &1.summary)

    if summarised == [] do
      {:error, :no_summaries}
    else
      # Truly concurrent, and independent on purpose. Feeding the composition's
      # throughline into the guidelines pass would have been one line shorter
      # and would have anchored the second reading to the first — two prongs
      # that agree because one was told what the other said are one prong.
      tasks = [
        Task.async(fn -> {:compose, compose(work, summarised, opts)} end),
        Task.async(fn -> {:guidelines, guidelines(work, sections, summarised, opts)} end)
      ]

      results = tasks |> Task.await_many(@section_timeout) |> Map.new()

      case results do
        %{compose: {:ok, comp}, guidelines: {:ok, guide}} ->
          store(work, sections, comp, guide)

        %{compose: {:ok, comp}, guidelines: {:error, reason}} ->
          store_partial(work, sections, comp, reason)

        %{compose: {:error, reason}} ->
          {:error, reason}
      end
    end
  end

  defp compose(work, summarised, opts) do
    spine =
      Enum.map_join(summarised, "\n\n", fn s ->
        "#{s.ordinal}. #{s.title}\n#{s.summary}" <>
          if(s.summary_sets_up, do: "\n(sets up: #{s.summary_sets_up})", else: "")
      end)

    call(
      @compose_tool,
      @compose_prompt,
      """
      Document: #{work.title}
      #{intent_line(work)}
      #{length(summarised)} sections, summarised, in order:

      #{spine}
      """,
      opts,
      3_000
    )
  end

  defp guidelines(work, sections, summarised, opts) do
    titles = Enum.map_join(sections, "\n", &"#{&1.ordinal}. #{&1.title}")

    # Its own material, not the other prong's conclusion: the section
    # summaries, which is what lets it read a practice off the document
    # instead of agreeing with a throughline it was handed.
    what = Enum.map_join(summarised, "\n", &"#{&1.ordinal}. #{&1.summary}")

    call(
      @guide_tool,
      @guide_prompt,
      """
      Document: #{work.title}
      #{intent_line(work)}
      Its sections:
      #{titles}

      What each section does:
      #{what}
      """,
      opts,
      2_500
    )
  end

  defp intent_line(%Work{intent: i}) when is_binary(i) and i != "",
    do: "What it is meant to do to a reader: #{i}\n"

  defp intent_line(_), do: ""

  defp call(tool, prompt, user, opts, max_tokens) do
    LLM.call_tool(
      tool: tool,
      provider: opts[:provider],
      model: LLM.default_model(opts[:provider]),
      effort: :high,
      temperature: 0.3,
      max_tokens: max_tokens,
      messages: [
        %{"role" => "system", "content" => prompt},
        %{"role" => "user", "content" => user}
      ]
    )
  end

  # --- checking and storing --------------------------------------------------

  @doc """
  Drop every citation to a section that does not exist.

  Public because it is pure and because it is the part that can be wrong
  invisibly: a guideline attributed to section 14 of a twelve-section draft
  reads exactly like one that is true.
  """
  def validate(comp, guide, sections) do
    ordinals = MapSet.new(sections, & &1.ordinal)

    {movements, dropped} = check_list(comp["movements"] || [], ordinals, "movement", [])
    {rules, dropped} = check_list(guide["guidelines"] || [], ordinals, "guideline", dropped)
    {tensions, dropped} = check_list(guide["tensions"] || [], ordinals, "tension", dropped)

    {%{
       summary: trimmed(comp["summary"]),
       throughline: trimmed(comp["throughline"]),
       movements: movements,
       guidelines: rules,
       tensions: tensions
     }, dropped}
  end

  defp check_list(items, ordinals, label, dropped) do
    items
    |> Enum.filter(&is_map/1)
    |> Enum.reduce({[], dropped}, fn item, {keep, bad} ->
      cited = item["sections"] || []
      good = Enum.filter(cited, &(is_integer(&1) and MapSet.member?(ordinals, &1)))
      missing = Enum.reject(cited, &(&1 in good))

      bad =
        if missing == [],
          do: bad,
          else: bad ++ ["#{label}: cites #{inspect(missing)}, which are not sections here"]

      {keep ++ [Map.put(item, "sections", good)], bad}
    end)
  end

  defp trimmed(v) when is_binary(v), do: String.trim(v)
  defp trimmed(_), do: ""

  @doc """
  What a document summary is current against.

  Both the section's current text and the summary written for it. The first
  version hashed only the stored `summary_fingerprint`, which is the hash of
  the body *at the time it was summarised* — so editing a section left it
  untouched and the document summary went on claiming to be current while
  standing on prose that had changed underneath it. The body covers the edit,
  the summary text covers a re-run that reworded it.
  """
  def fingerprint(sections) do
    sections
    |> Enum.map(fn s ->
      "#{s.ordinal}:#{Summary.fingerprint(s)}:#{:erlang.phash2(s.summary)}"
    end)
    |> Enum.join("|")
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc "Whether the document summary still matches the sections underneath it."
  def current?(%Work{} = work) do
    case get(work.id) do
      nil -> false
      doc -> doc.fingerprint == fingerprint(Works.list_sections(work.id))
    end
  end

  @doc "The stored document summary, or nil."
  def get(work_id), do: Repo.get_by(DocumentSummary, work_id: work_id)

  defp store(work, sections, comp, guide) do
    {attrs, dropped} = validate(comp, guide, sections)
    upsert(work, sections, attrs, dropped)
  end

  # The composing prong landed and the decomposing one did not. Keeping half
  # is right — it is the half that took one call per section to produce — but
  # it is recorded as half rather than presented as whole.
  defp store_partial(work, sections, comp, reason) do
    Logger.warning("marginalia: guidelines pass failed for work #{work.id}: #{inspect(reason)}")

    {attrs, dropped} = validate(comp, %{}, sections)
    upsert(work, sections, attrs, dropped ++ ["the guidelines pass failed: #{inspect(reason)}"])
  end

  defp upsert(work, sections, attrs, dropped) do
    existing = get(work.id) || %DocumentSummary{}

    existing
    |> DocumentSummary.changeset(
      Map.merge(attrs, %{
        work_id: work.id,
        fingerprint: fingerprint(sections),
        dropped: dropped
      })
    )
    |> Repo.insert_or_update()
  end
end
