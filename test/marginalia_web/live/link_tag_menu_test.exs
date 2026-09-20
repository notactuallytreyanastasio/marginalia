defmodule MarginaliaWeb.LinkTagMenuTest do
  @moduledoc """
  The "3 links" chip, and the two links it used to hide.

  A hub paragraph can be the near end of several edges. The strip between
  the columns, the wire and the tap handler all read
  `block.querySelector("[data-peer-ref]")` — the *first* note on the
  paragraph — so the chip counted three connections and there was no way to
  reach the second or the third. The count was honest and the page was a
  dead end.

  What is asserted here is the markup the hover menu is built from: one
  entry per edge, each carrying the paragraph on the other side that it
  points at. The hover itself is CSS and the jump is the hook; neither is
  reachable from a LiveView test, and both are worthless if the entries are
  not on the page to begin with.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Links, Repo, Works}
  alias Marginalia.Links.LinkEdge

  @far [
    "The kettle went cold on the counter.",
    "Nobody moved to fill it again.",
    "The window stayed open all night."
  ]

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    user = user_fixture()
    pad = String.duplicate("word ", 60)

    # one paragraph, so all three of the near ends land on the same block
    {:ok, a} =
      Works.create_work(user.id, %{
        "title" => "The novel",
        "body" => "# A\n\nHe stops in the doorway and does not go through. " <> pad
      })

    # three, so each far end has a paragraph of its own to be snapped to
    {:ok, b} =
      Works.create_work(user.id, %{
        "title" => "The story",
        "body" => "# B\n\n" <> Enum.map_join(@far, "\n\n", &(&1 <> " " <> pad))
      })

    {:ok, a} = Works.set_status(a, "read")
    {:ok, b} = Works.set_status(b, "read")

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

    {:ok, link} = Links.get_or_create(a.id, b.id)

    ~w(pays_off tension echoes)
    |> Enum.zip(@far)
    |> Enum.with_index(1)
    |> Enum.each(fn {{kind, quote}, i} ->
      Repo.insert!(%LinkEdge{
        link_id: link.id,
        from_id: node.(a, "Near end #{i}", "He stops in the doorway").id,
        to_id: node.(b, "Far end #{i}", quote).id,
        edge_type: kind,
        rationale: "Reason number #{i}, which the menu has room for."
      })
    end)

    # the split view is only rendered once the pass has finished; before
    # that the page is the waiting screen and has no paragraphs at all
    link = Repo.update!(Ecto.Changeset.change(link, status: "linked"))

    %{conn: log_in_user(conn, user), link: link}
  end

  defp read(conn, link) do
    {:ok, _view, html} = live(conn, ~p"/links/#{link.id}")
    html
  end

  test "the chip still counts them", %{conn: conn, link: link} do
    assert read(conn, link) =~ "3 links"
  end

  test "one entry per edge, not one for the first", %{conn: conn, link: link} do
    html = read(conn, link)

    for i <- 1..3 do
      assert html =~ "Far end #{i}", "the menu should name every far end, including ##{i}"
      assert html =~ "Reason number #{i}", "and give its reason"
    end

    # the left column's chip: three buttons under the one paragraph
    assert length(Regex.scan(~r/class="fl-jump/, html)) >= 3
  end

  test "each entry carries the paragraph it snaps to", %{conn: conn, link: link} do
    html = read(conn, link)

    refs =
      Regex.scan(~r/data-peer-ref="([^"]+)"/, html)
      |> Enum.map(fn [_, ref] -> ref end)
      |> Enum.uniq()

    # three far ends in three different paragraphs of the other draft; if
    # the peer refs collapsed to one, the jumps would all land in the same
    # place and the menu would be decoration
    assert Enum.sort(refs) == ["s1p1", "s1p2", "s1p3"]
  end

  test "the relation of each entry is its own, not the paragraph's", %{conn: conn, link: link} do
    html = read(conn, link)

    for kind <- ~w(pays_off tension echoes) do
      assert html =~ "fl-jump k-#{kind}", "entry for #{kind} should be coloured as itself"
    end

    # and the chip over a paragraph whose edges disagree says so rather
    # than borrowing the colour of the first one
    assert html =~ "fl-tagwrap mixed"
  end
end
