# The decision graph

`Marginalia.Analysis.DecisionGraph`: the `/decision-graph` methodology as tool
calls the server runs itself. The model is handed three tools (`add_node`,
`link`, `set_status`) and the server executes each against the database,
refusing what breaks a rule. Three rules are enforced in code, not asked for in
the prompt:

* the flow rule: goal, options, decision, actions, outcomes; a goal never
  leads straight to a decision;
* the temporal rule, which is the same table: only the steps in the flow are
  legal, so an option cannot be linked to an earlier decision;
* grounding: a node's quote must be in the draft word for word, or the node is
  refused at the tool boundary and the model is told why.

The imports.

    let { Db } = import("db/src");
    let { FieldError } = import("core/src");
    let {
      Work, Section, GraphNode, NodeParams, NodeResult, EventParams, worksListSections, worksNodes,
      worksListNodes, worksInsertNode, worksLink, worksSetNodeStatus, worksRecordEvent,
      worksResetDecisionGraph, worksListEvents, graphNodeStatuses,
    } = import("works/src");
    let { LlmClient, LlmCall, LlmMessage, LlmTool, LlmToolCall, LlmError, LlmReply } = import("llm/src");
    let { sysJoin } = import("sys/src");
    let {
      JsonSyntaxTree, JsonObject, JsonString, JsonInt32, JsonNull, JsonTextProducer, parseJson,
    } = import("std/json");

The most calls the model gets for one narrative.

    export let decisionGraphMaxIterations(): Int { 24 }

## The flow

The types a node of the key type may point at.

    export let decisionGraphFlowOf(kind: String): List<String> {
      if (kind == "goal") {
        ["option", "observation"]
      } else if (kind == "option") {
        ["decision", "observation"]
      } else if (kind == "decision") {
        ["action", "option", "observation", "outcome"]
      } else if (kind == "action") {
        ["outcome", "observation", "action"]
      } else if (kind == "outcome") {
        ["observation", "revisit", "decision", "goal"]
      } else if (kind == "observation") {
        ["decision", "goal", "observation", "revisit", "action", "outcome", "option"]
      } else if (kind == "revisit") {
        ["decision", "goal", "observation"]
      } else {
        []
      }
    }

    export let decisionGraphFlowTypes(): List<String> {
      ["goal", "option", "decision", "action", "outcome", "observation", "revisit"]
    }

## The tools

    export let decisionGraphTools(): List<LlmTool> {
      [
        new LlmTool(
          "add_node",
          "Add one node to the decision graph. Returns its id, which you use for linking. Equivalent to `deciduous add <type> \"<title>\"`.",
          decisionGraphAddNodeParameters(),
        ),
        new LlmTool(
          "link",
          "Connect two nodes: from leads_to to. Equivalent to `deciduous link <from> <to> -r \"<why>\"`. Refused if it breaks the flow rule or the temporal rule.",
          decisionGraphLinkParameters(),
        ),
        new LlmTool(
          "set_status",
          "Mark an option chosen or rejected, or a node superseded. Equivalent to `deciduous status <id> <status>`.",
          decisionGraphSetStatusParameters(),
        ),
      ]
    }

    export let decisionGraphPasses(): List<AnalysisPass> {
      [
        new AnalysisPass(
          "narratives",
          "Pass A \u{2014} find the narratives",
          analysisDefaultModel(),
          "once, over every section's beats",
          "3-7 narratives with their arcs, and the spine",
          decisionGraphNarrativePrompt(),
        ),
        new AnalysisPass(
          "decision_graph",
          "Pass B \u{2014} build the decision graph",
          analysisDefaultModel(),
          "once per narrative, as tool calls the server executes",
          "goal / option / decision / action / outcome nodes and their edges",
          decisionGraphPrompt(),
        ),
      ]
    }

## State

