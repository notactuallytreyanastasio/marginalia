# Tests for the controls that start work, and for what the page says when it ends

The read, the graph, the backend, linking, the summaries; the downloads; the
flash a finished run is owed; and the pure functions the frame is built from.

    let { accountsOwnerEmail, accountsGetUser, accountsProviderFor, scopeFor } = import("accounts/src");
    let { Ctx, webNewCtx } = import("webcore/src");
    let { worksGetBySlug, worksListNodes, worksListSections, worksGetById, WorkCounts } = import("works/src");
    let { runsGet, runsFinish, runsCounts } = import("runs/src");
    let { linksGetFor } = import("links/src");
    let { Row } = import("core/src");
    let { JsonObject, JsonSyntaxTree, parseJson } = import("std/json");

    let tRunStatus(db: Db, key: String): String throws Bubble {
      let run = runsGet(db, key);
      if (run != null) { run.status } else { "none" }
    }

    let tLinkId(db: Db, a: Work, b: Work): Int throws Bubble {
      let link = linksGetFor(db, a.id, b.id);
      if (link != null) { link.id } else { -1 }
    }

    let tAppliedAfter(state: ShowState): String {
      let a = state.applied;
      if (a != null) { a.after } else { "" }
    }

    let tCandidates(state: ShowState): Int {
      let r = state.rewrite;
      if (r != null) { r.candidates.length } else { -1 }
    }

## The read

    test("read: a reader's Read, Build and Provider say they are not the owner's") { test =>
      let w = tWorld();
      let denial = "This draft is someone else's. You can read it, not change it.";
      expectText(test, tFlash(tEvent(w.db, w.reader, tPage(w), "start_read", "{}", tKeyed()), "error"), denial);
      expectText(test, tFlash(tEvent(w.db, w.reader, tPage(w), "build_graph", "{}", tKeyed()), "error"), denial);
      expectText(test, tFlash(tEvent(w.db, w.reader, tPage(w), "set_provider", "{\"provider\":\"openai\"}", tKeyed()), "error"), denial);
      expectText(test, tFlash(tEvent(w.db, w.reader, tPage(w), "send", "{\"message\":\"hello\"}", tKeyed()), "error"), denial);
      expectText(test, tFlash(tEvent(w.db, w.reader, tPage(w), "set_mode", "{\"mode\":\"bounce\"}", tKeyed()), "error"), denial);
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
      expectText(test, tStatusOf(w.db, w.work), "read");
    }

    test("read: starting it marks the draft reading before the job is forked") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "start_read", "{}", tQueue());
      expectInt(test, r.resp.status, 200);
      expectText(test, tStatusOf(w.db, w.work), "reading");
      let run = runsGet(w.db, showReadKey(w.work.id));
      expectTrue(test, run != null, "the read is a run");
      expectHas(test, tMain(r), "Reading your draft");
      expectHas(test, tMain(r), "data-poll");
    }

    test("read: pressing it twice does not start a second read") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "start_read", "{}", tQueue());
      tEvent(w.db, w.owner, tPage(w), "start_read", "{}", tQueue());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 1);
    }

    test("read: a draft read before is thrown away first, and every section is pending again") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "A beat");
      w.db.exec("UPDATE sections SET status = 'read' WHERE work_id = $1", [w.work.id.toString()]);
      tEvent(w.db, w.owner, tPage(w), "start_read", "{}", tQueue());
      expectInt(test, worksListNodes(w.db, w.work.id, null, null, null).length, 0);
      expectText(test, worksListSections(w.db, w.work.id)[0].status, "pending");
    }

    test("read: run inline against a model that answers nothing, it ends and says how") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "start_read", "{}", tKeyed());
      expectInt(test, r.resp.status, 200);
      let status = tStatusOf(w.db, w.work);
      expectTrue(test, status == "read" || status == "failed", "the job ended: ${status}");
      expectText(test, tRunStatus(w.db, showReadKey(w.work.id)), "done");
    }

    test("read: the progress the job reports is the run's") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "start_read", "{}", tQueue());
      w.db.exec("UPDATE runs SET progress = $1 WHERE key = $2", [runsCounts(1, 4), showReadKey(w.work.id)]);
      expectTrue(test, runsGet(w.db, showReadKey(w.work.id)) != null, "still a run");
    }

