# pages_drafts: routes, dispatch and what the pages share

The router (`web`) takes three things from every page group: its routes in
Phoenix router order, a function that answers a matched route, and a function
that answers an event for a page the group owns.

    let { Ctx, PageMeta, webRedirect } = import("webcore/src");
    let { Route, Match, Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { accountsOwner } = import("accounts/src");
    let { markdownToHtml } = import("html/src");
    let { sysStringReplace, sysGraphemeTake } = import("sys/src");

Every top-level name here is shared by this library's files and, in the built
program, with every other library's: the private helpers start with `pd`.

## Routes

The order of `lib/marginalia_web/router.ex`: the sitemap, then the `:cases`
live session's drafts, linked and reading pages. All of them are public: no
guest is minted (the router comment: minting one per visitor had produced 762
`users` rows for five real uploaders), so the names are `public.`.

    export let pagesDraftsRoutes(): List<Route> {
      [
        new Route("GET", "/sitemap.xml", "public.sitemap"),
        new Route("GET", "/drafts", "public.drafts_index"),
        new Route("GET", "/drafts/:slug", "public.drafts_show"),
        new Route("GET", "/drafts/:slug/changes", "public.drafts_changes"),
        new Route("GET", "/linked", "public.linked_index"),
        new Route("GET", "/linked/:id", "public.linked_show"),
        new Route("GET", "/reading", "public.reading_index"),
        new Route("GET", "/reading/:slug", "public.reading_story"),
        new Route("GET", "/reading/:slug/:ordinal", "public.reading_step"),
      ]
    }

## Answering a route

A route name this library does not know is a bug in the router: it stops with
the name in the log.

    export let pagesDraftsGet(ctx: Ctx, match: Match): Response throws Bubble {
      let route = match.route.name;
      if (route == "public.sitemap") {
        pagesDraftsSitemap(ctx)
      } else if (route == "public.drafts_index") {
        pagesDraftsIndexPage(ctx)
      } else if (route == "public.drafts_show") {
        pagesDraftsShowPage(ctx, match.params.getOr("slug", ""))
      } else if (route == "public.drafts_changes") {
        pagesDraftsChangesPage(ctx, match.params.getOr("slug", ""))
      } else if (route == "public.linked_index") {
        pagesDraftsLinkedIndexPage(ctx)
      } else if (route == "public.linked_show") {
        pagesDraftsLinkedShowPage(ctx, match.params.getOr("id", ""))
      } else if (route == "public.reading_index") {
        pagesDraftsReadingIndexPage(ctx)
      } else if (route == "public.reading_story") {
        pagesDraftsReadingStoryPage(ctx, match.params.getOr("slug", ""))
      } else if (route == "public.reading_step") {
        pagesDraftsReadingStepPage(ctx, match.params.getOr("slug", ""), match.params.getOr("ordinal", ""))
      } else {
        console.log("pages_drafts: no handler for route ${route}");
        bubble()
      }
    }

## Answering an event

Only `/linked` has events (`filter` and `more`). `match` is the page the event
was sent from. An event nobody handles is a crash with the names in the log,
which is better than an answer that looks like success.

    export let pagesDraftsEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      let route = match.route.name;
      if (route == "public.linked_index") {
        pagesDraftsLinkedIndexEvent(ctx, event, payload)
      } else {
        console.log("pages_drafts: ${match.route.pattern} has no event ${event}");
        bubble()
      }
    }

## What the pages share

Whether `part` occurs in `s`.

    let pdHas(s: String, part: String): Boolean {
      s.split(part).length > 1
    }

`Integer.parse(text)` with nothing left over: an optional sign and at least one
digit, and nothing else. A value that does not fit in an `Int` is also no
number here (the Elixir had big integers, and nothing in the tables is that
large).

    let pdParseInt(text: String): Int? {
      if (text == "") { return null; }
      var i = String.begin;
      var digits = 0;
      var ok = true;
      var first = true;
      while (text.hasIndex(i)) {
        let c = text[i];
        let isDigit = c >= 48 && c <= 57;
        let isSign = first && (c == 43 || c == 45);
        if (isDigit) { digits += 1; } else if (!isSign) { ok = false; }
        first = false;
        i = text.next(i);
      }
      if (!ok || digits == 0) { return null; }
      var n = 0;
      let parsed = do { n = text.toInt32(); true } orelse false;
      if (parsed) { n } else { null }
    }

The id of the account this deploy belongs to, or null when there is none (every
public listing is then empty).

    let pdOwnerId(ctx: Ctx): Int? throws Bubble {
      let owner = accountsOwner(ctx.db);
      if (owner != null) { owner.id } else { null }
    }

`Markdown.to_html/1` of text that may be missing: nothing for nothing.

    let pdMarkdown(text: String?): String {
      if (text != null) { markdownToHtml(text) } else { "" }
    }

A nullable string, or the empty string.

    let pdOr(s: String?): String {
      if (s != null) { s } else { "" }
    }

`"pays_off"` printed as `"pays off"`.

    let pdSpaced(kind: String): String {
      sysStringReplace(kind, "_", " ")
    }

`{if n == 1, do: "", else: "s"}`.

    let pdS(n: Int): String {
      if (n == 1) { "" } else { "s" }
    }

`String.slice(text, 0, 300)`: the card description.

    let pdSlice300(text: String): String {
      sysGraphemeTake(text, 300)
    }

The page's head: a title, a description, and `index, follow` where the page
set `page_robots`. None of these pages sets a `page_url` or an image, so the
canonical link and `og:url` point at the site root (a quirk of the original,
kept: notes/web-public.md section 13, item 7).

    let pdMeta(title: String?, description: String?, robots: String?): PageMeta {
      new PageMeta(title, description, robots, null, null, null)
    }

A show page whose lookup came back empty: the flash, and the index it belongs
to.

    let pdBackTo(ctx: Ctx, to: String, flash: String): Response throws Bubble {
      webRedirect(ctx, to, new Pair("error", flash))
    }
