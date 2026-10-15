# Tests for the events

Each event on an in-memory database with a canned model, jobs run inline. The
answer of an event is JSON, so what is asserted on the markup is asserted on
the page fetched after it.

    let { accountsOwnerEmail, accountsGetUser } = import("accounts/src");
    let { Ctx, webNewCtx } = import("webcore/src");
    let { chatThreadsByBlock, chatAppend, chatHistory, ChatThread } = import("chat/src");
    let { worksGetBySlug, worksListSections, worksRevisions, worksGetSection } = import("works/src");
    let { runsGet, runsFinish } = import("runs/src");
    let { JsonObject, JsonSyntaxTree, parseJson } = import("std/json");

    let tReadPage(w: TWorld, who: TWho): String throws Bubble {
      tBodyOf(tGet(w.db, who, tPath(w.work, "read"), tKeyed()))
    }

    let tFirstRef(w: TWorld): String throws Bubble {
      let html = tReadPage(w, w.owner);
      html.split("id=\"block-").getOr(1, "").split("\"").getOr(0, "")
    }

## Navigation

    test("nav: a tab is a navigation to the address with the view in it") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "set_view", "{\"view\":\"graph\"}", tKeyed());
      expectText(test, tRedirect(r), "/works/${w.work.slug}?view=graph");
    }

    test("nav: an unknown view is the page") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "set_view", "{\"view\":\"nonsense\"}", tKeyed());
      expectText(test, tRedirect(r), "/works/${w.work.slug}?view=read");
    }

    test("nav: the drawer's toggle puts chat=1 in the address and takes it out") { test =>
      let w = tWorld();
      let open = tEvent(w.db, w.owner, tPage(w), "toggle_chat", "{}", tKeyed());
      expectText(test, tRedirect(open), "/works/${w.work.slug}?view=read&chat=1");
      let shut = tEvent(w.db, w.owner, "${tPage(w)}&chat=1", "toggle_chat", "{}", tKeyed());
      expectText(test, tRedirect(shut), "/works/${w.work.slug}?view=read");
    }

    test("nav: changing the view keeps the drawer") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, "${tPage(w)}&chat=1", "set_view", "{\"view\":\"spine\"}", tKeyed());
      expectText(test, tRedirect(r), "/works/${w.work.slug}?view=spine&chat=1");
    }

    test("nav: a plain request for the same event gets a redirect too") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "set_view", "{\"view\":\"threads\"}", tKeyed());
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBodyOf(r), "redirect");
    }

    test("nav: an event nobody answers is a crash with its name in the log") { test =>
      let w = tWorld();
      let ok = do { tEvent(w.db, w.owner, tPage(w), "no_such_event", "{}", tKeyed()); true } orelse false;
      expectFalse(test, ok, "an unknown event must not look like success");
    }

    test("nav: an event on a path that is not the page is a crash") { test =>
      let w = tWorld();
      let ok = do {
        let m = tMatch("GET", "/works/${w.work.slug}/graph.json");
        let req = tRaw("POST", "/works/${w.work.slug}/graph.json", "", "{}");
        let ctx = webNewCtx(w.db, ":memory:", req, m.params);
        let tree: JsonSyntaxTree = parseJson("{}");
        if (tree is JsonObject) { pagesShowEventWith(ctx, m, "set_view", tree, tKeyed()); }
        true
      } orelse false;
      expectFalse(test, ok, "the downloads have no events");
    }