## The graph

    test("graph: the owner starts a build, and the page says it is building") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "build_graph", "{}", tQueue());
      let run = runsGet(w.db, showGraphKey(w.work.id));
      expectTrue(test, run != null, "the build is a run");
      let state = loadShowFor(tCtxFor(w, w.owner, tPath(w.work, "graph")), w.work, tKeyed());
      expectTrue(test, state.graphBuilding, "graphBuilding is read off the run");
    }

    test("graph: a second press while it builds starts nothing") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "build_graph", "{}", tQueue());
      tEvent(w.db, w.owner, tPage(w), "build_graph", "{}", tQueue());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 1);
    }

    let tFresh(w: TWorld): Work throws Bubble {
      let again = worksGetById(w.db, w.work.id);
      if (again != null) { again } else { bubble() }
    }

    let tCtxFor(w: TWorld, who: TWho, path: String): Ctx throws Bubble {
      let req = tRaw("GET", path, tCookieHeader(who), "");
      let ctx = webNewCtx(w.db, ":memory:", req, tMatch("GET", tPlain(path)).params);
      webMountCurrentScope(ctx);
      ctx
    }

    test("graph: the graph tab has the export, the stats and the trace its own data") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "A beat");
      let ctx = tCtxFor(w, w.owner, tPath(w.work, "graph"));
      let state = loadShowFor(ctx, w.work, tKeyed());
      let json = state.graphJson;
      expectTrue(test, json != null, "graphJson is loaded for the graph view");
      expectTrue(test, state.graphStats != null, "graphStats too");
      expectInt(test, state.events.length, 0);
    }

    test("graph: the read view loads the page, and not the graph") { test =>
      let w = tWorld();
      let state = loadShowFor(tCtxFor(w, w.owner, tPath(w.work, "read")), w.work, tKeyed());
      expectTrue(test, state.page != null, "the page");
      expectTrue(test, state.graphJson == null, "no graph");
    }

    test("graph: the changes view loads the rows and their stat") { test =>
      let w = tWorld();
      tEdit(w.db, w.work, "kettle", "AMENDED");
      let state = loadShowFor(tCtxFor(w, w.owner, tPath(w.work, "changes")), tFresh(w), tKeyed());
      expectTrue(test, showAnyChange(state.diffRows), "there is a change to show");
      let stat = state.diffStat;
      expectTrue(test, stat != null, "stat");
      expectInt(test, state.revisions.length, 1);
    }

    test("graph: the prompts view loads the read's, the graph's and the rewrite's passes") { test =>
      let w = tWorld();
      let boss = tWho(w.db, accountsOwnerEmail());
      let state = loadShowFor(tCtxFor(w, boss, tPath(w.work, "prompts")), w.work, tKeyed());
      expectTrue(test, state.passes.length >= 5, "five passes at least");
      expectTrue(test, state.modes.length == 3, "three chat stances");
    }

## The backend

    test("provider: the deploy's owner chooses a backend") { test =>
      let w = tWorld();
      let boss = tWho(w.db, accountsOwnerEmail());
      let work = tRead(w.db, boss.scope, "Theirs", tBody());
      let r = tEvent(w.db, boss, tPath(work, "read"), "set_provider", "{\"provider\":\"openai\"}", tKeyed());
      expectText(test, tFlash(r, "info"), "Backend: openai");
      expectText(test, showOr(accountsProviderFor(accountsGetUser(w.db, boss.id)), ""), "openai");
    }

    test("provider: an unknown name changes nothing") { test =>
      let w = tWorld();
      let boss = tWho(w.db, accountsOwnerEmail());
      let work = tRead(w.db, boss.scope, "Theirs", tBody());
      let r = tEvent(w.db, boss, tPath(work, "read"), "set_provider", "{\"provider\":\"nonsense\"}", tKeyed());
      expectText(test, tFlash(r, "info"), "");
    }

    test("provider: anyone else's choice is a silent no-op") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "set_provider", "{\"provider\":\"openai\"}", tKeyed());
      expectText(test, tFlash(r, "info"), "Backend: deploy default");
      expectTrue(test, accountsProviderFor(accountsGetUser(w.db, w.owner.id)) == null, "no backend chosen");
    }

