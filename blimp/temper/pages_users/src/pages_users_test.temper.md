# Tests for pages_users

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.
Requests are parsed from raw text with `httpParse`. A user costs one PBKDF2
at the real iteration count, so each test makes as few as it can.

    let { dbOpen, Db } = import("db/src");
    let { Request, Response, Route, Match, httpParse, routeMatch, urlEncode } = import("http/src");
    let { User, noScope, accountsRegisterUser, accountsGetUserByEmail, accountsGetUserByEmailAndPassword,
          accountsGenerateUserSessionToken, accountsGetUser, accountsDeliverUserUpdateEmailInstructions } = import("accounts/src");
    let {
      Ctx, PageMeta, webNewCtx, webMountCurrentScope, webSessionCookieName, webRequireRealAccount,
      webRememberCookieName, webSaveSession, webPutFlash,
    } = import("webcore/src");
    let { hjoin } = import("html/src");
    let { JsonObject, JsonSyntaxTree, parseJson } = import("std/json");

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

    let tPassword(): String { "hello world!" }

    let tRaw(method: String, path: String, extra: String, body: String): Request {
      httpParse("${method} ${path} HTTP/1.1\r\nHost: localhost\r\n${extra}Content-Length: ${body.split("").length.toString()}\r\n\r\n${body}")
    }

    let tHeaders(r: Response, name: String): String {
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

    let tMakeUser(db: Db, email: String): User throws Bubble {
      let params = new MapBuilder<String, String>();
      params.set("email", email);
      params.set("password", tPassword());
      let r = accountsRegisterUser(db, params.toMap());
      let u = r.ok;
      if (u != null) { u } else { bubble() }
    }

A urlencoded form body from `user[...]` pairs.

    let tForm(pairs: List<Pair<String, String>>): String {
      pairs.map { (p: Pair<String, String>): String => "${urlEncode(p.key)}=${urlEncode(p.value)}" }.join("&") { (x: String): String => x }
    }

    let tUserForm(email: String, password: String): List<Pair<String, String>> {
      [new Pair("user[email]", email), new Pair("user[password]", password)]
    }

What one request came back with: the context it ran in (for the next request's
cookie) and the response.

    class TRun(public ctx: Ctx, public resp: Response) {}

    let tMatch(method: String, path: String): Match throws Bubble {
      let m = routeMatch(pagesUsersRoutes(), method, path);
      if (m != null) { m } else { bubble() }
    }

    let tCookieHeader(prev: Ctx?): String {
      if (prev != null) { "Cookie: ${webSessionCookieName()}=${prev.session.id}\r\n" } else { "" }
    }

The router in miniature: context, scope, the `real.` plug, the group.

    let tServe(db: Db, req: Request, match: Match): TRun throws Bubble {
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      var denied: Response? = null;
      if (hasText(match.route.name, "real.")) { denied = webRequireRealAccount(ctx); }
      let d = denied;
      if (d != null) { new TRun(ctx, d) } else { new TRun(ctx, pagesUsersGet(ctx, match)) }
    }

    let tGet(db: Db, prev: Ctx?, path: String): TRun throws Bubble {
      let bare = path.split("?").getOr(0, path);
      tServe(db, tRaw("GET", path, tCookieHeader(prev), ""), tMatch("GET", bare))
    }

    let tPost(db: Db, prev: Ctx?, path: String, form: String): TRun throws Bubble {
      let req = tRaw("POST", path, "${tCookieHeader(prev)}Content-Type: application/x-www-form-urlencoded\r\n", form);
      tServe(db, req, tMatch("POST", path))
    }

    let tDelete(db: Db, prev: Ctx?, path: String): TRun throws Bubble {
      tServe(db, tRaw("DELETE", path, tCookieHeader(prev), ""), tMatch("DELETE", path))
    }

An event: the page's GET route owns it, the request is the `/ev/` POST.

    let tEvent(db: Db, prev: Ctx?, page: String, name: String, payload: String): TRun throws Bubble {
      let req = tRaw("POST", "/ev/${name}", "${tCookieHeader(prev)}X-Requested-With: blimp\r\nContent-Type: application/json\r\n", "{\"payload\":${payload},\"path\":\"${page}\"}");
      let match = tMatch("GET", page);
      let ctx = webNewCtx(db, ":memory:", req, match.params);
      webMountCurrentScope(ctx);
      var denied: Response? = null;
      if (hasText(match.route.name, "real.")) { denied = webRequireRealAccount(ctx); }
      let d = denied;
      if (d != null) { return new TRun(ctx, d); }
      let tree: JsonSyntaxTree = parseJson(payload);
      if (tree is JsonObject) {
        new TRun(ctx, pagesUsersEvent(ctx, match, name, tree))
      } else { bubble() }
    }

Log in as `email`: a visit for the cookie, then the form.

    let tLogin(db: Db, email: String, remember: Boolean): TRun throws Bubble {
      let first = tGet(db, null, "/users/log-in");
      webSaveSession(db, first.ctx.session);
      let pairs = new ListBuilder<Pair<String, String>>();
      pairs.add(new Pair("user[email]", email));
      pairs.add(new Pair("user[password]", tPassword()));
      if (remember) { pairs.add(new Pair("user[remember_me]", "true")); }
      tPost(db, first.ctx, "/users/log-in", tForm(pairs.toList()))
    }

A logged-in session for a fresh user: the context to pass on.

    let tLoggedIn(db: Db, email: String): Ctx throws Bubble {
      tMakeUser(db, email);
      tLogin(db, email, false).ctx
    }

A session that holds a guest user: the row by SQL, since a guest costs a hash.

    let tGuestCtx(db: Db): Ctx throws Bubble {
      let first = tGet(db, null, "/users/log-in");
      let id = db.insert("INSERT INTO users (email, hashed_password, confirmed_at, is_guest) VALUES ('guest-x@guest.marginalia.local', 'x', '2020-01-01 00:00:00', 1)", []);
      let token = accountsGenerateUserSessionToken(db, accountsGetUser(db, id));
      let row = db.one("SELECT id FROM users_tokens WHERE token = $1", [token]);
      if (row != null) { first.ctx.session.userTokenId = row.int("id"); }
      first.ctx.session.dirty = true;
      webSaveSession(db, first.ctx.session);
      first.ctx
    }

    let tRepeat(s: String, n: Int): String {
      let parts = new ListBuilder<String>();
      for (var i = 0; i < n; ++i) { parts.add(s); }
      parts.toList().join("") { (x: String): String => x }
    }

    let tStatus(r: TRun): Int { r.resp.status }

    let tBody(r: TRun): String { r.resp.body }

    let tLocation(r: TRun): String { tHeaders(r.resp, "Location") }

## Routes

    test("routes: the group's routes, in router order") { test =>
      let names = pagesUsersRoutes().map { (r: Route): String => "${r.method} ${r.pattern}" };
      expectText(test, names.join(", ") { (x: String): String => x },
        "GET /users/settings, GET /users/settings/confirm-email/:token, POST /users/update-password, GET /users/register, POST /users/register, GET /users/log-in, POST /users/log-in, POST /users/log-out, DELETE /users/log-out");
    }

    test("routes: every name carries a plug prefix") { test =>
      for (let r of pagesUsersRoutes()) {
        expectTrue(test, hasText(r.name, "real.") || hasText(r.name, "anyone."), r.name);
      }
    }

    test("routes: settings routes need a real account, the rest do not") { test =>
      for (let r of pagesUsersRoutes()) {
        let settings = hasText(r.pattern, "settings") || hasText(r.pattern, "update-password");
        expectTrue(test, settings == hasText(r.name, "real."), r.name);
      }
    }

## Parameters

    let tObject(json: String): JsonObject throws Bubble {
      let tree: JsonSyntaxTree = parseJson(json);
      if (tree is JsonObject) { tree } else { bubble() }
    }

    test("params: the nested shape") { test =>
      let p = pagesUsersParams(tObject("{\"user\":{\"email\":\"a@b.c\",\"password\":\"pw\"}}"));
      expectText(test, p.getOr("email", "?"), "a@b.c");
      expectText(test, p.getOr("password", "?"), "pw");
    }

    test("params: the flat shape the client sends") { test =>
      let p = pagesUsersParams(tObject("{\"user[email]\":\"a@b.c\",\"user[password_confirmation]\":\"x\",\"_csrf_token\":\"t\"}"));
      expectText(test, p.getOr("email", "?"), "a@b.c");
      expectText(test, p.getOr("password_confirmation", "?"), "x");
      expectInt(test, p.keys().length, 2);
    }

    test("params: other keys are ignored") { test =>
      let p = pagesUsersParams(tObject("{\"action\":\"update_email\"}"));
      expectInt(test, p.keys().length, 0);
    }

    test("params: _target names the field that changed") { test =>
      expectText(test, pagesUsersTarget(tObject("{\"_target\":[\"user[email]\"]}")), "email");
      expectText(test, pagesUsersTarget(tObject("{}")), "");
    }

    test("used: a submit uses every field sent, a change only the filled ones and the target") { test =>
      let p = pagesUsersParams(tObject("{\"user\":{\"email\":\"x\",\"password\":\"\",\"password_confirmation\":\"\"}}"));
      expectInt(test, pagesUsersUsed(p, "", true).length, 3);
      let changed = pagesUsersUsed(p, "", false);
      expectInt(test, changed.length, 1);
      expectText(test, changed.getOr(0, "?"), "email");
      expectInt(test, pagesUsersUsed(p, "password", false).length, 2);
    }

## Log in: the markup

    let tLoginHtml(db: Db, reauth: Boolean): String throws Bubble {
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", "/users/log-in", "", ""), new MapBuilder<String, String>().toMap());
      hjoin(renderUsersLogin(ctx, new UsersLoginState(if (reauth) { "me@example.com" } else { "" }, reauth)))
    }

    test("login: the container, heading and hint classes") { test =>
      let html = tLoginHtml(dbOpen(":memory:"), false);
      expectHas(test, html, "<div class=\"mx-auto max-w-sm px-6 py-16 space-y-5\">");
      expectHas(test, html, "<h1 style=\"font-family:var(--mg-serif)\" class=\"text-2xl font-semibold tracking-tight\">Log in</h1>");
      expectHas(test, html, "<p class=\"mg-hint mt-1.5\">");
    }

    test("login: a visitor is offered Sign up") { test =>
      let html = tLoginHtml(dbOpen(":memory:"), false);
      expectHas(test, html, "Don't have an account? ");
      expectHas(test, html, "<a href=\"/users/register\" class=\"font-semibold text-[var(--mg-accent)] hover:underline\">Sign up</a>");
      expectHas(test, html, " for an account now.");
      expectLacks(test, html, "reauthenticate");
    }

    test("login: the form posts to the controller with a CSRF field") { test =>
      let html = tLoginHtml(dbOpen(":memory:"), false);
      expectHas(test, html, "<form id=\"login_form_password\" action=\"/users/log-in\" method=\"post\">");
      expectHas(test, html, "<input type=\"hidden\" name=\"_csrf_token\" value=\"");
      expectLacks(test, html, "phx-submit");
    }

    test("login: the email field, empty for a visitor") { test =>
      let html = tLoginHtml(dbOpen(":memory:"), false);
      expectHas(test, html, "<label for=\"login_form_password_email\">");
      expectHas(test, html, "<span class=\"mg-label block mb-1.5\">Email</span>");
      expectHas(test, html, "<input type=\"email\" name=\"user[email]\" id=\"login_form_password_email\" value=\"\" class=\"mg-input\"");
      expectHas(test, html, "autocomplete=\"username\" spellcheck=\"false\" required phx-mounted=");
      expectLacks(test, html, "readonly");
    }

    test("login: the password field never carries a value") { test =>
      let html = tLoginHtml(dbOpen(":memory:"), false);
      expectHas(test, html, "<input type=\"password\" name=\"user[password]\" id=\"login_form_password_password\" value=\"\" class=\"mg-input\" autocomplete=\"current-password\" spellcheck=\"false\" required>");
    }

    test("login: the two buttons") { test =>
      let html = tLoginHtml(dbOpen(":memory:"), false);
      expectHas(test, html, "<button class=\"mg-btn w-full mt-2\" name=\"user[remember_me]\" value=\"true\">Log in and stay logged in</button>");
      expectHas(test, html, "<button class=\"mg-btn ghost w-full mt-2\">Log in only this time</button>");
    }

    test("login: a visitor with a session gets the reauthenticate copy and a read-only email") { test =>
      let html = tLoginHtml(dbOpen(":memory:"), true);
      expectHas(test, html, "You need to reauthenticate to perform sensitive actions on your account.");
      expectLacks(test, html, "Sign up");
      expectLacks(test, html, "Register");
      expectHas(test, html, "<input type=\"email\" name=\"user[email]\" id=\"login_form_password_email\" value=\"me@example.com\" class=\"mg-input\" readonly");
    }

## Log in: the page

    test("login page: a visitor gets the page with the app layout") { test =>
      let db = dbOpen(":memory:");
      let r = tGet(db, null, "/users/log-in");
      expectInt(test, tStatus(r), 200);
      expectHas(test, tBody(r), "id=\"login_form_password\"");
      expectHas(test, tBody(r), "<meta name=\"csrf-token\" content=\"${r.ctx.session.csrf}\">");
      expectHas(test, tBody(r), "<a href=\"/users/log-in\">Log in</a>");
    }

    test("login page: the email flash prefills the field and is spent") { test =>
      let db = dbOpen(":memory:");
      let first = tGet(db, null, "/users/log-in");
      webPutFlash(first.ctx, "email", "typed@example.com");
      webSaveSession(db, first.ctx.session);
      let second = tGet(db, first.ctx, "/users/log-in");
      expectHas(test, tBody(second), "value=\"typed@example.com\"");
      let third = tGet(db, first.ctx, "/users/log-in");
      expectLacks(test, tBody(third), "typed@example.com");
    }

    test("login page: a logged-in user sees their own address, read-only") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "signed@example.com");
      let r = tGet(db, ctx, "/users/log-in");
      expectInt(test, tStatus(r), 200);
      expectHas(test, tBody(r), "You need to reauthenticate");
      expectHas(test, tBody(r), "<input type=\"email\" name=\"user[email]\" id=\"login_form_password_email\" value=\"signed@example.com\"");
      expectLacks(test, tBody(r), "Register");
    }

