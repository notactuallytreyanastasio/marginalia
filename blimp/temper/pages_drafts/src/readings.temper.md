# Readings: /reading, /reading/:slug, /reading/:slug/:ordinal

`ReadingLive.Index`, `.Story` and `.Step`. A reading is a folder with
`published_at` set, a composed story and its steps. These pages need no owner
and no account; what the viewer is matters only for one line, shown to the
folder's writer and to nobody else, because a draft's slug is the permission to
read it and printing one on a public page gives it to everyone who opens the
page.

None of the three sets `page_robots`, `page_url` or an image.

    let { Ctx, webPage } = import("webcore/src");
    let { Response } = import("http/src");
    let { h, htext, hraw, attr } = import("html/src");
    let { Folder, foldersPublished, foldersPublishedBySlug } = import("folders/src");
    let { StackStep, StackStory, StoryMovement, StackExcerpt, StackGuideEntry, stacksSteps, stacksStory, stacksGuide } = import("stacks/src");
    let { Work, worksGetById } = import("works/src");

## GET /reading

Every published folder, newest published first, that has a composed story: a
folder with none is hidden.

    export class ReadingListed(public folder: Folder, public story: StackStory, public steps: Int) {}

    export class ReadingIndexState(public readings: List<ReadingListed>) {}

    export let loadReadingIndex(ctx: Ctx): ReadingIndexState throws Bubble {
      let out = new ListBuilder<ReadingListed>();
      for (let folder of foldersPublished(ctx.db)) {
        let story = stacksStory(ctx.db, folder);
        if (story != null) {
          out.add(new ReadingListed(folder, story, stacksSteps(ctx.db, folder).length));
        }
      }
      new ReadingIndexState(out.toList())
    }

    let pdReadingRow(r: ReadingListed): List<AnyValue> {
      h("li", attr("id", "reading-${r.folder.id.toString()}"), [
        h("a", "${attr("href", "/reading/${pdOr(r.folder.slug)}")}${attr("class", "t")}", htext(pdOr(r.story.title))),
        h("p", attr("class", "mg-meta"),
          htext("${r.steps.toString()} documents · ${r.story.movements.length.toString()} parts · ${r.folder.name}")),
      ])
    }

    export let renderReadingIndex(ctx: Ctx, state: ReadingIndexState): List<AnyValue> {
      [
        h("div", attr("class", "lx"), [
          h("h1", "", htext("Readings")),
          h("p", attr("class", "lede"), [
            "A series of documents read ",
            h("em", "", htext("forwards")),
            " — each one told only what the ones before it established. Read that way, each says what somebody building the same thing must now do, and no single document contains it.",
          ]),
          if (state.readings.length == 0) {
            h("p", attr("class", "mg-empty"), htext("Nothing published yet."))
          } else { [] },
          h("ul", attr("class", "mg-rows"), state.readings.map { (r: ReadingListed): List<AnyValue> => pdReadingRow(r) }),
        ]),
      ]
    }

    export let pagesDraftsReadingIndexPage(ctx: Ctx): Response throws Bubble {
      webPage(
        ctx,
        pdMeta("Readings", "Series of documents read forwards, so that what they add up to is a method somebody else can follow.", null),
        renderReadingIndex(ctx, loadReadingIndex(ctx)),
        null, "app",
      )
    }

## GET /reading/:slug

`mine?` is true when the folder has a user and it is the viewer's. The movements
are numbered from 1. The prose is Markdown with hard breaks: the model writes
Markdown whether or not anyone asked it to, and this prose is thick with
identifiers in backticks.

    export class ReadingStoryState(
      public folder: Folder,
      public story: StackStory,
      public steps: List<StackStep>,
      public count: Int,
      public mine: Boolean,
    ) {}

    export let loadReadingStory(ctx: Ctx, folder: Folder, story: StackStory): ReadingStoryState throws Bubble {
      let steps = stacksSteps(ctx.db, folder);
      let viewer = ctx.scope.user;
      let mine = if (viewer != null) { folder.userId == viewer.id } else { false };
      new ReadingStoryState(folder, story, steps, steps.length, mine)
    }

