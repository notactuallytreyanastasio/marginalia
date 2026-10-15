# The Prompts view (not built yet)

OWNED BY THE VIEWS AGENT: replace this file. It is a stub that keeps the frame
building. `renderShowView` (`frame.temper.md`) calls `renderPromptsView`, which
draws the inside of the view (spec section 3.17, `prompts_pane/1`); the data it
needs is already loaded into `state` (`load.temper.md`: `passes`, the read's,
the decision graph's and the rewrite's, and `modes`, the chat's stances). The
view is the deploy owner's: for anyone else `state.view` is already `read`.

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");

    export let renderPromptsView(ctx: Ctx, state: ShowState): List<AnyValue> {
      h("div", attr("class", "mg-view-todo"), [htext("prompts is not built yet")])
    }
