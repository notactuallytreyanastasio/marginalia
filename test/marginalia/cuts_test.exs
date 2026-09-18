defmodule Marginalia.CutsTest do
  @moduledoc "Addressing passages across drafts, and what survives validation."
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Cuts, Works}

  setup do
    user = user_fixture()
    %{user: user, other: user_fixture()}
  end

  defp draft(user, title, extra \\ "") do
    body =
      "# #{title}\n\nThe first paragraph of #{title}, which is long enough to stand alone.\n\n" <>
        "A second paragraph. #{extra}\n\n" <> String.duplicate("word ", 120)

    {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
    w
  end

  describe "locating a quote" do
    @hay "A Blimp closure can see its caller's locals. `eval.zig` has a test\nthat says so outright, and tail call elimination is written around it."

    test "an exact quote comes back unchanged" do
      assert Cuts.locate("A Blimp closure", @hay) == "A Blimp closure"
    end

    test "a re-wrapped quote is found anyway" do
      # the model joins the line break; the passage still contains it
      assert found = Cuts.locate("has a test that says so outright", @hay)
      assert String.contains?(found, "\n")
      assert String.contains?(@hay, found)
    end

    test "what comes back is the draft's wording, not the model's" do
      found = Cuts.locate("has a test that says so outright", @hay)
      refute found == "has a test that says so outright"
    end

    test "a fabricated quote is not found" do
      refute Cuts.locate("A Blimp closure cannot see anything", @hay)
    end

    test "reordered words are not found" do
      refute Cuts.locate("locals caller's its see", @hay)
    end

    test "blank is not found" do
      refute Cuts.locate("   \n ", @hay)
    end
  end

  describe "addressing blocks" do
    test "every block is reachable by its ref", %{user: user} do
      w = draft(user, "Alpha")
      blocks = Cuts.blocks(w)

      assert length(blocks) > 1
      assert Enum.all?(blocks, &String.match?(&1.ref, ~r/^s\d+b\d+$/))

      for b <- blocks do
        assert Cuts.block(w, b.ref).text == b.text
      end
    end

    test "a ref that is not there returns nil", %{user: user} do
      assert Cuts.block(draft(user, "Alpha"), "s9b9") == nil
    end
  end

  describe "making a cut" do
    test "it reads the quote out of the draft, not out of the caller", %{user: user} do
      a = draft(user, "Alpha")
      b = draft(user, "Beta")
      [ba | _] = Cuts.blocks(a)
      [bb | _] = Cuts.blocks(b)

      {:ok, cut} =
        Cuts.create_cut(user.id, %{"title" => "Two drafts"}, [{a.id, ba.ref}, {b.id, bb.ref}])

      assert length(cut.picks) == 2
      assert Enum.map(cut.picks, & &1.quote) == [ba.text, bb.text]
      assert length(Cuts.works(cut)) == 2
    end

    test "another writer's draft cannot be picked", %{user: user, other: other} do
      mine = draft(user, "Mine")
      theirs = draft(other, "Theirs")
      [bm | _] = Cuts.blocks(mine)
      [bt | _] = Cuts.blocks(theirs)

      {:ok, cut} =
        Cuts.create_cut(user.id, %{"title" => "Try it"}, [{mine.id, bm.ref}, {theirs.id, bt.ref}])

      assert Enum.map(cut.picks, & &1.work_id) == [mine.id]
    end

    test "a cut with no reachable passage is refused", %{user: user, other: other} do
      theirs = draft(other, "Theirs")
      [bt | _] = Cuts.blocks(theirs)

      assert {:error, :no_passages} =
               Cuts.create_cut(user.id, %{"title" => "Nope"}, [{theirs.id, bt.ref}])
    end

    test "a result is only current for the passages it was made from", %{user: user} do
      a = draft(user, "Alpha")
      [b1, b2 | _] = Cuts.blocks(a)
      {:ok, cut} = Cuts.create_cut(user.id, %{"title" => "One"}, [{a.id, b1.ref}])

      refute Cuts.current?(cut)

      {:ok, cut} =
        cut
        |> Marginalia.Cuts.Cut.result_changeset(%{
          thesis: "x",
          content_sha: Cuts.content_sha(cut),
          status: "read"
        })
        |> Marginalia.Repo.update()

      cut = Cuts.get_cut(user.id, cut.id)
      assert Cuts.current?(cut)

      # add a passage: the stored reading is now about something else
      {:ok, wider} =
        Cuts.create_cut(user.id, %{"title" => "Two"}, [{a.id, b1.ref}, {a.id, b2.ref}])

      refute Cuts.content_sha(wider) == cut.content_sha
    end
  end
end
