# One pair: /links/:id and /links/:id/read

`LinkLive.Read`, the "follow" view. Two documents side by side: the left (the
lead) is read by scrolling, and the right is scrolled by the `Follow` hook to
the passage the paragraph in front of you is related to. Between them a strip
states the relation and the reason with a wire drawn through it; a bubble
lets the reader ask about the pair. While the pass that relates the two runs,
and after it failed, the page is the waiting view instead.

Both routes are this page. Its query: `lead=<slug>` (which draft is the left
column; default the pair's first), `only=<edge type>` (one kind of relation),
`walk=1` (the guided walkthrough, and no one-time card).

    let { Ctx, webMeta, webRedirect, webNotFound, uiGet, uiPut, uiDelete } = import("webcore/src");
    let { PageMeta } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { Db } = import("db/src");
    let { h, hv, htext, hraw, attr, classes, slugPlain, wordCount } = import("html/src");
    let { sysJoin, sysStringTrim } = import("sys/src");
    let { Work, GraphNode, worksNodes } = import("works/src");
    let { accountsSeenTour, accountsMarkTourSeen } = import("accounts/src");
    let {
      Link, LinkWorks, LinkEdgeEnds, LinkStats, LinkNote,
      linksGet, linksWorks, linksOther, linksForWork, linksStats, linksEdges, linksEdgeCount,
      linksMargin, linksNotesFor, linksSummary, linksSetStatus, linksAttrsError, linksChatAskCited,
    } = import("links/src");
    let {
      ReadingNote, ReadingSection, ReadingBlock, ReadingOptions, readingPage, readingRenderBlock,
    } = import("reading/src");
    let { runsGet } = import("runs/src");
    let { LlmMessage } = import("llm/src");

## State

What the columns need of a note, a paragraph and a section: the rest of
`Reading`'s records stays behind in `load`. A note's `peerRef` is the
paragraph at the far end of its edge, on the other page, or null when that
end has no anchored paragraph (it is a spine node, say).

    export class LinksNote(
      public edgeId: Int,
      public kind: String,
      public title: String,
      public body: String,
      public peerRef: String?,
    ) {}

    export class LinksBlock(
      public ref: String,
      public text: String,
      public mark: String?,
      public notes: List<LinksNote>,
    ) {}

    export class LinksSection(
      public ordinal: Int,
      public title: String,
      public blocks: List<LinksBlock>,
    ) {}

The other pairs the lead is in: the switcher in the reference's head.

    export class LinksOther(
      public linkId: Int,
      public status: String,
      public edges: Int,
      public title: String,
    ) {}

`waitA` and `waitB` are the titles of the beats of the lead and the other
draft, only while the link is not linked. `cited` are the edges the chat is
pointing at.

    export class LinksReadState(
      public link: Link,
      public summary: String?,
      public lead: Work,
      public other: Work,
      public leadPage: List<LinksSection>,
      public otherPage: List<LinksSection>,
      public waitA: List<String>,
      public waitB: List<String>,
      public others: List<LinksOther>,
      public only: String?,
      public stats: LinkStats,
      public tour: Boolean,
      public walk: Boolean,
      public chat: LinksChat,
      public cited: List<LinkEdgeEnds>,
    ) {}

The UI state of a pair: `links:<id>:only`, `links:<id>:chat` (see the chat
module), and the flags of the card and the walkthrough, which are not about one
pair.

    let plKeyOnly(id: Int): String { "links:${id.toString()}:only" }
    let plKeyTour(): String { "links:tour" }
    let plKeyWalk(): String { "links:walk" }

### The columns

A map from a key to what it keys, for the generic lookups below.

    let plLookup<K, V>(m: MapBuilder<K, V>, k: K): V? {
      if (m.has(k)) { m.get(k) orelse null } else { null }
    }

    let plReadingNotes(notes: List<LinkNote>): List<ReadingNote> {
      notes.map { (n: LinkNote): ReadingNote =>
        new ReadingNote(n.key, n.sectionId, n.kind, n.quote, n.title, n.body, false)
      }
    }

    let plNotesByKey(notes: List<LinkNote>): MapBuilder<String, LinkNote> {
      let out = new MapBuilder<String, LinkNote>();
      for (let n of notes) { out.set(n.key, n); }
      out
    }

For each node that is the near end of a placed note, the paragraph it sits in:
the answer to "where is this edge's end on that page".

    let plRefsByNear(secs: List<ReadingSection>, notes: List<LinkNote>): Map<Int, String> {
      let byKey = plNotesByKey(notes);
      let out = new MapBuilder<Int, String>();
      for (let sec of secs) {
        for (let b of sec.blocks) {
          for (let n of b.notes) {
            let ln = plLookup(byKey, n.key);
            if (ln != null) {
              if (!out.has(ln.nearId)) { out.set(ln.nearId, b.ref); }
            }
          }
        }
      }
      out.toMap()
    }

    let plSections(secs: List<ReadingSection>, notes: List<LinkNote>, peers: Map<Int, String>): List<LinksSection> {
      let byKey = plNotesByKey(notes);
      secs.map { (sec: ReadingSection): LinksSection =>
        new LinksSection(sec.section.ordinal, sec.section.title, sec.blocks.map { (b: ReadingBlock): LinksBlock =>
          new LinksBlock(b.ref, b.text, b.mark, b.notes.map { (n: ReadingNote): LinksNote =>
            let ln = plLookup(byKey, n.key);
            if (ln != null) {
              new LinksNote(ln.edgeId, ln.kind, ln.title, ln.body, if (peers.has(ln.peer)) { peers.getOr(ln.peer, "") } else { null })
            } else {
              new LinksNote(0, n.kind, n.title, plOrEmpty(n.body), null)
            }
          })
        })
      }
    }

### Loading

`only` and the tour and walkthrough flags are the session's, set by the visit
(`pagesLinksReadPage`) and the events. A link that is waiting has no pages.

    let plOnlyOf(ctx: Ctx, id: Int): String? {
      let raw = uiGet(ctx, plKeyOnly(id));
      if (raw == null || raw == "" || raw == "all") { null } else { raw }
    }

    let plBeatTitles(db: Db, work: Work): List<String> throws Bubble {
      let out = new ListBuilder<String>();
      for (let n of worksNodes(db, work.id)) {
        if (n.nodeType == "beat") { out.add(n.title); }
      }
      out.toList()
    }

    let plOthers(db: Db, lead: Work, link: Link): List<LinksOther> throws Bubble {
      let out = new ListBuilder<LinksOther>();
      for (let lw of linksForWork(db, lead.id)) {
        if (lw.link.id != link.id) {
          let far = linksOther(lw, lead.id);
          let edges = if (lw.link.status == "linked") { linksEdgeCount(db, lw.link.id) } else { 0 };
          out.add(new LinksOther(lw.link.id, lw.link.status, edges, far.title));
        }
      }
      out.toList()
    }

The edges the chat is pointing at, in the order the link has them.

    let plCitedEdges(db: Db, link: Link, ids: List<Int>): List<LinkEdgeEnds> throws Bubble {
      if (ids.length == 0) { return []; }
      let out = new ListBuilder<LinkEdgeEnds>();
      for (let e of linksEdges(db, link)) {
        var cited = false;
        for (let id of ids) { if (id == e.edge.id) { cited = true; } }
        if (cited) { out.add(e); }
      }
      out.toList()
    }

`lead=<slug of b>` swaps the sides; anything else leaves the first draft on the
left.

    let plLeadOf(ctx: Ctx, lw: LinkWorks): Work {
      if (ctx.req.query.getOr("lead", "") == lw.bWork.slug) { lw.bWork } else { lw.aWork }
    }

    export let loadLinksRead(ctx: Ctx, link: Link): LinksReadState throws Bubble {
      let lw = linksWorks(ctx.db, link);
      let lead = plLeadOf(ctx, lw);
      let other = linksOther(lw, lead.id);
      var leadPage: List<LinksSection> = [];
      var otherPage: List<LinksSection> = [];
      var waitA: List<String> = [];
      var waitB: List<String> = [];
      if (link.status == "linked") {
        let leadNotes = linksMargin(ctx.db, link, lead.id);
        let otherNotes = linksNotesFor(ctx.db, link, other.id);
        let leadSecs = readingPage(ctx.db, lead, new ReadingOptions(null, null, plReadingNotes(leadNotes)));
        let otherSecs = readingPage(ctx.db, other, new ReadingOptions(null, null, plReadingNotes(otherNotes)));
        leadPage = plSections(leadSecs, leadNotes, plRefsByNear(otherSecs, otherNotes));
        otherPage = plSections(otherSecs, otherNotes, plRefsByNear(leadSecs, leadNotes));
      } else {
        waitA = plBeatTitles(ctx.db, lead);
        waitB = plBeatTitles(ctx.db, other);
      }
      let chat = pagesLinksChatOf(ctx, link.id);
      new LinksReadState(
        link, linksSummary(ctx.db, link), lead, other, leadPage, otherPage, waitA, waitB,
        plOthers(ctx.db, lead, link), plOnlyOf(ctx, link.id), linksStats(ctx.db, link),
        plOrEmpty(uiGet(ctx, plKeyTour())) == "1", plOrEmpty(uiGet(ctx, plKeyWalk())) == "on",
        chat, plCitedEdges(ctx.db, link, chat.cited),
      )
    }

## Render

### The paragraphs

`tag_label`: the relation, or how many of them. `tag_kind`: the shared relation
or `mixed`.

    let plSpaced(kind: String): String { sysJoin(kind.split("_"), " ") }

    export let pagesLinksTagLabel(notes: List<LinksNote>): String {
      if (notes.length == 1) { plSpaced(notes[0].kind) } else { "${notes.length.toString()} links" }
    }

    export let pagesLinksTagKind(notes: List<LinksNote>): String {
      var kind = notes[0].kind;
      for (let n of notes) { if (n.kind != kind) { kind = "mixed"; } }
      kind
    }

    let plShown(n: LinksNote, only: String?): Boolean {
      if (only == null) { true } else { n.kind == only }
    }

    let plShownNotes(b: LinksBlock, only: String?): List<LinksNote> {
      let out = new ListBuilder<LinksNote>();
      var i = 0;
      while (i < b.notes.length) {
        let n = b.notes[i];
        if (plShown(n, only)) { out.add(n); }
        i += 1;
      }
      out.toList()
    }

### The quiet stretches

`condense`: a paragraph with a shown note is "linked", and it and its two
neighbours are kept. What is left over is cut into stretches: one paragraph is
drawn as itself, more are folded into a `<details>` that says how many and how
long. Nothing is deleted.

    export class LinksRun(public gap: Boolean, public blocks: List<LinksBlock>) {}

    export let pagesLinksCondense(blocks: List<LinksBlock>, only: String?): List<LinksRun> {
      let n = blocks.length;
      let keep = new MapBuilder<Int, Boolean>();
      var i = 0;
      while (i < n) {
        if (plShownNotes(blocks[i], only).length > 0) {
          keep.set(i, true);
          if (i > 0) { keep.set(i - 1, true); }
          if (i + 1 < n) { keep.set(i + 1, true); }
        }
        i += 1;
      }
      let out = new ListBuilder<LinksRun>();
      i = 0;
      while (i < n) {
        let kept = keep.has(i);
        var j = i;
        while (j < n && keep.has(j) == kept) { j += 1; }
        let chunk = blocks.slice(i, j);
        if (kept || chunk.length == 1) {
          var k = 0;
          while (k < chunk.length) {
            out.add(new LinksRun(false, [chunk[k]]));
            k += 1;
          }
        } else {
          out.add(new LinksRun(true, chunk));
        }
        i = j;
      }
      out.toList()
    }

Whitespace-separated words of the raw Markdown.

    export let pagesLinksWords(blocks: List<LinksBlock>): Int {
      var total = 0;
      for (let b of blocks) { total += wordCount(b.text); }
      total
    }

### One column

The ids of the paragraphs are namespaced by side, because both columns number
their paragraphs from their own first one: `blk-lead-s1p1`, `blk-other-s1p1`.
The anchored span is `anchor-<side>-<ref>` for the same reason.

    let plNoteData(n: LinksNote): List<AnyValue> {
      h("span", " hidden${attr("data-peer-ref", n.peerRef)}${attr("data-kind", n.kind)}${attr("data-why", n.body)}${attr("data-edge", n.edgeId.toString())}${attr("data-src", n.title)}", [])
    }

One entry per edge, each carrying the paragraph on the other side it points at.
An edge whose far end has no paragraph says so rather than showing a control
that looks live and does nothing.

    let plJump(n: LinksNote): List<AnyValue> {
      h("button", "${attr("type", "button")}${attr("class", "fl-jump k-${n.kind}")}${if (n.peerRef == null) { " disabled" } else { "" }}${attr("data-peer-ref", n.peerRef)}${attr("data-edge", n.edgeId.toString())}${attr("data-kind", n.kind)}", [
        "\n",
        h("span", attr("class", "rel"), htext(plSpaced(n.kind))),
        "\n",
        h("span", attr("class", "to"), htext(n.title)),
        "\n",
        h("span", attr("class", "why"), htext(n.body)),
        "\n",
        if (n.peerRef == null) {
          h("span", attr("class", "nowhere"), htext("whole draft — no passage to jump to"))
        } else { [] },
        "\n",
      ])
    }

    let plBlock(side: String, slug: String, b: LinksBlock, only: String?): List<AnyValue> {
      let notes = plShownNotes(b, only);
      let linked = notes.length > 0;
      let kind = if (linked) { pagesLinksTagKind(notes) } else { "" };
      h("div", "${attr("class", classes(["fl-block", if (linked) { "linked" } else { null }]))}${attr("id", "blk-${side}-${b.ref}")}", [
        "\n",
        hraw(readingRenderBlock(b.text, if (linked) { b.mark } else { null }, "${side}-${b.ref}", null)),
        "\n",
        h("a", "${attr("class", "fl-edit")}${attr("href", "/works/${slug}?view=read#block-${b.ref}")}${attr("title", "Edit this paragraph in the draft")}", htext("edit")),
        "\n",
        notes.map { (n: LinksNote): List<AnyValue> => [plNoteData(n), "\n"] },
        if (linked) {
          h("div", attr("class", "fl-tagwrap ${kind}"), [
            "\n",
            h("span", attr("class", "fl-tag ${kind}"), htext(pagesLinksTagLabel(notes))),
            "\n",
            h("div", attr("class", "fl-links"), [
              "\n",
              notes.map { (n: LinksNote): List<AnyValue> => [plJump(n), "\n"] },
            ]),
            "\n",
          ])
        } else { [] },
        "\n",
      ])
    }

    let plQuiet(side: String, b: LinksBlock): List<AnyValue> {
      h("div", "${attr("class", "fl-block quiet")}${attr("id", "blk-${side}-${b.ref}")}", [
        "\n",
        hraw(readingRenderBlock(b.text, null, "${side}-${b.ref}", null)),
        "\n",
      ])
    }

    let plRun(side: String, slug: String, run: LinksRun, only: String?): List<AnyValue> {
      if (run.gap) {
        h("details", attr("class", "fl-gap"), [
          "\n",
          h("summary", "", [
            "\n",
            h("span", attr("class", "n"), htext("${run.blocks.length.toString()} paragraphs")),
            "\n",
            h("span", attr("class", "w"), htext("${pagesLinksWords(run.blocks).toString()} words")),
            "\n",
          ]),
          "\n",
          h("div", attr("class", "fl-gap-body"), [
            "\n",
            run.blocks.map { (b: LinksBlock): List<AnyValue> => [plQuiet(side, b), "\n"] },
          ]),
          "\n",
        ])
      } else {
        plBlock(side, slug, run.blocks[0], only)
      }
    }

    export let renderLinksSide(page: List<LinksSection>, only: String?, side: String, slug: String): List<AnyValue> {
      h("div", attr("class", "fl-inner"), [
        "\n",
        page.map { (sec: LinksSection): List<AnyValue> =>
          [
            h("div", attr("class", "fl-sec"), [
              "\n",
              h("span", attr("class", "mg-label"), htext("Section ${sec.ordinal.toString()}")),
              "\n",
              h("h2", "", htext(sec.title)),
              "\n",
            ]),
            "\n",
            pagesLinksCondense(sec.blocks, only).map { (run: LinksRun): List<AnyValue> =>
              [plRun(side, slug, run, only), "\n"]
            },
          ]
        },
      ])
    }

### The bar

`/links/<id>/read?lead=<slug>`, and `&only=<kind>` when a relation is chosen:
the address a swap of sides goes to.

    export let pagesLinksReadPath(linkId: Int, lead: String, only: String?): String {
      if (only != null) {
        "/links/${linkId.toString()}/read?lead=${lead}&only=${only}"
      } else {
        "/links/${linkId.toString()}/read?lead=${lead}"
      }
    }

The legend: everything, then each relation the pair has, by count (largest
first) and then by name.

    export let pagesLinksLegend(stats: LinkStats): List<Pair<String, String>> {
      let all = new ListBuilder<Pair<String, Int>>();
      let kinds = stats.byType.keys();
      for (var i = 0; i < kinds.length; ++i) {
        let k = kinds.getOr(i, "");
        all.add(new Pair(k, stats.byType.getOr(k, 0)));
      }
      let sorted = all.toList().sorted { (x: Pair<String, Int>, y: Pair<String, Int>): Int =>
        if (x.value != y.value) { y.value - x.value } else if (x.key < y.key) { -1 } else if (x.key > y.key) { 1 } else { 0 }
      };
      let out = new ListBuilder<Pair<String, String>>();
      out.add(new Pair("all", "Everything"));
      for (let t of sorted) { out.add(new Pair(t.key, "${plSpaced(t.key)} ${t.value.toString()}")); }
      out.toList()
    }

    let plBar(s: LinksReadState): List<AnyValue> {
      let current = if (s.only != null) { plOrEmpty(s.only) } else { "all" };
      let summary = s.summary;
      h("div", attr("class", "fl-bar"), [
        "\n",
        h("button", "${attr("class", "fl-help")}${attr("phx-click", "show_tour")}${attr("title", "How this page works")}", htext("?")),
        "\n",
        h("a", "${attr("href", pagesLinksReadPath(s.link.id, s.other.slug, s.only))}${attr("class", "fl-swap")}${attr("title", "Read the other one instead")}", [
          "\n",
          h("span", attr("aria-hidden", "true"), htext("⇄")),
          " swap sides\n",
        ]),
        "\n",
        h("div", attr("class", "fl-legend"), [
          "\n",
          pagesLinksLegend(s.stats).map { (t: Pair<String, String>): List<AnyValue> =>
            [
              h("button", "${attr("class", "mg-tab${if (current == t.key) { " on" } else { "" }}")}${attr("phx-click", "set_only")}${attr("phx-value-only", t.key)}", htext(t.value)),
              "\n",
            ]
          },
        ]),
        "\n",
        if (summary != null) {
          h("details", attr("class", "fl-sum"), [
            "\n",
            h("summary", "", [
              "\n",
              h("span", attr("class", "mg-label"), htext("why")),
              "\n",
              h("span", attr("class", "peek"), htext(summary)),
              "\n",
              h("span", "${attr("class", "more")}${attr("aria-hidden", "true")}", []),
              "\n",
            ]),
            "\n",
            h("p", "", htext(summary)),
            "\n",
          ])
        } else { [] },
        "\n",
        h("span", attr("class", "fl-count"), [h("b", "", htext("0")), htext(" / ${s.stats.edges.toString()} addressed")]),
        "\n",
      ])
    }

### The columns and what is between them

A draft can be related to several others, and reading it against each of them
in turn is the point of having more than one: swapping is in the head of the
reference column rather than back on the list.

    let plOtherHead(s: LinksReadState): List<AnyValue> {
      if (s.others.length == 0) {
        return h("div", attr("class", "fl-colhead"), [
          "\n",
          h("span", attr("class", "mg-label"), htext("Referencing…")),
          "\n",
          h("a", attr("href", "/works/${s.other.slug}"), htext(s.other.title)),
          "\n",
        ]);
      }
      h("div", attr("class", "fl-colhead"), [
        "\n",
        h("details", attr("class", "fl-pick"), [
          "\n",
          h("summary", "", [
            "\n",
            h("span", attr("class", "mg-label"), htext("Referencing…")),
            "\n",
            h("span", attr("class", "t"), htext(s.other.title)),
            "\n",
            h("span", attr("class", "n"), htext((s.others.length + 1).toString())),
            "\n",
          ]),
          "\n",
          h("div", attr("class", "fl-pick-menu"), [
            "\n",
            h("span", attr("class", "here"), [
              "\n",
              h("span", attr("class", "t"), htext(s.other.title)),
              "\n",
              h("span", attr("class", "mg-label"), htext("reading against this")),
              "\n",
            ]),
            "\n",
            s.others.map { (o: LinksOther): List<AnyValue> =>
              [
                h("a", "${attr("href", "/links/${o.linkId.toString()}?lead=${s.lead.slug}")}${attr("class", "row")}", [
                  "\n",
                  h("span", attr("class", "t"), htext(o.title)),
                  "\n",
                  h("span", attr("class", "st ${o.status}"), htext(if (o.status == "linked") { "${o.edges.toString()} edges" } else { o.status })),
                  "\n",
                ]),
                "\n",
              ]
            },
            h("a", "${attr("href", "/links")}${attr("class", "row more")}", htext("Relate it to another…")),
            "\n",
          ]),
          "\n",
        ]),
        "\n",
      ])
    }

The wire is drawn across the whole split by the hook, through the reason card.
`hidden` until it has something to draw. Paths and circles are written with a
closing tag for the reason `<line>` is, in the index.

    let plWire(): List<AnyValue> {
      h("svg", "${attr("class", "fl-wire")} hidden", [
        "\n",
        h("path", "${attr("class", "w1")}${attr("fill", "none")}", []),
        "\n",
        h("path", "${attr("class", "w2")}${attr("fill", "none")}", []),
        "\n",
        h("circle", "${attr("class", "d1")}${attr("r", "4")}", []),
        "\n",
        h("circle", "${attr("class", "d2")}${attr("r", "4")}", []),
        "\n",
        h("path", "${attr("class", "h1 hit")}${attr("fill", "none")}", []),
        "\n",
        h("path", "${attr("class", "h2 hit")}${attr("fill", "none")}", []),
        "\n",
      ])
    }

The middle: the phone's sheet (one card per connection, built by the hook
because only the browser knows which paragraph was tapped), the wide screen's
strip (the drawn line points at one connection at a time), and the line shown
when neither has anything to say yet.

    let plMid(): List<AnyValue> {
      h("div", attr("class", "fl-mid"), [
        "\n",
        h("div", "${attr("class", "fl-sheet")} hidden", [
          "\n",
          h("div", attr("class", "fl-sheet-head"), [
            "\n",
            h("span", attr("class", "n"), []),
            "\n",
            h("button", "${attr("type", "button")}${attr("class", "shut")}${attr("aria-label", "Back to the reading")}", htext("×")),
            "\n",
          ]),
          "\n",
          h("div", attr("class", "fl-stack"), []),
          "\n",
        ]),
        "\n",
        h("div", "${attr("class", "fl-strip")} hidden", [
          "\n",
          h("div", attr("class", "fl-strip-head"), [
            "\n",
            h("span", attr("class", "rel"), []),
            "\n",
            h("span", attr("class", "nth"), []),
            "\n",
          ]),
          "\n",
          h("p", attr("class", "why"), []),
          "\n",
          h("blockquote", attr("class", "far"), []),
          "\n",
          h("button", "${attr("type", "button")}${attr("class", "ask")}", htext("ask about this")),
          "\n",
        ]),
        "\n",
        h("div", attr("class", "fl-idle"), htext("\nScroll. Where this draft touches the other, it will be shown here.\n")),
        "\n",
      ])
    }

    let plFollow(s: LinksReadState): List<AnyValue> {
      h("div", "${attr("class", "fl")}${attr("id", "follow")}${attr("phx-hook", "Follow")}", [
        "\n",
        plBar(s),
        "\n",
        h("div", attr("class", "fl-split"), [
          "\n",
          h("div", "${attr("class", "fl-col lead")}${attr("id", "fl-lead")}${attr("tabindex", "0")}", [
            "\n",
            h("div", attr("class", "fl-colhead"), [
              "\n",
              h("span", attr("class", "mg-label"), htext("Reading…")),
              "\n",
              h("a", attr("href", "/works/${s.lead.slug}"), htext(s.lead.title)),
              "\n",
            ]),
            "\n",
            renderLinksSide(s.leadPage, s.only, "lead", s.lead.slug),
            "\n",
          ]),
          "\n",
          plWire(),
          "\n",
          plMid(),
          "\n",
          h("div", "${attr("class", "fl-col other")}${attr("id", "fl-other")}${attr("tabindex", "0")}", [
            "\n",
            plOtherHead(s),
            "\n",
            renderLinksSide(s.otherPage, s.only, "other", s.other.slug),
            "\n",
          ]),
          "\n",
        ]),
        "\n",
      ])
    }

    let plTree(parts: List<AnyValue>): List<AnyValue> { parts }

    export let renderLinksRead(ctx: Ctx, s: LinksReadState): List<AnyValue> throws Bubble {
      let linked = s.link.status == "linked";
      let waiting: List<AnyValue> = if (!linked) {
        renderLinkWaiting(s.lead.title, s.other.title, s.waitA, s.waitB, s.link.status, s.link.error)
      } else { [] };
      let follow: List<AnyValue> = if (linked) { plFollow(s) } else { [] };
      let tour: List<AnyValue> = if (s.tour) { renderLinkTour() } else { [] };
      let walk: List<AnyValue> = if (s.walk) { renderLinkWalk() } else { [] };
      let bubble: List<AnyValue> = if (!s.tour) { renderLinkChatBubble(s.chat, false, s.cited) } else { [] };
      plTree([waiting, "\n", follow, "\n", tour, "\n", walk, "\n", bubble, "\n"])
    }

## The visit

A link that is not there: `No such link.` and the drafts.

    let plNoLink(ctx: Ctx): Response throws Bubble {
      webRedirect(ctx, "/works", new Pair("error", "No such link."))
    }

The pass of a link whose job died without writing its failure: the run says
`crashed` and the link still says `linking`, which would poll for ever.

    let plReconcile(ctx: Ctx, link: Link): Link throws Bubble {
      if (link.status == "linking") {
        let run = runsGet(ctx.db, pagesLinksReadKey(link.id));
        if (run != null) {
          if (run.status == "crashed") {
            let set = linksSetStatus(ctx.db, link, "failed", linksAttrsError(":crashed: ${plOrEmpty(run.detail)}"));
            let again = set.ok;
            if (again != null) { return again; }
          }
        }
      }
      link
    }

The title is `<lead> · alongside <other>`; the page is not for search engines.

    let plReadMeta(s: LinksReadState): PageMeta {
      new PageMeta("${s.lead.title} · alongside ${s.other.title}", null, "noindex, nofollow", null, null, null)
    }

    let plPollOf(link: Link): Int? {
      if (link.status == "pending" || link.status == "linking") { 2 } else { null }
    }

The link as the database has it now, rendered. `data-poll` while the pass is
pending or running: the next poll shows whatever it has become.

    let plReadReply(ctx: Ctx, stale: Link, flash: Pair<String, String>?): Response throws Bubble {
      let fresh = linksGet(ctx.db, stale.id);
      let link = plReconcile(ctx, if (fresh != null) { fresh } else { stale });
      let state = loadLinksRead(ctx, link);
      plRender(ctx, plReadMeta(state), renderLinksRead(ctx, state), plPollOf(link), flash, "bleed")
    }

A plain visit is a fresh mount: no chat, the relation from the query, the
walkthrough if `?walk=1`, and the one-time card if this user has not seen it.
The Elixir marked the card seen on the connected mount; this is the one
request, so it marks it when it shows it.

    let plFreshVisit(ctx: Ctx, link: Link): Void throws Bubble {
      uiDelete(ctx, pagesLinksChatKey(link.id));
      let only = ctx.req.query.getOr("only", "");
      if (only == "" || only == "all") {
        uiDelete(ctx, plKeyOnly(link.id));
      } else {
        uiPut(ctx, plKeyOnly(link.id), only);
      }
      let walking = ctx.req.query.getOr("walk", "") == "1";
      if (walking) { uiPut(ctx, plKeyWalk(), "on"); } else { uiDelete(ctx, plKeyWalk()); }
      var showTour = false;
      let user = ctx.scope.user;
      if (user != null) {
        if (!walking && !accountsSeenTour(user, "follow")) {
          showTour = true;
          accountsMarkTourSeen(ctx.db, user, "follow");
        }
      }
      uiPut(ctx, plKeyTour(), if (showTour) { "1" } else { "0" });
    }

    export let pagesLinksReadPage(ctx: Ctx, rawId: String): Response throws Bubble {
      let id = plInt(rawId);
      if (id != null) {
        let link = linksGet(ctx.db, id);
        if (link != null) {
          if (!ctx.isAjax) { plFreshVisit(ctx, link); }
          plReadReply(ctx, link, null)
        } else { plNoLink(ctx) }
      } else { webNotFound(ctx) }
    }

## Events

Whether the user has one of the two drafts. Looking at a pair is open to
whoever has the address (links are sent to people); making the model read it
again, or ask about it, spends the deployment's credit and is for the owner.

    let plOwns(ctx: Ctx, link: Link): Boolean throws Bubble {
      let user = ctx.scope.user;
      if (user != null) {
        let lw = linksWorks(ctx.db, link);
        lw.aWork.userId == user.id || lw.bWork.userId == user.id
      } else { false }
    }

    let plNotYours(): Pair<String, String> {
      new Pair("error", "That pair is not yours to run.")
    }

    let plCapped(history: List<LlmMessage>): List<LlmMessage> {
      let keep = pagesLinksChatKept();
      if (history.length > keep) { history.slice(history.length - keep, history.length) } else { history }
    }

`chat_send` with `message`: ignored when empty. The question is added to the
history, the cited edges are cleared, and the model is asked here, in this
request (the Elixir asked in a task and the socket updated when it answered;
there is no socket). A failed answer leaves the question in the chat and says
so in a flash.

    let plChatSend(ctx: Ctx, link: Link, payload: JsonObject, launcher: LinksLauncher): Response throws Bubble {
      let message = sysStringTrim(plPayloadString(payload, "message"));
      if (message == "") { return plReadReply(ctx, link, null); }
      if (!plOwns(ctx, link)) { return plReadReply(ctx, link, plNotYours()); }
      let chat = pagesLinksChatOf(ctx, link.id);
      let asked = new ListBuilder<LlmMessage>();
      asked.addAll(chat.history);
      asked.add(new LlmMessage("user", message));
      let history = plCapped(asked.toList());
      let result = linksChatAskCited(ctx.db, launcher.llm(), link, history, "", chat.cited);
      let reply = result.ok;
      let kept = new ListBuilder<LlmMessage>();
      kept.addAll(history);
      var flash: Pair<String, String>? = null;
      if (reply != null) {
        kept.add(new LlmMessage("assistant", reply));
      } else {
        flash = new Pair("error", "That did not go through: ${plOrEmpty(result.error)}");
      }
      pagesLinksChatPut(ctx, link.id, new LinksChat(chat.open, plCapped(kept.toList()), []));
      plReadReply(ctx, link, flash)
    }

    let plWithChat(ctx: Ctx, link: Link, chat: LinksChat): Response throws Bubble {
      pagesLinksChatPut(ctx, link.id, chat);
      plReadReply(ctx, link, null)
    }

    let plCite(ctx: Ctx, link: Link, payload: JsonObject): Response throws Bubble {
      let chat = pagesLinksChatOf(ctx, link.id);
      let edge = plPayloadInt(payload, "edge");
      if (edge != null) {
        let ids = new ListBuilder<Int>();
        ids.addAll(chat.cited);
        var present = false;
        for (let id of chat.cited) { if (id == edge) { present = true; } }
        if (!present) { ids.add(edge); }
        plWithChat(ctx, link, new LinksChat(true, chat.history, ids.toList()))
      } else {
        console.log("pages_links: /links/${link.id.toString()} cite_edge without a numeric edge");
        bubble()
      }
    }

    let plUncite(ctx: Ctx, link: Link, payload: JsonObject): Response throws Bubble {
      let chat = pagesLinksChatOf(ctx, link.id);
      let edge = plPayloadInt(payload, "edge");
      let ids = new ListBuilder<Int>();
      for (let id of chat.cited) { if (edge == null || id != edge) { ids.add(id); } }
      plWithChat(ctx, link, new LinksChat(chat.open, chat.history, ids.toList()))
    }

`set_only` with `only`: `""` and `all` are every relation. The Elixir
`push_patch`ed to the same page with `&only=`; the client here can only
navigate, which would end a walkthrough in the middle, so the page re-renders
in place and the address bar is left as it was.

    let plSetOnly(ctx: Ctx, link: Link, payload: JsonObject): Response throws Bubble {
      let only = plPayloadString(payload, "only");
      if (only == "" || only == "all") {
        uiDelete(ctx, plKeyOnly(link.id));
      } else {
        uiPut(ctx, plKeyOnly(link.id), only);
      }
      plReadReply(ctx, link, null)
    }

`walk_hop` with `to: "case_read"`: on to the same opinion read with its whole
case, if the lead belongs to one; otherwise the walkthrough ends here.

    let plWalkHop(ctx: Ctx, link: Link): Response throws Bubble {
      let lw = linksWorks(ctx.db, link);
      let lead = plLeadOf(ctx, lw);
      let collection = lead.collection;
      if (collection != null) {
        webRedirect(ctx, "/cases/${slugPlain(collection)}/read/${lead.slug}?walk=1", null)
      } else {
        uiDelete(ctx, plKeyWalk());
        plReadReply(ctx, link, null)
      }
    }

`relink`: the pass again, on a pair that failed (or any other). The Elixir
`Linker.start`ed it and set the assign to `linking` so the waiting view shows;
the launcher does both.

    let plRelink(ctx: Ctx, link: Link, launcher: LinksLauncher): Response throws Bubble {
      if (!plOwns(ctx, link)) { return plReadReply(ctx, link, plNotYours()); }
      launcher.readLink(ctx, link);
      plReadReply(ctx, link, null)
    }

    let plReadEventOf(ctx: Ctx, link: Link, event: String, payload: JsonObject, launcher: LinksLauncher): Response throws Bubble {
      if (event == "dismiss_tour") {
        uiPut(ctx, plKeyTour(), "0");
        plReadReply(ctx, link, null)
      } else if (event == "show_tour") {
        uiPut(ctx, plKeyTour(), "1");
        plReadReply(ctx, link, null)
      } else if (event == "start_walk") {
        uiPut(ctx, plKeyTour(), "0");
        uiPut(ctx, plKeyWalk(), "on");
        plReadReply(ctx, link, null)
      } else if (event == "end_walk") {
        uiDelete(ctx, plKeyWalk());
        plReadReply(ctx, link, null)
      } else if (event == "walk_hop") {
        plWalkHop(ctx, link)
      } else if (event == "toggle_chat") {
        let chat = pagesLinksChatOf(ctx, link.id);
        plWithChat(ctx, link, new LinksChat(!chat.open, chat.history, chat.cited))
      } else if (event == "close_chat") {
        let chat = pagesLinksChatOf(ctx, link.id);
        plWithChat(ctx, link, new LinksChat(false, chat.history, chat.cited))
      } else if (event == "cite_edge") {
        plCite(ctx, link, payload)
      } else if (event == "uncite") {
        plUncite(ctx, link, payload)
      } else if (event == "chat_send") {
        plChatSend(ctx, link, payload, launcher)
      } else if (event == "relink") {
        plRelink(ctx, link, launcher)
      } else if (event == "set_only") {
        plSetOnly(ctx, link, payload)
      } else {
        console.log("pages_links: /links/:id has no event ${event}");
        bubble()
      }
    }

    export let pagesLinksReadEvent(
      ctx: Ctx, rawId: String, event: String, payload: JsonObject, launcher: LinksLauncher,
    ): Response throws Bubble {
      let id = plInt(rawId);
      if (id != null) {
        let link = linksGet(ctx.db, id);
        if (link != null) {
          plReadEventOf(ctx, link, event, payload, launcher)
        } else { plNoLink(ctx) }
      } else { webNotFound(ctx) }
    }
