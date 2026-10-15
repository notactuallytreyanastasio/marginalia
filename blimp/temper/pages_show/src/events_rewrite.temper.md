# Events: rewrites and edits of the prose

`suggest_rewrite`, `steer_rewrite`, `preview_rewrite`, `clear_preview`,
`close_rewrite`, `apply_rewrite`, `edit_block`, `cancel_edit`, `save_block`,
`dismiss_applied`. The one place the page writes to the draft, and it only
opens from the owner's side.

A rewrite is a slow model call, so it is a job under `work:<id>:rewrite`.
`rewritePending` says the panel is waiting for it; the page reads the answer off
the run when it has ended (`load.temper.md`) and puts the candidates in the
panel, or the reason there are none in a flash.

    let { Ctx } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { Db } = import("db/src");
    let {
      Section, worksGetSection, worksSectionById, worksGetById, worksReplaceBlock, worksRevisions,
      gitEnabled, gitCommitWork,
    } = import("works/src");
    let { chatAllowed } = import("chat/src");
    let {
      ReadingPreview, RewriteCandidate, rewriteBlockText, rewritePlace, rewriteApplySpan,
    } = import("reading/src");
    let { walkthroughRewrite, WalkRewrite, WalkCandidate } = import("cases/src");
    let { runsRunning } = import("runs/src");

    export let showRewriteEvents(): List<String> {
      [
        "suggest_rewrite", "steer_rewrite", "preview_rewrite", "clear_preview", "close_rewrite",
        "apply_rewrite", "edit_block", "cancel_edit", "save_block", "dismiss_applied",
      ]
    }

## The questions left

`Chat.allowed?`: asking costs a question of the account's quota; the deploy's
owner has no limit. When none are left the event does nothing and the drawer
says why.

    let psAllowed(ctx: Ctx, state: ShowState): Boolean throws Bubble {
      let user = state.user;
      if (user != null) { chatAllowed(ctx.db, user) } else { false }
    }

## Asking for rewrites

The walkthrough never calls the model: its panel is filled with the canned
candidates at once. (The Elixir answered after 1.2 seconds, to look like
thinking; there is no timer here.) The fixture carries `spansBlocks` and
`covers`, so the panel draws it through the same path as a real answer.

    let psDemoRewrite(): ShowRewrite {
      let w = walkthroughRewrite();
      new ShowRewrite(
        w.reading, w.original, null,
        w.candidates.map { (c: WalkCandidate): RewriteCandidate => new RewriteCandidate(c.text, c.move, c.cost) },
        w.spansBlocks, w.covers,
      )
    }

    let psAsk(ctx: Ctx, state: ShowState, launcher: ShowLauncher, span: String, steer: String?): ShowOutcome throws Bubble {
      let key = showRewriteKey(state.work.id);
      if (runsRunning(ctx.db, key)) { return showDone(); }
      state.rewrite = null;
      state.preview = null;
      showPickMutter(ctx, state);
      let work = state.work;
      let provider = state.provider;
      let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
        showJobRewrite(own, launcher.llm(provider), work, span, steer, key)
      };
      if (started) {
        state.rewritePending = true;
        state.rewriting = true;
        showMarkLaunched(ctx, work, key);
      }
      showDone()
    }

`suggest_rewrite {text, ref}` from the selection toolbar; `ref` is the
paragraph the selection ended in, and the panel opens under it.

    let psSuggest(ctx: Ctx, state: ShowState, payload: JsonObject, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      let text = showPayloadStr(payload, "text");
      let ref = showPayloadStr(payload, "ref");
      if (showTrim(text) == "") { return showDone(); }
      if (state.demo) {
        state.rewriting = false;
        state.rewrite = psDemoRewrite();
        state.preview = null;
        state.steer = null;
        state.rewriteSpan = text;
        state.rewriteRef = ref;
        return showDone();
      }
      if (!psAllowed(ctx, state)) { return showDone(); }
      if (state.rewriting || state.rewritePending) { return showDone(); }
      state.steer = null;
      state.rewriteSpan = text;
      state.rewriteRef = ref;
      psAsk(ctx, state, launcher, text, null)
    }

`steer_rewrite {steer}` ("Again"): the same span, with the writer's note. A
blank note, no span, or a pass still going does nothing.

    let psSteerSpan(ctx: Ctx, state: ShowState, launcher: ShowLauncher, span: String, steer: String): ShowOutcome throws Bubble {
      if (state.demo) {
        state.rewrite = psDemoRewrite();
        state.preview = null;
        return showDone();
      }
      if (!psAllowed(ctx, state)) { return showDone(); }
      state.steer = steer;
      psAsk(ctx, state, launcher, span, steer)
    }

    let psSteer(ctx: Ctx, state: ShowState, payload: JsonObject, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      let steer = showTrim(showPayloadStr(payload, "steer"));
      let span = state.rewriteSpan;
      if (span != null) {
        if (state.rewriting || state.rewritePending || steer == "") {
          showDone()
        } else {
          psSteerSpan(ctx, state, launcher, span, steer)
        }
      } else {
        showDone()
      }
    }

## Looking at a candidate

