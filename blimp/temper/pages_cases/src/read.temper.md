# One document, read with the case in its margin: /cases/:slug/read[/:lead]

`CaseLive.Read`. The document down the left, its paragraphs in order, and
beside each paragraph the notes every other document of the case has written
against it (and, last, the notes from other cases that reach it), each saying
which document it came from. The layout is `bleed`: the page takes the whole
width.

Who is speaking is filterable (`source`), so is what they are saying (`only`),
quiet stretches fold away, a phone gets a rail of marks that opens a sheet,
and a bubble opens a chat that holds the whole case. A guided walk runs when
the page is opened with `?walk=1`.

What the LiveView kept in the socket lives in the session's UI state, one key
per value under `cases:<slug>:`: `only`, `source`, `peek` (the paragraph whose
sheet is open), `chat_open`, `cited` (edge ids, comma separated), `chat` (the
history, JSON, the last 60 turns) and `walk`. They survive a move to another
document of the same case, as they did across the `patch`. A plain visit
forgets the open sheet and nothing else; it starts the walk if the address
says `?walk=1` and ends it if not.

The reply to a question arrives whole. It is asked inside the event, so
`chat_send` answers once the model has, with the question and the reply in the
history.

    let { Ctx, PageMeta, webRedirect } = import("webcore/src");
    let { Response } = import("http/src");
    let {
      JsonObject, JsonArray, JsonString, JsonSyntaxTree, parseJson, JsonTextProducer, NullInterchangeContext,
    } = import("std/json");
    let { h, hraw, htext, attr } = import("html/src");
    let { markdownToHtml, wordCount } = import("html/src");
    let { sysStringReplace, sysStringTrim, sysJoin } = import("sys/src");
    let { Work } = import("works/src");
    let { LinkEdgeEnds } = import("links/src");
    let { LlmMessage, LlmClient, llmFromEnv } = import("llm/src");
    let {
      ReadingNote, ReadingBlock, ReadingSection, ReadingOptions, readingPage, readingRenderBlock,
    } = import("reading/src");
    let {
      CaseStudy, CaseReading, CaseNote, CaseSource, CaseChatResult, casesGet, casesDefaultLead,
      casesReading, casesChatEdges, casesChatAskLead, casesWalkSteps, CaseSourceEdge, casesCompareText,
    } = import("cases/src");

## State

A block with the margin notes the case wrote against it, in the shape the page
reads (`CaseNote` carries the far end, `ReadingNote` does not).

    export class PgcBlock(public block: ReadingBlock, public notes: List<CaseNote>) {}

    export class PgcSection(public section: ReadingSection, public blocks: List<PgcBlock>) {}

`page` is empty when nothing has been read. `cited` are the ids the chat is
pointing at, `citedEnds` those edges with their two nodes.

    export class CasesReadState(
      public study: CaseStudy,
      public reading: CaseReading?,
      public page: List<PgcSection>,
      public only: String?,
      public source: String?,
      public peek: String?,
      public chatOpen: Boolean,
      public history: List<LlmMessage>,
      public cited: List<Int>,
      public citedEnds: List<LinkEdgeEnds>,
      public walk: Boolean,
    ) {}

### The lead

`:lead` is a work slug. An unknown or absent one is the default lead, with no
404.

    export let pagesCasesLeadOf(c: CaseStudy, leadSlug: String?): Work? {
      var found: Work? = null;
      if (leadSlug != null) {
        var i = 0;
        while (i < c.works.length) {
          if (c.works[i].slug == leadSlug && found == null) { found = c.works[i]; }
          i += 1;
        }
      }
      let hit = found;
      if (hit != null) { hit } else { casesDefaultLead(c) }
    }

### The history

A list of `{"role", "content"}` in a JSON array, the last 60.

    let pgcHistoryCap(): Int { 60 }

    export let pagesCasesHistoryJson(history: List<LlmMessage>): String {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startArray();
      let from = if (history.length > pgcHistoryCap()) { history.length - pgcHistoryCap() } else { 0 };
      var i = from;
      while (i < history.length) {
        p.startObject();
        p.objectKey("role");
        p.stringValue(history[i].role);
        p.objectKey("content");
        p.stringValue(history[i].content);
        p.endObject();
        i += 1;
      }
      p.endArray();
      p.toJsonString() orelse panic()
    }

    export let pagesCasesHistoryOf(text: String?): List<LlmMessage> {
      if (text != null) { pgcHistoryFrom(text) } else { [] }
    }

    let pgcHistoryFrom(text: String): List<LlmMessage> {
      let tree: JsonSyntaxTree? = parseJson(text) orelse null;
      let out = new ListBuilder<LlmMessage>();
      if (tree is JsonArray) {
        for (let item of tree.elements) {
          if (item is JsonObject) {
            let role = item.propertyValueOrNull("role");
            let content = item.propertyValueOrNull("content");
            if (role is JsonString) {
              if (content is JsonString) {
                out.add(new LlmMessage(role.content, content.content));
              }
            }
          }
        }
      }
      out.toList()
    }

