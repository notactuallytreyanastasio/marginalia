defmodule Marginalia.SentencesWorksTest do
  @moduledoc """
  One sentence per line, seen from the draft's point of view.

  The splitter is tested on its own. What matters here is what the form
  does to everything built on a draft: the baseline, the anchors, the
  edits, the diff and the page. The property to hold on to is that none of
  them can tell the difference, except the diff, which gets better.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Diff, Reading, Works}
  alias Marginalia.Analysis.Anchor

  @wrapped """
  # A draft

  She had been standing at the window for an hour
  before anyone noticed. The kettle went cold on
  the counter. Nobody moved to fill it again.

  By evening the argument had found its real
  subject, which was not the kettle. It was the
  window.
  """

  setup do
    user = user_fixture()
    {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => @wrapped})
    %{user: user, work: work, section: hd(Works.list_sections(work.id))}
  end

  test "a hard-wrapped upload is stored one sentence per line", %{section: s} do
    # one heading is not enough for the segmenter to cut on, so it stays in the body
    assert s.body ==
             "# A draft\n\n" <>
               "She had been standing at the window for an hour before anyone noticed.\n" <>
               "The kettle went cold on the counter.\n" <>
               "Nobody moved to fill it again.\n\n" <>
               "By evening the argument had found its real subject, which was not the kettle.\n" <>
               "It was the window."
  end

  test "the baseline is the reflowed body, so the replay starts from what is stored", %{
    work: work
  } do
    assert work.baseline_body == work.body
    assert work.body =~ "before anyone noticed.\nThe kettle"
  end

  test "reflowing does not change the word count", %{work: work} do
    assert work.word_count == length(String.split(@wrapped, ~r/\s+/, trim: true))
  end

  test "a windowed draft's title is its first sentence, not a wrapped fragment", %{user: user} do
    # wrapped after two words: as it arrived, the first line was too short to be a title
    body =
      "The opening\nsentence is the title of this section, whole. Then more. " <>
        String.duplicate("word ", 40)

    {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
    [s] = Works.list_sections(work.id)
    assert s.title =~ "The opening sentence is the title"
    refute s.title == "Section 1"
  end

  test "a quote spanning two sentences verifies against the stored text and keeps the newline", %{
    section: s
  } do
    flat = "went cold on the counter. Nobody moved"
    assert {:ok, span} = Anchor.verify(flat, s.body)
    assert span == "went cold on the counter.\nNobody moved"
  end

  test "a note anchored across a sentence break lands on its paragraph", %{work: work, section: s} do
    {:ok, _} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: s.id,
        node_type: "beat",
        title: "Cold kettle, nobody moves",
        quote: "The kettle went cold on the counter. Nobody moved to fill it again."
      })

    [page] = Reading.page(work)
    assert page.unplaced == []
    [block] = Enum.filter(page.blocks, &(&1.notes != []))
    assert block.text =~ "She had been standing"
    assert block.text =~ "Nobody moved to fill it again."
  end

  test "editing one sentence supersedes only the note on that sentence", %{work: work, section: s} do
    {:ok, kettle} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: s.id,
        node_type: "beat",
        title: "The kettle",
        quote: "The kettle went cold on the counter."
      })

    {:ok, window} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: s.id,
        node_type: "beat",
        title: "The window",
        quote: "It was the window."
      })

    [_heading, first, _second] = String.split(s.body, "\n\n")

    edited =
      String.replace(first, "The kettle went cold on the counter.", "The kettle boiled dry.")

    {:ok, %{superseded: 1}} = Works.replace_block(s, first, edited)

    statuses = work.id |> Works.list_nodes() |> Map.new(&{&1.id, &1.status})
    assert statuses[kettle.id] == "superseded"
    refute statuses[window.id] == "superseded"
  end

  test "an edit of one sentence is one changed paragraph, and the diff names only that sentence",
       %{
         work: work,
         section: s
       } do
    [_heading, first, _] = String.split(s.body, "\n\n")
    edited = String.replace(first, "Nobody moved to fill it again.", "Nobody moved.")
    {:ok, _} = Works.replace_block(s, first, edited)

    work = Works.get_work(work.user_id, work.id)
    rows = Diff.rows(Works.baseline(work), work.body)

    assert [{:same, _, _}, {:change, before, aft}, {:same, _, _}] = rows
    assert Diff.stat(rows) == %{same: 2, changed: 1, added: 0, removed: 0}

    changed_words =
      Diff.words(before, aft)
      |> Enum.reject(&match?({:same, _}, &1))
      |> Enum.map_join(" ", fn {_, t} -> String.trim(t) end)

    assert changed_words =~ "to fill it again"
    refute changed_words =~ "standing at the window"
  end

  test "the stored form survives an edit pasted as one long line", %{work: work, section: s} do
    [_heading, _, second] = String.split(s.body, "\n\n")

    pasted =
      "By evening the argument had found its real subject. It was the window. It always was."

    {:ok, %{section: s}} = Works.replace_block(s, second, pasted)

    assert s.body =~
             "By evening the argument had found its real subject.\nIt was the window.\nIt always was."

    [rev] = Works.revisions(work.id)

    assert rev.after ==
             "By evening the argument had found its real subject.\nIt was the window.\nIt always was."
  end

  test "the page shows one block per paragraph, however many sentences it holds", %{work: work} do
    [page] = Reading.page(work)
    assert [heading, first, second] = page.blocks
    assert heading.text == "# A draft"
    assert first.text =~ "\n"
    assert second.text =~ "\n"
  end

  test "an edit that only re-wraps a paragraph is no edit at all", %{work: work, section: s} do
    [_heading, first, _] = String.split(s.body, "\n\n")

    rewrapped =
      first |> String.replace("\n", " ") |> String.replace("hour before", "hour\nbefore")

    {:ok, %{superseded: 0}} = Works.replace_block(s, first, rewrapped)
    assert Works.revisions(work.id) == []
  end
end