## The tour

    test("tour: the first visit to a tab explains it") { test =>
      let w = tWorld();
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "The page, with its notes in the margin");
      expectHas(test, html, "thin line appears");
      expectHas(test, html, "class=\"mg-tour\"");
      expectHas(test, html, "phx-click=\"dismiss_tour\"");
    }

    test("tour: the second visit does not") { test =>
      let w = tWorld();
      tReadPage(w, w.owner);
      expectLacks(test, tReadPage(w, w.owner), "The page, with its notes in the margin");
    }

    test("tour: it is remembered on the account") { test =>
      let w = tWorld();
      tReadPage(w, w.owner);
      let user = accountsGetUser(w.db, w.owner.id);
      expectTrue(test, user.seenTours.length == 1 && user.seenTours[0] == "read", "read is seen");
    }

    test("tour: each tab gets its own, once") { test =>
      let w = tWorld();
      tReadPage(w, w.owner);
      let graph = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "graph"), tKeyed()));
      expectHas(test, graph, "What leads to what");
      let spine = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "spine"), tKeyed()));
      expectHas(test, spine, "The whole draft at once");
      expectLacks(test, spine, "What leads to what");
      let back = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "graph"), tKeyed()));
      expectLacks(test, back, "What leads to what");
      let user = accountsGetUser(w.db, w.owner.id);
      expectInt(test, user.seenTours.length, 3);
    }

    test("tour: help brings it back, and dismissing hides it for the visit") { test =>
      let w = tWorld();
      tReadPage(w, w.owner);
      let r = tEvent(w.db, w.owner, tPage(w), "show_help", "{}", tKeyed());
      expectInt(test, r.resp.status, 200);
      expectHas(test, tMain(r), "The page, with its notes in the margin");
      let gone = tEvent(w.db, w.owner, tPage(w), "dismiss_tour", "{}", tKeyed());
      expectLacks(test, tMain(gone), "The page, with its notes in the margin");
      expectLacks(test, tMain(tPoll(w.db, w.owner, tPage(w), tKeyed())), "The page, with its notes in the margin");
    }

    test("tour: someone who has seen everything is never shown one") { test =>
      let w = tWorld();
      let views = ["read", "graph", "spine", "threads"];
      var i = 0;
      while (i < views.length) {
        tGet(w.db, w.owner, tPath(w.work, views[i]), tKeyed());
        i += 1;
      }
      i = 0;
      while (i < views.length) {
        let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, views[i]), tKeyed()));
        expectLacks(test, html, "mg-tour");
        i += 1;
      }
    }

    test("tour: the changes tab has none") { test =>
      let w = tWorld();
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPath(w.work, "changes"), tKeyed())), "class=\"mg-tour\"");
    }

    test("tour: the card offers the walkthrough only on the read view") { test =>
      let w = tWorld();
      expectHas(test, tReadPage(w, w.owner), "phx-click=\"start_walk\"");
      let graph = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "graph"), tKeyed()));
      expectHas(test, graph, "What leads to what");
      expectLacks(test, graph, "start_walk");
    }

