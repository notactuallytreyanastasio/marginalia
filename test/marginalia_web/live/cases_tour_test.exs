defmodule MarginaliaWeb.CasesTourTest do
  @moduledoc """
  The guided run through a term.

  What is worth pinning is not the copy, it is the two things that make
  it a tour rather than three unrelated overlays: every step points at
  something that is actually on its page, and each leg hands over to the
  next.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Cases, Links, Works}
  alias Marginalia.Analysis.Linker
  alias Marginalia.Walkthrough

  @quote "A sentence long enough"

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    Application.put_env(:marginalia, :owner_email, "owner@example.com")
    on_exit(fn -> Application.delete_env(:marginalia, :owner_email) end)

    owner = user_fixture(%{email: "owner@example.com"})

    mk = fn title, role ->
      body =
        "# #{title}\n\n#{@quote} to be a section. We hold that it is so.\n\n" <>
          String.duplicate("word ", 200)

      {:ok, w} = Works.create_work(owner.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      {:ok, w} = Cases.place(w, "Some v. Case", role)
      s = hd(Works.list_sections(w.id))

      {:ok, n} =
        Works.insert_node(%{
          work_id: w.id,
          section_id: s.id,
          node_type: "beat",
          title: "a beat in the #{role}",
          quote: @quote
        })

      {w, n}
    end

    {op, op_n} = mk.("Some v. Case — Opinion of the Court", "opinion")
    {di, di_n} = mk.("Some v. Case — Dissent (Jackson)", "dissent")

    {:ok, l} = Links.get_or_create(op.id, di.id)
    {:ok, l} = Links.set_status(l, "linked", %{summary: "They disagree."})

    Links.store_edges(
      l,
      [%{"from" => op_n.id, "to" => di_n.id, "type" => "tension", "why" => "They part."}],
      Linker.types()
    )

    %{conn: conn, owner: owner, op: op, di: di, link: l}
  end

  describe "the steps themselves" do
    test "every leg has steps, and every step says something" do
      for leg <- [:cases, :follow, :case_read] do
        steps = Walkthrough.Cases.steps(leg)

        assert length(steps) >= 5, "#{leg} is too short to be a tour"

        for s <- steps do
          assert s.title != ""
          assert String.length(s.body) > 40, "#{leg}/#{s.id} says nothing"
          assert Map.has_key?(s, :target)
        end
      end
    end

    test "a view with no leg gets none" do
      assert Walkthrough.Cases.steps(:graph) == []
      refute Walkthrough.Cases.for_view?(:graph)
    end

    test "each leg but the last hands over to the next" do
      assert %{act: %{kind: "hop", to: "first_pair"}} = List.last(Walkthrough.Cases.steps(:cases))
      assert %{act: %{kind: "hop", to: "case_read"}} = List.last(Walkthrough.Cases.steps(:follow))
      refute Map.has_key?(List.last(Walkthrough.Cases.steps(:case_read)), :act)
    end
  end

  describe "running it" do
    # The overlay always ships with the page and the browser decides
    # whether to run it, against a flag in localStorage. That is what
    # lets this page work with no account: "has this person seen the
    # tour" is a fact about a browser, and making it a fact about a user
    # is why there were 762 accounts.
    test "the page always carries the tour, and says to gate it locally", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases")

      assert html =~ ~s(id="walk")
      assert html =~ ~s(data-auto="cases")
      assert html =~ "One real disagreement, first"
      assert html =~ "Take the tour"
    end

    test "no account is created to remember it", %{conn: conn} do
      before = Marginalia.Repo.aggregate(Marginalia.Accounts.User, :count)

      {:ok, _view, _html} = live(conn, ~p"/cases")
      {:ok, _view, _html} = live(build_conn(), ~p"/cases")

      assert Marginalia.Repo.aggregate(Marginalia.Accounts.User, :count) == before,
             "a read-only public page minted an account"
    end

    test "a signed-out visitor is not told they are a guest", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases")

      assert html =~ "Log in"
      refute html =~ ">guest<"
    end

    test "the button asks the overlay directly, with no round trip", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases")

      assert html =~ "mg:walk"
      # there is no server event left to start or end it
      refute html =~ ~s(phx-click="start_walk")
      refute html =~ ~s(phx-click="end_walk")
    end

    test "arriving with walk=1 starts the pairwise leg, instead of the one-time card",
         %{conn: conn, link: l, op: op} do
      {:ok, _view, html} = live(conn, ~p"/links/#{l.id}/read?lead=#{op.slug}&walk=1")

      assert html =~ "Left is read. Right is the reference"
      # the tour card would be a second overlay over the first
      refute html =~ "Two documents, read as one"
    end

    test "the pairwise leg hands over to the whole-case reading", %{conn: conn, link: l, op: op} do
      {:ok, view, _html} = live(conn, ~p"/links/#{l.id}/read?lead=#{op.slug}&walk=1")

      assert {:error, {:live_redirect, %{to: to}}} =
               render_click(view, "walk_hop", %{"to" => "case_read"})

      assert to == "/cases/some-v-case/read/#{op.slug}?walk=1"
    end

    test "the last leg runs on the whole-case reading and ends there", %{conn: conn, op: op} do
      {:ok, view, html} = live(conn, ~p"/cases/some-v-case/read/#{op.slug}?walk=1")

      assert html =~ "The whole case in one margin"
      refute render_click(view, "end_walk", %{}) =~ ~s(id="walk")
    end

    # the whole point of the auto-run: a visitor who has never been here
    test "a brand new visitor gets it without doing anything", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases")
      assert html =~ "One real disagreement, first"

      # and a different new visitor gets it too — it is per person, not
      # per site
      {:ok, _view, html} = live(build_conn(), ~p"/cases")
      assert html =~ "One real disagreement, first"
    end

    test "a plain visit runs no tour", %{conn: conn, op: op} do
      {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read/#{op.slug}")
      refute html =~ ~s(id="walk")
    end
  end
end
