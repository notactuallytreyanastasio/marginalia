# The Changes view (not built yet)

OWNED BY THE VIEWS AGENT: replace this file. It is a stub that keeps the frame
building. `renderShowView` (`frame.temper.md`) calls `renderChangesView`, which
draws the inside of the view (spec section 3.9, `changes_pane/1`); the data it
needs is already loaded into `state` (`load.temper.md`: `diffRows`, `diffStat`,
`revisions`, newest first). `renderDiffTable` and `renderWordSpans`
(`components.temper.md`) draw the split view and the word diffs;
`showAnyChange(rows)` is `Diff.any?/1`.

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");

    export let renderChangesView(ctx: Ctx, state: ShowState): List<AnyValue> {
      h("div", attr("class", "mg-view-todo"), [htext("changes is not built yet")])
    }
