# Tests for the pair page

The fixtures and the request helpers are those of `pages_links_test`.

    let { dbOpen, Db } = import("db/src");
    let { hjoin } = import("html/src");
    let { Scope } = import("accounts/src");
    let { Work, GraphNode, NodeParams, worksInsertNode, worksListSections } = import("works/src");
    let {
      Link, linksGetOrCreate, linksSetStatus, linksAttrsSummary, linksAttrsError, linksGet, LinkStats,
    } = import("links/src");
    let { LlmMessage, llmFake, llmRequests, LlmClient } = import("llm/src");
    let { JsonSyntaxTree, parseJson } = import("std/json");

    let tPage(fx: TFx, who: TWho, path: String): String throws Bubble {
      tBody(tGet(fx.db, who.ctx, path))
    }

    let tLinkPath(fx: TFx): String { "/links/${fx.link.id.toString()}" }

## Missing and malformed

    test("read: a link that is not there goes to the drafts with a flash") { test =>
      let fx = tFx();
      let r = tGet(fx.db, fx.me.ctx, "/links/99999");
      expectInt(test, r.resp.status, 303);
      expectText(test, tLocation(r), "/works");
      let after = tGet(fx.db, fx.me.ctx, "/links");
      expectHas(test, tBody(after), "No such link.");
    }

    test("read: a link that is not there, asked for by an event, redirects in JSON") { test =>
      let fx = tFx();
      let r = tEvent(fx.db, fx.me.ctx, "/links/99999", "toggle_chat", "{}", tNever());
      expectText(test, tRedirect(r), "/works");
    }

    test("read: an id that is not a number is a 404") { test =>
      let fx = tFx();
      expectInt(test, tGet(fx.db, fx.me.ctx, "/links/abc").resp.status, 404);
    }

