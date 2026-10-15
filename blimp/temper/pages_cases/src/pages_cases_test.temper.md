# Tests for pages_cases

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse` and answered by the group
the way the router would: the scope mounted, the page's own path and query on
the request. The model is `llmFake`.

The fixtures are those of `case_index_test`, `case_page_test`, `case_read_test`
and `cases_tour_test`: an owner, and a case of documents with anchored beats
and the links between them, built through the public functions of `works`,
`cases` and `links`.

    let { Db, dbOpen } = import("db/src");
    let { Request, Response, Match, httpParse, routeMatch } = import("http/src");
    let { Ctx, webNewCtx, webMountCurrentScope, webSessionCookieName } = import("webcore/src");
    let { Scope, User, userColumns, accountsOwnerEmail } = import("accounts/src");
    let {
      Work, GraphNode, NodeParams, workParams, worksCreateWork, worksSetStatus, worksListSections, worksInsertNode,
    } = import("works/src");
    let { Link, linksGetOrCreate, linksSetStatus, linksAttrsSummary, linksStoreEdges, linkerTypes } = import("links/src");
    let { ReadingBlock, ReadingNote } = import("reading/src");
    let { CaseNote, CaseStudy, casesPlace, casesGet, casesWalkSteps } = import("cases/src");
    let { hjoin } = import("html/src");
    let { LlmClient, LlmMessage, llmFake, llmRequests } = import("llm/src");
    let { JsonObject, JsonString, JsonSyntaxTree, JsonArray, parseJson } = import("std/json");
    let { sysJoin } = import("sys/src");

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let expectTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let countOf(s: String, part: String): Int { s.split(part).length - 1 }

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "missing: ${part}\nin: ${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "unexpected: ${part}\nin: ${s}" }
    }

## Fixtures

    let tRepeat(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = tRepeat(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

    let tQuote(): String { "A sentence long enough" }

    let tWork(w: Work?): Work throws Bubble { if (w != null) { w } else { bubble() } }

    let tLink(l: Link?): Link throws Bubble { if (l != null) { l } else { bubble() } }

    let tNode(n: GraphNode?): GraphNode throws Bubble { if (n != null) { n } else { bubble() } }

    let tOwner(db: Db): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [accountsOwnerEmail()]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { new Scope(User.fromRow(row)) } else { bubble() }
    }

    class TMade(public work: Work, public node: GraphNode) {}

A read draft placed in a collection, with one beat anchored to the quote in its
first section. `held` puts a holding sentence in the body.

    let tDoc(db: Db, scope: Scope, title: String, collection: String, role: String, held: Boolean): TMade throws Bubble {
      let sentence = if (held) { " We hold that the removal power is the President's alone." } else { "" };
      let body = "# ${title}\n\n${tQuote()} to be a section.${sentence}\n\n${tRepeat("word ", 30)}";
      let made = tWork(worksCreateWork(db, scope, workParams(title, body)).ok);
      let work = worksSetStatus(db, made, "read", null);
      let placed = casesPlace(db, work, collection, role);
      let section = worksListSections(db, placed.id)[0];
      let p = new NodeParams(placed.id, "beat", "a beat in the ${role}");
      p.sectionId = section.id;
      p.body = "what the ${role} is doing here";
      p.quote = tQuote();
      new TMade(placed, tNode(worksInsertNode(db, p).node))
    }

    let tProposal(from: Int, to: Int, kind: String, why: String): JsonSyntaxTree throws Bubble {
      parseJson("{\"from\": ${from.toString()}, \"to\": ${to.toString()}, \"type\": \"${kind}\", \"why\": \"${why}\"}")
    }

    let tJoin(db: Db, a: TMade, b: TMade, kind: String, why: String, summary: String): Link throws Bubble {
      let made = tLink(linksGetOrCreate(db, a.work.id, b.work.id).ok);
      let linked = tLink(linksSetStatus(db, made, "linked", linksAttrsSummary(summary)).ok);
      let stored = linksStoreEdges(db, linked, [tProposal(a.node.id, b.node.id, kind, why)], linkerTypes());
      if (stored.kept != 1) { bubble() }
      linked
    }

"Some v. Case" as `case_read_test` builds it: argument, opinion and dissent (so
reading order is not id order), the opinion linked to each, and the dissent to
the argument.

    class TFx(
      public db: Db, public owner: Scope, public op: TMade, public di: TMade, public ar: TMade,
      public opDi: Link, public opAr: Link, public diAr: Link,
    ) {}

    let tCase(): TFx throws Bubble {
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let ar = tDoc(db, owner, "Some v. Case — Argument: Counsel", "Some v. Case", "argument", false);
      let op = tDoc(db, owner, "Some v. Case — Opinion", "Some v. Case", "opinion", false);
      let di = tDoc(db, owner, "Some v. Case — Dissent", "Some v. Case", "dissent", false);
      let opDi = tJoin(db, op, di, "tension", "They part on consent.", "tension between them.");
      let opAr = tJoin(db, op, ar, "answers", "The lectern already settled this.", "answers between them.");
      let diAr = tJoin(db, di, ar, "echoes", "Dissent and counsel agree here.", "echoes between them.");
      new TFx(db, owner, op, di, ar, opDi, opAr, diAr)
    }

"Other v. Matter", one opinion linked to the opinion of "Some v. Case".

    class TShared {
      public var fx: TFx? = null;
      public var sl: TSlaughter? = null;
    }

    let tShared = new TShared();

The same fixtures, built once for the tests that only read.

    let tCaseShared(): TFx throws Bubble {
      let have = tShared.fx;
      if (have != null) {
        have
      } else {
        let made = tCase();
        tShared.fx = made;
        made
      }
    }

    let tSlaughterShared(): TSlaughter throws Bubble {
      let have = tShared.sl;
      if (have != null) {
        have
      } else {
        let made = tSlaughter();
        tShared.sl = made;
        made
      }
    }

    let tFar(fx: TFx): TMade throws Bubble {
      let far = tDoc(fx.db, fx.owner, "Other v. Matter — Opinion", "Other v. Matter", "opinion", false);
      tJoin(fx.db, fx.op, far, "echoes", "The same Court on the same clause, three weeks apart.", "Two cases, one question.");
      far
    }

"Trump v. Slaughter" as `case_index_test` builds it, with a record, a holding, a
first impression and a source.

    class TSlaughter(public db: Db, public op: TMade, public di: TMade, public ar: TMade) {}

    let tSlaughter(): TSlaughter throws Bubble {
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let op = tDoc(db, owner, "Trump v. Slaughter — Opinion of the Court", "Trump v. Slaughter", "opinion", true);
      let di = tDoc(db, owner, "Trump v. Slaughter — Dissent (Sotomayor)", "Trump v. Slaughter", "dissent", true);
      let ar = tDoc(db, owner, "Trump v. Slaughter — Argument: Gen. D. John Sauer", "Trump v. Slaughter", "argument", true);
      db.exec(
        "UPDATE works SET first_impression = $1, source_url = $2 WHERE id = $3",
        ["A majority opinion that announces its destination in section one.", "https://www.supremecourt.gov/opinions/25pdf/25-332_new_geil.pdf", op.work.id.toString()],
      );
      tJoin(db, op, di, "tension", "The Court grounds removal in the Framers' single executive; the dissent finds no founding-era support for it.", "They disagree about removal.");
      tJoin(db, op, ar, "echoes", "Sauer's framing.", "Adopted from the lectern.");
      new TSlaughter(db, op, di, ar)
    }

## Requests

    let tRaw(method: String, path: String, extra: String, body: String): Request {
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${body.split("").length.toString()}\r\n\r\n${body}")
    }

    class TRun(public ctx: Ctx, public resp: Response) {}

    let tMatch(method: String, path: String): Match throws Bubble {
      let m = routeMatch(pagesCasesRoutes(), method, path);
      if (m != null) { m } else { bubble() }
    }

    let tCookie(prev: Ctx?): String {
      if (prev != null) { "Cookie: ${webSessionCookieName()}=${prev.session.id}\r\n" } else { "" }
    }

    let tBare(path: String): String { path.split("?")[0] }

A page: the context a plain GET would run in.

    let tGet(db: Db, prev: Ctx?, path: String): TRun throws Bubble {
      let m = tMatch("GET", tBare(path));
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", path, tCookie(prev), ""), m.params);
      webMountCurrentScope(ctx);
      new TRun(ctx, pagesCasesGet(ctx, m))
    }

An event: the request carries the page's path and query and the client header.

    let tEventWith(db: Db, prev: Ctx?, page: String, name: String, payload: String, llm: LlmClient?): TRun throws Bubble {
      let m = tMatch("GET", tBare(page));
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", page, "${tCookie(prev)}X-Requested-With: blimp\r\n", ""), m.params);
      webMountCurrentScope(ctx);
      let tree: JsonSyntaxTree = parseJson(payload);
      if (tree is JsonObject) {
        new TRun(ctx, pagesCasesEventWith(ctx, m, name, tree, llm))
      } else { bubble() }
    }

    let tEvent(db: Db, prev: Ctx?, page: String, name: String, payload: String): TRun throws Bubble {
      tEventWith(db, prev, page, name, payload, null)
    }

The `#main` region of an event's JSON answer, and its flash.

    let tMain(r: Response): String throws Bubble {
      let tree: JsonSyntaxTree = parseJson(r.body);
      if (tree is JsonObject) {
        let regions = tree.propertyValueOrNull("regions");
        if (regions is JsonObject) {
          let main = regions.propertyValueOrNull("#main");
          if (main is JsonString) { main.content } else { bubble() }
        } else { bubble() }
      } else { bubble() }
    }

    let tFlash(r: Response, kind: String): String throws Bubble {
      let tree: JsonSyntaxTree = parseJson(r.body);
      if (tree is JsonObject) {
        let flash = tree.propertyValueOrNull("flash");
        if (flash is JsonObject) {
          let v = flash.propertyValueOrNull(kind);
          if (v is JsonString) { v.content } else { "" }
        } else { "" }
      } else { "" }
    }

    let tRedirect(r: Response): String throws Bubble {
      let tree: JsonSyntaxTree = parseJson(r.body);
      if (tree is JsonObject) {
        let to = tree.propertyValueOrNull("redirect");
        if (to is JsonString) { to.content } else { "" }
      } else { "" }
    }

    let tLocation(r: Response): String {
      var out = "";
      var i = 0;
      while (i < r.headers.length) {
        if (r.headers[i].key == "Location") { out = r.headers[i].value; }
        i += 1;
      }
      out
    }

    let tCount(db: Db, q: String): Int throws Bubble {
      let row = db.one(q, []);
      if (row != null) { row.int("n") } else { -1 }
    }

    let tFails(f: fn (): Void throws Bubble): Boolean {
      let ok = do { f(); true } orelse false;
      !ok
    }

