# The chat drawer (not built yet)

OWNED BY THE CHAT AGENT: replace this file. It is a stub that keeps the frame
building; nothing else in the library should need to change.

What the frame needs from this file:

* `renderChatPanel(ctx, state)`: the inside of `div.mg-drawer`, drawn only
  while `state.chatOpen` (spec section 3.18, `chat_panel/1`).
* `showChatEventNames()`: the events this file answers, which the dispatcher
  (`events.temper.md`) routes here. The 42-event list assigns these eleven to
  the drawer: `discuss`, `discuss_node`, `clear_focus`, `add_context`,
  `drop_context`, `new_chat`, `switch_chat`, `delete_chat`, `set_mode`, `send`,
  `thread_send`. (`set_mode` and `send` are already refused for a reader who
  is not the draft's owner before they get here: `handleShowWith`.)
* `showChatEvent(ctx, state, event, payload, launcher)`: answers one of them.
  It changes fields of `state` (`focus`, `cited`, `conversation`, `history`,
  `mode`, `loading`, `threadLoading`, `threadHistory`, `mutter`/`mutterSeen`;
  `showPickMutter(ctx, state)` fills the wait) and answers a `ShowOutcome`
  (`showDone()`, `showInfo(text)`, `showError(text)`, `showGoing(path)`; the
  `chat:clear` event for the composer is `new ShowOutcome(null, null,
  [new Pair("chat:clear", "{}")])`). `showSaveUi` writes the ui fields after it
  returns. A model call is a job: `launcher.start(ctx, key, body)` under a key
  `showRunKey(state.work.id, "chat")`-style, and the answer left in the run's
  `detail` (see `launch.temper.md` and `load.temper.md` for the pattern the
  rewrite uses); `launcher.llm(state.provider)` is the client. A run under
  `work:<id>:` that is going makes the page poll by itself.

The four ui fields the drawer's data lives in are saved by `ui.temper.md`
(`focus`, `cited`, `conversation`, `loading`, `threadLoading`, `mutter`,
`mutterSeen`); the rest (`history`, `threadsList`, `quota`, `blockThreads`,
`threadHistory`) are read from the database by `psLoadChat` in `load.temper.md`.

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");
    let { JsonObject } = import("std/json");

    export let renderChatPanel(ctx: Ctx, state: ShowState): List<AnyValue> {
      h("div", attr("class", "mg-view-todo"), [htext("the chat is not built yet")])
    }

    export let showChatEventNames(): List<String> {
      [
        "discuss", "discuss_node", "clear_focus", "add_context", "drop_context",
        "new_chat", "switch_chat", "delete_chat", "set_mode", "send", "thread_send",
      ]
    }

    export let showChatEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      console.log("TODO pages_show chat: event ${event} is the chat agent's (chat.temper.md)");
      bubble()
    }
