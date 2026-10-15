# Tests for pages_import

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse` and go through the router in
miniature: context, scope, the `guest.` plug, the group.

`runsStart` refuses `:memory:`, so the events are given a launcher that does what
a real start does without the fork: it writes the `running` row and runs the job
body in the same process (`tLaunch`), or only writes the row (`tQueue`), for the
tests that look at a run in the middle. GitHub is `importerFake` with routes
shaped as `FakeHub` answered: the same four pull requests, `#7` the one that
can not be fetched.

    let { dbOpen, Db, DbRow } = import("db/src");
    let { Request, Response, Route, Match, httpParse, routeMatch, httpHtml } = import("http/src");
    let { Scope, scopeFor, accountsGetUser, accountsGenerateUserSessionToken } = import("accounts/src");
    let {
      Ctx, webNewCtx, webMountCurrentScope, webEnsureUserOrGuest, webSessionCookieName, webSaveSession,
    } = import("webcore/src");
    let { ImporterHttp, ImporterPull, ImporterFakeRoute, importerFake, importerRoute } = import("importer/src");
    let { runsGet } = import("runs/src");
    let { JsonObject, JsonString, JsonSyntaxTree, parseJson } = import("std/json");
    let { sysJoin, sysByteLength } = import("sys/src");
    let { hjoin } = import("html/src");

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

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "missing: ${part}\nin: ${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "unexpected: ${part}\nin: ${s}" }
    }

## Fixtures

    class TWho(public id: Int, public scope: Scope, public ctx: Ctx) {}

    class TRun(public ctx: Ctx, public resp: Response) {}

    let tRaw(method: String, path: String, extra: String, body: String): Request {
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${sysByteLength(body).toString()}\r\n\r\n${body}")
    }

    let tMatch(method: String, path: String): Match throws Bubble {
      let m = routeMatch(pagesImportRoutes(), method, path);
      if (m != null) { m } else { bubble() }
    }

    let tCookieHeader(prev: Ctx?): String {
      if (prev != null) { "Cookie: ${webSessionCookieName()}=${prev.session.id}\r\n" } else { "" }
    }

