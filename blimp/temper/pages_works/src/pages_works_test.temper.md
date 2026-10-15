# Tests for pages_works

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated. A
user is a row inserted by SQL (a real account costs a PBKDF2); a draft is a
row too, except in the tests of the upload, which go through
`worksCreateWork`. One `Ctx` is kept for a whole test, so the session's UI
state (what is collapsed, what is being renamed) carries from one event to the
next as it does between requests.

    let { dbOpen, Db } = import("db/src");
    let { Request, Response, Match, Route, UploadedFile, httpParse, routeMatch } = import("http/src");
    let { Scope, scopeFor, accountsGetUser } = import("accounts/src");
    let { Ctx, webNewCtx, uiGet, uiPut } = import("webcore/src");
    let { hjoin, wordCount } = import("html/src");
    let { JsonObject, JsonSyntaxTree, parseJson } = import("std/json");
    let { foldersCreateFolder, foldersMoveWork, foldersMoveFolder, foldersTree } = import("folders/src");
    let { worksGetBySlug, worksCreateWork, workParams } = import("works/src");
    let { StackStepRef } = import("stacks/src");
    let { ImporterHttp, importerFake, importerRoute, importerRouteFail, importerFetchPage } = import("importer/src");

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

    let tNoParams(): Map<String, String> {
      new MapBuilder<String, String>().toMap()
    }

    let tRaw(method: String, path: String, extra: String, body: String): Request {
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${body.split("").length.toString()}\r\n\r\n${body}")
    }

    let tMatch(method: String, path: String): Match throws Bubble {
      let m = routeMatch(pagesWorksRoutes(), method, path);
      if (m != null) { m } else { bubble() }
    }

    let tObject(json: String): JsonObject throws Bubble {
      let tree: JsonSyntaxTree = parseJson(json);
      if (tree is JsonObject) { tree } else { bubble() }
    }

    let tScope(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password, is_guest) VALUES ($1, 'x', 1)", [email]);
      scopeFor(accountsGetUser(db, id))
    }