What one narrative's loop carries: the work, the narrative's name, the
sections it runs through, every node id made so far in the run (with its
type), the sequence number of the next trace row, and the calls the server has
already refused. `nodes` is threaded from one narrative to the next, so a later
chain can link back into an earlier one.

    export class DecisionGraphState(
      public work: Work,
      public narrative: String,
      public sections: List<Section>,
      public nodes: MapBuilder<Int, String>,
    ) {
      public var seq: Int = 0;
      public refused: MapBuilder<String, Boolean> = new MapBuilder<String, Boolean>();
      public anchors: MapBuilder<Int, AnchorIndex> = new MapBuilder<Int, AnchorIndex>();
    }

A fresh state over `known` (id to type), which is copied.

    export let decisionGraphState(
      work: Work, narrative: String, sections: List<Section>, known: Map<Int, String>,
    ): DecisionGraphState {
      let nodes = new MapBuilder<Int, String>();
      for (let k of known.keys().toList()) { nodes.set(k, known.getOr(k, "")); }
      new DecisionGraphState(work, narrative, sections, nodes)
    }

    export let decisionGraphKnown(state: DecisionGraphState): Map<Int, String> {
      state.nodes.toMap()
    }

## Answers

The text of a tool's answer plus whether it was a refusal and the node it made.

    export class DecisionGraphAnswer(public json: String, public error: Boolean, public nodeId: Int?) {}

Jason writes a map's keys alphabetically, so each answer is written with its
keys in that order.

    let dgError(message: String): DecisionGraphAnswer throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("error");
      p.stringValue(message);
      p.endObject();
      new DecisionGraphAnswer(p.toJsonString(), true, null)
    }

    let dgStrings(p: JsonTextProducer, xs: List<String>): Void {
      p.startArray();
      for (let x of xs) { p.stringValue(x); }
      p.endArray();
    }

    let dgSorted(xs: List<String>): List<String> {
      xs.sorted { (a: String, b: String): Int =>
        if (a == b) { 0 } else if (a < b) { -1 } else { 1 }
      }
    }

## Finding things

An `add_node` argument that is an integer or an integer in a string, matched
against the ordinals of this narrative's sections only.

    let dgFindSection(sections: List<Section>, t: JsonSyntaxTree?): Section? {
      var ordinal: Int? = null;
      if (t is JsonInt32) {
        ordinal = t.content;
      } else if (t is JsonString) {
        ordinal = anParseInt(t.content);
      }
      if (ordinal != null) {
        for (let s of sections) {
          if (s.ordinal == ordinal) { return s; }
        }
      }
      null
    }

    let dgIndexOf(state: DecisionGraphState, s: Section): AnchorIndex {
      let have = state.anchors.getOr(s.id, new AnchorIndex("", [], []));
      if (have.text == "" && s.body != "") {
        let built = anchorPrepare(s.body);
        state.anchors.set(s.id, built);
        built
      } else {
        have
      }
    }

    let dgVerify(state: DecisionGraphState, s: Section, quote: String): AnchorResult {
      anchorVerifyIn(quote, s.body, dgIndexOf(state, s))
    }

The first of the narrative's sections the quote verifies in.

    let dgAnySection(state: DecisionGraphState, quote: String): AnchorResult {
      for (let s of state.sections) {
        let r = dgVerify(state, s, quote);
        if (r.ok) { return r; }
      }
      new AnchorResult(false, "")
    }

## add_node

`repair`: the title written under the node type's own key
(`{"action": "Name the method"}`) is a real thing a real run produced. The
title is a label, not a claim, so recovering it costs nothing the quote check
protects.

    class DgTitle(public title: String, public movedKey: String?) {}

    let dgTitle(args: JsonObject): DgTitle {
      let chosen = anStr(anField(args, "title"));
      if (chosen != null) {
        if (chosen != "") { return new DgTitle(chosen, null); }
      }
      let kind = anStr(anField(args, "type"));
      if (kind != null) {
        let moved = anStr(anField(args, kind));
        if (moved != null) {
          if (moved != "") { return new DgTitle(moved, kind); }
        }
      }
      new DgTitle(if (chosen != null) { chosen } else { "" }, null)
    }

