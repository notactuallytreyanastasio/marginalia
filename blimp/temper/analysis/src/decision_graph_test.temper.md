# Tests for the decision graph

Ported from `decision_graph_test.exs`: the three rules enforced in code
(grounding, the flow rule, refusal accounting), driven by `execute` the way
the model would. Then the loop and the whole build, driven by `llmFakeScript`.

    let { Db } = import("db/src");
    let {
      Work, Section, GraphNode, GraphEdge, GraphEvent, NodeParams, worksInsertNode, worksListEdges, worksNodes,
      worksLink, worksGetNode, worksListEvents, worksEventStats, worksClearEvents, worksResetDecisionGraph,
      worksListNodes,
    } = import("works/src");
    let {
      LlmClient, LlmTool, LlmToolCall, LlmMessage, llmFakeScript, LlmFakeResponse, llmRequests,
    } = import("llm/src");
    let { sysJoin } = import("sys/src");
    let { JsonSyntaxTree, JsonObject, JsonArray, JsonTextProducer, parseJson } = import("std/json");

    class DgFx(public fx: AnFx, public state: DecisionGraphState) {}

    let dgFixture(): DgFx throws Bubble {
      let fx = fxGraph();
      let none = new MapBuilder<Int, String>().toMap();
      new DgFx(fx, decisionGraphState(fx.work, "n", [fx.sections[0]], none))
    }

`call(state, name, args)`: the answer, decoded.

    let dgCall(g: DgFx, name: String, args: String): JsonSyntaxTree throws Bubble {
      let text = decisionGraphExecute(g.fx.db, new LlmToolCall("x", name, args), g.state);
      parseJson(text)
    }

    let dgAddArgs(kind: String, title: String): String {
      "{\"type\":\"${kind}\",\"title\":\"${title}\",\"narrative\":\"n\"}"
    }

    let dgAdd(g: DgFx, kind: String, title: String): Int throws Bubble {
      let r = dgCall(g, "add_node", dgAddArgs(kind, title));
      let id = anInt(anField(r, "id"));
      if (id != null) { id } else { bubble() }
    }

    let dgErr(r: JsonSyntaxTree): String { anOrEmpty(anStr(anField(r, "error"))) }

    let dgLinkArgs(from: Int, to: Int): String {
      "{\"from\":${from.toString()},\"to\":${to.toString()}}"
    }

## The tool surface mirrors the deciduous CLI

    test("add_node, link and set_status are the three operations") { test =>
      let names = decisionGraphTools().map { (t: LlmTool): String => t.name };
      expectText(test, sysJoin(names, ","), "add_node,link,set_status");
    }

    let dgCollect(values: List<JsonSyntaxTree>?, into: ListBuilder<String>): Void {
      if (values != null) {
        for (let v of values) { into.add(anOrEmpty(anStr(v))); }
      }
    }

    test("add_node offers exactly the decision-graph vocabulary") { test =>
      let add = decisionGraphTools()[0];
      let tree = parseJson(add.parametersJson);
      let enumValues = anElements(anField(anField(anField(tree, "properties"), "type"), "enum"));
      let types = new ListBuilder<String>();
      dgCollect(enumValues, types);
      expectText(test, sysJoin(dgSorted(types.toList()), " "), "action decision goal observation option outcome revisit");
      let required = anElements(anField(tree, "required"));
      expectInt(test, if (required != null) { required.length } else { 0 }, 3);
    }

    test("the descriptions are the ones the model was given") { test =>
      let tools = decisionGraphTools();
      expectText(test, tools[0].description, "Add one node to the decision graph. Returns its id, which you use for linking. Equivalent to `deciduous add <type> \"<title>\"`.");
      expectText(test, tools[1].description, "Connect two nodes: from leads_to to. Equivalent to `deciduous link <from> <to> -r \"<why>\"`. Refused if it breaks the flow rule or the temporal rule.");
      expectText(test, tools[2].description, "Mark an option chosen or rejected, or a node superseded. Equivalent to `deciduous status <id> <status>`.");
    }

