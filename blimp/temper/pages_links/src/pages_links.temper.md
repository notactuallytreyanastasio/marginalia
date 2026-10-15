# pages_links: routes and dispatch

The router (`web`) takes three things from every page group: its routes in
Phoenix router order, a function that answers a matched route, and a function
that answers an event for a page the group owns.

    let { Ctx, PageMeta, webPutFlash, webPage, webEventReply } = import("webcore/src");
    let { Route, Match, Response } = import("http/src");
    let { Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { JsonObject, JsonString, JsonNumeric, JsonTextProducer, NullInterchangeContext } = import("std/json");
    let { Link, linksSetStatus, linksAttrsError, BulkPair, linksBulkRun, linksBulkRelate, linkerRunPair } = import("links/src");
    let { runsStart, runsFinish, runsRunning } = import("runs/src");
    let { LlmClient, llmFromEnv } = import("llm/src");

Every top-level name here is shared by this library's files and, in the built
program, with every other library's: the private helpers start with `pl`.

## Routes

The three are in the `scope "/"` of `ensure_user_or_guest`, so a stranger who
opens `/links` is given a guest and sees a list of nothing: names `guest.`.
`/links/:id/read` stays an alias of `/links/:id` ("links already sent to
people keep working"), and both are the one page.

    export let pagesLinksRoutes(): List<Route> {
      [
        new Route("GET", "/links", "guest.links_index"),
        new Route("GET", "/links/:id", "guest.links_show"),
        new Route("GET", "/links/:id/read", "guest.links_read"),
      ]
    }

## What starts background work

A page never forks. Everything it needs run away from the request goes
through a launcher, so the tests can give one that runs the work inline on the
in-memory database with a canned model (`runsStart` refuses `:memory:`).

* `readLink` marks the link `linking` and starts the pass that reads the pair
  under the run key `link:<id>`. (`Linker.start`.)
* `bulkPropose` starts the one cheap call that chooses the pairs of a folder,
  under `bulk:<folder>`; `bulkRelate` starts reading the chosen pairs, one
  after another, under the same key.
* `llm` is the client the chat asks, synchronously.

<!-- -->

    export interface LinksLauncher {
      public readLink(ctx: Ctx, link: Link): Void throws Bubble;
      public bulkPropose(ctx: Ctx, folderId: Int): Void throws Bubble;
      public bulkRelate(ctx: Ctx, folderId: Int, pairs: List<BulkPair>): Void throws Bubble;
      public llm(): LlmClient;
    }

`bulk:<folder>` and `link:<id>`: the keys the page and the job agree on.

    export let pagesLinksBulkKey(folderId: Int): String { "bulk:${folderId.toString()}" }

    export let pagesLinksReadKey(linkId: Int): String { "link:${linkId.toString()}" }

### The bodies of the jobs

These take their own database and client: nothing of the request's is used in
the child. The tests call them with the page's database and a fake client.
The bulk ones leave their result in the run's `detail` for the page to pick up,
as JSON.

    let plJsonStrings(p: JsonTextProducer, key: String, xs: List<String>): Void {
      p.objectKey(key);
      p.startArray();
      for (let x of xs) { p.stringValue(x); }
      p.endArray();
    }

Elixir's `inspect/1` of the reason: the two atoms the run can fail with
print as atoms, anything else is a quoted string.

    export let pagesLinksInspect(reason: String): String {
      if (reason == "no_folder" || reason == "empty_folder") {
        ":${reason}"
      } else {
        let escaped = reason.split("\\").join("\\\\") { (x: String): String => x };
        let quoted = escaped.split("\"").join("\\\"") { (x: String): String => x };
        "\"${quoted}\""
      }
    }

`{"error": null | ":no_folder" | "\"text\"", "pairs": [{"a", "b", "why", "expect"}], "skipped", "dropped"}`

    let plProposeDetail(db: Db, llm: LlmClient, scope: Scope, folderId: Int): String throws Bubble {
      let run = linksBulkRun(db, llm, scope, folderId, true);
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      p.objectKey("error");
      let error = run.error;
      if (error != null) { p.stringValue(pagesLinksInspect(error)); } else { p.nullValue(); }
      p.objectKey("pairs");
      p.startArray();
      let triage = run.triage;
      if (triage != null) {
        for (let pair of triage.pairs) {
          p.startObject();
          p.objectKey("a");
          p.int32Value(pair.a.id);
          p.objectKey("b");
          p.int32Value(pair.b.id);
          p.objectKey("why");
          p.stringValue(pair.why);
          p.objectKey("expect");
          p.stringValue(pair.expect);
          p.endObject();
        }
      }
      p.endArray();
      p.objectKey("skipped");
      p.stringValue(if (triage != null) { triage.skipped } else { "" });
      plJsonStrings(p, "dropped", if (triage != null) { triage.dropped } else { [] });
      p.endObject();
      p.toJsonString()
    }

    export let pagesLinksRunPropose(db: Db, key: String, llm: LlmClient, scope: Scope, folderId: Int): Void throws Bubble {
      runsFinish(db, key, "done", plProposeDetail(db, llm, scope, folderId));
    }

`{"started": n, "not_read": [..]}`

    export let pagesLinksRunRelate(db: Db, key: String, llm: LlmClient, pairs: List<BulkPair>): Void throws Bubble {
      let related = linksBulkRelate(db, llm, pairs);
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      p.objectKey("started");
      p.int32Value(related.started.length);
      plJsonStrings(p, "not_read", related.notRead);
      p.endObject();
      runsFinish(db, key, "done", p.toJsonString());
    }

    export let pagesLinksRunLink(db: Db, llm: LlmClient, linkId: Int): Void throws Bubble {
      let result = linkerRunPair(db, llm, linkId);
    }

### The production launcher

The pass is marked `linking` before it is forked, so the page that answers
this very request already says so (the Elixir set the assign locally for the
same reason). A pass already running under the key is left alone.

    export class LinksForkLauncher extends LinksLauncher {
      public readLink(ctx: Ctx, link: Link): Void throws Bubble {
        let id = link.id;
        let key = pagesLinksReadKey(id);
        if (!runsRunning(ctx.db, key)) {
          linksSetStatus(ctx.db, link, "linking", linksAttrsError(null));
          let queued = runsStart(ctx.dbPath, ctx.db, key) { (jobDb: Db): Void throws Bubble =>
            pagesLinksRunLink(jobDb, llmFromEnv(), id)
          };
        }
      }
      public bulkPropose(ctx: Ctx, folderId: Int): Void throws Bubble {
        let key = pagesLinksBulkKey(folderId);
        let scope = ctx.scope;
        let queued = runsStart(ctx.dbPath, ctx.db, key) { (jobDb: Db): Void throws Bubble =>
          pagesLinksRunPropose(jobDb, key, llmFromEnv(), scope, folderId)
        };
      }
      public bulkRelate(ctx: Ctx, folderId: Int, pairs: List<BulkPair>): Void throws Bubble {
        let key = pagesLinksBulkKey(folderId);
        let queued = runsStart(ctx.dbPath, ctx.db, key) { (jobDb: Db): Void throws Bubble =>
          pagesLinksRunRelate(jobDb, key, llmFromEnv(), pairs)
        };
      }
      public llm(): LlmClient { llmFromEnv() }
    }

## Answering

    export let pagesLinksGet(ctx: Ctx, match: Match): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.links_index") {
        pagesLinksIndexPage(ctx)
      } else if (route == "guest.links_show" || route == "guest.links_read") {
        pagesLinksReadPage(ctx, match.params.getOr("id", ""))
      } else {
        console.log("pages_links: no handler for route ${route}");
        bubble()
      }
    }