A logged-in user by SQL (a registration costs a PBKDF2), and the session that
holds them: the context to pass on to the next request.

    let tWho(db: Db, email: String): TWho throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password, confirmed_at) VALUES ($1, 'x', '2020-01-01 00:00:00')", [email]);
      let user = accountsGetUser(db, id);
      let token = accountsGenerateUserSessionToken(db, user);
      let carrier = webNewCtx(db, ":memory:", tRaw("GET", "/import", "", ""), tMatch("GET", "/import").params);
      let row = db.one("SELECT id FROM users_tokens WHERE token = $1", [token]);
      if (row != null) { carrier.session.userTokenId = row.int("id"); }
      carrier.session.dirty = true;
      webSaveSession(db, carrier.session);
      new TWho(id, scopeFor(user), carrier)
    }

    let tRepeat(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = tRepeat(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

    let tN(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

The titles of every draft, sorted, joined with `|`.

    let tTitles(db: Db): String throws Bubble {
      let rows = db.query("SELECT title FROM works ORDER BY title", []);
      let out = new ListBuilder<String>();
      var i = 0;
      while (i < rows.length) {
        out.add(rows[i].str("title"));
        i += 1;
      }
      sysJoin(out.toList(), "|")
    }

## GitHub, as FakeHub answered

Four pull requests, "deliberately not in merge order". `#7` is the one that
cannot be fetched, so every test has a named failure available. `#6` is open and
unmerged; its date is when it was opened, which puts it between 7 and 9.

    let tPull(number: Int, title: String, state: String, draft: Boolean, created: String, merged: String?): String {
      let m = if (merged != null) { "\"${merged}T00:00:00Z\"" } else { "null" };
      "{\"number\":${number.toString()},\"title\":\"${title}\",\"body\":\"# ${title}\\n\\n${tRepeat("word ", 80)}\",\"html_url\":\"https://example.invalid/temper/blimp/pull/${number.toString()}\",\"state\":\"${state}\",\"draft\":${if (draft) { "true" } else { "false" }},\"base\":{\"ref\":\"main\"},\"head\":{\"ref\":\"b${number.toString()}\"},\"created_at\":\"${created}T00:00:00Z\",\"updated_at\":\"2026-01-01T00:00:00Z\",\"merged_at\":${m},\"changed_files\":0}"
    }

    let tP9(): String { tPull(9, "Fix the parser", "closed", false, "2025-01-01", "2025-04-01") }
    let tP8(): String { tPull(8, "Revert the fix", "open", false, "2025-01-01", null) }
    let tP7(): String { tPull(7, "Add a test", "closed", true, "2025-01-01", "2025-02-01") }
    let tP6(): String { tPull(6, "Nothing to do with it", "open", false, "2025-03-01", null) }

    let tHit(repo: String, number: Int, title: String): String {
      "{\"number\":${number.toString()},\"title\":\"${title}\",\"html_url\":\"https://github.com/${repo}/pull/${number.toString()}\",\"state\":\"closed\",\"repository_url\":\"https://api.github.com/repos/${repo}\",\"created_at\":\"2025-03-01T00:00:00Z\",\"pull_request\":{\"merged_at\":\"2025-03-02T00:00:00Z\"}}"
    }

    let tRoutes(): List<ImporterFakeRoute> {
      [
        importerRoute("q=boom", 403, "{}"),
        importerRoute("q=nothing", 200, "{\"items\":[]}"),
        importerRoute("/search/issues", 200, "{\"items\":[${tHit("found/elsewhere", 4, "Fix the search")},${tHit("found/elsewhere", 3, "Revert it")}]}"),
        importerRoute("/repos/temper/blimp/pulls?state=all", 200, "[${tP9()},${tP8()},${tP7()},${tP6()}]"),
        importerRoute("/repos/temper/blimp/pulls?state=open", 200, "[${tP8()},${tP6()}]"),
        importerRoute("/repos/empty/repo/pulls", 200, "[]"),
        importerRoute("/repos/priv/repo/pulls", 404, "{}"),
        importerRoute("/pulls/7", 404, "{}"),
        importerRoute("/commits", 200, "[]"),
        importerRoute("/files", 200, "[]"),
        importerRoute("/pulls/9", 200, tP9()),
        importerRoute("/pulls/8", 200, tP8()),
        importerRoute("/pulls/6", 200, tP6()),
      ]
    }

    let tFake(): ImporterHttp { importerFake(tRoutes()) }

## The launchers

`tQueue` is the production start without the fork: the row `runsStart` would
have written, with the page's first report. Refused (`false`) when the key is
taken. `tLaunch` also runs the job in-process, with the canned GitHub.

    let tQueue(ctx: Ctx, key: String, job: PimJob): Boolean throws Bubble {
      let taken = tN(ctx.db, "SELECT count(*) AS n FROM runs WHERE key = '${key}' AND status = 'running'");
      if (taken > 0) { return false; }
      ctx.db.exec(
        "INSERT OR REPLACE INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ($1, 'running', $2, 'fetching', NULL, '2026-01-01 10:00:00', NULL)",
        [key, "0/${job.picked.length.toString()}"],
      );
      true
    }

    let tLaunch(ctx: Ctx, key: String, job: PimJob): Boolean throws Bubble {
      let queued = tQueue(ctx, key, job);
      if (queued) { pagesImportJob(ctx.db, ctx.scope, key, tFake(), job); }
      queued
    }

    let tNever(ctx: Ctx, key: String, job: PimJob): Boolean throws Bubble {
      console.log("the launcher should not have been called");
      bubble()
    }

## Requests

    let tServe(db: Db, req: Request, match: Match): TRun throws Bubble {
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let denied = webEnsureUserOrGuest(ctx);
      if (denied != null) { new TRun(ctx, denied) } else { new TRun(ctx, pagesImportGet(ctx, match)) }
    }

    let tGet(db: Db, who: Ctx?, path: String): TRun throws Bubble {
      tServe(db, tRaw("GET", path, tCookieHeader(who), ""), tMatch("GET", path))
    }

The poll: the same page fetched the way `blimp.js` fetches it.

    let tPoll(db: Db, who: Ctx): TRun throws Bubble {
      tServe(db, tRaw("GET", "/import", "${tCookieHeader(who)}X-Requested-With: blimp\r\nAccept: application/json\r\n", ""), tMatch("GET", "/import"))
    }

    let tEventWith(
      db: Db, who: Ctx, name: String, payload: String,
      launch: fn (Ctx, String, PimJob): Boolean throws Bubble,
    ): TRun throws Bubble {
      let req = tRaw("POST", "/ev/${name}", "${tCookieHeader(who)}X-Requested-With: blimp\r\nContent-Type: application/json\r\n", "{\"payload\":${payload},\"path\":\"/import\"}");
      let match = tMatch("GET", "/import");
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let tree: JsonSyntaxTree = parseJson(payload);
      if (tree is JsonObject) {
        new TRun(ctx, pagesImportEventWith(ctx, match, name, tree, tFake(), launch))
      } else { bubble() }
    }

    let tEvent(db: Db, who: Ctx, name: String, payload: String): TRun throws Bubble {
      tEventWith(db, who, name, payload, tLaunch)
    }

    let tBody(r: TRun): String { r.resp.body }

The inside of `#main` in a JSON answer, unescaped.

    let tMain(r: TRun): String throws Bubble {
      let tree: JsonSyntaxTree = parseJson(r.resp.body);
      if (tree is JsonObject) {
        let regions = tree.propertyValueOrNull("regions");
        if (regions is JsonObject) {
          let main = regions.propertyValueOrNull("#main");
          if (main is JsonString) { main.content } else { bubble() }
        } else { bubble() }
      } else { bubble() }
    }

    let tRedirect(r: TRun): String throws Bubble {
      let tree: JsonSyntaxTree = parseJson(r.resp.body);
      if (tree is JsonObject) {
        let to = tree.propertyValueOrNull("redirect");
        if (to is JsonString) { to.content } else { "" }
      } else { "" }
    }

    let tLocation(r: TRun): String {
      var out = "";
      for (let p of r.resp.headers) { if (p.key == "Location") { out = p.value; } }
      out
    }

The wizard to its listing the way a person gets there: `source`, then `find`.

    let tFindListing(db: Db, who: Ctx): TRun throws Bubble {
      tEvent(db, who, "source", "{\"to\":\"github\"}");
      tEvent(db, who, "find", "{\"mode\":\"repo\",\"repo\":\"temper/blimp\",\"token\":\"t\"}")
    }

The same listing written straight into the session and the table, as `find` leaves
it: what a request costs in the interpreter is what a test of the next step should
not pay for again. The four pull requests as the importer reads them from
`tRoutes`, oldest first.

    let tSeedCands(): List<ImporterPull> {
      [
        new ImporterPull("temper/blimp", 8, "Revert the fix", "https://example.invalid/temper/blimp/pull/8", "open", false, "main", "b8", "2026-01-01T00:00:00Z", "2025-01-01T00:00:00Z", null),
        new ImporterPull("temper/blimp", 7, "Add a test", "https://example.invalid/temper/blimp/pull/7", "merged", true, "main", "b7", "2026-01-01T00:00:00Z", "2025-01-01T00:00:00Z", "2025-02-01T00:00:00Z"),
        new ImporterPull("temper/blimp", 6, "Nothing to do with it", "https://example.invalid/temper/blimp/pull/6", "open", false, "main", "b6", "2026-01-01T00:00:00Z", "2025-03-01T00:00:00Z", null),
        new ImporterPull("temper/blimp", 9, "Fix the parser", "https://example.invalid/temper/blimp/pull/9", "merged", false, "main", "b9", "2026-01-01T00:00:00Z", "2025-01-01T00:00:00Z", "2025-04-01T00:00:00Z"),
      ]
    }

    let httpHtmlOk(): Response { httpHtml(200, "") }

    let tToListing(db: Db, who: Ctx): TRun throws Bubble {
      let req = tRaw("GET", "/import", tCookieHeader(who), "");
      let ctx = webNewCtx(db, ":memory:", req, tMatch("GET", "/import").params);
      webMountCurrentScope(ctx);
      let cands = tSeedCands();
      pimSaveCands(ctx, cands);
      pimSetShown(ctx, [0, 1, 2, 3]);
      let w = pimNewWiz();
      w.step = "pick";
      w.source = "github";
      w.repo = "temper/blimp";
      w.folder = "temper/blimp";
      pimSaveWiz(ctx, w);
      pimStoreToken(ctx, "t");
      webSaveSession(db, ctx.session);
      new TRun(ctx, httpHtmlOk())
    }

The numbers on the rows of the list, in the order they stand.

    let tRowNumbers(html: String): String {
      let parts = html.split("phx-value-key=\"temper/blimp#");
      let out = new ListBuilder<String>();
      var i = 1;
      while (i < parts.length) {
        out.add(parts.getOr(i, "").split("\"").getOr(0, ""));
        i += 1;
      }
      sysJoin(out.toList(), ",")
    }

## Multipart

A form posted to `POST /import` the way a browser sends it.

    let tPartFile(filename: String, content: String): String {
      "--XB\r\nContent-Disposition: form-data; name=\"docs\"; filename=\"${filename}\"\r\nContent-Type: text/plain\r\n\r\n${content}\r\n"
    }

    let tPartField(name: String, value: String): String {
      "--XB\r\nContent-Disposition: form-data; name=\"${name}\"\r\n\r\n${value}\r\n"
    }

    let tChapter(title: String): String { "# ${title}\n\n${tRepeat("word ", 80)}" }

    let tPostFiles(db: Db, who: Ctx?, files: List<String>, folder: String, number: Boolean): TRun throws Bubble {
      let body = "${tPartField("_form", "files")}${tPartField("folder", folder)}${tPartField("number", if (number) { "true" } else { "false" })}${sysJoin(files, "")}--XB--\r\n";
      let req = tRaw("POST", "/import", "${tCookieHeader(who)}Content-Type: multipart/form-data; boundary=XB\r\n", body);
      tServe(db, req, tMatch("POST", "/import"))
    }

## Routes

    test("routes: the wizard and the plain post of its files form, in that order") { test =>
      let names = pagesImportRoutes().map { (r: Route): String => "${r.method} ${r.pattern}" };
      expectText(test, sysJoin(names, ", "), "GET /import, POST /import");
    }

    test("routes: both are guest routes") { test =>
      for (let r of pagesImportRoutes()) {
        expectTrue(test, hasText(r.name, "guest."), r.name);
      }
    }

## Rendering each step

A view by hand, so the markup is looked at without a session behind it.

    let tCtx(db: Db): Ctx throws Bubble {
      webNewCtx(db, ":memory:", tRaw("GET", "/import", "", ""), tMatch("GET", "/import").params)
    }

    let tCand(repo: String, number: Int, title: String, state: String, draft: Boolean, merged: String?): ImporterPull {
      new ImporterPull(
        repo, number, title, "https://example.invalid/${repo}/pull/${number.toString()}", state, draft,
        "main", "b", "2026-01-01T00:00:00Z", "2025-01-01T00:00:00Z", merged,
      )
    }

    let tTicked(keys: List<String>, key: String): Boolean {
      var found = false;
      var i = 0;
      while (!found && i < keys.length) {
        if (keys[i] == key) { found = true; }
        i += 1;
      }
      found
    }

The pick step as the page builds it: the rows at `shown`, ticked if their key is
in `chosen`, and the counts the bar reads.

    let tPickView(w: PimWiz, cands: List<ImporterPull>, shown: List<Int>, chosen: List<String>): PimView {
      let rows = new ListBuilder<PimRow>();
      var i = 0;
      while (i < shown.length) {
        let c = cands[shown[i]];
        rows.add(new PimRow(c, tTicked(chosen, pimKey(c))));
        i += 1;
      }
      pimViewOf(w, rows.toList(), new PimCounts(cands.length, shown.length, chosen.length), null, "fetching", 0, 0)
    }

    let tView(w: PimWiz): PimView {
      pimViewOf(w, [], new PimCounts(0, 0, 0), null, "fetching", 0, 0)
    }

    let tRenderStep(db: Db, w: PimWiz): String throws Bubble {
      hjoin(renderImport(tCtx(db), tView(w)))
    }

    let tRenderView(db: Db, v: PimView): String throws Bubble {
      hjoin(renderImport(tCtx(db), v))
    }

    let tListing(): List<ImporterPull> {
      [
        tCand("temper/blimp", 8, "Revert the fix", "open", false, null),
        tCand("temper/blimp", 7, "Add a test", "closed", true, "2025-02-01T00:00:00Z"),
        tCand("temper/blimp", 6, "Nothing <b>to</b> do", "open", false, null),
        tCand("temper/blimp", 9, "Fix the parser", "merged", false, "2025-04-01T00:00:00Z"),
      ]
    }

    let tPickWiz(): PimWiz {
      let w = pimNewWiz();
      w.step = "pick";
      w.folder = "temper/blimp";
      w
    }

    test("render: the source step is a choice of two cards") { test =>
      let db = dbOpen(":memory:");
      let html = tRenderStep(db, pimNewWiz());
      expectHas(test, html, "<h1 style=\"font-family:var(--mg-serif)\" class=\"mt-2 text-2xl font-semibold tracking-tight\">Import documents</h1>");
      expectHas(test, html, "<div class=\"mg-meta\"><a href=\"/works\">← every draft</a></div>");
      expectHas(test, html, "<button class=\"im-card\" type=\"button\" phx-click=\"source\" phx-value-to=\"github\">");
      expectHas(test, html, "<button class=\"im-card\" type=\"button\" phx-click=\"source\" phx-value-to=\"files\">");
      expectHas(test, html, "<span class=\"mg-label\">GitHub</span><b>Pull requests</b>");
      expectHas(test, html, "<span class=\"mg-label\">Files</span><b>From this computer</b>");
      expectHas(test, html, "Up to 40 markdown or text files, dropped together.");
      expectHas(test, html, "Both of these land in a folder and stop.");
    }

    let tAt(db: Db, step: String): String throws Bubble {
      let w = pimNewWiz();
      w.step = step;
      tRenderStep(db, w)
    }

    test("render: the numbered steps light the one the wizard is on") { test =>
      let db = dbOpen(":memory:");
      expectHas(test, tAt(db, "source"), "<li class=\"im-step on\"><span>1</span> Source</li><li class=\"im-step\"><span>2</span> Find</li><li class=\"im-step\"><span>3</span> Choose</li><li class=\"im-step\"><span>4</span> Import</li>");
      expectHas(test, tAt(db, "find"), "<li class=\"im-step\"><span>1</span> Source</li><li class=\"im-step on\"><span>2</span> Find</li>");
      expectHas(test, tAt(db, "files"), "<li class=\"im-step on\"><span>2</span> Find</li>");
      expectHas(test, tAt(db, "pick"), "<li class=\"im-step on\"><span>3</span> Choose</li>");
      expectHas(test, tAt(db, "running"), "<li class=\"im-step on\"><span>4</span> Import</li>");
      expectHas(test, tAt(db, "done"), "<li class=\"im-step on\"><span>4</span> Import</li>");
    }

    test("render: the find step for a repository") { test =>
      let db = dbOpen(":memory:");
      let w = pimNewWiz();
      w.step = "find";
      w.repo = "temper/blimp";
      w.state = "closed";
      let html = tRenderStep(db, w);
      expectHas(test, html, "id=\"im-find\"");
      expectHas(test, html, "phx-submit=\"find\" phx-change=\"form\"");
      expectHas(test, html, "<label class=\"im-mode on\"><input type=\"radio\" name=\"mode\" value=\"repo\" checked><b>One repository</b><span>Every pull request in it, then filter.</span></label>");
      expectHas(test, html, "<label class=\"im-mode\"><input type=\"radio\" name=\"mode\" value=\"search\"><b>A search</b>");
      expectHas(test, html, "<input type=\"text\" name=\"repo\" value=\"temper/blimp\" placeholder=\"owner/name\" autocomplete=\"off\" class=\"mg-input\">");
      expectHas(test, html, "<option value=\"closed\" selected>Closed only</option>");
      expectHas(test, html, "<option value=\"all\">All, open and closed</option>");
      expectLacks(test, html, "name=\"query\"");
      expectHas(test, html, "<button class=\"mg-btn\" type=\"submit\">Find them</button>");
      expectHas(test, html, "phx-click=\"back\">back</button>");
    }

    test("render: the find step for a search swaps the fields and keeps the token empty") { test =>
      let db = dbOpen(":memory:");
      let w = pimNewWiz();
      w.step = "find";
      w.mode = "search";
      w.query = "label:design";
      let html = tRenderStep(db, w);
      expectHas(test, html, "<label class=\"im-mode on\"><input type=\"radio\" name=\"mode\" value=\"search\" checked>");
      expectHas(test, html, "name=\"query\" value=\"label:design\" placeholder=\"repo:owner/name label:design merged:&gt;2025-01-01\"");
      expectHas(test, html, "<code>is:pr</code> is added for you");
      expectHas(test, html, "<code>@today-30d</code> is turned into the date it means");
      expectLacks(test, html, "name=\"repo\"");
      expectHas(test, html, "<input type=\"password\" name=\"token\" value=\"\" autocomplete=\"off\" placeholder=\"leave blank for a public repository\" class=\"mg-input\">");
      expectHas(test, html, "GitHub token <em>optional</em>");
    }

    test("render: the find form carries the token's csrf field and posts to /import") { test =>
      let db = dbOpen(":memory:");
      let w = pimNewWiz();
      w.step = "find";
      let html = tRenderStep(db, w);
      expectHas(test, html, "<form id=\"im-find\" method=\"post\" action=\"/import\"");
      expectHas(test, html, "<input type=\"hidden\" name=\"_csrf_token\" value=\"");
    }

    test("render: the choosing step lists the rows with their ids and keys") { test =>
      let db = dbOpen(":memory:");
      let v = tPickView(tPickWiz(), tListing(), [0, 1, 2, 3], ["temper/blimp#8", "temper/blimp#9"]);
      let html = tRenderView(db, v);
      expectHas(test, html, "<li id=\"im-row-temper-blimp-8\" class=\"im-row on\"><label><input type=\"checkbox\" checked phx-click=\"toggle\" phx-value-key=\"temper/blimp#8\"><span class=\"n\">#8</span><span class=\"t\">Revert the fix</span><span class=\"s open\">open</span><span class=\"r\">temper/blimp</span></label></li>");
      expectHas(test, html, "<li id=\"im-row-temper-blimp-7\" class=\"im-row\"><label><input type=\"checkbox\" phx-click=\"toggle\" phx-value-key=\"temper/blimp#7\"><span class=\"n\">#7</span><span class=\"t\">Add a test</span><span class=\"d\">2025-02-01</span><span class=\"s closed\">closed</span><span class=\"s draft\">draft</span>");
      expectHas(test, html, "<span class=\"d\">2025-04-01</span><span class=\"s merged\">merged</span>");
      expectText(test, tRowNumbers(html), "8,7,6,9");
    }

    test("render: a title from GitHub is escaped") { test =>
      let db = dbOpen(":memory:");
      let v = tPickView(tPickWiz(), tListing(), [2], []);
      let html = tRenderView(db, v);
      expectHas(test, html, "Nothing &lt;b&gt;to&lt;/b&gt; do");
      expectLacks(test, html, "Nothing <b>to</b> do");
    }

    test("render: the bar counts what is shown and what is selected") { test =>
      let db = dbOpen(":memory:");
      let all = tRenderView(db, tPickView(tPickWiz(), tListing(), [0, 1, 2, 3], ["a#1", "a#2", "a#3", "a#4"]));
      expectHas(test, all, "<span>4 pull requests shown · <b>4 selected</b></span>");
      expectHas(test, all, "phx-click=\"all\">select all shown</button>");
      expectHas(test, all, "phx-click=\"none\">clear shown</button>");
      let some = tRenderView(db, tPickView(tPickWiz(), tListing(), [0, 3], ["a#1"]));
      expectHas(test, some, "<span>2 pull requests shown of 4 · <b>1 selected</b></span>");
      let one = tRenderView(db, tPickView(tPickWiz(), tListing(), [0], []));
      expectHas(test, one, "<span>1 pull request shown of 4 · <b>0 selected</b></span>");
    }

    test("render: the query help, and the regex help, and the placeholders") { test =>
      let db = dbOpen(":memory:");
      let q = tRenderView(db, tPickView(tPickWiz(), tListing(), [0], []));
      expectHas(test, q, "Runs over the rows already fetched, so it costs nothing and does not have to be right first time.");
      expectHas(test, q, "<code>state:</code> <code>is:</code> <code>draft:</code>");
      expectHas(test, q, "placeholder=\"is:pr state:closed created:&gt;@today-30d\"");
      expectHas(test, q, "<option value=\"query\" selected>Query</option><option value=\"regex\">Title regex</option>");
      expectHas(test, q, "phx-debounce=\"300\"");
      let w = tPickWiz();
      w.how = "regex";
      let r = tRenderView(db, tPickView(w, tListing(), [0], []));
      expectHas(test, r, "Case insensitive, matched against the title. Filters the list and selects what it matches — the boxes below still have the last word.");
      expectHas(test, r, "placeholder=\"a regular expression — ^d+. or fix|revert\"");
      expectHas(test, r, "<option value=\"regex\" selected>Title regex</option>");
      expectLacks(test, r, "Runs over the rows already fetched");
    }

    test("render: a pattern that will not compile is named and replaces the help") { test =>
      let db = dbOpen(":memory:");
      let w = tPickWiz();
      w.how = "regex";
      w.pattern = "(unclosed";
      w.patternError = "missing closing parenthesis at character 9";
      let html = tRenderView(db, tPickView(w, tListing(), [0], []));
      expectHas(test, html, "<p class=\"cut-err mt-2\">missing closing parenthesis at character 9</p>");
      expectLacks(test, html, "Case insensitive, matched against the title.");
      expectHas(test, html, "name=\"pattern\" value=\"(unclosed\"");
    }

    test("render: nothing shown says so for the language in use, and the hint only when there is one") { test =>
      let db = dbOpen(":memory:");
      let none = tRenderView(db, tPickView(tPickWiz(), tListing(), [], []));
      expectHas(test, none, "<p class=\"mg-meta\">Nothing matches that query.</p>");
      expectLacks(test, none, "is that one day");
      let w = tPickWiz();
      w.how = "regex";
      expectHas(test, tRenderView(db, tPickView(w, tListing(), [], [])), "Nothing matches that pattern.");
      let h = tPickWiz();
      h.hintWas = "created:@today-90d";
      h.hintTry = "created:>@today-90d";
      let hinted = tRenderView(db, tPickView(h, tListing(), [], []));
      expectHas(test, hinted, "<p class=\"mg-meta mt-1\"><code>created:@today-90d</code> is that one day. For everything since it, write <code>created:&gt;@today-90d</code>.</p>");
      expectLacks(test, tRenderView(db, tPickView(h, tListing(), [0], [])), "Nothing matches");
    }

    test("render: the settings form, its three checkboxes and the count on the button") { test =>
      let db = dbOpen(":memory:");
      let w = tPickWiz();
      w.files = false;
      let html = tRenderView(db, tPickView(w, tListing(), [0, 1], ["temper/blimp#8", "temper/blimp#7"]));
      expectHas(test, html, "<form id=\"im-settings\" phx-submit=\"import\" phx-change=\"settings\"");
      expectHas(test, html, "name=\"folder\" value=\"temper/blimp\" placeholder=\"left empty, named for what the files have in common\"");
      expectHas(test, html, "<input type=\"hidden\" name=\"commits\" value=\"false\"><input type=\"checkbox\" name=\"commits\" value=\"true\" checked>");
      expectHas(test, html, "<input type=\"hidden\" name=\"files\" value=\"false\"><input type=\"checkbox\" name=\"files\" value=\"true\"><span><b>Include the files changed.</b>");
      expectHas(test, html, "<input type=\"hidden\" name=\"number\" value=\"false\"><input type=\"checkbox\" name=\"number\" value=\"true\"><span><b>Number the titles.</b>");
      expectHas(test, html, "<button class=\"mg-btn\" type=\"submit\">Import 2</button>");
      expectLacks(test, html, "type=\"submit\" disabled");
    }

    test("render: the import button is disabled when nothing is ticked") { test =>
      let db = dbOpen(":memory:");
      let html = tRenderView(db, tPickView(tPickWiz(), tListing(), [0], []));
      expectHas(test, html, "<button class=\"mg-btn\" type=\"submit\" disabled>Import 0</button>");
    }

    test("render: the order form") { test =>
      let db = dbOpen(":memory:");
      let w = tPickWiz();
      w.order = "newest";
      let html = tRenderView(db, tPickView(w, tListing(), [0], []));
      expectHas(test, html, "<form id=\"im-order\" phx-submit=\"order\" phx-change=\"order\" class=\"im-order\">");
      expectHas(test, html, "<option value=\"oldest\">Oldest first, by when it landed</option><option value=\"newest\" selected>Newest first</option>");
      expectHas(test, html, "For a release, oldest first.");
    }

    test("render: the files step is a multipart form posting to /import") { test =>
      let db = dbOpen(":memory:");
      let w = pimNewWiz();
      w.step = "files";
      w.number = true;
      let html = tRenderStep(db, w);
      expectHas(test, html, "<form id=\"im-files\" method=\"post\" action=\"/import\" enctype=\"multipart/form-data\"");
      expectHas(test, html, "<input type=\"hidden\" name=\"_csrf_token\" value=\"");
      expectHas(test, html, "<input type=\"hidden\" name=\"_form\" value=\"files\">");
      expectHas(test, html, "Drop up to 40 markdown or text files here, or choose them.");
      expectHas(test, html, "<input type=\"file\" name=\"docs\" id=\"im-docs\" multiple=\"\" accept=\".txt,.md,.markdown,.text\">");
      expectHas(test, html, "<input type=\"checkbox\" name=\"number\" value=\"true\" checked><span><b>Number the titles.</b> Only if these are a series meant to be read in order.</span>");
      expectHas(test, html, "<button class=\"mg-btn\" type=\"submit\">Import</button>");
      expectLacks(test, html, "name=\"commits\"");
    }

    test("render: the running step shows the bar and the phase") { test =>
      let db = dbOpen(":memory:");
      let w = pimNewWiz();
      w.step = "running";
      let fetching = tRenderView(db, pimViewOf(w, [], new PimCounts(0, 0, 0), null, "fetching", 5, 10));
      expectHas(test, fetching, "<p class=\"mg-label\">Reading them off GitHub</p>");
      expectHas(test, fetching, "<div class=\"im-progress\"><span style=\"width:50%\"></span></div>");
      expectHas(test, fetching, "<p class=\"mg-meta mt-2\">5 of 10</p>");
      let landing = tRenderView(db, pimViewOf(w, [], new PimCounts(0, 0, 0), null, "landing", 1, 3));
      expectHas(test, landing, "<p class=\"mg-label\">Filing them</p>");
      expectHas(test, landing, "width:33%");
      expectHas(test, tRenderView(db, pimViewOf(w, [], new PimCounts(0, 0, 0), null, "fetching", 0, 0)), "width:0%");
    }

    test("render: the results step lists what was filed, skipped, refused and missed") { test =>
      let db = dbOpen(":memory:");
      let w = pimNewWiz();
      w.step = "done";
      let r = new PimResult(
        12, 3, ["A", "B"], [new Pair("Empty one", "there is no text in it")],
        [new PimMissed(7, "Add a test", "No such repository, or the token cannot see it.")],
      );
      let html = tRenderView(db, pimViewOf(w, [], new PimCounts(0, 0, 0), r, "fetching", 0, 0));
      expectHas(test, html, "<p style=\"font-family:var(--mg-serif)\" class=\"text-xl font-semibold\">3 drafts imported.</p>");
      expectHas(test, html, "2 were already in the folder under the same title and were left alone.");
      expectHas(test, html, "<p class=\"mg-label\">Not imported</p><ul class=\"im-bad\"><li>Empty one — there is no text in it</li></ul>");
      expectHas(test, html, "<p class=\"mg-label\">Could not be fetched</p><ul class=\"im-bad\"><li>#7 Add a test — No such repository, or the token cannot see it.</li></ul>");
      expectHas(test, html, "<a href=\"/stacks/12\" class=\"mg-btn\">Open the folder</a>");
      expectHas(test, html, "phx-click=\"restart\">import some more</button>");
    }

    test("render: one draft, one skipped, and no folder") { test =>
      let db = dbOpen(":memory:");
      let w = pimNewWiz();
      w.step = "done";
      let r = new PimResult(null, 1, ["A"], [], []);
      let html = tRenderView(db, pimViewOf(w, [], new PimCounts(0, 0, 0), r, "fetching", 0, 0));
      expectHas(test, html, ">1 draft imported.</p>");
      expectHas(test, html, "1 was already in the folder under the same title and was left alone.");
      expectHas(test, html, "<a href=\"/works\" class=\"mg-btn\">Every draft</a>");
      expectLacks(test, html, "Not imported");
      expectLacks(test, html, "Could not be fetched");
      expectLacks(test, html, "Open the folder");
    }

    test("render: a results step with no result offers to start again, under the error") { test =>
      let db = dbOpen(":memory:");
      let w = pimNewWiz();
      w.step = "done";
      w.error = "The import crashed: Bubble";
      let html = tRenderView(db, pimViewOf(w, [], new PimCounts(0, 0, 0), null, "fetching", 0, 0));
      expectHas(test, html, "<p class=\"cut-err mt-4\">The import crashed: Bubble</p>");
      expectHas(test, html, "phx-click=\"restart\">start again</button>");
      expectLacks(test, html, "imported.");
    }

## The page

    test("page: a visitor with no session is given a guest and the source step; the page asks not to be indexed") { test =>
      let db = dbOpen(":memory:");
      let r = tGet(db, null, "/import");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, ">Import documents · Marginalia</title>");
      expectHas(test, body, "<meta name=\"robots\" content=\"noindex, nofollow\">");
      expectHas(test, body, "<span class=\"mg-label\">GitHub</span>");
      expectHas(test, body, "Keep my drafts");
      expectLacks(test, body, "data-poll");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("page: the first step creates nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let body = tBody(tGet(db, me.ctx, "/import"));
      expectHas(test, body, "Pull requests");
      expectHas(test, body, "From this computer");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works"), 0);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders"), 0);
    }

    test("page: a new page load starts the wizard over, a poll does not") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      expectHas(test, tMain(tPoll(db, me.ctx)), "Fix the parser");
      expectHas(test, tBody(tGet(db, me.ctx, "/import")), "<span class=\"mg-label\">GitHub</span>");
      expectLacks(test, tMain(tPoll(db, me.ctx)), "Fix the parser");
    }

