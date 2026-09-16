defmodule Marginalia.Analysis.Weave do
  @moduledoc """
  Pass 3 — the connections the first two passes cannot see.

  The Read produces beats section by section, and the synthesis produces a
  spine and threads over the top. Between them they leave a map whose only
  edges are *document order* inside a section and the spine's own chain: a
  stack of lists, not a model of an argument. Nothing says that the claim in
  section 4 is the one section 1 promised, that a thread runs through these
  six beats and not those, or that this passage only lands if the reader has
  already been given that one.

  This pass draws those. It is the difference between "here is what the draft
  contains, in order" and "here is what leads to what".

  Five relations, and they are deliberately few — a vocabulary a writer can
  hold in their head while reading the graph:

  | edge | means |
  |---|---|
  | `develops`   | the later beat builds directly on the earlier one |
  | `pays_off`   | the later beat delivers on a promise the earlier one made |
  | `requires`   | the later beat only works if the reader already has the earlier |
  | `tension`    | the two pull against each other; the draft may not have noticed |
  | `realises`   | this beat is where a spine node or thread actually happens |

  Two rules are enforced in code rather than asked for:

  * **Both ends must exist.** An edge to an invented id is dropped, not stored.
  * **Time flows forward.** Between two beats, an edge always runs from the
    earlier position in the manuscript to the later one; a backwards edge is
    flipped rather than discarded, because the model usually has the relation
    right and the direction backwards.
  """

  require Logger

  alias Marginalia.{LLM, Works}

  @types ~w(develops pays_off requires tension realises asks_about)

  # Enough to connect a real manuscript, few enough that the graph stays
  # readable. A model asked for "all the connections" returns a mesh.
  @max_edges 160

  def types, do: @types

  @weave_prompt """
  You are given the complete map of a manuscript: every beat in document order, plus the
  spine and the threads drawn over them. You are NOT given the full text and must not
  pretend you have it.

  Your job is the part the earlier passes could not do: say what leads to what.

  So far the only connections in this map are "these two beats are next to each other on the
  page" and "the spine runs in this order". That is not a model of an argument. Find the real
  ones — especially the ones that cross sections, because those are the ones a writer cannot
  see while working inside a single chapter.

  Return JSON:
  {"edges": [{"from": <id>, "to": <id>, "type": "...", "why": "..."}]}

  TYPES
    develops  the later beat builds directly on the earlier one — same idea, carried further
    pays_off  the later beat delivers on a promise, setup or question the earlier one made
    requires  the later beat only works if the reader already has the earlier one
    tension   the two pull against each other, and the draft may not have noticed
    realises  this beat is where a spine node or a thread actually happens on the page
    asks_about  this open question is about this beat — every question should have one

  RULES
  - Use the numeric ids exactly as given. An id that is not in the list gets the edge thrown away.
  - Prefer connections that CROSS sections. Two adjacent beats in the same section are already
    joined by document order; saying so again adds nothing.
  - Every spine node should be linked by `realises` to the one or two beats where it actually
    happens. Every thread should be linked by `realises` to the beats it runs through.
  - Every open question should be linked by `asks_about` to the beat or beats it is asking
    about. A question floating loose is a question the writer cannot act on.
  - "why": one sentence, concrete to this draft, naming what passes between the two. Not
    "these are related". This sentence is shown to the writer beside the edge.
  - A `tension` edge is a real claim: only draw one where the draft genuinely asserts two
    things that sit badly together. Do not manufacture them for interest.
  - Quality over count. Thirty edges that are true beat a hundred that are plausible.
  """

  def prompt, do: @weave_prompt

  def passes do
    [
      %{
        id: "weave",
        name: "Pass 3 — what leads to what",
        model: LLM.default_model(),
        runs: "once, over the whole map",
        produces: "cross-section edges: develops, pays_off, requires, tension, realises",
        prompt: @weave_prompt
      }
    ]
  end

  @doc """
  Draw the cross-section connections for a work that has been read.

  Returns `{:ok, count}`. A failure here degrades rather than voids the read:
  the beats and the spine are already stored and useful without it.
  """
  def run(work, provider \\ nil) do
    nodes = Works.list_nodes(work.id)
    sections = Works.list_sections(work.id)
    beats = Enum.filter(nodes, &(&1.node_type == "beat"))

    if length(beats) < 2 do
      {:ok, 0}
    else
      case LLM.json(
             provider: provider,
             model: LLM.default_model(provider),
             # one call, and the one that decides what leads to what
             effort: :high,
             temperature: 0.4,
             max_tokens: 8_000,
             messages: [
               %{"role" => "system", "content" => @weave_prompt},
               %{"role" => "user", "content" => inventory(work, sections, nodes)}
             ]
           ) do
        {:ok, %{"edges" => edges}} when is_list(edges) ->
          {:ok, store(work, nodes, edges)}

        {:ok, _} ->
          {:error, :no_edges}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # The model needs ids it can point at and enough context to know what each
  # node is, without being handed the manuscript again.
  defp inventory(work, sections, nodes) do
    by_section = Enum.group_by(nodes, & &1.section_id)

    beats =
      Enum.map_join(sections, "\n\n", fn s ->
        lines =
          by_section
          |> Map.get(s.id, [])
          |> Enum.filter(&(&1.node_type == "beat"))
          |> Enum.map_join("\n", &"  [#{&1.id}] #{&1.title}#{note(&1)}")

        "## Section #{s.ordinal}: #{s.title}\n#{lines}"
      end)

    loose = fn type, label ->
      case Enum.filter(nodes, &(&1.node_type == type)) do
        [] -> ""
        list -> "\n\n## #{label}\n" <> Enum.map_join(list, "\n", &"  [#{&1.id}] #{&1.title}#{note(&1)}")
      end
    end

    """
    Manuscript: #{work.title}
    #{if work.intent && work.intent != "", do: "Intended effect on a reader: #{work.intent}\n", else: ""}
    #{beats}#{loose.("spine", "Spine")}#{loose.("thread", "Threads")}#{loose.("question", "Open questions")}
    """
  end

  defp note(%{body: b}) when is_binary(b) and b != "", do: " — #{String.slice(b, 0, 160)}"
  defp note(_), do: ""

  defp store(work, nodes, edges) do
    by_id = Map.new(nodes, &{&1.id, &1})

    # document position, for the temporal rule. Spine and thread nodes have no
    # position on the page, so they are exempt rather than guessed at.
    pos =
      nodes
      |> Enum.filter(&(&1.node_type == "beat"))
      |> Enum.sort_by(&{&1.section_id, &1.ordinal, &1.id})
      |> Enum.with_index()
      |> Map.new(fn {n, i} -> {n.id, i} end)

    edges
    |> Enum.filter(&is_map/1)
    |> Enum.map(&normalise(&1, by_id, pos))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(fn {f, t, ty, _w} -> {f, t, ty} end)
    |> Enum.take(@max_edges)
    |> Enum.with_index()
    |> Enum.reduce(0, fn {{from, to, type, why}, i}, n ->
      case Works.link(work.id, from, to, type, 1_000 + i, why) do
        {:ok, _} -> n + 1
        _ -> n
      end
    end)
  end

  defp normalise(edge, by_id, pos) do
    from = as_id(edge["from"])
    to = as_id(edge["to"])
    type = edge["type"]

    cond do
      is_nil(from) or is_nil(to) -> nil
      from == to -> nil
      not Map.has_key?(by_id, from) -> nil
      not Map.has_key?(by_id, to) -> nil
      type not in @types -> nil
      true -> {from, to, type, why(edge)} |> forward(pos)
    end
  end

  # Time flows forward. Between two beats the edge runs earlier -> later; the
  # model usually has the relation right and the direction backwards, so flip
  # rather than discard. `realises` is exempt: it points from the spine node
  # or thread, which has no position, at the beat that realises it.
  defp forward({from, to, "realises", why}, _pos), do: {from, to, "realises", why}
  defp forward({from, to, "asks_about", why}, _pos), do: {from, to, "asks_about", why}

  defp forward({from, to, type, why} = edge, pos) do
    case {Map.get(pos, from), Map.get(pos, to)} do
      {a, b} when is_integer(a) and is_integer(b) and a > b -> {to, from, type, why}
      _ -> edge
    end
  end

  defp why(%{"why" => w}) when is_binary(w) and w != "" do
    w |> String.replace(~r/\s+/, " ") |> String.trim() |> String.slice(0, 400)
  end

  defp why(_), do: nil

  defp as_id(n) when is_integer(n), do: n

  defp as_id(n) when is_binary(n) do
    case Integer.parse(String.trim_leading(n, "[")) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp as_id(_), do: nil
end