The link's `title`: the step's capability, or `step <n>` when there is no such
step (a step that exists with no capability has no title attribute).

    let pdStepTitle(steps: List<StackStep>, n: Int): String? {
      var i = 0;
      while (i < steps.length) {
        if (steps[i].ordinal == n) { return steps[i].capability; }
        i += 1;
      }
      "step ${n.toString()}"
    }

    let pdMovementStep(state: ReadingStoryState, n: Int): List<AnyValue> {
      h("a", "${attr("href", "/reading/${pdOr(state.folder.slug)}/${n.toString()}")}${attr("title", pdStepTitle(state.steps, n))}", htext(n.toString()))
    }

    let pdMovementNav(state: ReadingStoryState, m: StoryMovement): List<AnyValue> {
      if (m.steps.length > 0) {
        h("nav", attr("class", "st-move-steps"), [
          h("span", attr("class", "mg-label"), htext("from")),
          m.steps.map { (n: Int): List<AnyValue> => pdMovementStep(state, n) },
        ])
      } else { [] }
    }

    let pdMovement(state: ReadingStoryState, m: StoryMovement, i: Int): List<AnyValue> {
      h("section", attr("class", "st-move"), [
        h("h2", "", [
          h("span", attr("class", "n"), htext(i.toString())),
          htext(m.heading),
        ]),
        h("div", attr("class", "md st-md"), hraw(pdMarkdown(m.prose))),
        if (m.turn != "") {
          h("aside", attr("class", "st-turn md st-md"), hraw(pdMarkdown(m.turn)))
        } else { [] },
        pdMovementNav(state, m),
      ])
    }

    let pdMovements(state: ReadingStoryState): List<AnyValue> {
      let out = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < state.story.movements.length) {
        out.add(pdMovement(state, state.story.movements[i], i + 1));
        i += 1;
      }
      out.toList()
    }

The owner-only line. `Yours.` and a way into the folder.

    let pdYours(state: ReadingStoryState): List<AnyValue> {
      if (state.mine) {
        h("p", attr("class", "mg-meta st-yours"), [
          "Yours. ",
          h("a", attr("href", "/stacks/${state.folder.id.toString()}"), htext("Open the folder")),
          htext(" to read it forwards again, compose it again, or get at any of the ${state.count.toString()} drafts."),
        ])
      } else { [] }
    }

    export let renderReadingStory(ctx: Ctx, state: ReadingStoryState): List<AnyValue> {
      [
        h("article", attr("class", "st-story"), [
          h("div", attr("class", "mg-meta"),
            h("a", attr("href", "/reading"), htext("← Readings"))),
          h("h1", "", htext(pdOr(state.story.title))),
          h("p", attr("class", "mg-meta"), htext("${state.count.toString()} documents, read forwards. ${state.folder.name}")),
          pdYours(state),
          h("div", attr("class", "lede md st-md"), hraw(pdMarkdown(state.story.opening))),
          pdMovements(state),
          h("div", attr("class", "st-closing md st-md"), hraw(pdMarkdown(state.story.closing))),
        ]),
      ]
    }

The title is the story's, else the folder's name; the description is the first
300 characters of the opening.

    let pdStoryFound(ctx: Ctx, folder: Folder, story: StackStory): Response throws Bubble {
      let title = story.title;
      webPage(
        ctx,
        pdMeta(if (title != null) { title } else { folder.name }, pdSlice300(pdOr(story.opening)), null),
        renderReadingStory(ctx, loadReadingStory(ctx, folder, story)),
        null, "app",
      )
    }

    let pdStoryOf(ctx: Ctx, folder: Folder): Response throws Bubble {
      let story = stacksStory(ctx.db, folder);
      if (story != null) {
        pdStoryFound(ctx, folder, story)
      } else {
        pdBackTo(ctx, "/reading", "No such reading.")
      }
    }

    export let pagesDraftsReadingStoryPage(ctx: Ctx, slug: String): Response throws Bubble {
      let folder = foldersPublishedBySlug(ctx.db, slug);
      if (folder != null) {
        pdStoryOf(ctx, folder)
      } else {
        pdBackTo(ctx, "/reading", "No such reading.")
      }
    }

