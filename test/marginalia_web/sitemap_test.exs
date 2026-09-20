defmodule MarginaliaWeb.SitemapTest do
  @moduledoc """
  What a crawler is told exists.

  Several hundred public pages and almost none reachable by following links:
  a crawler that lands on one linked pair cannot discover the other three
  hundred and ninety-one. robots.txt says what not to visit; this says what
  is there.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Marginalia.AccountsFixtures

  alias Marginalia.Works

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    Marginalia.Cache.invalidate_all()
    on_exit(&Marginalia.Cache.invalidate_all/0)

    owner = user_fixture(%{email: Application.get_env(:marginalia, :owner_email)})
    stranger = user_fixture()
    body = "# H\n\nALPHA. " <> String.duplicate("word ", 300)

    {:ok, mine} = Works.create_work(owner.id, %{"title" => "Mine", "body" => body})
    {:ok, theirs} = Works.create_work(stranger.id, %{"title" => "Theirs", "body" => body})

    %{conn: conn, mine: mine, theirs: theirs}
  end

  defp fetch(conn), do: conn |> get(~p"/sitemap.xml") |> response(200)

  test "it is xml and lists the public entry points", %{conn: conn} do
    xml = fetch(conn)

    assert xml =~ "<?xml"
    assert xml =~ "<urlset"

    for path <- ~w(/ /cases /drafts /linked /reading) do
      assert xml =~ "<loc>http://localhost:4000#{path}</loc>", "#{path} is missing"
    end
  end

  test "the owner's drafts are in it", %{conn: conn, mine: mine} do
    assert fetch(conn) =~ "/drafts/#{mine.slug}</loc>"
  end

  test "nobody else's draft is", %{conn: conn, theirs: theirs} do
    refute fetch(conn) =~ theirs.slug
  end

  test "a draft with no changes has no changes page listed", %{conn: conn, mine: mine} do
    refute fetch(conn) =~ "/drafts/#{mine.slug}/changes",
           "listing hundreds of empty diffs asks a crawler to fetch hundreds of empty tables"
  end

  test "a draft with changes does", %{conn: conn, mine: mine} do
    section = hd(Works.list_sections(mine.id))
    block = section.body |> String.split(~r/\n{2,}/, trim: true) |> Enum.find(&(&1 =~ "ALPHA"))
    {:ok, _} = Works.replace_block(section, block, String.replace(block, "ALPHA", "AMENDED"))

    Marginalia.Cache.invalidate_all()

    assert fetch(conn) =~ "/drafts/#{mine.slug}/changes</loc>"
  end

  test "robots.txt points at it" do
    robots = File.read!("priv/static/robots.txt")

    assert robots =~ "Sitemap:"
    assert robots =~ "/sitemap.xml"
    assert robots =~ "Disallow: /works/", "the private pages stay disallowed"
  end
end
