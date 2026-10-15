# The Trace view (not built yet)

OWNED BY THE VIEWS AGENT: replace this file. It is a stub that keeps the frame
building. `renderShowView` (`frame.temper.md`) calls `renderTraceView`, which
draws the inside of the view (spec section 3.16, `trace_pane/1`); the data it
needs is already loaded into `state` (`load.temper.md`: `events`, `eventStats`,
`graphBuilding`). The view is the deploy owner's: for anyone else `state.view`
is already `read`.

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");

    export let renderTraceView(ctx: Ctx, state: ShowState): List<AnyValue> {
      h("div", attr("class", "mg-view-todo"), [htext("trace is not built yet")])
    }
