# One case: /cases/:slug

`CaseLive.Show`. The case's documents, the way into reading it whole, the ways
into reading it two at a time, and every connection between its documents in a
box that can be sliced: by what a connection says, by which two kinds of
document it joins, and by a search over the reasons and both passages.

A slug that is not a published case is the flash `No such case.` and the list.

    let { Ctx, PageMeta, webRedirect } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, hv, hraw, htext, attr } = import("html/src");
    let { sysUtf8Downcase, sysStringReplace, sysJoin } = import("sys/src");
    let { Work, GraphNode } = import("works/src");
    let { Link, LinkEdgeEnds, linksEdges } = import("links/src");
    let { readingPlain } = import("reading/src");
    let { CaseStudy, casesGet, casesDefaultLead, casesRank, casesCompareText } = import("cases/src");

## State

One connection of the case, with the documents at its ends, the kind of pair
it joins (`dissent+opinion`, the two roles sorted, `?` if either work is
missing) and the text a search looks in.

    export class CasesShowEdge(
      public ends: LinkEdgeEnds,
      public link: Link,
      public fromWork: Work?,
      public toWork: Work?,
      public pair: String,
      public haystack: String,
    ) {}

`q`, `kind` and `pair` are the filters (the empty string or null for none),
`open` the edge whose two passages are showing and `shut` whether the documents
are folded away. `shown` is `all` after the filters.

    export class CasesShowState(
      public study: CaseStudy,
      public all: List<CasesShowEdge>,
      public shown: List<CasesShowEdge>,
      public q: String,
      public kind: String?,
      public pair: String?,
      public open: Int?,
      public shut: Boolean,
    ) {}

### Loading the edges

The order a reader wants them in: what pulls apart first.

    let pgcEdgeRank(t: String): Int {
      if (t == "tension") {
        0
      } else if (t == "answers") {
        1
      } else if (t == "requires") {
        2
      } else if (t == "develops") {
        3
      } else if (t == "pays_off") {
        4
      } else {
        5
      }
    }

    let pgcWorkOf(c: CaseStudy, id: Int): Work? {
      var found: Work? = null;
      var k = 0;
      while (k < c.works.length) {
        if (c.works[k].id == id && found == null) { found = c.works[k]; }
        k += 1;
      }
      found
    }

    let pgcRoleOf(w: Work?): String {
      if (w != null) {
        let r = w.collectionRole;
        if (r != null) { r } else { "?" }
      } else { "?" }
    }

The two roles in alphabetical order, joined by a plus; `?` if either work is
not in the case.

    let pgcPairOf(a: Work?, b: Work?): String {
      if (a == null || b == null) { return "?"; }
      let ra = pgcRoleOf(a);
      let rb = pgcRoleOf(b);
      if (casesCompareText(ra, rb) <= 0) { "${ra}+${rb}" } else { "${rb}+${ra}" }
    }

    let pgcHaystack(e: LinkEdgeEnds): String {
      let parts = new ListBuilder<String>();
      let why = e.edge.rationale;
      if (why != null) { parts.add(why); }
      parts.add(e.from.title);
      parts.add(e.to.title);
      let fq = e.from.quote;
      if (fq != null) { parts.add(fq); }
      let tq = e.to.quote;
      if (tq != null) { parts.add(tq); }
      sysUtf8Downcase(sysJoin(parts.toList(), " "))
    }

    export let pagesCasesShowEdges(ctx: Ctx, c: CaseStudy): List<CasesShowEdge> throws Bubble {
      let out = new ListBuilder<CasesShowEdge>();
      for (let l of c.links) {
        for (let e of linksEdges(ctx.db, l)) {
          let fw = pgcWorkOf(c, e.from.workId);
          let tw = pgcWorkOf(c, e.to.workId);
          out.add(new CasesShowEdge(e, l, fw, tw, pgcPairOf(fw, tw), pgcHaystack(e)));
        }
      }
      out.toList().sorted { (x: CasesShowEdge, y: CasesShowEdge): Int =>
        pgcEdgeRank(x.ends.edge.edgeType) - pgcEdgeRank(y.ends.edge.edgeType)
      }
    }

### Filtering

