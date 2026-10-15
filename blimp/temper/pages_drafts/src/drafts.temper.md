# Drafts: /drafts and /drafts/:slug

`DraftLive.Index` and `DraftLive.Show`. The owner's works, read by anybody.
"Public drafts" is every work the owner has, the documents that belong to
cases included: nothing filters on `collection` (notes/web-public.md section
13, item 6). A visitor's own upload is never listed or served here:
`worksPublicDraft` is scoped to the owner's `user_id`.

    let { Ctx, webMeta, webPage } = import("webcore/src");
    let { Response } = import("http/src");
    let { h, htext, hraw, attr } = import("html/src");
    let { Work, worksPublicDrafts, worksPublicDraft, worksRevisionCount } = import("works/src");
    let {
      ReadingSection, ReadingBlock, ReadingNote, readingPage, readingNoOptions, readingRenderBlock,
    } = import("reading/src");

## GET /drafts

`{@total} drafts` is not singularised (`1 drafts`): kept. `d.status` is the
work's status string.

    export class DraftsIndexState(public drafts: List<Work>) {}

    export let loadDraftsIndex(ctx: Ctx): DraftsIndexState throws Bubble {
      new DraftsIndexState(worksPublicDrafts(ctx.db, pdOwnerId(ctx)))
    }

    let pdDraftRow(d: Work): List<AnyValue> {
      h("li", "", [
        h("a", "${attr("href", "/drafts/${d.slug}")}${attr("class", "t")}", htext(d.title)),
        h("p", attr("class", "mg-meta"), htext("${d.wordCount.toString()} words · ${d.status}")),
      ])
    }

    export let renderDraftsIndex(ctx: Ctx, state: DraftsIndexState): List<AnyValue> {
      let drafts = state.drafts;
      [
        h("div", attr("class", "lx"), [
          h("h1", "", htext("Drafts")),
          h("p", attr("class", "lede"), htext("${drafts.length.toString()} drafts, read end to end. Each one carries the notes that came out of reading it, in the margin beside the sentence that caused them.")),
          if (drafts.length == 0) {
            h("p", attr("class", "mg-empty"), htext("Nothing here yet."))
          } else { [] },
          h("ul", attr("class", "mg-rows"), drafts.map { (d: Work): List<AnyValue> => pdDraftRow(d) }),
        ]),
      ]
    }

    export let pagesDraftsIndexPage(ctx: Ctx): Response throws Bubble {
      webPage(
        ctx,
        pdMeta("Drafts", "Drafts read end to end, with the notes that came out of reading them.", "index, follow"),
        renderDraftsIndex(ctx, loadDraftsIndex(ctx)),
        null, "app",
      )
    }

## GET /drafts/:slug

The page is `Reading.page(work)` with no options: every beat of the draft's own
graph is a note (stale ones included), and so is every connection that starts
at a beat with a section. Notes whose quote is in no paragraph are dropped
silently.

    export class DraftShowState(
      public work: Work,
      public page: List<ReadingSection>,
      public changed: Int,
    ) {}

    export let loadDraftShow(ctx: Ctx, work: Work): DraftShowState throws Bubble {
      new DraftShowState(
        work,
        readingPage(ctx.db, work, readingNoOptions()),
        worksRevisionCount(ctx.db, work.id),
      )
    }

`1 change since it arrived`, `3 changes since it arrived`, once there is
something to show.

    let pdChangedLink(work: Work, changed: Int): List<AnyValue> {
      if (changed > 0) {
        h("span", "", [
          " · ",
          h("a", attr("href", "/drafts/${work.slug}/changes"), htext("${changed.toString()} change${pdS(changed)} since it arrived")),
        ])
      } else { [] }
    }