### The cited edges

A comma-separated list of ids.

    export let pagesCasesIdsOf(text: String?): List<Int> {
      if (text != null) { pgcIdsFrom(text) } else { [] }
    }

    let pgcIdsFrom(text: String): List<Int> {
      let out = new ListBuilder<Int>();
      let parts = text.split(",");
      var k = 0;
      while (k < parts.length) {
        let n: Int? = pgcIntOf(parts[k]);
        if (n != null) { out.add(n); }
        k += 1;
      }
      out.toList()
    }

    let pgcIntOf(s: String): Int? {
      let n: Int? = do { s.toInt32() } orelse null;
      n
    }

    export let pagesCasesIdsText(ids: List<Int>): String {
      sysJoin(ids.map { (i: Int): String => i.toString() }, ",")
    }

    let pgcHas(ids: List<Int>, id: Int): Boolean {
      var found = false;
      var k = 0;
      while (k < ids.length) {
        if (ids[k] == id) { found = true; }
        k += 1;
      }
      found
    }

### Loading

    let pgcNoteByKey(notes: List<CaseNote>, key: String): CaseNote? {
      var found: CaseNote? = null;
      var k = 0;
      while (k < notes.length) {
        if (notes[k].key == key && found == null) { found = notes[k]; }
        k += 1;
      }
      found
    }

    let pgcReadingNotes(notes: List<CaseNote>): List<ReadingNote> {
      notes.map { (n: CaseNote): ReadingNote =>
        new ReadingNote(n.key, n.sectionId, n.kind, n.quote, n.title, n.body, n.stale)
      }
    }

    let pgcPageOf(all: List<CaseNote>, sections: List<ReadingSection>): List<PgcSection> {
      sections.map { (s: ReadingSection): PgcSection =>
        new PgcSection(s, s.blocks.map { (b: ReadingBlock): PgcBlock =>
          let mine = new ListBuilder<CaseNote>();
          for (let rn of b.notes) {
            let cn = pgcNoteByKey(all, rn.key);
            if (cn != null) { mine.add(cn); }
          }
          new PgcBlock(b, mine.toList())
        })
      }
    }

    export let loadCasesRead(ctx: Ctx, c: CaseStudy, leadSlug: String?): CasesReadState throws Bubble {
      let slug = c.slug;
      let lead = pagesCasesLeadOf(c, leadSlug);
      var reading: CaseReading? = null;
      if (lead != null) { reading = casesReading(ctx.db, c, lead.id); }
      let r = reading;
      var page: List<PgcSection> = [];
      var citedEnds: List<LinkEdgeEnds> = [];
      let cited = pagesCasesIdsOf(pagesCasesGetKey(ctx, slug, "cited"));
      if (r != null) {
        let sections = readingPage(ctx.db, r.lead, new ReadingOptions(null, null, pgcReadingNotes(r.notes)));
        page = pgcPageOf(r.notes, sections);
        if (cited.length > 0) {
          let wanted = new ListBuilder<LinkEdgeEnds>();
          for (let se of casesChatEdges(ctx.db, r)) {
            if (pgcHas(cited, se.ends.edge.id)) { wanted.add(se.ends); }
          }
          citedEnds = wanted.toList();
        }
      }
      new CasesReadState(
        c, r, page,
        pagesCasesOptional(ctx, slug, "only"), pagesCasesOptional(ctx, slug, "source"), pagesCasesOptional(ctx, slug, "peek"),
        pagesCasesFlag(ctx, slug, "chat_open"), pagesCasesHistoryOf(pagesCasesGetKey(ctx, slug, "chat")),
        cited, citedEnds, pagesCasesFlag(ctx, slug, "walk"),
      )
    }

## What the margin shows

`shown?(note, only, source)`: both filters, when set.

    export let pagesCasesNoteShown(n: CaseNote, only: String?, source: String?): Boolean {
      (only == null || n.kind == only) && (source == null || n.fromWork.toString() == source)
    }

    let pgcShownNotes(b: PgcBlock, only: String?, source: String?): List<CaseNote> {
      let out = new ListBuilder<CaseNote>();
      var k = 0;
      while (k < b.notes.length) {
        if (pagesCasesNoteShown(b.notes[k], only, source)) { out.add(b.notes[k]); }
        k += 1;
      }
      out.toList()
    }

