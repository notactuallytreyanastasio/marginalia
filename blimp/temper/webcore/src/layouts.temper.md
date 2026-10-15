# Layouts

`MarginaliaWeb.Layouts`: the root and bare layouts (the HTML document), the
head metadata, and the app layout (the header with the nav, the main region,
the flash group).

    let { Scope } = import("accounts/src");
    let { sysGetEnv } = import("sys/src");
    let { attr, h, hv, htext, hraw, hjoin } = import("html/src");

## Constants

    export let webTagline(): String { "Someone who has actually read the whole thing" }

    export let webPitch(): String {
      "Upload a draft. It reads end to end, maps what's on the page, and argues with you in the margin — a thread on any paragraph, anchored to your own sentences."
    }

    export let webOgAlt(): String {
      "Marginalia, a reader for drafts. A note in the margin reads: your opening promises a book about grief, chapter nine is the best thing here, and it belongs to a different one."
    }

    export let webTitleSuffix(): String { " · Marginalia" }

## Page metadata

`title` is the page title without the site suffix (null for the tagline).
`robots` is only emitted when set. `image` and `url` may be a path or an
absolute URL.

    export class PageMeta(
      public title: String?,
      public description: String?,
      public robots: String?,
      public image: String?,
      public imageAlt: String?,
      public url: String?,
    ) {}

A page that only has a title.

    export let webMeta(title: String?): PageMeta {
      new PageMeta(title, null, null, null, null, null)
    }

    export let webMetaDefault(): PageMeta { webMeta(null) }

`Endpoint.url()`: the site origin, from `MARGINALIA_ORIGIN`, default
`http://localhost:4000`. One trailing slash is dropped.

    export let webOrigin(): String {
      let v = sysGetEnv("MARGINALIA_ORIGIN");
      let o = if (v != null && v != "") { wcOr(v, "") } else { "http://localhost:4000" };
      let parts = o.split("/");
      if (parts.length > 3 && parts.getOr(parts.length - 1, "x") == "") {
        parts.slice(0, parts.length - 1).join("/") { (p: String): String => p }
      } else { o }
    }

`absolute(v)`: an `http...` value is returned unchanged, anything else is
appended to the origin.

    export let webAbsolute(v: String): String {
      if (wcStartsWith(v, "http")) { v } else { "${webOrigin()}${v}" }
    }

The title as the browser shows it: `<page title> · Marginalia`, the tagline
when there is none (`live_title` appends the suffix to the default too).

    export let webDocumentTitle(meta: PageMeta): String {
      let t = meta.title;
      "${if (t != null) { t } else { webTagline() }}${webTitleSuffix()}"
    }

## head_meta/1

Every tag, in the Phoenix order. `og:title` and `twitter:title` carry the bare
title with no suffix.

    export let webHeadMeta(ctx: Ctx, meta: PageMeta): List<AnyValue> {
      let t = meta.title;
      let title = if (t != null) { t } else { webTagline() };
      let d = meta.description;
      let description = if (d != null) { d } else { webPitch() };
      let im = meta.image;
      let image = webAbsolute(if (im != null) { im } else { "/images/og.png" });
      let ia = meta.imageAlt;
      let imageAlt = if (ia != null) { ia } else { webOgAlt() };
      let u = meta.url;
      let canonical = webAbsolute(if (u != null) { u } else { "/" });
      let robots = meta.robots;
      [
        h("title", "${attr("data-default", webTagline())}${attr("data-suffix", webTitleSuffix())}", htext(webDocumentTitle(meta))),
        "\n",
        if (robots != null) { [hv("meta", "${attr("name", "robots")}${attr("content", robots)}"), "\n"] } else { [] },
        wcMetaName("description", description),
        wcMetaProp("og:type", "website"),
        wcMetaProp("og:site_name", "Marginalia"),
        wcMetaProp("og:title", title),
        wcMetaProp("og:description", description),
        wcMetaProp("og:url", canonical),
        hv("link", "${attr("rel", "canonical")}${attr("href", canonical)}"),
        "\n",
        wcMetaProp("og:image", image),
        wcMetaProp("og:image:width", "2400"),
        wcMetaProp("og:image:height", "1260"),
        wcMetaProp("og:image:alt", imageAlt),
        wcMetaName("twitter:card", "summary_large_image"),
        wcMetaName("twitter:title", title),
        wcMetaName("twitter:description", description),
        wcMetaName("twitter:image", image),
        wcMetaName("theme-color", "#fbfaf7"),
      ]
    }

    let wcMetaName(name: String, content: String): List<AnyValue> {
      [hv("meta", "${attr("name", name)}${attr("content", content)}"), "\n"]
    }

    let wcMetaProp(property: String, content: String): List<AnyValue> {
      [hv("meta", "${attr("property", property)}${attr("content", content)}"), "\n"]
    }

