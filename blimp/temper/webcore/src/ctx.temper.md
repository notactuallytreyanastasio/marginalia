# The request context, the session, CSRF

Every request gets one `Ctx`. There is no socket and no process to keep state in,
so the little that Phoenix kept in the cookie, in `socket.assigns` and in the
LiveView process lives in one row of the `sessions` table, found by the cookie.

    let { Db, DbRow } = import("db/src");
    let { Request, Response, httpWithCookie, httpClearCookie, httpText } = import("http/src");
    let { Scope, noScope } = import("accounts/src");
    let { sysRandomToken, sysConstantTimeEq, sysUtcNow } = import("sys/src");
    let { attr, hv } = import("html/src");
    let { JsonSyntaxTree, JsonObject, JsonString, JsonBoolean, JsonTextProducer,
          NullInterchangeContext, parseJson } = import("std/json");

## Names

    export let webSessionCookieName(): String { "_marginalia_key" }
    export let webRememberCookieName(): String { "_marginalia_web_user_remember_me" }

The remember-me cookie lasts 14 days (1,209,600 s): `UserAuth`'s
`@max_cookie_age_in_days`, and what `blimp/test/e2e/10_accounts.sh` asserts.

    export let webRememberMaxAge(): Int { 1209600 }

## Small helpers

Every top-level name in this library is shared by all of its files, so the
private helpers all start with `wc`.

    let wcStartsWith(s: String, prefix: String): Boolean {
      if (s == "" || prefix == "") { return false; }
      let parts = s.split(prefix);
      parts.length > 1 && parts.getOr(0, "x") == ""
    }

    let wcOr(s: String?, fallback: String): String {
      if (s != null) { s } else { fallback }
    }

    let wcMapPut(m: Map<String, String>, key: String, value: String): Map<String, String> {
      let out = new MapBuilder<String, String>();
      let ks = m.keys();
      for (var i = 0; i < ks.length; ++i) {
        let k = ks.getOr(i, "");
        if (k != key) { out.set(k, m.getOr(k, "")); }
      }
      out.set(key, value);
      out.toMap()
    }

    let wcMapDel(m: Map<String, String>, key: String): Map<String, String> {
      let out = new MapBuilder<String, String>();
      let ks = m.keys();
      for (var i = 0; i < ks.length; ++i) {
        let k = ks.getOr(i, "");
        if (k != key) { out.set(k, m.getOr(k, "")); }
      }
      out.toMap()
    }

    let wcEmptyMap(): Map<String, String> {
      new MapBuilder<String, String>().toMap()
    }

## The session

One row of `sessions`: `id` is the cookie value, `user_token_id` the
`users_tokens` row of the logged-in user (the database nulls it when the token
is deleted), `data` a JSON object:

{"csrf": "...", "flash": {"info": "..."}, "ui": {"work:view": "spine"}, "remember": true, "return_to": "/works/x?y=1"}

The Phoenix cookie was a signed copy of the session. Here the cookie value is
`sysRandomToken()` (32 random bytes, url-safe): an unguessable id, so there is
nothing to sign, and the contents never leave the server. An id that is not in
the table is not adopted: the visitor gets a fresh session and a fresh id, so a
planted cookie value cannot fix a session.

Fields are `var` because the plugs change them in place; every change sets
`dirty`, and `webSaveSession` writes only a dirty or new session. `isNew` means
the cookie must be sent. `rememberCookie` is a token to put in the remember-me
cookie on this response; `clearRememberCookie` deletes it. `oldId` is a session
row to delete when the id was renewed.

    export class Session(
      public var id: String,
      public var isNew: Boolean,
      public var userTokenId: Int?,
      public var flash: Map<String, String>,
      public var csrf: String,
      public var ui: Map<String, String>,
      public var remember: Boolean,
      public var returnTo: String?,
      public var dirty: Boolean,
      public var rememberCookie: String?,
      public var clearRememberCookie: Boolean,
      public var oldId: String?,
    ) {}

    export let webNewSession(): Session {
      new Session(
        sysRandomToken(), true, null, wcEmptyMap(), sysRandomToken(), wcEmptyMap(),
        false, null, true, null, false, null,
      )
    }

## The context

`isAjax` is true for an event (`POST /ev/<name>`) and a poll (`GET` with
`x-requested-with: blimp`): they are answered with JSON, not a page. `scope`
starts as `noScope()`; `webMountCurrentScope` and `webEnsureUserOrGuest` set it.

    export class Ctx(
      public db: Db,
      public dbPath: String,
      public req: Request,
      public var scope: Scope,
      public session: Session,
      public params: Map<String, String>,
      public now: String,
      public isAjax: Boolean,
    ) {}

    export let webIsAjaxRequest(req: Request): Boolean {
      let v = req.header("x-requested-with");
      v != null && v == "blimp"
    }

Loads the session for the request and builds the context.

    export let webNewCtx(db: Db, dbPath: String, req: Request, params: Map<String, String>): Ctx throws Bubble {
      new Ctx(db, dbPath, req, noScope(), webLoadSession(db, req), params, sysUtcNow(), webIsAjaxRequest(req))
    }

