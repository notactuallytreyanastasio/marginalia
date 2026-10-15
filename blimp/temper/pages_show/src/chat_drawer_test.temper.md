# Tests for the chat drawer

What the drawer draws for the owner and for someone holding the link, each of
the eleven events, and the model call as a job: the question stored before the
model is asked, the answer left in the database, the page waiting while it
runs, and the reason when it fails.

    let { LlmClient, llmFake, llmRequests } = import("llm/src");
    let { runsGet } = import("runs/src");
    let { chatAppend, chatMessages, chatListConversations, chatGetOrCreateConversation, chatCreateConversation, chatSetMode } = import("chat/src");
    let { readingBlocks } = import("reading/src");

    let tChatReply(content: String): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"${content}\"},\"finish_reason\":\"stop\"}]}"
    }

    let tChatRunStatus(db: Db, key: String): String throws Bubble {
      let run = runsGet(db, key);
      if (run != null) { run.status } else { "none" }
    }

    let tChatPage(w: TWorld): String { "${tPage(w)}&chat=1" }

    let tChatLauncher(client: LlmClient): ShowLauncher { new ShowInlineLauncher(client, true) }

    let tChatOpen(w: TWorld, who: TWho): String throws Bubble {
      tBodyOf(tGet(w.db, who, tChatPage(w), tKeyed()))
    }

    let tChatSend(w: TWorld, who: TWho, text: String, launcher: ShowLauncher): TRun throws Bubble {
      tEvent(w.db, who, tChatPage(w), "send", "{\"message\":\"${text}\"}", launcher)
    }

    let tChatConvo(w: TWorld): Int throws Bubble {
      let c = chatGetOrCreateConversation(w.db, w.work.id).conversation;
      if (c != null) { c.id } else { -1 }
    }

    let tChatCount(w: TWorld, role: String): Int throws Bubble {
      tN(w.db, "SELECT count(*) AS n FROM messages WHERE role = '${role}'")
    }

    let tChatLastRole(w: TWorld, convo: Int): String throws Bubble {
      let ms = chatMessages(w.db, convo);
      if (ms.length > 0) { ms[ms.length - 1].role } else { "" }
    }