The keys the model sent, as `Map.keys(args)` of the repaired arguments.

    let dgSentKeys(args: JsonObject, t: DgTitle): List<String> {
      let keys = new ListBuilder<String>();
      let moved = t.movedKey;
      for (let k of anKeys(args)) {
        if (moved == null || k != moved) { keys.add(k); }
      }
      if (moved != null && !anIn(keys.toList(), "title")) { keys.add("title"); }
      dgSorted(keys.toList())
    }

`%{field: ["message"]}` as Elixir prints a changeset's error map.

    let dgInspectErrors(errors: List<FieldError>): String {
      let fields = new ListBuilder<String>();
      for (let e of errors) {
        if (!anIn(fields.toList(), e.field)) { fields.add(e.field); }
      }
      let parts = new ListBuilder<String>();
      for (let f of dgSorted(fields.toList())) {
        let messages = new ListBuilder<String>();
        for (let e of errors) {
          if (e.field == f) { messages.add("\"${e.message}\""); }
        }
        parts.add("${f}: [${sysJoin(messages.toList(), ", ")}]");
      }
      "%{${sysJoin(parts.toList(), ", ")}}"
    }

    let dgAddNode(db: Db, args: JsonObject, state: DecisionGraphState): DecisionGraphAnswer throws Bubble {
      let t = dgTitle(args);
      let section = dgFindSection(state.sections, anField(args, "section"));
      let q = anField(args, "quote");
      var anchored = new AnchorResult(true, "");
      var quote: String? = null;
      if (q is JsonString) {
        if (q.content != "") {
          anchored = if (section != null) {
            dgVerify(state, section, q.content)
          } else {
            dgAnySection(state, q.content)
          };
          quote = anchored.span;
        }
      } else if (q != null && !(q is JsonNull)) {
        anchored = new AnchorResult(false, "");
      }
      if (!anchored.ok) {
        let p = new JsonTextProducer();
        p.startObject();
        p.objectKey("error");
        p.stringValue("quote not found in the draft, character for character. The node was not added.");
        p.objectKey("hint");
        p.stringValue("Copy the span exactly, including punctuation, or omit quote if this node is structural.");
        p.endObject();
        return new DecisionGraphAnswer(p.toJsonString(), true, null);
      }
      let kind = anOrEmpty(anStr(anField(args, "type")));
      let params = new NodeParams(state.work.id, kind, t.title);
      if (section != null) { params.sectionId = section.id; }
      params.body = anStr(anField(args, "description"));
      params.quote = quote;
      let chosen = anStr(anField(args, "narrative"));
      params.narrative = if (chosen != null) { chosen } else { state.narrative };
      params.ordinal = state.nodes.length;
      let r = worksInsertNode(db, params);
      let node = r.node;
      if (node != null) {
        state.nodes.set(node.id, node.nodeType);
        let p = new JsonTextProducer();
        p.startObject();
        p.objectKey("added");
        p.stringValue(node.title);
        p.objectKey("id");
        p.int32Value(node.id);
        p.objectKey("type");
        p.stringValue(node.nodeType);
        p.endObject();
        new DecisionGraphAnswer(p.toJsonString(), false, node.id)
      } else {
        let p = new JsonTextProducer();
        p.startObject();
        p.objectKey("error");
        p.stringValue("rejected: ${dgInspectErrors(r.errors)}");
        p.objectKey("hint");
        p.stringValue("add_node takes type, title, description, quote, section, narrative.");
        p.objectKey("you_sent");
        dgStrings(p, dgSentKeys(args, t));
        p.endObject();
        new DecisionGraphAnswer(p.toJsonString(), true, null)
      }
    }

## link