## Moving between steps

    test("source: github goes to the find step, files to the files step") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tMain(tEvent(db, me.ctx, "source", "{\"to\":\"github\"}"));
      expectHas(test, a, "id=\"im-find\"");
      expectHas(test, a, "<li class=\"im-step on\"><span>2</span> Find</li>");
      tEvent(db, me.ctx, "back", "{}");
      let b = tMain(tEvent(db, me.ctx, "source", "{\"to\":\"files\"}"));
      expectHas(test, b, "Drop up to 40 markdown or text files here");
      expectHas(test, b, "id=\"im-files\"");
    }

    test("back: walks the steps rather than reloading, and keeps the listing") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let find = tMain(tEvent(db, me.ctx, "back", "{}"));
      expectHas(test, find, "GitHub token");
      expectHas(test, find, "value=\"temper/blimp\"");
      let source = tMain(tEvent(db, me.ctx, "back", "{}"));
      expectHas(test, source, "Pull requests");
      expectLacks(test, source, "GitHub token");
      let still = tMain(tEvent(db, me.ctx, "back", "{}"));
      expectHas(test, still, "Pull requests");
    }

    test("back: from the files step is the source step") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"files\"}");
      expectHas(test, tMain(tEvent(db, me.ctx, "back", "{}")), "Pull requests");
    }

    test("restart: back to the source with the listing forgotten and the repository kept") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "restart", "{}");
      expectHas(test, tMain(tEvent(db, me.ctx, "source", "{\"to\":\"github\"}")), "value=\"temper/blimp\"");
      let w = pimLoadWiz(tEvent(db, me.ctx, "validate", "{}").ctx);
      expectInt(test, pimLoadCands(tEvent(db, me.ctx, "validate", "{}").ctx).length, 0);
      expectText(test, w.step, "find");
    }

    test("form: the fields as typed come back, and the mode swaps the fields") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      let html = tMain(tEvent(db, me.ctx, "form", "{\"mode\":\"search\",\"repo\":\"a/b\",\"query\":\"label:x\",\"state\":\"open\",\"token\":\"secret\"}"));
      expectHas(test, html, "name=\"query\" value=\"label:x\"");
      expectLacks(test, html, "name=\"repo\"");
      expectLacks(test, html, "secret");
      let back = tMain(tEvent(db, me.ctx, "form", "{\"mode\":\"repo\"}"));
      expectHas(test, back, "name=\"repo\" value=\"a/b\"");
      expectHas(test, back, "<option value=\"open\" selected>Open only</option>");
    }