## Threads on a paragraph

    let tOpen(w: TWorld, who: TWho, ref: String): TRun throws Bubble {
      let s = worksListSections(w.db, w.work.id)[0];
      tEvent(w.db, who, tPage(w), "open_thread", "{\"ref\":\"${ref}\",\"section\":\"${s.id.toString()}\"}", tKeyed())
    }

    test("thread: opening one shows it under that paragraph and nowhere else") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p1");
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "on this paragraph");
      expectHas(test, html, "What about this paragraph?");
      expectHas(test, html, "id=\"block-s1p1\"");
      expectInt(test, tCount(html, "class=\"mg-thread-panel\""), 1);
    }

    test("thread: coming back to the same paragraph returns to the same thread") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p1");
      let first = chatThreadsByBlock(w.db, w.work.id);
      tEvent(w.db, w.owner, tPage(w), "close_thread", "{}", tKeyed());
      expectLacks(test, tReadPage(w, w.owner), "class=\"mg-thread-panel\"");
      tOpen(w, w.owner, "s1p1");
      let again = chatThreadsByBlock(w.db, w.work.id);
      expectInt(test, again.keys().length, 1);
      expectInt(test, again.getOr("s1p1", first.getOr("s1p1", tNoThread())).id, first.getOr("s1p1", tNoThread()).id);
    }

    test("thread: a different paragraph gets its own thread") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p0");
      tOpen(w, w.owner, "s1p1");
      expectInt(test, chatThreadsByBlock(w.db, w.work.id).keys().length, 2);
    }

    test("thread: a paragraph that is not there makes no thread") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p99");
      expectInt(test, chatThreadsByBlock(w.db, w.work.id).keys().length, 0);
      tOpen(w, w.owner, "s9p0");
      expectInt(test, chatThreadsByBlock(w.db, w.work.id).keys().length, 0);
    }

    test("thread: a selection pins the thread to the passage, not just the paragraph") { test =>
      let w = tWorld();
      let s = worksListSections(w.db, w.work.id)[0];
      tEvent(w.db, w.owner, tPage(w), "open_thread", "{\"ref\":\"s1p1\",\"section\":\"${s.id.toString()}\",\"quote\":\"The kettle went cold on the counter\"}", tKeyed());
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "on this passage");
      expectHas(test, html, "The kettle went cold on the counter");
      expectHas(test, html, "class=\"mg-thread-quote\"");
      let t = chatThreadsByBlock(w.db, w.work.id).getOr("s1p1", tNoThread());
      expectText(test, showOr(t.quote, ""), "The kettle went cold on the counter");
    }

    test("thread: the tick carries the thread's message count") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p1");
      let t = chatThreadsByBlock(w.db, w.work.id).getOr("s1p1", tNoThread());
      chatAppend(w.db, t.id, "user", "what is this doing");
      chatAppend(w.db, t.id, "assistant", "holding the room still");
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "2 in this thread");
      expectHas(test, html, "has-thread");
    }

    test("thread: its messages are drawn, the reader's markdown and the writer's text") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p1");
      let t = chatThreadsByBlock(w.db, w.work.id).getOr("s1p1", tNoThread());
      chatAppend(w.db, t.id, "user", "what is <this> doing");
      chatAppend(w.db, t.id, "assistant", "It is **holding** the room still.");
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "what is &lt;this&gt; doing");
      expectHas(test, html, "<strong>holding</strong>");
      expectHas(test, html, "mg-thread-turn mine");
      expectHas(test, html, "mg-thread-turn theirs");
    }

    test("thread: a thread can be settled and reopened") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p1");
      let t = chatThreadsByBlock(w.db, w.work.id).getOr("s1p1", tNoThread());
      chatAppend(w.db, t.id, "user", "said something");
      let settled = tEvent(w.db, w.owner, tPage(w), "resolve_thread", "{}", tKeyed());
      expectHas(test, tMain(settled), "settled");
      expectTrue(test, chatThreadsByBlock(w.db, w.work.id).getOr("s1p1", tNoThread()).resolved, "settled in the store");
      tEvent(w.db, w.owner, tPage(w), "resolve_thread", "{}", tKeyed());
      expectFalse(test, chatThreadsByBlock(w.db, w.work.id).getOr("s1p1", tNoThread()).resolved, "reopened");
    }

    test("thread: a link-holder can read a thread but not add to it") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p1");
      let t = chatThreadsByBlock(w.db, w.work.id).getOr("s1p1", tNoThread());
      chatAppend(w.db, t.id, "user", "the owner said this");
      tEvent(w.db, w.reader, tPage(w), "open_thread", "{\"ref\":\"s1p1\",\"section\":\"1\"}", tKeyed());
      let html = tReadPage(w, w.reader);
      expectHas(test, html, "the owner said this");
      expectLacks(test, html, "What about this paragraph?");
      expectLacks(test, html, "phx-click=\"resolve_thread\"");
    }

    test("thread: a link-holder cannot make one") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.reader, tPage(w), "open_thread", "{\"ref\":\"s1p1\",\"section\":\"1\"}", tKeyed());
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
      expectInt(test, chatThreadsByBlock(w.db, w.work.id).keys().length, 0);
    }

    test("thread: a link-holder cannot settle one") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p1");
      tEvent(w.db, w.reader, tPage(w), "open_thread", "{\"ref\":\"s1p1\",\"section\":\"1\"}", tKeyed());
      let r = tEvent(w.db, w.reader, tPage(w), "resolve_thread", "{}", tKeyed());
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
    }

    test("thread: pinned threads stay out of the drawer's strip") { test =>
      let w = tWorld();
      tOpen(w, w.owner, "s1p1");
      let r = tBodyOf(tGet(w.db, w.owner, "${tPage(w)}&chat=1", tKeyed()));
      expectLacks(test, r, "phx-value-id=\"${chatThreadsByBlock(w.db, w.work.id).getOr("s1p1", tNoThread()).id.toString()}\"");
    }

    test("thread: the walkthrough's thread is never inserted") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", tKeyed());
      tOpen(w, w.owner, "s1p1");
      expectInt(test, chatThreadsByBlock(w.db, w.work.id).keys().length, 0);
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "on this paragraph");
      expectHas(test, html, "id=\"thread-0\"");
    }

    let tNoThread(): ChatThread { new ChatThread("", 0, 0, null, false, "read") }