## Linking

    test("link: the owner links two read drafts, and goes to the pair") { test =>
      let w = tWorld();
      let other = tRead(w.db, w.owner.scope, "Other", tBody());
      let r = tEvent(w.db, w.owner, tPage(w), "link_to", "{\"id\":\"${other.id.toString()}\"}", tKeyed());
      let linkId = tLinkId(w.db, w.work, other);
      expectTrue(test, linkId > 0, "the pair has a link");
      expectText(test, tRedirect(r), "/links/${linkId.toString()}?lead=${w.work.slug}");
      expectText(test, tRunStatus(w.db, showLinkKey(linkId)), "done");
    }

    test("link: a draft that is not the owner's cannot be linked") { test =>
      let w = tWorld();
      let theirs = tRead(w.db, w.reader.scope, "Theirs", tBody());
      let r = tEvent(w.db, w.owner, tPage(w), "link_to", "{\"id\":\"${theirs.id.toString()}\"}", tKeyed());
      expectText(test, tFlash(r, "error"), "That draft can't be linked.");
      expectTrue(test, linksGetFor(w.db, w.work.id, theirs.id) == null, "no link");
    }

    test("link: a draft cannot be linked to itself") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "link_to", "{\"id\":\"${w.work.id.toString()}\"}", tKeyed());
      expectText(test, tFlash(r, "error"), "That draft can't be linked.");
    }

    test("link: a reader cannot link someone else's draft") { test =>
      let w = tWorld();
      let mine = tRead(w.db, w.reader.scope, "Mine", tBody());
      let r = tEvent(w.db, w.reader, tPage(w), "link_to", "{\"id\":\"${mine.id.toString()}\"}", tKeyed());
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
      expectTrue(test, linksGetFor(w.db, w.work.id, mine.id) == null, "no link");
    }

    test("link: a pair already being read is not read again") { test =>
      let w = tWorld();
      let other = tRead(w.db, w.owner.scope, "Other", tBody());
      tEvent(w.db, w.owner, tPage(w), "link_to", "{\"id\":\"${other.id.toString()}\"}", tQueue());
      let before = tN(w.db, "SELECT count(*) AS n FROM runs");
      tEvent(w.db, w.owner, tPage(w), "link_to", "{\"id\":\"${other.id.toString()}\"}", tQueue());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), before);
    }