## The session controller

    test("session: a good password logs in, to /, with Welcome back!") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "good@example.com");
      let r = tLogin(db, "good@example.com", false);
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/");
      expectHas(test, tHeaders(r.resp, "Set-Cookie"), "${webSessionCookieName()}=");
      expectLacks(test, tHeaders(r.resp, "Set-Cookie"), webRememberCookieName());
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens WHERE context = 'session'"), 1);
      let next = tGet(db, r.ctx, "/users/log-in");
      expectHas(test, tBody(next), "Welcome back!");
      expectHas(test, tBody(next), "good@example.com");
    }

    test("session: the flash is spent after one page") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "once@example.com");
      let r = tLogin(db, "once@example.com", false);
      tGet(db, r.ctx, "/users/log-in");
      let again = tGet(db, r.ctx, "/users/log-in");
      expectLacks(test, tBody(again), "Welcome back!");
    }

    test("session: remember me sets the 14-day cookie") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "mine@example.com");
      let r = tLogin(db, "mine@example.com", true);
      expectInt(test, tStatus(r), 303);
      expectHas(test, tHeaders(r.resp, "Set-Cookie"), "${webRememberCookieName()}=");
      expectHas(test, tHeaders(r.resp, "Set-Cookie"), "Max-Age=1209600");
    }

    test("session: a wrong password goes back to the form with the flash and the address") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "real@example.com");
      let first = tGet(db, null, "/users/log-in");
      webSaveSession(db, first.ctx.session);
      let r = tPost(db, first.ctx, "/users/log-in", tForm(tUserForm("real@example.com", "not the password")));
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/users/log-in");
      let page = tGet(db, first.ctx, "/users/log-in");
      expectHas(test, tBody(page), "Invalid email or password");
      expectHas(test, tBody(page), "value=\"real@example.com\"");
    }

    test("session: an unknown address gets the same flash") { test =>
      let db = dbOpen(":memory:");
      let first = tGet(db, null, "/users/log-in");
      webSaveSession(db, first.ctx.session);
      let r = tPost(db, first.ctx, "/users/log-in", tForm(tUserForm("nobody@example.com", "123456")));
      expectText(test, tLocation(r), "/users/log-in");
      let page = tGet(db, first.ctx, "/users/log-in");
      expectHas(test, tBody(page), "Invalid email or password");
    }

    test("session: only the first 160 characters of the address are kept") { test =>
      let db = dbOpen(":memory:");
      let first = tGet(db, null, "/users/log-in");
      webSaveSession(db, first.ctx.session);
      let long = tRepeat("a", 200);
      tPost(db, first.ctx, "/users/log-in", tForm(tUserForm(long, "x")));
      let page = tGet(db, first.ctx, "/users/log-in");
      expectHas(test, tBody(page), "value=\"${tRepeat("a", 160)}\"");
      expectLacks(test, tBody(page), tRepeat("a", 161));
    }

    test("session: a request without the fields is a bubble, not a login") { test =>
      let db = dbOpen(":memory:");
      let first = tGet(db, null, "/users/log-in");
      let failed = do { tPost(db, first.ctx, "/users/log-in", "x=y"); false } orelse true;
      expectTrue(test, failed, "bubbled");
    }

    test("session: the stored return-to wins, and is spent") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "back@example.com");
      let denied = tGet(db, null, "/users/settings?bar=baz");
      expectText(test, tLocation(denied), "/users/log-in");
      let r = tPost(db, denied.ctx, "/users/log-in", tForm(tUserForm("back@example.com", tPassword())));
      expectText(test, tLocation(r), "/users/settings?bar=baz");
      let second = tPost(db, r.ctx, "/users/log-in", tForm(tUserForm("back@example.com", tPassword())));
      expectText(test, tLocation(second), "/users/settings");
    }

    test("session: logging out goes to / with Logged out successfully.") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "bye@example.com");
      let r = tDelete(db, ctx, "/users/log-out");
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens"), 0);
      let page = tGet(db, r.ctx, "/users/log-in");
      expectHas(test, tBody(page), "Logged out successfully.");
      expectLacks(test, tBody(page), "bye@example.com");
    }

    test("session: logging out expires the remember-me cookie") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "gone@example.com");
      let login = tLogin(db, "gone@example.com", true);
      let r = tDelete(db, login.ctx, "/users/log-out");
      expectHas(test, tHeaders(r.resp, "Set-Cookie"), webRememberCookieName());
      expectHas(test, tHeaders(r.resp, "Set-Cookie"), "Max-Age=0");
    }

    test("session: logging out with no session still redirects to /") { test =>
      let db = dbOpen(":memory:");
      let r = tDelete(db, null, "/users/log-out");
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/");
      let page = tGet(db, r.ctx, "/users/log-in");
      expectHas(test, tBody(page), "Logged out successfully.");
    }

    test("session: a form posting to /users/log-out is the same action") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "form@example.com");
      let r = tPost(db, ctx, "/users/log-out", "_method=delete");
      expectText(test, tLocation(r), "/");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens"), 0);
    }