Hovering one shows it in the paragraph as a word diff against what is there;
leaving puts the paragraph back.

    let psPreviewOf(state: ShowState, rewrite: ShowRewrite, i: Int): ShowOutcome {
      if (i >= 0 && i < rewrite.candidates.length) {
        state.preview = new ReadingPreview(rewrite.original, rewrite.candidates[i].text);
      }
      showDone()
    }

    let psPreview(state: ShowState, payload: JsonObject): ShowOutcome {
      let rewrite = state.rewrite;
      let i = showPayloadInt(payload, "i");
      if (rewrite != null) {
        if (i != null) { psPreviewOf(state, rewrite, i) } else { showDone() }
      } else { showDone() }
    }

`close_rewrite`. It forgets the pass that was pending too: a late answer does
not reopen a panel that was closed.

    let psClose(state: ShowState): ShowOutcome {
      state.rewrite = null;
      state.preview = null;
      state.rewriting = false;
      state.rewritePending = false;
      state.rewriteRef = null;
      showDone()
    }

## Putting a candidate in

The history of the draft is a git repository when the deploy has a root for
them; a commit follows a write, off the request.

    let psCommit(ctx: Ctx, state: ShowState, launcher: ShowLauncher, origin: String): Void throws Bubble {
      if (gitEnabled()) {
        let fresh = worksGetById(ctx.db, state.work.id);
        if (fresh != null) {
          let user = state.user;
          let author: String? = if (user != null) { "${user.email} <${user.email}>" } else { null };
          let target = fresh;
          let message = "${origin}: ${target.title}";
          let started = launcher.start(ctx, showRunKey(target.id, "git")) { (own: Db): Void throws Bubble =>
            gitCommitWork(target, message, author);
          };
        }
      }
    }

    let psSupersede(n: Int): String {
      if (n == 1) {
        "One note was about the line you changed. It is greyed, not gone."
      } else {
        "${n.toString()} notes were about lines you changed. They are greyed, not gone."
      }
    }

What was stored for the last change, which is what the paragraph now holds:
the text is reflowed to a sentence a line on the way in, so the submitted text
is not always the stored one.

    let psStored(ctx: Ctx, workId: Int, submitted: String): String throws Bubble {
      let revs = worksRevisions(ctx.db, workId);
      if (revs.length == 0) { submitted } else { revs[revs.length - 1].after }
    }

    let psReloadWork(ctx: Ctx, state: ShowState): Void throws Bubble {
      let fresh = worksGetById(ctx.db, state.work.id);
      if (fresh != null) { state.work = fresh; }
    }

`apply_rewrite {i}` ("replace the passage with this"): the owner's, and not in
the walkthrough. The section is looked up fresh by ordinal; a candidate asked
for before another edit is applied to the draft as it is now, or refused as
`moved` if its text has since gone.

    let psApplyChosen(
      ctx: Ctx, state: ShowState, rewrite: ShowRewrite, section: Section, chosen: RewriteCandidate, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      let r = rewriteApplySpan(ctx.db, section, rewrite.original, chosen);
      let why = r.error;
      if (why == null) {
        state.rewrite = null;
        state.preview = null;
        state.rewriteRef = null;
        state.rewriteSpan = null;
        state.steer = null;
        state.rewritePending = false;
        state.applied = new ShowApplied(rewrite.original, psStored(ctx, state.work.id, chosen.text));
        psReloadWork(ctx, state);
        psCommit(ctx, state, launcher, "rewrite");
        showInfo("Replaced. ${if (r.superseded > 0) { psSupersede(r.superseded) } else { "It is in the Changes tab if you want it back." }}")
      } else if (why == "moved") {
        state.rewrite = null;
        state.preview = null;
        showError("That passage changed underneath the rewrite. Nothing was replaced.")
      } else {
        showError("Could not replace it: :${why}")
      }
    }

    let psApplySection(
      ctx: Ctx, state: ShowState, rewrite: ShowRewrite, ordinal: Int, i: Int, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      let section = worksGetSection(ctx.db, state.work.id, ordinal);
      if (section != null) {
        if (i >= 0 && i < rewrite.candidates.length) {
          psApplyChosen(ctx, state, rewrite, section, rewrite.candidates[i], launcher)
        } else { showDone() }
      } else { showDone() }
    }

    let psApply(ctx: Ctx, state: ShowState, payload: JsonObject, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (!state.mine) { return showError(showDeniedPlain()); }
      if (state.demo) { return showDone(); }
      let rewrite = state.rewrite;
      let i = showPayloadInt(payload, "i");
      if (rewrite != null) {
        let ordinal = rewrite.sectionOrdinal;
        if (ordinal != null) {
          if (i != null) { psApplySection(ctx, state, rewrite, ordinal, i, launcher) } else { showDone() }
        } else { showDone() }
      } else { showDone() }
    }

## Editing a paragraph in place

The paragraph's markdown, not a rich-text editor: the page is rendered from this
source and every note is anchored into it, so round-tripping HTML back to
markdown would quietly move every anchor in the section.