## Grounding is enforced at the tool boundary

    test("a fabricated quote is refused, and the model is told why") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "{\"type\":\"observation\",\"title\":\"invented\",\"narrative\":\"n\",\"quote\":\"She turned and left without saying anything at all.\"}");
      expectHas(test, dgErr(r), "not found in the draft");
      expectHas(test, anOrEmpty(anStr(anField(r, "hint"))), "Copy the span exactly");
      expectInt(test, g.state.nodes.length, 0);
      expectInt(test, worksNodes(g.fx.db, g.fx.work.id).length, 0);
    }

    test("a real quote is accepted and rewritten to the source's wording") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "{\"type\":\"observation\",\"title\":\"real\",\"narrative\":\"n\",\"quote\":\"STANDING at the window for an hour\"}");
      let id = anInt(anField(r, "id"));
      expectTrue(test, id != null, "an id");
      expectInt(test, g.state.nodes.length, 1);
      if (id != null) {
        let node = worksGetNode(g.fx.db, g.fx.work.id, id);
        expectTrue(test, node != null, "stored");
        if (node != null) {
          expectText(test, orNull(node.quote), "standing at the window for an hour");
          expectTrue(test, anContains(g.fx.sections[0].body, orNull(node.quote)), "in the section");
          expectText(test, node.title, "real");
          expectText(test, orNull(node.narrative), "n");
          expectText(test, node.nodeType, "observation");
        }
      }
    }

    test("a structural node may omit a quote") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", dgAddArgs("goal", "the goal"));
      expectTrue(test, anInt(anField(r, "id")) != null, "an id");
      expectText(test, orNull(anStr(anField(r, "added"))), "the goal");
      expectText(test, orNull(anStr(anField(r, "type"))), "goal");
    }

    test("an empty quote counts as no quote") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "{\"type\":\"goal\",\"title\":\"g\",\"narrative\":\"n\",\"quote\":\"\"}");
      expectTrue(test, anInt(anField(r, "id")) != null, "an id");
      let node = worksNodes(g.fx.db, g.fx.work.id)[0];
      expectTrue(test, node.quote == null, "no quote stored");
    }

    test("a quote that is not a string is refused") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "{\"type\":\"goal\",\"title\":\"g\",\"narrative\":\"n\",\"quote\":7}");
      expectHas(test, dgErr(r), "character for character");
    }

    test("a quote is checked against the section the node names, and only that one") { test =>
      let fx = fxRead();
      let none = new MapBuilder<Int, String>().toMap();
      let g = new DgFx(fx, decisionGraphState(fx.work, "n", fx.sections, none));
      let ok = dgCall(g, "add_node", "{\"type\":\"observation\",\"title\":\"a\",\"narrative\":\"n\",\"section\":1,\"quote\":\"${q1()}\"}");
      expectTrue(test, anInt(anField(ok, "id")) != null, "section one holds it");
      let wrong = dgCall(g, "add_node", "{\"type\":\"observation\",\"title\":\"b\",\"narrative\":\"n\",\"section\":\"2\",\"quote\":\"${q1()}\"}");
      expectHas(test, dgErr(wrong), "not found in the draft");
      let any = dgCall(g, "add_node", "{\"type\":\"observation\",\"title\":\"c\",\"narrative\":\"n\",\"quote\":\"${q5()}\"}");
      expectTrue(test, anInt(anField(any, "id")) != null, "found in the section that has it");
      let node = worksGetNode(fx.db, fx.work.id, 2);
      expectTrue(test, node != null, "the third node");
      let sectionOfAny = worksGetNode(fx.db, fx.work.id, 2);
      if (sectionOfAny != null) {
        expectTrue(test, sectionOfAny.sectionId == null, "no section given, none stored");
      }
      let first = worksGetNode(fx.db, fx.work.id, 1);
      if (first != null) {
        expectTrue(test, first.sectionId == fx.sections[0].id, "section one stored");
      }
    }

