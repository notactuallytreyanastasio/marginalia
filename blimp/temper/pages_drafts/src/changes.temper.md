# Changes: /drafts/:slug/changes

`DraftLive.Changes`. What the draft said when it arrived, beside what it says
now, one paragraph to a row; a paragraph that changed carries the word diff
inside it. Public: the claim on the front page that every change is kept was
unfalsifiable while the before and after lived behind a login.

The paragraph rows are `core`'s `rows(baseline, body)` (a longest common
subsequence over paragraphs, a rewrap not being an edit). The word diff is
`Rewrite.diff`, run on each changed paragraph and on each revision, never on a
whole draft: a word diff of 2,000 words takes seconds in the interpreter
(PLAN section 6a).

    let { Ctx, webPage } = import("webcore/src");
    let { Response } = import("http/src");
    let { h, htext, attr } = import("html/src");
    let { Row, Part, rows } = import("core/src");
    let { Work, Revision, worksPublicDraft, worksBaseline, worksRevisions } = import("works/src");
    let { rewriteDiff } = import("reading/src");

## State

`stat` counts `same`, `changed`, `added` and `removed` rows; `Diff.any?` is
true when some row is not `same`. `revisions` are newest first.

    export class ChangesStat(public same: Int, public changed: Int, public added: Int, public removed: Int) {}

    export class DraftChangesState(
      public work: Work,
      public rows: List<Row>,
      public stat: ChangesStat,
      public revisions: List<Revision>,
    ) {}

    let pdChangesStat(xs: List<Row>): ChangesStat {
      var same = 0;
      var changed = 0;
      var added = 0;
      var removed = 0;
      for (let r of xs) {
        if (r.kind == "same") { same += 1; } else if (r.kind == "change") { changed += 1; } else if (r.kind == "ins") { added += 1; } else if (r.kind == "del") { removed += 1; }
      }
      new ChangesStat(same, changed, added, removed)
    }

    let pdChangesAny(xs: List<Row>): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i].kind != "same") { return true; }
        i += 1;
      }
      false
    }

    let pdNewestFirst(xs: List<Revision>): List<Revision> {
      let out = new ListBuilder<Revision>();
      var i = xs.length - 1;
      while (i >= 0) {
        out.add(xs[i]);
        i -= 1;
      }
      out.toList()
    }

    export let loadDraftChanges(ctx: Ctx, work: Work): DraftChangesState throws Bubble {
      let diffRows = rows(worksBaseline(ctx.db, work), work.body);
      new DraftChangesState(work, diffRows, pdChangesStat(diffRows), pdNewestFirst(worksRevisions(ctx.db, work.id)))
    }

## Render

`klass(op, side)`: a word is `w`, a deleted word is struck on the old side
(`w del`) and hidden on the new, an inserted word is hidden on the old side
and highlighted on the new (`w ins`). Each span holds one token with its
trailing whitespace, and nothing sits between spans.

    let pdWordClass(op: String, side: String): String {
      if (op == "del") {
        if (side == "old") { "w del" } else { "w hide" }
      } else if (op == "ins") {
        if (side == "old") { "w hide" } else { "w ins" }
      } else { "w" }
    }

    let pdWordSpan(p: Part, side: String): List<AnyValue> {
      h("span", attr("class", pdWordClass(p.kind, side)), htext(p.text))
    }

    let pdWords(parts: List<Part>, side: String): List<AnyValue> {
      parts.map { (p: Part): List<AnyValue> => pdWordSpan(p, side) }
    }