The commonest refusal in a real run was `outcome -> action`. The rule is
right, but a bare refusal makes the model guess; naming the one-hop detour
turns the refusal into an instruction.

    export let decisionGraphRoute(from: String, to: String): String? {
      let vias = decisionGraphFlowOf(from);
      var i = 0;
      while (i < vias.length) {
        let via = vias[i];
        if (anIn(decisionGraphFlowOf(via), to)) {
          return "go through a ${via}: link the ${from} to a ${via}, then that ${via} to the ${to}.";
        }
        i += 1;
      }
      null
    }

    let dgKnownIds(state: DecisionGraphState): List<Int> {
      state.nodes.toMap().keys().toList().sorted { (a: Int, b: Int): Int => a - b }
    }

    let dgTypeOf(state: DecisionGraphState, id: Int?): String? {
      if (id != null) {
        if (state.nodes.has(id)) { return state.nodes.getOr(id, ""); }
      }
      null
    }

    let dgLink(db: Db, args: JsonObject, state: DecisionGraphState): DecisionGraphAnswer throws Bubble {
      let from = anInt(anField(args, "from"));
      let to = anInt(anField(args, "to"));
      let fromType = dgTypeOf(state, from);
      let toType = dgTypeOf(state, to);
      if (from != null) {
        if (to != null) {
          if (fromType != null) {
            if (toType != null) {
              return dgLinkKnown(db, args, state, from, to, fromType, toType);
            }
          }
        }
      }
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("error");
      p.stringValue("unknown node id. Link nodes you created in this run \u{2014} this narrative, or one listed under ALREADY IN THE GRAPH.");
      p.objectKey("known");
      p.startArray();
      for (let id of dgKnownIds(state)) { p.int32Value(id); }
      p.endArray();
      p.endObject();
      new DecisionGraphAnswer(p.toJsonString(), true, null)
    }

    let dgLinkKnown(
      db: Db, args: JsonObject, state: DecisionGraphState, from: Int, to: Int, fromType: String, toType: String,
    ): DecisionGraphAnswer throws Bubble {
      if (fromType == "goal" && toType == "decision") {
        return dgError("the flow rule: a goal cannot lead straight to a decision. Add the options it was choosing between, link the goal to each option, then link the options to the decision.");
      }
      if (!anIn(decisionGraphFlowOf(fromType), toType)) {
        let p = new JsonTextProducer();
        p.startObject();
        p.objectKey("allowed");
        dgStrings(p, decisionGraphFlowOf(fromType));
        p.objectKey("error");
        p.stringValue("${fromType} -> ${toType} is not a step in goal -> option -> decision -> action -> outcome");
        p.objectKey("route");
        let route = decisionGraphRoute(fromType, toType);
        if (route != null) { p.stringValue(route); } else { p.nullValue(); }
        p.endObject();
        return new DecisionGraphAnswer(p.toJsonString(), true, null);
      }
      worksLink(db, state.work.id, from, to, "leads_to", state.nodes.length, anStr(anField(args, "rationale")));
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("linked");
      p.stringValue("${from.toString()} -> ${to.toString()}");
      p.endObject();
      new DecisionGraphAnswer(p.toJsonString(), false, null)
    }

## set_status

An invalid status is a changeset error; Elixir prints the whole changeset
struct. This is that text for the one error a status can have.

    let dgChangesetText(status: String): String throws Bubble {
      let enums = new ListBuilder<String>();
      for (let s of graphNodeStatuses()) { enums.add("\"${s}\""); }
      "#Ecto.Changeset<action: :update, changes: %{status: ${anQuote(status)}}, errors: [status: {\"is invalid\", [validation: :inclusion, enum: [${sysJoin(enums.toList(), ", ")}]]}], data: #Marginalia.Works.Node<>, valid?: false>"
    }

    let dgSetStatus(db: Db, args: JsonObject, state: DecisionGraphState): DecisionGraphAnswer throws Bubble {
      let id = anInt(anField(args, "id"));
      let status = anStr(anField(args, "status"));
      if (id != null) {
        if (status != null) { return dgSetStatusOf(db, state, id, status); }
      }
      dgError(":not_found")
    }

    let dgSetStatusOf(db: Db, state: DecisionGraphState, id: Int, status: String): DecisionGraphAnswer throws Bubble {
      let r = worksSetNodeStatus(db, state.work.id, id, status);
      if (r.notFound) { return dgError(":not_found"); }
      if (r.errors.length > 0) { return dgError(dgChangesetText(status)); }
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("ok");
      p.stringValue("${id.toString()} is ${status}");
      p.endObject();
      new DecisionGraphAnswer(p.toJsonString(), false, null)
    }