### Condensing

A run of the section: one block with its shown notes, or a gap, two or more
blocks nothing else in the case touches.

    export class PgcRun(public gap: Boolean, public blocks: List<PgcBlock>) {}

`condense/3`. A block is kept if it has a shown note or sits next to one; runs
of consecutive blocks with the same answer are cut, and a kept run (or a run
of one) is shown block by block, any other is one gap.

    export let pagesCasesCondense(blocks: List<PgcBlock>, only: String?, source: String?): List<PgcRun> {
      let n = blocks.length;
      let hasList = new ListBuilder<Boolean>();
      var h0 = 0;
      while (h0 < n) {
        hasList.add(pgcShownNotes(blocks[h0], only, source).length > 0);
        h0 += 1;
      }
      let has = hasList.toList();
      let kept = new ListBuilder<Boolean>();
      var i = 0;
      while (i < n) {
        let near = has[i] || (i > 0 && has[i - 1]) || (i + 1 < n && has[i + 1]);
        kept.add(near);
        i += 1;
      }
      let out = new ListBuilder<PgcRun>();
      var start = 0;
      while (start < n) {
        var stop = start + 1;
        while (stop < n && kept[stop] == kept[start]) { stop += 1; }
        let run = blocks.slice(start, stop);
        if (kept[start] || run.length == 1) {
          var r0 = 0;
          while (r0 < run.length) {
            out.add(new PgcRun(false, [run[r0]]));
            r0 += 1;
          }
        } else {
          out.add(new PgcRun(true, run));
        }
        start = stop;
      }
      out.toList()
    }

### Capping

A hub paragraph can draw eighteen notes, which makes a grid row two thousand
pixels tall beside four lines of prose. Five or fewer are all shown. More are
dealt out one document at a time, round robin, in the order the documents first
appear, so the first five are spread across the documents rather than taken in
order; the rest are folded. `cap` is given the `from_work` of each note and
answers the positions to show and the positions to fold.

    export class PgcCap(public shown: List<Int>, public rest: List<Int>) {}

    export let pagesCasesCap(workIds: List<Int>): PgcCap {
      let n = workIds.length;
      let all = new ListBuilder<Int>();
      var k = 0;
      while (k < n) { all.add(k); k += 1; }
      if (n <= 5) { return new PgcCap(all.toList(), []); }
      let order = new ListBuilder<Int>();
      let firsts = new ListBuilder<Int>();
      let groups = new ListBuilder<ListBuilder<Int>>();
      var i = 0;
      while (i < n) {
        var at = -1;
        var g = 0;
        while (g < firsts.length) {
          if (firsts[g] == workIds[i]) { at = g; }
          g += 1;
        }
        if (at < 0) {
          firsts.add(workIds[i]);
          let fresh = new ListBuilder<Int>();
          fresh.add(i);
          groups.add(fresh);
        } else {
          groups[at].add(i);
        }
        i += 1;
      }
      var round = 0;
      while (order.length < n) {
        var gi = 0;
        while (gi < groups.length) {
          if (round < groups[gi].length) { order.add(groups[gi][round]); }
          gi += 1;
        }
        round += 1;
      }
      let ordered = order.toList();
      new PgcCap(ordered.slice(0, 5), ordered.slice(5, n))
    }

    let pgcPick(notes: List<CaseNote>, idx: List<Int>): List<CaseNote> {
      idx.map { (i: Int): CaseNote => notes[i] }
    }

## Render

### Who is speaking

`rank_id(reading, note)` and `elsewhere(reading, note)`: the source whose work
wrote the note.

    let pgcSourceOf(r: CaseReading, n: CaseNote): CaseSource? {
      var found: CaseSource? = null;
      var k = 0;
      while (k < r.sources.length) {
        if (r.sources[k].work.id == n.fromWork && found == null) { found = r.sources[k]; }
        k += 1;
      }
      found
    }

    let pgcRankId(r: CaseReading, n: CaseNote): Int {
      let s = pgcSourceOf(r, n);
      if (s != null) { pagesCasesRank9(s.work.collectionRole) } else { 9 }
    }

    let pgcElsewhere(r: CaseReading, n: CaseNote): String? {
      let s = pgcSourceOf(r, n);
      if (s != null) { s.elsewhere } else { null }
    }

### A note

