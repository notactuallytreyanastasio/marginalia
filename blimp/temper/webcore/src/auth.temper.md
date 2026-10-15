# Auth: the plugs

`MarginaliaWeb.UserAuth` as functions over `Ctx`. A plug that may stop the
request returns `Response?`: a redirect to send instead of the page (already
finished, see `webFinish`), or `null` to go on. The others change the context.
The router applies them by the route name prefix: `public.` mounts the scope,
`guest.` also ensures a user (minting a guest), `real.` requires a real
account.

    let { User, Scope, scopeFor } = import("accounts/src");
    let {
      accountsGetUserBySessionToken, accountsGenerateUserSessionToken,
      accountsGenerateUserSessionTokenAt, accountsDeleteUserSessionToken,
      accountsCreateGuest, accountsSessionNeedsReissue, accountsSessionAuthenticatedAt,
    } = import("accounts/src");
    let { Response, httpRedirect, httpJson } = import("http/src");
    let { urlEncode } = import("http/src");
    let { sysRandomToken } = import("sys/src");

## Session helpers

The session stores the id of the `users_tokens` row, not the token.

    let wcTokenOfId(ctx: Ctx, id: Int): String? throws Bubble {
      let row = ctx.db.one("SELECT token FROM users_tokens WHERE id = $1 AND context = 'session'", [id.toString()]);
      if (row != null) { row.str("token") } else { null }
    }

    let wcIdOfToken(ctx: Ctx, token: String): Int? throws Bubble {
      let row = ctx.db.one("SELECT id FROM users_tokens WHERE token = $1 AND context = 'session'", [token]);
      if (row != null) { row.int("id") } else { null }
    }

`put_token_in_session`.

    let wcAttachToken(ctx: Ctx, token: String): Void throws Bubble {
      ctx.session.userTokenId = wcIdOfToken(ctx, token);
      ctx.session.dirty = true;
    }

`renew_session`: a new session id (the old row is deleted when the session is
saved), and the old cookie value is no longer any use. `clear` empties the
session as `clear_session` did, with a new CSRF token; without it the CSRF
token, the UI state and the flash survive. A mid-flight page keeps working
either way: the page that follows a clearing renewal is rendered after it and
carries the new token.

    let wcRenewSession(ctx: Ctx, clear: Boolean): Void {
      let s = ctx.session;
      if (!s.isNew) { s.oldId = s.id; }
      s.id = sysRandomToken();
      s.isNew = true;
      s.dirty = true;
      s.userTokenId = null;
      if (clear) {
        s.csrf = sysRandomToken();
        s.flash = wcEmptyMap();
        s.ui = wcEmptyMap();
        s.remember = false;
        s.returnTo = null;
      }
    }

`create_or_extend_session`: a token for the user, the session renewed unless
this request is already that user's, the token stored, the remember-me cookie
written when asked or when the session already remembers.

    let wcCreateOrExtendSession(ctx: Ctx, user: User, rememberParam: Boolean, clear: Boolean): Void throws Bubble {
      let token = accountsGenerateUserSessionToken(ctx.db, user);
      let rememberMe = ctx.session.remember;
      let current = ctx.scope.user;
      let same = current != null && current.id == user.id;
      if (!same) {
        let keepFlash = ctx.session.flash;
        wcRenewSession(ctx, clear);
        if (!clear) { ctx.session.flash = keepFlash; }
      }
      wcAttachToken(ctx, token);
      if (rememberParam || rememberMe) {
        ctx.session.remember = true;
        ctx.session.rememberCookie = token;
      }
    }

## Where the request is

`current_path`: the path and, if there is one, the query string.

    export let webCurrentPath(ctx: Ctx): String {
      let q = ctx.req.query;
      let ks = q.keys();
      if (ks.length == 0) { return ctx.req.path; }
      let parts = new ListBuilder<String>();
      for (var i = 0; i < ks.length; ++i) {
        let k = ks.getOr(i, "");
        parts.add("${urlEncode(k)}=${urlEncode(q.getOr(k, ""))}");
      }
      "${ctx.req.path}?${parts.toList().join("&") { (p: String): String => p }}"
    }

`maybe_store_return_to`: a denied GET is remembered for after the login.

    let wcStoreReturnTo(ctx: Ctx): Void {
      if (ctx.req.method == "GET" && !ctx.isAjax) {
        ctx.session.returnTo = webCurrentPath(ctx);
        ctx.session.dirty = true;
      }
    }

## fetch_current_scope_for_user