## One call

`execute/2`. Parse the arguments (a non-object is empty), refuse an exact
repeat of a call already refused, otherwise run the tool; remember a refusal;
record the call and its answer in the trace; answer with the JSON text that
goes back to the model. Public so tests can drive the tools the way the model
would.

    let dgEmpty(): JsonObject {
      let tree = parseJson("{}") orelse panic();
      tree as JsonObject orelse panic()
    }

    let dgRepeat(): DecisionGraphAnswer throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("error");
      p.stringValue("you already sent this exact call and it was refused. Change it or move on.");
      p.objectKey("repeat");
      p.booleanValue(true);
      p.endObject();
      new DecisionGraphAnswer(p.toJsonString(), true, null)
    }

    let dgRun(db: Db, fname: String, args: JsonObject, state: DecisionGraphState): DecisionGraphAnswer throws Bubble {
      if (fname == "add_node") {
        dgAddNode(db, args, state)
      } else if (fname == "link") {
        dgLink(db, args, state)
      } else if (fname == "set_status") {
        dgSetStatus(db, args, state)
      } else {
        dgError("unknown tool ${fname}")
      }
    }

    export let decisionGraphExecute(db: Db, call: LlmToolCall, state: DecisionGraphState): String throws Bubble {
      let parsed = anParse(call.argumentsJson);
      let args = if (parsed is JsonObject) { parsed } else { dgEmpty() };
      let canon = anCanon(args);
      let key = "${call.name}\n${canon}";
      let result = if (state.refused.has(key)) {
        dgRepeat()
      } else {
        dgRun(db, call.name, args, state)
      };
      if (result.error) { state.refused.set(key, true); }
      let ev = new EventParams(state.work.id, call.name);
      ev.narrative = state.narrative;
      ev.seq = state.seq;
      ev.args = canon;
      ev.result = result.json;
      ev.ok = !result.error;
      ev.nodeId = result.nodeId;
      worksRecordEvent(db, ev);
      analysisBump(db, state.work.id);
      state.seq = state.seq + 1;
      result.json
    }

## The prompts' user messages

`Marginalia.Analysis.DecisionGraph.find_narratives`: the beat titles by
section.

    export let decisionGraphNarrativeUser(work: Work, sections: List<Section>, beats: List<GraphNode>): String {
      let blocks = new ListBuilder<String>();
      for (let s of sections) {
        let lines = new ListBuilder<String>();
        for (let b of beats) {
          if (b.sectionId == s.id) { lines.add("  - ${b.title}"); }
        }
        blocks.add("## Section ${s.ordinal.toString()}: ${s.title}\n${sysJoin(lines.toList(), "\n")}");
      }
      let intent = anIntent("Intended effect on a reader: ", work.intent);
      "Manuscript: ${work.title}\n${intent}\n${sysJoin(blocks.toList(), "\n\n")}\n"
    }