A context for a page (`ajax` false) or an event (true), signed in as `scope`.

    let tCtx(db: Db, scope: Scope, path: String, ajax: Boolean): Ctx throws Bubble {
      let extra = if (ajax) { "X-Requested-With: blimp\r\n" } else { "" };
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", path, extra, ""), tNoParams());
      ctx.scope = scope;
      ctx
    }

    let tHeader(r: Response, name: String): String {
      var out = "";
      for (var i = 0; i < r.headers.length; ++i) {
        let p = r.headers.getOr(i, new Pair("", ""));
        if (p.key == name) { out = p.value; }
      }
      out
    }

    let tCount(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

A draft by SQL: titled, with the status given.

    let tWork(db: Db, scope: Scope, title: String, status: String): Int throws Bubble {
      db.insert(
        "INSERT INTO works (user_id, title, slug, body, word_count, status) VALUES ($1, $2, $3, 'a b c', 3, $4)",
        [scope.userId.toString(), title, "slug-${title}", status],
      )
    }

    let tFolder(db: Db, scope: Scope, name: String, parent: Int?): Int throws Bubble {
      let f = foldersCreateFolder(db, scope, name, parent).folder;
      if (f != null) { f.id } else { bubble() }
    }

    let tFolderOf(db: Db, id: Int): Int? throws Bubble {
      let row = db.one("SELECT folder_id FROM works WHERE id = $1", [id.toString()]);
      if (row != null) { row.intOrNull("folder_id") } else { bubble() }
    }

    let tParentOf(db: Db, id: Int): Int? throws Bubble {
      let row = db.one("SELECT parent_id FROM folders WHERE id = $1", [id.toString()]);
      if (row != null) { row.intOrNull("parent_id") } else { bubble() }
    }

    let tIs(got: Int?, want: Int): Boolean {
      got != null && got == want
    }

The `<main>` of /works as it would be sent now.

    let tIndexHtml(ctx: Ctx): String throws Bubble {
      hjoin(renderWorksIndex(ctx, loadWorksIndex(ctx)))
    }

An event on /works.

    let tEv(ctx: Ctx, event: String, payload: String): Response throws Bubble {
      pagesWorksEvent(ctx, tMatch("GET", "/works"), event, tObject(payload))
    }

An event on /works/new.

    let tNewEv(ctx: Ctx, event: String, payload: String): Response throws Bubble {
      pagesWorksEvent(ctx, tMatch("GET", "/works/new"), event, tObject(payload))
    }

    let tRepeat(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = tRepeat(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

    let tIndexSetup(): Db throws Bubble { dbOpen(":memory:") }

## Routes

    test("routes: the group's routes, in router order") { test =>
      let names = pagesWorksRoutes().map { (r: Route): String => "${r.method} ${r.pattern}" };
      expectText(test, names.join(", ") { (x: String): String => x },
        "POST /works/new, GET /works, GET /works/new");
    }

    test("routes: every one is in the guest scope") { test =>
      for (let r of pagesWorksRoutes()) {
        expectTrue(test, hasText(r.name, "guest."), r.name);
      }
    }

    test("routes: /works/new is matched before anything with a slug") { test =>
      let m = routeMatch(pagesWorksRoutes(), "GET", "/works/new");
      expectTrue(test, m != null, "matches");
      expectText(test, if (m != null) { m.route.name } else { "none" }, "guest.works_new");
    }

    test("routes: a draft's slug is not this group's") { test =>
      expectTrue(test, routeMatch(pagesWorksRoutes(), "GET", "/works/abc123") == null, "no match");
    }

## Index: the markup

    test("index: with nothing it says so and carries no tree") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works", false);
      let html = tIndexHtml(ctx);
      expectHas(test, html, "<p class=\"mg-empty mt-8\">Nothing here yet. Bring the draft in the drawer.</p>");
      expectLacks(test, html, "id=\"tree\"");
      expectHas(test, html, "<span class=\"mg-meta\">0</span>");
    }

    test("index: the heading, the count and the three ways to add") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "Alpha", "pending");
      tWork(db, me, "Beta", "pending");
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectHas(test, html, "<div class=\"mx-auto max-w-4xl px-6 py-10\">");
      expectHas(test, html, "<h1 style=\"font-family:var(--mg-serif)\" class=\"text-2xl font-semibold tracking-tight\">Your drafts</h1><span class=\"mg-meta\">2</span>");
      expectHas(test, html, "<form id=\"new-folder\" phx-submit=\"new_folder\" class=\"ml-auto flex items-center gap-2\">");
      expectHas(test, html, "name=\"name\" value=\"\" autocomplete=\"off\" placeholder=\"New folder\" class=\"mg-input sm mg-newfolder\"");
      expectHas(test, html, ">add folder</button>");
      expectHas(test, html, "<a href=\"/import\" class=\"mg-btn sm ghost\">Import many</a>");
      expectHas(test, html, "<a href=\"/works/new\" class=\"mg-btn\">Upload a draft</a>");
    }

    test("index: the tree is the hook's element and the root is a drop zone") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "Alpha", "pending");
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectHas(test, html, "<div id=\"tree\" phx-hook=\"Tree\" class=\"mg-tree mt-2\">");
      expectHas(test, html, "<div class=\"mg-tree-root\" data-drop-kind=\"folder\" data-drop-id=\"root\">");
    }

    test("index: the drag hint appears only when there is a folder") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "Alpha", "pending");
      let ctx = tCtx(db, me, "/works", false);
      expectLacks(test, tIndexHtml(ctx), "mg-tree-hint");
      tFolder(db, me, "Files", null);
      expectHas(test, tIndexHtml(ctx), "<p class=\"mg-tree-hint\">drag a draft onto a folder to file it · drop it out here to unfile it</p>");
    }

    test("index: a folder alone still draws the tree") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tFolder(db, me, "Files", null);
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectHas(test, html, "id=\"tree\"");
      expectLacks(test, html, "Nothing here yet");
    }

    test("index: a draft's row") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let w = tWork(db, me, "Alpha", "pending");
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectHas(test, html, "<div id=\"work-${w.toString()}\" class=\"mg-wrow\" draggable=\"true\" data-drag-kind=\"work\" data-drag-id=\"${w.toString()}\" style=\"padding-left:0.4rem\">");
      expectHas(test, html, "<span class=\"mg-grip\" aria-hidden=\"true\">⠿</span>");
      expectHas(test, html, "<a href=\"/works/slug-Alpha\" style=\"font-family:var(--mg-serif)\" class=\"text-[1.1rem] hover:text-[var(--mg-accent)]\">Alpha</a>");
      expectHas(test, html, "<div class=\"mg-meta mt-0.5\">3 words</div>");
      expectHas(test, html, "<button class=\"mg-btn sm ghost\" phx-click=\"delete\" phx-value-id=\"${w.toString()}\" data-confirm=\"Delete this draft, its map and its conversations?\">delete</button>");
    }

    test("index: the badge is ink only for a draft that has been read") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "Done", "read");
      tWork(db, me, "Waiting", "pending");
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectHas(test, html, "<span class=\"mg-badge ink\">read</span>");
      expectHas(test, html, "<span class=\"mg-badge \">pending</span>");
    }

    test("index: a draft that became a step links to it") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let w = tWork(db, me, "Alpha", "pending");
      let steps = new MapBuilder<Int, StackStepRef>();
      steps.set(w, new StackStepRef(w, 7, 3));
      let ctx = tCtx(db, me, "/works", false);
      let st = loadWorksIndex(ctx);
      let html = hjoin(renderWorksIndex(ctx, new WorksIndexState(st.tree, steps.toMap(), 0, [], null)));
      expectHas(test, html, "<a href=\"/stacks/7/3\" class=\"mg-btn sm ghost\" title=\"The step of the method this document became\">step 3</a>");
    }

    test("index: no step link without a step") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "Alpha", "pending");
      expectLacks(test, tIndexHtml(tCtx(db, me, "/works", false)), "/stacks/");
    }

    test("index: a folder's block") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      let id = f.toString();
      expectHas(test, html, "<div id=\"folder-${id}\" class=\"mg-fold\" draggable=\"true\" data-drag-kind=\"folder\" data-drag-id=\"${id}\">");
      expectHas(test, html, "<div class=\"mg-frow\" data-drop-kind=\"folder\" data-drop-id=\"${id}\" style=\"padding-left:0.4rem\">");
      expectHas(test, html, "<button type=\"button\" class=\"mg-twist\" phx-click=\"toggle\" phx-value-id=\"${id}\" aria-label=\"Collapse\">▾</button>");
      expectHas(test, html, "<button type=\"button\" class=\"mg-fname\" phx-click=\"toggle\" phx-value-id=\"${id}\">Case files</button>");
      expectHas(test, html, "<span class=\"mg-meta\">1</span>");
      expectHas(test, html, "<span class=\"mg-frow-tools\">");
      expectHas(test, html, "phx-click=\"rename_start\" phx-value-id=\"${id}\">rename</button>");
      expectHas(test, html, "phx-click=\"delete_folder\" phx-value-id=\"${id}\" data-confirm=\"Delete this folder? The drafts in it move up a level, they are not deleted.\">delete</button>");
    }

    test("index: a folder holds its children inside its own element") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      let fold = html.split("id=\"folder-${f.toString()}\"").getOr(1, "");
      let inside = fold.split("id=\"work-${w.toString()}\"");
      expectTrue(test, inside.length > 1, "the work row follows the folder");
      expectHas(test, fold, "<div class=\"mg-fkids\" style=\"--rail:0.95rem\">");
    }

    test("index: depth indents by 1.25rem and the rail follows") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let a = tFolder(db, me, "A", null);
      let b = tFolder(db, me, "B", a);
      let c = tFolder(db, me, "C", b);
      let w = tWork(db, me, "Deep", "pending");
      foldersMoveWork(db, me, w, c);
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectHas(test, html, "data-drop-id=\"${a.toString()}\" style=\"padding-left:0.4rem\"");
      expectHas(test, html, "data-drop-id=\"${b.toString()}\" style=\"padding-left:1.65rem\"");
      expectHas(test, html, "data-drop-id=\"${c.toString()}\" style=\"padding-left:2.9rem\"");
      expectHas(test, html, "style=\"--rail:0.95rem\"");
      expectHas(test, html, "style=\"--rail:2.2rem\"");
      expectHas(test, html, "style=\"--rail:3.45rem\"");
      expectHas(test, html, "data-drag-kind=\"work\" data-drag-id=\"${w.toString()}\" style=\"padding-left:4.15rem\"");
    }

    test("index: the rem sums print as the floats did") { test =>
      expectText(test, pwRem(40), "0.4");
      expectText(test, pwRem(165), "1.65");
      expectText(test, pwRem(290), "2.9");
      expectText(test, pwRem(415), "4.15");
      expectText(test, pwRem(540), "5.4");
      expectText(test, pwRem(105), "1.05");
      expectText(test, pwRem(200), "2");
    }

    test("index: an empty folder says so") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tFolder(db, me, "Files", null);
      expectHas(test, tIndexHtml(tCtx(db, me, "/works", false)), "<p class=\"mg-fempty\">empty — drag a draft here</p>");
    }

    test("index: folders are in name order and drafts newest first") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tFolder(db, me, "beta", null);
      tFolder(db, me, "Alpha", null);
      tWork(db, me, "First", "pending");
      tWork(db, me, "Second", "pending");
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectTrue(test, html.split("Alpha</button>").getOr(0, "").split("beta</button>").length == 1, "Alpha before beta");
      expectTrue(test, html.split("Second</a>").getOr(0, "").split("First</a>").length == 1, "newest first");
    }

    test("index: another writer's drafts and folders are not shown") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let them = tScope(db, "b@x.test");
      tWork(db, them, "Theirs", "pending");
      tFolder(db, them, "Their folder", null);
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectLacks(test, html, "Theirs");
      expectLacks(test, html, "Their folder");
      expectHas(test, html, "Nothing here yet");
    }

    test("index: the offer to file by case appears only with something to file") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let w = tWork(db, me, "Alpha", "pending");
      expectLacks(test, tIndexHtml(tCtx(db, me, "/works", false)), "file them by case");
      db.exec("UPDATE works SET collection = 'Demo v. Example', collection_role = 'opinion' WHERE id = $1", [w.toString()]);
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectHas(test, html, "<p class=\"mg-tidy\">1 of these already say which case they belong to. <button phx-click=\"backfill\" class=\"mg-btn sm ghost\">file them by case</button></p>");
    }

    test("index: a collapsed folder shows the other twist and none of its contents") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "toggle", "{\"id\":\"${f.toString()}\"}");
      let html = tIndexHtml(ctx);
      expectHas(test, html, "aria-label=\"Expand\">▸</button>");
      expectLacks(test, html, "Alpha");
      expectLacks(test, html, "mg-fkids");
    }

    test("index: the folder being renamed is a form") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "rename_start", "{\"id\":\"${f.toString()}\"}");
      let html = tIndexHtml(ctx);
      let id = f.toString();
      expectHas(test, html, "<form id=\"rename-${id}\" phx-submit=\"rename\" class=\"flex flex-1 items-center gap-2\">");
      expectHas(test, html, "<input type=\"hidden\" name=\"folder_id\" value=\"${id}\">");
      expectHas(test, html, "name=\"name\" value=\"Case files\" autocomplete=\"off\" class=\"mg-input sm flex-1\" phx-mounted=");
      expectHas(test, html, "phx-window-keydown=\"rename_cancel\" phx-key=\"Escape\"");
      expectHas(test, html, "<button class=\"mg-btn sm ghost\" type=\"submit\">save</button>");
      expectLacks(test, html, "class=\"mg-fname\"");
      expectLacks(test, html, "class=\"mg-frow-tools\"");
    }

    test("index: text from the database is escaped") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "<b>Bold</b> & \"quoted\"", "pending");
      tFolder(db, me, "<i>f</i>", null);
      let html = tIndexHtml(tCtx(db, me, "/works", false));
      expectHas(test, html, "&lt;b&gt;Bold&lt;/b&gt; &amp; &quot;quoted&quot;");
      expectHas(test, html, "&lt;i&gt;f&lt;/i&gt;");
      expectLacks(test, html, "<b>Bold");
    }

