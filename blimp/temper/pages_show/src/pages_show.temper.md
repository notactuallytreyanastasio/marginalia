# pages_show: routes and dispatch

The router (`web`) takes three things from every page group: its routes in
Phoenix router order, a function that answers a matched route, and a function
that answers an event for a page the group owns.

    let { Ctx, PageMeta, webPage, webEventReply, webRedirect, webFinish } = import("webcore/src");
    let { Route, Match, Response, httpText } = import("http/src");
    let { JsonObject } = import("std/json");
    let { Work, worksGetBySlug } = import("works/src");
    let { graphJson, graphDot, graphTrace, graphSlug } = import("analysis/src");

Every top-level name here is shared by this library's files and, in the built
program, with every other library's: the private helpers start with `ps`.

## Routes

All of them sit in the `scope "/"` of `ensure_user_or_guest`: a stranger who
opens a draft's address is given a guest and reads it (the slug is the
permission to read), so `guest.`.

The three downloads come before the page in `router.ex` and have a segment
more, so the order between them does not matter; the page comes after
`/works/new` (`pages_works`), which is why this group is appended after that
one in `web`.

    export let pagesShowRoutes(): List<Route> {
      [
        new Route("GET", "/works/:id/graph.json", "guest.show_graph_json"),
        new Route("GET", "/works/:id/graph.dot", "guest.show_graph_dot"),
        new Route("GET", "/works/:id/trace.json", "guest.show_trace_json"),
        new Route("GET", "/works/:slug", "guest.show"),
      ]
    }

## The page

`mount/3` found the draft by slug and, with none, put `No such draft.` up and
went to `/works`. The title is the draft's; the page asks not to be indexed.

    let psNoDraft(ctx: Ctx): Response throws Bubble {
      webRedirect(ctx, "/works", new Pair("error", "No such draft."))
    }

    export let pagesShowPageWith(ctx: Ctx, slug: String, launcher: ShowLauncher): Response throws Bubble {
      let work = worksGetBySlug(ctx.db, slug);
      if (work != null) {
        let state = loadShowFor(ctx, work, launcher);
        let meta = new PageMeta(state.work.title, null, "noindex, nofollow", null, null, null);
        webPage(ctx, meta, renderShow(ctx, state), showPoll(state), "app")
      } else {
        psNoDraft(ctx)
      }
    }

## The downloads

`GraphController`. The graph is for anyone holding the slug; the trace does not
travel with the link, and is the draft's owner's alone. A draft that is not
there, or a trace that is not yours, is a plain 404 (`not found`). The file is
named after the draft's title.

    let psNotFound(ctx: Ctx): Response throws Bubble {
      webFinish(ctx, httpText(404, "not found"))
    }

    let psDownload(ctx: Ctx, type: String, name: String, body: String): Response throws Bubble {
      webFinish(ctx, new Response(200, [
        new Pair("Content-Type", type),
        new Pair("Content-Disposition", "attachment; filename=\"${name}\""),
      ], body))
    }

    let psGraphJson(ctx: Ctx, slug: String): Response throws Bubble {
      let work = worksGetBySlug(ctx.db, slug);
      if (work != null) {
        psDownload(ctx, "application/json; charset=utf-8", "${graphSlug(work.title)}-graph.json", graphJson(ctx.db, work))
      } else { psNotFound(ctx) }
    }

    let psGraphDot(ctx: Ctx, slug: String): Response throws Bubble {
      let work = worksGetBySlug(ctx.db, slug);
      if (work != null) {
        psDownload(ctx, "text/vnd.graphviz; charset=utf-8", "${graphSlug(work.title)}-graph.dot", graphDot(ctx.db, work))
      } else { psNotFound(ctx) }
    }

    let psTraceJson(ctx: Ctx, slug: String): Response throws Bubble {
      let work = worksGetBySlug(ctx.db, slug);
      if (work != null) { psTraceOf(ctx, work) } else { psNotFound(ctx) }
    }

    let psTraceOf(ctx: Ctx, work: Work): Response throws Bubble {
      let user = ctx.scope.user;
      if (user != null) {
        if (work.userId == user.id) {
          psDownload(ctx, "application/json; charset=utf-8", "${graphSlug(work.title)}-trace.json", graphTrace(ctx.db, work))
        } else { psNotFound(ctx) }
      } else { psNotFound(ctx) }
    }

## Answering a route

The launcher is what starts background work: production is `ShowForkLauncher`;
the tests give one that runs the job inline (`runsStart` refuses `:memory:`).

    export let pagesShowGet(ctx: Ctx, match: Match): Response throws Bubble {
      pagesShowGetWith(ctx, match, new ShowForkLauncher())
    }

    export let pagesShowGetWith(ctx: Ctx, match: Match, launcher: ShowLauncher): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.show") {
        pagesShowPageWith(ctx, match.params.getOr("slug", ""), launcher)
      } else if (route == "guest.show_graph_json") {
        psGraphJson(ctx, match.params.getOr("id", ""))
      } else if (route == "guest.show_graph_dot") {
        psGraphDot(ctx, match.params.getOr("id", ""))
      } else if (route == "guest.show_trace_json") {
        psTraceJson(ctx, match.params.getOr("id", ""))
      } else {
        console.log("pages_show: no handler for route ${route}");
        bubble()
      }
    }

## Answering an event

`match` is the page the event was sent from. The state is loaded as for a plain
request, the handler changes it, the part of it only the page knows is saved,
and the page is read again from the database and sent back as the new `<main>`
(with `data-poll` while something is running, which has to be repeated here:
the attribute lives inside the region, and a reply without it stops the
polling). An event that goes to another page is a redirect.

    export let pagesShowEventWith(
      ctx: Ctx, match: Match, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): Response throws Bubble {
      if (match.route.name != "guest.show") {
        console.log("pages_show: ${match.route.name} has no event ${event}");
        bubble()
      }
      let slug = match.params.getOr("slug", "");
      let work = worksGetBySlug(ctx.db, slug);
      if (work != null) { psEventFor(ctx, work, event, payload, launcher) } else { psNoDraft(ctx) }
    }

    let psEventFor(
      ctx: Ctx, work: Work, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): Response throws Bubble {
      let state = loadShowFor(ctx, work, launcher);
      let outcome = handleShowWith(ctx, state, event, payload, launcher);
      showSaveUi(ctx, state);
      let to = outcome.redirect;
      if (to != null) {
        webRedirect(ctx, to, outcome.flash)
      } else {
        let again = worksGetBySlug(ctx.db, work.slug);
        if (again != null) {
          let shown = loadShowFor(ctx, again, launcher);
          webEventReply(ctx, renderShow(ctx, shown), outcome.events, outcome.flash, showPoll(shown))
        } else {
          psNoDraft(ctx)
        }
      }
    }

    export let pagesShowEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      pagesShowEventWith(ctx, match, event, payload, new ShowForkLauncher())
    }