## Registration: the markup

    let tRegistrationHtml(db: Db, state: UsersRegistrationState): String throws Bubble {
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", "/users/register", "", ""), new MapBuilder<String, String>().toMap());
      hjoin(renderUsersRegistration(ctx, state))
    }

    test("registration: the container, header and subtitle") { test =>
      let html = tRegistrationHtml(dbOpen(":memory:"), loadUsersRegistration());
      expectHas(test, html, "<div class=\"mx-auto max-w-sm px-6 py-16\">");
      expectHas(test, html, "<div class=\"text-center\">");
      expectHas(test, html, "<h1 class=\"text-lg font-semibold leading-8\">Register for an account</h1>");
      expectHas(test, html, "Already registered? ");
      expectHas(test, html, "<a href=\"/users/log-in\" class=\"font-semibold text-[var(--mg-accent)] hover:underline\">Log in</a>");
      expectHas(test, html, " to your account now.");
    }

    test("registration: the form keeps its events and posts when there is no client") { test =>
      let html = tRegistrationHtml(dbOpen(":memory:"), loadUsersRegistration());
      expectHas(test, html, "<form id=\"registration_form\" action=\"/users/register\" method=\"post\" phx-submit=\"save\" phx-change=\"validate\">");
      expectHas(test, html, "name=\"_csrf_token\"");
    }

    test("registration: email and password fields, no confirmation") { test =>
      let html = tRegistrationHtml(dbOpen(":memory:"), loadUsersRegistration());
      expectHas(test, html, "<input type=\"email\" name=\"user[email]\" id=\"registration_form_email\" value=\"\" class=\"mg-input\" autocomplete=\"username\" spellcheck=\"false\" required phx-mounted=");
      expectHas(test, html, "<input type=\"password\" name=\"user[password]\" id=\"registration_form_password\" value=\"\" class=\"mg-input\" autocomplete=\"new-password\" spellcheck=\"false\" required>");
      expectLacks(test, html, "password_confirmation");
    }

    test("registration: the submit button") { test =>
      let html = tRegistrationHtml(dbOpen(":memory:"), loadUsersRegistration());
      expectHas(test, html, "<button class=\"mg-btn w-full mt-2\" phx-disable-with=\"Creating account...\">Create an account</button>");
    }

    test("registration: errors sit under their field, with the icon and the accent border") { test =>
      let state = new UsersRegistrationState("with spaces", ["must have the @ sign and no spaces"], ["can't be blank"]);
      let html = tRegistrationHtml(dbOpen(":memory:"), state);
      expectHas(test, html, "must have the @ sign and no spaces");
      expectHas(test, html, "can&#39;t be blank");
      expectHas(test, html, "<p class=\"mt-1.5 flex gap-2 items-center text-sm text-error\"><span class=\"hero-exclamation-circle size-5\"></span>");
      expectHas(test, html, "class=\"mg-input border-[var(--mg-accent)]\"");
      expectHas(test, html, "value=\"with spaces\"");
    }