## Reading and writing the data column

    let wcWriteStringMap(p: JsonTextProducer, m: Map<String, String>): Void {
      p.startObject();
      let ks = m.keys();
      for (var i = 0; i < ks.length; ++i) {
        let k = ks.getOr(i, "");
        p.objectKey(k);
        p.stringValue(m.getOr(k, ""));
      }
      p.endObject();
    }

    export let webSessionData(s: Session): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      p.objectKey("csrf");
      p.stringValue(s.csrf);
      p.objectKey("flash");
      wcWriteStringMap(p, s.flash);
      p.objectKey("remember");
      p.booleanValue(s.remember);
      let rt = s.returnTo;
      if (rt != null) {
        p.objectKey("return_to");
        p.stringValue(rt);
      }
      p.objectKey("ui");
      wcWriteStringMap(p, s.ui);
      p.endObject();
      p.toJsonString()
    }

    let wcReadStringMap(t: JsonSyntaxTree?): Map<String, String> {
      let out = new MapBuilder<String, String>();
      if (t is JsonObject) {
        let ks = t.properties.keys();
        for (var i = 0; i < ks.length; ++i) {
          let k = ks.getOr(i, "");
          let v = t.propertyValueOrNull(k);
          if (v is JsonString) { out.set(k, v.content); }
        }
      }
      out.toMap()
    }

    let wcField(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

    let wcSessionFromRow(row: DbRow): Session throws Bubble {
      let tree: JsonSyntaxTree? = parseJson(row.str("data")) orelse null;
      let csrfTree = wcField(tree, "csrf");
      var csrf = "";
      if (csrfTree is JsonString) { csrf = csrfTree.content; }
      var remember = false;
      let remTree = wcField(tree, "remember");
      if (remTree is JsonBoolean) { remember = remTree.content; }
      var returnTo: String? = null;
      let rtTree = wcField(tree, "return_to");
      if (rtTree is JsonString) { returnTo = rtTree.content; }
      let s = new Session(
        row.str("id"), false, row.intOrNull("user_token_id"),
        wcReadStringMap(wcField(tree, "flash")), csrf, wcReadStringMap(wcField(tree, "ui")),
        remember, returnTo, false, null, false, null,
      );
      if (csrf == "") {
        s.csrf = sysRandomToken();
        s.dirty = true;
      }
      s
    }

## Load and save

A request with no cookie, or a cookie that matches no row, gets a new session
(not stored until `webSaveSession`).

    export let webLoadSession(db: Db, req: Request): Session throws Bubble {
      let cookie = req.cookies.getOr(webSessionCookieName(), "");
      if (cookie != "") {
        let row = db.one("SELECT id, user_token_id, data FROM sessions WHERE id = $1", [cookie]);
        if (row != null) { return wcSessionFromRow(row); }
      }
      webNewSession()
    }

Writes the row when the session is new or changed, and deletes the row of a
renewed id.

    export let webSaveSession(db: Db, s: Session): Void throws Bubble {
      if (!s.dirty && !s.isNew) { return; }
      let old = s.oldId;
      if (old != null) {
        db.exec("DELETE FROM sessions WHERE id = $1", [old]);
        s.oldId = null;
      }
      let tokenId = s.userTokenId;
      let tokenParam: String? = if (tokenId != null) { tokenId.toString() } else { null };
      let now = sysUtcNow();
      db.exec(
        "INSERT INTO sessions (id, user_token_id, data, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $4) ON CONFLICT(id) DO UPDATE SET user_token_id = excluded.user_token_id, data = excluded.data, updated_at = excluded.updated_at",
        [s.id, tokenParam, webSessionData(s), now],
      );
      s.dirty = false;
    }

Anonymous sessions pile up (every cookieless request makes one; a crawler makes
many). This deletes the logged-out ones not touched for `days` days and returns
how many went. Nothing calls it on a schedule yet.

    export let webPruneSessions(db: Db, days: Int): Int throws Bubble {
      db.exec(
        "DELETE FROM sessions WHERE user_token_id IS NULL AND updated_at < datetime('now', '-${days.toString()} days')",
        [],
      )
    }

## Finishing a response

Every `Response` that webcore returns has been through here: the session is
saved and the cookies are on it. A caller (the router) sends it as it is and
does not finish it again.

    export let webFinish(ctx: Ctx, r: Response): Response throws Bubble {
      let s = ctx.session;
      webSaveSession(ctx.db, s);
      var out = r;
      if (s.isNew) { out = httpWithCookie(out, webSessionCookieName(), s.id, null, true); }
      let rc = s.rememberCookie;
      if (rc != null) {
        out = httpWithCookie(out, webRememberCookieName(), rc, webRememberMaxAge(), true);
        s.rememberCookie = null;
      }
      if (s.clearRememberCookie) {
        out = httpClearCookie(out, webRememberCookieName());
        s.clearRememberCookie = false;
      }
      out
    }

## CSRF

One token per session, made with the session and kept in its data. Every
state-changing request must carry it: a form posts it as `_csrf_token`, the
client runtime sends it as `x-csrf-token` (read from the layout's
`<meta name="csrf-token">`).

    export let webCsrfToken(ctx: Ctx): String { ctx.session.csrf }

The hidden input every form needs.

    export let webCsrfField(ctx: Ctx): List<AnyValue> {
      hv("input", "${attr("type", "hidden")}${attr("name", "_csrf_token")}${attr("value", ctx.session.csrf)}")
    }

    let wcIsUnsafeMethod(m: String): Boolean {
      m == "POST" || m == "PUT" || m == "PATCH" || m == "DELETE"
    }

`null` when the request may go on: a GET or HEAD, or a write carrying the
right token. Otherwise a 403 with the body `invalid CSRF token`. The comparison
is constant-time.

    export let webCheckCsrf(ctx: Ctx): Response? {
      if (!wcIsUnsafeMethod(ctx.req.method)) { return null; }
      let want = ctx.session.csrf;
      let fromForm = ctx.req.form.getOr("_csrf_token", "");
      let fromHeader = wcOr(ctx.req.header("x-csrf-token"), "");
      let presented = if (fromHeader != "") { fromHeader } else { fromForm };
      if (presented != "" && want != "" && sysConstantTimeEq(presented, want)) {
        null
      } else {
        httpText(403, "invalid CSRF token")
      }
    }
