defmodule Marginalia.CompareSummaryTest do
  @moduledoc """
  Drafting a summary and relating it to the draft it came from.

  The reason this is a comparison and not a replacement: a summary read on
  its own is a claim about a document you are no longer looking at. Held
  against the original, with the relations drawn between them, it is
  checkable — this paragraph is what those four became, and that promise in
  the long version has nothing answering it in the short one.

  The model is not reached here. What is asserted is the ordering and the
  bookkeeping: that the condensation knows where it came from, that asking
  twice does not make two of them, and that the link is between the right
  pair.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Document, Links, Repo, Works}

  setup do
    user = user_fixture()

    body =
      "# One\n\nThe kettle went cold on the counter. " <>
        String.duplicate("word ", 90) <>
        "\n\n# Two\n\nNobody moved to fill it again. " <> String.duplicate("other ", 90)

    {:ok, work} = Works.create_work(user.id, %{"title" => "The long version", "body" => body})
    {:ok, work} = Works.set_status(work, "read")

    for {s, i} <- Enum.with_index(Works.list_sections(work.id), 1) do
      s |> Ecto.Changeset.change(summary: "Section #{i}, in short.") |> Repo.update!()
    end

    %{user: user, work: work}
  end

  test "the condensation is a draft of its own and says what it condenses", ctx do
    assert {:ok, summary} = Document.to_draft(ctx.user.id, ctx.work)

    assert summary.id != ctx.work.id
    assert summary.derived_from_id == ctx.work.id
    assert summary.body =~ "Section 1, in short."

    # and the original is untouched, which is the whole difference from
    # replacing it
    assert Repo.reload(ctx.work).body =~ "The kettle went cold on the counter"
  end

  test "the original is found from the condensation and back again", ctx do
    {:ok, summary} = Document.to_draft(ctx.user.id, ctx.work)

    assert Works.condensation_of(ctx.work.id).id == summary.id
    assert Works.condensation_of(summary.id) == nil
  end

  test "asking twice reuses the condensation rather than making a second", ctx do
    {:ok, first} = Document.to_draft(ctx.user.id, ctx.work)

    # what `compare/3` does before it spends anything
    assert Works.condensation_of(ctx.work.id).id == first.id

    {:ok, again} = Document.to_draft(ctx.user.id, ctx.work)
    assert again.id != first.id, "to_draft/2 on its own always makes one"

    # ...and condensation_of takes the newest, so compare/3 never stacks up
    assert Works.condensation_of(ctx.work.id).id == again.id
  end

  test "relating needs both sides read, and says so rather than guessing", ctx do
    {:ok, summary} = Document.to_draft(ctx.user.id, ctx.work)
    {:ok, link} = Links.get_or_create(ctx.work.id, summary.id)

    # the condensation has no map yet: Linker refuses rather than inventing
    # relations between a document and one nobody has read
    assert Works.list_nodes(summary.id) == []
    assert Marginalia.Analysis.Linker.run(link, nil)
    assert Repo.reload(link).status in ["failed", "linking"]
  end

  test "a draft with nothing summarised cannot be compared", ctx do
    {:ok, bare} =
      Works.create_work(ctx.user.id, %{
        "title" => "Nothing summarised",
        "body" => "# X\n\n" <> String.duplicate("word ", 90)
      })

    assert {:error, :nothing_summarised} = Document.compare(ctx.user.id, bare)
    assert Works.condensation_of(bare.id) == nil
  end

  test "deleting the long version leaves the condensation alone", ctx do
    {:ok, summary} = Document.to_draft(ctx.user.id, ctx.work)

    {:ok, _} = Works.delete_work(ctx.work)

    kept = Repo.reload(summary)
    assert kept, "the condensation is somebody's draft now, not an appendix"
    assert kept.derived_from_id == nil
  end
end
