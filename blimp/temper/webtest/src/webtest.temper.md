# Tests for web

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. The database is one `:memory:` handle kept across
the requests of a test (`webRespond` takes it), so a login on one request is
there on the next. Requests are parsed from raw text with `httpParse`.

    let {
      WebGroup, webGroups, webRoutes, webFind, webMethodOf, webRespond, webDispatch, webEarly,
      webPlug, webFailed,
    } = import("web/src");
    let { dbOpen, Db } = import("db/src");
    let { Request, Response, Route, httpParse } = import("http/src");
    let { webNewCtx, webSessionCookieName } = import("webcore/src");
    let { accountsRegisterUser } = import("accounts/src");
    let { urlEncode } = import("http/src");

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

    let tRaw(method: String, path: String, extra: String, body: String): Request {
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${body.split("").length.toString()}\r\n\r\n${body}")
    }

    let tHeader(r: Response, name: String): String {
      let out = new ListBuilder<String>();
      for (var i = 0; i < r.headers.length; ++i) {
        let p = r.headers.getOr(i, new Pair("", ""));
        if (p.key == name) { out.add(p.value); }
      }
      out.toList().join(" | ") { (x: String): String => x }
    }

    let tCount(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

The text between two markers, or "".

    let tBetween(s: String, start: String, end: String): String {
      let after = s.split(start);
      if (after.length > 1) { after.getOr(1, "").split(end).getOr(0, "") } else { "" }
    }

A browser in miniature: a session cookie and the CSRF token of the last page.

    class TBrowser(public var cookie: String, public var csrf: String) {}

    let tNewBrowser(): TBrowser { new TBrowser("", "") }

    let tCookieLine(b: TBrowser): String {
      if (b.cookie != "") { "Cookie: ${webSessionCookieName()}=${b.cookie}\r\n" } else { "" }
    }

The cookie value a response set, if it set one.

    let tLearn(b: TBrowser, r: Response): Void {
      let set = tHeader(r, "Set-Cookie");
      let value = tBetween(set, "${webSessionCookieName()}=", ";");
      if (value != "") { b.cookie = value; }
      let token = tBetween(r.body, "<meta name=\"csrf-token\" content=\"", "\"");
      if (token != "") { b.csrf = token; }
    }

    let tSend(db: Db, b: TBrowser, req: Request): Response throws Bubble {
      let r = webRespond(db, ":memory:", req);
      tLearn(b, r);
      r
    }

    let tGet(db: Db, b: TBrowser, path: String): Response throws Bubble {
      tSend(db, b, tRaw("GET", path, tCookieLine(b), ""))
    }

A form post carrying the token the browser last saw.

    let tPost(db: Db, b: TBrowser, path: String, form: String): Response throws Bubble {
      let body = if (b.csrf != "") { "${form}&_csrf_token=${b.csrf}" } else { form };
      tSend(db, b, tRaw("POST", path, "${tCookieLine(b)}Content-Type: application/x-www-form-urlencoded\r\n", body))
    }

    let tEventRequest(b: TBrowser, name: String, page: String, payload: String): Request {
      let csrf = if (b.csrf != "") { "X-CSRF-Token: ${b.csrf}\r\n" } else { "" };
      tRaw("POST", "/ev/${name}", "${tCookieLine(b)}${csrf}X-Requested-With: blimp\r\nContent-Type: application/json\r\n", "{\"payload\":${payload},\"path\":\"${page}\"}")
    }

    let tEvent(db: Db, b: TBrowser, name: String, page: String, payload: String): Response throws Bubble {
      tSend(db, b, tEventRequest(b, name, page, payload))
    }

    let tLoginForm(email: String, password: String): String {
      "user%5Bemail%5D=${urlEncode(email)}&user%5Bpassword%5D=${urlEncode(password)}"
    }

    let tMakeUser(db: Db, email: String): Void throws Bubble {
      let params = new MapBuilder<String, String>();
      params.set("email", email);
      params.set("password", "hello world!");
      accountsRegisterUser(db, params.toMap());
    }

## Routes

    test("routes: the placeholder is last") { test =>
      let routes = webRoutes();
      let last = routes.getOr(routes.length - 1, new Route("", "", ""));
      expectText(test, last.pattern, "/");
      expectText(test, last.name, "public.home");
    }

    test("routes: pages_users and pages_works are both in") { test =>
      var users = false;
      var works = false;
      for (let r of webRoutes()) {
        if (r.pattern == "/users/settings") { users = true; }
        if (r.pattern == "/works/new" && r.method == "POST") { works = true; }
      }
      expectTrue(test, users, "/users/settings");
      expectTrue(test, works, "POST /works/new");
    }

    test("page: /works is pages_works', and it mints a guest") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("GET", "/works", "", ""));
      expectInt(test, r.status, 200);
      expectHas(test, r.body, "Your drafts");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users"), 1);
    }

    test("routes: webRoutes is the groups' routes in order") { test =>
      var n = 0;
      let groups = webGroups();
      for (var i = 0; i < groups.length; ++i) { n += groups.getOr(i, new WebGroup("", [])).routes.length; }
      expectInt(test, webRoutes().length, n);
      expectText(test, groups.getOr(groups.length - 1, new WebGroup("", [])).id, "web");
    }

    test("routes: every route name starts with a plug prefix") { test =>
      for (let r of webRoutes()) {
        let ok = hasText("|${r.name}", "|public.") || hasText("|${r.name}", "|anyone.") ||
          hasText("|${r.name}", "|guest.") || hasText("|${r.name}", "|real.");
        expectTrue(test, ok, r.name);
      }
    }

    test("routes: no method and pattern twice") { test =>
      let seen = new ListBuilder<String>();
      for (let r of webRoutes()) {
        let key = "${r.method} ${r.pattern}";
        var dup = false;
        for (let s of seen.toList()) { if (s == key) { dup = true; } }
        expectTrue(test, !dup, key);
        seen.add(key);
      }
    }

    test("routes: webFind names the group") { test =>
      let users = webFind("GET", "/users/log-in");
      expectTrue(test, users != null, "found");
      expectText(test, if (users != null) { users.group } else { "?" }, "pages_users");
      let home = webFind("GET", "/");
      expectText(test, if (home != null) { home.group } else { "?" }, "web");
      expectTrue(test, webFind("GET", "/nothing/here") == null, "unknown");
      expectTrue(test, webFind("PUT", "/users/log-in") == null, "wrong method");
    }

    test("routes: a captured segment arrives as a param") { test =>
      let m = webFind("GET", "/users/settings/confirm-email/abc123");
      expectText(test, if (m != null) { m.match.params.getOr("token", "?") } else { "?" }, "abc123");
    }

    test("method override: a POST with _method=delete is a DELETE") { test =>
      let req = tRaw("POST", "/users/log-out", "Content-Type: application/x-www-form-urlencoded\r\n", "_method=delete");
      expectText(test, webMethodOf(req), "DELETE");
      let up = tRaw("POST", "/x", "Content-Type: application/x-www-form-urlencoded\r\n", "_method=PUT");
      expectText(test, webMethodOf(up), "PUT");
    }

    test("method override: anything else stays what it was") { test =>
      let odd = tRaw("POST", "/x", "Content-Type: application/x-www-form-urlencoded\r\n", "_method=get");
      expectText(test, webMethodOf(odd), "POST");
      expectText(test, webMethodOf(tRaw("GET", "/x?_method=delete", "", "")), "GET");
      expectText(test, webMethodOf(tRaw("POST", "/x", "", "")), "POST");
    }