## While the pass runs

    test("waiting: a pending pair shows both maps and says what the arcs are") { test =>
      let bare = tBare();
      let body = tBody(tGet(bare.db, bare.me.ctx, "/links/${bare.link.id.toString()}"));
      expectHas(test, body, "id=\"wiring\"");
      expectHas(test, body, "phx-hook=\"Wiring\"");
      expectHas(test, body, "data-a=\"[&quot;a beat in First&quot;]\"");
      expectHas(test, body, "data-b=\"[&quot;a beat in Second&quot;]\"");
      expectHas(test, body, "<span class=\"mg-label\">relating</span>");
      expectHas(test, body, "<h2>First <span class=\"x\">↔</span> Second</h2>");
      expectHas(test, body, "Reading both maps against each other — 1 nodes on one side, 1 on the other, 1 possible pairs. A minute or two.");
      expectHas(test, body, "This page fills in on its own.");
      expectHas(test, body, "The nodes are yours. The lines are the pass trying pairs — none of them are");
      expectHas(test, body, "<svg class=\"lw-svg\" viewBox=\"0 0 680 360\" preserveAspectRatio=\"xMidYMid meet\">");
      expectHas(test, body, "<circle cx=\"90\" cy=\"30.0\" r=\"3.5\" data-side=\"a\" data-i=\"0\" style=\"animation-delay:0ms\"></circle>");
      expectHas(test, body, "<circle cx=\"590\" cy=\"30.0\" r=\"3.5\" data-side=\"b\" data-i=\"0\" style=\"animation-delay:0ms\"></circle>");
      expectHas(test, body, "<g class=\"arcs\"></g>");
      expectHas(test, body, "<span class=\"arrow\" aria-hidden=\"true\">⇢</span>");
      expectLacks(test, body, "id=\"split\"");
      expectLacks(test, body, "id=\"follow\"");
    }

    test("waiting: it polls while the pass is pending or running, and not when it failed") { test =>
      let bare = tBare();
      let path = "/links/${bare.link.id.toString()}";
      expectHas(test, tBody(tGet(bare.db, bare.me.ctx, path)), "<div class=\"space-y-4\" data-poll=\"2\">");
      linksSetStatus(bare.db, bare.link, "linking", linksAttrsError(null));
      expectHas(test, tMain(tPoll(bare.db, bare.me.ctx, path)), "data-poll=\"2\"");
      linksSetStatus(bare.db, bare.link, "failed", linksAttrsError(":truncated"));
      expectLacks(test, tMain(tPoll(bare.db, bare.me.ctx, path)), "data-poll");
    }

    test("waiting: the follow view is the same page and is just as patient") { test =>
      let bare = tBare();
      let body = tBody(tGet(bare.db, bare.me.ctx, "/links/${bare.link.id.toString()}/read?lead=${bare.a.slug}"));
      expectHas(test, body, "id=\"wiring\"");
      expectHas(test, body, "data-poll=\"2\"");
    }

    test("waiting: a failure is shown with the reason and a way to retry") { test =>
      let bare = tBare();
      linksSetStatus(bare.db, bare.link, "failed", linksAttrsError(":truncated"));
      let body = tBody(tGet(bare.db, bare.me.ctx, "/links/${bare.link.id.toString()}"));
      expectHas(test, body, "<h2>That did not go through</h2>");
      expectHas(test, body, "<p class=\"why\">:truncated</p>");
      expectHas(test, body, "<button class=\"mg-btn sm\" phx-click=\"relink\">Try again</button>");
      expectLacks(test, body, "id=\"wiring\"");
      expectLacks(test, body, "data-poll");
    }

    test("waiting: try again starts the pass again and the waiting view comes back") { test =>
      let bare = tBare();
      linksSetStatus(bare.db, bare.link, "failed", linksAttrsError(":truncated"));
      let launcher = tQueue();
      let main = tMain(tEvent(bare.db, bare.me.ctx, "/links/${bare.link.id.toString()}", "relink", "{}", launcher));
      expectReads(test, launcher, 1);
      expectHas(test, main, "id=\"wiring\"");
      expectHas(test, main, "data-poll=\"2\"");
      expectLacks(test, main, "did not go through");
    }

    test("waiting: when the pass lands the page fills in on its own, from the poll") { test =>
      let bare = tBare();
      let path = "/links/${bare.link.id.toString()}";
      expectHas(test, tBody(tGet(bare.db, bare.me.ctx, path)), "id=\"wiring\"");
      let first = tNow([tLinkerReply(bare.aNode, bare.bNode)]);
      let main = tMain(tEvent(bare.db, bare.me.ctx, path, "relink", "{}", first));
      expectLacks(test, main, "id=\"wiring\"");
      expectHas(test, main, "id=\"follow\"");
      expectLacks(test, main, "data-poll");
      let poll = tMain(tPoll(bare.db, bare.me.ctx, path));
      expectHas(test, poll, "id=\"follow\"");
      expectHas(test, poll, "First and Second part ways.");
    }

    test("waiting: a pass that read nothing leaves the pair failed with the reason") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "First", "read");
      let b = tWork(db, me.scope, "Second", "read");
      let l = linksGetOrCreate(db, a.id, b.id).ok;
      if (l != null) {
        let main = tMain(tEvent(db, me.ctx, "/links/${l.id.toString()}", "relink", "{}", tNow([])));
        expectHas(test, main, "did not go through");
        expectHas(test, main, ":not_read");
      }
    }

    test("waiting: a stranger cannot make the model read someone else's pair") { test =>
      let bare = tBare();
      let stranger = tWho(bare.db, "z@example.com");
      let launcher = tQueue();
      let r = tEvent(bare.db, stranger.ctx, "/links/${bare.link.id.toString()}", "relink", "{}", launcher);
      expectText(test, tFlash(r), "error: That pair is not yours to run.");
      expectReads(test, launcher, 0);
    }

    test("waiting: a pass whose job died is failed, not polled for ever") { test =>
      let bare = tBare();
      linksSetStatus(bare.db, bare.link, "linking", linksAttrsError(null));
      bare.db.exec("INSERT INTO runs (key, status, detail) VALUES ($1, 'crashed', 'Bubble')", [pagesLinksReadKey(bare.link.id)]);
      let main = tMain(tPoll(bare.db, bare.me.ctx, "/links/${bare.link.id.toString()}"));
      expectHas(test, main, "did not go through");
      expectHas(test, main, ":crashed: Bubble");
      expectLacks(test, main, "data-poll");
    }

    test("waiting: at most 24 dots a side, evenly sampled") { test =>
      let titles = new ListBuilder<String>();
      for (var i = 0; i < 48; ++i) { titles.add("t${i.toString()}"); }
      let dots = pagesLinksDots(titles.toList());
      expectInt(test, dots.length, 24);
      expectText(test, dots[0], "t0");
      expectText(test, dots[1], "t2");
      expectText(test, dots[23], "t46");
      expectInt(test, pagesLinksDots(["a", "b"]).length, 2);
    }

    test("waiting: a dot's height mirrors the hook's y(i, n)") { test =>
      expectText(test, pagesLinksDotY(0, 5), "30.0");
      expectText(test, pagesLinksDotY(4, 5), "330.0");
      expectText(test, pagesLinksDotY(0, 1), "30.0");
      expectText(test, pagesLinksDotY(1, 3), "180.0");
    }

    test("waiting: with no nodes on a side there are no dots to wire") { test =>
      let html = hjoin(renderLinkWaiting("A", "B", [], ["x"], "pending", null));
      expectHas(test, html, "data-a=\"[]\"");
      expectHas(test, html, "0 possible pairs");
      expectLacks(test, html, "data-side=\"a\"");
    }

