defmodule Marginalia.Summary do
  @moduledoc """
  What one section of a draft actually says, in a few lines.

  Not a review and not a note in the margin — those exist already and are
  about whether the prose works. This answers the duller and more often
  needed question: I am looking at section seven of twelve, what is in it?

  Run per section, on request, because a draft here can be a hundred and
  eleven documents and summarising all of them unasked is a bill nobody
  agreed to. Cached against a fingerprint of the text, so a section edited
  after it was summarised says so rather than describing prose that has
  since been rewritten.
  """

  require Logger

  alias Marginalia.{LLM, Repo, Works}
  alias Marginalia.Works.Section

  @tool %{
    "type" => "function",
    "function" => %{
      "name" => "report_summary",
      "description" => "Report what this section of the draft says.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "summary" => %{
            "type" => "string",
            "description" =>
              "Three or four sentences saying what this section contains, in the order it " <>
                "contains it. Describe the prose, do not judge it. No praise, no advice, " <>
                "no 'the author argues' — say what is on the page as if summarising a " <>
                "chapter for somebody deciding whether to read it."
          }
        },
        "required" => ["summary"]
      }
    }
  }

  @prompt """
  You summarise one section of a draft for its own writer, who knows the material and \
  wants to find their place in it.

  Say what is in the section, in the order it appears. Concrete nouns from the text \
  itself, not categories: "the out-grammar, kcodegen, and the first emitted module", \
  not "technical foundations".

  This is not a review. Do not say whether it works, what is missing, or what to do \
  about it. Report by calling report_summary.
  """

  @body_cap 12_000

  @doc "What a summary is current against."
  def fingerprint(%Section{body: body}),
    do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

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
      ask(section, body, opts)
    end
  end

  defp ask(section, body, opts) do
    case LLM.call_tool(
           tool: @tool,
           provider: opts[:provider],
           model: LLM.fast_model(opts[:provider]),
           effort: :low,
           temperature: 0.2,
           max_tokens: 900,
           messages: [
             %{"role" => "system", "content" => @prompt},
             %{
               "role" => "user",
               "content" => "Section #{section.ordinal}: #{section.title}\n\n#{body}"
             }
           ]
         ) do
      {:ok, %{"summary" => text}} when is_binary(text) ->
        store(section, String.trim(text))

      {:ok, _} ->
        {:error, :no_summary}

      {:error, reason} ->
        Logger.warning("marginalia: summary for section #{section.id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp store(_section, ""), do: {:error, :no_summary}

  defp store(section, text) do
    section
    |> Ecto.Changeset.change(
      summary: text,
      summary_fingerprint: fingerprint(section),
      summarised_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update()
  end

  @doc "A section by ordinal, for a work the caller has already established is theirs."
  def section(work_id, ordinal), do: Works.get_section(work_id, ordinal)
end