## The flow rule is enforced, not requested

    class DgFlow(public g: DgFx, public goal: Int, public option: Int, public decision: Int, public action: Int) {}

    let dgFlow(): DgFlow throws Bubble {
      let g = dgFixture();
      new DgFlow(g, dgAdd(g, "goal", "g"), dgAdd(g, "option", "o"), dgAdd(g, "decision", "d"), dgAdd(g, "action", "a"))
    }

    test("goal -> decision is refused with the fix spelled out") { test =>
      let f = dgFlow();
      let r = dgCall(f.g, "link", dgLinkArgs(f.goal, f.decision));
      expectHas(test, dgErr(r), "a goal cannot lead straight to a decision");
      expectHas(test, dgErr(r), "options");
      expectInt(test, worksListEdges(f.g.fx.db, f.g.fx.work.id).length, 0);
    }

    test("goal -> option -> decision -> action is allowed") { test =>
      let f = dgFlow();
      let steps = [dgLinkArgs(f.goal, f.option), dgLinkArgs(f.option, f.decision), dgLinkArgs(f.decision, f.action)];
      var i = 0;
      while (i < steps.length) {
        let r = dgCall(f.g, "link", steps[i]);
        expectTrue(test, anStr(anField(r, "linked")) != null, "expected step ${i.toString()} to be allowed, got ${dgErr(r)}");
        i += 1;
      }
      let edges = worksListEdges(f.g.fx.db, f.g.fx.work.id);
      expectInt(test, edges.length, 3);
      expectText(test, edges[0].edgeType, "leads_to");
    }

    test("the linked answer names both ends") { test =>
      let f = dgFlow();
      let r = dgCall(f.g, "link", dgLinkArgs(f.goal, f.option));
      expectText(test, orNull(anStr(anField(r, "linked"))), "${f.goal.toString()} -> ${f.option.toString()}");
    }

    test("a rationale is stored on the edge, and its ordinal is the number of nodes") { test =>
      let f = dgFlow();
      dgCall(f.g, "link", "{\"from\":${f.goal.toString()},\"to\":${f.option.toString()},\"rationale\":\"because\"}");
      let e = worksListEdges(f.g.fx.db, f.g.fx.work.id)[0];
      expectText(test, orNull(e.rationale), "because");
      expectInt(test, e.ordinal, 4);
    }

    test("a step that is not in the flow is refused and the legal ones named") { test =>
      let f = dgFlow();
      let r = dgCall(f.g, "link", dgLinkArgs(f.action, f.option));
      expectHas(test, dgErr(r), "not a step in goal -> option -> decision");
      expectHas(test, dgErr(r), "action -> option");
      let allowed = anElements(anField(r, "allowed"));
      expectTrue(test, allowed != null, "a list");
      if (allowed != null) { expectInt(test, allowed.length, 3); }
    }

    test("a node id the model never created cannot be linked") { test =>
      let f = dgFlow();
      let r = dgCall(f.g, "link", dgLinkArgs(f.goal, 999999));
      expectHas(test, dgErr(r), "unknown node id");
    }

    test("a link with ids of the wrong kind is an unknown id") { test =>
      let f = dgFlow();
      let r = dgCall(f.g, "link", "{\"from\":\"1\",\"to\":2.0}");
      expectHas(test, dgErr(r), "unknown node id");
    }

    test("an option can be marked chosen or rejected") { test =>
      let g = dgFixture();
      let opt = dgAdd(g, "option", "o");
      let r = dgCall(g, "set_status", "{\"id\":${opt.toString()},\"status\":\"rejected\"}");
      expectText(test, orNull(anStr(anField(r, "ok"))), "${opt.toString()} is rejected");
      let node = worksGetNode(g.fx.db, g.fx.work.id, opt);
      expectTrue(test, node != null, "stored");
      if (node != null) { expectText(test, node.status, "rejected"); }
    }

    test("set_status on a node the work does not have is :not_found") { test =>
      let g = dgFixture();
      let r = dgCall(g, "set_status", "{\"id\":999,\"status\":\"chosen\"}");
      expectText(test, dgErr(r), ":not_found");
    }

    test("set_status with a status outside the five prints the changeset") { test =>
      let g = dgFixture();
      let opt = dgAdd(g, "option", "o");
      let r = dgCall(g, "set_status", "{\"id\":${opt.toString()},\"status\":\"vibes\"}");
      expectHas(test, dgErr(r), "#Ecto.Changeset<");
      expectHas(test, dgErr(r), "status: {\"is invalid\"");
    }

    test("an unknown tool is named") { test =>
      let g = dgFixture();
      expectText(test, dgErr(dgCall(g, "delete_everything", "{}")), "unknown tool delete_everything");
    }

    test("arguments that are not an object are treated as empty") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "[1,2]");
      expectHas(test, dgErr(r), "can't be blank");
      let r2 = dgCall(g, "add_node", "not json");
      expectHas(test, dgErr(r2), "already sent this exact call");
    }