## The follow view

    test("follow: a linked pair is the follow view at both addresses, and not the waiting one") { test =>
      let fx = tFx();
      for (let path of [tLinkPath(fx), "${tLinkPath(fx)}/read"]) {
        let body = tPage(fx, fx.me, path);
        expectHas(test, body, "<div class=\"fl\" id=\"follow\" phx-hook=\"Follow\">");
        expectLacks(test, body, "id=\"wiring\"");
        expectLacks(test, body, "id=\"split\"");
        expectLacks(test, body, ">Split<");
        expectLacks(test, body, "data-poll");
      }
    }

    test("follow: the page is for readers, not for search, and is titled by the two drafts") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectHas(test, body, "First · alongside Second · Marginalia");
      expectHas(test, body, "noindex, nofollow");
    }

    test("follow: both columns are rendered and addressable, headed by their drafts") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, "${tLinkPath(fx)}/read");
      expectHas(test, body, "<div class=\"fl-col lead\" id=\"fl-lead\" tabindex=\"0\">");
      expectHas(test, body, "<div class=\"fl-col other\" id=\"fl-other\" tabindex=\"0\">");
      expectHas(test, body, "<span class=\"mg-label\">Reading…</span>");
      expectHas(test, body, "<a href=\"/works/${fx.a.slug}\">First</a>");
      expectHas(test, body, "<span class=\"mg-label\">Referencing…</span>");
      expectHas(test, body, "<a href=\"/works/${fx.b.slug}\">Second</a>");
      expectHas(test, body, "<div class=\"fl-sec\">");
      expectHas(test, body, "<span class=\"mg-label\">Section 1</span>");
      expectHas(test, body, "<h2>Section 1</h2>");
    }

    test("follow: the bar: help, swap sides, the legend, the account of the pair, the count") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectHas(test, body, "<button class=\"fl-help\" phx-click=\"show_tour\" title=\"How this page works\">?</button>");
      expectHas(test, body, "<a href=\"/links/${tIdOf(fx.link)}/read?lead=${fx.b.slug}\" class=\"fl-swap\" title=\"Read the other one instead\">");
      expectHas(test, body, "<span aria-hidden=\"true\">⇄</span> swap sides");
      expectHas(test, body, "<button class=\"mg-tab on\" phx-click=\"set_only\" phx-value-only=\"all\">Everything</button>");
      expectHas(test, body, "<button class=\"mg-tab\" phx-click=\"set_only\" phx-value-only=\"tension\">tension 1</button>");
      expectHas(test, body, "<details class=\"fl-sum\">");
      expectHas(test, body, "<span class=\"mg-label\">why</span>");
      expectHas(test, body, "<span class=\"peek\">They disagree.</span>");
      expectHas(test, body, "<p>They disagree.</p>");
      expectHas(test, body, "<span class=\"fl-count\"><b>0</b> / 1 addressed</span>");
    }

    test("follow: no summary, no account of the pair") { test =>
      let fx = tFx();
      linksSetStatus(fx.db, fx.link, "linked", linksAttrsSummary(null));
      expectLacks(test, tPage(fx, fx.me, tLinkPath(fx)), "fl-sum");
    }

    test("follow: lead=<slug of the second> reads the second on the left") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, "${tLinkPath(fx)}/read?lead=${fx.b.slug}");
      expectHas(test, body, "<div class=\"fl-colhead\">\n<span class=\"mg-label\">Reading…</span>\n<a href=\"/works/${fx.b.slug}\">Second</a>");
      expectHas(test, body, "<a href=\"/links/${tIdOf(fx.link)}/read?lead=${fx.a.slug}\" class=\"fl-swap\"");
    }

    test("follow: the reference column is the one that may be swapped, the lead is not offered") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectLacks(test, body, "fl-pick");
    }

    test("follow: the paragraphs are addressable by side, and carry what the hook reads") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectHas(test, body, "id=\"blk-lead-s1p1\"");
      expectHas(test, body, "id=\"blk-other-s1p1\"");
      expectHas(test, body, "<div class=\"fl-block linked\" id=\"blk-lead-s1p1\">");
      expectHas(test, body, "<mark id=\"anchor-lead-s1p1\">A sentence long enough</mark>");
      expectHas(test, body, "<mark id=\"anchor-other-s1p1\">A sentence long enough</mark>");
      expectHas(test, body, "data-peer-ref=\"s1p1\"");
      expectHas(test, body, "data-kind=\"tension\"");
      expectHas(test, body, "data-why=\"They part.\"");
      expectHas(test, body, "data-src=\"→ a beat in Second\"");
      expectHas(test, body, "data-src=\"← a beat in First\"");
      expectHas(test, body, "data-edge=\"");
      expectHas(test, body, "<a class=\"fl-edit\" href=\"/works/${fx.a.slug}?view=read#block-s1p1\" title=\"Edit this paragraph in the draft\">edit</a>");
      expectHas(test, body, "<a class=\"fl-edit\" href=\"/works/${fx.b.slug}?view=read#block-s1p1\"");
    }

    test("follow: the chip over a paragraph says what the relation is and the entry its reason") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectHas(test, body, "<div class=\"fl-tagwrap tension\">");
      expectHas(test, body, "<span class=\"fl-tag tension\">tension</span>");
      expectHas(test, body, "<button type=\"button\" class=\"fl-jump k-tension\" data-peer-ref=\"s1p1\"");
      expectHas(test, body, "<span class=\"rel\">tension</span>");
      expectHas(test, body, "<span class=\"to\">→ a beat in Second</span>");
      expectHas(test, body, "<span class=\"why\">They part.</span>");
      expectLacks(test, body, "nowhere");
    }

    test("follow: the strip, the sheet and the idle line the hook drives are all there") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectHas(test, body, "<div class=\"fl-mid\">");
      expectHas(test, body, "<div class=\"fl-strip\" hidden>");
      expectHas(test, body, "<div class=\"fl-sheet\" hidden>");
      expectHas(test, body, "<div class=\"fl-strip-head\">");
      expectHas(test, body, "<span class=\"rel\"></span>");
      expectHas(test, body, "<span class=\"nth\"></span>");
      expectHas(test, body, "<p class=\"why\"></p>");
      expectHas(test, body, "<blockquote class=\"far\"></blockquote>");
      expectHas(test, body, "<button type=\"button\" class=\"ask\">ask about this</button>");
      expectHas(test, body, "<div class=\"fl-stack\"></div>");
      expectHas(test, body, "Scroll. Where this draft touches the other, it will be shown here.");
      expectInt(test, tCount(body, "class=\"shut\""), 1);
      expectLacks(test, body, "cite_current");
    }

    test("follow: the wire runs through the middle: two curves, two dots, two wide ones to hit") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectHas(test, body, "<svg class=\"fl-wire\" hidden>");
      expectHas(test, body, "<path class=\"w1\" fill=\"none\"></path>");
      expectHas(test, body, "<circle class=\"d2\" r=\"4\"></circle>");
      expectHas(test, body, "<path class=\"h2 hit\" fill=\"none\"></path>");
    }

    test("follow: a paragraph with no relation is plain, and there is no chip on it") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectHas(test, body, "<div class=\"fl-block\" id=\"blk-lead-s1p0\">");
      expectHas(test, body, "<div class=\"fl-block\" id=\"blk-lead-s1p2\">");
    }

