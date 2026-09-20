defmodule MarginaliaWeb.LandingFeaturesTest do
  @moduledoc """
  The homepage describes what exists.

  A landing page drifts from the product silently: nothing breaks when a
  feature ships and the pitch does not mention it, and nothing breaks when
  the pitch keeps promising one that was removed. These are the claims worth
  pinning, and the links out of them have to actually resolve.
  """
  use MarginaliaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    # HEEx wraps prose at the source margin, so a phrase in the rendered page
    # can carry a newline and ten spaces in the middle of it.
    %{html: flat(html), conn: conn}
  end

  defp flat(html), do: String.replace(html, ~r/\s+/, " ")

  test "it names the things that were built after it was written", %{html: html} do
    assert html =~ "Where you are in twelve sections", "per-section and document summaries"
    assert html =~ "Every change, kept", "revisions, the diff and git"
    assert html =~ "read forwards", "stacks"
  end

  test "the rewrite section is not still quoting an old limit", %{html: html} do
    assert html =~ "2,500 words"

    refute html =~ "250 words",
           "the ceiling moved three times; the page must not keep the first one"
  end

  test "it says what the whole-document pass actually does", %{html: html} do
    assert html =~ "working under", "the decomposing prong"
    assert html =~ "not told what the first concluded", "the prongs are independent"
  end

  test "the git claim is specific rather than a metaphor", %{html: html} do
    assert html =~ "git log -p"
    assert html =~ "one per draft"
  end

  test "the numbers it cites are the real ones", %{html: html} do
    assert html =~ "111 stacked pull requests"
    assert html =~ "Sixty-five", "the count of chapters walked back by a later one"
  end

  describe "the work it points at" do
    # Whether that slug is published is data, not code, and the test database
    # has none — so what is checked here is that the route exists and that the
    # page it lands on behaves when the reading is absent, which is what a
    # visitor gets if it is ever unpublished.
    test "the published reading is a real route, and degrades when there is nothing there", %{
      conn: conn
    } do
      assert {:error, {:live_redirect, %{to: "/reading"}}} =
               live(conn, ~p"/reading/a-temper-backend-for-blimp-pull-request-stack")

      {:ok, _view, html} = live(conn, ~p"/reading")
      assert html =~ "Readings"
    end

    test "the cases page resolves", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/cases")
    end

    test "every link out of the page is one the router serves", %{html: html} do
      paths =
        Regex.scan(~r/href="(\/[^"#?]*)"/, html)
        |> Enum.map(fn [_, p] -> p end)
        |> Enum.uniq()
        |> Enum.reject(&String.starts_with?(&1, "/assets"))

      assert "/cases" in paths
      assert "/reading/a-temper-backend-for-blimp-pull-request-stack" in paths
      assert "/works/new" in paths

      for path <- paths do
        assert Phoenix.Router.route_info(MarginaliaWeb.Router, "GET", path, "example.com") !=
                 :error,
               "#{path} is linked from the homepage and is not a route"
      end
    end
  end

  describe "the demos" do
    test "each major feature carries one", %{html: html} do
      assert html =~ "Section 7 of 12, asked what is in it"
      assert html =~ "The Changes tab, after one accepted rewrite"
      assert html =~ "111 chapters, read forwards"
    end

    test "a demo's final frame is in the markup, not assembled by the script", %{html: html} do
      # The page has to read correctly with the script dead or motion turned
      # down. Only `reveal-ready` — which JS adds — ever hides anything.
      assert html =~ "temper_date"
      assert html =~ "cuts the gloss"
      assert html =~ "65 of the 111 are walked back by a later chapter"
    end

    test "the steps are declared in the markup for the hook to walk", %{html: html} do
      assert html =~ ~s(data-demo)
      assert html =~ ~s(data-step="1")
      assert html =~ ~s(data-step="4")
    end

    test "the diff demo marks removals and additions the same way the real one does", %{
      html: html
    } do
      assert html =~ "<del", "removed words"
      assert html =~ "<ins", "added words"
    end

    test "nothing is hidden without the class the script adds" do
      source = File.read!("lib/marginalia_web/live/landing_live.ex")

      hiding =
        Regex.scan(~r/^\s*(\.[a-z-]+[^{]*)\{[^}]*opacity:0/m, source)
        |> Enum.map(fn [_, sel] -> String.trim(sel) end)

      for sel <- hiding do
        assert String.contains?(sel, "reveal-ready"),
               "#{sel} hides content without waiting for the script; a landing page that " <>
                 "needs JS to show its own copy sometimes shows nothing"
      end
    end
  end
end