## Pure

    test("plural: one is singular, the rest add an s") { test =>
      expectText(test, pagesCasesPlural(1, "case"), "case");
      expectText(test, pagesCasesPlural(0, "case"), "cases");
      expectText(test, pagesCasesPlural(16, "document"), "documents");
    }

    test("fmt: a thousand and over is k to one decimal") { test =>
      expectText(test, pagesCasesFmt(999), "999");
      expectText(test, pagesCasesFmt(1000), "1.0k");
      expectText(test, pagesCasesFmt(2000), "2.0k");
      expectText(test, pagesCasesFmt(1234), "1.2k");
      expectText(test, pagesCasesFmt(1250), "1.3k");
      expectText(test, pagesCasesFmt(48000), "48.0k");
    }

    test("commas: digits grouped by thousands") { test =>
      expectText(test, pagesCasesCommas(7), "7");
      expectText(test, pagesCasesCommas(999), "999");
      expectText(test, pagesCasesCommas(1000), "1,000");
      expectText(test, pagesCasesCommas(12345), "12,345");
      expectText(test, pagesCasesCommas(1234567), "1,234,567");
    }

    test("pair label: the roles capitalised and joined") { test =>
      expectText(test, pagesCasesPairLabel("dissent+opinion"), "Dissent ↔ Opinion");
      expectText(test, pagesCasesPairLabel("?"), "?");
      expectText(test, pagesCasesCapitalize("ARGUMENT"), "Argument");
    }

    test("span: no date, one year, several") { test =>
      expectText(test, pagesCasesSpan([]), "");
      expectText(test, pagesCasesSpan([2026]), "'s 2025 term");
      expectText(test, pagesCasesSpan([2025, 2026]), "'s 2024–2025 terms");
    }

    test("titles: the part after the first dash, the whole when there is none") { test =>
      expectText(test, pagesCasesShortTitle("Some v. Case — Dissent"), "Dissent");
      expectText(test, pagesCasesShortTitle("No dash here"), "No dash here");
      expectText(test, pagesCasesShortTitle("A — B — C"), "B — C");
    }

    test("rank: the reading order, nine for anything else") { test =>
      expectInt(test, pagesCasesRank9("opinion"), 0);
      expectInt(test, pagesCasesRank9("concurrence"), 1);
      expectInt(test, pagesCasesRank9("dissent"), 2);
      expectInt(test, pagesCasesRank9("argument"), 3);
      expectInt(test, pagesCasesRank9("amicus"), 9);
      expectInt(test, pagesCasesRank9(null), 9);
    }

    test("cls: the empty entries of a class list drop out") { test =>
      expectText(test, pagesCasesCls(["cr-text", "", "linked"]), "cr-text linked");
      expectText(test, pagesCasesCls(["", ""]), "");
    }

    test("routes: the landing page first, then the cases in the router's order") { test =>
      let rs = pagesCasesRoutes();
      expectInt(test, rs.length, 5);
      expectText(test, rs[0].pattern, "/");
      expectText(test, rs[1].pattern, "/cases");
      expectText(test, rs[2].pattern, "/cases/:slug");
      expectText(test, rs[3].pattern, "/cases/:slug/read");
      expectText(test, rs[4].pattern, "/cases/:slug/read/:lead");
      expectTrue(test, hasText(rs[0].name, "public."), "public, so no guest is minted");
    }

    let routesCheck(test: Test): Void throws Bubble {
      let m = routeMatch(pagesCasesRoutes(), "GET", "/cases/some-v-case/read/a-slug");
      expectTrue(test, m != null, "the read route with a lead matches");
      if (m != null) {
        expectText(test, m.params.getOr("slug", "?"), "some-v-case");
        expectText(test, m.params.getOr("lead", "?"), "a-slug");
      }
      let plain = routeMatch(pagesCasesRoutes(), "GET", "/cases/some-v-case/read");
      expectTrue(test, plain != null && !plain.params.has("lead"), "and without one");
      expectTrue(test, routeMatch(pagesCasesRoutes(), "POST", "/cases") == null, "GET only");
    }

    test("routes: the lead is a parameter of the read route") { test => routesCheck(test); }

### The cap

    let capCheck(test: Test): Void throws Bubble {
      let ids = [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3];
      let c = pagesCasesCap(ids);
      expectInt(test, c.shown.length, 5);
      expectInt(test, c.rest.length, 7);
      let seen = new MapBuilder<Int, Boolean>();
      for (let i of c.shown) { seen.set(ids[i], true); }
      expectInt(test, seen.keys().length, 3);
    }

    test("cap: the visible notes are spread across the documents, not taken in order") { test => capCheck(test); }

    let capShortCheck(test: Test): Void throws Bubble {
      let c = pagesCasesCap([1, 1, 1, 1, 1]);
      expectInt(test, c.shown.length, 5);
      expectInt(test, c.rest.length, 0);
      expectInt(test, c.shown[0], 0);
      expectInt(test, c.shown[4], 4);
    }

    test("cap: a short stack is not folded at all") { test => capShortCheck(test); }

    let capLossCheck(test: Test): Void throws Bubble {
      let ids = new ListBuilder<Int>();
      var i = 1;
      while (i <= 18) { ids.add(i % 3); i += 1; }
      let c = pagesCasesCap(ids.toList());
      let all = new ListBuilder<Int>();
      all.addAll(c.shown);
      all.addAll(c.rest);
      let sorted = all.toList().sorted { (a: Int, b: Int): Int => a - b };
      var k = 0;
      while (k < 18) {
        expectInt(test, sorted[k], k);
        k += 1;
      }
    }

    test("cap: nothing is lost to it") { test => capLossCheck(test); }

    let capOrderCheck(test: Test): Void throws Bubble {
      let c = pagesCasesCap([7, 7, 7, 8, 8, 9, 9]);
      expectInt(test, c.shown[0], 0);
      expectInt(test, c.shown[1], 3);
      expectInt(test, c.shown[2], 5);
      expectInt(test, c.shown[3], 1);
      expectInt(test, c.shown[4], 4);
    }

    test("cap: documents take turns in the order they first appear") { test => capOrderCheck(test); }

### Condensing

    let tBlock(ref: String, kinds: List<String>): PgcBlock {
      let rns = kinds.map { (k: String): ReadingNote => new ReadingNote("link:${k}", 1, k, "q", "t", "b", false) };
      let cns = kinds.map { (k: String): CaseNote =>
        new CaseNote("link:${k}", 1, k, "q", "t", "b", false, 1, 2, "ft", null, null, "beat", null, 7, "T", "dissent", null, 3)
      };
      new PgcBlock(new ReadingBlock("text of ${ref}", null, rns, ref), cns)
    }

    let condenseCheck(test: Test): Void throws Bubble {
      let blocks = [
        tBlock("a", []), tBlock("b", []), tBlock("c", []), tBlock("d", []),
        tBlock("e", ["tension"]), tBlock("f", []), tBlock("g", []), tBlock("h", []), tBlock("i", []),
      ];
      let runs = pagesCasesCondense(blocks, null, null);
      expectInt(test, runs.length, 5);
      expectTrue(test, runs[0].gap, "a b c fold");
      expectInt(test, runs[0].blocks.length, 3);
      expectTrue(test, !runs[1].gap, "d, e's neighbour, is shown");
      expectText(test, runs[1].blocks[0].block.ref, "d");
      expectTrue(test, !runs[2].gap, "e, the note");
      expectTrue(test, !runs[3].gap, "f, the other neighbour");
      expectTrue(test, runs[4].gap, "g h i fold");
      expectInt(test, runs[4].blocks.length, 3);
    }

    test("condense: quiet stretches fold, a note's neighbours stay") { test => condenseCheck(test); }

    let condenseLoneCheck(test: Test): Void throws Bubble {
      let blocks = [tBlock("a", ["tension"]), tBlock("b", []), tBlock("c", []), tBlock("d", ["answers"])];
      let runs = pagesCasesCondense(blocks, null, null);
      expectInt(test, runs.length, 4);
      var folded = 0;
      for (let r of runs) { if (r.gap) { folded += 1; } }
      expectInt(test, folded, 0);
    }

    test("condense: a stretch of one block is shown, never folded") { test => condenseLoneCheck(test); }

    let condenseFilterCheck(test: Test): Void throws Bubble {
      let blocks = [
        tBlock("a", ["tension"]), tBlock("b", []), tBlock("c", []), tBlock("d", []), tBlock("e", ["answers"]),
      ];
      let all = pagesCasesCondense(blocks, null, null);
      var gapsAll = 0;
      for (let r of all) { if (r.gap) { gapsAll += 1; } }
      expectInt(test, gapsAll, 0);
      let only = pagesCasesCondense(blocks, "answers", null);
      var gaps = 0;
      for (let r of only) { if (r.gap) { gaps += 1; } }
      expectInt(test, gaps, 1);
      expectInt(test, only[0].blocks.length, 3);
    }

    test("condense: a filter makes more of the page quiet") { test => condenseFilterCheck(test); }

    let shownCheck(test: Test): Void throws Bubble {
      let b = tBlock("a", ["tension"]);
      let n = b.notes[0];
      expectTrue(test, pagesCasesNoteShown(n, null, null), "no filter");
      expectTrue(test, pagesCasesNoteShown(n, "tension", null), "its kind");
      expectTrue(test, !pagesCasesNoteShown(n, "answers", null), "another kind");
      expectTrue(test, pagesCasesNoteShown(n, null, "7"), "its source");
      expectTrue(test, !pagesCasesNoteShown(n, null, "8"), "another source");
      expectTrue(test, !pagesCasesNoteShown(n, "tension", "8"), "both must hold");
    }

    test("shown: the relation and the source filters both apply") { test => shownCheck(test); }

