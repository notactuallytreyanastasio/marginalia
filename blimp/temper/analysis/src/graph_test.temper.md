# Tests for the graph export

`graph.json`, `graph.dot`, `trace.json`, the stats and the download name,
each compared byte for byte with the text `Marginalia.Graph` and
`GraphController` produce. In the expected text `'` stands for `"` and `^` for
`\"`, so a JSON line reads like JSON.

    let { Db } = import("db/src");
    let {
      Work, Section, GraphNode, NodeParams, EventParams, worksInsertNodes, worksInsertNode, worksLink,
      worksRecordEvent, worksUpdateWork, workParams,
    } = import("works/src");
    let { sysJoin, sysStringReplace } = import("sys/src");
    let { parseJson, JsonObject } = import("std/json");

    let gx(s: String): String {
      sysStringReplace(sysStringReplace(s, "'", "\""), "^", "\\\"")
    }

    let gxLines(lines: List<String>): String {
      gx(sysJoin(lines, "\n"))
    }

    let stampedFixture(): AnFx throws Bubble {
      let fx = fxWith("Export Me", "# One\n\nShe kept them in the freezer, which she never explained to anyone.\n");
      let work = fx.work;
      let section = fx.sections[0];
      let trunk = new NodeParams(work.id, "spine", "The trunk");
      trunk.body = "the body";
      worksInsertNodes(fx.db, work.id, null, [trunk]);
      let beat = new NodeParams(work.id, "beat", "A \"quoted\" beat");
      beat.sectionId = section.id;
      beat.quote = "She kept them in the freezer";
      worksInsertNodes(fx.db, work.id, section.id, [beat]);
      let option = new NodeParams(work.id, "option", "Option");
      option.body = "why";
      option.quote = "a\nb";
      option.narrative = "one";
      option.status = "chosen";
      option.ordinal = 3;
      worksInsertNode(fx.db, option);
      worksLink(fx.db, work.id, 1, 2, "leads_to", 0, null);
      worksLink(fx.db, work.id, 2, 3, "follows", 1, "why it");
      fx.db.exec("UPDATE nodes SET inserted_at = '2026-10-14 09:12:04'", []);
      fx.db.exec("UPDATE edges SET inserted_at = '2026-10-14 09:12:05'", []);
      fx
    }