## Summaries

    test("summarise: one section, run inline, leaves its summary on the section") { test =>
      let w = tWorld();
      let launcher = tInline([tSummaryReply()]);
      tEvent(w.db, w.owner, tPage(w), "summarise", "{\"ordinal\":\"1\"}", launcher);
      let section = worksListSections(w.db, w.work.id)[0];
      expectText(test, showOr(section.summary, ""), "It opens at the window and ends on the kettle.");
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), launcher));
      expectHas(test, html, "It opens at the window and ends on the kettle.");
      expectHas(test, html, "Summarise again");
    }

    test("summarise: while it runs the button is the thing that goes quiet") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "summarise", "{\"ordinal\":\"1\"}", tQueue());
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed()));
      expectHas(test, html, "disabled>Summarising…<");
      expectHas(test, html, "data-poll=\"2\"");
    }

    test("summarise: pressing it twice does not start a second pass") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "summarise", "{\"ordinal\":\"1\"}", tQueue());
      tEvent(w.db, w.owner, tPage(w), "summarise", "{\"ordinal\":\"1\"}", tQueue());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 1);
    }

    test("summarise: a section that is not there changes nothing") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "summarise", "{\"ordinal\":\"9\"}", tQueue());
      tEvent(w.db, w.owner, tPage(w), "summarise", "{\"ordinal\":\"nine\"}", tQueue());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
    }

    test("summarise: a reader cannot spend the owner's credit") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.reader, tPage(w), "summarise", "{\"ordinal\":\"1\"}", tQueue());
      expectText(test, tFlash(r, "error"), "This draft is someone else's.");
      let d = tEvent(w.db, w.reader, tPage(w), "summarise_document", "{}", tQueue());
      expectText(test, tFlash(d, "error"), "This draft is someone else's.");
      let c = tEvent(w.db, w.reader, tPage(w), "compare_summary", "{}", tQueue());
      expectText(test, tFlash(c, "error"), "This draft is someone else's.");
      let t = tEvent(w.db, w.reader, tPage(w), "summaries_to_draft", "{}", tQueue());
      expectText(test, tFlash(t, "error"), "This draft is someone else's.");
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
    }

    test("summarise: the walkthrough does not call the model") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "start_walk", "{}", tQueue());
      let r = tEvent(w.db, w.owner, tPage(w), "summarise", "{\"ordinal\":\"1\"}", tQueue());
      expectText(test, tFlash(r, "info"), "The walkthrough does not call the model.");
      let d = tEvent(w.db, w.owner, tPage(w), "summarise_document", "{}", tQueue());
      expectText(test, tFlash(d, "info"), "The walkthrough does not call the model.");
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 0);
    }

    test("document: the pass is a run, and the button says so") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "summarise_document", "{}", tQueue());
      expectTrue(test, runsGet(w.db, showDocumentKey(w.work.id)) != null, "a run");
      expectHas(test, tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed())), "Reading it all…");
    }

    test("compare: the pass is a run, and the button names the stage") { test =>
      let w = tWorld();
      tSummariseFirst(w);
      tEvent(w.db, w.owner, tPage(w), "compare_summary", "{}", tQueue());
      w.db.exec("UPDATE runs SET progress = 'Relating' WHERE key = $1", [showCompareKey(w.work.id)]);
      expectHas(test, tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed())), "Relating…");
    }

    test("compare: one at a time") { test =>
      let w = tWorld();
      tSummariseFirst(w);
      tEvent(w.db, w.owner, tPage(w), "compare_summary", "{}", tQueue());
      let r = tEvent(w.db, w.owner, tPage(w), "compare_summary", "{}", tQueue());
      expectText(test, tFlash(r, "error"), "A compare pass is already running on this draft.");
    }

    let tSummariseFirst(w: TWorld): Void throws Bubble {
      let s = tSection(w.db, w.work);
      w.db.exec("UPDATE sections SET summary = 'S', summary_fingerprint = 'x' WHERE id = $1", [s.id.toString()]);
    }

    test("to draft: nothing summarised is refused") { test =>
      let w = tWorld();
      let r = tEvent(w.db, w.owner, tPage(w), "summaries_to_draft", "{}", tKeyed());
      expectText(test, tFlash(r, "error"), "Summarise at least one section first.");
    }

    test("to draft: the summaries become a draft of their own, and the page goes to it") { test =>
      let w = tWorld();
      tSummariseFirst(w);
      let r = tEvent(w.db, w.owner, tPage(w), "summaries_to_draft", "{}", tKeyed());
      let to = tRedirect(r);
      expectTrue(test, showStartsWith(to, "/works/"), "to a draft: ${to}");
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM works WHERE derived_from_id IS NOT NULL"), 1);
    }

## What a finished run is owed

