# The term, read closely: /cases

`CaseLive.Index`. Every case the owner has published, each as a card: the
record facts, the question presented, the Court's own holding sentence, the
read pass's account of the opinion, the sharpest disagreement it found between
the documents, the pairings a reader can open, and the documents themselves
with the PDF each was made from.

A visitor needs no account; nothing here mints one. The tour overlay is always
on the page and the browser decides whether to run it, against a flag in
`localStorage`.

    let { Ctx } = import("webcore/src");
    let { PageMeta } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, hraw, htext, attr } = import("html/src");
    let { sysGraphemeLength } = import("sys/src");
    let { webRedirect } = import("webcore/src");
    let { Work } = import("works/src");
    let { LinkEdgeEnds } = import("links/src");
    let {
      CaseStudy, CasePreview, CaseRecord, CaseWay, CaseKin, casesPublished, casesPreview, casesRecordFor,
      casesWays, casesKin, casesWalkSteps,
    } = import("cases/src");

## State

A case as the index shows it: the study, what the card previews, the record
facts (null for a collection that is not a court case), the pairings in the
order they are offered and the cases it is related to.

    export class CasesIndexCard(
      public study: CaseStudy,
      public preview: CasePreview,
      public record: CaseRecord?,
      public ways: List<CaseWay>,
      public kin: List<CaseKin>,
    ) {}

`opener`: one real disagreement, set above the cards before any explanation of
what a connection is. `count` is how many tensions the case has in all.

    export class CasesOpener(public study: CaseStudy, public count: Int, public edge: LinkEdgeEnds) {}

`open` is the slug whose first impression is unclamped, or null.

    export class CasesIndexState(
      public cards: List<CasesIndexCard>,
      public open: String?,
      public words: Int,
      public docs: Int,
      public edges: Int,
      public span: String,
      public opener: CasesOpener?,
    ) {}

The index keeps its one piece of state under a name no case slug can have
(slugs have no leading dash).

    let pgcIndexSlug(): String { "-index" }

### The year

The last word of `Decided June 29, 2026`, when it is four digits.

    let pgcYearOf(decided: String): Int? {
      let words = decided.split(" ");
      let last = words[words.length - 1];
      if (sysGraphemeLength(last) == 4) {
        let n: Int? = do { last.toInt32() } orelse null;
        n
      } else { null }
    }

The decision years of the cases on the page, each once, oldest first.

    let pgcYears(cards: List<CasesIndexCard>): List<Int> {
      let seen = new MapBuilder<Int, Boolean>();
      let out = new ListBuilder<Int>();
      for (let c of cards) {
        let r = c.record;
        if (r != null) {
          let y = pgcYearOf(r.decided);
          if (y != null) {
            if (!seen.has(y)) { seen.set(y, true); out.add(y); }
          }
        }
      }
      out.toList().sorted { (a: Int, b: Int): Int => a - b }
    }

`span/1`: nothing when no case has a date, `'s 2025 term` for one year,
`'s 2024–2025 terms` for several. A term is named by the year it began, so a
decision in 2026 prints 2025.

    export let pagesCasesSpan(years: List<Int>): String {
      if (years.length == 0) {
        ""
      } else if (years.length == 1) {
        "'s ${(years[0] - 1).toString()} term"
      } else {
        "'s ${(years[0] - 1).toString()}–${(years[years.length - 1] - 1).toString()} terms"
      }
    }

### The opener

