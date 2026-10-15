# The Graph view (not built yet)

OWNED BY THE VIEWS AGENT: replace this file. It is a stub that keeps the frame
building. `renderShowView` (`frame.temper.md`) calls `renderGraphView`, which
draws the inside of the view (spec section 3.8, `graph_pane/1`, with the
`LaneTree` hook); the data it needs is already loaded into `state`
(`load.temper.md`: `graphJson` (the pretty-printed export, which the page may
compact for `data-graph`), `graphStats`, `graphBuilding`). The Build button is
the `build_graph` event, answered in `events_read.temper.md`.

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");

    export let renderGraphView(ctx: Ctx, state: ShowState): List<AnyValue> {
      h("div", attr("class", "mg-view-todo"), [htext("graph is not built yet")])
    }
