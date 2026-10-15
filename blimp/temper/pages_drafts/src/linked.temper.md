# Linked drafts: /linked and /linked/:id

`LinkedLive.Index` and `LinkedLive.Show`. Pairs of the owner's drafts read
against each other, and the edges between them. The scoping is the point: a
pair is two drafts at once, so `linksPublicLink` insists that BOTH belong to
the owner and that the pair found something.

    let { Ctx, webPage, webEventReply, uiGet, uiPut, uiDelete } = import("webcore/src");
    let { Response, httpHtml } = import("http/src");
    let { JsonObject, JsonString } = import("std/json");
    let { h, hv, htext, attr } = import("html/src");
    let { sysUtf8Downcase } = import("sys/src");
    let { Work } = import("works/src");
    let { PublicLink, LinkWorks, LinkEdgeEnds, linksPublicLinks, linksPublicLink, linksEdges } = import("links/src");

## GET /linked

The filter string and the number shown are LiveView assigns that the page
reset on every mount; here they live in the session's UI state, and a plain
page load clears them, so a visit starts from the whole list as it did.

    let pdLinkedFilterKey(): String { "linked:filter" }
    let pdLinkedLimitKey(): String { "linked:limit" }
    let pdLinkedPage(): Int { 40 }

    export class LinkedIndexState(
      public rows: List<PublicLink>,
      public filter: String,
      public limit: Int,
    ) {}

`Links.public_links/0`: strongest first, most tensions and then most edges;
pairs that found nothing are not in it.

    export let loadLinkedIndex(ctx: Ctx): LinkedIndexState throws Bubble {
      if (!ctx.isAjax) {
        uiDelete(ctx, pdLinkedFilterKey());
        uiDelete(ctx, pdLinkedLimitKey());
      }
      let saved = uiGet(ctx, pdLinkedFilterKey());
      let filter = if (saved != null) { saved } else { "" };
      let savedLimit = uiGet(ctx, pdLinkedLimitKey());
      var limit = pdLinkedPage();
      if (savedLimit != null) {
        let n = pdParseInt(savedLimit);
        if (n != null) { limit = n; }
      }
      new LinkedIndexState(linksPublicLinks(ctx.db), filter, limit)
    }

The rows whose either title contains the query, case-insensitively (a plain
substring; an empty query keeps all), then the first `limit` of them.

    let pdLinkedMatches(r: PublicLink, query: String): Boolean {
      if (query == "") { return true; }
      let q = sysUtf8Downcase(query);
      pdHas(sysUtf8Downcase(r.link.aWork.title), q) || pdHas(sysUtf8Downcase(r.link.bWork.title), q)
    }

    let pdLinkedFound(state: LinkedIndexState): List<PublicLink> {
      state.rows.filter { (r: PublicLink): Boolean => pdLinkedMatches(r, state.filter) }
    }

    let pdLinkedShown(found: List<PublicLink>, limit: Int): List<PublicLink> {
      if (found.length > limit) { found.slice(0, limit) } else { found }
    }

    let pdLinkedTensions(rows: List<PublicLink>): Int {
      var n = 0;
      for (let r of rows) {
        if (r.tensions > 0) { n += 1; }
      }
      n
    }

### Render

The row's class is `has-tension` or the empty string (`class=""` is emitted).
`1 edges` is not singularised; `1 tension` and `2 tensions` are.

    let pdLinkedRow(r: PublicLink): List<AnyValue> {
      let tension = if (r.tensions > 0) {
        h("span", attr("class", "tension-count"), htext(" · ${r.tensions.toString()} tension${pdS(r.tensions)}"))
      } else { [] };
      h("li", "${attr("id", "link-${r.link.link.id.toString()}")}${attr("class", if (r.tensions > 0) { "has-tension" } else { "" })}", [
        h("a", "${attr("href", "/linked/${r.link.link.id.toString()}")}${attr("class", "t")}",
          htext("${r.link.aWork.title} ↔ ${r.link.bWork.title}")),
        h("p", attr("class", "mg-meta"), [
          htext("${r.edges.toString()} edges"),
          tension,
        ]),
      ])
    }

`Show <min(40, left)> more`, then `of <left> left`.

    let pdLinkedMore(found: List<PublicLink>, shown: List<PublicLink>): List<AnyValue> {
      if (found.length > shown.length) {
        let left = found.length - shown.length;
        let step = if (left < pdLinkedPage()) { left } else { pdLinkedPage() };
        h("div", attr("class", "lk-more"),
          h("button", "${attr("class", "mg-btn sm")}${attr("phx-click", "more")}", [
            htext("Show ${step.toString()} more "),
            h("span", attr("class", "mg-meta"), htext("of ${left.toString()} left")),
          ]))
      } else { [] }
    }

