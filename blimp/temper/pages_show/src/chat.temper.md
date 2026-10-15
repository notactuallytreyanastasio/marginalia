# The chat drawer

`chat_panel/1` and the eleven events that feed it. This file is the front door
(the three names the frame and the dispatcher call) and the events that only
change what the chat is holding or which conversation it is in; the drawer is
drawn by `chat_panel.temper.md`, and the two that ask the model (`send`,
`thread_send`) and the job behind them are in `chat_ask.temper.md`.

The drawer's data is read from the database on every request (`psLoadChat` in
`load.temper.md`: the conversation in use, its last messages, the strip of
threads, the questions left, the open thread's messages). What lives in the
session is in `ui.temper.md`: `focus`, `cited`, `conversation`, `mutter`,
`mutterSeen`. `loading` and `threadLoading` are in it too, but they are not
believed: `showChatSettle` sets both again on every load from the runs table,
which is what makes a question in flight survive a reload and what stops a
page whose answer has arrived from polling for ever.

    let { Ctx, uiGet, uiDelete } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { GraphNode, worksGetNode } = import("works/src");
    let {
      Conversation, ChatTurn, chatCreateConversation, chatGetConversation, chatDeleteConversation,
      chatGetOrCreateConversation, chatSetMode,
    } = import("chat/src");
    let {
      ReadingFocus, ReadingCite, ReadingGround, readingFocus, readingCite, readingGrounding,
    } = import("reading/src");

    export let showChatEventNames(): List<String> {
      [
        "discuss", "discuss_node", "clear_focus", "add_context", "drop_context",
        "new_chat", "switch_chat", "delete_chat", "set_mode", "send", "thread_send",
      ]
    }

## Waiting, and the walkthrough's thread

