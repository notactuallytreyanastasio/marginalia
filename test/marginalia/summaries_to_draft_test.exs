defmodule Marginalia.SummariesToDraftTest do
  @moduledoc """
  The summaries, as something to write from.

  Until now they could only be read where they were written, which makes them
  a report. A condensation you can edit and have read is a draft.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Document, Summary, Works}
  alias Marginalia.Works.DocumentSummary

  setup do
    user = user_fixture()

    body =
      Enum.map_join(1..3, "\n\n", fn i ->
        "# Part #{i}\n\nSection #{i} body. " <> String.duplicate("word ", 300)
      end)

    {:ok, work} = Works.create_work(user.id, %{"title" => "The Quiet House", "body" => body})
    %{user: user, work: work, sections: Works.list_sections(work.id)}
  end

  defp summarise(section, text, opts \\ []) do
    {:ok, s} =
      section
      |> Ecto.Changeset.change(
        Keyword.merge(
          [
            summary: text,
            summary_fingerprint: Summary.fingerprint(section),
            summary_body: section.body
          ],
          opts
        )
      )
      |> Repo.update()

    s
  end

  test "nothing summarised makes no draft", ctx do
    assert Document.to_draft(ctx.user.id, ctx.work) == {:error, :nothing_summarised}
    assert length(Works.list_works(ctx.user.id)) == 1
  end

  test "each summarised section becomes a part of the new draft", ctx do
    for {s, i} <- Enum.with_index(ctx.sections, 1) do
      summarise(s, "What section #{i} does, at length. " <> String.duplicate("word ", 280))
    end

    {:ok, draft} = Document.to_draft(ctx.user.id, ctx.work)

    assert draft.title == "The Quiet House — in summary"
    assert draft.body =~ "What section 1 does"
    assert draft.body =~ "What section 3 does"
    assert length(Works.list_sections(draft.id)) >= 2
  end

  test "a section nobody summarised is left out rather than blank", ctx do
    [first | _] = ctx.sections
    summarise(first, "Only this one. " <> String.duplicate("word ", 280))

    {:ok, draft} = Document.to_draft(ctx.user.id, ctx.work)

    assert draft.body =~ "Only this one."

    titles = Works.list_sections(draft.id) |> Enum.map(& &1.title)
    refute Enum.any?(titles, &(&1 =~ "2. Part 2"))
    assert draft.intent =~ "1 of its 3 sections"
  end

  test "the covers and what it sets up ride along", ctx do
    [first | _] = ctx.sections

    summarise(first, "A summary. " <> String.duplicate("word ", 280),
      summary_covers: ["the out-grammar", "kcodegen"],
      summary_sets_up: "a module that runs"
    )

    {:ok, draft} = Document.to_draft(ctx.user.id, ctx.work)

    assert draft.body =~ "It deals with: the out-grammar, kcodegen."
    assert draft.body =~ "It leaves in place: a module that runs"
  end

  test "the document summary opens it and the guidelines close it", ctx do
    [first | _] = ctx.sections
    summarise(first, "A summary. " <> String.duplicate("word ", 280))

    Repo.insert!(%DocumentSummary{
      work_id: ctx.work.id,
      summary: "It builds a thing and then fixes what is underneath it.",
      throughline: "Nothing runs until the emitter is generated.",
      guidelines: [
        %{"guideline" => "Name the failing case first.", "because" => "It locates the fix."}
      ]
    })

    {:ok, draft} = Document.to_draft(ctx.user.id, ctx.work)

    assert draft.body =~ "It builds a thing and then fixes what is underneath it."
    assert draft.body =~ "Nothing runs until the emitter is generated."
    # the `##` itself is gone from the body: a work's body is the join of its
    # sections and the segmenter lifts a heading into the section title
    assert draft.body =~ "Name the failing case first."

    titles = Works.list_sections(draft.id) |> Enum.map(& &1.title)
    assert Enum.any?(titles, &(&1 =~ "working under" or &1 =~ "Part 1"))
  end

  test "it is not filed in the folder of the draft it condenses", ctx do
    [first | _] = ctx.sections
    summarise(first, "A summary. " <> String.duplicate("word ", 280))

    {:ok, draft} = Document.to_draft(ctx.user.id, ctx.work)

    assert is_nil(draft.folder_id),
           "a condensation in the folder it condenses becomes document N+1 of it"
  end

  test "the new draft is an ordinary one: editable, with its own history", ctx do
    [first | _] = ctx.sections
    summarise(first, "A summary worth editing. " <> String.duplicate("word ", 280))

    {:ok, draft} = Document.to_draft(ctx.user.id, ctx.work)

    section = hd(Works.list_sections(draft.id))

    block =
      section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "worth editing"))

    {:ok, _} =
      Works.replace_block(section, block, String.replace(block, "worth editing", "EDITED"))

    assert Works.revision_count(draft.id) == 1
    assert Repo.reload!(draft).body =~ "EDITED"
  end
end
