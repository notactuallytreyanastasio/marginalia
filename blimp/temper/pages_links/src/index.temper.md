# Linked drafts: /links

`LinkLive.Index`. The page that lists every linked pair and makes new ones:
the folded tool that relates a whole folder, the picker that relates two
drafts, the webs the links form (a diagram per group of three or more), the
filter, and the rows, forty at a time.

    let { Ctx, PageMeta, webMeta, webRedirect, uiGet, uiPut, uiDelete } = import("webcore/src");
    let { Response } = import("http/src");
    let { Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { JsonObject, JsonSyntaxTree, JsonArray, JsonString, parseJson } = import("std/json");
    let { h, hv, htext, hraw, attr, classes } = import("html/src");
    let { sysUtf8Downcase, sysByteLength, sysGraphemeTake, sysJoin } = import("sys/src");
    let { Work, worksListWorks, worksGetById } = import("works/src");
    let { Folder, foldersListFolders } = import("folders/src");
    let {
      Link, LinkWorks, LinkStats, LinkCluster, LinkMissing, BulkPair,
      linksForUser, linksClusters, linksLinkable, linksStats, linksEdgeCount, linksGetOrCreate,
      linksName, linksPlainWith, linksBulkIneligible, linksJsonInt, linksJsonField, linksJsonTrimmed,
    } = import("links/src");
    let { runsGet } = import("runs/src");

## State

`@page` is forty: a page of rows, and what "Show N more" adds.

    export let pagesLinksPageSize(): Int { 40 }

What the triage chose, as the page shows it. `pairs` are at most 24, `skipped`
is the model's one sentence on what it left out, `dropped` the proposals that
were thrown away and why.

    export class LinksBulkView(
      public pairs: List<BulkPair>,
      public skipped: String,
      public dropped: List<String>,
    ) {}

`bulkRunning` is a triage or a relate in flight for the chosen folder. `stats`
is held for the linked links of the rows shown only, and `counts` (edges per
link) for the links the webs draw: the Elixir asked every link, which is a
query or three each.

    export class LinksIndexState(
      public folders: List<Folder>,
      public bulk: LinksBulkView?,
      public bulkRunning: Boolean,
      public filter: String,
      public limit: Int,
      public a: Int?,
      public b: Int?,
      public links: List<LinkWorks>,
      public clusters: List<LinkCluster>,
      public drafts: List<Work>,
      public unread: Int,
      public stats: Map<Int, LinkStats>,
      public counts: Map<Int, Int>,
      public flash: Pair<String, String>?,
    ) {}

The UI state this page keeps in the session. A plain visit starts clean (a
LiveView mounted with no filter, no picks and the first page); the folder tool
survives, because its work does.

    let plKeyFilter(): String { "links:filter" }
    let plKeyLimit(): String { "links:limit" }
    let plKeyA(): String { "links:a" }
    let plKeyB(): String { "links:b" }
    let plKeyBulk(): String { "links:bulk" }
    let plKeyBulkFolder(): String { "links:bulk_folder" }
    let plKeyBulkPhase(): String { "links:bulk_phase" }

    let plResetIndex(ctx: Ctx): Void {
      uiDelete(ctx, plKeyFilter());
      uiDelete(ctx, plKeyLimit());
      uiDelete(ctx, plKeyA());
      uiDelete(ctx, plKeyB());
    }

### The folder tool

The triage comes back as JSON in the run's `detail` and is kept in the UI
state as it came, so the tool still shows what it chose while the second stage
runs. The three outcomes a finished run has are settled once, with the flash
the Elixir gave them:

* a triage that failed: `Could not read that folder: <reason>`;
* a relate that finished: the triage is gone and `Started N readings.`;
* a run that crashed: `Crashed: <why>`.

<!-- -->

    class PlBulk(
      public view: LinksBulkView?,
      public running: Boolean,
      public flash: Pair<String, String>?,
    ) {}

    let plStrings(t: JsonSyntaxTree?): List<String> {
      let out = new ListBuilder<String>();
      if (t is JsonArray) {
        for (let x of t.elements) {
          if (x is JsonString) { out.add(x.content); }
        }
      }
      out.toList()
    }

A stored triage as the page shows it. A pair whose draft is gone is left out.

    let plBulkView(db: Db, text: String): LinksBulkView? throws Bubble {
      let tree: JsonSyntaxTree? = parseJson(text) orelse null;
      if (!(tree is JsonObject)) { return null; }
      let out = new ListBuilder<BulkPair>();
      let pairs = linksJsonField(tree, "pairs");
      if (pairs is JsonArray) {
        for (let item of pairs.elements) {
          let a = linksJsonInt(linksJsonField(item, "a"), false);
          let b = linksJsonInt(linksJsonField(item, "b"), false);
          if (a != null) {
            if (b != null) {
              let wa = worksGetById(db, a);
              let wb = worksGetById(db, b);
              if (wa != null) {
                if (wb != null) {
                  out.add(new BulkPair(
                    wa, wb,
                    linksJsonTrimmed(linksJsonField(item, "why")),
                    linksJsonTrimmed(linksJsonField(item, "expect")),
                  ));
                }
              }
            }
          }
        }
      }
      new LinksBulkView(
        out.toList(),
        linksJsonTrimmed(linksJsonField(tree, "skipped")),
        plStrings(linksJsonField(tree, "dropped")),
      )
    }

The error a finished triage reports, or null.

    let plBulkError(text: String): String? {
      let tree: JsonSyntaxTree? = parseJson(text) orelse null;
      let e = linksJsonField(tree, "error");
      if (e is JsonString) { e.content } else { null }
    }

    let plBulkStarted(text: String): Int {
      let tree: JsonSyntaxTree? = parseJson(text) orelse null;
      let n = linksJsonInt(linksJsonField(tree, "started"), false);
      if (n != null) { n } else { 0 }
    }

A run that has finished, for the phase the page started it in: the flash it
leaves, and what it changes in the UI state.

    let plBulkSettle(ctx: Ctx, status: String, detail: String, phase: String): Pair<String, String>? {
      uiDelete(ctx, plKeyBulkPhase());
      if (status != "done") {
        return new Pair("error", "Crashed: ${detail}");
      }
      if (phase == "relate") {
        uiDelete(ctx, plKeyBulk());
        uiDelete(ctx, plKeyBulkFolder());
        return new Pair("info", "Started ${plBulkStarted(detail).toString()} readings.");
      }
      let error = plBulkError(detail);
      if (error != null) {
        new Pair("error", "Could not read that folder: ${error}")
      } else {
        uiPut(ctx, plKeyBulk(), detail);
        null
      }
    }

    let plBulkLoad(ctx: Ctx): PlBulk throws Bubble {
      let folder = plInt(plOrEmpty(uiGet(ctx, plKeyBulkFolder())));
      var running = false;
      var flash: Pair<String, String>? = null;
      if (folder != null) {
        let run = runsGet(ctx.db, pagesLinksBulkKey(folder));
        let phase = plOrEmpty(uiGet(ctx, plKeyBulkPhase()));
        if (run != null) {
          running = run.isRunning();
          if (!running && phase != "") {
            flash = plBulkSettle(ctx, run.status, plOrEmpty(run.detail), phase);
          }
        }
      }
      let stored = uiGet(ctx, plKeyBulk());
      let view: LinksBulkView? = if (stored != null) { plBulkView(ctx.db, stored) } else { null };
      new PlBulk(view, running, flash)
    }

### Loading

Case-insensitive substring of either draft's title.

    let plMatching(links: List<LinkWorks>, q: String): List<LinkWorks> {
      if (q == "") { return links; }
      let needle = sysUtf8Downcase(q);
      let out = new ListBuilder<LinkWorks>();
      for (let lw of links) {
        if (plHas(sysUtf8Downcase(lw.aWork.title), needle) || plHas(sysUtf8Downcase(lw.bWork.title), needle)) {
          out.add(lw);
        }
      }
      out.toList()
    }

    let plTake(links: List<LinkWorks>, n: Int): List<LinkWorks> {
      if (links.length <= n) { links } else { links.slice(0, n) }
    }

    export let pagesLinksWebs(clusters: List<LinkCluster>): List<LinkCluster> {
      let out = new ListBuilder<LinkCluster>();
      for (let c of clusters) {
        if (c.works.length > 2) { out.add(c); }
      }
      out.toList()
    }

    export let loadLinksIndex(ctx: Ctx): LinksIndexState throws Bubble {
      let bulk = plBulkLoad(ctx);
      let links = linksForUser(ctx.db, ctx.scope);
      let clusters = linksClusters(ctx.db, ctx.scope);
      let drafts = linksLinkable(ctx.db, ctx.scope, null);
      var unread = 0;
      for (let w of worksListWorks(ctx.db, ctx.scope)) {
        if (w.status != "read") { unread += 1; }
      }
      let filter = plOrEmpty(uiGet(ctx, plKeyFilter()));
      let limitText = uiGet(ctx, plKeyLimit());
      var limit = pagesLinksPageSize();
      if (limitText != null) {
        let n = plInt(limitText);
        if (n != null) { limit = n; }
      }
      let stats = new MapBuilder<Int, LinkStats>();
      for (let lw of plTake(plMatching(links, filter), limit)) {
        if (lw.link.status == "linked") { stats.set(lw.link.id, linksStats(ctx.db, lw.link)); }
      }
      let counts = new MapBuilder<Int, Int>();
      for (let c of pagesLinksWebs(clusters)) {
        for (let lw of c.links) {
          counts.set(lw.link.id, linksEdgeCount(ctx.db, lw.link.id));
        }
      }
      new LinksIndexState(
        foldersListFolders(ctx.db, ctx.scope), bulk.view, bulk.running, filter, limit,
        plInt(plOrEmpty(uiGet(ctx, plKeyA()))), plInt(plOrEmpty(uiGet(ctx, plKeyB()))),
        links, clusters, drafts, unread, stats.toMap(), counts.toMap(), bulk.flash,
      )
    }

## Render

### Helpers

    let plPlural(n: Int, one: String, many: String): String {
      if (n == 1) { one } else { many }
    }

A float as Elixir printed the coordinates: one decimal, `260.0`. The Elixir
printed the shortest exact form (`429.99999999999994`); the browser reads both
the same.

    export let pagesLinksOneDecimal(x: Float64): String {
      let tenths = (x * 10.0 + 0.5).floor().toInt32() orelse 0;
      "${(tenths / 10).toString()}.${(tenths % 10).toString()}"
    }

`point(i, n)`: the angle is `2π·i/n − π/2` and the point sits on an ellipse of
170 by 105 around (260, 150).

    class PlPoint(public x: Float64, public y: Float64) {}

    let plPoint(i: Int, n: Int): PlPoint {
      let ratio = (i.toFloat64() / n.toFloat64()) orelse 0.0;
      let angle = 2.0 * 3.141592653589793 * ratio - 3.141592653589793 / 2.0;
      new PlPoint(260.0 + 170.0 * angle.cos(), 150.0 + 105.0 * angle.sin())
    }

`short(title)`: the title if it is 32 bytes or fewer, else the first 30
characters and an ellipsis.

    export let pagesLinksShort(title: String): String {
      if (sysByteLength(title) <= 32) { title } else { "${sysGraphemeTake(title, 30)}…" }
    }

    let plLabelY(y: Float64): Float64 {
      if (y > 150.0) { y + 22.0 } else { y - 14.0 }
    }

    let plNoStats(): LinkStats {
      new LinkStats(0, new MapBuilder<String, Int>().toMap(), 0, 0)
    }

Up to three relation kinds of a linked pair: by count, largest first, then by
name. Underscores stay here.

    export let pagesLinksTop(stats: LinkStats): List<Pair<String, Int>> {
      let all = new ListBuilder<Pair<String, Int>>();
      let kinds = stats.byType.keys();
      for (var i = 0; i < kinds.length; ++i) {
        let k = kinds.getOr(i, "");
        all.add(new Pair(k, stats.byType.getOr(k, 0)));
      }
      let sorted = all.toList().sorted { (x: Pair<String, Int>, y: Pair<String, Int>): Int =>
        if (x.value != y.value) { y.value - x.value } else if (x.key < y.key) { -1 } else if (x.key > y.key) { 1 } else { 0 }
      };
      if (sorted.length > 3) { sorted.slice(0, 3) } else { sorted }
    }

### The constellation

One web: a circle of the drafts, a line per link with its edge count, a dashed
line per pair nobody has related yet (drawn as the question it is).
`<line>` and friends are written with a closing tag: inside `<svg>` a start tag
alone opens an element that is never closed.

    let plCoord(p: PlPoint, axis: Int): String {
      pagesLinksOneDecimal(if (axis == 0) { p.x } else { p.y })
    }

    let plAt(points: Map<Int, PlPoint>, id: Int): PlPoint {
      points.getOr(id, new PlPoint(260.0, 150.0))
    }

    let plLine(attrs: String, a: PlPoint, b: PlPoint): List<AnyValue> {
      h("line", "${attrs}${attr("x1", plCoord(a, 0))}${attr("y1", plCoord(a, 1))}${attr("x2", plCoord(b, 0))}${attr("y2", plCoord(b, 1))}", [])
    }

    let plConstellation(c: LinkCluster, counts: Map<Int, Int>): List<AnyValue> {
      let points = new MapBuilder<Int, PlPoint>();
      var i = 0;
      while (i < c.works.length) {
        points.set(c.works[i].id, plPoint(i, c.works.length));
        i += 1;
      }
      let at = points.toMap();
      [
        h("svg", "${attr("class", "lx-svg")}${attr("viewBox", "0 0 520 300")}${attr("preserveAspectRatio", "xMidYMid meet")}", [
          c.missing.map { (m: LinkMissing): List<AnyValue> =>
            plLine(attr("class", "gap"), plAt(at, m.a.id), plAt(at, m.b.id))
          },
          c.links.map { (lw: LinkWorks): List<AnyValue> =>
            let a = plAt(at, lw.link.aWorkId);
            let b = plAt(at, lw.link.bWorkId);
            h("a", "${attr("href", "/links/${lw.link.id.toString()}")}${attr("class", "edge")}", [
              plLine("", a, b),
              h("text", "${attr("x", pagesLinksOneDecimal((a.x + b.x) * 0.5))}${attr("y", pagesLinksOneDecimal((a.y + b.y) * 0.5 - 4.0))}",
                htext(counts.getOr(lw.link.id, 0).toString())),
            ])
          },
          c.works.map { (w: Work): List<AnyValue> =>
            let p = plAt(at, w.id);
            h("a", "${attr("href", "/works/${w.slug}")}${attr("class", "node")}", [
              h("circle", "${attr("cx", plCoord(p, 0))}${attr("cy", plCoord(p, 1))}${attr("r", "7")}", []),
              h("text", "${attr("x", plCoord(p, 0))}${attr("y", pagesLinksOneDecimal(plLabelY(p.y)))}${attr("text-anchor", "middle")}",
                htext(pagesLinksShort(w.title))),
            ])
          },
        ]),
        if (c.missing.length > 0) {
          h("p", attr("class", "lx-gap"), [
            "\nNot related yet:\n",
            c.missing.map { (m: LinkMissing): List<AnyValue> =>
              h("span", attr("class", "pair"), htext("${pagesLinksShort(m.a.title)} ↔ ${pagesLinksShort(m.b.title)}"))
            },
          ])
        } else { [] },
      ]
    }

### The folder tool

`<details>`, rendered only when the user has folders, and open while a triage
is on the page or running. `data-confirm` is on the relate button as in the
HEEx; `blimp.js` asks before sending the click.

    let plBulkOut(s: LinksIndexState, bulk: LinksBulkView): List<AnyValue> {
      let ineligible = linksBulkIneligible(bulk.pairs);
      let relatable = bulk.pairs.length - ineligible.length;
      h("div", attr("class", "lx-bulk-out"), [
        if (bulk.pairs.length == 0) {
          h("p", attr("class", "none"), htext("\nNothing in that folder looked worth relating.\n"))
        } else {
          h("ol", attr("class", "mg-rows"), bulk.pairs.map { (p: BulkPair): List<AnyValue> =>
            h("li", "", [
              h("span", attr("class", "n"), htext(p.expect)),
              "\n",
              h("strong", "", htext(p.a.title)),
              "\n↔ ",
              h("strong", "", htext(p.b.title)),
              "\n",
              h("p", attr("class", "mg-meta"), htext(p.why)),
            ])
          })
        },
        if (bulk.skipped != "") {
          h("p", attr("class", "mg-meta"), htext("\nLeft out: ${bulk.skipped}\n"))
        } else { [] },
        if (bulk.dropped.length > 0) {
          h("p", attr("class", "cut-err"), htext("\n${bulk.dropped.length.toString()} proposal(s) discarded: ${sysJoin(bulk.dropped, "; ")}\n"))
        } else { [] },
        if (ineligible.length > 0) {
          h("p", attr("class", "cut-err"), htext("\n${ineligible.length.toString()} of these cannot be read yet — ${sysJoin(ineligible, "; ")}\n"))
        } else { [] },
        if (bulk.pairs.length > 0 && ineligible.length != bulk.pairs.length) {
          h("button", "${attr("class", "mg-btn sm")}${attr("phx-click", "bulk_relate")}${if (s.bulkRunning) { " disabled" } else { "" }}${attr("data-confirm", "Read each of these pairs against each other? That is one model call per pair.")}",
            htext("\nRelate these ${relatable.toString()}\n"))
        } else { [] },
      ])
    }

    let plBulkTool(s: LinksIndexState): List<AnyValue> {
      if (s.folders.length == 0) { return []; }
      let bulk = s.bulk;
      h("details", "${attr("class", "lx-fold")}${if (bulk != null || s.bulkRunning) { " open" } else { "" }}", [
        "\n",
        h("summary", "", h("span", attr("class", "mg-label"), htext("relate a whole folder"))),
        "\n",
        h("form", "${attr("phx-submit", "bulk_propose")}${attr("class", "lx-bulk-pick")}", [
          "\n",
          h("select", "${attr("name", "folder")}${if (s.bulkRunning) { " disabled" } else { "" }}",
            s.folders.map { (f: Folder): List<AnyValue> =>
              h("option", attr("value", f.id.toString()), htext(f.name))
            }),
          "\n",
          h("button", "${attr("type", "submit")}${attr("class", "mg-btn sm")}${if (s.bulkRunning) { " disabled" } else { "" }}",
            htext(if (s.bulkRunning) { "Reading the folder…" } else { "Work out what to relate" })),
          "\n",
        ]),
        "\n",
        if (bulk != null) { plBulkOut(s, bulk) } else { [] },
      ])
    }

### The picker

One form, two selects. The pick the other select holds is disabled in this one.

    let plPickOptions(drafts: List<Work>, mine: Int?, other: Int?): List<AnyValue> {
      [
        h("option", attr("value", ""), htext("Choose a draft…")),
        drafts.map { (d: Work): List<AnyValue> =>
          h("option", "${attr("value", d.id.toString())}${if (mine != null && mine == d.id) { " selected" } else { "" }}${if (other != null && other == d.id) { " disabled" } else { "" }}",
            htext("${d.title} · ${d.wordCount.toString()}w"))
        },
      ]
    }

    let plMake(s: LinksIndexState): List<AnyValue> {
      h("div", attr("class", "lx-make"), [
        "\n",
        h("span", attr("class", "mg-label"), htext("relate two drafts")),
        "\n",
        if (s.drafts.length < 2) {
          h("p", attr("class", "none"), [
            "\nYou need two drafts that have been read. ",
            h("a", attr("href", "/works/new"), htext("Upload another")),
            ".\n",
          ])
        } else {
          h("form", "${attr("id", "make-link")}${attr("class", "row")}${attr("phx-change", "pick")}${attr("phx-submit", "make")}", [
            "\n",
            h("select", "${attr("id", "pick-a")}${attr("name", "a")}${attr("class", "lx-pick")}", plPickOptions(s.drafts, s.a, s.b)),
            "\n",
            h("span", "${attr("class", "x")}${attr("aria-hidden", "true")}", htext("↔")),
            "\n",
            h("select", "${attr("id", "pick-b")}${attr("name", "b")}${attr("class", "lx-pick")}", plPickOptions(s.drafts, s.b, s.a)),
            "\n",
            h("button", "${attr("type", "submit")}${attr("class", "mg-btn")}${if (s.a == null || s.b == null) { " disabled" } else { "" }}",
              htext("\nLink them\n")),
            "\n",
          ])
        },
        if (s.unread > 0) {
          h("p", attr("class", "none pending"),
            htext("\n${s.unread.toString()} ${plPlural(s.unread, "draft is", "drafts are")} still being read.\nThey can be linked once that finishes.\n"))
        } else { [] },
      ])
    }

### The rows

    let plRow(s: LinksIndexState, lw: LinkWorks): List<AnyValue> {
      let l = lw.link;
      let summary = l.summary;
      let error = l.error;
      let stats = s.stats.getOr(l.id, plNoStats());
      h("a", "${attr("href", "/links/${l.id.toString()}")}${attr("class", "lx-row")}", [
        h("div", attr("class", "min-w-0"), [
          "\n",
          h("span", attr("class", "pair"), [
            htext("${lw.aWork.title} "),
            h("span", attr("class", "x"), htext("↔")),
            htext(" ${lw.bWork.title}"),
          ]),
          "\n",
          if (summary != null) {
            h("p", attr("class", "sum"), htext(linksPlainWith(summary, linksName(lw.aWork.title), linksName(lw.bWork.title))))
          } else { [] },
          if (l.status == "failed") {
            h("p", attr("class", "sum err"), htext(plOrEmpty(error)))
          } else { [] },
          "\n",
        ]),
        h("div", attr("class", "right"), [
          "\n",
          if (l.status == "linked") {
            [
              h("span", attr("class", "n"), htext("${stats.edges.toString()} edges")),
              pagesLinksTop(stats).map { (t: Pair<String, Int>): List<AnyValue> =>
                h("span", attr("class", "k ${t.key}"), htext("${t.key} ${t.value.toString()}"))
              },
            ]
          } else {
            h("span", attr("class", "st ${l.status}"), htext(l.status))
          },
          "\n",
        ]),
      ])
    }

    let plLinked(s: LinksIndexState): List<AnyValue> {
      if (s.links.length == 0) {
        return h("p", attr("class", "none mt-8"), htext("Nothing linked yet."));
      }
      let webs = pagesLinksWebs(s.clusters);
      let found = plMatching(s.links, s.filter);
      let shown = plTake(found, s.limit);
      let left = found.length - shown.length;
      let more = if (left < pagesLinksPageSize()) { left } else { pagesLinksPageSize() };
      [
        if (webs.length > 0) {
          h("details", attr("class", "lx-fold"), [
            "\n",
            h("summary", "", h("span", attr("class", "mg-label"),
              htext("\n${webs.length.toString()} ${plPlural(webs.length, "web", "webs")} of three or more\n"))),
            "\n",
            webs.map { (c: LinkCluster): List<AnyValue> =>
              h("div", attr("class", "lx-web"), [
                h("span", attr("class", "mg-label"), htext("${c.works.length.toString()} drafts, ${c.links.length.toString()} links")),
                plConstellation(c, s.counts),
              ])
            },
          ])
        } else { [] },
        "\n",
        h("form", "${attr("phx-change", "filter")}${attr("id", "lx-filter")}${attr("class", "lx-filter")}", [
          "\n",
          hv("input", "${attr("type", "text")}${attr("name", "q")}${attr("value", s.filter)}${attr("placeholder", "narrow by either draft's title")}${attr("autocomplete", "off")}${attr("phx-debounce", "150")}"),
          "\n",
          h("span", attr("class", "mg-label"), htext("\n${found.length.toString()} of ${s.links.length.toString()} linked\n")),
          "\n",
        ]),
        "\n",
        if (found.length == 0) {
          h("p", attr("class", "none"), htext("\nNothing matches “${s.filter}”.\n"))
        } else { [] },
        shown.map { (lw: LinkWorks): List<AnyValue> => plRow(s, lw) },
        if (left > 0) {
          h("div", attr("class", "lx-more"),
            h("button", "${attr("class", "mg-btn sm")}${attr("phx-click", "more")}", [
              htext("\nShow ${more.toString()} more\n"),
              h("span", attr("class", "mg-meta"), htext("of ${left.toString()} left")),
              "\n",
            ]))
        } else { [] },
      ]
    }

    export let renderLinksIndex(ctx: Ctx, s: LinksIndexState): List<AnyValue> {
      h("div", attr("class", "lx"), [
        "\n",
        h("h1", "", htext("Linked drafts")),
        "\n",
        h("p", attr("class", "lede"), [
          "\nA link relates two drafts' ",
          h("strong", "", htext("maps")),
          " — every beat, the spine, the\nthreads — and draws the edges between them: what develops what, what answers what,\nwhere they argue. Both drafts have to have been read first, because that is what\nproduces the maps.\n",
        ]),
        "\n",
        plBulkTool(s),
        "\n",
        plMake(s),
        "\n",
        plLinked(s),
        "\n",
      ])
    }

## GET /links

`data-poll` while a triage or a relate of the chosen folder is running: the
Elixir learned of it by `start_async` and this page learns by asking.

    let plIndexReply(ctx: Ctx, extra: Pair<String, String>?): Response throws Bubble {
      let state = loadLinksIndex(ctx);
      let flash = if (extra != null) { extra } else { state.flash };
      plRender(ctx, webMeta("Linked drafts"), renderLinksIndex(ctx, state), if (state.bulkRunning) { 2 } else { null }, flash, "app")
    }

    export let pagesLinksIndexPage(ctx: Ctx): Response throws Bubble {
      if (!ctx.isAjax) { plResetIndex(ctx); }
      plIndexReply(ctx, null)
    }

## Events

`bulk_propose` with `folder`: the cheap triage of a folder, away from the
request. An id that is not a number is no folder and nothing happens.

    let plBulkPropose(ctx: Ctx, payload: JsonObject, launcher: LinksLauncher): Response throws Bubble {
      let folder = plPayloadInt(payload, "folder");
      if (folder != null) {
        uiPut(ctx, plKeyBulkFolder(), folder.toString());
        uiPut(ctx, plKeyBulkPhase(), "propose");
        uiDelete(ctx, plKeyBulk());
        launcher.bulkPropose(ctx, folder);
      }
      plIndexReply(ctx, null)
    }

`bulk_relate`: read each pair of the triage on the page against each other, one
model call a pair. Nothing to relate is a no-op.

    let plBulkRelate(ctx: Ctx, launcher: LinksLauncher): Response throws Bubble {
      let folder = plInt(plOrEmpty(uiGet(ctx, plKeyBulkFolder())));
      let stored = uiGet(ctx, plKeyBulk());
      if (folder != null) {
        if (stored != null) {
          let view = plBulkView(ctx.db, stored);
          if (view != null) {
            if (view.pairs.length > 0) {
              uiPut(ctx, plKeyBulkPhase(), "relate");
              launcher.bulkRelate(ctx, folder, view.pairs);
            }
          }
        }
      }
      plIndexReply(ctx, null)
    }

`filter` with `q`: the text, and the first page again. `more`: another page.

    let plFilter(ctx: Ctx, payload: JsonObject): Response throws Bubble {
      uiPut(ctx, plKeyFilter(), plPayloadString(payload, "q"));
      uiDelete(ctx, plKeyLimit());
      plIndexReply(ctx, null)
    }

    let plMore(ctx: Ctx): Response throws Bubble {
      let current = plInt(plOrEmpty(uiGet(ctx, plKeyLimit())));
      let base = if (current != null) { current } else { pagesLinksPageSize() };
      uiPut(ctx, plKeyLimit(), (base + pagesLinksPageSize()).toString());
      plIndexReply(ctx, null)
    }

`pick` with `a` and `b`: either may be `""`, which clears it.

    let plPutPick(ctx: Ctx, key: String, v: Int?): Void {
      if (v != null) { uiPut(ctx, key, v.toString()); } else { uiDelete(ctx, key); }
    }

    let plPick(ctx: Ctx, payload: JsonObject): Response throws Bubble {
      plPutPick(ctx, plKeyA(), plPayloadInt(payload, "a"));
      plPutPick(ctx, plKeyB(), plPayloadInt(payload, "b"));
      plIndexReply(ctx, null)
    }

    let plDraftOf(drafts: List<Work>, id: Int): Boolean {
      var found = false;
      for (let d of drafts) { if (d.id == id) { found = true; } }
      found
    }

`make`: the picks of the submitted form, each falling back to the stored pick
when empty. Two different drafts make (or find) the link, start the pass unless
one is already running, and go to the pair. Anything else is
`Pick two different drafts.`

The Elixir did not check that the drafts were the writer's or read: the picker
only offered those. Anyone could send any two ids; this checks, and says
`Pick two drafts of yours that have been read.` (a difference from the Elixir,
named in the report).

    let plMakeBetween(ctx: Ctx, a: Int, b: Int, launcher: LinksLauncher): Response throws Bubble {
      let drafts = linksLinkable(ctx.db, ctx.scope, null);
      if (!plDraftOf(drafts, a) || !plDraftOf(drafts, b)) {
        return plIndexReply(ctx, new Pair("error", "Pick two drafts of yours that have been read."));
      }
      let made = linksGetOrCreate(ctx.db, a, b);
      let link = made.ok;
      if (link != null) {
        if (link.status != "linking") { launcher.readLink(ctx, link); }
        webRedirect(ctx, "/links/${link.id.toString()}", null)
      } else {
        plIndexReply(ctx, new Pair("error", "Pick two different drafts."))
      }
    }

    let plMakeLink(ctx: Ctx, payload: JsonObject, launcher: LinksLauncher): Response throws Bubble {
      let sentA = plPayloadInt(payload, "a");
      let sentB = plPayloadInt(payload, "b");
      let a = if (sentA != null) { sentA } else { plInt(plOrEmpty(uiGet(ctx, plKeyA()))) };
      let b = if (sentB != null) { sentB } else { plInt(plOrEmpty(uiGet(ctx, plKeyB()))) };
      plPutPick(ctx, plKeyA(), a);
      plPutPick(ctx, plKeyB(), b);
      if (a != null) {
        if (b != null) {
          if (a != b) { return plMakeBetween(ctx, a, b, launcher); }
        }
      }
      plIndexReply(ctx, new Pair("error", "Pick two different drafts."))
    }

    export let pagesLinksIndexEvent(ctx: Ctx, event: String, payload: JsonObject, launcher: LinksLauncher): Response throws Bubble {
      if (event == "bulk_propose") {
        plBulkPropose(ctx, payload, launcher)
      } else if (event == "bulk_relate") {
        plBulkRelate(ctx, launcher)
      } else if (event == "filter") {
        plFilter(ctx, payload)
      } else if (event == "more") {
        plMore(ctx)
      } else if (event == "pick") {
        plPick(ctx, payload)
      } else if (event == "make") {
        plMakeLink(ctx, payload, launcher)
      } else {
        console.log("pages_links: /links has no event ${event}");
        bubble()
      }
    }