`mg-sum-text` shows the section summary if the section has one; an empty one
still renders (an empty string is truthy in the HEEx).

    let pdSectionHead(sec: ReadingSection): List<AnyValue> {
      let summary = sec.section.summary;
      h("div", attr("class", "mg-read-head"), [
        h("div", attr("class", "mg-label"), htext("Section ${sec.section.ordinal.toString()}")),
        h("h2", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-[1.45rem] font-semibold mt-1")}", htext(sec.section.title)),
        if (summary != null) {
          h("div", attr("class", "mg-sum-text"), htext(summary))
        } else { [] },
      ])
    }

The block is trusted HTML: it came out of the Markdown step.

    let pdBlock(b: ReadingBlock): List<AnyValue> {
      h("div", "${attr("class", "mg-block")}${attr("id", "block-${b.ref}")}", hraw(readingRenderBlock(b.text, b.mark, b.ref, null)))
    }

    let pdSectionBody(sec: ReadingSection): List<AnyValue> {
      [
        pdSectionHead(sec),
        sec.blocks.map { (b: ReadingBlock): List<AnyValue> => pdBlock(b) },
      ]
    }

One margin note. There is no hook on this page: nothing measures the rail or
levels a note with its mark, so the rail is a plain column and every note of
every section stacks from the top, in document order (notes/web-public.md
section 13, item 3). `data-anchor` is there all the same, as it was.

    let pdNote(b: ReadingBlock, n: ReadingNote): List<AnyValue> {
      let body = n.body;
      h("div", "${attr("class", "mg-note-slot ${n.kind}")}${attr("data-anchor", b.ref)}",
        h("div", attr("class", "mg-note ${n.kind}"), [
          h("span", attr("class", "who"), htext(pdSpaced(n.kind))),
          h("span", attr("class", "said"), htext(n.title)),
          if (body != null) {
            h("span", attr("class", "why"), htext(body))
          } else { [] },
        ]))
    }

    let pdBlockNotes(b: ReadingBlock): List<AnyValue> {
      b.notes.map { (n: ReadingNote): List<AnyValue> => pdNote(b, n) }
    }

    let pdSectionNotes(sec: ReadingSection): List<AnyValue> {
      sec.blocks.map { (b: ReadingBlock): List<AnyValue> => pdBlockNotes(b) }
    }

    export let renderDraftShow(ctx: Ctx, state: DraftShowState): List<AnyValue> {
      let work = state.work;
      [
        h("div", attr("class", "mx-auto max-w-5xl px-6 py-8"), [
          h("div", attr("class", "mg-meta"),
            h("a", attr("href", "/drafts"), htext("← Drafts"))),
          h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-2xl font-semibold tracking-tight mt-2")}", htext(work.title)),
          h("p", attr("class", "mg-meta"), [
            htext("${work.wordCount.toString()} words"),
            pdChangedLink(work, state.changed),
          ]),
          h("div", attr("class", "mg-read mt-6"), [
            h("div", attr("class", "mg-read-body"),
              state.page.map { (sec: ReadingSection): List<AnyValue> => pdSectionBody(sec) }),
            h("div", attr("class", "mg-read-rail"),
              state.page.map { (sec: ReadingSection): List<AnyValue> => pdSectionNotes(sec) }),
          ]),
        ]),
      ]
    }

An unknown slug and somebody else's slug are the same answer: back to the list.
The description is the first impression, else the title, cut at 300.

    let pdShowFound(ctx: Ctx, work: Work): Response throws Bubble {
      let impression = work.firstImpression;
      let described = if (impression != null) { impression } else { work.title };
      webPage(
        ctx,
        pdMeta(work.title, pdSlice300(described), "index, follow"),
        renderDraftShow(ctx, loadDraftShow(ctx, work)),
        null, "app",
      )
    }

    export let pagesDraftsShowPage(ctx: Ctx, slug: String): Response throws Bubble {
      let work = worksPublicDraft(ctx.db, pdOwnerId(ctx), slug);
      if (work != null) {
        pdShowFound(ctx, work)
      } else {
        pdBackTo(ctx, "/drafts", "No such draft.")
      }
    }
