defmodule Marginalia.StackToDraftTest do
  @moduledoc """
  The telling, brought back in as something that can be read.

  It is prose somebody wrote — by machine, out of other documents, but
  prose — and the thing this application does to prose is argue with it in
  the margin. The one document it could not do that to was its own.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Repo, Stacks, Works}
  alias Marginalia.Stacks.Story

  setup do
    user = user_fixture()
    {:ok, folder} = Folders.create_folder(user.id, %{"name" => "A stack"})

    story = fn movements ->
      Repo.insert!(%Story{
        folder_id: folder.id,
        title: "Half of building it is fixing the thing underneath",
        opening: "Nothing here is hand-written at the level you would expect.",
        movements: movements,
        closing: "That is the method.",
        uncovered: [],
        dropped: []
      })
    end

    %{user: user, folder: folder, story: story}
  end

  # Over @min_words (250), because a shorter section is merged into the one
  # before it — correctly, and it would make this test prove nothing. Real
  # movements run about 1,700 words.
  defp long(lead), do: lead <> " " <> String.duplicate("word ", 320)

  defp movements do
    [
      %{
        "heading" => "Get it running first",
        "prose" => long("Emit one module."),
        "steps" => [1]
      },
      %{
        "heading" => "Lowering is where the semantics live",
        "prose" => long("Every construct needs a shape."),
        "turn" => "This is the part that surprised me.",
        "steps" => [2, 3]
      }
    ]
  end

  test "each movement becomes a section, so a note lands on the part it is about", ctx do
    ctx.story.(movements())

    {:ok, work} = Stacks.to_draft(ctx.user.id, ctx.folder.id)
    sections = Works.list_sections(work.id)

    assert work.title == "Half of building it is fixing the thing underneath"
    assert length(sections) >= 3

    titles = Enum.map(sections, & &1.title)
    assert "1. Get it running first" in titles
    assert "2. Lowering is where the semantics live" in titles

    # The closing gets its own heading, but a short one is merged into the
    # section before it by the segmenter's @min_words rule. That is right —
    # a two-line section is not worth a note of its own.
    #
    # The `##` itself is gone from the body: a work's body is the join of its
    # sections, and the segmenter lifts a heading into the section title. So
    # what is asserted is that the closing text survives.
    assert work.body =~ "That is the method."
  end

  test "the opening, the turns and the closing all survive", ctx do
    ctx.story.(movements())

    {:ok, work} = Stacks.to_draft(ctx.user.id, ctx.folder.id)

    assert work.body =~ "Nothing here is hand-written"
    assert work.body =~ "This is the part that surprised me."
    assert work.body =~ "That is the method."
  end

  test "it is not filed into the stack's own folder", ctx do
    ctx.story.(movements())

    {:ok, work} = Stacks.to_draft(ctx.user.id, ctx.folder.id)

    refute work.folder_id == ctx.folder.id,
           "a draft in the stack's folder becomes document N+1 of the series it summarises, " <>
             "re-read as a chapter and shifting every ordinal after it"

    assert Stacks.documents(ctx.user.id, ctx.folder.id) == []
  end

  test "the intent says what the draft is for, so the read is not generic", ctx do
    ctx.story.(movements())

    {:ok, work} = Stacks.to_draft(ctx.user.id, ctx.folder.id)

    assert work.intent =~ "2 parts"
    assert work.intent =~ "could be acted on"
  end

  test "a stack with no telling yet says so rather than making an empty draft", ctx do
    assert {:error, :not_composed} = Stacks.to_draft(ctx.user.id, ctx.folder.id)
    assert Works.list_works(ctx.user.id) == []
  end

  test "a movement with no turn does not leave a stray quote marker", ctx do
    ctx.story.([%{"heading" => "One", "prose" => long("Just prose."), "steps" => [1]}])

    {:ok, work} = Stacks.to_draft(ctx.user.id, ctx.folder.id)

    refute work.body =~ ">"
  end
end
