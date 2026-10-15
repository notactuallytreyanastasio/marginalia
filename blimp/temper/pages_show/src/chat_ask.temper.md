# Asking the model: `send` and `thread_send`

A question to the model is a slow call, so it is a job under the run key of the
conversation it belongs to (`work:<id>:chat:<conversation>` for the drawer,
`work:<id>:thread:<thread>` for a thread under a paragraph). The Elixir kept one
`loading` flag per kind; asking the runs table instead means two conversations
can be asked in at once and a page opened mid-answer is still waiting.

The writer's question is stored before the model is called, as it was, so the
very next render has it. The answer is stored by the job, which leaves in its
run's `detail` only whether it worked: `{"ok": true}`, or `{"error": "<why>"}`.
What the page shows next is read from the database again.

    let { Ctx, uiPut } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { Db } = import("db/src");
    let { Work, Section, worksGetById, worksSectionById } = import("works/src");
    let { LlmClient } = import("llm/src");
    let { Run, runsRunning, runsFinish } = import("runs/src");
    let {
      Conversation, ChatTurn, chatAllowed, chatAppend, chatHistory, chatContextWindow,
      ChatFocus, ChatFocusSection, ChatCited, ChatAskResult, editorAsk,
    } = import("chat/src");
    let { ReadingFocus, ReadingCite } = import("reading/src");
    let { walkthroughExchange } = import("cases/src");

## The run keys

    export let showChatConversationKey(workId: Int, conversationId: Int): String {
      showRunKey(workId, "chat:${conversationId.toString()}")
    }

    export let showChatThreadKey(workId: Int, threadId: Int): String {
      showRunKey(workId, "thread:${threadId.toString()}")
    }

## What the model is handed

The note the chat is holding, as the editor's card: the note and each section it
touches in full. The passages the writer carried in.

    let psChatFocusOf(f: ReadingFocus?): ChatFocus? {
      if (f != null) {
        new ChatFocus(
          f.kind, f.title, f.body, f.quote,
          f.sections.map { (s: Section): ChatFocusSection => new ChatFocusSection(s.ordinal, s.title, s.body) },
        )
      } else { null }
    }

    let psChatCitedOf(cited: List<ReadingCite>): List<ChatCited> {
      cited.map { (c: ReadingCite): ChatCited => new ChatCited(c.text, c.section, c.ordinal) }
    }

What a thread tells the model it is about: the paragraph is the subject, so it
goes in as the focus rather than leaving the model to search for what "this"
means (`thread_focus/2`).

    let psChatThreadFocus(ctx: Ctx, thread: Conversation): ChatFocus throws Bubble {
      let kind = if (thread.quote != null) { "passage" } else { "paragraph" };
      let sections = new ListBuilder<ChatFocusSection>();
      let sectionId = thread.sectionId;
      if (sectionId != null) {
        let s = worksSectionById(ctx.db, sectionId);
        if (s != null) { sections.add(new ChatFocusSection(s.ordinal, s.title, s.body)); }
      }
      new ChatFocus(
        kind, "A thread pinned to one place in the draft",
        "The writer opened this thread on a single ${kind}. Stay on it. Quote it back, say what it is doing and not doing, and propose what would have to change — in their terms, without writing the replacement.",
        thread.quote, sections.toList(),
      )
    }

## The job

The history the model sees is read from the database in the job, the last twenty
turns, so it includes the question just stored. A reply is stored; a failure
stores nothing (the question stays, as it did) and is left in the run for the
page to say.

    let psChatWhy(r: ChatAskResult): String {
      let text = r.error;
      if (text != null) {
        text
      } else if (r.quotaExhausted) {
        "no questions left"
      } else {
        "no reply"
      }
    }

    let psChatJobWith(
      own: Db, llm: LlmClient, work: Work, conversationId: Int, mode: String,
      focus: ChatFocus?, cited: List<ChatCited>, key: String,
    ): Void throws Bubble {
      let window = chatContextWindow(chatHistory(own, conversationId));
      let result = editorAsk(own, llm, work, window, mode, focus, cited, "owner");
      let reply = result.text;
      if (reply != null) {
        chatAppend(own, conversationId, "assistant", reply);
        runsFinish(own, key, "done", showAnswerOk());
      } else {
        runsFinish(own, key, "done", showAnswerError(psChatWhy(result), null));
      }
    }

    export let showJobChat(
      own: Db, llm: LlmClient, workId: Int, conversationId: Int, mode: String,
      focus: ChatFocus?, cited: List<ChatCited>, key: String,
    ): Void throws Bubble {
      let work = worksGetById(own, workId);
      if (work != null) {
        psChatJobWith(own, llm, work, conversationId, mode, focus, cited, key);
      } else {
        runsFinish(own, key, "done", showAnswerError("the draft is gone", null));
      }
    }

## `send {message}`

