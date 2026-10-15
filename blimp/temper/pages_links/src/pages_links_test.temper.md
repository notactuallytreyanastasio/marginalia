# Tests for pages_links

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse` and go through the router
in miniature: context, scope, the `guest.` plug, the group.

`runsStart` refuses `:memory:`, so the group is given a launcher (see
`LinksLauncher`): one that only marks the work as started, or one that also
runs it inline with a canned model.

    let { dbOpen, Db } = import("db/src");
    let { Request, Response, Route, Match, httpParse, routeMatch } = import("http/src");
    let { Scope, scopeFor, accountsGetUser, accountsGenerateUserSessionToken } = import("accounts/src");
    let {
      Ctx, webNewCtx, webMountCurrentScope, webEnsureUserOrGuest, webSessionCookieName, webSaveSession,
    } = import("webcore/src");
    let {
      Work, GraphNode, NodeParams, workParams, worksCreateWork, worksSetStatus, worksInsertNode, worksListSections,
    } = import("works/src");
    let { Folder, foldersCreateFolder, foldersMoveWork } = import("folders/src");
    let {
      Link, LinkWorks, linksGet, linksGetOrCreate, linksSetStatus, linksAttrsSummary, linksAttrsError, linksStoreEdges,
      linkerTypes, linksForUser, linksEdgeCount, LinkStats, BulkPair,
    } = import("links/src");
    let { LlmClient, LlmMessage, LlmFakeResponse, llmFake, llmFakeScript, llmRequests } = import("llm/src");
    let { runsGet } = import("runs/src");
    let { JsonObject, JsonArray, JsonString, JsonTextProducer, NullInterchangeContext, JsonSyntaxTree, parseJson } = import("std/json");

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
      let bare = path.split("?").getOr(0, path);
      let m = routeMatch(pagesLinksRoutes(), method, bare);
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
      let carrier = webNewCtx(db, ":memory:", tRaw("GET", "/links", "", ""), tMatch("GET", "/links").params);
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

A draft: a title heading, a first paragraph quoting "A sentence long enough",
and 20 words. `status` is what the read left it as.

    let tWork(db: Db, s: Scope, title: String, status: String): Work throws Bubble {
      let body = "# ${title}\n\nA sentence long enough to be a section.\n\n${tRepeat(20)}";
      let r = worksCreateWork(db, s, workParams(title, body));
      let w = r.ok;
      if (w != null) { worksSetStatus(db, w, status, null) } else { bubble() }
    }

A draft of several paragraphs, each of them starting with one of `lines`
(`tFar` below puts a beat on each).

    let tWorkOf(db: Db, s: Scope, title: String, lines: List<String>): Work throws Bubble {
      let pad = tRepeat(8);
      let body = "# ${title}\n\n${lines.map { (l: String): String => "${l} ${pad}" }.join("\n\n") { (x: String): String => x }}";
      let r = worksCreateWork(db, s, workParams(title, body));
      let w = r.ok;
      if (w != null) { worksSetStatus(db, w, "read", null) } else { bubble() }
    }

    let tBeat(db: Db, w: Work, title: String, quote: String): GraphNode throws Bubble {
      let p = new NodeParams(w.id, "beat", title);
      p.sectionId = worksListSections(db, w.id)[0].id;
      p.quote = quote;
      p.body = "b";
      let r = worksInsertNode(db, p);
      let n = r.node;
      if (n != null) { n } else { bubble() }
    }

    let tEdge(db: Db, link: Link, from: GraphNode, to: GraphNode, kind: String, why: String): Void throws Bubble {
      let tree: JsonSyntaxTree = parseJson("[{\"from\":${from.id.toString()},\"to\":${to.id.toString()},\"type\":\"${kind}\",\"why\":\"${why}\"}]");
      let stored = linksStoreEdges(db, link, tPairItems(tree), linkerTypes());
    }

    let tPairItems(tree: JsonSyntaxTree): List<JsonSyntaxTree> {
      let out = new ListBuilder<JsonSyntaxTree>();
      if (tree is JsonArray) { out.addAll(tree.elements); }
      out.toList()
    }

A read pair with one beat each and one `tension` edge between them; the link is
`linked` with a summary.

    class TFx(
      public db: Db,
      public me: TWho,
      public a: Work,
      public b: Work,
      public aNode: GraphNode,
      public bNode: GraphNode,
      public link: Link,
    ) {}

    let tFx(): TFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "First", "read");
      let b = tWork(db, me.scope, "Second", "read");
      let an = tBeat(db, a, "a beat in First", "A sentence long enough");
      let bn = tBeat(db, b, "a beat in Second", "A sentence long enough");
      let made = linksGetOrCreate(db, a.id, b.id).ok;
      if (made == null) { bubble(); }
      let link = tLinked(db, made, an, bn);
      new TFx(db, me, a, b, an, bn, link)
    }

    let tLinked(db: Db, made: Link?, an: GraphNode, bn: GraphNode): Link throws Bubble {
      if (made != null) {
        tEdge(db, made, an, bn, "tension", "They part.");
        let set = linksSetStatus(db, made, "linked", linksAttrsSummary("They disagree."));
        let l = set.ok;
        if (l != null) { l } else { bubble() }
      } else { bubble() }
    }

A pair of read drafts with nothing between them yet (`pending`).

    class TBare(
      public db: Db, public me: TWho, public a: Work, public b: Work, public aNode: GraphNode, public bNode: GraphNode,
      public link: Link,
    ) {}

    let tBare(): TBare throws Bubble {
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "First", "read");
      let b = tWork(db, me.scope, "Second", "read");
      let an = tBeat(db, a, "a beat in First", "A sentence long enough");
      let bn = tBeat(db, b, "a beat in Second", "A sentence long enough");
      let l = linksGetOrCreate(db, a.id, b.id).ok;
      if (l != null) { new TBare(db, me, a, b, an, bn, l) } else { bubble() }
    }

### Canned model replies

    let tChat(content: String): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
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

The reply to `propose_links`: one tool call with these arguments.

    let tTool(args: String): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("message");
      p.startObject();
      p.objectKey("role"); p.stringValue("assistant");
      p.objectKey("content"); p.nullValue();
      p.objectKey("tool_calls");
      p.startArray();
      p.startObject();
      p.objectKey("id"); p.stringValue("call_1");
      p.objectKey("type"); p.stringValue("function");
      p.objectKey("function");
      p.startObject();
      p.objectKey("name"); p.stringValue("propose_links");
      p.objectKey("arguments"); p.stringValue(args);
      p.endObject();
      p.endObject();
      p.endArray();
      p.endObject();
      p.objectKey("finish_reason"); p.stringValue("tool_calls");
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

What the linker answers: one `tension` edge between the two nodes.

    let tLinkerReply(a: GraphNode, b: GraphNode): String throws Bubble {
      tChat("{\"summary\":\"Manuscript A and Manuscript B part ways.\",\"edges\":[{\"from\":${a.id.toString()},\"to\":${b.id.toString()},\"type\":\"tension\",\"why\":\"Manuscript A and Manuscript B part here.\"}]}")
    }

    let tFailScript(): LlmClient {
      llmFakeScript([
        new LlmFakeResponse(500, "{}"), new LlmFakeResponse(500, "{}"), new LlmFakeResponse(500, "{}"),
      ])
    }

### Launchers

`inline` runs the work the page starts straight away on the page's database,
with the canned client; otherwise the launcher only marks it started, as the
fork does before the job has done anything.

    class TLauncher(public client: LlmClient, public inline: Boolean) extends LinksLauncher {
      public var reads: Int = 0;
      public var proposes: Int = 0;
      public var relates: Int = 0;
      public readLink(ctx: Ctx, link: Link): Void throws Bubble {
        reads += 1;
        linksSetStatus(ctx.db, link, "linking", linksAttrsError(null));
        if (inline) { pagesLinksRunLink(ctx.db, client, link.id); }
      }
      public bulkPropose(ctx: Ctx, folderId: Int): Void throws Bubble {
        proposes += 1;
        let key = pagesLinksBulkKey(folderId);
        tClaim(ctx.db, key);
        if (inline) { pagesLinksRunPropose(ctx.db, key, client, ctx.scope, folderId); }
      }
      public bulkRelate(ctx: Ctx, folderId: Int, pairs: List<BulkPair>): Void throws Bubble {
        relates += 1;
        let key = pagesLinksBulkKey(folderId);
        tClaim(ctx.db, key);
        if (inline) { pagesLinksRunRelate(ctx.db, key, client, pairs); }
      }
      public llm(): LlmClient { client }
    }

    let tClaim(db: Db, key: String): Void throws Bubble {
      db.exec(
        "INSERT INTO runs (key, status, started_at) VALUES ($1, 'running', '2026-01-01 00:00:00') ON CONFLICT(key) DO UPDATE SET status = 'running', detail = NULL, finished_at = NULL",
        [key],
      );
    }

    let tNever(): TLauncher { new TLauncher(llmFake([]), false) }

    let tQueue(): TLauncher { new TLauncher(llmFake([]), false) }

    let tNow(replies: List<String>): TLauncher { new TLauncher(llmFake(replies), true) }

    let expectReads(test: Test, l: TLauncher, want: Int): Void {
      assert(l.reads == want) { "reads: got ${l.reads.toString()}, want ${want.toString()}" }
    }

    let expectProposes(test: Test, l: TLauncher, want: Int): Void {
      assert(l.proposes == want) { "proposes: got ${l.proposes.toString()}, want ${want.toString()}" }
    }

    let expectRelates(test: Test, l: TLauncher, want: Int): Void {
      assert(l.relates == want) { "relates: got ${l.relates.toString()}, want ${want.toString()}" }
    }

## Requests

    let tServe(db: Db, req: Request, match: Match): TRun throws Bubble {
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let denied = webEnsureUserOrGuest(ctx);
      if (denied != null) { new TRun(ctx, denied) } else { new TRun(ctx, pagesLinksGet(ctx, match)) }
    }

    let tGet(db: Db, who: Ctx?, path: String): TRun throws Bubble {
      tServe(db, tRaw("GET", path, tCookieHeader(who), ""), tMatch("GET", path))
    }

The poll: the same page fetched the way `blimp.js` fetches it.

    let tPoll(db: Db, who: Ctx?, path: String): TRun throws Bubble {
      tServe(db, tRaw("GET", path, "${tCookieHeader(who)}X-Requested-With: blimp\r\nAccept: application/json\r\n", ""), tMatch("GET", path))
    }

    let tEvent(db: Db, who: Ctx?, page: String, name: String, payload: String, launcher: LinksLauncher): TRun throws Bubble {
      let req = tRaw("POST", "/ev/${name}", "${tCookieHeader(who)}X-Requested-With: blimp\r\nContent-Type: application/json\r\n", "{\"payload\":${payload},\"path\":\"${page}\"}");
      let match = tMatch("GET", page);
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let tree: JsonSyntaxTree = parseJson(payload);
      if (tree is JsonObject) {
        new TRun(ctx, pagesLinksEventWith(ctx, match, name, tree, launcher))
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

The flash of a JSON answer, `kind: text`, or the empty string.

    let tFlash(r: TRun): String throws Bubble {
      let tree: JsonSyntaxTree = parseJson(r.resp.body);
      if (tree is JsonObject) {
        let flash = tree.propertyValueOrNull("flash");
        if (flash is JsonObject) {
          let err = flash.propertyValueOrNull("error");
          let info = flash.propertyValueOrNull("info");
          if (err is JsonString) { "error: ${err.content}" } else if (info is JsonString) { "info: ${info.content}" } else { "" }
        } else { "" }
      } else { "" }
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

    let tN(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

    let tIdOf(l: Link): String { l.id.toString() }

    let tStatus(db: Db, l: Link): String throws Bubble {
      let again = linksGet(db, l.id);
      if (again != null) { again.status } else { "gone" }
    }

## Routes

    test("routes: /links, /links/:id, /links/:id/read, all guest routes, in router order") { test =>
      let names = pagesLinksRoutes().map { (r: Route): String => "${r.method} ${r.pattern} ${r.name}" };
      expectText(test, names.join(", ") { (x: String): String => x },
        "GET /links guest.links_index, GET /links/:id guest.links_show, GET /links/:id/read guest.links_read");
    }

    test("routes: /links/12/read matches the read alias with its id") { test =>
      let m = tMatch("GET", "/links/12/read");
      expectText(test, m.route.name, "guest.links_read");
      expectText(test, m.params.getOr("id", ""), "12");
    }

    test("routes: /links/12 is the show route") { test =>
      expectText(test, tMatch("GET", "/links/12").route.name, "guest.links_show");
    }

## The index

    test("index: with nothing at all there is the heading, the lede and the empty state") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let r = tGet(db, me.ctx, "/links");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<div class=\"lx\">");
      expectHas(test, body, "<h1>Linked drafts</h1>");
      expectHas(test, body, "<p class=\"lede\">");
      expectHas(test, body, "A link relates two drafts' <strong>maps</strong> — every beat, the spine, the");
      expectHas(test, body, "Both drafts have to have been read first, because that is what");
      expectHas(test, body, "You need two drafts that have been read. <a href=\"/works/new\">Upload another</a>.");
      expectHas(test, body, "<p class=\"none mt-8\">Nothing linked yet.</p>");
      expectLacks(test, body, "relate a whole folder");
      expectLacks(test, body, "<select");
      expectHas(test, body, "Linked drafts · Marginalia");
    }

    test("index: a stranger is given a guest and sees the same empty page") { test =>
      let db = dbOpen(":memory:");
      let r = tGet(db, null, "/links");
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBody(r), "Nothing linked yet.");
    }

    test("index: the drafts that have been read are offered, the others are explained") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tWork(db, me.scope, "Alpha draft", "read");
      tWork(db, me.scope, "Beta draft", "read");
      tWork(db, me.scope, "Gamma draft", "reading");
      let body = tBody(tGet(db, me.ctx, "/links"));
      expectHas(test, body, "Alpha draft");
      expectHas(test, body, "Beta draft");
      expectLacks(test, body, "Gamma draft");
      expectHas(test, body, "<p class=\"none pending\">");
      expectHas(test, body, "1 draft is still being read.");
      expectHas(test, body, "They can be linked once that finishes.");
    }

    test("index: more than one unread draft is plural") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tWork(db, me.scope, "Alpha draft", "read");
      tWork(db, me.scope, "Beta draft", "reading");
      tWork(db, me.scope, "Gamma draft", "reading");
      let body = tBody(tGet(db, me.ctx, "/links"));
      expectHas(test, body, "2 drafts are still being read.");
    }

    test("index: the picker is one form with two selects, options are title and words") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let b = tWork(db, me.scope, "Beta draft", "read");
      let body = tBody(tGet(db, me.ctx, "/links"));
      expectInt(test, tCount(body, "<select"), 2);
      expectHas(test, body, "<form id=\"make-link\" class=\"row\" phx-change=\"pick\" phx-submit=\"make\">");
      expectHas(test, body, "<select id=\"pick-a\" name=\"a\" class=\"lx-pick\">");
      expectHas(test, body, "<select id=\"pick-b\" name=\"b\" class=\"lx-pick\">");
      expectHas(test, body, "<option value=\"\">Choose a draft…</option>");
      expectHas(test, body, "<option value=\"${a.id.toString()}\">Alpha draft · ${a.wordCount.toString()}w</option>");
      expectHas(test, body, "<span class=\"x\" aria-hidden=\"true\">↔</span>");
      expectHas(test, body, "<button type=\"submit\" class=\"mg-btn\" disabled>");
      expectLacks(test, body, "You need two drafts");
      expectLacks(test, body, "still being read");
    }

    test("index: picking patches the form: still two selects, the pick selected there and disabled in the other") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let b = tWork(db, me.scope, "Beta draft", "read");
      let first = tMain(tEvent(db, me.ctx, "/links", "pick", "{\"a\":\"${a.id.toString()}\",\"b\":\"\"}", tNever()));
      expectInt(test, tCount(first, "<select"), 2);
      expectHas(test, first, "<option value=\"${a.id.toString()}\" selected>");
      expectHas(test, first, "<option value=\"${a.id.toString()}\" disabled>");
      expectHas(test, first, "<button type=\"submit\" class=\"mg-btn\" disabled>");
      let both = tMain(tEvent(db, me.ctx, "/links", "pick", "{\"a\":\"${a.id.toString()}\",\"b\":\"${b.id.toString()}\"}", tNever()));
      expectInt(test, tCount(both, "<select"), 2);
      expectHas(test, both, "<button type=\"submit\" class=\"mg-btn\">");
      let cleared = tMain(tEvent(db, me.ctx, "/links", "pick", "{\"a\":\"\",\"b\":\"${a.id.toString()}\"}", tNever()));
      expectInt(test, tCount(cleared, "<select"), 2);
      expectHas(test, cleared, "<option value=\"${a.id.toString()}\" disabled>");
      expectHas(test, cleared, "<button type=\"submit\" class=\"mg-btn\" disabled>");
    }

    test("index: a plain visit forgets the picks (a fresh mount)") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      tWork(db, me.scope, "Beta draft", "read");
      tEvent(db, me.ctx, "/links", "pick", "{\"a\":\"${a.id.toString()}\",\"b\":\"\"}", tNever());
      expectLacks(test, tBody(tGet(db, me.ctx, "/links")), " selected>");
    }

    test("index: the same draft twice is refused with a flash and makes no link") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      tWork(db, me.scope, "Beta draft", "read");
      let launcher = tNever();
      let r = tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${a.id.toString()}\",\"b\":\"${a.id.toString()}\"}", launcher);
      expectText(test, tFlash(r), "error: Pick two different drafts.");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM links"), 0);
      expectReads(test, launcher, 0);
    }

    test("index: an empty pick is refused the same way") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      tWork(db, me.scope, "Beta draft", "read");
      let r = tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${a.id.toString()}\",\"b\":\"\"}", tNever());
      expectText(test, tFlash(r), "error: Pick two different drafts.");
    }

    test("index: make falls back on the stored pick when the form sends an empty one") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let b = tWork(db, me.scope, "Beta draft", "read");
      tEvent(db, me.ctx, "/links", "pick", "{\"a\":\"${a.id.toString()}\",\"b\":\"${b.id.toString()}\"}", tNever());
      let r = tEvent(db, me.ctx, "/links", "make", "{\"a\":\"\",\"b\":\"\"}", tQueue());
      expectInt(test, tN(db, "SELECT count(*) AS n FROM links"), 1);
      expectHas(test, tRedirect(r), "/links/");
    }

    test("index: two drafts make the link, start the pass and go to the pair") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let b = tWork(db, me.scope, "Beta draft", "read");
      let launcher = tQueue();
      let r = tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${b.id.toString()}\",\"b\":\"${a.id.toString()}\"}", launcher);
      let link = linksGetOrCreate(db, a.id, b.id).ok;
      expectTrue(test, link != null, "the pair should have been created");
      if (link != null) {
        expectText(test, tRedirect(r), "/links/${link.id.toString()}");
        expectText(test, link.status, "linking");
        expectInt(test, link.aWorkId, a.id);
      }
      expectReads(test, launcher, 1);
      expectInt(test, tN(db, "SELECT count(*) AS n FROM links"), 1);
    }

    test("index: a plain post of the same form redirects with a 303") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let b = tWork(db, me.scope, "Beta draft", "read");
      let req = tRaw("POST", "/ev/make", tCookieHeader(me.ctx), "");
      let match = tMatch("GET", "/links");
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let tree: JsonSyntaxTree = parseJson("{\"a\":\"${a.id.toString()}\",\"b\":\"${b.id.toString()}\"}");
      if (tree is JsonObject) {
        let resp = pagesLinksEventWith(ctx, match, "make", tree, tQueue());
        expectInt(test, resp.status, 303);
        expectHas(test, resp.headers.map { (p: Pair<String, String>): String => "${p.key}=${p.value}" }.join(";") { (x: String): String => x }, "Location=/links/");
      }
    }

    test("index: linking the same pair twice reuses the one link, from either side") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let b = tWork(db, me.scope, "Beta draft", "read");
      tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${a.id.toString()}\",\"b\":\"${b.id.toString()}\"}", tQueue());
      tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${b.id.toString()}\",\"b\":\"${a.id.toString()}\"}", tQueue());
      expectInt(test, tN(db, "SELECT count(*) AS n FROM links"), 1);
    }

    test("index: a pair already being linked is not started again") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let b = tWork(db, me.scope, "Beta draft", "read");
      let launcher = tQueue();
      tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${a.id.toString()}\",\"b\":\"${b.id.toString()}\"}", launcher);
      tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${a.id.toString()}\",\"b\":\"${b.id.toString()}\"}", launcher);
      expectReads(test, launcher, 1);
    }

    test("index: a draft that belongs to someone else cannot be linked in") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let them = tWho(db, "b@example.com");
      let mine = tWork(db, me.scope, "Alpha draft", "read");
      let theirs = tWork(db, them.scope, "Not yours", "read");
      let launcher = tQueue();
      let r = tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${mine.id.toString()}\",\"b\":\"${theirs.id.toString()}\"}", launcher);
      expectText(test, tFlash(r), "error: Pick two drafts of yours that have been read.");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM links"), 0);
      expectReads(test, launcher, 0);
    }

    test("index: a draft that has not been read cannot be linked") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let u = tWork(db, me.scope, "Gamma draft", "reading");
      let r = tEvent(db, me.ctx, "/links", "make", "{\"a\":\"${a.id.toString()}\",\"b\":\"${u.id.toString()}\"}", tQueue());
      expectText(test, tFlash(r), "error: Pick two drafts of yours that have been read.");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM links"), 0);
    }

    test("index: a pair that was found is listed with its summary, its edges and their kinds") { test =>
      let fx = tFx();
      let body = tBody(tGet(fx.db, fx.me.ctx, "/links"));
      expectHas(test, body, "<a href=\"/links/${tIdOf(fx.link)}\" class=\"lx-row\">");
      expectHas(test, body, "<span class=\"pair\">First <span class=\"x\">↔</span> Second</span>");
      expectHas(test, body, "<p class=\"sum\">They disagree.</p>");
      expectHas(test, body, "<span class=\"n\">1 edges</span>");
      expectHas(test, body, "<span class=\"k tension\">tension 1</span>");
      expectHas(test, body, "1 of 1 linked");
      expectLacks(test, body, "Nothing linked yet.");
      expectLacks(test, body, "lx-more");
    }

    test("index: the summary has the documents called by their names") { test =>
      let fx = tFx();
      linksSetStatus(fx.db, fx.link, "linked", linksAttrsSummary("Manuscript B answers Manuscript A's open question."));
      let body = tBody(tGet(fx.db, fx.me.ctx, "/links"));
      expectHas(test, body, "Second answers First&#39;s open question.");
    }

    test("index: a pair still being worked on says so, and a failed one says why") { test =>
      let bare = tBare();
      linksSetStatus(bare.db, bare.link, "linking", linksAttrsError(null));
      let working = tBody(tGet(bare.db, bare.me.ctx, "/links"));
      expectHas(test, working, "<span class=\"st linking\">linking</span>");
      expectLacks(test, working, "edges</span>");
      linksSetStatus(bare.db, bare.link, "failed", linksAttrsError(":no_edges"));
      let failed = tBody(tGet(bare.db, bare.me.ctx, "/links"));
      expectHas(test, failed, "<span class=\"st failed\">failed</span>");
      expectHas(test, failed, "<p class=\"sum err\">:no_edges</p>");
    }

    test("index: someone else's links are not listed") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let them = tWho(db, "b@example.com");
      let a = tWork(db, me.scope, "Alpha draft", "read");
      let b = tWork(db, me.scope, "Beta draft", "read");
      let x = tWork(db, them.scope, "Theirs one", "read");
      let y = tWork(db, them.scope, "Theirs two", "read");
      linksGetOrCreate(db, x.id, y.id);
      linksGetOrCreate(db, a.id, b.id);
      let body = tBody(tGet(db, me.ctx, "/links"));
      expectLacks(test, body, "Theirs one");
      expectHas(test, body, "Alpha draft");
      expectHas(test, body, "1 of 1 linked");
    }