### State kept in the session

    let historyCheck(test: Test): Void throws Bubble {
      let h = [new LlmMessage("user", "Who \"conceded\" what?"), new LlmMessage("assistant", "Line one.\nLine two.")];
      let back = pagesCasesHistoryOf(pagesCasesHistoryJson(h));
      expectInt(test, back.length, 2);
      expectText(test, back[0].role, "user");
      expectText(test, back[0].content, "Who \"conceded\" what?");
      expectText(test, back[1].content, "Line one.\nLine two.");
      expectInt(test, pagesCasesHistoryOf(null).length, 0);
      expectInt(test, pagesCasesHistoryOf("not json").length, 0);
    }

    test("history: JSON in, JSON out, bad JSON is an empty conversation") { test => historyCheck(test); }

    let historyCapCheck(test: Test): Void throws Bubble {
      let many = new ListBuilder<LlmMessage>();
      var i = 0;
      while (i < 75) { many.add(new LlmMessage("user", "m${i.toString()}")); i += 1; }
      let back = pagesCasesHistoryOf(pagesCasesHistoryJson(many.toList()));
      expectInt(test, back.length, 60);
      expectText(test, back[0].content, "m15");
      expectText(test, back[59].content, "m74");
    }

    test("history: only the last sixty turns are kept") { test => historyCapCheck(test); }

    let idsCheck(test: Test): Void throws Bubble {
      expectText(test, pagesCasesIdsText([4, 17, 3]), "4,17,3");
      let back = pagesCasesIdsOf("4,17,3");
      expectInt(test, back.length, 3);
      expectInt(test, back[1], 17);
      expectInt(test, pagesCasesIdsOf(null).length, 0);
      expectInt(test, pagesCasesIdsOf("").length, 0);
    }

    test("ids: a comma-separated list of edge ids") { test => idsCheck(test); }

### Components

    let walkCheck(test: Test): Void throws Bubble {
      let html = hjoin(pagesCasesWalkOverlay(casesWalkSteps("cases"), "cases", "A note &"));
      expectHas(test, html, "id=\"walk\"");
      expectHas(test, html, "phx-hook=\"Walk\"");
      expectHas(test, html, "data-auto=\"cases\"");
      expectHas(test, html, "data-steps=\"");
      expectHas(test, html, "One real disagreement, first");
      expectHas(test, html, "class=\"mg-walk-ring\" hidden");
      expectHas(test, html, "class=\"mg-walk-veil\" hidden");
      expectHas(test, html, "class=\"mg-walk-card\" hidden");
      expectHas(test, html, "class=\"mg-btn sm ghost ml-auto end\"");
      expectHas(test, html, "class=\"mg-walk-safe\">A note &amp;</p>");
      let manual = hjoin(pagesCasesWalkOverlay(casesWalkSteps("case_read"), null, pagesCasesWalkNote()));
      expectLacks(test, manual, "data-auto");
      expectHas(test, manual, "Nothing here is saved, and no model is called");
    }

    test("walk overlay: the ring, the veil, the card, the steps as JSON") { test => walkCheck(test); }

    let bubbleShutCheck(test: Test): Void throws Bubble {
      let html = hjoin(pagesCasesChatBubble(pagesCasesChatCopy(false, [], [])));
      expectHas(test, html, "id=\"linkchat\"");
      expectHas(test, html, "phx-hook=\"LinkChat\"");
      expectHas(test, html, "lc-bubble");
      expectHas(test, html, "phx-click=\"toggle_chat\"");
      expectLacks(test, html, "lc-panel");
      expectLacks(test, html, "class=\"n\"");
    }

    test("chat bubble: shut, it is a button and nothing else") { test => bubbleShutCheck(test); }

    let bubbleOpenCheck(test: Test): Void throws Bubble {
      let html = hjoin(pagesCasesChatBubble(pagesCasesChatCopy(true, [], [])));
      expectHas(test, html, "lc-bubble on");
      expectHas(test, html, "lc-panel");
      expectHas(test, html, "About this case");
      expectLacks(test, html, "About this pair");
      expectHas(test, html, "phx-submit=\"chat_send\"");
      expectHas(test, html, "id=\"lc-form\"");
      expectHas(test, html, "phx-hook=\"LinkChatComposer\"");
      expectHas(test, html, "id=\"lc-body\"");
      expectHas(test, html, "phx-hook=\"StickDown\"");
      expectHas(test, html, "class=\"lc-hint\"");
      expectHas(test, html, "phx-value-message=\"What did the dissent already answer?\"");
      expectHas(test, html, "placeholder=\"How do these sit together?\"");
      expectHas(test, html, "Enter to send");
    }

    test("chat bubble: open, it is a panel about the case with the hint and the openers") { test => bubbleOpenCheck(test); }

    let bubbleTurnsCheck(test: Test): Void throws Bubble {
      let history = [new LlmMessage("user", "Who <won>?"), new LlmMessage("assistant", "The **dissent**.")];
      let open = hjoin(pagesCasesChatBubble(pagesCasesChatCopy(true, history, [])));
      expectHas(test, open, "lc-turn user");
      expectHas(test, open, "Who &lt;won&gt;?");
      expectHas(test, open, "lc-turn assistant");
      expectHas(test, open, "<strong>dissent</strong>");
      expectLacks(test, open, "class=\"lc-hint\"");
      expectLacks(test, open, "lc-openers");
      let shut = hjoin(pagesCasesChatBubble(pagesCasesChatCopy(false, history, [])));
      expectHas(test, shut, "<span class=\"n\">2</span>");
    }

    test("chat bubble: the reader's words are escaped, the reply is markdown, the count shows when shut") { test => bubbleTurnsCheck(test); }

