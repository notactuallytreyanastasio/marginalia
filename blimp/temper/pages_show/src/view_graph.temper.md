# The Graph view

`graph_pane/1` (3.8): the knowledge graph, drawn by the `LaneTree` hook into
`#graph-svg` from the export the page carries in `data-graph`, with the node
under the pointer described in `#graph-detail`. The canvas is
`phx-update="ignore"`: the client owns what is inside it.

The header says what the graph holds, offers the build to the draft's owner
(and says "building the decision graph…" while its run is going, which the
frame's poll keeps fresh) and links the two downloads. Pressing Build is the
`build_graph` event (`events_read.temper.md`).

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");
    let { sysStringReplace } = import("sys/src");
    let { GraphStats } = import("analysis/src");

## The export, compacted

`state.graphJson` is the pretty-printed export `graph.json` downloads. The
Elixir put the compact encoding in `data-graph`; on a draft of a few hundred
nodes the indentation is a fifth of the attribute. A pretty printer's
newlines are always followed by an even run of spaces, and a newline inside a
string value is the two characters backslash and n, so these replacements
touch nothing but layout. The longest run goes first.

    let pvCompact(pretty: String): String {
      let a = sysStringReplace(pretty, "\n        ", "");
      let b = sysStringReplace(a, "\n      ", "");
      let c = sysStringReplace(b, "\n    ", "");
      let d = sysStringReplace(c, "\n  ", "");
      sysStringReplace(d, "\n", "")
    }

## The header

    let pvStats(stats: GraphStats?): List<AnyValue> {
      if (stats != null) {
        h("span", attr("class", "mg-meta"),
          htext("${stats.nodes.toString()} nodes · ${stats.edges.toString()} edges · ${stats.anchored.toString()} anchored"))
      } else { [] }
    }

    let pvBuild(state: ShowState): List<AnyValue> {
      if (state.graphBuilding) {
        h("span", attr("class", "text-[0.75rem] italic text-[var(--mg-dim)]"), htext("building the decision graph…"))
      } else if (state.mine) {
        h("button", "${attr("class", "mg-btn sm")}${attr("phx-click", "build_graph")}", htext("Build decision graph"))
      } else {
        h("span", "", [])
      }
    }

## The legend

    let pvSwatch(kind: String, colour: String): List<AnyValue> {
      h("span", attr("id", "legend-${kind}"), [
        h("i", attr("style", "background:${colour}"), []),
        htext(kind),
      ])
    }

## The canvas

Neither the canvas nor the detail panel is drawn until the tab has loaded its
export (`graphJson` is null on every other view).

    let pvCanvas(json: String?): List<AnyValue> {
      if (json != null) {
        pvCanvasOf(json)
      } else { [] }
    }

    let pvCanvasOf(json: String): List<AnyValue> {
      h("div", "${attr("class", "mg-card mg-graph mt-3.5")}${attr("style", "height:calc(100vh - 17rem); min-height:26rem")}", [
        h("div", "${attr("id", "graph-canvas")}${attr("phx-hook", "LaneTree")}${attr("phx-update", "ignore")}${attr("data-graph", pvCompact(json))}${attr("class", "mg-graph-canvas")}", [
          h("svg", attr("id", "graph-svg"), []),
        ]),
        h("div", "${attr("class", "mg-graph-detail")}${attr("id", "graph-detail")}", [
          h("p", attr("class", "mg-empty"), htext("Pick a node to see what it says and why it is there.")),
        ]),
      ])
    }

## The view

    export let renderGraphView(ctx: Ctx, state: ShowState): List<AnyValue> {
      let slug = state.work.slug;
      h("div", "", [
        h("div", attr("class", "flex items-baseline gap-3 flex-wrap"), [
          h("h2", attr("class", "mg-label"), htext("Knowledge graph")),
          pvStats(state.graphStats),
          h("div", attr("class", "ml-auto flex gap-2 items-baseline"), [
            pvBuild(state),
            h("a", "${attr("href", "/works/${slug}/graph.json")}${attr("class", "mg-btn sm ghost")}", htext("graph.json")),
            h("a", "${attr("href", "/works/${slug}/graph.dot")}${attr("class", "mg-btn sm ghost")}", htext("graph.dot")),
          ]),
        ]),
        h("div", attr("class", "mt-2.5 flex items-baseline gap-4 flex-wrap"), [
          h("div", attr("class", "mg-legend"), [
            pvSwatch("goal", "#8a3324"),
            pvSwatch("option", "#b45309"),
            pvSwatch("decision", "#1e3a8a"),
            pvSwatch("action", "#166534"),
            pvSwatch("outcome", "#0891b2"),
            pvSwatch("observation", "#6b665e"),
            pvSwatch("revisit", "#7c2d92"),
          ]),
          h("span", attr("class", "mg-hint mt-0"), htext("solid = leads to · dotted = develops / pays off / requires / tension")),
        ]),
        pvCanvas(state.graphJson),
      ])
    }