The ref `s<ordinal>p<index>` names the section; the block is looked up in it.

    let psSectionOfRef(state: ShowState, ref: String): Section? {
      let head = ref.split("p").getOr(0, "");
      let ordinal = showIntOr(showInt(head.split("s").getOr(1, "")), -1);
      var found: Section? = null;
      for (let s of state.sections) {
        if (s.ordinal == ordinal) { found = s; }
      }
      found
    }

    let psBlockOf(state: ShowState, ref: String): String? {
      let section = psSectionOfRef(state, ref);
      if (section != null) { rewriteBlockText(section, ref) } else { null }
    }

`edit_block {ref, seed?}`: a click in a paragraph, or "or edit it first →"
(which seeds the box with a candidate). A candidate is dropped into the
paragraph where the original sat, so the writer edits their own line; if the
rewrite covers more than this paragraph it cannot be, and that is said, not
guessed at (the LiveView once replaced a whole paragraph with a rewrite of text
that was not in it).

    let psOpenEditor(state: ShowState, ref: String, text: String): ShowOutcome {
      state.editing = ref;
      state.editText = text;
      state.rewrite = null;
      state.preview = null;
      showDone()
    }

    let psEditSeeded(state: ShowState, ref: String, block: String, seed: String): ShowOutcome {
      let rewrite = state.rewrite;
      if (rewrite != null) {
        let placed = rewritePlace(block, rewrite.original, seed);
        if (placed != null) {
          psOpenEditor(state, ref, placed)
        } else {
          showError("That rewrite covers more than this paragraph, so it cannot be dropped into it. Copy the version you want, or select inside one paragraph and rewrite again.")
        }
      } else {
        psOpenEditor(state, ref, seed)
      }
    }

    let psEdit(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      if (!state.mine) { return showDone(); }
      let ref = showPayloadStr(payload, "ref");
      if (ref == "") { return showDone(); }
      let seed = showPayloadStr(payload, "seed");
      let block = showOr(psBlockOf(state, ref), "");
      if (seed != "") { psEditSeeded(state, ref, block, seed) } else { psOpenEditor(state, ref, block) }
    }

`save_block {text}`: the owner's. The walkthrough discards it. The section is
read again for the write, so an edit made in another tab is not overwritten by
a stale copy.

    let psSectionOr(s: Section?, d: Section): Section {
      if (s != null) { s } else { d }
    }

    let psStopEditing(state: ShowState): Void {
      state.editing = null;
      state.editText = null;
    }

    let psSaveBlock(
      ctx: Ctx, state: ShowState, held: Section, block: String, text: String, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      let section = psSectionOr(worksSectionById(ctx.db, held.id), held);
      let r = worksReplaceBlock(ctx.db, section, block, text, "edit", null);
      let why = r.error;
      if (why == null) {
        psStopEditing(state);
        state.applied = new ShowApplied(block, psStored(ctx, state.work.id, text));
        psReloadWork(ctx, state);
        psCommit(ctx, state, launcher, "edit");
        if (r.superseded > 0) { showInfo(psSupersede(r.superseded)) } else { showDone() }
      } else if (why == "empty") {
        showError("An empty paragraph is a deletion. Select it and cut it instead.")
      } else if (why == "moved") {
        psStopEditing(state);
        showError("That paragraph changed underneath the edit. Nothing was saved.")
      } else {
        psStopEditing(state);
        showDone()
      }
    }

    let psSaveRef(ctx: Ctx, state: ShowState, ref: String, text: String, launcher: ShowLauncher): ShowOutcome throws Bubble {
      let held = psSectionOfRef(state, ref);
      let block = psBlockOf(state, ref);
      if (held != null) {
        if (block != null) {
          psSaveBlock(ctx, state, held, block, text, launcher)
        } else {
          psStopEditing(state);
          showDone()
        }
      } else {
        psStopEditing(state);
        showDone()
      }
    }

    let psSave(ctx: Ctx, state: ShowState, payload: JsonObject, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (state.demo) {
        psStopEditing(state);
        return showInfo("Nothing was saved — the walkthrough does not touch your draft.");
      }
      let ref = state.editing;
      if (ref != null) {
        if (state.mine) {
          psSaveRef(ctx, state, ref, showPayloadStr(payload, "text"), launcher)
        } else {
          psStopEditing(state);
          showDone()
        }
      } else {
        psStopEditing(state);
        showDone()
      }
    }

## Dispatch

    export let showRewriteEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      if (event == "suggest_rewrite") {
        psSuggest(ctx, state, payload, launcher)
      } else if (event == "steer_rewrite") {
        psSteer(ctx, state, payload, launcher)
      } else if (event == "preview_rewrite") {
        psPreview(state, payload)
      } else if (event == "clear_preview") {
        state.preview = null;
        showDone()
      } else if (event == "close_rewrite") {
        psClose(state)
      } else if (event == "apply_rewrite") {
        psApply(ctx, state, payload, launcher)
      } else if (event == "edit_block") {
        psEdit(ctx, state, payload)
      } else if (event == "cancel_edit") {
        psStopEditing(state);
        showDone()
      } else if (event == "save_block") {
        psSave(ctx, state, payload, launcher)
      } else {
        state.applied = null;
        showDone()
      }
    }