The owner's (the dispatcher has refused everyone else). A blank question, one
already being answered in this conversation, or an account with no questions
left does nothing; so does a deploy with no key and a draft not yet read, which
the composer is not drawn for (the Elixir let a crafted event through and spent
a question on an error). `chat:clear` empties the box. The held note stays; the
carried passages are used up.

    let psChatClear(): ShowOutcome {
      new ShowOutcome(null, null, [new Pair("chat:clear", "{}")])
    }

    let psChatMay(ctx: Ctx, state: ShowState): Boolean throws Bubble {
      let user = state.user;
      if (user != null) {
        if (!state.llmReady || state.work.status == "pending") { false } else { chatAllowed(ctx.db, user) }
      } else { false }
    }

    let psChatAsk(
      ctx: Ctx, state: ShowState, convo: Conversation, text: String, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      let key = showChatConversationKey(state.work.id, convo.id);
      if (runsRunning(ctx.db, key)) { return showDone(); }
      if (!psChatMay(ctx, state)) { return showDone(); }
      chatAppend(ctx.db, convo.id, "user", text);
      showPickMutter(ctx, state);
      let workId = state.work.id;
      let provider = state.provider;
      let mode = state.mode;
      let focus = psChatFocusOf(state.focus);
      let cited = psChatCitedOf(state.cited);
      let convoId = convo.id;
      let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
        showJobChat(own, launcher.llm(provider), workId, convoId, mode, focus, cited, key)
      };
      state.cited = [];
      state.loading = started;
      psChatClear()
    }

    let psChatSend(ctx: Ctx, state: ShowState, payload: JsonObject, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      let text = showTrim(showPayloadStr(payload, "message"));
      let convo = state.conversation;
      if (text == "") { return showDone(); }
      if (convo != null) { psChatAsk(ctx, state, convo, text, launcher) } else { showDone() }
    }

## `thread_send {message}`

The same, into the thread open under a paragraph. A reader who sends it by hand
is told the draft is not theirs (the Elixir ignored it silently).

The walkthrough's thread is never saved, so its two turns are kept in the
session instead (`show:<slug>:demo_thread`, with the paragraph they belong to),
and the answer is the fixture, at once: the Elixir waited 1.1 seconds so the
answer would not be there before the question had finished rendering, and there
is no timer here. The model is never called and nothing is written to the
database.

    export let showChatDemoKey(slug: String): String { "show:${slug}:demo_thread" }

    let psChatDemoSend(ctx: Ctx, state: ShowState, thread: Conversation, text: String): ShowOutcome throws Bubble {
      let ref = showOr(thread.blockRef, "");
      let turns = new ListBuilder<ChatTurn>();
      turns.addAll(state.threadHistory);
      turns.add(new ChatTurn("user", text));
      turns.add(new ChatTurn("assistant", walkthroughExchange().answer));
      state.threadHistory = turns.toList();
      uiPut(ctx, showChatDemoKey(state.work.slug), showChatTurnsJson(ref, state.threadHistory));
      psChatClear()
    }

    let psChatThreadAsk(
      ctx: Ctx, state: ShowState, thread: Conversation, text: String, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      let key = showChatThreadKey(state.work.id, thread.id);
      if (runsRunning(ctx.db, key)) { return showDone(); }
      if (!psChatMay(ctx, state)) { return showDone(); }
      chatAppend(ctx.db, thread.id, "user", text);
      showPickMutter(ctx, state);
      let workId = state.work.id;
      let provider = state.provider;
      let mode = thread.mode;
      let focus = psChatThreadFocus(ctx, thread);
      let threadId = thread.id;
      let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
        showJobChat(own, launcher.llm(provider), workId, threadId, mode, focus, [], key)
      };
      if (started) { showMarkLaunched(ctx, state.work, key); }
      state.threadLoading = started;
      psChatClear()
    }

    let psChatThreadSend(ctx: Ctx, state: ShowState, payload: JsonObject, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      let text = showTrim(showPayloadStr(payload, "message"));
      let thread = state.openThread;
      if (text == "") { return showDone(); }
      if (thread != null) {
        if (state.demo) {
          psChatDemoSend(ctx, state, thread, text)
        } else if (thread.id == 0) {
          showDone()
        } else {
          psChatThreadAsk(ctx, state, thread, text, launcher)
        }
      } else { showDone() }
    }

## The wait, and what the answer was

`threadSend` flashes when its run ends in an error: `psFlashFor` (load.temper.md)
asks here for any run under `work:<id>:thread:`. The drawer's own failure is
drawn in the transcript instead (`chat_panel.temper.md`).

    export let showChatThreadFlash(run: Run): Pair<String, String>? {
      if (run.status == "crashed") {
        new Pair("error", "That did not go through: ${showOr(run.detail, "crashed")}")
      } else {
        let error = showJStr(showParse(run.detail), "error");
        if (error != null) { new Pair("error", "That did not go through: ${error}") } else { null }
      }
    }
