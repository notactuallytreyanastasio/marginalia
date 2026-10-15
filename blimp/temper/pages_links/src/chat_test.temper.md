# Tests for the chat about a pair

The fixtures and the request helpers are those of `pages_links_test`.

    let { Db } = import("db/src");
    let { hjoin } = import("html/src");
    let { LinkEdgeEnds, linksEdges } = import("links/src");
    let { LlmClient, LlmMessage, llmFake, llmRequests } = import("llm/src");
    let { JsonSyntaxTree, parseJson } = import("std/json");

    let tChatPage(fx: TFx): String { "/links/${fx.link.id.toString()}" }

A first visit, with the one-time card put away, so the bubble is up.

    let tReady(fx: TFx): Void throws Bubble {
      tGet(fx.db, fx.me.ctx, tChatPage(fx));
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "dismiss_tour", "{}", tNever());
    }

    let tOpenChat(fx: TFx): Void throws Bubble {
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", tNever());
    }

    let tSend(fx: TFx, launcher: LinksLauncher, text: String): TRun throws Bubble {
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "chat_send", "{\"message\":\"${text}\"}", launcher)
    }

    let tFirstEdge(fx: TFx): Int throws Bubble {
      linksEdges(fx.db, fx.link)[0].edge.id
    }

    let tRequestCount(l: LlmClient): Int { llmRequests(l).length }

    let expectRequests(test: Test, l: LlmClient, want: Int): Void {
      assert(llmRequests(l).length == want) { "requests: got ${llmRequests(l).length.toString()}, want ${want.toString()}" }
    }

    let tLastRequest(l: LlmClient): String {
      let all = llmRequests(l);
      if (all.length > 0) { all[all.length - 1] } else { "" }
    }

## The bubble

    test("chat: the bubble is on the page, shut, and says what it is for") { test =>
      let fx = tFx();
      tReady(fx);
      let body = tPage(fx, fx.me, tChatPage(fx));
      expectHas(test, body, "<div class=\"lc\" id=\"linkchat\" phx-hook=\"LinkChat\">");
      expectHas(test, body, "<button class=\"lc-bubble\" phx-click=\"toggle_chat\" aria-label=\"Talk about how these two relate\" title=\"Talk about how these two relate\">");
      expectHas(test, body, "<span class=\"mark\" aria-hidden=\"true\">↔</span>");
      expectLacks(test, body, "class=\"lc-panel\"");
      expectLacks(test, body, "class=\"n\">0<");
    }

    test("chat: the bubble opens the panel, and a second press shuts it") { test =>
      let fx = tFx();
      tReady(fx);
      let open = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", tNever()));
      expectHas(test, open, "<button class=\"lc-bubble on\" phx-click=\"toggle_chat\"");
      expectHas(test, open, "<div class=\"lc-panel\" role=\"dialog\" aria-label=\"About this pair\">");
      expectHas(test, open, "<span class=\"mg-label\">About this pair</span>");
      expectHas(test, open, "<button class=\"lc-x\" phx-click=\"toggle_chat\" aria-label=\"Close\">×</button>");
      expectHas(test, open, "<form class=\"lc-foot\" phx-submit=\"chat_send\" id=\"lc-form\" phx-hook=\"LinkChatComposer\">");
      expectHas(test, open, "<textarea name=\"message\" rows=\"2\" placeholder=\"How do these two sit together?\"></textarea>");
      expectHas(test, open, "<span class=\"mg-hint mt-0\">Enter to send</span>");
      expectHas(test, open, "<button type=\"submit\" class=\"mg-btn sm\">Ask</button>");
      expectHas(test, open, "id=\"lc-body\" phx-hook=\"StickDown\"");
      let shut = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", tNever()));
      expectLacks(test, shut, "class=\"lc-panel\"");
      expectHas(test, shut, "<button class=\"lc-bubble\"");
    }

    test("chat: the hook's close_chat shuts it and a close when it is shut breaks nothing") { test =>
      let fx = tFx();
      tReady(fx);
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", tNever());
      expectLacks(test, tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "close_chat", "{}", tNever())), "class=\"lc-panel\"");
      expectLacks(test, tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "close_chat", "{}", tNever())), "class=\"lc-panel\"");
    }

    test("chat: an empty chat offers questions rather than a blank box") { test =>
      let fx = tFx();
      tReady(fx);
      let open = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", tNever()));
      expectHas(test, open, "<p class=\"lc-hint\">");
      expectHas(test, open, "This one holds both maps and every edge between them.");
      expectHas(test, open, "It will not write for either of them.");
      expectHas(test, open, "<div class=\"lc-openers\">");
      expectHas(test, open, "<button type=\"button\" phx-click=\"chat_send\" phx-value-message=\"What does the second document already answer?\">");
      expectHas(test, open, "Which disagreement here is real, and which is vocabulary?");
      expectHas(test, open, "Which connection is doing the most work?");
    }