## The landing page

    let landingCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let before = tCount(fx.db, "SELECT count(*) AS n FROM users");
      let r = tGet(fx.db, null, "/").resp;
      expectInt(test, r.status, 200);
      expectInt(test, tCount(fx.db, "SELECT count(*) AS n FROM users"), before);
      expectInt(test, countOf(r.body, "<!DOCTYPE html>"), 1);
      expectHas(test, r.body, "Someone who has actually read the whole thing");
      expectHas(test, r.body, "what a reader leaves in the margin");
      expectHas(test, r.body, "It reads. You decide.");
      expectHas(test, r.body, "<title");
      expectLacks(test, r.body, "menu menu-horizontal");
      expectLacks(test, r.body, "<header class=\"mg-bar\">");
      expectLacks(test, r.body, "id=\"flash-group\"");
      expectHas(test, r.body, "Marginalia");
    }

    test("landing: the pitch and the promise, one document, no app header, no guest") { test => landingCheck(test); }

    let landingVisitorCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let r = tGet(fx.db, null, "/").resp;
      expectHas(test, r.body, "href=\"/works/new\"");
      expectHas(test, r.body, "<a href=\"/users/log-in\">Log in</a>");
      expectHas(test, r.body, "class=\"cta ghost\">Log in</a>");
      expectLacks(test, r.body, "Your drafts");
      expectLacks(test, r.body, "href=\"/users/register\"");
    }

    test("landing: a visitor is offered the upload and a log-in") { test => landingVisitorCheck(test); }

    let landingSignedInCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let m = tMatch("GET", "/");
      let ctx = webNewCtx(fx.db, ":memory:", tRaw("GET", "/", "", ""), m.params);
      ctx.scope = fx.owner;
      let body = pagesCasesGet(ctx, m).body;
      expectHas(test, body, "<a href=\"/works\">Your drafts</a>");
      expectHas(test, body, "href=\"/works/new\"");
      expectLacks(test, body, "href=\"/users/register\"");
      expectLacks(test, body, "class=\"cta ghost\">Log in</a>");
      expectLacks(test, body, "<a href=\"/users/log-in\">Log in</a>");
    }

    test("landing: a signed-in writer is pointed at their drafts, and the upload still goes to /works/new") { test => landingSignedInCheck(test); }

    let landingSectionsCheck(test: Test): Void throws Bubble {
      let html = hjoin(pagesCasesLandingMarkup(false, false));
      expectInt(test, countOf(html, "<section class=\"sec head\" id=\""), 18);
      expectInt(test, countOf(html, "<section class=\"sec head\""), 18);
      expectHas(test, html, "<h1>Someone who has actually read the whole thing.</h1>");
      var i = 0;
      let ids = ["top", "why", "the-read", "anchoring", "margin", "threads", "graph", "rewrites", "editing", "retrieval", "summaries", "changes", "links", "import", "stacks", "reading", "costs", "start"];
      while (i < ids.length) {
        expectHas(test, html, "<section class=\"sec head\" id=\"${ids[i]}\">");
        expectInt(test, countOf(html, "id=\"${ids[i]}\""), 1);
        i += 1;
      }
    }

    test("landing: eighteen sections, each addressable once") { test => landingSectionsCheck(test); }

    let landingMarkupCheck(test: Test): Void throws Bubble {
      let html = hjoin(pagesCasesLandingMarkup(false, false));
      expectTrue(test, countOf(html, "data-reveal") >= 10, "the rail is revealed progressively");
      expectHas(test, html, "style=\"--i:0\"");
      expectHas(test, html, "style=\"--i:2\"");
      expectHas(test, html, "data-demo");
      expectHas(test, html, "data-step=\"1\"");
      expectHas(test, html, "data-step=\"4\"");
      expectHas(test, html, "<del");
      expectHas(test, html, "<ins");
      expectLacks(test, html, "@@");
      expectLacks(test, html, "<.");
      expectLacks(test, html, "phx-no-curly");
      expectLacks(test, html, "<%");
      expectLacks(test, html, "{@");
      expectHas(test, html, "Which thread did I set up and never pay off?");
      expectHas(test, html, "Rewrite my opening paragraph so it hits harder.");
      expectHas(test, html, "Find yours");
      expectHas(test, html, "Try to break it");
      expectHas(test, html, "annotating its own pitch");
      expectHas(test, html, "they read as a contradiction");
      expectHas(test, html, "This section argues with the one before it");
    }

    test("landing: the notes, the worked examples and the reveal markers are in the markup") { test => landingMarkupCheck(test); }

    let landingLinksCheck(test: Test): Void throws Bubble {
      let html = hjoin(pagesCasesLandingMarkup(false, false));
      expectHas(test, html, "<p class=\"seeit\"><a href=\"/drafts/TGokc15wZbB6WGUJuE0Dcg\">");
      expectHas(test, html, "<a href=\"/drafts/Eba9cP98i1LVY5fA8QZtdA\">");
      expectHas(test, html, "<a href=\"/drafts/DhEGqQm_go9N3wm9Y4tCWg/changes\">");
      expectHas(test, html, "<a href=\"/linked\">");
      expectHas(test, html, "href=\"/reading/a-temper-backend-for-blimp-pull-request-stack\"");
      expectHas(test, html, "href=\"/cases\"");
      expectHas(test, html, "href=\"/import\"");
      expectTrue(test, countOf(html, "class=\"seeit\"") >= 6, "a feature described and never shown is a claim");
    }

    test("landing: the example documents and the routes it links to") { test => landingLinksCheck(test); }

    let landingCopyCheck(test: Test): Void throws Bubble {
      let html = hjoin(pagesCasesLandingMarkup(false, false));
      expectHas(test, html, "Where you are in twelve sections");
      expectHas(test, html, "Every change, kept");
      expectHas(test, html, "git log -p");
      expectHas(test, html, "111 stacked pull requests");
      expectHas(test, html, "<b>1</b> find");
      expectHas(test, html, "<b>8</b> compare");
      expectHas(test, html, "<code>@today</code>");
      expectHas(test, html, "<code>stat:closed</code>");
      expectHas(test, html, "No account to upload");
      expectHas(test, html, "private to whoever holds its link");
      expectLacks(test, html, "It never writes a word of your book");
      expectHas(test, html, "<span class=\"tool\">search_manuscript</span>");
    }

    test("landing: the claims the drift guards pin") { test => landingCopyCheck(test); }

    let landingCssCheck(test: Test): Void throws Bubble {
      let css = pagesCasesLandingCss();
      expectInt(test, css.split("\n").length, 307);
      expectTrue(test, hasText(css, "--mg-paper:#fbfaf7"), "the tokens");
      expectTrue(test, hasText(css, ".reveal-ready"), "nothing hides without the class the script adds");
      expectTrue(test, hasText(css, ".notes-only"), "the notes-only mode");
      expectTrue(test, css.split("\n")[0] == "  :root{", "the first line, dedented as in the extract");
    }

    test("landing: the stylesheet is the extract") { test => landingCssCheck(test); }

    let landingStyleCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let r = tGet(fx.db, null, "/").resp;
      expectHas(test, r.body, "<style>\n  :root{");
      expectHas(test, r.body, "--mg-accent:#8a3324; --mg-margin:#f4f1ea;");
      expectHas(test, r.body, "</style>\n<div id=\"landing\" phx-hook=\"Reveal\" class=\"mg\">");
    }

    test("landing: the style element comes first, then div#landing") { test => landingStyleCheck(test); }

    let landingToggleCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/");
      let on = tEvent(fx.db, first.ctx, "/", "toggle_notes", "{}");
      let main = tMain(on.resp);
      expectHas(test, main, "class=\"mg notes-only\"");
      expectHas(test, main, "class=\"mg-toggle on\"");
      expectHas(test, main, "annotating its own pitch");
      expectLacks(test, main, "<!DOCTYPE");
      let off = tEvent(fx.db, on.ctx, "/", "toggle_notes", "{}");
      let main2 = tMain(off.resp);
      expectLacks(test, main2, "class=\"mg notes-only\"");
      expectLacks(test, main2, "class=\"mg-toggle on\"");
      expectHas(test, main2, "class=\"mg\"");
    }

    test("landing: just the notes switches on and off and keeps the notes") { test => landingToggleCheck(test); }

    let landingResetCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/");
      let on = tEvent(fx.db, first.ctx, "/", "toggle_notes", "{}");
      let again = tGet(fx.db, on.ctx, "/");
      expectLacks(test, again.resp.body, "class=\"mg notes-only\"");
      expectHas(test, again.resp.body, "class=\"mg\"");
    }

    test("landing: a plain visit starts with the prose showing, as a mount did") { test => landingResetCheck(test); }

    let landingRegionCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/");
      let on = tEvent(fx.db, first.ctx, "/", "toggle_notes", "{}");
      expectHas(test, on.resp.body, "display:contents");
      expectLacks(test, on.resp.body, "space-y-4");
    }

    test("landing: the event's region is the bare wrapper, not the app's") { test => landingRegionCheck(test); }

    let landingUnknownCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let failed = tFails(fn (): Void throws Bubble { tEvent(fx.db, null, "/", "no_such_event", "{}"); });
      expectTrue(test, failed, "an event the page does not have is not an answer");
    }

    test("landing: an event it does not have stops") { test => landingUnknownCheck(test); }

