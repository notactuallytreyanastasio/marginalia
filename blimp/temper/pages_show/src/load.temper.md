# Loading the page

`mount/3` and `handle_params/3`, as one function of the request: find the
draft, work out who is looking, read the database, ask the runs table what is
going on in the background, restore the ui state, and load what the chosen
view needs. The same function answers a plain page load, a poll and an event,
which is the whole difference from a LiveView: nothing is remembered between
two calls except what the database and the session remember.

    let { Ctx, webPutFlash, uiGet, uiPut } = import("webcore/src");
    let { Db } = import("db/src");
    let {
      Work, Section, GraphNode, Revision, WorkCounts,
      worksGetBySlug, worksGetById, worksIsOwner, worksListSections, worksListNodes, worksCounts,
      worksRevisions, worksRevisionCount, worksEventStats, worksListEvents, worksBaseline,
      worksCondensationOf, worksSetStatus,
    } = import("works/src");
    let { User, accountsIsOwner, accountsIsAdmin, accountsProviderFor, accountsSeenTour, accountsMarkTourSeen } = import("accounts/src");
    let {
      Conversation, chatGetOrCreateConversation, chatGetConversation, chatHistory, chatConversationSummaries,
      chatThreadsByBlock, chatRemaining, editorModes,
    } = import("chat/src");
    let {
      readingPage, ReadingOptions, ReadingSection, documentGet, rewritePasses, RewritePass,
    } = import("reading/src");
    let { linksForWork, linksGetFor, linksLinkable } = import("links/src");
    let { graphJson, graphStats, analysisPasses, decisionGraphPasses, AnalysisPass } = import("analysis/src");
    let { tourFor, TourCard, walkthroughSteps } = import("cases/src");
    let { rows, Row } = import("core/src");
    let { Run, runsReclaim, runsGet } = import("runs/src");
    let { llmProvider } = import("llm/src");
    let { JsonSyntaxTree, JsonTextProducer } = import("std/json");

## Which view

`to_view/1`: anything but the seven is the page itself.

    export let showViewOf(raw: String): String {
      if (raw == "spine" || raw == "threads" || raw == "graph" || raw == "changes" || raw == "trace" || raw == "prompts") {
        raw
      } else {
        "read"
      }
    }

## Who is looking, and what the deploy can do

The slug is the permission to read; `mine` is the permission to change. A
guest is a user and can own a draft. A visitor with no user at all (the
tests, never the router) owns nothing.

    let psFinishWho(state: ShowState, launcher: ShowLauncher): Void {
      let user = state.user;
      if (user != null) {
        state.mine = worksIsOwner(state.work, user);
        state.owner = accountsIsOwner(user);
        state.admin = accountsIsAdmin(user);
        state.provider = accountsProviderFor(user);
      }
      state.llmReady = launcher.ready(state.provider);
      state.backends = showBackends();
    }

## The stages of a read

`infer_stages/1`: read off what is in the database, because a page opened
mid-read hears nothing about the stages that already finished.

    let psAllRead(sections: List<Section>): Boolean {
      if (sections.length == 0) { return false; }
      for (let s of sections) {
        if (s.status != "read" && s.status != "failed") { return false; }
      }
      true
    }

    export let showStagesOf(work: Work, sections: List<Section>, counts: WorkCounts): ShowStages {
      if (work.status == "read") {
        new ShowStages("done", "done", "done")
      } else if (work.status != "reading") {
        new ShowStages("waiting", "waiting", "waiting")
      } else if (counts.spine > 0) {
        new ShowStages("done", "done", "start")
      } else if (psAllRead(sections)) {
        new ShowStages("done", "start", "waiting")
      } else {
        new ShowStages("start", "waiting", "waiting")
      }
    }

## What finished in the background

