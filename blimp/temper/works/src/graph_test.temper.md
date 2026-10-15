# Tests for nodes, edges, search, the build trace and resets

Ported from `decision_graph_test`, `editor_tools_test`, `reading_test` (the
edge and node calls) and `work_trace_test` in `notes/tests.md`, plus the rules
the notes state for `Node.changeset`, `Edge.changeset` and the Works queries.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { sysJoin } = import("sys/src");
    let { FieldError } = import("core/src");

    class WorksGraphFx(public db: Db, public scope: Scope, public work: Work, public section: Section) {}

    let graphFixture(): WorksGraphFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "Chapter 1\n\nShe had been standing at the window for an hour before anyone noticed. ${repeated("word ", 300)}";
      let work = makeWork(db, me, "W", body);
      new WorksGraphFx(db, me, work, firstSection(db, work))
    }

    let nodeErrors(r: NodeResult): String {
      sysJoin(r.errors.map { (e: FieldError): String => "${e.field} ${e.message}" }, "; ")
    }

    let titlesOfNodes(nodes: List<GraphNode>): String {
      sysJoin(nodes.map { (n: GraphNode): String => n.title }, ",")
    }

## Nodes

    test("a node has the defaults: pending, ordinal zero, in its work") { test =>
      let g = graphFixture();
      let n = worksInsertNode(g.db, new NodeParams(g.work.id, "goal", "Establish the watcher")).node;
      expectTrue(test, n != null, "inserted");
      if (n != null) {
        expectText(test, n.status, "pending");
        expectInt(test, n.ordinal, 0);
        expectInt(test, n.workId, g.work.id);
        expectTrue(test, n.sectionId == null, "no section");
        expectTrue(test, n.quote == null, "no quote");
      }
    }

    test("every node type of the vocabulary is accepted and another is not") { test =>
      let g = graphFixture();
      let types = ["goal", "decision", "option", "observation", "action", "outcome", "revisit", "beat", "spine", "thread", "note", "question"];
      expectInt(test, graphNodeTypes().length, 12);
      for (let t of types) {
        expectTrue(test, worksInsertNode(g.db, new NodeParams(g.work.id, t, "x")).node != null, t);
      }
      let bad = worksInsertNode(g.db, new NodeParams(g.work.id, "vibe", "x"));
      expectTrue(test, bad.node == null, "refused");
      expectText(test, nodeErrors(bad), "node_type is invalid");
    }

    test("a node needs a title and a type") { test =>
      let g = graphFixture();
      expectText(test, nodeErrors(worksInsertNode(g.db, new NodeParams(g.work.id, "beat", "  "))), "title can't be blank");
      expectText(test, nodeErrors(worksInsertNode(g.db, new NodeParams(g.work.id, "", "t"))), "node_type can't be blank");
      let p = new NodeParams(g.work.id, "beat", "t");
      p.status = "nearly";
      expectText(test, nodeErrors(worksInsertNode(g.db, p)), "status is invalid");
      expectInt(test, count(g.db, "SELECT count(*) AS n FROM nodes"), 0);
    }

    test("set_node_status marks a node and keeps its title") { test =>
      let g = graphFixture();
      let n = worksInsertNode(g.db, new NodeParams(g.work.id, "option", "Use a queue")).node;
      if (n != null) {
        let chosen = worksSetNodeStatus(g.db, g.work.id, n.id, "chosen");
        let cn = chosen.node;
        expectText(test, if (cn != null) { cn.status } else { "none" }, "chosen");
        let bad = worksSetNodeStatus(g.db, g.work.id, n.id, "maybe");
        expectText(test, nodeErrors(bad), "status is invalid");
        let still = worksGetNode(g.db, g.work.id, n.id);
        expectText(test, if (still != null) { still.status } else { "none" }, "chosen");
        expectText(test, if (still != null) { still.title } else { "none" }, "Use a queue");
      }
    }

    test("set_node_status on a node that is not in this work is not found") { test =>
      let g = graphFixture();
      let other = makeWork(g.db, g.scope, "Other", "one two three");
      let n = worksInsertNode(g.db, new NodeParams(other.id, "option", "Elsewhere")).node;
      if (n != null) {
        expectTrue(test, worksSetNodeStatus(g.db, g.work.id, n.id, "chosen").notFound, "scoped to the work");
        expectTrue(test, worksGetNode(g.db, g.work.id, n.id) == null, "not visible from this work");
      }
      expectTrue(test, worksSetNodeStatus(g.db, g.work.id, 9999, "chosen").notFound, "no such node");
    }

    test("insert_nodes numbers the batch from zero and returns the nodes in order") { test =>
      let g = graphFixture();
      let batch = new ListBuilder<NodeParams>();
      batch.add(new NodeParams(0, "beat", "The promise"));
      batch.add(new NodeParams(0, "beat", "The payoff"));
      let made = worksInsertNodes(g.db, g.work.id, g.section.id, batch.toList());
      expectText(test, titlesOfNodes(made), "The promise,The payoff");
      expectInt(test, made[0].ordinal, 0);
      expectInt(test, made[1].ordinal, 1);
      expectInt(test, orZero(made[1].sectionId), g.section.id);
      expectInt(test, made[1].workId, g.work.id);
    }

    test("a rejected node in a batch is skipped and its position is spent") { test =>
      let g = graphFixture();
      let batch = new ListBuilder<NodeParams>();
      batch.add(new NodeParams(0, "beat", "First"));
      batch.add(new NodeParams(0, "wrong", "Skipped"));
      batch.add(new NodeParams(0, "beat", "Third"));
      let named = new NodeParams(0, "beat", "Named");
      named.ordinal = 40;
      batch.add(named);
      let made = worksInsertNodes(g.db, g.work.id, null, batch.toList());
      expectText(test, titlesOfNodes(made), "First,Third,Named");
      expectInt(test, made[1].ordinal, 2);
      expectInt(test, made[2].ordinal, 40);
    }

    test("list_nodes orders by ordinal then id and filters by type, section and narrative") { test =>
      let g = graphFixture();
      let a = new NodeParams(g.work.id, "beat", "late");
      a.ordinal = 5;
      a.sectionId = g.section.id;
      worksInsertNode(g.db, a);
      let b = new NodeParams(g.work.id, "spine", "early");
      b.ordinal = 1;
      b.narrative = "arc";
      worksInsertNode(g.db, b);
      let c = new NodeParams(g.work.id, "beat", "early too");
      c.ordinal = 1;
      worksInsertNode(g.db, c);
      expectText(test, titlesOfNodes(worksNodes(g.db, g.work.id)), "early,early too,late");
      expectText(test, titlesOfNodes(worksListNodes(g.db, g.work.id, "beat", null, null)), "early too,late");
      expectText(test, titlesOfNodes(worksListNodes(g.db, g.work.id, null, g.section.id, null)), "late");
      expectText(test, titlesOfNodes(worksListNodes(g.db, g.work.id, null, null, "arc")), "early");
      expectText(test, titlesOfNodes(worksListNodes(g.db, g.work.id, "spine", g.section.id, null)), "");
    }

    test("counts are by type and the total counts every type") { test =>
      let g = graphFixture();
      for (let t of ["beat", "beat", "beat", "spine", "question", "question", "thread", "note", "goal", "goal"]) {
        worksInsertNode(g.db, new NodeParams(g.work.id, t, "x"));
      }
      let c = worksCounts(g.db, g.work.id);
      expectInt(test, c.beats, 3);
      expectInt(test, c.spine, 1);
      expectInt(test, c.questions, 2);
      expectInt(test, c.threads, 1);
      expectInt(test, c.notes, 1);
      expectInt(test, c.total, 10);
      let empty = worksCounts(g.db, 12345);
      expectInt(test, empty.total, 0);
    }