## /cases

    let indexCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let r = tGet(fx.db, null, "/cases").resp;
      expectInt(test, r.status, 200);
      let b = r.body;
      expectHas(test, b, "The term, read closely");
      expectHas(test, b, "No. 25-332");
      expectHas(test, b, "Argued December 8, 2025");
      expectHas(test, b, "Decided June 29, 2026");
      expectHas(test, b, "question presented");
      expectHas(test, b, "Humphrey&#39;s Executor");
      expectHas(test, b, "the Court, holding");
      expectHas(test, b, "We hold that the removal power is the President&#39;s alone.");
      expectHas(test, b, "constitutes no part of the");
      expectHas(test, b, "The Reporter's syllabus is excluded");
      expectLacks(test, b, "what the Court held");
    }

    test("cases: the record facts, the question and the Court's own sentence are on the card") { test => indexCheck(test); }

    let indexImpressionCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let first = tGet(fx.db, null, "/cases");
      let b = first.resp.body;
      expectHas(test, b, "on reading the opinion");
      expectHas(test, b, "announces its destination in section one");
      expectHas(test, b, "class=\"fi clamped\"");
      expectHas(test, b, "phx-value-slug=\"trump-v-slaughter\"");
      let opened = tEvent(fx.db, first.ctx, "/cases", "impression", "{\"slug\": \"trump-v-slaughter\"}");
      let m = tMain(opened.resp);
      expectLacks(test, m, "fi clamped");
      expectHas(test, m, "class=\"fi\"");
      expectHas(test, m, ">less</button>");
      let shut = tEvent(fx.db, opened.ctx, "/cases", "impression", "{\"slug\": \"trump-v-slaughter\"}");
      expectHas(test, tMain(shut.resp), "fi clamped");
    }

    test("cases: the pass's account of the opinion is clamped until asked, and one at a time") { test => indexImpressionCheck(test); }

    let indexImpressionResetCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let first = tGet(fx.db, null, "/cases");
      let opened = tEvent(fx.db, first.ctx, "/cases", "impression", "{\"slug\": \"trump-v-slaughter\"}");
      let again = tGet(fx.db, opened.ctx, "/cases");
      expectHas(test, again.resp.body, "fi clamped");
    }

    test("cases: a plain visit starts with every clamp shut") { test => indexImpressionResetCheck(test); }

    let indexDocsCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "Argument: Gen. D. John Sauer");
      expectHas(test, b, "Opinion of the Court");
      expectHas(test, b, "supremecourt.gov/opinions/25pdf/25-332_new_geil.pdf");
      expectHas(test, b, "/cases/trump-v-slaughter/read/${fx.ar.work.slug}");
      expectHas(test, b, "class=\"pdf\"");
      expectHas(test, b, "title=\"The PDF this was made from\"");
    }

    test("cases: every document is named and carries its source") { test => indexDocsCheck(test); }

    let indexWaysCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "<ul class=\"cs-ways\">");
      expectHas(test, b, "against");
      expectHas(test, b, "<span class=\"a opinion\">Opinion of the Court</span>");
      expectHas(test, b, "<span class=\"b dissent\">Dissent (Sotomayor)</span>");
      expectHas(test, b, "/links/");
      expectHas(test, b, "?lead=${fx.op.work.slug}");
      expectHas(test, b, "or all 3 at once →");
      expectHas(test, b, "connections →");
    }

    test("cases: the card offers pairings, the opinion leading") { test => indexWaysCheck(test); }

    let indexHookCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "<p class=\"cs-hook\">");
      expectHas(test, b, "no founding-era support");
      expectHas(test, b, "<details class=\"cs-how\"");
      expectHas(test, b, "for instance");
      expectHas(test, b, "read it →");
      expectHas(test, b, "one of <b>1</b> places the documents in");
    }

    test("cases: it opens with one real connection, and the method is folded below") { test => indexHookCheck(test); }

    let indexCountCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "</b> case</span>");
      expectLacks(test, b, "</b> cases</span>");
      expectHas(test, b, "1 case from the Supreme Court");
      expectHas(test, b, "2025 term");
      expectLacks(test, b, "Four cases");
      expectHas(test, b, "<b>3</b> documents");
      expectHas(test, b, "<b>2</b> connections drawn between them");
    }

    test("cases: one case is one case, and the lede counts what it shows") { test => indexCountCheck(test); }

    let indexProvenanceCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "Supreme Court of the United States");
      expectHas(test, b, "verified against the source");
      expectHas(test, b, "a substitute for reading the opinion");
      expectHas(test, b, "<footer class=\"cs-prov\">");
    }

    test("cases: the provenance note says what this is and is not") { test => indexProvenanceCheck(test); }

    let indexTourCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let before = tCount(fx.db, "SELECT count(*) AS n FROM users");
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "id=\"walk\"");
      expectHas(test, b, "data-auto=\"cases\"");
      expectHas(test, b, "One real disagreement, first");
      expectHas(test, b, "Take the tour");
      expectHas(test, b, "mg:walk");
      expectLacks(test, b, "phx-click=\"start_walk\"");
      expectLacks(test, b, "phx-click=\"end_walk\"");
      expectHas(test, b, "Log in");
      expectLacks(test, b, ">guest<");
      expectInt(test, tCount(fx.db, "SELECT count(*) AS n FROM users"), before);
    }

    test("cases: the tour is always on the page, runs in the browser, and mints no account") { test => indexTourCheck(test); }

    let indexMetaCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "<meta property=\"og:title\" content=\"The term, read closely\">");
      expectHas(test, b, "<meta property=\"og:image\" content=\"http://localhost:4000/images/og-cases.png\">");
      expectHas(test, b, "<meta name=\"twitter:image\" content=\"http://localhost:4000/images/og-cases.png\">");
      expectHas(test, b, "dissent arguing with that exact sentence");
      expectHas(test, b, "<meta property=\"og:description\" content=\"1 Supreme Court cases, 3 documents — every opinion");
      expectHas(test, b, "anchored to a sentence in both");
      expectHas(test, b, "<meta property=\"og:url\" content=\"http://localhost:4000/cases\">");
      expectHas(test, b, "<title data-default=");
      expectHas(test, b, ">The term, read closely · Marginalia</title>");
    }

    test("cases: its own title, description, card and address") { test => indexMetaCheck(test); }

    let indexHopCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let first = tGet(fx.db, null, "/cases");
      let hop = tEvent(fx.db, first.ctx, "/cases", "walk_hop", "{\"to\": \"first_pair\"}");
      let to = tRedirect(hop.resp);
      expectHas(test, to, "/links/");
      expectHas(test, to, "?lead=${fx.op.work.slug}&walk=1");
    }

    test("cases: the tour's last step opens the strongest pairing of the first case, with the next leg") { test => indexHopCheck(test); }

    let indexHopOtherCheck(test: Test): Void throws Bubble {
      let fx = tSlaughterShared();
      let failed = tFails(fn (): Void throws Bubble { tEvent(fx.db, null, "/cases", "walk_hop", "{\"to\": \"elsewhere\"}"); });
      expectTrue(test, failed, "any other hop is a bug in the caller");
    }

    test("cases: a hop it does not know stops") { test => indexHopOtherCheck(test); }

    let indexEmptyCheck(test: Test): Void throws Bubble {
      let db = dbOpen(":memory:");
      tOwner(db);
      let b = tGet(db, null, "/cases").resp.body;
      expectHas(test, b, "Nothing here yet.");
      expectHas(test, b, "0 cases from the Supreme Court");
      expectLacks(test, b, "cs-prov");
      expectHas(test, b, "cs-how");
      expectHas(test, b, "Supreme Court cases, read document by document and related to each other.");
      let hop = tEvent(db, null, "/cases", "walk_hop", "{\"to\": \"first_pair\"}");
      expectHas(test, tMain(hop.resp), "Nothing here yet.");
    }

    test("cases: with nothing published it says so, and the tour has nowhere to hop") { test => indexEmptyCheck(test); }

    let indexNoRecordCheck(test: Test): Void throws Bubble {
      let fx = tCase();
      tDoc(fx.db, fx.owner, "Loose ends", "Not a court case", "opinion", false);
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "Not a court case");
      expectHas(test, b, "Some v. Case");
      expectInt(test, countOf(b, "<article class=\"cs-case\">"), 2);
      expectInt(test, countOf(b, "<span class=\"rec\">"), 0);
    }

    test("cases: a collection with no public record still renders") { test => indexNoRecordCheck(test); }

    let indexOpenerCheck(test: Test): Void throws Bubble {
      let fx = tCase();
      tFar(fx);
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "They part on consent.");
      expectHas(test, b, "elsewhere in the term");
      expectHas(test, b, "class=\"k\"");
      expectHas(test, b, "Other v. Matter <span class=\"n\">1</span>");
    }

    test("cases: the opener is the most tense case's tension, and the term argues with itself") { test => indexOpenerCheck(test); }

    let indexRawCheck(test: Test): Void throws Bubble {
      let fx = tCase();
      let ar = tDoc(fx.db, fx.owner, "Lettered v. Case — Opinion", "Lettered v. Case", "opinion", false);
      let di = tDoc(fx.db, fx.owner, "Lettered v. Case — Dissent", "Lettered v. Case", "dissent", false);
      tJoin(fx.db, ar, di, "tension", "Manuscript A grounds it; B does not.", "Manuscript A and B differ.");
      let b = tGet(fx.db, null, "/cases").resp.body;
      expectHas(test, b, "Manuscript A grounds it; B does not.");
    }

    test("cases: the opener and the hook keep the raw reason, A and B unresolved, as the page always showed them") { test => indexRawCheck(test); }

    let indexSpanCheck(test: Test): Void throws Bubble {
      let years = pagesCasesIndexDescription([]);
      expectText(test, years, "Supreme Court cases, read document by document and related to each other.");
    }

    test("cases: the description of nothing") { test => indexSpanCheck(test); }

