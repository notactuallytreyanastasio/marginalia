# pages_import: routes and dispatch

Two routes: the wizard, and the plain `POST /import` that the files form sends
(the live upload of the Phoenix app is a form that carries its files here). Both
sit in the guest scope: a stranger who opens `/import` is given a guest of their
own and can import into it.

    let { Ctx } = import("webcore/src");
    let { Route, Match, Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { ImporterHttp, importerRealHttp } = import("importer/src");

Every top-level name in this library is shared by its files and, in the built
program, with every other library's: the private helpers start with `pim`.

## Routes

`live "/import"` comes after `/works/new` and before `/works/:id` in
`router.ex`. `POST /import` is not in the Phoenix router.

    export let pagesImportRoutes(): List<Route> {
      [
        new Route("GET", "/import", "guest.import"),
        new Route("POST", "/import", "guest.import_files"),
      ]
    }

## Answering a route

    export let pagesImportGet(ctx: Ctx, match: Match): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.import") {
        pagesImportPage(ctx)
      } else if (route == "guest.import_files") {
        pagesImportFiles(ctx)
      } else {
        console.log("pages_import: no handler for route ${route}");
        bubble()
      }
    }

## Answering an event

`match` is the page the event was sent from. The seams are the importer's HTTP
(GitHub) and the way an import is started; production is `importerRealHttp` and
`pagesImportLaunch`, the tests give a canned GitHub and a launcher that does not
fork.

    export let pagesImportEventWith(
      ctx: Ctx, match: Match, event: String, payload: JsonObject, http: ImporterHttp,
      launch: fn (Ctx, String, PimJob): Boolean throws Bubble,
    ): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.import") {
        pagesImportEventPage(ctx, event, payload, http, launch)
      } else {
        pimUnhandledEvent(match.route.pattern, event)
      }
    }

    export let pagesImportEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      pagesImportEventWith(ctx, match, event, payload, importerRealHttp(1), pagesImportLaunch)
    }