## Finding

    test("find: lists the pull requests without importing any, oldest first, all selected") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let html = tMain(tFindListing(db, me.ctx));
      expectHas(test, html, "Fix the parser");
      expectHas(test, html, "Revert the fix");
      expectHas(test, html, "Add a test");
      expectHas(test, html, "Nothing to do with it");
      expectHas(test, html, "<b>4 selected</b>");
      expectHas(test, html, "<li class=\"im-step on\"><span>3</span> Choose</li>");
      expectText(test, tRowNumbers(html), "8,7,6,9");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("find: the folder box is named for the repository") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      expectHas(test, tMain(tFindListing(db, me.ctx)), "name=\"folder\" value=\"temper/blimp\"");
    }

    test("find: a search lists across repositories, and its folder is named for the search") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      let html = tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"search\",\"query\":\"label:design\",\"token\":\"t\"}"));
      expectHas(test, html, "found/elsewhere");
      expectHas(test, html, "Fix the search");
      expectHas(test, html, "phx-value-key=\"found/elsewhere#4\"");
      expectHas(test, html, "name=\"folder\" value=\"Search: label:design\"");
    }

    test("find: a search that GitHub refuses is reported in words, and shows no list") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      let html = tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"search\",\"query\":\"boom\",\"token\":\"t\"}"));
      expectHas(test, html, "<p class=\"cut-err mt-4\">GitHub refused: the token may lack access, or you are rate limited.");
      expectLacks(test, html, "Fix the parser");
      expectHas(test, html, "id=\"im-find\"");
    }

    test("find: an empty search is refused before any request") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      let html = tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"search\",\"query\":\"   \",\"token\":\"\"}"));
      expectHas(test, html, "Write a search query first.");
    }

    test("find: a repository written wrongly is refused before any request") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      expectHas(test, tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"repo\",\"repo\":\"blimp\",\"token\":\"t\"}")), "Write the repository as owner/name.");
      expectHas(test, tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"repo\",\"repo\":\"/blimp\",\"token\":\"t\"}")), "Write the repository as owner/name.");
      expectHas(test, tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"repo\",\"repo\":\"temper/\",\"token\":\"t\"}")), "Write the repository as owner/name.");
    }

    test("find: names GitHub would not accept are explained") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      let html = tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"repo\",\"repo\":\"a b/c\",\"token\":\"\"}"));
      expectHas(test, html, "Owner and repository must look like GitHub names.");
    }

    test("find: a repository that is not there, and one with nothing in it") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      expectHas(test, tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"repo\",\"repo\":\"priv/repo\",\"token\":\"\"}")), "No such repository, or the token cannot see it.");
      expectHas(test, tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"repo\",\"repo\":\"empty/repo\",\"token\":\"\"}")), "Nothing matched.");
    }

    test("find: a mode the page does not have is a crash with its name, not a guess") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      let bubbled = do { tEvent(db, me.ctx, "find", "{\"mode\":\"sideways\",\"token\":\"\"}"); false } orelse true;
      expectTrue(test, bubbled, "an unknown mode bubbles");
    }

    test("find: a state of open asks GitHub for the open ones only") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      let html = tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"repo\",\"repo\":\"temper/blimp\",\"state\":\"open\",\"token\":\"\"}"));
      expectText(test, tRowNumbers(html), "8,6");
    }