## Registration: the page and events

    test("register page: a visitor gets the form") { test =>
      let db = dbOpen(":memory:");
      let r = tGet(db, null, "/users/register");
      expectInt(test, tStatus(r), 200);
      expectHas(test, tBody(r), "Register for an account");
    }

    test("register page: someone with a user is sent to /") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "in@example.com");
      let r = tGet(db, ctx, "/users/register");
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/");
    }

    test("register page: a guest is sent to / too, as in the Elixir") { test =>
      let db = dbOpen(":memory:");
      let ctx = tGuestCtx(db);
      let r = tGet(db, ctx, "/users/register");
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/");
    }

    test("validate: a bad email shows its message, an untouched password does not") { test =>
      let db = dbOpen(":memory:");
      let r = tEvent(db, null, "/users/register", "validate", "{\"user\":{\"email\":\"with spaces\"}}");
      expectInt(test, tStatus(r), 200);
      expectHas(test, tBody(r), "must have the @ sign and no spaces");
      expectLacks(test, tBody(r), "can&#39;t be blank");
      expectHas(test, tBody(r), "\"regions\"");
    }

    test("validate: the flat shape the client sends works the same") { test =>
      let db = dbOpen(":memory:");
      let r = tEvent(db, null, "/users/register", "validate", "{\"user[email]\":\"with spaces\",\"user[password]\":\"\",\"_target\":[\"user[email]\"]}");
      expectHas(test, tBody(r), "must have the @ sign and no spaces");
      expectLacks(test, tBody(r), "can&#39;t be blank");
    }

    test("validate: a short password is reported once it has something in it") { test =>
      let db = dbOpen(":memory:");
      let r = tEvent(db, null, "/users/register", "validate", "{\"user\":{\"email\":\"a@b.co\",\"password\":\"short\"}}");
      expectHas(test, tBody(r), "should be at least 12 character(s)");
    }

    test("validate: no uniqueness check while typing") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "taken@example.com");
      let r = tEvent(db, null, "/users/register", "validate", "{\"user\":{\"email\":\"taken@example.com\"}}");
      expectLacks(test, tBody(r), "has already been taken");
    }

    test("save: creates a confirmed account and sends the visitor to log in") { test =>
      let db = dbOpen(":memory:");
      let r = tEvent(db, null, "/users/register", "save", "{\"user\":{\"email\":\"new@example.com\",\"password\":\"hello world!\"}}");
      expectHas(test, tBody(r), "\"redirect\":\"/users/log-in\"");
      let user = accountsGetUserByEmail(db, "new@example.com");
      expectTrue(test, user != null, "the user exists");
      if (user != null) {
        expectTrue(test, user.confirmedAt != null, "confirmed");
        expectTrue(test, user.hashedPassword != null, "hashed");
        expectTrue(test, !user.isGuest, "not a guest");
      }
      let page = tGet(db, r.ctx, "/users/log-in");
      expectHas(test, tBody(page), "Account created. Log in to get started.");
      expectHas(test, tBody(page), "value=\"new@example.com\"");
    }

    test("save: a blank password is can't be blank") { test =>
      let db = dbOpen(":memory:");
      let r = tEvent(db, null, "/users/register", "save", "{\"user\":{\"email\":\"np@example.com\",\"password\":\"\"}}");
      expectHas(test, tBody(r), "can&#39;t be blank");
      expectTrue(test, accountsGetUserByEmail(db, "np@example.com") == null, "no user");
    }

    test("save: a taken email is has already been taken") { test =>
      let db = dbOpen(":memory:");
      tMakeUser(db, "dup@example.com");
      let r = tEvent(db, null, "/users/register", "save", "{\"user\":{\"email\":\"dup@example.com\",\"password\":\"hello world!\"}}");
      expectHas(test, tBody(r), "has already been taken");
    }

    test("save: someone with a user is sent to / and nothing is made") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "had@example.com");
      let r = tEvent(db, ctx, "/users/register", "save", "{\"user\":{\"email\":\"other@example.com\",\"password\":\"hello world!\"}}");
      expectHas(test, tBody(r), "\"redirect\":\"/\"");
      expectTrue(test, accountsGetUserByEmail(db, "other@example.com") == null, "no user");
    }

    test("register POST: the plain form does the same, with a 303") { test =>
      let db = dbOpen(":memory:");
      let first = tGet(db, null, "/users/register");
      webSaveSession(db, first.ctx.session);
      let r = tPost(db, first.ctx, "/users/register", tForm(tUserForm("plain@example.com", tPassword())));
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/users/log-in");
      expectTrue(test, accountsGetUserByEmail(db, "plain@example.com") != null, "the user exists");
    }

    test("register POST: invalid data re-renders the whole page with the errors") { test =>
      let db = dbOpen(":memory:");
      let first = tGet(db, null, "/users/register");
      webSaveSession(db, first.ctx.session);
      let r = tPost(db, first.ctx, "/users/register", tForm(tUserForm("with spaces", "")));
      expectInt(test, tStatus(r), 200);
      expectHas(test, tBody(r), "<!DOCTYPE html>");
      expectHas(test, tBody(r), "must have the @ sign and no spaces");
      expectHas(test, tBody(r), "can&#39;t be blank");
    }

    test("an event the page does not have is a bubble") { test =>
      let db = dbOpen(":memory:");
      let failed = do { tEvent(db, null, "/users/register", "nope", "{}"); false } orelse true;
      expectTrue(test, failed, "bubbled");
    }

    test("the log-in page has no events") { test =>
      let db = dbOpen(":memory:");
      let failed = do { tEvent(db, null, "/users/log-in", "submit_password", "{}"); false } orelse true;
      expectTrue(test, failed, "bubbled");
    }