## One draft, several references

    test("others: a draft with two links offers the other, and a draft with one does not") { test =>
      let fx = tFx();
      let c = tWork(fx.db, fx.me.scope, "Third", "read");
      let cn = tBeat(fx.db, c, "a beat in Third", "A sentence long enough");
      let two = linksGetOrCreate(fx.db, fx.a.id, c.id).ok;
      if (two != null) {
        linksSetStatus(fx.db, two, "linked", linksAttrsSummary("Third develops First."));
        tEdge(fx.db, two, fx.aNode, cn, "develops", "It carries on.");
      }
      let body = tPage(fx, fx.me, "${tLinkPath(fx)}?lead=${fx.a.slug}");
      expectHas(test, body, "<details class=\"fl-pick\">");
      expectHas(test, body, "<span class=\"t\">Second</span>");
      expectHas(test, body, "<span class=\"n\">2</span>");
      expectHas(test, body, "<span class=\"mg-label\">reading against this</span>");
      expectHas(test, body, "<span class=\"t\">Third</span>");
      expectHas(test, body, "<span class=\"st linked\">1 edges</span>");
      expectHas(test, body, "<a href=\"/links\" class=\"row more\">Relate it to another…</a>");
      if (two != null) {
        expectHas(test, body, "<a href=\"/links/${two.id.toString()}?lead=${fx.a.slug}\" class=\"row\">");
        let swapped = tPage(fx, fx.me, "/links/${two.id.toString()}?lead=${fx.a.slug}");
        expectHas(test, swapped, "<span class=\"t\">Third</span>");
        expectHas(test, swapped, "Third develops First.");
        expectLacks(test, swapped, "They disagree.");
      }
      let alone = tPage(fx, fx.me, "${tLinkPath(fx)}?lead=${fx.b.slug}");
      expectLacks(test, alone, "fl-pick");
    }

    test("others: a pair still being read is listed with its status") { test =>
      let fx = tFx();
      let c = tWork(fx.db, fx.me.scope, "Third", "read");
      linksGetOrCreate(fx.db, fx.a.id, c.id);
      let body = tPage(fx, fx.me, "${tLinkPath(fx)}?lead=${fx.a.slug}");
      expectHas(test, body, "<span class=\"st pending\">pending</span>");
    }