Of the case with the most tensions (the first by name on a tie), the tension
whose reason is closest to 170 characters long (the first on a tie). The reason
is the raw one, with its A and B unresolved, as the page has always shown it.

    let pgcTensions(c: CaseStudy): List<LinkEdgeEnds> {
      let out = new ListBuilder<LinkEdgeEnds>();
      for (let l of c.links) {
        for (let e of c.byLink.getOr(l.id, [])) {
          if (e.edge.edgeType == "tension") { out.add(e); }
        }
      }
      out.toList()
    }

    let pgcDistance(e: LinkEdgeEnds): Int {
      let r = e.edge.rationale;
      let len = if (r != null) { sysGraphemeLength(r) } else { 0 };
      if (len > 170) { len - 170 } else { 170 - len }
    }

    export let pagesCasesOpener(cards: List<CasesIndexCard>): CasesOpener? {
      var best: CasesIndexCard? = null;
      var bestCount = 0;
      for (let c of cards) {
        let n = pgcTensions(c.study).length;
        if (n > bestCount) { best = c; bestCount = n; }
      }
      let b = best;
      if (b != null) {
        let ts = pgcTensions(b.study);
        var pick = ts[0];
        for (let t of ts) {
          if (pgcDistance(t) < pgcDistance(pick)) { pick = t; }
        }
        new CasesOpener(b.study, bestCount, pick)
      } else {
        null
      }
    }

### The description

    export let pagesCasesIndexDescription(cards: List<CasesIndexCard>): String {
      if (cards.length == 0) {
        "Supreme Court cases, read document by document and related to each other."
      } else {
        var docs = 0;
        for (let c of cards) { docs += c.study.works.length; }
        "${cards.length.toString()} Supreme Court cases, ${docs.toString()} documents — every opinion, concurrence, dissent and advocate's argument read on its own, then read against each other, with every connection anchored to a sentence in both."
      }
    }

### Loading

    let pgcTake<T>(xs: List<T>, n: Int): List<T> {
      xs.slice(0, if (xs.length < n) { xs.length } else { n })
    }

    export let loadCasesIndex(ctx: Ctx): CasesIndexState throws Bubble {
      let studies = casesPublished(ctx.db);
      let cards = studies.map { (c: CaseStudy): CasesIndexCard =>
        new CasesIndexCard(c, casesPreview(c), casesRecordFor(c.name), casesWays(c), casesKin(c))
      };
      var words = 0;
      var docs = 0;
      var edges = 0;
      for (let c of studies) {
        words += c.words;
        docs += c.works.length;
        edges += c.edges;
      }
      new CasesIndexState(
        cards, pagesCasesOptional(ctx, pgcIndexSlug(), "open"), words, docs, edges,
        pagesCasesSpan(pgcYears(cards)), pagesCasesOpener(cards),
      )
    }

## Render

### The head

    let pgcIndexTop(state: CasesIndexState): List<AnyValue> {
      let n = state.cards.length;
      h("header", attr("class", "cs-top"), [
        "\n      ",
        h("h1", "", hraw("The term, read closely")),
        "\n      ",
        h("p", attr("class", "lede"), [
          htext("${n.toString()} ${pagesCasesPlural(n, "case")} from the Supreme Court${state.span}"),
          hraw(". Each arrives as a pile of separate documents — the opinion of the Court, everything written alongside or against it, and every advocate's turn at the lectern — and each one is read on its own terms before any of them are compared."),
        ]),
        "\n      ",
        h("p", attr("class", "how1"), hraw("Each document read on its own, then related to the others — so you can read the opinion with the dissent following along beside it, snapping to whatever it is answering.")),
        "\n      ",
        h("button", "${attr("class", "cs-tour")}${attr("onclick", "document.getElementById('walk').dispatchEvent(new CustomEvent('mg:walk', {bubbles: true}))")}", [
          "Take the tour ", h("span", attr("aria-hidden", "true"), hraw("→")),
        ]),
        "\n\n      ",
        h("p", attr("class", "tally"), [
          "\n        ",
          h("span", "", [h("b", "", htext(n.toString())), " ", htext(pagesCasesPlural(n, "case"))]),
          "\n        ",
          h("span", "", [h("b", "", htext(state.docs.toString())), " ", htext(pagesCasesPlural(state.docs, "document"))]),
          "\n        ",
          h("span", "", [h("b", "", htext(pagesCasesFmt(state.words))), " words"]),
          "\n        ",
          h("span", "", [h("b", "", htext(state.edges.toString())), " connections drawn between them"]),
          "\n      ",
        ]),
        "\n    ",
      ])
    }

    let pgcIndexOpener(o: CasesOpener?): List<AnyValue> {
      if (o != null) { pgcOpenerSection(o) } else { [] }
    }

    let pgcOpenerSection(o: CasesOpener): List<AnyValue> {
      let why = o.edge.edge.rationale;
      h("section", attr("class", "cs-opener"), [
        "\n      ",
        h("span", attr("class", "mg-label"), hraw("for instance")),
        "\n      ",
        h("p", attr("class", "q"), htext(if (why != null) { why } else { "" })),
        "\n      ",
        h("p", attr("class", "src"), [
          "\n        one of ", h("b", "", htext(o.count.toString())), " places the documents in\n        ",
          h("em", "", htext(o.study.name)),
          "\n        pull against each other —\n        ",
          h("a", attr("href", "/cases/${o.study.slug}/read"), hraw("read it →")),
          "\n      ",
        ]),
        "\n    ",
      ])
    }