A run is last seen by the page as `<started at>|<status>`, kept in the ui
state. A run that is finished now and was not when the page last looked has
ended since, and the page says so once (`handle_info` and `handle_async` did,
on the message). A page that has never seen the run says nothing: opening an
old draft does not announce a summary finished last week.

    let psSeenKey(slug: String): String { "show:${slug}:runs" }

    let psMark(run: Run): String { "${showOr(run.startedAt, "")}|${run.status}" }

    let psSeenOf(ctx: Ctx, slug: String): JsonSyntaxTree? {
      showParse(uiGet(ctx, psSeenKey(slug)))
    }

Called by an event right after it started a run: the page now has seen it
running, so the flash is owed when it ends.

    export let showMarkLaunched(ctx: Ctx, work: Work, key: String): Void throws Bubble {
      let run = runsGet(ctx.db, key);
      if (run != null) {
        let seen = psSeenOf(ctx, work.slug);
        let p = showProducer();
        p.startObject();
        if (seen is JsonObject) {
          let ks = seen.properties.keys();
          for (var i = 0; i < ks.length; ++i) {
            let k = ks.getOr(i, "");
            if (k != key) { showKeyStr(p, k, showJStr(seen, k)); }
          }
        }
        showKeyStr(p, key, "${showOr(run.startedAt, "")}|running");
        p.endObject();
        uiPut(ctx, psSeenKey(work.slug), p.toJsonString());
      }
    }

The text a finished run is flashed as, or null when it needs no flash. `what`
is the key after `work:<id>:`.

    let psFlashFor(what: String, run: Run): Pair<String, String>? {
      let answer = showParse(run.detail);
      let error = showJStr(answer, "error");
      let reason = showReason(error, showJStr(answer, "detail"));
      if (what == "document") {
        if (run.status == "crashed") {
          new Pair("error", "The document pass crashed: ${showOr(run.detail, "")}")
        } else if (error != null) {
          new Pair("error", "Could not summarise the document: ${reason}")
        } else {
          new Pair("info", "The whole document has been read.")
        }
      } else if (showStartsWith(what, "summarise:")) {
        let n = what.split(":").getOr(1, "");
        if (run.status == "crashed") {
          new Pair("error", "The summary crashed: ${showOr(run.detail, "")}")
        } else if (error != null) {
          new Pair("error", "Could not summarise section ${n}: ${reason}")
        } else { null }
      } else if (what == "compare") {
        if (run.status == "crashed") {
          new Pair("error", "The comparison crashed. Anything it finished is saved.")
        } else if (error != null) {
          new Pair("error", "Could not compare them: ${reason}")
        } else {
          new Pair("info", "Drafted, read and related. They are side by side now.")
        }
      } else if (what == "read") {
        if (run.status == "crashed") { new Pair("error", "The read crashed.") } else { null }
      } else if (showStartsWith(what, "thread:")) {
        showChatThreadFlash(run)
      } else { null }
    }

    export let showRewriteError(error: String, detail: String?, words: Int, max: Int): String {
      if (error == "not_in_draft") {
        "That selection is not in the draft, character for character."
      } else if (error == "span_too_long") {
        "That is ${words.toString()} words. Rewrites go up to ${max.toString()} — past that, split it and take the part you actually want reworked."
      } else if (error == "no_candidates") {
        "Nothing came back that was different from what you wrote."
      } else {
        "That did not go through: ${showReason(":${error}", detail)}"
      }
    }

The rewrite's answer, once, when its run has ended: the candidates into the
panel, or the reason there are none into a flash. `close_rewrite` forgets the
pending answer (the Elixir let a late one reopen the panel, with the panel
hidden and the paragraphs dimmed).

    let psRewriteEnded(ctx: Ctx, state: ShowState, found: Run): Void throws Bubble {
      state.rewritePending = false;
      if (found.status == "crashed") {
        webPutFlash(ctx, "error", "That did not go through: ${showOr(found.detail, "crashed")}");
      } else {
        let answer = showParse(found.detail);
        let error = showJStr(answer, "error");
        if (error != null) {
          webPutFlash(ctx, "error", showRewriteError(
            error, showJStr(answer, "detail"),
            showIntOr(showJInt(answer, "words"), 0), showIntOr(showJInt(answer, "max"), 0),
          ));
        } else {
          state.rewrite = showRewriteFrom(found.detail);
          state.preview = null;
        }
      }
    }

    let psSettleRewrite(ctx: Ctx, state: ShowState, runs: List<Run>): Void throws Bubble {
      if (!state.rewritePending) { return; }
      let key = showRewriteKey(state.work.id);
      var run: Run? = null;
      for (let r of runs) { if (r.key == key) { run = r; } }
      let found = run;
      if (found != null) {
        if (found.isRunning()) { state.rewriting = true; } else { psRewriteEnded(ctx, state, found); }
      } else {
        state.rewritePending = false;
      }
    }