## The document

The theme script is copied byte for byte from `root.html.heex` (it sets
`data-theme` before first paint and listens for `phx:set-theme`). The
stylesheet and script URLs carry `?v=<MARGINALIA_ASSET_VERSION>` when that
variable is set, because `/assets/` files are served with a year-long
`Cache-Control` and a new build must get a new URL. `phx-track-static` is gone
with the `Freshness` hook it served.

    let wcThemeScriptLines(): List<String> {
      [
        "      (() => {",
        "        const systemTheme = () => matchMedia(\"(prefers-color-scheme: dark)\").matches ? \"dark\" : \"light\";",
        "",
        "        const setTheme = (theme) => {",
        "          if (theme === \"system\") {",
        "            localStorage.removeItem(\"phx:theme\");",
        "            document.documentElement.setAttribute(\"data-theme\", systemTheme());",
        "            document.documentElement.setAttribute(\"data-theme-source\", \"system\");",
        "          } else {",
        "            localStorage.setItem(\"phx:theme\", theme);",
        "            document.documentElement.setAttribute(\"data-theme\", theme);",
        "            document.documentElement.setAttribute(\"data-theme-source\", \"user\");",
        "          }",
        "        };",
        "        if (!document.documentElement.hasAttribute(\"data-theme\")) {",
        "          setTheme(localStorage.getItem(\"phx:theme\") || \"system\");",
        "        }",
        "        window.addEventListener(\"storage\", (e) => e.key === \"phx:theme\" && setTheme(e.newValue || \"system\"));",
        "        window.addEventListener(\"phx:set-theme\", (e) => setTheme(e.target.dataset.phxTheme));",
        "",
        "        matchMedia(\"(prefers-color-scheme: dark)\").addEventListener(\"change\", (e) => {",
        "          if (document.documentElement.getAttribute(\"data-theme-source\") === \"system\") {",
        "            document.documentElement.setAttribute(\"data-theme\", systemTheme());",
        "          }",
        "        });",
        "      })();",
      ]
    }

    export let webThemeScript(): String {
      wcThemeScriptLines().join("\n") { (l: String): String => l }
    }

    export let webAssetVersion(): String? {
      let v = sysGetEnv("MARGINALIA_ASSET_VERSION");
      if (v != null && v != "") { v } else { null }
    }

    let wcAssetUrl(path: String): String {
      let v = webAssetVersion();
      if (v != null) { "${path}?v=${v}" } else { path }
    }

    let wcDocument(ctx: Ctx, meta: PageMeta, body: List<AnyValue>): List<AnyValue> {
      [
        "<!DOCTYPE html>\n",
        h("html", attr("lang", "en"), [
          "\n",
          h("head", "", [
            "\n",
            hv("meta", attr("charset", "utf-8")), "\n",
            hv("meta", "${attr("name", "viewport")}${attr("content", "width=device-width, initial-scale=1")}"), "\n",
            hv("meta", "${attr("name", "csrf-token")}${attr("content", webCsrfToken(ctx))}"), "\n",
            webHeadMeta(ctx, meta),
            hv("link", "${attr("rel", "stylesheet")}${attr("href", wcAssetUrl("/assets/css/app.css"))}"), "\n",
            h("script", " defer${attr("type", "text/javascript")}${attr("src", wcAssetUrl("/assets/js/app.js"))}", []), "\n",
            "<script>\n", hraw(webThemeScript()), "\n    </script>\n",
          ]),
          "\n",
          h("body", "", ["\n", body, "\n"]),
          "\n",
        ]),
        "\n",
      ]
    }

`root.html.heex`: the body is the inner content.

    export let webRootLayout(ctx: Ctx, meta: PageMeta, body: List<AnyValue>): List<AnyValue> {
      wcDocument(ctx, meta, body)
    }

`bare.html.heex` is byte-identical to the root layout except for a comment that
renders nothing. The landing page uses it and has no app header.

    export let webBareLayout(ctx: Ctx, meta: PageMeta, body: List<AnyValue>): List<AnyValue> {
      wcDocument(ctx, meta, body)
    }