The far end travels with it: the sentence in the other document, the section it
is in, a way to point the chat at it and the way into the pair.

    let pgcNote(r: CaseReading, n: CaseNote): List<AnyValue> {
      let from = pgcElsewhere(r, n);
      let farQuote = n.farQuote;
      let farSection = n.farSection;
      h("article", attr("class", pagesCasesCls(["cr-note", "s${pgcRankId(r, n).toString()}", if (from != null) { "far" } else { "" }])), [
        "\n  ",
        h("header", "", [
          "\n    ",
          h("span", attr("class", "src"), htext(pagesCasesShortTitle(n.fromTitle))),
          "\n    ",
          h("span", attr("class", "rel k-${n.kind}"), htext(sysStringReplace(n.kind, "_", " "))),
          "\n  ",
        ]),
        "\n  ",
        if (from != null) { [h("p", attr("class", "from"), htext(from)), "\n  "] } else { [] },
        h("p", attr("class", "why"), htext(n.body)),
        "\n  ",
        if (farQuote != null) { [h("blockquote", "", htext(farQuote)), "\n  "] } else { [] },
        h("footer", "", [
          "\n    ",
          if (farSection != null) { [h("span", "", htext("§${farSection.toString()}")), "\n    "] } else { [] },
          h("button", "${attr("phx-click", "cite_edge")}${attr("phx-value-edge", n.edgeId.toString())}${attr("class", "ask")}", hraw("talk about this")),
          "\n    ",
          h("a", attr("href", "/links/${n.linkId.toString()}?lead=${r.lead.slug}"), hraw("read the pair →")),
          "\n  ",
        ]),
        "\n",
      ])
    }

### The bar

Counts of the notes by document and by relation. The count is the useful half:
it says which of the other documents this one is actually arguing with.

    class PgcTally(public work: Work, public n: Int) {}

    let pgcSourceCounts(r: CaseReading): List<PgcTally> {
      let out = new ListBuilder<PgcTally>();
      for (let s of r.sources) {
        var n = 0;
        for (let note of r.notes) {
          if (note.fromWork == s.work.id) { n += 1; }
        }
        if (n > 0) { out.add(new PgcTally(s.work, n)); }
      }
      out.toList()
    }

    class PgcKindTally(public kind: String, public n: Int) {}

    let pgcKindCounts(r: CaseReading): List<PgcKindTally> {
      let seen = new MapBuilder<String, Int>();
      let order = new ListBuilder<String>();
      for (let n of r.notes) {
        if (!seen.has(n.kind)) { seen.set(n.kind, 0); order.add(n.kind); }
        seen.set(n.kind, seen.getOr(n.kind, 0) + 1);
      }
      order.toList()
        .sorted { (a: String, b: String): Int => casesCompareText(a, b) }
        .map { (k: String): PgcKindTally => new PgcKindTally(k, seen.getOr(k, 0)) }
        .sorted { (x: PgcKindTally, y: PgcKindTally): Int => y.n - x.n }
    }

