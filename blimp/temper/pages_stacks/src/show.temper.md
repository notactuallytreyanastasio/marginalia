# /stacks/:id and /stacks/:id/:ordinal

`StackLive.Show`: a folder read forwards, and a page per step. One page library
module for both, as it was one LiveView with two renders: with no ordinal it is
the folder page (the chain of capabilities, the six passes, the telling's
card), with one it is that step.

The folder page is a viewer of a pass and not its owner. A pass is a `runs` row
(`stack:<folder id>`) that a forked job writes; the page reads it on every
request, shows the counter and the note, and carries `data-poll` while the
row says `running`, so the next fetch re-renders from the database: the steps
a forward read has written show up as they are written, as the LiveView's
`load` on every progress tick did.

    let { Ctx, webRedirect, webPutFlash, uiGet, webCsrfField } = import("webcore/src");
    let { Response, Match } = import("http/src");
    let { JsonObject } = import("std/json");
    let { Db } = import("db/src");
    let { Folder, foldersGetFolderOrNull, foldersParseId, foldersPublishAsOwner, foldersUnpublish } = import("folders/src");
    let { Work } = import("works/src");
    let { accountsOwner } = import("accounts/src");
    let { Run } = import("runs/src");
    let {
      StackStory, StackStep, StackExcerpt, StackGuideEntry, StackStats, StackRunView, StackFlash,
      stacksGetStory, stacksGuide, stacksDocuments, stacksStats, stacksStoryCurrent,
      stacksRunView, stacksPassNote, stacksFlashFor, stacksAlreadyRunning, stacksRunKey,
    } = import("stacks/src");
    let { h, hv, htext, attr } = import("html/src");
    let { sysJoin } = import("sys/src");

## State

Everything `mount` and `load` assigned: the folder, the telling (if composed),
the guide (one entry per step, with what it needs and what needs it), the
folder's documents, the counts, whether the telling still matches the steps,
and the pass in flight, if any. `view` is null when nothing is running.

    export class PagesStacksShowState(
      public folder: Folder,
      public ordinal: Int?,
      public story: StackStory?,
      public guide: List<StackGuideEntry>,
      public documents: List<Work>,
      public stats: StackStats,
      public storyCurrent: Boolean,
      public view: StackRunView?,
    ) {}

    let pkStoryCurrent(db: Db, story: StackStory?, folderId: Int): Boolean throws Bubble {
      if (story != null) { stacksStoryCurrent(db, story, folderId) } else { true }
    }

    export let loadStacksShow(ctx: Ctx, folder: Folder, ordinal: Int?, run: Run?): PagesStacksShowState throws Bubble {
      let story = stacksGetStory(ctx.db, folder.id);
      new PagesStacksShowState(
        folder, ordinal, story,
        stacksGuide(ctx.db, folder.id),
        stacksDocuments(ctx.db, ctx.scope, folder.id),
        stacksStats(ctx.db, ctx.scope, folder.id),
        pkStoryCurrent(ctx.db, story, folder.id),
        stacksRunView(run),
      )
    }

`from_run`: `reading` is the counter of every pass but the composition, which
has a stage instead.

    let pkComposing(state: PagesStacksShowState): Boolean {
      let v = state.view;
      if (v != null) { v.kind == "compose" } else { false }
    }

    let pkReading(state: PagesStacksShowState): Boolean {
      let v = state.view;
      if (v != null) { v.kind != "compose" } else { false }
    }

    let pkBusy(state: PagesStacksShowState): Boolean { state.view != null }

    let pkStageOf(state: PagesStacksShowState): String? {
      let v = state.view;
      if (v != null) { v.stageText() } else { null }
    }

    let pkPoll(state: PagesStacksShowState): Int? {
      if (state.view != null) { 2 } else { null }
    }

`round(done / total * 100)` as a percent, `0%` when there is no total.

    let pkPercent(done: Int, total: Int): String {
      if (total > 0) {
        do { "${((done * 200 + total) / (total * 2)).toString()}%" } orelse "0%"
      } else { "0%" }
    }

