# pages_cuts: routes and dispatch

The router (`web`) takes three things from every page group: its routes in
Phoenix router order, a function that answers a matched route, and a function
that answers an event for a page the group owns.

    let { Ctx, webMeta, webPage, webEventReply, webPutFlash } = import("webcore/src");
    let { Route, Match, Response } = import("http/src");
    let { Db } = import("db/src");
    let { JsonObject, JsonString, JsonNumeric } = import("std/json");
    let { Cut, cutsStartRead, cutsRead } = import("cuts/src");
    let { runsStart } = import("runs/src");
    let { llmFromEnv } = import("llm/src");

Every top-level name here is shared by this library's files and, in the built
program, with every other library's: the private helpers start with `pc`.

## Routes

Both are in the `scope "/"` of `ensure_user_or_guest`, so a stranger who opens
`/cuts` is given a guest and sees a list of nothing: names `guest.`.

    export let pagesCutsRoutes(): List<Route> {
      [
        new Route("GET", "/cuts", "guest.cuts_index"),
        new Route("GET", "/cuts/:id", "guest.cuts_show"),
      ]
    }

## Starting a read

A read is one slow model call. The page marks the cut `reading` (and tells
the watchers of its topic), then hands the call to `runsStart`, which forks it
away from the request under the key `cut:<id>`; the page learns of it by
polling. The job opens its own database and its own client: nothing of the
request's is used in the child.

    let pcRunRead(jobDb: Db, cut: Cut): Void throws Bubble {
      cutsRead(jobDb, llmFromEnv(), cut);
    }

    export let pagesCutsLaunch(ctx: Ctx, cut: Cut): Void throws Bubble {
      let started = cutsStartRead(ctx.db, cut);
      let queued = runsStart(ctx.dbPath, ctx.db, "cut:${cut.id.toString()}") { (jobDb: Db): Void throws Bubble =>
        pcRunRead(jobDb, started)
      };
    }

## Answering

The `launch` argument is what starts a read. Production is `pagesCutsLaunch`;
the tests give one that runs the read inline, since `runsStart` refuses
`:memory:`.

    export let pagesCutsGet(ctx: Ctx, match: Match): Response throws Bubble {
      pagesCutsGetWith(ctx, match, pagesCutsLaunch)
    }

    export let pagesCutsGetWith(ctx: Ctx, match: Match, launch: fn (Ctx, Cut): Void throws Bubble): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.cuts_index") {
        pagesCutsIndexPage(ctx)
      } else if (route == "guest.cuts_show") {
        pagesCutsShowPage(ctx, match.params.getOr("id", ""), launch)
      } else {
        console.log("pages_cuts: no handler for route ${route}");
        bubble()
      }
    }

`match` is the page the event was sent from. An event the page does not have
is a crash with the names in the log, which is better than an answer that
looks like success.

    export let pagesCutsEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      pagesCutsEventWith(ctx, match, event, payload, pagesCutsLaunch)
    }

    export let pagesCutsEventWith(
      ctx: Ctx, match: Match, event: String, payload: JsonObject,
      launch: fn (Ctx, Cut): Void throws Bubble,
    ): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.cuts_index") {
        pagesCutsIndexEvent(ctx, event, payload)
      } else if (route == "guest.cuts_show") {
        pagesCutsShowEvent(ctx, match.params.getOr("id", ""), event, payload, launch)
      } else {
        console.log("pages_cuts: ${route} has no event ${event}");
        bubble()
      }
    }

## What both pages share

An event answers with the region; a plain request with the whole page. `poll`
is the seconds between refetches while a read is running, or null.

    let pcRender(ctx: Ctx, title: String, tree: List<AnyValue>, poll: Int?, flash: Pair<String, String>?): Response throws Bubble {
      if (ctx.isAjax) {
        webEventReply(ctx, tree, [], flash, poll)
      } else {
        let f = flash;
        if (f != null) { webPutFlash(ctx, f.key, f.value); }
        webPage(ctx, webMeta(title), tree, poll, "app")
      }
    }

An id from a path or a payload: digits, or null. (`String.to_integer` raised
in the Elixir: a 400 for a path, a crash for an event.)

    let pcInt(s: String): Int? {
      if (s == "") { null } else {
        let n: Int? = do { s.toInt32() } orelse null;
        n
      }
    }

    let pcPayloadInt(payload: JsonObject, key: String): Int? {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) {
        pcInt(v.content)
      } else if (v is JsonNumeric) {
        pcInt(v.asJsonNumericToken())
      } else { null }
    }
