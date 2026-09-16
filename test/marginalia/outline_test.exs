defmodule Marginalia.OutlineTest do
  @moduledoc "The draft's headings, for jumping around it."
  use Marginalia.DataCase, async: true

  alias Marginalia.{Reading, Works}
  import Marginalia.AccountsFixtures

  setup do
    user = user_fixture()

    # the segmenter promotes # to ### into sections of their own, so the
    # headings that stay *inside* a section are the deeper ones
    body =
      "# What are we talking about?\n\n" <>
        String.duplicate("word ", 300) <>
        "\n\n#### A sub heading\n\nMore prose here.\n\n" <>
        "##### Deeper still\n\nYet more prose.\n\n" <>
        String.duplicate("other ", 300)

    {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
    %{page: Reading.page(work)}
  end

  test "sections and the headings inside them, in order", %{page: page} do
    titles = page |> Reading.outline() |> Enum.map(& &1.title)

    assert "What are we talking about?" in titles
    assert "A sub heading" in titles
    assert "Deeper still" in titles
    assert Enum.find_index(titles, &(&1 == "A sub heading")) <
             Enum.find_index(titles, &(&1 == "Deeper still"))
  end

  test "each entry points at an element that exists on the page", %{page: page} do
    refs =
      page
      |> Enum.flat_map(fn s -> Enum.map(s.blocks, &"block-#{&1.ref}") end)
      |> MapSet.new()

    sections = page |> Enum.map(&"sec-#{&1.section.ordinal}") |> MapSet.new()
    ids = MapSet.union(refs, sections)

    for e <- Reading.outline(page) do
      assert MapSet.member?(ids, e.id), "#{e.id} is not on the page"
    end
  end

  test "nesting is carried as a level", %{page: page} do
    by_title = page |> Reading.outline() |> Map.new(&{&1.title, &1.level})

    assert by_title["A sub heading"] == 4
    assert by_title["Deeper still"] == 5
  end

  test "a section is not listed twice under its own title", %{page: page} do
    entries = Reading.outline(page)
    titles = Enum.map(entries, & &1.title)

    assert length(titles) == length(Enum.uniq(titles))
  end

  test "sections carry their length", %{page: page} do
    assert [%{level: 0, words: w} | _] = Reading.outline(page)
    assert w > 0
  end
end
