# pages_stacks: routes and dispatch

The router (`web`) takes three things from every page group: its routes in
Phoenix router order, a function that answers a matched route, and a function
that answers an event for a page the group owns.

    let { Ctx } = import("webcore/src");
    let { Route, Match, Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { Folder } = import("folders/src");

Every top-level name here is shared by this library's files and, in the built
program, with every other library's: the private helpers start with `pk`.

## Routes

All of them sit in the `scope "/"` of `ensure_user_or_guest`: a stranger who
opens `/stacks` is given a guest and sees a list of nothing, so `guest.`.

The order of `lib/marginalia_web/router.ex` is the contract. `/stacks/new` must
come before `/stacks/:id`, or it is a folder called `new`; `/stacks/:id/story`
before `/stacks/:id/:ordinal`, or it is step `story` (and
`String.to_integer("story")` raised). `POST /stacks/new` is not in the Phoenix
router: the form was a LiveView event there, and here it is also a plain post,
because a form without the client runtime would otherwise `GET` the token into
the address bar.

    export let pagesStacksRoutes(): List<Route> {
      [
        new Route("GET", "/stacks", "guest.stacks_index"),
        new Route("GET", "/stacks/new", "guest.stacks_new"),
        new Route("POST", "/stacks/new", "guest.stacks_new_post"),
        new Route("GET", "/stacks/:id", "guest.stacks_show"),
        new Route("GET", "/stacks/:id/story", "guest.stacks_story"),
        new Route("GET", "/stacks/:id/:ordinal", "guest.stacks_step"),
      ]
    }

## Answering a route

`pass` starts a pass over a folder and `importing` starts the import of a
stack; production is `pagesStacksLaunch` and `pagesStacksLaunchImport`. The
tests give ones that run in-process, since `runsStart` refuses `:memory:`.

    export let pagesStacksGet(ctx: Ctx, match: Match): Response throws Bubble {
      pagesStacksGetWith(ctx, match, pagesStacksLaunchImport)
    }

    export let pagesStacksGetWith(
      ctx: Ctx, match: Match,
      importing: fn (Ctx, String, String, String, String, String): Boolean throws Bubble,
    ): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.stacks_index") {
        pagesStacksIndexPage(ctx)
      } else if (route == "guest.stacks_new") {
        pagesStacksNewPage(ctx)
      } else if (route == "guest.stacks_new_post") {
        pagesStacksNewPost(ctx, importing)
      } else if (route == "guest.stacks_show") {
        pagesStacksShowPage(ctx, match.params.getOr("id", ""), null)
      } else if (route == "guest.stacks_story") {
        pagesStacksStoryPage(ctx, match.params.getOr("id", ""))
      } else if (route == "guest.stacks_step") {
        pagesStacksShowPage(ctx, match.params.getOr("id", ""), match.params.getOr("ordinal", ""))
      } else {
        console.log("pages_stacks: no handler for route ${route}");
        bubble()
      }
    }

## Answering an event

`match` is the page the event was sent from (its path, matched as a `GET`).
The step page has no events. An event the page does not have is a crash with
the names in the log.

    export let pagesStacksEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      pagesStacksEventWith(ctx, match, event, payload, pagesStacksLaunch, pagesStacksLaunchImport)
    }

    export let pagesStacksEventWith(
      ctx: Ctx, match: Match, event: String, payload: JsonObject,
      pass: fn (Ctx, String, Folder, Int): Boolean throws Bubble,
      importing: fn (Ctx, String, String, String, String, String): Boolean throws Bubble,
    ): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.stacks_new") {
        pagesStacksNewEvent(ctx, event, payload, importing)
      } else if (route == "guest.stacks_show") {
        pagesStacksShowEvent(ctx, match, event, payload, pass)
      } else if (route == "guest.stacks_story") {
        pagesStacksStoryEvent(ctx, match, event, payload)
      } else {
        pkUnhandledEvent(match.route.pattern, event)
      }
    }