## Edges

    test("link stores an edge, defaulting the type, and a duplicate is silently not stored") { test =>
      let g = graphFixture();
      let a = worksInsertNode(g.db, new NodeParams(g.work.id, "goal", "a")).node;
      let b = worksInsertNode(g.db, new NodeParams(g.work.id, "option", "b")).node;
      if (a != null) {
        if (b != null) {
          let first = worksLink(g.db, g.work.id, a.id, b.id, null, 0, "because");
          let edge = first.edge;
          expectTrue(test, edge != null, "stored");
          expectText(test, if (edge != null) { edge.edgeType } else { "none" }, "leads_to");
          expectText(test, if (edge != null) { orNull(edge.rationale) } else { "none" }, "because");
          let again = worksLink(g.db, g.work.id, a.id, b.id, "leads_to", 0, "again");
          expectTrue(test, again.edge == null, "no new edge");
          expectTrue(test, again.duplicate, "duplicate");
          let other = worksLink(g.db, g.work.id, a.id, b.id, "follows", 1, null);
          expectTrue(test, other.edge != null, "another type is another edge");
          expectInt(test, worksListEdges(g.db, g.work.id).length, 2);
          let blank = worksLink(g.db, g.work.id, a.id, b.id, "  ", 0, null);
          expectTrue(test, blank.edge == null, "refused");
          expectInt(test, blank.errors.length, 1);
          expectText(test, blank.errors[0].message, "can't be blank");
        }
      }
    }

    test("edges are listed by ordinal then id and die with their nodes") { test =>
      let g = graphFixture();
      let a = worksInsertNode(g.db, new NodeParams(g.work.id, "beat", "a")).node;
      let b = worksInsertNode(g.db, new NodeParams(g.work.id, "beat", "b")).node;
      let c = worksInsertNode(g.db, new NodeParams(g.work.id, "beat", "c")).node;
      if (a != null) {
        if (b != null) {
          if (c != null) {
            worksLink(g.db, g.work.id, b.id, c.id, "follows", 2, null);
            worksLink(g.db, g.work.id, a.id, b.id, "follows", 1, null);
            let edges = worksListEdges(g.db, g.work.id);
            expectInt(test, edges[0].ordinal, 1);
            expectInt(test, edges[1].ordinal, 2);
            g.db.exec("DELETE FROM nodes WHERE id = $1", [b.id.toString()]);
            expectInt(test, worksListEdges(g.db, g.work.id).length, 0);
          }
        }
      }
    }

    test("connections report the cross-section edges with their reasons") { test =>
      let g = graphFixture();
      let batch = new ListBuilder<NodeParams>();
      batch.add(new NodeParams(0, "beat", "The promise"));
      batch.add(new NodeParams(0, "beat", "The payoff"));
      let made = worksInsertNodes(g.db, g.work.id, g.section.id, batch.toList());
      worksLink(g.db, g.work.id, made[0].id, made[1].id, "pays_off", 0, "the opening promise lands here");
      worksLink(g.db, g.work.id, made[0].id, made[1].id, "follows", 0, "just the order");
      let c = worksConnections(g.db, g.work.id, made[0].id);
      expectInt(test, c.out.length, 1);
      expectText(test, c.out[0].edgeType, "pays_off");
      expectText(test, orNull(c.out[0].why), "the opening promise lands here");
      expectText(test, c.out[0].node.title, "The payoff");
      expectInt(test, c.into.length, 0);
      let back = worksConnections(g.db, g.work.id, made[1].id);
      expectInt(test, back.into.length, 1);
      expectText(test, back.into[0].node.title, "The promise");
      let all = worksAllConnections(g.db, g.work.id);
      expectInt(test, all.length, 1);
      expectText(test, all[0].from.title, "The promise");
      expectText(test, all[0].to.title, "The payoff");
    }

    test("the weave has six edge types") { test =>
      expectText(test, sysJoin(graphWeaveTypes(), ","), "develops,pays_off,requires,tension,realises,asks_about");
    }