## Asking

    test("chat: asking shows the question and the reader's answer, and the openers go away") { test =>
      let fx = tFx();
      tReady(fx);
      let launcher = tNow([tChat("They part over the kettle.\n\nNothing else is drawn.")]);
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", launcher);
      let r = tSend(fx, launcher, "What is the disagreement?");
      let main = tMain(r);
      expectHas(test, main, "<div class=\"lc-turn user\">");
      expectHas(test, main, "<span class=\"who\">you</span>");
      expectHas(test, main, "What is the disagreement?");
      expectHas(test, main, "<div class=\"lc-turn assistant\">");
      expectHas(test, main, "<span class=\"who\">the reader</span>");
      expectHas(test, main, "<p>They part over the kettle.</p>");
      expectHas(test, main, "<p>Nothing else is drawn.</p>");
      expectLacks(test, main, "lc-openers");
      expectLacks(test, main, "lc-hint");
      expectLacks(test, main, "mg-dots");
      expectLacks(test, main, "lc-thinking");
      expectText(test, tFlash(r), "");
      expectRequests(test, launcher.client, 1);
    }

    test("chat: the model is handed the system prompt, both maps and the question") { test =>
      let fx = tFx();
      tReady(fx);
      let launcher = tNow([tChat("Ok.")]);
      tSend(fx, launcher, "Where is the kettle?");
      let sent = tLastRequest(launcher.client);
      expectHas(test, sent, "You are reading two manuscripts that someone has related to each other");
      expectHas(test, sent, "# THE PAIR");
      expectHas(test, sent, "A: First");
      expectHas(test, sent, "Where is the kettle?");
      expectLacks(test, sent, "The reader is pointing at these connections");
    }

    test("chat: a user turn is text, not markup") { test =>
      let fx = tFx();
      tReady(fx);
      tOpenChat(fx);
      let main = tMain(tSend(fx, tNow([tChat("Fine.")]), "<b>bold</b> & more"));
      expectHas(test, main, "&lt;b&gt;bold&lt;/b&gt; &amp; more");
      expectLacks(test, main, "<b>bold</b>");
    }

    test("chat: an answer is markdown") { test =>
      let fx = tFx();
      tReady(fx);
      tOpenChat(fx);
      let main = tMain(tSend(fx, tNow([tChat("It is **the kettle**.")]), "Which?"));
      expectHas(test, main, "<strong>the kettle</strong>");
    }

    test("chat: tapping an opener asks it, as the form would") { test =>
      let fx = tFx();
      tReady(fx);
      tOpenChat(fx);
      let launcher = tNow([tChat("Ok.")]);
      let main = tMain(tSend(fx, launcher, "Which connection is doing the most work?"));
      expectHas(test, main, "Which connection is doing the most work?");
      expectLacks(test, main, "class=\"lc-openers\"");
    }

    test("chat: a question that is only spaces is ignored and costs nothing") { test =>
      let fx = tFx();
      tReady(fx);
      let launcher = tNow([]);
      let r = tSend(fx, launcher, "   ");
      expectRequests(test, launcher.client, 0);
      expectText(test, tFlash(r), "");
      expectLacks(test, tMain(r), "lc-turn");
    }

    test("chat: a failed answer says so and keeps the question") { test =>
      let fx = tFx();
      tReady(fx);
      let launcher = new TLauncher(tFailScript(), true);
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", launcher);
      let r = tSend(fx, launcher, "anything");
      expectHas(test, tFlash(r), "error: That did not go through: ");
      expectHas(test, tMain(r), "anything");
      expectLacks(test, tMain(r), "lc-turn assistant");
      expectLacks(test, tMain(r), "lc-thinking");
      expectLacks(test, tMain(r), "mg-dots");
    }

    test("chat: the number of turns is on the bubble while the panel is shut") { test =>
      let fx = tFx();
      tReady(fx);
      let launcher = tNow([tChat("Ok.")]);
      tSend(fx, launcher, "One?");
      let shut = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "close_chat", "{}", launcher));
      expectHas(test, shut, "<span class=\"n\">2</span>");
      let open = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", launcher));
      expectLacks(test, open, "<span class=\"n\">2</span>");
    }

    test("chat: it lasts across events and not across a fresh visit") { test =>
      let fx = tFx();
      tReady(fx);
      let launcher = tNow([tChat("Ok.")]);
      tSend(fx, launcher, "Remember this");
      expectHas(test, tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "toggle_chat", "{}", launcher)), "Remember this");
      let fresh = tPage(fx, fx.me, tChatPage(fx));
      expectLacks(test, fresh, "Remember this");
      expectLacks(test, fresh, "class=\"lc-panel\"");
    }

    test("chat: a second question carries the first turns to the model") { test =>
      let fx = tFx();
      tReady(fx);
      let launcher = tNow([tChat("First answer."), tChat("Second answer.")]);
      tSend(fx, launcher, "First question");
      tSend(fx, launcher, "Second question");
      let sent = tLastRequest(launcher.client);
      expectHas(test, sent, "First question");
      expectHas(test, sent, "First answer.");
      expectHas(test, sent, "Second question");
    }

    test("chat: someone who owns neither draft may look but not ask") { test =>
      let fx = tFx();
      let stranger = tWho(fx.db, "z@example.com");
      let launcher = tNow([tChat("Never.")]);
      let r = tEvent(fx.db, stranger.ctx, tChatPage(fx), "chat_send", "{\"message\":\"hello\"}", launcher);
      expectText(test, tFlash(r), "error: That pair is not yours to run.");
      expectRequests(test, launcher.client, 0);
      expectInt(test, tGet(fx.db, stranger.ctx, tChatPage(fx)).resp.status, 200);
    }