The chip's text: the document's name when it is in this case, the other case's
name when it is not.

    let pgcChipText(w: Work, caseName: String): String {
      let coll = w.collection;
      if (coll != null && coll == caseName) {
        pagesCasesShortTitle(w.title)
      } else if (coll != null) {
        coll
      } else {
        ""
      }
    }

    let pgcSourceChip(state: CasesReadState, t: PgcTally): List<AnyValue> {
      let w = t.work;
      let coll = w.collection;
      let far = coll == null || coll != state.study.name;
      let on = state.source != null && state.source == w.id.toString();
      h("button", "${attr("class", pagesCasesCls(["cr-chip", "s${pagesCasesRank9(w.collectionRole).toString()}", if (far) { "far" } else { "" }, if (on) { "on" } else { "" }]))}${attr("phx-click", "source")}${attr("phx-value-w", w.id.toString())}${attr("title", w.title)}", [
        "\n            ",
        h("span", attr("class", "t"), htext(pgcChipText(w, state.study.name))),
        "\n            ",
        h("span", attr("class", "n"), htext(t.n.toString())),
        "\n          ",
      ])
    }

    let pgcKindChip(state: CasesReadState, k: PgcKindTally): List<AnyValue> {
      let on = state.only != null && state.only == k.kind;
      h("button", "${attr("class", pagesCasesCls(["cr-chip", "k-${k.kind}", if (on) { "on" } else { "" }]))}${attr("phx-click", "only")}${attr("phx-value-k", k.kind)}", [
        "\n            ",
        h("span", attr("class", "t"), htext(sysStringReplace(k.kind, "_", " "))),
        "\n            ",
        h("span", attr("class", "n"), htext(k.n.toString())),
        "\n          ",
      ])
    }

    let pgcPick1(state: CasesReadState, r: CaseReading, w: Work): List<AnyValue> {
      h("a", "${attr("href", "/cases/${state.study.slug}/read/${w.slug}")}${attr("class", pagesCasesCls(["row", if (w.id == r.lead.id) { "here" } else { "" }]))}", [
        "\n                ",
        h("span", attr("class", "t"), htext(w.title)),
        "\n                ",
        h("span", attr("class", "r"), htext(pgcRoleText(w.collectionRole))),
        "\n              ",
      ])
    }

    let pgcRoleText(r: String?): String {
      if (r != null) { r } else { "" }
    }

    let pgcBar(state: CasesReadState, r: CaseReading): List<AnyValue> {
      let study = state.study;
      h("div", attr("class", "cr-bar"), [
        "\n      ",
        h("div", attr("class", "cr-bar-in"), [
          "\n        ",
          h("div", attr("class", "cr-who"), [
            "\n          ",
            h("span", attr("class", "mg-label"), hraw("Reading…")),
            "\n          ",
            h("details", attr("class", "cr-pick"), [
              "\n            ",
              h("summary", "", [
                "\n              ",
                h("span", attr("class", "t"), htext(r.lead.title)),
                "\n              ",
                h("span", attr("class", "n"), htext(study.works.length.toString())),
                "\n            ",
              ]),
              "\n            ",
              h("div", attr("class", "cr-pick-menu"), [
                "\n              ",
                study.works.map { (w: Work): List<AnyValue> => [pgcPick1(state, r, w), "\n              "] },
                "\n            ",
              ]),
              "\n          ",
            ]),
            "\n        ",
          ]),
          "\n\n        ",
          h("div", attr("class", "cr-srcs"), [
            "\n          ",
            h("span", attr("class", "mg-label"), hraw("Against…")),
            "\n          ",
            pgcSourceCounts(r).map { (t: PgcTally): List<AnyValue> => [pgcSourceChip(state, t), "\n          "] },
            "\n        ",
          ]),
          "\n\n        ",
          h("div", attr("class", "cr-kinds"), [
            "\n          ",
            pgcKindCounts(r).map { (k: PgcKindTally): List<AnyValue> => [pgcKindChip(state, k), "\n          "] },
            if (state.only != null || state.source != null) {
              h("button", "${attr("class", "cr-clear")}${attr("phx-click", "clear")}", hraw("clear"))
            } else { [] },
            "\n        ",
          ]),
          "\n      ",
        ]),
        "\n    ",
      ])
    }

### The paragraphs

    let pgcWordsOf(blocks: List<PgcBlock>): Int {
      var n = 0;
      for (let b of blocks) { n += wordCount(b.block.text); }
      n
    }

Prose nothing else in the case touches. Folded, never dropped: a reader must
be able to satisfy themselves that the quiet stretches really are quiet.

    let pgcGap(blocks: List<PgcBlock>): List<AnyValue> {
      h("details", attr("class", "cr-gap"), [
        "\n                ",
        h("summary", "", [
          "\n                  ",
          h("span", attr("class", "n"), htext("${blocks.length.toString()} paragraphs")),
          "\n                  ",
          h("span", attr("class", "w"), htext("${pgcWordsOf(blocks).toString()} words")),
          "\n                  ",
          h("span", attr("class", "s"), hraw("nothing else in the case touches this")),
          "\n                ",
        ]),
        "\n                ",
        blocks.map { (b: PgcBlock): List<AnyValue> =>
          [
            h("div", attr("class", "cr-quiet"), [
              "\n                  ",
              hraw(readingRenderBlock(b.block.text, null, b.block.ref, null)),
              "\n                ",
            ]),
            "\n                ",
          ]
        },
        "\n              ",
      ])
    }

The phone's rail: one mark per relation, up to four, and how many in all.

    let pgcRail(b: PgcBlock, shown: List<CaseNote>): List<AnyValue> {
      if (shown.length == 0) { return []; }
      let ticks = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < shown.length && i < 4) {
        ticks.add(h("span", attr("class", "tick k-${shown[i].kind}"), []));
        i += 1;
      }
      [
        h("button", "${attr("class", "cr-rail")}${attr("phx-click", "peek")}${attr("phx-value-ref", b.block.ref)}${attr("aria-label", "${shown.length.toString()} connections on this paragraph")}", [
          "\n          ",
          ticks.toList(),
          "\n          ",
          h("span", attr("class", "c"), htext(shown.length.toString())),
          "\n        ",
        ]),
        "\n        ",
      ]
    }

    let pgcMore(r: CaseReading, rest: List<CaseNote>): List<AnyValue> {
      if (rest.length == 0) { return []; }
      h("details", attr("class", "cr-more"), [
        "\n          ",
        h("summary", "", htext("${rest.length.toString()} more on this paragraph")),
        "\n          ",
        rest.map { (n: CaseNote): List<AnyValue> => [pgcNote(r, n), "\n          "] },
        "\n        ",
      ])
    }