## The build trace

    test("records the calls that succeeded") { test =>
      let g = dgFixture();
      let id = dgAdd(g, "goal", "A goal");
      dgCall(g, "add_node", "{\"type\":\"option\",\"title\":\"An option\",\"narrative\":\"n\",\"quote\":\"standing at the window for an hour\"}");
      let events = worksListEvents(g.fx.db, g.fx.work.id);
      expectInt(test, events.length, 2);
      expectTrue(test, events[0].ok && events[1].ok, "both ok");
      expectText(test, events[0].tool, "add_node");
      expectText(test, events[1].tool, "add_node");
      expectInt(test, events[0].seq, 0);
      expectInt(test, events[1].seq, 1);
      expectTrue(test, events[0].nodeId == id, "node id recorded");
      expectText(test, orNull(events[0].narrative), "n");
    }

    test("the stored args are sorted JSON and the result is the answer sent back") { test =>
      let g = dgFixture();
      dgCall(g, "add_node", "{\"title\":\"A goal\",\"type\":\"goal\",\"narrative\":\"n\"}");
      let e = worksListEvents(g.fx.db, g.fx.work.id)[0];
      expectText(test, orNull(e.args), "{\"narrative\":\"n\",\"title\":\"A goal\",\"type\":\"goal\"}");
      expectText(test, orNull(e.result), "{\"added\":\"A goal\",\"id\":1,\"type\":\"goal\"}");
    }

    test("records a refused quote as a refusal, not a silent gap") { test =>
      let g = dgFixture();
      dgCall(g, "add_node", "{\"type\":\"action\",\"title\":\"Invented\",\"narrative\":\"n\",\"quote\":\"a sentence the writer never wrote at all\"}");
      let events = worksListEvents(g.fx.db, g.fx.work.id);
      expectInt(test, events.length, 1);
      expectFalse(test, events[0].ok, "refused");
      expectHas(test, orNull(events[0].result), "character for character");
      let stats = worksEventStats(g.fx.db, g.fx.work.id);
      expectInt(test, stats.calls, 1);
      expectInt(test, stats.refused, 1);
      expectInt(test, stats.refusals.getOr("quote not in draft", 0), 1);
    }

    test("records a refused link and names the flow rule") { test =>
      let g = dgFixture();
      let goal = dgAdd(g, "goal", "G");
      let dec = dgAdd(g, "decision", "D");
      dgCall(g, "link", dgLinkArgs(goal, dec));
      let stats = worksEventStats(g.fx.db, g.fx.work.id);
      expectInt(test, stats.calls, 3);
      expectInt(test, stats.refused, 1);
      expectInt(test, stats.refusals.getOr("flow rule", 0), 1);
      expectInt(test, stats.byTool.getOr("add_node", 0), 2);
      expectInt(test, stats.byTool.getOr("link", 0), 1);
    }

    test("a rebuild clears the previous run's trace") { test =>
      let g = dgFixture();
      dgAdd(g, "goal", "G");
      expectInt(test, worksListEvents(g.fx.db, g.fx.work.id).length, 1);
      worksClearEvents(g.fx.db, g.fx.work.id);
      expectInt(test, worksListEvents(g.fx.db, g.fx.work.id).length, 0);
      expectInt(test, worksEventStats(g.fx.db, g.fx.work.id).calls, 0);
    }

    test("every call bumps the work's version") { test =>
      let g = dgFixture();
      dgAdd(g, "goal", "G");
      dgAdd(g, "goal", "H");
      expectInt(test, bumps(g.fx.db, g.fx.work), 2);
    }

## Malformed tool calls

    test("a title written under the type key is recovered") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "{\"type\":\"action\",\"action\":\"Name the method\",\"narrative\":\"n\"}");
      expectText(test, orNull(anStr(anField(r, "added"))), "Name the method");
      expectText(test, orNull(anStr(anField(r, "type"))), "action");
    }

    test("a genuinely titleless node is still refused, and the error says what was sent") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "{\"type\":\"action\",\"narrative\":\"n\"}");
      expectHas(test, dgErr(r), "title");
      expectText(test, dgErr(r), "rejected: %{title: [\"can't be blank\"]}");
      let sent = anElements(anField(r, "you_sent"));
      expectTrue(test, sent != null, "a list");
      if (sent != null) {
        expectText(test, sysJoin(sent.map { (s: JsonSyntaxTree): String => anOrEmpty(anStr(s)) }, ","), "narrative,type");
      }
      expectHas(test, anOrEmpty(anStr(anField(r, "hint"))), "add_node takes type, title, description, quote, section, narrative.");
    }

    test("an empty call does not recover a title from nowhere") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "{}");
      expectHas(test, dgErr(r), "can't be blank");
      expectText(test, dgErr(r), "rejected: %{node_type: [\"can't be blank\"], title: [\"can't be blank\"]}");
    }

    test("a type outside the vocabulary is invalid") { test =>
      let g = dgFixture();
      let r = dgCall(g, "add_node", "{\"type\":\"vibe\",\"title\":\"t\"}");
      expectText(test, dgErr(r), "rejected: %{node_type: [\"is invalid\"]}");
    }

    test("a narrative the model names is kept, and a missing one is the state's") { test =>
      let g = dgFixture();
      dgCall(g, "add_node", "{\"type\":\"goal\",\"title\":\"a\",\"narrative\":\"other\"}");
      dgCall(g, "add_node", "{\"type\":\"goal\",\"title\":\"b\"}");
      let nodes = worksNodes(g.fx.db, g.fx.work.id);
      expectText(test, orNull(nodes[0].narrative), "other");
      expectText(test, orNull(nodes[1].narrative), "n");
    }

