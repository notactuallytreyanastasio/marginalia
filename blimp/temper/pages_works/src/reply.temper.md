# Answering

What the two pages share: one way to answer with a rendered `<main>` whether
the request was a page or an event, and the small readers for an event's JSON.

Every top-level name in this library is shared by all of its files, so the
private helpers start with `pw`.

    let { Ctx, webMeta, webPage, webEventReply, webPutFlash } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject, JsonString, JsonInt } = import("std/json");

An event answers with the region and a flash; a plain request answers with
the whole page. `status` is 200 except for the upload form refused (422).

    let pwRender(ctx: Ctx, title: String, tree: List<AnyValue>, flash: Pair<String, String>?, status: Int): Response throws Bubble {
      if (ctx.isAjax) {
        webEventReply(ctx, tree, [], flash, null)
      } else {
        let f = flash;
        if (f != null) { webPutFlash(ctx, f.key, f.value); }
        let r = webPage(ctx, webMeta(title), tree, null, "app");
        if (status == 200) { r } else { new Response(status, r.headers, r.body) }
      }
    }

An event the page does not have.

    let pwUnhandledEvent(page: String, event: String): Response throws Bubble {
      console.log("pages_works: ${page} has no event ${event}");
      bubble()
    }

## Reading a payload

A string field; a number is read as its digits (a hand-written client may send
an id as a number); anything else, and a missing key, is the empty string.

    let pwStr(payload: JsonObject, key: String): String {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) {
        v.content
      } else if (v is JsonInt) {
        v.content.toString()
      } else { "" }
    }

    let pwStartsWith(s: String, prefix: String): Boolean {
      if (s == "" || prefix == "") { return false; }
      let parts = s.split(prefix);
      parts.length > 1 && parts.getOr(0, "x") == ""
    }

    let pwOr(s: String?, d: String): String {
      if (s != null) { s } else { d }
    }
