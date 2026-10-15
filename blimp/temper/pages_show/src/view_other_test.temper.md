# Tests for the other views

Spine, Threads, Graph, Changes, Trace and Prompts: what each one draws from
the state the frame loaded, the ids the hooks and the morph key on, and who
sees which control.

    let { accountsOwnerEmail } = import("accounts/src");
    let { NodeParams, worksInsertNode, EventParams, worksRecordEvent } = import("works/src");

    let tvPage(w: TWorld, who: TWho, view: String): String throws Bubble {
      tBodyOf(tGet(w.db, who, tPath(w.work, view), tKeyed()))
    }

The text of the first attribute called `name` on the page.

    let tvAttr(html: String, name: String): String {
      let parts = html.split("${name}=\"");
      if (parts.length < 2) { return ""; }
      parts.getOr(1, "").split("\"").getOr(0, "")
    }

    let tvSpine(w: TWorld, title: String): GraphNode throws Bubble {
      tNode(w.db, w.work, "spine", title, null)
    }

## The Spine

    test("spine: the spine is numbered, in order, with the first impression above it") { test =>
      let w = tWorld();
      w.db.exec("UPDATE works SET first_impression = $1 WHERE id = $2", ["It circles one afternoon.", w.work.id.toString()]);
      tvSpine(w, "The watcher at the window");
      tvSpine(w, "The cold kettle");
      let html = tvPage(w, w.owner, "spine");
      expectHas(test, html, "<h2 class=\"mg-label\">First impression</h2>");
      expectHas(test, html, "It circles one afternoon.");
      expectHas(test, html, "<h2 class=\"mg-label mt-12\">The spine</h2>");
      expectHas(test, html, "The chain the whole draft hangs off, in order.");
      expectHas(test, html, "<span class=\"mg-meta mr-1.5\">01</span>The watcher at the window");
      expectHas(test, html, "<span class=\"mg-meta mr-1.5\">02</span>The cold kettle");
      expectHas(test, html, "class=\"mg-cards mt-5\"");
      w.db.close();
    }

    test("spine: with no first impression the heading has no gap above it") { test =>
      let w = tWorld();
      tvSpine(w, "The watcher");
      let html = tvPage(w, w.owner, "spine");
      expectHas(test, html, "<h2 class=\"mg-label\">The spine</h2>");
      expectLacks(test, html, "First impression");
      w.db.close();
    }

    test("spine: a draft with no spine says so") { test =>
      let w = tWorld();
      let html = tvPage(w, w.owner, "spine");
      expectHas(test, html, "No spine was produced for this draft.");
      expectLacks(test, html, "mg-cards");
      expectLacks(test, html, "Questions this raised");
      w.db.close();
    }

    test("spine: what the read left unfinished is said under the impression") { test =>
      let w = tWorld();
      w.db.exec("UPDATE works SET status_detail = $1 WHERE id = $2", ["The weave failed.", w.work.id.toString()]);
      expectHas(test, tvPage(w, w.owner, "spine"), "border-l-2 border-[var(--mg-accent)] pl-2.5 py-1 text-[var(--mg-dim)]\">The weave failed.</p>");
      w.db.close();
    }

    test("spine: the questions come after, without a number") { test =>
      let w = tWorld();
      tvSpine(w, "The watcher");
      tNode(w.db, w.work, "question", "Who is she waiting for?", null);
      let html = tvPage(w, w.owner, "spine");
      expectHas(test, html, "Questions this raised");
      expectHas(test, html, "Each names something specific in the draft.");
      expectHas(test, html, "Who is she waiting for?");
      expectInt(test, tCount(html, "mg-meta mr-1.5"), 1);
      w.db.close();
    }

    test("spine: every card has an id, and the owner's has a Discuss button for that node") { test =>
      let w = tWorld();
      let n = tvSpine(w, "The watcher");
      let html = tvPage(w, w.owner, "spine");
      expectHas(test, html, "id=\"grounded-${n.id.toString()}\"");
      expectHas(test, html, "phx-click=\"discuss_node\" phx-value-id=\"${n.id.toString()}\"");
      expectHas(test, html, "title=\"Open the chat holding this and everywhere it happens\">Discuss</button>");
      w.db.close();
    }

    test("spine: someone holding the link has no Discuss button") { test =>
      let w = tWorld();
      tvSpine(w, "The watcher");
      let html = tvPage(w, w.reader, "spine");
      expectHas(test, html, "The watcher");
      expectLacks(test, html, "discuss_node");
      w.db.close();
    }

    test("spine: a node with no beats says it is not linked") { test =>
      let w = tWorld();
      tvSpine(w, "The watcher");
      let html = tvPage(w, w.owner, "spine");
      expectHas(test, html, "not yet linked to anywhere in the draft");
      expectLacks(test, html, "class=\"mg-where\"");
      w.db.close();
    }

    test("spine: a node shows where it happens, with the beat's section and quote") { test =>
      let w = tWorld();
      let n = tvSpine(w, "The cold kettle");
      let b = tBeat(w.db, w.work, "The kettle goes cold");
      tEdge(w.db, w.work, n, b, "realises");
      let html = tvPage(w, w.owner, "spine");
      expectHas(test, html, "where it happens");
      expectHas(test, html, "id=\"hit-${n.id.toString()}-${b.id.toString()}\"");
      expectHas(test, html, "<span class=\"n\">1</span>");
      expectHas(test, html, "<span class=\"t\">The kettle goes cold</span>");
      expectHas(test, html, "<span class=\"q\">\"The kettle went cold on the counter\"</span>");
      expectLacks(test, html, "not yet linked");
      w.db.close();
    }

    test("spine: what the database holds is escaped") { test =>
      let w = tWorld();
      tvSpine(w, "<b>loud</b> & \"quiet\"");
      let html = tvPage(w, w.owner, "spine");
      expectHas(test, html, "&lt;b&gt;loud&lt;/b&gt; &amp; &quot;quiet&quot;");
      expectLacks(test, html, "<b>loud</b>");
      w.db.close();
    }

