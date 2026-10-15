# What the work page's tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse`, the way the server sees
them, and go through the router in miniature: context, scope, the group.

`runsStart` refuses `:memory:`, so the group is given a launcher
(`launch.temper.md`): one that claims the run and does nothing (`ShowQueueLauncher`,
a page mid-pass), or one that runs the job inline with a canned model
(`ShowInlineLauncher`).

Users are inserted by SQL (a registration costs a PBKDF2), each with a session
the next request finds by its cookie.

    let { dbOpen, Db } = import("db/src");
    let { Request, Response, Route, Match, httpParse, routeMatch } = import("http/src");
    let {
      Scope, scopeFor, accountsGetUser, accountsGenerateUserSessionToken, accountsOwnerEmail,
    } = import("accounts/src");
    let {
      Ctx, webNewCtx, webMountCurrentScope, webEnsureUserOrGuest, webSessionCookieName, webSaveSession,
    } = import("webcore/src");
    let {
      Work, Section, GraphNode, NodeParams, workParams, worksCreateWork, worksListSections,
      worksInsertNode, worksSetStatus, worksReplaceBlock, worksLink, worksGetById,
    } = import("works/src");
    let { LlmClient, llmFake } = import("llm/src");
    let { JsonObject, JsonString, JsonTextProducer, JsonSyntaxTree, parseJson } = import("std/json");

## Assertions

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let expectTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let expectFalse(test: Test, got: Boolean, what: String): Void {
      assert(!got) { what }
    }

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "missing: ${part}\nin: ${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "unexpected: ${part}\nin: ${s}" }
    }

    let tCount(s: String, part: String): Int { s.split(part).length - 1 }

    let tRepeat(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = tRepeat(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

    let tWords(n: Int): String { tRepeat("word ", n) }

## People

    class TWho(public id: Int, public scope: Scope, public ctx: Ctx) {}

    class TRun(public ctx: Ctx, public resp: Response) {}

    let tRaw(method: String, path: String, extra: String, body: String): Request {
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${body.split("").length.toString()}\r\n\r\n${body}")
    }

    let tMatch(method: String, path: String): Match throws Bubble {
      let m = routeMatch(pagesShowRoutes(), method, path);
      if (m != null) { m } else {
        console.log("no route for ${method} ${path}");
        bubble()
      }
    }

    let tPlain(path: String): String { path.split("?").getOr(0, path) }

    let tCookieHeader(who: TWho?): String {
      if (who != null) { "Cookie: ${webSessionCookieName()}=${who.ctx.session.id}\r\n" } else { "" }
    }

A logged-in user, and the session that holds them.

    let tWho(db: Db, email: String): TWho throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password, confirmed_at) VALUES ($1, 'x', '2020-01-01 00:00:00')", [email]);
      let user = accountsGetUser(db, id);
      let token = accountsGenerateUserSessionToken(db, user);
      let carrier = webNewCtx(db, ":memory:", tRaw("GET", "/works/x", "", ""), tMatch("GET", "/works/x").params);
      let row = db.one("SELECT id FROM users_tokens WHERE token = $1", [token]);
      if (row != null) { carrier.session.userTokenId = row.int("id"); }
      carrier.session.dirty = true;
      webSaveSession(db, carrier.session);
      new TWho(id, scopeFor(user), carrier)
    }

## Drafts

A draft: a heading and two short paragraphs a note can point at, then 260
words. Its first section is "A draft".

    let tBody(): String {
      "# A draft\n\nShe had been standing at the window for an hour before anyone noticed.\n\nThe kettle went cold on the counter, and nobody moved to fill it again.\n\n${tWords(260)}"
    }

    let tDraft(db: Db, s: Scope, title: String, body: String): Work throws Bubble {
      let r = worksCreateWork(db, s, workParams(title, body));
      let w = r.ok;
      if (w != null) { w } else { bubble() }
    }

A draft that has been read.

    let tRead(db: Db, s: Scope, title: String, body: String): Work throws Bubble {
      worksSetStatus(db, tDraft(db, s, title, body), "read", null)
    }

    let tSection(db: Db, w: Work): Section throws Bubble {
      worksListSections(db, w.id)[0]
    }

A note: a node of `kind` with a quote that is in the draft (or is not).

    let tNode(db: Db, w: Work, kind: String, title: String, quote: String?): GraphNode throws Bubble {
      let p = new NodeParams(w.id, kind, title);
      p.sectionId = tSection(db, w).id;
      p.body = "why ${title}";
      p.quote = quote;
      let n = worksInsertNode(db, p).node;
      if (n != null) { n } else { bubble() }
    }

    let tSpan(): String { "The kettle went cold on the counter, and nobody moved to fill it again." }

    let tKettle(): String { "The kettle went cold on the counter" }

    let tBeat(db: Db, w: Work, title: String): GraphNode throws Bubble {
      tNode(db, w, "beat", title, tKettle())
    }

A beat nobody can find in the text, so it stacks at the top of the rail.

    let tLost(db: Db, w: Work, kind: String, title: String): GraphNode throws Bubble {
      tNode(db, w, kind, title, "nowhere in the text")
    }

    let tEdge(db: Db, w: Work, from: GraphNode, to: GraphNode, kind: String): Void throws Bubble {
      worksLink(db, w.id, from.id, to.id, kind, 0, "because ${kind}");
    }

