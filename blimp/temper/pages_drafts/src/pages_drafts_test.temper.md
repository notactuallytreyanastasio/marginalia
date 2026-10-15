# Tests for pages_drafts

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse` and go through the router
in miniature: context, scope, the group. Users are made by SQL (a registration
costs a PBKDF2); drafts through `worksCreateWork`, so they are stored the way
an upload stores them; nodes, edges, folders and steps by SQL.

The owner is the account with the default owner email (`OWNER_EMAIL` is not
set when the tests run).

    let { dbOpen, Db } = import("db/src");
    let { Request, Response, Route, Match, httpParse, routeMatch } = import("http/src");
    let { Scope, scopeFor, accountsGetUser, accountsGenerateUserSessionToken } = import("accounts/src");
    let {
      Ctx, webNewCtx, webMountCurrentScope, webSessionCookieName, webSaveSession,
    } = import("webcore/src");
    let { Work, WorkParams, workParams, worksCreateWork, worksListSections, worksReplaceBlock, worksSetStatus } = import("works/src");
    let { linksGetOrCreate } = import("links/src");
    let { rows, paragraphs } = import("core/src");
    let { JsonObject, JsonString, JsonSyntaxTree, parseJson } = import("std/json");
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
      let m = routeMatch(pagesDraftsRoutes(), method, path);
      if (m != null) { m } else { bubble() }
    }

    let tCookieHeader(prev: Ctx?): String {
      if (prev != null) { "Cookie: ${webSessionCookieName()}=${prev.session.id}\r\n" } else { "" }
    }

A user by SQL, and the session that holds them: the context to pass on to the
next request.

    let tWho(db: Db, email: String): TWho throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password, confirmed_at) VALUES ($1, 'x', '2020-01-01 00:00:00')", [email]);
      let user = accountsGetUser(db, id);
      let token = accountsGenerateUserSessionToken(db, user);
      let carrier = webNewCtx(db, ":memory:", tRaw("GET", "/drafts", "", ""), tMatch("GET", "/drafts").params);
      let row = db.one("SELECT id FROM users_tokens WHERE token = $1", [token]);
      if (row != null) { carrier.session.userTokenId = row.int("id"); }
      carrier.session.dirty = true;
      webSaveSession(db, carrier.session);
      new TWho(id, scopeFor(user), carrier)
    }

    let tOwner(db: Db): TWho throws Bubble { tWho(db, "bobbbygrayson@gmail.com") }

A request as the visitor `prev` is (or nobody), through the group.

    let tGet(db: Db, prev: Ctx?, path: String): TRun throws Bubble {
      let bare = path.split("?").getOr(0, path);
      let match = tMatch("GET", bare);
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", path, tCookieHeader(prev), ""), match.params);
      webMountCurrentScope(ctx);
      new TRun(ctx, pagesDraftsGet(ctx, match))
    }

    let tGetWith(db: Db, extra: String, path: String): TRun throws Bubble {
      let match = tMatch("GET", path);
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", path, extra, ""), match.params);
      webMountCurrentScope(ctx);
      new TRun(ctx, pagesDraftsGet(ctx, match))
    }

    let tEvent(db: Db, prev: Ctx?, page: String, name: String, payload: String): TRun throws Bubble {
      let req = tRaw("POST", "/ev/${name}", "${tCookieHeader(prev)}X-Requested-With: blimp\r\nContent-Type: application/json\r\n", "{\"payload\":${payload},\"path\":\"${page}\"}");
      let match = tMatch("GET", page);
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      let tree: JsonSyntaxTree = parseJson(payload);
      if (tree is JsonObject) {
        new TRun(ctx, pagesDraftsEvent(ctx, match, name, tree))
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

    let tHeader(r: TRun, name: String): String {
      var out = "";
      for (let p of r.resp.headers) { if (p.key == name) { out = p.value; } }
      out
    }

    let tLocation(r: TRun): String { tHeader(r, "Location") }

    let tN(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

    let tRepeat(n: Int): String {
      let parts = new ListBuilder<String>();
      for (var i = 0; i < n; ++i) { parts.add("word "); }
      parts.toList().join("") { (x: String): String => x }
    }

Whether `first` occurs before `second` in `s`, the first occurrence of each.

    let tBefore(s: String, first: String, second: String): Boolean {
      let upToSecond = s.split(second).getOr(0, "");
      hasText(upToSecond, first)
    }

    let tParse(text: String): Int {
      let n = pdParseInt(text);
      if (n != null) { n } else { -1000 }
    }

A draft with a title heading, a first paragraph naming the title, a second
paragraph and 120 words; stored the way an upload is.

    let tBody120(title: String): String {
      "# ${title}\n\nThe first paragraph of ${title}, which is long enough to stand alone.\n\nA second paragraph.\n\n${tRepeat(120)}"
    }

    let tDraftBody(db: Db, userId: Int, title: String, body: String): Work throws Bubble {
      let r = worksCreateWork(db, scopeFor(accountsGetUser(db, userId)), workParams(title, body));
      let w = r.ok;
      if (w != null) { w } else { bubble() }
    }

    let tDraft(db: Db, userId: Int, title: String): Work throws Bubble {
      tDraftBody(db, userId, title, tBody120(title))
    }

    let tSection(db: Db, w: Work): Int throws Bubble {
      worksListSections(db, w.id)[0].id
    }

A node by SQL: a beat quoting `quote`, in the work's first section.

    let tBeat(db: Db, w: Work, title: String, quote: String): Int throws Bubble {
      db.insert(
        "INSERT INTO nodes (work_id, section_id, node_type, title, body, quote) VALUES ($1, $2, 'beat', $3, 'b', $4)",
        [w.id.toString(), tSection(db, w).toString(), title, quote],
      )
    }

An edge of a link by SQL, between two fresh beats (one in each draft).

    let tEdge(db: Db, linkId: Int, a: Work, b: Work, kind: String, fromTitle: String, toTitle: String, why: String?): Void throws Bubble {
      let from = tBeat(db, a, fromTitle, "word word");
      let to = tBeat(db, b, toTitle, "word word");
      db.exec(
        "INSERT INTO link_edges (link_id, from_id, to_id, edge_type, rationale) VALUES ($1, $2, $3, $4, $5)",
        [linkId.toString(), from.toString(), to.toString(), kind, why],
      );
    }

    let tLink(db: Db, a: Work, b: Work): Int throws Bubble {
      let l = linksGetOrCreate(db, a.id, b.id).ok;
      if (l != null) { l.id } else { bubble() }
    }

The paragraph of the first section that contains `needle`, as it is stored.

    let tBlock(db: Db, w: Work, needle: String): String throws Bubble {
      let ps = paragraphs(worksListSections(db, w.id)[0].body);
      var out = "";
      for (let p of ps) { if (hasText(p, needle)) { out = p; } }
      out
    }

Change a paragraph through the editor's own function, so a revision is kept.

    let tEdit(db: Db, w: Work, needle: String, replacement: String, origin: String?, note: String?): Void throws Bubble {
      let section = worksListSections(db, w.id)[0];
      let old = tBlock(db, w, needle);
      let edited = sysJoin(old.split(needle), replacement);
      worksReplaceBlock(db, section, old, edited, origin, note);
    }

A published folder with a story of one movement and one step.

    let tFolder(db: Db, userId: Int, name: String, slug: String?, published: Boolean): Int throws Bubble {
      db.insert(
        "INSERT INTO folders (name, user_id, slug, published_at) VALUES ($1, $2, $3, $4)",
        [name, userId.toString(), slug, if (published) { "2026-01-01 00:00:00" } else { null }],
      )
    }

    let tStory(db: Db, folderId: Int): Void throws Bubble {
      db.exec(
        "INSERT INTO stack_stories (folder_id, title, opening, movements, closing) VALUES ($1, 'Half of building it is fixing the thing underneath', 'Nothing about this is hand-written at the level you would expect.', '[{\"heading\":\"Get it running first\",\"prose\":\"Do the `cheap` part.\",\"steps\":[1],\"turn\":\"\"}]', 'That is the method.')",
        [folderId.toString()],
      );
    }

    let tStep(db: Db, folderId: Int, workId: Int, ordinal: Int, capability: String, requires: String): Void throws Bubble {
      db.exec(
        "INSERT INTO stack_steps (folder_id, work_id, ordinal, capability, lesson, pitfall, pitfall_quote, excerpts, requires) VALUES ($1, $2, $3, $4, 'Emit one module and run it before building anything clever.', 'Assuming the printed form round-trips.', 'a whole Double prints as 1', '[{\"caption\":\"the grammar\",\"text\":\"out_grammar do ... end\"}]', $5)",
        [folderId.toString(), workId.toString(), ordinal.toString(), capability, requires],
      );
    }

A published reading: a folder with a story and two steps (each from a draft the
owner wrote).

    class TReading(public folderId: Int, public work1: Work, public work2: Work) {}

    let tReading(db: Db, ownerId: Int): TReading throws Bubble {
      let w1 = tDraft(db, ownerId, "1. The first thing");
      let w2 = tDraft(db, ownerId, "2. The second thing");
      let f = tFolder(db, ownerId, "A Backend For Something", "a-backend-for-something", true);
      tStory(db, f);
      tStep(db, f, w1.id, 1, "The thing emits a file that runs", "[]");
      tStep(db, f, w2.id, 2, "The file is the test", "[1]");
      new TReading(f, w1, w2)
    }

## Routes

    test("routes: nine, all public, the sitemap first") { test =>
      let names = pagesDraftsRoutes().map { (r: Route): String => "${r.method} ${r.pattern} ${r.name}" };
      expectText(test, names.join(", ") { (x: String): String => x },
        "GET /sitemap.xml public.sitemap, GET /drafts public.drafts_index, GET /drafts/:slug public.drafts_show, GET /drafts/:slug/changes public.drafts_changes, GET /linked public.linked_index, GET /linked/:id public.linked_show, GET /reading public.reading_index, GET /reading/:slug public.reading_story, GET /reading/:slug/:ordinal public.reading_step");
    }

    test("routes: every name has the public prefix, so no guest is minted") { test =>
      for (let r of pagesDraftsRoutes()) {
        expectTrue(test, hasText(r.name, "public."), r.name);
      }
    }

    test("routes: paths pick their pages and carry their params") { test =>
      expectText(test, tMatch("GET", "/drafts/abc").route.name, "public.drafts_show");
      expectText(test, tMatch("GET", "/drafts/abc").params.getOr("slug", ""), "abc");
      expectText(test, tMatch("GET", "/drafts/abc/changes").route.name, "public.drafts_changes");
      expectText(test, tMatch("GET", "/linked/12").params.getOr("id", ""), "12");
      expectText(test, tMatch("GET", "/reading/x").route.name, "public.reading_story");
      expectText(test, tMatch("GET", "/reading/x/3").route.name, "public.reading_step");
      expectText(test, tMatch("GET", "/reading/x/3").params.getOr("ordinal", ""), "3");
    }

## /drafts

    test("drafts: a stranger sees the owner's drafts with their word counts") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "A draft of my own");
      let r = tGet(db, null, "/drafts");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<h1>Drafts</h1>");
      expectHas(test, body, "<a href=\"/drafts/${w.slug}\" class=\"t\">A draft of my own</a>");
      expectHas(test, body, "<p class=\"mg-meta\">${w.wordCount.toString()} words · pending</p>");
      expectHas(test, body, "<div class=\"lx\">");
      expectHas(test, body, "<ul class=\"mg-rows\">");
      expectLacks(test, body, "Nothing here yet.");
    }

    test("drafts: nobody else's draft is listed") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let other = tWho(db, "stranger@example.com");
      tDraft(db, owner.id, "A draft of my own");
      tDraft(db, other.id, "Somebody else's");
      let body = tBody(tGet(db, null, "/drafts"));
      expectHas(test, body, "A draft of my own");
      expectLacks(test, body, "Somebody else");
      expectHas(test, body, "1 drafts, read end to end.");
    }

    test("drafts: the count is not singularised, and the lede is the original's") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tDraft(db, owner.id, "One");
      tDraft(db, owner.id, "Two");
      let body = tBody(tGet(db, null, "/drafts"));
      expectHas(test, body, "2 drafts, read end to end. Each one carries the notes that came out of reading it, in the margin beside the sentence that caused them.");
    }

    test("drafts: with no owner account the list is empty and says so") { test =>
      let db = dbOpen(":memory:");
      tWho(db, "somebody@example.com");
      let body = tBody(tGet(db, null, "/drafts"));
      expectHas(test, body, "<p class=\"mg-empty\">Nothing here yet.</p>");
      expectHas(test, body, "0 drafts, read end to end.");
    }

    test("drafts: every work the owner has is listed, a case's documents too") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Opinion");
      db.exec("UPDATE works SET collection = 'Some v. Case', collection_role = 'opinion' WHERE id = $1", [w.id.toString()]);
      let body = tBody(tGet(db, null, "/drafts"));
      expectHas(test, body, ">Opinion</a>");
    }

    test("drafts: the head says index, follow, and the canonical is the site root") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let body = tBody(tGet(db, null, "/drafts"));
      expectHas(test, body, "<title data-default=\"Someone who has actually read the whole thing\" data-suffix=\" · Marginalia\">Drafts · Marginalia</title>");
      expectHas(test, body, "<meta name=\"robots\" content=\"index, follow\">");
      expectLacks(test, body, "noindex");
      expectHas(test, body, "<meta name=\"description\" content=\"Drafts read end to end, with the notes that came out of reading them.\">");
      expectHas(test, body, "<link rel=\"canonical\" href=\"http://localhost:4000/\">");
    }

    test("drafts: reading the list mints no user") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let before = tN(db, "SELECT count(*) AS n FROM users");
      tGet(db, null, "/drafts");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM users"), before);
    }

## /drafts/:slug

    test("draft: the owner's draft reads with no account") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "A draft of my own");
      let r = tGet(db, null, "/drafts/${w.slug}");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<h1 style=\"font-family:var(--mg-serif)\" class=\"text-2xl font-semibold tracking-tight mt-2\">A draft of my own</h1>");
      expectHas(test, body, "<a href=\"/drafts\">← Drafts</a>");
      expectHas(test, body, "<p class=\"mg-meta\">${w.wordCount.toString()} words</p>");
      expectHas(test, body, "<div class=\"mg-read mt-6\">");
      expectHas(test, body, "<div class=\"mg-read-rail\">");
      expectHas(test, body, "<meta name=\"robots\" content=\"index, follow\">");
      expectLacks(test, body, "noindex");
    }

    test("draft: somebody else's slug, and a slug nobody owns, go back to the list") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let other = tWho(db, "stranger@example.com");
      let theirs = tDraft(db, other.id, "Theirs");
      let r = tGet(db, null, "/drafts/${theirs.slug}");
      expectInt(test, r.resp.status, 303);
      expectText(test, tLocation(r), "/drafts");
      let r2 = tGet(db, null, "/drafts/not-a-real-slug");
      expectInt(test, r2.resp.status, 303);
      expectText(test, tLocation(r2), "/drafts");
    }

    test("draft: the redirect carries the flash No such draft.") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let r = tGet(db, null, "/drafts/not-a-real-slug");
      expectText(test, r.ctx.session.flash.getOr("error", ""), "No such draft.");
    }

    test("draft: the public page carries none of the controls that write or spend") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      let body = tBody(tGet(db, null, "/drafts/${w.slug}"));
      for (let c of ["summarise_document", "summarise", "suggest_rewrite", "edit_block", "save_block", "start_read"]) {
        expectLacks(test, body, c);
      }
    }

    test("draft: reading one mints no account") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      let before = tN(db, "SELECT count(*) AS n FROM users");
      tGet(db, null, "/drafts/${w.slug}");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM users"), before);
    }

    test("draft: blocks carry the ids the notes anchor to") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      let body = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, body, "<div class=\"mg-block\" id=\"block-s1p0\">");
      expectHas(test, body, "<div class=\"mg-block\" id=\"block-s1p1\">");
      expectHas(test, body, "<div class=\"mg-label\">Section 1</div>");
    }

    test("draft: the sentences of a paragraph run on and only a blank line breaks it") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let text = "# The post\n\nAt 04:47 UTC agent-7 implemented the Guideline step\nreset for lock delay. The idea came from agent-8.\n\n> agent-8 logged that the cap locks a piece. Agent-7\n> read it.\n\n```\nline one\nline two\n```\n\n- one. Two.\n- three.\n\nEvery node, by minute. ${tRepeat(200)}";
      let w = tDraftBody(db, owner.id, "The post", text);
      let body = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectLacks(test, body, "<br");
      expectHas(test, body, "<p>At 04:47 UTC agent-7 implemented the Guideline step reset for lock delay.\nThe idea came from agent-8.</p>");
      expectHas(test, body, "<p>agent-8 logged that the cap locks a piece.\nAgent-7 read it.</p>");
      expectHas(test, body, "<code>line one\nline two\n</code>");
      expectHas(test, body, "<li>one. Two.</li>");
      expectHas(test, body, "<li>three.</li>");
    }

    test("draft: the changes link appears once there is a change, singular then plural") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      let none = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectLacks(test, none, "since it arrived");
      expectLacks(test, none, "/changes");
      tEdit(db, w, "first paragraph", "opening paragraph", null, null);
      let one = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, one, " · <a href=\"/drafts/${w.slug}/changes\">1 change since it arrived</a>");
      tEdit(db, w, "second paragraph", "later paragraph", null, null);
      let two = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, two, "2 changes since it arrived");
    }

    test("draft: a beat is a note in the rail beside its block, in document order") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      tBeat(db, w, "The opening sentence", "A second paragraph.");
      let body = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, body, "<div class=\"mg-note-slot beat\" data-anchor=\"s1p2\">");
      expectHas(test, body, "<div class=\"mg-note beat\">");
      expectHas(test, body, "<span class=\"who\">beat</span>");
      expectHas(test, body, "<span class=\"said\">The opening sentence</span>");
      expectHas(test, body, "<span class=\"why\">b</span>");
      expectHas(test, body, "<mark id=\"anchor-s1p2\">");
    }

    test("draft: a note whose quote is in no paragraph is dropped") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      tBeat(db, w, "Lost", "this sentence is nowhere in the draft");
      let body = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectLacks(test, body, "Lost");
      expectLacks(test, body, "mg-note-slot");
    }

    test("draft: a connection is a note on the beat it starts from, labelled with its direction") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      let a = tBeat(db, w, "The promise", "A second paragraph.");
      let b = tBeat(db, w, "The payoff", "The first paragraph of Mine");
      db.exec(
        "INSERT INTO edges (work_id, from_id, to_id, edge_type, rationale) VALUES ($1, $2, $3, 'develops', 'It grows.')",
        [w.id.toString(), a.toString(), b.toString()],
      );
      let body = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, body, "<div class=\"mg-note-slot develops\" data-anchor=\"s1p2\">");
      expectHas(test, body, "<span class=\"said\">develops → The payoff</span>");
      expectHas(test, body, "<span class=\"why\">It grows.</span>");
    }

    test("draft: the description is the first impression, else the title") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      let plain = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, plain, "<meta name=\"description\" content=\"Mine\">");
      expectHas(test, plain, "<title data-default=\"Someone who has actually read the whole thing\" data-suffix=\" · Marginalia\">Mine · Marginalia</title>");
      db.exec("UPDATE works SET first_impression = 'It is about a kettle.' WHERE id = $1", [w.id.toString()]);
      let told = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, told, "<meta name=\"description\" content=\"It is about a kettle.\">");
    }

    test("draft: a section's summary shows under its heading") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      db.exec("UPDATE sections SET summary = 'The gist of it.' WHERE work_id = $1", [w.id.toString()]);
      let body = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, body, "<div class=\"mg-sum-text\">The gist of it.</div>");
    }

    test("draft: a title with markup is escaped") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "<b>Bold</b> & co");
      let body = tBody(tGet(db, null, "/drafts/${w.slug}"));
      expectHas(test, body, "&lt;b&gt;Bold&lt;/b&gt; &amp; co");
      expectLacks(test, body, "<b>Bold</b>");
    }

## /drafts/:slug/changes

    test("changes: an unchanged draft says so and shows no table") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Untouched");
      let body = tBody(tGet(db, null, "/drafts/${w.slug}/changes"));
      expectHas(test, body, "<p class=\"mg-empty\">Nothing has been changed yet.</p>");
      expectLacks(test, body, "As it arrived");
      expectLacks(test, body, "mg-diff-cols");
      expectLacks(test, body, "Every change, newest first");
      expectHas(test, body, "0 edited · 0 added · 0 removed");
    }

    test("changes: one edited sentence is one changed row with the words marked") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      tEdit(db, w, "first paragraph", "opening paragraph", "rewrite", "cuts the gloss");
      let r = tGet(db, null, "/drafts/${w.slug}/changes");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "1 edited · 0 added · 0 removed");
      expectHas(test, body, "<span>As it arrived</span><span>Now</span>");
      expectHas(test, body, "<div class=\"mg-diff-row change\">");
      expectHas(test, body, "class=\"w ins\"");
      expectHas(test, body, "class=\"w del\"");
      expectHas(test, body, "<span class=\"w del\">first </span>");
      expectHas(test, body, "<span class=\"w ins\">opening </span>");
      expectHas(test, body, "<div class=\"side old\">");
      expectHas(test, body, "<div class=\"side new\">");
      expectHas(test, body, "<meta name=\"robots\" content=\"index, follow\">");
    }

    test("changes: an old row hides the inserted words and the new row hides the deleted ones") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      tEdit(db, w, "first paragraph", "opening paragraph", null, null);
      let body = tBody(tGet(db, null, "/drafts/${w.slug}/changes"));
      expectHas(test, body, "<span class=\"w hide\">opening </span>");
      expectHas(test, body, "<span class=\"w hide\">first </span>");
    }

    test("changes: the log gives the origin, the note and the section, newest first") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      tEdit(db, w, "first paragraph", "opening paragraph", "rewrite", "cuts the gloss");
      tEdit(db, w, "second paragraph", "later paragraph", null, null);
      let body = tBody(tGet(db, null, "/drafts/${w.slug}/changes"));
      expectHas(test, body, "Every change, newest first");
      expectHas(test, body, "<span class=\"mg-meta\">rewrite — cuts the gloss · section 1</span>");
      expectHas(test, body, "<span class=\"mg-meta\">edit · section 1</span>");
      let two = body.split("<span class=\"n\">2</span>");
      let one = body.split("<span class=\"n\">1</span>");
      expectInt(test, two.length, 2);
      expectInt(test, one.length, 2);
      expectTrue(test, tBefore(body, "<span class=\"n\">2</span>", "<span class=\"n\">1</span>"), "revision 2 is listed before revision 1");
    }

    test("changes: the log shows the after text with insertions marked and deletions hidden") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      tEdit(db, w, "first paragraph", "opening paragraph", null, null);
      let body = tBody(tGet(db, null, "/drafts/${w.slug}/changes"));
      let log = body.split("<div class=\"mg-diff-patch\">");
      expectInt(test, log.length, 2);
      expectHas(test, log[1], "<span class=\"w hide\">first </span>");
      expectHas(test, log[1], "<span class=\"w ins\">opening </span>");
      expectLacks(test, log[1], "<span class=\"w del\">");
    }

    test("changes: an added paragraph and a removed one are rows of their own") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      db.exec("UPDATE works SET baseline_body = $1, body = $2 WHERE id = $3", ["alpha\n\nbravo\n\ncharlie", "alpha\n\ncharlie\n\ndelta", w.id.toString()]);
      let body = tBody(tGet(db, null, "/drafts/${w.slug}/changes"));
      expectHas(test, body, "0 edited · 1 added · 1 removed");
      expectHas(test, body, "<div class=\"mg-diff-row del\"><div class=\"side old gone\">bravo</div><div class=\"side new empty\"></div></div>");
      expectHas(test, body, "<div class=\"mg-diff-row ins\"><div class=\"side old empty\"></div><div class=\"side new fresh\">delta</div></div>");
      expectHas(test, body, "<div class=\"mg-diff-row same\"><div class=\"side old\">alpha</div><div class=\"side new\">alpha</div></div>");
    }

    test("changes: a stored baseline is the left side, with no revision needed") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      db.exec("UPDATE works SET baseline_body = $1 WHERE id = $2", ["# Mine\n\nA different start.", w.id.toString()]);
      let body = tBody(tGet(db, null, "/drafts/${w.slug}/changes"));
      expectHas(test, body, "As it arrived");
      expectHas(test, body, "A different start.");
      expectLacks(test, body, "Every change, newest first");
    }

    test("changes: the title, the description and the way back") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      let body = tBody(tGet(db, null, "/drafts/${w.slug}/changes"));
      expectHas(test, body, "Mine — what changed · Marginalia</title>");
      expectHas(test, body, "<meta name=\"description\" content=\"Every change made to this draft, as a before and after.\">");
      expectHas(test, body, "<a href=\"/drafts/${w.slug}\">← Mine</a>");
      expectHas(test, body, "<span class=\"mg-label\">Changes since it arrived</span>");
      expectHas(test, body, "<span class=\"mg-meta ml-auto\">0 edited · 0 added · 0 removed</span>");
    }

    test("changes: somebody else's draft has no public diff") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let other = tWho(db, "stranger@example.com");
      let theirs = tDraft(db, other.id, "Theirs");
      let r = tGet(db, null, "/drafts/${theirs.slug}/changes");
      expectInt(test, r.resp.status, 303);
      expectText(test, tLocation(r), "/drafts");
    }

    test("changes: the diff page has no control that writes") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let w = tDraft(db, owner.id, "Mine");
      tEdit(db, w, "first paragraph", "opening paragraph", null, null);
      let body = tBody(tGet(db, null, "/drafts/${w.slug}/changes"));
      for (let c of ["edit_block", "save_block", "suggest_rewrite", "apply_rewrite", "summarise"]) {
        expectLacks(test, body, c);
      }
    }

## /linked

    test("linked: the index lists the owner's pairs only, with their edge counts") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let other = tWho(db, "stranger@example.com");
      let a = tDraft(db, owner.id, "The novel");
      let b = tDraft(db, owner.id, "The story");
      let ta = tDraft(db, other.id, "Their first");
      let tb = tDraft(db, other.id, "Their second");
      let link = tLink(db, a, b);
      tEdge(db, link, a, b, "pays_off", "He stops in the doorway", "The unanswered question", "Nine pays off the promise the story made.");
      let theirs = tLink(db, ta, tb);
      tEdge(db, theirs, ta, tb, "develops", "Private", "Also private", null);
      let empty = tLink(db, b, tDraft(db, owner.id, "Unrelated"));
      let body = tBody(tGet(db, null, "/linked"));
      expectHas(test, body, "The novel ↔ The story");
      expectHas(test, body, "<a href=\"/linked/${link.toString()}\" class=\"t\">");
      expectHas(test, body, "1 edges");
      expectLacks(test, body, "Their first");
      expectLacks(test, body, "Unrelated");
      expectHas(test, body, "1 pairs · 0 of them contain a tension, and those are first");
      expectLacks(test, body, "/linked/${empty.toString()}");
    }

    test("linked: a pair with a tension outranks a pair with more edges, and the page counts them") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let qa = tDraft(db, owner.id, "Quiet one");
      let qb = tDraft(db, owner.id, "Quiet two");
      let la = tDraft(db, owner.id, "Argues one");
      let lb = tDraft(db, owner.id, "Argues two");
      let quiet = tLink(db, qa, qb);
      for (let k of ["develops", "develops", "develops", "pays_off"]) { tEdge(db, quiet, qa, qb, k, "x", "y", null); }
      let loud = tLink(db, la, lb);
      tEdge(db, loud, la, lb, "tension", "x", "y", null);
      tEdge(db, loud, la, lb, "develops", "x", "y", null);
      let body = tBody(tGet(db, null, "/linked"));
      expectHas(test, body, "2 pairs · 1 of them contain a tension, and those are first");
      expectHas(test, body, "<li id=\"link-${loud.toString()}\" class=\"has-tension\">");
      expectHas(test, body, "<li id=\"link-${quiet.toString()}\" class=\"\">");
      expectHas(test, body, "<span class=\"tension-count\"> · 1 tension</span>");
      expectTrue(test, tBefore(body, "Argues one", "Quiet one"), "the tension pair is first");
    }

    test("linked: two tensions say tensions") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let a = tDraft(db, owner.id, "Aa");
      let b = tDraft(db, owner.id, "Bb");
      let link = tLink(db, a, b);
      tEdge(db, link, a, b, "tension", "x", "y", null);
      tEdge(db, link, a, b, "tension", "x", "z", null);
      let body = tBody(tGet(db, null, "/linked"));
      expectHas(test, body, " · 2 tensions</span>");
      expectHas(test, body, "2 edges");
    }

    test("linked: with no pairs at all the empty line reads Nothing matches with empty quotes") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let body = tBody(tGet(db, null, "/linked"));
      expectHas(test, body, "<p class=\"mg-empty\">Nothing matches “”.</p>");
      expectHas(test, body, "0 pairs · 0 of them contain a tension");
    }

    test("linked: the form is a phx-change filter with the original placeholder") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let body = tBody(tGet(db, null, "/linked"));
      expectHas(test, body, "<form phx-change=\"filter\" id=\"lk-filter\" class=\"lk-filter\">");
      expectHas(test, body, "name=\"q\" value=\"\" placeholder=\"narrow by title — a case name, a chapter number\" autocomplete=\"off\">");
      expectHas(test, body, "<meta name=\"robots\" content=\"index, follow\">");
      expectHas(test, body, "Linked drafts · Marginalia");
    }

    test("linked: the filter event narrows by either title and answers with the region") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let qa = tDraft(db, owner.id, "Quiet one");
      let qb = tDraft(db, owner.id, "Quiet two");
      let la = tDraft(db, owner.id, "Argues one");
      let lb = tDraft(db, owner.id, "Argues two");
      tEdge(db, tLink(db, qa, qb), qa, qb, "develops", "x", "y", null);
      tEdge(db, tLink(db, la, lb), la, lb, "tension", "x", "y", null);
      let first = tGet(db, null, "/linked");
      let r = tEvent(db, first.ctx, "/linked", "filter", "{\"q\":\"argues\"}");
      expectInt(test, r.resp.status, 200);
      let main = tMain(r);
      expectHas(test, main, "Argues one");
      expectLacks(test, main, "Quiet one");
      expectHas(test, main, "value=\"argues\"");
    }

    test("linked: a filter matching nothing says so, with the query in curly quotes") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let a = tDraft(db, owner.id, "Aa");
      let b = tDraft(db, owner.id, "Bb");
      tEdge(db, tLink(db, a, b), a, b, "develops", "x", "y", null);
      let first = tGet(db, null, "/linked");
      let main = tMain(tEvent(db, first.ctx, "/linked", "filter", "{\"q\":\"nothing here\"}"));
      expectHas(test, main, "Nothing matches “nothing here”.");
      expectLacks(test, main, "Aa ↔ Bb");
    }

    test("linked: the filter is kept for the session until the page is loaded again") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let a = tDraft(db, owner.id, "Aa");
      let b = tDraft(db, owner.id, "Bb");
      tEdge(db, tLink(db, a, b), a, b, "develops", "x", "y", null);
      let first = tGet(db, null, "/linked");
      tEvent(db, first.ctx, "/linked", "filter", "{\"q\":\"zzz\"}");
      let again = tGet(db, first.ctx, "/linked");
      expectHas(test, tBody(again), "Aa ↔ Bb");
      expectLacks(test, tBody(again), "Nothing matches");
    }

    test("linked: forty rows, then a button for the rest, and more shows forty more") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let hub = tDraft(db, owner.id, "Hub");
      for (var i = 0; i < 43; ++i) {
        let spoke = tDraft(db, owner.id, "Spoke ${i.toString()}");
        tEdge(db, tLink(db, hub, spoke), hub, spoke, "develops", "x", "y", null);
      }
      let first = tGet(db, null, "/linked");
      let body = tBody(first);
      expectInt(test, tCount(body, "<li id=\"link-"), 40);
      expectHas(test, body, "<button class=\"mg-btn sm\" phx-click=\"more\">Show 3 more <span class=\"mg-meta\">of 3 left</span></button>");
      let main = tMain(tEvent(db, first.ctx, "/linked", "more", "{}"));
      expectInt(test, tCount(main, "<li id=\"link-"), 43);
      expectLacks(test, main, "phx-click=\"more\"");
    }

    test("linked: an event the page does not have stops loudly") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let first = tGet(db, null, "/linked");
      let survived = do { tEvent(db, first.ctx, "/linked", "make", "{}"); true } orelse false;
      expectTrue(test, !survived, "an unknown event must not look like success");
    }

## /linked/:id

    test("linked show: a stranger sees the pair, its edges, the rationale and the way to each draft") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let a = tDraft(db, owner.id, "The novel");
      let b = tDraft(db, owner.id, "The story");
      let link = tLink(db, a, b);
      tEdge(db, link, a, b, "pays_off", "He stops in the doorway", "The unanswered question", "Nine pays off the promise the story made.");
      let r = tGet(db, null, "/linked/${link.toString()}");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<h1>The novel ↔ The story</h1>");
      expectHas(test, body, "1 edges. Each names a part of one draft and a part of the other, and the direction is part of the claim.");
      expectHas(test, body, "<a href=\"/drafts/${a.slug}\">The novel</a> · <a href=\"/drafts/${b.slug}\">The story</a>");
      expectHas(test, body, "<h2 class=\"mg-label\">pays off · 1</h2>");
      expectHas(test, body, "<div class=\"lk-edge pays_off\">");
      expectHas(test, body, "<span class=\"from\">He stops in the doorway</span>");
      expectHas(test, body, "<span class=\"arrow\">pays off →</span>");
      expectHas(test, body, "<span class=\"to\">The unanswered question</span>");
      expectHas(test, body, "<p class=\"why\">Nine pays off the promise the story made.</p>");
      expectHas(test, body, "<blockquote class=\"lk-quote\">word word</blockquote>");
      expectHas(test, body, "<a href=\"/linked\">← Linked drafts</a>");
      expectHas(test, body, "The novel ↔ The story · Marginalia</title>");
      expectHas(test, body, "<meta name=\"description\" content=\"1 edges between two drafts.\">");
    }

    test("linked show: the groups come in the fixed order, tension first") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let a = tDraft(db, owner.id, "Aa");
      let b = tDraft(db, owner.id, "Bb");
      let link = tLink(db, a, b);
      tEdge(db, link, a, b, "echoes", "e", "f", null);
      tEdge(db, link, a, b, "develops", "d", "e", null);
      tEdge(db, link, a, b, "tension", "t", "u", null);
      let body = tBody(tGet(db, null, "/linked/${link.toString()}"));
      expectTrue(test, tBefore(body, "tension · 1", "develops · 1"), "tension before develops");
      expectTrue(test, tBefore(body, "develops · 1", "echoes · 1"), "develops before echoes");
      expectLacks(test, body, "pays off ·");
    }

    test("linked show: a rationale that says A and B names the drafts") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let a = tDraft(db, owner.id, "The novel");
      let b = tDraft(db, owner.id, "The story");
      let link = tLink(db, a, b);
      tEdge(db, link, a, b, "pays_off", "x", "y", "Manuscript A pays off what Manuscript B promised.");
      let body = tBody(tGet(db, null, "/linked/${link.toString()}"));
      expectLacks(test, body, "Manuscript A");
      expectLacks(test, body, "Manuscript B");
    }

    test("linked show: somebody else's pair, an empty pair and a missing one go to the list") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let other = tWho(db, "stranger@example.com");
      let ta = tDraft(db, other.id, "Their first");
      let tb = tDraft(db, other.id, "Their second");
      let theirs = tLink(db, ta, tb);
      tEdge(db, theirs, ta, tb, "develops", "Private", "Also private", null);
      let a = tDraft(db, owner.id, "Aa");
      let b = tDraft(db, owner.id, "Bb");
      let empty = tLink(db, a, b);
      let mixed = tLink(db, a, ta);
      tEdge(db, mixed, a, ta, "develops", "x", "y", null);
      for (let id of [theirs, empty, mixed, 9999]) {
        let r = tGet(db, null, "/linked/${id.toString()}");
        expectInt(test, r.resp.status, 303);
        expectText(test, tLocation(r), "/linked");
      }
      expectText(test, tGet(db, null, "/linked/${theirs.toString()}").ctx.session.flash.getOr("error", ""), "No such pair.");
    }

    test("linked show: an id that is no integer is a 400") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let r = tGet(db, null, "/linked/abc");
      expectInt(test, r.resp.status, 400);
    }

    test("linked show: it carries no control that writes") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let a = tDraft(db, owner.id, "Aa");
      let b = tDraft(db, owner.id, "Bb");
      let link = tLink(db, a, b);
      tEdge(db, link, a, b, "develops", "x", "y", null);
      let body = tBody(tGet(db, null, "/linked/${link.toString()}"));
      for (let c of ["make", "pick", "relink", "edit_block", "suggest_rewrite"]) {
        expectLacks(test, body, "phx-click=\"${c}\"");
      }
    }

## /reading

    test("reading: nothing published says so and lists no private folder") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let f = tFolder(db, owner.id, "A Backend For Something", null, false);
      tStory(db, f);
      let body = tBody(tGet(db, null, "/reading"));
      expectHas(test, body, "<p class=\"mg-empty\">Nothing published yet.</p>");
      expectLacks(test, body, "Half of building it");
      expectHas(test, body, "<h1>Readings</h1>");
      expectHas(test, body, "A series of documents read <em>forwards</em> — each one told only what the ones before it established.");
    }

    test("reading: a published folder with no story is hidden") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tFolder(db, owner.id, "Bare", "bare", true);
      let body = tBody(tGet(db, null, "/reading"));
      expectHas(test, body, "Nothing published yet.");
    }

    test("reading: a published reading is listed with its counts and its folder") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let body = tBody(tGet(db, null, "/reading"));
      expectHas(test, body, "<a href=\"/reading/a-backend-for-something\" class=\"t\">Half of building it is fixing the thing underneath</a>");
      expectHas(test, body, "<p class=\"mg-meta\">2 documents · 1 parts · A Backend For Something</p>");
      expectLacks(test, body, "Nothing published yet.");
      expectHas(test, body, "<title data-default=\"Someone who has actually read the whole thing\" data-suffix=\" · Marginalia\">Readings · Marginalia</title>");
      expectLacks(test, body, "name=\"robots\"");
    }

    test("reading: only the published folder is listed") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let other = tFolder(db, owner.id, "Employment agreements", null, false);
      tStory(db, other);
      let body = tBody(tGet(db, null, "/reading"));
      expectLacks(test, body, "Employment agreements");
    }

## /reading/:slug

    test("story: a stranger reads the telling") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let r = tGet(db, null, "/reading/a-backend-for-something");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<article class=\"st-story\">");
      expectHas(test, body, "<h1>Half of building it is fixing the thing underneath</h1>");
      expectHas(test, body, "<p class=\"mg-meta\">2 documents, read forwards. A Backend For Something</p>");
      expectHas(test, body, "<div class=\"lede md st-md\"><p>Nothing about this is hand-written at the level you would expect.</p>");
      expectHas(test, body, "<section class=\"st-move\"><h2><span class=\"n\">1</span>Get it running first</h2>");
      expectHas(test, body, "<code>cheap</code>");
      expectHas(test, body, "<div class=\"st-closing md st-md\"><p>That is the method.</p>");
      expectHas(test, body, "<a href=\"/reading\">← Readings</a>");
    }

    test("story: a movement lists the steps it comes from, each titled by its capability") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let body = tBody(tGet(db, null, "/reading/a-backend-for-something"));
      expectHas(test, body, "<nav class=\"st-move-steps\"><span class=\"mg-label\">from</span><a href=\"/reading/a-backend-for-something/1\" title=\"The thing emits a file that runs\">1</a></nav>");
    }

    test("story: a step that does not exist is titled step n") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let t = tReading(db, owner.id);
      db.exec("UPDATE stack_stories SET movements = '[{\"heading\":\"H\",\"prose\":\"p\",\"steps\":[7],\"turn\":\"\"}]' WHERE folder_id = $1", [t.folderId.toString()]);
      let body = tBody(tGet(db, null, "/reading/a-backend-for-something"));
      expectHas(test, body, "title=\"step 7\">7</a>");
    }

    test("story: a turn is an aside, and no turn is no aside") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let t = tReading(db, owner.id);
      let plain = tBody(tGet(db, null, "/reading/a-backend-for-something"));
      expectLacks(test, plain, "st-turn");
      db.exec("UPDATE stack_stories SET movements = '[{\"heading\":\"H\",\"prose\":\"p\",\"steps\":[],\"turn\":\"And then it **turned**.\"}]' WHERE folder_id = $1", [t.folderId.toString()]);
      let turned = tBody(tGet(db, null, "/reading/a-backend-for-something"));
      expectHas(test, turned, "<aside class=\"st-turn md st-md\"><p>And then it <strong>turned</strong>.</p>");
      expectLacks(test, turned, "st-move-steps");
    }

    test("story: the title and description of the page") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let body = tBody(tGet(db, null, "/reading/a-backend-for-something"));
      expectHas(test, body, "Half of building it is fixing the thing underneath · Marginalia</title>");
      expectHas(test, body, "<meta name=\"description\" content=\"Nothing about this is hand-written at the level you would expect.\">");
      expectLacks(test, body, "name=\"robots\"");
    }

    test("story: only its writer is offered the folder") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let t = tReading(db, owner.id);
      let stranger = tWho(db, "stranger@example.com");
      let stranger_page = tBody(tGet(db, stranger.ctx, "/reading/a-backend-for-something"));
      expectLacks(test, stranger_page, "Open the folder");
      expectLacks(test, stranger_page, "/stacks/");
      let anon = tBody(tGet(db, null, "/reading/a-backend-for-something"));
      expectLacks(test, anon, "Open the folder");
      let mine = tBody(tGet(db, owner.ctx, "/reading/a-backend-for-something"));
      expectHas(test, mine, "Yours. <a href=\"/stacks/${t.folderId.toString()}\">Open the folder</a> to read it forwards again, compose it again, or get at any of the 2 drafts.");
    }

    test("story: an unpublished folder, an unknown slug and a published folder with no story go to the list") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let f = tFolder(db, owner.id, "Hidden", "hidden", false);
      tStory(db, f);
      tFolder(db, owner.id, "Bare", "bare", true);
      for (let slug of ["hidden", "nope", "bare"]) {
        let r = tGet(db, null, "/reading/${slug}");
        expectInt(test, r.resp.status, 303);
        expectText(test, tLocation(r), "/reading");
        expectText(test, r.ctx.session.flash.getOr("error", ""), "No such reading.");
      }
    }

## /reading/:slug/:ordinal

    test("step: a stranger reads the step behind a paragraph") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let r = tGet(db, null, "/reading/a-backend-for-something/1");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectHas(test, body, "<article class=\"st-step\">");
      expectHas(test, body, "<span class=\"n\">Step 1 of 2</span>");
      expectHas(test, body, "<h1>The thing emits a file that runs</h1>");
      expectHas(test, body, "<h2 class=\"mg-label\">What to do</h2>");
      expectHas(test, body, "Emit one module and run it before building anything clever.");
      expectHas(test, body, "<section class=\"st-pitfall\"><h2 class=\"mg-label\">The obvious version is wrong</h2>");
      expectHas(test, body, "Assuming the printed form round-trips.");
      expectHas(test, body, "<blockquote>a whole Double prints as 1</blockquote>");
      expectHas(test, body, "<figure class=\"st-excerpt\"><pre><code>out_grammar do ... end</code></pre><figcaption>the grammar</figcaption></figure>");
      expectHas(test, body, "<h2 class=\"mg-label\">From the document</h2>");
      expectLacks(test, body, "How it works");
      expectLacks(test, body, "Get right now");
      expectLacks(test, body, "Walked back");
    }

    test("step: the title is the capability and the card is the default pitch") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let body = tBody(tGet(db, null, "/reading/a-backend-for-something/1"));
      expectHas(test, body, "The thing emits a file that runs · Marginalia</title>");
      expectHas(test, body, "<a href=\"/reading/a-backend-for-something\">← Half of building it is fixing the thing underneath</a>");
    }

    test("step: the neighbours, and what the step stands on") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let two = tBody(tGet(db, null, "/reading/a-backend-for-something/2"));
      expectHas(test, two, "<nav class=\"st-move-steps\"><span class=\"mg-label\">stands on</span><a href=\"/reading/a-backend-for-something/1\">1</a></nav>");
      expectHas(test, two, "<nav class=\"st-nav\"><a href=\"/reading/a-backend-for-something/1\">← 1. The thing emits a file that runs</a></nav>");
      let one = tBody(tGet(db, null, "/reading/a-backend-for-something/1"));
      expectHas(test, one, "<nav class=\"st-nav\"><a href=\"/reading/a-backend-for-something/2\">2. The file is the test →</a></nav>");
      expectLacks(test, one, "stands on");
    }

    test("step: mechanism, watch for and a walked-back step have sections of their own") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let t = tReading(db, owner.id);
      db.exec("UPDATE stack_steps SET mechanism = 'It works by **loading**.', watch_for = 'Check the exit code.', revised_by = 2, revision = 'Later this was wrong.', revision_quote = 'it was wrong' WHERE folder_id = $1 AND ordinal = 1", [t.folderId.toString()]);
      let body = tBody(tGet(db, null, "/reading/a-backend-for-something/1"));
      expectHas(test, body, "<h2 class=\"mg-label\">How it works</h2>");
      expectHas(test, body, "<strong>loading</strong>");
      expectHas(test, body, "<h2 class=\"mg-label\">Get right now</h2>");
      expectHas(test, body, "<section class=\"st-revision\"><h2 class=\"mg-label\">Walked back by step 2</h2>");
      expectHas(test, body, "<blockquote>it was wrong</blockquote>");
    }

    test("step: only the writer is told which draft it was read out of, and the slug is nowhere else") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let t = tReading(db, owner.id);
      let stranger = tWho(db, "stranger@example.com");
      let anon = tBody(tGet(db, null, "/reading/a-backend-for-something/1"));
      expectLacks(test, anon, t.work1.slug);
      expectLacks(test, anon, "yours to edit");
      let other = tBody(tGet(db, stranger.ctx, "/reading/a-backend-for-something/1"));
      expectLacks(test, other, t.work1.slug);
      let mine = tBody(tGet(db, owner.ctx, "/reading/a-backend-for-something/1"));
      expectHas(test, mine, "<a href=\"/works/${t.work1.slug}?view=read\">1. The first thing</a>");
      expectHas(test, mine, "which is yours to edit.");
    }

    test("step: a bad ordinal, a missing step and an unpublished folder go to the list") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      tReading(db, owner.id);
      let hidden = tFolder(db, owner.id, "Hidden", "hidden", false);
      let w = tDraft(db, owner.id, "Hidden doc");
      tStep(db, hidden, w.id, 1, "A step", "[]");
      for (let path of ["/reading/a-backend-for-something/1x", "/reading/a-backend-for-something/99", "/reading/hidden/1", "/reading/x/1"]) {
        let r = tGet(db, null, path);
        expectInt(test, r.resp.status, 303);
        expectText(test, tLocation(r), "/reading");
        expectText(test, r.ctx.session.flash.getOr("error", ""), "No such step.");
      }
    }

## /sitemap.xml

    test("sitemap: it is xml and lists the entry points under the origin") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let r = tGet(db, null, "/sitemap.xml");
      let body = tBody(r);
      expectInt(test, r.resp.status, 200);
      expectText(test, tHeader(r, "Content-Type"), "application/xml; charset=utf-8");
      expectHas(test, body, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemap.org/schemas/sitemap/0.9\">\n");
      for (let p of ["/", "/cases", "/drafts", "/linked", "/reading", "/works/new"]) {
        expectHas(test, body, "  <url><loc>http://localhost:4000${p}</loc></url>");
      }
      expectTrue(test, body.split("</urlset>").length == 2, "closed");
    }

    test("sitemap: the owner's drafts are in it and nobody else's, a changes page only with a revision") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let other = tWho(db, "stranger@example.com");
      let mine = tDraft(db, owner.id, "Mine");
      let theirs = tDraft(db, other.id, "Theirs");
      let plain = tBody(tGet(db, null, "/sitemap.xml"));
      expectHas(test, plain, "/drafts/${mine.slug}</loc>");
      expectLacks(test, plain, theirs.slug);
      expectLacks(test, plain, "/drafts/${mine.slug}/changes");
      tEdit(db, mine, "first paragraph", "opening paragraph", null, null);
      let changed = tBody(tGet(db, null, "/sitemap.xml"));
      expectHas(test, changed, "/drafts/${mine.slug}/changes</loc>");
    }

    test("sitemap: pairs that found something and published readings are in it") { test =>
      let db = dbOpen(":memory:");
      let owner = tOwner(db);
      let a = tDraft(db, owner.id, "Aa");
      let b = tDraft(db, owner.id, "Bb");
      let c = tDraft(db, owner.id, "Cc");
      let link = tLink(db, a, b);
      tEdge(db, link, a, b, "develops", "x", "y", null);
      let empty = tLink(db, a, c);
      tReading(db, owner.id);
      let hidden = tFolder(db, owner.id, "Hidden", "hidden", false);
      let body = tBody(tGet(db, null, "/sitemap.xml"));
      expectHas(test, body, "/linked/${link.toString()}</loc>");
      expectLacks(test, body, "/linked/${empty.toString()}<");
      expectHas(test, body, "/reading/a-backend-for-something</loc>");
      expectLacks(test, body, "/reading/hidden");
      expectLacks(test, body, "/reading/a-backend-for-something/1");
      expectTrue(test, hidden > 0, "made");
    }

    test("sitemap: a path is listed once") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let body = tBody(tGet(db, null, "/sitemap.xml"));
      expectInt(test, tCount(body, "<loc>http://localhost:4000/drafts</loc>"), 1);
      expectInt(test, tCount(body, "<loc>http://localhost:4000/</loc>"), 1);
    }

    test("sitemap: ampersand, less-than and greater-than are escaped, quotes are not") { test =>
      let xml = renderSitemap("http://x", ["/a&b<c>d\"e"]);
      expectHas(test, xml, "<loc>http://x/a&amp;b&lt;c&gt;d\"e</loc>");
    }

    test("sitemap: it sets no cookie and writes no session") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      let before = tN(db, "SELECT count(*) AS n FROM sessions");
      let r = tGet(db, null, "/sitemap.xml");
      expectText(test, tHeader(r, "Set-Cookie"), "");
      expectInt(test, tN(db, "SELECT count(*) AS n FROM sessions"), before);
    }

    test("sitemap: a client that accepts neither html nor anything gets a 406") { test =>
      let db = dbOpen(":memory:");
      tOwner(db);
      expectInt(test, tGetWith(db, "Accept: application/json\r\n", "/sitemap.xml").resp.status, 406);
      expectInt(test, tGetWith(db, "Accept: */*\r\n", "/sitemap.xml").resp.status, 200);
      expectInt(test, tGetWith(db, "Accept: text/html,application/xml\r\n", "/sitemap.xml").resp.status, 200);
      expectInt(test, tGetWith(db, "", "/sitemap.xml").resp.status, 200);
    }

## Helpers that carry the quirks

    test("parse: an ordinal is a whole integer or nothing") { test =>
      expectInt(test, tParse("12"), 12);
      expectInt(test, tParse("-3"), -3);
      expectInt(test, tParse("+4"), 4);
      expectInt(test, tParse("0"), 0);
      expectInt(test, tParse(""), -1000);
      expectInt(test, tParse("1x"), -1000);
      expectInt(test, tParse("x1"), -1000);
      expectInt(test, tParse("1 "), -1000);
      expectInt(test, tParse("-"), -1000);
      expectInt(test, tParse("1.5"), -1000);
    }
