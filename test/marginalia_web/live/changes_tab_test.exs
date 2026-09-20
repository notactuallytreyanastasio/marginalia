defmodule MarginaliaWeb.ChangesTabTest do
  @moduledoc "The draft as it arrived, beside the draft as it is."
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    user = user_fixture()

    body =
      "# A draft\n\nALPHA the first paragraph. " <>
        String.duplicate("word ", 120) <>
        "\n\nBRAVO the second paragraph. " <> String.duplicate("word ", 120)

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

  test "the tab is not offered on a draft nobody has changed", %{conn: conn, work: work} do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    refute html =~ ">Changes<"
  end

  test "it appears once there is something to show", %{conn: conn, work: work} do
    edit(work, "ALPHA", "AMENDED")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    assert html =~ ">Changes<"
  end

  test "the old and the new are both on the page", %{conn: conn, work: work} do
    edit(work, "ALPHA", "AMENDED")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=changes")

    assert html =~ "As it arrived"
    assert html =~ "ALPHA", "the version that was replaced has to still be visible"
    assert html =~ "AMENDED"
    assert html =~ "1 edited"
  end

  test "the revision log names where each change came from", %{conn: conn, work: work} do
    edit(work, "BRAVO", "BETTER")
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=changes")

    assert html =~ "rewrite"
    assert html =~ "cuts the gloss"
    assert html =~ "Every change, newest first"
  end

  test "an untouched draft asked for the tab directly says so rather than erroring", %{
    conn: conn,
    work: work
  } do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=changes")
    assert html =~ "Nothing has changed yet"
  end
end