## Index: the page

    test("page: GET /works is the whole page for a plain request") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "Alpha", "pending");
      let ctx = tCtx(db, me, "/works", false);
      let r = pagesWorksGet(ctx, tMatch("GET", "/works"));
      expectInt(test, r.status, 200);
      expectHas(test, r.body, "<title");
      expectHas(test, r.body, "Your drafts");
      expectHas(test, r.body, "Alpha");
    }

    test("page: GET /works answers a poll with the region") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "Alpha", "pending");
      let ctx = tCtx(db, me, "/works", true);
      let r = pagesWorksGet(ctx, tMatch("GET", "/works"));
      expectInt(test, r.status, 200);
      expectHas(test, r.body, "\"regions\"");
      expectHas(test, r.body, "Alpha");
    }

    test("page: a page load starts with nothing collapsed and no rename") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Files", null);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "toggle", "{\"id\":\"${f.toString()}\"}");
      tEv(ctx, "rename_start", "{\"id\":\"${f.toString()}\"}");
      expectTrue(test, uiGet(ctx, "works:collapsed") != null, "collapsed is kept by an event");
      expectTrue(test, uiGet(ctx, "works:renaming") != null, "renaming is kept by an event");
      let again = tCtx(db, me, "/works", false);
      again.session.ui = ctx.session.ui;
      pagesWorksGet(again, tMatch("GET", "/works"));
      expectTrue(test, uiGet(again, "works:collapsed") == null, "a load clears collapsed");
      expectTrue(test, uiGet(again, "works:renaming") == null, "a load clears renaming");
    }

## Index: new_folder

    test("new_folder: makes a top-level folder") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let ctx = tCtx(db, me, "/works", true);
      let r = tEv(ctx, "new_folder", "{\"name\":\"Case files\"}");
      expectInt(test, r.status, 200);
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders WHERE name = 'Case files' AND parent_id IS NULL"), 1);
      expectHas(test, r.body, "Case files");
      expectHas(test, r.body, "empty — drag a draft here");
    }

    test("new_folder: the name is trimmed") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tEv(tCtx(db, me, "/works", true), "new_folder", "{\"name\":\"   Padded  \"}");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders WHERE name = 'Padded'"), 1);
    }

    test("new_folder: a blank name is ignored, with no flash") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tEv(tCtx(db, me, "/works", true), "new_folder", "{\"name\":\"   \"}");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), 0);
      expectLacks(test, r.body, "\"error\"");
    }

    test("new_folder: a duplicate says so and is not made twice") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "new_folder", "{\"name\":\"Case files\"}");
      let r = tEv(ctx, "new_folder", "{\"name\":\"Case files\"}");
      expectHas(test, r.body, "name there is already a folder with that name here");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), 1);
    }

    test("new_folder: two writers may use the same name") { test =>
      let db = dbOpen(":memory:");
      let a = tScope(db, "a@x.test");
      let b = tScope(db, "b@x.test");
      tEv(tCtx(db, a, "/works", true), "new_folder", "{\"name\":\"Files\"}");
      tEv(tCtx(db, b, "/works", true), "new_folder", "{\"name\":\"Files\"}");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), 2);
    }

    test("new_folder: a name over 80 characters is refused out loud") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tEv(tCtx(db, me, "/works", true), "new_folder", "{\"name\":\"${tRepeat("x", 81)}\"}");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), 0);
      expectHas(test, r.body, "\"error\"");
    }