## The folder page

    let pkBtn(cls: String, event: String, busy: Boolean, label: String): List<AnyValue> {
      h("button", "${attr("class", cls)}${attr("phx-click", event)}${if (busy) { " disabled" } else { "" }}", htext(label))
    }

    let pkDeepenLabel(stats: StackStats): String {
      if (stats.deepFailed > 0) {
        "Retry ${stats.deepFailed.toString()} failed"
      } else if (stats.deepened > 0) {
        "Deepen again"
      } else {
        "Second pass"
      }
    }

    let pkComposeLabel(state: PagesStacksShowState): String {
      let stage = pkStageOf(state);
      if (pkComposing(state) && stage != null) {
        "Composing — ${stage}"
      } else if (pkComposing(state)) {
        "Composing…"
      } else if (state.story != null) {
        "Compose again"
      } else {
        "Compose the telling"
      }
    }

    let pkStatsLine(stats: StackStats): List<AnyValue> {
      let deepened: List<AnyValue> = if (stats.deepened > 0) {
        [h("span", "", htext("· ${stats.deepened.toString()} deepened · ${stats.revisions.toString()} revised later")), "\n"]
      } else { [] };
      let failed: List<AnyValue> = if (stats.deepFailed > 0) {
        [h("span", attr("class", "cut-err"), htext("· ${stats.deepFailed.toString()} failed the second pass")), "\n"]
      } else { [] };
      let dropped: List<AnyValue> = if (stats.dropped > 0) {
        h("span", "", htext("· ${stats.dropped.toString()} claims dropped"))
      } else { [] };
      h("div", attr("class", "mg-meta mt-1"), [
        htext("${stats.documents.toString()} documents · ${stats.read.toString()} read · ${stats.summarised.toString()} summarised · ${stats.mapped.toString()} mapped · ${stats.related.toString()} related · ${stats.pitfalls.toString()} pitfalls · ${stats.links.toString()} dependencies"),
        "\n", deepened, failed, dropped,
      ])
    }

The row of buttons. Each pass but the first is offered only when it has
something to do; every one is disabled while a pass is in flight.

    let pkCounter(state: PagesStacksShowState): List<AnyValue> {
      let v = state.view;
      if (v != null) {
        if (v.kind != "compose") {
          h("span", attr("class", "mg-meta"), htext("${v.done.toString()} of ${v.total.toString()} — ${stacksPassNote(v.kind)}"))
        } else { [] }
      } else { [] }
    }

    let pkButtons(state: PagesStacksShowState): List<AnyValue> {
      let stats = state.stats;
      let busy = pkBusy(state);
      let readLabel = if (stats.read > 0) { "Read forwards again" } else { "Read forwards" };
      let deepen: List<AnyValue> = if (stats.read > 0) {
        pkBtn("mg-btn ghost", "deepen", busy, pkDeepenLabel(stats))
      } else { [] };
      let left = if (stats.mapped > 0) { " (${(stats.documents - stats.mapped).toString()} left)" } else { "" };
      let readEach: List<AnyValue> = if (stats.mapped < stats.documents) {
        pkBtn("mg-btn ghost", "read_each", busy, "Read each document${left}")
      } else { [] };
      let relate: List<AnyValue> = if (stats.documents > 1 && stats.mapped > 1) {
        pkBtn("mg-btn ghost", "relate", busy, if (stats.related > 0) { "Relate them again" } else { "Relate the documents" })
      } else { [] };
      let summarise: List<AnyValue> = if (stats.documents > stats.summarised) {
        pkBtn("mg-btn ghost", "summarise", busy, if (stats.summarised > 0) { "Summarise the other ${(stats.documents - stats.summarised).toString()}" } else { "Summarise each document" })
      } else { [] };
      let compose: List<AnyValue> = if (stats.read > 0) {
        pkBtn("mg-btn ghost", "compose", busy, pkComposeLabel(state))
      } else { [] };
      let counter = pkCounter(state);
      h("div", attr("class", "mt-5 flex items-center gap-3"), [
        pkBtn("mg-btn", "read", busy, readLabel), "\n",
        deepen, "\n", readEach, "\n", relate, "\n", summarise, "\n", compose, "\n",
        counter,
      ])
    }

    let pkComposingNote(state: PagesStacksShowState): List<AnyValue> {
      if (!pkComposing(state)) { return []; }
      let stage = pkStageOf(state);
      let bold: List<AnyValue> = if (stage != null) {
        [h("b", "", htext("Composing — ${stage}.")), "\n"]
      } else { [] };
      h("p", attr("class", "mg-meta mt-2"), [
        bold,
        htext("Composing runs on the server too. Leave, come back, open it on your phone — the page finds the pass still going. A deploy is the one thing that stops it."),
      ])
    }

    let pkProgressBar(state: PagesStacksShowState): List<AnyValue> {
      let v = state.view;
      if (v != null) {
        if (v.kind != "compose") {
          h("p", "${attr("class", "st-progress")}${attr("style", "--done:${pkPercent(v.done, v.total)}")}", h("span", "", []))
        } else { [] }
      } else { [] }
    }