## The token

    test("token: never rendered back, at any step, and gone once the import has started") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"github\"}");
      let found = tMain(tEvent(db, me.ctx, "find", "{\"mode\":\"repo\",\"repo\":\"temper/blimp\",\"token\":\"ghp_secret_do_not_print\"}"));
      expectLacks(test, found, "ghp_secret_do_not_print");
      expectText(test, pimStoredToken(tEvent(db, me.ctx, "settings", "{\"folder\":\"x\"}").ctx), "ghp_secret_do_not_print");
      expectLacks(test, tMain(tEvent(db, me.ctx, "settings", "{\"folder\":\"x\"}")), "ghp_secret_do_not_print");
      let done = tMain(tEvent(db, me.ctx, "import", "{}"));
      expectLacks(test, done, "ghp_secret_do_not_print");
      expectText(test, pimStoredToken(tEvent(db, me.ctx, "validate", "{}").ctx), "");
      expectLacks(test, tBody(tGet(db, me.ctx, "/import")), "ghp_secret_do_not_print");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM runs WHERE detail LIKE '%ghp_secret%' OR progress LIKE '%ghp_secret%'"), 0);
    }

    test("token: only what was typed is used, a blank box is no token at all") { test =>
      expectText(test, pimEffectiveToken("typed"), "typed");
      expectText(test, pimEffectiveToken(""), "");
    }