## Settings: the markup

    let tSettingsHtml(db: Db, state: UsersSettingsState): String throws Bubble {
      let ctx = webNewCtx(db, ":memory:", tRaw("GET", "/users/settings", "", ""), new MapBuilder<String, String>().toMap());
      hjoin(renderUsersSettings(ctx, state))
    }

    let tPlainSettings(): UsersSettingsState {
      new UsersSettingsState("me@example.com", "me@example.com", [], [], [])
    }

    test("settings: the header") { test =>
      let html = tSettingsHtml(dbOpen(":memory:"), tPlainSettings());
      expectHas(test, html, "<div class=\"text-center\">");
      expectHas(test, html, "<h1 class=\"text-lg font-semibold leading-8\">Account Settings</h1>");
      expectHas(test, html, "<p class=\"text-sm text-base-content/70\">Manage your account email address and password settings</p>");
    }

    test("settings: the email form") { test =>
      let html = tSettingsHtml(dbOpen(":memory:"), tPlainSettings());
      expectHas(test, html, "<form id=\"email_form\" phx-submit=\"update_email\" phx-change=\"validate_email\">");
      expectHas(test, html, "<input type=\"email\" name=\"user[email]\" id=\"email_form_email\" value=\"me@example.com\" class=\"mg-input\" autocomplete=\"username\" spellcheck=\"false\" required>");
      expectHas(test, html, "<button class=\"btn mg-btn\" phx-disable-with=\"Changing...\">Change Email</button>");
    }

    test("settings: the divider sits between the forms") { test =>
      let html = tSettingsHtml(dbOpen(":memory:"), tPlainSettings());
      let parts = html.split("<div class=\"divider\"></div>");
      expectInt(test, parts.length, 2);
      expectHas(test, parts.getOr(0, ""), "id=\"email_form\"");
      expectHas(test, parts.getOr(1, ""), "id=\"password_form\"");
    }

    test("settings: the password form posts to the controller and has the hidden email") { test =>
      let html = tSettingsHtml(dbOpen(":memory:"), tPlainSettings());
      expectHas(test, html, "<form id=\"password_form\" action=\"/users/update-password\" method=\"post\" phx-change=\"validate_password\" phx-submit=\"update_password\">");
      expectHas(test, html, "<input name=\"user[email]\" type=\"hidden\" id=\"hidden_user_email\" spellcheck=\"false\" value=\"me@example.com\">");
    }

    test("settings: the password fields") { test =>
      let html = tSettingsHtml(dbOpen(":memory:"), tPlainSettings());
      expectHas(test, html, "<span class=\"mg-label block mb-1.5\">New password</span>");
      expectHas(test, html, "<input type=\"password\" name=\"user[password]\" id=\"password_form_password\" value=\"\" class=\"mg-input\" autocomplete=\"new-password\" spellcheck=\"false\" required>");
      expectHas(test, html, "<span class=\"mg-label block mb-1.5\">Confirm new password</span>");
      expectHas(test, html, "<input type=\"password\" name=\"user[password_confirmation]\" id=\"password_form_password_confirmation\" value=\"\" class=\"mg-input\" autocomplete=\"new-password\" spellcheck=\"false\">");
      expectHas(test, html, "<button class=\"btn mg-btn\" phx-disable-with=\"Saving...\">Save Password</button>");
    }

    test("settings: errors under the fields they belong to") { test =>
      let state = new UsersSettingsState("me@example.com", "bad", ["did not change"], ["should be at least 12 character(s)"], ["does not match password"]);
      let html = tSettingsHtml(dbOpen(":memory:"), state);
      expectHas(test, html, "did not change");
      expectHas(test, html, "should be at least 12 character(s)");
      expectHas(test, html, "does not match password");
      expectHas(test, html, "value=\"bad\"");
    }

