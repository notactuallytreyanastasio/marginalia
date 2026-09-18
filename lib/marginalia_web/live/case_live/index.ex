defmodule MarginaliaWeb.CaseLive.Index do
  @moduledoc """
  The front of the micro-site: every case, and how to read one.

  A contents page made of counts tells a reader nothing about whether to
  open anything. What does tell them is the disagreement — so each case
  leads with the read pass's own account of the opinion, the record facts
  a reader checks first, and the sharpest places the documents collide, in
  the words of the passages themselves.

  The method sits above the list rather than on a separate page, because
  the method is the unusual part: these documents are not summarised, they
  are read separately and then related, and a reader who does not know
  that will not understand what they are looking at.

  Every document links back to the PDF on supremecourt.gov it was made
  from. That is not decoration — the whole claim of the page is that
  nothing here is invented, and the only way to make that checkable is to
  put the source one click away.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Cases
  alias Marginalia.Cases.Record
  alias Marginalia.Walkthrough

  @impl true
  def mount(_params, _session, socket) do
    # the front of the site, not the viewer's own drafts — see Cases.published/0
    cases =
      Cases.published()
      |> Enum.map(fn c ->
        c
        |> Map.put(:preview, Cases.preview(c))
        |> Map.put(:record, Record.for(c.name))
      end)

    {:ok,
     socket
     |> assign(
       # Its own card: this page is not the product pitch, it is a thing
       # somebody would link to on its own terms, and "Cases · Marginalia"
       # unfurling the product's front-door image says nothing about it.
       page_title: "The term, read closely",
       page_description: description(cases),
       page_image: ~p"/images/og-cases.png",
       page_image_alt:
         "A line of a Supreme Court opinion, highlighted, with a line drawn across to " <>
           "the dissent arguing with that exact sentence in the margin.",
       page_url: url(~p"/cases"),
       cases: cases,
       open: nil,
       words: cases |> Enum.map(& &1.words) |> Enum.sum(),
       docs: cases |> Enum.map(&length(&1.works)) |> Enum.sum(),
       edges: cases |> Enum.map(& &1.edges) |> Enum.sum(),
       span: span(cases),
       opener: opener(cases)
     )}
  end

  # Expanding an impression is a display detail, not a destination: no patch,
  # no history entry, one open at a time.
  @impl true
  # The tour crosses pages, because what it is explaining is not a page.
  # The first leg ends by opening the strongest pairing it just described.
  def handle_event("walk_hop", %{"to" => "first_pair"}, socket) do
    case first_pair(socket.assigns.cases) do
      nil -> {:noreply, assign(socket, walk: [])}
      path -> {:noreply, push_navigate(socket, to: path)}
    end
  end

  def handle_event("impression", %{"slug" => slug}, socket),
    do: {:noreply, assign(socket, open: if(socket.assigns.open == slug, do: nil, else: slug))}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%!-- Always rendered; the hook decides whether to run it, against
            a flag in this browser. That is what lets this page work with
            no account at all. --%>
      <MarginaliaWeb.Walk.overlay
        steps={Walkthrough.Cases.steps(:cases)}
        auto="cases"
        note="Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would."
      />

      <div class="cs">
        <header class="cs-top">
          <h1>The term, read closely</h1>
          <p class="lede">
            {length(@cases)} {plural(length(@cases), "case")} from the Supreme Court{@span}. Each arrives as a pile of
            separate documents — the opinion of the Court, everything written alongside or
            against it, and every advocate's turn at the lectern — and each one is read on
            its own terms before any of them are compared.
          </p>
          <p class="how1">
            Each document read on its own, then related to the others — so you can read the
            opinion with the dissent following along beside it, snapping to whatever it is
            answering.
          </p>
          <button class="cs-tour" phx-click={Phoenix.LiveView.JS.dispatch("mg:walk", to: "#walk")}>
            Take the tour <span aria-hidden="true">→</span>
          </button>

          <p class="tally">
            <span><b>{length(@cases)}</b> {plural(length(@cases), "case")}</span>
            <span><b>{@docs}</b> {plural(@docs, "document")}</span>
            <span><b>{fmt(@words)}</b> words</span>
            <span><b>{@edges}</b> connections drawn between them</span>
          </p>
        </header>

        <%!-- One real connection, before any explanation of what a
              connection is. The page is making an unusual claim and the
              fastest way to make it concrete is to show the thing. --%>
        <section :if={@opener} class="cs-opener">
          <span class="mg-label">for instance</span>
          <p class="q">{@opener.edge.rationale}</p>
          <p class="src">
            one of <b>{@opener.count}</b> places the documents in
            <em>{@opener.case.name}</em>
            pull against each other —
            <.link navigate={~p"/cases/#{@opener.case.slug}/read"}>read it →</.link>
          </p>
        </section>

        <p :if={@cases == []} class="none">Nothing here yet.</p>

        <article :for={c <- @cases} class="cs-case">
          <div class="cs-case-head">
            <h2><.link navigate={~p"/cases/#{c.slug}/read"}>{c.name}</.link></h2>
            <span :if={c.record} class="rec">
              <span class="dk">{c.record.docket}</span>
              <span>Argued {c.record.argued}</span>
              <span>Decided {c.record.decided}</span>
            </span>
          </div>

          <%!-- What the Court was asked, where that is written; otherwise
                the Reporter's own statement of what it decided. Both are
                the line a reader checks before opening anything. --%>
          <p :if={c.record && c.record[:question]} class="qp">
            <span class="mg-label">question presented</span>
            {c.record.question}
          </p>
          <%!-- The Court's own sentence, quoted. It was the Reporter's
                headnote, which is the obvious source and the wrong one:
                the syllabus is not part of the opinion, carries no
                authority, and a lawyer does not read it. --%>
          <blockquote :if={c.holding} class="cs-held">
            <span class="mg-label">the Court, holding</span>
            {c.holding}
          </blockquote>

          <%!-- The read pass's own account of the opinion, written before any
                of the comparing. It is the most useful paragraph on the page
                and it was being computed and thrown away. --%>
          <div :if={c.preview.impression} class="cs-fi">
            <span class="mg-label">on reading the opinion</span>
            <p class={["fi", @open != c.slug && "clamped"]}>{c.preview.impression}</p>
            <button phx-click="impression" phx-value-slug={c.slug} class="more">
              {if @open == c.slug, do: "less", else: "more"}
            </button>
          </div>

          <%!-- The hook: the sharpest thing the pass found between these
                documents, in its own words. A reader decides whether to
                open a case on a sentence, not on a count. --%>
          <p :if={hook(c)} class="cs-hook">{hook(c).rationale}</p>

          <%!-- And then the actual ways in. A case is not read as a case,
                it is read as one document against another, scrolling —
                so the card offers the pairings themselves, best first,
                each landing in the reading where the second follows the
                first. --%>
          <ul class="cs-ways">
            <li :for={w <- Enum.take(Cases.ways(c), 3)}>
              <.link navigate={~p"/links/#{w.link.id}?lead=#{w.lead.slug}"}>
                <span class={["a", w.lead.collection_role]}>{short(w.lead.title)}</span>
                <span class="x" aria-hidden="true">against</span>
                <span class={["b", w.other.collection_role]}>{short(w.other.title)}</span>
                <span class="n">{w.edges}</span>
                <span class="arrow" aria-hidden="true">→</span>
              </.link>
            </li>
          </ul>

          <details :if={c.preview.impression} class="cs-fi">
            <summary>
              <span class="mg-label">on reading the opinion</span>
              <span class="peek">{c.preview.impression}</span>
            </summary>
            <p>{c.preview.impression}</p>
          </details>

          <%!-- The term arguing with itself: the only thing on this page
                that could not have come from reading one case carefully. --%>
          <div :if={(kin = Cases.kin(c)) != []} class="cs-kin">
            <span class="mg-label">elsewhere in the term</span>
            <.link
              :for={k <- Enum.take(kin, 3)}
              navigate={~p"/links/#{k.link_id}?lead=#{k.lead.slug}"}
              class="k"
            >
              {k.case} <span class="n">{k.edges}</span>
            </.link>
          </div>

          <%!-- The inventory, and where each piece came from. Quiet, but
                not optional: the page's whole claim is that none of this
                is invented, and the only way to make that checkable is to
                keep the source one click away. --%>
          <div class="cs-parts">
            <ul>
              <li :for={w <- c.works} class={w.collection_role}>
                <.link navigate={~p"/cases/#{c.slug}/read/#{w.slug}"} class="t">{label(w)}</.link>
                <span class="n">{fmt(w.word_count)}</span>
                <a
                  :if={w.source_url}
                  href={w.source_url}
                  rel="noopener"
                  class="pdf"
                  title="The PDF this was made from"
                >pdf</a>
              </li>
            </ul>
          </div>

          <div class="cs-case-foot">
            <.link navigate={~p"/cases/#{c.slug}/read"} class="go">
              or all {length(c.works)} at once →
            </.link>
            <.link navigate={~p"/cases/#{c.slug}"} class="go">
              all {c.edges} connections →
            </.link>
          </div>
        </article>

        <%!-- The method used to sit above the list, on the theory that
              nothing makes sense without it. It does not earn that place:
              five paragraphs between a reader and the first real
              disagreement is five paragraphs they leave on. Folded, and
              after the cases, where someone who has seen the thing work
              will go looking for how. --%>
        <details class="cs-how">
          <summary><span class="mg-label">how this works</span></summary>
          <ol>
            <li>
              <b>The Reporter's syllabus is not one of the documents.</b>
              Every slip opinion opens with a headnote summarising itself, and every slip
              opinion says on the same page that the headnote "constitutes no part of the
              opinion of the Court". It is not read here and nothing on this site is drawn
              from it. Where a case states its holding below, that is the Court's own
              sentence, quoted out of the opinion; three of these sixteen never put their
              holding in one sentence, and those cases show none.
            </li>
            <li>
              <b>Every document is read separately.</b>
              Not summarised — read. Each paragraph gets the beats it contains, anchored to
              a sentence copied out of the document character for character, and above those
              sit the spine of the argument, the threads that run through it, and the
              questions it leaves open.
            </li>
            <li>
              <b>An argument is split at the lectern.</b>
              A transcript is not one document. Each advocate's turn is its own case to make,
              with its own questions from the bench, so each is read as its own draft. The
              difference is not cosmetic: kept whole, one argument came back with 44
              connections to its opinion, and split it came back with 215.
            </li>
            <li>
              <b>Then the documents are related to each other.</b>
              Not the texts — the maps. A pass reads both graphs and draws the edges between
              them: what one develops, what it answers, and where the two genuinely pull
              apart. An edge that does not land on a real anchored passage in both documents
              is thrown away before it is stored.
            </li>
            <li>
              <b>Then you read the case with the case in the margin.</b>
              The opinion down the left, and every other document beside it at once — the
              dissent and both advocates on the same paragraph, each saying which one it is.
              Or take them two at a time, one following the other as you scroll, with a line
              drawn between the passages and the reason in the middle.
            </li>
            <li>
              <b>And you can argue with it.</b>
              Every passage can be talked about, on its own or against its counterpart in
              another document. Click the line between two passages and both go into the
              question.
            </li>
          </ol>
        </details>

        <%!-- What a reader is entitled to know about where this came from
              and what it is worth. Last, because it is the answer to a
              question you only have once you have seen the rest. --%>
        <footer :if={@cases != []} class="cs-prov">
          <span class="mg-label">about these</span>
          <p>
            The documents are slip opinions and argument transcripts published by the
            Supreme Court of the United States; every one links to the PDF it was made
            from. The Reporter's syllabus is excluded — it is no part of the opinion and
            says so itself — as are the headnotes of any other reporter. The reading and the connections are machine-made, and every passage
            quoted back to you is verified against the source before it is stored — a
            quote that cannot be found in the document, character for character, is
            discarded rather than shown. Nothing here is a summary, a headnote, or legal
            advice, and none of it is a substitute for reading the opinion.
          </p>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  # The one connection the page opens with: a genuine disagreement, taken
  # from whichever case has the most of them, so the example is drawn from
  # the case the reader is most likely to find something in rather than
  # picked to flatter.
  defp opener([]), do: nil

  defp opener(cases) do
    cases
    |> Enum.map(fn c ->
      tensions =
        c.links
        |> Enum.flat_map(&Marginalia.Links.edges/1)
        |> Enum.filter(&(&1.edge_type == "tension"))

      %{case: c, count: length(tensions), edge: pick(tensions)}
    end)
    |> Enum.filter(& &1.edge)
    |> Enum.max_by(& &1.count, fn -> nil end)
  end

  # Long enough to be a thought, short enough to read standing up.
  defp pick([]), do: nil

  defp pick(edges) do
    Enum.min_by(edges, &abs(String.length(&1.rationale || "") - 170))
  end

  # The description is the corpus, not a claim about it: whoever pastes
  # this link gets the size of the thing and what it does with it.
  defp description([]), do: "Supreme Court cases, read document by document and related to each other."

  defp description(cases) do
    docs = cases |> Enum.map(&length(&1.works)) |> Enum.sum()

    "#{length(cases)} Supreme Court cases, #{docs} documents — every opinion, concurrence, " <>
      "dissent and advocate's argument read on its own, then read against each other, " <>
      "with every connection anchored to a sentence in both."
  end

  # "'s 2025 term" — taken from the decision dates on the cases actually
  # here, so the sentence cannot drift from the corpus the way "Four cases
  # from the last quarter" did the moment there were sixteen of them.
  defp span(cases) do
    years =
      cases
      |> Enum.map(& &1.record)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1[:decided])
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&year/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    case years do
      [] -> ""
      [y] -> "'s #{y - 1} term"
      list -> "'s #{List.first(list) - 1}–#{List.last(list) - 1} terms"
    end
  end

  defp year(date) do
    case Regex.run(~r/(\d{4})\s*$/, date) do
      [_, y] -> String.to_integer(y)
      _ -> nil
    end
  end

  # the pairing the first card leads with, which is the one the tour has
  # just been pointing at
  defp first_pair([]), do: nil

  defp first_pair([c | _rest]) do
    case Cases.ways(c) do
      [w | _] -> ~p"/links/#{w.link.id}?lead=#{w.lead.slug}&walk=1"
      [] -> nil
    end
  end

  # The sharpest disagreement in the case, which is what a reader will
  # open it for. Falls back to whatever the pass found if nothing in the
  # case is a disagreement at all — a unanimous case is still a case.
  defp hook(c) do
    List.first(c.preview.sharpest)
  end

  # A case now has three or four arguments, one per advocate, so "Oral
  # argument" four times over is no longer a label — the name is.
  defp label(w) do
    case w.collection_role do
      "opinion" -> "Opinion of the Court"
      "argument" -> short(w.title)
      _ -> short(w.title)
    end
  end

  defp short(title) do
    case String.split(title, " — ", parts: 2) do
      [_case, rest] -> rest
      [whole] -> whole
    end
  end

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  defp fmt(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp fmt(n), do: to_string(n)
end
