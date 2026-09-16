defmodule Marginalia.Chat.EditorToolsTest do
  @moduledoc """
  The system prompt names tools by hand. For three releases it named two that
  did not exist — `record_correction` and `recall_sessions` — so every promise
  to remember a ruling was empty. This pins prompt and tool surface together.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.Chat.Editor
  alias Marginalia.{Chat, Works}
  import Marginalia.AccountsFixtures

  setup do
    user = user_fixture()
    body = "Chapter 1\n\nShe stood at the window. " <> String.duplicate("word ", 300)
    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    %{work: work, section: hd(Works.list_sections(work.id))}
  end

  defp names, do: Enum.map(Editor.tools(), & &1["function"]["name"])

  defp call(work, name, args) do
    fun = %{"id" => "x", "function" => %{"name" => name, "arguments" => Jason.encode!(args)}}
    :erlang.apply(Editor, :run_call, [work, fun])["content"] |> Jason.decode!()
  end

  test "every tool the prompt tells the model to call actually exists" do
    prompt = Editor.system_prompt()

    for name <- names() do
      assert is_binary(name)
    end

    # any lower_snake_case token in the prompt that looks like a tool call
    mentioned =
      Regex.scan(~r/\b([a-z][a-z_]{4,})\b(?=\s|,|\.|\)|$)/m, prompt)
      |> Enum.map(&List.last/1)
      |> Enum.uniq()

    # the ones that are unambiguously tool names: they appear in our list, or
    # they are named in a "call X" construction
    called =
      Regex.scan(~r/call(?:ing)?\s+`?([a-z_]{4,})`?/, prompt)
      |> Enum.map(&List.last/1)
      |> Enum.uniq()

    for c <- called do
      assert c in names(), "the prompt says to call #{c}/0 but there is no such tool"
    end

    assert "search_manuscript" in mentioned
  end

  test "the connections tool exposes the cross-section pass" do
    assert "connections" in names()
  end

  describe "record_correction" do
    test "a misread is stored and comes back from recall", %{work: work} do
      out = call(work, "record_correction", %{"kind" => "misread", "about" => "Del leaves in ch 3"})
      assert out["recorded"] == "misread"

      recalled = call(work, "recall_sessions", %{})
      assert [%{"kind" => "misread", "about" => "Del leaves in ch 3"}] = recalled["corrections"]
    end

    test "a ruling keeps the writer's own words", %{work: work} do
      call(work, "record_correction", %{
        "kind" => "ruling",
        "about" => "the prologue should go",
        "ruling" => "I want the prologue. It stays."
      })

      assert [c] = Works.list_corrections(work.id)
      assert c.kind == "ruling"
      assert c.ruling == "I want the prologue. It stays."
    end

    test "an unknown kind is refused rather than stored", %{work: work} do
      out = call(work, "record_correction", %{"kind" => "vibes", "about" => "x"})
      assert out["error"] =~ "not recorded"
      assert Works.list_corrections(work.id) == []
    end
  end

  describe "recall_sessions" do
    test "finds what was said in an earlier conversation", %{work: work} do
      {:ok, c} = Chat.get_or_create_conversation(work.id)
      Chat.append(c.id, "user", "I am worried the prologue is doing nothing")
      Chat.append(c.id, "assistant", "The prologue introduces nobody who returns")

      out = call(work, "recall_sessions", %{"query" => "prologue"})
      assert length(out["earlier_talk"]) == 2
      assert Enum.any?(out["earlier_talk"], &(&1["who"] == "assistant"))
    end

    test "no query returns the corrections alone", %{work: work} do
      out = call(work, "recall_sessions", %{})
      assert out["earlier_talk"] == []
    end
  end

  describe "connections" do
    test "reports the cross-section edges with their reasons", %{work: work, section: s} do
      [a, b] =
        Works.insert_nodes(work.id, s.id, [
          %{node_type: "beat", title: "The promise"},
          %{node_type: "beat", title: "The payoff"}
        ])

      Works.link(work.id, a.id, b.id, "pays_off", 0, "the opening promise lands here")

      out = call(work, "connections", %{})
      assert [%{"type" => "pays_off", "why" => "the opening promise lands here"}] = out

      assert call(work, "connections", %{"type" => "tension"}) == %{
               "result" => "no cross-section connections were drawn for this draft yet"
             }
    end
  end
end
