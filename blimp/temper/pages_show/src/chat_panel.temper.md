# The drawer

`chat_panel/1`: the inside of `div.mg-drawer`, drawn only while the drawer is
open. The draft's whole-conversation transcript, the mode picker, the strip of
threads, what the chat is holding, the passages it is carrying, the composer,
and in place of the composer the reason there is none (a reader's box, the
questions used up).

Every private name here starts `psChat`: the names of a library's files are one
namespace, and the frame, the read view and the events already own `ps` plus a
common noun.

    let { Ctx, cMutter } = import("webcore/src");
    let { h, htext, hraw, attr, markdownToHtml } = import("html/src");
    let { Section } = import("works/src");
    let { Conversation, ChatTurn, ChatSummary, ChatMode, editorMode, chatMessageLimit } = import("chat/src");
    let { ReadingFocus, ReadingCite } = import("reading/src");
    let { llmProvider } = import("llm/src");
    let { Run, runsGet } = import("runs/src");
    let { sysStringReplace } = import("sys/src");

## The head

The backend's label, the close button, and while the draft has been read and a
key exists, the three stances. A stance is a button whose title is its blurb;
the line under them is the lit one's.

    let psChatBlurb(state: ShowState): String {
      var out = "";
      for (let m of state.modes) { if (m.id == state.mode) { out = m.blurb; } }
      out
    }

    let psChatModes(state: ShowState): List<AnyValue> {
      if (!(state.llmReady && state.work.status != "pending")) { return []; }
      [
        h("div", attr("class", "mg-tabs mt-2.5"),
          state.modes.map { (m: ChatMode): List<AnyValue> =>
            h("button", "${attr("class", if (m.id == state.mode) { "mg-tab on" } else { "mg-tab" })}${attr("phx-click", "set_mode")}${attr("phx-value-mode", m.id)}${attr("title", m.blurb)}", htext(m.label))
          }),
        h("div", attr("class", "text-[0.72rem] text-[var(--mg-dim)] mt-1.5"), htext(psChatBlurb(state))),
      ]
    }

    let psChatHead(state: ShowState): List<AnyValue> {
      h("div", attr("class", "px-4 pt-3 pb-2.5 shrink-0 bg-[var(--mg-paper)]"), [
        h("div", attr("class", "flex items-baseline gap-2"), [
          h("span", attr("class", "mg-label"), htext("Talk about it")),
          h("span", attr("class", "mg-meta opacity-70"), htext(llmProvider(showProviderName(state.provider)).label)),
          h("button", "${attr("class", "mg-btn sm ghost ml-auto")}${attr("phx-click", "toggle_chat")}${attr("title", "Close")}", htext("Close")),
        ]),
        psChatModes(state),
      ])
    }

## The strip of threads

The owner's: a new one, every whole-draft conversation (named after the question
that started it, with how many messages it holds), and a delete for the one the
drawer is in when there is another to land in.

    let psChatDelete(convo: Conversation?, others: Int): List<AnyValue> {
      if (convo != null) {
        if (others > 1) {
          return h("button", "${attr("class", "mg-thread")}${attr("phx-click", "delete_chat")}${attr("phx-value-id", convo.id.toString())}${attr("data-confirm", "Delete this thread and everything said in it?")}${attr("title", "Delete the thread you are in")}", htext("×"));
        }
      }
      []
    }

    let psChatStrip(state: ShowState): List<AnyValue> {
      if (!state.mine) { return []; }
      let convo = state.conversation;
      let current = if (convo != null) { convo.id } else { -1 };
      let remove = psChatDelete(convo, state.threadsList.length);
      h("div", attr("class", "mg-threads shrink-0"), [
        h("button", "${attr("class", "mg-thread")}${attr("phx-click", "new_chat")}${attr("title", "Start a new thread")}", htext("+ New")),
        state.threadsList.map { (t: ChatSummary): List<AnyValue> =>
          h("button", "${attr("class", if (t.id == current) { "mg-thread on" } else { "mg-thread" })}${attr("phx-click", "switch_chat")}${attr("phx-value-id", t.id.toString())}", [
            h("span", attr("class", "name"), htext(t.title)),
            h("span", attr("class", "n"), htext(t.messages.toString())),
          ])
        },
        remove,
      ])
    }

## The transcript

The writer's own words are text; the reader's are markdown. A turn gets an id by
its place in the transcript, which is what the morph keys on (the history is the
last sixty, so a place is stable until the sixty slide).

    let psChatTurn(i: Int, m: ChatTurn): List<AnyValue> {
      if (m.role == "user") {
        h("div", "${attr("class", "mg-turn-you")}${attr("id", "chat-turn-${i.toString()}")}", htext(m.content))
      } else {
        h("div", "${attr("class", "md")}${attr("id", "chat-turn-${i.toString()}")}", hraw(markdownToHtml(m.content)))
      }
    }

