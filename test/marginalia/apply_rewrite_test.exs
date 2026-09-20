defmodule Marginalia.ApplyRewriteTest do
  @moduledoc """
  Replacing a passage with a rewrite of it, whatever it spans.

  This was refused for anything crossing a paragraph boundary, on the grounds
  that the editor writes one paragraph at a time. The editor does;
  `Works.replace_block/4` does not — it replaces any substring of the section
  body, so a span across four paragraphs was replaceable the whole time.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup do
    user = user_fixture()

    body =
      "# One\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 120) <>
        "\n\nBRAVO the second paragraph. " <>
        String.duplicate("word ", 120) <>
        "\n\nCHARLIE the third paragraph. " <> String.duplicate("word ", 120)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    %{user: user, work: work, section: hd(Works.list_sections(work.id))}
  end

  defp span_across_two(section) do
    [a, b | _] =
      section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.drop_while(&(&1 =~ "# One"))

    a <> "\n\n" <> b
  end

  test "a span crossing two paragraphs is replaced whole", ctx do
    span = span_across_two(ctx.section)
    assert String.contains?(ctx.section.body, span)

    {:ok, _} =
      Works.replace_block(ctx.section, span, "ONE SENTENCE INSTEAD OF BOTH.", origin: "rewrite")

    body = Repo.reload!(ctx.work).body

    assert body =~ "ONE SENTENCE INSTEAD OF BOTH."
    refute body =~ "ALPHA the first paragraph."
    refute body =~ "BRAVO the second paragraph."
    assert body =~ "CHARLIE the third paragraph.", "the paragraph after it is untouched"
  end

  test "it records one revision, so the replacement is undoable", ctx do
    span = span_across_two(ctx.section)

    {:ok, _} =
      Works.replace_block(ctx.section, span, "A SHORTER VERSION.",
        origin: "rewrite",
        note: "cuts the gloss"
      )

    assert [rev] = Works.revisions(ctx.work.id)
    assert rev.origin == "rewrite"
    assert rev.note == "cuts the gloss"
    assert rev.before =~ "ALPHA"
    assert rev.before =~ "BRAVO", "the whole passage is what was replaced"
    assert rev.after == "A SHORTER VERSION."
  end

  test "replaying the history reproduces the draft after a multi-paragraph replace", ctx do
    span = span_across_two(ctx.section)
    {:ok, _} = Works.replace_block(ctx.section, span, "A SHORTER VERSION.", origin: "rewrite")

    assert {:ok, replayed} = Works.replay(ctx.work.id)
    assert replayed == Repo.reload!(ctx.work).body
  end

  test "a passage that has changed underneath is refused rather than guessed at", ctx do
    span = span_across_two(ctx.section)

    # somebody edits one of those paragraphs first
    first =
      ctx.section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "ALPHA"))

    {:ok, %{section: moved}} = Works.replace_block(ctx.section, first, "REWRITTEN ALREADY.")

    assert Works.replace_block(moved, span, "TOO LATE.") == {:error, :moved}
    refute Repo.reload!(ctx.work).body =~ "TOO LATE."
  end

  test "an empty replacement is refused: a deletion is not a rewrite", ctx do
    span = span_across_two(ctx.section)
    assert Works.replace_block(ctx.section, span, "   ") == {:error, :empty}
  end
end
