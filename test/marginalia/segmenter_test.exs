defmodule Marginalia.Works.SegmenterTest do
  use ExUnit.Case, async: true
  alias Marginalia.Works.Segmenter

  test "a blog post with no structure is one section" do
    text = Enum.map_join(1..4, "\n\n", fn i -> "Paragraph #{i}. " <> String.duplicate("word ", 40) end)
    assert [%{body: body}] = Segmenter.split(text)
    assert body =~ "Paragraph 1"
    assert body =~ "Paragraph 4"
  end

  test "markdown headings win when the writer supplied them" do
    text = """
    # The Opening
    #{String.duplicate("alpha ", 300)}

    # The Middle
    #{String.duplicate("beta ", 300)}

    # The End
    #{String.duplicate("gamma ", 300)}
    """

    sections = Segmenter.split(text)
    assert length(sections) == 3
    assert Enum.map(sections, & &1.title) == ["The Opening", "The Middle", "The End"]
    assert hd(sections).body =~ "alpha"
  end

  test "chapter markers are found when there is no markdown" do
    text = """
    Chapter 1
    #{String.duplicate("one ", 300)}

    Chapter 2
    #{String.duplicate("two ", 300)}
    """

    sections = Segmenter.split(text)
    assert length(sections) == 2
    assert Enum.at(sections, 0).title =~ "Chapter 1"
  end

  test "prose before the first marker is kept, not dropped" do
    text = """
    #{String.duplicate("prologue ", 300)}

    Chapter 1
    #{String.duplicate("one ", 300)}

    Chapter 2
    #{String.duplicate("two ", 300)}
    """

    sections = Segmenter.split(text)
    assert Enum.any?(sections, &(&1.body =~ "prologue"))
  end

  test "a long unstructured draft is packed into multiple sections without splitting paragraphs" do
    para = String.duplicate("word ", 300)
    text = Enum.map_join(1..12, "\n\n", fn i -> "P#{i} " <> para end)

    sections = Segmenter.split(text)
    assert length(sections) > 1
    # every paragraph survives intact somewhere
    for i <- 1..12 do
      assert Enum.any?(sections, &String.contains?(&1.body, "P#{i} "))
    end
  end

  test "runt trailing sections are folded rather than left as stubs" do
    text = """
    # Big
    #{String.duplicate("alpha ", 400)}

    # Tiny
    two words
    """

    sections = Segmenter.split(text)
    assert length(sections) == 1
    assert hd(sections).body =~ "two words"
  end

  test "empty input yields nothing" do
    assert Segmenter.split("") == []
    assert Segmenter.split("   \n\n  ") == []
    assert Segmenter.split(nil) == []
  end
end
