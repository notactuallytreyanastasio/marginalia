# Log in

`UserLive.Login`. Not a live form any more: `phx-trigger-action` only ever
turned a LiveView submit into a native POST, and the LiveView did no
validation, so the form is an ordinary `method="post"` form to
`POST /users/log-in` (the session controller, in `session.temper.md`).

A visitor who already holds a session, a guest included, gets the
"reauthenticate" copy and a read-only email field holding their own address,
so a guest cannot type an existing account's email here.

    let { Ctx, PageMeta, webMeta, webPage, webCsrfField, cInputSpec, cInput, cButton } = import("webcore/src");
    let { Response } = import("http/src");
    let { h, htext, attr } = import("html/src");

## State

`email` is what the field holds: the address the failed attempt typed (the
`email` flash the controller left), else the session user's, else empty.
`reauth` is true when the visitor already has a user.

    export class UsersLoginState(public email: String, public reauth: Boolean) {}

    export let loadUsersLogin(ctx: Ctx): UsersLoginState {
      let user = ctx.scope.user;
      let flashed = ctx.session.flash.getOr("email", "");
      if (user != null) {
        new UsersLoginState(if (flashed != "") { flashed } else { user.email }, true)
      } else {
        new UsersLoginState(flashed, false)
      }
    }

## Render

    let puLoginHint(state: UsersLoginState): List<AnyValue> {
      if (state.reauth) {
        htext("You need to reauthenticate to perform sensitive actions on your account.")
      } else {
        [
          "Don't have an account? ",
          h("a", "${attr("href", "/users/register")}${attr("class", "font-semibold text-[var(--mg-accent)] hover:underline")}", htext("Sign up")),
          " for an account now.",
        ]
      }
    }

`phx-mounted={JS.focus()}`: `blimp.js` focuses an element carrying `phx-mounted`
once, when it first appears.

    let puFocusOnMount(): String {
      attr("phx-mounted", "[[\"focus\",{}]]")
    }

The field ids carry the form's id (`login_form_password_email`), as the
Phoenix test asserts.

    let puLoginEmail(state: UsersLoginState): List<AnyValue> {
      let spec = cInputSpec("user[email]");
      spec.kind = "email";
      spec.id = "login_form_password_email";
      spec.label = "Email";
      spec.value = state.email;
      spec.rest = "${if (state.reauth) { " readonly" } else { "" }}${attr("autocomplete", "username")}${attr("spellcheck", "false")} required${puFocusOnMount()}";
      cInput(spec)
    }

    let puLoginPassword(): List<AnyValue> {
      let spec = cInputSpec("user[password]");
      spec.kind = "password";
      spec.id = "login_form_password_password";
      spec.label = "Password";
      spec.value = "";
      spec.rest = "${attr("autocomplete", "current-password")}${attr("spellcheck", "false")} required";
      cInput(spec)
    }

    export let renderUsersLogin(ctx: Ctx, state: UsersLoginState): List<AnyValue> {
      h("div", attr("class", "mx-auto max-w-sm px-6 py-16 space-y-5"), [
        h("div", "", [
          h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-2xl font-semibold tracking-tight")}", htext("Log in")),
          h("p", attr("class", "mg-hint mt-1.5"), puLoginHint(state)),
        ]),
        h("form", "${attr("id", "login_form_password")}${attr("action", "/users/log-in")}${attr("method", "post")}", [
          webCsrfField(ctx),
          puLoginEmail(state),
          puLoginPassword(),
          h("button", "${attr("class", "mg-btn w-full mt-2")}${attr("name", "user[remember_me]")}${attr("value", "true")}", htext("Log in and stay logged in")),
          h("button", attr("class", "mg-btn ghost w-full mt-2"), htext("Log in only this time")),
        ]),
      ])
    }

## GET /users/log-in

No page title: the tagline stands in.

    export let pagesUsersLoginPage(ctx: Ctx): Response throws Bubble {
      webPage(ctx, webMeta(null), renderUsersLogin(ctx, loadUsersLogin(ctx)), null, "app")
    }
