defmodule Marginalia.MutteringsTest do
  @moduledoc """
  The words in front of the dots. The model is replaced by a function of
  `n` throughout; what is under test is what happens to what it says.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.Mutterings

  # a fresh batch every call: the table refuses a line it already holds
  defp lines(n) do
    tag = System.unique_integer([:positive])
    {:ok, Enum.map_join(1..n, "\n", &"Line #{&1} of batch #{tag}.")}
  end

  describe "parse/1" do
    test "bare lines come back as they are" do
      assert Mutterings.parse("The cheese knows.\nNobody orders rye.") == [
               "The cheese knows.",
               "Nobody orders rye."
             ]
    end

    test "numbering, bullets and quotation marks are stripped" do
      text =
        ~s|1. "The cheese knows."\n2) 'Nobody orders rye.'\n- “Butter, again.”\n* Press.\n• Wait.|

      assert Mutterings.parse(text) == [
               "The cheese knows.",
               "Nobody orders rye.",
               "Butter, again.",
               "Press.",
               "Wait."
             ]
    end

    test "an introduction, blank lines and an explanation are dropped" do
      text =
        "Here are ten things he might say:\n\nThe cheese knows.\n\n" <>
          String.duplicate("word ", 60)

      assert Mutterings.parse(text) == ["The cheese knows."]
    end

    test "a line of exactly 240 characters is kept, one more is not" do
      kept = String.duplicate("a", 240)
      dropped = String.duplicate("b", 241)
      assert Mutterings.parse(kept <> "\n" <> dropped) == [kept]
    end

    test "duplicates collapse, and nil is nothing" do
      assert Mutterings.parse("Same.\nSame.\nOther.") == ["Same.", "Other."]
      assert Mutterings.parse(nil) == []
    end
  end

  describe "generate/2" do
    test "stores what the call says, up to n, with its source" do
      assert {:ok, 3} = Mutterings.generate(3, call: &lines/1, source: "seed")
      assert Mutterings.count() == 3

      assert {:ok, 2} = Mutterings.generate(2, call: fn _ -> lines(5) end)
      assert Mutterings.count() == 5
    end

    test "a call that fails is passed through and stores nothing" do
      assert {:error, :rate_limited} =
               Mutterings.generate(3, call: fn _ -> {:error, :rate_limited} end)

      assert Mutterings.count() == 0
    end

    test "a reply with nothing usable in it is an error, not an empty success" do
      assert {:error, :nothing_usable} =
               Mutterings.generate(3, call: fn _ -> {:ok, "Here they are:\n\n"} end)
    end
  end

  describe "seed/1 and topup/1" do
    test "seed fills to a hundred and then does nothing" do
      assert {:ok, 100} = Mutterings.seed(call: &lines/1)
      assert Mutterings.count() == 100
      assert {:ok, 0} = Mutterings.seed(call: fn _ -> flunk("should not be called") end)
    end

    test "seed asks only for what is missing" do
      {:ok, 90} = Mutterings.generate(90, call: &lines/1)
      parent = self()
      assert {:ok, 10} = Mutterings.seed(call: fn n -> send(parent, {:asked, n}) && lines(n) end)
      assert_received {:asked, 10}
    end

    test "topup adds a batch every time" do
      assert {:ok, 10} = Mutterings.topup(call: &lines/1)
      assert {:ok, 10} = Mutterings.topup(call: &lines/1)
      assert Mutterings.count() == 20
      assert {:ok, 3} = Mutterings.topup(call: &lines/1, count: 3)
    end
  end

  describe "some/1" do
    test "nothing while the table is empty" do
      assert Mutterings.some(8) == []
    end

    test "up to n distinct lines, fewer when there are fewer" do
      {:ok, _} = Mutterings.generate(5, call: &lines/1)
      got = Mutterings.some(8)
      assert length(got) == 5
      assert Enum.uniq(got) == got
      assert length(Mutterings.some(2)) == 2
    end
  end

  describe "some/1 across a page's waits" do
    test "the next pick avoids what this process was shown, until it has seen nearly everything" do
      {:ok, _} = Mutterings.generate(20, call: &lines/1)
      first = Mutterings.some(8)
      second = Mutterings.some(8)
      assert first -- second == first
      third = Mutterings.some(8)
      assert length(third) == 4
      assert (first ++ second) -- third == first ++ second
      fourth = Mutterings.some(8)
      assert length(fourth) == 8
    end

    test "another process has its own memory" do
      {:ok, _} = Mutterings.generate(8, call: &lines/1)
      mine = Mutterings.some(8)
      parent = self()

      Task.await(
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Marginalia.Repo, parent, self())
          send(parent, {:theirs, Mutterings.some(8)})
        end)
      )

      assert_received {:theirs, theirs}
      assert length(theirs) == 8
      assert length(mine) == 8
    end
  end

  describe "duplicates" do
    test "a line the table already has is skipped, not stored twice and not an error" do
      same = fn _ -> {:ok, "One.\nTwo.\nThree.\nFour.\nFive."} end
      assert {:ok, 5} = Mutterings.generate(5, call: same)
      assert {:ok, 0} = Mutterings.generate(5, call: same)
      assert Mutterings.count() == 5
    end

    test "seed keeps asking when the model comes up short, and stops when full" do
      parent = self()

      call = fn n ->
        send(parent, {:asked, n})
        {:ok, Enum.map_join(1..min(n, 57), "\n", fn i -> "Round #{n} line #{i}." end)}
      end

      assert {:ok, 100} = Mutterings.seed(call: call)
      assert Mutterings.count() == 100
      assert_received {:asked, 100}
      assert_received {:asked, 43}
      refute_received {:asked, _}
    end

    test "seed gives up after four short answers and reports what it added" do
      call = fn _ -> {:ok, "The same line every time."} end
      assert {:ok, 1} = Mutterings.seed(call: call)
      assert Mutterings.count() == 1
    end
  end

  describe "one/0" do
    test "nil while the table is empty, so the dots stand alone" do
      assert Mutterings.one() == nil
    end

    test "a stored line once there are some" do
      {:ok, _} = Mutterings.generate(5, call: &lines/1)
      assert Mutterings.one() =~ ~r/^Line \d of batch \d+\.$/
    end
  end

  test "the prompt is Bobby's, verbatim" do
    assert Mutterings.prompt() ==
             "You are Fyordor Dostoyevsky. You live in the modern day. You work a job at a grilled cheese sandwich factory in Menlo Park, CA. Give some words you might utter while working alone at teh sandwich counter. Keep it 240 characters or less."
  end
end
