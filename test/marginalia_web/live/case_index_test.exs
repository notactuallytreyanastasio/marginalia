defmodule MarginaliaWeb.CaseIndexTest do
  @moduledoc """
  The front of the micro-site.

  What is pinned here is what a reader is owed: the record facts, the read
  pass's own account of the opinion, every document named and sourced, and
  one real connection before any explanation of what a connection is.
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

    mk = fn title, role, extra ->
      body =
        "# #{title}\n\n#{@quote} to be a section. We hold that the removal power is " <>
          "the President's alone.\n\n" <> String.duplicate("word ", 200)

      {:ok, w} = Works.create_work(owner.id, %{"title" => title, "body" => body})
      {:ok, w} = Works.set_status(w, "read")
      {:ok, w} = Cases.place(w, "Trump v. Slaughter", role)

      {:ok, w} =
        w |> Ecto.Changeset.change(extra) |> Marginalia.Repo.update()

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

    {op, op_n} =
      mk.("Trump v. Slaughter — Opinion of the Court", "opinion", %{
        first_impression: "A majority opinion that announces its destination in section one.",
        source_url: "https://www.supremecourt.gov/opinions/25pdf/25-332_new_geil.pdf"
      })

    {di, di_n} = mk.("Trump v. Slaughter — Dissent (Sotomayor)", "dissent", %{})
    {ar, ar_n} = mk.("Trump v. Slaughter — Argument: Gen. D. John Sauer", "argument", %{})

    {:ok, l} = Links.get_or_create(op.id, di.id)
    {:ok, l} = Links.set_status(l, "linked", %{summary: "They disagree about removal."})

    Links.store_edges(
      l,
      [
        %{
          "from" => op_n.id,
          "to" => di_n.id,
          "type" => "tension",
          "why" =>
            "The Court grounds removal in the Framers' single executive; the dissent finds no founding-era support for it."
        }
      ],
      Linker.types()
    )

    {:ok, l2} = Links.get_or_create(op.id, ar.id)
    {:ok, l2} = Links.set_status(l2, "linked", %{summary: "Adopted from the lectern."})

    Links.store_edges(
      l2,
      [%{"from" => op_n.id, "to" => ar_n.id, "type" => "echoes", "why" => "Sauer's framing."}],
      Linker.types()
    )

    %{conn: conn, owner: owner, op: op, ar: ar, di: di}
  end

  test "the record facts a reader checks first are on the card", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases")

    assert html =~ "No. 25-332"
    assert html =~ "Argued December 8, 2025"
    assert html =~ "Decided June 29, 2026"
    assert html =~ "question presented"
    assert html =~ "Humphrey&#39;s Executor"
  end

  # Lawyers do not read the syllabus, and the syllabus says why: it is no
  # part of the opinion. It was the source of "what the Court held".
  describe "the holding" do
    test "the record carries no headnote any more" do
      rec = Marginalia.Cases.Record.for("Wolford v. Lopez")

      assert rec.docket == "No. 24-1046"
      refute Map.has_key?(rec, :held)
    end

    test "it is the Court's own sentence, lifted from the opinion" do
      body = """
      The Government says otherwise. We are not persuaded. We hold that the
      statute does not reach conduct outside the United States. It is so ordered.
      """

      held = Cases.holding(%Marginalia.Works.Work{body: body})

      assert held == "We hold that the statute does not reach conduct outside the United States."
      assert String.contains?(String.replace(body, ~r/\s+/, " "), held)
    end

    test "'we hold that' is preferred over a bare 'accordingly'" do
      body = """
      Accordingly, the court of appeals had jurisdiction to hear the appeal.
      We conclude that the claim is preempted by the federal scheme.
      """

      assert Cases.holding(%Marginalia.Works.Work{body: body}) =~ "the claim is preempted"
    end

    test "a holding buried mid-sentence is quoted from where the sentence began" do
      body = """
      The parties dispute the scope of the clause. Because we conclude that
      Durnell's claim is expressly preempted, we need not reach the second question.
      """

      held = Cases.holding(%Marginalia.Works.Work{body: body})

      assert String.starts_with?(held, "Because we conclude that")
      refute String.starts_with?(held, "we conclude")
    end

    test "a division heading before the sentence is not part of the quotation" do
      for lead <- ["III", "II A", "* * *", "1."] do
        body =
          "Some earlier reasoning ends here.\n\n#{lead}\n\nWe hold that the statute is valid."

        assert Cases.holding(%Marginalia.Works.Work{body: body}) ==
                 "We hold that the statute is valid.",
               "leading #{inspect(lead)} survived into the quote"
      end
    end

    test "an opinion that never says it in one sentence gets nothing" do
      body =
        "The judgment below rested on a mistaken premise about the text. " <>
          String.duplicate("More reasoning follows. ", 40)

      assert Cases.holding(%Marginalia.Works.Work{body: body}) == nil
    end

    test "the page quotes it, and says the syllabus is not a source", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cases")

      assert html =~ "the Court, holding"
      assert html =~ "constitutes no part of the"
      assert html =~ "The Reporter&#39;s syllabus is excluded"
      refute html =~ "what the Court held"
    end
  end

  test "the read pass's own account of the opinion is shown, and expands", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/cases")

    assert html =~ "on reading the opinion"
    assert html =~ "announces its destination in section one"
    # clamped until asked
    assert html =~ "fi clamped"

    html = view |> element("button[phx-value-slug='trump-v-slaughter']") |> render_click()
    refute html =~ "fi clamped"
  end

  test "every document is named and carries its source", %{conn: conn, ar: ar} do
    {:ok, _view, html} = live(conn, ~p"/cases")

    # the advocate, not "Oral argument" three times over
    assert html =~ "Argument: Gen. D. John Sauer"
    assert html =~ "Opinion of the Court"
    assert html =~ "supremecourt.gov/opinions/25pdf/25-332_new_geil.pdf"
    # and each one opens the case read on that document
    assert html =~ "/cases/trump-v-slaughter/read/#{ar.slug}"
  end

  test "the card offers pairings, which are how a case is actually read", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases")

    # one document against another, landing in the reading where the
    # second follows the first
    assert html =~ ~s(class="cs-ways")
    assert html =~ "against"
    assert html =~ ~r{href="/links/\d+\?lead=}
    # the opinion leads the pair, not the dissent
    assert html =~ ~r{class="a opinion"[^>]*>\s*Opinion of the Court}
    # the whole-case and connections views are the quiet alternatives
    assert html =~ "or all 3 at once →"
    assert html =~ "connections →"
  end

  test "the hook is a real disagreement, before any explanation", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases")

    assert html =~ ~s(class="cs-hook")
    assert html =~ "no founding-era support"
    # the method is folded, and below
    assert html =~ ~s(<details class="cs-how")
  end

  test "one case is one case, not 1 cases", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases")
    assert html =~ "</b> case</span>"
    refute html =~ "</b> cases</span>"
    assert html =~ "1 case from the Supreme Court"
  end

  # "Four cases from the Supreme Court's last quarter" was true of four
  # cases and then quietly false of sixteen.
  test "the lede counts the cases it is actually showing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases")

    refute html =~ "Four cases"
    # the year comes off the decision dates of the cases on the page
    assert html =~ "2025 term"
  end

  test "it opens with one real connection, not a description of one", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases")

    assert html =~ "for instance"
    assert html =~ "no founding-era support"
    assert html =~ "read it →"
  end

  test "the provenance note says what this is and is not", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/cases")

    assert html =~ "Supreme Court of the United States"
    assert html =~ "verified against the source"
    assert html =~ "a substitute for reading the opinion"
  end

  test "a visitor who is not the owner sees all of it", %{} do
    {:ok, _view, html} = live(build_conn(), ~p"/cases")

    assert html =~ "The term, read closely"
    assert html =~ "No. 25-332"
  end

  test "a summary calls the documents by name, not Manuscript A and B",
       %{conn: conn, op: op, di: di} do
    # by name, not the head of the list: `op` has two links and this asserts
    # on which documents A and B resolve to
    l = Enum.find(Links.for_work(op.id), &(&1.a_work_id == di.id or &1.b_work_id == di.id))

    {:ok, l} =
      Links.set_status(l, "linked", %{
        summary: "Manuscript A grounds removal in the Framers; Manuscript B does not."
      })

    assert Links.summary(l) =~ "Opinion of the Court grounds removal"
    assert Links.summary(l) =~ "Dissent (Sotomayor) does not"
    refute Links.summary(l) =~ "Manuscript"

    {:ok, _view, html} = live(conn, ~p"/cases")
    refute html =~ "Manuscript A"
  end

  # "A says Congress entrenched the common law; B Jackson charges that..."
  # is a sentence a reader has to decode before they can read it.
  test "a bare A and B at the start of a sentence are named too", %{op: op, di: di} do
    # the dissent link by name, not the head of the list: `op` has two links
    # and this asserts on which documents A and B resolve to
    l = Enum.find(Links.for_work(op.id), &(&1.a_work_id == di.id or &1.b_work_id == di.id))

    {:ok, l} =
      Links.set_status(l, "linked", %{
        summary: "A says Congress entrenched the common law; B charges that it did not."
      })

    assert Links.summary(l) =~ "Opinion of the Court says Congress entrenched"
    assert Links.summary(l) =~ "Dissent (Sotomayor) charges that it did not"
  end

  test "a lettered part of a statute is not a document", %{op: op} do
    [l | _] = Links.for_work(op.id)

    text = "The majority relies on Part A of the statute and Exhibit B at trial."
    {:ok, l} = Links.set_status(l, "linked", %{summary: text})

    assert Links.summary(l) == text
  end

  test "a summary that never mentioned a manuscript is left alone", %{op: op} do
    [l | _] = Links.for_work(op.id)
    {:ok, l} = Links.set_status(l, "linked", %{summary: "They disagree about removal."})
    assert Links.summary(l) == "They disagree about removal."
  end

  test "a collection with no public record still renders", %{conn: conn, owner: owner} do
    body = "# Loose\n\n#{@quote} to be a section.\n\n" <> String.duplicate("word ", 200)
    {:ok, w} = Works.create_work(owner.id, %{"title" => "Loose ends", "body" => body})
    {:ok, w} = Works.set_status(w, "read")
    {:ok, _} = Cases.place(w, "Not a court case", "opinion")

    {:ok, _view, html} = live(conn, ~p"/cases")
    assert html =~ "Not a court case"
  end
end