Not read yet: the documents in the order they will be read.

    let pkUnread(state: PagesStacksShowState): List<AnyValue> {
      let items = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < state.documents.length) {
        let w = state.documents[i];
        items.add(h("li", attr("id", "doc-${w.id.toString()}"), [
          h("span", attr("class", "n"), htext((i + 1).toString())),
          htext(w.title),
        ]));
        i += 1;
      }
      [
        h("p", attr("class", "mg-empty mt-8"), htext("Not read yet. Reading is one call per document, in order, because each one is told what the ones before it established.")),
        h("ol", attr("class", "st-docs mt-4"), items.toList()),
      ]
    }

The card of the telling, with publish and unpublish.

    let pkPublishBlock(state: PagesStacksShowState): List<AnyValue> {
      let folder = state.folder;
      let slug = pkOr(folder.slug, "");
      if (folder.publishedAt != null) {
        h("div", attr("class", "mg-meta st-publish"), [
          htext("public at "),
          h("a", attr("href", "/reading/${slug}"), htext("/reading/${slug}")),
          "\n",
          h("button", "${attr("phx-click", "unpublish")}${attr("class", "mg-btn sm ml-2")}", htext("Make private")),
        ])
      } else {
        h("div", attr("class", "mg-meta st-publish"), [
          h("button", "${attr("phx-click", "publish")}${attr("data-confirm", "Publish this stack? Anyone with the link will be able to read the telling and every step of it.")}${attr("class", "mg-btn sm")}", htext("Publish")),
          "\n",
          h("span", attr("class", "ml-2"), htext("private — only you can read it")),
        ])
      }
    }

    let pkStoryCard(state: PagesStacksShowState): List<AnyValue> {
      let story = state.story;
      if (story != null) { pkStoryCardOf(state, story) } else { [] }
    }

    let pkStoryCardOf(state: PagesStacksShowState, story: StackStory): List<AnyValue> {
      let left: List<AnyValue> = if (story.uncovered.length > 0) {
        [h("span", attr("class", "cut-err"), htext("· ${story.uncovered.length.toString()} steps left out")), "\n"]
      } else { [] };
      let stale: List<AnyValue> = if (!state.storyCurrent) {
        h("span", attr("class", "cut-err"), htext("· stale"))
      } else { [] };
      h("div", attr("class", "st-story-card"), [
        h("div", attr("class", "mg-label"), htext("The telling")),
        h("a", "${attr("href", "/stacks/${state.folder.id.toString()}/story")}${attr("class", "t")}", htext(pkOr(story.title, ""))),
        h("div", attr("class", "mg-meta"), [
          htext("${story.movements.length.toString()} parts"), "\n", left, stale,
        ]),
        pkPublishBlock(state),
      ])
    }

    let pkRevisedBy(step: StackStep): List<AnyValue> {
      let by = step.revisedBy;
      if (by != null) { h("span", attr("class", "dep rev"), htext("revised by ${by.toString()}")) } else { [] }
    }

    let pkChainItem(folderId: Int, e: StackGuideEntry): List<AnyValue> {
      let step = e.step;
      let needs: List<AnyValue> = if (e.requires.length > 0) {
        let ordinals = e.requires.map { (s: StackStep): String => s.ordinal.toString() };
        [h("span", attr("class", "dep"), htext("needs ${sysJoin(ordinals, ", ")}")), "\n"]
      } else { [] };
      let revised = pkRevisedBy(step);
      h("li", "${attr("id", "step-${step.ordinal.toString()}")}${attr("class", if (step.pitfall != null) { "has-pitfall" } else { "" })}", [
        h("a", attr("href", "/stacks/${folderId.toString()}/${step.ordinal.toString()}"), [
          h("span", attr("class", "n"), htext(step.ordinal.toString())),
          h("span", attr("class", "c"), htext(pkOr(step.capability, ""))),
        ]),
        "\n", needs, revised,
      ])
    }

    let pkRead(state: PagesStacksShowState): List<AnyValue> {
      let folderId = state.folder.id;
      let deepenedNote: List<AnyValue> = if (state.stats.deepened == 0) {
        h("span", "", htext("The second pass adds how each one works, what to get right now, and where a later step walks it back — none of which the first pass can see."))
      } else { [] };
      [
        pkStoryCard(state),
        h("h2", attr("class", "cut-h"), htext("The method")),
        h("ol", attr("class", "st-chain"), state.guide.map { (e: StackGuideEntry): List<AnyValue> => pkChainItem(folderId, e) }),
        h("p", attr("class", "mg-meta mt-5"), [
          htext("Start at step 1. Every step links back to what it stands on and forward to what stands on it."), "\n",
          deepenedNote,
        ]),
      ]
    }

    export let renderStacksFolder(ctx: Ctx, state: PagesStacksShowState): List<AnyValue> {
      let body = if (state.guide.length == 0) { pkUnread(state) } else { pkRead(state) };
      h("div", attr("class", "mx-auto max-w-3xl px-6 py-10"), [
        h("div", attr("class", "mg-meta"), h("a", attr("href", "/stacks"), htext("← every method"))),
        h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "mt-2 text-2xl font-semibold tracking-tight")}", htext(state.folder.name)),
        pkStatsLine(state.stats),
        pkButtons(state),
        pkComposingNote(state),
        pkProgressBar(state),
        body,
      ])
    }

