# The session controller

`UserSessionController`: the three actions that are not pages.

    let { Ctx, webLogOut, webRedirect, webPutFlash, webSaveSession } = import("webcore/src");
    let { Response } = import("http/src");
    let { accountsGetUserByEmailAndPassword } = import("accounts/src");
    let { sysGraphemeTake } = import("sys/src");

## POST /users/log-in

`user[email]`, `user[password]` and, from the second button, `user[remember_me]`
= `true`. A request without the first two is a bug in the caller and the
Elixir raised (a 500); this stops the same way, with a line in the log.

Success: flash `Welcome back!`, and `webLogIn` decides where to go (the stored
return-to, else `/users/settings` for a visitor who already had a user, else
`/`). Failure: the same flash for an unknown address and a wrong password,
`Invalid email or password`, the first 160 characters of the address kept in
the `email` flash for the form to prefill, back to `/users/log-in`.

    export let pagesUsersLogin(ctx: Ctx): Response throws Bubble {
      let form = ctx.req.form;
      if (!form.has("user[email]") || !form.has("user[password]")) {
        console.log("pages_users: POST /users/log-in without user[email] and user[password]");
        bubble()
      }
      let email = form.getOr("user[email]", "");
      let password = form.getOr("user[password]", "");
      let remember = form.getOr("user[remember_me]", "") == "true";
      let user = accountsGetUserByEmailAndPassword(ctx.db, email, password);
      if (user != null) {
        puLogInWithFlash(ctx, user, remember, "Welcome back!")
      } else {
        webPutFlash(ctx, "email", sysGraphemeTake(email, 160));
        webRedirect(ctx, "/users/log-in", new Pair("error", "Invalid email or password"))
      }
    }

## DELETE /users/log-out

Works for a visitor who is not logged in. The flash goes into the new session
`webLogOut` makes, after it has cleared the old one.

    export let pagesUsersLogout(ctx: Ctx): Response throws Bubble {
      let r = webLogOut(ctx);
      webPutFlash(ctx, "info", "Logged out successfully.");
      webSaveSession(ctx.db, ctx.session);
      r
    }