### One card

The sharpest connection of the case, in the pass's own words: the first of the
preview's sharpest three.

    let pgcHook(c: CasesIndexCard): List<AnyValue> {
      if (c.preview.sharpest.length == 0) {
        []
      } else {
        let why = c.preview.sharpest[0].edge.rationale;
        [h("p", attr("class", "cs-hook"), htext(if (why != null) { why } else { "" })), "\n      "]
      }
    }

    let pgcRecordSpans(c: CasesIndexCard): List<AnyValue> {
      let r = c.record;
      if (r != null) {
        h("span", attr("class", "rec"), [
          "\n          ",
          h("span", attr("class", "dk"), htext(r.docket)),
          "\n          ",
          h("span", "", htext("Argued ${r.argued}")),
          "\n          ",
          h("span", "", htext("Decided ${r.decided}")),
          "\n        ",
        ])
      } else { [] }
    }

    let pgcQuestion(c: CasesIndexCard): List<AnyValue> {
      let r = c.record;
      let q = if (r != null) { r.question } else { null };
      if (q != null) {
        [
          h("p", attr("class", "qp"), [
            h("span", attr("class", "mg-label"), hraw("question presented")),
            "\n        ", htext(q), "\n      ",
          ]),
          "\n      ",
        ]
      } else { [] }
    }

    let pgcHolding(c: CasesIndexCard): List<AnyValue> {
      let held = c.study.holding;
      if (held != null) {
        [
          h("blockquote", attr("class", "cs-held"), [
            h("span", attr("class", "mg-label"), hraw("the Court, holding")),
            "\n        ", htext(held), "\n      ",
          ]),
          "\n      ",
        ]
      } else { [] }
    }

The opinion's first impression, clamped until its button asks for the rest.
The same text is also offered as a `details`, which the stylesheet shows where
the clamp does not fit.

    let pgcImpression(c: CasesIndexCard, openSlug: String?): List<AnyValue> {
      let fi = c.preview.impression;
      let isOpen = openSlug != null && openSlug == c.study.slug;
      if (fi != null) { pgcImpressionBlock(c, fi, isOpen) } else { [] }
    }

    let pgcImpressionBlock(c: CasesIndexCard, fi: String, isOpen: Boolean): List<AnyValue> {
      [
        h("div", attr("class", "cs-fi"), [
          "\n        ",
          h("span", attr("class", "mg-label"), hraw("on reading the opinion")),
          "\n        ",
          h("p", attr("class", if (isOpen) { "fi" } else { "fi clamped" }), htext(fi)),
          "\n        ",
          h("button", "${attr("phx-click", "impression")}${attr("phx-value-slug", c.study.slug)}${attr("class", "more")}", htext(if (isOpen) { "less" } else { "more" })),
          "\n      ",
        ]),
        "\n      ",
      ]
    }

    let pgcImpressionDetails(c: CasesIndexCard): List<AnyValue> {
      let fi = c.preview.impression;
      if (fi != null) { pgcImpressionFold(fi) } else { [] }
    }

    let pgcImpressionFold(fi: String): List<AnyValue> {
      [
        "\n      ",
        h("details", attr("class", "cs-fi"), [
          "\n        ",
          h("summary", "", [
            h("span", attr("class", "mg-label"), hraw("on reading the opinion")),
            "\n          ",
            h("span", attr("class", "peek"), htext(fi)),
            "\n        ",
          ]),
          "\n        ",
          h("p", "", htext(fi)),
          "\n      ",
        ]),
      ]
    }

