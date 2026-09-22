defmodule Marginalia.RevisionsTest do
  @moduledoc """
  The history of a draft's prose, and the property it has to keep.

  Patches applied in order over the baseline reproduce the body. If that ever
  stops being true the diff view is showing something that is not the draft,
  so it is asserted here rather than assumed.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup do
    user = user_fixture()

    body =
      "# A draft\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 120) <>
        "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 120)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    %{user: user, work: work, section: hd(Works.list_sections(work.id))}
  end

  defp block(section, lead) do
    section.body
    |> String.split(~r/\n{2,}/, trim: true)
    |> Enum.find(&String.contains?(&1, lead))
  end

  test "the baseline is captured when the draft arrives", %{work: work} do
    assert work.baseline_body == work.body
    assert Works.baseline(work) == work.body
  end

  test "an edit records one revision", %{work: work, section: section} do
    b = block(section, "ALPHA")
    {:ok, _} = Works.replace_block(section, b, String.replace(b, "ALPHA", "AMENDED"))

    assert [rev] = Works.revisions(work.id)
    assert rev.seq == 1
    assert rev.origin == "edit"
    assert rev.before =~ "ALPHA"
    assert rev.after =~ "AMENDED"
    assert rev.section_ordinal == section.ordinal
  end

  test "a rewrite says so, and carries the candidate's label", %{work: work, section: section} do
    b = block(section, "BRAVO")

    {:ok, _} =
      Works.replace_block(section, b, String.replace(b, "BRAVO", "BETTER"),
        origin: "rewrite",
        note: "cuts the gloss"
      )

    assert [rev] = Works.revisions(work.id)
    assert rev.origin == "rewrite"
    assert rev.note == "cuts the gloss"
  end

  test "replaying every patch over the baseline reproduces the body", %{
    work: work,
    section: section
  } do
    b1 = block(section, "ALPHA")

    {:ok, %{section: section}} =
      Works.replace_block(section, b1, String.replace(b1, "ALPHA", "ONE"))

    b2 = block(section, "BRAVO")
    {:ok, _} = Works.replace_block(section, b2, String.replace(b2, "BRAVO", "TWO"))

    assert {:ok, replayed} = Works.replay(work.id)
    assert replayed == Repo.reload!(work).body
    assert Works.revision_count(work.id) == 2
  end

  test "seq is per work and does not skip", %{work: work, section: section} do
    for lead <- ["ALPHA", "BRAVO"] do
      section = Repo.reload!(section)
      b = block(section, lead)
      {:ok, _} = Works.replace_block(section, b, String.replace(b, lead, lead <> "!"))
    end

    assert Enum.map(Works.revisions(work.id), & &1.seq) == [1, 2]
  end

  test "an edit that changes nothing records nothing", %{work: work, section: section} do
    b = block(section, "ALPHA")
    {:ok, %{superseded: 0}} = Works.replace_block(section, b, b)

    assert Works.revisions(work.id) == []
  end

  test "a draft from before any history still has a baseline", %{work: work} do
    stripped = %{work | baseline_body: nil}
    assert Works.baseline(stripped) == work.body
  end

  describe "a draft from before the baseline column existed" do
    test "the baseline is reconstructed from the revisions rather than the body", %{
      work: work,
      section: section
    } do
      b = block(section, "ALPHA")
      {:ok, _} = Works.replace_block(section, b, String.replace(b, "ALPHA", "AMENDED"))

      # what those drafts look like: history, no stored baseline
      {:ok, _} = work |> Ecto.Changeset.change(baseline_body: nil) |> Repo.update()
      work = Repo.reload!(work)

      baseline = Works.baseline(work)

      assert baseline =~ "ALPHA", "the text that was replaced has to come back"
      refute baseline =~ "AMENDED"

      refute baseline == work.body,
             "falling back to the body makes the draft diff against itself and report no changes"
    end

    test "the reconstructed baseline actually diffs", %{work: work, section: section} do
      b = block(section, "BRAVO")
      {:ok, _} = Works.replace_block(section, b, String.replace(b, "BRAVO", "BETTER"))
      {:ok, _} = work |> Ecto.Changeset.change(baseline_body: nil) |> Repo.update()
      work = Repo.reload!(work)

      rows = Marginalia.Diff.rows(Works.baseline(work), work.body)

      assert Marginalia.Diff.any?(rows)
      assert Marginalia.Diff.stat(rows).changed == 1
    end

    test "a stored baseline is still preferred over reconstructing one", %{work: work} do
      assert Works.baseline(work) == work.baseline_body
    end
  end

  test "an edit is stored one sentence per line, and the replay still holds", %{
    work: work,
    section: section
  } do
    b = block(section, "ALPHA")

    typed =
      "ALPHA was rewritten. It came back\nwrapped, as pasted text does. Two sentences became three."

    {:ok, %{section: section}} = Works.replace_block(section, b, typed)

    assert section.body =~
             "ALPHA was rewritten.\nIt came back wrapped, as pasted text does.\nTwo sentences became three."

    [rev] = Works.revisions(work.id)

    assert rev.after ==
             "ALPHA was rewritten.\nIt came back wrapped, as pasted text does.\nTwo sentences became three."

    work = Works.get_work(work.user_id, work.id)

    replayed =
      Enum.reduce(Works.revisions(work.id), Works.baseline(work), fn r, body ->
        String.replace(body, r.before, r.after, global: false)
      end)

    assert replayed == work.body
  end
end