## Narrowing

    test("pattern: a title regex filters the list and sets the selection") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"regex\",\"pattern\":\"fix\"}"));
      expectHas(test, html, "Fix the parser");
      expectHas(test, html, "Revert the fix");
      expectLacks(test, html, "Nothing to do with it");
      expectHas(test, html, "<b>2 selected</b>");
      expectHas(test, html, "2 pull requests shown of 4");
    }

    test("pattern: a regex that will not compile says so and keeps the list") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"regex\",\"pattern\":\"(unclosed\"}"));
      expectHas(test, html, "Fix the parser");
      expectHas(test, html, "<p class=\"cut-err mt-2\">");
      expectHas(test, html, "<b>4 selected</b>");
    }

    test("pattern: the boxes have the last word over the regex") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "pattern", "{\"how\":\"regex\",\"pattern\":\"fix\"}");
      let html = tMain(tEvent(db, me.ctx, "toggle", "{\"key\":\"temper/blimp#6\"}"));
      expectHas(test, html, "<b>3 selected</b>");
      let off = tMain(tEvent(db, me.ctx, "toggle", "{\"key\":\"temper/blimp#6\"}"));
      expectHas(test, off, "<b>2 selected</b>");
    }

    test("pattern: clearing and selecting work on what is shown, not on everything") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "pattern", "{\"how\":\"regex\",\"pattern\":\"fix\"}");
      expectHas(test, tMain(tEvent(db, me.ctx, "none", "{}")), "<b>0 selected</b>");
      expectHas(test, tMain(tEvent(db, me.ctx, "all", "{}")), "<b>2 selected</b>");
    }

    test("pattern: clearing what is shown keeps the selection that is hidden") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "pattern", "{\"how\":\"regex\",\"pattern\":\"fix\"}");
      tEvent(db, me.ctx, "toggle", "{\"key\":\"temper/blimp#6\"}");
      expectHas(test, tMain(tEvent(db, me.ctx, "none", "{}")), "<b>1 selected</b>");
    }

    test("query: narrows by state without another request") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"state:open\"}"));
      expectHas(test, html, "Revert the fix");
      expectHas(test, html, "Nothing to do with it");
      expectLacks(test, html, "Fix the parser");
      expectHas(test, html, "<b>2 selected</b>");
    }

    test("query: the shape from the report") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"is:pr state:merged\"}"));
      expectHas(test, html, "Fix the parser");
      expectHas(test, html, "<b>2 selected</b>");
    }

    test("query: a bare word matches the title, and a minus takes it away") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      expectHas(test, tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"fix\"}")), "<b>2 selected</b>");
      expectHas(test, tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"-fix\"}")), "<b>2 selected</b>");
    }

    test("query: a typo is refused by name and the list and selection are kept") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"stat:closed\"}"));
      expectHas(test, html, "do not know");
      expectHas(test, html, "stat");
      expectHas(test, html, "Fix the parser");
      expectHas(test, html, "<b>4 selected</b>");
      expectHas(test, html, "name=\"pattern\" value=\"stat:closed\"");
    }

    test("query: switching language re-runs the same text") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      expectHas(test, tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"regex\",\"pattern\":\"fix|test\"}")), "<b>3 selected</b>");
      expectHas(test, tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"fix|test\"}")), "<b>0 selected</b>");
    }

    test("query: an empty result explains the guessable mistake") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"created:@today-90d\"}"));
      expectHas(test, html, "Nothing matches that query");
      expectHas(test, html, "that one day");
      expectHas(test, html, "created:&gt;@today-90d");
    }

    test("query: and says nothing more when it is simply too narrow") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"nonesuch\"}"));
      expectHas(test, html, "Nothing matches that query");
      expectLacks(test, html, "that one day");
    }

    test("query: pressing Enter in the filter is the same event and stays on the step") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"state:merged\"}");
      let html = tMain(tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"state:merged\"}"));
      expectHas(test, html, "Fix the parser");
      expectHas(test, html, "<b>2 selected</b>");
      expectHas(test, html, "<li class=\"im-step on\"><span>3</span> Choose</li>");
      expectLacks(test, html, "Pull requests");
    }

## Order

    test("order: oldest first by default, so the folder reads forwards") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      expectText(test, tRowNumbers(tMain(tFindListing(db, me.ctx))), "8,7,6,9");
    }

    test("order: flipped, and the selection starts over") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "pattern", "{\"how\":\"regex\",\"pattern\":\"fix\"}");
      let html = tMain(tEvent(db, me.ctx, "order", "{\"order\":\"newest\"}"));
      expectText(test, tRowNumbers(html), "9,8");
      expectHas(test, html, "<option value=\"newest\" selected>Newest first</option>");
      expectHas(test, html, "<b>2 selected</b>");
    }

    test("order: the form survives Enter too") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "order", "{\"order\":\"newest\"}"));
      expectText(test, tRowNumbers(html), "9,6,7,8");
      expectHas(test, html, "<b>4 selected</b>");
    }

## Settings

    test("settings: the folder, and each box is whether it said true") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let html = tMain(tEvent(db, me.ctx, "settings", "{\"folder\":\"Picked\",\"commits\":\"false\",\"files\":\"true\",\"number\":\"true\"}"));
      expectHas(test, html, "name=\"folder\" value=\"Picked\"");
      expectHas(test, html, "<input type=\"hidden\" name=\"commits\" value=\"false\"><input type=\"checkbox\" name=\"commits\" value=\"true\"><span>");
      expectHas(test, html, "<input type=\"checkbox\" name=\"files\" value=\"true\" checked>");
      expectHas(test, html, "<input type=\"checkbox\" name=\"number\" value=\"true\" checked>");
      let bare = tMain(tEvent(db, me.ctx, "settings", "{\"folder\":\"x\"}"));
      expectLacks(test, bare, "name=\"files\" value=\"true\" checked");
    }