## Pointing at a connection

    test("cite: citing an edge puts that connection into the chat and opens it") { test =>
      let fx = tFx();
      tReady(fx);
      let edge = tFirstEdge(fx);
      let main = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "cite_edge", "{\"edge\":\"${edge.toString()}\"}", tNever()));
      expectHas(test, main, "class=\"lc-panel\"");
      expectHas(test, main, "<div class=\"lc-cited\">");
      expectHas(test, main, "<span class=\"mg-label\">pointing at</span>");
      expectHas(test, main, "<div class=\"chip tension\">");
      expectHas(test, main, "<span class=\"rel\">tension</span>");
      expectHas(test, main, "<span class=\"t\">a beat in First ↔ a beat in Second</span>");
      expectHas(test, main, "<button phx-click=\"uncite\" phx-value-edge=\"${edge.toString()}\" aria-label=\"Remove\">×</button>");
      expectHas(test, main, "They part.");
    }

    test("cite: citing the same edge twice is one chip") { test =>
      let fx = tFx();
      tReady(fx);
      let edge = tFirstEdge(fx);
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "cite_edge", "{\"edge\":\"${edge.toString()}\"}", tNever());
      let main = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "cite_edge", "{\"edge\":\"${edge.toString()}\"}", tNever()));
      expectInt(test, tCount(main, "class=\"chip tension\""), 1);
    }

    test("cite: the x takes it out of the question") { test =>
      let fx = tFx();
      tReady(fx);
      let edge = tFirstEdge(fx);
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "cite_edge", "{\"edge\":\"${edge.toString()}\"}", tNever());
      let main = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "uncite", "{\"edge\":\"${edge.toString()}\"}", tNever()));
      expectLacks(test, main, "lc-cited");
      expectLacks(test, main, "class=\"chip");
      expectHas(test, main, "class=\"lc-panel\"");
    }

    test("cite: an edge that is not this pair's is kept off the page") { test =>
      let fx = tFx();
      tReady(fx);
      let main = tMain(tEvent(fx.db, fx.me.ctx, tChatPage(fx), "cite_edge", "{\"edge\":\"99999\"}", tNever()));
      expectLacks(test, main, "lc-cited");
    }

    test("cite: both passages go to the model in full, and the chips are cleared by asking") { test =>
      let fx = tFx();
      tReady(fx);
      let edge = tFirstEdge(fx);
      tEvent(fx.db, fx.me.ctx, tChatPage(fx), "cite_edge", "{\"edge\":${edge.toString()}}", tNever());
      let launcher = tNow([tChat("Ok.")]);
      let main = tMain(tSend(fx, launcher, "What about this?"));
      let sent = tLastRequest(launcher.client);
      expectHas(test, sent, "The reader is pointing at these connections");
      expectHas(test, sent, "Why it was drawn: They part.");
      expectLacks(test, main, "lc-cited");
    }

    test("cite: a cite_edge with no edge is a bug in the caller, and stops") { test =>
      let fx = tFx();
      tReady(fx);
      let stopped = do {
        tEvent(fx.db, fx.me.ctx, tChatPage(fx), "cite_edge", "{}", tNever());
        false
      } orelse true;
      expectTrue(test, stopped, "no edge, no answer");
    }

