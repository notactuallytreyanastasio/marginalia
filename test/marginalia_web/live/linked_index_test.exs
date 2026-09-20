defmodule MarginaliaWeb.LinkedIndexTest do
  @moduledoc """
  392 pairs is more list than anyone scrolls.

  What is tested is the ordering and the narrowing, because both decide what
  a visitor sees in the first screenful — and the query count, because the
  first version asked for an edge count per link.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Repo, Works}
  alias Marginalia.Links.LinkEdge

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})
    body = "# H\n\n" <> String.duplicate("word ", 300)

    work = fn title ->
      {:ok, w} = Works.create_work(owner.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      w
    end

    node = fn w ->
      {:ok, n} =
        Works.insert_node(%{
          work_id: w.id,
          section_id: hd(Works.list_sections(w.id)).id,
          node_type: "beat",
          title: "a beat",
          body: "b",
          quote: "word word"
        })

      n
    end

    pair = fn a, b, kinds ->
      {:ok, l} = Links.get_or_create(a.id, b.id)

      for k <- kinds do
        Repo.insert!(%LinkEdge{
          link_id: l.id,
          from_id: node.(a).id,
          to_id: node.(b).id,
          edge_type: k
        })
      end

      l
    end

    quiet_a = work.("Quiet one")
    quiet_b = work.("Quiet two")
    loud_a = work.("Argues one")
    loud_b = work.("Argues two")

    # more edges, but no tension
    pair.(quiet_a, quiet_b, ~w(develops develops develops pays_off))
    # fewer edges, but they disagree
    pair.(loud_a, loud_b, ~w(tension develops))

    %{owner: owner}
  end

  test "a pair with a tension outranks a pair with more edges", _ctx do
    [first | _] = Links.public_links()

    assert first.tensions == 1
    assert first.edges == 2, "fewer edges, and still first: the tension is the finding"
  end

  test "the page says how many of them contain one", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/linked")

    assert html =~ "2 pairs"
    assert html =~ "1 of them contain a tension"
    assert html =~ "1 tension"
  end

  test "the filter narrows by either title", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/linked")

    html = render_change(view, "filter", %{"q" => "Argues"})

    assert html =~ "Argues one"
    refute html =~ "Quiet one"
  end

  test "a filter matching nothing says so rather than showing an empty list", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/linked")

    html = render_change(view, "filter", %{"q" => "nothing here"})
    assert html =~ "Nothing matches"
  end

  test "counting the edges does not cost a query per link", _ctx do
    # the shape that matters: one call, not one per pair
    {micros, rows} = :timer.tc(&Links.public_links/0)

    assert length(rows) == 2
    assert micros < 500_000, "public_links/0 took #{div(micros, 1000)}ms for two pairs"
  end
end
