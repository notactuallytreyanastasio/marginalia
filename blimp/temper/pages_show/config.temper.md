# pages_show

The work page, `/works/:slug`: a draft read with its notes in the margin, the
controls that start the read, the graph, the summaries and the rewrites, and
the seven views (read, graph, spine, threads, changes, trace, prompts) behind
one tab strip. `WorkLive.Show` of the Phoenix app, and the three guest
endpoints beside it (`graph.json`, `graph.dot`, `trace.json`).

The library is one frame that several authors fill in: `state.temper.md` holds
what the LiveView had in its assigns and loads it, `frame.temper.md` draws the
header, the tabs and the drawer, `read_view.temper.md` is the read view, and
one file per other view (`view_*.temper.md`, `chat.temper.md`) is a stub until
its owner replaces it.

    export let name = "pages_show";