## Rewrites

    test("rewrite: one paragraph opens the panel instead of dropping the socket") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tWords(120)}\",\"ref\":\"s1p2\"}", tQueue());
      expectInt(test, r.resp.status, 200);
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "mg-rewrite working");
      expectHas(test, html, "Rewrites of");
      expectHas(test, html, "id=\"rewrite-panel\"");
    }

    test("rewrite: several paragraphs open it too, and it says how much") { test =>
      let w = tWorld();
      let span = "Paragraph 1. ${tWords(150)}\\n\\nParagraph 2. ${tWords(150)}\\n\\nParagraph 3. ${tWords(150)}";
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${span}\",\"ref\":\"s1p2\"}", tQueue());
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "mg-rewrite");
      expectLacks(test, html, "Rewrites of one line");
      expectHas(test, html, "Rewrites of 456 words");
    }

    test("rewrite: a long span shows its extent, since the rest runs off below the panel") { test =>
      let w = tWorld();
      let span = "THE VERY START. ${tRepeat("middle ", 300)}THE VERY END.";
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${span}\",\"ref\":\"s1p2\"}", tQueue());
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "THE VERY START");
      expectHas(test, html, "THE VERY END");
      expectHas(test, html, "mg-rw-extent");
    }

    test("rewrite: the steer box is there and survives the panel opening") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tWords(120)}\",\"ref\":\"s1p2\"}", tQueue());
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "steer_rewrite");
      expectHas(test, html, "ask for something specific");
      expectHas(test, html, "name=\"steer\"");
      expectHas(test, html, "<textarea");
      expectHas(test, html, "id=\"rw-steer\"");
    }

    test("rewrite: the steer box is never disabled, because the morph would freeze it that way") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tWords(120)}\",\"ref\":\"s1p2\"}", tQueue());
      let html = tReadPage(w, w.owner);
      let box = html.split("<textarea id=\"rw-steer\"").getOr(1, "").split(">").getOr(0, "");
      expectLacks(test, box, "disabled");
      expectHas(test, box, "phx-update=\"ignore\"");
    }

    test("rewrite: the button is the thing that goes quiet during a pass") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tWords(120)}\",\"ref\":\"s1p2\"}", tQueue());
      expectHas(test, tReadPage(w, w.owner), "class=\"mg-btn sm\" disabled>Again<");
    }

    test("rewrite: while the pass is going the page polls") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tWords(120)}\",\"ref\":\"s1p2\"}", tQueue());
      expectHas(test, tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed())), "data-poll=\"2\"");
    }

    test("rewrite: the paragraphs it covers are dimmed, the others not") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tWords(120)}\",\"ref\":\"s1p2\"}", tQueue());
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "class=\"mg-block rewriting\" id=\"block-s1p2\"");
      expectLacks(test, html, "class=\"mg-block rewriting\" id=\"block-s1p1\"");
    }

    test("rewrite: the answer arrives, with each candidate's move and cost") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectHas(test, html, "The kettle went cold; nobody refilled it.");
      expectHas(test, html, "Cuts the gloss.");
      expectHas(test, html, "Loses the again.");
      expectHas(test, html, "It states the scene flatly.");
      expectHas(test, html, "replace the passage with this →");
      expectHas(test, html, "or edit it first →");
      expectHas(test, html, "id=\"rw-list\" phx-hook=\"Hover\"");
      expectLacks(test, html, "mg-rewrite working");
    }

    test("rewrite: a selection that is not in the draft says so") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      let r = tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"a sentence that was never in the draft at all\",\"ref\":\"s1p1\"}", launcher);
      expectText(test, tFlash(r, "error"), "That selection is not in the draft, character for character.");
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPage(w), launcher)), "id=\"rewrite-panel\"");
    }

    test("rewrite: a span too long is refused with its length") { test =>
      let w = tWorld();
      let long = tWords(2600);
      let launcher = tInline([tRewriteReply()]);
      let r = tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${long}\",\"ref\":\"s1p1\"}", launcher);
      expectHas(test, tFlash(r, "error"), "That is 2600 words. Rewrites go up to 2500");
    }

    test("rewrite: hovering a candidate shows it in the paragraph, leaving puts it back") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      tEvent(w.db, w.owner, tPage(w), "preview_rewrite", "{\"i\":\"0\"}", launcher);
      let shown = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectTrue(test, tCount(shown, "<ins class=\"mg-swap\">") >= 2, "the candidate's insertions, beside the legend's");
      expectTrue(test, tCount(shown, "<del class=\"mg-cut\">") >= 2, "and its deletions");
      expectLacks(test, shown, "class=\"mg-block rewriting\"");
      tEvent(w.db, w.owner, tPage(w), "clear_preview", "{}", launcher);
      let back = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectInt(test, tCount(back, "<ins class=\"mg-swap\">"), 1);
      expectHas(test, back, "class=\"mg-block rewriting\"");
    }

    test("rewrite: a candidate that is not there is not previewed") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      tEvent(w.db, w.owner, tPage(w), "preview_rewrite", "{\"i\":\"9\"}", launcher);
      expectInt(test, tCount(tBodyOf(tGet(w.db, w.owner, tPage(w), launcher)), "<ins class=\"mg-swap\">"), 1);
    }

    test("rewrite: closing the panel puts everything back") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      tEvent(w.db, w.owner, tPage(w), "close_rewrite", "{}", launcher);
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectLacks(test, html, "id=\"rewrite-panel\"");
      expectLacks(test, html, "mg-block rewriting");
    }

    test("rewrite: applying one replaces the passage, and the change is in the Changes tab") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      let r = tEvent(w.db, w.owner, tPage(w), "apply_rewrite", "{\"i\":\"0\"}", launcher);
      expectHas(test, tFlash(r, "info"), "Replaced.");
      expectHas(test, tFlash(r, "info"), "It is in the Changes tab if you want it back.");
      let revs = worksRevisions(w.db, w.work.id);
      expectInt(test, revs.length, 1);
      expectText(test, revs[0].origin, "rewrite");
      expectText(test, showOr(revs[0].note, ""), "Cuts the gloss.");
      expectText(test, revs[0].after, "The kettle went cold; nobody refilled it.");
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectHas(test, html, ">Changes<");
      expectHas(test, html, "class=\"mg-applied\"");
      expectLacks(test, html, "id=\"rewrite-panel\"");
      tEvent(w.db, w.owner, tPage(w), "dismiss_applied", "{}", launcher);
      expectHas(test, tBodyOf(tGet(w.db, w.owner, tPage(w), launcher)), "The kettle went cold; nobody refilled it.");
    }

    test("rewrite: the applied box is dismissable, and then the paragraph is just a paragraph") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      tEvent(w.db, w.owner, tPage(w), "apply_rewrite", "{\"i\":\"0\"}", launcher);
      tEvent(w.db, w.owner, tPage(w), "dismiss_applied", "{}", launcher);
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPage(w), launcher)), "class=\"mg-applied\"");
    }

    test("rewrite: a note about the line that changed is greyed, not gone") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "About the kettle");
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      let r = tEvent(w.db, w.owner, tPage(w), "apply_rewrite", "{\"i\":\"1\"}", launcher);
      expectText(test, tFlash(r, "info"), "Replaced. One note was about the line you changed. It is greyed, not gone.");
      expectHas(test, tBodyOf(tGet(w.db, w.owner, tPage(w), launcher)), "About the kettle");
    }

    test("rewrite: a passage that moved underneath is not replaced") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      tEdit(w.db, w.work, "nobody moved", "nobody stirred");
      let r = tEvent(w.db, w.owner, tPage(w), "apply_rewrite", "{\"i\":\"0\"}", launcher);
      expectText(test, tFlash(r, "error"), "That passage changed underneath the rewrite. Nothing was replaced.");
      expectInt(test, worksRevisions(w.db, w.work.id).length, 1);
    }

    test("rewrite: only the owner applies one, and the walkthrough never does") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      let r = tEvent(w.db, w.reader, tPage(w), "apply_rewrite", "{\"i\":\"0\"}", launcher);
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
      expectInt(test, worksRevisions(w.db, w.work.id).length, 0);
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", launcher);
      tEvent(w.db, w.owner, tPage(w), "apply_rewrite", "{\"i\":\"0\"}", launcher);
      expectInt(test, worksRevisions(w.db, w.work.id).length, 0);
    }

    test("rewrite: a reader cannot ask for one") { test =>
      let w = tWorld();
      let before = tN(w.db, "SELECT count(*) AS n FROM runs");
      let r = tEvent(w.db, w.reader, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", tInline([tRewriteReply()]));
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), before);
    }

    test("rewrite: again, with a note, asks the same span with the steer") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply(), tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      tEvent(w.db, w.owner, tPage(w), "steer_rewrite", "{\"steer\":\"  shorter please  \"}", launcher);
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectHas(test, html, ">shorter please</textarea>");
    }

    test("rewrite: again with nothing typed does nothing") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      let r = tEvent(w.db, w.owner, tPage(w), "steer_rewrite", "{\"steer\":\"   \"}", launcher);
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBodyOf(tGet(w.db, w.owner, tPage(w), launcher)), "Cuts the gloss.");
    }

    test("rewrite: the walkthrough's rewrite is the fixed example, with no model") { test =>
      let w = tWorld();
      let launcher = tInline([]);
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", launcher);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectHas(test, html, "It changed how she saw her father.");
      expectHas(test, html, "Cuts the gloss");
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
    }