## Importing

    test("import: nothing selected is refused by name and nothing is started") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "none", "{}");
      let r = tEventWith(db, me.ctx, "import", "{}", tNever);
      expectHas(test, tMain(r), "Nothing is selected.");
    }

    test("import: more than two hundred is refused with the number") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let ctx = tEvent(db, me.ctx, "validate", "{}").ctx;
      let cands = new ListBuilder<ImporterPull>();
      let positions = new ListBuilder<Int>();
      var n = 1;
      while (n <= 201) {
        cands.add(tCand("big/repo", n, "Pull ${n.toString()}", "open", false, null));
        positions.add(n - 1);
        n += 1;
      }
      pimSaveCands(ctx, cands.toList());
      pimSetShown(ctx, positions.toList());
      pimSaveWiz(ctx, tPickWiz());
      webSaveSession(db, ctx.session);
      let html = tMain(tEventWith(db, me.ctx, "import", "{}", tNever));
      expectHas(test, html, "That is 201 pull requests, and the ceiling is 200 in one go. Narrow it and run it again — importing twice into the same folder skips what is already there.");
    }

    test("import: lands them in a folder and says what could not be fetched") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "settings", "{\"folder\":\"temper/blimp\",\"commits\":\"true\"}");
      let html = tMain(tEvent(db, me.ctx, "import", "{}"));
      expectHas(test, html, "3 drafts imported.");
      expectHas(test, html, "Could not be fetched");
      expectHas(test, html, "#7 Add a test — No such repository, or the token cannot see it.");
      expectText(test, tTitles(db), "Fix the parser|Nothing to do with it|Revert the fix");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works WHERE folder_id IS NOT NULL"), 3);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders WHERE name = 'temper/blimp'"), 1);
      expectHas(test, html, "<a href=\"/stacks/");
      expectHas(test, html, "phx-click=\"restart\">import some more</button>");
    }

    test("import: the boxes have the last word over the regex") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "pattern", "{\"how\":\"regex\",\"pattern\":\"fix\"}");
      tEvent(db, me.ctx, "toggle", "{\"key\":\"temper/blimp#6\"}");
      tEvent(db, me.ctx, "settings", "{\"folder\":\"Picked\",\"commits\":\"false\"}");
      tEvent(db, me.ctx, "import", "{}");
      expectText(test, tTitles(db), "Fix the parser|Nothing to do with it|Revert the fix");
    }

    let tRunTwice(db: Db, who: Ctx): String throws Bubble {
      tGet(db, who, "/import");
      tToListing(db, who);
      tEvent(db, who, "settings", "{\"folder\":\"temper/blimp\"}");
      tMain(tEvent(db, who, "import", "{}"))
    }

    test("import: a second import into the same folder skips what is there") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tRunTwice(db, me.ctx);
      let html = tRunTwice(db, me.ctx);
      expectHas(test, html, "0 drafts imported.");
      expectHas(test, html, "3 were already in the folder under the same title and were left alone.");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works"), 3);
    }

    test("import: the order can be flipped, and numbering follows it") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "order", "{\"order\":\"newest\"}");
      tEvent(db, me.ctx, "settings", "{\"folder\":\"Backwards\",\"number\":\"true\"}");
      tEvent(db, me.ctx, "import", "{}");
      expectText(test, tTitles(db), "1. Fix the parser|2. Nothing to do with it|3. Revert the fix");
    }

    test("import: a clean import is the end of the wizard: on to the folder, with the flash") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"-number:7\"}");
      tEvent(db, me.ctx, "settings", "{\"folder\":\"Clean\"}");
      let r = tEvent(db, me.ctx, "import", "{}");
      let folder = db.one("SELECT id FROM folders WHERE name = 'Clean'", []);
      expectTrue(test, folder != null, "the folder exists");
      if (folder != null) {
        expectText(test, tRedirect(r), "/stacks/${folder.int("id").toString()}");
      }
      expectText(test, r.ctx.session.flash.getOr("info", ""), "3 drafts imported.");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works"), 3);
      expectHas(test, tBody(tGet(db, me.ctx, "/import")), "<span class=\"mg-label\">GitHub</span>");
    }

    let tCleanImport(db: Db, who: Ctx): TRun throws Bubble {
      tGet(db, who, "/import");
      tToListing(db, who);
      tEvent(db, who, "pattern", "{\"how\":\"query\",\"pattern\":\"-number:7\"}");
      tEvent(db, who, "settings", "{\"folder\":\"Clean\"}");
      tEvent(db, who, "import", "{}")
    }

    test("import: a clean import that skipped some says how many") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tCleanImport(db, me.ctx);
      let again = tCleanImport(db, me.ctx);
      expectText(test, again.ctx.session.flash.getOr("info", ""), "0 drafts imported, 3 already there and left alone.");
    }

    test("import: with the folder box empty the drafts stay loose, and the results are shown") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "pattern", "{\"how\":\"query\",\"pattern\":\"-number:7\"}");
      tEvent(db, me.ctx, "settings", "{\"folder\":\"\"}");
      let html = tMain(tEvent(db, me.ctx, "import", "{}"));
      expectHas(test, html, "3 drafts imported.");
      expectHas(test, html, "<a href=\"/works\" class=\"mg-btn\">Every draft</a>");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works WHERE folder_id IS NULL"), 3);
    }

    test("import: the settings in the submit are the ones used") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "import", "{\"folder\":\"From submit\",\"commits\":\"false\",\"files\":\"false\",\"number\":\"true\"}");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders WHERE name = 'From submit'"), 1);
      expectText(test, tTitles(db), "1. Revert the fix|2. Nothing to do with it|3. Fix the parser");
    }

    test("import: a second one while the first is going is refused") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEventWith(db, me.ctx, "import", "{}", tQueue);
      let again = tEventWith(db, me.ctx, "import", "{}", tQueue);
      expectHas(test, tMain(again), "Reading them off GitHub");
      expectHas(test, tMain(again), "An import is already running.");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM runs WHERE status = 'running'"), 1);
    }

    test("import: the run is keyed by the session, not by the cookie itself") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let r = tEventWith(db, me.ctx, "import", "{}", tQueue);
      let key = pimRunKey(r.ctx);
      expectHas(test, key, "import:");
      expectLacks(test, key, me.ctx.session.id);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM runs WHERE key = '${key}'"), 1);
    }