## GET /reading/:slug/:ordinal

The folder must be published, the ordinal must parse whole, and the guide must
hold a step of that ordinal; any failing is `No such step.` and the list. The
neighbours are found by ordinal arithmetic, so a gap in the ordinals gives no
link.

`source` is the draft the step was read out of, for the viewer who owns it and
for nobody else: the lookup is the owner's, so a stranger gets nothing and the
draft's slug is nowhere on the page.

    export class ReadingStepState(
      public folder: Folder,
      public entry: StackGuideEntry,
      public count: Int,
      public story: StackStory?,
      public source: Work?,
    ) {}

    let pdSourceFor(ctx: Ctx, step: StackStep): Work? throws Bubble {
      let viewer = ctx.scope.user;
      if (viewer != null) {
        let work = worksGetById(ctx.db, step.workId);
        if (work != null) {
          if (work.userId == viewer.id) { work } else { null }
        } else { null }
      } else { null }
    }

    export let loadReadingStep(ctx: Ctx, folder: Folder, entry: StackGuideEntry, count: Int): ReadingStepState throws Bubble {
      new ReadingStepState(folder, entry, count, stacksStory(ctx.db, folder), pdSourceFor(ctx, entry.step))
    }

A section whose field is not nil renders even when the field is empty (an
empty string is truthy in the HEEx); `pitfall` and the quotes are tested
against both nil and the empty string.

    let pdSection(label: String, cls: String?, body: String?): List<AnyValue> {
      if (body != null) {
        h("section", attr("class", cls), [
          h("h2", attr("class", "mg-label"), htext(label)),
          h("div", attr("class", "md st-md"), hraw(pdMarkdown(body))),
        ])
      } else { [] }
    }

    let pdQuote(quote: String?): List<AnyValue> {
      if (quote != null && quote != "") {
        h("blockquote", "", htext(pdOr(quote)))
      } else { [] }
    }

    let pdPitfall(step: StackStep): List<AnyValue> {
      let pitfall = step.pitfall;
      if (pitfall != null && pitfall != "") {
        h("section", attr("class", "st-pitfall"), [
          h("h2", attr("class", "mg-label"), htext("The obvious version is wrong")),
          h("div", attr("class", "md st-md"), hraw(pdMarkdown(pitfall))),
          pdQuote(step.pitfallQuote),
        ])
      } else { [] }
    }

    let pdRevision(step: StackStep): List<AnyValue> {
      let by = step.revisedBy;
      if (by != null) {
        h("section", attr("class", "st-revision"), [
          h("h2", attr("class", "mg-label"), htext("Walked back by step ${by.toString()}")),
          h("div", attr("class", "md st-md"), hraw(pdMarkdown(step.revision))),
          pdQuote(step.revisionQuote),
        ])
      } else { [] }
    }

`text` is the passage the quote was located in, not the model's quote.

    let pdExcerpt(e: StackExcerpt): List<AnyValue> {
      h("figure", attr("class", "st-excerpt"), [
        h("pre", "", h("code", "", htext(e.text))),
        if (e.caption != "") {
          h("figcaption", "", htext(e.caption))
        } else { [] },
      ])
    }

    let pdExcerpts(step: StackStep): List<AnyValue> {
      if (step.excerpts.length > 0) {
        h("section", "", [
          h("h2", attr("class", "mg-label"), htext("From the document")),
          step.excerpts.map { (e: StackExcerpt): List<AnyValue> => pdExcerpt(e) },
        ])
      } else { [] }
    }

    let pdStepLink(folder: Folder, ordinal: Int, text: String): List<AnyValue> {
      h("a", attr("href", "/reading/${pdOr(folder.slug)}/${ordinal.toString()}"), htext(text))
    }

    let pdStandsOn(state: ReadingStepState): List<AnyValue> {
      if (state.entry.requires.length > 0) {
        h("nav", attr("class", "st-move-steps"), [
          h("span", attr("class", "mg-label"), htext("stands on")),
          state.entry.requires.map { (r: StackStep): List<AnyValue> => pdStepLink(state.folder, r.ordinal, r.ordinal.toString()) },
        ])
      } else { [] }
    }

    let pdPrevNext(state: ReadingStepState): List<AnyValue> {
      let prev = state.entry.previous;
      let next = state.entry.next;
      h("nav", attr("class", "st-nav"), [
        if (prev != null) {
          pdStepLink(state.folder, prev.ordinal, "← ${prev.ordinal.toString()}. ${pdOr(prev.capability)}")
        } else { [] },
        if (next != null) {
          pdStepLink(state.folder, next.ordinal, "${next.ordinal.toString()}. ${pdOr(next.capability)} →")
        } else { [] },
      ])
    }