## graph.json

    test("graph.json is Jason's pretty output, key for key") { test =>
      let fx = stampedFixture();
      let w = reloaded(fx.db, fx.work);
      let title = fx.sections[0].title;
      let want = gxLines([
        "{",
        "  'edges': [",
        "    {",
        "      'created_at': '2026-10-14T09:12:05Z',",
        "      'edge_type': 'leads_to',",
        "      'from_node_id': 1,",
        "      'id': 1,",
        "      'rationale': null,",
        "      'to_node_id': 2,",
        "      'weight': 1.0",
        "    },",
        "    {",
        "      'created_at': '2026-10-14T09:12:05Z',",
        "      'edge_type': 'follows',",
        "      'from_node_id': 2,",
        "      'id': 2,",
        "      'rationale': 'why it',",
        "      'to_node_id': 3,",
        "      'weight': 1.0",
        "    }",
        "  ],",
        "  'node_themes': [],",
        "  'nodes': [",
        "    {",
        "      'body': 'the body',",
        "      'created_at': '2026-10-14T09:12:04Z',",
        "      'description': 'the body',",
        "      'id': 1,",
        "      'marginalia_type': 'spine',",
        "      'metadata_json': '{^anchored^:false,^branch^:^spine^,^narrative^:null,^ordinal^:0,^section^:null,^status^:^pending^}',",
        "      'narrative': null,",
        "      'node_type': 'goal',",
        "      'quote': null,",
        "      'section': null,",
        "      'section_ordinal': null,",
        "      'status': 'pending',",
        "      'title': 'The trunk'",
        "    },",
        "    {",
        "      'body': null,",
        "      'created_at': '2026-10-14T09:12:04Z',",
        "      'description': 'Sources:\\n\\n- ^She kept them in the freezer^',",
        "      'id': 2,",
        "      'marginalia_type': 'beat',",
        "      'metadata_json': '{^anchored^:true,^branch^:^section-1^,^narrative^:null,^ordinal^:0,^section^:^${title}^,^status^:^pending^}',",
        "      'narrative': null,",
        "      'node_type': 'action',",
        "      'quote': 'She kept them in the freezer',",
        "      'section': '${title}',",
        "      'section_ordinal': 1,",
        "      'status': 'pending',",
        "      'title': 'A ^quoted^ beat'",
        "    },",
        "    {",
        "      'body': 'why',",
        "      'created_at': '2026-10-14T09:12:04Z',",
        "      'description': 'why\\n\\nSources:\\n\\n- ^a b^',",
        "      'id': 3,",
        "      'marginalia_type': 'option',",
        "      'metadata_json': '{^anchored^:true,^branch^:^options^,^narrative^:^one^,^ordinal^:3,^section^:null,^status^:^chosen^}',",
        "      'narrative': 'one',",
        "      'node_type': 'option',",
        "      'quote': 'a\\nb',",
        "      'section': null,",
        "      'section_ordinal': null,",
        "      'status': 'chosen',",
        "      'title': 'Option'",
        "    }",
        "  ],",
        "  'themes': [],",
        "  'work': {",
        "    'exported_at': '2026-10-14T10:00:00.000000Z',",
        "    'first_impression': null,",
        "    'id': ${w.id.toString()},",
        "    'intent': null,",
        "    'sections': 1,",
        "    'status': 'pending',",
        "    'title': 'Export Me',",
        "    'words': ${w.wordCount.toString()}",
        "  }",
        "}",
      ]);
      expectText(test, graphJsonAt(fx.db, w, "2026-10-14T10:00:00.000000Z"), want);
    }

    test("an empty graph is empty lists and an object of the work") { test =>
      let fx = fxWith("Empty", "# One\n\nSome words here to read.\n");
      let w = reloaded(fx.db, fx.work);
      let want = gxLines([
        "{",
        "  'edges': [],",
        "  'node_themes': [],",
        "  'nodes': [],",
        "  'themes': [],",
        "  'work': {",
        "    'exported_at': 'T',",
        "    'first_impression': null,",
        "    'id': ${w.id.toString()},",
        "    'intent': null,",
        "    'sections': 1,",
        "    'status': 'pending',",
        "    'title': 'Empty',",
        "    'words': ${w.wordCount.toString()}",
        "  }",
        "}",
      ]);
      expectText(test, graphJsonAt(fx.db, w, "T"), want);
    }

    test("the work block carries intent and first impression when there are some") { test =>
      let fx = fxWith("Told", "# One\n\nSome words here to read.\n");
      let p = workParams("Told", "# One\n\nSome words here to read.\n");
      p.intent = "Make a \"point\"";
      p.firstImpression = "It waits.";
      let w = worksUpdateWork(fx.db, fx.work, p).ok;
      expectTrue(test, w != null, "updated");
      if (w != null) {
        let text = graphJsonAt(fx.db, w, "T");
        expectHas(test, text, gx("    'first_impression': 'It waits.',\n"));
        expectHas(test, text, gx("    'intent': 'Make a ^point^',\n"));
      }
    }

    test("graph.json parses and has the five top-level keys") { test =>
      let fx = stampedFixture();
      let tree = parseJson(graphJson(fx.db, reloaded(fx.db, fx.work)));
      let top = if (tree is JsonObject) { sysJoin(anKeys(tree), ",") } else { "" };
      expectText(test, top, "edges,node_themes,nodes,themes,work");
    }

    test("the export time has microsecond precision and a Z") { test =>
      let t = graphNow();
      expectInt(test, anCodePoints(t), 27);
      expectText(test, anSliceCp(t, 10, 11), "T");
      expectText(test, anSliceCp(t, 19, 27), ".000000Z");
      expectText(test, graphIso("2026-10-14 09:12:04"), "2026-10-14T09:12:04Z");
    }

    test("a quote with no body is the whole description, and no quote is the body") { test =>
      let n = new GraphNode(1, 1, null, "beat", "t", null, "q\nr", 0, "pending", null, "x", "x");
      expectText(test, orNull(graphDescription(n)), "Sources:\n\n- \"q r\"");
      let m = new GraphNode(1, 1, null, "beat", "t", "body", "", 0, "pending", null, "x", "x");
      expectText(test, orNull(graphDescription(m)), "body");
      let k = new GraphNode(1, 1, null, "beat", "t", null, null, 0, "pending", null, "x", "x");
      expectText(test, orNull(graphDescription(k)), "<null>");
    }

    test("the deciduous names for the read's own types") { test =>
      expectText(test, graphDeciduousType("spine"), "goal");
      expectText(test, graphDeciduousType("beat"), "action");
      expectText(test, graphDeciduousType("thread"), "observation");
      expectText(test, graphDeciduousType("question"), "decision");
      expectText(test, graphDeciduousType("option"), "option");
      expectText(test, graphDeciduousType("note"), "note");
    }

