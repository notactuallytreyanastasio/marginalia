# Register

`UserLive.Registration`. Open to anyone without a user. The form keeps its
`phx-change="validate"` and `phx-submit="save"` events, and is also a plain
`method="post"` form to `POST /users/register`, so a browser without the
client runtime registers all the same (the client intercepts a form that
carries `phx-submit`; the plain POST is what is left when it does not run).

Both paths end the same way: the account is made (confirmed at once, no
email to wait for), and the visitor is sent to the log-in form with the
address prefilled. Nobody is logged in by registering.

    let { Ctx, webMeta, webPage, webCsrfField, webEventReply, webPutFlash, webRedirect, cInputSpec, cInput, cButton, cHeader } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, htext, attr } = import("html/src");
    let { AccountsError, AccountsResult, accountsRegisterUser, accountsChangeUserRegistration } = import("accounts/src");

## State

The form after a render: what the email field holds and the messages under
each field. The password field is always rendered empty.

    export class UsersRegistrationState(
      public email: String,
      public emailErrors: List<String>,
      public passwordErrors: List<String>,
    ) {}

    export let loadUsersRegistration(): UsersRegistrationState {
      new UsersRegistrationState("", [], [])
    }

The state for a set of params, with the errors of the fields in `used`.

    let puRegistrationState(params: Map<String, String>, errors: List<AccountsError>, used: List<String>): UsersRegistrationState {
      new UsersRegistrationState(
        params.getOr("email", ""),
        pagesUsersShown(errors, used, "email"),
        pagesUsersShown(errors, used, "password"),
      )
    }

## Render

    let puRegistrationEmail(state: UsersRegistrationState): List<AnyValue> {
      let spec = cInputSpec("user[email]");
      spec.kind = "email";
      spec.id = "registration_form_email";
      spec.label = "Email";
      spec.value = state.email;
      spec.errors = state.emailErrors;
      spec.rest = "${attr("autocomplete", "username")}${attr("spellcheck", "false")} required${puFocusOnMount()}";
      cInput(spec)
    }

    let puRegistrationPassword(state: UsersRegistrationState): List<AnyValue> {
      let spec = cInputSpec("user[password]");
      spec.kind = "password";
      spec.id = "registration_form_password";
      spec.label = "Password";
      spec.value = "";
      spec.errors = state.passwordErrors;
      spec.rest = "${attr("autocomplete", "new-password")}${attr("spellcheck", "false")} required";
      cInput(spec)
    }

    let puLoginLink(label: String): List<AnyValue> {
      h("a", "${attr("href", "/users/log-in")}${attr("class", "font-semibold text-[var(--mg-accent)] hover:underline")}", htext(label))
    }

    export let renderUsersRegistration(ctx: Ctx, state: UsersRegistrationState): List<AnyValue> {
      h("div", attr("class", "mx-auto max-w-sm px-6 py-16"), [
        h("div", attr("class", "text-center"), [
          cHeader(
            htext("Register for an account"),
            ["Already registered? ", puLoginLink("Log in"), " to your account now."],
            [],
          ),
        ]),
        h("form", "${attr("id", "registration_form")}${attr("action", "/users/register")}${attr("method", "post")}${attr("phx-submit", "save")}${attr("phx-change", "validate")}", [
          webCsrfField(ctx),
          puRegistrationEmail(state),
          puRegistrationPassword(state),
          cButton(null, null, "mg-btn w-full mt-2", attr("phx-disable-with", "Creating account..."), htext("Create an account")),
        ]),
      ])
    }

## Handlers

The page is shown with `webPage`; an event answers with the re-rendered
`<main>`. A visitor who holds a user, a guest included, never sees the form:
`mount` sent them to `/` (`signed_in_path` of a socket).

    let puRegistrationReply(ctx: Ctx, state: UsersRegistrationState): Response throws Bubble {
      puRender(ctx, renderUsersRegistration(ctx, state), null)
    }

    export let pagesUsersRegistrationPage(ctx: Ctx): Response throws Bubble {
      if (ctx.scope.user != null) { return webRedirect(ctx, "/", null); }
      puRegistrationReply(ctx, loadUsersRegistration())
    }

`validate`: the changeset without the uniqueness check, errors on the fields
in use.

    let puRegistrationValidate(ctx: Ctx, payload: JsonObject): Response throws Bubble {
      let params = pagesUsersParams(payload);
      let errors = accountsChangeUserRegistration(ctx.db, params);
      let used = pagesUsersUsed(params, pagesUsersTarget(payload), false);
      puRegistrationReply(ctx, puRegistrationState(params, errors, used))
    }

`save` and `POST /users/register`: `Accounts.register_user`. On success the
log-in form, with flash `Account created. Log in to get started.` and the
`email` flash it prefills from. On failure the form again, every field the
request carried marked used.

    let puRegister(ctx: Ctx, params: Map<String, String>): Response throws Bubble {
      if (ctx.scope.user != null) { return webRedirect(ctx, "/", null); }
      let registered: AccountsResult = accountsRegisterUser(ctx.db, params);
      let user = registered.ok;
      if (user != null) {
        webPutFlash(ctx, "email", user.email);
        webRedirect(ctx, "/users/log-in", new Pair("info", "Account created. Log in to get started."))
      } else {
        let used = pagesUsersUsed(params, "", true);
        puRegistrationReply(ctx, puRegistrationState(params, registered.errors, used))
      }
    }

    export let pagesUsersRegisterPost(ctx: Ctx): Response throws Bubble {
      let params = new MapBuilder<String, String>();
      let keys = ctx.req.form.keys();
      for (var i = 0; i < keys.length; ++i) {
        let k = keys.getOr(i, "");
        let field = puFieldOf(k);
        if (field != "") { params.set(field, ctx.req.form.getOr(k, "")); }
      }
      puRegister(ctx, params.toMap())
    }

    export let pagesUsersRegistrationEvent(ctx: Ctx, event: String, payload: JsonObject): Response throws Bubble {
      if (ctx.scope.user != null) { return webRedirect(ctx, "/", null); }
      if (event == "validate") {
        puRegistrationValidate(ctx, payload)
      } else if (event == "save") {
        puRegister(ctx, pagesUsersParams(payload))
      } else {
        puUnhandledEvent("/users/register", event)
      }
    }