## Pages

    test("page: the placeholder home") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("GET", "/", "", ""));
      expectInt(test, r.status, 200);
      expectHas(test, r.body, "Marginalia");
      expectHas(test, r.body, "<header class=\"mg-bar\">");
      expectHas(test, r.body, "id=\"flash-group\"");
    }

    test("page: a route group's page is served, with a session cookie") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("GET", "/users/log-in", "", ""));
      expectInt(test, r.status, 200);
      expectHas(test, r.body, "id=\"login_form_password\"");
      expectHas(test, tHeader(r, "Set-Cookie"), "${webSessionCookieName()}=");
    }

    test("404: an unknown path is the not-found page, no session") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("GET", "/no/such/page", "", ""));
      expectInt(test, r.status, 404);
      expectHas(test, r.body, "Nothing at that address");
      expectText(test, tHeader(r, "Set-Cookie"), "");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM sessions"), 0);
    }

    test("404: a known path with the wrong method") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("PUT", "/users/log-in", "", ""));
      expectInt(test, r.status, 404);
    }

    test("404: an event for a page nobody owns") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let r = tEvent(db, b, "validate", "/no/such/page", "{}");
      expectInt(test, r.status, 404);
    }

    test("early: healthz needs no database") { test =>
      let r = webDispatch("/nonexistent-dir/never.sqlite3", tRaw("GET", "/healthz", "", ""));
      expectInt(test, r.status, 200);
      expectText(test, r.body, "ok");
    }

    test("early: the sitemap is not early any more, it lists the database's pages") { test =>
      let r = webDispatch("/nonexistent-dir/never.sqlite3", tRaw("GET", "/sitemap.xml", "", ""));
      expectInt(test, r.status, 500);
    }

    test("early: a static-looking path that is not there is a 404 before the database") { test =>
      let r = webDispatch("/nonexistent-dir/never.sqlite3", tRaw("GET", "/assets/css/not-there.css", "", ""));
      expectInt(test, r.status, 404);
    }

    test("early: only a GET is served statically") { test =>
      expectTrue(test, webEarly(tRaw("POST", "/healthz", "", "")) == null, "post");
      expectTrue(test, webEarly(tRaw("GET", "/users/log-in", "", "")) == null, "not early");
    }