`match` is the page the event was sent from. An event the page does not have
is a crash with the names in the log, which is better than an answer that
looks like success.

    export let pagesLinksEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      pagesLinksEventWith(ctx, match, event, payload, new LinksForkLauncher())
    }

    export let pagesLinksEventWith(
      ctx: Ctx, match: Match, event: String, payload: JsonObject, launcher: LinksLauncher,
    ): Response throws Bubble {
      let route = match.route.name;
      if (route == "guest.links_index") {
        pagesLinksIndexEvent(ctx, event, payload, launcher)
      } else if (route == "guest.links_show" || route == "guest.links_read") {
        pagesLinksReadEvent(ctx, match.params.getOr("id", ""), event, payload, launcher)
      } else {
        console.log("pages_links: ${route} has no event ${event}");
        bubble()
      }
    }

## What both pages share

An event answers with the region; a plain request with the whole page. `poll`
is the seconds between refetches while the page waits for background work, or
null. `layout` is `app`, or `bleed` for the pair page, whose columns run to
the edges. A flash is put in the session first, so it shows on whichever
answer this is.

    let plRender(ctx: Ctx, meta: PageMeta, tree: List<AnyValue>, poll: Int?, flash: Pair<String, String>?, layout: String): Response throws Bubble {
      let f = flash;
      if (f != null) { webPutFlash(ctx, f.key, f.value); }
      if (ctx.isAjax) {
        webEventReply(ctx, tree, [], null, poll)
      } else {
        webPage(ctx, meta, tree, poll, layout)
      }
    }

An id from a path or a payload: digits, or null. (`String.to_integer` raised
in the Elixir: a 404 for a path, a crash for an event.)

    let plInt(s: String): Int? {
      if (s == "") { null } else {
        let n: Int? = do { s.toInt32() } orelse null;
        n
      }
    }

A payload value as an id: a string of digits or a number; anything else
(`""`, null, text) is no id.

    let plPayloadInt(payload: JsonObject, key: String): Int? {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) {
        plInt(v.content)
      } else if (v is JsonNumeric) {
        plInt(v.asJsonNumericToken())
      } else { null }
    }

    let plPayloadString(payload: JsonObject, key: String): String {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) { v.content } else { "" }
    }

    let plOrEmpty(s: String?): String {
      if (s != null) { s } else { "" }
    }

    let plHas(s: String, part: String): Boolean { s.split(part).length > 1 }