Whether a question is in flight is the question "is the run for it going?",
asked of the runs the page found (`state.running`), for the conversation the
drawer is in and the thread that is open. The walkthrough's thread has no row to
keep its turns in, so they are kept in the session under a key of their own and
read back here; they are dropped as soon as the walkthrough is not on, or the
thread is some other paragraph's.

    export let showChatTurnsJson(ref: String, turns: List<ChatTurn>): String throws Bubble {
      let p = showProducer();
      p.startObject();
      showKeyStr(p, "ref", ref);
      p.objectKey("turns");
      p.startArray();
      for (let t of turns) {
        p.startObject();
        showKeyStr(p, "role", t.role);
        showKeyStr(p, "content", t.content);
        p.endObject();
      }
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

    let psChatDemoTurns(ctx: Ctx, state: ShowState, thread: Conversation): List<ChatTurn> {
      let kept = showParse(uiGet(ctx, showChatDemoKey(state.work.slug)));
      let out = new ListBuilder<ChatTurn>();
      if (showJStr(kept, "ref") == thread.blockRef) {
        for (let t of showJList(kept, "turns")) {
          out.add(new ChatTurn(showOr(showJStr(t, "role"), "assistant"), showOr(showJStr(t, "content"), "")));
        }
      }
      out.toList()
    }

    let psChatDemoHistory(ctx: Ctx, state: ShowState): Void {
      let thread = state.openThread;
      if (state.demo) {
        if (thread != null) {
          if (thread.id == 0) { state.threadHistory = psChatDemoTurns(ctx, state, thread); }
        }
      } else if (uiGet(ctx, showChatDemoKey(state.work.slug)) != null) {
        uiDelete(ctx, showChatDemoKey(state.work.slug));
      }
    }

Called by the end of `psLoadChat`, after the runs have been read.

    export let showChatSettle(ctx: Ctx, state: ShowState): Void {
      var asking = false;
      var threadAsking = false;
      let convo = state.conversation;
      let thread = state.openThread;
      for (let r of state.running) {
        if (convo != null) {
          if (r.key == showChatConversationKey(state.work.id, convo.id)) { asking = true; }
        }
        if (thread != null) {
          if (r.key == showChatThreadKey(state.work.id, thread.id)) { threadAsking = true; }
        }
      }
      state.loading = asking;
      state.threadLoading = threadAsking;
      psChatDemoHistory(ctx, state);
    }

## What the chat is holding

`discuss {key}` (a note card): the note and the sections it touches become the
focus, and the drawer opens (the address gains `chat=1`). A key that names
nothing changes nothing. A reader may do it: the card is theirs to look at, and
the box that would use it is not drawn for them.

    let psChatOpen(state: ShowState): ShowOutcome {
      showGoing(showPath(state.work.slug, state.view, true))
    }

    let psChatDiscuss(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      let focus = readingFocus(ctx.db, state.work, showPayloadStr(payload, "key"));
      if (focus != null) {
        state.focus = focus;
        psChatOpen(state)
      } else { showDone() }
    }

`discuss_node {id}` (the Discuss button on a spine node, thread or question): the
node, and the beats it is grounded in with the sections they sit in, in full.
The note says which sections it runs through. The owner's.

    let psChatGroundNote(beats: List<ReadingGround>): String? {
      if (beats.length == 0) { return null; }
      let parts = beats.map { (b: ReadingGround): String =>
        let s = b.section;
        "section ${if (s != null) { s.ordinal.toString() } else { "" }}: ${b.title}"
      };
      "It runs through ${showJoin(parts, "; ")}."
    }

    let psChatNodeBody(node: GraphNode, note: String?): String? {
      let parts = new ListBuilder<String>();
      let body = node.body;
      if (body != null) { if (body != "") { parts.add(body); } }
      if (note != null) { if (note != "") { parts.add(note); } }
      if (parts.length == 0) { null } else { showJoin(parts.toList(), " ") }
    }

    let psChatNodeQuote(node: GraphNode, beats: List<ReadingGround>): String? {
      let own = node.quote;
      if (own != null) { return own; }
      if (beats.length > 0) { beats[0].quote } else { null }
    }

    let psChatDiscussNode(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      let id = showIntOr(showPayloadInt(payload, "id"), -1);
      let node = worksGetNode(ctx.db, state.work.id, id);
      if (node != null) {
        let g = readingGrounding(ctx.db, state.work, node.id);
        state.focus = new ReadingFocus(
          node.nodeType, node.title, psChatNodeBody(node, psChatGroundNote(g.beats)),
          psChatNodeQuote(node, g.beats), g.sections,
        );
        psChatOpen(state)
      } else { showDone() }
    }

`clear_focus` ("drop").

## Passages carried into the next question

`add_context {text}` (the selection toolbar's "Add to question"): the passage is
looked for in the draft, and what is kept is the draft's own characters, not
what the browser's selection picked up. Six at most, one of each text. The owner's.
The drawer opens, and, being open by address now, the address says so (the
Elixir opened it in state only, so the next navigation shut it again).

    let psChatCarried(cited: List<ReadingCite>, cite: ReadingCite): List<ReadingCite> {
      let out = new ListBuilder<ReadingCite>();
      for (let c of cited) { out.add(c); }
      var seen = false;
      for (let c of cited) { if (c.text == cite.text) { seen = true; } }
      if (!seen) { out.add(cite); }
      out.toList().slice(0, if (out.length > 6) { 6 } else { out.length })
    }

    let psChatAddContext(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      let cite = readingCite(ctx.db, state.work, showTrim(showPayloadStr(payload, "text")));
      if (cite != null) {
        state.cited = psChatCarried(state.cited, cite);
        if (state.chatOpen) { showDone() } else { psChatOpen(state) }
      } else { showDone() }
    }

`drop_context {i}`: the one at that place goes. (The Elixir took the last one
for an index that was not a number.)

    let psChatDropContext(state: ShowState, payload: JsonObject): ShowOutcome {
      let i = showPayloadInt(payload, "i");
      if (i != null) {
        let out = new ListBuilder<ReadingCite>();
        var at = 0;
        for (let c of state.cited) {
          if (at != i) { out.add(c); }
          at += 1;
        }
        state.cited = out.toList();
      }
      showDone()
    }

## Which conversation

`switch_to/2`: the conversation in use, with nothing held and nothing carried.
The messages and the strip are read again by the load that follows.

    let psChatSwitchTo(state: ShowState, convo: Conversation): ShowOutcome {
      state.conversation = convo;
      state.savedConversation = convo.id;
      state.mode = convo.mode;
      state.history = [];
      state.focus = null;
      state.cited = [];
      state.loading = false;
      showDone()
    }

`new_chat`: a new whole-draft conversation in the stance the drawer is in.

    let psChatNew(ctx: Ctx, state: ShowState): ShowOutcome throws Bubble {
      let made = chatCreateConversation(ctx.db, state.work.id, state.mode).conversation;
      if (made != null) { psChatSwitchTo(state, made) } else { showDone() }
    }

`switch_chat {id}`: a conversation of this draft. One of another draft is not
reachable by guessing its id.

    let psChatSwitch(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      let id = showIntOr(showPayloadInt(payload, "id"), -1);
      let found = chatGetConversation(ctx.db, state.work.id, id);
      if (found != null) { psChatSwitchTo(state, found) } else { showDone() }
    }

`delete_chat {id}`: the conversation and everything said in it, and then the
latest that remains, or a fresh one.

    let psChatDeleteConvo(ctx: Ctx, state: ShowState, found: Conversation): ShowOutcome throws Bubble {
      if (chatDeleteConversation(ctx.db, found)) {
        let next = chatGetOrCreateConversation(ctx.db, state.work.id).conversation;
        if (next != null) { psChatSwitchTo(state, next) } else { showDone() }
      } else { showDone() }
    }

    let psChatRemove(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      let id = showIntOr(showPayloadInt(payload, "id"), -1);
      let found = chatGetConversation(ctx.db, state.work.id, id);
      if (found != null) { psChatDeleteConvo(ctx, state, found) } else { showDone() }
    }

`set_mode {mode}` (the owner's, refused before it gets here for anyone else):
the stance of the conversation in use; it keeps its history. A mode that is not
one of the three is told so (the Elixir crashed the process on it).

    let psChatMode(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      let convo = state.conversation;
      if (convo != null) {
        let r = chatSetMode(ctx.db, convo, showPayloadStr(payload, "mode"));
        let changed = r.conversation;
        if (changed != null) {
          state.conversation = changed;
          state.mode = changed.mode;
          showDone()
        } else {
          showError("That is not one of the ways to talk about it.")
        }
      } else { showDone() }
    }

## The events

    export let showChatEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      if (event == "discuss") {
        psChatDiscuss(ctx, state, payload)
      } else if (event == "discuss_node") {
        psChatDiscussNode(ctx, state, payload)
      } else if (event == "clear_focus") {
        state.focus = null;
        showDone()
      } else if (event == "add_context") {
        psChatAddContext(ctx, state, payload)
      } else if (event == "drop_context") {
        psChatDropContext(state, payload)
      } else if (event == "set_mode") {
        psChatMode(ctx, state, payload)
      } else if (event == "send") {
        psChatSend(ctx, state, payload, launcher)
      } else if (event == "thread_send") {
        psChatThreadSend(ctx, state, payload, launcher)
      } else if (!state.mine) {
        showError(showDeniedPlain())
      } else if (event == "new_chat") {
        psChatNew(ctx, state)
      } else if (event == "switch_chat") {
        psChatSwitch(ctx, state, payload)
      } else if (event == "delete_chat") {
        psChatRemove(ctx, state, payload)
      } else {
        console.log("pages_show chat: no event ${event}");
        bubble()
      }
    }