The three filters together. `q` is trimmed and lower-cased and matched as a
substring of the haystack; `kind` and `pair` are matched exactly.

    export let pagesCasesFilter(all: List<CasesShowEdge>, q: String, kind: String?, pair: String?): List<CasesShowEdge> {
      let needle = pgcLower(q);
      all.filter { (e: CasesShowEdge): Boolean =>
        (kind == null || e.ends.edge.edgeType == kind) &&
        (pair == null || e.pair == pair) &&
        (needle == "" || pagesCasesContains(e.haystack, needle))
      }
    }

    let pgcLower(q: String): String {
      sysUtf8Downcase(pgcTrimmed(q))
    }

    let pgcTrimmed(q: String): String {
      let flat = q.split("\n").join(" ") { (p: String): String => p };
      var start = String.begin;
      while (flat.hasIndex(start) && (flat[start] == 32 || flat[start] == 9)) { start = flat.next(start); }
      var end = start;
      var i = start;
      while (flat.hasIndex(i)) {
        if (flat[i] != 32 && flat[i] != 9) { end = flat.next(i); }
        i = flat.next(i);
      }
      flat.slice(start, end)
    }

    export let loadCasesShow(ctx: Ctx, c: CaseStudy): CasesShowState throws Bubble {
      let slug = c.slug;
      let q = pgcOr(pagesCasesGetKey(ctx, slug, "q"), "");
      let kind = pagesCasesOptional(ctx, slug, "kind");
      let pair = pagesCasesOptional(ctx, slug, "pair");
      let open = pgcOpenId(ctx, slug);
      let all = pagesCasesShowEdges(ctx, c);
      new CasesShowState(c, all, pagesCasesFilter(all, q, kind, pair), q, kind, pair, open, pagesCasesFlag(ctx, slug, "shut"))
    }

    let pgcOr(s: String?, d: String): String {
      if (s != null) { s } else { d }
    }

    let pgcOpenId(ctx: Ctx, slug: String): Int? {
      let s = pagesCasesOptional(ctx, slug, "open");
      if (s == null) { null } else { let n: Int? = do { s.toInt32() } orelse null; n }
    }

## Render

How many of each: the keys in the order of how many they have, most first, ties
in key order.

    class PgcCount(public key: String, public n: Int) {}

    let pgcCounts(keys: List<String>): List<PgcCount> {
      let seen = new MapBuilder<String, Int>();
      let order = new ListBuilder<String>();
      for (let k of keys) {
        if (!seen.has(k)) { seen.set(k, 0); order.add(k); }
        seen.set(k, seen.getOr(k, 0) + 1);
      }
      let sortedKeys = order.toList().sorted { (a: String, b: String): Int => casesCompareText(a, b) };
      sortedKeys
        .map { (k: String): PgcCount => new PgcCount(k, seen.getOr(k, 0)) }
        .sorted { (x: PgcCount, y: PgcCount): Int => y.n - x.n }
    }

`dissent+opinion` as `Dissent ↔ Opinion`.

    export let pagesCasesPairLabel(p: String): String {
      let parts = p.split("+").map { (s: String): String => pagesCasesCapitalize(s) };
      sysJoin(parts, " ↔ ")
    }

    let pgcSpaced(t: String): String { sysStringReplace(t, "_", " ") }

    let pgcFiltered(state: CasesShowState): Boolean {
      state.q != "" || state.kind != null || state.pair != null
    }

A work's slug, for the pairing that leads with it.

    let pgcEnds(c: CaseStudy, l: Link): List<Work> {
      let a = pgcWorkOf(c, l.aWorkId);
      let b = pgcWorkOf(c, l.bWorkId);
      let out = new ListBuilder<Work>();
      if (a != null) { out.add(a); }
      if (b != null) { out.add(b); }
      out.toList().sorted { (x: Work, y: Work): Int => pgcEndRank(x.collectionRole) - pgcEndRank(y.collectionRole) }
    }

    let pgcEndRank(r: String?): Int {
      if (r == "opinion") {
        0
      } else if (r == "concurrence") {
        1
      } else if (r == "dissent") {
        2
      } else if (r == "argument") {
        3
      } else {
        4
      }
    }

    let pgcDoc(w: Work): List<AnyValue> {
      let fi = w.firstImpression;
      h("section", attr("class", pagesCasesCls(["doc", pgcRoleName(w.collectionRole)])), [
        "\n        ",
        h("div", attr("class", "head"), [
          "\n          ",
          h("span", attr("class", "mg-label"), htext(pagesCasesRoleName(w))),
          "\n          ",
          h("span", attr("class", "n"), htext("${w.wordCount.toString()} words")),
          "\n        ",
        ]),
        "\n        ",
        if (fi != null) {
          [h("p", attr("class", "impression"), htext("${pgcSlice340(fi)}…")), "\n        "]
        } else { [] },
        h("a", "${attr("href", "/works/${w.slug}")}${attr("class", "open")}", hraw("Read it →")),
        "\n      ",
      ])
    }

    let pgcRoleName(r: String?): String {
      if (r != null) { r } else { "" }
    }