The empty-state line is shown whenever nothing is found, an empty query
included, so with no public pairs at all it reads `Nothing matches “”.`
(notes/web-public.md section 13, item 8).

    export let renderLinkedIndex(ctx: Ctx, state: LinkedIndexState): List<AnyValue> {
      let found = pdLinkedFound(state);
      let shown = pdLinkedShown(found, state.limit);
      [
        h("div", attr("class", "lx"), [
          h("h1", "", htext("Linked drafts")),
          h("p", attr("class", "lede"), htext("Two drafts read against each other, with every edge the pass found: what develops what, what pays off a promise the other made, and where the two argue. The direction is part of the claim.")),
          h("p", attr("class", "mg-meta"),
            htext("${state.rows.length.toString()} pairs · ${pdLinkedTensions(state.rows).toString()} of them contain a tension, and those are first")),
          h("form", "${attr("phx-change", "filter")}${attr("id", "lk-filter")}${attr("class", "lk-filter")}",
            hv("input", "${attr("type", "text")}${attr("name", "q")}${attr("value", state.filter)}${attr("placeholder", "narrow by title — a case name, a chapter number")}${attr("autocomplete", "off")}")),
          if (found.length == 0) {
            h("p", attr("class", "mg-empty"), htext("Nothing matches “${state.filter}”."))
          } else { [] },
          h("ul", attr("class", "mg-rows"), shown.map { (r: PublicLink): List<AnyValue> => pdLinkedRow(r) }),
          pdLinkedMore(found, shown),
        ]),
      ]
    }

    export let pagesDraftsLinkedIndexPage(ctx: Ctx): Response throws Bubble {
      webPage(
        ctx,
        pdMeta("Linked drafts", "Pairs of drafts read against each other, with the edges between them: what develops what, what pays off what, and where they argue.", "index, follow"),
        renderLinkedIndex(ctx, loadLinkedIndex(ctx)),
        null, "app",
      )
    }

### Events

`filter` with `q`: the filter becomes `q` and the limit goes back to 40. `more`:
the limit grows by 40. The page is answered from the database again (the state
is only these two numbers and a string).

    let pdPayloadString(payload: JsonObject, key: String): String {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) { v.content } else { "" }
    }

    export let handleLinkedIndex(ctx: Ctx, event: String, payload: JsonObject): Void throws Bubble {
      if (event == "filter") {
        uiPut(ctx, pdLinkedFilterKey(), pdPayloadString(payload, "q"));
        uiPut(ctx, pdLinkedLimitKey(), pdLinkedPage().toString());
      } else if (event == "more") {
        let before = loadLinkedIndex(ctx);
        uiPut(ctx, pdLinkedLimitKey(), (before.limit + pdLinkedPage()).toString());
      } else {
        console.log("pages_drafts: /linked has no event ${event}");
        bubble()
      }
    }

    export let pagesDraftsLinkedIndexEvent(ctx: Ctx, event: String, payload: JsonObject): Response throws Bubble {
      handleLinkedIndex(ctx, event, payload);
      webEventReply(ctx, renderLinkedIndex(ctx, loadLinkedIndex(ctx)), [], null, null)
    }

## GET /linked/:id

`Links.edges/1` has the rationale's bare `A` and `B` and `Manuscript A` already
turned into the drafts' names, so this page shows them resolved (the index of
cases does not). The groups come in a fixed order, then any other type that
occurs; only types that occur are shown.

    export class LinkedGroup(public kind: String, public edges: List<LinkEdgeEnds>) {}

    export class LinkedShowState(
      public pair: LinkWorks,
      public groups: List<LinkedGroup>,
      public total: Int,
    ) {}

    let pdLinkedKindOrder(): List<String> {
      ["tension", "answers", "pays_off", "develops", "requires", "echoes"]
    }

    let pdEdgesOfKind(edges: List<LinkEdgeEnds>, kind: String): List<LinkEdgeEnds> {
      edges.filter { (e: LinkEdgeEnds): Boolean => e.edge.edgeType == kind }
    }

