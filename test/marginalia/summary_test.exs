defmodule Marginalia.SummaryTest do
  @moduledoc """
  A summary of a section, and knowing when it has stopped being true.

  A summary of prose that has since been rewritten is worse than none: it is
  a confident description of text that is not there.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Repo, Summary, Works}

  setup do
    user = user_fixture()

    body =
      "# One\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 300) <> "\n\n# Two\n\nBRAVO. " <> String.duplicate("word ", 300)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    %{work: work, section: hd(Works.list_sections(work.id))}
  end

  test "a section with no summary is not current", %{section: section} do
    refute Summary.current?(section)
  end

  test "a stored summary is current against the text it was made from", %{section: section} do
    {:ok, section} =
      section
      |> Ecto.Changeset.change(
        summary: "It sets up alpha.",
        summary_fingerprint: Summary.fingerprint(section)
      )
      |> Repo.update()

    assert Summary.current?(section)
  end

  test "editing the section makes its summary stale", %{work: work, section: section} do
    {:ok, section} =
      section
      |> Ecto.Changeset.change(
        summary: "It sets up alpha.",
        summary_fingerprint: Summary.fingerprint(section)
      )
      |> Repo.update()

    assert Summary.current?(section)

    block =
      section.body
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.find(&String.contains?(&1, "ALPHA"))

    {:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))

    refute Summary.current?(Repo.reload!(section)),
           "a summary of prose that has been rewritten describes text that is not there"

    assert Repo.reload!(section).summary == "It sets up alpha.",
           "the stale summary is kept and marked, not silently deleted"

    assert work.id
  end

  test "an empty section is refused before any call is made", %{section: section} do
    assert Summary.run(%{section | body: "   "}) == {:error, :empty}
  end

  test "the fingerprint changes with the text and not with anything else", %{section: section} do
    a = Summary.fingerprint(section)
    assert a == Summary.fingerprint(%{section | title: "A different title"})
    refute a == Summary.fingerprint(%{section | body: section.body <> " more"})
  end

  describe "the prompt knows where the section sits" do
    test "the spine lists every section and marks this one", %{work: work, section: section} do
      siblings = Works.list_sections(work.id)
      spine = Summary.spine(siblings, section)

      assert spine =~ "1. One"
      assert spine =~ "2. Two"
      assert spine =~ "<- THIS ONE"
      assert length(String.split(spine, "\n")) == length(siblings)
    end

    test "the section before is handed over in the words already used for it", %{work: work} do
      [first, second] = Works.list_sections(work.id)

      {:ok, _} =
        first
        |> Ecto.Changeset.change(summary: "It establishes alpha.")
        |> Repo.update()

      block = Summary.previous_block(Works.list_sections(work.id), second)

      assert block =~ "It establishes alpha."
      assert block =~ "1. One"
    end

    test "the first section has no previous block rather than an empty one", %{work: work} do
      [first | _] = Works.list_sections(work.id)
      assert Summary.previous_block(Works.list_sections(work.id), first) == ""
    end

    test "an unsummarised predecessor contributes nothing", %{work: work} do
      [_, second] = Works.list_sections(work.id)
      assert Summary.previous_block(Works.list_sections(work.id), second) == ""
    end
  end

  describe "validate/3" do
    @body "The out-grammar declares the syntax, and kcodegen expands it into Blimp.kt."

    test "a term that is really in the section is kept" do
      {attrs, dropped} =
        Summary.validate(
          %{"summary" => "It sets up the emitter.", "covers" => ["out-grammar", "kcodegen"]},
          @body,
          3
        )

      assert attrs.summary_covers == ["out-grammar", "kcodegen"]
      assert dropped == []
    end

    test "a term the section never mentions is dropped and said so" do
      {attrs, dropped} =
        Summary.validate(
          %{"summary" => "s", "covers" => ["out-grammar", "monad transformers"]},
          @body,
          3
        )

      assert attrs.summary_covers == ["out-grammar"]
      assert [reason] = dropped
      assert reason =~ "monad transformers"
      assert reason =~ "not in the section"
    end

    test "matching ignores case, because prose capitalises at a sentence start" do
      {attrs, []} = Summary.validate(%{"summary" => "s", "covers" => ["Out-Grammar"]}, @body, 3)
      assert attrs.summary_covers == ["Out-Grammar"]
    end

    test "follows_from only points backwards" do
      {attrs, dropped} =
        Summary.validate(
          %{"summary" => "s", "covers" => [], "follows_from" => [1, 2, 5, 3]},
          @body,
          3
        )

      assert attrs.summary_follows == [1, 2]
      assert length(dropped) == 2, "5 and 3 are not earlier than 3"
    end

    test "an empty sets_up is nil rather than a blank line on the page" do
      {attrs, _} =
        Summary.validate(%{"summary" => "s", "covers" => [], "sets_up" => "  "}, @body, 2)

      assert attrs.summary_sets_up == nil
    end

    test "duplicates are collapsed and the list is bounded" do
      covers = ["kcodegen", "kcodegen"] ++ for(_ <- 1..10, do: "out-grammar")
      {attrs, _} = Summary.validate(%{"summary" => "s", "covers" => covers}, @body, 2)

      assert attrs.summary_covers == ["kcodegen", "out-grammar"]
    end
  end

  describe "what moved under a stale summary" do
    setup %{section: section} do
      {:ok, section} =
        section
        |> Ecto.Changeset.change(
          summary: "It sets up alpha.",
          summary_fingerprint: Summary.fingerprint(section),
          summary_body: section.body
        )
        |> Repo.update()

      %{section: section}
    end

    test "a current summary has no drift to show", %{section: section} do
      assert Summary.drift(section) == []
    end

    test "an edited section shows the paragraph that changed", %{section: section} do
      block =
        section.body
        |> String.split(~r/\n{2,}/, trim: true)
        |> Enum.find(&String.contains?(&1, "ALPHA"))

      {:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))

      rows = Summary.drift(Repo.reload!(section))

      assert Enum.any?(rows, &match?({:change, _, _}, &1))

      {:change, old, new} = Enum.find(rows, &match?({:change, _, _}, &1))
      assert old =~ "ALPHA"
      assert new =~ "AMENDED"
    end

    test "the word diff marks what went and what arrived", %{section: section} do
      block =
        section.body
        |> String.split(~r/\n{2,}/, trim: true)
        |> Enum.find(&String.contains?(&1, "ALPHA"))

      {:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))

      {:change, old, new} =
        Repo.reload!(section) |> Summary.drift() |> Enum.find(&match?({:change, _, _}, &1))

      parts = Marginalia.Diff.words(old, new)

      assert Enum.any?(parts, fn {op, t} -> op == :del and t =~ "ALPHA" end)
      assert Enum.any?(parts, fn {op, t} -> op == :ins and t =~ "AMENDED" end)
    end

    test "a summary written before the source was kept draws no diff", %{section: section} do
      {:ok, section} =
        section
        |> Ecto.Changeset.change(summary_body: nil, summary_fingerprint: "stale")
        |> Repo.update()

      refute Summary.current?(section)

      assert Summary.drift(section) == [],
             "inventing a baseline would draw a diff that never happened"
    end
  end
end
