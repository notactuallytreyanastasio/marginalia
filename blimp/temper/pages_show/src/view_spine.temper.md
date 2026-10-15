# The Spine view (not built yet)

OWNED BY THE VIEWS AGENT: replace this file. It is a stub that keeps the frame
building. `renderShowView` (`frame.temper.md`) calls `renderSpineView`, which
draws the inside of the view (spec section 3.5, `map_view/1`, the `:spine`
branch, with `grounded_node/1` of 3.6); the data it needs is already loaded
into `state` (`load.temper.md`: `spine`, `questions`, `work.firstImpression`).

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");

    export let renderSpineView(ctx: Ctx, state: ShowState): List<AnyValue> {
      h("div", attr("class", "mg-view-todo"), [htext("spine is not built yet")])
    }