What the previous narratives built, so this one can join onto it.

    export let decisionGraphAlready(work: Work, everyNode: List<GraphNode>, known: Map<Int, String>): String {
      if (known.keys().toList().length == 0) { return ""; }
      let titles = new ListBuilder<String>();
      for (let n of everyNode) {
        if (known.has(n.id)) { titles.add("  [${n.id.toString()}] ${n.nodeType}: ${n.title}"); }
      }
      "\nALREADY IN THE GRAPH, from the narratives built before this one. You may link to any of\nthese ids. Do it where this narrative genuinely grows out of, answers, or complicates one\nof them ${anDash()} that connection is the whole reason the graph is a graph and not a list of\nseparate trees. Do not link for the sake of it.\n\n${sysJoin(titles.toList(), "\n")}\n"
    }

    export let decisionGraphUser(narrativeName: String, arc: String, already: String, relevant: List<Section>, work: Work): String {
      let blocks = new ListBuilder<String>();
      for (let s of relevant) {
        blocks.add("## Section ${s.ordinal.toString()}: ${s.title}\n${s.body}");
      }
      "Manuscript: ${work.title}\n\nNARRATIVE TO BUILD: ${narrativeName}\n${arc}\n${already}\nThe sections it runs through are below in full. Build this narrative's chain with the tools.\n\n${sysJoin(blocks.toList(), "\n\n")}\n"
    }

## The loop