One pairing: the two documents by their names, the lead first, and how many
connections they share.

    let pgcWay(w: CaseWay): List<AnyValue> {
      h("li", "", [
        h("a", attr("href", "/links/${w.link.id.toString()}?lead=${w.lead.slug}"), [
          "\n            ",
          h("span", attr("class", pagesCasesCls(["a", pgcRoleOr(w.lead.collectionRole)])), htext(pagesCasesShortTitle(w.lead.title))),
          "\n            ",
          h("span", "${attr("class", "x")}${attr("aria-hidden", "true")}", hraw("against")),
          "\n            ",
          h("span", attr("class", pagesCasesCls(["b", pgcRoleOr(w.other.collectionRole)])), htext(pagesCasesShortTitle(w.other.title))),
          "\n            ",
          h("span", attr("class", "n"), htext(w.edges.toString())),
          "\n            ",
          h("span", "${attr("class", "arrow")}${attr("aria-hidden", "true")}", hraw("→")),
          "\n          ",
        ]),
      ])
    }

    let pgcRoleOr(role: String?): String {
      if (role != null) { role } else { "" }
    }

    let pgcKin(c: CasesIndexCard): List<AnyValue> {
      if (c.kin.length == 0) { return []; }
      [
        h("div", attr("class", "cs-kin"), [
          "\n        ",
          h("span", attr("class", "mg-label"), hraw("elsewhere in the term")),
          pgcTake(c.kin, 3).map { (k: CaseKin): List<AnyValue> =>
            [
              "\n        ",
              h("a", "${attr("href", "/links/${k.linkId.toString()}?lead=${k.lead.slug}")}${attr("class", "k")}", [
                htext(k.caseName), " ", h("span", attr("class", "n"), htext(k.edges.toString())),
              ]),
            ]
          },
          "\n      ",
        ]),
        "\n\n      ",
      ]
    }

`label(w)`: the opinion is the Opinion of the Court; the others are named by
what distinguishes them.

    let pgcLabel(w: Work): String {
      if (w.collectionRole == "opinion") { "Opinion of the Court" } else { pagesCasesShortTitle(w.title) }
    }

    let pgcPart(c: CaseStudy, w: Work): List<AnyValue> {
      let src = w.sourceUrl;
      h("li", attr("class", pgcRoleOr(w.collectionRole)), [
        "\n            ",
        h("a", "${attr("href", "/cases/${c.slug}/read/${w.slug}")}${attr("class", "t")}", htext(pgcLabel(w))),
        "\n            ",
        h("span", attr("class", "n"), htext(pagesCasesFmt(w.wordCount))),
        "\n            ",
        if (src != null) {
          h("a", "${attr("href", src)}${attr("rel", "noopener")}${attr("class", "pdf")}${attr("title", "The PDF this was made from")}", hraw("pdf"))
        } else { [] },
        "\n          ",
      ])
    }

    let pgcCard(c: CasesIndexCard, openSlug: String?): List<AnyValue> {
      let s = c.study;
      h("article", attr("class", "cs-case"), [
        "\n      ",
        h("div", attr("class", "cs-case-head"), [
          "\n        ",
          h("h2", "", h("a", attr("href", "/cases/${s.slug}/read"), htext(s.name))),
          "\n        ",
          pgcRecordSpans(c),
          "\n      ",
        ]),
        "\n\n      ",
        pgcQuestion(c),
        pgcHolding(c),
        "\n      ",
        pgcImpression(c, openSlug),
        pgcHook(c),
        h("ul", attr("class", "cs-ways"), [
          "\n        ",
          pgcTake(c.ways, 3).map { (w: CaseWay): List<AnyValue> => [pgcWay(w), "\n        "] },
          "\n      ",
        ]),
        "\n",
        pgcImpressionDetails(c),
        "\n      ",
        pgcKin(c),
        h("div", attr("class", "cs-parts"), [
          "\n        ",
          h("ul", "", [
            "\n          ",
            s.works.map { (w: Work): List<AnyValue> => [pgcPart(s, w), "\n          "] },
            "\n        ",
          ]),
          "\n      ",
        ]),
        "\n\n      ",
        h("div", attr("class", "cs-case-foot"), [
          "\n        ",
          h("a", "${attr("href", "/cases/${s.slug}/read")}${attr("class", "go")}", htext("or all ${s.works.length.toString()} at once →")),
          "\n        ",
          h("a", "${attr("href", "/cases/${s.slug}")}${attr("class", "go")}", htext("all ${s.edges.toString()} connections →")),
          "\n      ",
        ]),
        "\n    ",
      ])
    }