The key after `work:<id>:`.

    let psAfterPrefix(key: String, prefix: String): String {
      let parts = key.split(prefix);
      if (parts.length < 2) { key } else { showJoin(parts.slice(1, parts.length), prefix) }
    }

Every run of the work, looked at once: the flags that were assigns, the
flashes that were messages, a read that died.

    let psSettle(ctx: Ctx, state: ShowState, runs: List<Run>): Void throws Bubble {
      let work = state.work;
      let prefix = showKeyPrefix(work.id);
      let summarising = new ListBuilder<Int>();
      let seen = psSeenOf(ctx, work.slug);
      let p = showProducer();
      p.startObject();
      for (let run of runs) {
        let what = psAfterPrefix(run.key, prefix);
        let mark = psMark(run);
        showKeyStr(p, run.key, mark);
        if (run.isRunning()) {
          if (what == "document") { state.docRunning = true; }
          if (what == "graph") { state.graphBuilding = true; }
          if (what == "compare") {
            state.comparing = showOr(run.progress, "Drafting the summary");
          }
          if (showStartsWith(what, "summarise:")) {
            let n = showInt(what.split(":").getOr(1, ""));
            if (n != null) { summarising.add(n); }
          }
        } else {
          let before = showJStr(seen, run.key);
          if (before != null && before != mark) {
            let flash = psFlashFor(what, run);
            if (flash != null) { webPutFlash(ctx, flash.key, flash.value); }
          }
          if (what == "read" && run.status == "crashed" && work.status == "reading") {
            state.work = worksSetStatus(ctx.db, work, "failed", showOr(run.detail, "the read stopped"));
          }
        }
      }
      p.endObject();
      state.summarising = summarising.toList();
      let text = p.toJsonString();
      let was = uiGet(ctx, psSeenKey(work.slug));
      if (was == null || was != text) { uiPut(ctx, psSeenKey(work.slug), text); }
      psSettleRewrite(ctx, state, runs);
    }

## Loading

The runs, with a job whose process died given up on first (`runsReclaim`), so
a page does not poll for ever after a restart.

    let psRuns(ctx: Ctx, workId: Int): List<Run> throws Bubble {
      let first = showRunsOf(ctx, workId);
      var dead = false;
      for (let r of first) {
        if (r.isRunning()) {
          if (runsReclaim(ctx.db, r.key)) { dead = true; }
        }
      }
      if (dead) { showRunsOf(ctx, workId) } else { first }
    }

    let psNodes(db: Db, workId: Int, kind: String): List<GraphNode> throws Bubble {
      worksListNodes(db, workId, kind, null, null)
    }

Newest first.

    let psNewestFirst(xs: List<Revision>): List<Revision> {
      let out = new ListBuilder<Revision>();
      var i = xs.length - 1;
      while (i >= 0) {
        out.add(xs[i]);
        i -= 1;
      }
      out.toList()
    }

`Diff.stat/1`.

    export let showDiffStatOf(rs: List<Row>): ShowDiffStat {
      var same = 0;
      var changed = 0;
      var added = 0;
      var removed = 0;
      for (let r of rs) {
        if (r.kind == "same") { same += 1; }
        if (r.kind == "change") { changed += 1; }
        if (r.kind == "ins") { added += 1; }
        if (r.kind == "del") { removed += 1; }
      }
      new ShowDiffStat(same, changed, added, removed)
    }

    export let showAnyChange(rs: List<Row>): Boolean {
      for (let r of rs) {
        if (r.kind != "same") { return true; }
      }
      false
    }