## The Threads

    test("threads: a draft with none says so") { test =>
      let w = tWorld();
      let html = tvPage(w, w.owner, "threads");
      expectHas(test, html, "<h2 class=\"mg-label\">Threads</h2>");
      expectHas(test, html, "Patterns that run across sections rather than happening in one.");
      expectHas(test, html, "No threads were identified.");
      w.db.close();
    }

    test("threads: each is a card, unnumbered, with a Discuss button") { test =>
      let w = tWorld();
      let t = tNode(w.db, w.work, "thread", "Things that go cold", null);
      tNode(w.db, w.work, "thread", "People who do not move", null);
      let html = tvPage(w, w.owner, "threads");
      expectHas(test, html, "Things that go cold");
      expectHas(test, html, "People who do not move");
      expectHas(test, html, "class=\"mg-cards mt-5\"");
      expectHas(test, html, "id=\"grounded-${t.id.toString()}\"");
      expectLacks(test, html, "mg-meta mr-1.5");
      expectInt(test, tCount(html, "phx-click=\"discuss_node\""), 2);
      expectLacks(test, html, "No threads were identified.");
      w.db.close();
    }

    test("threads: the spine's nodes are not here") { test =>
      let w = tWorld();
      tvSpine(w, "The watcher");
      expectLacks(test, tvPage(w, w.owner, "threads"), "The watcher");
      w.db.close();
    }