`String.slice(text, 0, 340)`: the first 340 characters.

    let pgcSlice340(s: String): String {
      var i = String.begin;
      var k = 0;
      while (k < 340 && s.hasIndex(i)) {
        i = s.next(i);
        k += 1;
      }
      s.slice(String.begin, i)
    }

    let pgcWayLink(c: CaseStudy, l: Link): List<AnyValue> {
      let ends = pgcEnds(c, l);
      let lead = if (ends.length > 0) { ends[0].slug } else { "" };
      let a = if (ends.length > 0) { pagesCasesRoleName(ends[0]) } else { "—" };
      let b = if (ends.length > 1) { pagesCasesRoleName(ends[1]) } else { "—" };
      h("a", "${attr("href", "/links/${l.id.toString()}?lead=${lead}")}${attr("class", "way")}", [
        "\n          ",
        h("span", attr("class", "t"), htext("${a} ↔ ${b}")),
        "\n          ",
        h("span", attr("class", "n"), htext("${c.byLink.getOr(l.id, []).length.toString()} connections")),
        "\n        ",
      ])
    }

One connection: the button with the relation, the reason and who it runs
between; open, the two passages and the way into the pair.

    let pgcShowRow(state: CasesShowState, e: CasesShowEdge): List<AnyValue> {
      let ed = e.ends.edge;
      let isOpen = state.open != null && state.open == ed.id;
      let why = ed.rationale;
      h("div", attr("class", pagesCasesCls(["row", ed.edgeType, if (isOpen) { "open" } else { "" }])), [
        "\n          ",
        h("button", "${attr("phx-click", "open")}${attr("phx-value-id", ed.id.toString())}", [
          "\n            ",
          h("span", attr("class", "rel"), htext(pgcSpaced(ed.edgeType))),
          "\n            ",
          h("span", attr("class", "why"), htext(if (why != null) { why } else { "" })),
          "\n            ",
          h("span", attr("class", "who"), htext("${pagesCasesRoleShort(e.fromWork)}→${pagesCasesRoleShort(e.toWork)}")),
          "\n          ",
        ]),
        "\n\n          ",
        if (isOpen) { pgcBoth(e) } else { [] },
        "\n        ",
      ])
    }

    let pgcSide(w: Work?, node: GraphNode): List<AnyValue> {
      h("div", attr("class", "side"), [
        "\n              ",
        h("span", attr("class", "mg-label"), htext("${pagesCasesRoleName(w)} · ${node.title}")),
        "\n              ",
        if (node.quote != null) { h("blockquote", "", htext(readingPlain(node.quote))) } else { [] },
        "\n            ",
      ])
    }

    let pgcBoth(e: CasesShowEdge): List<AnyValue> {
      h("div", attr("class", "both"), [
        "\n            ",
        pgcSide(e.fromWork, e.ends.from),
        "\n            ",
        pgcSide(e.toWork, e.ends.to),
        "\n            ",
        h("a", "${attr("href", "/links/${e.link.id.toString()}")}${attr("class", "read")}", hraw("Read these two side by side →")),
        "\n          ",
      ])
    }

    let pgcDocs(state: CasesShowState): List<AnyValue> {
      if (state.shut) { return []; }
      h("div", attr("class", "cs-docs"), [
        "\n      ",
        state.study.works.map { (w: Work): List<AnyValue> => [pgcDoc(w), "\n      "] },
      ])
    }

