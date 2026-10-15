# Responses

What turns a rendered `<main>` tree into the right `Response` for the request:
a full HTML page on a plain GET, the JSON the client runtime applies on an
event or a poll, a redirect either way. Every response that comes out of here
is final: the session is saved and the cookies are on it.

    let { Response, httpHtml, httpJson, httpRedirect } = import("http/src");
    let { attr, h, hv, htext, hraw, hjoin } = import("html/src");
    let { JsonSyntaxTree, JsonTextProducer, NullInterchangeContext, parseJson } = import("std/json");

## Pages

`layout` is one of

* `"app"`: the root document wrapping the app layout (header, `<main
  id="main">`, flash group). Almost every page.
* `"bleed"`: the same with the page padding dropped (`CaseLive.Read`).
* `"bare"`: the bare document around the page's own markup, which sits in a
  `#main` box that does not lay out (the landing page).
* `"root"`: the root document around the tree as given, with no chrome and no
  `#main`.

Anything else is a bug in the caller and stops with a located message.

`poll` is the seconds between refetches while the page waits for background
work, or `null`.

On an ajax request (an event, or the poll) the answer is JSON:

{"regions": {"#main": "<inner html of main>"}, "title": "...", "flash": {"info": "..."}}

On a plain request it is the whole document. `meta.title` becomes the title
with the ` · Marginalia` suffix in both. The flash waiting in the session is
taken and shown in both.

    let wcWriteRegion(p: JsonTextProducer, html: String): Void {
      p.objectKey("regions");
      p.startObject();
      p.objectKey("#main");
      p.stringValue(html);
      p.endObject();
    }

    let wcWriteFlash(p: JsonTextProducer, flash: Map<String, String>): Void {
      p.objectKey("flash");
      wcWriteStringMap(p, flash);
    }

    let wcRegionHtml(main: List<AnyValue>, poll: Int?, layout: String): String {
      if (layout == "bare") {
        hjoin(webBareMainInner(main, poll))
      } else {
        hjoin(webMainInner(main, poll))
      }
    }

    export let webPage(ctx: Ctx, meta: PageMeta, main: List<AnyValue>, poll: Int?, layout: String): Response throws Bubble {
      if (layout != "app" && layout != "bleed" && layout != "bare" && layout != "root") {
        console.log("webPage: unknown layout ${layout}");
        panic()
      }
      let flash = webTakeFlash(ctx);
      if (ctx.isAjax) {
        let p = new JsonTextProducer(NullInterchangeContext.instance);
        p.startObject();
        wcWriteFlash(p, flash);
        wcWriteRegion(p, wcRegionHtml(main, poll, layout));
        p.objectKey("title");
        p.stringValue(webDocumentTitle(meta));
        p.endObject();
        return webFinish(ctx, httpJson(200, p.toJsonString() orelse panic()));
      }
      let doc = if (layout == "bare") {
        webBareLayout(ctx, meta, webBareMain(main, poll))
      } else if (layout == "root") {
        webRootLayout(ctx, meta, main)
      } else {
        webRootLayout(ctx, meta, webAppLayout(ctx, main, poll, layout == "bleed", flash))
      };
      webFinish(ctx, httpHtml(200, hjoin(doc)))
    }

## Event replies

The answer to `POST /ev/<name>`: the re-rendered `<main>`, the client events
(`name` and a JSON `payload` text each) for the hooks, and a flash. A flash
already waiting in the session is shown with it, the explicit one winning for
its kind. `poll` is as for `webPage`: it has to be repeated here, because the
attribute lives inside the region and a reply without it stops the polling.

    export let webEventReply(
      ctx: Ctx,
      main: List<AnyValue>,
      events: List<Pair<String, String>>,
      flash: Pair<String, String>?,
      poll: Int?,
    ): Response throws Bubble {
      let f = flash;
      if (f != null) { webPutFlash(ctx, f.key, f.value); }
      let shown = webTakeFlash(ctx);
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      p.objectKey("events");
      p.startArray();
      for (var i = 0; i < events.length; ++i) {
        let e = events.getOr(i, new Pair("", "{}"));
        p.startObject();
        p.objectKey("name");
        p.stringValue(e.key);
        p.objectKey("payload");
        let tree: JsonSyntaxTree = parseJson(e.value);
        tree.produce(p);
        p.endObject();
      }
      p.endArray();
      wcWriteFlash(p, shown);
      wcWriteRegion(p, hjoin(webMainInner(main, poll)));
      p.endObject();
      webFinish(ctx, httpJson(200, p.toJsonString() orelse panic()))
    }

## Redirects

A 303 on a plain request. On an ajax request the JSON `{"redirect": to}`, which
the client turns into a navigation. A flash rides in the session either way and
shows on the page that is arrived at.

    export let webRedirect(ctx: Ctx, to: String, flash: Pair<String, String>?): Response throws Bubble {
      let f = flash;
      if (f != null) { webPutFlash(ctx, f.key, f.value); }
      if (ctx.isAjax) {
        let p = new JsonTextProducer(NullInterchangeContext.instance);
        p.startObject();
        p.objectKey("redirect");
        p.stringValue(to);
        p.endObject();
        webFinish(ctx, httpJson(200, p.toJsonString() orelse panic()))
      } else {
        webFinish(ctx, httpRedirect(to))
      }
    }

