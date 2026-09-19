defmodule MarginaliaWeb.CaseReadTest do
  @moduledoc """
  Reading one document of a case with every other document in the margin.

  The thing worth pinning is the merge: two *separate* links, both touching
  the opinion, have to arrive in one margin on the same paragraph. Reading
  the pairs one at a time is what this page exists not to do.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Cases, Links, Works}
  alias Marginalia.Analysis.Linker

  @quote "A sentence long enough"

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})
    # Restored, not deleted. `delete_env` drops the configured value instead
    # of putting it back, so anything reading `:owner_email` afterwards sees
    # nil rather than what config set — invisible in one run, because ExUnit
    # runs the async readers before these sync modules, and immediately fatal
    # under --repeat-until-failure, which is the tool for finding flakes.
    previous_owner = Application.get_env(:marginalia, :owner_email)
    Application.put_env(:marginalia, :owner_email, "owner@example.com")

    on_exit(fn ->
      case previous_owner do
        nil -> Application.delete_env(:marginalia, :owner_email)
        email -> Application.put_env(:marginalia, :owner_email, email)
      end
    end)

    owner = user_fixture(%{email: "owner@example.com"})

    mk = fn title, role ->
      body = "# #{title}\n\n#{@quote} to be a section.\n\n" <> String.duplicate("word ", 200)
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
          body: "what the #{role} is doing here",
          quote: @quote
        })

      {w, n}
    end

    {op, op_n} = mk.("Some v. Case — Opinion", "opinion")
    {di, di_n} = mk.("Some v. Case — Dissent", "dissent")
    {ar, ar_n} = mk.("Some v. Case — Argument: Counsel", "argument")

    join = fn a, a_n, b, b_n, type, why ->
      {:ok, l} = Links.get_or_create(a.id, b.id)
      {:ok, l} = Links.set_status(l, "linked", %{summary: "#{type} between them."})

      Links.store_edges(
        l,
        [%{"from" => a_n.id, "to" => b_n.id, "type" => type, "why" => why}],
        Linker.types()
      )

      l
    end

    join.(op, op_n, di, di_n, "tension", "They part on consent.")
    join.(op, op_n, ar, ar_n, "answers", "The lectern already settled this.")
    # a link that does not touch the opinion at all, to prove the margin is
    # the lead's links and not the whole collection's
    join.(di, di_n, ar, ar_n, "echoes", "Dissent and counsel agree here.")

    %{conn: conn, owner: owner, op: op, di: di, ar: ar}
  end

  test "the opinion is read with both other documents in one margin", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read")

    assert html =~ "Reading…"
    assert html =~ "Some v. Case — Opinion"

    # both reasons, from two separate links, on the page at once
    assert html =~ "They part on consent."
    assert html =~ "The lectern already settled this."

    # and not the link between the other two, which the opinion is not in
    refute html =~ "Dissent and counsel agree here."
  end

  test "each note says which document it came from, without the case name", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read")

    assert html =~ ~s(<span class="src">Dissent</span>)
    assert html =~ ~s(<span class="src">Argument: Counsel</span>)
  end

  test "the far passage travels with the note", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read")
    assert html =~ "<blockquote>#{@quote}</blockquote>"
  end

  test "a source chip narrows the margin to one document", %{conn: conn, di: di} do
    {:ok, view, _html} = live(conn, ~p"/cases/some-v-case/read")

    html = view |> element("button[phx-value-w='#{di.id}']") |> render_click()

    assert html =~ "They part on consent."
    refute html =~ "The lectern already settled this."

    html = view |> element("button.cr-clear") |> render_click()
    assert html =~ "The lectern already settled this."
  end

  test "a relation chip narrows the margin to one kind", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/cases/some-v-case/read")

    html = view |> element("button[phx-value-k='answers']") |> render_click()

    assert html =~ "The lectern already settled this."
    refute html =~ "They part on consent."
  end

  test "any document in the case can be the one you read", %{conn: conn, ar: ar} do
    {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read/#{ar.slug}")

    assert html =~ "Some v. Case — Argument: Counsel"
    # from the argument's side it sees both of its own links
    assert html =~ "The lectern already settled this."
    assert html =~ "Dissent and counsel agree here."
    refute html =~ "They part on consent."
  end

  test "the case page offers the whole-case read before the pairs", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases/some-v-case")

    assert html =~ ~p"/cases/some-v-case/read"
    assert html =~ "with 2 other documents in the margin"
  end

  describe "a case related to another case" do
    setup %{owner: owner, op: op} do
      body = "# other\n\n#{@quote} to be a section.\n\n" <> String.duplicate("word ", 200)

      {:ok, far} =
        Works.create_work(owner.id, %{"title" => "Other v. Matter — Opinion", "body" => body})

      {:ok, far} = Works.set_status(far, "read")
      {:ok, far} = Cases.place(far, "Other v. Matter", "opinion")
      s = hd(Works.list_sections(far.id))

      {:ok, far_n} =
        Works.insert_node(%{
          work_id: far.id,
          section_id: s.id,
          node_type: "beat",
          title: "a beat in the other case",
          quote: @quote
        })

      [op_n] = Works.list_nodes(op.id) |> Enum.filter(&(&1.node_type == "beat")) |> Enum.take(1)

      {:ok, l} = Links.get_or_create(op.id, far.id)
      {:ok, l} = Links.set_status(l, "linked", %{summary: "Two cases, one question."})

      Links.store_edges(
        l,
        [
          %{
            "from" => op_n.id,
            "to" => far_n.id,
            "type" => "echoes",
            "why" => "The same Court on the same clause, three weeks apart."
          }
        ],
        Linker.types()
      )

      %{far: far}
    end

    test "its notes appear in the margin, saying where they are from", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read")

      assert html =~ "The same Court on the same clause"
      assert html =~ ~s(<p class="from">Other v. Matter</p>)
      # and it is visibly not from this case
      assert html =~ "cr-note s0 far"
    end

    test "the chip for another case names the case, not the document", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read")

      assert html =~ ~r{cr-chip[^"]*far[^>]*>\s*<span class="t">Other v. Matter}
    end

    test "a connection from another case is marked as such in the context", %{} do
      c = Cases.published() |> Enum.find(&(&1.name == "Some v. Case"))
      reading = Cases.reading(c, Cases.default_lead(c).id)

      assert Marginalia.Cases.Chat.card(reading) =~ "a different case"
    end

    test "filtering to this case's own documents leaves it out", %{conn: conn, di: di} do
      {:ok, view, _html} = live(conn, ~p"/cases/some-v-case/read")

      html = view |> element("button[phx-value-w='#{di.id}']") |> render_click()
      refute html =~ "The same Court on the same clause"
    end
  end

  # On a phone the margin cannot be a column of cards — two columns of
  # prose at 390px is twenty-four characters a line. It becomes a rail of
  # marks beside the text, and a tap brings the notes up in a sheet.
  describe "the phone's margin" do
    test "every linked paragraph carries a rail with its relations on it", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases/some-v-case/read")

      assert html =~ ~s(class="cr-rail")
      assert html =~ ~s(<span class="tick k-tension">)
      assert html =~ ~s(<span class="tick k-answers">)
      assert html =~ "connections on this paragraph"
    end

    test "tapping the rail opens that paragraph's notes, and closing dismisses them",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cases/some-v-case/read")

      html = view |> element("button.cr-rail") |> render_click()

      assert html =~ ~s(class="cr-sheet")
      assert html =~ "on this paragraph"
      assert html =~ "They part on consent."

      refute render_click(view, "unpeek", %{}) =~ ~s(class="cr-sheet")
    end

    test "a filter change dismisses a sheet that may no longer apply", %{conn: conn, di: di} do
      {:ok, view, _html} = live(conn, ~p"/cases/some-v-case/read")

      view |> element("button[phx-value-w='#{di.id}']") |> render_click()
      assert render_click(view, "peek", %{"ref" => first_ref(view)}) =~ ~s(class="cr-sheet")

      # clearing the filter changes what the rail would show, so the sheet
      # standing open over it would be showing the wrong paragraph's notes
      refute view |> element("button.cr-clear") |> render_click() =~ ~s(class="cr-sheet")
    end
  end

  defp first_ref(view) do
    [_, ref] = Regex.run(~r/phx-value-ref="([^"]+)"/, render(view))
    ref
  end

  describe "the chat about the case" do
    test "the bubble is there and opens a panel about the case", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/cases/some-v-case/read")

      assert html =~ "lc-bubble"
      refute html =~ "lc-panel"

      html = view |> element("button.lc-bubble") |> render_click()

      assert html =~ "lc-panel"
      # it holds a case, not a pair, and says so
      assert html =~ "About this case"
      refute html =~ "About this pair"
      assert html =~ ~s(phx-submit="chat_send")
    end

    test "a note carries its connection into the chat", %{conn: conn, op: op} do
      {:ok, view, html} = live(conn, ~p"/cases/some-v-case/read")

      assert html =~ ~s(phx-click="cite_edge")

      # one such button per note, so name the connection
      [edge | _] = Links.edges(hd(Links.for_work(op.id)))
      html = view |> element("button[phx-value-edge='#{edge.id}']") |> render_click()

      # citing opens the panel with that connection in it
      assert html =~ "lc-panel"
      assert html =~ "lc-cited" or html =~ "tension"
    end

    test "asking keeps the question and does not hang", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/cases/some-v-case/read")
      view |> element("button.lc-bubble") |> render_click()

      view
      |> form("form[phx-submit=chat_send]", %{"message" => "Who conceded what?"})
      |> render_submit()

      html = render_async(view, 5_000)

      assert html =~ "Who conceded what?"
      refute html =~ "lc-thinking"
    end

    test "the context names documents rather than lettering them", %{} do
      c = Cases.published() |> hd()
      reading = Cases.reading(c, Cases.default_lead(c).id)

      card = Marginalia.Cases.Chat.card(reading)

      assert card =~ "Dissent"
      assert card =~ "Argument: Counsel"
      # the pairwise chat labels its two documents A and B and the answers
      # came back full of "A:[4030]"; with four documents that is useless
      refute card =~ ~r/\bA:\[\d+\]/
      refute card =~ ~r/^A: /m
    end
  end

  describe "a hub paragraph" do
    # Taking the first five in source order would show five from the dissent
    # and none from either advocate on exactly the paragraphs where all three
    # have something to say.
    test "the visible notes are spread across the documents, not taken in order" do
      notes =
        List.duplicate(%{from_work: 1}, 6) ++
          List.duplicate(%{from_work: 2}, 4) ++ List.duplicate(%{from_work: 3}, 2)

      {shown, rest} = MarginaliaWeb.CaseLive.Read.cap(notes)

      assert length(shown) == 5
      assert length(rest) == 7
      assert shown |> Enum.map(& &1.from_work) |> Enum.uniq() |> length() == 3
    end

    test "a short stack is not folded at all" do
      notes = List.duplicate(%{from_work: 1}, 5)
      assert {^notes, []} = MarginaliaWeb.CaseLive.Read.cap(notes)
    end

    test "nothing is lost to the cap" do
      notes = for i <- 1..18, do: %{from_work: rem(i, 3), n: i}
      {shown, rest} = MarginaliaWeb.CaseLive.Read.cap(notes)

      assert Enum.sort_by(shown ++ rest, & &1.n) == notes
    end
  end

  test "an unknown case sends you back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/cases"}}} = live(conn, ~p"/cases/nope/read")
  end
end