A page that last saw a run going, and now finds it ended, says how it ended
once. A page that never saw it going says nothing.

    test("flash: a document pass that finished is announced once") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "summarise_document", "{}", tQueue());
      runsFinish(w.db, showDocumentKey(w.work.id), "done", showAnswerOk());
      let first = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(first, "info"), "The whole document has been read.");
      let second = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(second, "info"), "");
    }

    test("flash: a document pass that failed says why") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "summarise_document", "{}", tQueue());
      runsFinish(w.db, showDocumentKey(w.work.id), "done", showAnswerError("no_summaries", null));
      let r = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(r, "error"), "Could not summarise the document: no_summaries");
    }

    test("flash: a document pass that crashed says so") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "summarise_document", "{}", tQueue());
      runsFinish(w.db, showDocumentKey(w.work.id), "crashed", "Bubble");
      let r = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(r, "error"), "The document pass crashed: Bubble");
    }

    test("flash: a section's summary that failed names the section") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "summarise", "{\"ordinal\":\"1\"}", tQueue());
      runsFinish(w.db, showSummariseKey(w.work.id, 1), "done", showAnswerError("rate_limited", null));
      let r = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(r, "error"), "Could not summarise section 1: rate_limited");
    }

    test("flash: a comparison that finished says the two are side by side") { test =>
      let w = tWorld();
      tSummariseFirst(w);
      tEvent(w.db, w.owner, tPage(w), "compare_summary", "{}", tQueue());
      runsFinish(w.db, showCompareKey(w.work.id), "done", "{\"compared\":1}");
      let r = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(r, "info"), "Drafted, read and related. They are side by side now.");
    }

    test("flash: a comparison that crashed keeps what it finished") { test =>
      let w = tWorld();
      tSummariseFirst(w);
      tEvent(w.db, w.owner, tPage(w), "compare_summary", "{}", tQueue());
      runsFinish(w.db, showCompareKey(w.work.id), "crashed", "Bubble");
      let r = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(r, "error"), "The comparison crashed. Anything it finished is saved.");
    }

    test("flash: a page that never saw the run going says nothing") { test =>
      let w = tWorld();
      w.db.exec("INSERT INTO runs (key, status, detail, started_at) VALUES ($1, 'done', $2, '2020-01-01 00:00:00')", [showDocumentKey(w.work.id), showAnswerOk()]);
      let r = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(r, "info"), "");
    }

    test("flash: a rewrite that came back with nothing says so, and no panel stays") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tWords(40)}\",\"ref\":\"s1p1\"}", tQueue());
      runsFinish(w.db, showRewriteKey(w.work.id), "done", "{\"error\":\"no_candidates\"}");
      let r = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(r, "error"), "Nothing came back that was different from what you wrote.");
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed())), "id=\"rewrite-panel\"");
    }

    test("flash: a rewrite whose job crashed says so") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tWords(40)}\",\"ref\":\"s1p1\"}", tQueue());
      runsFinish(w.db, showRewriteKey(w.work.id), "crashed", "Bubble");
      let r = tPoll(w.db, w.owner, tPage(w), tKeyed());
      expectText(test, tFlash(r, "error"), "That did not go through: Bubble");
    }

    test("flash: a rewrite that came back is put in the panel") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", tQueue());
      let found = new ShowRewrite("Flat.", tSpan(), 1, [new RewriteCandidate("Shorter.", "Cuts", "Loses")], false, []);
      runsFinish(w.db, showRewriteKey(w.work.id), "done", showRewriteJson(found));
      tPoll(w.db, w.owner, tPage(w), tKeyed());
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed()));
      expectHas(test, html, "Shorter.");
      expectHas(test, html, "Flat.");
      expectLacks(test, html, "data-poll");
    }

    test("flash: closing the panel forgets a pass that is still going") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", tQueue());
      tEvent(w.db, w.owner, tPage(w), "close_rewrite", "{}", tQueue());
      let found = new ShowRewrite("Flat.", tSpan(), 1, [new RewriteCandidate("Shorter.", "Cuts", "Loses")], false, []);
      runsFinish(w.db, showRewriteKey(w.work.id), "done", showRewriteJson(found));
      let html = tBodyOf(tGet(w.db, w.owner, tPage(w), tKeyed()));
      expectLacks(test, html, "Shorter.");
      expectLacks(test, html, "id=\"rewrite-panel\"");
    }

    test("flash: a rewrite is a job a second asker cannot start over the first") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p1\"}", tQueue());
      tEvent(w.db, w.owner, tPage(w), "suggest_rewrite", "{\"text\":\"${tSpan()}\",\"ref\":\"s1p0\"}", tQueue());
      expectInt(test, tN(w.db, "SELECT count(*) AS n FROM runs"), 1);
    }