## Search

    class WorksSearchFx(public db: Db, public work: Work) {}

    let searchFixture(): WorksSearchFx throws Bubble {
      let g = graphFixture();
      let a = new NodeParams(g.work.id, "beat", "The kettle goes cold");
      a.quote = "The kettle went cold on the counter";
      worksInsertNode(g.db, a);
      let b = new NodeParams(g.work.id, "beat", "Nobody moves");
      b.body = "Nobody fills the kettle again";
      worksInsertNode(g.db, b);
      let c = new NodeParams(g.work.id, "spine", "A window");
      worksInsertNode(g.db, c);
      new WorksSearchFx(g.db, g.work)
    }

    test("search scores nodes by the terms they contain, best first") { test =>
      let f = searchFixture();
      expectText(test, titlesOfNodes(worksSearch(f.db, f.work.id, "kettle cold", 12)), "The kettle goes cold,Nobody moves");
      expectText(test, titlesOfNodes(worksSearch(f.db, f.work.id, "WINDOW", 12)), "A window");
      expectText(test, titlesOfNodes(worksSearch(f.db, f.work.id, "kettle", 1)), "The kettle goes cold");
    }

    test("search drops short terms and finds nothing in nothing") { test =>
      let f = searchFixture();
      expectInt(test, worksSearch(f.db, f.work.id, "a of to", 12).length, 0);
      expectInt(test, worksSearch(f.db, f.work.id, "", 12).length, 0);
      expectInt(test, worksSearch(f.db, f.work.id, null, 12).length, 0);
      expectInt(test, worksSearch(f.db, f.work.id, "zebra", 12).length, 0);
      expectText(test, titlesOfNodes(worksSearch(f.db, f.work.id, "a kettle!", 12)), "The kettle goes cold,Nobody moves");
    }

    test("find_in_source gives a window around the first hit in each section") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "# One\n\n${repeated("alpha ", 300)} The Kettle went cold. ${repeated("beta ", 300)}\n\n# Two\n\nShort kettle here.\n\n${repeated("gamma ", 300)}";
      let w = makeWork(db, me, "W", body);
      let hits = worksFindInSource(db, w.id, "  KETTLE ", 5);
      expectInt(test, hits.length, 2);
      expectText(test, hits[0].section, "One");
      expectInt(test, hits[0].ordinal, 1);
      expectHas(test, hits[0].window, "The Kettle went cold.");
      expectTrue(test, hits[0].window.countBetween(String.begin, hits[0].window.end) <= 326, "window length");
      expectText(test, hits[1].section, "Two");
      expectInt(test, worksFindInSource(db, w.id, "kettle", 1).length, 1);
      expectInt(test, worksFindInSource(db, w.id, "   ", 5).length, 0);
      expectInt(test, worksFindInSource(db, w.id, "zebra", 5).length, 0);
    }

