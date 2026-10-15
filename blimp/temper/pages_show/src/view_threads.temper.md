# The Threads view

`map_view/1`, the `:threads` branch: the patterns that run across sections
rather than happening in one, each drawn as the Spine's cards are
(`showGroundedNode`, `view_spine.temper.md`), without a number.

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");

    export let renderThreadsView(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      let body: List<AnyValue> = if (state.threads.length == 0) {
        h("p", attr("class", "mg-empty mt-4"), htext("No threads were identified."))
      } else {
        let cards = new ListBuilder<List<AnyValue>>();
        var i = 0;
        while (i < state.threads.length) {
          cards.add(showGroundedNode(ctx, state, state.threads[i], ""));
          i += 1;
        }
        h("div", attr("class", "mg-cards mt-5"), cards.toList())
      };
      [
        h("h2", attr("class", "mg-label"), htext("Threads")),
        h("p", attr("class", "mg-hint"), htext("Patterns that run across sections rather than happening in one.")),
        body,
      ]
    }