## Index: move

    test("move: a draft dropped on a folder is filed there") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "move", "{\"kind\":\"work\",\"id\":\"${w.toString()}\",\"into\":\"${f.toString()}\"}");
      expectTrue(test, tIs(tFolderOf(db, w), f), "filed");
      let node = foldersTree(db, me).folders.getOr(0, foldersTree(db, me));
      expectInt(test, node.works.length, 1);
    }

    test("move: dropped on the root it comes out again") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"work\",\"id\":\"${w.toString()}\",\"into\":\"root\"}");
      expectTrue(test, tFolderOf(db, w) == null, "unfiled");
    }

    test("move: an empty `into` is the root too") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"work\",\"id\":\"${w.toString()}\",\"into\":\"\"}");
      expectTrue(test, tFolderOf(db, w) == null, "unfiled");
    }

    test("move: a draft dropped where it already is stays") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      let r = tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"work\",\"id\":\"${w.toString()}\",\"into\":\"${f.toString()}\"}");
      expectInt(test, r.status, 200);
      expectTrue(test, tIs(tFolderOf(db, w), f), "still there");
    }

    test("move: a folder dropped on a folder nests it") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let outer = tFolder(db, me, "Outer", null);
      let inner = tFolder(db, me, "Inner", null);
      tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"folder\",\"id\":\"${inner.toString()}\",\"into\":\"${outer.toString()}\"}");
      expectTrue(test, tIs(tParentOf(db, inner), outer), "nested");
    }

    test("move: a folder dropped on the root is lifted out") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let outer = tFolder(db, me, "Outer", null);
      let inner = tFolder(db, me, "Inner", outer);
      tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"folder\",\"id\":\"${inner.toString()}\",\"into\":\"root\"}");
      expectTrue(test, tParentOf(db, inner) == null, "at the root");
    }

    test("move: a folder into its own child is refused out loud") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let outer = tFolder(db, me, "Outer", null);
      let inner = tFolder(db, me, "Inner", outer);
      let r = tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"folder\",\"id\":\"${outer.toString()}\",\"into\":\"${inner.toString()}\"}");
      expectHas(test, r.body, "A folder cannot go inside itself.");
      expectTrue(test, tParentOf(db, outer) == null, "unchanged");
    }

    test("move: a folder into itself is the same refusal") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Solo", null);
      let r = tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"folder\",\"id\":\"${f.toString()}\",\"into\":\"${f.toString()}\"}");
      expectHas(test, r.body, "A folder cannot go inside itself.");
    }

    test("move: a folder whose name is taken in the new place says so") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let outer = tFolder(db, me, "Outer", null);
      tFolder(db, me, "Same", outer);
      let loose = tFolder(db, me, "Same", null);
      let r = tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"folder\",\"id\":\"${loose.toString()}\",\"into\":\"${outer.toString()}\"}");
      expectHas(test, r.body, "name there is already a folder with that name here");
      expectTrue(test, tParentOf(db, loose) == null, "unchanged");
    }

    test("move: someone else's draft is not moved") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let them = tScope(db, "b@x.test");
      let mine = tFolder(db, me, "Mine", null);
      let theirs = tWork(db, them, "Theirs", "pending");
      let r = tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"work\",\"id\":\"${theirs.toString()}\",\"into\":\"${mine.toString()}\"}");
      expectInt(test, r.status, 200);
      expectTrue(test, tFolderOf(db, theirs) == null, "not filed");
    }

    test("move: into someone else's folder lands at the root") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let them = tScope(db, "b@x.test");
      let mine = tFolder(db, me, "Mine", null);
      let theirs = tFolder(db, them, "Theirs", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, mine);
      tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"work\",\"id\":\"${w.toString()}\",\"into\":\"${theirs.toString()}\"}");
      expectTrue(test, tFolderOf(db, w) == null, "unfiled, not in theirs");
    }

    test("move: ids sent as numbers work too") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"work\",\"id\":${w.toString()},\"into\":${f.toString()}}");
      expectTrue(test, tIs(tFolderOf(db, w), f), "filed");
    }

    test("move: an id that is no number moves nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let w = tWork(db, me, "Alpha", "pending");
      let r = tEv(tCtx(db, me, "/works", true), "move", "{\"kind\":\"work\",\"id\":\"nope\",\"into\":\"root\"}");
      expectInt(test, r.status, 200);
      expectTrue(test, tFolderOf(db, w) == null, "nothing happened");
    }

## Index: toggle, rename, delete

    test("toggle: closes a folder and a second toggle opens it again") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "toggle", "{\"id\":\"${f.toString()}\"}");
      expectLacks(test, tIndexHtml(ctx), "Alpha");
      tEv(ctx, "toggle", "{\"id\":\"${f.toString()}\"}");
      expectHas(test, tIndexHtml(ctx), "Alpha");
      expectTrue(test, tIs(tFolderOf(db, w), f), "nothing moved");
    }

    test("toggle: one folder at a time") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let a = tFolder(db, me, "A", null);
      let b = tFolder(db, me, "B", null);
      let wa = tWork(db, me, "InA", "pending");
      let wb = tWork(db, me, "InB", "pending");
      foldersMoveWork(db, me, wa, a);
      foldersMoveWork(db, me, wb, b);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "toggle", "{\"id\":\"${a.toString()}\"}");
      let html = tIndexHtml(ctx);
      expectLacks(test, html, "InA");
      expectHas(test, html, "InB");
    }

    test("toggle: touches no row") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let before = tCount(db, "SELECT count(*) AS n FROM folders");
      tEv(tCtx(db, me, "/works", true), "toggle", "{\"id\":\"${f.toString()}\"}");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), before);
    }

    test("rename_start and rename_cancel") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "rename_start", "{\"id\":\"${f.toString()}\"}");
      expectHas(test, tIndexHtml(ctx), "id=\"rename-${f.toString()}\"");
      tEv(ctx, "rename_cancel", "{\"key\":\"Escape\"}");
      expectLacks(test, tIndexHtml(ctx), "id=\"rename-");
      expectHas(test, tIndexHtml(ctx), "class=\"mg-fname\"");
    }

    test("rename: a new name replaces the old and keeps the contents") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "rename_start", "{\"id\":\"${f.toString()}\"}");
      tEv(ctx, "rename", "{\"folder_id\":\"${f.toString()}\",\"name\":\"Briefs\"}");
      let html = tIndexHtml(ctx);
      expectHas(test, html, "Briefs");
      expectLacks(test, html, "Case files");
      expectLacks(test, html, "id=\"rename-");
      expectTrue(test, tIs(tFolderOf(db, w), f), "contents kept");
    }

    test("rename: a name that clashes stays in rename mode and says why") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tFolder(db, me, "Taken", null);
      let f = tFolder(db, me, "Mine", null);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "rename_start", "{\"id\":\"${f.toString()}\"}");
      let r = tEv(ctx, "rename", "{\"folder_id\":\"${f.toString()}\",\"name\":\"Taken\"}");
      expectHas(test, r.body, "name there is already a folder with that name here");
      expectHas(test, tIndexHtml(ctx), "id=\"rename-${f.toString()}\"");
    }

    test("rename: a blank name is refused") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Mine", null);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "rename_start", "{\"id\":\"${f.toString()}\"}");
      let r = tEv(ctx, "rename", "{\"folder_id\":\"${f.toString()}\",\"name\":\"  \"}");
      expectHas(test, r.body, "\"error\"");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders WHERE name = 'Mine'"), 1);
    }

    test("rename: a folder that is gone ends the rename without a flash") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Mine", null);
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "rename_start", "{\"id\":\"${f.toString()}\"}");
      db.exec("DELETE FROM folders WHERE id = $1", [f.toString()]);
      let r = tEv(ctx, "rename", "{\"folder_id\":\"${f.toString()}\",\"name\":\"Other\"}");
      expectLacks(test, r.body, "\"error\"");
      expectTrue(test, uiGet(ctx, "works:renaming") == null, "rename ended");
    }

    test("rename: someone else's folder is not renamed") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let them = tScope(db, "b@x.test");
      let theirs = tFolder(db, them, "Theirs", null);
      tEv(tCtx(db, me, "/works", true), "rename", "{\"folder_id\":\"${theirs.toString()}\",\"name\":\"Mine now\"}");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders WHERE name = 'Theirs'"), 1);
    }

    test("delete_folder: the drafts move up and are not deleted") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let f = tFolder(db, me, "Case files", null);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, f);
      let r = tEv(tCtx(db, me, "/works", true), "delete_folder", "{\"id\":\"${f.toString()}\"}");
      expectHas(test, r.body, "Folder gone. What was in it moved up a level.");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), 0);
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 1);
      expectTrue(test, tFolderOf(db, w) == null, "at the root");
    }

    test("delete_folder: what it held goes to its parent, not the root") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let outer = tFolder(db, me, "Outer", null);
      let mid = tFolder(db, me, "Mid", outer);
      let inner = tFolder(db, me, "Inner", mid);
      let w = tWork(db, me, "Alpha", "pending");
      foldersMoveWork(db, me, w, mid);
      tEv(tCtx(db, me, "/works", true), "delete_folder", "{\"id\":\"${mid.toString()}\"}");
      expectTrue(test, tIs(tFolderOf(db, w), outer), "draft in outer");
      expectTrue(test, tIs(tParentOf(db, inner), outer), "inner in outer");
    }

    test("delete_folder: someone else's folder stays and nothing is said") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let them = tScope(db, "b@x.test");
      let theirs = tFolder(db, them, "Theirs", null);
      let r = tEv(tCtx(db, me, "/works", true), "delete_folder", "{\"id\":\"${theirs.toString()}\"}");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), 1);
      expectLacks(test, r.body, "Folder gone");
    }

    test("delete: removes the draft and says so") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let w = tWork(db, me, "Alpha", "pending");
      tWork(db, me, "Beta", "pending");
      let r = tEv(tCtx(db, me, "/works", true), "delete", "{\"id\":\"${w.toString()}\"}");
      expectHas(test, r.body, "Deleted.");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 1);
      expectLacks(test, r.body, "Alpha");
      expectHas(test, r.body, "Beta");
    }

    test("delete: takes the sections with it") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let made = worksCreateWork(db, me, workParams("Real", "# One\n\n${tRepeat("word ", 50)}\n\n# Two\n\n${tRepeat("word ", 50)}"));
      let w = made.ok;
      expectTrue(test, w != null, "made");
      expectTrue(test, tCount(db, "SELECT count(*) AS n FROM sections") > 0, "sections exist");
      if (w != null) { tEv(tCtx(db, me, "/works", true), "delete", "{\"id\":\"${w.id.toString()}\"}"); }
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM sections"), 0);
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("delete: someone else's draft is no draft of yours") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let them = tScope(db, "b@x.test");
      let theirs = tWork(db, them, "Theirs", "pending");
      let r = tEv(tCtx(db, me, "/works", true), "delete", "{\"id\":\"${theirs.toString()}\"}");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 1);
      expectLacks(test, r.body, "Deleted.");
    }

    test("delete: a draft that is not there is a no-op") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tEv(tCtx(db, me, "/works", true), "delete", "{\"id\":\"9999\"}");
      expectInt(test, r.status, 200);
      expectLacks(test, r.body, "Deleted.");
    }