## Relations, tags and quiet stretches

A pair in which one paragraph of the novel is the near end of three edges,
each to a different paragraph of the story.

    class TFar(public db: Db, public me: TWho, public a: Work, public b: Work, public link: Link) {}

    let tFarLines(): List<String> {
      ["The kettle went cold on the counter.", "Nobody moved to fill it again.", "The window stayed open all night."]
    }

    let tFar(): TFar throws Bubble {
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWorkOf(db, me.scope, "The novel", ["He stops in the doorway and does not go through."]);
      let b = tWorkOf(db, me.scope, "The story", tFarLines());
      let made = linksGetOrCreate(db, a.id, b.id).ok;
      if (made == null) { bubble(); }
      let kinds = ["pays_off", "tension", "echoes"];
      for (var i = 0; i < 3; ++i) {
        let near = tBeat(db, a, "Near end ${(i + 1).toString()}", "He stops in the doorway");
        let far = tBeat(db, b, "Far end ${(i + 1).toString()}", tFarLines()[i].split(".")[0]);
        if (made != null) { tEdge(db, made, near, far, kinds[i], "Reason number ${(i + 1).toString()}, which the menu has room for."); }
      }
      if (made != null) {
        linksSetStatus(db, made, "linked", linksAttrsSummary(null));
        new TFar(db, me, a, b, made)
      } else { bubble() }
    }

    let tFarPage(fx: TFar, path: String): String throws Bubble {
      tBody(tGet(fx.db, fx.me.ctx, path))
    }

    test("tags: the chip counts the edges, and says when they disagree") { test =>
      let fx = tFar();
      let body = tFarPage(fx, "/links/${fx.link.id.toString()}");
      expectHas(test, body, "3 links");
      expectHas(test, body, "fl-tagwrap mixed");
      expectHas(test, body, "<span class=\"fl-tag mixed\">3 links</span>");
    }

    test("tags: one entry per edge, each with its far end and its reason") { test =>
      let fx = tFar();
      let body = tFarPage(fx, "/links/${fx.link.id.toString()}");
      for (var i = 1; i <= 3; ++i) {
        expectHas(test, body, "Far end ${i.toString()}");
        expectHas(test, body, "Reason number ${i.toString()}, which the menu has room for.");
      }
      expectTrue(test, tCount(body, "class=\"fl-jump k-") >= 3, "three buttons under the one paragraph");
    }

    test("tags: each entry carries the paragraph it snaps to, three different ones") { test =>
      let fx = tFar();
      let body = tFarPage(fx, "/links/${fx.link.id.toString()}");
      expectHas(test, body, "data-peer-ref=\"s1p1\"");
      expectHas(test, body, "data-peer-ref=\"s1p2\"");
      expectHas(test, body, "data-peer-ref=\"s1p3\"");
      expectLacks(test, body, "data-peer-ref=\"s1p4\"");
    }

    test("tags: the relation of each entry is its own, not the paragraph's") { test =>
      let fx = tFar();
      let body = tFarPage(fx, "/links/${fx.link.id.toString()}");
      for (let kind of ["pays_off", "tension", "echoes"]) {
        expectHas(test, body, "fl-jump k-${kind}");
      }
      expectHas(test, body, "<span class=\"rel\">pays off</span>");
    }

    test("tags: the legend lists every relation, by count and then by name") { test =>
      let by = new MapBuilder<String, Int>();
      by.set("tension", 2);
      by.set("pays_off", 2);
      by.set("answers", 5);
      let legend = pagesLinksLegend(new LinkStats(9, by.toMap(), 3, 3));
      expectInt(test, legend.length, 4);
      expectText(test, "${legend[0].key}/${legend[0].value}", "all/Everything");
      expectText(test, "${legend[1].key}/${legend[1].value}", "answers/answers 5");
      expectText(test, "${legend[2].key}/${legend[2].value}", "pays_off/pays off 2");
      expectText(test, "${legend[3].key}/${legend[3].value}", "tension/tension 2");
    }

    test("tags: choosing one relation keeps only its notes, and the legend shows which") { test =>
      let fx = tFar();
      let page = "/links/${fx.link.id.toString()}";
      let main = tMain(tEvent(fx.db, fx.me.ctx, page, "set_only", "{\"only\":\"tension\"}", tNever()));
      expectHas(test, main, "<button class=\"mg-tab on\" phx-click=\"set_only\" phx-value-only=\"tension\">tension 1</button>");
      expectHas(test, main, "<button class=\"mg-tab\" phx-click=\"set_only\" phx-value-only=\"all\">Everything</button>");
      expectHas(test, main, "<span class=\"fl-tag tension\">tension</span>");
      expectLacks(test, main, "k-pays_off");
      expectLacks(test, main, "k-echoes");
      let again = tMain(tEvent(fx.db, fx.me.ctx, page, "set_only", "{\"only\":\"all\"}", tNever()));
      expectHas(test, again, "<button class=\"mg-tab on\" phx-click=\"set_only\" phx-value-only=\"all\">Everything</button>");
      expectHas(test, again, "k-pays_off");
    }

    test("tags: a plain visit takes the relation from the address") { test =>
      let fx = tFar();
      let body = tFarPage(fx, "/links/${fx.link.id.toString()}/read?lead=${fx.a.slug}&only=echoes");
      expectHas(test, body, "<button class=\"mg-tab on\" phx-click=\"set_only\" phx-value-only=\"echoes\">echoes 1</button>");
      expectHas(test, body, "<span class=\"fl-tag echoes\">echoes</span>");
      expectHas(test, body, "?lead=${fx.b.slug}&amp;only=echoes");
    }

    test("tags: a far end with no paragraph says so and is not a live control") { test =>
      let fx = tFx();
      let w = tNodeOf(fx.db, fx.b, "spine", "The spine of Second");
      let extra = tBeat(fx.db, fx.a, "Another near end", "A sentence long enough");
      tEdge(fx.db, fx.link, extra, w, "answers", "It answers the whole.");
      let body = tPage(fx, fx.me, tLinkPath(fx));
      expectHas(test, body, "<span class=\"nowhere\">whole draft — no passage to jump to</span>");
      expectHas(test, body, "<button type=\"button\" class=\"fl-jump k-answers\" disabled data-edge=");
    }

    let tNodeOf(db: Db, w: Work, kind: String, title: String): GraphNode throws Bubble {
      let r = worksInsertNode(db, new NodeParams(w.id, kind, title));
      let n = r.node;
      if (n != null) { n } else { bubble() }
    }

    let tRun(blocks: List<LinksBlock>, only: String?): List<String> {
      pagesLinksCondense(blocks, only).map { (r: LinksRun): String =>
        "${if (r.gap) { "gap" } else { "block" }}:${r.blocks.length.toString()}"
      }
    }

    let tBlocks(kinds: List<String>): List<LinksBlock> {
      let out = new ListBuilder<LinksBlock>();
      var i = 0;
      while (i < kinds.length) {
        let k = kinds[i];
        let n = i + 1;
        let notes = new ListBuilder<LinksNote>();
        if (k != "") { notes.add(new LinksNote(n, k, "t", "w", null)); }
        out.add(new LinksBlock("s1p${n.toString()}", "para ${n.toString()} here", null, notes.toList()));
        i += 1;
      }
      out.toList()
    }

    test("condense: a paragraph with a relation keeps its neighbours, the rest is folded") { test =>
      let runs = tRun(tBlocks(["", "", "", "tension", "", "", "", "", ""]), null);
      expectText(test, runs.join(",") { (x: String): String => x }, "gap:2,block:1,block:1,block:1,gap:4");
    }

    test("condense: a stretch of one paragraph is shown as itself, not folded") { test =>
      let runs = tRun(tBlocks(["tension", "", "", "tension"]), null);
      expectText(test, runs.join(",") { (x: String): String => x }, "block:1,block:1,block:1,block:1");
      let single = tRun(tBlocks(["tension", "", "", "", "tension"]), null);
      expectText(test, single.join(",") { (x: String): String => x }, "block:1,block:1,block:1,block:1,block:1");
      let two = tRun(tBlocks(["", "", "", "tension", "", "", "", ""]), null);
      expectText(test, two.join(",") { (x: String): String => x }, "gap:2,block:1,block:1,block:1,gap:3");
    }

    test("condense: a draft with nothing to say to the other is one fold") { test =>
      expectText(test, tRun(tBlocks(["", "", "", ""]), null).join(",") { (x: String): String => x }, "gap:4");
      expectText(test, tRun(tBlocks([""]), null).join(",") { (x: String): String => x }, "block:1");
      expectText(test, tRun([], null).join(",") { (x: String): String => x }, "");
    }

    test("condense: only a chosen relation counts as a relation") { test =>
      let blocks = tBlocks(["", "", "", "tension", "", "", "", "echoes", "", "", ""]);
      expectText(test, tRun(blocks, "echoes").join(",") { (x: String): String => x }, "gap:6,block:1,block:1,block:1,gap:2");
      expectText(test, tRun(blocks, "answers").join(",") { (x: String): String => x }, "gap:11");
    }

    test("condense: the words of a fold are counted from the raw text") { test =>
      expectInt(test, pagesLinksWords(tBlocks(["", "", ""])), 9);
    }

    test("condense: the quiet stretch is a details with its size on the label, and its paragraphs inside") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWorkOf(db, me.scope, "Long", ["Line one.", "Line two.", "Line three.", "Line four.", "Line five.", "Line six.", "Line seven.", "Line eight."]);
      let b = tWorkOf(db, me.scope, "Other", ["Elsewhere."]);
      let l = linksGetOrCreate(db, a.id, b.id).ok;
      if (l != null) {
        tEdge(db, l, tBeat(db, a, "n1", "Line one"), tBeat(db, b, "n2", "Elsewhere"), "echoes", "Same move.");
        linksSetStatus(db, l, "linked", linksAttrsSummary(null));
        let body = tBody(tGet(db, me.ctx, "/links/${l.id.toString()}?lead=${a.slug}"));
        expectHas(test, body, "<details class=\"fl-gap\">");
        expectHas(test, body, "<span class=\"n\">6 paragraphs</span>");
        expectHas(test, body, " words</span>");
        expectHas(test, body, "<div class=\"fl-gap-body\">");
        expectHas(test, body, "<div class=\"fl-block quiet\" id=\"blk-lead-s1p8\">");
        expectLacks(test, body, "id=\"blk-other-s1p5\"");
      }
    }

