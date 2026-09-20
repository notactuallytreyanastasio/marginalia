defmodule MarginaliaWeb.SitemapController do
  @moduledoc """
  Where the public pages are, for anything that reads sitemaps.

  There are several hundred of them and almost none are reachable by
  following links from the front page: the drafts index lists them, but a
  crawler arriving at one linked pair has no way to discover the other three
  hundred and ninety-one. robots.txt says what not to visit; this says what
  is there.

  Built from the same functions the pages use, so a page that stops being
  public stops being listed without anybody remembering to edit this. Cached
  alongside them, because it is the same work.
  """
  use MarginaliaWeb, :controller

  alias Marginalia.{Cache, Cases, Links, Works}

  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, Cache.fetch(:sitemap, &build/0, :timer.minutes(30)))
  end

  defp build do
    urls =
      ["/", "/cases", "/drafts", "/linked", "/reading", "/works/new"] ++
        case_urls() ++ draft_urls() ++ link_urls() ++ reading_urls()

    body =
      urls
      |> Enum.uniq()
      |> Enum.map_join("\n", fn path ->
        "  <url><loc>#{escape(absolute(path))}</loc></url>"
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemap.org/schemas/sitemap/0.9">
    #{body}
    </urlset>
    """
  end

  defp case_urls do
    Enum.flat_map(Cases.published(), fn c ->
      ["/cases/#{c.slug}", "/cases/#{c.slug}/read"]
    end)
  end

  # Every draft, and the diff for the ones that have one. A draft nobody has
  # changed has a changes page that says so, and listing three hundred of
  # those is asking a crawler to fetch three hundred empty tables.
  defp draft_urls do
    Enum.flat_map(Works.public_drafts(), fn w ->
      ["/drafts/#{w.slug}"] ++
        if Works.revision_count(w.id) > 0, do: ["/drafts/#{w.slug}/changes"], else: []
    end)
  end

  defp link_urls, do: Enum.map(Links.public_links(), &"/linked/#{&1.link.id}")

  defp reading_urls do
    Enum.map(Marginalia.Folders.published(), &"/reading/#{&1.slug}")
  end

  # NOT `url/1`: that is Phoenix's verified-routes macro, and defining one
  # here shadows it into a compile error about a non-literal ~p path.
  defp absolute(path), do: MarginaliaWeb.Endpoint.url() <> path

  defp escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end
end