What went wrong with the last question, from its run: the Elixir put an
unsaved assistant message at the end of the transcript (`I hit an error:` and
the reason, or `Something crashed:`), which the next reload lost. The run's row
is kept until the next question in this conversation, so this stays until then.

    let psChatFailure(ctx: Ctx, state: ShowState): String? throws Bubble {
      let convo = state.conversation;
      if (convo != null) {
        psChatFailureOf(runsGet(ctx.db, showChatConversationKey(state.work.id, convo.id)))
      } else { null }
    }

    let psChatFailureOf(run: Run?): String? {
      if (run != null) {
        if (run.isRunning()) {
          null
        } else if (run.status == "crashed") {
          "Something crashed: ${showOr(run.detail, "")}"
        } else {
          let error = showJStr(showParse(run.detail), "error");
          if (error != null) { "I hit an error: ${error}" } else { null }
        }
      } else { null }
    }

    let psChatTurns(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      let turns = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < state.history.length) {
        turns.add(psChatTurn(i, state.history[i]));
        i += 1;
      }
      let failure = psChatFailure(ctx, state);
      if (failure != null) {
        turns.add(h("div", "${attr("class", "md")}${attr("id", "chat-turn-error")}", hraw(markdownToHtml(failure))));
      }
      turns.toList()
    }

What stands where the transcript will be: why there is none, or how to begin.

    let psChatBody(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      if (!state.llmReady) {
        h("p", attr("class", "text-sm opacity-60"),
          htext("No ${llmProvider(showProviderName(state.provider)).label} key configured on this deploy."))
      } else if (state.work.status == "pending") {
        h("p", attr("class", "text-sm opacity-60"), htext("Confirm the sections and run the read first."))
      } else if (!state.mine && state.history.length == 0) {
        h("p", attr("class", "mg-empty"), htext("Nothing has been said about this draft yet."))
      } else if (state.history.length == 0) {
        h("p", attr("class", "mg-prose text-[0.95rem] text-[var(--mg-dim)]"), htext(editorMode(state.mode).opener))
      } else {
        psChatTurns(ctx, state)
      }
    }

    let psChatScroll(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      let dots: List<AnyValue> = if (state.loading) { cMutter(state.mutter, "thinking", "py-1") } else { [] };
      h("div", "${attr("id", "chat-scroll")}${attr("phx-hook", "StickToBottom")}${attr("class", "flex-1 overflow-y-auto min-h-0 px-4 py-4 flex flex-col gap-4")}", [
        psChatBody(ctx, state),
        dots,
      ])
    }

## Below the transcript

A reader is told why there is no box. So is a writer who has used every question.

    let psChatReadOnly(): List<AnyValue> {
      h("div", attr("class", "border-t border-[var(--mg-rule)] p-4 shrink-0 bg-[var(--mg-margin)]"), [
        h("div", attr("class", "mg-label"), htext("Read only")),
        h("p", attr("class", "text-[0.8rem] mt-1.5 leading-relaxed text-[var(--mg-dim)]"),
          htext("You have the link to someone else's draft. You can read everything here — the page, the map, what has already been said — but the asking is theirs.")),
      ])
    }

    let psChatSpent(): List<AnyValue> {
      h("div", attr("class", "border-t border-[var(--mg-rule)] p-4 shrink-0 bg-[var(--mg-margin)]"), [
        h("div", attr("class", "mg-label"), htext("Out of questions")),
        h("p", attr("class", "text-[0.8rem] mt-1.5 leading-relaxed text-[var(--mg-dim)]"),
          htext("This deploy gives every account ${chatMessageLimit().toString()} questions. The read, the graph and everything already said stay where they are.")),
      ])
    }