## Plugs

    test("plug: public. and anyone. do nothing, and mint no guest") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      expectInt(test, tGet(db, b, "/").status, 200);
      expectInt(test, tGet(db, b, "/users/log-in").status, 200);
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users"), 0);
    }

    test("plug: real. sends a visitor to log in") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      let r = tGet(db, b, "/users/settings");
      expectInt(test, r.status, 303);
      expectText(test, tHeader(r, "Location"), "/users/log-in");
      expectHas(test, tGet(db, b, "/users/log-in").body, "You must log in to access this page.");
    }

    test("plug: real. sends a guest to register") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let id = db.insert("INSERT INTO users (email, hashed_password, confirmed_at, is_guest) VALUES ('guest-y@guest.marginalia.local', 'x', '2020-01-01 00:00:00', 1)", []);
      let tokenId = db.insert("INSERT INTO users_tokens (user_id, token, context, authenticated_at) VALUES ($1, 'tok2', 'session', datetime('now'))", [id.toString()]);
      db.exec("UPDATE sessions SET user_token_id = $1 WHERE id = $2", [tokenId.toString(), b.cookie]);
      let r = tGet(db, b, "/users/settings");
      expectInt(test, r.status, 303);
      expectText(test, tHeader(r, "Location"), "/users/register");
    }

    test("plug: guest. mints a guest and keeps the CSRF token") { test =>
      let db = dbOpen(":memory:");
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", "/", "", ""), new MapBuilder<String, String>().toMap());
      let before = ctx.session.csrf;
      let stopped = webPlug(ctx, "guest.anything");
      expectTrue(test, stopped == null, "carries on");
      let user = ctx.scope.user;
      expectTrue(test, user != null, "a user");
      expectTrue(test, if (user != null) { user.isGuest } else { false }, "a guest");
      expectText(test, ctx.session.csrf, before);
    }

    test("plug: an unknown prefix stops the request") { test =>
      let db = dbOpen(":memory:");
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", "/", "", ""), new MapBuilder<String, String>().toMap());
      let failed = do { webPlug(ctx, "oops.page"); false } orelse true;
      expectTrue(test, failed, "bubbled");
    }

    test("plug: public. and anyone. return nothing") { test =>
      let db = dbOpen(":memory:");
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", "/", "", ""), new MapBuilder<String, String>().toMap());
      expectTrue(test, webPlug(ctx, "public.home") == null, "public");
      expectTrue(test, webPlug(ctx, "anyone.users_login") == null, "anyone");
    }