## /cases/:slug

    let showCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let r = tGet(fx.db, null, "/cases/some-v-case").resp;
      expectInt(test, r.status, 200);
      let b = r.body;
      expectHas(test, b, "Some v. Case");
      expectHas(test, b, "They part on consent.");
      expectLacks(test, b, ">clear<");
      let c = casesGetStudy(fx);
      expectHas(test, b, "3 documents · ${pagesCasesCommas(c.words)} words · 3 connections");
    }

    test("case page: it renders with no filters set") { test => showCheck(test); }

    let showFastTrackCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case").resp.body;
      expectHas(test, b, "or one against another");
      expectHas(test, b, "Opinion ↔ Dissent");
      expectHas(test, b, "lead=${fx.op.work.slug}");
      expectHas(test, b, "href=\"/cases/some-v-case/read\"");
      expectHas(test, b, "with 2 other documents in the margin");
      expectHas(test, b, "read the case");
      expectHas(test, b, "1 connections");
    }

    test("case page: the whole-case read comes before the pairs, which lead with the opinion") { test => showFastTrackCheck(test); }

    let showSearchCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/cases/some-v-case");
      let found = tEvent(fx.db, first.ctx, "/cases/some-v-case", "search", "{\"q\": \"consent\", \"_target\": [\"q\"]}");
      let m = tMain(found.resp);
      expectHas(test, m, "They part on consent.");
      expectLacks(test, m, "The lectern already settled this.");
      expectHas(test, m, ">clear<");
      expectHas(test, m, "1<span> of 3</span>");
      let cleared = tEvent(fx.db, found.ctx, "/cases/some-v-case", "clear", "{}");
      let c = tMain(cleared.resp);
      expectHas(test, c, "The lectern already settled this.");
      expectLacks(test, c, ">clear<");
    }

    test("case page: searching narrows the connections, and clearing brings them back") { test => showSearchCheck(test); }

    let showSearchBothCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let found = tEvent(fx.db, null, "/cases/some-v-case", "search", "{\"q\": \"  A SENTENCE long \"}");
      let m = tMain(found.resp);
      expectHas(test, m, "They part on consent.");
      expectHas(test, m, "The lectern already settled this.");
    }

    test("case page: the search reaches both passages, ignores case and trims") { test => showSearchBothCheck(test); }

    let showKindCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let a = tEvent(fx.db, null, "/cases/some-v-case", "kind", "{\"k\": \"tension\"}");
      let m = tMain(a.resp);
      expectHas(test, m, "They part on consent.");
      expectLacks(test, m, "The lectern already settled this.");
      expectHas(test, m, "chip tension on");
      let b = tEvent(fx.db, a.ctx, "/cases/some-v-case", "kind", "{\"k\": \"tension\"}");
      expectHas(test, tMain(b.resp), "The lectern already settled this.");
    }

    test("case page: slicing by relation, and toggling it off again") { test => showKindCheck(test); }

    let showPairCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case").resp.body;
      expectHas(test, b, "Dissent ↔ Opinion <span class=\"n\">1</span>");
      expectHas(test, b, "Argument ↔ Dissent <span class=\"n\">1</span>");
      expectHas(test, b, "phx-value-p=\"dissent+opinion\"");
      let a = tEvent(fx.db, null, "/cases/some-v-case", "pair", "{\"p\": \"dissent+opinion\"}");
      let m = tMain(a.resp);
      expectHas(test, m, "They part on consent.");
      expectLacks(test, m, "Dissent and counsel agree here.");
      expectHas(test, m, "chip pair on");
    }

    test("case page: slicing by which two kinds of document a connection joins") { test => showPairCheck(test); }

    let showNothingCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let a = tEvent(fx.db, null, "/cases/some-v-case", "search", "{\"q\": \"zzzzz\"}");
      let m = tMain(a.resp);
      expectHas(test, m, "Nothing matches that.");
      expectHas(test, m, "Clear the filters");
    }

    test("case page: a search matching nothing says so") { test => showNothingCheck(test); }

    let showOpenCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/cases/some-v-case");
      let b = first.resp.body;
      expectLacks(test, b, "class=\"both\"");
      expectHas(test, b, "phx-click=\"open\"");
      let edgeId = tCount(fx.db, "SELECT id AS n FROM link_edges WHERE rationale = 'They part on consent.'");
      let opened = tEvent(fx.db, first.ctx, "/cases/some-v-case", "open", "{\"id\": \"${edgeId.toString()}\"}");
      let m = tMain(opened.resp);
      expectHas(test, m, "class=\"both\"");
      expectHas(test, m, "Opinion · a beat in the opinion");
      expectHas(test, m, "Dissent · a beat in the dissent");
      expectHas(test, m, "<blockquote>A sentence long enough</blockquote>");
      expectHas(test, m, "Read these two side by side →");
      expectHas(test, m, "row tension open");
      expectHas(test, m, "Op→Diss");
      let shut = tEvent(fx.db, opened.ctx, "/cases/some-v-case", "open", "{\"id\": \"${edgeId.toString()}\"}");
      expectLacks(test, tMain(shut.resp), "class=\"both\"");
    }

    test("case page: a connection opens to its two passages, and shuts") { test => showOpenCheck(test); }

    let showDocsCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/cases/some-v-case");
      expectHas(test, first.resp.body, "class=\"cs-docs\"");
      expectHas(test, first.resp.body, "hide the documents");
      expectHas(test, first.resp.body, "/works/${fx.op.work.slug}");
      expectHas(test, first.resp.body, "class=\"doc opinion\"");
      let folded = tEvent(fx.db, first.ctx, "/cases/some-v-case", "toggle_docs", "{}");
      let m = tMain(folded.resp);
      expectLacks(test, m, "class=\"cs-docs\"");
      expectHas(test, m, "show the documents");
      let again = tEvent(fx.db, folded.ctx, "/cases/some-v-case", "toggle_docs", "{}");
      expectHas(test, tMain(again.resp), "class=\"cs-docs\"");
    }

    test("case page: the documents fold away and come back") { test => showDocsCheck(test); }

    let showNamesCheck(test: Test): Void throws Bubble {
      let fx = tCase();
      tDoc(fx.db, fx.owner, "Some v. Case — Argument: Amit Agarwal", "Some v. Case", "argument", false);
      let b = tGet(fx.db, null, "/cases/some-v-case").resp.body;
      expectHas(test, b, "Argument: Amit Agarwal");
      expectHas(test, b, "Argument: Counsel");
      expectLacks(test, b, ">Oral argument<");
    }

    test("case page: each document is named by what distinguishes it") { test => showNamesCheck(test); }

    let showUnknownCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let run = tGet(fx.db, null, "/cases/nope");
      expectInt(test, run.resp.status, 303);
      expectText(test, tLocation(run.resp), "/cases");
      let list = tGet(fx.db, run.ctx, "/cases");
      expectHas(test, list.resp.body, "No such case.");
    }

    test("case page: an unknown case sends you back to the list with a flash") { test => showUnknownCheck(test); }

    let showUnknownEventCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let run = tEvent(fx.db, null, "/cases/nope", "clear", "{}");
      expectText(test, tRedirect(run.resp), "/cases");
    }

    test("case page: an event for a case that is gone redirects too") { test => showUnknownEventCheck(test); }

    let showMetaCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case").resp.body;
      expectHas(test, b, "<meta property=\"og:title\" content=\"Some v. Case\">");
      expectHas(test, b, "<meta property=\"og:url\" content=\"http://localhost:4000/cases/some-v-case\">");
      expectHas(test, b, "<link rel=\"canonical\" href=\"http://localhost:4000/cases/some-v-case\">");
      expectHas(test, b, "/images/og-cases.png");
      expectHas(test, b, "Upload a draft. It reads end to end");
    }

    test("case page: its own title and address, the product's pitch for a description") { test => showMetaCheck(test); }

    let showResetCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let a = tEvent(fx.db, null, "/cases/some-v-case", "search", "{\"q\": \"consent\"}");
      let again = tGet(fx.db, a.ctx, "/cases/some-v-case");
      expectHas(test, again.resp.body, "The lectern already settled this.");
      expectLacks(test, again.resp.body, ">clear<");
    }

    test("case page: a plain visit starts with no filters, as a mount did") { test => showResetCheck(test); }