## The step page

A step, with what it stands on and what stands on it. `""` is as present as
any other text: a step whose mechanism is the empty string still shows its
heading, as `:if={@entry.step.mechanism}` did.

    let pkChain(folderId: Int, items: List<StackStep>): List<AnyValue> {
      h("ul", attr("class", "st-links"), items.map { (s: StackStep): List<AnyValue> =>
        h("li", attr("id", "link-${s.ordinal.toString()}"),
          h("a", attr("href", "/stacks/${folderId.toString()}/${s.ordinal.toString()}"), [
            h("span", attr("class", "n"), htext(s.ordinal.toString())),
            htext(pkOr(s.capability, "")),
          ]))
      })
    }

    let pkSection(title: String, inner: List<AnyValue>): List<AnyValue> {
      h("div", "", [h("h2", attr("class", "cut-h"), htext(title)), inner])
    }

    let pkExcerpt(i: Int, x: StackExcerpt): List<AnyValue> {
      let caption: List<AnyValue> = if (x.caption != "") {
        h("figcaption", "", htext(x.caption))
      } else { [] };
      h("figure", "${attr("id", "excerpt-${i.toString()}")}${attr("class", "st-excerpt")}", [
        h("pre", "", h("code", "", htext(x.text))),
        caption,
      ])
    }

    let pkExcerpts(step: StackStep): List<AnyValue> {
      if (step.excerpts.length == 0) { return []; }
      let figures = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < step.excerpts.length) {
        figures.add(pkExcerpt(i, step.excerpts[i]));
        i += 1;
      }
      pkSection("From the document", figures.toList())
    }

    let pkRevision(folderId: Int, step: StackStep): List<AnyValue> {
      let by = step.revisedBy;
      if (by != null) {
        pkSection("A later step walks this back", [
          h("p", attr("class", "st-pitfall"), htext(pkOr(step.revision, ""))),
          h("blockquote", attr("class", "st-quote"), htext(pkOr(step.revisionQuote, ""))),
          h("p", attr("class", "mg-meta mt-1"), h("a", attr("href", "/stacks/${folderId.toString()}/${by.toString()}"), htext("read step ${by.toString()} →"))),
        ])
      } else { [] }
    }

    let pkText(title: String, cls: String, text: String?): List<AnyValue> {
      if (text != null) {
        pkSection(title, h("p", attr("class", cls), htext(text)))
      } else { [] }
    }

    let pkPitfall(step: StackStep): List<AnyValue> {
      let p = step.pitfall;
      if (p != null) {
        pkSection("Why the obvious version is wrong", [
          h("p", attr("class", "st-pitfall"), htext(p)),
          h("blockquote", attr("class", "st-quote"), htext(pkOr(step.pitfallQuote, ""))),
        ])
      } else { [] }
    }

    let pkNeighbours(folderId: Int, entry: StackGuideEntry): List<AnyValue> {
      let prev = entry.previous;
      let next = entry.next;
      let before: List<AnyValue> = if (prev != null) {
        h("a", attr("href", "/stacks/${folderId.toString()}/${prev.ordinal.toString()}"), htext("← ${pkOr(prev.capability, "")}"))
      } else { h("span", "", []) };
      let after: List<AnyValue> = if (next != null) {
        h("a", "${attr("href", "/stacks/${folderId.toString()}/${next.ordinal.toString()}")}${attr("class", "next")}", htext("${pkOr(next.capability, "")} →"))
      } else { [] };
      h("nav", attr("class", "st-nav"), [before, "\n", after])
    }

    let pkStepWork(step: StackStep): List<AnyValue> throws Bubble {
      let w = step.work;
      if (w != null) {
        h("div", attr("class", "mg-meta"), [
          htext("from "),
          h("a", attr("href", "/works/${w.slug}"), htext(w.title)),
        ])
      } else {
        console.log("pages_stacks: step ${step.ordinal.toString()} has no work");
        bubble()
      }
    }

    let pkStepBody(state: PagesStacksShowState, entry: StackGuideEntry): List<AnyValue> throws Bubble {
      let step = entry.step;
      let folderId = state.folder.id;
      let needs: List<AnyValue> = if (entry.requires.length > 0) {
        pkSection("You need these first", pkChain(folderId, entry.requires))
      } else { [] };
      let makes: List<AnyValue> = if (entry.requiredBy.length > 0) {
        pkSection("What this makes possible", pkChain(folderId, entry.requiredBy))
      } else { [] };
      [
        h("div", attr("class", "st-step-head"), [
          h("span", attr("class", "n"), htext("Step ${step.ordinal.toString()} of ${state.stats.read.toString()}")),
          h("h1", attr("style", "font-family:var(--mg-serif)"), htext(pkOr(step.capability, ""))),
          pkStepWork(step),
        ]),
        h("h2", attr("class", "cut-h"), htext("What to do")),
        h("p", attr("class", "st-lesson"), htext(pkOr(step.lesson, ""))),
        pkText("How it works", "st-lesson", step.mechanism),
        pkText("Get this right now", "st-watch", step.watchFor),
        pkRevision(folderId, step),
        pkPitfall(step),
        pkExcerpts(step),
        needs, makes,
        pkNeighbours(folderId, entry),
      ]
    }

    let pkEntryOf(state: PagesStacksShowState, ordinal: Int): StackGuideEntry? {
      var found: StackGuideEntry? = null;
      for (let e of state.guide) {
        if (e.step.ordinal == ordinal) { found = e; }
      }
      found
    }

    export let renderStacksStep(ctx: Ctx, state: PagesStacksShowState, ordinal: Int): List<AnyValue> throws Bubble {
      let entry = pkEntryOf(state, ordinal);
      let inner: List<AnyValue> = if (entry != null) {
        pkStepBody(state, entry)
      } else {
        h("p", attr("class", "mg-empty mt-8"), htext("No step ${ordinal.toString()} here."))
      };
      h("div", attr("class", "mx-auto max-w-2xl px-6 py-10"), [
        h("div", attr("class", "mg-meta"), h("a", attr("href", "/stacks/${state.folder.id.toString()}"), htext("← ${state.folder.name}"))),
        inner,
      ])
    }

    export let renderStacksShow(ctx: Ctx, state: PagesStacksShowState): List<AnyValue> throws Bubble {
      let n = state.ordinal;
      if (n != null) { renderStacksStep(ctx, state, n) } else { renderStacksFolder(ctx, state) }
    }

