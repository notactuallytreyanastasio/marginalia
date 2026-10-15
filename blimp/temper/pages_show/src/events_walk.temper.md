# Events: the walkthrough

`start_walk`, `walk_reset`, `end_walk`. "Show me" on the tour card runs the
read view's controls for the reader, with the writes switched off: a thread it
opens is never saved, the rewrite is a fixed example, saving a paragraph
discards, and no model is called. The steps are `Walkthrough.steps/2`, and the
`Walk` hook does the pressing; this keeps the flag that makes the page behave.

    let { Ctx } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { walkthroughViews } = import("cases/src");
    let { User, accountsSeenTour, accountsMarkTourSeen } = import("accounts/src");

    export let showWalkEvents(): List<String> {
      ["start_walk", "walk_reset", "end_walk"]
    }

What the tour put on the page, taken off again.

    let psClear(state: ShowState): Void {
      state.openThread = null;
      state.threadHistory = [];
      state.threadLoading = false;
      state.rewrite = null;
      state.rewriting = false;
      state.rewritePending = false;
      state.rewriteRef = null;
      state.preview = null;
      state.editing = null;
      state.editText = null;
    }

`mark_walk_seen`: the walkthrough is offered once per account, kept in the same
list as the tab tours under `walk:<view>`.

    let psMarkFor(ctx: Ctx, state: ShowState, user: User): Void throws Bubble {
      let tag = "walk:${state.view}";
      for (let v of walkthroughViews()) {
        if (v == state.view && !accountsSeenTour(user, tag)) {
          accountsMarkTourSeen(ctx.db, user, tag);
        }
      }
    }

    let psMarkSeen(ctx: Ctx, state: ShowState): Void throws Bubble {
      let user = state.user;
      if (user != null) { psMarkFor(ctx, state, user); }
    }

    export let showWalkEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      if (event == "start_walk") {
        state.demo = true;
        state.tour = null;
        psMarkSeen(ctx, state);
        showDone()
      } else if (event == "walk_reset") {
        psClear(state);
        state.only = null;
        showDone()
      } else {
        state.demo = false;
        psClear(state);
        showDone()
      }
    }
