# Settings

`UserLive.Settings`: change the email address, change the password. The router
has already required a real (non-guest) account; this page also requires sudo
mode, a login no more than ten minutes old, and sends anyone else to the log-in
form with `You must re-authenticate to access this page.` (no return-to is
stored, as in `on_mount :require_sudo_mode`).

The email form is `phx-change="validate_email"` / `phx-submit="update_email"`.
The password form is `phx-change="validate_password"` /
`phx-submit="update_password"` and also a plain `method="post"` form to
`POST /users/update-password`: Phoenix validated over the socket and then
triggered a native POST to the controller, which is the one place the password
is changed. Here the `update_password` event does the same work in one step
(through `puChangePassword`, which the controller route shares), and the plain
POST is what a browser without the client runtime sends.

    let { Ctx, webMeta, webPage, webCsrfField, webRedirect, webAbsolute, cInputSpec, cInput, cButton, cHeader } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, hv, htext, attr } = import("html/src");
    let {
      User, AccountsError, AccountsResult, accountsSudoModeWithin, accountsChangeUserEmail,
      accountsChangeUserPassword, accountsDeliverUserUpdateEmailInstructions,
      accountsUpdateUserEmail, accountsUpdateUserPassword,
    } = import("accounts/src");

## Sudo mode

When the session's token was made by a login: the `authenticated_at` of the
`users_tokens` row the session holds. Ten minutes, as `require_sudo_mode` asked.

    let puSudo(ctx: Ctx): Boolean throws Bubble {
      let id = ctx.session.userTokenId;
      if (id != null) {
        let row = ctx.db.one("SELECT authenticated_at FROM users_tokens WHERE id = $1", [id.toString()]);
        if (row != null) { accountsSudoModeWithin(row.strOrNull("authenticated_at"), -10) } else { false }
      } else { false }
    }

    let puReauthenticate(ctx: Ctx): Response throws Bubble {
      webRedirect(ctx, "/users/log-in", new Pair("error", "You must re-authenticate to access this page."))
    }

The plug put a real user here; a missing one is a bug in the router.

    let puSettingsUser(ctx: Ctx): User throws Bubble {
      let u = ctx.scope.user;
      if (u != null) { u } else { bubble() }
    }

## State

`email` is what the email field holds. The password fields are always empty.

    export class UsersSettingsState(
      public currentEmail: String,
      public email: String,
      public emailErrors: List<String>,
      public passwordErrors: List<String>,
      public confirmationErrors: List<String>,
    ) {}

    export let loadUsersSettings(user: User): UsersSettingsState {
      new UsersSettingsState(user.email, user.email, [], [], [])
    }

## Render

    let puSettingsEmailInput(state: UsersSettingsState): List<AnyValue> {
      let spec = cInputSpec("user[email]");
      spec.kind = "email";
      spec.id = "email_form_email";
      spec.label = "Email";
      spec.value = state.email;
      spec.errors = state.emailErrors;
      spec.rest = "${attr("autocomplete", "username")}${attr("spellcheck", "false")} required";
      cInput(spec)
    }

    let puSettingsPasswordInput(state: UsersSettingsState): List<AnyValue> {
      let spec = cInputSpec("user[password]");
      spec.kind = "password";
      spec.id = "password_form_password";
      spec.label = "New password";
      spec.value = "";
      spec.errors = state.passwordErrors;
      spec.rest = "${attr("autocomplete", "new-password")}${attr("spellcheck", "false")} required";
      cInput(spec)
    }

    let puSettingsConfirmationInput(state: UsersSettingsState): List<AnyValue> {
      let spec = cInputSpec("user[password_confirmation]");
      spec.kind = "password";
      spec.id = "password_form_password_confirmation";
      spec.label = "Confirm new password";
      spec.value = "";
      spec.errors = state.confirmationErrors;
      spec.rest = "${attr("autocomplete", "new-password")}${attr("spellcheck", "false")}";
      cInput(spec)
    }

    export let renderUsersSettings(ctx: Ctx, state: UsersSettingsState): List<AnyValue> {
      [
        h("div", attr("class", "text-center"), [
          cHeader(
            htext("Account Settings"),
            htext("Manage your account email address and password settings"),
            [],
          ),
        ]),
        h("form", "${attr("id", "email_form")}${attr("phx-submit", "update_email")}${attr("phx-change", "validate_email")}", [
          webCsrfField(ctx),
          puSettingsEmailInput(state),
          cButton(null, "primary", null, attr("phx-disable-with", "Changing..."), htext("Change Email")),
        ]),
        h("div", attr("class", "divider"), []),
        h("form", "${attr("id", "password_form")}${attr("action", "/users/update-password")}${attr("method", "post")}${attr("phx-change", "validate_password")}${attr("phx-submit", "update_password")}", [
          webCsrfField(ctx),
          hv("input", "${attr("name", "user[email]")}${attr("type", "hidden")}${attr("id", "hidden_user_email")}${attr("spellcheck", "false")}${attr("value", state.currentEmail)}"),
          puSettingsPasswordInput(state),
          puSettingsConfirmationInput(state),
          cButton(null, "primary", null, attr("phx-disable-with", "Saving..."), htext("Save Password")),
        ]),
      ]
    }

## GET /users/settings

    let puSettingsReply(ctx: Ctx, state: UsersSettingsState, flash: Pair<String, String>?): Response throws Bubble {
      puRender(ctx, renderUsersSettings(ctx, state), flash)
    }

    export let pagesUsersSettingsPage(ctx: Ctx): Response throws Bubble {
      if (!puSudo(ctx)) { return puReauthenticate(ctx); }
      puSettingsReply(ctx, loadUsersSettings(puSettingsUser(ctx)), null)
    }