## The downloads

    test("downloads: the graph is for anyone holding the slug") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "A beat");
      let r = tGet(w.db, w.reader, "/works/${w.work.slug}/graph.json", tKeyed());
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBodyOf(r), "\"nodes\"");
      expectHas(test, tBodyOf(r), "A beat");
      expectHas(test, tHeader(r, "Content-Type"), "application/json");
      expectText(test, tHeader(r, "Content-Disposition"), "attachment; filename=\"draft-graph.json\"");
    }

    test("downloads: the graph as dot") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "A beat");
      let r = tGet(w.db, w.reader, "/works/${w.work.slug}/graph.dot", tKeyed());
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBodyOf(r), "digraph marginalia");
      expectHas(test, tHeader(r, "Content-Type"), "text/vnd.graphviz");
      expectText(test, tHeader(r, "Content-Disposition"), "attachment; filename=\"draft-graph.dot\"");
    }

    test("downloads: a slug nobody has is a 404 that says so") { test =>
      let w = tWorld();
      let r = tGet(w.db, w.owner, "/works/1/graph.json", tKeyed());
      expectInt(test, r.resp.status, 404);
      expectText(test, tBodyOf(r), "not found");
      expectInt(test, tGet(w.db, w.owner, "/works/1/graph.dot", tKeyed()).resp.status, 404);
      expectInt(test, tGet(w.db, w.owner, "/works/1/trace.json", tKeyed()).resp.status, 404);
    }

    test("downloads: the trace does not travel with the link") { test =>
      let w = tWorld();
      let mine = tGet(w.db, w.owner, "/works/${w.work.slug}/trace.json", tKeyed());
      expectInt(test, mine.resp.status, 200);
      expectHas(test, tBodyOf(mine), "\"events\"");
      expectText(test, tHeader(mine, "Content-Disposition"), "attachment; filename=\"draft-trace.json\"");
      let theirs = tGet(w.db, w.reader, "/works/${w.work.slug}/trace.json", tKeyed());
      expectInt(test, theirs.resp.status, 404);
    }

    test("downloads: a title with no letters is a draft") { test =>
      let w = tWorld();
      let odd = tRead(w.db, w.owner.scope, "!!!", tBody());
      let r = tGet(w.db, w.owner, "/works/${odd.slug}/graph.json", tKeyed());
      expectText(test, tHeader(r, "Content-Disposition"), "attachment; filename=\"draft-graph.json\"");
    }

