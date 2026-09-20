defmodule MarginaliaWeb.ReadChangesTest do
  @moduledoc """
  Reading the draft with what changed beside it.

  The Changes tab answers "what is different" away from the prose. This
  answers it while you are reading: the rail that normally holds the notes
  holds the before and after instead, and the notes move under the paragraph
  that caused them rather than disappearing.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    user = user_fixture()

    body =
      "# One\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 150) <>
        "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 150)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")
    %{conn: log_in_user(conn, user), work: work, user: user}
  end

  defp edit(work, from, to) do
    section = hd(Works.list_sections(work.id))

    block =
      section.body
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.find(&String.contains?(&1, from))

    {:ok, _} =
      Works.replace_block(section, block, String.replace(block, from, to),
        origin: "rewrite",
        note: "cuts the gloss"
      )
  end

  test "the toggle is not offered on a draft nobody has changed", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    refute html =~ "Show what changed"
  end

  test "it appears once something has changed", %{conn: conn, work: work} do
    edit(work, "ALPHA", "AMENDED")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    assert html =~ "Show what changed"
  end

  test "turning it on puts the before and after in the rail", %{conn: conn, work: work} do
    edit(work, "ALPHA", "AMENDED")
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    html = render_click(view, "toggle_changes", %{})

    assert html =~ "mg-read-rail changes"
    assert html =~ "ALPHA", "the text that was replaced has to still be readable"
    assert html =~ "AMENDED"
    assert html =~ "cuts the gloss", "and where the change came from"
  end

  test "the notes rail is replaced, not shown twice", %{conn: conn, work: work} do
    edit(work, "ALPHA", "AMENDED")
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    on = render_click(view, "toggle_changes", %{})

    rails = Regex.scan(~r/class="mg-read-rail/, on) |> length()
    assert rails == 1, "one rail at a time: notes or changes, never both"
  end

  test "it toggles back", %{conn: conn, work: work} do
    edit(work, "ALPHA", "AMENDED")
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    render_click(view, "toggle_changes", %{})
    back = render_click(view, "toggle_changes", %{})

    refute back =~ "mg-read-rail changes"
    assert back =~ "Show what changed"
  end
end