## What it draws

    test("chat panel: the owner's drawer has the head, the stances, the strip, the transcript and the box") { test =>
      let w = tWorld();
      let page = tChatOpen(w, w.owner);
      expectHas(test, page, "mg-drawer open");
      expectHas(test, page, "Talk about it");
      expectHas(test, page, "phx-click=\"toggle_chat\"");
      expectHas(test, page, "phx-value-mode=\"bounce\"");
      expectHas(test, page, "class=\"mg-tab on\" phx-click=\"set_mode\" phx-value-mode=\"read\"");
      expectHas(test, page, "What is actually on the page");
      expectHas(test, page, "class=\"mg-threads shrink-0\"");
      expectHas(test, page, "phx-click=\"new_chat\"");
      expectHas(test, page, "id=\"chat-scroll\" phx-hook=\"StickToBottom\"");
      expectHas(test, page, "Ask me what");
      expectHas(test, page, "id=\"chat-form\" phx-hook=\"ChatComposer\"");
      expectHas(test, page, "phx-submit=\"send\"");
      expectHas(test, page, "Enter to send · Shift+Enter for a new line");
      expectHas(test, page, ">Ask</button>");
      expectLacks(test, page, "Read only");
      expectLacks(test, page, "data-poll");
    }

    test("chat panel: a closed drawer draws nothing inside it") { test =>
      let w = tWorld();
      let page = tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed()));
      expectHas(test, page, "mg-drawer ");
      expectLacks(test, page, "chat-scroll");
    }

    test("chat panel: someone holding the link reads the transcript and has no box") { test =>
      let w = tWorld();
      let convo = tChatConvo(w);
      chatAppend(w.db, convo, "user", "is the kettle doing enough");
      chatAppend(w.db, convo, "assistant", "It is doing **a lot**.");
      let page = tChatOpen(w, w.reader);
      expectHas(test, page, "is the kettle doing enough");
      expectHas(test, page, "<strong>a lot</strong>");
      expectHas(test, page, "Read only");
      expectHas(test, page, "the asking is theirs");
      expectLacks(test, page, "chat-form");
      expectLacks(test, page, "mg-threads");
    }

    test("chat panel: a reader of a draft nobody has talked about is told so") { test =>
      let w = tWorld();
      expectHas(test, tChatOpen(w, w.reader), "Nothing has been said about this draft yet.");
    }

    test("chat panel: the turns are told apart, and each has an id for the morph") { test =>
      let w = tWorld();
      let convo = tChatConvo(w);
      chatAppend(w.db, convo, "user", "first <b>thing</b>");
      chatAppend(w.db, convo, "assistant", "second");
      let page = tChatOpen(w, w.owner);
      expectHas(test, page, "class=\"mg-turn-you\" id=\"chat-turn-0\">first &lt;b&gt;thing&lt;/b&gt;");
      expectHas(test, page, "class=\"md\" id=\"chat-turn-1\"");
      expectLacks(test, page, "Ask me what");
    }

    test("chat panel: a draft that is not read yet says to read it first, with no stances") { test =>
      let w = tWorld();
      let fresh = tDraft(w.db, w.owner.scope, "Unread", tBody());
      let page = tBodyOf(tGet(w.db, w.owner, "${tPath(fresh, "read")}&chat=1", tKeyed()));
      expectHas(test, page, "Confirm the sections and run the read first.");
      expectLacks(test, page, "phx-value-mode");
      expectLacks(test, page, "chat-form");
    }

    test("chat panel: no key says so, and draws no box") { test =>
      let w = tWorld();
      let page = tBodyOf(tGet(w.db, w.owner, tChatPage(w), tNoKey()));
      expectHas(test, page, "key configured on this deploy.");
      expectLacks(test, page, "chat-form");
      expectLacks(test, page, "phx-value-mode");
    }

    test("chat panel: the questions left show once they are twenty or fewer, and none left says why") { test =>
      let w = tWorld();
      let convo = tChatConvo(w);
      var i = 0;
      while (i < 85) {
        chatAppend(w.db, convo, "user", "q${i.toString()}");
        i += 1;
      }
      let page = tChatOpen(w, w.owner);
      expectHas(test, page, "15 left");
      while (i < 100) {
        chatAppend(w.db, convo, "user", "q${i.toString()}");
        i += 1;
      }
      let spent = tChatOpen(w, w.owner);
      expectHas(test, spent, "Out of questions");
      expectHas(test, spent, "100 questions");
      expectLacks(test, spent, "chat-form");
    }

    test("chat panel: the thread strip names each conversation after its first question and marks the one in use") { test =>
      let w = tWorld();
      let first = tChatConvo(w);
      chatAppend(w.db, first, "user", "the first question I asked");
      let second = chatCreateConversation(w.db, w.work.id, "read").conversation;
      expectTrue(test, second != null, "a second conversation");
      let page = tChatOpen(w, w.owner);
      expectHas(test, page, "the first question I asked");
      expectHas(test, page, "<span class=\"n\">1</span>");
      expectHas(test, page, "phx-click=\"delete_chat\"");
      expectHas(test, page, "data-confirm=\"Delete this thread and everything said in it?\"");
      expectHas(test, page, "class=\"mg-thread on\"");
    }