## A pass that ended since the page last looked

The LiveView put the flash up when `{:run, :done | :crashed, ...}` arrived. The
page holds what it last saw of the run in the UI state (`pkFlashDue`), and a
run that has ended since is worded by `stacksFlashFor`. A run that ended
without a kind in its detail (a job whose process was killed, found by
`runsReclaim`) is the same crash without the name of the pass.

    let pkRunMark(run: Run?): String {
      if (run != null) { "${pkOr(run.startedAt, "")}|${run.status}" } else { "none" }
    }

    let pkRunFlash(run: Run): StackFlash? {
      let detail = pkOr(run.detail, "");
      if (run.status == "crashed" && detail.split("|").length < 2) {
        new StackFlash("error", "The pass crashed. What finished is saved.")
      } else {
        stacksFlashFor(run.status, run.detail)
      }
    }

Looks at the run, puts the flash if one is due, and remembers what it saw.

    let pkNoteRun(ctx: Ctx, folderId: Int, run: Run?): Void throws Bubble {
      let uiKey = "stacks:run:${folderId.toString()}";
      let seen = uiGet(ctx, uiKey);
      let mark = pkRunMark(run);
      if (run != null) {
        if (pkFlashDue(seen, mark, !run.isRunning())) {
          let flash = pkRunFlash(run);
          if (flash != null) { webPutFlash(ctx, flash.level, flash.text); }
        }
      }
      pkRemember(ctx, uiKey, mark);
    }