## The Graph

    test("graph: the canvas carries the export for the hook, compact") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "The kettle goes cold");
      let html = tvPage(w, w.owner, "graph");
      expectHas(test, html, "<h2 class=\"mg-label\">Knowledge graph</h2>");
      expectHas(test, html, "id=\"graph-canvas\" phx-hook=\"LaneTree\" phx-update=\"ignore\" data-graph=\"");
      expectHas(test, html, "class=\"mg-graph-canvas\"><svg id=\"graph-svg\"></svg></div>");
      expectHas(test, html, "id=\"graph-detail\"");
      expectHas(test, html, "Pick a node to see what it says and why it is there.");
      let data = tvAttr(html, "data-graph");
      expectHas(test, data, "&quot;nodes&quot;");
      expectHas(test, data, "The kettle goes cold");
      expectHas(test, data, "&quot;metadata_json&quot;");
      expectLacks(test, data, "\n");
      expectLacks(test, data, "  ");
      w.db.close();
    }

    test("graph: the header counts what the graph holds") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "The kettle goes cold");
      expectHas(test, tvPage(w, w.owner, "graph"), "1 nodes · 0 edges · 1 anchored");
      w.db.close();
    }

    test("graph: an empty draft still draws the canvas, and says 0 nodes") { test =>
      let w = tWorld();
      let html = tvPage(w, w.owner, "graph");
      expectHas(test, html, "0 nodes · 0 edges · 0 anchored");
      expectHas(test, html, "id=\"graph-canvas\"");
      w.db.close();
    }

    test("graph: the legend names the seven kinds, the hint says what the lines mean") { test =>
      let w = tWorld();
      let html = tvPage(w, w.owner, "graph");
      expectHas(test, html, "<span id=\"legend-goal\"><i style=\"background:#8a3324\"></i>goal</span>");
      expectHas(test, html, "<span id=\"legend-revisit\"><i style=\"background:#7c2d92\"></i>revisit</span>");
      expectInt(test, tCount(html, "id=\"legend-"), 7);
      expectHas(test, html, "solid = leads to · dotted = develops / pays off / requires / tension");
      w.db.close();
    }

    test("graph: the two downloads are links") { test =>
      let w = tWorld();
      let html = tvPage(w, w.owner, "graph");
      expectHas(test, html, "href=\"/works/${w.work.slug}/graph.json\" class=\"mg-btn sm ghost\">graph.json</a>");
      expectHas(test, html, "href=\"/works/${w.work.slug}/graph.dot\" class=\"mg-btn sm ghost\">graph.dot</a>");
      w.db.close();
    }

    test("graph: the owner is offered the build, and a link-holder is not") { test =>
      let w = tWorld();
      let mine = tvPage(w, w.owner, "graph");
      expectHas(test, mine, "phx-click=\"build_graph\"");
      expectHas(test, mine, "Build decision graph");
      let theirs = tvPage(w, w.reader, "graph");
      expectLacks(test, theirs, "build_graph");
      expectHas(test, theirs, "id=\"graph-canvas\"");
      w.db.close();
    }

    test("graph: while the build runs the button gives way to a line saying so") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPath(w.work, "graph"), "build_graph", "{}", tQueue());
      let html = tvPage(w, w.owner, "graph");
      expectHas(test, html, "building the decision graph…");
      expectLacks(test, html, "phx-click=\"build_graph\"");
      w.db.close();
    }

    test("graph: it is not drawn on the other tabs") { test =>
      let w = tWorld();
      expectLacks(test, tvPage(w, w.owner, "read"), "graph-canvas");
      expectLacks(test, tvPage(w, w.owner, "spine"), "graph-canvas");
      w.db.close();
    }