## Refusals are actionable

    test("a refused link names the legal one-hop route") { test =>
      let g = dgFixture();
      let o = dgAdd(g, "outcome", "O");
      let a = dgAdd(g, "action", "A");
      let r = dgCall(g, "link", dgLinkArgs(o, a));
      expectHas(test, dgErr(r), "outcome -> action");
      expectHas(test, anOrEmpty(anStr(anField(r, "route"))), "observation");
      expectText(test, anOrEmpty(anStr(anField(r, "route"))), "go through a observation: link the outcome to a observation, then that observation to the action.");
    }

    test("a refusal names the first legal detour, or none") { test =>
      let g = dgFixture();
      let gl = dgAdd(g, "goal", "G");
      let ac = dgAdd(g, "action", "A");
      let text = decisionGraphExecute(g.fx.db, new LlmToolCall("x", "link", dgLinkArgs(gl, ac)), g.state);
      expectHas(test, text, "\"route\":\"go through a observation");
      expectText(test, orNull(decisionGraphRoute("goal", "note")), "<null>");
    }

    test("re-sending a refused call verbatim is called out, not re-run") { test =>
      let g = dgFixture();
      let bad = "{\"type\":\"action\",\"title\":\"X\",\"narrative\":\"n\",\"quote\":\"not in the draft at all\"}";
      let first = dgCall(g, "add_node", bad);
      expectHas(test, dgErr(first), "character for character");
      let second = dgCall(g, "add_node", bad);
      expectHas(test, dgErr(second), "already sent this exact call");
      expectTrue(test, second is JsonObject, "an object");
      let text = decisionGraphExecute(g.fx.db, new LlmToolCall("x", "add_node", bad), g.state);
      expectText(test, text, "{\"error\":\"you already sent this exact call and it was refused. Change it or move on.\",\"repeat\":true}");
    }

    test("the same call with the keys in another order is the same call") { test =>
      let g = dgFixture();
      dgCall(g, "add_node", "{\"type\":\"action\",\"title\":\"X\",\"narrative\":\"n\",\"quote\":\"not in the draft at all\"}");
      let again = dgCall(g, "add_node", "{\"quote\":\"not in the draft at all\",\"narrative\":\"n\",\"title\":\"X\",\"type\":\"action\"}");
      expectHas(test, dgErr(again), "already sent this exact call");
    }

    test("a different call after a refusal still runs") { test =>
      let g = dgFixture();
      dgCall(g, "add_node", "{\"type\":\"action\",\"title\":\"X\",\"narrative\":\"n\",\"quote\":\"nope nope nope\"}");
      let ok = dgCall(g, "add_node", "{\"type\":\"action\",\"title\":\"Y\",\"narrative\":\"n\",\"quote\":\"standing at the window for an hour\"}");
      expectText(test, orNull(anStr(anField(ok, "added"))), "Y");
      expectInt(test, worksEventStats(g.fx.db, g.fx.work.id).refused, 1);
    }

    test("the repeat refusal is recorded too") { test =>
      let g = dgFixture();
      let bad = "{\"type\":\"action\",\"title\":\"X\",\"narrative\":\"n\",\"quote\":\"not in the draft at all\"}";
      dgCall(g, "add_node", bad);
      dgCall(g, "add_node", bad);
      let stats = worksEventStats(g.fx.db, g.fx.work.id);
      expectInt(test, stats.calls, 2);
      expectInt(test, stats.refused, 2);
    }

## Rebuilding replaces rather than stacks

    test("the previous decision graph is cleared, the read is not") { test =>
      let g = dgFixture();
      let work = g.fx.work;
      let db = g.fx.db;
      let beatParams = new NodeParams(work.id, "beat", "a beat");
      beatParams.sectionId = g.fx.sections[0].id;
      let beat = worksInsertNode(db, beatParams).node;
      let spine = worksInsertNode(db, new NodeParams(work.id, "spine", "the trunk")).node;
      dgAdd(g, "goal", "G");
      let opt = dgAdd(g, "option", "O");
      dgCall(g, "link", dgLinkArgs(opt - 1, opt));
      if (beat != null) {
        if (spine != null) { worksLink(db, work.id, beat.id, spine.id, "realises", 0, "why"); }
      }
      expectInt(test, worksResetDecisionGraph(db, work.id), 2);
      let kept = sysJoin(dgSorted(worksNodes(db, work.id).map { (n: GraphNode): String => n.nodeType }), ",");
      expectText(test, kept, "beat,spine");
      let edges = worksListEdges(db, work.id);
      expectInt(test, edges.length, 1);
      expectText(test, edges[0].edgeType, "realises");
      expectInt(test, worksListEvents(db, work.id).length, 0);
    }

    test("clearing an empty graph is not an error") { test =>
      let g = dgFixture();
      expectInt(test, worksResetDecisionGraph(g.fx.db, g.fx.work.id), 0);
    }