## Answering

The folder of the route, or null: the id is read strictly as an integer, and
a folder that is not the user's is as absent as one that is not there.

    let pkFolderOf(ctx: Ctx, idText: String): Folder? throws Bubble {
      let id = foldersParseId(idText);
      if (id != null) { foldersGetFolderOrNull(ctx.db, ctx.scope, id) } else { null }
    }

    let pkNoFolder(ctx: Ctx): Response throws Bubble {
      webRedirect(ctx, "/stacks", new Pair("error", "No such folder."))
    }

`String.to_integer` raised for a segment that was not one (a 500). So does
this, with the segment in the log.

    let pkOrdinalOf(text: String): Int throws Bubble {
      let n = do { text.toInt32() } orelse -1000000007;
      if (n == -1000000007) {
        console.log("pages_stacks: ${text} is not a step number");
        bubble()
      }
      n
    }

The page, re-read from the database: the run first (a pass found dead is given
up on), then the flash it is owed, then the state.

    let pkShowReply(ctx: Ctx, folder: Folder, ordinal: Int?, flash: Pair<String, String>?): Response throws Bubble {
      let run = pagesStacksRunOf(ctx, stacksRunKey(folder.id));
      pkNoteRun(ctx, folder.id, run);
      let fresh = pkFolderOf(ctx, folder.id.toString());
      let current = if (fresh != null) { fresh } else { folder };
      let state = loadStacksShow(ctx, current, ordinal, run);
      pkRender(ctx, current.name, renderStacksShow(ctx, state), flash, pkPoll(state))
    }

GET `/stacks/:id` and `/stacks/:id/:ordinal`.

    export let pagesStacksShowPage(ctx: Ctx, idText: String, ordinalText: String?): Response throws Bubble {
      let folder = pkFolderOf(ctx, idText);
      if (folder != null) {
        let at = if (ordinalText != null) { pkOrdinalOf(ordinalText) } else { null };
        pkShowReply(ctx, folder, at, null)
      } else {
        pkNoFolder(ctx)
      }
    }