## graph.dot

    test("graph.dot lists nodes then edges, solid only for follows") { test =>
      let fx = stampedFixture();
      let want = gxLines([
        "digraph marginalia {",
        "  rankdir=TB;",
        "  node [shape=box, style=rounded];",
        "  n1 [label='The trunk', color='#8a3324'];",
        "  n2 [label='A ^quoted^ beat', color='#166534'];",
        "  n3 [label='Option', color='#b45309'];",
        "  n1 -> n2 [style=dashed, label='leads_to'];",
        "  n2 -> n3 [style=solid, label='follows'];",
        "}",
      ]);
      expectText(test, graphDot(fx.db, fx.work), want);
    }

    test("an empty graph is the three header lines and a brace, with no trailing newline") { test =>
      let fx = fxWith("Empty", "# One\n\nSome words here to read.\n");
      expectText(test, graphDot(fx.db, fx.work), "digraph marginalia {\n  rankdir=TB;\n  node [shape=box, style=rounded];\n}");
    }

    test("a label is escaped, one line, and cut to 90 after escaping") { test =>
      expectText(test, graphEscape("a\\b\"c\nd"), "a\\\\b\\\"c d");
      expectText(test, graphEscape(repeated("x", 100)), repeated("x", 90));
      expectText(test, graphEscape(repeated("\"", 60)), repeated("\\\"", 45));
    }

    test("every colour of the table") { test =>
      expectText(test, graphColour("goal"), "#8a3324");
      expectText(test, graphColour("option"), "#b45309");
      expectText(test, graphColour("decision"), "#1e3a8a");
      expectText(test, graphColour("action"), "#166534");
      expectText(test, graphColour("outcome"), "#0891b2");
      expectText(test, graphColour("observation"), "#6b665e");
      expectText(test, graphColour("revisit"), "#7c2d92");
      expectText(test, graphColour("spine"), "#8a3324");
      expectText(test, graphColour("beat"), "#166534");
      expectText(test, graphColour("thread"), "#0891b2");
      expectText(test, graphColour("question"), "#7c2d92");
      expectText(test, graphColour("note"), "#9a948a");
    }

## stats

    test("stats count nodes, edges, anchored nodes and types") { test =>
      let fx = stampedFixture();
      let s = graphStats(fx.db, fx.work);
      expectInt(test, s.nodes, 3);
      expectInt(test, s.edges, 2);
      expectInt(test, s.anchored, 2);
      expectInt(test, s.byType.getOr("spine", 0), 1);
      expectInt(test, s.byType.getOr("beat", 0), 1);
      expectInt(test, s.byType.getOr("option", 0), 1);
      expectInt(test, s.byType.getOr("goal", 0), 0);
    }

