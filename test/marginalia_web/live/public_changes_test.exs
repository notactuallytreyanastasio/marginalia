defmodule MarginaliaWeb.PublicChangesTest do
  @moduledoc """
  The diff, readable by a stranger.

  "Every change is kept" was the one claim on the front page nobody could
  check: the before and after lived behind a login, which makes it a promise
  rather than a demonstration.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})
    stranger = user_fixture()

    body =
      "# One\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 150) <>
        "\n\nBRAVO the second. " <> String.duplicate("word ", 150)

    {:ok, mine} = Works.create_work(owner.id, %{"title" => "Mine", "body" => body})
    {:ok, theirs} = Works.create_work(stranger.id, %{"title" => "Theirs", "body" => body})

    section = hd(Works.list_sections(mine.id))
    block = section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "ALPHA"))

    {:ok, _} =
      Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"),
        origin: "rewrite",
        note: "cuts the gloss"
      )

    %{mine: Marginalia.Repo.reload!(mine), theirs: theirs}
  end

  test "a stranger sees what the draft used to say", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{ctx.mine.slug}/changes")

    assert html =~ "As it arrived"
    assert html =~ "ALPHA", "the version that was replaced"
    assert html =~ "AMENDED"
    assert html =~ "1 edited"
  end

  test "and where the change came from", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{ctx.mine.slug}/changes")

    assert html =~ "rewrite"
    assert html =~ "cuts the gloss"
  end

  test "the draft page links to it once there is something to show", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{ctx.mine.slug}")

    assert html =~ "1 change since it arrived"
    assert html =~ "/drafts/#{ctx.mine.slug}/changes"
  end

  test "somebody else's draft has no public diff either", ctx do
    assert {:error, {:live_redirect, %{to: "/drafts"}}} =
             live(build_conn(), ~p"/drafts/#{ctx.theirs.slug}/changes")
  end

  test "an unchanged draft says so instead of showing an empty table", _ctx do
    {:ok, other} =
      Works.create_work(
        Marginalia.Accounts.owner().id,
        %{"title" => "Untouched", "body" => "# H\n\n" <> String.duplicate("word ", 300)}
      )

    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{other.slug}/changes")

    assert html =~ "Nothing has been changed yet"
    refute html =~ "As it arrived"
  end

  test "it carries no control that writes", ctx do
    {:ok, _view, html} = live(build_conn(), ~p"/drafts/#{ctx.mine.slug}/changes")

    for control <- ~w(edit_block save_block suggest_rewrite apply_rewrite summarise) do
      refute html =~ control
    end
  end
end