A paragraph and its notes are one row: the text, then the notes beside it.

    let pgcRow(state: CasesReadState, r: CaseReading, b: PgcBlock): List<AnyValue> {
      let shown = pgcShownNotes(b, state.only, state.source);
      let linked = shown.length > 0;
      let mark = if (linked) { b.block.mark } else { null };
      let split = pagesCasesCap(shown.map { (n: CaseNote): Int => n.fromWork });
      [
        h("div", "${attr("class", pagesCasesCls(["cr-text", if (linked) { "linked" } else { "" }]))}${attr("id", "b-${b.block.ref}")}", [
          "\n                ",
          hraw(readingRenderBlock(b.block.text, mark, b.block.ref, null)),
          "\n              ",
        ]),
        "\n              ",
        h("div", attr("class", pagesCasesCls(["cr-notes", if (linked) { "" } else { "bare" }])), [
          "\n                ",
          pgcPick(shown, split.shown).map { (n: CaseNote): List<AnyValue> => [pgcNote(r, n), "\n                "] },
          "\n                ",
          pgcRail(b, shown),
          pgcMore(r, pgcPick(shown, split.rest)),
          "\n              ",
        ]),
        "\n              ",
      ]
    }

    let pgcRun(state: CasesReadState, r: CaseReading, run: PgcRun): List<AnyValue> {
      if (run.gap) { pgcGap(run.blocks) } else { pgcRow(state, r, run.blocks[0]) }
    }

    let pgcSection(state: CasesReadState, r: CaseReading, s: PgcSection): List<AnyValue> {
      [
        h("div", attr("class", "cr-sechead"), [
          "\n          ",
          h("span", attr("class", "mg-label"), htext("Section ${s.section.section.ordinal.toString()}")),
          "\n          ",
          h("h2", "", htext(s.section.section.title)),
          "\n        ",
        ]),
        "\n\n        ",
        pagesCasesCondense(s.blocks, state.only, state.source).map { (run: PgcRun): List<AnyValue> =>
          [pgcRun(state, r, run), "\n        "]
        },
      ]
    }

### The sheet

What the rail opens: a sheet from the edge the thumb is at, with every note of
the paragraph (not only the ones the filters leave).

    let pgcPeeked(state: CasesReadState): List<CaseNote> {
      let ref = state.peek;
      var found: List<CaseNote> = [];
      if (ref != null) {
        for (let s of state.page) {
          for (let b of s.blocks) {
            if (b.block.ref == ref) { found = b.notes; }
          }
        }
      }
      found
    }

    let pgcSheet(state: CasesReadState, r: CaseReading): List<AnyValue> {
      let notes = pgcPeeked(state);
      if (notes.length == 0) { return []; }
      [
        h("div", "${attr("class", "cr-sheet-veil")}${attr("phx-click", "unpeek")}", [
          "\n    ",
          h("div", "${attr("class", "cr-sheet")}${attr("phx-click-away", "unpeek")}", [
            "\n      ",
            h("div", attr("class", "cr-sheet-head"), [
              "\n        ",
              h("span", attr("class", "mg-label"), hraw("on this paragraph")),
              "\n        ",
              h("button", "${attr("phx-click", "unpeek")}${attr("aria-label", "close")}", hraw("×")),
              "\n      ",
            ]),
            "\n      ",
            notes.map { (n: CaseNote): List<AnyValue> => [pgcNote(r, n), "\n      "] },
            "\n    ",
          ]),
          "\n  ",
        ]),
        "\n\n  ",
      ]
    }