## The build trace

    let event(g: WorksGraphFx, tool: String, seq: Int, ok: Boolean, result: String?): GraphEvent? {
      let p = new EventParams(g.work.id, tool);
      p.narrative = "The Window";
      p.seq = seq;
      p.ok = ok;
      p.result = result;
      p.args = "{}";
      worksRecordEvent(g.db, p)
    }

    test("events are recorded in order with their fields") { test =>
      let g = graphFixture();
      let one = event(g, "add_node", 0, true, "{\"id\":1}");
      event(g, "link", 1, false, "{\"error\":\"goal -> decision is the flow rule\"}");
      expectTrue(test, one != null, "recorded");
      let events = worksListEvents(g.db, g.work.id);
      expectInt(test, events.length, 2);
      expectText(test, events[0].tool, "add_node");
      expectTrue(test, events[0].ok, "ok");
      expectFalse(test, events[1].ok, "refused");
      expectInt(test, events[1].seq, 1);
      expectText(test, orNull(events[1].narrative), "The Window");
      expectTrue(test, events[0].nodeId == null, "no node");
      expectInt(test, worksGraphEvents(g.db, g.work.id).length, 2);
    }

    test("an event that cannot be written is not an error") { test =>
      let g = graphFixture();
      let nobody = new EventParams(99999, "add_node");
      expectTrue(test, worksRecordEvent(g.db, nobody) == null, "no such work");
      expectTrue(test, worksRecordEvent(g.db, new EventParams(g.work.id, "")) == null, "no tool");
      expectInt(test, worksListEvents(g.db, g.work.id).length, 0);
    }

    test("stats count calls, refusals by kind, and tools") { test =>
      let g = graphFixture();
      event(g, "add_node", 0, true, "{\"id\":1}");
      event(g, "add_node", 1, false, "{\"error\":\"the quote must match character for character\"}");
      event(g, "link", 2, false, "{\"error\":\"goal -> decision is the flow rule\"}");
      event(g, "link", 3, false, "{\"error\":\"decision is not a step in the flow\"}");
      event(g, "link", 4, false, "{\"error\":\"unknown node id 7\"}");
      event(g, "set_status", 5, false, "{\"error\":\"something else\"}");
      event(g, "set_status", 6, false, null);
      let s = worksEventStats(g.db, g.work.id);
      expectInt(test, s.calls, 7);
      expectInt(test, s.refused, 6);
      expectInt(test, s.byTool.getOr("add_node", 0), 2);
      expectInt(test, s.byTool.getOr("link", 0), 3);
      expectInt(test, s.refusals.getOr("quote not in draft", 0), 1);
      expectInt(test, s.refusals.getOr("flow rule", 0), 2);
      expectInt(test, s.refusals.getOr("unknown node id", 0), 1);
      expectInt(test, s.refusals.getOr("other", 0), 1);
      expectInt(test, s.refusals.getOr("unknown", 0), 1);
    }

    test("clearing the trace leaves nothing and no calls") { test =>
      let g = graphFixture();
      event(g, "add_node", 0, true, null);
      expectInt(test, worksListEvents(g.db, g.work.id).length, 1);
      worksClearEvents(g.db, g.work.id);
      expectInt(test, worksListEvents(g.db, g.work.id).length, 0);
      expectInt(test, worksEventStats(g.db, g.work.id).calls, 0);
    }

