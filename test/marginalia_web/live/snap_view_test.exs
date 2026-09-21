defmodule MarginaliaWeb.SnapViewTest do
  @moduledoc """
  Reading two drafts against each other, and getting back to changing one.

  The side-by-side view is where you see the problem; the draft's own page
  is where you fix it. Before this there was no way from one to the other
  except the back button and a search for the paragraph.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Repo, Works}
  alias Marginalia.Links.LinkEdge

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    user = user_fixture()
    pad = String.duplicate("word ", 80)

    make = fn title, first ->
      {:ok, w} = Works.create_work(user.id, %{"title" => title, "body" => "# H\n\n#{first} #{pad}"})
      {:ok, w} = Works.set_status(w, "read")
      w
    end

    long = make.("The long version", "The kettle went cold on the counter.")
    short = make.("The long version — in summary", "It went cold.")

    node = fn w, title, quote ->
      {:ok, n} =
        Works.insert_node(%{
          work_id: w.id,
          section_id: hd(Works.list_sections(w.id)).id,
          node_type: "beat",
          title: title,
          body: "b",
          quote: quote
        })

      n
    end

    {:ok, link} = Links.get_or_create(long.id, short.id)

    Repo.insert!(%LinkEdge{
      link_id: link.id,
      from_id: node.(long, "The kettle", "The kettle went cold on the counter.").id,
      to_id: node.(short, "It went cold", "It went cold.").id,
      edge_type: "echoes",
      rationale: "Four sentences became one."
    })

    link = Repo.update!(Ecto.Changeset.change(link, status: "linked"))

    %{conn: log_in_user(conn, user), link: link, long: long, short: short}
  end

  test "every paragraph offers a way back to editing it", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/links/#{ctx.link.id}?lead=#{ctx.long.slug}")

    # the fragment matters: it lands on the paragraph, not at the top of a
    # document you then have to find it in
    assert html =~ ~s(href="/works/#{ctx.long.slug}?view=read#block-s1p1")
    assert html =~ ~s(href="/works/#{ctx.short.slug}?view=read#block-s1p1")
    assert html =~ ">edit</a>"
  end

  test "each side links to its own draft, not to the other one", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/links/#{ctx.link.id}?lead=#{ctx.long.slug}")

    [lead, other] = String.split(html, ~s(id="fl-other"), parts: 2)

    assert lead =~ ctx.long.slug
    refute lead =~ ~s(/works/#{ctx.short.slug}?view=read#block)
    assert other =~ ctx.short.slug
  end

  test "swapping sides swaps which draft each column edits", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/links/#{ctx.link.id}?lead=#{ctx.short.slug}")

    [lead, _other] = String.split(html, ~s(id="fl-other"), parts: 2)
    assert lead =~ ~s(/works/#{ctx.short.slug}?view=read#block)
  end

  test "the block ids it links to are the ones the draft's page renders", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/works/#{ctx.long.slug}?view=read")

    # the fragment is only a way back if the target exists
    assert html =~ ~s(id="block-s1p1")
  end
end
