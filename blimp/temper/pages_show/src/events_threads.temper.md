# Events: threads on a paragraph

`open_thread`, `close_thread`, `resolve_thread`. A thread is a conversation
pinned to one paragraph (`block_ref`), or to a passage inside it (a `quote`,
`anchor_kind` `span`). There is one per `(work, block ref)`: opening the same
paragraph again returns to the thread already there. Sending into it is the
chat's (`thread_send`, `chat.temper.md`).

    let { Ctx } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { Section, worksSectionById } = import("works/src");
    let { Conversation, ChatThread, chatThreadForBlock, chatResolveThread, chatGetConversation } = import("chat/src");
    let { readingBlocks, ReadingBlock } = import("reading/src");

    export let showThreadEvents(): List<String> {
      ["open_thread", "close_thread", "resolve_thread"]
    }

Whether the section has a block of that ref. A click on a paragraph that is not
there makes no thread: the Elixir wrote a row for any ref a payload carried.

    let psSectionHasBlock(section: Section, workId: Int, ref: String): Boolean {
      if (section.workId != workId) { return false; }
      for (let b of readingBlocks(section)) {
        if (b.ref == ref) { return true; }
      }
      false
    }

    let psHasBlock(ctx: Ctx, state: ShowState, sectionId: Int?, ref: String): Boolean throws Bubble {
      if (sectionId != null) {
        let section = worksSectionById(ctx.db, sectionId);
        if (section != null) { psSectionHasBlock(section, state.work.id, ref) } else { false }
      } else { false }
    }

The walkthrough opens a thread that is never saved: an unsaved conversation
with id 0, which the ui state carries and the page draws like any other.

    let psDemoThread(ctx: Ctx, state: ShowState, ref: String, sectionId: Int?, quote: String?): Conversation {
      new Conversation(
        0, state.work.id, null, "read", if (quote != null) { "span" } else { "block" },
        sectionId, ref, quote, null, ctx.now, ctx.now,
      )
    }

A reader holding the link may open a thread that exists, to read it, but not
make one.

    let psReaderOpens(ctx: Ctx, state: ShowState, ref: String): ShowOutcome throws Bubble {
      let known: ChatThread? = state.blockThreads.get(ref) orelse null;
      if (known != null) {
        state.openThread = chatGetConversation(ctx.db, state.work.id, known.id);
        state.threadLoading = false;
        showDone()
      } else {
        showError(showDeniedPlain())
      }
    }

    let psOwnerOpens(ctx: Ctx, state: ShowState, ref: String, sectionId: Int?, quote: String?): ShowOutcome throws Bubble {
      if (psHasBlock(ctx, state, sectionId, ref)) {
        let thread = chatThreadForBlock(ctx.db, state.work.id, sectionId, ref, quote, null).conversation;
        if (thread != null) {
          state.openThread = thread;
          state.threadLoading = false;
        }
      }
      showDone()
    }

`open_thread {ref, section, quote?}`. The tick sends the ref and the section's
id; the selection toolbar adds the passage.

    let psOpenThread(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      let ref = showPayloadStr(payload, "ref");
      if (ref == "") { return showDone(); }
      let sectionId = showPayloadInt(payload, "section");
      let quoteText = showPayloadStr(payload, "quote");
      let quote: String? = if (quoteText == "") { null } else { quoteText };
      if (state.demo) {
        state.openThread = psDemoThread(ctx, state, ref, sectionId, quote);
        state.threadHistory = [];
        state.threadLoading = false;
        showDone()
      } else if (state.mine) {
        psOwnerOpens(ctx, state, ref, sectionId, quote)
      } else {
        psReaderOpens(ctx, state, ref)
      }
    }

`resolve_thread` ("settle", "reopen"): the open thread is marked settled, or
settled no longer. The owner's.

    let psResolveOpen(ctx: Ctx, state: ShowState, thread: Conversation): ShowOutcome throws Bubble {
      if (thread.id != 0) {
        let updated = chatResolveThread(ctx.db, thread, thread.resolvedAt == null).conversation;
        if (updated != null) { state.openThread = updated; }
      }
      showDone()
    }

    let psResolveThread(ctx: Ctx, state: ShowState): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      let thread = state.openThread;
      if (thread != null) { psResolveOpen(ctx, state, thread) } else { showDone() }
    }

    export let showThreadEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      if (event == "open_thread") {
        psOpenThread(ctx, state, payload)
      } else if (event == "close_thread") {
        state.openThread = null;
        state.threadHistory = [];
        state.threadLoading = false;
        showDone()
      } else {
        psResolveThread(ctx, state)
      }
    }