## Resets

    test("reset_decision_graph deletes the seven decision types and keeps the read") { test =>
      let g = graphFixture();
      let goal = worksInsertNode(g.db, new NodeParams(g.work.id, "goal", "G")).node;
      let option = worksInsertNode(g.db, new NodeParams(g.work.id, "option", "O")).node;
      let beat = worksInsertNode(g.db, new NodeParams(g.work.id, "beat", "B")).node;
      let spine = worksInsertNode(g.db, new NodeParams(g.work.id, "spine", "S")).node;
      if (goal != null) {
        if (option != null) {
          if (beat != null) {
            if (spine != null) {
              worksLink(g.db, g.work.id, goal.id, option.id, "leads_to", 0, null);
              worksLink(g.db, g.work.id, option.id, beat.id, "leads_to", 0, null);
              worksLink(g.db, g.work.id, beat.id, spine.id, "follows", 0, null);
              event(g, "add_node", 0, true, null);
              expectInt(test, worksResetDecisionGraph(g.db, g.work.id), 2);
              expectText(test, titlesOfNodes(worksNodes(g.db, g.work.id)), "B,S");
              expectInt(test, worksListEdges(g.db, g.work.id).length, 1);
              expectInt(test, worksListEvents(g.db, g.work.id).length, 0);
              expectInt(test, worksResetDecisionGraph(g.db, g.work.id), 0);
            }
          }
        }
      }
    }

    test("reset_read deletes every node, edge and event and sets the sections pending") { test =>
      let g = graphFixture();
      let a = worksInsertNode(g.db, new NodeParams(g.work.id, "beat", "half-written")).node;
      let b = worksInsertNode(g.db, new NodeParams(g.work.id, "goal", "G")).node;
      if (a != null) {
        if (b != null) { worksLink(g.db, g.work.id, a.id, b.id, "leads_to", 0, null); }
      }
      event(g, "add_node", 0, true, null);
      worksSetSectionStatus(g.db, g.section, "read");
      let status = worksSetStatus(g.db, g.work, "read", null);
      worksResetRead(g.db, g.work.id);
      expectInt(test, worksNodes(g.db, g.work.id).length, 0);
      expectInt(test, worksListEdges(g.db, g.work.id).length, 0);
      expectInt(test, worksListEvents(g.db, g.work.id).length, 0);
      expectText(test, worksListSections(g.db, g.work.id)[0].status, "pending");
      let work = worksGetById(g.db, g.work.id);
      expectText(test, if (work != null) { work.status } else { "none" }, status.status);
    }

    test("a reset touches only its own work") { test =>
      let g = graphFixture();
      let other = makeWork(g.db, g.scope, "Other", "one two three");
      worksInsertNode(g.db, new NodeParams(other.id, "goal", "kept"));
      worksInsertNode(g.db, new NodeParams(g.work.id, "goal", "gone"));
      worksResetRead(g.db, g.work.id);
      expectText(test, titlesOfNodes(worksNodes(g.db, other.id)), "kept");
      expectInt(test, worksResetDecisionGraph(g.db, g.work.id), 0);
    }
