defmodule MarginaliaWeb.NoteDeckTest do
  @moduledoc """
  The rail, when a section has more notes than it has room for.

  What is asserted is that the notes are all still on the page. The deck is
  a control, and a control that quietly drops the fifth note would be a much
  worse bug than the height it was added to fix — invisible, and only found
  by somebody who knew what they were looking for.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Repo, Works}
  alias Marginalia.Works.Edge

  setup %{conn: conn} do
    user = user_fixture()

    para = "The kettle went cold on the counter. " <> String.duplicate("word ", 120)
    body = "# A draft\n\n" <> para <> "\n\n" <> String.duplicate("other ", 120)

    {:ok, work} = Works.create_work(user.id, %{"title" => "Draft", "body" => body})
    {:ok, work} = Works.set_status(work, "read")

    section = hd(Works.list_sections(work.id))
    %{conn: log_in_user(conn, user), work: work, section: section}
  end

  defp beat(section, work, kind, title, quote) do
    {:ok, n} =
      Works.insert_node(%{
        work_id: work.id,
        section_id: section.id,
        node_type: kind,
        title: title,
        body: "why #{title}",
        quote: quote
      })

    n
  end

  # A draft's own margin notes are its beats plus the connections between
  # them, and the connection is shown on the beat it starts from. That is
  # the only way to get more than one kind into one place in the rail, which
  # is the case the stacking exists for.
  defp links(work, from, to, type) do
    Repo.insert!(%Edge{
      work_id: work.id,
      from_id: from.id,
      to_id: to.id,
      edge_type: type,
      rationale: "because #{type}"
    })
  end

  defp read(conn, work) do
    {:ok, _view, html} = live(conn, ~p"/works/#{work.slug}?view=read")
    html
  end

  test "four notes are four plain cards, with nothing to press", ctx do
    for i <- 1..4, do: beat(ctx.section, ctx.work, "beat", "Beat #{i}", "nowhere in the text")

    html = read(ctx.conn, ctx.work)

    for i <- 1..4, do: assert(html =~ "Beat #{i}")
    refute html =~ ~r/class="mg-note-slot [a-z_]+ deck"/, "four fits; a pager on it is noise"
    refute html =~ ~s(data-step)
  end

  test "seven notes stack by kind and every one is still on the page", ctx do
    titles = [
      "Opens on the broken link",
      "Locates it in file mode",
      "Gives a verification procedure",
      "Prescribes the two-part edit",
      "Template edits are inert",
      "Splits seven into four and three",
      "Lists the deliverables"
    ]

    [a, b, c, d, e, f, g] =
      Enum.map(titles, &beat(ctx.section, ctx.work, "beat", &1, "nowhere in the text"))

    # three beats carry a connection each, so the pile is four kinds: the
    # shape of the screenshot this came from
    links(ctx.work, b, a, "pays_off")
    links(ctx.work, c, a, "pays_off")
    links(ctx.work, d, e, "requires")
    links(ctx.work, e, f, "develops")

    html = read(ctx.conn, ctx.work)

    # the whole point: behind a control is not the same as gone
    for title <- titles do
      assert html =~ title, "#{title} must still be in the document"
    end

    _ = g

    assert html =~ ~r/class="mg-note-slot [a-z_]+ deck"/
    assert html =~ ~s(data-step="1")
    assert html =~ ~s(data-step="-1")

    # seven beats in one stack, and the two pays-off connections in another
    assert html =~ "1 / 7"
    assert html =~ "1 / 2"
  end

  test "only the first card of a stack starts visible", ctx do
    for i <- 1..5, do: beat(ctx.section, ctx.work, "beat", "Beat #{i}", "nowhere in the text")

    html = read(ctx.conn, ctx.work)

    # one `on` per deck, and it is the first
    [deck] = Regex.run(~r/<div class="cards">.*?<\/div>\s*<div class="nav">/s, html)
    ons = Regex.scan(~r/class="[^"]*\bon\b[^"]*"/, deck)

    assert length(ons) == 1, "exactly one card of the five is visible to start with"
    assert html =~ "1 / 5"
  end

  test "a pile of one is a card, not a deck of one", ctx do
    beat(ctx.section, ctx.work, "beat", "The only note", "nowhere in the text")

    html = read(ctx.conn, ctx.work)

    assert html =~ "The only note"
    refute html =~ ~s(class="nav")
  end

  test "the pile does not lie about how deep it is", ctx do
    # two layers drawn under a pile of two would say three, and the pager
    # under it says two — a stack that contradicts its own count is worse
    # than a flat card
    [a, b, c, d, e] =
      Enum.map(1..5, &beat(ctx.section, ctx.work, "beat", "Beat #{&1}", "nowhere in the text"))

    links(ctx.work, b, a, "pays_off")
    links(ctx.work, c, a, "pays_off")
    links(ctx.work, d, e, "requires")

    html = read(ctx.conn, ctx.work)

    assert html =~ ~r/class="mg-note-slot beat deck deep"/, "five beats is deep"

    refute html =~ ~r/class="mg-note-slot pays_off deck deep"/,
           "two pays-off is a pair, not a pile"

    assert html =~ ~r/class="mg-note-slot pays_off deck"/
  end
end
