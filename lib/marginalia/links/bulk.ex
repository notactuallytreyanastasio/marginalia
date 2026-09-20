defmodule Marginalia.Links.Bulk do
  @moduledoc """
  Working out which documents in a pile are worth relating, before relating any.

  Relating two drafts costs a model call over both their maps. A folder of
  twelve is sixty-six pairs; the stack of pull requests is a hundred and
  eleven documents, which is six thousand one hundred and five. Linking
  everything to everything is not expensive, it is impossible, and most of
  the answers would be "these two are both about the compiler".

  So this is two stages, and the first one is cheap.

  ## Triage

  One call. Every document gets one line — its title and the best short
  description already on hand — and the model picks the pairs worth the
  second stage, each with the reason it expects to find something. The spine
  does not grow with document length, so the cost of deciding is the same for
  a folder of twelve as for a hundred and eleven.

  A proposal is not a finding. The model is guessing from one line each about
  what a full pass over two graphs would turn up, and it says so: `why` is a
  hypothesis, and the pair exists to be tested rather than believed.

  ## Relating

  The pairs that survive validation are created and handed to
  `Marginalia.Analysis.Linker`, bounded, because that stage is one call per
  pair and the pair count is what the triage exists to keep small.

  ## What it will not do

  `Linker.run/2` needs both documents to have been read — it works over the
  node maps, and a document nobody has read has none. Unread halves are
  reported by name rather than skipped quietly, because "I related your
  folder" followed by silence about the nine documents that were not eligible
  is the kind of help that costs more than it gives.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Marginalia.{Folders, LLM, Links, Repo, Works}
  alias Marginalia.Analysis.Linker
  alias Marginalia.Works.Work

  @concurrency 3
  @max_pairs 24
  @line_cap 220

  @tool %{
    "type" => "function",
    "function" => %{
      "name" => "propose_links",
      "description" =>
        "Choose which pairs of these documents are worth reading against each other.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "pairs" => %{
            "type" => "array",
            "maxItems" => @max_pairs,
            "description" =>
              "The pairs worth the expensive pass, best first. Far fewer than every " <>
                "combination: a pair belongs here only if you expect a specific relation " <>
                "between specific parts, not because the two share a subject.",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "a" => %{
                  "type" => "integer",
                  "description" => "The number of the first document, from the list given."
                },
                "b" => %{
                  "type" => "integer",
                  "description" => "The number of the second. Must differ from a."
                },
                "why" => %{
                  "type" => "string",
                  "description" =>
                    "One sentence naming what you expect to find between them, concretely. " <>
                      "\"Nine sets up the promise that fourteen pays off\", not \"both " <>
                      "discuss the parser\". This is a hypothesis for the next pass to " <>
                      "test, so it should be falsifiable."
                },
                "expect" => %{
                  "type" => "string",
                  "enum" => ~w(develops pays_off requires tension answers echoes),
                  "description" =>
                    "The relation you expect, from the kinds the linker can record. " <>
                      "A guess; the pass that follows decides."
                }
              },
              "required" => ["a", "b", "why", "expect"]
            }
          },
          "skipped" => %{
            "type" => "string",
            "description" =>
              "One sentence on what you deliberately left out and why. Empty if nothing " <>
                "stood out as a near miss."
          }
        },
        "required" => ["pairs", "skipped"]
      }
    }
  }

  @prompt """
  You are given a list of documents that belong to one writer, one line each, and must \
  choose which PAIRS are worth reading against each other in full.

  The pass that follows is expensive and reads both documents' maps, so the list you \
  return should be short. Two documents sharing a subject is not a reason. A specific \
  part of one standing in a specific relation to a specific part of the other is.

  Prefer pairs that are far apart in the list over adjacent ones: consecutive documents \
  in a series are related by construction and the writer already knows it. What nobody \
  can see unaided is the thing in document four that the thing in document ninety walks \
  back.

  Report by calling propose_links.
  """

  # --- what the model is given ----------------------------------------------

  @doc """
  One line per document: whatever short description already exists for it.

  In preference order, because each is better than the next and all of them
  are already paid for: the step read for it as part of a stack, then its own
  section summaries, then the first impression from its read, then nothing
  but the title. A document with only a title is still offered — the model
  can tell that it has been given little.
  """
  def describe(%Work{} = work) do
    [
      stack_capability(work),
      section_summary(work),
      work.first_impression
    ]
    |> Enum.find(&(is_binary(&1) and String.trim(&1) != ""))
    |> case do
      nil -> ""
      text -> text |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, @line_cap)
    end
  end

  defp stack_capability(%Work{id: id}) do
    Repo.one(
      from s in Marginalia.Stacks.Step,
        where: s.work_id == ^id,
        order_by: [desc: s.id],
        limit: 1,
        select: s.capability
    )
  end

  defp section_summary(%Work{id: id}) do
    Repo.all(
      from s in Works.Section,
        where: s.work_id == ^id and not is_nil(s.summary),
        order_by: [asc: s.ordinal],
        limit: 2,
        select: s.summary
    )
    |> Enum.join(" ")
  end

  @doc "The documents of a folder, with the line each will be described by."
  def sheet(user_id, folder_id) do
    user_id
    |> Works.list_works()
    |> Enum.filter(&(&1.folder_id == folder_id))
    |> Enum.sort_by(& &1.id)
    |> Enum.with_index(1)
    |> Enum.map(fn {w, i} -> %{n: i, work: w, line: describe(w)} end)
  end

  # --- triage ---------------------------------------------------------------

  @doc """
  Ask which pairs are worth relating. One call, whatever the folder's size.
  """
  def propose(sheet, opts \\ []) do
    listing =
      Enum.map_join(sheet, "\n", fn %{n: n, work: w, line: line} ->
        "#{n}. #{w.title}" <> if(line == "", do: "", else: " — #{line}")
      end)

    case LLM.call_tool(
           tool: @tool,
           provider: opts[:provider],
           model: LLM.default_model(opts[:provider]),
           effort: :high,
           temperature: 0.3,
           max_tokens: 3_000,
           messages: [
             %{"role" => "system", "content" => @prompt},
             %{
               "role" => "user",
               "content" => "#{length(sheet)} documents:\n\n#{listing}"
             }
           ]
         ) do
      {:ok, raw} -> {:ok, validate(raw, sheet)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Keep the pairs that name two real, different documents, once each.

  Public because it is pure and because a proposal citing document 140 of a
  folder of twelve reads exactly like one that is real.
  """
  def validate(raw, sheet) do
    by_n = Map.new(sheet, &{&1.n, &1.work})

    {pairs, dropped, _seen} =
      (raw["pairs"] || [])
      |> Enum.filter(&is_map/1)
      |> Enum.reduce({[], [], MapSet.new()}, fn p, {keep, bad, seen} ->
        a = as_int(p["a"])
        b = as_int(p["b"])

        # Unordered, because 3–1 is the pair 1–3 proposed again.
        key = MapSet.new([a, b])

        cond do
          is_nil(a) or is_nil(b) ->
            {keep, bad ++ ["a pair without two numbers: #{inspect(Map.take(p, ["a", "b"]))}"],
             seen}

          a == b ->
            {keep, bad ++ ["#{a} paired with itself"], seen}

          is_nil(by_n[a]) or is_nil(by_n[b]) ->
            missing = Enum.reject([a, b], &Map.has_key?(by_n, &1))
            {keep, bad ++ ["#{inspect(missing)} is not in this folder"], seen}

          MapSet.member?(seen, key) ->
            {keep, bad ++ ["#{a}–#{b} proposed twice"], seen}

          true ->
            {keep ++
               [
                 %{
                   a: by_n[a],
                   b: by_n[b],
                   why: trimmed(p["why"]),
                   expect: trimmed(p["expect"])
                 }
               ], bad, MapSet.put(seen, key)}
        end
      end)

    %{
      pairs: Enum.take(pairs, @max_pairs),
      dropped: dropped,
      skipped: trimmed(raw["skipped"])
    }
  end

  # --- relating -------------------------------------------------------------

  @doc """
  Triage a folder and relate the pairs that come back.

  Returns what happened to every pair, including the ones that could not be
  run. `:propose_only` stops after the cheap stage, which is the sensible
  thing to do the first time on a folder of a hundred.
  """
  def run(user_id, folder_id, opts \\ []) do
    with %{} <- Folders.get_folder(user_id, folder_id),
         sheet when sheet != [] <- sheet(user_id, folder_id),
         {:ok, %{pairs: pairs} = triage} <- propose(sheet, opts) do
      if opts[:propose_only] do
        {:ok, Map.put(triage, :started, [])}
      else
        {:ok, Map.merge(triage, relate(pairs, opts))}
      end
    else
      nil -> {:error, :no_folder}
      [] -> {:error, :empty_folder}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Relate an already-triaged list of pairs.

  Separate from `run/3` so the page can show the proposals, let somebody read
  them, and only then spend anything.
  """
  def relate_pairs(pairs, opts \\ []), do: relate(pairs, opts)

  # Bounded: this stage is one model call per pair over two full graphs, and
  # it is the reason the triage exists.
  defp relate(pairs, opts) do
    {eligible, ineligible_pairs} = Enum.split_with(pairs, &readable?/1)

    started =
      eligible
      |> Task.async_stream(
        fn %{a: a, b: b} = pair ->
          case Links.get_or_create(a.id, b.id) do
            {:ok, link} ->
              Linker.run(link, opts[:provider])
              Map.put(pair, :link_id, link.id)

            {:error, reason} ->
              Map.put(pair, :error, reason)
          end
        end,
        max_concurrency: @concurrency,
        timeout: 300_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, result} -> [result]
        {:exit, _} -> []
      end)

    %{
      started: started,
      not_read: ineligible(ineligible_pairs)
    }
  end

  @doc """
  The pairs that cannot be related, said in full.

  Public because it is the part worth testing and the part most likely to be
  quietly dropped: "I related your folder" with no word about the nine
  documents that were not eligible is worse than doing nothing.
  """
  def ineligible(pairs) do
    pairs
    |> Enum.reject(&readable?/1)
    |> Enum.map(fn %{a: a, b: b} ->
      unread = Enum.reject([a, b], &read?/1) |> Enum.map_join(" and ", & &1.title)
      "#{a.title} ↔ #{b.title}: #{unread} has not been read"
    end)
  end

  defp readable?(%{a: a, b: b}), do: read?(a) and read?(b)
  defp read?(%Work{status: "read"}), do: true
  defp read?(_), do: false

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
end