### The method and the provenance

Folded, and after the cases, where someone who has seen the thing work will go
looking for how.

    let pgcHow(): List<AnyValue> {
      h("details", attr("class", "cs-how"), [
        "\n      ",
        h("summary", "", h("span", attr("class", "mg-label"), hraw("how this works"))),
        "\n      ",
        h("ol", "", [
          "\n        ",
          h("li", "", [
            "\n          ", h("b", "", hraw("The Reporter's syllabus is not one of the documents.")),
            "\n          ", hraw("Every slip opinion opens with a headnote summarising itself, and every slip opinion says on the same page that the headnote \"constitutes no part of the opinion of the Court\". It is not read here and nothing on this site is drawn from it. Where a case states its holding below, that is the Court's own sentence, quoted out of the opinion; three of these sixteen never put their holding in one sentence, and those cases show none."),
            "\n        ",
          ]),
          "\n        ",
          h("li", "", [
            "\n          ", h("b", "", hraw("Every document is read separately.")),
            "\n          ", hraw("Not summarised — read. Each paragraph gets the beats it contains, anchored to a sentence copied out of the document character for character, and above those sit the spine of the argument, the threads that run through it, and the questions it leaves open."),
            "\n        ",
          ]),
          "\n        ",
          h("li", "", [
            "\n          ", h("b", "", hraw("An argument is split at the lectern.")),
            "\n          ", hraw("A transcript is not one document. Each advocate's turn is its own case to make, with its own questions from the bench, so each is read as its own draft. The difference is not cosmetic: kept whole, one argument came back with 44 connections to its opinion, and split it came back with 215."),
            "\n        ",
          ]),
          "\n        ",
          h("li", "", [
            "\n          ", h("b", "", hraw("Then the documents are related to each other.")),
            "\n          ", hraw("Not the texts — the maps. A pass reads both graphs and draws the edges between them: what one develops, what it answers, and where the two genuinely pull apart. An edge that does not land on a real anchored passage in both documents is thrown away before it is stored."),
            "\n        ",
          ]),
          "\n        ",
          h("li", "", [
            "\n          ", h("b", "", hraw("Then you read the case with the case in the margin.")),
            "\n          ", hraw("The opinion down the left, and every other document beside it at once — the dissent and both advocates on the same paragraph, each saying which one it is. Or take them two at a time, one following the other as you scroll, with a line drawn between the passages and the reason in the middle."),
            "\n        ",
          ]),
          "\n        ",
          h("li", "", [
            "\n          ", h("b", "", hraw("And you can argue with it.")),
            "\n          ", hraw("Every passage can be talked about, on its own or against its counterpart in another document. Click the line between two passages and both go into the question."),
            "\n        ",
          ]),
          "\n      ",
        ]),
        "\n    ",
      ])
    }

    let pgcProvenance(): List<AnyValue> {
      h("footer", attr("class", "cs-prov"), [
        "\n      ",
        h("span", attr("class", "mg-label"), hraw("about these")),
        "\n      ",
        h("p", "", hraw("The documents are slip opinions and argument transcripts published by the Supreme Court of the United States; every one links to the PDF it was made from. The Reporter's syllabus is excluded — it is no part of the opinion and says so itself — as are the headnotes of any other reporter. The reading and the connections are machine-made, and every passage quoted back to you is verified against the source before it is stored — a quote that cannot be found in the document, character for character, is discarded rather than shown. Nothing here is a summary, a headnote, or legal advice, and none of it is a substitute for reading the opinion.")),
        "\n    ",
      ])
    }