## Index: backfill

    let tPlace(db: Db, id: Int, collection: String, role: String): Void throws Bubble {
      db.exec("UPDATE works SET collection = $1, collection_role = $2 WHERE id = $3", [collection, role, id.toString()]);
    }

    test("backfill: files the drafts by case and says how many") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let a = tWork(db, me, "Alpha", "pending");
      let b = tWork(db, me, "Beta", "pending");
      tPlace(db, a, "Demo v. Example", "opinion");
      tPlace(db, b, "Demo v. Example", "dissent");
      let ctx = tCtx(db, me, "/works", true);
      let r = tEv(ctx, "backfill", "{}");
      expectHas(test, r.body, "Filed 2 drafts by case.");
      let top = foldersTree(db, me);
      expectInt(test, top.folders.length, 1);
      let cases = top.folders.getOr(0, top);
      let cf = cases.folder;
      expectText(test, if (cf != null) { cf.name } else { "none" }, "Cases");
      let inner = cases.folders.getOr(0, top);
      let nf = inner.folder;
      expectText(test, if (nf != null) { nf.name } else { "none" }, "Demo v. Example");
      expectInt(test, inner.works.length, 2);
      expectLacks(test, tIndexHtml(ctx), "file them by case");
    }

    test("backfill: one draft is `draft`") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let a = tWork(db, me, "Alpha", "pending");
      tPlace(db, a, "Demo v. Example", "opinion");
      let r = tEv(tCtx(db, me, "/works", true), "backfill", "{}");
      expectHas(test, r.body, "Filed 1 draft by case.");
    }

    test("backfill: a draft already in a folder is left alone") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let pile = tFolder(db, me, "Reading pile", null);
      let a = tWork(db, me, "Alpha", "pending");
      let b = tWork(db, me, "Beta", "pending");
      tPlace(db, a, "Demo v. Example", "opinion");
      tPlace(db, b, "Demo v. Example", "dissent");
      foldersMoveWork(db, me, a, pile);
      let ctx = tCtx(db, me, "/works", true);
      expectHas(test, tIndexHtml(ctx), "1 of these already say which case");
      tEv(ctx, "backfill", "{}");
      expectTrue(test, tIs(tFolderOf(db, a), pile), "still in the pile");
    }

    test("backfill: with nothing to file it says nothing and makes nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tWork(db, me, "Alpha", "pending");
      let r = tEv(tCtx(db, me, "/works", true), "backfill", "{}");
      expectLacks(test, r.body, "Filed");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), 0);
    }

    test("backfill: twice files nothing the second time") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let a = tWork(db, me, "Alpha", "pending");
      tPlace(db, a, "Demo v. Example", "opinion");
      let ctx = tCtx(db, me, "/works", true);
      tEv(ctx, "backfill", "{}");
      let r = tEv(ctx, "backfill", "{}");
      expectLacks(test, r.body, "Filed");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM folders"), 2);
    }

    test("an event the page does not have stops the request") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let ctx = tCtx(db, me, "/works", true);
      var answered = false;
      let ok = do { tEv(ctx, "frobnicate", "{}"); answered = true; true } orelse false;
      expectTrue(test, !answered, "no answer");
      let ok2 = do { tNewEv(ctx, "frobnicate", "{}"); answered = true; true } orelse false;
      expectTrue(test, !answered, "no answer from /works/new either");
    }

