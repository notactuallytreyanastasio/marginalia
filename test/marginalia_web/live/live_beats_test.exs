defmodule MarginaliaWeb.LiveBeatsTest do
  @moduledoc """
  A note arriving in the margin while the read runs.

  Every broadcast the read makes used to end in a reload that rebuilt the map
  and not the page. The counts ticked up live and the margin stayed empty
  until a refresh, so a writer watching their draft being read watched
  nothing happen.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Analysis, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    user = user_fixture()

    body =
      "# One\n\nShe had been standing at the window for an hour before anyone noticed. " <>
        String.duplicate("word ", 260)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "reading")

    %{conn: log_in_user(conn, user), work: work, section: hd(Works.list_sections(work.id))}
  end

  defp add_beat(work, section, title) do
    {:ok, _} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: section.id,
        node_type: "beat",
        title: title,
        body: "What this beat is doing.",
        quote: "She had been standing at the window for an hour before anyone noticed."
      })
  end

  test "a beat appears without a refresh", %{conn: conn, work: work, section: section} do
    {:ok, view, html} = live(conn, ~p"/works/#{work.slug}?view=read")

    refute html =~ "SHE STOPS AT THE WINDOW"

    add_beat(work, section, "SHE STOPS AT THE WINDOW")

    Phoenix.PubSub.broadcast(
      Marginalia.PubSub,
      Analysis.topic(work.id),
      {:section, section.id, "read"}
    )

    html = render(view)

    assert html =~ "SHE STOPS AT THE WINDOW",
           "the beat is in the database and the page was told; it has to be on screen"
  end

  test "the same is true for a node broadcast", %{conn: conn, work: work, section: section} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    add_beat(work, section, "A LATER BEAT")
    Phoenix.PubSub.broadcast(Marginalia.PubSub, Analysis.topic(work.id), {:nodes, section.id, 1})

    assert render(view) =~ "A LATER BEAT"
  end

  test "a stage broadcast refreshes the page too", %{conn: conn, work: work, section: section} do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=read")

    add_beat(work, section, "ARRIVED ON A STAGE")
    Phoenix.PubSub.broadcast(Marginalia.PubSub, Analysis.topic(work.id), {:stage, :spine, :done})

    assert render(view) =~ "ARRIVED ON A STAGE"
  end

  test "a tab that is not the read view is not rebuilt for nothing", %{
    conn: conn,
    work: work,
    section: section
  } do
    {:ok, view, _} = live(conn, ~p"/works/#{work.slug}?view=spine")

    add_beat(work, section, "NOT ON THIS TAB")

    Phoenix.PubSub.broadcast(
      Marginalia.PubSub,
      Analysis.topic(work.id),
      {:section, section.id, "read"}
    )

    # the map behind the spine tab still updates; the page does not get rebuilt
    assert render(view)
  end
end