## Asking

    test("send: the question is stored, the model is asked, the answer is stored and shown") { test =>
      let w = tWorld();
      let client = llmFake([tChatReply("The kettle is the whole scene.")]);
      let r = tChatSend(w, w.owner, "What is the kettle doing?", tChatLauncher(client));
      expectInt(test, r.resp.status, 200);
      expectHas(test, r.resp.body, "chat:clear");
      let convo = tChatConvo(w);
      let ms = chatMessages(w.db, convo);
      expectInt(test, ms.length, 2);
      expectText(test, ms[0].role, "user");
      expectText(test, ms[0].content, "What is the kettle doing?");
      expectText(test, ms[1].role, "assistant");
      expectText(test, ms[1].content, "The kettle is the whole scene.");
      let main = tMain(r);
      expectHas(test, main, "What is the kettle doing?");
      expectHas(test, main, "The kettle is the whole scene.");
      expectLacks(test, main, "data-poll");
      expectText(test, tChatRunStatus(w.db, showChatConversationKey(w.work.id, convo)), "done");
    }

    test("send: what the model is handed is the system prompt, the draft's card, the stance and the turns") { test =>
      let w = tWorld();
      let client = llmFake([tChatReply("Fine.")]);
      tChatSend(w, w.owner, "Is the opening late?", tChatLauncher(client));
      let reqs = llmRequests(client);
      expectInt(test, reqs.length, 1);
      expectHas(test, reqs[0], "You are Marginalia");
      expectHas(test, reqs[0], "THIS MANUSCRIPT");
      expectHas(test, reqs[0], "Title: Draft");
      expectHas(test, reqs[0], "Is the opening late?");
    }

    test("send: the question is stored before the model is called, and the page waits while it runs") { test =>
      let w = tWorld();
      let r = tChatSend(w, w.owner, "Wait for me", tQueue());
      let convo = tChatConvo(w);
      expectInt(test, chatMessages(w.db, convo).length, 1);
      expectText(test, tChatLastRole(w, convo), "user");
      let main = tMain(r);
      expectHas(test, main, "Wait for me");
      expectHas(test, main, "data-poll");
      expectHas(test, main, "mg-dots");
      expectHas(test, main, "Thinking…");
      expectHas(test, main, "disabled");
      expectText(test, tChatRunStatus(w.db, showChatConversationKey(w.work.id, convo)), "running");
    }

    test("send: a second question while one is being answered starts nothing and stores nothing") { test =>
      let w = tWorld();
      tChatSend(w, w.owner, "One", tQueue());
      tChatSend(w, w.owner, "Two", tQueue());
      expectInt(test, chatMessages(w.db, tChatConvo(w)).length, 1);
    }

    test("send: a blank question does nothing") { test =>
      let w = tWorld();
      let r = tChatSend(w, w.owner, "   ", tKeyed());
      expectInt(test, r.resp.status, 200);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages"), 0);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
    }

    test("send: someone holding the link is told the draft is not theirs, and nothing is asked") { test =>
      let w = tWorld();
      let r = tChatSend(w, w.reader, "hello", tKeyed());
      expectText(test, tFlash(r, "error"), "This draft is someone else's. You can read it, not change it.");
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages"), 0);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
    }

    test("send: an account with no questions left asks nothing") { test =>
      let w = tWorld();
      let convo = tChatConvo(w);
      var i = 0;
      while (i < 100) {
        chatAppend(w.db, convo, "user", "q${i.toString()}");
        i += 1;
      }
      tChatSend(w, w.owner, "one too many", tKeyed());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages"), 100);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
    }

    test("send: with no key, or before the read, nothing is stored") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tChatPage(w), "send", "{\"message\":\"hello\"}", tNoKey());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages"), 0);
      let fresh = tDraft(w.db, w.owner.scope, "Unread", tBody());
      tEvent(w.db, w.owner, "${tPath(fresh, "read")}&chat=1", "send", "{\"message\":\"hello\"}", tKeyed());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages"), 0);
    }

    test("send: a model that fails leaves the question, stores no answer, and the transcript says why") { test =>
      let w = tWorld();
      let r = tChatSend(w, w.owner, "Will this fail?", tChatLauncher(llmFake([])));
      let convo = tChatConvo(w);
      expectInt(test, chatMessages(w.db, convo).length, 1);
      expectText(test, tChatLastRole(w, convo), "user");
      let main = tMain(r);
      expectHas(test, main, "Will this fail?");
      expectHas(test, main, "I hit an error: ");
      expectLacks(test, main, "data-poll");
      let again = tChatOpen(w, w.owner);
      expectHas(test, again, "I hit an error: ");
    }

    test("send: a job that crashes is said to have crashed") { test =>
      let w = tWorld();
      tChatSend(w, w.owner, "Crash", tQueue());
      let convo = tChatConvo(w);
      w.db.exec("UPDATE runs SET status = 'crashed', detail = 'Bubble' WHERE key = $1", [showChatConversationKey(w.work.id, convo)]);
      expectHas(test, tChatOpen(w, w.owner), "Something crashed: Bubble");
    }

    test("send: the next question clears the last one's error") { test =>
      let w = tWorld();
      tChatSend(w, w.owner, "Fail first", tChatLauncher(llmFake([])));
      let r = tChatSend(w, w.owner, "Then work", tChatLauncher(llmFake([tChatReply("It worked.")])));
      let main = tMain(r);
      expectHas(test, main, "It worked.");
      expectLacks(test, main, "I hit an error: ");
      expectInt(test, chatMessages(w.db, tChatConvo(w)).length, 3);
    }

    test("send: the questions left go down by one, and the mutter is picked for the wait") { test =>
      let w = tWorld();
      w.db.exec("INSERT INTO mutterings (text, source) VALUES ('Brooding over the kettle', 'cron')", []);
      let convo = tChatConvo(w);
      var i = 0;
      while (i < 90) {
        chatAppend(w.db, convo, "user", "q${i.toString()}");
        i += 1;
      }
      let r = tChatSend(w, w.owner, "Mutter", tQueue());
      let main = tMain(r);
      expectHas(test, main, "9 left");
      expectHas(test, main, "Brooding over the kettle");
    }

