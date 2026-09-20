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

    assert html =~ "never tell the second pass what the first concluded",
           "the prongs are independent"
  end

  test "the git claim is specific rather than a metaphor", %{html: html} do
    assert html =~ "git log -p"
    assert html =~ "one per draft"
  end

  test "the numbers it cites are the real ones", %{html: html} do
    assert html =~ "111 stacked pull requests"
    assert html =~ "It found sixty-five", "the chapters walked back by a later one"
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

  describe "the chat" do
    test "the page says the chat fetches rather than recalls", %{html: html} do
      assert html =~ "It goes and looks"
      assert html =~ "the quote was fetched from your book"
    end

    test "it names the tools the chat really has", %{html: html} do
      # these are the actual function names in Marginalia.Chat.Editor
      for tool <- ["search_manuscript", "read_passage", "find_exact"] do
        assert html =~ tool, "#{tool} is shown on the page and must exist in the editor"
      end
    end

    test "every tool the page shows is one the editor defines", %{html: html} do
      source = File.read!("lib/marginalia/chat/editor.ex")

      shown =
        Regex.scan(~r/<span class="tool">([a-z_]+)<\/span>/, html)
        |> Enum.map(fn [_, name] -> name end)
        |> Enum.uniq()

      refute shown == []

      for name <- shown do
        assert source =~ ~s("name" => "#{name}"),
               "the homepage shows #{name} as a tool the chat calls, and it is not one"
      end
    end

    test "the three modes are the three that exist", %{html: html} do
      ids = Enum.map(Marginalia.Chat.Editor.modes(), & &1.label)

      for label <- ids do
        assert html =~ label, "mode #{label} exists and the page does not mention it"
      end

      assert length(ids) == 3
    end

    test "overruling it is described, in both kinds", %{html: html} do
      assert html =~ "misreading"
      assert html =~ "records a ruling"
    end
  end

  describe "the linkage preview" do
    test "the section is there with its demo", %{html: html} do
      assert html =~ "Two drafts, and what runs between them"
      assert html =~ "A novel and the story it came out of"
    end

    test "every edge kind it shows is one the linker can emit", %{html: html} do
      source = File.read!("lib/marginalia/analysis/linker.ex")

      [_, types] = Regex.run(~r/@types ~w\(([^)]+)\)/, source)
      real = String.split(types)

      shown =
        Regex.scan(~r/class="d-edge[^"]*"[^>]*><i>([a-z_]+)<\/i>/, html)
        |> Enum.map(fn [_, k] -> k end)
        |> Enum.uniq()

      refute shown == []

      for kind <- shown do
        assert kind in real,
               "the homepage draws a #{kind} edge and the linker cannot produce one"
      end
    end

    test "it names all six kinds, since it claims there are six", %{html: html} do
      source = File.read!("lib/marginalia/analysis/linker.ex")
      [_, types] = Regex.run(~r/@types ~w\(([^)]+)\)/, source)
      real = String.split(types)

      assert length(real) == 6, "the copy says six kinds"

      for kind <- real do
        assert html =~ kind, "#{kind} exists and the page does not mention it"
      end
    end

    test "the direction of an edge is part of the claim", %{html: html} do
      assert html =~ "the direction is part of the claim"
      assert html =~ "not merely that the two are about fathers"
    end

    test "clusters are mentioned as what pairs become", %{html: html} do
      assert html =~ "cluster"
    end
  end

  test "the demo blocks do not reuse a class the page already styles" do
    source = File.read!("lib/marginalia_web/live/landing_live.ex")

    # `.demo` was already in use for the worked example further up the page.
    # Styling my blocks with the same class silently restyled that one.
    refute source =~ ~s(class="demo" data-demo),
           "a demo block is using the page's pre-existing .demo class"

    duplicated =
      Regex.scan(~r/^\s{6}(\.[a-z][a-z0-9-]*)\{/m, source)
      |> Enum.map(fn [_, sel] -> sel end)
      |> Enum.frequencies()
      |> Enum.filter(fn {_sel, n} -> n > 1 end)

    assert duplicated == [],
           "two top-level rules for the same class in one stylesheet: #{inspect(duplicated)}"
  end

  describe "the anchors" do
    # A link to a feature is something somebody pastes into a message and
    # then cannot re-send when it breaks. So the ids are named for the
    # feature rather than the headline above it — the headline is prose and
    # gets reworded, and an id derived from it would rot on the first pass
    # of copy editing without anything failing.
    test "every section is addressable and no id is used twice", %{html: html} do
      sections = Regex.scan(~r/<section class="sec head"([^>]*)>/, html)

      ids =
        Regex.scan(~r/<section class="sec head" id="([a-z-]+)"/, html)
        |> Enum.map(fn [_, id] -> id end)

      assert length(ids) == length(sections),
             "#{length(sections) - length(ids)} section(s) on the page cannot be linked to"

      assert ids == Enum.uniq(ids),
             "a repeated id sends two links to the same place: #{inspect(ids -- Enum.uniq(ids))}"
    end

    test "the features people will link at have the ids they were given", %{html: html} do
      for {id, what} <- [
            {"changes", "revisions, the split diff and git"},
            {"summaries", "per-section and document summaries"},
            {"links", "two drafts related"},
            {"stacks", "a folder read forwards"},
            {"graph", "what leads to what"},
            {"rewrites", "the one place it writes"}
          ] do
        assert html =~ ~s(id="#{id}"), "/##{id} is the link for #{what}"
      end
    end
  end

  describe "the example documents" do
    test "the feature sections point at something a stranger can open", %{html: html} do
      seeits = Regex.scan(~r/class="seeit"><a[^>]*href="([^"]+)"/, html) |> Enum.map(&List.last/1)

      assert length(seeits) >= 6, "a feature described and never shown is a claim"

      for path <- seeits do
        assert Phoenix.Router.route_info(MarginaliaWeb.Router, "GET", path, "example.com") !=
                 :error,
               "#{path} is offered as an example and is not a route"
      end
    end

    test "they are public routes, not ones behind a login", %{html: html} do
      seeits = Regex.scan(~r/class="seeit"><a[^>]*href="([^"]+)"/, html) |> Enum.map(&List.last/1)

      # /works, /stacks and /links mint a guest or need an account. These four
      # are the public faces. An example nobody can open is worse than none.
      public = ~w(/drafts /cases /reading /linked)

      for path <- seeits do
        assert Enum.any?(public, &String.starts_with?(path, &1)),
               "#{path} is not on a public page"
      end
    end

    test "each one is a different thing to look at", %{html: html} do
      seeits = Regex.scan(~r/class="seeit"><a[^>]*href="([^"]+)"/, html) |> Enum.map(&List.last/1)

      assert length(Enum.uniq(seeits)) >= 3,
             "six links to one document is one example wearing six hats"
    end
  end
end