## Editing in place

    test("edit: editing a paragraph with no rewrite open still works") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", tKeyed());
      expectInt(test, r.resp.status, 200);
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "mg-edit");
      expectHas(test, html, "id=\"edit-s1p1\"");
      expectHas(test, html, "She had been standing at the window for an hour before anyone noticed.");
      expectHas(test, html, "phx-hook=\"Editor\"");
    }

    test("edit: cancelling closes the box") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", tKeyed());
      tEvent(w.db, w.owner, tPage(w), "cancel_edit", "{}", tKeyed());
      expectLacks(test, tReadPage(w, w.owner), "id=\"edit-s1p1\"");
    }

    test("edit: saving writes the paragraph, as an edit, and shows what it replaced") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", tKeyed());
      let r = tEvent(w.db, w.owner, tPage(w), "save_block", "{\"text\":\"She stood at the window.\"}", tKeyed());
      expectInt(test, r.resp.status, 200);
      let revs = worksRevisions(w.db, w.work.id);
      expectInt(test, revs.length, 1);
      expectText(test, revs[0].origin, "edit");
      expectText(test, revs[0].after, "She stood at the window.");
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "class=\"mg-applied\"");
      expectLacks(test, html, "id=\"edit-s1p1\"");
      tEvent(w.db, w.owner, tPage(w), "dismiss_applied", "{}", tKeyed());
      expectHas(test, tReadPage(w, w.owner), "She stood at the window.");
    }

    test("edit: an empty paragraph is a deletion and is refused") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", tKeyed());
      let r = tEvent(w.db, w.owner, tPage(w), "save_block", "{\"text\":\"  \"}", tKeyed());
      expectText(test, tFlash(r, "error"), "An empty paragraph is a deletion. Select it and cut it instead.");
      expectInt(test, worksRevisions(w.db, w.work.id).length, 0);
      expectHas(test, tReadPage(w, w.owner), "id=\"edit-s1p1\"");
    }

    test("edit: the paragraph is read again when saved, so another tab's edit is not overwritten") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", tKeyed());
      tEdit(w.db, w.work, "standing at the window", "sitting by the window");
      let r = tEvent(w.db, w.owner, tPage(w), "save_block", "{\"text\":\"Something else.\"}", tKeyed());
      expectInt(test, r.resp.status, 200);
      let revs = worksRevisions(w.db, w.work.id);
      expectInt(test, revs.length, 2);
      expectHas(test, revs[1].before, "sitting by the window");
    }

    test("edit: a candidate can seed the box when there is a rewrite open") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p2\",\"seed\":\"Nobody moved, and the kettle went cold.\"}", launcher);
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectHas(test, html, "id=\"edit-s1p2\"");
      expectHas(test, html, "Nobody moved, and the kettle went cold.");
      expectLacks(test, html, "id=\"rewrite-panel\"");
    }

    test("edit: a seed that does not belong to this paragraph is refused, not placed") { test =>
      let w = tWorld();
      let launcher = tInline([tRewriteReply()]);
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tGet(w.db, w.owner, tPage(w), launcher);
      let r = tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p0\",\"seed\":\"A rewrite of something else.\"}", launcher);
      expectHas(test, tFlash(r, "error"), "That rewrite covers more than this paragraph");
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPage(w), launcher)), "id=\"edit-s1p0\"");
    }

    test("edit: a reader cannot open the box, or save through it") { test =>
      let w = tWorld();
      tEvent(w.db, w.reader, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", tKeyed());
      expectLacks(test, tReadPage(w, w.reader), "id=\"edit-s1p1\"");
      tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", tKeyed());
      tEvent(w.db, w.reader, tPage(w), "save_block", "{\"text\":\"Vandalised.\"}", tKeyed());
      expectInt(test, worksRevisions(w.db, w.work.id).length, 0);
    }

    test("edit: the walkthrough's save discards, and says so") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", tKeyed());
      tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", tKeyed());
      let r = tEvent(w.db, w.owner, tPage(w), "save_block", "{\"text\":\"Gone.\"}", tKeyed());
      expectText(test, tFlash(r, "info"), "Nothing was saved — the walkthrough does not touch your draft.");
      expectInt(test, worksRevisions(w.db, w.work.id).length, 0);
    }

