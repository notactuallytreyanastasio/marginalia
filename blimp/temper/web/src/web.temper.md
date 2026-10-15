# The router

A request is answered in this order, and the order is the contract:

1. A static file (`/assets/...`, `/images/...`, `favicon.ico`, `robots.txt`)
   if the path is one: no database, no session.
2. `/healthz` and a placeholder `/sitemap.xml`: no database either.
3. The database is opened. (A fresh child per request: see `webDispatch`.)
4. The route is matched, group by group in Phoenix router order. A `POST` with
   `_method=delete` (or `put`, `patch`) is matched as that method, as
   `Plug.MethodOverride` did. Nothing matches: the 404 page.
5. The session is loaded, and every write (`POST`, `PUT`, `PATCH`, `DELETE`,
   and every event) must carry the session's CSRF token: a 403 otherwise.
6. The current scope is mounted (`fetch_current_scope_for_user`).
7. The group's plug, named by the route-name prefix: `public.` and `anyone.`
   nothing more, `guest.` `ensure_user_or_guest`, `real.` `require_real_account`.
   A plug may answer instead of the page (a redirect).
8. The group answers: its `Get` for a route, its `Event` for `POST /ev/<name>`.

A bubble anywhere after the database is open becomes the 500 page and a line
in `log/error.log`. The Temper bubble carries no text; the line says so.

    let { Request, Response, Route, Match, httpStatic, httpHtml, httpText, routeMatch, queryParse, urlDecode } = import("http/src");
    let { Db, dbOpen } = import("db/src");
    let {
      Ctx, webNewCtx, webNewSession, webMountCurrentScope, webEnsureUserOrGuest, webRequireRealAccount,
      webCheckCsrf, webNotFound, webServerError, webErrorDocument, webMeta, webPage, webPruneSessions,
    } = import("webcore/src");
    let { noScope } = import("accounts/src");
    let {
      sysGetEnv, sysFileSize, sysExec, sysAppendFile, sysUtcNow, sysUtf8Upcase, sysFork, sysWaitPid, sysExit,
    } = import("sys/src");
    let { h, htext, attr } = import("html/src");
    let { JsonObject, JsonString, JsonSyntaxTree, parseJson } = import("std/json");
    let { pagesUsersRoutes, pagesUsersGet, pagesUsersEvent } = import("pages_users/src");
    let { pagesWorksRoutes, pagesWorksGet, pagesWorksEvent } = import("pages_works/src");
    let { pagesCutsRoutes, pagesCutsGet, pagesCutsEvent } = import("pages_cuts/src");
    let { pagesStacksRoutes, pagesStacksGet, pagesStacksEvent } = import("pages_stacks/src");
    let { recoveryRun } = import("runs/src");
    let { portFromEnv } = import("server/src");

Every top-level name here is shared by the library's files and, in the built
program, with every other library's: the private helpers start with `wr`.

## Page groups

A group is its routes. The router matches the groups one after another, in the
order below, and the first group with a match owns the request; inside a group
the first route wins. That is `Phoenix.Router`'s first match, as long as no
two groups claim the same path, which none does (`/works/new` and
`/works/:id` are both `pages_works`, in that order).

    export class WebGroup(public id: String, public routes: List<Route>) {}

The groups, in Phoenix router order. To add one: append a line here, and add
its `id` to `wrGroupGet` and `wrGroupEvent` below. `pages_public` goes first
(`/`, `/cases`, `/drafts`... come before the guest scope in `router.ex`), then
the guest scope's groups, then `pages_users`; the `web` placeholders stay last
so a real `/` wins over the placeholder.

    export let webGroups(): List<WebGroup> {
      [
        // ---- Added as the page libraries land. ---------------------------------
        // pages_public  /, /cases, /drafts, /linked, /reading, /sitemap.xml
        // pages_works   POST /works/new, /works/:id/graph.json, /works, /works/new, /works/:id
        // pages_show    /works/:id and its views (if split from pages_works)
        // pages_import  /import
        // pages_stacks  /stacks, /stacks/new, /stacks/:id, /stacks/:id/story, /stacks/:id/:ordinal
        // pages_cuts    /cuts, /cuts/:id
        // pages_links   /links, /links/:id, /links/:id/read
        // -----------------------------------------------------------------------
        new WebGroup("pages_stacks", pagesStacksRoutes()),
        new WebGroup("pages_cuts", pagesCutsRoutes()),
        new WebGroup("pages_works", pagesWorksRoutes()),
        new WebGroup("pages_users", pagesUsersRoutes()),
        // The placeholders for pages whose group has not landed. Keep last.
        new WebGroup("web", wrPlaceholderRoutes()),
      ]
    }