### The page

The tour overlay first, always rendered: the hook decides whether to run it.

    export let renderCasesIndex(state: CasesIndexState): List<AnyValue> {
      [
        pagesCasesWalkOverlay(
          casesWalkSteps("cases"), "cases",
          "Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would.",
        ),
        "\n\n  ",
        h("div", attr("class", "cs"), [
          "\n    ",
          pgcIndexTop(state),
          "\n\n    ",
          pgcIndexOpener(state.opener),
          "\n\n    ",
          if (state.cards.length == 0) { h("p", attr("class", "none"), hraw("Nothing here yet.")) } else { [] },
          "\n\n    ",
          state.cards.map { (c: CasesIndexCard): List<AnyValue> => [pgcCard(c, state.open), "\n\n    "] },
          pgcHow(),
          "\n\n    ",
          if (state.cards.length > 0) { pgcProvenance() } else { [] },
          "\n  ",
        ]),
      ]
    }

    export let pagesCasesIndexMeta(state: CasesIndexState): PageMeta {
      new PageMeta(
        "The term, read closely",
        pagesCasesIndexDescription(state.cards),
        null,
        "/images/og-cases.png",
        "A line of a Supreme Court opinion, highlighted, with a line drawn across to the dissent arguing with that exact sentence in the margin.",
        "/cases",
      )
    }

## GET /cases

A plain visit starts with every clamp shut, as a mount did.

    export let pagesCasesIndexPage(ctx: Ctx): Response throws Bubble {
      if (!ctx.isAjax) { pagesCasesDropKey(ctx, pgcIndexSlug(), "open"); }
      let state = loadCasesIndex(ctx);
      pagesCasesAnswer(ctx, pagesCasesIndexMeta(state), renderCasesIndex(state), null, "app")
    }

## Events

`impression` with `slug`: the clamp of that case opens, or shuts if it was the
open one; only one is open at a time.

`walk_hop` with `to` = `first_pair`: the first case (by name), its first pairing,
opened in the pairwise reading with the next leg of the tour. With no pairing
the tour ends where it stands. Any other `to` is a bug in the caller, which
the Elixir crashed on and this stops on, with a line in the log.

    let pgcFirstPair(ctx: Ctx, state: CasesIndexState): String? {
      if (state.cards.length == 0) { return null; }
      let ways = state.cards[0].ways;
      if (ways.length == 0) { return null; }
      "/links/${ways[0].link.id.toString()}?lead=${ways[0].lead.slug}&walk=1"
    }

    export let pagesCasesIndexEvent(ctx: Ctx, event: String, payload: JsonObject): Response throws Bubble {
      if (event == "impression") {
        let slug = pagesCasesField(payload, "slug");
        let current = pagesCasesOptional(ctx, pgcIndexSlug(), "open");
        if (current != null && current == slug) {
          pagesCasesDropKey(ctx, pgcIndexSlug(), "open");
        } else {
          pagesCasesPutKey(ctx, pgcIndexSlug(), "open", slug);
        }
        let state = loadCasesIndex(ctx);
        pagesCasesAnswer(ctx, pagesCasesIndexMeta(state), renderCasesIndex(state), null, "app")
      } else if (event == "walk_hop") {
        let to = pagesCasesField(payload, "to");
        if (to != "first_pair") {
          console.log("pages_cases: /cases walk_hop to ${to}");
          bubble()
        }
        let state = loadCasesIndex(ctx);
        let path = pgcFirstPair(ctx, state);
        if (path != null) {
          webRedirect(ctx, path, null)
        } else {
          pagesCasesAnswer(ctx, pagesCasesIndexMeta(state), renderCasesIndex(state), null, "app")
        }
      } else {
        pagesCasesUnhandled("/cases", event)
      }
    }
