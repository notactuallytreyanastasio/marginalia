# Events: summaries and relating drafts

`summarise`, `summarise_document`, `compare_summary`, `summaries_to_draft`.
Summarising calls the model, so the first three are jobs (`work:<id>:summarise:<n>`,
`…:document`, `…:compare`) and the owner's; the page shows each button as going
while its run is, and says how it ended once.

    let { Ctx } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { Db } = import("db/src");
    let { Section, worksGetSection } = import("works/src");
    let { documentToDraft } = import("reading/src");
    let { runsRunning } = import("runs/src");

    export let showSummaryEvents(): List<String> {
      ["summarise", "summarise_document", "compare_summary", "summaries_to_draft"]
    }

Inside the walkthrough nothing calls the model.

    let psNotInTour(): String { "The walkthrough does not call the model." }

`summarise {ordinal}`: one section's summary, kept beside it (`Summary.run`).

    let psSummariseSection(
      ctx: Ctx, state: ShowState, section: Section, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      let key = showSummariseKey(state.work.id, section.ordinal);
      if (runsRunning(ctx.db, key)) { return showDone(); }
      let provider = state.provider;
      let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
        showJobSummarise(own, launcher.llm(provider), section, key)
      };
      if (started) { showMarkLaunched(ctx, state.work, key); }
      showDone()
    }

    let psSummarise(ctx: Ctx, state: ShowState, payload: JsonObject, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (state.demo) { return showInfo(psNotInTour()); }
      if (!psAllowed(ctx, state)) { return showDone(); }
      let n = showPayloadInt(payload, "ordinal");
      if (n != null) {
        let section = worksGetSection(ctx.db, state.work.id, n);
        if (section != null) { psSummariseSection(ctx, state, section, launcher) } else { showDone() }
      } else {
        showDone()
      }
    }

`summarise_document`: every section's summary that is missing or stale, then
the composition of the whole and the rules it works under.

    let psDocument(ctx: Ctx, state: ShowState, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (state.demo) { return showInfo(psNotInTour()); }
      if (!psAllowed(ctx, state)) { return showDone(); }
      let key = showDocumentKey(state.work.id);
      if (runsRunning(ctx.db, key)) { return showDone(); }
      let work = state.work;
      let provider = state.provider;
      let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
        showJobDocument(own, launcher.llm(provider), work, key)
      };
      if (started) {
        showMarkLaunched(ctx, work, key);
        state.docRunning = true;
      }
      showDone()
    }

`compare_summary`: draft the summaries as a draft of their own, read it, and
relate the two so they can be held against each other. One comparison at a time.

    let psCompare(ctx: Ctx, state: ShowState, launcher: ShowLauncher): ShowOutcome throws Bubble {
      let key = showCompareKey(state.work.id);
      if (runsRunning(ctx.db, key)) { return showError("A compare pass is already running on this draft."); }
      let work = state.work;
      let scope = ctx.scope;
      let provider = state.provider;
      let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
        showJobCompare(own, launcher.llm(provider), scope, work, key)
      };
      if (started) {
        showMarkLaunched(ctx, work, key);
        state.comparing = "Drafting the summary";
        showDone()
      } else {
        showError("A compare pass is already running on this draft.")
      }
    }

`summaries_to_draft` ("Open as a draft"): a draft of the summaries, to edit and
read like any other, and the page goes to it.

    let psToDraft(ctx: Ctx, state: ShowState): ShowOutcome throws Bubble {
      let r = documentToDraft(ctx.db, ctx.scope, state.work);
      let draft = r.ok;
      if (draft != null) {
        showGoingFlashed("/works/${draft.slug}", "info", "Opened the summaries as a draft of their own.")
      } else if (r.error == "nothing_summarised") {
        showError("Summarise at least one section first.")
      } else {
        showError("Could not make a draft: ${showOr(r.error, "unknown")}")
      }
    }

    export let showSummaryEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      if (event == "summarise") {
        psSummarise(ctx, state, payload, launcher)
      } else if (event == "summarise_document") {
        psDocument(ctx, state, launcher)
      } else if (event == "compare_summary") {
        psCompare(ctx, state, launcher)
      } else {
        psToDraft(ctx, state)
      }
    }
