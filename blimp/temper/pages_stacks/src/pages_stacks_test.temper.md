# Tests for pages_stacks

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse` and go through the router
in miniature: context, scope, the `guest.` plug, the group.

`runsStart` refuses `:memory:`, so the group is given launchers (see
`pagesStacksGetWith` and `pagesStacksEventWith`): one that only writes the
`running` row a real start would have written (`tQueue`), one that also runs
the pass inline through `pagesStacksRun` with a canned model (`tInline`), and
for the import one that records what it was given (`tImportQueue`).

    let { dbOpen, Db } = import("db/src");
    let { Request, Response, Route, Match, httpParse, routeMatch } = import("http/src");
    let { Scope, scopeFor, accountsGetUser, accountsGenerateUserSessionToken } = import("accounts/src");
    let {
      Ctx, webNewCtx, webMountCurrentScope, webEnsureUserOrGuest, webSessionCookieName, webSaveSession,
    } = import("webcore/src");
    let { Work, workParams, worksCreateWork } = import("works/src");
    let { Folder, foldersCreateFolder, foldersMoveWork } = import("folders/src");
    let {
      stacksRunKey, stacksListSteps, stacksGetStory, stacksStoryFingerprint, stacksDocuments,
    } = import("stacks/src");
    let { runsCounts, runsGet } = import("runs/src");
    let { LlmClient, llmFake } = import("llm/src");
    let { JsonObject, JsonString, JsonTextProducer, JsonSyntaxTree, parseJson } = import("std/json");
    let { sysStringReplace } = import("sys/src");

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
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${body.split("").length.toString()}\r\n\r\n${body}")
    }

    let tMatch(method: String, path: String): Match throws Bubble {
      let m = routeMatch(pagesStacksRoutes(), method, path);
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
      let carrier = webNewCtx(db, ":memory:", tRaw("GET", "/stacks", "", ""), tMatch("GET", "/stacks").params);
      let row = db.one("SELECT id FROM users_tokens WHERE token = $1", [token]);
      if (row != null) { carrier.session.userTokenId = row.int("id"); }
      carrier.session.dirty = true;
      webSaveSession(db, carrier.session);
      new TWho(id, scopeFor(user), carrier)
    }

    let tRepeat(n: Int): String {
      let parts = new ListBuilder<String>();
      for (var i = 0; i < n; ++i) { parts.add("word "); }
      parts.toList().join("") { (x: String): String => x }
    }

    let tDraft(db: Db, s: Scope, title: String): Work throws Bubble {
      let body = "# ${title}\n\nThe first paragraph of ${title}, which is long enough to stand alone.\n\nA second paragraph with something quotable in it.\n\n${tRepeat(120)}";
      let r = worksCreateWork(db, s, workParams(title, body));
      let w = r.ok;
      if (w != null) { w } else { bubble() }
    }

    let tFolder(db: Db, s: Scope, name: String, parent: Folder?): Folder throws Bubble {
      let parentId = if (parent != null) { parent.id } else { null };
      let r = foldersCreateFolder(db, s, name, parentId);
      let f = r.folder;
      if (f != null) { f } else { bubble() }
    }

    let tMove(db: Db, s: Scope, w: Work, f: Folder): Void throws Bubble {
      let r = foldersMoveWork(db, s, w.id, f.id);
      if (!r.ok) { bubble(); }
    }

A folder of `n` numbered documents, "1. Doc 1" onwards.

    let tStack(db: Db, s: Scope, name: String, n: Int): Folder throws Bubble {
      let f = tFolder(db, s, name, null);
      var i = 1;
      while (i <= n) {
        tMove(db, s, tDraft(db, s, "${i.toString()}. Doc ${i.toString()}"), f);
        i += 1;
      }
      f
    }

A step row inserted directly, as the Elixir tests did with `Repo.insert!`.

    let tStep(db: Db, f: Folder, ordinal: Int, capability: String, requires: String): Void throws Bubble {
      let docs = stacksDocuments(db, scopeFor(accountsGetUser(db, f.userId)), f.id);
      let w = docs[ordinal - 1];
      db.exec(
        "INSERT INTO stack_steps (folder_id, work_id, ordinal, capability, requires, lesson) VALUES ($1, $2, $3, $4, $5, $6)",
        [f.id.toString(), w.id.toString(), ordinal.toString(), capability, requires, "Lesson ${ordinal.toString()}."],
      );
    }

A folder that has been read: `n` documents, each with a step "cap 1"...

    let tRead(db: Db, s: Scope, name: String, n: Int): Folder throws Bubble {
      let f = tStack(db, s, name, n);
      var i = 1;
      while (i <= n) {
        tStep(db, f, i, "cap ${i.toString()}", "[]");
        i += 1;
      }
      f
    }

A run row, as `runsStart` and a job would leave it.

    let tRunning(db: Db, f: Folder, progress: String, detail: String): Void throws Bubble {
      db.exec(
        "INSERT OR REPLACE INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ($1, 'running', $2, $3, NULL, '2026-01-01 10:00:00', NULL)",
        [stacksRunKey(f.id), progress, detail],
      );
    }

    let tEnded(db: Db, f: Folder, status: String, detail: String): Void throws Bubble {
      db.exec(
        "UPDATE runs SET status = $1, detail = $2, finished_at = '2026-01-01 10:05:00' WHERE key = $3",
        [status, detail, stacksRunKey(f.id)],
      );
    }

    let tRunRow(db: Db, f: Folder): String throws Bubble {
      let r = runsGet(db, stacksRunKey(f.id));
      if (r != null) {
        "${r.status}|${if (r.progress != null) { r.progress } else { "-" }}|${if (r.detail != null) { r.detail } else { "-" }}"
      } else { "none" }
    }

    let tN(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

A chat completion whose one tool call is `name` with `args` (single-quoted
JSON) as its arguments.

    let tToolReply(name: String, args: String): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("message");
      p.startObject();
      p.objectKey("role");
      p.stringValue("assistant");
      p.objectKey("content");
      p.nullValue();
      p.objectKey("tool_calls");
      p.startArray();
      p.startObject();
      p.objectKey("id");
      p.stringValue("call_1");
      p.objectKey("type");
      p.stringValue("function");
      p.objectKey("function");
      p.startObject();
      p.objectKey("name");
      p.stringValue(name);
      p.objectKey("arguments");
      p.stringValue(sysStringReplace(args, "'", "\""));
      p.endObject();
      p.endObject();
      p.endArray();
      p.endObject();
      p.objectKey("finish_reason");
      p.stringValue("tool_calls");
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

    let tStepReply(capability: String): String throws Bubble {
      tToolReply("report_step", "{'capability':'${capability}','requires':[],'lesson':'Do ${capability}.','pitfall':'','pitfall_quote':'','excerpts':[]}")
    }

## The launchers

`tQueue` is the production start without the fork: the row `runsStart` would
have written, with the page's first report. Refused (`false`) when the key is
taken, as `runsStart` refuses.

    let tQueue(ctx: Ctx, kind: String, f: Folder, total: Int): Boolean throws Bubble {
      let taken = tN(ctx.db, "SELECT count(*) AS n FROM runs WHERE key = '${stacksRunKey(f.id)}' AND status = 'running'");
      if (taken > 0) { return false; }
      tRunning(ctx.db, f, runsCounts(0, total), kind);
      true
    }

`tInline` runs the pass in-process after queueing it.

    let tInline(ctx: Ctx, kind: String, f: Folder, total: Int, llm: LlmClient): Boolean throws Bubble {
      let queued = tQueue(ctx, kind, f, total);
      if (queued) { pagesStacksRun(ctx.db, llm, kind, ctx.scope, f); }
      queued
    }

    let tNever(ctx: Ctx, kind: String, f: Folder, total: Int): Boolean throws Bubble {
      console.log("the launcher should not have been called");
      bubble()
    }

The import: a `running` row under the user's key whose detail carries what
the launcher was given, so a test reads the arguments back.

    let tImportQueue(ctx: Ctx, owner: String, repo: String, token: String, folder: String, state: String): Boolean throws Bubble {
      let key = pagesStacksImportKey(ctx.scope.userId);
      let taken = tN(ctx.db, "SELECT count(*) AS n FROM runs WHERE key = '${key}' AND status = 'running'");
      if (taken > 0) { return false; }
      ctx.db.exec(
        "INSERT OR REPLACE INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ($1, 'running', '0/0', $2, NULL, '2026-01-01 10:00:00', NULL)",
        [key, "import:${owner}~${repo}~${token}~${folder}~${state}"],
      );
      true
    }

    let tImportNever(ctx: Ctx, owner: String, repo: String, token: String, folder: String, state: String): Boolean throws Bubble {
      console.log("the import launcher should not have been called");
      bubble()
    }

## Requests

    let tServe(db: Db, req: Request, match: Match): TRun throws Bubble {
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let denied = webEnsureUserOrGuest(ctx);
      if (denied != null) { new TRun(ctx, denied) } else { new TRun(ctx, pagesStacksGetWith(ctx, match, tImportQueue)) }
    }

    let tGet(db: Db, who: Ctx?, path: String): TRun throws Bubble {
      let bare = path.split("?").getOr(0, path);
      tServe(db, tRaw("GET", path, tCookieHeader(who), ""), tMatch("GET", bare))
    }

The poll: the same page fetched the way `blimp.js` fetches it.

    let tPoll(db: Db, who: Ctx, path: String): TRun throws Bubble {
      tServe(db, tRaw("GET", path, "${tCookieHeader(who)}X-Requested-With: blimp\r\nAccept: application/json\r\n", ""), tMatch("GET", path))
    }

    let tEventWith(
      db: Db, who: Ctx, page: String, name: String, payload: String,
      pass: fn (Ctx, String, Folder, Int): Boolean throws Bubble,
      importing: fn (Ctx, String, String, String, String, String): Boolean throws Bubble,
    ): TRun throws Bubble {
      let req = tRaw("POST", "/ev/${name}", "${tCookieHeader(who)}X-Requested-With: blimp\r\nContent-Type: application/json\r\n", "{\"payload\":${payload},\"path\":\"${page}\"}");
      let match = tMatch("GET", page);
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let tree: JsonSyntaxTree = parseJson(payload);
      if (tree is JsonObject) {
        new TRun(ctx, pagesStacksEventWith(ctx, match, name, tree, pass, importing))
      } else { bubble() }
    }

    let tEvent(db: Db, who: Ctx, page: String, name: String, payload: String): TRun throws Bubble {
      tEventWith(db, who, page, name, payload, tQueue, tImportQueue)
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

## Routes

    test("routes: the literal pages come before the ones with variables, in router.ex order") { test =>
      let names = pagesStacksRoutes().map { (r: Route): String => "${r.method} ${r.pattern}" };
      expectText(test, names.join(", ") { (x: String): String => x },
        "GET /stacks, GET /stacks/new, POST /stacks/new, GET /stacks/:id, GET /stacks/:id/story, GET /stacks/:id/:ordinal");
    }

    test("routes: /stacks/new is the import page, not a folder called new") { test =>
      expectText(test, tMatch("GET", "/stacks/new").route.name, "guest.stacks_new");
      expectText(test, tMatch("GET", "/stacks/12").route.name, "guest.stacks_show");
      expectText(test, tMatch("GET", "/stacks/12").params.getOr("id", ""), "12");
    }

    test("routes: /stacks/:id/story is the telling, not step story") { test =>
      expectText(test, tMatch("GET", "/stacks/12/story").route.name, "guest.stacks_story");
      let step = tMatch("GET", "/stacks/12/3");
      expectText(test, step.route.name, "guest.stacks_step");
      expectText(test, step.params.getOr("ordinal", ""), "3");
    }

    test("routes: every one is a guest route") { test =>
      for (let r of pagesStacksRoutes()) {
        expectTrue(test, hasText(r.name, "guest."), r.name);
      }
    }

## The index

    test("index: nothing to read is the empty state and no rows") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tGet(db, me.ctx, "/stacks");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<h1 style=\"font-family:var(--mg-serif)\" class=\"text-2xl font-semibold tracking-tight\">Methods</h1>");
      expectHas(test, body, "<span class=\"mg-meta\">0 readable folders</span>");
      expectHas(test, body, "Nothing here yet. Put some drafts in a folder and it becomes readable.");
      expectHas(test, body, "<a href=\"/import\" class=\"mg-btn sm ghost ml-auto\">Import many</a>");
      expectHas(test, body, "<a href=\"/stacks/new\" class=\"mg-btn sm\">Import a stack</a>");
      expectHas(test, body, "<em>forwards</em>");
      expectHas(test, body, "Methods · Marginalia");
      expectLacks(test, body, "cut-row");
    }

    test("index: a folder of documents is a row, with its counts and no pluralisation") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Phoenix 1.8", 1);
      let body = tBody(tGet(db, me.ctx, "/stacks"));
      expectHas(test, body, "<span class=\"mg-meta\">1 readable folders</span>");
      expectHas(test, body, "id=\"stack-row-${f.id.toString()}\" class=\"cut-row\" style=\"padding-left:0.0rem\"");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}\" style=\"font-family:var(--mg-serif)\" class=\"text-[1.05rem] hover:text-[var(--mg-accent)]\">Phoenix 1.8</a>");
      expectHas(test, body, "1 documents");
      expectLacks(test, body, "· 0 read");
      expectLacks(test, body, "mg-badge ink");
    }

    test("index: a folder that has been read says so, and is badged") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tRead(db, me.scope, "Read", 2);
      let f = tFolder(db, me.scope, "Not yet", null);
      tMove(db, me.scope, tDraft(db, me.scope, "1. Lone"), f);
      let body = tBody(tGet(db, me.ctx, "/stacks"));
      expectHas(test, body, "2 documents");
      expectHas(test, body, "<span>· 2 read</span>");
      expectHas(test, body, "<span class=\"mg-badge ink\">read</span>");
      expectInt(test, body.split("mg-badge ink").length - 1, 1);
    }

    test("index: a folder with no documents of its own is not listed, a subfolder's are its own") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let top = tFolder(db, me.scope, "Top", null);
      let leaf = tFolder(db, me.scope, "Leaf", top);
      tMove(db, me.scope, tDraft(db, me.scope, "1. One"), leaf);
      let body = tBody(tGet(db, me.ctx, "/stacks"));
      expectHas(test, body, "<span class=\"mg-meta\">1 readable folders</span>");
      expectLacks(test, body, "stack-row-${top.id.toString()}");
      expectHas(test, body, "id=\"stack-row-${leaf.id.toString()}\" class=\"cut-row\" style=\"padding-left:1.4rem\"");
    }

    test("index: folders are listed depth first, indented 1.4rem a level") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let top = tFolder(db, me.scope, "Top", null);
      let mid = tFolder(db, me.scope, "Mid", top);
      let leaf = tFolder(db, me.scope, "Leaf", mid);
      tMove(db, me.scope, tDraft(db, me.scope, "1. A"), top);
      tMove(db, me.scope, tDraft(db, me.scope, "1. B"), mid);
      tMove(db, me.scope, tDraft(db, me.scope, "1. C"), leaf);
      let body = tBody(tGet(db, me.ctx, "/stacks"));
      expectHas(test, body, "stack-row-${top.id.toString()}\" class=\"cut-row\" style=\"padding-left:0.0rem\"");
      expectHas(test, body, "stack-row-${mid.id.toString()}\" class=\"cut-row\" style=\"padding-left:1.4rem\"");
      expectHas(test, body, "stack-row-${leaf.id.toString()}\" class=\"cut-row\" style=\"padding-left:2.8rem\"");
      let at = body.split("id=\"stack-row-");
      expectTrue(test, hasText(at.getOr(1, ""), ">Top<") && hasText(at.getOr(2, ""), ">Mid<") && hasText(at.getOr(3, ""), ">Leaf<"), "Top, Mid, Leaf in that order");
    }

    test("index: stale steps are called out (a step with no fingerprint is stale), pitfalls counted") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      db.exec("UPDATE stack_steps SET pitfall = 'p', fingerprint = 'old' WHERE ordinal = 1", []);
      let body = tBody(tGet(db, me.ctx, "/stacks"));
      expectHas(test, body, "<span>· 1 pitfalls</span>");
      expectHas(test, body, "<span class=\"cut-err\">· 2 stale</span>");
    }

    test("index: somebody else's folders are not in this list") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let them = tWho(db, "b@example.com");
      tStack(db, them.scope, "Theirs", 2);
      let body = tBody(tGet(db, me.ctx, "/stacks"));
      expectHas(test, body, "0 readable folders");
      expectLacks(test, body, "Theirs");
    }

    test("index: a visitor is given a guest and sees the same empty list") { test =>
      let db = dbOpen(":memory:");
      let r = tGet(db, null, "/stacks");
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBody(r), "0 readable folders");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM users WHERE is_guest = 1"), 1);
    }

## /stacks/new

    test("new: the import page is its own page, with the repo and token fields") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tGet(db, me.ctx, "/stacks/new");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "Import a stack");
      expectHas(test, body, "name=\"repo\"");
      expectHas(test, body, "name=\"token\"");
      expectHas(test, body, "type=\"password\"");
      expectHas(test, body, "placeholder=\"used for this fetch, never stored\"");
      expectHas(test, body, "placeholder=\"defaults to owner/name\"");
      expectHas(test, body, "<option value=\"open\" selected>Open</option>");
      expectHas(test, body, "<option value=\"all\">All, open and closed</option>");
      expectHas(test, body, "phx-submit=\"import\"");
      expectHas(test, body, "phx-change=\"form\"");
      expectHas(test, body, "<button class=\"mg-btn\" type=\"submit\">Import</button>");
      expectHas(test, body, "<a href=\"/stacks\">← every method</a>");
      expectHas(test, body, "<a href=\"/import\">import in bulk</a>");
      expectLacks(test, body, "data-poll");
    }

    test("new: typing keeps the fields, the placeholder follows the repo, the token is not kept") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEvent(db, me.ctx, "/stacks/new", "form", "{\"repo\":\"o/r\",\"token\":\"ghp_secret\",\"folder\":\"\",\"state\":\"all\"}");
      let main = tMain(r);
      expectHas(test, main, "value=\"o/r\"");
      expectHas(test, main, "placeholder=\"o/r\"");
      expectHas(test, main, "<option value=\"all\" selected>");
      expectLacks(test, main, "ghp_secret");
      let again = tBody(tGet(db, r.ctx, "/stacks/new"));
      expectHas(test, again, "value=\"o/r\"");
      expectLacks(test, again, "ghp_secret");
      expectLacks(test, tBody(tGet(db, r.ctx, "/stacks")), "ghp_secret");
      let stored = tN(db, "SELECT count(*) AS n FROM sessions WHERE data LIKE '%ghp_secret%'");
      expectInt(test, stored, 0);
    }

    test("new: a repository that is not owner/name is told so, and kept") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEventWith(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"  justaname \",\"token\":\"\",\"folder\":\"\",\"state\":\"open\"}", tNever, tImportNever);
      let main = tMain(r);
      expectHas(test, main, "<p class=\"cut-err\">Write the repository as owner/name.</p>");
      expectHas(test, main, "value=\"justaname\"");
      expectLacks(test, main, "Importing…");
    }

    test("new: owner/ and /name are not owner/name either") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tEventWith(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"owner/\"}", tNever, tImportNever);
      expectHas(test, tMain(a), "Write the repository as owner/name.");
      let b = tEventWith(db, a.ctx, "/stacks/new", "import", "{\"repo\":\"/name\"}", tNever, tImportNever);
      expectHas(test, tMain(b), "Write the repository as owner/name.");
      let c = tEventWith(db, b.ctx, "/stacks/new", "import", "{}", tNever, tImportNever);
      expectHas(test, tMain(c), "Write the repository as owner/name.");
    }

    test("new: typing clears the error") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let bad = tEventWith(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"nope\"}", tNever, tImportNever);
      expectHas(test, tMain(bad), "cut-err");
      let typed = tEvent(db, bad.ctx, "/stacks/new", "form", "{\"repo\":\"no/pe\"}");
      expectLacks(test, tMain(typed), "cut-err");
    }

    test("new: an import is started with the fields trimmed, the folder name and the state") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEvent(db, me.ctx, "/stacks/new", "import", "{\"repo\":\" phoenixframework/phoenix \",\"token\":\" ghp_x \",\"folder\":\" My stack \",\"state\":\"all\"}");
      let main = tMain(r);
      expectHas(test, main, "Importing…");
      expectHas(test, main, "0 documents saved");
      expectHas(test, main, "disabled");
      expectHas(test, main, "data-poll=\"2\"");
      let row = db.one("SELECT detail FROM runs WHERE key = $1", [pagesStacksImportKey(me.id)]);
      expectText(test, if (row != null) { row.str("detail") } else { "-" }, "import:phoenixframework~phoenix~ghp_x~My stack~all");
    }

    test("new: the count of saved documents is the run's, singular at one") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEvent(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"o/r\"}");
      db.exec("UPDATE runs SET progress = '1/5', detail = 'import' WHERE key = $1", [pagesStacksImportKey(me.id)]);
      expectHas(test, tMain(tPoll(db, r.ctx, "/stacks/new")), "1 document saved");
      db.exec("UPDATE runs SET progress = '3/5' WHERE key = $1", [pagesStacksImportKey(me.id)]);
      expectHas(test, tMain(tPoll(db, r.ctx, "/stacks/new")), "3 documents saved");
    }

    test("new: a second import while one is going is refused, the first untouched") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let first = tEvent(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"o/r\"}");
      let second = tEvent(db, first.ctx, "/stacks/new", "import", "{\"repo\":\"x/y\"}");
      expectHas(test, tMain(second), "An import is already running.");
      let row = db.one("SELECT detail FROM runs WHERE key = $1", [pagesStacksImportKey(me.id)]);
      expectText(test, if (row != null) { row.str("detail") } else { "-" }, "import:o~r~~~open");
    }

    test("new: a finished import goes to the folder with the count, once") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEvent(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"o/r\"}");
      db.exec("UPDATE runs SET status = 'done', detail = 'import|ok:7:4:4', finished_at = '2026-01-01 10:05:00' WHERE key = $1", [pagesStacksImportKey(me.id)]);
      let done = tPoll(db, r.ctx, "/stacks/new");
      expectText(test, tRedirect(done), "/stacks/7");
      let there = tPoll(db, done.ctx, "/stacks");
      expectHas(test, tBody(there), "Imported 4 documents.");
      let again = tGet(db, done.ctx, "/stacks/new");
      expectInt(test, again.resp.status, 200);
      expectLacks(test, tBody(again), "Importing…");
    }

    test("new: some of them already there is said so") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEvent(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"o/r\"}");
      db.exec("UPDATE runs SET status = 'done', detail = 'import|ok:7:1:4', finished_at = '2026-01-01 10:05:00' WHERE key = $1", [pagesStacksImportKey(me.id)]);
      let done = tPoll(db, r.ctx, "/stacks/new");
      expectText(test, tRedirect(done), "/stacks/7");
      expectHas(test, tBody(tPoll(db, done.ctx, "/stacks")), "1 new, 3 already there.");
    }

    test("new: a failed import puts the reason under the form and the repo stays") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEvent(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"o/r\"}");
      db.exec("UPDATE runs SET status = 'done', detail = 'import|error:GitHub rejected the token.', finished_at = '2026-01-01 10:05:00' WHERE key = $1", [pagesStacksImportKey(me.id)]);
      let done = tPoll(db, r.ctx, "/stacks/new");
      let main = tMain(done);
      expectHas(test, main, "<p class=\"cut-err\">GitHub rejected the token.</p>");
      expectHas(test, main, "value=\"o/r\"");
      expectLacks(test, main, "data-poll");
    }

    test("new: an import that crashed says so") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEvent(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"o/r\"}");
      db.exec("UPDATE runs SET status = 'crashed', detail = 'Bubble', finished_at = '2026-01-01 10:05:00' WHERE key = $1", [pagesStacksImportKey(me.id)]);
      expectHas(test, tMain(tPoll(db, r.ctx, "/stacks/new")), "The import crashed: Bubble");
    }

    test("new: a page that never started an import is not moved by one that finished") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tEvent(db, me.ctx, "/stacks/new", "import", "{\"repo\":\"o/r\"}");
      let other = tWho(db, "b@example.com");
      db.exec("UPDATE runs SET status = 'done', detail = 'import|ok:7:4:4', finished_at = '2026-01-01 10:05:00' WHERE key = $1", [pagesStacksImportKey(me.id)]);
      let theirs = tGet(db, other.ctx, "/stacks/new");
      expectInt(test, theirs.resp.status, 200);
      expectLacks(test, tBody(theirs), "Importing…");
    }

    test("new: the plain post starts the same import and comes back to the page") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let page = tGet(db, me.ctx, "/stacks/new");
      let match = tMatch("POST", "/stacks/new");
      let req = tRaw("POST", "/stacks/new", "${tCookieHeader(page.ctx)}Content-Type: application/x-www-form-urlencoded\r\n", "repo=o%2Fr&token=t&folder=&state=open");
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let resp = pagesStacksGetWith(ctx, match, tImportQueue);
      expectInt(test, resp.status, 303);
      let row = db.one("SELECT detail FROM runs WHERE key = $1", [pagesStacksImportKey(me.id)]);
      expectText(test, if (row != null) { row.str("detail") } else { "-" }, "import:o~r~t~~open");
    }

    test("new: the form carries the CSRF field and posts, so no token is ever put in an address") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let body = tBody(tGet(db, me.ctx, "/stacks/new"));
      expectHas(test, body, "method=\"post\"");
      expectHas(test, body, "name=\"_csrf_token\"");
    }

## A folder that has not been read

    test("folder: an unread folder lists its documents in order and offers the first pass") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Phoenix 1.8", 3);
      let r = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "Phoenix 1.8 · Marginalia");
      expectHas(test, body, "<a href=\"/stacks\">← every method</a>");
      expectHas(test, body, "3 documents · 0 read · 0 summarised · 0 mapped · 0 related · 0 pitfalls · 0 dependencies");
      expectHas(test, body, "<button class=\"mg-btn\" phx-click=\"read\">Read forwards</button>");
      expectHas(test, body, "Not read yet. Reading is one call per document, in order, because each one is told what the ones before it established.");
      expectHas(test, body, "<span class=\"n\">1</span>1. Doc 1");
      expectHas(test, body, "<span class=\"n\">3</span>3. Doc 3");
      expectHas(test, body, "<button class=\"mg-btn ghost\" phx-click=\"read_each\">Read each document</button>");
      expectHas(test, body, "<button class=\"mg-btn ghost\" phx-click=\"summarise\">Summarise each document</button>");
      expectLacks(test, body, "phx-click=\"deepen\"");
      expectLacks(test, body, "phx-click=\"compose\"");
      expectLacks(test, body, "phx-click=\"relate\"");
      expectLacks(test, body, "st-chain");
      expectLacks(test, body, "data-poll");
      expectLacks(test, body, "disabled");
    }

    test("folder: documents without numbers come in the order they were made") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Loose", null);
      tMove(db, me.scope, tDraft(db, me.scope, "Zebra"), f);
      tMove(db, me.scope, tDraft(db, me.scope, "Apple"), f);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      let z = body.split("Zebra").getOr(0, "").split("").length;
      let a = body.split("Apple").getOr(0, "").split("").length;
      expectTrue(test, z < a, "Zebra before Apple");
    }

    test("folder: somebody else's folder, a missing one and a word are the same redirect") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let them = tWho(db, "b@example.com");
      let theirs = tStack(db, them.scope, "Theirs", 1);
      let one = tGet(db, me.ctx, "/stacks/${theirs.id.toString()}");
      expectInt(test, one.resp.status, 303);
      expectText(test, tLocation(one), "/stacks");
      let two = tGet(db, one.ctx, "/stacks/999999");
      expectText(test, tLocation(two), "/stacks");
      let three = tGet(db, two.ctx, "/stacks/abc");
      expectText(test, tLocation(three), "/stacks");
      expectHas(test, tBody(tGet(db, three.ctx, "/stacks")), "No such folder.");
    }

    test("folder: a missing folder through the poll is the redirect the client follows") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tPoll(db, me.ctx, "/stacks/999999");
      expectText(test, tRedirect(r), "/stacks");
    }

## A folder that has been read

    test("folder: a read folder shows the chain, the dependencies and the counts") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 3);
      db.exec("UPDATE stack_steps SET requires = '[1,2]', pitfall = 'Why' WHERE ordinal = 3", []);
      db.exec("UPDATE stack_steps SET revised_by = 3 WHERE ordinal = 1", []);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "3 documents · 3 read · 0 summarised · 0 mapped · 0 related · 1 pitfalls · 2 dependencies");
      expectHas(test, body, "<h2 class=\"cut-h\">The method</h2>");
      expectHas(test, body, "<li id=\"step-1\" class=\"\">");
      expectHas(test, body, "<li id=\"step-3\" class=\"has-pitfall\">");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}/3\"><span class=\"n\">3</span><span class=\"c\">cap 3</span></a>");
      expectHas(test, body, "<span class=\"dep\">needs 1, 2</span>");
      expectHas(test, body, "<span class=\"dep rev\">revised by 3</span>");
      expectHas(test, body, "Start at step 1. Every step links back to what it stands on and forward to what stands on it.");
      expectHas(test, body, "The second pass adds how each one works");
      expectHas(test, body, "<button class=\"mg-btn\" phx-click=\"read\">Read forwards again</button>");
      expectHas(test, body, "<button class=\"mg-btn ghost\" phx-click=\"deepen\">Second pass</button>");
      expectHas(test, body, "<button class=\"mg-btn ghost\" phx-click=\"compose\">Compose the telling</button>");
      expectLacks(test, body, "Not read yet");
      expectLacks(test, body, "st-story-card");
    }

    test("folder: once deepened the line counts it, the buttons change and the explanation goes") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      db.exec("UPDATE stack_steps SET deepened_at = '2026-01-01 00:00:00' WHERE ordinal = 1", []);
      db.exec("UPDATE stack_steps SET revised_by = 2 WHERE ordinal = 1", []);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "· 1 deepened · 1 revised later");
      expectHas(test, body, "phx-click=\"deepen\">Deepen again</button>");
      expectLacks(test, body, "The second pass adds how each one works");
    }

    test("folder: a failed second pass is counted and offers the retry") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      db.exec("UPDATE stack_steps SET deep_dropped = '[\"the second pass failed: boom\"]', dropped = '[\"a claim\"]' WHERE ordinal = 2", []);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "<span class=\"cut-err\">· 1 failed the second pass</span>");
      expectHas(test, body, "phx-click=\"deepen\">Retry 1 failed</button>");
      expectHas(test, body, "· 1 claims dropped");
    }

    test("folder: relate needs two documents that have been mapped, read each counts what is left") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let none = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectLacks(test, none, "Relate the documents");
      expectHas(test, none, "Read each document</button>");
      db.exec("UPDATE works SET status = 'read' WHERE id = (SELECT min(id) FROM works)", []);
      let one = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, one, "Read each document (1 left)</button>");
      expectLacks(test, one, "Relate the documents");
      db.exec("UPDATE works SET status = 'read'", []);
      let two = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, two, "phx-click=\"relate\">Relate the documents</button>");
      expectLacks(test, two, "phx-click=\"read_each\"");
      expectHas(test, two, "0 related");
    }

    test("folder: summarising counts the documents that have a summary") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let first = stacksDocuments(db, me.scope, f.id)[0];
      db.exec("INSERT INTO document_summaries (work_id, summary) VALUES ($1, 'It says things.')", [first.id.toString()]);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "1 summarised");
      expectHas(test, body, "Summarise the other 1</button>");
      db.exec("INSERT INTO document_summaries (work_id, summary) VALUES ($1, 'More.')", [stacksDocuments(db, me.scope, f.id)[1].id.toString()]);
      let all = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectLacks(test, all, "phx-click=\"summarise\"");
    }

## A page that arrives mid-pass

    test("run: a page that arrives mid-read shows the read, not the button") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "4/12", "read");
      let r = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      let body = tBody(r);
      expectHas(test, body, "4 of 12");
      expectHas(test, body, "you can close the page");
      expectHas(test, body, "each document waits on the one before it.");
      expectHas(test, body, "disabled");
      expectHas(test, body, "data-poll=\"2\"");
      expectHas(test, body, "<p class=\"st-progress\" style=\"--done:33%\"><span></span></p>");
      expectLacks(test, body, "<button class=\"mg-btn\" phx-click=\"read\">");
    }

    test("run: every button is disabled while a pass runs") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      tRunning(db, f, "0/2", "read");
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "<button class=\"mg-btn\" phx-click=\"read\" disabled>");
      expectHas(test, body, "phx-click=\"deepen\" disabled>");
      expectHas(test, body, "phx-click=\"compose\" disabled>");
      expectHas(test, body, "phx-click=\"summarise\" disabled>");
      expectHas(test, body, "phx-click=\"read_each\" disabled>");
    }

    test("run: the progress bar is the done share of the total, 0% with no total") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "0/0", "relate");
      expectHas(test, tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}")), "style=\"--done:0%\"");
      tRunning(db, f, "2/3", "read");
      expectHas(test, tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}")), "style=\"--done:67%\"");
      tRunning(db, f, "12/12", "read");
      expectHas(test, tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}")), "style=\"--done:100%\"");
    }

    test("run: a page that arrives mid-compose says which part it is on") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "2/5", "compose:writing");
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "Composing — part 2 of 5");
      expectHas(test, body, "<b>Composing — part 2 of 5.</b>");
      expectHas(test, body, "Composing runs on the server too.");
      expectHas(test, body, "data-poll=\"2\"");
      expectLacks(test, body, "st-progress");
      expectLacks(test, body, "of 5 —");
    }

    test("run: composing before there is a stage is the ellipsis, outlining is the stage") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "0/0", "compose");
      let bare = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, bare, "Composing…");
      expectLacks(test, bare, "<b>");
      tRunning(db, f, "0/0", "compose:outlining");
      let outline = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, outline, "Composing — outlining");
    }

    test("run: an open page follows a pass it did not start, and lets go when it ends") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let first = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      expectLacks(test, tBody(first), "Composing");
      tRunning(db, f, "0/0", "compose:outlining");
      let during = tPoll(db, first.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tMain(during), "Composing — outlining");
      expectHas(test, tMain(during), "data-poll=\"2\"");
      tEnded(db, f, "done", "compose|ok");
      let after = tPoll(db, during.ctx, "/stacks/${f.id.toString()}");
      expectLacks(test, tMain(after), "Composing —");
      expectLacks(test, tMain(after), "data-poll");
    }

    test("run: the summarise pass has its own sentence") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "1/3", "summarise");
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "1 of 3");
      expectHas(test, body, "one whole-document summary each");
      expectLacks(test, body, "waits on the one before it");
    }

    test("run: relating and reading each have theirs") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "2/5", "relate:relating");
      let relate = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, relate, "2 of 5");
      expectHas(test, relate, "one call per pair");
      expectLacks(test, relate, "waits on the one before it");
      tRunning(db, f, "1/4", "read_each");
      let each = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, each, "the ordinary read of each one, sections at a time.");
    }

    test("run: a progress tick shows the work, not only the count") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Method", 2);
      tStep(db, f, 1, "the first capability", "[]");
      tRunning(db, f, "1/2", "read");
      let one = tPoll(db, me.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tMain(one), "the first capability");
      expectLacks(test, tMain(one), "the second capability");
      tStep(db, f, 2, "the second capability", "[1]");
      db.exec("UPDATE runs SET progress = '2/2'", []);
      let two = tPoll(db, one.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tMain(two), "2 of 2");
      expectHas(test, tMain(two), "the second capability");
    }

    test("run: a job whose process is gone is given up on, and the page says so") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let first = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      tRunning(db, f, "1/2", "read");
      db.exec("UPDATE runs SET pid = 2147483646", []);
      let after = tPoll(db, first.ctx, "/stacks/${f.id.toString()}");
      expectLacks(test, tMain(after), "data-poll");
      expectHas(test, tBody(after), "The pass crashed. What finished is saved.");
    }

## What happens when it ends

    test("end: the relate pass says how many pairs, once") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let first = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      tRunning(db, f, "2/5", "relate:relating");
      let mid = tPoll(db, first.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tMain(mid), "2 of 5");
      tEnded(db, f, "done", "relate|related:5:0");
      let done = tPoll(db, mid.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tBody(done), "Related 5 pairs.");
      let later = tPoll(db, done.ctx, "/stacks/${f.id.toString()}");
      expectLacks(test, tBody(later), "Related 5 pairs.");
    }

    test("end: a pair that was skipped is counted") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let first = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      tRunning(db, f, "1/1", "relate:relating");
      let mid = tPoll(db, first.ctx, "/stacks/${f.id.toString()}");
      tEnded(db, f, "done", "relate|related:1:2");
      let done = tPoll(db, mid.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tBody(done), "Related 1. 2 could not be: both documents have to have been read.");
    }

    test("end: documents that did not read are an error flash") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let first = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      tRunning(db, f, "1/2", "read");
      let mid = tPoll(db, first.ctx, "/stacks/${f.id.toString()}");
      tEnded(db, f, "done", "read|errors:2");
      let done = tPoll(db, mid.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tBody(done), "2 document(s) did not read.");
      expectHas(test, tBody(done), "\"flash\":{\"error\"");
    }

    test("end: no errors is no flash") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let first = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      tRunning(db, f, "1/2", "read");
      let mid = tPoll(db, first.ctx, "/stacks/${f.id.toString()}");
      tEnded(db, f, "done", "read|errors:0");
      let done = tPoll(db, mid.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tBody(done), "\"flash\":{}");
    }

    test("end: a pass that failed names the pass and the reason") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let first = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      tRunning(db, f, "0/0", "compose:outlining");
      let mid = tPoll(db, first.ctx, "/stacks/${f.id.toString()}");
      tEnded(db, f, "done", "compose|error:not_read");
      let done = tPoll(db, mid.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tBody(done), "The compose pass failed: not_read");
    }

    test("end: a pass that crashes frees the folder and says so") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let first = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      tRunning(db, f, "0/0", "compose");
      tEnded(db, f, "crashed", "compose|crashed");
      let done = tPoll(db, first.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tBody(done), "The compose pass crashed. What finished is saved.");
      expectLacks(test, tMain(done), "data-poll");
      expectHas(test, tMain(done), "phx-click=\"read\">Read forwards again</button>");
    }

    test("end: a page that has never looked is not told about a pass that ended long ago") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "0/0", "relate");
      tEnded(db, f, "done", "relate|related:5:0");
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectLacks(test, body, "Related 5 pairs.");
    }

## The buttons

    test("event: read starts the pass and the answer already shows it") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Method", 3);
      let page = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      let r = tEvent(db, page.ctx, "/stacks/${f.id.toString()}", "read", "{}");
      let main = tMain(r);
      expectHas(test, main, "0 of 3");
      expectHas(test, main, "disabled");
      expectHas(test, main, "data-poll=\"2\"");
      expectText(test, tRunRow(db, f), "running|0/3|read");
    }

    test("event: each pass starts with the total the Elixir page captured") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 3);
      db.exec("UPDATE works SET status = 'read' WHERE id = (SELECT min(id) FROM works)", []);
      let first = stacksDocuments(db, me.scope, f.id)[0];
      db.exec("INSERT INTO document_summaries (work_id, summary) VALUES ($1, 'x')", [first.id.toString()]);
      let deepen = tEvent(db, me.ctx, "/stacks/${f.id.toString()}", "deepen", "{}");
      expectText(test, tRunRow(db, f), "running|0/3|deepen");
      db.exec("DELETE FROM runs", []);
      let summarise = tEvent(db, deepen.ctx, "/stacks/${f.id.toString()}", "summarise", "{}");
      expectText(test, tRunRow(db, f), "running|0/2|summarise");
      db.exec("DELETE FROM runs", []);
      let readEach = tEvent(db, summarise.ctx, "/stacks/${f.id.toString()}", "read_each", "{}");
      expectText(test, tRunRow(db, f), "running|0/2|read_each");
      db.exec("DELETE FROM runs", []);
      let compose = tEvent(db, readEach.ctx, "/stacks/${f.id.toString()}", "compose", "{}");
      expectText(test, tRunRow(db, f), "running|0/0|compose");
      expectHas(test, tMain(compose), "Composing…");
      db.exec("DELETE FROM runs", []);
      tEvent(db, compose.ctx, "/stacks/${f.id.toString()}", "relate", "{}");
      expectText(test, tRunRow(db, f), "running|0/0|relate");
    }

    test("event: pressing the button twice does not start a second pass") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "1/4", "read");
      let r = tEventWith(db, me.ctx, "/stacks/${f.id.toString()}", "compose", "{}", tNever, tImportNever);
      expectHas(test, r.resp.body, "A read pass is already running on this folder.");
      expectText(test, tRunRow(db, f), "running|1/4|read");
    }

    test("event: it will not start while another pass is running") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "1/4", "read");
      let r = tEventWith(db, me.ctx, "/stacks/${f.id.toString()}", "summarise", "{}", tNever, tImportNever);
      expectHas(test, r.resp.body, "A read pass is already running");
      expectHas(test, tMain(r), "1 of 4");
    }

    test("event: a start that loses the race to another is the same refusal") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let r = tEventWith(db, me.ctx, "/stacks/${f.id.toString()}", "read", "{}",
        fn (c: Ctx, kind: String, fo: Folder, total: Int): Boolean throws Bubble {
          tRunning(c.db, fo, "0/1", "deepen");
          false
        }, tImportNever);
      expectHas(test, r.resp.body, "A deepen pass is already running on this folder.");
    }

    test("event: an unknown event crashes with its name in the log") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let ok = do { tEvent(db, me.ctx, "/stacks/${f.id.toString()}", "launch_missiles", "{}"); true } orelse false;
      expectTrue(test, !ok, "unhandled");
    }

    test("event: the step page has no events") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let ok = do { tEvent(db, me.ctx, "/stacks/${f.id.toString()}/1", "read", "{}"); true } orelse false;
      expectTrue(test, !ok, "unhandled");
    }

    test("event: an event on somebody else's folder is the redirect") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let them = tWho(db, "b@example.com");
      let theirs = tStack(db, them.scope, "Theirs", 1);
      let r = tEventWith(db, me.ctx, "/stacks/${theirs.id.toString()}", "read", "{}", tNever, tImportNever);
      expectText(test, tRedirect(r), "/stacks");
    }

## The passes, run inline

The job bodies `runsStart` forks, run in-process with canned model answers over
a row that is `running`.

    test("job: a read pass over the folder writes its steps and finishes the run") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Method", 2);
      let llm = llmFake([tStepReply("one"), tStepReply("two")]);
      let page = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      let r = tEventWith(db, page.ctx, "/stacks/${f.id.toString()}", "read", "{}",
        fn (c: Ctx, kind: String, fo: Folder, total: Int): Boolean throws Bubble { tInline(c, kind, fo, total, llm) },
        tImportNever);
      expectText(test, tRunRow(db, f), "done|2/2|read|errors:0");
      expectInt(test, stacksListSteps(db, f.id).length, 2);
      let after = tPoll(db, r.ctx, "/stacks/${f.id.toString()}");
      expectHas(test, tMain(after), "<span class=\"c\">one</span>");
      expectHas(test, tMain(after), "<span class=\"c\">two</span>");
      expectLacks(test, tMain(after), "data-poll");
    }

    test("job: a read pass whose documents failed is the error flash on the page") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Method", 2);
      let llm = llmFake([]);
      let page = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      let r = tEventWith(db, page.ctx, "/stacks/${f.id.toString()}", "read", "{}",
        fn (c: Ctx, kind: String, fo: Folder, total: Int): Boolean throws Bubble { tInline(c, kind, fo, total, llm) },
        tImportNever);
      expectText(test, tRunRow(db, f), "done|0/2|read|errors:2");
      expectHas(test, tBody(r), "2 document(s) did not read.");
      let after = tPoll(db, r.ctx, "/stacks/${f.id.toString()}");
      expectLacks(test, tBody(after), "2 document(s) did not read.");
    }

    test("job: compose writes the telling under the folder's name and the card shows it") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let llm = llmFake([
        tToolReply("outline_story", "{'title':'How it is built','opening':'Open.','closing':'Close.','parts':[{'heading':'Groundwork','steps':[1,2]}]}"),
        tToolReply("write_part", "{'prose':'Prose one.','turn':''}"),
      ]);
      let page = tGet(db, me.ctx, "/stacks/${f.id.toString()}");
      let r = tEventWith(db, page.ctx, "/stacks/${f.id.toString()}", "compose", "{}",
        fn (c: Ctx, kind: String, fo: Folder, total: Int): Boolean throws Bubble { tInline(c, kind, fo, total, llm) },
        tImportNever);
      expectText(test, tRunRow(db, f), "done|1/1|compose|ok");
      let after = tPoll(db, r.ctx, "/stacks/${f.id.toString()}");
      let main = tMain(after);
      expectHas(test, main, "<div class=\"mg-label\">The telling</div>");
      expectHas(test, main, "<a href=\"/stacks/${f.id.toString()}/story\" class=\"t\">How it is built</a>");
      expectHas(test, main, "1 parts");
      expectHas(test, main, "phx-click=\"compose\">Compose again</button>");
    }

    test("job: the summarise pass runs the document summary of each document") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Method", 1);
      let llm = llmFake([]);
      let r = tEventWith(db, me.ctx, "/stacks/${f.id.toString()}", "summarise", "{}",
        fn (c: Ctx, kind: String, fo: Folder, total: Int): Boolean throws Bubble { tInline(c, kind, fo, total, llm) },
        tImportNever);
      expectText(test, tRunRow(db, f), "done|1/1|summarise|errors:1");
    }

    test("job: the read-each pass starts the ordinary read of each unread document") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Method", 1);
      let llm = llmFake([]);
      let r = tEventWith(db, me.ctx, "/stacks/${f.id.toString()}", "read_each", "{}",
        fn (c: Ctx, kind: String, fo: Folder, total: Int): Boolean throws Bubble { tInline(c, kind, fo, total, llm) },
        tImportNever);
      expectText(test, tRunRow(db, f), "done|1/1|read_each|errors:1");
    }

    test("job: relating an empty folder says why, and a folder not read is not related") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Method", 2);
      let llm = llmFake([]);
      let r = tEventWith(db, me.ctx, "/stacks/${f.id.toString()}", "relate", "{}",
        fn (c: Ctx, kind: String, fo: Folder, total: Int): Boolean throws Bubble { tInline(c, kind, fo, total, llm) },
        tImportNever);
      let row = tRunRow(db, f);
      expectHas(test, row, "done|0/0|relate|");
      expectHas(test, row, "error:");
    }

    test("job: a pass of a kind the page does not have stops with its name") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tStack(db, me.scope, "Method", 1);
      let ok = do { pagesStacksRun(db, llmFake([]), "dance", me.scope, f); true } orelse false;
      expectTrue(test, !ok, "refused");
    }

## Publishing

    test("publish: the card offers it, private until it is") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      db.insert("INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, fingerprint) VALUES ($1, 'The telling', 'O', '[]', 'C', '[]', $2)", [f.id.toString(), stacksStoryFingerprint(stacksListSteps(db, f.id))]);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "phx-click=\"publish\" data-confirm=\"Publish this stack? Anyone with the link will be able to read the telling and every step of it.\" class=\"mg-btn sm\">Publish</button>");
      expectHas(test, body, "<span class=\"ml-2\">private — only you can read it</span>");
      expectLacks(test, body, "· stale");
      expectLacks(test, body, "steps left out");
    }

    test("publish: only the account the deploy belongs to can") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let r = tEvent(db, me.ctx, "/stacks/${f.id.toString()}", "publish", "{}");
      expectHas(test, r.resp.body, "Only the account this deploy belongs to can publish.");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders WHERE published_at IS NOT NULL"), 0);
    }

    test("publish: the owner publishes, the slug is the name, and takes it down again") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "bobbbygrayson@gmail.com");
      let f = tRead(db, me.scope, "Phoenix 1.8", 1);
      db.insert("INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, fingerprint) VALUES ($1, 'The telling', 'O', '[]', 'C', '[]', $2)", [f.id.toString(), stacksStoryFingerprint(stacksListSteps(db, f.id))]);
      let r = tEvent(db, me.ctx, "/stacks/${f.id.toString()}", "publish", "{}");
      expectHas(test, r.resp.body, "Published at /reading/phoenix-1-8");
      expectHas(test, tMain(r), "public at");
      expectHas(test, tMain(r), "<a href=\"/reading/phoenix-1-8\">/reading/phoenix-1-8</a>");
      expectHas(test, tMain(r), "phx-click=\"unpublish\" class=\"mg-btn sm ml-2\">Make private</button>");
      expectLacks(test, tMain(r), "private — only you can read it");
      let down = tEvent(db, r.ctx, "/stacks/${f.id.toString()}", "unpublish", "{}");
      expectHas(test, down.resp.body, "Taken off the public site.");
      expectHas(test, tMain(down), "phx-click=\"publish\"");
      let again = tEvent(db, down.ctx, "/stacks/${f.id.toString()}", "publish", "{}");
      expectHas(test, again.resp.body, "Published at /reading/phoenix-1-8");
    }

    test("publish: a stale telling and a telling that left steps out are called out on the card") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      db.insert("INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, fingerprint) VALUES ($1, 'T', 'O', '[]', 'C', '[2]', 'old')", [f.id.toString()]);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "<span class=\"cut-err\">· 1 steps left out</span>");
      expectHas(test, body, "<span class=\"cut-err\">· stale</span>");
    }

## A step

    test("step: what to do, how it works, what to watch, where it came from, where to go") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 3);
      db.exec("UPDATE stack_steps SET requires = '[1]', mechanism = 'It lifts the tail.', watch_for = 'Mind the exit.' WHERE ordinal = 2", []);
      db.exec("UPDATE stack_steps SET requires = '[2]' WHERE ordinal = 3", []);
      let r = tGet(db, me.ctx, "/stacks/${f.id.toString()}/2");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<span class=\"n\">Step 2 of 3</span>");
      expectHas(test, body, "<h1 style=\"font-family:var(--mg-serif)\">cap 2</h1>");
      expectHas(test, body, "from <a href=\"/works/");
      expectHas(test, body, ">2. Doc 2</a>");
      expectHas(test, body, "<h2 class=\"cut-h\">What to do</h2>");
      expectHas(test, body, "<p class=\"st-lesson\">Lesson 2.</p>");
      expectHas(test, body, "<h2 class=\"cut-h\">How it works</h2>");
      expectHas(test, body, "<p class=\"st-lesson\">It lifts the tail.</p>");
      expectHas(test, body, "<h2 class=\"cut-h\">Get this right now</h2>");
      expectHas(test, body, "<p class=\"st-watch\">Mind the exit.</p>");
      expectHas(test, body, "<h2 class=\"cut-h\">You need these first</h2>");
      expectHas(test, body, "<h2 class=\"cut-h\">What this makes possible</h2>");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}/1\"><span class=\"n\">1</span>cap 1</a>");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}/3\"><span class=\"n\">3</span>cap 3</a>");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}/1\">← cap 1</a>");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}/3\" class=\"next\">cap 3 →</a>");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}\">← Method</a>");
      expectLacks(test, body, "Why the obvious version is wrong");
      expectLacks(test, body, "A later step walks this back");
      expectLacks(test, body, "From the document");
    }

    test("step: the first step has an empty slot where the previous link would be") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}/1"));
      expectHas(test, body, "<nav class=\"st-nav\"><span></span>");
      expectHas(test, body, "cap 2 →");
      expectLacks(test, body, "You need these first");
    }

    test("step: a pitfall, a revision and an excerpt are shown with their quotes") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      db.exec("UPDATE stack_steps SET pitfall = 'Do not.', pitfall_quote = 'because it breaks', revised_by = 2, revision = 'Step 2 replaces it.', revision_quote = 'we dropped it', excerpts = '[{\"caption\":\"the shape\",\"text\":\"fn main() {}\"},{\"caption\":\"\",\"text\":\"second\"}]' WHERE ordinal = 1", []);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}/1"));
      expectHas(test, body, "<h2 class=\"cut-h\">Why the obvious version is wrong</h2>");
      expectHas(test, body, "<p class=\"st-pitfall\">Do not.</p>");
      expectHas(test, body, "<blockquote class=\"st-quote\">because it breaks</blockquote>");
      expectHas(test, body, "<h2 class=\"cut-h\">A later step walks this back</h2>");
      expectHas(test, body, "<p class=\"st-pitfall\">Step 2 replaces it.</p>");
      expectHas(test, body, "<blockquote class=\"st-quote\">we dropped it</blockquote>");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}/2\">read step 2 →</a>");
      expectHas(test, body, "<h2 class=\"cut-h\">From the document</h2>");
      expectHas(test, body, "<pre><code>fn main() {}</code></pre>");
      expectHas(test, body, "<figcaption>the shape</figcaption>");
      expectInt(test, body.split("<figcaption>").length - 1, 1);
    }

    test("step: an empty mechanism still shows its heading, as the nil check did") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      db.exec("UPDATE stack_steps SET mechanism = ''", []);
      expectHas(test, tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}/1")), "How it works");
    }

    test("step: text from a document is escaped") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      db.exec("UPDATE stack_steps SET capability = '<script>x</script>', lesson = 'a < b & c'", []);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}/1"));
      expectHas(test, body, "&lt;script&gt;x&lt;/script&gt;");
      expectHas(test, body, "a &lt; b &amp; c");
      expectLacks(test, body, "<script>x");
    }

    test("step: a step that is not there says so, and the link back stays") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}/9"));
      expectHas(test, body, "<p class=\"mg-empty mt-8\">No step 9 here.</p>");
      expectHas(test, body, "← Method");
    }

    test("step: a segment that is not a number is a crash with the segment in the log") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let ok = do { tGet(db, me.ctx, "/stacks/${f.id.toString()}/abc"); true } orelse false;
      expectTrue(test, !ok, "String.to_integer raised");
    }

    test("step: the step page follows a run too") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tRunning(db, f, "1/2", "read");
      expectHas(test, tMain(tPoll(db, me.ctx, "/stacks/${f.id.toString()}/1")), "data-poll=\"2\"");
    }

    test("step: somebody else's step is the redirect") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let them = tWho(db, "b@example.com");
      let theirs = tRead(db, them.scope, "Theirs", 1);
      expectText(test, tLocation(tGet(db, me.ctx, "/stacks/${theirs.id.toString()}/1")), "/stacks");
    }

## The telling

    let tStory(db: Db, f: Folder): Void throws Bubble {
      let movements = "[{\"heading\":\"Groundwork\",\"prose\":\"First *line*\\nsecond line\",\"steps\":[1,2],\"turn\":\"Then it turns.\"},{\"heading\":\"The rest\",\"prose\":\"More.\",\"steps\":[],\"turn\":\"\"}]";
      db.insert(
        "INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, dropped, fingerprint) VALUES ($1, 'How it is built', 'The *opening*.', $2, 'The closing.', '[]', '[]', $3)",
        [f.id.toString(), movements, stacksStoryFingerprint(stacksListSteps(db, f.id))],
      );
    }

    test("story: the telling, part by part, with the steps each part is from") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      tStory(db, f);
      let r = tGet(db, me.ctx, "/stacks/${f.id.toString()}/story");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "How it is built · Marginalia");
      expectHas(test, body, "<article class=\"st-story\">");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}\">← Method</a>");
      expectHas(test, body, "<h1>How it is built</h1>");
      expectHas(test, body, "<button phx-click=\"to-draft\" class=\"mg-btn sm\">Open as a draft</button>");
      expectHas(test, body, "a copy, read and annotated like any other manuscript");
      expectHas(test, body, "<div class=\"lede md st-md\"><p>The <em>opening</em>.</p>");
      expectHas(test, body, "<h2><span class=\"n\">1</span>Groundwork</h2>");
      expectHas(test, body, "<h2><span class=\"n\">2</span>The rest</h2>");
      expectHas(test, body, "<em>line</em><br>");
      expectHas(test, body, "<aside class=\"st-turn md st-md\"><p>Then it turns.</p>");
      expectHas(test, body, "<span class=\"mg-label\">from</span>");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}/1\" title=\"cap 1\">1</a>");
      expectHas(test, body, "<a href=\"/stacks/${f.id.toString()}/2\" title=\"cap 2\">2</a>");
      expectHas(test, body, "<div class=\"st-closing md st-md\"><p>The closing.</p>");
      expectLacks(test, body, "cut-stale");
      expectLacks(test, body, "st-drops");
      expectInt(test, body.split("st-move-steps").length - 1, 1);
      expectInt(test, body.split("<aside").length - 1, 1);
    }

    test("story: a telling the steps have outgrown, one with steps left out, one with problems") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 3);
      db.insert("INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, dropped, fingerprint) VALUES ($1, 'T', 'O', '[]', 'C', '[2,3]', '[\"part 1 named a step that is not there\",\"another\"]', 'old')", [f.id.toString()]);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}/story"));
      expectHas(test, body, "<p class=\"cut-stale\">The steps have been re-read since this was composed.</p>");
      expectHas(test, body, "2 steps found no place in this telling: 2, 3. The composition is incomplete, not the stack.");
      expectHas(test, body, "<p class=\"mg-meta st-drops\">2 problems with the composition: part 1 named a step that is not there; another</p>");
    }

    test("story: singular at one") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 3);
      db.insert("INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, dropped, fingerprint) VALUES ($1, 'T', 'O', '[]', 'C', '[3]', '[\"just one\"]', 'old')", [f.id.toString()]);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}/story"));
      expectHas(test, body, "1 step found no place in this telling: 3.");
      expectHas(test, body, "1 problem with the composition: just one");
    }

    test("story: markdown is not raw html") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      db.insert("INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, fingerprint) VALUES ($1, 'T', '<script>alert(1)</script>', '[]', 'C', '[]', 'x')", [f.id.toString()]);
      expectLacks(test, tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}/story")), "<script>alert");
    }

    test("story: no telling yet is the list with a flash") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      let r = tGet(db, me.ctx, "/stacks/${f.id.toString()}/story");
      expectInt(test, r.resp.status, 303);
      expectText(test, tLocation(r), "/stacks");
      expectHas(test, tBody(tGet(db, r.ctx, "/stacks")), "No telling for that folder yet.");
    }

    test("story: somebody else's telling is the same answer") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let them = tWho(db, "b@example.com");
      let theirs = tRead(db, them.scope, "Theirs", 1);
      tStory(db, theirs);
      expectText(test, tLocation(tGet(db, me.ctx, "/stacks/${theirs.id.toString()}/story")), "/stacks");
    }

    test("story: open as a draft makes a copy that is not in the folder, and goes to it") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 2);
      tStory(db, f);
      let r = tEvent(db, me.ctx, "/stacks/${f.id.toString()}/story", "to-draft", "{}");
      let to = tRedirect(r);
      expectTrue(test, hasText(to, "/works/"), to);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works WHERE title = 'How it is built' AND folder_id IS NULL"), 1);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM works WHERE folder_id IS NOT NULL"), 2);
      let there = tGet(db, r.ctx, "/stacks");
      expectHas(test, tBody(there), "Opened as a draft. Read it the way you would anything else.");
    }

    test("story: the story page has no other events") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method", 1);
      tStory(db, f);
      let ok = do { tEvent(db, me.ctx, "/stacks/${f.id.toString()}/story", "publish", "{}"); true } orelse false;
      expectTrue(test, !ok, "unhandled");
    }

## The index of the folder page

    test("page: the folder page carries the folder's title and no poll when idle") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tRead(db, me.scope, "Method & more", 1);
      let body = tBody(tGet(db, me.ctx, "/stacks/${f.id.toString()}"));
      expectHas(test, body, "Method &amp; more · Marginalia");
      expectHas(test, body, ">Method &amp; more</h1>");
      expectLacks(test, body, "data-poll");
      expectLacks(test, body, "st-progress");
    }