## Settings: the page

    test("settings: a real user inside the sudo window gets the page") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "page@example.com");
      let r = tGet(db, ctx, "/users/settings");
      expectInt(test, tStatus(r), 200);
      expectHas(test, tBody(r), "Change Email");
      expectHas(test, tBody(r), "Save Password");
      expectHas(test, tBody(r), "value=\"page@example.com\"");
    }

    test("settings: nobody logged in is sent to log in, and the path is remembered") { test =>
      let db = dbOpen(":memory:");
      let r = tGet(db, null, "/users/settings");
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/users/log-in");
      let page = tGet(db, r.ctx, "/users/log-in");
      expectHas(test, tBody(page), "You must log in to access this page.");
    }

    test("settings: a login older than ten minutes is asked to re-authenticate") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "stale@example.com");
      db.exec("UPDATE users_tokens SET authenticated_at = datetime('now', '-11 minutes')", []);
      let r = tGet(db, ctx, "/users/settings");
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/users/log-in");
      let page = tGet(db, ctx, "/users/log-in");
      expectHas(test, tBody(page), "You must re-authenticate to access this page.");
    }

    test("settings: a login nine minutes old is still inside the window") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "nine@example.com");
      db.exec("UPDATE users_tokens SET authenticated_at = datetime('now', '-9 minutes')", []);
      expectInt(test, tStatus(tGet(db, ctx, "/users/settings")), 200);
    }