### The page

    export let renderCasesRead(state: CasesReadState): List<AnyValue> {
      let r = state.reading;
      let study = state.study;
      [
        if (state.walk) {
          [
            pagesCasesWalkOverlay(
              casesWalkSteps("case_read"), null,
              "Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would.",
            ),
            "\n\n  ",
          ]
        } else { [] },
        if (r != null) {
          [pagesCasesChatBubble(pagesCasesChatCopy(state.chatOpen, state.history, state.citedEnds)), "\n\n  "]
        } else { [] },
        if (r != null) { pgcSheet(state, r) } else { [] },
        if (r == null) {
          [
            h("div", attr("class", "cr-empty"), [
              "\n    ",
              h("p", "", ["Nothing in ", h("b", "", htext(study.name)), " has been read yet."]),
              "\n    ",
              h("a", "${attr("href", "/cases/${study.slug}")}${attr("class", "mg-btn")}", hraw("Back to the case")),
              "\n  ",
            ]),
            "\n\n  ",
          ]
        } else { [] },
        if (r != null) {
          h("div", attr("class", "cr"), [
            "\n    ",
            pgcBar(state, r),
            "\n\n    ",
            h("div", attr("class", "cr-grid"), [
              "\n      ",
              state.page.map { (s: PgcSection): List<AnyValue> => [pgcSection(state, r, s), "\n      "] },
              "\n    ",
            ]),
            "\n  ",
          ])
        } else { [] },
      ]
    }

The head: the title and description say which document is being read and how
many others are in its margin; with nothing read, only the case's name.

    export let pagesCasesReadMeta(state: CasesReadState): PageMeta {
      let r = state.reading;
      if (r == null) {
        new PageMeta(state.study.name, null, null, null, null, null)
      } else {
        new PageMeta(
          "${r.lead.title} · read against the case",
          "${r.lead.title}, read with ${r.sources.length.toString()} other documents from ${state.study.name} in the margin.",
          null,
          "/images/og-cases.png",
          null,
          "/cases/${state.study.slug}/read/${r.lead.slug}",
        )
      }
    }

## GET /cases/:slug/read[/:lead]

A plain visit shuts a sheet that was open and takes the walk from the address
(`?walk=1` starts it; without, it is over).

    export let pagesCasesReadPage(ctx: Ctx, slug: String, leadSlug: String?): Response throws Bubble {
      let c = casesGet(ctx.db, slug);
      if (c != null) {
        if (!ctx.isAjax) {
          pagesCasesDropKey(ctx, slug, "peek");
          pagesCasesSetFlag(ctx, slug, "walk", ctx.req.query.getOr("walk", "") == "1");
        }
        let state = loadCasesRead(ctx, c, leadSlug);
        pagesCasesAnswer(ctx, pagesCasesReadMeta(state), renderCasesRead(state), null, "bleed")
      } else {
        webRedirect(ctx, "/cases", new Pair("error", "No such case."))
      }
    }

## Events

Thirteen. Twelve are the LiveView's; `close_chat` is the one it lacked (the
bubble's hook pushes it on Escape and on a click outside the panel, and the
LiveView crashed and remounted on it).

* `start_walk`: the walk starts. `end_walk` and `walk_hop`: it ends (the walk's
  last leg is this page, so a hop here just ends it).
* `only` with `k`, `source` with `w`: toggle the filter.
* `clear`: no filters and no sheet.
* `toggle_chat`: open or shut the panel. `close_chat`: shut it.
* `cite_edge` with `edge`: point the chat at that connection, open the panel,
  shut the sheet. `uncite` with `edge`: stop pointing at it.
* `chat_send` with `message`: ask.
* `peek` with `ref`, `unpeek`: the sheet.

<!-- -->

    let pgcToggle(ctx: Ctx, slug: String, name: String, value: String): Void {
      let current = pagesCasesOptional(ctx, slug, name);
      if (current != null && current == value) {
        pagesCasesDropKey(ctx, slug, name);
      } else {
        pagesCasesPutKey(ctx, slug, name, value);
      }
    }

    let pgcCite(ctx: Ctx, slug: String, id: Int): Void {
      let ids = pagesCasesIdsOf(pagesCasesGetKey(ctx, slug, "cited"));
      if (!pgcHas(ids, id)) {
        let more = new ListBuilder<Int>();
        more.addAll(ids);
        more.add(id);
        pagesCasesPutKey(ctx, slug, "cited", pagesCasesIdsText(more.toList()));
      }
      pagesCasesSetFlag(ctx, slug, "chat_open", true);
      pagesCasesDropKey(ctx, slug, "peek");
    }

    let pgcUncite(ctx: Ctx, slug: String, id: Int): Void {
      let ids = pagesCasesIdsOf(pagesCasesGetKey(ctx, slug, "cited"));
      let left = ids.filter { (i: Int): Boolean => i != id };
      if (left.length == 0) {
        pagesCasesDropKey(ctx, slug, "cited");
      } else {
        pagesCasesPutKey(ctx, slug, "cited", pagesCasesIdsText(left));
      }
    }

### Asking