The writer's line: the draft the step was read out of, with the one link that
lets them in.

    let pdSourceLine(state: ReadingStepState): List<AnyValue> {
      let source = state.source;
      if (source != null) {
        h("p", attr("class", "mg-meta st-yours"), [
          "Read out of ",
          h("a", attr("href", "/works/${source.slug}?view=read"), htext(source.title)),
          htext(", which is yours to edit."),
        ])
      } else { [] }
    }

    let pdBackLabel(state: ReadingStepState): String {
      let story = state.story;
      if (story != null) {
        let title = story.title;
        if (title != null) { title } else { state.folder.name }
      } else { state.folder.name }
    }

    export let renderReadingStep(ctx: Ctx, state: ReadingStepState): List<AnyValue> {
      let step = state.entry.step;
      [
        h("article", attr("class", "st-step"), [
          h("div", attr("class", "mg-meta"),
            h("a", attr("href", "/reading/${pdOr(state.folder.slug)}"), htext("← ${pdBackLabel(state)}"))),
          h("span", attr("class", "n"), htext("Step ${step.ordinal.toString()} of ${state.count.toString()}")),
          h("h1", "", htext(pdOr(step.capability))),
          pdSourceLine(state),
          pdSection("What to do", null, step.lesson),
          pdSection("How it works", null, step.mechanism),
          pdPitfall(step),
          pdSection("Get right now", null, step.watchFor),
          pdRevision(step),
          pdExcerpts(step),
          pdStandsOn(state),
          pdPrevNext(state),
        ]),
      ]
    }

    let pdGuideEntry(guide: List<StackGuideEntry>, n: Int): StackGuideEntry? {
      var i = 0;
      while (i < guide.length) {
        if (guide[i].step.ordinal == n) { return guide[i]; }
        i += 1;
      }
      null
    }

    let pdStepFound(ctx: Ctx, folder: Folder, entry: StackGuideEntry, count: Int): Response throws Bubble {
      webPage(
        ctx,
        pdMeta(entry.step.capability, null, null),
        renderReadingStep(ctx, loadReadingStep(ctx, folder, entry, count)),
        null, "app",
      )
    }

    let pdStepOf(ctx: Ctx, folder: Folder, n: Int): Response throws Bubble {
      let guide = stacksGuide(ctx.db, folder.id);
      let entry = pdGuideEntry(guide, n);
      if (entry != null) {
        pdStepFound(ctx, folder, entry, guide.length)
      } else {
        pdBackTo(ctx, "/reading", "No such step.")
      }
    }

    export let pagesDraftsReadingStepPage(ctx: Ctx, slug: String, ordinal: String): Response throws Bubble {
      let folder = foldersPublishedBySlug(ctx.db, slug);
      if (folder != null) {
        pdStepOrdinal(ctx, folder, pdParseInt(ordinal))
      } else {
        pdBackTo(ctx, "/reading", "No such step.")
      }
    }

    let pdStepOrdinal(ctx: Ctx, folder: Folder, n: Int?): Response throws Bubble {
      if (n != null) {
        pdStepOf(ctx, folder, n)
      } else {
        pdBackTo(ctx, "/reading", "No such step.")
      }
    }
