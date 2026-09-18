defmodule Marginalia.CutsTest do
  @moduledoc "Addressing passages across drafts, and what survives validation."
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Cuts, Folders, Works}

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

  describe "keeping only what can be checked" do
    # These exist because the validator was private, nothing exercised it, and
    # a rename from "document" to "member" silently dropped every claim on
    # every folder while the theses still looked fine.
    setup do
      members = [
        %{
          n: 1,
          kind: "work",
          id: 10,
          label: "Opinion",
          text: "The court held that standing\nwas absent from the start."
        },
        %{
          n: 2,
          kind: "work",
          id: 11,
          label: "Dissent",
          text: "Standing was plainly present, and the majority says otherwise."
        }
      ]

      %{members: members}
    end

    defp thread(evidence),
      do: %{"threads" => [%{"claim" => "They disagree.", "evidence" => evidence}]}

    test "a claim with two locatable quotes survives", %{members: members} do
      raw =
        thread([
          %{"member" => 1, "quote" => "standing was absent"},
          %{"member" => 2, "quote" => "Standing was plainly present"}
        ])

      {result, dropped} = Cuts.validate(raw, members)

      assert dropped == []
      assert [%{"claim" => "They disagree.", "evidence" => evidence}] = result.threads
      assert Enum.map(evidence, & &1["label"]) == ["Opinion", "Dissent"]
      assert Enum.map(evidence, & &1["id"]) == [10, 11]
    end

    test "the stored quote is the member's wording, not the model's", %{members: members} do
      # the source has a line break in it; the model quotes across it
      raw =
        thread([
          %{"member" => 1, "quote" => "held that standing was absent"},
          %{"member" => 2, "quote" => "Standing was plainly present"}
        ])

      {result, []} = Cuts.validate(raw, members)
      [first, _] = hd(result.threads)["evidence"]
      assert String.contains?(first["quote"], "\n")
    end

    test "a fabricated quote takes the claim down with it", %{members: members} do
      raw =
        thread([
          %{"member" => 1, "quote" => "standing was absent"},
          %{"member" => 2, "quote" => "the court never reached the question"}
        ])

      {result, dropped} = Cuts.validate(raw, members)

      assert result.threads == []
      assert Enum.any?(dropped, &String.contains?(&1, "quote is not in member 2"))
      assert Enum.any?(dropped, &String.contains?(&1, "needs 2"))
    end

    test "a claim resting on one member is not a finding about the group", %{members: members} do
      raw = thread([%{"member" => 1, "quote" => "standing was absent"}])

      {result, dropped} = Cuts.validate(raw, members)

      assert result.threads == []
      assert Enum.any?(dropped, &String.contains?(&1, "1 verifiable citation"))
    end

    test "a member number that is not in the group is refused", %{members: members} do
      raw =
        thread([
          %{"member" => 1, "quote" => "standing was absent"},
          %{"member" => 7, "quote" => "standing was absent"}
        ])

      {_result, dropped} = Cuts.validate(raw, members)
      assert Enum.any?(dropped, &String.contains?(&1, "member 7 is not in this group"))
    end

    test "the older key name still parses, so a prompt tweak cannot silently void everything",
         %{members: members} do
      raw =
        thread([
          %{"document" => 1, "quote" => "standing was absent"},
          %{"document" => 2, "quote" => "Standing was plainly present"}
        ])

      {result, dropped} = Cuts.validate(raw, members)
      assert dropped == []
      assert length(result.threads) == 1
    end

    test "tensions are checked exactly as threads are", %{members: members} do
      raw = %{
        "tensions" => [
          %{
            "claim" => "One says the opposite of the other.",
            "evidence" => [
              %{"member" => 1, "quote" => "standing was absent"},
              %{"member" => 2, "quote" => "made this up entirely"}
            ]
          }
        ]
      }

      {result, dropped} = Cuts.validate(raw, members)
      assert result.tensions == []
      assert dropped != []
    end
  end

  describe "reading a folder" do
    test "a leaf folder is read over its drafts", %{user: user} do
      {:ok, f} = Folders.create_folder(user.id, %{name: "A case"})
      a = draft(user, "Opinion")
      b = draft(user, "Dissent")
      for w <- [a, b], do: {:ok, _} = Folders.move_work(user.id, w.id, f.id)

      members = Cuts.members(user.id, f.id)

      assert length(members) == 2
      assert Enum.map(members, & &1.kind) == ["work", "work"]
      assert Enum.map(members, & &1.n) == [1, 2]
      assert Enum.all?(members, &(&1.text != ""))
    end

    test "a folder of folders is read over its children, not their drafts", %{user: user} do
      {:ok, top} = Folders.create_folder(user.id, %{name: "Cases"})
      {:ok, one} = Folders.create_folder(user.id, %{name: "Case one", parent_id: top.id})
      {:ok, two} = Folders.create_folder(user.id, %{name: "Case two", parent_id: top.id})
      {:ok, _} = Folders.move_work(user.id, draft(user, "Opinion").id, one.id)
      {:ok, _} = Folders.move_work(user.id, draft(user, "Dissent").id, two.id)

      members = Cuts.members(user.id, top.id)

      assert Enum.map(members, & &1.kind) == ["folder", "folder"]
      assert Enum.map(members, & &1.label) == ["Case one", "Case two"]
      # neither child has been read, and the text says so rather than pretending
      assert Enum.all?(members, &String.contains?(&1.text, "not read yet"))
      refute Enum.any?(members, & &1.read?)
    end

    test "a read child contributes its reading, not its drafts", %{user: user} do
      {:ok, top} = Folders.create_folder(user.id, %{name: "Cases"})
      {:ok, one} = Folders.create_folder(user.id, %{name: "Case one", parent_id: top.id})
      {:ok, _} = Folders.move_work(user.id, draft(user, "Opinion").id, one.id)

      {:ok, cut} = Cuts.open_folder_reading(user.id, one.id)

      {:ok, _} =
        cut
        |> Marginalia.Cuts.Cut.result_changeset(%{
          status: "read",
          thesis: "The court split on standing.",
          threads: [%{"claim" => "Both turn on the same footnote."}]
        })
        |> Marginalia.Repo.update()

      [member] = Cuts.members(user.id, top.id)

      assert member.read?
      assert member.text =~ "The court split on standing."
      assert member.text =~ "Both turn on the same footnote."
    end

    test "a folder has one reading, and re-opening replaces it", %{user: user} do
      {:ok, f} = Folders.create_folder(user.id, %{name: "A case"})
      {:ok, _} = Folders.move_work(user.id, draft(user, "Opinion").id, f.id)

      {:ok, first} = Cuts.open_folder_reading(user.id, f.id, "why?")
      {:ok, again} = Cuts.open_folder_reading(user.id, f.id, "why really?")

      assert first.id == again.id
      assert again.question == "why really?"
      assert length(Cuts.list_cuts(user.id)) == 1
    end

    test "another writer's folder cannot be read", %{user: user, other: other} do
      {:ok, theirs} = Folders.create_folder(other.id, %{name: "Theirs"})
      assert {:error, :not_found} = Cuts.open_folder_reading(user.id, theirs.id)
    end

    test "a reading is stale once the folder holds something else", %{user: user} do
      {:ok, f} = Folders.create_folder(user.id, %{name: "A case"})
      {:ok, _} = Folders.move_work(user.id, draft(user, "Opinion").id, f.id)
      {:ok, cut} = Cuts.open_folder_reading(user.id, f.id)

      {:ok, cut} =
        cut
        |> Marginalia.Cuts.Cut.result_changeset(%{
          status: "read",
          content_sha: Cuts.content_sha(Cuts.members(user.id, f.id))
        })
        |> Marginalia.Repo.update()

      assert Cuts.current?(cut, user.id)

      {:ok, _} = Folders.move_work(user.id, draft(user, "Late arrival").id, f.id)
      refute Cuts.current?(cut, user.id)
    end
  end
end