The tool calls of a reply as the OpenAI wire spells them, so the assistant turn
can be sent back.

    let dgCallsJson(calls: List<LlmToolCall>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      for (let c of calls) {
        p.startObject();
        p.objectKey("function");
        p.startObject();
        p.objectKey("arguments");
        p.stringValue(c.argumentsJson);
        p.objectKey("name");
        p.stringValue(c.name);
        p.endObject();
        p.objectKey("id");
        p.stringValue(c.id);
        p.objectKey("type");
        p.stringValue("function");
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

One narrative. Ask with the tools; execute every call of a reply in order and
send back the assistant turn and every result; stop when the model stops
calling tools, on an error (the partial graph is kept, no retry), or after 24
calls. Answers the ids known afterwards.

    let dgTurn(db: Db, state: DecisionGraphState, messages: ListBuilder<LlmMessage>, reply: LlmReply): Void throws Bubble {
      let assistant = new LlmMessage("assistant", anOrEmpty(reply.content));
      assistant.toolCallsJson = dgCallsJson(reply.toolCalls);
      let results = new ListBuilder<LlmMessage>();
      for (let c of reply.toolCalls) {
        let content = decisionGraphExecute(db, c, state);
        let m = new LlmMessage("tool", content);
        m.toolCallId = c.id;
        results.add(m);
      }
      messages.add(assistant);
      for (let m of results.toList()) { messages.add(m); }
    }

    export let decisionGraphLoop(db: Db, llm: LlmClient, state: DecisionGraphState, start: List<LlmMessage>): Map<Int, String> throws Bubble {
      let messages = new ListBuilder<LlmMessage>();
      for (let m of start) { messages.add(m); }
      var n = 0;
      while (n < decisionGraphMaxIterations()) {
        let call = new LlmCall(messages.toList(), null, "high", 4000, 0.4, false, decisionGraphTools(), null, 0);
        let r = llm.chat(call);
        let reply = r.ok;
        if (reply != null) {
          if (reply.toolCalls.length == 0) {
            analysisBump(db, state.work.id);
            return state.nodes.toMap();
          }
          dgTurn(db, state, messages, reply);
        } else {
          let e: LlmError? = r.err;
          console.log("marginalia: graph pass failed: ${if (e != null) { anInspect(e) } else { "unknown" }}");
          return state.nodes.toMap();
        }
        n += 1;
      }
      console.log("marginalia: narrative ${state.narrative} hit the tool-call ceiling");
      state.nodes.toMap()
    }

## Pass A

    class DgNarrative(public label: String, public arc: String, public ordinals: List<Int>?) {}

    let dgNarratives(items: List<JsonSyntaxTree>): List<DgNarrative> {
      let out = new ListBuilder<DgNarrative>();
      for (let it of items) {
        if (it is JsonObject) {
          let label = anStr(anField(it, "name"));
          let arc = anStr(anField(it, "arc"));
          var ordinals: List<Int>? = null;
          let raw = anElements(anField(it, "sections"));
          if (raw != null) {
            let ns = new ListBuilder<Int>();
            for (let r of raw) {
              let v = anInt(r);
              if (v != null) { ns.add(v); }
            }
            if (raw.length > 0) { ordinals = ns.toList(); }
          }
          out.add(new DgNarrative(if (label != null) { label } else { "untitled" }, anOrEmpty(arc), ordinals));
        }
      }
      out.toList()
    }

    class DgFound(public narratives: List<DgNarrative>, public error: String?) {}

    let dgFindNarratives(db: Db, llm: LlmClient, work: Work): DgFound throws Bubble {
      let sections = worksListSections(db, work.id);
      let beats = worksListNodes(db, work.id, "beat", null, null);
      let call = new LlmCall(
        [
          new LlmMessage("system", decisionGraphNarrativePrompt()),
          new LlmMessage("user", decisionGraphNarrativeUser(work, sections, beats)),
        ],
        null,
        "high",
        4000,
        0.4,
        true,
        [],
        null,
        0,
      );
      let r = llm.json(call);
      let data = r.ok;
      if (data != null) {
        let items = anElements(anField(data, "narratives"));
        if (items != null) {
          new DgFound(dgNarratives(items), null)
        } else {
          new DgFound([], ":no_narratives")
        }
      } else {
        let e: LlmError? = r.err;
        new DgFound([], if (e != null) { anInspect(e) } else { "unknown" })
      }
    }

## Pass B

    let dgRelevant(sections: List<Section>, ordinals: List<Int>?): List<Section> {
      if (ordinals != null) {
        let out = new ListBuilder<Section>();
        for (let s of sections) {
          var wanted = false;
          for (let o of ordinals) {
            if (o == s.ordinal) { wanted = true; }
          }
          if (wanted) { out.add(s); }
        }
        out.toList()
      } else {
        sections
      }
    }

    let dgBuildNarrative(db: Db, llm: LlmClient, work: Work, n: DgNarrative, known: Map<Int, String>): Map<Int, String> throws Bubble {
      let sections = worksListSections(db, work.id);
      let relevant = dgRelevant(sections, n.ordinals);
      let already = decisionGraphAlready(work, worksNodes(db, work.id), known);
      let user = decisionGraphUser(n.label, n.arc, already, relevant, work);
      let state = decisionGraphState(work, n.label, relevant, known);
      decisionGraphLoop(
        db, llm, state,
        [new LlmMessage("system", decisionGraphPrompt()), new LlmMessage("user", user)],
      )
    }

## Build

Replace the work's decision graph: clear the old one (the read stays), find the
narratives, then build each with the tool loop, passing the known ids forward.
`narrative` null runs Pass A; a name builds just that one narrative over every
section. Answers how many narratives were built, or why Pass A failed.

    export let decisionGraphBuild(db: Db, llm: LlmClient, work: Work, narrative: String?): DecisionGraphResult throws Bubble {
      let cleared = worksResetDecisionGraph(db, work.id);
      if (cleared > 0) { console.log("marginalia: cleared ${cleared.toString()} nodes from the previous graph"); }
      analysisBump(db, work.id);
      var found = new DgFound([], null);
      if (narrative != null) {
        found = new DgFound([new DgNarrative(narrative, "", null)], null);
      } else {
        found = dgFindNarratives(db, llm, work);
      }
      let why = found.error;
      if (why != null) {
        console.log("marginalia: decision graph failed: ${why}");
        analysisBump(db, work.id);
        return new DecisionGraphResult(false, 0, why, 0, 0);
      }
      var known: Map<Int, String> = new MapBuilder<Int, String>().toMap();
      for (let n of found.narratives) {
        known = dgBuildNarrative(db, llm, work, n, known);
      }
      analysisBump(db, work.id);
      new DecisionGraphResult(true, found.narratives.length, null, known.keys().toList().length, worksListEvents(db, work.id).length)
    }