Finds the user: from the session's token, or failing that from the remember-me
cookie (whose value is the session token; the token is already unguessable and
checked against the database, so the cookie is not additionally signed). A
token that matches nothing leaves the scope empty and the session as it was.
A token seven days old or older is replaced by a fresh one that inherits its
`authenticated_at`; the old row ages out on its own.

    export let webMountCurrentScope(ctx: Ctx): Void throws Bubble {
      var token: String? = null;
      var viaCookie = false;
      let tokenId = ctx.session.userTokenId;
      if (tokenId != null) { token = wcTokenOfId(ctx, tokenId); }
      if (token == null) {
        let c = ctx.req.cookies.getOr(webRememberCookieName(), "");
        if (c != "") {
          token = c;
          viaCookie = true;
        }
      }
      let t = token;
      if (t != null) { wcMountToken(ctx, t, viaCookie); }
    }

    let wcMountToken(ctx: Ctx, t: String, viaCookie: Boolean): Void throws Bubble {
      let found = accountsGetUserBySessionToken(ctx.db, t);
      if (found != null) {
        let user: User = found.key;
        let insertedAt: String = found.value;
        if (viaCookie) {
          wcAttachToken(ctx, t);
          ctx.session.remember = true;
        }
        ctx.scope = scopeFor(user);
        if (accountsSessionNeedsReissue(ctx.db, insertedAt)) {
          let authAt = accountsSessionAuthenticatedAt(ctx.db, t);
          let fresh = if (authAt != null) {
            accountsGenerateUserSessionTokenAt(ctx.db, user, authAt)
          } else {
            accountsGenerateUserSessionToken(ctx.db, user)
          };
          wcAttachToken(ctx, fresh);
          if (ctx.session.remember) { ctx.session.rememberCookie = fresh; }
        }
      }
    }

## ensure_user_or_guest

Nothing to do when there is a user. Otherwise a guest account is made and
logged in (a session token, no remember-me cookie, so the guest lives and dies
with the session cookie). The session id is renewed but its CSRF token, UI state
and flash are kept: the visitor's page was rendered with that token and its
next form or event must still pass. When the account cannot be made: flash
`Something went wrong. Try logging in.` and a redirect to `/users/log-in`.

    export let webEnsureUserOrGuest(ctx: Ctx): Response? throws Bubble {
      if (ctx.scope.user != null) { return null; }
      var guest: User? = null;
      do { guest = accountsCreateGuest(ctx.db); } orelse null;
      let g = guest;
      if (g != null) {
        wcCreateOrExtendSession(ctx, g, false, false);
        ctx.scope = scopeFor(g);
        null
      } else {
        console.log("marginalia: could not create a guest account");
        webPutFlash(ctx, "error", "Something went wrong. Try logging in.");
        webRedirect(ctx, "/users/log-in", null)
      }
    }

## require_real_account

* no user: flash error `You must log in to access this page.`, the path of a
  GET stored for after the login, redirect to `/users/log-in`;
* a guest: flash info `Create an account to keep your drafts.`, redirect to
  `/users/register`;
* otherwise go on.

<!-- -->

    export let webRequireRealAccount(ctx: Ctx): Response? throws Bubble {
      let user = ctx.scope.user;
      if (user == null) {
        webPutFlash(ctx, "error", "You must log in to access this page.");
        wcStoreReturnTo(ctx);
        webRedirect(ctx, "/users/log-in", null)
      } else if (user.isGuest) {
        webPutFlash(ctx, "info", "Create an account to keep your drafts.");
        webRedirect(ctx, "/users/register", null)
      } else {
        null
      }
    }

`require_authenticated_user`: any user, a guest included.

    export let webRequireAuthenticated(ctx: Ctx): Response? throws Bubble {
      if (ctx.scope.user != null) { return null; }
      webPutFlash(ctx, "error", "You must log in to access this page.");
      wcStoreReturnTo(ctx);
      webRedirect(ctx, "/users/log-in", null)
    }

The registration page sends anyone who holds a user, a guest included, to `/`
(its mount did `redirect(to: signed_in_path(socket))`, which is `/` for a
socket). The login page does not use this: it shows the "reauthenticate" copy
to a logged-in visitor.

    export let webRedirectIfAuthenticated(ctx: Ctx): Response? throws Bubble {
      if (ctx.scope.user != null) { webRedirect(ctx, "/", null) } else { null }
    }

## Log in and out

`signed_in_path`: `/users/settings` if the request already had a user (a guest
logging in), else `/`. `log_in_user` reads the stored return-to first, then
creates the session (a login clears the old session: a new id, a new CSRF
token), then redirects there. The `live_socket_id` broadcast has no equivalent:
there are no sockets to disconnect, and a deleted token stops working on the
next request.

    export let webLogIn(ctx: Ctx, user: User, remember: Boolean): Response throws Bubble {
      let returnTo = ctx.session.returnTo;
      let signedIn = if (ctx.scope.user != null) { "/users/settings" } else { "/" };
      wcCreateOrExtendSession(ctx, user, remember, true);
      ctx.session.returnTo = null;
      ctx.session.dirty = true;
      webRedirect(ctx, if (returnTo != null) { returnTo } else { signedIn }, null)
    }

`log_out_user`: the token is deleted, the session renewed and cleared, the
remember-me cookie deleted, and the visitor sent to `/`. With no session it
still redirects.

    export let webLogOut(ctx: Ctx): Response throws Bubble {
      let tokenId = ctx.session.userTokenId;
      if (tokenId != null) {
        let token = wcTokenOfId(ctx, tokenId);
        if (token != null) { accountsDeleteUserSessionToken(ctx.db, token); }
      }
      let c = ctx.req.cookies.getOr(webRememberCookieName(), "");
      if (c != "") { accountsDeleteUserSessionToken(ctx.db, c); }
      wcRenewSession(ctx, true);
      ctx.scope = scopeFor(null);
      ctx.session.clearRememberCookie = true;
      webRedirect(ctx, "/", null)
    }