What the chat is holding: the note the writer clicked, and one card for each
section it touches, so two sections plainly look like two.

    let psChatHeld(sec: Section): List<AnyValue> {
      h("div", attr("class", "mg-held"), [
        h("span", attr("class", "n"), htext(sec.ordinal.toString())),
        h("span", attr("class", "min-w-0"), [
          h("span", attr("class", "t"), htext(sec.title)),
          h("span", attr("class", "mg-meta"), htext("${sec.wordCount.toString()} words, in full")),
        ]),
      ])
    }

    let psChatHolding(focus: ReadingFocus?): List<AnyValue> {
      if (focus != null) { psChatHeldCard(focus) } else { [] }
    }

    let psChatHeldCard(focus: ReadingFocus): List<AnyValue> {
      h("div", attr("class", "mg-holding"), [
        h("div", attr("class", "flex items-start gap-2"), [
          h("div", attr("class", "min-w-0 flex-1"), [
            h("div", attr("class", "mg-label"), htext("holding · ${sysStringReplace(focus.kind, "_", " ")}")),
            h("div", attr("class", "text-[0.8rem] mt-1 leading-snug font-medium"), htext(focus.title)),
          ]),
          h("button", "${attr("type", "button")}${attr("class", "mg-btn sm ghost shrink-0")}${attr("phx-click", "clear_focus")}", htext("drop")),
        ]),
        h("div", attr("class", "mt-2 flex gap-2 flex-wrap"),
          focus.sections.map { (sec: Section): List<AnyValue> => psChatHeld(sec) }),
      ])
    }

Passages carried into the next question, each with a way to drop it.

    let psChatChip(i: Int, c: ReadingCite): List<AnyValue> {
      h("div", attr("class", "mg-chip"), [
        h("span", attr("class", "min-w-0"), [
          h("span", attr("class", "cited"), htext("\"${c.text}\"")),
          h("span", attr("class", "mg-meta"), htext("section ${c.ordinal.toString()}")),
        ]),
        h("button", "${attr("type", "button")}${attr("class", "x")}${attr("phx-click", "drop_context")}${attr("phx-value-i", i.toString())}${attr("title", "Drop")}", htext("×")),
      ])
    }

    let psChatCarrying(state: ShowState): List<AnyValue> {
      if (state.cited.length == 0) { return []; }
      let chips = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < state.cited.length) {
        chips.add(psChatChip(i, state.cited[i]));
        i += 1;
      }
      h("div", attr("class", "flex flex-col gap-1.5 mb-2.5"), [
        h("div", attr("class", "mg-label"),
          htext("Carrying ${state.cited.length.toString()} passage${if (state.cited.length > 1) { "s" } else { "" }}")),
        chips.toList(),
      ])
    }

The composer: the box, the hint (with the questions left once they are twenty or
fewer) and the button, which says it is thinking while a question is in flight.
The `ChatComposer` hook sends on Enter and empties the box on `chat:clear`.

    let psChatComposer(state: ShowState): List<AnyValue> {
      let loading = state.loading;
      let q = state.quota;
      let left: List<AnyValue> = if (!q.unlimited && q.left <= 20) {
        [htext(" · "), h("span", attr("class", "text-[var(--mg-accent)]"), htext("${q.left.toString()} left"))]
      } else { [] };
      h("form", "${attr("phx-submit", "send")}${attr("id", "chat-form")}${attr("phx-hook", "ChatComposer")}${attr("class", "flex flex-col gap-2")}", [
        h("textarea", "${attr("name", "message")}${attr("rows", "5")}${attr("autocomplete", "off")}${attr("placeholder", "Ask it something. Paste a paragraph you're stuck on, or a question you can't answer yourself.")}${attr("class", "w-full text-[0.84rem] leading-relaxed resize-none min-h-[7.5rem] max-h-[22rem] px-3 py-2.5 bg-[var(--mg-card)] border border-[var(--mg-rule)] rounded-sm focus:outline-none focus:border-[var(--mg-accent)]")}${if (loading) { " disabled" } else { "" }}", []),
        h("div", attr("class", "flex items-center gap-3"), [
          h("span", attr("class", "mg-hint mt-0"), [htext("Enter to send · Shift+Enter for a new line"), left]),
          h("button", "${attr("type", "submit")}${attr("class", "mg-btn ml-auto")}${if (loading) { " disabled" } else { "" }}", htext(if (loading) { "Thinking…" } else { "Ask" })),
        ]),
      ])
    }

    let psChatFoot(state: ShowState): List<AnyValue> {
      if (!state.mine) { return psChatReadOnly(); }
      if (!(state.llmReady && state.work.status != "pending")) { return []; }
      if (!state.quota.unlimited && state.quota.left == 0) { return psChatSpent(); }
      h("div", attr("class", "border-t border-[var(--mg-rule)] p-3 shrink-0 bg-[var(--mg-paper)]"), [
        psChatHolding(state.focus),
        psChatCarrying(state),
        psChatComposer(state),
      ])
    }

## The panel

    export let renderChatPanel(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      h("div", attr("class", "flex flex-col h-full min-h-0"), [
        psChatHead(state),
        psChatStrip(state),
        psChatScroll(ctx, state),
        psChatFoot(state),
      ])
    }