## Settings: the email form

    test("validate_email: a bad address") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "ve@example.com");
      let r = tEvent(db, ctx, "/users/settings", "validate_email", "{\"action\":\"update_email\",\"user\":{\"email\":\"with spaces\"}}");
      expectHas(test, tBody(r), "Change Email");
      expectHas(test, tBody(r), "must have the @ sign and no spaces");
    }

    test("update_email: the same address did not change") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "same@example.com");
      let r = tEvent(db, ctx, "/users/settings", "update_email", "{\"user\":{\"email\":\"same@example.com\"}}");
      expectHas(test, tBody(r), "Change Email");
      expectHas(test, tBody(r), "did not change");
    }

    test("update_email: a taken address") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "mine2@example.com");
      tMakeUser(db, "theirs@example.com");
      let r = tEvent(db, ctx, "/users/settings", "update_email", "{\"user\":{\"email\":\"theirs@example.com\"}}");
      expectHas(test, tBody(r), "has already been taken");
    }

    test("update_email: a new address sends the link and changes nothing yet") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "old@example.com");
      let r = tEvent(db, ctx, "/users/settings", "update_email", "{\"user\":{\"email\":\"fresh@example.com\"}}");
      expectHas(test, tBody(r), "A link to confirm your email change has been sent to the new address.");
      expectTrue(test, accountsGetUserByEmail(db, "old@example.com") != null, "the old address still resolves");
      expectTrue(test, accountsGetUserByEmail(db, "fresh@example.com") == null, "the new one does not yet");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM outbox WHERE to_addr = 'fresh@example.com'"), 1);
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens WHERE context = 'change:old@example.com'"), 1);
    }

    test("update_email: the mail names the confirm URL") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "link@example.com");
      tEvent(db, ctx, "/users/settings", "update_email", "{\"user\":{\"email\":\"linked@example.com\"}}");
      let row = db.one("SELECT body FROM outbox", []);
      expectTrue(test, row != null, "a mail");
      expectHas(test, if (row != null) { row.str("body") } else { "" }, "/users/settings/confirm-email/");
    }

    test("update_email: a lapsed sudo window sends the visitor to log in") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "lapse@example.com");
      db.exec("UPDATE users_tokens SET authenticated_at = datetime('now', '-30 minutes')", []);
      let r = tEvent(db, ctx, "/users/settings", "update_email", "{\"user\":{\"email\":\"later@example.com\"}}");
      expectHas(test, tBody(r), "\"redirect\":\"/users/log-in\"");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM sqlite_master WHERE name = 'outbox'"), 0);
    }

## Settings: confirming the address

    let tConfirmToken(db: Db, user: User, newEmail: String): String throws Bubble {
      let renamed = new User(
        user.id, newEmail, user.hashedPassword, user.confirmedAt, user.isAdmin,
        user.llmProvider, user.isGuest, user.seenTours, user.insertedAt, user.updatedAt,
      );
      let mail = accountsDeliverUserUpdateEmailInstructions(db, renamed, user.email, fn (t: String): String { "[T]${t}[T]" });
      mail.body.split("[T]").getOr(1, "")
    }

    test("confirm-email: a good token changes the address, once") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "c1@example.com");
      let user = accountsGetUserByEmail(db, "c1@example.com");
      expectTrue(test, user != null, "user");
      if (user != null) {
        let token = tConfirmToken(db, user, "c1new@example.com");
        let r = tGet(db, ctx, "/users/settings/confirm-email/${token}");
        expectInt(test, tStatus(r), 303);
        expectText(test, tLocation(r), "/users/settings");
        let page = tGet(db, ctx, "/users/settings");
        expectHas(test, tBody(page), "Email changed successfully.");
        expectTrue(test, accountsGetUserByEmail(db, "c1@example.com") == null, "old address gone");
        expectTrue(test, accountsGetUserByEmail(db, "c1new@example.com") != null, "new address present");
        let again = tGet(db, ctx, "/users/settings/confirm-email/${token}");
        expectText(test, tLocation(again), "/users/settings");
        let page2 = tGet(db, ctx, "/users/settings");
        expectHas(test, tBody(page2), "Email change link is invalid or it has expired.");
      }
    }

    test("confirm-email: a bad token is the error flash") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "c2@example.com");
      let r = tGet(db, ctx, "/users/settings/confirm-email/oops");
      expectText(test, tLocation(r), "/users/settings");
      let page = tGet(db, ctx, "/users/settings");
      expectHas(test, tBody(page), "Email change link is invalid or it has expired.");
      expectTrue(test, accountsGetUserByEmail(db, "c2@example.com") != null, "address kept");
    }

    test("confirm-email: nobody logged in is sent to log in") { test =>
      let db = dbOpen(":memory:");
      let r = tGet(db, null, "/users/settings/confirm-email/oops");
      expectText(test, tLocation(r), "/users/log-in");
      let page = tGet(db, r.ctx, "/users/log-in");
      expectHas(test, tBody(page), "You must log in to access this page.");
    }

    test("confirm-email: a lapsed sudo window is asked to re-authenticate, even with a good link") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "c3@example.com");
      db.exec("UPDATE users_tokens SET authenticated_at = datetime('now', '-30 minutes')", []);
      let r = tGet(db, ctx, "/users/settings/confirm-email/anything");
      expectText(test, tLocation(r), "/users/log-in");
      let page = tGet(db, ctx, "/users/log-in");
      expectHas(test, tBody(page), "You must re-authenticate to access this page.");
    }