## trace.json

    test("trace.json carries the events with their args and results parsed") { test =>
      let fx = fxWith("Traced", "# One\n\nSome words here to read.\n");
      let a = new EventParams(fx.work.id, "add_node");
      a.narrative = "one";
      a.args = "{\"title\":\"G\"}";
      a.result = "{\"id\":3}";
      a.nodeId = 3;
      worksRecordEvent(fx.db, a);
      let b = new EventParams(fx.work.id, "link");
      b.seq = 1;
      b.args = "not json";
      worksRecordEvent(fx.db, b);
      let c = new EventParams(fx.work.id, "link");
      c.seq = 2;
      c.args = "[1,2.5,true,null,\"s\"]";
      c.result = "{\"error\":\"the flow rule: x\"}";
      c.ok = false;
      worksRecordEvent(fx.db, c);
      fx.db.exec("UPDATE graph_events SET inserted_at = '2026-10-14 09:12:04'", []);
      let w = reloaded(fx.db, fx.work);
      let want = gxLines([
        "{",
        "  'events': [",
        "    {",
        "      'args': {",
        "        'title': 'G'",
        "      },",
        "      'at': '2026-10-14T09:12:04Z',",
        "      'narrative': 'one',",
        "      'ok': true,",
        "      'result': {",
        "        'id': 3",
        "      },",
        "      'seq': 0,",
        "      'tool': 'add_node'",
        "    },",
        "    {",
        "      'args': 'not json',",
        "      'at': '2026-10-14T09:12:04Z',",
        "      'narrative': null,",
        "      'ok': true,",
        "      'result': null,",
        "      'seq': 1,",
        "      'tool': 'link'",
        "    },",
        "    {",
        "      'args': [",
        "        1,",
        "        2.5,",
        "        true,",
        "        null,",
        "        's'",
        "      ],",
        "      'at': '2026-10-14T09:12:04Z',",
        "      'narrative': null,",
        "      'ok': false,",
        "      'result': {",
        "        'error': 'the flow rule: x'",
        "      },",
        "      'seq': 2,",
        "      'tool': 'link'",
        "    }",
        "  ],",
        "  'stats': {",
        "    'by_tool': {",
        "      'add_node': 1,",
        "      'link': 2",
        "    },",
        "    'calls': 3,",
        "    'refusals': {",
        "      'flow rule': 1",
        "    },",
        "    'refused': 1",
        "  },",
        "  'work': {",
        "    'id': ${w.id.toString()},",
        "    'title': 'Traced'",
        "  }",
        "}",
      ]);
      expectText(test, graphTrace(fx.db, w), want);
    }

    test("an empty trace is empty containers") { test =>
      let fx = fxWith("Traced", "# One\n\nSome words here to read.\n");
      let w = reloaded(fx.db, fx.work);
      let want = gxLines([
        "{",
        "  'events': [],",
        "  'stats': {",
        "    'by_tool': {},",
        "    'calls': 0,",
        "    'refusals': {},",
        "    'refused': 0",
        "  },",
        "  'work': {",
        "    'id': ${w.id.toString()},",
        "    'title': 'Traced'",
        "  }",
        "}",
      ]);
      expectText(test, graphTrace(fx.db, w), want);
    }

## The download name

    test("the slug is lower case, hyphenated, trimmed and cut to 50") { test =>
      expectText(test, graphSlug("The Long Wait"), "the-long-wait");
      expectText(test, graphSlug("  Hello,  World!! "), "hello-world");
      expectText(test, graphSlug("2020: a (very) odd year"), "2020-a-very-odd-year");
      expectText(test, graphSlug(""), "draft");
      expectText(test, graphSlug("***"), "draft");
      expectText(test, graphSlug("\u{e9}t\u{e9}"), "t");
      expectText(test, graphSlug("${repeated("a", 49)} bcd"), "${repeated("a", 49)}-");
      expectInt(test, anCodePoints(graphSlug(repeated("a", 80))), 50);
    }
