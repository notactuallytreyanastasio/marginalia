# Answering

What the page, its events and its one POST share: one way to answer with a
rendered `<main>` whether the request was a page or an event, the small readers
for an event's JSON, and the one way to refuse an event nobody handles.

Every top-level name in this library is shared by all of its files and, in the
built program, with every other library's: the private helpers start with `pim`.

    let { Ctx, PageMeta, webPage, webEventReply, webPutFlash } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject, JsonString, JsonInt } = import("std/json");

## Meta

The page title and `page_robots: "noindex, nofollow"`: the only page here that
asks not to be indexed.

    let pimMeta(): PageMeta {
      new PageMeta("Import documents", null, "noindex, nofollow", null, null, null)
    }

An event answers with the region, the flash and, while an import is going, the
poll interval (it has to be repeated here: the attribute lives inside the
region, and a reply without it stops the polling). A plain request answers with
the whole page, at `status` (200, or 422 for the files form refused).

    let pimRender(ctx: Ctx, tree: List<AnyValue>, flash: Pair<String, String>?, poll: Int?, status: Int): Response throws Bubble {
      if (ctx.isAjax) {
        webEventReply(ctx, tree, [], flash, poll)
      } else {
        let f = flash;
        if (f != null) { webPutFlash(ctx, f.key, f.value); }
        let r = webPage(ctx, pimMeta(), tree, poll, "app");
        if (status == 200) { r } else { new Response(status, r.headers, r.body) }
      }
    }

An event the page does not have. A crash with the names in the log is better
than an answer that looks like success.

    let pimUnhandledEvent(page: String, event: String): Response throws Bubble {
      console.log("pages_import: ${page} has no event ${event}");
      bubble()
    }

## Reading a payload

A string field; a number is read as its digits; anything else, and a missing
key, is the empty string.

    let pimStr(payload: JsonObject, key: String): String {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) {
        v.content
      } else if (v is JsonInt) {
        v.content.toString()
      } else { "" }
    }

The field if the event carried it, else what the page already held
(`params["x"] || current`).

    let pimStrOr(payload: JsonObject, key: String, current: String): String {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) { v.content } else { current }
    }

    let pimHas(payload: JsonObject, key: String): Boolean {
      payload.propertyValueOrNull(key) is JsonString
    }
