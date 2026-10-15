# Events: the dispatcher and the state a page moves between

`handle_event/3`, 42 of them. An event is `POST /ev/<name>` with a JSON
payload and the page's own path; the page's state is loaded as it would be for
a plain request, the handler changes it and says what to flash or where to go,
and the dispatcher saves the ui part and renders the page again from the
database.

The events are grouped by the module that handles them. Each module has a
list of the names it answers (`show…Events()`) and one function that takes the
event (`show…Event(ctx, state, event, payload, launcher)`), and `handleShow`
asks each list in turn:

| module | file | events |
|---|---|---|
| navigation and view state | `events.temper.md` | `set_view` `toggle_chat` `set_only` `show_help` `dismiss_tour` `toggle_changes` `toggle_linking` |
| the read, the graph, the backend, linking | `events_read.temper.md` | `start_read` `build_graph` `set_provider` `link_to` |
| threads on a paragraph | `events_threads.temper.md` | `open_thread` `close_thread` `resolve_thread` |
| rewrites and edits of the prose | `events_rewrite.temper.md` | `suggest_rewrite` `steer_rewrite` `preview_rewrite` `clear_preview` `close_rewrite` `apply_rewrite` `edit_block` `cancel_edit` `save_block` `dismiss_applied` |
| summaries and relating drafts | `events_summary.temper.md` | `summarise` `summarise_document` `compare_summary` `summaries_to_draft` |
| the walkthrough | `events_walk.temper.md` | `start_walk` `walk_reset` `end_walk` |
| the chat drawer | `chat.temper.md` (the chat agent's) | `discuss` `discuss_node` `clear_focus` `add_context` `drop_context` `new_chat` `switch_chat` `delete_chat` `set_mode` `send` `thread_send` |
| the other views | `view_events.temper.md` (the views agent's) | none yet |

An event nobody answers is a crash with its name in the log, which is better
than an answer that looks like success.

    let { Ctx, uiGet, uiPut } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { tourFor } = import("cases/src");
    let { mutteringsSome, mutteringsRemembered, Mutter } = import("runs/src");

## Who may

The five events the LiveView guarded with one clause, for a reader who is not
the draft's owner: they would spend the owner's credit or change the draft.

    export let showDeniedReader(): String {
      "This draft is someone else's. You can read it, not change it."
    }

    export let showDeniedPlain(): String { "This draft is someone else's." }

    let psGuardedEvents(): List<String> {
      ["build_graph", "start_read", "send", "set_mode", "set_provider"]
    }

    export let showIn(names: List<String>, name: String): Boolean {
      for (let n of names) { if (n == name) { return true; } }
      false
    }

Every event that writes to the draft, the model's credit or the account
checks `state.mine`. The LiveView checked some of them and left the rest to
the controls being hidden (`open_thread`, `resolve_thread`, `new_chat`,
`switch_chat`, `delete_chat`, `discuss_node`, `add_context`); here a reader who
sends one by hand gets the denial. The exceptions are the ones that only move
the page (`set_view`, `set_only`, the tour, the walkthrough, the toggles) and
`open_thread` on a thread that already exists, which a reader may open to read.

## The wait

`Mutterings.some(8)`: a few in-character lines to show in front of the dots
while a model works. The page remembers the last forty it showed, in the ui
state, so a wait does not repeat the last one. Called when a model call starts.

    export let showPickMutter(ctx: Ctx, state: ShowState): Void throws Bubble {
      let picked = mutteringsSome(ctx.db, 8, state.mutterSeen);
      state.mutter = picked.map { (m: Mutter): String => m.text };
      state.mutterSeen = mutteringsRemembered(picked, state.mutterSeen);
    }

## Navigation

The URL is authoritative, as it was with `push_patch`: the view and the drawer
are in the address, so changing either is a navigation to the new address (a
`replace`, in the Elixir; here a redirect the client follows). Everything the
page held for the writer is in the ui state and is there on the other side.

    export let showNavEvents(): List<String> {
      ["set_view", "toggle_chat", "set_only", "show_help", "dismiss_tour", "toggle_changes", "toggle_linking"]
    }

    export let showNavEvent(ctx: Ctx, state: ShowState, event: String, payload: JsonObject): ShowOutcome throws Bubble {
      let slug = state.work.slug;
      if (event == "set_view") {
        showGoing(showPath(slug, showViewOf(showPayloadStr(payload, "view")), state.chatOpen))
      } else if (event == "toggle_chat") {
        showGoing(showPath(slug, state.view, !state.chatOpen))
      } else if (event == "set_only") {
        let only = showPayloadStr(payload, "only");
        state.only = if (only == "" || only == "all") { null } else { only };
        showDone()
      } else if (event == "show_help") {
        state.tour = tourFor(state.view);
        showDone()
      } else if (event == "dismiss_tour") {
        state.tour = null;
        showDone()
      } else if (event == "toggle_changes") {
        state.changesOn = !state.changesOn;
        showDone()
      } else {
        state.linking = !state.linking;
        showDone()
      }
    }

## The dispatcher

`events` is the list a module answers, `ours` whether the event is one of them.
The launcher is what starts background work; the tests give an inline one.

    export let handleShowWith(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      if (!state.mine && showIn(psGuardedEvents(), event)) {
        return showError(showDeniedReader());
      }
      if (showIn(showNavEvents(), event)) {
        showNavEvent(ctx, state, event, payload)
      } else if (showIn(showReadEvents(), event)) {
        showReadEvent(ctx, state, event, payload, launcher)
      } else if (showIn(showThreadEvents(), event)) {
        showThreadEvent(ctx, state, event, payload, launcher)
      } else if (showIn(showRewriteEvents(), event)) {
        showRewriteEvent(ctx, state, event, payload, launcher)
      } else if (showIn(showSummaryEvents(), event)) {
        showSummaryEvent(ctx, state, event, payload, launcher)
      } else if (showIn(showWalkEvents(), event)) {
        showWalkEvent(ctx, state, event, payload, launcher)
      } else if (showIn(showChatEventNames(), event)) {
        showChatEvent(ctx, state, event, payload, launcher)
      } else if (showIn(showViewEventNames(), event)) {
        showViewEvent(ctx, state, event, payload, launcher)
      } else {
        console.log("pages_show: /works/:slug has no event ${event}");
        bubble()
      }
    }

    export let handleShow(ctx: Ctx, state: ShowState, event: String, payload: JsonObject): ShowOutcome throws Bubble {
      handleShowWith(ctx, state, event, payload, new ShowForkLauncher())
    }