The prompts the Prompts tab prints: the read's, the decision graph's and the
rewrite's, in that order. The rewrite has no model of its own in the table, so
it carries the default's.

    let psRewritePass(p: RewritePass, model: String): AnalysisPass {
      new AnalysisPass(p.id, p.name, model, p.runs, p.produces, p.prompt)
    }

    export let showPassesOf(): List<AnalysisPass> {
      let out = new ListBuilder<AnalysisPass>();
      out.addAll(analysisPasses());
      out.addAll(decisionGraphPasses());
      let model = llmProvider(showProviderName(null)).model;
      for (let p of rewritePasses()) { out.add(psRewritePass(p, model)); }
      out.toList()
    }

What the chosen view needs and the others do not (`load_for_view/1`).

    let psLoadForView(ctx: Ctx, state: ShowState): Void throws Bubble {
      let work = state.work;
      if (state.view == "read") {
        state.page = readingPage(ctx.db, work, new ReadingOptions(state.only, null, null));
      } else if (state.view == "graph") {
        state.graphJson = graphJson(ctx.db, work);
        state.graphStats = graphStats(ctx.db, work);
      } else if (state.view == "trace") {
        state.events = worksListEvents(ctx.db, work.id);
        state.eventStats = worksEventStats(ctx.db, work.id);
      } else if (state.view == "changes") {
        // An untouched draft is the common case, and `rows` over an
        // unchanged 17,000-word draft took 3.7 s to find nothing: the two
        // texts are compared whole first, and only a changed draft is diffed.
        let baseline = worksBaseline(ctx.db, work);
        let diff: List<Row> = if (baseline == work.body) { [] } else { rows(baseline, work.body) };
        state.diffRows = diff;
        state.diffStat = showDiffStatOf(diff);
      } else if (state.view == "prompts") {
        state.passes = showPassesOf();
      }
    }

## The tour

`maybe_tour/1`: each tab explains itself once. A fresh page load shows the
card for the tab it opens on, if the account has not seen it, and marks it
seen. A poll or an event keeps the card as the ui state has it (`show_help`
and `dismiss_tour` change that).

    let psTourFor(ctx: Ctx, state: ShowState, card: TourCard): Void throws Bubble {
      let user = state.user;
      if (user != null) {
        if (accountsSeenTour(user, state.view)) {
          state.tour = null;
        } else {
          state.tour = card;
          accountsMarkTourSeen(ctx.db, user, state.view);
        }
      } else {
        state.tour = card;
      }
    }

    let psMaybeTour(ctx: Ctx, state: ShowState): Void throws Bubble {
      if (!state.fresh) { return; }
      if (state.work.status == "pending") {
        state.tour = null;
        return;
      }
      let card = tourFor(state.view);
      if (card != null) { psTourFor(ctx, state, card); } else { state.tour = null; }
    }

## The chat's data

The whole-draft conversation in use (made if the draft has none: the Elixir
wrote this row on mount, for a read-only visitor too), its last messages, the
strip of threads and the questions left. The drawer's own events change these.

    let psLoadChat(ctx: Ctx, state: ShowState): Void throws Bubble {
      let work = state.work;
      var convo: Conversation? = null;
      let saved = state.savedConversation;
      if (saved != null) { convo = chatGetConversation(ctx.db, work.id, saved); }
      if (convo == null) { convo = chatGetOrCreateConversation(ctx.db, work.id).conversation; }
      let found = convo;
      state.conversation = found;
      state.modes = editorModes();
      if (found != null) {
        state.mode = found.mode;
        state.history = chatHistory(ctx.db, found.id);
      }
      state.threadsList = chatConversationSummaries(ctx.db, work.id);
      state.blockThreads = chatThreadsByBlock(ctx.db, work.id);
      let thread = state.openThread;
      if (thread != null) {
        if (thread.id != 0) { state.threadHistory = chatHistory(ctx.db, thread.id); }
      }
      let user = state.user;
      if (user != null) { state.quota = chatRemaining(ctx.db, user); }
      showChatSettle(ctx, state);
    }

