defmodule Marginalia.PromptsTest do
  @moduledoc """
  What every pass is told, checked for the things a prompt teaches by accident.

  A prompt's examples are not illustrations, they are the format. The beats
  pass said to write a title as "He sets June 2020 as the baseline", and so
  every beat in the database says "He shows", "He reduces", "He makes" — of
  writers nobody has ever met and whose gender no draft states. One word in
  one example, thousands of rows downstream.

  Nothing else in the system would ever have failed over it, which is what
  this file is for.
  """
  use ExUnit.Case, async: true

  alias Marginalia.{Analysis, Rewrite}
  alias Marginalia.Analysis.{DecisionGraph, Linker, Weave}

  # every pass that ships a prompt, by the module that owns it
  defp all_passes do
    Analysis.passes() ++
      Linker.passes() ++
      Weave.passes() ++
      Rewrite.passes() ++
      DecisionGraph.passes() ++
      Marginalia.Links.Chat.passes() ++
      Marginalia.Cases.Chat.passes()
  end

  describe "pronouns" do
    # The rule is not "always they" — that would flatten a character the
    # manuscript has already told you about. It is: never *assume*. A
    # pronoun is a fact to be read off the page, like any other, and the
    # prompts are where the difference gets taught or lost.
    @gendered ~r/\b(he|him|his|she|her|hers)\b/i
    @rule ~r/never assume anyone's gender/i

    test "a prompt may use a gendered pronoun only if it also says not to assume" do
      # An example like "quote what she has said elsewhere" is legitimate —
      # the writer asking the question already said "she". What is not
      # legitimate is a prompt that shows one without ever stating where a
      # pronoun is supposed to come from, which is how the beats pass came
      # to describe 3,537 writers as "he".
      offenders =
        for pass <- all_passes(),
            prompt = pass.prompt || "",
            prompt =~ @gendered,
            not (prompt =~ @rule) do
          hits = Regex.scan(@gendered, prompt) |> Enum.map(&hd/1) |> Enum.uniq()
          "#{pass.id}: #{Enum.join(hits, ", ")}"
        end

      assert offenders == [],
             "these prompts model a pronoun without saying where one comes from, and every " <>
               "row they produce inherits the guess:\n  " <> Enum.join(offenders, "\n  ")
    end

    test "the passes that write about the writer state the rule outright" do
      for id <- ["beats", "link"] do
        pass = Enum.find(all_passes(), &(&1.id == id))
        assert pass, "#{id} is a pass that names the writer, and it is missing"

        assert pass.prompt =~ @rule,
               "#{id} shows the convention but never states it; the next edit to the " <>
                 "example silently undoes it"
      end
    end

    test "the beats prompt shows the writer as they, since the example is the format" do
      beats = Enum.find(all_passes(), &(&1.id == "beats"))
      assert beats.prompt =~ "They set June 2020 as the baseline"
      refute beats.prompt =~ ~r/\bHe sets\b/
    end

    test "the rule covers characters as well as the writer" do
      beats = Enum.find(all_passes(), &(&1.id == "beats"))

      assert beats.prompt =~ ~r/calls her she/i,
             "a character the draft has already gendered keeps those pronouns"
    end

    test "the passes that are not in the pass list are covered too" do
      # `Summary` and `Document` have no `passes/0` — they are reached from
      # the Read tab rather than the pass list, which is exactly how they
      # would have been missed. Read from source, since neither exposes its
      # prompt.
      for file <- ["lib/marginalia/summary.ex", "lib/marginalia/document.ex"] do
        for [_, body] <- Regex.scan(~r/@prompt """\n(.*?)\n  """/s, File.read!(file)) do
          assert not (body =~ @gendered) or body =~ @rule,
                 "#{file} models a gendered pronoun without stating the rule"
        end
      end
    end

    test "the editor, which talks about characters most, carries the rule" do
      # Not a `passes/0` entry either, and the one prompt where following a
      # stated pronoun actually comes up every conversation.
      assert Marginalia.Chat.Editor.system_prompt() =~ @rule
    end
  end

  describe "the linker's naming convention" do
    test "it requires the full form, because a bare letter cannot be resolved" do
      # `Links.plain/2` substitutes the real titles in. A lone "A" is
      # indistinguishable from the article, so the prompt has to stop
      # producing them rather than the substitution having to guess.
      assert Linker.prompt() =~ "Never a bare"
      assert Linker.prompt() =~ ~r/Manuscript A.*IN FULL|IN FULL.*Manuscript/s
    end
  end
end