## What it is holding, and what it carries

    test("discuss: a note carries its sections into the chat, and the address says the drawer is open") { test =>
      let w = tWorld();
      let beat = tBeat(w.db, w.work, "A beat");
      let r = tEvent(w.db, w.owner, tPage(w), "discuss", "{\"key\":\"beat:${beat.id.toString()}\"}", tKeyed());
      expectText(test, tRedirect(r), "/works/${w.work.slug}?view=read&chat=1");
      let page = tChatOpen(w, w.owner);
      expectHas(test, page, "holding · beat");
      expectHas(test, page, "A beat");
      expectHas(test, page, "class=\"mg-held\"");
      expectHas(test, page, "words, in full");
      expectHas(test, page, "phx-click=\"clear_focus\"");
    }

    test("discuss: a key that names nothing changes nothing") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "discuss", "{\"key\":\"beat:99999\"}", tKeyed());
      expectText(test, tRedirect(r), "");
      expectLacks(test, tChatOpen(w, w.owner), "holding ·");
    }

    test("discuss: a connection is held with both its sections") { test =>
      let w = tWorld();
      let a = tBeat(w.db, w.work, "Alpha");
      let b = tBeat(w.db, w.work, "Beta");
      tEdge(w.db, w.work, a, b, "develops");
      tEvent(w.db, w.owner, tPage(w), "discuss", "{\"key\":\"conn:${a.id.toString()}:${b.id.toString()}:develops\"}", tKeyed());
      let page = tChatOpen(w, w.owner);
      expectHas(test, page, "holding · develops");
      expectHas(test, page, "Alpha  —develops→  Beta");
    }

    test("clear_focus: dropping the held note takes the card away") { test =>
      let w = tWorld();
      let beat = tBeat(w.db, w.work, "A beat");
      tEvent(w.db, w.owner, tPage(w), "discuss", "{\"key\":\"beat:${beat.id.toString()}\"}", tKeyed());
      let r = tEvent(w.db, w.owner, tChatPage(w), "clear_focus", "{}", tKeyed());
      expectLacks(test, tMain(r), "holding ·");
    }

    test("discuss_node: a spine node is held with the beats under it and the sections they sit in") { test =>
      let w = tWorld();
      let node = tNode(w.db, w.work, "spine", "The spine", null);
      let beat = tBeat(w.db, w.work, "A beat");
      tEdge(w.db, w.work, node, beat, "realises");
      let r = tEvent(w.db, w.owner, tPage(w), "discuss_node", "{\"id\":\"${node.id.toString()}\"}", tKeyed());
      expectText(test, tRedirect(r), "/works/${w.work.slug}?view=read&chat=1");
      let page = tChatOpen(w, w.owner);
      expectHas(test, page, "holding · spine");
      expectHas(test, page, "The spine");
      let client = llmFake([tChatReply("Held.")]);
      tChatSend(w, w.owner, "About that", tChatLauncher(client));
      let reqs = llmRequests(client);
      expectHas(test, reqs[0], "It runs through section 1: A beat.");
    }

    test("discuss_node: a node of another draft, or none, holds nothing") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "discuss_node", "{\"id\":\"99999\"}", tKeyed());
      expectLacks(test, tChatOpen(w, w.owner), "holding ·");
    }

    test("discuss_node: someone holding the link cannot hold a node") { test =>
      let w = tWorld();
      let node = tNode(w.db, w.work, "spine", "The spine", null);
      let r = tEvent(w.db, w.reader, tPage(w), "discuss_node", "{\"id\":\"${node.id.toString()}\"}", tKeyed());
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
    }

    test("add_context: a real selection is kept, verbatim from the draft") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"  The kettle went cold on the counter \"}", tKeyed());
      let main = tMain(r);
      expectHas(test, main, "Carrying 1 passage");
      expectHas(test, main, "The kettle went cold on the counter");
      expectHas(test, main, "phx-click=\"drop_context\"");
    }

    test("add_context: with the drawer shut, the address gains chat=1") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "add_context", "{\"text\":\"The kettle went cold on the counter\"}", tKeyed());
      expectText(test, tRedirect(r), "/works/${w.work.slug}?view=read&chat=1");
    }

    test("add_context: a selection that is not in the draft, or a stray word, is refused") { test =>
      let w = tWorld();
      let a = tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"a sentence the writer never wrote\"}", tKeyed());
      expectLacks(test, tMain(a), "Carrying");
      let b = tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"the\"}", tKeyed());
      expectLacks(test, tMain(b), "Carrying");
    }

    test("add_context: the same passage twice is carried once, and two are carried as two") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"The kettle went cold on the counter\"}", tKeyed());
      let twice = tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"The kettle went cold on the counter\"}", tKeyed());
      expectHas(test, tMain(twice), "Carrying 1 passage");
      let two = tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"She had been standing at the window for an hour\"}", tKeyed());
      expectHas(test, tMain(two), "Carrying 2 passages");
    }

    test("add_context: someone holding the link cannot carry a passage") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.reader, tChatPage(w), "add_context", "{\"text\":\"The kettle went cold on the counter\"}", tKeyed());
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
    }

    test("drop_context: the passage at that place goes, the other stays") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"The kettle went cold on the counter\"}", tKeyed());
      tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"She had been standing at the window for an hour\"}", tKeyed());
      let r = tEvent(w.db, w.owner, tChatPage(w), "drop_context", "{\"i\":\"0\"}", tKeyed());
      let main = tMain(r);
      expectHas(test, main, "Carrying 1 passage");
      expectHas(test, main, "She had been standing at the window");
      expectLacks(test, main, "&quot;The kettle went cold on the counter&quot;");
      let none = tEvent(w.db, w.owner, tChatPage(w), "drop_context", "{\"i\":\"0\"}", tKeyed());
      expectLacks(test, tMain(none), "Carrying");
    }

    test("send: the carried passages and the held note go to the model; the passages are used up, the note stays") { test =>
      let w = tWorld();
      let beat = tBeat(w.db, w.work, "A beat");
      tEvent(w.db, w.owner, tPage(w), "discuss", "{\"key\":\"beat:${beat.id.toString()}\"}", tKeyed());
      tEvent(w.db, w.owner, tChatPage(w), "add_context", "{\"text\":\"The kettle went cold on the counter\"}", tKeyed());
      let client = llmFake([tChatReply("Noted.")]);
      let r = tChatSend(w, w.owner, "Look at these", tChatLauncher(client));
      let reqs = llmRequests(client);
      expectHas(test, reqs[0], "THE WRITER CLICKED A NOTE");
      expectHas(test, reqs[0], "THE WRITER SELECTED THESE PASSAGES");
      expectHas(test, reqs[0], "From section 1");
      let main = tMain(r);
      expectLacks(test, main, "Carrying");
      expectHas(test, main, "holding · beat");
    }