The paragraph of the first section that holds `lead`, replaced by `to`.

    let tEdit(db: Db, w: Work, from: String, to: String): Void throws Bubble {
      let s = tSection(db, w);
      var block = "";
      for (let p of s.body.split("\n\n")) {
        if (hasText(p, from)) { block = p; }
      }
      worksReplaceBlock(db, s, block, block.split(from).join(to) { (x: String): String => x }, "rewrite", "cuts the gloss");
    }

    class TWorld(public db: Db, public owner: TWho, public reader: TWho, public work: Work) {}

A draft that has been read, its owner, and someone holding the link.

    let tWorld(): TWorld throws Bubble {
      let db = dbOpen(":memory:");
      let owner = tWho(db, "writer@example.com");
      let reader = tWho(db, "reader@example.com");
      new TWorld(db, owner, reader, tRead(db, owner.scope, "Draft", tBody()))
    }

    let tPath(w: Work, view: String): String { "/works/${w.slug}?view=${view}" }

    let tPage(w: TWorld): String { tPath(w.work, "read") }

## Launchers

    let tQueue(): ShowLauncher { new ShowQueueLauncher() }

    let tInline(replies: List<String>): ShowLauncher { new ShowInlineLauncher(llmFake(replies), true) }

    let tKeyed(): ShowLauncher { new ShowInlineLauncher(llmFake([]), true) }

    let tNoKey(): ShowLauncher { new ShowInlineLauncher(llmFake([]), false) }

## Requests

The page, as a browser fetches it.

    let tServe(db: Db, who: TWho?, req: Request, match: Match, launcher: ShowLauncher): TRun throws Bubble {
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let denied = webEnsureUserOrGuest(ctx);
      if (denied != null) { new TRun(ctx, denied) } else { new TRun(ctx, pagesShowGetWith(ctx, match, launcher)) }
    }

    let tGet(db: Db, who: TWho?, path: String, launcher: ShowLauncher): TRun throws Bubble {
      tServe(db, who, tRaw("GET", path, tCookieHeader(who), ""), tMatch("GET", tPlain(path)), launcher)
    }

The poll: the same page fetched the way `blimp.js` fetches it.

    let tPoll(db: Db, who: TWho?, path: String, launcher: ShowLauncher): TRun throws Bubble {
      tServe(db, who, tRaw("GET", path, "${tCookieHeader(who)}X-Requested-With: blimp\r\nAccept: application/json\r\n", ""), tMatch("GET", tPlain(path)), launcher)
    }

An event from the page at `page`, with a JSON payload.

    let tEvent(db: Db, who: TWho?, page: String, name: String, payload: String, launcher: ShowLauncher): TRun throws Bubble {
      let req = tRaw("POST", page, "${tCookieHeader(who)}X-Requested-With: blimp\r\nContent-Type: application/json\r\n", payload);
      let match = tMatch("GET", tPlain(page));
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let tree: JsonSyntaxTree = parseJson(payload);
      if (tree is JsonObject) {
        new TRun(ctx, pagesShowEventWith(ctx, match, name, tree, launcher))
      } else { bubble() }
    }

    let tBodyOf(r: TRun): String { r.resp.body }

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

The text of a flash of `level` in a JSON answer, or "".

    let tFlash(r: TRun, level: String): String throws Bubble {
      let tree: JsonSyntaxTree = parseJson(r.resp.body);
      if (tree is JsonObject) {
        let flash = tree.propertyValueOrNull("flash");
        if (flash is JsonObject) {
          let text = flash.propertyValueOrNull(level);
          if (text is JsonString) { text.content } else { "" }
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

    let tHeader(r: TRun, name: String): String {
      var out = "";
      for (let p of r.resp.headers) { if (p.key == name) { out = p.value; } }
      out
    }

    let tN(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

    let tStatusOf(db: Db, w: Work): String throws Bubble {
      let again = worksGetById(db, w.id);
      if (again != null) { again.status } else { "gone" }
    }

## The model's side of a call

An answer in which the model called `name` with `argsJson`.

    let tToolReply(name: String, argsJson: String): String throws Bubble {
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
      p.stringValue(argsJson);
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

Three candidates for the kettle line.

    let tRewriteReply(): String throws Bubble {
      tToolReply("propose_rewrites", "{\"reading\":\"It states the scene flatly.\",\"rewrites\":[{\"text\":\"The kettle went cold; nobody refilled it.\",\"move\":\"Cuts the gloss.\",\"cost\":\"Loses the again.\"},{\"text\":\"Nobody moved, and the kettle went cold.\",\"move\":\"Puts people first.\",\"cost\":\"Buries the kettle.\"}]}")
    }

    let tSummaryReply(): String throws Bubble {
      tToolReply("report_section", "{\"summary\":\"It opens at the window and ends on the kettle.\",\"covers\":[\"the window\"],\"follows_from\":[],\"sets_up\":\"The rest.\"}")
    }