## The Changes

    test("changes: an untouched draft asked for the tab says so rather than erroring") { test =>
      let w = tWorld();
      let html = tvPage(w, w.owner, "changes");
      expectHas(test, html, "Changes since it arrived");
      expectHas(test, html, "Nothing has changed yet. Edits and applied rewrites show up here.");
      expectLacks(test, html, "Every change, newest first");
      expectLacks(test, html, "mg-diff-cols");
      w.db.close();
    }

    test("changes: the old and the new are both on the page") { test =>
      let w = tWorld();
      tEdit(w.db, w.work, "kettle", "AMENDED");
      let html = tvPage(w, w.owner, "changes");
      expectHas(test, html, "As it arrived");
      expectHas(test, html, "<span>As it arrived</span><span>Now</span>");
      expectHas(test, html, "AMENDED");
      expectHas(test, html, "1 edited · 0 added · 0 removed");
      expectHas(test, html, "class=\"mg-diff-cols\"");
      expectHas(test, html, "class=\"w del\"");
      expectHas(test, html, "class=\"w ins\"");
      expectLacks(test, html, "Nothing has changed yet");
      w.db.close();
    }

    test("changes: the log names where each change came from, newest first") { test =>
      let w = tWorld();
      tEdit(w.db, w.work, "kettle", "AMENDED");
      let html = tvPage(w, w.owner, "changes");
      expectHas(test, html, "Every change, newest first");
      expectHas(test, html, "rewrite — cuts the gloss · section 1");
      expectHas(test, html, "<ol class=\"mg-rows\">");
      expectHas(test, html, "class=\"mg-diff-patch\"");
      expectHas(test, html, "<li id=\"rev-");
      w.db.close();
    }

    test("changes: a link-holder sees them too") { test =>
      let w = tWorld();
      tEdit(w.db, w.work, "kettle", "AMENDED");
      expectHas(test, tvPage(w, w.reader, "changes"), "Every change, newest first");
      w.db.close();
    }

