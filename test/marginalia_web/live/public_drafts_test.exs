defmodule MarginaliaWeb.PublicDraftsTest do
  @moduledoc """
  The owner's drafts, out in the open.

  The interesting tests are the ones about everybody else. A visitor who
  uploads something has always had exactly one thing — a private link — and
  a public index of the owner's work must not quietly become an index of
  theirs.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})
    stranger = user_fixture()

    body = "# One\n\n" <> String.duplicate("word ", 300)

    {:ok, mine} = Works.create_work(owner.id, %{"title" => "A draft of my own", "body" => body})

    {:ok, theirs} =
      Works.create_work(stranger.id, %{"title" => "Somebody else's", "body" => body})

    %{owner: owner, stranger: stranger, mine: mine, theirs: theirs}
  end

  test "a stranger with no account sees the owner's drafts listed", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts")

    assert html =~ "A draft of my own"
    assert html =~ "#{ctx.mine.word_count} words"
  end

  test "somebody else's draft is not on the list", _ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts")
    refute html =~ "Somebody else's"
  end

  test "somebody else's draft is not served by slug either", ctx do
    assert {:error, {:live_redirect, %{to: "/drafts"}}} =
             live(build_conn(), ~p"/drafts/#{ctx.theirs.slug}")

    assert Works.public_draft(ctx.theirs.slug) == nil
  end

  test "the owner's draft reads, with no account, and is indexable", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{ctx.mine.slug}")

    assert html =~ "A draft of my own"
    assert html =~ "index, follow"
    refute html =~ "noindex"
  end

  test "the public page carries none of the controls that write or spend", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{ctx.mine.slug}")

    for control <-
          ~w(summarise_document summarise suggest_rewrite edit_block save_block start_read) do
      refute html =~ control, "#{control} is reachable from the public draft page"
    end
  end

  test "reading one mints no account for the visitor", ctx do
    before = Marginalia.Repo.aggregate(Marginalia.Accounts.User, :count)

    {:ok, _view, _html} = live(build_conn(), ~p"/drafts/#{ctx.mine.slug}")

    assert Marginalia.Repo.aggregate(Marginalia.Accounts.User, :count) == before,
           "a public page that mints a user row per crawler fills the users table"
  end

  test "a slug nobody owns goes back to the list rather than erroring", _ctx do
    assert {:error, {:live_redirect, %{to: "/drafts"}}} =
             live(build_conn(), ~p"/drafts/not-a-real-slug")
  end
end
