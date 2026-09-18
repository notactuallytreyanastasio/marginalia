defmodule Marginalia.Cases.KinshipTest do
  @moduledoc """
  Which cases are about the same thing as which other cases.

  The first attempt scored the read pass's own commentary, which has one
  author across every document, so it measured writing style: the top
  pairs shared "inversion", "breath" and "demolition". Scoring the
  anchored quotes instead scores the judges' own words.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Cases.Kinship

  defp bag(text), do: Kinship.terms([text])

  describe "terms" do
    test "a word used once is not what a document is about" do
      assert MapSet.member?(bag("removal removal of officers"), "removal")
      refute MapSet.member?(bag("removal of officers"), "removal")
    end

    test "plurals and singulars are the same word" do
      assert MapSet.member?(bag("warrants and warrant"), "warrant")
      assert MapSet.member?(bag("agencies and agency policies policies"), "agency")
    end

    test "furniture is dropped" do
      terms = bag("the court held that the court held that the opinion says the opinion says")
      assert MapSet.size(terms) == 0
    end

    test "short words are dropped" do
      refute MapSet.member?(bag("the writ the writ"), "writ")
    end
  end

  describe "pairs" do
    setup do
      # Two pairs that share something, and filler. A term has to be in at
      # least two documents to be shared at all and in no more than a third
      # of them to be distinctive, so the fixtures have to be a corpus
      # rather than a handful.
      bags =
        %{
          1 => bag("alien alien border border unique_one unique_one"),
          2 => bag("alien alien border border unique_two unique_two"),
          3 => bag("glyphosate glyphosate labeling labeling unique_three unique_three"),
          4 => bag("glyphosate glyphosate labeling labeling unique_four unique_four"),
          5 => bag("citizenship citizenship unique_five unique_five"),
          6 => bag("sovereign sovereign unique_six unique_six")
        }

      %{bags: bags}
    end

    test "documents about the same thing find each other", %{bags: bags} do
      pairs = Kinship.pairs(bags, 10)
      found = Enum.map(pairs, &Enum.sort([&1.a, &1.b]))

      assert [1, 2] in found
      assert [3, 4] in found
      # nothing distinctive ties the filler to anything
      refute Enum.any?(found, &(5 in &1 or 6 in &1))
    end

    test "each pair names what it is that they share", %{bags: bags} do
      top = Kinship.pairs(bags, 10) |> Enum.find(&(Enum.sort([&1.a, &1.b]) == [1, 2]))

      assert "alien" in top.shared
      assert "border" in top.shared
      assert top.score > 0
    end

    test "a pair with nothing distinctive in common is not a pair" do
      bags = %{
        1 => bag("glyphosate glyphosate labeling labeling"),
        2 => bag("citizenship citizenship jurisdiction jurisdiction")
      }

      assert Kinship.pairs(bags, 10) == []
    end

    # The longest document had the most chances to coincide, and came out
    # as everyone's nearest relation.
    test "length is divided out, so the biggest document is not everyone's kin" do
      long = Enum.map_join(1..400, " ", fn i -> "filler#{i} filler#{i}" end)

      bags = %{
        1 => bag("alien alien border border " <> long),
        2 => bag("alien alien border border"),
        3 => bag("glyphosate glyphosate labeling labeling"),
        4 => bag("glyphosate glyphosate labeling labeling")
      }

      [top | _] = Kinship.pairs(bags, 10)

      assert Enum.sort([top.a, top.b]) == [3, 4],
             "the pair with a huge document in it outscored the clean one"
    end
  end
end
