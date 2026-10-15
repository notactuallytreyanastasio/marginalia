# Tests for pages_cuts

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse` and go through the router
in miniature: context, scope, the `guest.` plug, the group.

`runsStart` refuses `:memory:`, so the group is given a launcher (see
`pagesCutsGetWith`): one that only marks the cut `reading`, or one that also
runs the read inline through `cutsRead` with a canned model.

    let { dbOpen, Db } = import("db/src");
    let { Request, Response, Route, Match, httpParse, routeMatch } = import("http/src");
    let { Scope, scopeFor, accountsGetUser, accountsGenerateUserSessionToken } = import("accounts/src");
    let {
      Ctx, webNewCtx, webMountCurrentScope, webEnsureUserOrGuest, webSessionCookieName, webSaveSession,
    } = import("webcore/src");
    let { Work, WorkParams, workParams, worksCreateWork } = import("works/src");
    let { Folder, foldersCreateFolder, foldersMoveWork } = import("folders/src");
    let { Cut, cutsOpenFolderReading, cutsStartRead, cutsRead, cutsGet, cutsForFolder, cutsList } = import("cuts/src");
    let { LlmClient, LlmFakeResponse, llmFake, llmFakeScript } = import("llm/src");
    let { JsonObject, JsonString, JsonTextProducer, JsonSyntaxTree, parseJson } = import("std/json");

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

    let tCount(s: String, part: String): Int { s.split(part).length - 1 }

## Fixtures

    class TWho(public id: Int, public scope: Scope, public ctx: Ctx) {}

    class TRun(public ctx: Ctx, public resp: Response) {}

    let tRaw(method: String, path: String, extra: String, body: String): Request {
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${body.split("").length.toString()}\r\n\r\n${body}")
    }

    let tMatch(method: String, path: String): Match throws Bubble {
      let m = routeMatch(pagesCutsRoutes(), method, path);
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
      let carrier = webNewCtx(db, ":memory:", tRaw("GET", "/cuts", "", ""), tMatch("GET", "/cuts").params);
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

A draft: a title heading, a first paragraph naming the title, a second
paragraph, and 120 words. A read quotes "first paragraph of <title>".

    let tDraft(db: Db, s: Scope, title: String): Work throws Bubble {
      let body = "# ${title}\n\nThe first paragraph of ${title}, which is long enough to stand alone.\n\nA second paragraph.\n\n${tRepeat(120)}";
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

A folder holding drafts with these titles, oldest first (so member 1 is the
first title).

    let tLeaf(db: Db, s: Scope, name: String, titles: List<String>): Folder throws Bubble {
      let f = tFolder(db, s, name, null);
      for (let t of titles) { tMove(db, s, tDraft(db, s, t), f); }
      f
    }

    let tPair(db: Db, s: Scope): Folder throws Bubble {
      tLeaf(db, s, "A case", ["Opinion", "Dissent"])
    }

    let tTri(db: Db, s: Scope): Folder throws Bubble {
      tLeaf(db, s, "Three", ["Alpha", "Beta", "Gamma"])
    }

An open reading of a folder, and one with its read done by `launch`.

    let tOpened(db: Db, s: Scope, f: Folder): Cut throws Bubble {
      let c = cutsOpenFolderReading(db, s, f.id, null).ok;
      if (c != null) { c } else { bubble() }
    }

    let tChat(content: String): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("message");
      p.startObject();
      p.objectKey("role"); p.stringValue("assistant");
      p.objectKey("content"); p.stringValue(content);
      p.endObject();
      p.objectKey("finish_reason"); p.stringValue("stop");
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

Two members; one good through-line and one made up.

    let tPairReply(): String {
      "{\"thesis\":\"Both papers turn on one paragraph.\",\"threads\":[{\"claim\":\"Each opens with a first paragraph.\",\"evidence\":[{\"member\":1,\"quote\":\"first paragraph of Opinion\"},{\"member\":2,\"quote\":\"first paragraph of Dissent\"}]},{\"claim\":\"Made up.\",\"evidence\":[{\"member\":1,\"quote\":\"nothing like this\"},{\"member\":2,\"quote\":\"first paragraph of Dissent\"}]}],\"tensions\":[],\"not_supported\":\"Nothing on remedy.\"}"
    }

Three members; X rests on 1 and 2, Y on 2 and 3, a tension on 1 and 3.

    let tTriReply(): String {
      "{\"thesis\":\"Three drafts, one habit.\",\"threads\":[{\"claim\":\"X: the first two open alike.\",\"evidence\":[{\"member\":1,\"quote\":\"first paragraph of Alpha\"},{\"member\":2,\"quote\":\"first paragraph of Beta\"}]},{\"claim\":\"Y: the last two close alike.\",\"evidence\":[{\"member\":2,\"quote\":\"A second paragraph\"},{\"member\":3,\"quote\":\"A second paragraph\"}]}],\"tensions\":[{\"claim\":\"T: one and three part ways.\",\"evidence\":[{\"member\":1,\"quote\":\"first paragraph of Alpha\"},{\"member\":3,\"quote\":\"first paragraph of Gamma\"}]}],\"not_supported\":\"\"}"
    }

    let tFailScript(): LlmClient {
      llmFakeScript([
        new LlmFakeResponse(500, "{}"), new LlmFakeResponse(500, "{}"), new LlmFakeResponse(500, "{}"),
      ])
    }

The launchers. `tQueue` is the production start without the fork: the cut is
`reading` and nothing finishes it.

    let tQueue(ctx: Ctx, cut: Cut): Void throws Bubble {
      let started = cutsStartRead(ctx.db, cut);
    }

    let tInline(ctx: Ctx, cut: Cut, llm: LlmClient): Void throws Bubble {
      let started = cutsStartRead(ctx.db, cut);
      let result = cutsRead(ctx.db, llm, started);
    }

    let tPairNow(ctx: Ctx, cut: Cut): Void throws Bubble { tInline(ctx, cut, llmFake([tChat(tPairReply())])) }

    let tTriNow(ctx: Ctx, cut: Cut): Void throws Bubble { tInline(ctx, cut, llmFake([tChat(tTriReply())])) }

    let tFailNow(ctx: Ctx, cut: Cut): Void throws Bubble { tInline(ctx, cut, tFailScript()) }

    let tNever(ctx: Ctx, cut: Cut): Void throws Bubble {
      console.log("the launcher should not have been called");
      bubble()
    }

## Requests

    let tServe(db: Db, req: Request, match: Match, launch: fn (Ctx, Cut): Void throws Bubble): TRun throws Bubble {
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let denied = webEnsureUserOrGuest(ctx);
      if (denied != null) { new TRun(ctx, denied) } else { new TRun(ctx, pagesCutsGetWith(ctx, match, launch)) }
    }

    let tGet(db: Db, who: Ctx, path: String, launch: fn (Ctx, Cut): Void throws Bubble): TRun throws Bubble {
      let bare = path.split("?").getOr(0, path);
      tServe(db, tRaw("GET", path, tCookieHeader(who), ""), tMatch("GET", bare), launch)
    }

The poll: the same page fetched the way `blimp.js` fetches it.

    let tPoll(db: Db, who: Ctx, path: String, launch: fn (Ctx, Cut): Void throws Bubble): TRun throws Bubble {
      tServe(db, tRaw("GET", path, "${tCookieHeader(who)}X-Requested-With: blimp\r\nAccept: application/json\r\n", ""), tMatch("GET", path), launch)
    }

    let tEvent(db: Db, who: Ctx, page: String, name: String, payload: String, launch: fn (Ctx, Cut): Void throws Bubble): TRun throws Bubble {
      let req = tRaw("POST", "/ev/${name}", "${tCookieHeader(who)}X-Requested-With: blimp\r\nContent-Type: application/json\r\n", "{\"payload\":${payload},\"path\":\"${page}\"}");
      let match = tMatch("GET", page);
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let tree: JsonSyntaxTree = parseJson(payload);
      if (tree is JsonObject) {
        new TRun(ctx, pagesCutsEventWith(ctx, match, name, tree, launch))
      } else { bubble() }
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

    let tIdOf(c: Cut): String { c.id.toString() }

    let tN(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

## Routes

    test("routes: /cuts then /cuts/:id, both guest routes") { test =>
      let names = pagesCutsRoutes().map { (r: Route): String => "${r.method} ${r.pattern} ${r.name}" };
      expectText(test, names.join(", ") { (x: String): String => x },
        "GET /cuts guest.cuts_index, GET /cuts/:id guest.cuts_show");
    }

    test("routes: /cuts/12 matches the show page with its id") { test =>
      let m = tMatch("GET", "/cuts/12");
      expectText(test, m.route.name, "guest.cuts_show");
      expectText(test, m.params.getOr("id", ""), "12");
    }

## The index

    test("index: with no folders there is the empty state and no explanation") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tGet(db, me.ctx, "/cuts", tNever);
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<h1 style=\"font-family:var(--mg-serif)\" class=\"text-2xl font-semibold tracking-tight\">Readings</h1>");
      expectHas(test, body, "<span class=\"mg-meta\">0 of 0 folders read</span>");
      expectHas(test, body, "class=\"mg-empty mt-8\"");
      expectHas(test, body, "A reading is what a folder says that none of its drafts says alone. Make a folder on the drafts page and there will be something here to read.");
      expectLacks(test, body, "Read from the inside out");
      expectHas(test, body, "<a href=\"/works\" class=\"mg-btn sm ghost ml-auto\">Folders</a>");
      expectHas(test, body, "<title");
      expectHas(test, body, "Readings · Marginalia");
    }

    test("index: a folder with no reading is dim text and a read button") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let body = tBody(tGet(db, me.ctx, "/cuts", tNever));
      expectHas(test, body, "Read from the inside out. A folder of folders is read over what its children already found, so reading a case first makes the reading above it worth more.");
      expectLacks(test, body, "class=\"mg-empty mt-8\"");
      expectHas(test, body, "id=\"cut-row-${f.id.toString()}\" class=\"cut-row\" style=\"padding-left:0.0rem\"");
      expectHas(test, body, "<span style=\"font-family:var(--mg-serif)\" class=\"text-[1.05rem] text-[var(--mg-dim)]\">A case</span>");
      expectLacks(test, body, "mg-badge ink");
      expectHas(test, body, "2 drafts");
      expectHas(test, body, "<button class=\"mg-btn sm ghost\" phx-click=\"read\" phx-value-folder=\"${f.id.toString()}\">read</button>");
      expectHas(test, body, "<span class=\"mg-meta\">0 of 1 folders read</span>");
    }

    test("index: folders are listed depth first, indented 1.4rem a level, with their counts") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let top = tFolder(db, me.scope, "Top", null);
      let mid = tFolder(db, me.scope, "Mid", top);
      let leaf = tFolder(db, me.scope, "Leaf", mid);
      tMove(db, me.scope, tDraft(db, me.scope, "One"), leaf);
      tMove(db, me.scope, tDraft(db, me.scope, "Two"), leaf);
      let body = tBody(tGet(db, me.ctx, "/cuts", tNever));
      expectHas(test, body, "id=\"cut-row-${top.id.toString()}\" class=\"cut-row\" style=\"padding-left:0.0rem\"");
      expectHas(test, body, "id=\"cut-row-${mid.id.toString()}\" class=\"cut-row\" style=\"padding-left:1.4rem\"");
      expectHas(test, body, "id=\"cut-row-${leaf.id.toString()}\" class=\"cut-row\" style=\"padding-left:2.8rem\"");
      expectHas(test, body, "1 folders · 2 drafts below");
      expectHas(test, body, "<div class=\"mg-meta mt-0.5\">\n2 drafts\n</div>");
      let at = body.split("id=\"cut-row-");
      expectTrue(test, hasText(at.getOr(1, ""), "Top") && hasText(at.getOr(2, ""), "Mid") && hasText(at.getOr(3, ""), "Leaf"), "Top, Mid, Leaf in that order");
    }

    test("index: a finished reading is a link, a badge, a through-line count and read again") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      tPairNow(me.ctx, cut);
      let body = tBody(tGet(db, me.ctx, "/cuts", tNever));
      expectHas(test, body, "<span class=\"mg-badge ink mr-2\">read</span>");
      expectHas(test, body, "<a href=\"/cuts/${tIdOf(cut)}\" style=\"font-family:var(--mg-serif)\" class=\"text-[1.05rem] hover:text-[var(--mg-accent)]\">A case</a>");
      expectHas(test, body, "<span>· 1 through-lines</span>");
      expectHas(test, body, "phx-value-folder=\"${f.id.toString()}\">read again</button>");
      expectHas(test, body, "<span class=\"mg-meta\">1 of 1 folders read</span>");
    }

    test("index: a reading that is not read shows its status, a queued one nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tPair(db, me.scope);
      let b = tLeaf(db, me.scope, "Other", ["Solo"]);
      let ca = tOpened(db, me.scope, a);
      tQueue(me.ctx, ca);
      tOpened(db, me.scope, b);
      let body = tBody(tGet(db, me.ctx, "/cuts", tNever));
      expectHas(test, body, "<span>· reading</span>");
      expectLacks(test, body, "· draft");
      expectLacks(test, body, "through-lines");
      expectHas(test, body, "<span class=\"mg-meta\">2 of 2 folders read</span>");
      expectLacks(test, body, "data-poll");
    }

    test("index: a failed reading says failed") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      tFailNow(me.ctx, tOpened(db, me.scope, f));
      let body = tBody(tGet(db, me.ctx, "/cuts", tNever));
      expectHas(test, body, "<span>· failed</span>");
    }

    test("index: another user's folders and readings are not listed") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let you = tWho(db, "b@example.com");
      let theirs = tLeaf(db, you.scope, "Theirs", ["Secret"]);
      tOpened(db, you.scope, theirs);
      let body = tBody(tGet(db, me.ctx, "/cuts", tNever));
      expectLacks(test, body, "Theirs");
      expectHas(test, body, "0 of 0 folders read");
    }

    test("index: a folder name is escaped") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tFolder(db, me.scope, "<b>bold</b>", null);
      let body = tBody(tGet(db, me.ctx, "/cuts", tNever));
      expectHas(test, body, "&lt;b&gt;bold&lt;/b&gt;");
      expectLacks(test, body, "<b>bold</b>");
    }

    test("index: a visitor is given a guest and sees the empty list") { test =>
      let db = dbOpen(":memory:");
      let r = tServe(db, tRaw("GET", "/cuts", "", ""), tMatch("GET", "/cuts"), tNever);
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBody(r), "0 of 0 folders read");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM users WHERE is_guest = 1"), 1);
    }

## The index events

    test("read: opens the folder's reading and goes to it") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let r = tEvent(db, me.ctx, "/cuts", "read", "{\"folder\":\"${f.id.toString()}\"}", tNever);
      let cut = cutsForFolder(db, me.scope, f.id);
      expectTrue(test, cut != null, "a reading was made");
      if (cut != null) {
        expectText(test, tRedirect(r), "/cuts/${tIdOf(cut)}");
        expectText(test, cut.status, "draft");
        expectText(test, cut.title, "A case");
      }
    }

    test("read: asking twice is the same reading") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let one = tEvent(db, me.ctx, "/cuts", "read", "{\"folder\":\"${f.id.toString()}\"}", tNever);
      let two = tEvent(db, me.ctx, "/cuts", "read", "{\"folder\":\"${f.id.toString()}\"}", tNever);
      expectText(test, tRedirect(one), tRedirect(two));
      expectInt(test, cutsList(db, me.scope).length, 1);
    }

    test("read: reading again resets a finished reading to queued") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      tPairNow(me.ctx, tOpened(db, me.scope, f));
      tEvent(db, me.ctx, "/cuts", "read", "{\"folder\":${f.id.toString()}}", tNever);
      let cut = cutsForFolder(db, me.scope, f.id);
      expectText(test, if (cut != null) { cut.status } else { "none" }, "draft");
    }

    test("read: someone else's folder is refused with a flash and the list stays") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let you = tWho(db, "b@example.com");
      let theirs = tLeaf(db, you.scope, "Theirs", ["Secret"]);
      let r = tEvent(db, me.ctx, "/cuts", "read", "{\"folder\":\"${theirs.id.toString()}\"}", tNever);
      expectHas(test, tBody(r), "\"flash\"");
      expectHas(test, tBody(r), "That folder is not yours.");
      expectHas(test, tMain(r), "Readings");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM cuts"), 0);
    }

    test("read: a folder that is not a number stops the event") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let crashed = do { tEvent(db, me.ctx, "/cuts", "read", "{\"folder\":\"abc\"}", tNever); false } orelse true;
      expectTrue(test, crashed, "a bubble, not a plausible page");
    }

    test("an event the index does not have stops") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let crashed = do { tEvent(db, me.ctx, "/cuts", "frobnicate", "{}", tNever); false } orelse true;
      expectTrue(test, crashed, "a bubble");
    }

## The show page: the waiting state

    test("show: a draft is started on the first fetch, and the page polls") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      let r = tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tQueue);
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<p class=\"cut-working\">Reading this folder. One call, and it is the slow kind.</p>");
      expectHas(test, body, "data-poll=\"2\"");
      let again = cutsGet(db, me.scope, cut.id);
      expectText(test, if (again != null) { again.status } else { "none" }, "reading");
    }

    test("show: the weave and the members are there while the first read runs") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tQueue));
      expectHas(test, body, "id=\"weave-${tIdOf(cut)}\" class=\"cut-weave\" phx-hook=\"Weave\" phx-update=\"ignore\" data-status=\"reading\"");
      expectHas(test, body, "data-members=\"[{&quot;n&quot;:1,&quot;kind&quot;:&quot;work&quot;");
      expectHas(test, body, "&quot;label&quot;:&quot;Opinion&quot;,&quot;read?&quot;:false}");
      expectHas(test, body, "data-links=\"[]\"");
      expectHas(test, body, "<svg aria-hidden=\"true\"></svg>");
      expectHas(test, body, "<span class=\"l\">Dissent</span>");
    }

    test("show: a reading with no work in it fails with the reason, and offers try again") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Empty", null);
      let cut = tOpened(db, me.scope, f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tPairNow));
      expectHas(test, body, "<p class=\"cut-err mt-6\">this folder holds nothing to read <button class=\"mg-btn sm ghost ml-2\" phx-click=\"again\">try again</button></p>");
      expectLacks(test, body, "cut-weave");
      expectLacks(test, body, "data-poll");
    }

    test("show: a model failure is the reason, in the page") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tFailNow));
      expectHas(test, body, "class=\"cut-err mt-6\"");
      expectHas(test, body, "phx-click=\"again\">try again</button>");
      expectLacks(test, body, "Thesis");
    }

    test("show: a job that crashed turns the reading into a failure on the next fetch") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      tQueue(me.ctx, cut);
      db.exec("INSERT INTO runs (key, status, detail) VALUES ($1, 'crashed', 'Bubble: boom')", ["cut:${tIdOf(cut)}"]);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tNever));
      expectHas(test, body, "Bubble: boom");
      expectHas(test, body, "The read crashed.");
      expectLacks(test, body, "data-poll");
      let again = cutsGet(db, me.scope, cut.id);
      expectText(test, if (again != null) { again.status } else { "none" }, "failed");
    }

    test("show: a running job leaves the page polling") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      tQueue(me.ctx, cut);
      db.exec("INSERT INTO runs (key, status, pid) VALUES ($1, 'running', 1)", ["cut:${tIdOf(cut)}"]);
      let poll = tPoll(db, me.ctx, "/cuts/${tIdOf(cut)}", tNever);
      expectHas(test, tMain(poll), "data-poll=\"2\"");
      expectHas(test, tMain(poll), "Reading this folder.");
    }

## The show page: the answer

    test("show: a finished read shows the thesis, the through-lines and what it does not show") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tPairNow));
      expectHas(test, body, "<h1 style=\"font-family:var(--mg-serif)\" class=\"mt-2 text-2xl font-semibold tracking-tight\">A case</h1>");
      expectHas(test, body, "<h2 class=\"cut-h\">Thesis</h2>");
      expectHas(test, body, "<p class=\"cut-thesis\">Both papers turn on one paragraph.</p>");
      expectHas(test, body, "<h2 class=\"cut-h\">Through-lines</h2>");
      expectHas(test, body, "<p class=\"c\">Each opens with a first paragraph.</p>");
      expectHas(test, body, "<cite>Opinion</cite>");
      expectHas(test, body, "<cite>Dissent</cite>");
      expectLacks(test, body, "Tensions");
      expectHas(test, body, "<h2 class=\"cut-h\">What this does not show</h2>");
      expectHas(test, body, "<p class=\"cut-body\">Nothing on remedy.</p>");
      expectLacks(test, body, "data-poll");
      expectLacks(test, body, "Queued.");
    }

    test("show: the quote is the member's own wording and is escaped") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tPairNow));
      expectHas(test, body, "<blockquote>\nfirst paragraph of Opinion\n<cite>Opinion</cite>\n</blockquote>");
    }

    test("show: the weave of a finished read carries its pairs") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tTri(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tTriNow));
      expectHas(test, body, "data-status=\"read\"");
      expectHas(test, body, "data-links=\"[{&quot;a&quot;:1,&quot;b&quot;:2,&quot;kind&quot;:&quot;thread&quot;},{&quot;a&quot;:2,&quot;b&quot;:3,&quot;kind&quot;:&quot;thread&quot;},{&quot;a&quot;:1,&quot;b&quot;:3,&quot;kind&quot;:&quot;tension&quot;}]\"");
      expectHas(test, body, "<h2 class=\"cut-h\">Tensions</h2>");
    }

    test("show: one button per member, numbered, none focused") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tTri(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tTriNow));
      expectHas(test, body, "<div class=\"cut-members\">");
      expectHas(test, body, "<button id=\"cut-member-2\" type=\"button\" phx-click=\"focus\" phx-value-n=\"2\" class=\"cut-member\"><span class=\"i\">2</span><span class=\"l\">Beta</span></button>");
      expectInt(test, tCount(body, "class=\"cut-member\""), 3);
      expectLacks(test, body, "cut-member on");
      expectLacks(test, body, "cut-hole");
    }

    test("show: the question is shown when there is one") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      cutsOpenFolderReading(db, me.scope, f.id, "what do they share?");
      let cut = tOpened(db, me.scope, f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tPairNow));
      expectHas(test, body, "<p class=\"cut-ask\">what do they share?</p>");
    }

    test("show: no question, no cut-ask") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tPair(db, me.scope));
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tPairNow));
      expectLacks(test, body, "cut-ask");
      expectHas(test, body, "<a href=\"/cuts\">← every reading</a>");
    }

    test("show: dropped claims are counted, in the singular for one") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tPair(db, me.scope));
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tPairNow));
      expectHas(test, body, "<span class=\"mg-meta\">2 claims dropped for quotes that could not be found</span>");
    }

    test("show: the footer has read again for a finished read, and delete with its confirmation") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tPair(db, me.scope));
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tPairNow));
      expectHas(test, body, "<button class=\"mg-btn sm ghost\" phx-click=\"again\">read again</button>");
      expectHas(test, body, "<button class=\"mg-btn sm ghost ml-auto\" phx-click=\"delete\" data-confirm=\"Delete this reading?\">delete</button>");
      expectLacks(test, body, "This folder has changed since it was read.");
    }

    test("show: a folder that has changed since the read says so, with a way to read again") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      tPairNow(me.ctx, cut);
      tMove(db, me.scope, tDraft(db, me.scope, "Concurrence"), f);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tNever));
      expectHas(test, body, "<p class=\"cut-stale\">This folder has changed since it was read. <button class=\"mg-btn sm ghost ml-2\" phx-click=\"again\">read again</button></p>");
      expectInt(test, tCount(body, "phx-click=\"again\""), 2);
    }

    test("show: a folder of folders flags a member that has not been read") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let top = tFolder(db, me.scope, "Top", null);
      let kid = tFolder(db, me.scope, "Kid", top);
      let other = tFolder(db, me.scope, "Other", top);
      tMove(db, me.scope, tDraft(db, me.scope, "K1"), kid);
      tMove(db, me.scope, tDraft(db, me.scope, "K2"), other);
      let cut = tOpened(db, me.scope, top);
      let body = tBody(tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tQueue));
      expectHas(test, body, "<span class=\"u\">not read</span>");
      expectHas(test, body, "<p class=\"cut-hole\">Some of these have not been read yet, so this stands on their titles rather than on what they say. Read them first and this will be worth more.</p>");
    }

## The show page: who it is for

    test("show: another user's reading is not found") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let you = tWho(db, "b@example.com");
      let cut = tOpened(db, you.scope, tPair(db, you.scope));
      let r = tGet(db, me.ctx, "/cuts/${tIdOf(cut)}", tNever);
      expectInt(test, r.resp.status, 303);
      expectText(test, tLocation(r), "/cuts");
      let list = tGet(db, me.ctx, "/cuts", tNever);
      expectHas(test, tBody(list), "No such reading.");
    }

    test("show: an id nothing has is the same") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tGet(db, me.ctx, "/cuts/999", tNever);
      expectInt(test, r.resp.status, 303);
      expectText(test, tLocation(r), "/cuts");
    }

    test("show: an id that is not a number is a 404") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      expectInt(test, tGet(db, me.ctx, "/cuts/abc", tNever).resp.status, 404);
    }

## The show events

    test("again: starts a read and the answer polls") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tPair(db, me.scope));
      tPairNow(me.ctx, cut);
      let r = tEvent(db, me.ctx, "/cuts/${tIdOf(cut)}", "again", "{}", tQueue);
      let main = tMain(r);
      expectHas(test, main, "data-poll=\"2\"");
      expectHas(test, main, "Reading this folder.");
      expectLacks(test, main, "Thesis");
      expectHas(test, main, "data-status=\"reading\"");
    }

    test("again: a failed read can be tried again") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tPair(db, me.scope));
      tFailNow(me.ctx, cut);
      let r = tEvent(db, me.ctx, "/cuts/${tIdOf(cut)}", "again", "{}", tPairNow);
      let main = tMain(r);
      expectHas(test, main, "Both papers turn on one paragraph.");
      expectLacks(test, main, "data-poll");
    }

    test("focus: keeps the claims that rest on the member and lights its button") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tTri(db, me.scope));
      let path = "/cuts/${tIdOf(cut)}";
      tGet(db, me.ctx, path, tTriNow);
      let r = tEvent(db, me.ctx, path, "focus", "{\"n\":\"1\"}", tNever);
      let main = tMain(r);
      expectHas(test, main, "X: the first two open alike.");
      expectLacks(test, main, "Y: the last two close alike.");
      expectHas(test, main, "T: one and three part ways.");
      expectHas(test, main, "class=\"cut-member on\"");
      expectInt(test, tCount(main, "cut-member on"), 1);
      expectHas(test, main, "id=\"cut-member-1\" type=\"button\" phx-click=\"focus\" phx-value-n=\"1\" class=\"cut-member on\"");
    }

    test("focus: a group with nothing left is not drawn") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tTri(db, me.scope));
      let path = "/cuts/${tIdOf(cut)}";
      tGet(db, me.ctx, path, tTriNow);
      let main = tMain(tEvent(db, me.ctx, path, "focus", "{\"n\":3}", tNever));
      expectLacks(test, main, "X: the first two open alike.");
      expectHas(test, main, "Y: the last two close alike.");
      expectHas(test, main, "Tensions");
    }

    test("focus: the same member again lets go") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tTri(db, me.scope));
      let path = "/cuts/${tIdOf(cut)}";
      tGet(db, me.ctx, path, tTriNow);
      tEvent(db, me.ctx, path, "focus", "{\"n\":\"2\"}", tNever);
      let main = tMain(tEvent(db, me.ctx, path, "focus", "{\"n\":\"2\"}", tNever));
      expectLacks(test, main, "cut-member on");
      expectHas(test, main, "Y: the last two close alike.");
      expectHas(test, main, "X: the first two open alike.");
    }

    test("focus: another member replaces it") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tTri(db, me.scope));
      let path = "/cuts/${tIdOf(cut)}";
      tGet(db, me.ctx, path, tTriNow);
      tEvent(db, me.ctx, path, "focus", "{\"n\":\"1\"}", tNever);
      let main = tMain(tEvent(db, me.ctx, path, "focus", "{\"n\":\"3\"}", tNever));
      expectInt(test, tCount(main, "cut-member on"), 1);
      expectHas(test, main, "id=\"cut-member-3\" type=\"button\" phx-click=\"focus\" phx-value-n=\"3\" class=\"cut-member on\"");
      expectLacks(test, main, "X: the first two open alike.");
    }

    test("focus: held across the poll, forgotten on a fresh visit") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tTri(db, me.scope));
      let path = "/cuts/${tIdOf(cut)}";
      tGet(db, me.ctx, path, tTriNow);
      tEvent(db, me.ctx, path, "focus", "{\"n\":\"1\"}", tNever);
      expectHas(test, tMain(tPoll(db, me.ctx, path, tNever)), "cut-member on");
      expectLacks(test, tBody(tGet(db, me.ctx, path, tNever)), "cut-member on");
    }

    test("focus: without a number stops") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tTri(db, me.scope));
      let path = "/cuts/${tIdOf(cut)}";
      tGet(db, me.ctx, path, tTriNow);
      let crashed = do { tEvent(db, me.ctx, path, "focus", "{}", tNever); false } orelse true;
      expectTrue(test, crashed, "a bubble");
    }

    test("delete: removes the reading, goes to the list, says so") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tPair(db, me.scope);
      let cut = tOpened(db, me.scope, f);
      let path = "/cuts/${tIdOf(cut)}";
      tGet(db, me.ctx, path, tPairNow);
      let r = tEvent(db, me.ctx, path, "delete", "{}", tNever);
      expectText(test, tRedirect(r), "/cuts");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM cuts"), 0);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM folders"), 1);
      let list = tGet(db, me.ctx, "/cuts", tNever);
      expectHas(test, tBody(list), "Reading deleted.");
      expectHas(test, tBody(list), "0 of 1 folders read");
    }

    test("delete: not another user's reading") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let you = tWho(db, "b@example.com");
      let cut = tOpened(db, you.scope, tPair(db, you.scope));
      let r = tEvent(db, me.ctx, "/cuts/${tIdOf(cut)}", "delete", "{}", tNever);
      expectText(test, tRedirect(r), "/cuts");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM cuts"), 1);
    }

    test("an event the show page does not have stops") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let cut = tOpened(db, me.scope, tPair(db, me.scope));
      let crashed = do { tEvent(db, me.ctx, "/cuts/${tIdOf(cut)}", "frobnicate", "{}", tNever); false } orelse true;
      expectTrue(test, crashed, "a bubble");
    }
