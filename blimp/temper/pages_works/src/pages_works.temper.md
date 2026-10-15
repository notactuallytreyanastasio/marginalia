# pages_works: routes and dispatch

Three routes, in the order of `router.ex`: the plain `POST /works/new` that
the upload form posts to (it carries the file as well, which the LiveView
could not do without a socket), then the two pages. All three sit in the
guest scope: a visitor with no session is given a guest of their own.

    let { Ctx } = import("webcore/src");
    let { Route, Match, Response } = import("http/src");
    let { JsonObject } = import("std/json");

## Routes

`/works/new` comes before `/works/:id`, which is another group's: the
router tries the groups in order, so a draft whose slug is `new` can not
shadow the form.

    export let pagesWorksRoutes(): List<Route> {
      [
        new Route("POST", "/works/new", "guest.works_create"),
        new Route("GET", "/works", "guest.works_index"),
        new Route("GET", "/works/new", "guest.works_new"),
      ]
    }

## Answering a route

    export let pagesWorksGet(ctx: Ctx, match: Match): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.works_index") {
        pagesWorksIndexPage(ctx)
      } else if (route == "guest.works_new") {
        pagesWorksNewPage(ctx)
      } else if (route == "guest.works_create") {
        pagesWorksCreate(ctx)
      } else {
        console.log("pages_works: no handler for route ${route}");
        bubble()
      }
    }

## Answering an event

`match` is the page the event was sent from. An event the page does not have
is a bug in the page or a stale client: a crash with the names in the log.

    export let pagesWorksEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.works_index") {
        pagesWorksIndexEvent(ctx, event, payload)
      } else if (route == "guest.works_new") {
        pagesWorksNewEvent(ctx, event, payload)
      } else {
        pwUnhandledEvent(match.route.pattern, event)
      }
    }