## The Trace

    let tvBoss(w: TWorld): TWho throws Bubble { tWho(w.db, accountsOwnerEmail()) }

    let tvEvent(
      w: TWorld, narrative: String, seq: Int, tool: String, args: String, result: String, ok: Boolean,
    ): Void throws Bubble {
      let p = new EventParams(w.work.id, tool);
      p.narrative = narrative;
      p.seq = seq;
      p.args = args;
      p.result = result;
      p.ok = ok;
      worksRecordEvent(w.db, p);
    }

    let tvCalls(w: TWorld): Void throws Bubble {
      tvEvent(w, "The Window", 0, "add_node", "{\"type\":\"goal\",\"title\":\"Establish the watcher\"}", "{\"id\":1}", true);
      tvEvent(w, "The Window", 1, "link", "{\"from\":1,\"to\":2}", "{\"error\":\"goal -> decision is the flow rule\"}", false);
      tvEvent(w, "The Door", 2, "set_status", "{\"id\":3,\"status\":\"done\"}", "{\"ok\":true}", true);
      tvEvent(w, "The Door", 3, "link", "{\"from\":2,\"to\":4,\"rationale\":\"because\"}", "{\"ok\":true}", true);
    }

    test("trace: each tool call is a line, and the refusals are flagged with their reason") { test =>
      let w = tWorld();
      tvCalls(w);
      let html = tvPage(w, tvBoss(w), "trace");
      expectHas(test, html, "<h2 class=\"mg-label\">Build trace</h2>");
      expectHas(test, html, "4 tool calls · 1 refused");
      expectHas(test, html, "goal  Establish the watcher");
      expectHas(test, html, "1 → 2");
      expectHas(test, html, "2 → 4  (because)");
      expectHas(test, html, "3 → done");
      expectHas(test, html, "class=\"call no\"");
      expectHas(test, html, "<span class=\"why\">↳ goal -&gt; decision is the flow rule</span>");
      expectInt(test, tCount(html, "class=\"call no\""), 1);
      expectInt(test, tCount(html, "class=\"call\""), 3);
      w.db.close();
    }

    test("trace: consecutive calls under one narrative are one block with its label") { test =>
      let w = tWorld();
      tvCalls(w);
      let html = tvPage(w, tvBoss(w), "trace");
      expectInt(test, tCount(html, "class=\"mg-label mb-1\""), 2);
      expectHas(test, html, "class=\"mg-label mb-1\">The Window</div>");
      expectHas(test, html, "class=\"mg-label mb-1\">The Door</div>");
      expectHas(test, html, "class=\"mg-trace mt-4\"");
      expectHas(test, html, "<span class=\"seq\">0</span><span class=\"tool\">add_node</span>");
      w.db.close();
    }

    test("trace: the kinds of refusal are badges with their counts") { test =>
      let w = tWorld();
      tvCalls(w);
      let html = tvPage(w, tvBoss(w), "trace");
      expectHas(test, html, "class=\"mg-badge accent\"");
      expectHas(test, html, "flow rule × 1");
      w.db.close();
    }

    test("trace: a call of another kind is the first 160 characters of its arguments") { test =>
      let w = tWorld();
      tvEvent(w, "Odd", 0, "frobnicate", "{\"a\":\"${tWords(60)}\"}", "{}", true);
      let html = tvPage(w, tvBoss(w), "trace");
      expectHas(test, html, "{&quot;a&quot;:&quot;word word");
      expectLacks(test, html, tRepeat("word ", 40));
      w.db.close();
    }

    test("trace: an answer that is not JSON is shown as it is, cut at 200 characters") { test =>
      let w = tWorld();
      tvEvent(w, "Odd", 0, "link", "{\"from\":1,\"to\":2}", "plain refusal text", false);
      expectHas(test, tvPage(w, tvBoss(w), "trace"), "↳ plain refusal text");
      w.db.close();
    }

    test("trace: with nothing recorded it says so, and the download is still offered") { test =>
      let w = tWorld();
      let html = tvPage(w, tvBoss(w), "trace");
      expectHas(test, html, "Nothing recorded yet. Build the decision graph from the Graph tab and this fills in live.");
      expectHas(test, html, "href=\"/works/${w.work.slug}/trace.json\" class=\"mg-btn sm ghost\">trace.json</a>");
      expectLacks(test, html, "tool calls");
      expectLacks(test, html, "building…");
      w.db.close();
    }

    test("trace: the hint names the three calls and the flow rule") { test =>
      let w = tWorld();
      let html = tvPage(w, tvBoss(w), "trace");
      expectHas(test, html, "<code>add_node</code>, <code>link</code> and <code>set_status</code>");
      expectHas(test, html, "<code>goal → option → decision → action → outcome</code>");
      w.db.close();
    }

    test("trace: while the graph builds it says so") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPath(w.work, "graph"), "build_graph", "{}", tQueue());
      expectHas(test, tvPage(w, tvBoss(w), "trace"), "building…");
      w.db.close();
    }

## The Prompts

    test("prompts: every pass is shown with its model, cadence and prompt") { test =>
      let w = tWorld();
      let html = tvPage(w, tvBoss(w), "prompts");
      expectHas(test, html, "<h2 class=\"mg-label\">How the graph was built</h2>");
      expectHas(test, html, "The exact prompts that ran against your draft");
      expectTrue(test, tCount(html, "id=\"pass-") >= 5, "five passes at least");
      expectHas(test, html, "produces ");
      expectHas(test, html, "<pre class=\"mt-2.5 text-[0.74rem] leading-relaxed whitespace-pre-wrap");
      w.db.close();
    }

    test("prompts: the three chat stances follow, each with its blurb and its text") { test =>
      let w = tWorld();
      let html = tvPage(w, tvBoss(w), "prompts");
      expectHas(test, html, "<h2 class=\"mg-label mt-12\">How the chat is steered</h2>");
      expectHas(test, html, "id=\"mode-read\"");
      expectHas(test, html, "id=\"mode-provoke\"");
      expectHas(test, html, "id=\"mode-bounce\"");
      expectHas(test, html, "<span class=\"font-normal text-[var(--mg-dim)]\">— Pressure-test an idea against the draft</span>");
      w.db.close();
    }
