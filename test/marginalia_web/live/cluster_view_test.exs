defmodule MarginaliaWeb.ClusterViewTest do
  @moduledoc "The constellation drawn for a group of related drafts."
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    user = user_fixture()

    make = fn title ->
      body =
        "# #{title}\n\nA sentence long enough for a section.\n\n" <>
          String.duplicate("word ", 200)

      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      w
    end

    a = make.("Miller v. Alabama — Opinion of the Court")
    b = make.("Miller v. Alabama — Oral Argument")
    c = make.("Miller v. Alabama — Concurrence and Dissents")

    {:ok, l1} = Links.get_or_create(a.id, b.id)
    {:ok, _} = Links.set_status(l1, "linked", %{summary: "The argument that produced it."})
    {:ok, l2} = Links.get_or_create(a.id, c.id)
    {:ok, _} = Links.set_status(l2, "linked", %{summary: "The writings that answer it."})

    %{conn: log_in_user(conn, user), a: a, b: b, c: c}
  end

  test "three drafts and two links draw as one shape", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/links")

    assert html =~ "lx-web"
    assert count(html, ~s(class="node")) == 3
    assert count(html, ~s(class="edge")) == 2
    # the pair nobody has related yet, as a dashed line and in words
    assert count(html, ~s(class="gap")) == 1
    assert html =~ "Not related yet:"
  end

  test "a node opens its draft and an edge opens that pair", %{conn: conn, a: a} do
    {:ok, _view, html} = live(conn, ~p"/links")

    assert html =~ ~s(href="/works/#{a.slug}")
    assert html =~ ~r{href="/links/\d+"}
  end

  test "a lone pair is not drawn — there is no shape to show", %{conn: conn} do
    Marginalia.Repo.delete_all(Marginalia.Links.Link)
    user = user_fixture()

    mk = fn t ->
      {:ok, w} =
        Works.create_work(user.id, %{"title" => t, "body" => String.duplicate("word ", 300)})

      {:ok, w} = Works.set_status(w, "read")
      w
    end

    {:ok, _} = Links.get_or_create(mk.("Solo one").id, mk.("Solo two").id)

    {:ok, _view, html} = live(log_in_user(build_conn(), user), ~p"/links")
    refute html =~ "lx-web"
  end

  @tag :screenshot
  test "save the rendered page so it can be looked at", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/links")
    css = File.read!("priv/static/assets/css/app.css")

    File.write!(
      "/tmp/cluster.html",
      "<!doctype html><meta charset=utf-8><style>#{css}</style><body style='padding:2rem'>" <>
        Regex.replace(~r/^.*?<main[^>]*>/s, html, "")
    )
  end

  defp count(html, needle), do: length(String.split(html, needle)) - 1
end
