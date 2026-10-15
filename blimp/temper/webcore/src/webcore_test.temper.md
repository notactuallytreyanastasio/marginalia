# Tests for webcore

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse`, the way the server sees
them. Guests are inserted by SQL in most tests, because `accountsCreateGuest`
pays for the real 600,000 PBKDF2 iterations; the two tests that go through it
(`webEnsureUserOrGuest`) say so.

    let { dbOpen, Db } = import("db/src");
    let { Request, Response, httpParse } = import("http/src");
    let { User, Scope, scopeFor, noScope } = import("accounts/src");
    let { accountsGetUser, accountsGetUserBySessionToken, accountsGenerateUserSessionToken } = import("accounts/src");
    let { sysUtcNow, sysRandomHex } = import("sys/src");
    let { hjoin, h, htext } = import("html/src");
    let { JsonObject, JsonString, JsonSyntaxTree, parseJson } = import("std/json");

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

## Fixtures

    let noParams(): Map<String, String> {
      new MapBuilder<String, String>().toMap()
    }

    let tRaw(method: String, path: String, extra: String, body: String): Request {
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${body.split("").length.toString()}\r\n\r\n${body}")
    }

    let tGet(path: String): Request { tRaw("GET", path, "", "") }

    let tCookie(name: String, value: String): String { "Cookie: ${name}=${value}\r\n" }

    let tCtx(db: Db, req: Request): Ctx throws Bubble {
      webNewCtx(db, ":memory:", req, noParams())
    }

    let tCtxGet(db: Db, path: String): Ctx throws Bubble { tCtx(db, tGet(path)) }

The header's value, or "" when absent. Every header of that name, joined with
` | `, since a response can set two cookies.

    let tHeaders(r: Response, name: String): String {
      let want = name;
      let out = new ListBuilder<String>();
      for (var i = 0; i < r.headers.length; ++i) {
        let p = r.headers.getOr(i, new Pair("", ""));
        if (p.key == want) { out.add(p.value); }
      }
      out.toList().join(" | ") { (x: String): String => x }
    }

    let tUser(db: Db, email: String, guest: Boolean): User throws Bubble {
      let id = db.insert(
        "INSERT INTO users (email, hashed_password, confirmed_at, is_guest) VALUES ($1, 'x', $2, $3)",
        [email, sysUtcNow(), if (guest) { "1" } else { "0" }],
      );
      accountsGetUser(db, id)
    }

    let tRealUser(db: Db): User throws Bubble {
      tUser(db, "u${sysRandomHex(5)}@example.com", false)
    }

    let tGuestUser(db: Db): User throws Bubble {
      tUser(db, "guest-${sysRandomHex(5)}@guest.marginalia.local", true)
    }

A request with the cookie of the session `ctx` just saved.

    let tNextCtx(db: Db, ctx: Ctx, path: String): Ctx throws Bubble {
      tCtx(db, tRaw("GET", path, tCookie(webSessionCookieName(), ctx.session.id), ""))
    }

    let tNextPost(db: Db, ctx: Ctx, path: String, extra: String, body: String): Ctx throws Bubble {
      tCtx(db, tRaw("POST", path, "${tCookie(webSessionCookieName(), ctx.session.id)}${extra}", body))
    }

    let tJsonField(body: String, key: String): JsonSyntaxTree? throws Bubble {
      let tree: JsonSyntaxTree = parseJson(body);
      if (tree is JsonObject) { tree.propertyValueOrNull(key) } else { null }
    }

    let tJsonString(body: String, key: String): String throws Bubble {
      let v = tJsonField(body, key);
      if (v is JsonString) { v.content } else { "<not a string>" }
    }

    let tCount(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

## Sessions

    test("session: a request with no cookie gets a new session") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      expectTrue(test, ctx.session.isNew, "new");
      expectTrue(test, ctx.session.id != "", "an id");
      expectTrue(test, ctx.session.csrf != "", "a csrf token");
      expectTrue(test, ctx.session.id != ctx.session.csrf, "id and csrf differ");
    }

    test("session: the cookie value is an unguessable token, not the csrf token") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      let b = tCtxGet(db, "/");
      expectTrue(test, a.session.id != b.session.id, "two visitors, two ids");
      expectTrue(test, a.session.csrf != b.session.csrf, "two visitors, two tokens");
    }

    test("session: nothing is stored until it is saved") { test =>
      let db = dbOpen(":memory:");
      tCtxGet(db, "/");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM sessions"), 0);
    }

    test("session: save then load through the cookie returns the same session") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      uiPut(a, "page:key", "value");
      webPutFlash(a, "info", "hello");
      webSaveSession(db, a.session);
      let b = tNextCtx(db, a, "/");
      expectFalse(test, b.session.isNew, "not new");
      expectText(test, b.session.id, a.session.id);
      expectText(test, b.session.csrf, a.session.csrf);
      expectText(test, wcOr(uiGet(b, "page:key"), "<none>"), "value");
      expectText(test, b.session.flash.getOr("info", ""), "hello");
    }

    test("session: an unknown cookie value starts a new session and is not adopted") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("GET", "/", tCookie(webSessionCookieName(), "planted"), ""));
      expectTrue(test, ctx.session.isNew, "new");
      expectTrue(test, ctx.session.id != "planted", "the planted id is not used");
    }

    test("session: webFinish sets the cookie of a new session, with the flags the endpoint had") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      let r = webFinish(ctx, httpHtmlOk());
      expectText(test, tHeaders(r, "Set-Cookie"), "_marginalia_key=${ctx.session.id}; Path=/; HttpOnly; SameSite=Lax");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM sessions"), 1);
    }

    test("session: the cookie has no Max-Age (a browser-session cookie)") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      let r = webFinish(ctx, httpHtmlOk());
      expectLacks(test, tHeaders(r, "Set-Cookie"), "Max-Age");
    }

    test("session: a returning visitor is not sent the cookie again") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      webFinish(a, httpHtmlOk());
      let b = tNextCtx(db, a, "/");
      let r = webFinish(b, httpHtmlOk());
      expectText(test, tHeaders(r, "Set-Cookie"), "");
    }

    test("session: an unchanged returning session is not rewritten") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      webFinish(a, httpHtmlOk());
      db.exec("UPDATE sessions SET updated_at = '2000-01-01 00:00:00'", []);
      let b = tNextCtx(db, a, "/");
      webFinish(b, httpHtmlOk());
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM sessions WHERE updated_at = '2000-01-01 00:00:00'"), 1);
    }

    test("session: the data column is a JSON object with csrf, flash, ui, remember") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      uiPut(ctx, "k", "v");
      let data = webSessionData(ctx.session);
      expectHas(test, data, "\"csrf\":\"${ctx.session.csrf}\"");
      expectHas(test, data, "\"flash\":{}");
      expectHas(test, data, "\"remember\":false");
      expectHas(test, data, "\"ui\":{\"k\":\"v\"}");
    }

    test("session: pruning removes old logged-out sessions only") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      webFinish(a, httpHtmlOk());
      db.exec("UPDATE sessions SET updated_at = '2000-01-01 00:00:00'", []);
      expectInt(test, webPruneSessions(db, 30), 1);
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM sessions"), 0);
    }

    test("session: a recent session survives pruning") { test =>
      let db = dbOpen(":memory:");
      webFinish(tCtxGet(db, "/"), httpHtmlOk());
      expectInt(test, webPruneSessions(db, 30), 0);
    }

    test("ctx: isAjax follows x-requested-with: blimp") { test =>
      let db = dbOpen(":memory:");
      expectTrue(test, tCtx(db, tRaw("GET", "/", "X-Requested-With: blimp\r\n", "")).isAjax, "blimp");
      expectFalse(test, tCtx(db, tRaw("GET", "/", "", "")).isAjax, "plain");
      expectFalse(test, tCtx(db, tRaw("GET", "/", "X-Requested-With: XMLHttpRequest\r\n", "")).isAjax, "other");
    }

    let httpHtmlOk(): Response {
      new Response(200, [new Pair("Content-Type", "text/html; charset=utf-8")], "ok")
    }

## CSRF

    test("csrf: a POST with no token is a 403 'invalid CSRF token'") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("POST", "/users/log-in", "Content-Type: application/x-www-form-urlencoded\r\n", "a=b"));
      let r = webCheckCsrf(ctx);
      expectInt(test, if (r != null) { r.status } else { 0 }, 403);
      expectText(test, if (r != null) { r.body } else { "" }, "invalid CSRF token");
    }

    test("csrf: a POST with the form token passes") { test =>
      let db = dbOpen(":memory:");
      let first = tCtxGet(db, "/");
      webSaveSession(db, first.session);
      let ctx = tNextPost(db, first, "/x", "Content-Type: application/x-www-form-urlencoded\r\n", "_csrf_token=${first.session.csrf}&a=b");
      expectTrue(test, webCheckCsrf(ctx) == null, "passes");
    }

    test("csrf: a POST with the header token passes (an event)") { test =>
      let db = dbOpen(":memory:");
      let first = tCtxGet(db, "/");
      webSaveSession(db, first.session);
      let ctx = tNextPost(db, first, "/ev/x", "X-CSRF-Token: ${first.session.csrf}\r\nContent-Type: application/json\r\n", "{}");
      expectTrue(test, webCheckCsrf(ctx) == null, "passes");
    }

    test("csrf: a wrong token is rejected") { test =>
      let db = dbOpen(":memory:");
      let first = tCtxGet(db, "/");
      webSaveSession(db, first.session);
      let ctx = tNextPost(db, first, "/x", "X-CSRF-Token: nope\r\n", "");
      let r = webCheckCsrf(ctx);
      expectInt(test, if (r != null) { r.status } else { 0 }, 403);
    }

    test("csrf: another session's token is rejected") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      let b = tCtxGet(db, "/");
      webSaveSession(db, a.session);
      let ctx = tNextPost(db, a, "/x", "X-CSRF-Token: ${b.session.csrf}\r\n", "");
      expectTrue(test, webCheckCsrf(ctx) != null, "rejected");
    }

    test("csrf: a GET needs no token") { test =>
      let db = dbOpen(":memory:");
      expectTrue(test, webCheckCsrf(tCtxGet(db, "/")) == null, "passes");
    }

    test("csrf: PUT and DELETE are checked too") { test =>
      let db = dbOpen(":memory:");
      expectTrue(test, webCheckCsrf(tCtx(db, tRaw("DELETE", "/x", "", ""))) != null, "delete");
      expectTrue(test, webCheckCsrf(tCtx(db, tRaw("PUT", "/x", "", ""))) != null, "put");
    }

    test("csrf: the hidden field carries the token") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      expectText(test, hjoin(webCsrfField(ctx)), "<input type=\"hidden\" name=\"_csrf_token\" value=\"${ctx.session.csrf}\">");
    }

## Flash

    test("flash: put then take returns it") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      webPutFlash(ctx, "error", "no");
      expectText(test, webTakeFlash(ctx).getOr("error", ""), "no");
    }

    test("flash: take clears") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      webPutFlash(ctx, "info", "once");
      webTakeFlash(ctx);
      expectInt(test, webTakeFlash(ctx).keys().length, 0);
    }

    test("flash: a later put of the same kind replaces") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      webPutFlash(ctx, "info", "a");
      webPutFlash(ctx, "info", "b");
      expectText(test, webTakeFlash(ctx).getOr("info", ""), "b");
    }

    test("flash: it survives a save and is gone after being taken and saved") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      webPutFlash(a, "info", "carried");
      webSaveSession(db, a.session);
      let b = tNextCtx(db, a, "/");
      expectText(test, webTakeFlash(b).getOr("info", ""), "carried");
      webSaveSession(db, b.session);
      let c = tNextCtx(db, a, "/");
      expectInt(test, webTakeFlash(c).keys().length, 0);
    }

    test("flash: the info toast has its id, role and classes") { test =>
      let m = new MapBuilder<String, String>();
      m.set("info", "Saved <ok>");
      let html = hjoin(cFlash(null, m.toMap(), null, "info", false, null));
      expectHas(test, html, "<div id=\"flash-info\" role=\"alert\" class=\"toast toast-top toast-end z-50\">");
      expectHas(test, html, "class=\"alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap alert-info\"");
      expectHas(test, html, "<span class=\"hero-information-circle size-5 shrink-0\"></span>");
      expectHas(test, html, "<p>Saved &lt;ok&gt;</p>");
      expectHas(test, html, "<button type=\"button\" class=\"group self-start cursor-pointer\" aria-label=\"close\">");
    }

    test("flash: no message renders nothing") { test =>
      expectText(test, hjoin(cFlash(null, noParams(), null, "error", false, null)), "");
    }

    test("flash: the group has the two flashes and the two connection toasts") { test =>
      let m = new MapBuilder<String, String>();
      m.set("error", "bad");
      let html = hjoin(cFlashGroup(m.toMap(), null));
      expectHas(test, html, "<div id=\"flash-group\" aria-live=\"polite\">");
      expectHas(test, html, "id=\"flash-error\"");
      expectLacks(test, html, "id=\"flash-info\"");
      expectHas(test, html, "<div id=\"client-error\" role=\"alert\" class=\"toast toast-top toast-end z-50\" hidden>");
      expectHas(test, html, "<div id=\"server-error\" role=\"alert\" class=\"toast toast-top toast-end z-50\" hidden>");
      expectHas(test, html, "<p class=\"font-semibold\">We can't find the internet</p>".split("'").join("&#39;") { (p: String): String => p });
      expectHas(test, html, "<p class=\"font-semibold\">Something went wrong!</p>");
      expectHas(test, html, "Attempting to reconnect<span class=\"hero-arrow-path ml-1 size-3 motion-safe:animate-spin\"></span>");
    }

## Head meta

    let tMeta(ctx: Ctx, meta: PageMeta): String { hjoin(webHeadMeta(ctx, meta)) }

    test("head: the defaults") { test =>
      let db = dbOpen(":memory:");
      let s = tMeta(tCtxGet(db, "/"), webMetaDefault());
      expectHas(test, s, "<title data-default=\"Someone who has actually read the whole thing\" data-suffix=\" · Marginalia\">Someone who has actually read the whole thing · Marginalia</title>");
      expectHas(test, s, "<meta name=\"description\" content=\"Upload a draft. It reads end to end, maps what&#39;s on the page, and argues with you in the margin — a thread on any paragraph, anchored to your own sentences.\">");
      expectHas(test, s, "<meta property=\"og:type\" content=\"website\">");
      expectHas(test, s, "<meta property=\"og:site_name\" content=\"Marginalia\">");
      expectHas(test, s, "<meta property=\"og:title\" content=\"Someone who has actually read the whole thing\">");
      expectHas(test, s, "<meta property=\"og:url\" content=\"http://localhost:4000/\">");
      expectHas(test, s, "<link rel=\"canonical\" href=\"http://localhost:4000/\">");
      expectHas(test, s, "<meta property=\"og:image\" content=\"http://localhost:4000/images/og.png\">");
      expectHas(test, s, "<meta property=\"og:image:width\" content=\"2400\">");
      expectHas(test, s, "<meta property=\"og:image:height\" content=\"1260\">");
      expectHas(test, s, "<meta name=\"twitter:card\" content=\"summary_large_image\">");
      expectHas(test, s, "<meta name=\"twitter:image\" content=\"http://localhost:4000/images/og.png\">");
      expectHas(test, s, "<meta name=\"theme-color\" content=\"#fbfaf7\">");
      expectLacks(test, s, "name=\"robots\"");
    }

    test("head: the og alt text default") { test =>
      let db = dbOpen(":memory:");
      let s = tMeta(tCtxGet(db, "/"), webMetaDefault());
      expectHas(test, s, "<meta property=\"og:image:alt\" content=\"Marginalia, a reader for drafts. A note in the margin reads: your opening promises a book about grief, chapter nine is the best thing here, and it belongs to a different one.\">");
    }

    test("head: a page title gets the suffix in <title> and none in og:title") { test =>
      let db = dbOpen(":memory:");
      let s = tMeta(tCtxGet(db, "/"), webMeta("Cases"));
      expectHas(test, s, ">Cases · Marginalia</title>");
      expectHas(test, s, "<meta property=\"og:title\" content=\"Cases\">");
      expectHas(test, s, "<meta name=\"twitter:title\" content=\"Cases\">");
    }

    test("head: overrides") { test =>
      let db = dbOpen(":memory:");
      let meta = new PageMeta("T", "Desc & more", "index, follow", "/images/og-cases.png", "Alt", "/cases/x");
      let s = tMeta(tCtxGet(db, "/"), meta);
      expectHas(test, s, "<meta name=\"robots\" content=\"index, follow\">");
      expectHas(test, s, "<meta name=\"description\" content=\"Desc &amp; more\">");
      expectHas(test, s, "<meta property=\"og:image\" content=\"http://localhost:4000/images/og-cases.png\">");
      expectHas(test, s, "<meta property=\"og:image:alt\" content=\"Alt\">");
      expectHas(test, s, "<link rel=\"canonical\" href=\"http://localhost:4000/cases/x\">");
    }

    test("head: an absolute image or url passes through") { test =>
      let db = dbOpen(":memory:");
      let meta = new PageMeta(null, null, null, "https://cdn.example/a.png", null, "https://example.org/p");
      let s = tMeta(tCtxGet(db, "/"), meta);
      expectHas(test, s, "<meta property=\"og:image\" content=\"https://cdn.example/a.png\">");
      expectHas(test, s, "<meta property=\"og:url\" content=\"https://example.org/p\">");
    }

    test("head: the title is escaped") { test =>
      let db = dbOpen(":memory:");
      let s = tMeta(tCtxGet(db, "/"), webMeta("A <b> & \"c\""));
      expectHas(test, s, ">A &lt;b&gt; &amp; &quot;c&quot; · Marginalia</title>");
    }

    test("head: the tags come in the Phoenix order") { test =>
      let db = dbOpen(":memory:");
      let s = tMeta(tCtxGet(db, "/"), new PageMeta("T", null, "noindex", null, null, null));
      let order = ["<title", "name=\"robots\"", "name=\"description\"", "og:type", "og:site_name", "og:title", "og:url", "rel=\"canonical\"", "og:image\"", "og:image:width", "twitter:card", "theme-color"];
      var rest = s;
      for (var i = 0; i < order.length; ++i) {
        let at = rest.split(order.getOr(i, "")).length;
        expectTrue(test, at > 1, "tag ${order.getOr(i, "")} missing or out of order");
        rest = rest.split(order.getOr(i, "")).slice(1, at).join(order.getOr(i, "")) { (p: String): String => p };
      }
    }

## Layouts

    let tPage(ctx: Ctx, meta: PageMeta, main: List<AnyValue>, layout: String): String throws Bubble {
      webPage(ctx, meta, main, null, layout).body
    }

    test("layout: the document has the head, the csrf meta, the stylesheet and the deferred script") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      let s = tPage(ctx, webMeta("X"), htext("hi"), "app");
      expectHas(test, s, "<!DOCTYPE html>\n<html lang=\"en\">");
      expectHas(test, s, "<meta charset=\"utf-8\">");
      expectHas(test, s, "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">");
      expectHas(test, s, "<meta name=\"csrf-token\" content=\"${ctx.session.csrf}\">");
      expectHas(test, s, "<link rel=\"stylesheet\" href=\"/assets/css/app.css\">");
      expectHas(test, s, "<script defer type=\"text/javascript\" src=\"/assets/js/app.js\"></script>");
    }

    test("layout: the theme script is the HEEx's, byte for byte") { test =>
      let script = webThemeScript();
      expectTrue(test, wcStartsWith(script, "      (() => {\n        const systemTheme = () => matchMedia(\"(prefers-color-scheme: dark)\").matches ? \"dark\" : \"light\";\n"), "starts");
      expectHas(test, script, "        window.addEventListener(\"phx:set-theme\", (e) => setTheme(e.target.dataset.phxTheme));\n");
      expectHas(test, script, "          setTheme(localStorage.getItem(\"phx:theme\") || \"system\");\n");
      expectTrue(test, script.split("\n").length == 26, "26 lines");
    }

    test("layout: the document embeds the theme script") { test =>
      let db = dbOpen(":memory:");
      let s = tPage(tCtxGet(db, "/"), webMeta(null), htext("hi"), "root");
      expectHas(test, s, "<script>\n${webThemeScript()}\n    </script>");
    }

    test("layout: the bare document is the same document with the page's own markup") { test =>
      let db = dbOpen(":memory:");
      let s = tPage(tCtxGet(db, "/"), webMeta(null), h("div", " id=\"landing\"", htext("x")), "bare");
      expectHas(test, s, "<div id=\"main\" style=\"display:contents\">");
      expectHas(test, s, "<div id=\"landing\">x</div>");
      expectLacks(test, s, "class=\"mg-bar\"");
    }

    test("layout: the root layout alone has no app chrome") { test =>
      let db = dbOpen(":memory:");
      let s = tPage(tCtxGet(db, "/"), webMeta(null), htext("bare text"), "root");
      expectHas(test, s, "<body>\nbare text\n</body>");
    }

    test("app: a visitor sees Cases and Log in") { test =>
      let db = dbOpen(":memory:");
      let s = tPage(tCtxGet(db, "/"), webMeta(null), htext("x"), "app");
      expectHas(test, s, "<header class=\"mg-bar\">");
      expectHas(test, s, "<a href=\"/\" class=\"mg-brand\">Marginalia <span>a reader for drafts</span></a>");
      expectHas(test, s, "<a href=\"/cases\">Cases</a>");
      expectHas(test, s, "<a href=\"/users/log-in\">Log in</a>");
      expectLacks(test, s, "Drafts");
      expectLacks(test, s, "Log out");
    }

    test("app: the main element has the id and the HEEx's classes") { test =>
      let db = dbOpen(":memory:");
      let s = tPage(tCtxGet(db, "/"), webMeta(null), htext("x"), "app");
      expectHas(test, s, "<main id=\"main\" class=\"px-4 py-8 sm:px-6 lg:px-8\">");
      expectHas(test, s, "<div class=\"space-y-4\">");
    }

    test("app: bleed drops the padding") { test =>
      let db = dbOpen(":memory:");
      let s = tPage(tCtxGet(db, "/"), webMeta(null), htext("x"), "bleed");
      expectHas(test, s, "<main id=\"main\" class=\"\">");
    }

    test("app: a poll interval goes on the inner div, where a morph can remove it") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      let s = webPage(ctx, webMeta(null), htext("x"), 2, "app").body;
      expectHas(test, s, "<div class=\"space-y-4\" data-poll=\"2\">");
      expectHas(test, s, "<main id=\"main\" class=\"px-4 py-8 sm:px-6 lg:px-8\">");
    }

    test("app: a guest sees the guest nav") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      ctx.scope = scopeFor(tGuestUser(db));
      let s = tPage(ctx, webMeta(null), htext("x"), "app");
      expectHas(test, s, "<a href=\"/works\">Drafts</a>");
      expectHas(test, s, "<a href=\"/works/new\">New draft</a>");
      expectHas(test, s, "<span class=\"text-[var(--mg-dim)] opacity-70\">guest</span>");
      expectHas(test, s, "<a href=\"/users/register\" class=\"mg-btn sm\">Keep my drafts</a>");
      expectLacks(test, s, "Linked");
      expectLacks(test, s, "Log in");
    }

    test("app: a user sees the full nav, their email and a log-out form") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      let user = tUser(db, "me@example.com", false);
      ctx.scope = scopeFor(user);
      let s = tPage(ctx, webMeta(null), htext("x"), "app");
      expectHas(test, s, "<a href=\"/works\">Drafts</a>");
      expectHas(test, s, "<a href=\"/links\">Linked</a>");
      expectHas(test, s, "<a href=\"/cuts\">Cuts</a>");
      expectHas(test, s, "<a href=\"/stacks\">Methods</a>");
      expectHas(test, s, "<a href=\"/works/new\">New draft</a>");
      expectHas(test, s, "<a href=\"/users/settings\">me@example.com</a>");
      expectHas(test, s, "action=\"/users/log-out\"");
      expectHas(test, s, "<input type=\"hidden\" name=\"_method\" value=\"delete\">");
      expectHas(test, s, "<input type=\"hidden\" name=\"_csrf_token\" value=\"${ctx.session.csrf}\">");
      expectHas(test, s, "<button type=\"submit\">Log out</button>");
    }

    test("app: the email is escaped") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      ctx.scope = scopeFor(tUser(db, "a<b>@example.com", false));
      let s = tPage(ctx, webMeta(null), htext("x"), "app");
      expectHas(test, s, ">a&lt;b&gt;@example.com</a>");
    }

    test("app: the page ends with the flash group, showing the taken flash") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      webPutFlash(ctx, "error", "You must log in to access this page.");
      let s = tPage(ctx, webMeta(null), htext("x"), "app");
      expectHas(test, s, "<div id=\"flash-group\" aria-live=\"polite\">");
      expectHas(test, s, "<p>You must log in to access this page.</p>");
      expectInt(test, webTakeFlash(ctx).keys().length, 0);
    }

## webPage, events, redirects

    test("webPage: a plain request gets the full HTML with the cookie") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      let r = webPage(ctx, webMeta("Cases"), htext("body text"), null, "app");
      expectInt(test, r.status, 200);
      expectHas(test, tHeaders(r, "Content-Type"), "text/html");
      expectHas(test, r.body, "<!DOCTYPE html>");
      expectHas(test, r.body, "body text");
      expectHas(test, tHeaders(r, "Set-Cookie"), "_marginalia_key=");
    }

    test("webPage: an ajax request gets the region as JSON") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("GET", "/cases", "X-Requested-With: blimp\r\nAccept: application/json\r\n", ""));
      let r = webPage(ctx, webMeta("Cases"), htext("body <text>"), null, "app");
      expectInt(test, r.status, 200);
      expectHas(test, tHeaders(r, "Content-Type"), "application/json");
      expectLacks(test, r.body, "<!DOCTYPE");
      let regions = tJsonField(r.body, "regions");
      expectTrue(test, regions is JsonObject, "regions object");
      if (regions is JsonObject) {
        let main = regions.propertyValueOrNull("#main");
        expectTrue(test, main is JsonString, "#main string");
        if (main is JsonString) {
          expectText(test, main.content, "<div class=\"space-y-4\">\nbody &lt;text&gt;\n</div>");
        }
      }
      expectText(test, tJsonString(r.body, "title"), "Cases · Marginalia");
    }

    test("webPage: the ajax reply carries the pending flash and takes it") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("GET", "/x", "X-Requested-With: blimp\r\n", ""));
      webPutFlash(ctx, "info", "Saved.");
      let r = webPage(ctx, webMeta(null), htext("x"), null, "app");
      let flash = tJsonField(r.body, "flash");
      expectTrue(test, flash is JsonObject, "flash object");
      if (flash is JsonObject) {
        let info = flash.propertyValueOrNull("info");
        expectTrue(test, info is JsonString, "info");
        if (info is JsonString) { expectText(test, info.content, "Saved."); }
      }
      expectInt(test, ctx.session.flash.keys().length, 0);
    }

    test("webPage: the ajax region of a polling page keeps data-poll") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("GET", "/x", "X-Requested-With: blimp\r\n", ""));
      let r = webPage(ctx, webMeta(null), htext("x"), 2, "app");
      expectHas(test, r.body, "<div class=\\\"space-y-4\\\" data-poll=\\\"2\\\">");
    }

    test("webPage: the session is saved") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      webPage(ctx, webMeta(null), htext("x"), null, "app");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM sessions WHERE id = '${ctx.session.id}'"), 1);
    }

    test("webEventReply: regions, events and flash") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("POST", "/ev/go", "X-Requested-With: blimp\r\n", ""));
      let r = webEventReply(ctx, htext("new"), [new Pair("chat:clear", "{\"a\":1}")], new Pair("error", "Nope"), null);
      expectHas(test, r.body, "\"events\":[{\"name\":\"chat:clear\",\"payload\":{\"a\":1}}]");
      expectHas(test, r.body, "\"flash\":{\"error\":\"Nope\"}");
      expectHas(test, r.body, "\"regions\":{\"#main\":\"<div class=\\\"space-y-4\\\">\\nnew\\n</div>\"}");
    }

    test("webEventReply: no events, no flash") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("POST", "/ev/go", "X-Requested-With: blimp\r\n", ""));
      let r = webEventReply(ctx, htext("n"), [], null, null);
      expectHas(test, r.body, "\"events\":[]");
      expectHas(test, r.body, "\"flash\":{}");
    }

    test("webRedirect: a plain request is a 303") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      let r = webRedirect(ctx, "/works", new Pair("info", "Done"));
      expectInt(test, r.status, 303);
      expectText(test, tHeaders(r, "Location"), "/works");
      expectText(test, ctx.session.flash.getOr("info", ""), "Done");
      expectHas(test, tHeaders(r, "Set-Cookie"), "_marginalia_key=");
    }

    test("webRedirect: an ajax request gets {\"redirect\": to}") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("POST", "/ev/x", "X-Requested-With: blimp\r\n", ""));
      let r = webRedirect(ctx, "/works/abc", null);
      expectInt(test, r.status, 200);
      expectText(test, r.body, "{\"redirect\":\"/works/abc\"}");
    }

    test("webRedirect: the flash survives to the next page") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      webRedirect(a, "/works", new Pair("error", "Work not found."));
      let b = tNextCtx(db, a, "/works");
      expectText(test, webTakeFlash(b).getOr("error", ""), "Work not found.");
    }

    test("errors: the 404 page") { test =>
      let db = dbOpen(":memory:");
      let r = webNotFound(tCtxGet(db, "/"));
      expectInt(test, r.status, 404);
      expectHas(test, r.body, "<h1>Nothing at that address</h1>");
      expectHas(test, r.body, "<p>The link may be old, or the draft may have been taken down. Nothing is lost by following a wrong address.</p>");
      expectHas(test, r.body, "<title>Nothing at that address · Marginalia</title>");
      expectHas(test, r.body, "<meta name=\"robots\" content=\"noindex\">");
      expectHas(test, r.body, "<a href=\"/reading\">Readings</a>");
    }

    test("errors: the 500 page") { test =>
      let db = dbOpen(":memory:");
      let r = webServerError(tCtxGet(db, "/"));
      expectInt(test, r.status, 500);
      expectHas(test, r.body, "<h1>Something broke</h1>");
      expectHas(test, r.body, "That is this end, not yours, and it has been logged.");
    }

    test("errors: forbidden is the plain message") { test =>
      let db = dbOpen(":memory:");
      let r = webForbidden(tCtxGet(db, "/"));
      expectInt(test, r.status, 403);
      expectText(test, r.body, "Forbidden");
    }

## UI state

    test("ui: put and get") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      expectTrue(test, uiGet(ctx, "a") == null, "absent");
      uiPut(ctx, "a", "1");
      uiPut(ctx, "a", "2");
      expectText(test, wcOr(uiGet(ctx, "a"), "<none>"), "2");
    }

    test("ui: delete") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      uiPut(ctx, "a", "1");
      uiDelete(ctx, "a");
      expectTrue(test, uiGet(ctx, "a") == null, "gone");
    }

    test("ui: json round trip, through the database") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      let tree: JsonSyntaxTree = parseJson("{\"open\":[1,2],\"name\":\"x\"}");
      uiPutJson(a, "panel", tree);
      webSaveSession(db, a.session);
      let b = tNextCtx(db, a, "/");
      let got = uiGetJson(b, "panel");
      expectTrue(test, got is JsonObject, "an object");
      if (got is JsonObject) {
        let name = got.propertyValueOrNull("name");
        expectTrue(test, name is JsonString, "name");
        if (name is JsonString) { expectText(test, name.content, "x"); }
      }
    }

    test("ui: a stored value that is not JSON reads as absent") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      uiPut(ctx, "k", "not json {");
      expectTrue(test, uiGetJson(ctx, "k") == null, "absent");
    }

## The plugs

    test("require_real_account: a visitor goes to log in with the verbatim flash") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/works");
      webMountCurrentScope(ctx);
      let r = webRequireRealAccount(ctx);
      expectTrue(test, r != null, "redirects");
      if (r != null) {
        expectInt(test, r.status, 303);
        expectText(test, tHeaders(r, "Location"), "/users/log-in");
      }
      expectText(test, ctx.session.flash.getOr("error", ""), "You must log in to access this page.");
    }

    test("require_real_account: a GET is remembered for after the login") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("GET", "/works?page=2", "", ""));
      webRequireRealAccount(ctx);
      expectText(test, wcOr(ctx.session.returnTo, "<none>"), "/works?page=2");
    }

    test("require_real_account: a POST is not remembered") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("POST", "/works/new", "", ""));
      webRequireRealAccount(ctx);
      expectTrue(test, ctx.session.returnTo == null, "not stored");
    }

    test("require_real_account: a guest goes to register with the verbatim flash") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/users/settings");
      ctx.scope = scopeFor(tGuestUser(db));
      let r = webRequireRealAccount(ctx);
      expectTrue(test, r != null, "redirects");
      if (r != null) { expectText(test, tHeaders(r, "Location"), "/users/register"); }
      expectText(test, ctx.session.flash.getOr("info", ""), "Create an account to keep your drafts.");
    }

    test("require_real_account: a real user goes on") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/users/settings");
      ctx.scope = scopeFor(tRealUser(db));
      expectTrue(test, webRequireRealAccount(ctx) == null, "goes on");
    }

    test("require_real_account: on an ajax request the redirect is JSON") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("POST", "/ev/x", "X-Requested-With: blimp\r\n", ""));
      let r = webRequireRealAccount(ctx);
      expectTrue(test, r != null, "redirects");
      if (r != null) { expectText(test, r.body, "{\"redirect\":\"/users/log-in\"}"); }
    }

    test("require_authenticated: a guest is let through, a visitor is not") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/");
      a.scope = scopeFor(tGuestUser(db));
      expectTrue(test, webRequireAuthenticated(a) == null, "guest");
      expectTrue(test, webRequireAuthenticated(tCtxGet(db, "/")) != null, "visitor");
    }

    test("redirect_if_authenticated: a user is sent to /, a visitor goes on") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/users/register");
      a.scope = scopeFor(tRealUser(db));
      let r = webRedirectIfAuthenticated(a);
      expectTrue(test, r != null, "redirects");
      if (r != null) { expectText(test, tHeaders(r, "Location"), "/"); }
      expectTrue(test, webRedirectIfAuthenticated(tCtxGet(db, "/users/register")) == null, "visitor");
    }

    test("mount_current_scope: no session leaves the visitor scope") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtxGet(db, "/");
      webMountCurrentScope(ctx);
      expectTrue(test, ctx.scope.user == null, "no user");
    }

    test("login: a token, the session, a redirect to /") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let a = tCtxGet(db, "/users/log-in");
      let oldCsrf = a.session.csrf;
      let r = webLogIn(a, user, false);
      expectInt(test, r.status, 303);
      expectText(test, tHeaders(r, "Location"), "/");
      expectHas(test, tHeaders(r, "Set-Cookie"), "_marginalia_key=${a.session.id}");
      expectTrue(test, a.session.csrf != oldCsrf, "a login renews the csrf token");
      expectText(test, tHeaders(r, "Set-Cookie").split(webRememberCookieName()).length.toString(), "1");
      let b = tNextCtx(db, a, "/works");
      webMountCurrentScope(b);
      let u = b.scope.user;
      expectTrue(test, u != null, "logged in on the next request");
      if (u != null) { expectInt(test, u.id, user.id); }
    }

    test("login: an already-logged-in user goes to settings") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let a = tCtxGet(db, "/users/log-in");
      a.scope = scopeFor(tGuestUser(db));
      let r = webLogIn(a, user, false);
      expectText(test, tHeaders(r, "Location"), "/users/settings");
    }

    test("login: the stored return-to wins, and is used once") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let a = tCtxGet(db, "/works");
      webRequireRealAccount(a);
      webSaveSession(db, a.session);
      let b = tNextCtx(db, a, "/users/log-in");
      let r = webLogIn(b, user, false);
      expectText(test, tHeaders(r, "Location"), "/works");
      expectTrue(test, b.session.returnTo == null, "cleared");
    }

    test("login: remember me writes the 14-day cookie with the token") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let a = tCtxGet(db, "/users/log-in");
      let r = webLogIn(a, user, true);
      let cookies = tHeaders(r, "Set-Cookie");
      expectHas(test, cookies, "${webRememberCookieName()}=");
      expectHas(test, cookies, "Max-Age=1209600");
      expectHas(test, cookies, "HttpOnly; SameSite=Lax; Max-Age=1209600");
      expectTrue(test, a.session.remember, "the session remembers");
    }

    test("remember me: the cookie alone authenticates") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let token = accountsGenerateUserSessionToken(db, user);
      let ctx = tCtx(db, tRaw("GET", "/works", tCookie(webRememberCookieName(), token), ""));
      webMountCurrentScope(ctx);
      let u = ctx.scope.user;
      expectTrue(test, u != null, "user found");
      if (u != null) { expectInt(test, u.id, user.id); }
      expectTrue(test, ctx.session.remember, "remembered");
      expectTrue(test, ctx.session.userTokenId != null, "the session now holds the token");
    }

    test("remember me: a bad cookie is no user") { test =>
      let db = dbOpen(":memory:");
      let ctx = tCtx(db, tRaw("GET", "/works", tCookie(webRememberCookieName(), "garbage"), ""));
      webMountCurrentScope(ctx);
      expectTrue(test, ctx.scope.user == null, "no user");
    }

    test("mount_current_scope: a token 8 days old is reissued") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let a = tCtxGet(db, "/");
      let token = accountsGenerateUserSessionToken(db, user);
      db.exec("UPDATE users_tokens SET inserted_at = datetime('now', '-8 days') WHERE token = $1", [token]);
      let row = db.one("SELECT id FROM users_tokens WHERE token = $1", [token]);
      a.session.userTokenId = if (row != null) { row.int("id") } else { -1 };
      webMountCurrentScope(a);
      expectTrue(test, a.scope.user != null, "still logged in");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens WHERE context = 'session'"), 2);
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens WHERE token = '${token}'"), 1);
      expectTrue(test, a.session.userTokenId != (if (row != null) { row.int("id") } else { -1 }), "the session holds the new token");
    }

    test("mount_current_scope: a fresh token is not reissued") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let a = tCtxGet(db, "/");
      let token = accountsGenerateUserSessionToken(db, user);
      let row = db.one("SELECT id FROM users_tokens WHERE token = $1", [token]);
      a.session.userTokenId = if (row != null) { row.int("id") } else { -1 };
      webMountCurrentScope(a);
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens WHERE context = 'session'"), 1);
    }

    test("mount_current_scope: an expired token is no user") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let a = tCtxGet(db, "/");
      let token = accountsGenerateUserSessionToken(db, user);
      db.exec("UPDATE users_tokens SET inserted_at = datetime('now', '-15 days') WHERE token = $1", [token]);
      let row = db.one("SELECT id FROM users_tokens WHERE token = $1", [token]);
      a.session.userTokenId = if (row != null) { row.int("id") } else { -1 };
      webMountCurrentScope(a);
      expectTrue(test, a.scope.user == null, "no user");
    }

    test("logout: the token dies, the cookie is cleared, redirect to /") { test =>
      let db = dbOpen(":memory:");
      let user = tRealUser(db);
      let a = tCtxGet(db, "/users/log-in");
      webLogIn(a, user, true);
      let b = tNextCtx(db, a, "/works");
      webMountCurrentScope(b);
      expectTrue(test, b.scope.user != null, "logged in");
      let r = webLogOut(b);
      expectInt(test, r.status, 303);
      expectText(test, tHeaders(r, "Location"), "/");
      expectHas(test, tHeaders(r, "Set-Cookie"), "${webRememberCookieName()}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens WHERE context = 'session'"), 0);
      let c = tNextCtx(db, b, "/works");
      webMountCurrentScope(c);
      expectTrue(test, c.scope.user == null, "the old session cookie no longer logs in");
    }

    test("logout: with no session it still redirects to /") { test =>
      let db = dbOpen(":memory:");
      let r = webLogOut(tCtxGet(db, "/users/log-out"));
      expectInt(test, r.status, 303);
      expectText(test, tHeaders(r, "Location"), "/");
    }

    test("ensure_user_or_guest: a visitor gets a guest, a session token and no remember cookie (real hashing)") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/works/new");
      let oldCsrf = a.session.csrf;
      expectTrue(test, webEnsureUserOrGuest(a) == null, "goes on");
      let u = a.scope.user;
      expectTrue(test, u != null, "a user");
      if (u != null) {
        expectTrue(test, u.isGuest, "a guest");
        expectHas(test, u.email, "@guest.marginalia.local");
      }
      expectText(test, a.session.csrf, oldCsrf);
      expectFalse(test, a.session.remember, "no remember");
      let r = webPage(a, webMeta(null), htext("x"), null, "app");
      expectLacks(test, tHeaders(r, "Set-Cookie"), webRememberCookieName());
      let b = tNextCtx(db, a, "/works");
      webMountCurrentScope(b);
      let bu = b.scope.user;
      expectTrue(test, bu != null, "the guest persists on the next request");
      if (bu != null) { if (u != null) { expectInt(test, bu.id, u.id); } }
    }

    test("ensure_user_or_guest: an existing user is left alone") { test =>
      let db = dbOpen(":memory:");
      let a = tCtxGet(db, "/works");
      let user = tRealUser(db);
      a.scope = scopeFor(user);
      expectTrue(test, webEnsureUserOrGuest(a) == null, "goes on");
      let u = a.scope.user;
      if (u != null) { expectInt(test, u.id, user.id); }
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users WHERE is_guest = 1"), 0);
    }

## Components

    test("button: the default is a ghost button with the btn class") { test =>
      expectText(test, hjoin(cButton(null, null, null, "", htext("Go"))), "<button class=\"btn mg-btn ghost\">Go</button>");
    }

    test("button: primary, and a link when there is an href") { test =>
      expectText(test, hjoin(cButton(null, "primary", null, " type=\"submit\"", htext("Go"))), "<button class=\"btn mg-btn\" type=\"submit\">Go</button>");
      expectText(test, hjoin(cButton("/x", "primary", null, "", htext("Go"))), "<a class=\"btn mg-btn\" href=\"/x\">Go</a>");
    }

    test("button: a class replaces the default") { test =>
      expectText(test, hjoin(cButton(null, null, "mg-btn sm", "", htext("Go"))), "<button class=\"mg-btn sm\">Go</button>");
    }

    test("input: a text input with a label") { test =>
      let html = hjoin(cTextInput("user[email]", "user_email", "Email", "email", "a@b.c", []));
      expectText(test, html, "<div class=\"mg-field\"><label for=\"user_email\"><span class=\"mg-label block mb-1.5\">Email</span><input type=\"email\" name=\"user[email]\" id=\"user_email\" value=\"a@b.c\" class=\"mg-input\"></label></div>");
    }

    test("input: errors add the border class and a message with the icon") { test =>
      let html = hjoin(cTextInput("n", "n", null, "text", null, ["can't be blank"]));
      expectHas(test, html, "class=\"mg-input border-[var(--mg-accent)]\"");
      expectHas(test, html, "<p class=\"mt-1.5 flex gap-2 items-center text-sm text-error\"><span class=\"hero-exclamation-circle size-5\"></span>can&#39;t be blank</p>");
      expectLacks(test, html, "value=");
    }

    test("input: a textarea") { test =>
      let spec = cInputSpec("work[body]");
      spec.kind = "textarea";
      spec.id = "body";
      spec.label = "Text";
      spec.value = "\nfirst";
      let html = hjoin(cInput(spec));
      expectHas(test, html, "<textarea id=\"body\" name=\"work[body]\" class=\"mg-textarea\">\n\nfirst</textarea>");
    }

    test("input: a select marks the selected option and shows the prompt") { test =>
      let spec = cInputSpec("p");
      spec.kind = "select";
      spec.id = "p";
      spec.value = "b";
      spec.prompt = "Choose";
      spec.options = [new Pair("A", "a"), new Pair("B", "b")];
      let html = hjoin(cInput(spec));
      expectHas(test, html, "<select id=\"p\" name=\"p\" class=\"mg-select\">");
      expectHas(test, html, "<option value=\"\">Choose</option>");
      expectHas(test, html, "<option value=\"a\">A</option>");
      expectHas(test, html, "<option value=\"b\" selected>B</option>");
    }

    test("input: a checkbox has its hidden twin and follows the value") { test =>
      let spec = cInputSpec("remember_me");
      spec.kind = "checkbox";
      spec.id = "rm";
      spec.label = "Keep me logged in";
      spec.value = "true";
      let html = hjoin(cInput(spec));
      expectHas(test, html, "<input type=\"hidden\" name=\"remember_me\" value=\"false\">");
      expectHas(test, html, "<input type=\"checkbox\" id=\"rm\" name=\"remember_me\" value=\"true\" checked class=\"checkbox checkbox-sm\">Keep me logged in</span>");
    }

    test("input: a hidden input") { test =>
      let spec = cInputSpec("k");
      spec.kind = "hidden";
      spec.value = "v";
      expectText(test, hjoin(cInput(spec)), "<input type=\"hidden\" name=\"k\" value=\"v\">");
    }

    test("header: with and without actions") { test =>
      expectText(test, hjoin(cHeader(htext("Title"), [], [])), "<header class=\"pb-4\"><div><h1 class=\"text-lg font-semibold leading-8\">Title</h1></div><div class=\"flex-none\"></div></header>");
      let withAll = hjoin(cHeader(htext("T"), htext("sub"), htext("act")));
      expectHas(test, withAll, "<header class=\"flex items-center justify-between gap-6 pb-4\">");
      expectHas(test, withAll, "<p class=\"text-sm text-base-content/70\">sub</p>");
      expectHas(test, withAll, "<div class=\"flex-none\">act</div>");
    }

    test("table: columns, rows, row ids and the actions column") { test =>
      let rows = [new CRow("r1", [htext("a"), htext("b")], [htext("edit")], "open")];
      let html = hjoin(cTable("things", ["One", "Two"], rows, true));
      expectHas(test, html, "<table class=\"table table-zebra\">");
      expectHas(test, html, "<thead><tr><th>One</th><th>Two</th><th><span class=\"sr-only\">Actions</span></th></tr></thead>");
      expectHas(test, html, "<tbody id=\"things\"><tr id=\"r1\"><td phx-click=\"open\" class=\"hover:cursor-pointer\">a</td>");
      expectHas(test, html, "<td class=\"w-0 font-semibold\"><div class=\"flex gap-4\">edit</div></td>");
    }

    test("list: items with titles") { test =>
      let html = hjoin(cList([new Pair("Title", htext("body"))]));
      expectText(test, html, "<ul class=\"list\"><li class=\"list-row\"><div class=\"list-col-grow\"><div class=\"font-bold\">Title</div><div>body</div></div></li></ul>");
    }

    test("icon: the span the stylesheet masks, and the inline svg") { test =>
      expectText(test, hjoin(cIcon("hero-x-mark")), "<span class=\"hero-x-mark size-4\"></span>");
      let svg = hjoin(cIconSvg("hero-x-mark", "size-5"));
      expectHas(test, svg, "<svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" aria-hidden=\"true\" data-slot=\"icon\" class=\"size-5\">");
      expectHas(test, svg, "d=\"M6 18 18 6M6 6l12 12\"/></svg>");
    }

    test("icon: all seven svgs build") { test =>
      let names = ["hero-information-circle", "hero-exclamation-circle", "hero-x-mark", "hero-arrow-path", "hero-computer-desktop-micro", "hero-sun-micro", "hero-moon-micro"];
      for (var i = 0; i < names.length; ++i) {
        let svg = hjoin(cIconSvg(names.getOr(i, ""), "c"));
        expectTrue(test, wcStartsWith(svg, "<svg "), names.getOr(i, ""));
        expectHas(test, svg, "</svg>");
      }
    }

    test("mutter: the dots alone when there are no lines") { test =>
      expectText(test, hjoin(cMutter([], "thinking", null)), "<div class=\"mg-dots\" aria-label=\"thinking\"><span class=\"mg-dot\"></span><span class=\"mg-dot\" style=\"animation-delay:.18s\"></span><span class=\"mg-dot\" style=\"animation-delay:.36s\"></span></div>");
    }

    test("mutter: the first line, the hook and the lines as JSON") { test =>
      let html = hjoin(cMutter(["one", "t\"wo"], "waiting", "extra"));
      expectHas(test, html, "<div class=\"mg-dots extra\" aria-label=\"waiting\">");
      expectHas(test, html, "class=\"mg-mutter\" phx-hook=\"Rotate\" phx-update=\"ignore\" data-lines=\"[&quot;one&quot;,&quot;t\\&quot;wo&quot;]\">one</span>");
    }

    test("mutter: the same lines give the same id, different lines another") { test =>
      let a = hjoin(cMutter(["x", "y"], "t", null));
      let b = hjoin(cMutter(["x", "y"], "t", null));
      let c = hjoin(cMutter(["x", "z"], "t", null));
      expectText(test, a, b);
      expectTrue(test, a != c, "different");
      expectHas(test, a, "id=\"mutter-");
    }

    test("translate_error: placeholders are filled") { test =>
      let m = new MapBuilder<String, String>();
      m.set("count", "8");
      expectText(test, cTranslateError("should be at least %{count} character(s)", m.toMap()), "should be at least 8 character(s)");
      expectText(test, cTranslateError("can't be blank", noParams()), "can't be blank");
    }

    test("translate_errors: only the field's messages") { test =>
      let errs = [new Pair("email", "is invalid"), new Pair("password", "too short"), new Pair("email", "taken")];
      expectText(test, cTranslateErrors(errs, "email").join("|") { (x: String): String => x }, "is invalid|taken");
    }

    test("theme toggle: three buttons with data-phx-theme") { test =>
      let html = hjoin(cThemeToggle());
      expectHas(test, html, "<button class=\"flex p-2 cursor-pointer w-1/3\" data-phx-theme=\"system\"><span class=\"hero-computer-desktop-micro size-4 opacity-75 hover:opacity-100\"></span></button>");
      expectHas(test, html, "data-phx-theme=\"light\"");
      expectHas(test, html, "data-phx-theme=\"dark\"");
    }