## Error pages

`ErrorHTML`: `404.html` and `500.html` are complete, self-contained documents
(no layout, no session, no assigns beyond the two strings); every other status
renders its plain message. They are not given the root layout, as Phoenix did
not. They do not touch the session either, so an error does not write a row.

    let wcErrorStyle(): String {
      [
        "      :root{color-scheme:light dark}",
        "      body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;",
        "        background:#fbfaf7;color:#1c1a17;",
        "        font-family:\"Iowan Old Style\",\"Palatino Linotype\",Palatino,Georgia,serif}",
        "      main{max-width:32rem;padding:2rem 1.5rem}",
        "      h1{font-size:1.5rem;font-weight:600;margin:0 0 .6rem;letter-spacing:-.01em}",
        "      p{margin:0 0 1.2rem;line-height:1.65;color:#6b665e}",
        "      nav{display:flex;gap:1rem;flex-wrap:wrap;font-size:.85rem;",
        "        font-family:-apple-system,BlinkMacSystemFont,\"Segoe UI\",Helvetica,Arial,sans-serif}",
        "      a{color:#8a3324;text-decoration:none;border-bottom:1px solid #e0dbd2;padding-bottom:1px}",
        "      a:hover{border-bottom-color:#8a3324}",
        "      @media (prefers-color-scheme:dark){",
        "        body{background:#16150f;color:#e9e4d9}",
        "        p{color:#a49e91}",
        "        a{color:#e0a48a;border-bottom-color:#2e2b24}",
        "      }",
      ].join("\n") { (l: String): String => l }
    }

    export let webErrorDocument(heading: String, body: String): String {
      hjoin([
        "<!DOCTYPE html>\n",
        h("html", attr("lang", "en"), [
          "\n  ",
          h("head", "", [
            "\n    ",
            hv("meta", attr("charset", "utf-8")), "\n    ",
            hv("meta", "${attr("name", "viewport")}${attr("content", "width=device-width, initial-scale=1")}"), "\n    ",
            hv("meta", "${attr("name", "robots")}${attr("content", "noindex")}"), "\n    ",
            h("title", "", htext("${heading} · Marginalia")), "\n    ",
            h("style", "", ["\n", hraw(wcErrorStyle()), "\n    "]),
            "\n  ",
          ]),
          "\n  ",
          h("body", "", [
            "\n    ",
            h("main", "", [
              "\n      ",
              h("h1", "", htext(heading)), "\n      ",
              h("p", "", htext(body)), "\n      ",
              h("nav", "", [
                "\n        ",
                h("a", attr("href", "/"), htext("Marginalia")), "\n        ",
                h("a", attr("href", "/cases"), htext("Cases")), "\n        ",
                h("a", attr("href", "/drafts"), htext("Drafts")), "\n        ",
                h("a", attr("href", "/reading"), htext("Readings")), "\n      ",
              ]),
              "\n    ",
            ]),
            "\n  ",
          ]),
          "\n",
        ]),
        "\n",
      ])
    }

    export let webNotFound(ctx: Ctx): Response {
      httpHtml(404, webErrorDocument(
        "Nothing at that address",
        "The link may be old, or the draft may have been taken down. Nothing is lost by following a wrong address.",
      ))
    }

    export let webServerError(ctx: Ctx): Response {
      httpHtml(500, webErrorDocument(
        "Something broke",
        "That is this end, not yours, and it has been logged. Trying again in a moment is worth doing — most of what breaks here is transient.",
      ))
    }

The plain status message of any other template.

    export let webForbidden(ctx: Ctx): Response {
      httpHtml(403, "Forbidden")
    }

## UI state

The few things a LiveView kept in assigns that the database does not know (the
open panel, the chosen view, a filter string) live in the session's `ui` map.
Keys are strings the page picks, by convention `<page>:<key>`. Values are
strings; `uiPutJson` stores a JSON tree as its text and `uiGetJson` parses it
back. Keep it small: it is one column of one row, rewritten on every change.

    export let uiGet(ctx: Ctx, key: String): String? {
      let m = ctx.session.ui;
      if (m.has(key)) { m.getOr(key, "") } else { null }
    }

    export let uiPut(ctx: Ctx, key: String, value: String): Void {
      ctx.session.ui = wcMapPut(ctx.session.ui, key, value);
      ctx.session.dirty = true;
    }

    export let uiDelete(ctx: Ctx, key: String): Void {
      ctx.session.ui = wcMapDel(ctx.session.ui, key);
      ctx.session.dirty = true;
    }

    export let uiPutJson(ctx: Ctx, key: String, value: JsonSyntaxTree): Void throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      value.produce(p);
      uiPut(ctx, key, p.toJsonString());
    }

A stored value that is not JSON reads as absent.

    export let uiGetJson(ctx: Ctx, key: String): JsonSyntaxTree? {
      let s = uiGet(ctx, key);
      if (s != null) {
        let tree: JsonSyntaxTree? = parseJson(s) orelse null;
        tree
      } else { null }
    }