## Narratives are not sealed islands

    test("a node from an earlier narrative can be linked to") { test =>
      let g = dgFixture();
      let first = dgAdd(g, "outcome", "Where one ended");
      let carried = decisionGraphKnown(g.state);
      let two = new DgFx(g.fx, decisionGraphState(g.fx.work, "two", [g.fx.sections[0]], carried));
      let second = dgAdd(two, "observation", "What two noticed");
      let r = dgCall(two, "link", "{\"from\":${first.toString()},\"to\":${second.toString()},\"rationale\":\"one caused two\"}");
      expectText(test, orNull(anStr(anField(r, "linked"))), "${first.toString()} -> ${second.toString()}");
    }

    test("an id from no narrative at all is still refused, and says what is known") { test =>
      let g = dgFixture();
      let a = dgAdd(g, "goal", "G");
      let r = dgCall(g, "link", dgLinkArgs(a, 999999));
      expectHas(test, dgErr(r), "unknown node id");
      let known = anElements(anField(r, "known"));
      expectTrue(test, known != null, "a list");
      if (known != null) {
        expectInt(test, known.length, 1);
        expectInt(test, if (anInt(known[0]) != null) { a } else { -1 }, a);
      }
      expectInt(test, worksListEdges(g.fx.db, g.fx.work.id).length, 0);
    }

    test("the known ids are sorted") { test =>
      let g = dgFixture();
      dgAdd(g, "goal", "A");
      dgAdd(g, "goal", "B");
      dgAdd(g, "goal", "C");
      let text = decisionGraphExecute(g.fx.db, new LlmToolCall("x", "link", dgLinkArgs(1, 999)), g.state);
      expectHas(test, text, "\"known\":[1,2,3]");
    }

## The prompts and messages

    test("the narratives message lists each section's beat titles") { test =>
      let fx = fxRead();
      let p = new NodeParams(fx.work.id, "beat", "They open");
      p.sectionId = fx.sections[1].id;
      let beats = worksInsertNodes(fx.db, fx.work.id, fx.sections[1].id, [p]);
      let user = decisionGraphNarrativeUser(fx.work, fx.sections, beats);
      expectText(test, user, "Manuscript: The Long Wait\n\n## Section 1: The window\n\n\n## Section 2: The thermostat\n  - They open\n\n## Section 3: The telephone\n\n");
    }

    test("the narrative message carries the arc, the known nodes and the sections in full") { test =>
      let fx = fxRead();
      let a = worksInsertNode(fx.db, new NodeParams(fx.work.id, "goal", "First goal")).node;
      let known = new MapBuilder<Int, String>();
      known.set(1, "goal");
      let already = decisionGraphAlready(fx.work, worksNodes(fx.db, fx.work.id), known.toMap());
      expectHas(test, already, "\nALREADY IN THE GRAPH, from the narratives built before this one.");
      expectHas(test, already, "\n\n  [1] goal: First goal\n");
      expectText(test, decisionGraphAlready(fx.work, [], new MapBuilder<Int, String>().toMap()), "");
      let user = decisionGraphUser("The kettle", "Cold, then filled.", "", [fx.sections[0]], fx.work);
      expectHas(test, user, "Manuscript: The Long Wait\n\nNARRATIVE TO BUILD: The kettle\nCold, then filled.\n\nThe sections it runs through are below in full. Build this narrative's chain with the tools.\n\n## Section 1: The window\nShe had been standing");
      expectTrue(test, a != null, "inserted");
    }

    test("the flow table and the prompts are the ones the model was given") { test =>
      expectText(test, sysJoin(decisionGraphFlowOf("goal"), " "), "option observation");
      expectText(test, sysJoin(decisionGraphFlowOf("outcome"), " "), "observation revisit decision goal");
      expectText(test, sysJoin(decisionGraphFlowOf("observation"), " "), "decision goal observation revisit action outcome option");
      expectInt(test, decisionGraphFlowOf("note").length, 0);
      expectHas(test, decisionGraphPrompt(), "THE FLOW: goal -> option(s) -> decision -> action(s) -> outcome(s).");
      expectHas(test, decisionGraphNarrativePrompt(), "Find the SPINE among them: the question the draft keeps re-answering. Name it first.");
    }