## Events

`publish` is an explicit act, and the folder has to belong to the account this
deploy belongs to (`foldersPublishAsOwner`).

    let pkPublish(ctx: Ctx, folder: Folder): Pair<String, String> throws Bubble {
      let r = foldersPublishAsOwner(ctx.db, ctx.scope, accountsOwner(ctx.db), folder.id);
      let published = r.folder;
      if (published != null) {
        new Pair("info", "Published at /reading/${pkOr(published.slug, "")}")
      } else if (r.error == "not_owner") {
        new Pair("error", "Only the account this deploy belongs to can publish.")
      } else {
        new Pair("error", "Could not publish: :${pkOr(r.error, "unknown")}")
      }
    }

    let pkUnpublish(ctx: Ctx, folder: Folder): Pair<String, String> throws Bubble {
      let r = foldersUnpublish(ctx.db, ctx.scope, folder.id);
      if (r.ok) {
        new Pair("info", "Taken off the public site.")
      } else {
        new Pair("error", "Could not unpublish: :${pkOr(r.error, "unknown")}")
      }
    }

How much work the pass starts out with, as the page showed it: documents for
the read, the steps for the second pass, the ones not yet summarised or
mapped. The composition and the relation have no count of their own.

    let pkTotalFor(kind: String, stats: StackStats): Int {
      if (kind == "read") {
        stats.documents
      } else if (kind == "deepen") {
        stats.read
      } else if (kind == "summarise") {
        stats.documents - stats.summarised
      } else if (kind == "read_each") {
        stats.documents - stats.mapped
      } else {
        0
      }
    }

    let pkAlready(other: String): Pair<String, String> {
      pkFlashPair(stacksAlreadyRunning(if (other == "") { "background" } else { other }))
    }

A pass. If one is going the answer is the flash and the run untouched; else the
job is started and the page shows it at once.

    let pkPass(
      ctx: Ctx, folder: Folder, kind: String,
      pass: fn (Ctx, String, Folder, Int): Boolean throws Bubble,
    ): Response throws Bubble {
      let run = pagesStacksRunOf(ctx, stacksRunKey(folder.id));
      let going = stacksRunView(run);
      if (going != null) {
        return pkShowReply(ctx, folder, null, pkAlready(going.kind));
      }
      let total = pkTotalFor(kind, stacksStats(ctx.db, ctx.scope, folder.id));
      let started = pass(ctx, kind, folder, total);
      if (started) {
        pkShowReply(ctx, folder, null, null)
      } else {
        let now = stacksRunView(pagesStacksRunOf(ctx, stacksRunKey(folder.id)));
        pkShowReply(ctx, folder, null, pkAlready(if (now != null) { now.kind } else { "" }))
      }
    }

    export let pagesStacksShowEvent(
      ctx: Ctx, match: Match, event: String, payload: JsonObject,
      pass: fn (Ctx, String, Folder, Int): Boolean throws Bubble,
    ): Response throws Bubble {
      let found = pkFolderOf(ctx, match.params.getOr("id", ""));
      if (found != null) { pkShowEventFor(ctx, found, event, pass) } else { pkNoFolder(ctx) }
    }

    let pkShowEventFor(
      ctx: Ctx, folder: Folder, event: String,
      pass: fn (Ctx, String, Folder, Int): Boolean throws Bubble,
    ): Response throws Bubble {
      if (event == "publish") {
        pkShowReply(ctx, folder, null, pkPublish(ctx, folder))
      } else if (event == "unpublish") {
        pkShowReply(ctx, folder, null, pkUnpublish(ctx, folder))
      } else if (event == "read" || event == "deepen" || event == "summarise" || event == "read_each" || event == "relate" || event == "compose") {
        pkPass(ctx, folder, event, pass)
      } else {
        pkUnhandledEvent("/stacks/:id", event)
      }
    }
