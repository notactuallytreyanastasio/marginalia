defmodule MarginaliaWeb.NotePilesTest do
  @moduledoc """
  How many slots a pile of margin notes turns into.

  The case that forced this: a section whose beats could not be anchored has
  no paragraph for any of them to sit beside, so every one stacks at the top
  of the rail. Seven of those is thirteen hundred pixels of margin against
  three paragraphs of prose.

  The rule has to hold two things at once. Most paragraphs carry one or two
  notes and should carry no controls; a pile that fits is easier to read
  than a pile with a pager on it. And nothing may be dropped — a note behind
  a control is still reachable, a note that grouping lost is gone.
  """
  use ExUnit.Case, async: true

  alias MarginaliaWeb.WorkLive.Show

  defp note(kind, title), do: %{kind: kind, title: title, key: "#{kind}:#{title}", body: "b"}

  defp kinds(piles), do: Enum.map(piles, fn pile -> Enum.map(pile, & &1.kind) end)

  test "four or fewer get a slot each, with no pager on them" do
    notes = [note("beat", "a"), note("beat", "b"), note("tension", "c"), note("beat", "d")]

    assert kinds(Show.piles(notes)) == [["beat"], ["beat"], ["tension"], ["beat"]]
  end

  test "an empty section has no slots" do
    assert Show.piles([]) == []
  end

  test "past four, like notes stack together" do
    notes = [
      note("beat", "1"),
      note("pays_off", "2"),
      note("pays_off", "3"),
      note("requires", "4"),
      note("develops", "5"),
      note("beat", "6"),
      note("beat", "7")
    ]

    # the shape of the screenshot this came from: seven cards became four
    assert kinds(Show.piles(notes)) == [
             ["beat", "beat", "beat"],
             ["pays_off", "pays_off"],
             ["requires"],
             ["develops"]
           ]
  end

  test "the groups keep the order the notes arrived in" do
    notes = [
      note("develops", "1"),
      note("beat", "2"),
      note("develops", "3"),
      note("beat", "4"),
      note("tension", "5")
    ]

    # develops first because its first note is first, not alphabetically
    assert Enum.map(Show.piles(notes), &hd(&1).kind) == ["develops", "beat", "tension"]
  end

  test "nothing is lost, whichever side of the threshold it falls on" do
    for n <- 1..12 do
      notes = Enum.map(1..n, &note(Enum.at(~w(beat tension pays_off), rem(&1, 3)), "#{&1}"))
      flat = Show.piles(notes) |> List.flatten()

      assert length(flat) == n, "#{n} notes must still be #{n} notes"
      assert Enum.map(flat, & &1.key) |> Enum.sort() == Enum.map(notes, & &1.key) |> Enum.sort()
    end
  end

  test "five notes all of different kinds stay five slots" do
    # grouping has nothing to group; five slots is the honest answer, and
    # hiding four unrelated remarks behind a pager would be worse than the
    # height it saves
    notes = Enum.map(~w(beat tension pays_off requires develops), &note(&1, &1))

    assert length(Show.piles(notes)) == 5
  end

  test "the order within a stack is the order they were written" do
    notes = [
      note("beat", "first"),
      note("tension", "x"),
      note("beat", "second"),
      note("tension", "y"),
      note("beat", "third")
    ]

    [beats | _] = Show.piles(notes)
    assert Enum.map(beats, & &1.title) == ["first", "second", "third"]
  end
end
