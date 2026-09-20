defmodule Marginalia.Summary do
  @moduledoc """
  What one section of a draft says, read knowing what surrounds it.

  Not a review and not a note in the margin — those exist already and are
  about whether the prose works. This answers the duller and more often
  needed question: I am looking at section seven of twelve, what is in it?

  ## Why the neighbours are in the prompt

  The first version of this sent the section alone. A summary written that
  way re-establishes its own setup, because nothing told it the setup was
  three sections ago, and it cannot say what the section is *for* — which
  is most of what a reader scanning twelve of them wants.

  So the call is given the spine of the whole draft (every section's ordinal
  and title, one line each, which costs almost nothing and does not grow with
  section length) and the summary already written for the section before it,
  when there is one. That is the same arrangement `Stacks.read_step/6` uses,
  and for the same reason: a document read out of its order is a different
  document.

  ## Why `covers` is checked

  Prose is not quote-checkable the way a claim is, so the summary itself is
  taken on trust. Its nouns are not: each term in `covers` has to appear in
  the section, and one that does not is dropped and said so. A summary that
  lists a concept the section never mentions is the failure mode worth
  catching, because it is the one a reader cannot detect without going back
  to the text — which is the thing the summary existed to save them.
  """

  require Logger

  alias Marginalia.{LLM, Repo, Works}
  alias Marginalia.Works.Section

  @tool %{
    "type" => "function",
    "function" => %{
      "name" => "report_section",
      "description" =>
        "Report what this section of the draft contains and where it sits among the others.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "summary" => %{
            "type" => "string",
            "description" =>
              "Three or four sentences saying what is in this section, in the order it " <>
                "appears. Concrete nouns taken from the text itself — \"the out-grammar, " <>
                "kcodegen, and the first emitted module\", never \"technical foundations\". " <>
                "Describe the prose; do not judge it, do not say what is missing, and do " <>
                "not write \"the author argues\". Do not re-explain anything the listed " <>
                "earlier sections have already established — name it and move on."
          },
          "covers" => %{
            "type" => "array",
            "maxItems" => 6,
            "items" => %{"type" => "string"},
            "description" =>
              "The specific things this section deals with, two or three words each, as " <>
                "they are named IN THE SECTION. A program checks every one of these " <>
                "against the text and drops what it cannot find, so a term you inferred " <>
                "rather than read is a discarded entry."
          },
          "follows_from" => %{
            "type" => "array",
            "items" => %{"type" => "integer"},
            "description" =>
              "Ordinals of earlier sections this one leans on — whose material a reader " <>
                "would need before this makes sense. Only from the list you were given, " <>
                "only earlier ones, and empty if it stands on its own."
          },
          "sets_up" => %{
            "type" => "string",
            "description" =>
              "One sentence: what this section leaves in place for the ones after it. " <>
                "Empty string if it closes something rather than opening anything."
          }
        },
        "required" => ["summary", "covers", "follows_from", "sets_up"]
      }
    }
  }

  @prompt """
  You summarise one section of a draft for its own writer, who knows the material and \
  wants to find their place in it.

  You are given the whole draft's section list so you can see where this one sits, and \
  the summary of the section before it when one exists. Use them. A section that \
  continues an argument should say so rather than starting it again, and what a reader \
  needs from earlier belongs in follows_from, not repeated in the summary.

  Say what is in the section, in the order it appears. This is not a review: do not say \
  whether it works, what is missing, or what to do about it.

  Report by calling report_section.
  """

  @body_cap 12_000

  @doc "What a summary is current against."
  def fingerprint(%Section{body: body}),
    do: :crypto.hash(:sha256, body || "") |> Base.encode16(case: :lower)

  @doc "Whether this section's summary still describes its text."
  def current?(%Section{summary: nil}), do: false
  def current?(%Section{summary_fingerprint: f} = s), do: f == fingerprint(s)

  @doc """
  Summarise one section and store it.

  Owner-scoped by the caller: this spends money, so it is reached only from a
  path that has already established whose draft it is.
  """
  def run(%Section{} = section, opts \\ []) do
    body = String.slice(section.body || "", 0, @body_cap)

    if String.trim(body) == "" do
      {:error, :empty}
    else
      siblings = Works.list_sections(section.work_id)
      ask(section, body, siblings, opts)
    end
  end

  # One line per section. It is what lets the model place this one without
  # being handed the text of eleven others, and it costs the same whether the
  # draft is twelve sections or a hundred and eleven.
  @doc false
  def spine(siblings, %Section{ordinal: here}) do
    Enum.map_join(siblings, "\n", fn s ->
      mark = if s.ordinal == here, do: "  <- THIS ONE", else: ""
      "#{s.ordinal}. #{s.title}#{mark}"
    end)
  end

  # The section before, in the words already used for it, so consecutive
  # summaries read as a sequence rather than as twelve unrelated blurbs.
  @doc false
  def previous_block(siblings, %Section{ordinal: here}) do
    case Enum.find(siblings, &(&1.ordinal == here - 1)) do
      %Section{summary: s} = prev when is_binary(s) and s != "" ->
        "\nThe section before this one (#{prev.ordinal}. #{prev.title}) was summarised as:\n#{s}\n"

      _ ->
        ""
    end
  end

  defp ask(section, body, siblings, opts) do
    work = Repo.get!(Marginalia.Works.Work, section.work_id)

    user = """
    Draft: #{work.title}
    #{if work.intent && work.intent != "", do: "What it is meant to do to a reader: #{work.intent}\n", else: ""}
    The sections of this draft, in order:
    #{spine(siblings, section)}
    #{previous_block(siblings, section)}
    THE SECTION TO SUMMARISE — #{section.ordinal}. #{section.title}:

    #{body}
    """

    case LLM.call_tool(
           tool: @tool,
           provider: opts[:provider],
           model: LLM.fast_model(opts[:provider]),
           effort: :low,
           temperature: 0.2,
           max_tokens: 1_200,
           messages: [
             %{"role" => "system", "content" => @prompt},
             %{"role" => "user", "content" => user}
           ]
         ) do
      {:ok, raw} ->
        {attrs, dropped} = validate(raw, body, section.ordinal)
        store(section, attrs, dropped)

      {:error, reason} ->
        Logger.warning("marginalia: summary for section #{section.id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Normalise and check what came back.

  Public because it is pure and because it is the part that can be wrong in a
  way a reader cannot see.
  """
  def validate(raw, body, ordinal) do
    summary = raw |> Map.get("summary") |> trimmed()
    haystack = String.downcase(body)

    {covers, dropped} =
      (raw["covers"] || [])
      |> Enum.map(&trimmed/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.reduce({[], []}, fn term, {keep, bad} ->
        if String.contains?(haystack, String.downcase(term)),
          do: {keep ++ [term], bad},
          else: {keep, bad ++ ["covers: #{inspect(term)} is not in the section"]}
      end)

    {follows, dropped} =
      (raw["follows_from"] || [])
      |> Enum.reduce({[], dropped}, fn n, {keep, bad} ->
        case as_int(n) do
          i when is_integer(i) and i >= 1 and i < ordinal -> {keep ++ [i], bad}
          i when is_integer(i) -> {keep, bad ++ ["follows_from #{i}: not an earlier section"]}
          _ -> {keep, bad ++ ["follows_from #{inspect(n)}: not a number"]}
        end
      end)

    sets_up = raw |> Map.get("sets_up") |> trimmed()

    {%{
       summary: summary,
       summary_covers: Enum.take(covers, 6),
       summary_follows: Enum.uniq(follows),
       summary_sets_up: if(sets_up == "", do: nil, else: sets_up)
     }, dropped}
  end

  defp store(_section, %{summary: ""}, _dropped), do: {:error, :no_summary}

  defp store(section, attrs, dropped) do
    section
    |> Ecto.Changeset.change(
      Map.merge(attrs, %{
        summary_fingerprint: fingerprint(section),
        summarised_at: DateTime.utc_now() |> DateTime.truncate(:second),
        summary_dropped: dropped
      })
    )
    |> Repo.update()
  end

  defp trimmed(v) when is_binary(v), do: String.trim(v)
  defp trimmed(_), do: ""

  defp as_int(v) when is_integer(v), do: v

  defp as_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp as_int(_), do: nil

  @doc "A section by ordinal, for a work the caller has already established is theirs."
  def section(work_id, ordinal), do: Works.get_section(work_id, ordinal)
end