## Pure functions

    test("view: anything but the seven is the page") { test =>
      expectText(test, showViewOf("spine"), "spine");
      expectText(test, showViewOf("trace"), "trace");
      expectText(test, showViewOf("changes"), "changes");
      expectText(test, showViewOf("nonsense"), "read");
      expectText(test, showViewOf(""), "read");
      expectText(test, showViewOf("READ"), "read");
    }

    test("path: the view is always in it, the drawer when open") { test =>
      expectText(test, showPath("abc", "read", false), "/works/abc?view=read");
      expectText(test, showPath("abc", "graph", true), "/works/abc?view=graph&chat=1");
    }

    test("epoch: a UTC stamp as unix seconds") { test =>
      let a = showEpoch("2020-01-01 00:00:00");
      expectTrue(test, a != null && showIntOr(a, 0) == 1577836800, "2020-01-01");
      expectInt(test, showIntOr(showEpoch("1970-01-02 00:00:01"), 0), 86401);
      expectInt(test, showIntOr(showEpoch("2000-03-01 12:30:15"), 0), 951913815);
      expectTrue(test, showEpoch("yesterday") == null, "not a stamp");
    }

    test("stages: read off what is in the database") { test =>
      let w = tWorld();
      let sections = worksListSections(w.db, w.work.id);
      let zero = new WorkCounts(0, 0, 0, 0, 0, 0);
      let spined = new WorkCounts(0, 1, 0, 0, 0, 1);
      expectText(test, showStagesOf(w.work, sections, zero).weave, "done");
      let reading = worksSetStatusTest(w);
      expectText(test, showStagesOf(reading, sections, zero).sections, "start");
      expectText(test, showStagesOf(reading, sections, spined).weave, "start");
      expectText(test, showStagesOf(reading, sections, spined).spine, "done");
    }

    let worksSetStatusTest(w: TWorld): Work throws Bubble {
      worksSetStatus(w.db, w.work, "reading", null)
    }

    test("stages: every section read and no spine yet is the spine's turn") { test =>
      let w = tWorld();
      let reading = worksSetStatusTest(w);
      w.db.exec("UPDATE sections SET status = 'read'", []);
      let sections = worksListSections(w.db, w.work.id);
      let st = showStagesOf(reading, sections, new WorkCounts(2, 0, 0, 0, 0, 2));
      expectText(test, st.sections, "done");
      expectText(test, st.spine, "start");
      expectText(test, st.weave, "waiting");
    }

    test("stages: a draft that is not reading has nothing started") { test =>
      let w = tWorld();
      let pending = worksSetStatus(w.db, w.work, "pending", null);
      let st = showStagesOf(pending, [], new WorkCounts(0, 0, 0, 0, 0, 0));
      expectText(test, st.sections, "waiting");
      expectText(test, st.weave, "waiting");
    }

    test("diff: the stat counts each kind of row") { test =>
      let rows = [
        new Row("same", "a", "a"), new Row("change", "b", "c"), new Row("ins", null, "d"),
        new Row("del", "e", null), new Row("same", "f", "f"),
      ];
      let stat = showDiffStatOf(rows);
      expectInt(test, stat.same, 2);
      expectInt(test, stat.changed, 1);
      expectInt(test, stat.added, 1);
      expectInt(test, stat.removed, 1);
      expectTrue(test, showAnyChange(rows), "there is a change");
      expectFalse(test, showAnyChange([new Row("same", "a", "a")]), "none");
    }

    test("rewrite errors: the reasons are worded as the page worded them") { test =>
      expectText(test, showRewriteError("not_in_draft", null, 0, 0), "That selection is not in the draft, character for character.");
      expectText(test, showRewriteError("span_too_long", null, 3000, 2500), "That is 3000 words. Rewrites go up to 2500 — past that, split it and take the part you actually want reworked.");
      expectText(test, showRewriteError("no_candidates", null, 0, 0), "Nothing came back that was different from what you wrote.");
      expectText(test, showRewriteError("rate_limited", null, 0, 0), "That did not go through: :rate_limited");
      expectText(test, showRewriteError("http", "500", 0, 0), "That did not go through: :http: 500");
    }

    test("cls: a class list drops what is empty") { test =>
      expectText(test, showCls(["a", "", "b", ""]), "a b");
      expectText(test, showCls(["", ""]), "");
    }

    test("poll: waiting is a read, a run, a pending rewrite or a question in flight") { test =>
      let w = tWorld();
      let ctx = tCtxFor(w, w.owner, tPage(w));
      let idle = loadShowFor(ctx, w.work, tKeyed());
      expectTrue(test, showPoll(idle) == null, "idle");
      idle.rewritePending = true;
      expectTrue(test, showPoll(idle) != null, "a pending rewrite");
      idle.rewritePending = false;
      idle.loading = true;
      expectTrue(test, showPoll(idle) != null, "a question in flight");
    }

    test("ui: the state only the page knows survives the round trip") { test =>
      let w = tWorld();
      let ctx = tCtxFor(w, w.owner, tPage(w));
      let state = loadShowFor(ctx, w.work, tKeyed());
      state.only = "beats";
      state.steer = "shorter";
      state.rewriteSpan = "a span";
      state.rewriteRef = "s1p1";
      state.editing = "s1p2";
      state.editText = "text";
      state.changesOn = true;
      state.applied = new ShowApplied("before", "after");
      state.rewrite = new ShowRewrite("Flat.", "the line", 1, [new RewriteCandidate("A.", "m", null)], true, ["s1p1", "s1p2"]);
      showSaveUi(ctx, state);
      let again = loadShowFor(ctx, w.work, tKeyed());
      expectText(test, showOr(again.only, ""), "beats");
      expectText(test, showOr(again.steer, ""), "shorter");
      expectText(test, showOr(again.editing, ""), "s1p2");
      expectTrue(test, again.changesOn, "toggle");
      expectText(test, tAppliedAfter(again), "after");
      expectInt(test, tCandidates(again), 1);
    }