The clock counts from the start of this read: the read run's own start, or, for
a draft that is reading with no run to show for it, from when it was made (what
the Elixir did for every page loaded mid-read).

    let psStartedAt(work: Work, runs: List<Run>): Int? {
      var found: Int? = null;
      for (let r of runs) {
        if (r.key == showReadKey(work.id)) {
          let at = r.startedAt;
          if (at != null) { found = showEpoch(at); }
        }
      }
      let seen = found;
      if (seen != null) { seen } else { showEpoch(work.insertedAt) }
    }

## The whole load

`fresh` is a plain page load: the one time the tour is decided. The launcher
is only asked whether a key exists.

    export let loadShowFor(ctx: Ctx, work: Work, launcher: ShowLauncher): ShowState throws Bubble {
      let wantsView = showViewOf(ctx.req.query.getOr("view", "read"));
      let who = ctx.scope.user;
      let isOwner = if (who != null) { accountsIsOwner(who) } else { false };
      let view = if ((wantsView == "trace" || wantsView == "prompts") && !isOwner) { "read" } else { wantsView };
      let state = new ShowState(work, who, view);
      state.fresh = !ctx.isAjax && ctx.req.method == "GET";
      state.chatOpen = ctx.req.query.getOr("chat", "") == "1";
      psFinishWho(state, launcher);
      showApplyUi(ctx, state);

      let runs = psRuns(ctx, work.id);
      state.running = runs.filter { (r: Run): Boolean => r.isRunning() };
      psSettle(ctx, state, runs);
      let current = state.work;

      state.sections = worksListSections(ctx.db, current.id);
      state.beats = psNodes(ctx.db, current.id, "beat");
      state.spine = psNodes(ctx.db, current.id, "spine");
      state.threads = psNodes(ctx.db, current.id, "thread");
      state.questions = psNodes(ctx.db, current.id, "question");
      state.counts = worksCounts(ctx.db, current.id);
      state.revisions = psNewestFirst(worksRevisions(ctx.db, current.id));
      state.revisionCount = state.revisions.length;
      state.document = documentGet(ctx.db, current.id);
      let condensed = worksCondensationOf(ctx.db, current.id);
      if (condensed != null) {
        let link = linksGetFor(ctx.db, current.id, condensed.id);
        if (link != null) { state.summaryLink = link.id; }
      }
      state.links = linksForWork(ctx.db, current.id);
      if (state.mine && current.status == "read") {
        state.linkable = linksLinkable(ctx.db, ctx.scope, current.id);
      }
      state.stages = showStagesOf(current, state.sections, state.counts);
      if (current.status == "reading") { state.startedAt = psStartedAt(current, runs); }
      psLoadChat(ctx, state);
      psLoadForView(ctx, state);
      psMaybeTour(ctx, state);
      state.walk = if (state.demo && state.view == "read") { walkthroughSteps("read", state.mine) } else { [] };
      showSaveUi(ctx, state);
      state
    }

By slug. A slug with no draft behind it is a bubble; the page checks first
(`worksGetBySlug`) and redirects with `No such draft.`.

    export let loadShowWith(ctx: Ctx, slug: String, launcher: ShowLauncher): ShowState throws Bubble {
      let work = worksGetBySlug(ctx.db, slug);
      if (work != null) {
        loadShowFor(ctx, work, launcher)
      } else {
        console.log("pages_show: no draft with slug ${slug}");
        bubble()
      }
    }

    export let loadShow(ctx: Ctx, slug: String): ShowState throws Bubble {
      loadShowWith(ctx, slug, new ShowForkLauncher())
    }
