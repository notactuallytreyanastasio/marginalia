# pages_cases: routes and dispatch

The router (`web`) takes three things from every page group: its routes in
Phoenix router order, a function that answers a matched route, and a function
that answers an event for a page the group owns.

This group is `/` (the landing page, in the bare layout) and the public case
pages. None of them is behind a guest or a login: `public.` mounts the scope
and nothing more, and nothing here ever mints a guest.

    let { Ctx } = import("webcore/src");
    let { Route, Match, Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { LlmClient } = import("llm/src");

## Routes

`router.ex`: `/` first (`LandingLive`, the `:bare_browser` pipeline), then
`/cases`, `/cases/:slug`, `/cases/:slug/read` and `/cases/:slug/read/:lead`.

    export let pagesCasesRoutes(): List<Route> {
      [
        new Route("GET", "/", "public.landing"),
        new Route("GET", "/cases", "public.cases_index"),
        new Route("GET", "/cases/:slug", "public.cases_show"),
        new Route("GET", "/cases/:slug/read", "public.cases_read"),
        new Route("GET", "/cases/:slug/read/:lead", "public.cases_read"),
      ]
    }

## Answering a route

A route name this library does not know is a bug in the router: it stops with
the name in the log.

    export let pagesCasesGet(ctx: Ctx, match: Match): Response throws Bubble {
      let route = match.route.name;
      if (route == "public.landing") {
        pagesCasesLandingPage(ctx)
      } else if (route == "public.cases_index") {
        pagesCasesIndexPage(ctx)
      } else if (route == "public.cases_show") {
        pagesCasesShowPage(ctx, match.params.getOr("slug", ""))
      } else if (route == "public.cases_read") {
        pagesCasesReadPage(ctx, match.params.getOr("slug", ""), pgcLeadParam(match))
      } else {
        console.log("pages_cases: no handler for route ${route}");
        bubble()
      }
    }

The `:lead` of the read pages, or null when the route has none.

    let pgcLeadParam(match: Match): String? {
      if (match.params.has("lead")) { match.params.getOr("lead", "") } else { null }
    }

## Answering an event

`match` is the page the event was sent from. The model is `llmFromEnv()`
unless a test gives one.

    export let pagesCasesEventWith(
      ctx: Ctx, match: Match, event: String, payload: JsonObject, llm: LlmClient?,
    ): Response throws Bubble {
      let route = match.route.name;
      if (route == "public.landing") {
        pagesCasesLandingEvent(ctx, event, payload)
      } else if (route == "public.cases_index") {
        pagesCasesIndexEvent(ctx, event, payload)
      } else if (route == "public.cases_show") {
        pagesCasesShowEvent(ctx, match.params.getOr("slug", ""), event, payload)
      } else if (route == "public.cases_read") {
        pagesCasesReadEvent(ctx, match.params.getOr("slug", ""), pgcLeadParam(match), event, payload, llm)
      } else {
        pagesCasesUnhandled(match.route.pattern, event)
      }
    }

    export let pagesCasesEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      pagesCasesEventWith(ctx, match, event, payload, null)
    }