## CSRF

    test("csrf: a POST with no token is a 403, and nothing happens") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "c@example.com");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let r = tSend(db, b, tRaw("POST", "/users/log-in", "${tCookieLine(b)}Content-Type: application/x-www-form-urlencoded\r\n", tLoginForm("c@example.com", "hello world!")));
      expectInt(test, r.status, 403);
      expectText(test, r.body, "invalid CSRF token");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens"), 0);
    }

    test("csrf: a wrong token is a 403") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let r = tSend(db, b, tRaw("POST", "/users/log-in", "${tCookieLine(b)}Content-Type: application/x-www-form-urlencoded\r\n", "${tLoginForm("c@example.com", "x")}&_csrf_token=wrong"));
      expectInt(test, r.status, 403);
    }

    test("csrf: a POST with no session at all is a 403") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("POST", "/users/log-in", "Content-Type: application/x-www-form-urlencoded\r\n", "${tLoginForm("c@example.com", "x")}&_csrf_token=guess"));
      expectInt(test, r.status, 403);
    }

    test("csrf: the token in the form lets the POST through") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "d@example.com");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let r = tPost(db, b, "/users/log-in", tLoginForm("d@example.com", "hello world!"));
      expectInt(test, r.status, 303);
      expectText(test, tHeader(r, "Location"), "/");
    }

    test("csrf: an event needs the header token") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      tGet(db, b, "/users/register");
      let good = tEvent(db, b, "validate", "/users/register", "{\"user\":{\"email\":\"with spaces\"}}");
      expectInt(test, good.status, 200);
      b.csrf = "";
      let bad = tEvent(db, b, "validate", "/users/register", "{\"user\":{\"email\":\"with spaces\"}}");
      expectInt(test, bad.status, 403);
    }

    test("csrf: a DELETE is checked, a GET is not") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("DELETE", "/users/log-out", "", ""));
      expectInt(test, r.status, 403);
    }

    test("csrf: log-out through a form with _method=delete") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "e@example.com");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      tPost(db, b, "/users/log-in", tLoginForm("e@example.com", "hello world!"));
      tGet(db, b, "/users/settings");
      let r = tPost(db, b, "/users/log-out", "_method=delete");
      expectInt(test, r.status, 303);
      expectText(test, tHeader(r, "Location"), "/");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens"), 0);
    }