## GET /users/settings/confirm-email/:token

`Accounts.update_user_email`: the token must be a change token for the current
address, under seven days old. Either way the visitor lands on the settings
page with the answer.

    export let pagesUsersConfirmEmail(ctx: Ctx, token: String): Response throws Bubble {
      if (!puSudo(ctx)) { return puReauthenticate(ctx); }
      let result: AccountsResult = accountsUpdateUserEmail(ctx.db, puSettingsUser(ctx), token);
      if (result.ok != null) {
        webRedirect(ctx, "/users/settings", new Pair("info", "Email changed successfully."))
      } else {
        webRedirect(ctx, "/users/settings", new Pair("error", "Email change link is invalid or it has expired."))
      }
    }

## Events

`validate_email`: the changeset without the uniqueness check.

    let puValidateEmail(ctx: Ctx, payload: JsonObject): Response throws Bubble {
      let user = puSettingsUser(ctx);
      let params = pagesUsersParams(payload);
      let errors = accountsChangeUserEmail(ctx.db, user, params, false);
      let used = pagesUsersUsed(params, pagesUsersTarget(payload), false);
      let state = new UsersSettingsState(
        user.email, params.getOr("email", user.email),
        pagesUsersShown(errors, used, "email"), [], [],
      );
      puSettingsReply(ctx, state, null)
    }

The link the mail carries.

    let puConfirmUrl(token: String): String {
      webAbsolute("/users/settings/confirm-email/${token}")
    }

`update_email`: the changeset with uniqueness and "did not change". Valid: a
token is stored and the mail (a row in `outbox`, nothing sends it) names the
new address; the address on the account does not change until the link in it is
visited.

    let puUpdateEmail(ctx: Ctx, payload: JsonObject): Response throws Bubble {
      if (!puSudo(ctx)) { return puReauthenticate(ctx); }
      let user = puSettingsUser(ctx);
      let params = pagesUsersParams(payload);
      let errors = accountsChangeUserEmail(ctx.db, user, params, true);
      let typed = params.getOr("email", user.email);
      if (errors.length > 0) {
        let used = pagesUsersUsed(params, "", true);
        puSettingsReply(ctx, new UsersSettingsState(user.email, typed, pagesUsersShown(errors, used, "email"), [], []), null)
      } else {
        let renamed = new User(
          user.id, typed, user.hashedPassword, user.confirmedAt, user.isAdmin,
          user.llmProvider, user.isGuest, user.seenTours, user.insertedAt, user.updatedAt,
        );
        accountsDeliverUserUpdateEmailInstructions(
          ctx.db, renamed, user.email,
          puConfirmUrl,
        );
        puSettingsReply(
          ctx, new UsersSettingsState(user.email, typed, [], [], []),
          new Pair("info", "A link to confirm your email change has been sent to the new address."),
        )
      }
    }

`validate_password`: the rules without hashing.

    let puValidatePassword(ctx: Ctx, payload: JsonObject): Response throws Bubble {
      let user = puSettingsUser(ctx);
      let params = pagesUsersParams(payload);
      let errors = accountsChangeUserPassword(ctx.db, user, params);
      let used = pagesUsersUsed(params, pagesUsersTarget(payload), false);
      let state = new UsersSettingsState(
        user.email, user.email, [],
        pagesUsersShown(errors, used, "password"),
        pagesUsersShown(errors, used, "password_confirmation"),
      );
      puSettingsReply(ctx, state, null)
    }

The password change, shared by the `update_password` event and the controller
route. Every token the user has is deleted in the same transaction (every
device is logged out), and this device is logged in again with a fresh one and
sent to `/users/settings` (`put_session(:user_return_to, ...)` then `create`).
Invalid: the settings page with the errors, every field that was sent marked
used.

    let puChangePassword(ctx: Ctx, user: User, params: Map<String, String>): Response throws Bubble {
      if (!puSudo(ctx)) { return puReauthenticate(ctx); }
      let result: AccountsResult = accountsUpdateUserPassword(ctx.db, user, params);
      if (result.errors.length > 0) {
        let used = pagesUsersUsed(params, "", true);
        let state = new UsersSettingsState(
          user.email, user.email, [],
          pagesUsersShown(result.errors, used, "password"),
          pagesUsersShown(result.errors, used, "password_confirmation"),
        );
        return puSettingsReply(ctx, state, null);
      }
      let fresh = result.ok;
      if (fresh != null) {
        ctx.session.returnTo = "/users/settings";
        ctx.session.dirty = true;
        puLogInWithFlash(ctx, fresh, false, "Password updated successfully!")
      } else {
        bubble()
      }
    }

    export let pagesUsersUpdatePasswordPost(ctx: Ctx): Response throws Bubble {
      let params = new MapBuilder<String, String>();
      let keys = ctx.req.form.keys();
      for (var i = 0; i < keys.length; ++i) {
        let k = keys.getOr(i, "");
        let field = puFieldOf(k);
        if (field != "") { params.set(field, ctx.req.form.getOr(k, "")); }
      }
      puChangePassword(ctx, puSettingsUser(ctx), params.toMap())
    }

    export let pagesUsersSettingsEvent(ctx: Ctx, event: String, payload: JsonObject): Response throws Bubble {
      if (event == "validate_email") {
        puValidateEmail(ctx, payload)
      } else if (event == "update_email") {
        puUpdateEmail(ctx, payload)
      } else if (event == "validate_password") {
        puValidatePassword(ctx, payload)
      } else if (event == "update_password") {
        puChangePassword(ctx, puSettingsUser(ctx), pagesUsersParams(payload))
      } else {
        puUnhandledEvent("/users/settings", event)
      }
    }