## The history

    test("history: kept to the last twenty turns, oldest first") { test =>
      let fx = tFx();
      let turns = new ListBuilder<LlmMessage>();
      for (var i = 0; i < 30; ++i) {
        turns.add(new LlmMessage(if (i % 2 == 0) { "user" } else { "assistant" }, "turn ${i.toString()}"));
      }
      pagesLinksChatPut(fx.me.ctx, fx.link.id, new LinksChat(true, turns.toList(), [7, 9]));
      let back = pagesLinksChatOf(fx.me.ctx, fx.link.id);
      expectInt(test, back.history.length, 20);
      expectText(test, back.history[0].content, "turn 10");
      expectText(test, back.history[19].content, "turn 29");
      expectText(test, back.history[0].role, "user");
      expectTrue(test, back.open, "open survives");
      expectInt(test, back.cited.length, 2);
      expectInt(test, back.cited[1], 9);
    }

    test("history: each pair has its own, under links:<id>:chat") { test =>
      let fx = tFx();
      expectText(test, pagesLinksChatKey(fx.link.id), "links:${fx.link.id.toString()}:chat");
      pagesLinksChatPut(fx.me.ctx, fx.link.id, new LinksChat(false, [new LlmMessage("user", "mine")], []));
      expectInt(test, pagesLinksChatOf(fx.me.ctx, fx.link.id + 1).history.length, 0);
      expectInt(test, pagesLinksChatOf(fx.me.ctx, fx.link.id).history.length, 1);
    }

    test("history: a damaged value reads as no chat") { test =>
      let fx = tFx();
      fx.me.ctx.session.ui = new MapBuilder<String, String>().toMap();
      expectInt(test, pagesLinksChatOf(fx.me.ctx, fx.link.id).history.length, 0);
    }

    test("bubble: thinking shows the dots and shuts the box") { test =>
      let chat = new LinksChat(true, [new LlmMessage("user", "Why?")], []);
      let html = hjoin(renderLinkChatBubble(chat, true, []));
      expectHas(test, html, "<div class=\"mg-dots\" aria-label=\"reading\">");
      expectHas(test, html, "<span class=\"mg-dot\" style=\"animation-delay:.18s\"></span>");
      expectHas(test, html, "placeholder=\"How do these two sit together?\" disabled>");
      expectHas(test, html, "<button type=\"submit\" class=\"mg-btn sm\" disabled>Ask</button>");
    }