## Watching an import

    test("running: the page shows the bar and asks to be fetched again in two seconds") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let r = tEventWith(db, me.ctx, "import", "{}", tQueue);
      let main = tMain(r);
      expectHas(test, main, "<p class=\"mg-label\">Reading them off GitHub</p>");
      expectHas(test, main, "0 of 4");
      expectHas(test, main, "data-poll=\"2\"");
      let key = pimRunKey(r.ctx);
      db.exec("UPDATE runs SET progress = '2/3', detail = 'fetching' WHERE key = $1", [key]);
      let poll = tMain(tPoll(db, me.ctx));
      expectHas(test, poll, "width:67%");
      expectHas(test, poll, "2 of 3");
      db.exec("UPDATE runs SET progress = '1/3', detail = 'landing' WHERE key = $1", [key]);
      let landing = tBody(tGet(db, me.ctx, "/import"));
      expectHas(test, landing, "Filing them");
      expectHas(test, landing, "data-poll=\"2\"");
    }

    test("running: a page load keeps the import on screen rather than starting over") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEventWith(db, me.ctx, "import", "{}", tQueue);
      let body = tBody(tGet(db, me.ctx, "/import"));
      expectHas(test, body, "Reading them off GitHub");
      expectLacks(test, body, "<span class=\"mg-label\">GitHub</span><b>Pull requests</b>");
    }

    test("running: a run that finished while nobody looked is concluded by the next poll") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "settings", "{\"folder\":\"Later\"}");
      let r = tEventWith(db, me.ctx, "import", "{}", tQueue);
      let key = pimRunKey(r.ctx);
      let picked = [
        tCand("temper/blimp", 8, "Revert the fix", "open", false, null),
        tCand("temper/blimp", 7, "Add a test", "closed", true, null),
        tCand("temper/blimp", 6, "Nothing to do with it", "open", false, null),
        tCand("temper/blimp", 9, "Fix the parser", "merged", false, null),
      ];
      pagesImportJob(db, me.scope, key, tFake(), new PimJob("", picked, false, false, "Later", false));
      let poll = tMain(tPoll(db, me.ctx));
      expectHas(test, poll, "3 drafts imported.");
      expectHas(test, poll, "Could not be fetched");
      expectLacks(test, poll, "data-poll");
    }

    test("running: a run that crashed ends on the results step with the reason") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      let r = tEventWith(db, me.ctx, "import", "{}", tQueue);
      let key = pimRunKey(r.ctx);
      db.exec("UPDATE runs SET status = 'crashed', detail = 'Bubble: disk full', finished_at = '2026-01-01 10:05:00' WHERE key = $1", [key]);
      let html = tMain(tPoll(db, me.ctx));
      expectHas(test, html, "<p class=\"cut-err mt-4\">The import crashed: Bubble: disk full</p>");
      expectHas(test, html, "start again");
      expectLacks(test, html, "data-poll");
    }

    test("running: a run whose row is gone is a crash too, not a page that polls for ever") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEventWith(db, me.ctx, "import", "{}", tQueue);
      db.exec("DELETE FROM runs", []);
      let html = tMain(tPoll(db, me.ctx));
      expectHas(test, html, "The import crashed: its run is gone.");
      expectLacks(test, html, "data-poll");
    }

    test("running: the job reports its progress and its result in the run row") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tToListing(db, me.ctx);
      tEvent(db, me.ctx, "settings", "{\"folder\":\"Reported\"}");
      let imported = tEvent(db, me.ctx, "import", "{}");
      let run = runsGet(db, pimRunKey(imported.ctx));
      expectTrue(test, run != null, "the run row is kept");
      if (run != null) {
        expectText(test, run.status, "done");
        expectText(test, pimOr(run.progress, ""), "3/3");
        let result = pimResultFrom(pimOr(run.detail, ""));
        expectTrue(test, result != null, "the detail is a result");
        if (result != null) {
          expectInt(test, result.created, 3);
          expectInt(test, result.missed.length, 1);
          expectInt(test, result.missed[0].number, 7);
        }
      }
    }

## Events that belong to the live upload

    test("events: validate and drop_file change nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"files\"}");
      let a = tMain(tEvent(db, me.ctx, "validate", "{\"folder\":\"x\"}"));
      let b = tMain(tEvent(db, me.ctx, "drop_file", "{\"ref\":\"0\"}"));
      expectText(test, a, b);
      expectHas(test, a, "id=\"im-files\"");
    }

    test("events: import_files as an event can not carry a file, and says so") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tEvent(db, me.ctx, "source", "{\"to\":\"files\"}");
      expectHas(test, tMain(tEvent(db, me.ctx, "import_files", "{\"folder\":\"x\"}")), "No files yet — drop some in.");
    }

    test("events: one the page does not have is a crash with its name") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let bubbled = do { tEvent(db, me.ctx, "frobnicate", "{}"); false } orelse true;
      expectTrue(test, bubbled, "an unknown event bubbles");
    }

## Files dropped on the page

    test("files: a folder named for what they share, filed in the order their names say") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let files = [
        tPartFile("chapter-03.md", tChapter("Three")), tPartFile("chapter-01.md", tChapter("One")),
        tPartFile("chapter-02.md", tChapter("Two")),
      ];
      let r = tPostFiles(db, me.ctx, files, "", false);
      expectInt(test, r.resp.status, 303);
      let folder = db.one("SELECT id, name FROM folders", []);
      expectTrue(test, folder != null, "a folder was made");
      if (folder != null) {
        expectText(test, folder.str("name"), "chapter");
        expectText(test, tLocation(r), "/stacks/${folder.int("id").toString()}");
      }
      expectText(test, tTitles(db), "chapter-01|chapter-02|chapter-03");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works WHERE folder_id IS NOT NULL"), 3);
      expectText(test, r.ctx.session.flash.getOr("info", ""), "3 drafts imported.");
    }

    test("files: numbering follows the natural order of the names") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let files = [tPartFile("chapter-10.md", tChapter("Ten")), tPartFile("chapter-2.md", tChapter("Two"))];
      tPostFiles(db, me.ctx, files, "", true);
      expectText(test, tTitles(db), "1. chapter-2|2. chapter-10");
    }

    test("files: the folder box wins when it is filled in") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tPostFiles(db, me.ctx, [tPartFile("a.md", tChapter("A")), tPartFile("b.md", tChapter("B"))], "  My book  ", false);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders WHERE name = 'My book'"), 1);
    }

    test("files: one file is a folder named for it") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tPostFiles(db, me.ctx, [tPartFile("notes.md", tChapter("Notes"))], "", false);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders WHERE name = 'notes'"), 1);
    }

    test("files: files with nothing in common are filed under the moment") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tPostFiles(db, me.ctx, [tPartFile("apple.md", tChapter("A")), tPartFile("zebra.md", tChapter("Z"))], "", false);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders WHERE name LIKE 'Imported 20%'"), 1);
    }

    test("files: a file that is not text or markdown is named beside the ones that went in") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let files = [tPartFile("good.md", tChapter("Good")), tPartFile("scan.pdf", "%PDF-1.4 binary")];
      let r = tPostFiles(db, me.ctx, files, "Mixed", false);
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "1 draft imported.");
      expectHas(test, body, "Not imported");
      expectHas(test, body, "scan.pdf — not a text or markdown file");
      expectText(test, tTitles(db), "good");
    }

    test("files: an empty file fails alone and says why") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tPostFiles(db, me.ctx, [tPartFile("full.md", tChapter("Full")), tPartFile("empty.md", "")], "Two", false);
      let body = tBody(r);
      expectHas(test, body, "1 draft imported.");
      expectHas(test, body, "empty — there is no text in it");
      expectText(test, tTitles(db), "full");
    }

    test("files: importing the same files again skips them and shows the results") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let files = [tPartFile("a.md", tChapter("A")), tPartFile("b.md", tChapter("B"))];
      tPostFiles(db, me.ctx, files, "Twice", false);
      let r = tPostFiles(db, me.ctx, files, "Twice", false);
      expectInt(test, r.resp.status, 303);
      expectText(test, r.ctx.session.flash.getOr("info", ""), "0 drafts imported, 2 already there and left alone.");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works"), 2);
    }

    test("files: nothing chosen is refused with the sentence, and the step stays") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tPostFiles(db, me.ctx, [], "", false);
      expectInt(test, r.resp.status, 422);
      expectHas(test, tBody(r), "No files yet — drop some in.");
      expectHas(test, tBody(r), "id=\"im-files\"");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders"), 0);
    }

    test("files: more than forty is refused whole") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let files = new ListBuilder<String>();
      var n = 1;
      while (n <= 41) {
        files.add(tPartFile("f${n.toString()}.md", tChapter("F")));
        n += 1;
      }
      let r = tPostFiles(db, me.ctx, files.toList(), "", false);
      expectInt(test, r.resp.status, 422);
      expectHas(test, tBody(r), "more than 40 files");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("files: the form without its marker goes back to the wizard and does nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let body = "${tPartField("repo", "temper/blimp")}${tPartField("token", "ghp_x")}--XB--\r\n";
      let req = tRaw("POST", "/import", "${tCookieHeader(me.ctx)}Content-Type: multipart/form-data; boundary=XB\r\n", body);
      let r = tServe(db, req, tMatch("POST", "/import"));
      expectInt(test, r.resp.status, 303);
      expectText(test, tLocation(r), "/import");
    }

    test("files: the drafts are the guest's own") { test =>
      let db = dbOpen(":memory:");
      let first = tGet(db, null, "/import");
      tPostFiles(db, first.ctx, [tPartFile("g.md", tChapter("G"))], "", false);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works w JOIN users u ON u.id = w.user_id WHERE u.is_guest = 1"), 1);
    }
