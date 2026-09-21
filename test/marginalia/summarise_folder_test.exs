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
end