The question is trimmed; an empty one, or one with nothing read, is nothing.
Otherwise the question goes into the history, the model is asked once with the
documents of the case and whatever the reader is pointing at, and the reply (or
the failure, as a flash) is added. The connections the reader was pointing at
are let go either way.

    let pgcAsk(ctx: Ctx, c: CaseStudy, leadSlug: String?, message: String, client: LlmClient?): Pair<String, String>? throws Bubble {
      let text = sysStringTrim(message);
      let lead = pagesCasesLeadOf(c, leadSlug);
      if (lead != null) {
        if (text != "") { pgcAskLead(ctx, c, lead, text, client) } else { null }
      } else { null }
    }

    let pgcAskLead(ctx: Ctx, c: CaseStudy, lead: Work, text: String, client: LlmClient?): Pair<String, String>? throws Bubble {
      let slug = c.slug;
      let history = pagesCasesHistoryOf(pagesCasesGetKey(ctx, slug, "chat"));
      let cited = pagesCasesIdsOf(pagesCasesGetKey(ctx, slug, "cited"));
      let llm: LlmClient = if (client != null) { client } else { llmFromEnv() };
      let answer: CaseChatResult = casesChatAskLead(ctx.db, llm, c, lead.id, history, text, cited);
      let next = new ListBuilder<LlmMessage>();
      next.addAll(history);
      next.add(new LlmMessage("user", text));
      let reply = answer.text;
      var flash: Pair<String, String>? = null;
      if (reply != null) {
        next.add(new LlmMessage("assistant", reply));
      } else {
        let why = answer.error;
        flash = new Pair("error", "That did not go through: ${if (why != null) { why } else { "empty_reply" }}");
      }
      pagesCasesPutKey(ctx, slug, "chat", pagesCasesHistoryJson(next.toList()));
      pagesCasesDropKey(ctx, slug, "cited");
      flash
    }

    export let pagesCasesReadEvent(
      ctx: Ctx, slug: String, leadSlug: String?, event: String, payload: JsonObject, client: LlmClient?,
    ): Response throws Bubble {
      let c = casesGet(ctx.db, slug);
      if (c != null) {
        pgcReadEvent(ctx, c, leadSlug, event, payload, client)
      } else {
        webRedirect(ctx, "/cases", new Pair("error", "No such case."))
      }
    }

    let pgcReadEvent(
      ctx: Ctx, c: CaseStudy, leadSlug: String?, event: String, payload: JsonObject, client: LlmClient?,
    ): Response throws Bubble {
      let slug = c.slug;
      var flash: Pair<String, String>? = null;
      if (event == "start_walk") {
        pagesCasesSetFlag(ctx, slug, "walk", true);
      } else if (event == "end_walk" || event == "walk_hop") {
        pagesCasesSetFlag(ctx, slug, "walk", false);
      } else if (event == "only") {
        pgcToggle(ctx, slug, "only", pagesCasesField(payload, "k"));
      } else if (event == "source") {
        pgcToggle(ctx, slug, "source", pagesCasesField(payload, "w"));
      } else if (event == "clear") {
        pagesCasesDropKey(ctx, slug, "only");
        pagesCasesDropKey(ctx, slug, "source");
        pagesCasesDropKey(ctx, slug, "peek");
      } else if (event == "toggle_chat") {
        pagesCasesSetFlag(ctx, slug, "chat_open", !pagesCasesFlag(ctx, slug, "chat_open"));
      } else if (event == "close_chat") {
        pagesCasesSetFlag(ctx, slug, "chat_open", false);
      } else if (event == "cite_edge") {
        let id = pagesCasesFieldInt(payload, "edge");
        if (id == null) {
          console.log("pages_cases: /cases/${slug}/read cite_edge without a numeric edge");
          bubble()
        } else {
          pgcCite(ctx, slug, id);
        }
      } else if (event == "uncite") {
        let id = pagesCasesFieldInt(payload, "edge");
        if (id == null) {
          console.log("pages_cases: /cases/${slug}/read uncite without a numeric edge");
          bubble()
        } else {
          pgcUncite(ctx, slug, id);
        }
      } else if (event == "chat_send") {
        flash = pgcAsk(ctx, c, leadSlug, pagesCasesField(payload, "message"), client);
      } else if (event == "peek") {
        pagesCasesPutKey(ctx, slug, "peek", pagesCasesField(payload, "ref"));
      } else if (event == "unpeek") {
        pagesCasesDropKey(ctx, slug, "peek");
      } else {
        return pagesCasesUnhandled("/cases/:slug/read", event);
      }
      let state = loadCasesRead(ctx, c, leadSlug);
      pagesCasesAnswer(ctx, pagesCasesReadMeta(state), renderCasesRead(state), flash, "bleed")
    }