## Events

    test("event: validate on the registration page answers with the region") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      tGet(db, b, "/users/register");
      let r = tEvent(db, b, "validate", "/users/register", "{\"user\":{\"email\":\"with spaces\"}}");
      expectInt(test, r.status, 200);
      expectHas(test, tHeader(r, "Content-Type"), "application/json");
      expectHas(test, r.body, "\"regions\":{\"#main\":");
      expectHas(test, r.body, "must have the @ sign and no spaces");
    }

    test("event: the page's plug runs, so a visitor's settings event is a redirect") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let r = tEvent(db, b, "validate_email", "/users/settings", "{\"user\":{\"email\":\"x\"}}");
      expectInt(test, r.status, 200);
      expectHas(test, r.body, "\"redirect\":\"/users/log-in\"");
    }

    test("event: the page's query string is passed on") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let r = tEvent(db, b, "validate", "/users/register?x=1", "{\"user\":{\"email\":\"with spaces\"}}");
      expectInt(test, r.status, 200);
      expectHas(test, r.body, "must have the @ sign");
    }

    test("event: a body that is not JSON is a 400") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("POST", "/ev/validate", "Content-Type: application/json\r\n", "not json"));
      expectInt(test, r.status, 400);
    }

    test("event: a body that is JSON but not an object is a 400") { test =>
      let db = dbOpen(":memory:");
      let r = webRespond(db, ":memory:", tRaw("POST", "/ev/validate", "Content-Type: application/json\r\n", "[1,2]"));
      expectInt(test, r.status, 400);
    }

    test("event: a GET of /ev/ is just an unknown path") { test =>
      let db = dbOpen(":memory:");
      expectInt(test, webRespond(db, ":memory:", tRaw("GET", "/ev/validate", "", "")).status, 404);
    }

    test("event: an event its page does not have is a bubble, which webFailed turns into the 500 page") { test =>
      let db = dbOpen(":memory:");
      let b = tNewBrowser();
      tGet(db, b, "/users/register");
      let req = tEventRequest(b, "nope", "/users/register", "{}");
      let failed = do { webRespond(db, ":memory:", req); false } orelse true;
      expectTrue(test, failed, "bubbled");
      let page = webFailed(db, ":memory:", req);
      expectInt(test, page.status, 500);
      expectHas(test, page.body, "Something broke");
    }

## A visit from start to finish

    test("flow: log in, see the menu, log out, see the flash") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "flow@example.com");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let login = tPost(db, b, "/users/log-in", tLoginForm("flow@example.com", "hello world!"));
      expectInt(test, login.status, 303);
      let home = tGet(db, b, "/");
      expectHas(test, home.body, "Welcome back!");
      expectHas(test, home.body, "flow@example.com");
      expectHas(test, home.body, "action=\"/users/log-out\"");
      let out = tPost(db, b, "/users/log-out", "_method=delete");
      expectText(test, tHeader(out, "Location"), "/");
      let after = tGet(db, b, "/");
      expectHas(test, after.body, "Logged out successfully.");
      expectLacks(test, after.body, "flow@example.com");
    }

    test("flow: a bad password, then the form with the flash and the address") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "bad@example.com");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      let r = tPost(db, b, "/users/log-in", tLoginForm("bad@example.com", "nope nope nope"));
      expectText(test, tHeader(r, "Location"), "/users/log-in");
      let page = tGet(db, b, "/users/log-in");
      expectHas(test, page.body, "Invalid email or password");
      expectHas(test, page.body, "value=\"bad@example.com\"");
    }

    test("flow: the settings page after a login, and the event from it") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "set@example.com");
      let b = tNewBrowser();
      tGet(db, b, "/users/log-in");
      tPost(db, b, "/users/log-in", tLoginForm("set@example.com", "hello world!"));
      let page = tGet(db, b, "/users/settings");
      expectInt(test, page.status, 200);
      expectHas(test, page.body, "Change Email");
      let ev = tEvent(db, b, "validate_password", "/users/settings", "{\"user\":{\"password\":\"short\",\"password_confirmation\":\"x\"}}");
      expectHas(test, ev.body, "should be at least 12 character(s)");
      expectHas(test, ev.body, "does not match password");
    }

    test("flow: the return-to survives the redirect to log in") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "ret@example.com");
      let b = tNewBrowser();
      let denied = tGet(db, b, "/users/settings");
      expectText(test, tHeader(denied, "Location"), "/users/log-in");
      tGet(db, b, "/users/log-in");
      let r = tPost(db, b, "/users/log-in", tLoginForm("ret@example.com", "hello world!"));
      expectText(test, tHeader(r, "Location"), "/users/settings");
    }
