defmodule Marginalia.BeatDensityTest do
  @moduledoc """
  The section pass returned 8–10 beats for a 574-word section however plainly
  the prompt asked for two. A target alone is ignored; a stated limit is
  obeyed for short sections and still overshot for long ones, so the limit is
  enforced here too.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.{Analysis, Works}
  import Marginalia.AccountsFixtures

  describe "the target" do
    test "scales with the section, with a floor and a cap" do
      assert Analysis.beat_target(100) == 2
      assert Analysis.beat_target(1_100) == 5
      assert Analysis.beat_target(100_000) == 14
    end

    test "the limit leaves room above the target without licensing a list" do
      for words <- [100, 574, 1_309, 5_000] do
        t = Analysis.beat_target(words)
        c = Analysis.beat_ceiling(words)
        assert c > t, "the limit must leave room for a dense section"
        assert c < t * 2, "the limit must not license twice the target"
      end
    end
  end

  describe "thinning an over-long answer" do
    setup do
      user = user_fixture()
      # one long section, so the ceiling bites
      body = "# One\n\n" <> String.duplicate("word ", 1_300)
      {:ok, work} = Works.create_work(user.id, %{"title" => "W", "body" => body})
      %{work: work, section: hd(Works.list_sections(work.id))}
    end

    test "keeps the section covered end to end rather than truncating it",
         %{work: work, section: section} do
      ceiling = Analysis.beat_ceiling(section.word_count)

      beats =
        for i <- 1..(ceiling * 3) do
          %{node_type: "beat", title: "beat #{i}", quote: nil}
        end

      kept = :erlang.apply(Analysis, :thin, [beats, ceiling, section.id])

      assert length(kept) == ceiling
      # the first and last survive: truncation would drop the end of the
      # section, which is worse than having too many beats
      assert hd(kept).title == "beat 1"
      assert List.last(kept).title == "beat #{ceiling * 3}"
      assert work.id
    end

    test "leaves a normal answer alone", %{section: section} do
      beats = for i <- 1..3, do: %{title: "beat #{i}"}
      assert :erlang.apply(Analysis, :thin, [beats, 10, section.id]) == beats
    end
  end

  test "the section pass is a tool call, so the shape is enforced not requested" do
    tool = Analysis.beats_tool()
    assert tool["function"]["name"] == "record_beats"

    item = tool["function"]["parameters"]["properties"]["beats"]["items"]
    assert Enum.sort(item["required"]) == ["note", "quote", "title"]
  end
end