## The main region

What `blimp.js` replaces on an event or a poll is the inside of `#main`. The
Phoenix `<main>` held `<div class="space-y-4">`; that div carries `data-poll`
when the page is waiting for background work. It is on the inner div and not on
`<main>` so that it disappears when the work is done: a morph syncs a child's
attributes but never the region element's own, and a `data-poll` that could not
be removed would poll forever.

    let wcPollAttr(poll: Int?): String {
      if (poll != null) { attr("data-poll", poll.toString()) } else { "" }
    }

    export let webMainInner(inner: List<AnyValue>, poll: Int?): List<AnyValue> {
      h("div", "${attr("class", "space-y-4")}${wcPollAttr(poll)}", ["\n", inner, "\n"])
    }

A page with the bare layout has no `<main>`; its `#main` is a box that does not
lay out (`display: contents`), so the page's own markup keeps its geometry.

    export let webBareMainInner(inner: List<AnyValue>, poll: Int?): List<AnyValue> {
      h("div", "${attr("style", "display:contents")}${wcPollAttr(poll)}", ["\n", inner, "\n"])
    }

    export let webBareMain(inner: List<AnyValue>, poll: Int?): List<AnyValue> {
      h("div", "${attr("id", "main")}${attr("style", "display:contents")}", [webBareMainInner(inner, poll)])
    }

## app/1

The header, the main region, the flash group. `bleed` drops the page padding
(`class=""` on `<main>`). `flash` is what the page is showing. The nav has three
states; the labels and hrefs are the HEEx's:

* a visitor: Cases, Log in
* a guest: Cases, Drafts, New draft, "guest", the `mg-btn sm` button "Keep my drafts"
* a user: Cases, Drafts, Linked, Cuts, Methods, New draft, the email, Log out

Log out was `<a href data-method="delete">` handled by phoenix_html's JS; there
is none here, so it is a `<button>` in a small POST form carrying
`_method=delete` and the CSRF token, to `/users/log-out`. The nav's CSS styles
`nav button` like `nav a`.

    let wcLink(href: String, label: String): List<AnyValue> {
      [h("a", attr("href", href), htext(label)), "\n"]
    }

    let wcLogoutForm(ctx: Ctx): List<AnyValue> {
      h("form", "${attr("method", "post")}${attr("action", "/users/log-out")}${attr("style", "display:contents")}", [
        hv("input", "${attr("type", "hidden")}${attr("name", "_method")}${attr("value", "delete")}"),
        webCsrfField(ctx),
        h("button", attr("type", "submit"), htext("Log out")),
      ])
    }

    let wcNav(ctx: Ctx): List<AnyValue> {
      let user = ctx.scope.user;
      if (user != null) {
        if (user.isGuest) {
          [
            wcLink("/cases", "Cases"),
            wcLink("/works", "Drafts"),
            wcLink("/works/new", "New draft"),
            h("span", attr("class", "text-[var(--mg-dim)] opacity-70"), htext("guest")), "\n",
            [h("a", "${attr("href", "/users/register")}${attr("class", "mg-btn sm")}", htext("Keep my drafts")), "\n"],
          ]
        } else {
          [
            wcLink("/cases", "Cases"),
            wcLink("/works", "Drafts"),
            wcLink("/links", "Linked"),
            wcLink("/cuts", "Cuts"),
            wcLink("/stacks", "Methods"),
            wcLink("/works/new", "New draft"),
            wcLink("/users/settings", user.email),
            wcLogoutForm(ctx),
          ]
        }
      } else {
        [wcLink("/cases", "Cases"), wcLink("/users/log-in", "Log in")]
      }
    }

    export let webAppLayout(
      ctx: Ctx,
      inner: List<AnyValue>,
      poll: Int?,
      bleed: Boolean,
      flash: Map<String, String>,
    ): List<AnyValue> {
      [
        h("header", attr("class", "mg-bar"), [
          h("a", "${attr("href", "/")}${attr("class", "mg-brand")}", ["Marginalia ", h("span", "", htext("a reader for drafts"))]),
          "\n",
          h("nav", "", ["\n", wcNav(ctx)]),
        ]),
        "\n",
        h("main", "${attr("id", "main")}${attr("class", if (bleed) { "" } else { "px-4 py-8 sm:px-6 lg:px-8" })}", [
          webMainInner(inner, poll),
        ]),
        "\n",
        cFlashGroup(flash, null),
        "\n",
      ]
    }