## The one-time card, the walkthrough

    test("tour: a first visit is told how to work the page, and the bubble waits") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, "${tLinkPath(fx)}/read");
      expectHas(test, body, "<div class=\"fl-tour-veil\" phx-click=\"dismiss_tour\">");
      expectHas(test, body, "<div class=\"fl-tour\" phx-click-away=\"dismiss_tour\">");
      expectHas(test, body, "<h2>Two documents, read as one</h2>");
      expectHas(test, body, "The left is what you are reading. The right is the reference, and it is dimmed on purpose");
      expectHas(test, body, "<button class=\"mg-btn sm ghost\" phx-click=\"dismiss_tour\">Got it</button>");
      expectHas(test, body, "<p class=\"mg-hint\">The <strong>?</strong> in the bar brings this back.</p>");
      expectInt(test, tCount(body, "<li>"), 6);
      expectLacks(test, body, "lc-bubble");
    }

    test("tour: it is marked seen on sight, so it does not come back") { test =>
      let fx = tFx();
      tPage(fx, fx.me, tLinkPath(fx));
      let row = fx.db.one("SELECT seen_tours FROM users WHERE id = $1", [fx.me.id.toString()]);
      if (row != null) { expectHas(test, row.str("seen_tours"), "follow"); }
      let again = tPage(fx, fx.me, tLinkPath(fx));
      expectLacks(test, again, "Two documents, read as one");
      expectHas(test, again, "lc-bubble");
    }

    test("tour: dismissing it reveals the bubble, and the ? brings it back") { test =>
      let fx = tFx();
      let page = tLinkPath(fx);
      tPage(fx, fx.me, page);
      let shown = tMain(tEvent(fx.db, fx.me.ctx, page, "show_tour", "{}", tNever()));
      expectHas(test, shown, "Two documents, read as one");
      expectLacks(test, shown, "lc-bubble");
      let gone = tMain(tEvent(fx.db, fx.me.ctx, page, "dismiss_tour", "{}", tNever()));
      expectLacks(test, gone, "fl-tour-veil");
      expectLacks(test, gone, "Two documents, read as one");
      expectHas(test, gone, "lc-bubble");
    }

    test("tour: dismissing it on the very first visit leaves the page itself alone") { test =>
      let fx = tFx();
      let page = tLinkPath(fx);
      tPage(fx, fx.me, page);
      let gone = tMain(tEvent(fx.db, fx.me.ctx, page, "dismiss_tour", "{}", tNever()));
      expectHas(test, gone, "id=\"follow\"");
    }

    test("tour: the card is shown over the waiting view too") { test =>
      let bare = tBare();
      let body = tBody(tGet(bare.db, bare.me.ctx, "/links/${bare.link.id.toString()}"));
      expectHas(test, body, "Two documents, read as one");
    }

    test("walk: walk=1 starts the walkthrough, and the card stays away") { test =>
      let fx = tFx();
      let body = tPage(fx, fx.me, "${tLinkPath(fx)}/read?lead=${fx.a.slug}&walk=1");
      expectHas(test, body, "<div id=\"walk\" phx-hook=\"Walk\" data-steps=\"[");
      expectHas(test, body, "&quot;id&quot;:&quot;sides&quot;");
      expectHas(test, body, "&quot;target&quot;:&quot;.fl-colhead&quot;");
      expectHas(test, body, "&quot;act&quot;:{&quot;kind&quot;:&quot;push&quot;,&quot;event&quot;:&quot;set_only&quot;,&quot;params&quot;:{&quot;only&quot;:&quot;tension&quot;}}");
      expectHas(test, body, "&quot;act&quot;:{&quot;kind&quot;:&quot;hop&quot;,&quot;to&quot;:&quot;case_read&quot;}");
      expectHas(test, body, "<div class=\"mg-walk-ring\" hidden></div>");
      expectHas(test, body, "<button class=\"mg-btn sm ghost ml-auto end\">end</button>");
      expectHas(test, body, "Real documents, really read: these are the Court&#39;s own files and nothing here is a fixture.");
      expectLacks(test, body, "fl-tour-veil");
      expectHas(test, body, "lc-bubble");
    }

    test("walk: eight steps, the filter ones pressing set_only") { test =>
      let steps = pagesLinksWalkSteps();
      expectInt(test, steps.length, 8);
      expectText(test, steps[3].id, "filter");
      expectText(test, steps[3].actEvent, "set_only");
      expectText(test, steps[7].actValue, "case_read");
    }

    test("walk: ending it takes the overlay away, and a plain visit does not bring it back") { test =>
      let fx = tFx();
      let path = "${tLinkPath(fx)}/read?lead=${fx.a.slug}&walk=1";
      tPage(fx, fx.me, path);
      let ended = tMain(tEvent(fx.db, fx.me.ctx, path, "end_walk", "{}", tNever()));
      expectLacks(test, ended, "id=\"walk\"");
      expectLacks(test, tPage(fx, fx.me, tLinkPath(fx)), "id=\"walk\"");
    }

    test("walk: hopping to the case reading goes on to the opinion in its case") { test =>
      let fx = tFx();
      fx.db.exec("UPDATE works SET collection = 'Doe v. Roe' WHERE id = $1", [fx.a.id.toString()]);
      let path = "${tLinkPath(fx)}/read?lead=${fx.a.slug}&walk=1";
      tPage(fx, fx.me, path);
      let r = tEvent(fx.db, fx.me.ctx, path, "walk_hop", "{\"to\":\"case_read\"}", tNever());
      expectText(test, tRedirect(r), "/cases/doe-v-roe/read/${fx.a.slug}?walk=1");
    }

    test("walk: hopping from a draft with no case just ends the walk") { test =>
      let fx = tFx();
      let path = "${tLinkPath(fx)}/read?lead=${fx.a.slug}&walk=1";
      tPage(fx, fx.me, path);
      let r = tEvent(fx.db, fx.me.ctx, path, "walk_hop", "{\"to\":\"case_read\"}", tNever());
      expectText(test, tRedirect(r), "");
      expectLacks(test, tMain(r), "id=\"walk\"");
    }

    test("walk: start_walk puts the card away and the overlay up") { test =>
      let fx = tFx();
      tPage(fx, fx.me, tLinkPath(fx));
      let main = tMain(tEvent(fx.db, fx.me.ctx, tLinkPath(fx), "start_walk", "{}", tNever()));
      expectHas(test, main, "id=\"walk\"");
      expectLacks(test, main, "fl-tour-veil");
    }
