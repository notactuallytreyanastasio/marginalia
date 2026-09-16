defmodule Marginalia.EffortTest do
  @moduledoc """
  Reasoning tokens are billed as output and are never cached, so which passes
  think hard is the biggest single lever on the bill. This pins the choice so
  a future edit cannot quietly turn it back up everywhere.
  """
  use ExUnit.Case, async: true

  # the call sites, read out of the source rather than restated, so this test
  # fails if the effort moves rather than passing on a stale copy of it
  @sources %{
    "per-section beats" => {"lib/marginalia/analysis.ex", "@beats_prompt", :none},
    "the spine" => {"lib/marginalia/analysis.ex", "@spine_prompt", :high},
    "the weave" => {"lib/marginalia/analysis/weave.ex", "@weave_prompt", :high},
    "the narratives" => {"lib/marginalia/analysis/decision_graph.ex", "@narrative_prompt", :high},
    "the graph build" => {"lib/marginalia/analysis/decision_graph.ex", "@graph_prompt", :high}
  }

  test "effort is set per call, not per deploy" do
    body = File.read!("lib/marginalia/llm.ex")
    assert body =~ "put_effort"
    assert body =~ ~s(default_body: %{"reasoning_effort" => "low"})
  end

  for {name, {file, marker, effort}} <- @sources do
    test "#{name} runs at #{effort} effort" do
      source = File.read!(unquote(file))

      # find the call that uses this prompt, and read the effort next to it
      [_, after_marker] = String.split(source, unquote(marker) <> "}", parts: 2)
      window = String.slice(after_marker, 0, 600)

      case unquote(effort) do
        :high -> assert window =~ "effort: :high" or preceding_effort(source, unquote(marker)) == "high"
        :none -> assert preceding_effort(source, unquote(marker)) == "none"
      end
    end
  end

  # the effort flag sits above the messages list, so look backwards from the
  # prompt reference to the nearest one
  defp preceding_effort(source, marker) do
    case String.split(source, marker <> "}", parts: 2) do
      [before, _] ->
        case Regex.scan(~r/effort: :(\w+)/, before) do
          [] -> nil
          matches -> matches |> List.last() |> List.last()
        end

      _ ->
        nil
    end
  end
end