## New: the markup

    let tNewHtml(db: Db, state: WorksNewState): String throws Bubble {
      let ctx = tCtx(db, tScope(db, "n${state.title}@x.test"), "/works/new", false);
      hjoin(renderWorksNew(ctx, state))
    }

    let tBlankNew(): WorksNewState {
      new WorksNewState(null, null, "", "", "", "")
    }

    test("new: the heading and the lede") { test =>
      let html = tNewHtml(dbOpen(":memory:"), tBlankNew());
      expectHas(test, html, "<div class=\"mx-auto max-w-2xl px-6 py-10\">");
      expectHas(test, html, "<h1 style=\"font-family:var(--mg-serif)\" class=\"text-2xl font-semibold tracking-tight\">Upload a draft</h1>");
      expectHas(test, html, "<p class=\"mg-prose mt-2 text-[0.95rem] text-[var(--mg-dim)]\">Paste it or attach a <code>.txt</code>/<code>.md</code> file. Nothing is read until you confirm how it's divided on the next screen.</p>");
    }

    test("new: the form posts multipart to /works/new with a token") { test =>
      let html = tNewHtml(dbOpen(":memory:"), tBlankNew());
      expectHas(test, html, "<form id=\"upload-form\" action=\"/works/new\" method=\"post\" enctype=\"multipart/form-data\" class=\"mt-6 space-y-5\">");
      expectHas(test, html, "name=\"_csrf_token\"");
    }

    test("new: the main form is not an event form") { test =>
      let html = tNewHtml(dbOpen(":memory:"), tBlankNew());
      let main = html.split("id=\"upload-form\"").getOr(1, "");
      expectLacks(test, main.split(">").getOr(0, ""), "phx-submit");
    }

    test("new: title, intent and body fields") { test =>
      let html = tNewHtml(dbOpen(":memory:"), tBlankNew());
      expectHas(test, html, "<span class=\"mg-label block mb-1.5\">Title</span>");
      expectHas(test, html, "<input type=\"text\" name=\"work[title]\" id=\"work_title\" value=\"\" class=\"mg-input\" placeholder=\"Working title is fine\">");
      expectHas(test, html, "<span class=\"mg-label block mb-1.5\">In a sentence or two, what is this supposed to do to a reader?</span>");
      expectHas(test, html, "<textarea id=\"work_intent\" name=\"work[intent]\" class=\"mg-textarea\" rows=\"2\" placeholder=\"Optional — but it&#39;s what stops the notes being generic.\"></textarea>");
      expectHas(test, html, "<span class=\"mg-label block mb-1.5\">Paste the draft</span>");
      expectHas(test, html, "<textarea id=\"work_body\" name=\"work[body]\" class=\"mg-textarea\" rows=\"12\" placeholder=\"Paste the whole thing. Chapter headings or markdown headings help it divide the draft correctly.\"></textarea>");
    }

    test("new: the file input takes the four extensions") { test =>
      let html = tNewHtml(dbOpen(":memory:"), tBlankNew());
      expectHas(test, html, "<input type=\"file\" id=\"manuscript\" name=\"manuscript\" accept=\".txt,.md,.markdown,.text\">");
      expectHas(test, html, "Attach a file");
      expectHas(test, html, "<div class=\"border border-dashed border-[var(--mg-rule)] rounded-sm p-5 text-[0.85rem] bg-[var(--mg-card)]\">");
    }

    test("new: the or rule and the button") { test =>
      let html = tNewHtml(dbOpen(":memory:"), tBlankNew());
      expectHas(test, html, "<span class=\"mg-label\">or</span>");
      expectHas(test, html, "<button type=\"submit\" class=\"mg-btn\">Continue</button>");
    }

    test("new: the fetch form is its own form above the main one") { test =>
      let html = tNewHtml(dbOpen(":memory:"), tBlankNew());
      expectHas(test, html, "<form id=\"fetch-form\" phx-submit=\"fetch\" class=\"mt-6\">");
      expectHas(test, html, "<label class=\"mg-label block mb-1.5\" for=\"import-url\">Read it off the web</label>");
      expectHas(test, html, "<input type=\"url\" id=\"import-url\" name=\"url\" value=\"\" placeholder=\"https://…\"");
      expectHas(test, html, ">Fetch</button>");
      expectHas(test, html, "<p class=\"mg-hint mt-1.5\">The article is pulled out and turned into markdown");
      expectTrue(test, html.split("id=\"fetch-form\"").getOr(0, "").split("id=\"upload-form\"").length == 1, "fetch form comes first");
    }

    test("new: the address typed stays in its box") { test =>
      let html = tNewHtml(dbOpen(":memory:"), new WorksNewState(null, null, "https://example.com/a", "", "", ""));
      expectHas(test, html, "name=\"url\" value=\"https://example.com/a\"");
    }

    test("new: typed values are echoed and escaped") { test =>
      let html = tNewHtml(dbOpen(":memory:"), new WorksNewState(null, null, "", "A \"title\" <x>", "why & how", "<script>alert(1)</script>"));
      expectHas(test, html, "value=\"A &quot;title&quot; &lt;x&gt;\"");
      expectHas(test, html, ">why &amp; how</textarea>");
      expectHas(test, html, "&lt;script&gt;alert(1)&lt;/script&gt;");
      expectLacks(test, html, "<script>alert");
    }

    test("new: the error box and the file error") { test =>
      let none = tNewHtml(dbOpen(":memory:"), tBlankNew());
      expectLacks(test, none, "border-l-2");
      expectLacks(test, none, "text-[0.75rem]");
      let both = tNewHtml(dbOpen(":memory:"), new WorksNewState("Trouble.", "Only .txt and .md for now.", "", "", "", ""));
      expectHas(test, both, "<div class=\"mt-5 border-l-2 border-[var(--mg-accent)] pl-3 py-1.5 text-[0.85rem]\">Trouble.</div>");
      expectHas(test, both, "<p class=\"text-[var(--mg-accent)] text-[0.75rem] mt-1\">Only .txt and .md for now.</p>");
    }

    test("new: GET /works/new is a page and carries the title") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", false);
      let r = pagesWorksGet(ctx, tMatch("GET", "/works/new"));
      expectInt(test, r.status, 200);
      expectHas(test, r.body, "Upload a draft");
      expectHas(test, r.body, "action=\"/works/new\"");
    }

