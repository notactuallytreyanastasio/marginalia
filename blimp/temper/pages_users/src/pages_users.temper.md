# pages_users: routes and dispatch

The router (`web`) takes three things from every page group: its routes in
Phoenix router order, a function that answers a matched route, and a function
that answers an event for a page the group owns.

`pagesUsersGet` answers every matched route of the group whatever its method:
the pages are `GET`, the controller actions are `POST` and `DELETE`. The
router has already run the group's plug (named by the route-name prefix) and
checked the CSRF token of every write.

    let { Ctx } = import("webcore/src");
    let { Route, Match, Response } = import("http/src");
    let { JsonObject } = import("std/json");

## Routes

The order of `lib/marginalia_web/router.ex`: settings and the password change
(a real account), then the pages anyone may see and the controller actions.
`POST /users/register` is not in the Phoenix router: the registration form was
a LiveView event there, and here it is also a plain form post.
`POST /users/log-out` is what a form with `_method=delete` is when the
router does not rewrite the method; the router does, so it reaches the
`DELETE` route, and the `POST` route answers a client that does not.

Names: `real.` needs a real account, `anyone.` mounts the scope and nothing
more.

    export let pagesUsersRoutes(): List<Route> {
      [
        new Route("GET", "/users/settings", "real.users_settings"),
        new Route("GET", "/users/settings/confirm-email/:token", "real.users_confirm_email"),
        new Route("POST", "/users/update-password", "real.users_update_password"),
        new Route("GET", "/users/register", "anyone.users_register"),
        new Route("POST", "/users/register", "anyone.users_register_post"),
        new Route("GET", "/users/log-in", "anyone.users_login"),
        new Route("POST", "/users/log-in", "anyone.users_login_post"),
        new Route("POST", "/users/log-out", "anyone.users_logout_post"),
        new Route("DELETE", "/users/log-out", "anyone.users_logout"),
      ]
    }

## Answering a route

A route name this library does not know is a bug in the router: it stops with
the name in the log.

    export let pagesUsersGet(ctx: Ctx, match: Match): Response throws Bubble {
      let route = match.route.name;
      if (route == "anyone.users_login") {
        pagesUsersLoginPage(ctx)
      } else if (route == "anyone.users_login_post") {
        pagesUsersLogin(ctx)
      } else if (route == "anyone.users_logout" || route == "anyone.users_logout_post") {
        pagesUsersLogout(ctx)
      } else if (route == "anyone.users_register") {
        pagesUsersRegistrationPage(ctx)
      } else if (route == "anyone.users_register_post") {
        pagesUsersRegisterPost(ctx)
      } else if (route == "real.users_settings") {
        pagesUsersSettingsPage(ctx)
      } else if (route == "real.users_confirm_email") {
        pagesUsersConfirmEmail(ctx, match.params.getOr("token", ""))
      } else if (route == "real.users_update_password") {
        pagesUsersUpdatePasswordPost(ctx)
      } else {
        console.log("pages_users: no handler for route ${route}");
        bubble()
      }
    }

## Answering an event

`match` is the page the event was sent from (its path, matched as a `GET`).
The log-in page has no events: its form is a plain post.

    export let pagesUsersEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      let route = match.route.name;
      if (route == "anyone.users_register") {
        pagesUsersRegistrationEvent(ctx, event, payload)
      } else if (route == "real.users_settings") {
        pagesUsersSettingsEvent(ctx, event, payload)
      } else {
        puUnhandledEvent(match.route.pattern, event)
      }
    }
