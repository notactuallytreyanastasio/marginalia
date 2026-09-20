defmodule MarginaliaWeb.PublicReadingTest do
  @moduledoc """
  A published stack, and everything that must stay unpublished.

  The writer whose account can publish also keeps contracts and employment
  agreements in folders beside the one being published. So the interesting
  tests here are the negative ones: private by default, one folder at a
  time, and nothing readable off a guessed id.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Repo, Works}
  alias Marginalia.Stacks.{Step, Story}

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})
    {:ok, folder} = Folders.create_folder(owner.id, %{"name" => "A Backend For Something"})
    {:ok, other} = Folders.create_folder(owner.id, %{"name" => "Employment agreements"})

    {:ok, work} =
      Works.create_work(owner.id, %{
        "title" => "1. The first thing",
        "body" => "# One\n\n" <> String.duplicate("word ", 200)
      })

    {:ok, _} = Folders.move_work(owner.id, work.id, folder.id)

    Repo.insert!(%Step{
      folder_id: folder.id,
      work_id: work.id,
      ordinal: 1,
      capability: "The thing emits a file that runs",
      lesson: "Emit one module and run it before building anything clever.",
      pitfall: "Assuming the printed form round-trips.",
      pitfall_quote: "a whole Double prints as 1",
      excerpts: [%{"caption" => "the grammar", "text" => "out_grammar do ... end"}],
      requires: []
    })

    Repo.insert!(%Story{
      folder_id: folder.id,
      title: "Half of building it is fixing the thing underneath",
      opening: "Nothing about this is hand-written at the level you would expect.",
      movements: [
        %{"heading" => "Get it running first", "prose" => "Do the cheap part.", "steps" => [1]}
      ],
      closing: "That is the method.",
      uncovered: [],
      dropped: []
    })

    %{owner: owner, folder: folder, other: other}
  end

  describe "before anything is published" do
    test "the index says so rather than listing a private folder", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/reading")

      assert html =~ "Nothing published yet"
      refute html =~ "Half of building it"
    end

    test "a folder is private the moment it is made", %{folder: folder} do
      assert is_nil(Repo.reload!(folder).published_at)
      assert is_nil(Repo.reload!(folder).slug)
    end
  end

  describe "once published" do
    setup %{owner: owner, folder: folder} do
      {:ok, folder} = Folders.publish(owner.id, folder.id)
      %{folder: folder}
    end

    test "a signed-out stranger can read the telling", %{folder: folder} do
      {:ok, _view, html} = live(build_conn(), ~p"/reading/#{folder.slug}")

      assert html =~ "Half of building it is fixing the thing underneath"
      assert html =~ "Nothing about this is hand-written"
      assert html =~ "Get it running first"
    end

    test "and the step behind a paragraph of it", %{folder: folder} do
      {:ok, _view, html} = live(build_conn(), ~p"/reading/#{folder.slug}/1")

      assert html =~ "The thing emits a file that runs"
      assert html =~ "Emit one module and run it"
      assert html =~ "Assuming the printed form round-trips"
      assert html =~ "out_grammar do", "the located passage, not the model's bare quote"
    end

    test "it appears on the index", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/reading")
      assert html =~ "Half of building it is fixing the thing underneath"
    end

    test "the slug is readable and survives a rename", %{owner: owner, folder: folder} do
      assert folder.slug == "a-backend-for-something"

      {:ok, renamed} = Folders.rename_folder(owner.id, folder.id, "Something else entirely")

      assert renamed.slug == "a-backend-for-something",
             "a link already sent to somebody must not break because the folder was renamed"
    end

    test "publishing one folder publishes only that one", %{other: other} do
      assert is_nil(Repo.reload!(other).published_at)
      assert Folders.published() |> Enum.map(& &1.name) == ["A Backend For Something"]
    end

    test "taking it back down makes it unreadable again", %{owner: owner, folder: folder} do
      {:ok, _} = Folders.unpublish(owner.id, folder.id)

      assert {:error, {:live_redirect, %{to: "/reading"}}} =
               live(build_conn(), ~p"/reading/#{folder.slug}")
    end

    test "the slug is kept while private, so re-publishing restores the URL", %{
      owner: owner,
      folder: folder
    } do
      {:ok, down} = Folders.unpublish(owner.id, folder.id)
      assert down.slug == folder.slug

      {:ok, up} = Folders.publish(owner.id, folder.id)
      assert up.slug == folder.slug
    end
  end

  describe "what cannot be reached" do
    test "an unpublished folder is not readable by slug even if one is guessed", %{folder: folder} do
      assert {:error, {:live_redirect, %{to: "/reading"}}} =
               live(build_conn(), ~p"/reading/a-backend-for-something")

      assert is_nil(Repo.reload!(folder).published_at)
    end

    test "a stranger cannot publish somebody's folder", %{folder: folder} do
      stranger = user_fixture()

      assert {:error, _} = Folders.publish(stranger.id, folder.id)
      assert is_nil(Repo.reload!(folder).published_at)
    end

    test "not even the folder's own non-owner writer can publish it", %{owner: owner} do
      writer = user_fixture()
      {:ok, theirs} = Folders.create_folder(writer.id, %{"name" => "Their drafts"})

      assert {:error, :not_owner} = Folders.publish(writer.id, theirs.id)
      assert is_nil(Repo.reload!(theirs).published_at)
      refute writer.id == owner.id
    end

    test "a step of an unpublished folder is not readable", %{folder: folder} do
      assert {:error, {:live_redirect, %{to: "/reading"}}} =
               live(build_conn(), ~p"/reading/#{folder.slug || "x"}/1")
    end
  end
end