## The walkthrough

    test("walk: the overlay carries the steps, and says it is safe") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", tKeyed());
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "id=\"walk\" phx-hook=\"Walk\"");
      expectHas(test, html, "data-steps=");
      expectHas(test, html, "Nothing here is saved, and no model is called");
      expectHas(test, html, "The notes sit beside the line");
    }

    test("walk: a reader's walkthrough leaves out the steps they cannot use") { test =>
      let w = tWorld();
      tEvent(w.db, w.reader, tPage(w), "start_walk", "{}", tKeyed());
      let theirs = tReadPage(w, w.reader);
      expectLacks(test, theirs, "Three rewrites, each with its cost");
      expectLacks(test, theirs, "Ask about that spot");
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", tKeyed());
      let mine = tReadPage(w, w.owner);
      expectHas(test, mine, "Three rewrites, each with its cost");
      expectHas(test, mine, "Ask about that spot");
    }

    test("walk: starting it hides the tour card and marks it seen") { test =>
      let w = tWorld();
      tReadPage(w, w.owner);
      tEvent(w.db, w.owner, tPage(w), "show_help", "{}", tKeyed());
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", tKeyed());
      expectLacks(test, tReadPage(w, w.owner), "class=\"mg-tour\"");
      let user = accountsGetUser(w.db, w.owner.id);
      expectTrue(test, tCount(user.seenTours.join(",") { (x: String): String => x }, "walk:read") == 1, "walk:read is seen");
    }

    test("walk: ending it clears everything the tour put on the page") { test =>
      let w = tWorld();
      let launcher = tInline([]);
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", launcher);
      tOpen(w, w.owner, "s1p1");
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tEvent(w.db, w.owner, tPage(w), "end_walk", "{}", launcher);
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectLacks(test, html, "id=\"walk\"");
      expectLacks(test, html, "id=\"thread-0\"");
      expectLacks(test, html, "id=\"rewrite-panel\"");
    }

    test("walk: the last step resets the page and the filter, and the walk goes on") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "The kettle goes cold");
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", tKeyed());
      tEvent(w.db, w.owner, tPage(w), "set_only", "{\"only\":\"tensions\"}", tKeyed());
      tEvent(w.db, w.owner, tPage(w), "walk_reset", "{}", tKeyed());
      let html = tReadPage(w, w.owner);
      expectHas(test, html, "The kettle goes cold");
      expectHas(test, html, "id=\"walk\"");
    }

    test("walk: the walkthrough writes nothing at all") { test =>
      let w = tWorld();
      let launcher = tInline([]);
      tGet(w.db, w.owner, tPage(w), launcher);
      let before = tN(w.db, "SELECT count(*) AS n FROM conversations");
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", launcher);
      tOpen(w, w.owner, "s1p1");
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", launcher);
      tEvent(w.db, w.owner, tPage(w), "edit_block", "{\"ref\":\"s1p1\"}", launcher);
      tEvent(w.db, w.owner, tPage(w), "save_block", "{\"text\":\"Gone.\"}", launcher);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM conversations"), before);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM revisions"), 0);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
    }