Every route of every group, in match order.

    export let webRoutes(): List<Route> {
      let out = new ListBuilder<Route>();
      let groups = webGroups();
      for (var i = 0; i < groups.length; ++i) {
        let routes = groups.getOr(i, new WebGroup("", [])).routes;
        for (var j = 0; j < routes.length; ++j) {
          out.add(routes.getOr(j, new Route("", "", "")));
        }
      }
      out.toList()
    }

### The placeholder group

`/` until `pages_public` lands: the app layout and the word Marginalia.

    let wrPlaceholderRoutes(): List<Route> {
      [
        new Route("GET", "/", "public.home"),
      ]
    }

    let wrPlaceholderPage(ctx: Ctx, heading: String): Response throws Bubble {
      webPage(
        ctx, webMeta(null),
        h("div", attr("class", "mx-auto max-w-sm px-6 py-16"), h("h1", attr("class", "text-2xl font-semibold"), htext(heading))),
        null, "app",
      )
    }

    let wrPlaceholderGet(ctx: Ctx, match: Match): Response throws Bubble {
      if (match.route.name == "public.home") {
        wrPlaceholderPage(ctx, "Marginalia")
      } else {
        console.log("web: no handler for route ${match.route.name}");
        bubble()
      }
    }

### Handing a request to its group

    let wrGroupGet(id: String, ctx: Ctx, match: Match): Response throws Bubble {
      if (id == "pages_stacks") {
        pagesStacksGet(ctx, match)
      } else if (id == "pages_cuts") {
        pagesCutsGet(ctx, match)
      } else if (id == "pages_works") {
        pagesWorksGet(ctx, match)
      } else if (id == "pages_users") {
        pagesUsersGet(ctx, match)
      } else if (id == "web") {
        wrPlaceholderGet(ctx, match)
      } else {
        console.log("web: unknown group ${id}");
        bubble()
      }
    }

    let wrGroupEvent(id: String, ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      if (id == "pages_stacks") {
        pagesStacksEvent(ctx, match, event, payload)
      } else if (id == "pages_cuts") {
        pagesCutsEvent(ctx, match, event, payload)
      } else if (id == "pages_works") {
        pagesWorksEvent(ctx, match, event, payload)
      } else if (id == "pages_users") {
        pagesUsersEvent(ctx, match, event, payload)
      } else {
        console.log("web: group ${id} has no events (${event})");
        bubble()
      }
    }

## Matching

A route and the group that owns it.

    export class WebOwner(public group: String, public match: Match) {}

    export let webFind(method: String, path: String): WebOwner? {
      let groups = webGroups();
      var i = 0;
      while (i < groups.length) {
        let g = groups.getOr(i, new WebGroup("", []));
        let m = routeMatch(g.routes, method, path);
        if (m != null) { return new WebOwner(g.id, m); }
        i += 1;
      }
      null
    }

`Plug.MethodOverride`: a `POST` carrying `_method` = `delete`, `put` or `patch`
is that method for routing. The request itself stays a `POST` (the CSRF check
and the session see what the browser sent).

    export let webMethodOf(req: Request): String {
      if (req.method == "POST") {
        let m = sysUtf8Upcase(req.form.getOr("_method", ""));
        if (m == "DELETE" || m == "PUT" || m == "PATCH") { m } else { "POST" }
      } else { req.method }
    }

    let wrStartsWith(s: String, prefix: String): Boolean {
      if (s == "" || prefix == "") { return false; }
      let parts = s.split(prefix);
      parts.length > 1 && parts.getOr(0, "x") == ""
    }

## The plugs

The Phoenix pipelines, chosen by the route name's prefix. Anything else is a
bug in a page library and stops the request with the name in the log.

    export let webPlug(ctx: Ctx, routeName: String): Response? throws Bubble {
      if (wrStartsWith(routeName, "public.") || wrStartsWith(routeName, "anyone.")) {
        null
      } else if (wrStartsWith(routeName, "guest.")) {
        webEnsureUserOrGuest(ctx)
      } else if (wrStartsWith(routeName, "real.")) {
        webRequireRealAccount(ctx)
      } else {
        console.log("web: route ${routeName} has no plug prefix (public. anyone. guest. real.)");
        bubble()
      }
    }

