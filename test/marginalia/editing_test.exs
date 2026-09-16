defmodule Marginalia.EditingTest do
  @moduledoc """
  The draft is editable, and everything in the app is anchored into it. The
  interesting case is not saving text — it is what happens to the notes that
  were about the line you changed.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.Works
  import Marginalia.AccountsFixtures

  setup do
    user = user_fixture()

    body =
      "# A draft\n\nShe stood at the window for an hour.\n\n" <>
        "The kettle went cold on the counter.\n\n" <> String.duplicate("word ", 300)

    {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
    section = hd(Works.list_sections(work.id))

    {:ok, kettle} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: section.id,
        node_type: "beat",
        title: "The kettle",
        quote: "The kettle went cold on the counter."
      })

    {:ok, window} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: section.id,
        node_type: "beat",
        title: "The window",
        quote: "She stood at the window for an hour."
      })

    %{work: work, section: section, kettle: kettle, window: window}
  end

  test "an edit lands in the section and in the work", %{work: work, section: section} do
    {:ok, %{section: updated}} =
      Works.replace_block(section, "The kettle went cold on the counter.", "The kettle went stone cold.")

    assert updated.body =~ "stone cold"
    refute updated.body =~ "went cold on the counter"

    # the work's body is the sections joined back up
    assert Works.get_work!(work.user_id, work.id).body =~ "stone cold"
  end

  test "a note about the line you changed is superseded, not deleted",
       %{work: work, section: section, kettle: kettle, window: window} do
    {:ok, %{superseded: n}} =
      Works.replace_block(section, "The kettle went cold on the counter.", "The kettle went stone cold.")

    assert n == 1
    assert Works.get_node(work.id, kettle.id).status == "superseded"
    assert Works.get_node(work.id, kettle.id).title == "The kettle", "it is kept, not thrown away"

    # a note about a line you did not touch is untouched
    assert Works.get_node(work.id, window.id).status == "pending"
  end

  test "a note still anchored after the edit survives it", %{work: work, section: section, kettle: k} do
    # the quoted sentence is still there, with words added around it
    {:ok, %{superseded: n}} =
      Works.replace_block(
        section,
        "The kettle went cold on the counter.",
        "Nobody moved. The kettle went cold on the counter."
      )

    assert n == 0
    assert Works.get_node(work.id, k.id).status == "pending"
  end

  test "section boundaries do not move", %{work: work, section: section} do
    before = length(Works.list_sections(work.id))
    {:ok, _} = Works.replace_block(section, "She stood at the window for an hour.", "She stood there.")

    assert length(Works.list_sections(work.id)) == before
    assert hd(Works.list_sections(work.id)).id == section.id
  end

  test "emptying a paragraph is refused", %{section: section} do
    assert {:error, :empty} = Works.replace_block(section, "The kettle went cold on the counter.", "   ")
  end

  test "an edit against a paragraph that has moved is refused", %{section: section} do
    assert {:error, :moved} = Works.replace_block(section, "a paragraph that is not there", "new")
  end

  test "saving an unchanged paragraph does nothing", %{section: section} do
    block = "The kettle went cold on the counter."
    assert {:ok, %{superseded: 0}} = Works.replace_block(section, block, block)
  end

  test "the word count follows the edit", %{work: work, section: section} do
    {:ok, %{section: updated}} =
      Works.replace_block(section, "She stood at the window for an hour.", "She stood.")

    assert updated.word_count < section.word_count
    assert Works.get_work!(work.user_id, work.id).word_count < work.word_count
  end
end