## /cases/:slug/read

    let readCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let r = tGet(fx.db, null, "/cases/some-v-case/read").resp;
      expectInt(test, r.status, 200);
      let b = r.body;
      expectHas(test, b, "Reading…");
      expectHas(test, b, "Some v. Case — Opinion");
      expectHas(test, b, "They part on consent.");
      expectHas(test, b, "The lectern already settled this.");
      expectLacks(test, b, "Dissent and counsel agree here.");
    }

    test("case read: the opinion is read with both other documents in one margin") { test => readCheck(test); }

    let readNotesCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case/read").resp.body;
      expectHas(test, b, "<span class=\"src\">Dissent</span>");
      expectHas(test, b, "<span class=\"src\">Argument: Counsel</span>");
      expectHas(test, b, "<blockquote>A sentence long enough</blockquote>");
      expectHas(test, b, "<span class=\"rel k-tension\">tension</span>");
      expectHas(test, b, "<span class=\"rel k-answers\">answers</span>");
      expectHas(test, b, "class=\"cr-note s2\"");
      expectHas(test, b, "class=\"cr-note s3\"");
      expectHas(test, b, "talk about this");
      expectHas(test, b, "read the pair →");
      expectHas(test, b, "?lead=${fx.op.work.slug}");
      expectHas(test, b, "<span>§1</span>");
    }

    test("case read: each note says which document it came from and carries the far passage") { test => readNotesCheck(test); }

    let readLayoutCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case/read").resp.body;
      expectHas(test, b, "<main id=\"main\" class=\"\">");
      expectHas(test, b, "<div class=\"cr\">");
      expectHas(test, b, "class=\"cr-grid\"");
      expectHas(test, b, "class=\"cr-sechead\"");
      expectHas(test, b, "<span class=\"mg-label\">Section 1</span>");
      expectHas(test, b, "Some v. Case — Opinion…</h2>");
      expectHas(test, b, "class=\"cr-text\" id=\"b-s1p0\"");
      expectHas(test, b, "class=\"cr-text linked\" id=\"b-s1p1\"");
      expectHas(test, b, "<mark id=\"anchor-s1p1\">A sentence long enough</mark>");
      expectHas(test, b, "<details class=\"cr-pick\">");
      expectHas(test, b, "class=\"row here\"");
      expectHas(test, b, "<span class=\"n\">3</span>");
      expectLacks(test, b, "id=\"walk\"");
    }

    test("case read: the bleed layout, the grid, the highlighted anchor, the document picker") { test => readLayoutCheck(test); }

    let tLongDoc(db: Db, scope: Scope, title: String, role: String): TMade throws Bubble {
      let body = "# ${title}\n\n${tQuote()} to be a section.\n\nSecond paragraph here.\n\nThird paragraph here.\n\nFourth paragraph here.\n\nFifth paragraph here.";
      let made = tWork(worksCreateWork(db, scope, workParams(title, body)).ok);
      let work = worksSetStatus(db, made, "read", null);
      let placed = casesPlace(db, work, "Long v. Case", role);
      let section = worksListSections(db, placed.id)[0];
      let p = new NodeParams(placed.id, "beat", "a beat in the ${role}");
      p.sectionId = section.id;
      p.quote = tQuote();
      new TMade(placed, tNode(worksInsertNode(db, p).node))
    }

    let readGapCheck(test: Test): Void throws Bubble {
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let op = tLongDoc(db, owner, "Long v. Case — Opinion", "opinion");
      let di = tLongDoc(db, owner, "Long v. Case — Dissent", "dissent");
      tJoin(db, op, di, "tension", "They part.", "tension.");
      let b = tGet(db, null, "/cases/long-v-case/read").resp.body;
      expectHas(test, b, "<details class=\"cr-gap\">");
      expectHas(test, b, "<span class=\"n\">3 paragraphs</span>");
      expectHas(test, b, "<span class=\"w\">9 words</span>");
      expectHas(test, b, "nothing else in the case touches this");
      expectHas(test, b, "<div class=\"cr-quiet\">");
      expectHas(test, b, "Fifth paragraph here.");
      expectHas(test, b, "class=\"cr-notes bare\"");
    }

    test("case read: the quiet stretch folds, with its size on the label") { test => readGapCheck(test); }

    let readChipsCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case/read").resp.body;
      expectHas(test, b, "Against…");
      expectHas(test, b, "phx-value-w=\"${fx.di.work.id.toString()}\"");
      expectHas(test, b, "phx-value-w=\"${fx.ar.work.id.toString()}\"");
      expectHas(test, b, "phx-value-k=\"answers\"");
      expectHas(test, b, "phx-value-k=\"tension\"");
      expectHas(test, b, "cr-chip s2");
      expectHas(test, b, "cr-chip k-tension");
      expectLacks(test, b, "cr-clear");
      expectHas(test, b, "title=\"Some v. Case — Dissent\"");
    }

    test("case read: a chip for each document that has something to say, and each relation") { test => readChipsCheck(test); }

    let readSourceCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/cases/some-v-case/read");
      let w = fx.di.work.id.toString();
      let narrowed = tEvent(fx.db, first.ctx, "/cases/some-v-case/read", "source", "{\"w\": \"${w}\"}");
      let m = tMain(narrowed.resp);
      expectHas(test, m, "They part on consent.");
      expectLacks(test, m, "The lectern already settled this.");
      expectHas(test, m, "cr-clear");
      expectHas(test, m, "cr-chip s2 on");
      let again = tEvent(fx.db, narrowed.ctx, "/cases/some-v-case/read", "clear", "{}");
      let c = tMain(again.resp);
      expectHas(test, c, "The lectern already settled this.");
      expectLacks(test, c, "cr-clear");
    }

    test("case read: a source chip narrows the margin to one document, and clear brings it back") { test => readSourceCheck(test); }

    let readOnlyCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let a = tEvent(fx.db, null, "/cases/some-v-case/read", "only", "{\"k\": \"answers\"}");
      let m = tMain(a.resp);
      expectHas(test, m, "The lectern already settled this.");
      expectLacks(test, m, "They part on consent.");
      let off = tEvent(fx.db, a.ctx, "/cases/some-v-case/read", "only", "{\"k\": \"answers\"}");
      expectHas(test, tMain(off.resp), "They part on consent.");
    }

    test("case read: a relation chip narrows the margin to one kind, and again lets go") { test => readOnlyCheck(test); }

    let readLeadCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case/read/${fx.ar.work.slug}").resp.body;
      expectHas(test, b, "Some v. Case — Argument: Counsel");
      expectHas(test, b, "The lectern already settled this.");
      expectHas(test, b, "Dissent and counsel agree here.");
      expectLacks(test, b, "They part on consent.");
    }

    test("case read: any document in the case can be the one you read") { test => readLeadCheck(test); }

    let readUnknownLeadCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case/read/no-such-document").resp.body;
      expectHas(test, b, "Some v. Case — Opinion");
      expectHas(test, b, "They part on consent.");
    }

    test("case read: an unknown lead is the default lead, not a 404") { test => readUnknownLeadCheck(test); }

    let readFarCheck(test: Test): Void throws Bubble {
      let fx = tCase();
      tFar(fx);
      let b = tGet(fx.db, null, "/cases/some-v-case/read").resp.body;
      expectHas(test, b, "The same Court on the same clause");
      expectHas(test, b, "<p class=\"from\">Other v. Matter</p>");
      expectHas(test, b, "cr-note s0 far");
      expectHas(test, b, "<span class=\"t\">Other v. Matter</span>");
      expectHas(test, b, "cr-chip s0 far");
      let narrowed = tEvent(fx.db, null, "/cases/some-v-case/read", "source", "{\"w\": \"${fx.di.work.id.toString()}\"}");
      expectLacks(test, tMain(narrowed.resp), "The same Court on the same clause");
    }

    test("case read: a note from another case says so, its chip names the case, and a filter leaves it out") { test => readFarCheck(test); }

    let readRailCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case/read").resp.body;
      expectHas(test, b, "class=\"cr-rail\"");
      expectHas(test, b, "<span class=\"tick k-tension\">");
      expectHas(test, b, "<span class=\"tick k-answers\">");
      expectHas(test, b, "2 connections on this paragraph");
      expectHas(test, b, "<span class=\"c\">2</span>");
      expectHas(test, b, "phx-value-ref=\"s1p1\"");
    }

    test("case read: every linked paragraph carries a rail with its relations on it") { test => readRailCheck(test); }

    let readSheetCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/cases/some-v-case/read");
      expectLacks(test, first.resp.body, "class=\"cr-sheet\"");
      let peeked = tEvent(fx.db, first.ctx, "/cases/some-v-case/read", "peek", "{\"ref\": \"s1p1\"}");
      let m = tMain(peeked.resp);
      expectHas(test, m, "class=\"cr-sheet\"");
      expectHas(test, m, "on this paragraph");
      expectHas(test, m, "They part on consent.");
      expectHas(test, m, "phx-click-away=\"unpeek\"");
      let gone = tEvent(fx.db, peeked.ctx, "/cases/some-v-case/read", "unpeek", "{}");
      expectLacks(test, tMain(gone.resp), "class=\"cr-sheet\"");
    }

    test("case read: tapping the rail opens that paragraph's notes, and closing dismisses them") { test => readSheetCheck(test); }

    let readSheetFilterCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let a = tEvent(fx.db, null, "/cases/some-v-case/read", "source", "{\"w\": \"${fx.di.work.id.toString()}\"}");
      let b = tEvent(fx.db, a.ctx, "/cases/some-v-case/read", "peek", "{\"ref\": \"s1p1\"}");
      let sheet = tMain(b.resp);
      expectHas(test, sheet, "class=\"cr-sheet\"");
      expectHas(test, sheet, "The lectern already settled this.");
      let c = tEvent(fx.db, b.ctx, "/cases/some-v-case/read", "clear", "{}");
      expectLacks(test, tMain(c.resp), "class=\"cr-sheet\"");
    }

    test("case read: the sheet shows every note of the paragraph, and clear dismisses it") { test => readSheetFilterCheck(test); }

    let readSheetResetCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let a = tEvent(fx.db, null, "/cases/some-v-case/read", "peek", "{\"ref\": \"s1p1\"}");
      let again = tGet(fx.db, a.ctx, "/cases/some-v-case/read");
      expectLacks(test, again.resp.body, "class=\"cr-sheet\"");
    }

    test("case read: a plain visit shuts a sheet that was open") { test => readSheetResetCheck(test); }

    let chatToggleCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let first = tGet(fx.db, null, "/cases/some-v-case/read");
      expectHas(test, first.resp.body, "lc-bubble");
      expectLacks(test, first.resp.body, "lc-panel");
      let open = tEvent(fx.db, first.ctx, "/cases/some-v-case/read", "toggle_chat", "{}");
      let m = tMain(open.resp);
      expectHas(test, m, "lc-panel");
      expectHas(test, m, "About this case");
      expectLacks(test, m, "About this pair");
      expectHas(test, m, "phx-submit=\"chat_send\"");
      let shut = tEvent(fx.db, open.ctx, "/cases/some-v-case/read", "toggle_chat", "{}");
      expectLacks(test, tMain(shut.resp), "lc-panel");
    }

    test("case read: the bubble opens a panel about the case, and shuts it") { test => chatToggleCheck(test); }

    let chatCloseCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let open = tEvent(fx.db, null, "/cases/some-v-case/read", "toggle_chat", "{}");
      expectHas(test, tMain(open.resp), "lc-panel");
      let closed = tEvent(fx.db, open.ctx, "/cases/some-v-case/read", "close_chat", "{}");
      expectLacks(test, tMain(closed.resp), "lc-panel");
      let nothing = tEvent(fx.db, closed.ctx, "/cases/some-v-case/read", "close_chat", "{}");
      expectLacks(test, tMain(nothing.resp), "lc-panel");
    }

    test("case read: close_chat, the Escape key, shuts the panel instead of crashing the page") { test => chatCloseCheck(test); }

    let chatCiteCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let edgeId = tCount(fx.db, "SELECT id AS n FROM link_edges WHERE rationale = 'They part on consent.'");
      let first = tGet(fx.db, null, "/cases/some-v-case/read");
      expectHas(test, first.resp.body, "phx-click=\"cite_edge\"");
      expectHas(test, first.resp.body, "phx-value-edge=\"${edgeId.toString()}\"");
      let cited = tEvent(fx.db, first.ctx, "/cases/some-v-case/read", "cite_edge", "{\"edge\": \"${edgeId.toString()}\"}");
      let m = tMain(cited.resp);
      expectHas(test, m, "lc-panel");
      expectHas(test, m, "lc-cited");
      expectHas(test, m, "pointing at");
      expectHas(test, m, "a beat in the opinion ↔ a beat in the dissent");
      expectHas(test, m, "phx-click=\"uncite\"");
      let twice = tEvent(fx.db, cited.ctx, "/cases/some-v-case/read", "cite_edge", "{\"edge\": \"${edgeId.toString()}\"}");
      expectInt(test, countOf(tMain(twice.resp), "phx-click=\"uncite\""), 1);
      let gone = tEvent(fx.db, twice.ctx, "/cases/some-v-case/read", "uncite", "{\"edge\": \"${edgeId.toString()}\"}");
      expectLacks(test, tMain(gone.resp), "lc-cited");
    }

    test("case read: a note carries its connection into the chat, once, and it can be taken out") { test => chatCiteCheck(test); }

    let chatAskCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let llm = llmFake(["{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"The **dissent** answered it.\"},\"finish_reason\":\"stop\"}]}"]);
      let open = tEvent(fx.db, null, "/cases/some-v-case/read", "toggle_chat", "{}");
      let asked = tEventWith(fx.db, open.ctx, "/cases/some-v-case/read", "chat_send", "{\"message\": \"  Who conceded what?  \"}", llm);
      let m = tMain(asked.resp);
      expectHas(test, m, "Who conceded what?");
      expectHas(test, m, "<strong>dissent</strong> answered it.");
      expectHas(test, m, "lc-turn user");
      expectHas(test, m, "lc-turn assistant");
      expectLacks(test, m, "class=\"lc-hint\"");
      expectInt(test, llmRequests(llm).length, 1);
      expectHas(test, llmRequests(llm)[0], "Who conceded what?");
      expectHas(test, llmRequests(llm)[0], "THE DOCUMENT BEING READ");
      expectText(test, tFlash(asked.resp, "error"), "");
    }

    test("case read: asking puts the question and the reply in the conversation, one model call") { test => chatAskCheck(test); }

    let chatKeepsCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let llm = llmFake(["{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"First answer.\"},\"finish_reason\":\"stop\"}]}", "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Second answer.\"},\"finish_reason\":\"stop\"}]}"]);
      let open = tEvent(fx.db, null, "/cases/some-v-case/read", "toggle_chat", "{}");
      let one = tEventWith(fx.db, open.ctx, "/cases/some-v-case/read", "chat_send", "{\"message\": \"One?\"}", llm);
      let two = tEventWith(fx.db, one.ctx, "/cases/some-v-case/read", "chat_send", "{\"message\": \"Two?\"}", llm);
      let m = tMain(two.resp);
      expectHas(test, m, "One?");
      expectHas(test, m, "First answer.");
      expectHas(test, m, "Two?");
      expectHas(test, m, "Second answer.");
      expectHas(test, llmRequests(llm)[1], "First answer.");
      let moved = tGet(fx.db, two.ctx, "/cases/some-v-case/read/${fx.di.work.slug}");
      expectHas(test, moved.resp.body, "Second answer.");
    }

    test("case read: the conversation grows, reaches the model, and survives a move to another document") { test => chatKeepsCheck(test); }

    let chatFailCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let llm = llmFake(["{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null},\"finish_reason\":\"stop\"}]}"]);
      let open = tEvent(fx.db, null, "/cases/some-v-case/read", "toggle_chat", "{}");
      let asked = tEventWith(fx.db, open.ctx, "/cases/some-v-case/read", "chat_send", "{\"message\": \"Who conceded what?\"}", llm);
      let m = tMain(asked.resp);
      expectHas(test, m, "Who conceded what?");
      expectLacks(test, m, "lc-turn assistant");
      expectText(test, tFlash(asked.resp, "error"), "That did not go through: empty_reply");
    }

    test("case read: asking keeps the question when the model fails, and says so") { test => chatFailCheck(test); }

    let chatEmptyCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let llm = llmFake([]);
      let open = tEvent(fx.db, null, "/cases/some-v-case/read", "toggle_chat", "{}");
      let blank = tEventWith(fx.db, open.ctx, "/cases/some-v-case/read", "chat_send", "{\"message\": \"   \"}", llm);
      expectInt(test, llmRequests(llm).length, 0);
      expectHas(test, tMain(blank.resp), "class=\"lc-hint\"");
      expectText(test, tFlash(blank.resp, "error"), "");
    }

    test("case read: an empty question is nothing") { test => chatEmptyCheck(test); }

    let chatCitedCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let edgeId = tCount(fx.db, "SELECT id AS n FROM link_edges WHERE rationale = 'They part on consent.'");
      let llm = llmFake(["{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"Because.\"},\"finish_reason\":\"stop\"}]}"]);
      let cited = tEvent(fx.db, null, "/cases/some-v-case/read", "cite_edge", "{\"edge\": \"${edgeId.toString()}\"}");
      let asked = tEventWith(fx.db, cited.ctx, "/cases/some-v-case/read", "chat_send", "{\"message\": \"Why?\"}", llm);
      expectHas(test, llmRequests(llm)[0], "pointing at these connections");
      expectHas(test, llmRequests(llm)[0], "Why it was drawn: They part on consent.");
      expectLacks(test, tMain(asked.resp), "lc-cited");
    }

    test("case read: what the reader is pointing at goes to the model, and is let go after") { test => chatCitedCheck(test); }

    let walkCasesCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let plain = tGet(fx.db, null, "/cases/some-v-case/read/${fx.op.work.slug}");
      expectLacks(test, plain.resp.body, "id=\"walk\"");
      let walk = tGet(fx.db, plain.ctx, "/cases/some-v-case/read/${fx.op.work.slug}?walk=1");
      expectHas(test, walk.resp.body, "id=\"walk\"");
      expectHas(test, walk.resp.body, "The whole case in one margin");
      expectLacks(test, walk.resp.body, "data-auto");
      let ended = tEvent(fx.db, walk.ctx, "/cases/some-v-case/read/${fx.op.work.slug}?walk=1", "end_walk", "{}");
      expectLacks(test, tMain(ended.resp), "id=\"walk\"");
      let after = tGet(fx.db, ended.ctx, "/cases/some-v-case/read/${fx.op.work.slug}");
      expectLacks(test, after.resp.body, "id=\"walk\"");
    }

    test("case read: walk=1 starts the last leg, end_walk ends it, a plain visit runs none") { test => walkCasesCheck(test); }

    let walkEventsCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let started = tEvent(fx.db, null, "/cases/some-v-case/read", "start_walk", "{}");
      expectHas(test, tMain(started.resp), "The whole case in one margin");
      let hopped = tEvent(fx.db, started.ctx, "/cases/some-v-case/read", "walk_hop", "{\"to\": \"case_read\"}");
      expectLacks(test, tMain(hopped.resp), "id=\"walk\"");
    }

    test("case read: start_walk starts it and a hop here just ends it") { test => walkEventsCheck(test); }

    let readUnknownCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let run = tGet(fx.db, null, "/cases/nope/read");
      expectInt(test, run.resp.status, 303);
      expectText(test, tLocation(run.resp), "/cases");
      let ev = tEvent(fx.db, null, "/cases/nope/read", "toggle_chat", "{}");
      expectText(test, tRedirect(ev.resp), "/cases");
    }

    test("case read: an unknown case sends you back to the list") { test => readUnknownCheck(test); }

    let readMetaCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let b = tGet(fx.db, null, "/cases/some-v-case/read").resp.body;
      expectHas(test, b, "<meta property=\"og:title\" content=\"Some v. Case — Opinion · read against the case\">");
      expectHas(test, b, "Some v. Case — Opinion, read with 2 other documents from Some v. Case in the margin.");
      expectHas(test, b, "content=\"http://localhost:4000/cases/some-v-case/read/${fx.op.work.slug}\"");
      expectHas(test, b, "/images/og-cases.png");
    }

    test("case read: the title and the address say which document, and how many others are in the margin") { test => readMetaCheck(test); }

    let readEmptyCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let c = casesGetStudy(fx);
      let state = new CasesReadState(c, null, [], null, null, null, false, [], [], [], false);
      let html = hjoin(renderCasesRead(state));
      expectHas(test, html, "<div class=\"cr-empty\">");
      expectHas(test, html, "Nothing in <b>Some v. Case</b> has been read yet.");
      expectHas(test, html, "Back to the case");
      expectLacks(test, html, "linkchat");
      expectLacks(test, html, "class=\"cr\"");
      let title = pagesCasesReadMeta(state).title;
      expectText(test, if (title != null) { title } else { "<none>" }, "Some v. Case");
    }

    test("case read: with nothing read it says so and offers the way back") { test => readEmptyCheck(test); }

    let casesGetStudy(fx: TFx): CaseStudy throws Bubble {
      let c = casesGet(fx.db, "some-v-case");
      if (c != null) { c } else { bubble() }
    }

    let readCtxCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let m = tMatch("GET", "/cases/some-v-case/read/${fx.di.work.slug}");
      expectText(test, m.params.getOr("lead", "?"), fx.di.work.slug);
      let c = casesGetStudy(fx);
      let lead = pagesCasesLeadOf(c, fx.di.work.slug);
      expectText(test, if (lead != null) { lead.slug } else { "?" }, fx.di.work.slug);
      let fallback = pagesCasesLeadOf(c, "nope");
      expectText(test, if (fallback != null) { fallback.slug } else { "?" }, fx.op.work.slug);
      let none = pagesCasesLeadOf(c, null);
      expectText(test, if (none != null) { none.slug } else { "?" }, fx.op.work.slug);
    }

    test("case read: the lead is the slug's work, else the opinion") { test => readCtxCheck(test); }

    let showLoadCheck(test: Test): Void throws Bubble {
      let fx = tCaseShared();
      let c = casesGetStudy(fx);
      let ctx = webNewCtx(fx.db, ":memory:", tRaw("GET", "/cases/some-v-case", "", ""), new MapBuilder<String, String>().toMap());
      let edges = pagesCasesShowEdges(ctx, c);
      expectInt(test, edges.length, 3);
      expectText(test, edges[0].ends.edge.edgeType, "tension");
      expectText(test, edges[1].ends.edge.edgeType, "answers");
      expectText(test, edges[2].ends.edge.edgeType, "echoes");
      expectText(test, edges[0].pair, "dissent+opinion");
      expectText(test, edges[1].pair, "argument+opinion");
      expectInt(test, pagesCasesFilter(edges, "", null, null).length, 3);
      expectInt(test, pagesCasesFilter(edges, "", "answers", null).length, 1);
      expectInt(test, pagesCasesFilter(edges, "", null, "dissent+opinion").length, 1);
      expectInt(test, pagesCasesFilter(edges, "consent", "answers", null).length, 0);
      expectInt(test, pagesCasesFilter(edges, " ", null, null).length, 3);
    }

    test("case page: the edges in the order of what pulls apart first, and the filters together") { test => showLoadCheck(test); }