## One request, database open

    let wrNoParams(): Map<String, String> {
      new MapBuilder<String, String>().toMap()
    }

A context for an answer that needs none of the session (the error pages).

    let wrBareCtx(db: Db, dbPath: String, req: Request): Ctx {
      new Ctx(db, dbPath, req, noScope(), webNewSession(), wrNoParams(), sysUtcNow(), false)
    }

The part of an event's `path` before the `?`, decoded, and the query after it.

    let wrPagePath(full: String): String {
      urlDecodePath(full.split("?").getOr(0, full))
    }

    let wrPageQuery(full: String): Map<String, String> {
      let parts = full.split("?");
      if (parts.length > 1) { queryParse(parts.getOr(1, "")) } else { wrNoParams() }
    }

`+` stays a plus in a path; `urlDecode` is for forms.

    let urlDecodePath(p: String): String {
      urlDecode(p.split("+").join("%2B") { (x: String): String => x })
    }

    let wrEmptyObject(): JsonObject throws Bubble {
      let t: JsonSyntaxTree = parseJson("{}");
      if (t is JsonObject) { t } else { bubble() }
    }

An ordinary request: a page, or a controller action.

    let wrRoute(db: Db, dbPath: String, req: Request): Response throws Bubble {
      let owner = webFind(webMethodOf(req), req.path);
      if (owner != null) {
        let match = owner.match;
        let ctx = webNewCtx(db, dbPath, req, match.params);
        let denied = webCheckCsrf(ctx);
        if (denied != null) { return denied; }
        webMountCurrentScope(ctx);
        let stopped = webPlug(ctx, match.route.name);
        if (stopped != null) { return stopped; }
        wrGroupGet(owner.group, ctx, match)
      } else {
        webNotFound(wrBareCtx(db, dbPath, req))
      }
    }

An event, `POST /ev/<name>`: `{"payload": {...}, "path": "/users/settings?x=1"}`.
The page's path (a `GET`) finds the group; the context is that of the page, a
copy of the request whose path and query are the page's, so the plug, the
current path and the page's own handlers see the page and not `/ev/`.

    let wrEvent(db: Db, dbPath: String, req: Request, event: String): Response throws Bubble {
      let tree: JsonSyntaxTree? = parseJson(req.body) orelse null;
      if (!(tree is JsonObject)) { return httpText(400, "Bad Request"); }
      var pageFull = "/";
      var payload: JsonObject = wrEmptyObject();
      if (tree is JsonObject) {
        let p = tree.propertyValueOrNull("path");
        if (p is JsonString) { pageFull = p.content; }
        let body = tree.propertyValueOrNull("payload");
        if (body is JsonObject) { payload = body; }
      }
      let pagePath = wrPagePath(pageFull);
      let owner = webFind("GET", pagePath);
      if (owner != null) {
        let pageReq = new Request(
          req.method, pagePath, wrPageQuery(pageFull), req.headers, req.cookies,
          req.body, req.form, req.files, req.truncated,
        );
        let match = owner.match;
        let ctx = webNewCtx(db, dbPath, pageReq, match.params);
        let denied = webCheckCsrf(ctx);
        if (denied != null) { return denied; }
        webMountCurrentScope(ctx);
        let stopped = webPlug(ctx, match.route.name);
        if (stopped != null) { return stopped; }
        wrGroupEvent(owner.group, ctx, match, event, payload)
      } else {
        webNotFound(wrBareCtx(db, dbPath, req))
      }
    }

`/ev/<name>`: the name, or null when the path is not an event.

    let wrEventName(req: Request): String? {
      if (req.method == "POST" && wrStartsWith(req.path, "/ev/")) {
        let evName = req.path.split("/ev/").getOr(1, "");
        if (evName != "") { evName } else { null }
      } else { null }
    }

Routes and events, with the database already open. Exported for the tests,
which keep one in-memory database across requests.

    export let webRespond(db: Db, dbPath: String, req: Request): Response throws Bubble {
      let event = wrEventName(req);
      if (event != null) { wrEvent(db, dbPath, req, event) } else { wrRoute(db, dbPath, req) }
    }

The 500 page, for a database that is open.

    export let webFailed(db: Db, dbPath: String, req: Request): Response {
      webServerError(wrBareCtx(db, dbPath, req))
    }