The "how many": the shown count, and `of N` when some are filtered out.

    let pgcCount(state: CasesShowState): List<AnyValue> {
      h("span", attr("class", "count"), [
        htext(state.shown.length.toString()),
        if (state.shown.length != state.all.length) {
          h("span", "", htext(" of ${state.all.length.toString()}"))
        } else { [] },
      ])
    }

    let pgcChips(state: CasesShowState): List<AnyValue> {
      let kinds = pgcCounts(state.all.map { (e: CasesShowEdge): String => e.ends.edge.edgeType });
      let pairs = pgcCounts(state.all.map { (e: CasesShowEdge): String => e.pair });
      h("div", attr("class", "chips"), [
        "\n        ",
        kinds.map { (k: PgcCount): List<AnyValue> =>
          [
            h("button", "${attr("class", pagesCasesCls(["chip", k.key, if (state.kind != null && state.kind == k.key) { "on" } else { "" }]))}${attr("phx-click", "kind")}${attr("phx-value-k", k.key)}", [
              htext("${pgcSpaced(k.key)} "), h("span", attr("class", "n"), htext(k.n.toString())),
            ]),
            "\n        ",
          ]
        },
        h("span", "${attr("class", "sep")}${attr("aria-hidden", "true")}", []),
        "\n\n        ",
        pairs.map { (p: PgcCount): List<AnyValue> =>
          [
            h("button", "${attr("class", pagesCasesCls(["chip pair", if (state.pair != null && state.pair == p.key) { "on" } else { "" }]))}${attr("phx-click", "pair")}${attr("phx-value-p", p.key)}", [
              htext("${pagesCasesPairLabel(p.key)} "), h("span", attr("class", "n"), htext(p.n.toString())),
            ]),
            "\n        ",
          ]
        },
        "\n      ",
      ])
    }

    let pgcFind(state: CasesShowState): List<AnyValue> {
      h("div", attr("class", "cs-find"), [
        "\n      ",
        h("div", attr("class", "bar"), [
          "\n        ",
          h("form", "${attr("phx-change", "search")}${attr("class", "q")}${attr("id", "cs-q")}", [
            "\n          ",
            hv("input", "${attr("type", "search")}${attr("name", "q")}${attr("value", state.q)}${attr("placeholder", "Search the reasons and both passages — consent, Humphrey's, stare decisis…")}${attr("phx-debounce", "150")}${attr("autocomplete", "off")}"),
            "\n        ",
          ]),
          "\n        ",
          pgcCount(state),
          "\n        ",
          if (pgcFiltered(state)) { h("button", "${attr("class", "clear")}${attr("phx-click", "clear")}", hraw("clear")) } else { [] },
          "\n      ",
        ]),
        "\n\n      ",
        pgcChips(state),
        "\n\n      ",
        h("div", "${attr("class", "rows")}${attr("id", "edges")}", [
          "\n        ",
          if (state.shown.length == 0) {
            h("p", attr("class", "nothing"), [
              "Nothing matches that. ",
              h("button", attr("phx-click", "clear"), hraw("Clear the filters")),
            ])
          } else { [] },
          "\n\n        ",
          state.shown.map { (e: CasesShowEdge): List<AnyValue> => [pgcShowRow(state, e), "\n        "] },
          "\n      ",
        ]),
        "\n    ",
      ])
    }

    export let renderCasesShow(state: CasesShowState): List<AnyValue> {
      let c = state.study;
      let lead = casesDefaultLeadTitle(c);
      h("div", attr("class", "cs-one"), [
        "\n    ",
        h("div", attr("class", "cs-one-top"), [
          "\n      ",
          h("a", "${attr("href", "/cases")}${attr("class", "back")}", hraw("← all cases")),
          "\n      ",
          h("h1", "", htext(c.name)),
          "\n      ",
          h("span", attr("class", "tally"), [
            "\n        ",
            htext("${c.works.length.toString()} documents · ${pagesCasesCommas(c.words)} words · ${state.all.length.toString()} connections"),
            "\n      ",
          ]),
          "\n      ",
          h("button", "${attr("class", "fold")}${attr("phx-click", "toggle_docs")}", htext(if (state.shut) { "show the documents" } else { "hide the documents" })),
          "\n    ",
        ]),
        "\n\n    ",
        pgcDocs(state),
        "\n\n    ",
        h("div", attr("class", "cs-all"), [
          "\n      ",
          h("a", "${attr("href", "/cases/${c.slug}/read")}${attr("class", "cs-all-go")}", [
            "\n        ",
            h("span", attr("class", "mg-label"), hraw("read the case")),
            "\n        ",
            h("span", attr("class", "t"), htext(lead)),
            "\n        ",
            h("span", attr("class", "s"), htext("with ${(c.works.length - 1).toString()} other documents in the margin — the dissent and the argument on the same paragraph")),
            "\n      ",
          ]),
          "\n    ",
        ]),
        "\n\n    ",
        h("div", attr("class", "cs-go"), [
          "\n      ",
          h("span", attr("class", "mg-label"), hraw("or one against another")),
          "\n      ",
          h("div", attr("class", "ways"), [
            "\n        ",
            c.links.map { (l: Link): List<AnyValue> => [pgcWayLink(c, l), "\n        "] },
            "\n      ",
          ]),
          "\n    ",
        ]),
        "\n\n    ",
        pgcFind(state),
        "\n  ",
      ])
    }

The title of the document a case opens on: the default lead's, else nothing.

    let casesDefaultLeadTitle(c: CaseStudy): String {
      let w = casesDefaultLead(c);
      if (w != null) { w.title } else { "" }
    }

    export let pagesCasesShowMeta(c: CaseStudy): PageMeta {
      new PageMeta(c.name, null, null, "/images/og-cases.png", null, "/cases/${c.slug}")
    }

## GET /cases/:slug

A slug that is not a case is the list, with a flash. A plain visit starts with
no filters and the documents showing, as a mount did.

    export let pagesCasesShowPage(ctx: Ctx, slug: String): Response throws Bubble {
      let c = casesGet(ctx.db, slug);
      if (c != null) {
        if (!ctx.isAjax) { pgcShowReset(ctx, slug); }
        pagesCasesAnswer(ctx, pagesCasesShowMeta(c), renderCasesShow(loadCasesShow(ctx, c)), null, "app")
      } else {
        webRedirect(ctx, "/cases", new Pair("error", "No such case."))
      }
    }

    let pgcShowReset(ctx: Ctx, slug: String): Void {
      pagesCasesDropKey(ctx, slug, "q");
      pagesCasesDropKey(ctx, slug, "kind");
      pagesCasesDropKey(ctx, slug, "pair");
      pagesCasesDropKey(ctx, slug, "open");
      pagesCasesDropKey(ctx, slug, "shut");
    }

## Events

* `search` with `q`: the text, and the connections are recomputed.
* `kind` with `k` and `pair` with `p`: set the filter, or clear it if it was
  that one.
* `clear`: no text, no kind, no pair (the open connection stays open).
* `open` with `id`: show that connection's two passages, or hide them if it was
  the open one.
* `toggle_docs`: fold the documents away, or bring them back.

<!-- -->

    export let pagesCasesShowEvent(ctx: Ctx, slug: String, event: String, payload: JsonObject): Response throws Bubble {
      let c = casesGet(ctx.db, slug);
      if (c != null) {
        pgcShowEvent(ctx, c, event, payload)
      } else {
        webRedirect(ctx, "/cases", new Pair("error", "No such case."))
      }
    }

    let pgcShowEvent(ctx: Ctx, c: CaseStudy, event: String, payload: JsonObject): Response throws Bubble {
      let slug = c.slug;
      if (event == "search") {
        pagesCasesPutKey(ctx, slug, "q", pagesCasesField(payload, "q"));
      } else if (event == "kind") {
        pgcShowToggle(ctx, slug, "kind", pagesCasesField(payload, "k"));
      } else if (event == "pair") {
        pgcShowToggle(ctx, slug, "pair", pagesCasesField(payload, "p"));
      } else if (event == "clear") {
        pagesCasesDropKey(ctx, slug, "q");
        pagesCasesDropKey(ctx, slug, "kind");
        pagesCasesDropKey(ctx, slug, "pair");
      } else if (event == "open") {
        let id = pagesCasesFieldInt(payload, "id");
        let current = pgcOpenId(ctx, slug);
        if (id == null) {
          console.log("pages_cases: /cases/${slug} open without a numeric id");
          bubble()
        } else if (current != null && current == id) {
          pagesCasesDropKey(ctx, slug, "open");
        } else {
          pagesCasesPutKey(ctx, slug, "open", id.toString());
        }
      } else if (event == "toggle_docs") {
        pagesCasesSetFlag(ctx, slug, "shut", !pagesCasesFlag(ctx, slug, "shut"));
      } else {
        return pagesCasesUnhandled("/cases/:slug", event);
      }
      pagesCasesAnswer(ctx, pagesCasesShowMeta(c), renderCasesShow(loadCasesShow(ctx, c)), null, "app")
    }

    let pgcShowToggle(ctx: Ctx, slug: String, name: String, value: String): Void {
      let current = pagesCasesOptional(ctx, slug, name);
      if (current != null && current == value) {
        pagesCasesDropKey(ctx, slug, name);
      } else {
        pagesCasesPutKey(ctx, slug, name, value);
      }
    }
