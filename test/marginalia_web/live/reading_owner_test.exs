defmodule MarginaliaWeb.ReadingOwnerTest do
  @moduledoc """
  A published reading is a page anybody can open. The documents behind it
  are not.

  So the way back to them is shown to the writer and to nobody else, and
  that is the only thing worth testing carefully here: a draft's slug *is*
  the permission to read it, so printing one on a public page gives it away
  to everyone who ever opens that page.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Repo, Stacks, Works}

  setup do
    # publishing is reserved to the account this deploy belongs to, not to
    # whoever happens to own the folder — see Folders.publish/2
    owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})
    {:ok, folder} = Folders.create_folder(owner.id, %{name: "A method"})

    {:ok, work} =
      Works.create_work(owner.id, %{
        "title" => "The first chapter",
        "body" => "# One\n\n" <> String.duplicate("word ", 90)
      })

    {:ok, _} = Folders.move_work(owner.id, work.id, folder.id)

    Repo.insert!(%Stacks.Step{
      folder_id: folder.id,
      work_id: work.id,
      ordinal: 1,
      capability: "read a folder forwards"
    })

    {:ok, folder} = Folders.publish(owner.id, folder.id)

    %{owner: owner, folder: folder, work: work}
  end

  describe "the step page" do
    test "the writer is offered the draft it was read out of", ctx do
      conn = log_in_user(build_conn(), ctx.owner)
      {:ok, _view, html} = live(conn, ~p"/reading/#{ctx.folder.slug}/1")

      assert html =~ "The first chapter"
      assert html =~ ~s(href="/works/#{ctx.work.slug}?view=read")
      assert html =~ "yours to edit"
    end

    test "a stranger is not, and the slug is nowhere on the page", ctx do
      {:ok, _view, html} = live(build_conn(), ~p"/reading/#{ctx.folder.slug}/1")

      refute html =~ ctx.work.slug, "the slug is the permission; it must not leak"
      refute html =~ "yours to edit"
    end

    test "somebody else logged in is a stranger too", ctx do
      conn = log_in_user(build_conn(), user_fixture())
      {:ok, _view, html} = live(conn, ~p"/reading/#{ctx.folder.slug}/1")

      refute html =~ ctx.work.slug
    end
  end

  describe "the story page" do
    setup ctx do
      Repo.insert!(%Stacks.Story{
        folder_id: ctx.folder.id,
        title: "How the thing was built",
        opening: "It starts with one broken link.",
        closing: "And it ends with seven.",
        movements: [%{"heading" => "The first move", "prose" => "What happened.", "steps" => [1]}]
      })

      :ok
    end

    test "the writer is offered the folder the reading was composed from", ctx do
      conn = log_in_user(build_conn(), ctx.owner)
      {:ok, _view, html} = live(conn, ~p"/reading/#{ctx.folder.slug}")

      assert html =~ "Open the folder"
      assert html =~ ~s(href="/stacks/#{ctx.folder.id}")
    end

    test "a stranger sees no route into the folder", ctx do
      {:ok, _view, html} = live(build_conn(), ~p"/reading/#{ctx.folder.slug}")

      assert html =~ "How the thing was built", "the reading itself is public"
      refute html =~ "Open the folder"
      refute html =~ ~s(href="/stacks/#{ctx.folder.id}")
    end
  end
end
