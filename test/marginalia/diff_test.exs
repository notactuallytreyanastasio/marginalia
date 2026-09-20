defmodule Marginalia.DiffTest do
  @moduledoc """
  Aligning two versions of a draft.

  The alignment is the whole job. Zipping the two lists and comparing by
  position marks everything after an inserted paragraph as changed, which is
  a diff nobody can read.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Diff

  defp p(list), do: Enum.join(list, "\n\n")

  test "identical prose is all same" do
    text = p(["One.", "Two.", "Three."])
    rows = Diff.rows(text, text)

    assert Enum.all?(rows, &match?({:same, _, _}, &1))
    refute Diff.any?(rows)
  end

  test "an edited paragraph is a change, not a delete and an insert" do
    rows = Diff.rows(p(["One.", "Two.", "Three."]), p(["One.", "Two, amended.", "Three."]))

    assert [{:same, "One.", "One."}, {:change, "Two.", "Two, amended."}, {:same, _, _}] = rows
    assert Diff.stat(rows).changed == 1
  end

  test "a paragraph inserted in the middle shifts nothing after it" do
    rows = Diff.rows(p(["One.", "Two."]), p(["One.", "INSERTED.", "Two."]))

    assert [{:same, "One.", _}, {:ins, "INSERTED."}, {:same, "Two.", _}] = rows
    assert Diff.stat(rows) == %{same: 2, changed: 0, added: 1, removed: 0}
  end

  test "a removed paragraph is a delete, and the rest still lines up" do
    rows = Diff.rows(p(["One.", "GONE.", "Three."]), p(["One.", "Three."]))

    assert [{:same, "One.", _}, {:del, "GONE."}, {:same, "Three.", _}] = rows
    assert Diff.stat(rows).removed == 1
  end

  test "rewrapping is not an edit" do
    a = "A sentence that\nwraps across lines."
    b = "A sentence that wraps   across lines."

    assert [{:same, _, _}] = Diff.rows(a, b)
  end

  test "a changed pair carries a word-level diff inside it" do
    [{:change, l, r}] = Diff.rows("The kettle went cold.", "The kettle went stone cold.")

    parts = Diff.words(l, r)

    assert Enum.any?(parts, &match?({:ins, _}, &1))
    assert Enum.any?(parts, &match?({:same, _}, &1))
  end

  test "several edits in a row pair up rather than stacking" do
    rows = Diff.rows(p(["A.", "B.", "C."]), p(["A1.", "B1.", "C1."]))

    assert length(rows) == 3
    assert Enum.all?(rows, &match?({:change, _, _}, &1))
  end

  test "more new paragraphs than old leaves the extra as inserts" do
    rows = Diff.rows(p(["A."]), p(["A1.", "B.", "C."]))

    assert Enum.count(rows, &match?({:change, _, _}, &1)) == 1
    assert Enum.count(rows, &match?({:ins, _}, &1)) == 2
  end

  test "empty sides do not crash" do
    assert Diff.rows("", "") == []
    assert Enum.all?(Diff.rows("", p(["A.", "B."])), &match?({:ins, _}, &1))
    assert Enum.all?(Diff.rows(p(["A.", "B."]), ""), &match?({:del, _}, &1))
    assert Diff.rows(nil, nil) == []
  end

  test "a real-sized draft aligns in reasonable time" do
    old = p(for i <- 1..120, do: "Paragraph #{i}. " <> String.duplicate("word ", 60))

    new =
      p(
        for i <- 1..120,
            do:
              if(i == 75,
                do: "Paragraph 75 REWRITTEN.",
                else: "Paragraph #{i}. " <> String.duplicate("word ", 60)
              )
      )

    {micros, rows} = :timer.tc(fn -> Diff.rows(old, new) end)

    assert Diff.stat(rows).changed == 1
    assert micros < 3_000_000, "120 paragraphs took #{div(micros, 1000)}ms"
  end
end
