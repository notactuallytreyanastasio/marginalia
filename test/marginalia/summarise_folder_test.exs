defmodule Marginalia.SummariseFolderTest do
  @moduledoc """
  Summarising every document in a folder.

  Nothing here reaches the model. What is worth pinning down is which
  documents the pass would *skip*, because that is the difference between
  re-reading a hundred and eleven imported pull requests and reading the
  four that arrived since — and it is decided before a single call is made.
  """
  use Marginalia.DataCase, async: true

  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Repo, Stacks, Works}
  alias Marginalia.Works.DocumentSummary

  setup do
    user = user_fixture()
    {:ok, folder} = Folders.create_folder(user.id, %{name: "Imported"})

    make = fn title ->
      {:ok, w} =
        Works.create_work(user.id, %{
          "title" => title,
          "body" => "# #{title}\n\n" <> String.duplicate("word ", 90)
        })

      {:ok, _} = Folders.move_work(user.id, w.id, folder.id)
      w
    end

    %{user: user, folder: folder, a: make.("1. One"), b: make.("2. Two"), c: make.("3. Three")}
  end

  defp summarised(work, text \\ "what it says") do
    Repo.insert!(%DocumentSummary{work_id: work.id, summary: text, fingerprint: "f"})
  end

  test "the count is part of the folder's stats", ctx do
    assert Stacks.stats(ctx.user.id, ctx.folder.id).summarised == 0

    summarised(ctx.a)
    summarised(ctx.b)

    stats = Stacks.stats(ctx.user.id, ctx.folder.id)
    assert stats.documents == 3
    assert stats.summarised == 2
  end

  test "a row with an empty summary does not count as summarised", ctx do
    summarised(ctx.a, "")
    assert Stacks.stats(ctx.user.id, ctx.folder.id).summarised == 0
  end

  test "a folder already summarised does nothing and calls nobody", ctx do
    for w <- [ctx.a, ctx.b, ctx.c], do: summarised(w)

    me = self()

    assert {0, []} =
             Stacks.summarise_documents(ctx.user.id, ctx.folder.id,
               on_step: fn w, i, t -> send(me, {:step, w.title, i, t}) end
             )

    refute_received {:step, _, _, _}
  end

  test "an empty folder is not an error", ctx do
    {:ok, empty} = Folders.create_folder(ctx.user.id, %{name: "Nothing in it"})
    assert {0, []} = Stacks.summarise_documents(ctx.user.id, empty.id)
  end

  test "another writer's folder yields nothing rather than their documents", ctx do
    theirs = user_fixture()
    assert {0, []} = Stacks.summarise_documents(theirs.id, ctx.folder.id)
  end

  test "the count the page shows is what would actually be worked on", ctx do
    summarised(ctx.a)

    stats = Stacks.stats(ctx.user.id, ctx.folder.id)

    # the button says "Summarise the other N", and N has to be the number the
    # pass would really touch or the progress bar lies from the first tick
    assert stats.documents - stats.summarised == 2
  end

  describe "how many pairs of it are related" do
    test "counts only pairs with both ends inside the folder", ctx do
      assert Stacks.stats(ctx.user.id, ctx.folder.id).related == 0

      {:ok, inside} = Marginalia.Links.get_or_create(ctx.a.id, ctx.b.id)
      assert Stacks.stats(ctx.user.id, ctx.folder.id).related == 1

      # a link out of the folder is a real link and not this folder's
      # business: counting it would make the number under the button move
      # for something the button did not do
      {:ok, outside} =
        Works.create_work(ctx.user.id, %{
          "title" => "Elsewhere",
          "body" => "# E\n\n" <> String.duplicate("word ", 90)
        })

      {:ok, _} = Marginalia.Links.get_or_create(ctx.a.id, outside.id)
      assert Stacks.stats(ctx.user.id, ctx.folder.id).related == 1

      _ = inside
    end

    test "an empty folder has none rather than raising", ctx do
      {:ok, empty} = Folders.create_folder(ctx.user.id, %{name: "Empty"})
      assert Stacks.stats(ctx.user.id, empty.id).related == 0
    end
  end

  describe "reading each document" do
    test "a folder whose documents are all mapped has nothing to do", ctx do
      for w <- [ctx.a, ctx.b, ctx.c], do: Works.set_status(w, "read")

      me = self()

      assert {0, []} =
               Stacks.read_documents(ctx.user.id, ctx.folder.id,
                 on_step: fn w, i, t -> send(me, {:step, w.title, i, t}) end
               )

      refute_received {:step, _, _, _}
    end

    test "mapped counts documents with a graph, not documents with a step", ctx do
      stats = Stacks.stats(ctx.user.id, ctx.folder.id)
      assert stats.documents == 3
      assert stats.mapped == 0

      # a step is the forward read's output and says nothing about whether
      # the document has a map of its own — the distinction that made
      # relating a fully-stepped folder produce nothing
      Repo.insert!(%Stacks.Step{
        folder_id: ctx.folder.id,
        work_id: ctx.a.id,
        ordinal: 1,
        capability: "x"
      })

      stats = Stacks.stats(ctx.user.id, ctx.folder.id)
      assert stats.read == 1, "one step"
      assert stats.mapped == 0, "and still no map"

      Works.set_status(ctx.a, "read")
      assert Stacks.stats(ctx.user.id, ctx.folder.id).mapped == 1
    end

    test "another writer's folder reads nothing", ctx do
      assert {0, []} = Stacks.read_documents(user_fixture().id, ctx.folder.id)
    end
  end
end
