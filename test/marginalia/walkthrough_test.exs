defmodule Marginalia.WalkthroughTest do
  @moduledoc """
  The walkthrough drives the real controls, so its fixtures have to be the
  real shapes. The bug this file exists for: the canned rewrite was written
  with string keys, `rewrite_panel` reads `c.text`, and the render raised —
  which in a LiveView does not show an error, it drops the socket. The tour
  got to step eight and the page quietly stopped responding.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Walkthrough

  describe "steps" do
    test "the read view has one and every step is well formed" do
      steps = Walkthrough.steps(:read)
      assert length(steps) >= 8

      for s <- steps do
        assert is_binary(s.id) and s.id != ""
        assert is_binary(s.title) and s.title != ""
        assert is_binary(s.body) and s.body != ""
        assert is_nil(s[:target]) or is_binary(s[:target])
        assert s.place in ~w(left right bottom top centre)
      end
    end

    test "every id is distinct — the hook indexes by position and reports by id" do
      ids = Walkthrough.steps(:read) |> Enum.map(& &1.id)
      assert ids == Enum.uniq(ids)
    end

    test "every action is one the client knows how to perform" do
      known_client = ~w(open_map open_thread ask_thread select rewrite edit reset)

      for s <- Walkthrough.steps(:read), act = s[:act] do
        case act do
          %{kind: "push", event: e} ->
            assert is_binary(e)

          %{kind: "client", name: n} ->
            assert n in known_client, "unknown client action #{n}"
        end
      end
    end

    test "it ends by putting the page back" do
      last = Walkthrough.steps(:read) |> List.last()
      assert last.act == %{kind: "client", name: "reset"}
    end

    test "the steps survive the trip to the browser as JSON" do
      json = Walkthrough.steps(:read) |> Jason.encode!() |> Jason.decode!()
      assert length(json) == length(Walkthrough.steps(:read))
      assert Enum.all?(json, &is_map/1)
    end

    test "a reader who does not own the draft is not shown controls they lack" do
      # found on production: as a guest, the ask and edit steps spotlit a
      # composer and an editor that are never rendered for a non-owner, so
      # two of the ten steps narrated something that had not happened
      theirs = Walkthrough.steps(:read, mine?: false) |> Enum.map(& &1.id)

      refute "ask" in theirs
      refute "edit" in theirs
      refute "rewrite" in theirs

      # what is left still works for them, and still puts the page back
      assert "thread" in theirs
      assert "filters" in theirs
      assert List.last(theirs) == "done"
    end

    test "the owner gets all of them" do
      mine = Walkthrough.steps(:read, mine?: true) |> Enum.map(& &1.id)
      assert "ask" in mine and "edit" in mine and "rewrite" in mine
      assert length(mine) > length(Walkthrough.steps(:read, mine?: false))
    end

    test "views without one get an empty list rather than an error" do
      assert Walkthrough.steps(:graph) == []
      assert Walkthrough.steps(:spine) == []
      refute Walkthrough.for_view?(:graph)
      assert Walkthrough.for_view?(:read)
    end
  end

  describe "fixtures" do
    test "the canned rewrite has the shape Rewrite.propose returns" do
      r = Walkthrough.rewrite()

      assert is_binary(r.original) and r.original != ""
      assert is_binary(r.reading)
      assert Map.has_key?(r, :section)
      assert length(r.candidates) == 3
    end

    test "candidates carry the atom keys the panel reads, not strings" do
      # `rewrite_panel` renders c.move / c.cost / c.text. A string-keyed map
      # raises there, and a raise in render takes the whole LiveView down.
      for c <- Walkthrough.rewrite().candidates do
        assert is_binary(c.text) and c.text != ""
        assert is_binary(c.move) and c.move != ""
        assert is_binary(c.cost) and c.cost != ""
      end
    end

    test "the fixture keys match what Rewrite actually produces" do
      produced =
        Marginalia.Rewrite.clean(
          [%{"text" => "a rewritten line", "move" => "Cuts it", "cost" => "Loses the aside"}],
          "the line as it stands"
        )

      assert [%{}] = produced

      assert Map.keys(hd(produced)) |> Enum.sort() ==
               Walkthrough.rewrite().candidates |> hd() |> Map.keys() |> Enum.sort()
    end

    test "no candidate is the original, which the real cleaner also rejects" do
      r = Walkthrough.rewrite()
      refute Enum.any?(r.candidates, &(&1.text == r.original))
    end

    test "the canned answer says it is canned" do
      {question, answer} = Walkthrough.exchange()

      assert is_binary(question) and question != ""
      # a fixture presented as a reading of the writer's own paragraph is the
      # one thing this product must never do
      assert answer =~ "never calls the model"
    end
  end
end
