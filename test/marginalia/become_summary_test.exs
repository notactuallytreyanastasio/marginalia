defmodule Marginalia.BecomeSummaryTest do
  @moduledoc """
  Replacing a draft with its own summary.

  This is the one operation in the app that destroys work on purpose, so
  what is asserted is mostly what survives: the prose, as history you can
  still read, and the draft itself — same id, same slug, so every link to it
  still lands. What does not survive is the map, and that is the point
  rather than an oversight. A beat says "this sentence does this" about a
  sentence that no longer exists.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Document, Repo, Works}
  alias Marginalia.Works.{Edge, Node}

  setup do
    user = user_fixture()

    body =
      "# One\n\nThe kettle went cold on the counter. " <>
        String.duplicate("word ", 90) <>
        "\n\n# Two\n\nNobody moved to fill it again. " <> String.duplicate("other ", 90)

    {:ok, work} = Works.create_work(user.id, %{"title" => "The long version", "body" => body})
    {:ok, work} = Works.set_status(work, "read")

    sections = Works.list_sections(work.id)

    for {s, i} <- Enum.with_index(sections, 1) do
      s |> Ecto.Changeset.change(summary: "Section #{i}, in short.") |> Repo.update!()
    end

    %{user: user, work: work, a: hd(sections), b: List.last(sections), n: length(sections)}
  end

  defp beat(work, section, quote) do
    {:ok, n} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: section.id,
        node_type: "beat",
        title: "A beat",
        body: "why",
        quote: quote
      })

    n
  end

  test "the body becomes the summary, and the draft stays the same draft", ctx do
    assert {:ok, work} = Document.become_summary(ctx.work)

    assert work.id == ctx.work.id
    assert work.slug == ctx.work.slug, "every link to it has to still land"
    assert work.body =~ "Section 1, in short."
    assert work.body =~ "Section #{ctx.n}, in short."
    refute work.body =~ "The kettle went cold on the counter"
  end

  test "it is sectioned again, not left as one block", ctx do
    {:ok, work} = Document.become_summary(ctx.work)

    sections = Works.list_sections(work.id)
    assert sections != []
    assert Enum.map(sections, & &1.ordinal) == Enum.to_list(1..length(sections))
    assert work.body == Enum.map_join(sections, "\n\n", & &1.body)
  end

  test "the prose that was there is still readable as history", ctx do
    {:ok, work} = Document.become_summary(ctx.work)

    assert Works.baseline(work) =~ "The kettle went cold on the counter"

    [rev] = Enum.filter(Works.revisions(work.id), &(&1.origin == "summary"))
    assert rev.before =~ "The kettle went cold on the counter"
    assert rev.after =~ "Section 1, in short."
    assert rev.note =~ "#{ctx.n} of #{ctx.n} sections"
  end

  test "replaying the revisions still reproduces the body", ctx do
    {:ok, work} = Document.become_summary(ctx.work)

    # the property the whole diff view rests on, and the one a whole-body
    # revision was most likely to break
    assert {:ok, replayed} = Works.replay(work.id)
    assert replayed == work.body
  end

  test "the map goes, because it points at sentences that are gone", ctx do
    one = beat(ctx.work, ctx.a, "The kettle went cold on the counter.")
    two = beat(ctx.work, ctx.b, "Nobody moved to fill it again.")

    Repo.insert!(%Edge{
      work_id: ctx.work.id,
      from_id: one.id,
      to_id: two.id,
      edge_type: "leads_to"
    })

    assert Repo.aggregate(Node, :count) == 2

    {:ok, work} = Document.become_summary(ctx.work)

    assert Repo.aggregate(Node, :count) == 0
    assert Repo.aggregate(Edge, :count) == 0
    assert work.status == "pending", "and it is waiting to be read again"
  end

  test "a draft with nothing summarised is refused rather than emptied", ctx do
    {:ok, other} =
      Works.create_work(ctx.user.id, %{
        "title" => "Never summarised",
        "body" => "# X\n\n" <> String.duplicate("word ", 90)
      })

    assert {:error, :nothing_summarised} = Document.become_summary(other)
    assert Repo.reload(other).body =~ "word word"
  end

  test "an already-edited draft keeps the baseline it arrived with", ctx do
    original = Works.baseline(ctx.work)

    [a | _] = Works.list_sections(ctx.work.id)
    {:ok, _} = Works.replace_block(a, "The kettle went cold on the counter.", "It went cold.")

    work = Repo.reload(ctx.work)
    {:ok, work} = Document.become_summary(work)

    assert Works.baseline(work) == original,
           "baseline means as it arrived, and it arrived once"
  end
end