## Before the database

`STATIC_ROOT`, default `static`; when it is unset and there is no `static/`
here, `blimp/static`, which is where it is when the server is started from the
repository root (the end-to-end script does that).

    let wrStaticRoot(): String {
      let raw = sysGetEnv("STATIC_ROOT");
      if (raw != null) {
        raw
      } else if (sysFileSize("static/robots.txt") >= 0) {
        "static"
      } else {
        "blimp/static"
      }
    }

A static file for a `GET`, `/healthz`, the placeholder sitemap; null for
anything else.

    export let webEarly(req: Request): Response? {
      if (req.method != "GET") { return null; }
      let asset = httpStatic(wrStaticRoot(), req.path);
      if (asset != null) { return asset; }
      if (req.path == "/healthz") {
        httpText(200, "ok")
      } else if (req.path == "/sitemap.xml") {
        new Response(200, [new Pair("Content-Type", "application/xml; charset=utf-8")], "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\"></urlset>")
      } else {
        null
      }
    }

## The error log

    let wrLogDir(): String {
      let raw = sysGetEnv("LOG_DIR");
      if (raw != null) { raw } else { "log" }
    }

    let wrLogError(req: Request, what: String): Void {
      let logged = do {
        sysExec(["mkdir", "-p", wrLogDir()], "", null);
        sysAppendFile("${wrLogDir()}/error.log", "${sysUtcNow()} ${req.method} ${req.path} ${what}\n");
        true
      } orelse false;
      if (!logged) { console.log("marginalia: could not write ${wrLogDir()}/error.log: ${what}"); }
    }

## One request

The server forks a child for each request and the child calls this once, so
the database is opened here, per request: SQLite and `fork` do not mix, and a
connection the parent held would be shared with every child. `dbOpen` also
migrates (a `schema_migrations` check).

A bubble after the database is open is the 500 page and a line in the error
log. A database that will not open is the same page without a context.

    let wrServeOpen(db: Db, dbPath: String, req: Request): Response {
      var out: Response? = null;
      let fine = do { out = webRespond(db, dbPath, req); true } orelse false;
      let r = out;
      if (r != null) {
        r
      } else {
        wrLogError(req, "Bubble");
        webFailed(db, dbPath, req)
      }
    }

    export let webDispatch(dbPath: String, req: Request): Response throws Bubble {
      let early = webEarly(req);
      if (early != null) { return early; }
      var opened: Db? = null;
      let ok = do { opened = dbOpen(dbPath); true } orelse false;
      let db = opened;
      if (db != null) {
        wrServeOpen(db, dbPath, req)
      } else {
        wrLogError(req, "cannot open ${dbPath}");
        httpHtml(500, webErrorDocument(
          "Something broke",
          "That is this end, not yours, and it has been logged. Trying again in a moment is worth doing — most of what breaks here is transient.",
        ))
      }
    }

## The handler and boot

`MARGINALIA_DB`, default `out/dev.sqlite3`.

    export let webDbPath(): String {
      let raw = sysGetEnv("MARGINALIA_DB");
      if (raw != null) { raw } else { "out/dev.sqlite3" }
    }

What `serve` is given.

    export let webHandler(req: Request): Response throws Bubble {
      webDispatch(webDbPath(), req)
    }

Once, before the server listens: the sweep that marks the work a restart
interrupted, and the old anonymous sessions gone (30 days). It runs in a forked
child that the parent waits for, so the parent never touches SQLite. Opening
and closing a database in the parent made the first request's `sqlite3_open_v2`
segfault in the child it forked (found by running it; open and close inside one
process is fine).

    let wrSweep(path: String): Void {
      let ok = do {
        let db = dbOpen(path);
        let recovered = recoveryRun(db);
        let pruned = webPruneSessions(db, 30);
        console.log("marginalia: ${recovered.toString()} interrupted rows marked, ${pruned.toString()} old sessions pruned");
        db.close();
        true
      } orelse false;
      if (!ok) { console.log("marginalia: the start-up sweep failed; requests will report the database"); }
    }

    export let webBoot(): Void {
      let path = webDbPath();
      console.log("marginalia: starting on port ${portFromEnv().toString()}, database ${path}");
      let pid = sysFork();
      if (pid == 0) {
        wrSweep(path);
        sysExit(0);
      } else {
        sysWaitPid(pid, false);
      }
    }