## New: POST /works/new

    let tForm(title: String, intent: String, body: String): Map<String, String> {
      let m = new MapBuilder<String, String>();
      m.set("work[title]", title);
      m.set("work[intent]", intent);
      m.set("work[body]", body);
      m.toMap()
    }

    let tPostCtx(db: Db, scope: Scope, form: Map<String, String>, files: List<UploadedFile>, truncated: Boolean): Ctx throws Bubble {
      let req = new Request("POST", "/works/new", tNoParams(), tNoParams(), tNoParams(), "", form, files, truncated);
      let ctx = webNewCtx(db, ":memory:", req, tNoParams());
      ctx.scope = scope;
      ctx
    }

    let tPost(db: Db, scope: Scope, form: Map<String, String>, files: List<UploadedFile>): Response throws Bubble {
      pagesWorksGet(tPostCtx(db, scope, form, files, false), tMatch("POST", "/works/new"))
    }

    let tNoFiles(): List<UploadedFile> { [] }

    let tFile(name: String, content: String): List<UploadedFile> {
      [new UploadedFile("manuscript", name, "text/plain", content)]
    }

    let tDraft(): String {
      "# One\n\n${tRepeat("word ", 200)}\n\n# Two\n\n${tRepeat("more ", 200)}\n"
    }

    let tSlugOf(r: Response): String {
      let loc = tHeader(r, "Location");
      if (loc.split("/works/").length > 1) { loc.split("/works/").getOr(1, "") } else { "" }
    }

    test("post: a pasted draft is saved and the browser is sent to it") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("Pasted", "", tDraft()), tNoFiles());
      expectInt(test, r.status, 303);
      let slug = tSlugOf(r);
      expectTrue(test, slug != "", "a location: ${tHeader(r, "Location")}");
      let w = worksGetBySlug(db, slug);
      expectTrue(test, w != null, "the draft is there");
      expectText(test, if (w != null) { w.title } else { "none" }, "Pasted");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 1);
    }

    test("post: the draft is split into sections") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      tPost(db, me, tForm("Pasted", "", tDraft()), tNoFiles());
      expectTrue(test, tCount(db, "SELECT count(*) AS n FROM sections") > 0, "sections were written");
    }

    test("post: the slug is long and is not the row id") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("Pasted", "", tDraft()), tNoFiles());
      let slug = tSlugOf(r);
      expectTrue(test, slug.split("").length > 20, "long: ${slug}");
      expectTrue(test, slug != "1", "not 1");
    }

    test("post: the draft belongs to whoever posted it") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let them = tScope(db, "b@x.test");
      tPost(db, me, tForm("Mine", "", tDraft()), tNoFiles());
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works WHERE user_id = ${me.userId.toString()}"), 1);
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works WHERE user_id = ${them.userId.toString()}"), 0);
    }

    test("post: the intent is kept, trimmed") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("Pasted", "  make them stop  ", tDraft()), tNoFiles());
      let w = worksGetBySlug(db, tSlugOf(r));
      let i = if (w != null) { w.intent } else { null };
      expectText(test, if (i != null) { i } else { "none" }, "make them stop");
    }

    test("post: a blank title becomes Untitled draft") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("   ", "", tDraft()), tNoFiles());
      let w = worksGetBySlug(db, tSlugOf(r));
      expectText(test, if (w != null) { w.title } else { "none" }, "Untitled draft");
    }

    test("post: an empty draft is a 422 that says what to do") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("Nothing", "", "   "), tNoFiles());
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "There&#39;s no text there yet");
      expectHas(test, r.body, "paste a draft or attach a file.");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("post: a form with no fields at all is the same refusal") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tNoParams(), tNoFiles());
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "no text there yet");
    }

    test("post: 120,001 words is refused with the number and the limit") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("Too big", "a test", tRepeat("word ", 120001)), tNoFiles());
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "That&#39;s 120,001 words, and the limit is 120,000 for now. Split it and upload the first part.");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 0);
      expectHas(test, r.body, "value=\"Too big\"");
      expectHas(test, r.body, ">a test</textarea>");
      expectHas(test, r.body, tRepeat("word ", 50));
    }

    test("post: a 422 is the whole page, with the form again") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("Nothing", "", ""), tNoFiles());
      expectHas(test, r.body, "<title");
      expectHas(test, r.body, "action=\"/works/new\"");
      expectHas(test, r.body, "border-l-2 border-[var(--mg-accent)]");
    }

    test("post: a title over 200 characters is refused with the changeset's words") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm(tRepeat("t", 201), "", tDraft()), tNoFiles());
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "Title should be at most 200 character(s).");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("post: a title is written as typed, and escaped when shown back") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("<b>&</b>", "", "   "), tNoFiles());
      expectHas(test, r.body, "value=\"&lt;b&gt;&amp;&lt;/b&gt;\"");
    }

## New: the file

    test("file: its text is the draft and its name is the title") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("", "", ""), tFile("kettle.md", tDraft()));
      expectInt(test, r.status, 303);
      let w = worksGetBySlug(db, tSlugOf(r));
      expectText(test, if (w != null) { w.title } else { "none" }, "kettle");
      expectTrue(test, tCount(db, "SELECT count(*) AS n FROM sections") > 0, "split");
    }

    test("file: a title typed wins over the file's name") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("My title", "", ""), tFile("kettle.md", tDraft()));
      let w = worksGetBySlug(db, tSlugOf(r));
      expectText(test, if (w != null) { w.title } else { "none" }, "My title");
    }

    test("file: the pasted text is ignored when there is a file") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("", "", "pasted words that are not the draft"), tFile("kettle.txt", tDraft()));
      let w = worksGetBySlug(db, tSlugOf(r));
      let body = if (w != null) { w.body } else { "" };
      expectLacks(test, body, "pasted words");
      expectHas(test, body, "more");
    }

    test("file: only the last extension is dropped from the title") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("", "", ""), tFile("chapter.one.markdown", tDraft()));
      let w = worksGetBySlug(db, tSlugOf(r));
      expectText(test, if (w != null) { w.title } else { "none" }, "chapter.one");
    }

    test("file: .txt, .md, .markdown and .text are accepted in any case") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      for (let name of ["a.txt", "b.MD", "c.Markdown", "d.TEXT"]) {
        let r = tPost(db, me, tForm("", "", ""), tFile(name, tDraft()));
        expectInt(test, r.status, 303);
      }
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 4);
    }

    test("file: another kind is refused under the file input") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("", "", ""), tFile("draft.pdf", tDraft()));
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "<p class=\"text-[var(--mg-accent)] text-[0.75rem] mt-1\">Only .txt and .md for now.</p>");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("file: a name that only ends in the letters is not an extension") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("", "", ""), tFile("mdtxt", tDraft()));
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "Only .txt and .md for now.");
    }

    test("file: over eight million bytes is too big") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("", "", ""), tFile("big.txt", tRepeat("a", 8000001)));
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "That file is too big (8MB limit).");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("file: exactly eight million bytes is not too big") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = pwFileProblem(new UploadedFile("manuscript", "edge.txt", "text/plain", tRepeat("a", 8000000)));
      expectTrue(test, r == null, "no problem");
    }

    test("file: an empty file is the empty refusal") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("", "", ""), tFile("empty.txt", "  \n "));
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "no text there yet");
    }

    test("file: a file input left empty is no file, and the pasted text is the draft") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("Pasted", "", tDraft()), tFile("", ""));
      expectInt(test, r.status, 303);
    }

    test("file: a field of another name is not the manuscript") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = tPost(db, me, tForm("Pasted", "", tDraft()), [new UploadedFile("other", "x.pdf", "application/pdf", "zzz")]);
      expectInt(test, r.status, 303);
    }

    test("file: a request the server cut short is too big") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let r = pagesWorksCreate(tPostCtx(db, me, tNoParams(), tNoFiles(), true));
      expectInt(test, r.status, 422);
      expectHas(test, r.body, "That file is too big (8MB limit).");
    }

    test("file: the rootname rules") { test =>
      expectText(test, pwRootname("kettle.md"), "kettle");
      expectText(test, pwRootname("a.b.md"), "a.b");
      expectText(test, pwRootname("plain"), "plain");
      expectText(test, pwRootname(".md"), ".md");
    }

## New: events