## The loop

    let dgStop(): LlmFakeResponse { ok(fakeContent("Done.")) }

    let dgAddCall(kind: String, title: String): FakeCall {
      new FakeCall("add_node", dgAddArgs(kind, title))
    }

    test("two tool calls then a stop") { test =>
      let g = dgFixture();
      let llm = llmFakeScript([
        ok(fakeCalls([dgAddCall("goal", "G"), dgAddCall("option", "O")])),
        ok(fakeCalls([new FakeCall("link", dgLinkArgs(1, 2))])),
        dgStop(),
      ]);
      let known = decisionGraphLoop(g.fx.db, llm, g.state, [new LlmMessage("user", "build it")]);
      expectInt(test, known.keys().toList().length, 2);
      expectText(test, known.getOr(1, ""), "goal");
      expectText(test, known.getOr(2, ""), "option");
      expectInt(test, worksListEdges(g.fx.db, g.fx.work.id).length, 1);
      let events = worksListEvents(g.fx.db, g.fx.work.id);
      expectInt(test, events.length, 3);
      expectText(test, sysJoin(events.map { (e: GraphEvent): String => e.tool }, ","), "add_node,add_node,link");
      expectInt(test, events[2].seq, 2);
      expectInt(test, llmRequests(llm).length, 3);
    }

    test("the assistant turn and every result go back to the model") { test =>
      let g = dgFixture();
      let llm = llmFakeScript([
        ok(fakeCalls([dgAddCall("goal", "G"), dgAddCall("option", "O")])),
        dgStop(),
      ]);
      decisionGraphLoop(g.fx.db, llm, g.state, [new LlmMessage("user", "build it")]);
      let second = llmRequests(llm)[1];
      expectHas(test, second, "\"role\":\"assistant\"");
      expectHas(test, second, "\"tool_calls\":[{\"function\":{\"arguments\":");
      expectHas(test, second, "\"id\":\"call_1\"");
      expectHas(test, second, "\"role\":\"tool\",\"tool_call_id\":\"call_1\"");
      expectHas(test, second, "\"role\":\"tool\",\"tool_call_id\":\"call_2\"");
      expectHas(test, second, "{\\\"added\\\":\\\"G\\\",\\\"id\\\":1,\\\"type\\\":\\\"goal\\\"}");
    }

    test("the loop offers the three tools at high effort with no forced choice") { test =>
      let g = dgFixture();
      let llm = llmFakeScript([dgStop()]);
      decisionGraphLoop(g.fx.db, llm, g.state, [new LlmMessage("user", "build it")]);
      let sent = llmRequests(llm)[0];
      expectHas(test, sent, "\"tool_choice\":\"auto\"");
      expectHas(test, sent, "\"reasoning_effort\":\"high\"");
      expectHas(test, sent, "\"temperature\":0.4");
      expectHas(test, sent, "\"max_tokens\":28000");
      expectHas(test, sent, "\"name\":\"add_node\"");
      expectHas(test, sent, "\"name\":\"set_status\"");
    }

    test("an error ends the narrative and keeps what was built") { test =>
      let g = dgFixture();
      let llm = llmFakeScript([ok(fakeCalls([dgAddCall("goal", "G")])), new LlmFakeResponse(400, "{}")]);
      let known = decisionGraphLoop(g.fx.db, llm, g.state, [new LlmMessage("user", "build it")]);
      expectInt(test, known.keys().toList().length, 1);
      expectInt(test, worksNodes(g.fx.db, g.fx.work.id).length, 1);
    }

    test("the model gets 24 calls and no more") { test =>
      let g = dgFixture();
      let replies = new ListBuilder<LlmFakeResponse>();
      var i = 0;
      while (i < 30) {
        replies.add(ok(fakeCalls([dgAddCall("goal", "G${i.toString()}")])));
        i += 1;
      }
      let llm = llmFakeScript(replies.toList());
      let known = decisionGraphLoop(g.fx.db, llm, g.state, [new LlmMessage("user", "build it")]);
      expectInt(test, llmRequests(llm).length, 24);
      expectInt(test, known.keys().toList().length, 24);
    }

    test("a refused call fed back is not re-run when the model repeats it") { test =>
      let g = dgFixture();
      let bad = new FakeCall("add_node", "{\"type\":\"action\",\"title\":\"X\",\"narrative\":\"n\",\"quote\":\"not in the draft at all\"}");
      let llm = llmFakeScript([ok(fakeCalls([bad])), ok(fakeCalls([bad])), dgStop()]);
      decisionGraphLoop(g.fx.db, llm, g.state, [new LlmMessage("user", "build it")]);
      expectInt(test, worksEventStats(g.fx.db, g.fx.work.id).refused, 2);
      expectHas(test, llmRequests(llm)[2], "already sent this exact call");
    }

