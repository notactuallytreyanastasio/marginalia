defmodule Marginalia.BulkLinksTest do
  @moduledoc """
  Choosing which documents to relate, before paying to relate any.

  The stack of pull requests is 111 documents, which is 6,105 pairs. The
  triage is the whole feature; what is tested here is that it cannot propose
  a pair that does not exist, and that it does not quietly skip the documents
  it is not allowed to relate.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Links, Works}
  alias Marginalia.Links.Bulk

  setup do
    user = user_fixture()
    {:ok, folder} = Folders.create_folder(user.id, %{"name" => "A series"})

    works =
      for i <- 1..4 do
        {:ok, w} =
          Works.create_work(user.id, %{
            "title" => "#{i}. Chapter #{i}",
            "body" => "# H#{i}\n\n" <> String.duplicate("word ", 300)
          })

        {:ok, _} = Folders.move_work(user.id, w.id, folder.id)
        w
      end

    %{user: user, folder: folder, works: works}
  end

  defp sheet(ctx), do: Bulk.sheet(ctx.user.id, ctx.folder.id)

  describe "the sheet handed to the model" do
    test "one numbered line per document in the folder", ctx do
      s = sheet(ctx)

      assert length(s) == 4
      assert Enum.map(s, & &1.n) == [1, 2, 3, 4]
      assert Enum.map(s, & &1.work.title) == Enum.map(ctx.works, & &1.title)
    end

    test "a document with nothing written about it still gets a line", ctx do
      assert Enum.all?(sheet(ctx), &(&1.line == ""))
    end

    test "a section summary is used when there is one", ctx do
      [w | _] = ctx.works
      section = hd(Works.list_sections(w.id))

      {:ok, _} =
        section |> Ecto.Changeset.change(summary: "It establishes the doorway.") |> Repo.update()

      line = Bulk.describe(Repo.reload!(w))
      assert line == "It establishes the doorway."
    end

    test "a stack step beats a section summary, being the better description", ctx do
      [w | _] = ctx.works
      section = hd(Works.list_sections(w.id))
      {:ok, _} = section |> Ecto.Changeset.change(summary: "A summary.") |> Repo.update()

      Repo.insert!(%Marginalia.Stacks.Step{
        folder_id: ctx.folder.id,
        work_id: w.id,
        ordinal: 1,
        capability: "The thing emits a file that runs."
      })

      assert Bulk.describe(Repo.reload!(w)) == "The thing emits a file that runs."
    end
  end

  describe "validate/2" do
    test "a real pair is kept with its hypothesis", ctx do
      s = sheet(ctx)

      out =
        Bulk.validate(
          %{
            "pairs" => [
              %{"a" => 1, "b" => 4, "why" => "one sets up four", "expect" => "pays_off"}
            ]
          },
          s
        )

      assert [%{why: "one sets up four", expect: "pays_off"} = pair] = out.pairs
      assert pair.a.id == hd(ctx.works).id
      assert pair.b.id == List.last(ctx.works).id
      assert out.dropped == []
    end

    test "a document that is not in the folder is dropped and named", ctx do
      out = Bulk.validate(%{"pairs" => [%{"a" => 1, "b" => 140}]}, sheet(ctx))

      assert out.pairs == []
      assert [reason] = out.dropped
      assert reason =~ "140"
      assert reason =~ "not in this folder"
    end

    test "a document paired with itself is refused", ctx do
      out = Bulk.validate(%{"pairs" => [%{"a" => 2, "b" => 2}]}, sheet(ctx))

      assert out.pairs == []
      assert [reason] = out.dropped
      assert reason =~ "itself"
    end

    test "the same pair twice is only one pair", ctx do
      out =
        Bulk.validate(
          %{"pairs" => [%{"a" => 1, "b" => 3}, %{"a" => 3, "b" => 1}]},
          sheet(ctx)
        )

      assert length(out.pairs) == 1
      assert [reason] = out.dropped
      assert reason =~ "twice"
    end

    test "what it chose not to propose is carried through", ctx do
      out = Bulk.validate(%{"pairs" => [], "skipped" => "2 and 3 are adjacent."}, sheet(ctx))
      assert out.skipped == "2 and 3 are adjacent."
    end
  end

  describe "relating" do
    test "an unread pair is reported by name, not skipped in silence", ctx do
      [a, b | _] = ctx.works

      [message] = Bulk.ineligible([%{a: a, b: b, why: "w", expect: "develops"}])

      assert message =~ a.title
      assert message =~ b.title
      assert message =~ "has not been read"
    end

    test "a pair is eligible only when BOTH sides have been read", ctx do
      [a, b | _] = ctx.works
      {:ok, a} = Works.set_status(a, "read")

      assert [one] = Bulk.ineligible([%{a: a, b: b, why: "w", expect: "develops"}])
      assert one =~ b.title
      refute one =~ "#{a.title} has not been read"

      {:ok, b} = Works.set_status(b, "read")
      assert Bulk.ineligible([%{a: a, b: b, why: "w", expect: "develops"}]) == []
    end

    test "a folder with nothing in it says so rather than calling the model", ctx do
      {:ok, empty} = Folders.create_folder(ctx.user.id, %{"name" => "Nothing here"})
      assert Bulk.run(ctx.user.id, empty.id) == {:error, :empty_folder}
    end

    test "somebody else's folder is not readable", ctx do
      stranger = user_fixture()
      assert Bulk.run(stranger.id, ctx.folder.id) == {:error, :no_folder}
    end

    test "linkable/1 is what the real pass needs, and these are not it", ctx do
      assert Links.linkable(ctx.user.id) == [],
             "Linker.run/2 fails with :not_read without node maps, which is why " <>
               "the bulk pass reports unread halves instead of relating them"
    end
  end
end