## Settings: the password form

    test("validate_password: a short password and a confirmation that differs") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "vp@example.com");
      let r = tEvent(db, ctx, "/users/settings", "validate_password", "{\"user\":{\"password\":\"too short\",\"password_confirmation\":\"does not match\"}}");
      expectHas(test, tBody(r), "Save Password");
      expectHas(test, tBody(r), "should be at least 12 character(s)");
      expectHas(test, tBody(r), "does not match password");
    }

    test("validate_password: an untouched confirmation is not scolded") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "vq@example.com");
      let r = tEvent(db, ctx, "/users/settings", "validate_password", "{\"user\":{\"password\":\"a long enough password\",\"password_confirmation\":\"\"},\"_target\":[\"user[password]\"]}");
      expectLacks(test, tBody(r), "does not match password");
    }

    test("update_password: invalid data keeps the form with the errors") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "up@example.com");
      let r = tEvent(db, ctx, "/users/settings", "update_password", "{\"user\":{\"password\":\"too short\",\"password_confirmation\":\"does not match\"}}");
      expectHas(test, tBody(r), "Save Password");
      expectHas(test, tBody(r), "should be at least 12 character(s)");
      expectHas(test, tBody(r), "does not match password");
    }

    test("update_password: a good one changes it, logs the other devices out and this one in again") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "pw@example.com");
      let other = tLogin(db, "pw@example.com", false);
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens"), 2);
      let r = tEvent(db, ctx, "/users/settings", "update_password", "{\"user\":{\"email\":\"pw@example.com\",\"password\":\"a brand new passphrase\",\"password_confirmation\":\"a brand new passphrase\"}}");
      expectHas(test, tBody(r), "\"redirect\":\"/users/settings\"");
      expectInt(test, tCount(db, "SELECT COUNT(*) AS n FROM users_tokens"), 1);
      expectTrue(test, accountsGetUserByEmailAndPassword(db, "pw@example.com", "a brand new passphrase") != null, "new password works");
      expectTrue(test, accountsGetUserByEmailAndPassword(db, "pw@example.com", tPassword()) == null, "old password does not");
      let page = tGet(db, ctx, "/users/settings");
      expectInt(test, tStatus(page), 200);
      expectHas(test, tBody(page), "Password updated successfully!");
      let gone = tGet(db, other.ctx, "/users/settings");
      expectInt(test, tStatus(gone), 303);
      expectText(test, tLocation(gone), "/users/log-in");
    }

    test("update-password POST: the plain form redirects to /users/settings with the flash") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "pp@example.com");
      let r = tPost(db, ctx, "/users/update-password", tForm([
        new Pair("user[email]", "pp@example.com"),
        new Pair("user[password]", "a brand new passphrase"),
        new Pair("user[password_confirmation]", "a brand new passphrase"),
      ]));
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/users/settings");
      let page = tGet(db, ctx, "/users/settings");
      expectHas(test, tBody(page), "Password updated successfully!");
    }

    test("update-password POST: invalid data re-renders the page") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "pq@example.com");
      let r = tPost(db, ctx, "/users/update-password", tForm([
        new Pair("user[password]", "too short"),
        new Pair("user[password_confirmation]", "does not match"),
      ]));
      expectInt(test, tStatus(r), 200);
      expectHas(test, tBody(r), "<!DOCTYPE html>");
      expectHas(test, tBody(r), "should be at least 12 character(s)");
      expectHas(test, tBody(r), "does not match password");
    }

    test("update-password POST: nobody logged in is sent to log in") { test =>
      let db = dbOpen(":memory:");
      let r = tPost(db, null, "/users/update-password", "user%5Bpassword%5D=x");
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/users/log-in");
    }

    test("update-password POST: a guest is sent to register, not let in") { test =>
      let db = dbOpen(":memory:");
      let ctx = tGuestCtx(db);
      let r = tPost(db, ctx, "/users/update-password", "user%5Bpassword%5D=x");
      expectInt(test, tStatus(r), 303);
      expectText(test, tLocation(r), "/users/register");
    }

    test("settings: a guest is sent to register with the keep-your-drafts flash") { test =>
      let db = dbOpen(":memory:");
      let ctx = tGuestCtx(db);
      let r = tGet(db, ctx, "/users/settings");
      expectText(test, tLocation(r), "/users/register");
      let page = tGet(db, ctx, "/users/log-in");
      expectHas(test, tBody(page), "Create an account to keep your drafts.");
    }

    test("update-password POST: a lapsed sudo window is asked to re-authenticate") { test =>
      let db = dbOpen(":memory:");
      let ctx = tLoggedIn(db, "pr@example.com");
      db.exec("UPDATE users_tokens SET authenticated_at = datetime('now', '-30 minutes')", []);
      let r = tPost(db, ctx, "/users/update-password", tForm([
        new Pair("user[password]", "a brand new passphrase"),
        new Pair("user[password_confirmation]", "a brand new passphrase"),
      ]));
      expectText(test, tLocation(r), "/users/log-in");
      expectTrue(test, accountsGetUserByEmailAndPassword(db, "pr@example.com", tPassword()) != null, "password unchanged");
    }
