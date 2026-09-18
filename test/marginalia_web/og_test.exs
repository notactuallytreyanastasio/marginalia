defmodule MarginaliaWeb.OgTest do
  @moduledoc """
  What a link to this looks like pasted somewhere else.

  Every page used to declare `og:url` as the site root, so a link to a
  particular case unfurled as a link to the front door — and told the
  scrapers the two were the same page.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Cases, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    Application.put_env(:marginalia, :owner_email, "owner@example.com")
    on_exit(fn -> Application.delete_env(:marginalia, :owner_email) end)

    owner = user_fixture(%{email: "owner@example.com"})
    body = "# x\n\nA sentence long enough to be a section.\n\n" <> String.duplicate("word ", 200)

    {:ok, w} = Works.create_work(owner.id, %{"title" => "Some v. Case — Opinion", "body" => body})
    {:ok, w} = Works.set_status(w, "read")
    {:ok, _} = Cases.place(w, "Some v. Case", "opinion")

    %{conn: conn}
  end

  defp meta(html, property) do
    case Regex.run(~r/<meta[^>]*(?:property|name)="#{property}"[^>]*content="([^"]*)"/, html) do
      [_, value] -> value
      _ -> nil
    end
  end

  test "the front page keeps the product's own card", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert meta(html, "og:image") =~ "/images/og.png"
    assert meta(html, "og:url") =~ ~r{/$}
  end

  describe "the cases micro-site" do
    test "has its own title, description and card", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases")

      assert meta(html, "og:title") == "The term, read closely"
      assert meta(html, "og:image") =~ "/images/og-cases.png"
      assert meta(html, "twitter:image") =~ "/images/og-cases.png"
      assert meta(html, "og:image:alt") =~ "dissent arguing with that exact sentence"
    end

    test "the description counts the corpus rather than describing it", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases")

      assert meta(html, "og:description") =~ "1 Supreme Court cases, 1 documents"
      assert meta(html, "og:description") =~ "anchored to a sentence in both"
    end

    test "each page declares itself, not the site root", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases")
      assert meta(html, "og:url") =~ "/cases"

      {:ok, _view, html} = live(conn, ~p"/cases/some-v-case")
      assert meta(html, "og:url") =~ "/cases/some-v-case"
      assert meta(html, "og:title") == "Some v. Case"

      {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read")
      assert meta(html, "og:url") =~ "/cases/some-v-case/read"
    end

    test "the canonical link agrees with og:url", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases/some-v-case")

      assert [_, href] = Regex.run(~r/<link[^>]*rel="canonical"[^>]*href="([^"]*)"/, html)
      assert href == meta(html, "og:url")
    end
  end

  test "the card image is actually there" do
    path = Path.join(:code.priv_dir(:marginalia), "static/images/og-cases.png")

    assert File.exists?(path)
    # 1.91:1 at 2x, which is what every card wants
    assert <<_::binary-16, 2400::32, 1260::32, _::binary>> = File.read!(path)
  end
end