## Which conversation

    test("new_chat: a new thread starts empty and becomes the one you are in, in the stance you were in") { test =>
      let w = tWorld();
      let first = tChatConvo(w);
      chatAppend(w.db, first, "user", "the first question I asked");
      let held = chatGetOrCreateConversation(w.db, w.work.id).conversation;
      expectTrue(test, held != null, "the conversation");
      if (held != null) { chatSetMode(w.db, held, "bounce"); }
      let r = tEvent(w.db, w.owner, tChatPage(w), "new_chat", "{}", tKeyed());
      let main = tMain(r);
      expectInt(test, chatListConversations(w.db, w.work.id).length, 2);
      expectHas(test, main, "class=\"mg-thread on\"");
      expectHas(test, main, "the first question I asked");
      expectHas(test, main, "Tell me the idea.");
      expectHas(test, main, "class=\"mg-tab on\" phx-click=\"set_mode\" phx-value-mode=\"bounce\"");
    }

    test("switch_chat: going back brings its history with it, and leaves the held note behind") { test =>
      let w = tWorld();
      let a = tChatConvo(w);
      chatAppend(w.db, a, "user", "about the kettle");
      chatAppend(w.db, a, "assistant", "the kettle is doing a lot of work");
      tEvent(w.db, w.owner, tChatPage(w), "new_chat", "{}", tKeyed());
      let gone = tChatOpen(w, w.owner);
      expectLacks(test, gone, "the kettle is doing a lot of work");
      let r = tEvent(w.db, w.owner, tChatPage(w), "switch_chat", "{\"id\":\"${a.toString()}\"}", tKeyed());
      expectHas(test, tMain(r), "the kettle is doing a lot of work");
      expectHas(test, tChatOpen(w, w.owner), "the kettle is doing a lot of work");
    }

    test("switch_chat: a thread of another draft cannot be switched to") { test =>
      let w = tWorld();
      let other = tRead(w.db, w.owner.scope, "Other", tBody());
      let theirs = chatGetOrCreateConversation(w.db, other.id).conversation;
      expectTrue(test, theirs != null, "the other draft's conversation");
      if (theirs != null) {
        chatAppend(w.db, theirs.id, "user", "secret of the other draft");
        let r = tEvent(w.db, w.owner, tChatPage(w), "switch_chat", "{\"id\":\"${theirs.id.toString()}\"}", tKeyed());
        expectInt(test, r.resp.status, 200);
        expectLacks(test, tChatOpen(w, w.owner), "secret of the other draft");
      }
    }

    test("delete_chat: deleting the thread you are in takes its messages and lands you in another") { test =>
      let w = tWorld();
      let a = tChatConvo(w);
      chatAppend(w.db, a, "user", "the old one");
      tEvent(w.db, w.owner, tChatPage(w), "new_chat", "{}", tKeyed());
      let all = chatListConversations(w.db, w.work.id);
      expectInt(test, all.length, 2);
      let newest = all[0];
      chatAppend(w.db, newest.id, "user", "the doomed one");
      let r = tEvent(w.db, w.owner, tChatPage(w), "delete_chat", "{\"id\":\"${newest.id.toString()}\"}", tKeyed());
      let left = chatListConversations(w.db, w.work.id);
      expectInt(test, left.length, 1);
      expectInt(test, left[0].id, a);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages WHERE conversation_id = ${newest.id.toString()}"), 0);
      expectHas(test, tMain(r), "the old one");
      expectLacks(test, tMain(r), "the doomed one");
      expectLacks(test, tMain(r), "phx-click=\"delete_chat\"");
    }

    test("new_chat, switch_chat, delete_chat: someone holding the link changes nothing") { test =>
      let w = tWorld();
      let a = tChatConvo(w);
      let denial = "This draft is someone else's.";
      expectText(test, tFlash(tEvent(w.db, w.reader, tChatPage(w), "new_chat", "{}", tKeyed()), "error"), denial);
      expectText(test, tFlash(tEvent(w.db, w.reader, tChatPage(w), "switch_chat", "{\"id\":\"${a.toString()}\"}", tKeyed()), "error"), denial);
      expectText(test, tFlash(tEvent(w.db, w.reader, tChatPage(w), "delete_chat", "{\"id\":\"${a.toString()}\"}", tKeyed()), "error"), denial);
      expectInt(test, chatListConversations(w.db, w.work.id).length, 1);
    }

    test("set_mode: the stance changes and keeps the history; an unknown one is refused") { test =>
      let w = tWorld();
      let convo = tChatConvo(w);
      chatAppend(w.db, convo, "user", "kept");
      let r = tEvent(w.db, w.owner, tChatPage(w), "set_mode", "{\"mode\":\"provoke\"}", tKeyed());
      let main = tMain(r);
      expectHas(test, main, "class=\"mg-tab on\" phx-click=\"set_mode\" phx-value-mode=\"provoke\"");
      expectHas(test, main, "Questions that open the next draft");
      expectHas(test, main, "kept");
      let bad = tEvent(w.db, w.owner, tChatPage(w), "set_mode", "{\"mode\":\"hacker\"}", tKeyed());
      expectText(test, tFlash(bad, "error"), "That is not one of the ways to talk about it.");
      expectHas(test, tChatOpen(w, w.owner), "class=\"mg-tab on\" phx-click=\"set_mode\" phx-value-mode=\"provoke\"");
    }

    test("set_mode: the stance goes to the model") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tChatPage(w), "set_mode", "{\"mode\":\"bounce\"}", tKeyed());
      let client = llmFake([tChatReply("Bent.")]);
      tChatSend(w, w.owner, "An idea", tChatLauncher(client));
      expectHas(test, llmRequests(client)[0], "MODE: BOUNCE.");
    }