The types present that are not in the fixed order, in the order they first
occur.

    let pdOtherKinds(edges: List<LinkEdgeEnds>): List<String> {
      let fixed = pdLinkedKindOrder();
      let out = new ListBuilder<String>();
      for (let e of edges) {
        let kind = e.edge.edgeType;
        var known = false;
        for (let k of fixed) {
          if (k == kind) { known = true; }
        }
        for (let k of out.toList()) {
          if (k == kind) { known = true; }
        }
        if (!known) { out.add(kind); }
      }
      out.toList()
    }

    let pdGroupEdges(edges: List<LinkEdgeEnds>): List<LinkedGroup> {
      let kinds = new ListBuilder<String>();
      for (let k of pdLinkedKindOrder()) { kinds.add(k); }
      for (let k of pdOtherKinds(edges)) { kinds.add(k); }
      let out = new ListBuilder<LinkedGroup>();
      for (let k of kinds.toList()) {
        let matching = pdEdgesOfKind(edges, k);
        if (matching.length > 0) { out.add(new LinkedGroup(k, matching)); }
      }
      out.toList()
    }

    export let loadLinkedShow(ctx: Ctx, pair: LinkWorks): LinkedShowState throws Bubble {
      let edges = linksEdges(ctx.db, pair.link);
      new LinkedShowState(pair, pdGroupEdges(edges), edges.length)
    }

### Render

The quote under an edge is the from node's raw quote; the to node's is not
shown. A node that is missing prints nothing (the load bubbles on a missing
node, so this cannot happen here).

    let pdEdgeCard(kind: String, e: LinkEdgeEnds): List<AnyValue> {
      let why = e.edge.rationale;
      let quote = e.from.quote;
      h("div", attr("class", "lk-edge ${kind}"), [
        h("div", attr("class", "lk-ends"), [
          h("span", attr("class", "from"), htext(e.from.title)),
          h("span", attr("class", "arrow"), htext("${pdSpaced(kind)} →")),
          h("span", attr("class", "to"), htext(e.to.title)),
        ]),
        if (why != null) {
          h("p", attr("class", "why"), htext(why))
        } else { [] },
        if (quote != null) {
          h("blockquote", attr("class", "lk-quote"), htext(quote))
        } else { [] },
      ])
    }

    let pdGroupSection(g: LinkedGroup): List<AnyValue> {
      h("section", attr("class", "lk-group"), [
        h("h2", attr("class", "mg-label"), htext("${pdSpaced(g.kind)} · ${g.edges.length.toString()}")),
        g.edges.map { (e: LinkEdgeEnds): List<AnyValue> => pdEdgeCard(g.kind, e) },
      ])
    }

    export let renderLinkedShow(ctx: Ctx, state: LinkedShowState): List<AnyValue> {
      let a = state.pair.aWork;
      let b = state.pair.bWork;
      [
        h("div", attr("class", "lx"), [
          h("div", attr("class", "mg-meta"),
            h("a", attr("href", "/linked"), htext("← Linked drafts"))),
          h("h1", "", htext("${a.title} ↔ ${b.title}")),
          h("p", attr("class", "lede"), htext("${state.total.toString()} edges. Each names a part of one draft and a part of the other, and the direction is part of the claim.")),
          h("p", attr("class", "mg-meta"), [
            h("a", attr("href", "/drafts/${a.slug}"), htext(a.title)),
            " · ",
            h("a", attr("href", "/drafts/${b.slug}"), htext(b.title)),
          ]),
          state.groups.map { (g: LinkedGroup): List<AnyValue> => pdGroupSection(g) },
        ]),
      ]
    }

A pair that is not the owner's, or that found nothing, or that does not exist
is `No such pair.` and the list. An id that is no integer is a 400, as the
cast error was in Phoenix.

    let pdLinkedShowFound(ctx: Ctx, pair: LinkWorks): Response throws Bubble {
      let state = loadLinkedShow(ctx, pair);
      webPage(
        ctx,
        pdMeta("${pair.aWork.title} ↔ ${pair.bWork.title}", "${state.total.toString()} edges between two drafts.", "index, follow"),
        renderLinkedShow(ctx, state),
        null, "app",
      )
    }

    let pdLinkedShowLookup(ctx: Ctx, id: Int): Response throws Bubble {
      let pair = linksPublicLink(ctx.db, id);
      if (pair != null) {
        pdLinkedShowFound(ctx, pair)
      } else {
        pdBackTo(ctx, "/linked", "No such pair.")
      }
    }

    export let pagesDraftsLinkedShowPage(ctx: Ctx, idText: String): Response throws Bubble {
      let id = pdParseInt(idText);
      if (id != null) {
        pdLinkedShowLookup(ctx, id)
      } else {
        httpHtml(400, "Bad Request")
      }
    }
