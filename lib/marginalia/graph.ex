defmodule Marginalia.Graph do
  @moduledoc """
  The knowledge graph, in the shape the deciduous explorers already speak.

  `export/1` emits `{nodes, edges, themes, node_themes}` with a `metadata_json`
  string on every node — the same envelope the graph viewers in the blog read,
  so a manuscript analysed here can be dropped into one of those explorers, or
  into `deciduous`, without a translation layer.

  The mapping is deliberate rather than clever:

  | Marginalia | deciduous | why |
  |---|---|---|
  | spine     | goal        | the chain the whole draft hangs off |
  | beat      | action      | something that happens on the page |
  | thread    | observation | a pattern across sections, not an event |
  | question  | decision    | an open choice the writer has not made |

  `metadata_json.branch` carries the section, which is what the explorers group
  and colour by, so a manuscript's sections behave exactly like a book's
  chapters over there.
  """

  alias Marginalia.Works

  @type_map %{
    "spine" => "goal",
    "beat" => "action",
    "thread" => "observation",
    "question" => "decision"
  }

  @doc "The whole graph for one work, ready to encode as JSON."
  def export(work) do
    sections = Works.list_sections(work.id)
    section_by_id = Map.new(sections, &{&1.id, &1})
    nodes = Works.list_nodes(work.id)
    edges = Works.list_edges(work.id)

    %{
      work: %{
        id: work.id,
        title: work.title,
        intent: work.intent,
        words: work.word_count,
        sections: length(sections),
        status: work.status,
        first_impression: work.first_impression,
        exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      nodes: Enum.map(nodes, &node_json(&1, section_by_id)),
      edges: Enum.map(edges, &edge_json/1),
      # no theme layer yet — emitted empty so the explorers, which expect the
      # keys, render rather than crash
      themes: [],
      node_themes: []
    }
  end

  def to_json(work), do: work |> export() |> Jason.encode!(pretty: true)

  defp node_json(n, section_by_id) do
    section = n.section_id && Map.get(section_by_id, n.section_id)

    branch =
      cond do
        section -> "section-#{section.ordinal}"
        n.node_type == "spine" -> "spine"
        true -> n.node_type <> "s"
      end

    %{
      id: n.id,
      node_type: Map.get(@type_map, n.node_type, n.node_type),
      # the native type is kept too, so a round trip back into Marginalia
      # doesn't have to guess
      marginalia_type: n.node_type,
      title: n.title,
      description: description(n),
      # the viewer wants these apart, not glued into one string
      body: n.body,
      quote: n.quote,
      narrative: n.narrative,
      section: section && section.title,
      section_ordinal: section && section.ordinal,
      status: n.status || "pending",
      created_at: n.inserted_at,
      metadata_json:
        Jason.encode!(%{
          branch: branch,
          section: section && section.title,
          narrative: n.narrative,
          ordinal: n.ordinal,
          status: n.status,
          anchored: n.quote not in [nil, ""]
        })
    }
  end

  # The explorers render a trailing "Sources:" block as a quieter footnote,
  # which is exactly what the anchoring quote is.
  defp description(%{body: body, quote: q}) when is_binary(q) and q != "" do
    [body, "Sources:", "- \"#{String.replace(q, "\n", " ")}\""]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp description(%{body: body}), do: body

  defp edge_json(e) do
    %{
      id: e.id,
      from_node_id: e.from_id,
      to_node_id: e.to_id,
      edge_type: e.edge_type,
      weight: 1.0,
      # the model's own reason for drawing this edge — the commentary that
      # makes the graph readable instead of merely shaped
      rationale: e.rationale,
      created_at: e.inserted_at
    }
  end

  @doc """
  Graphviz DOT, for anyone who would rather look at it in a tool than a tab.
  """
  def to_dot(work) do
    %{nodes: nodes, edges: edges} = export(work)
    by_id = Map.new(nodes, &{&1.id, &1})

    lines =
      ["digraph marginalia {", "  rankdir=TB;", "  node [shape=box, style=rounded];"] ++
        Enum.map(nodes, fn n ->
          ~s(  n#{n.id} [label="#{escape(n.title)}", color="#{colour(n.marginalia_type)}"];)
        end) ++
        Enum.map(edges, fn e ->
          style = if e.edge_type == "follows", do: "solid", else: "dashed"

          if Map.has_key?(by_id, e.from_node_id) and Map.has_key?(by_id, e.to_node_id) do
            ~s(  n#{e.from_node_id} -> n#{e.to_node_id} [style=#{style}, label="#{e.edge_type}"];)
          end
        end) ++ ["}"]

    lines |> Enum.reject(&is_nil/1) |> Enum.join("\n")
  end

  defp colour("goal"), do: "#8a3324"
  defp colour("option"), do: "#b45309"
  defp colour("decision"), do: "#1e3a8a"
  defp colour("action"), do: "#166534"
  defp colour("outcome"), do: "#0891b2"
  defp colour("observation"), do: "#6b665e"
  defp colour("revisit"), do: "#7c2d92"
  defp colour("spine"), do: "#8a3324"
  defp colour("beat"), do: "#166534"
  defp colour("thread"), do: "#0891b2"
  defp colour("question"), do: "#7c2d92"
  defp colour(_), do: "#9a948a"

  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", " ")
    |> String.slice(0, 90)
  end

  @doc "Counts for the graph view header."
  def stats(work) do
    %{nodes: nodes, edges: edges} = export(work)

    %{
      nodes: length(nodes),
      edges: length(edges),
      anchored: Enum.count(nodes, &(Jason.decode!(&1.metadata_json)["anchored"] == true)),
      by_type: Enum.frequencies_by(nodes, & &1.marginalia_type)
    }
  end
end