A page whose address and prose are served by the fake.

    let tPageHtml(): String {
      "<html><head><title>On kettles</title></head><body><article><h1>On kettles</h1><p>${tRepeat("The kettle sings before it boils and the kitchen listens. ", 12)}</p></article></body></html>"
    }

    let tFakeKettles(): ImporterHttp {
      importerFake([importerRoute("example.com/kettles", 200, tPageHtml())])
    }

    test("fetch: fills the title and the body and says how much it read") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let ctx = tCtx(db, me, "/works/new", true);
      let got = importerFetchPage(tFakeKettles(), "https://example.com/kettles").page;
      expectTrue(test, got != null, "the fake serves the page");
      let words = if (got != null) { wordCount(got.text) } else { -1 };
      let r = pagesWorksFetch(ctx, tFakeKettles(), tObject("{\"url\":\"https://example.com/kettles\"}"));
      expectHas(test, r.body, "Read ${words.toString()} words from example.com. Check it over before uploading.");
      let html = hjoin(renderWorksNew(ctx, loadWorksNew(ctx)));
      expectHas(test, html, "id=\"work_title\" value=\"On kettles\"");
      expectHas(test, html, "The kettle sings before it boils");
      expectHas(test, html, "name=\"url\" value=\"https://example.com/kettles\"");
    }

    test("fetch: the markdown comes with its heading") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      pagesWorksFetch(ctx, tFakeKettles(), tObject("{\"url\":\"https://example.com/kettles\"}"));
      expectHas(test, pwUi(ctx, "works_new:body"), "# On kettles\n\n");
    }

    test("fetch: clears the intent, as the LiveView did") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      tNewEv(ctx, "validate", "{\"work\":{\"title\":\"\",\"intent\":\"keep me\",\"body\":\"\"}}");
      expectText(test, pwUi(ctx, "works_new:intent"), "keep me");
      pagesWorksFetch(ctx, tFakeKettles(), tObject("{\"url\":\"https://example.com/kettles\"}"));
      expectText(test, pwUi(ctx, "works_new:intent"), "");
    }

    test("fetch: an address of spaces does nothing") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      let r = pagesWorksFetch(ctx, tFakeKettles(), tObject("{\"url\":\"   \"}"));
      expectInt(test, r.status, 200);
      expectLacks(test, r.body, "words from");
      expectText(test, pwUi(ctx, "works_new:title"), "");
    }

    test("fetch: the address is trimmed") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      let r = pagesWorksFetch(ctx, tFakeKettles(), tObject("{\"url\":\"  https://example.com/kettles  \"}"));
      expectHas(test, r.body, "words from example.com.");
    }

    let tFetchError(url: String, http: ImporterHttp): String throws Bubble {
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      pagesWorksFetch(ctx, http, tObject("{\"url\":\"${url}\"}")).body
    }

    test("fetch: each way it can fail has its sentence") { test =>
      let fake = importerFake([
        importerRoute("example.com/missing", 404, "no"),
        importerRoute("example.com/broken", 503, "no"),
        importerRoute("example.com/thin", 200, "<html><body><article><p>Too short.</p></article></body></html>"),
        importerRouteFail("example.com/down", "econnrefused"),
      ]);
      expectHas(test, tFetchError("ftp://example.com/x", fake), "That needs to be an http or https address.");
      expectHas(test, tFetchError("http://localhost/x", fake), "That address points at a private network, so it will not be fetched.");
      expectHas(test, tFetchError("http://127.0.0.1/x", fake), "That address points at a private network");
      expectHas(test, tFetchError("https://example.com/missing", fake), "That page was not found.");
      expectHas(test, tFetchError("https://example.com/broken", fake), "That site answered with a 503.");
      expectHas(test, tFetchError("https://example.com/thin", fake), "There was not enough prose on that page to read. A paywall, or a page that builds itself with JavaScript.");
      expectHas(test, tFetchError("https://example.com/down", fake), "That site could not be reached.");
    }

    test("fetch: an address with no site in it") { test =>
      expectHas(test, tFetchError("http:///nothing", importerFake([])), "That address has no site in it.");
    }

    test("fetch: a failure leaves what was typed alone and keeps the address") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      tNewEv(ctx, "validate", "{\"work\":{\"title\":\"Mine\",\"intent\":\"why\",\"body\":\"my words\"}}");
      let r = pagesWorksFetch(ctx, importerFake([]), tObject("{\"url\":\"https://example.com/gone\"}"));
      expectInt(test, r.status, 200);
      expectText(test, pwUi(ctx, "works_new:title"), "Mine");
      expectText(test, pwUi(ctx, "works_new:intent"), "why");
      expectText(test, pwUi(ctx, "works_new:body"), "my words");
      expectText(test, pwUi(ctx, "works_new:url"), "https://example.com/gone");
    }

    test("fetch: an offline address from the real client is refused before any request") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      let r = tNewEv(ctx, "fetch", "{\"url\":\"http://localhost:1/\"}");
      expectHas(test, r.body, "private network");
    }

    test("fetch: the host in the sentence") { test =>
      expectText(test, pwHost("https://example.com/kettles"), "example.com");
      expectText(test, pwHost("http://user@example.com:8080/a?b#c"), "example.com");
      expectText(test, pwHost("https://example.com?x=1"), "example.com");
      expectText(test, pwHost("not a url"), "not a url");
    }

    test("validate: echoes what was typed") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      let r = tNewEv(ctx, "validate", "{\"work[title]\":\"Flat\",\"work[intent]\":\"i\",\"work[body]\":\"b\"}");
      expectInt(test, r.status, 200);
      expectText(test, pwUi(ctx, "works_new:title"), "Flat");
      let html = hjoin(renderWorksNew(ctx, loadWorksNew(ctx)));
      expectHas(test, html, "value=\"Flat\"");
      expectLacks(test, html, "border-l-2");
    }

    test("save: the same rules as the post, as an event, ending in a redirect") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let ctx = tCtx(db, me, "/works/new", true);
      let body = tDraft().split("\n").join("\\n") { (x: String): String => x };
      let r = tNewEv(ctx, "save", "{\"work\":{\"title\":\"By event\",\"intent\":\"\",\"body\":\"${body}\"}}");
      expectHas(test, r.body, "\"redirect\":\"/works/");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works WHERE title = 'By event'"), 1);
    }

    test("save: refuses 120,001 words with the limit") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      let r = tNewEv(ctx, "save", "{\"work\":{\"title\":\"x\",\"body\":\"${tRepeat("word ", 120001)}\"}}");
      expectHas(test, r.body, "and the limit is 120,000 for now");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("save: empty says to paste or attach") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      let r = tNewEv(ctx, "save", "{\"work\":{\"title\":\"x\",\"body\":\"\"}}");
      expectHas(test, r.body, "no text there yet");
    }

    test("save: flat keys work too") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tScope(db, "a@x.test"), "/works/new", true);
      let body = tDraft().split("\n").join("\\n") { (x: String): String => x };
      let r = tNewEv(ctx, "save", "{\"work[title]\":\"Flat\",\"work[body]\":\"${body}\"}");
      expectHas(test, r.body, "\"redirect\"");
      expectInt(test, tCount(db, "SELECT count(*) AS n FROM works WHERE title = 'Flat'"), 1);
    }

    test("a load of /works/new forgets a fetch") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let ctx = tCtx(db, me, "/works/new", true);
      pagesWorksFetch(ctx, tFakeKettles(), tObject("{\"url\":\"https://example.com/kettles\"}"));
      expectTrue(test, pwUi(ctx, "works_new:title") != "", "filled");
      let again = tCtx(db, me, "/works/new", false);
      again.session.ui = ctx.session.ui;
      pagesWorksGet(again, tMatch("GET", "/works/new"));
      expectText(test, pwUi(again, "works_new:title"), "");
      expectText(test, pwUi(again, "works_new:url"), "");
    }

    test("post: a saved draft clears the fetch") { test =>
      let db = dbOpen(":memory:");
      let me = tScope(db, "a@x.test");
      let ctx = tPostCtx(db, me, tForm("Pasted", "", tDraft()), tNoFiles(), false);
      uiPutFor(ctx);
      pagesWorksGet(ctx, tMatch("POST", "/works/new"));
      expectText(test, pwUi(ctx, "works_new:title"), "");
    }

    let uiPutFor(ctx: Ctx): Void {
      uiPut(ctx, "works_new:title", "left over");
    }