One row. A `same` row shows the earlier version's text on both sides.

    let pdDiffRow(r: Row): List<AnyValue> {
      let left = pdOr(r.left);
      let right = pdOr(r.right);
      let cls = "mg-diff-row ${r.kind}";
      if (r.kind == "same") {
        h("div", attr("class", cls), [
          h("div", attr("class", "side old"), htext(left)),
          h("div", attr("class", "side new"), htext(left)),
        ])
      } else if (r.kind == "change") {
        let parts = rewriteDiff(left, right);
        h("div", attr("class", cls), [
          h("div", attr("class", "side old"), pdWords(parts, "old")),
          h("div", attr("class", "side new"), pdWords(parts, "new")),
        ])
      } else if (r.kind == "del") {
        h("div", attr("class", cls), [
          h("div", attr("class", "side old gone"), htext(left)),
          h("div", attr("class", "side new empty"), []),
        ])
      } else {
        h("div", attr("class", cls), [
          h("div", attr("class", "side old empty"), []),
          h("div", attr("class", "side new fresh"), htext(right)),
        ])
      }
    }

    let pdDiffColumns(xs: List<Row>): List<AnyValue> {
      if (pdChangesAny(xs)) {
        h("div", attr("class", "mg-diff-cols"), [
          h("div", attr("class", "mg-diff-colhead"), [
            h("span", "", htext("As it arrived")),
            h("span", "", htext("Now")),
          ]),
          xs.map { (r: Row): List<AnyValue> => pdDiffRow(r) },
        ])
      } else { [] }
    }

`{rev.origin}{if rev.note, do: " — #{rev.note}"} · section {rev.section_ordinal}`.
The patch is drawn with the `new` side: the after text with insertions
highlighted, and the deleted words in the page but hidden (`w hide`), so a
deletion is never visible there (notes/web-public.md section 13, item 10).
A revision with no section prints `section ` and nothing.

    let pdRevisionLine(rev: Revision): String {
      let note = rev.note;
      let noted = if (note != null) { " — ${note}" } else { "" };
      let ordinal = rev.sectionOrdinal;
      let section = if (ordinal != null) { ordinal.toString() } else { "" };
      "${rev.origin}${noted} · section ${section}"
    }

    let pdRevisionItem(rev: Revision): List<AnyValue> {
      h("li", "", [
        h("span", attr("class", "n"), htext(rev.seq.toString())),
        " ",
        h("span", attr("class", "mg-meta"), htext(pdRevisionLine(rev))),
        h("div", attr("class", "mg-diff-patch"), pdWords(rewriteDiff(rev.before, rev.after), "new")),
      ])
    }

    let pdRevisionLog(xs: List<Revision>): List<AnyValue> {
      if (xs.length > 0) {
        h("div", attr("class", "mg-diff-log"), [
          h("div", attr("class", "mg-label"), htext("Every change, newest first")),
          h("ol", attr("class", "mg-rows"), xs.map { (rev: Revision): List<AnyValue> => pdRevisionItem(rev) }),
        ])
      } else { [] }
    }

    export let renderDraftChanges(ctx: Ctx, state: DraftChangesState): List<AnyValue> {
      let work = state.work;
      let stat = state.stat;
      [
        h("div", attr("class", "mg-diff"), [
          h("div", attr("class", "mg-meta"),
            h("a", attr("href", "/drafts/${work.slug}"), htext("← ${work.title}"))),
          h("div", attr("class", "mg-diff-head"), [
            h("span", attr("class", "mg-label"), htext("Changes since it arrived")),
            h("span", attr("class", "mg-meta ml-auto"),
              htext("${stat.changed.toString()} edited · ${stat.added.toString()} added · ${stat.removed.toString()} removed")),
          ]),
          if (!pdChangesAny(state.rows)) {
            h("p", attr("class", "mg-empty"), htext("Nothing has been changed yet."))
          } else { [] },
          pdDiffColumns(state.rows),
          pdRevisionLog(state.revisions),
        ]),
      ]
    }

## GET /drafts/:slug/changes

    let pdChangesFound(ctx: Ctx, work: Work): Response throws Bubble {
      webPage(
        ctx,
        pdMeta("${work.title} — what changed", "Every change made to this draft, as a before and after.", "index, follow"),
        renderDraftChanges(ctx, loadDraftChanges(ctx, work)),
        null, "app",
      )
    }

    export let pagesDraftsChangesPage(ctx: Ctx, slug: String): Response throws Bubble {
      let work = worksPublicDraft(ctx.db, pdOwnerId(ctx), slug);
      if (work != null) {
        pdChangesFound(ctx, work)
      } else {
        pdBackTo(ctx, "/drafts", "No such draft.")
      }
    }
