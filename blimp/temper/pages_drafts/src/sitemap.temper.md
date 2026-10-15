# GET /sitemap.xml

`SitemapController.index`. What a crawler is told exists: several hundred
public pages and almost none reachable by following links.

The Phoenix answer was cached for 30 minutes (`Marginalia.Cache`). A forked
child per request has no memory to keep it in, and the answer is a handful of
queries (the owner's drafts, one count per draft, the pairs, the published
folders), so it is built on every request.

    let { Ctx, webOrigin } = import("webcore/src");
    let { Response } = import("http/src");
    let { casesPublished, CaseStudy } = import("cases/src");
    let { Work, worksPublicDrafts, worksRevisionCount } = import("works/src");
    let { PublicLink, linksPublicLinks } = import("links/src");
    let { Folder, foldersPublished } = import("folders/src");
    let { sysJoin } = import("sys/src");

## The list

In this order, each path once (`Enum.uniq`): the entry points; each published
case and its reading; each public draft, with its changes page only when it has
a revision; each public pair; each published folder. Reading steps and
`/cases/:slug/read/:lead` are not listed.

    class PdPaths(public order: ListBuilder<String>, public seen: MapBuilder<String, Boolean>) {
      public add(path: String): Void {
        if (!seen.has(path)) {
          seen.set(path, true);
          order.add(path);
        }
      }
    }

    let pdSitemapPaths(ctx: Ctx): List<String> throws Bubble {
      let out = new PdPaths(new ListBuilder<String>(), new MapBuilder<String, Boolean>());
      for (let p of ["/", "/cases", "/drafts", "/linked", "/reading", "/works/new"]) {
        out.add(p);
      }
      for (let c of casesPublished(ctx.db)) {
        out.add("/cases/${c.slug}");
        out.add("/cases/${c.slug}/read");
      }
      for (let w of worksPublicDrafts(ctx.db, pdOwnerId(ctx))) {
        out.add("/drafts/${w.slug}");
        if (worksRevisionCount(ctx.db, w.id) > 0) {
          out.add("/drafts/${w.slug}/changes");
        }
      }
      for (let r of linksPublicLinks(ctx.db)) {
        out.add("/linked/${r.link.link.id.toString()}");
      }
      for (let f of foldersPublished(ctx.db)) {
        let slug = f.slug;
        if (slug != null) { out.add("/reading/${slug}"); }
      }
      out.order.toList()
    }

## The document

`&`, `<` and `>` are escaped, in that order; quotes are not. The namespace is
spelled `sitemap.org`, not the standard `sitemaps.org`, which is what the
Elixir emitted and what the og test and any scraper of the old site saw; a
strict validator would reject it. Kept, and listed in the report. There is no
`lastmod`, `changefreq` or `priority`.

    let pdXmlEscape(s: String): String {
      let amp = s.split("&").join("&amp;") { (p: String): String => p };
      let lt = amp.split("<").join("&lt;") { (p: String): String => p };
      lt.split(">").join("&gt;") { (p: String): String => p }
    }

    let pdSitemapLine(origin: String, path: String): String {
      "  <url><loc>${pdXmlEscape("${origin}${path}")}</loc></url>"
    }

    export let renderSitemap(origin: String, paths: List<String>): String {
      let lines = new ListBuilder<String>();
      lines.add("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
      lines.add("<urlset xmlns=\"http://www.sitemap.org/schemas/sitemap/0.9\">");
      var i = 0;
      while (i < paths.length) {
        lines.add(pdSitemapLine(origin, paths[i]));
        i += 1;
      }
      lines.add("</urlset>");
      sysJoin(lines.toList(), "\n")
    }

## The route

The route is in the `:browser` pipeline, which `accepts ["html"]`: a request
whose `Accept` header names neither `text/html` nor `*/*` is refused with 406
before the controller runs (notes/web-public.md section 13, item 18). A
request with no `Accept` at all is let through, as Plug does. The answer sets
no session cookie: a crawler gets no row in `sessions`.

    let pdAcceptsHtml(ctx: Ctx): Boolean {
      let accept = ctx.req.header("accept");
      if (accept != null) {
        pdHas(accept, "text/html") || pdHas(accept, "*/*") || pdHas(accept, "text/*")
      } else { true }
    }

    export let pagesDraftsSitemap(ctx: Ctx): Response throws Bubble {
      if (pdAcceptsHtml(ctx)) {
        new Response(
          200,
          [new Pair("Content-Type", "application/xml; charset=utf-8")],
          renderSitemap(webOrigin(), pdSitemapPaths(ctx)),
        )
      } else {
        new Response(406, [new Pair("Content-Type", "text/html; charset=utf-8")], "Not Acceptable")
      }
    }