## Threads under a paragraph

    let tChatThreadPage(w: TWorld): String { "${tPage(w)}" }

    let tChatRef(s: Section): String { readingBlocks(s)[1].ref }

    let tChatOpenThread(w: TWorld): Int throws Bubble {
      let s = tSection(w.db, w.work);
      let ref = tChatRef(s);
      tEvent(w.db, w.owner, tChatThreadPage(w), "open_thread", "{\"ref\":\"${ref}\",\"section\":\"${s.id.toString()}\"}", tKeyed());
      tN(w.db, "SELECT id AS n FROM conversations WHERE block_ref = '${ref}'")
    }

    test("thread_send: the question is stored, the reader answers, and the answer is under the paragraph") { test =>
      let w = tWorld();
      let thread = tChatOpenThread(w);
      expectTrue(test, thread > 0, "a thread was opened");
      let client = llmFake([tChatReply("It sets the kettle up.")]);
      let r = tEvent(w.db, w.owner, tChatThreadPage(w), "thread_send", "{\"message\":\"What is this doing?\"}", tChatLauncher(client));
      expectHas(test, r.resp.body, "chat:clear");
      let ms = chatMessages(w.db, thread);
      expectInt(test, ms.length, 2);
      expectText(test, ms[0].content, "What is this doing?");
      expectText(test, ms[1].content, "It sets the kettle up.");
      let main = tMain(r);
      expectHas(test, main, "id=\"thread-form-${thread.toString()}\"");
      expectHas(test, main, "id=\"thread-body-${thread.toString()}\"");
      expectHas(test, main, "What is this doing?");
      expectHas(test, main, "It sets the kettle up.");
      expectLacks(test, main, "data-poll");
      let reqs = llmRequests(client);
      expectHas(test, reqs[0], "A thread pinned to one place in the draft");
      expectHas(test, reqs[0], "Stay on it.");
      expectText(test, tChatRunStatus(w.db, showChatThreadKey(w.work.id, thread)), "done");
    }

    test("thread_send: the page waits while it runs, and the drawer's conversation is untouched") { test =>
      let w = tWorld();
      let thread = tChatOpenThread(w);
      let r = tEvent(w.db, w.owner, tChatThreadPage(w), "thread_send", "{\"message\":\"Hold on\"}", tQueue());
      let main = tMain(r);
      expectHas(test, main, "data-poll");
      expectHas(test, main, "Hold on");
      expectInt(test, chatMessages(w.db, thread).length, 1);
      expectInt(test, chatMessages(w.db, tChatConvo(w)).length, 0);
    }

    test("thread_send: a failure is said once, as a flash, and stores no answer") { test =>
      let w = tWorld();
      let thread = tChatOpenThread(w);
      let r = tEvent(w.db, w.owner, tChatThreadPage(w), "thread_send", "{\"message\":\"Will fail\"}", tChatLauncher(llmFake([])));
      expectText(test, tChatLastRole(w, thread), "user");
      expectHas(test, tFlash(r, "error"), "That did not go through: ");
      let again = tPoll(w.db, w.owner, tChatThreadPage(w), tKeyed());
      expectText(test, tFlash(again, "error"), "");
    }

    test("thread_send: someone holding the link is told the draft is not theirs") { test =>
      let w = tWorld();
      let thread = tChatOpenThread(w);
      let r = tEvent(w.db, w.reader, tChatThreadPage(w), "thread_send", "{\"message\":\"hello\"}", tKeyed());
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
      expectInt(test, chatMessages(w.db, thread).length, 0);
    }

    test("thread_send: with no thread open, or a blank message, nothing happens") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tChatThreadPage(w), "thread_send", "{\"message\":\"hello\"}", tKeyed());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages"), 0);
      tChatOpenThread(w);
      tEvent(w.db, w.owner, tChatThreadPage(w), "thread_send", "{\"message\":\"  \"}", tKeyed());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages"), 0);
    }

    test("thread_send: in the walkthrough the answer is the fixture, and nothing is written") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", tKeyed());
      let s = tSection(w.db, w.work);
      tEvent(w.db, w.owner, tPage(w), "open_thread", "{\"ref\":\"${tChatRef(s)}\",\"section\":\"${s.id.toString()}\"}", tKeyed());
      let before = tN(w.db, "SELECT count(*) AS n FROM messages");
      let calls = llmFake([]);
      let r = tEvent(w.db, w.owner, tPage(w), "thread_send", "{\"message\":\"What is this paragraph doing?\"}", tChatLauncher(calls));
      let main = tMain(r);
      expectHas(test, main, "What is this paragraph doing?");
      expectHas(test, main, "never calls the model");
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM messages"), before);
      expectInt(test, llmRequests(calls).length, 0);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM conversations WHERE block_ref IS NOT NULL"), 0);
      let again = tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed()));
      expectHas(test, again, "never calls the model");
      tEvent(w.db, w.owner, tPage(w), "end_walk", "{}", tKeyed());
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed())), "never calls the model");
    }