## The whole build

    let narrativesReply(): String throws Bubble {
      fakeContent("{\"narratives\":[{\"name\":\"The kettle\",\"arc\":\"Cold, then filled.\",\"sections\":[1,3],\"quote\":\"x\"},{\"name\":\"The waiting\",\"arc\":\"Ends with the phone.\",\"sections\":[]},\"junk\"]}")
    }

    test("a build finds the narratives, builds each, and threads the known ids forward") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([
        ok(narrativesReply()),
        ok(fakeCalls([dgAddCall("goal", "Fill the kettle"), dgAddCall("option", "Leave it cold")])),
        dgStop(),
        ok(fakeCalls([new FakeCall("add_node", "{\"type\":\"observation\",\"title\":\"They wait\",\"narrative\":\"The waiting\"}"), new FakeCall("link", dgLinkArgs(2, 3))])),
        dgStop(),
      ]);
      let r = decisionGraphBuild(fx.db, llm, fx.work, null);
      expectTrue(test, r.ok, "ok");
      expectInt(test, r.narratives, 2);
      expectInt(test, r.nodes, 3);
      expectInt(test, r.events, 4);
      expectInt(test, worksEventStats(fx.db, fx.work.id).refused, 0);
      let edges = worksListEdges(fx.db, fx.work.id);
      expectInt(test, edges.length, 1);
      expectInt(test, edges[0].fromId, 2);
      expectInt(test, edges[0].toId, 3);
      let sent = llmRequests(llm);
      expectInt(test, sent.length, 5);
      expectHas(test, sent[0], "\"response_format\":{\"type\":\"json_object\"}");
      expectHas(test, sent[1], "NARRATIVE TO BUILD: The kettle\\nCold, then filled.\\n");
      expectHas(test, sent[1], "## Section 1: The window\\n");
      expectHas(test, sent[1], "## Section 3: The telephone\\n");
      expectLacks(test, sent[1], "## Section 2: The thermostat");
      expectLacks(test, sent[1], "ALREADY IN THE GRAPH");
      expectHas(test, sent[3], "NARRATIVE TO BUILD: The waiting");
      expectHas(test, sent[3], "ALREADY IN THE GRAPH");
      expectHas(test, sent[3], "[1] goal: Fill the kettle\\n  [2] option: Leave it cold");
      expectHas(test, sent[3], "## Section 2: The thermostat");
    }

    test("a rebuild replaces the graph rather than stacking a second one") { test =>
      let fx = fxRead();
      let script = [
        ok(narrativesReply()),
        ok(fakeCalls([dgAddCall("goal", "G")])), dgStop(),
        ok(fakeCalls([dgAddCall("goal", "H")])), dgStop(),
      ];
      decisionGraphBuild(fx.db, llmFakeScript(script), fx.work, null);
      expectInt(test, worksNodes(fx.db, fx.work.id).length, 2);
      let r = decisionGraphBuild(fx.db, llmFakeScript(script), fx.work, null);
      expectInt(test, worksNodes(fx.db, fx.work.id).length, 2);
      expectInt(test, r.events, 2);
    }

    test("pass A failing leaves the read alone and reports why") { test =>
      let fx = fxRead();
      let r = decisionGraphBuild(fx.db, llmFakeScript([ok(fakeContent("{\"narratives\":7}"))]), fx.work, null);
      expectFalse(test, r.ok, "not ok");
      expectText(test, orNull(r.error), ":no_narratives");
      let r2 = decisionGraphBuild(fx.db, llmFakeScript([ok(fakeContent("not json"))]), fx.work, null);
      expectText(test, orNull(r2.error), ":invalid_json");
      let r3 = decisionGraphBuild(fx.db, llmFakeScript([ok(fakeLength())]), fx.work, null);
      expectText(test, orNull(r3.error), ":truncated");
    }

    test("naming a narrative builds just that one over every section") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(fakeCalls([dgAddCall("goal", "G")])), dgStop()]);
      let r = decisionGraphBuild(fx.db, llm, fx.work, "solo");
      expectTrue(test, r.ok, "ok");
      expectInt(test, r.narratives, 1);
      expectInt(test, llmRequests(llm).length, 2);
      expectHas(test, llmRequests(llm)[0], "NARRATIVE TO BUILD: solo");
      expectHas(test, llmRequests(llm)[0], "## Section 2: The thermostat");
    }

    test("a build bumps the work's version at the start, each call and the end") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(fakeCalls([dgAddCall("goal", "G")])), dgStop()]);
      decisionGraphBuild(fx.db, llm, fx.work, "solo");
      expectInt(test, bumps(fx.db, fx.work), 4);
    }
