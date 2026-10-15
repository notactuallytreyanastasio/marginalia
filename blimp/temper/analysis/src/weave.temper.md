# The weave

`Marginalia.Analysis.Weave`: pass 3. The first two passes leave a map whose only
edges are document order and the spine's own chain. This pass asks the model
what leads to what, and keeps the edges that are real: ids that exist, types
from the vocabulary, direction forward in time.

    let { Db } = import("db/src");
    let {
      Work, Section, GraphNode, worksNodes, worksListSections, worksLink, graphWeaveTypes,
    } = import("works/src");
    let { LlmClient, LlmCall, LlmMessage, LlmError } = import("llm/src");
    let { sysJoin, sysGraphemeTake } = import("sys/src");
    let { JsonSyntaxTree, JsonObject, JsonString, JsonInt32 } = import("std/json");

The edge types, `Weave.types/0`.

    export let weaveTypes(): List<String> { graphWeaveTypes() }

How many edges are kept.

    export let weaveMaxEdges(): Int { 160 }

`Weave.passes/0`.

    export let weavePass(): AnalysisPass {
      new AnalysisPass(
        "weave",
        "Pass 3 \u{2014} what leads to what",
        analysisDefaultModel(),
        "once, over the whole map",
        "cross-section edges: develops, pays_off, requires, tension, realises",
        weavePrompt(),
      )
    }

    export let weavePasses(): List<AnalysisPass> { [weavePass()] }

## The inventory

` \u{2014} ` and the first 160 graphemes of a body, when there is one.

    let weaveNote(n: GraphNode): String {
      let b = n.body;
      if (b != null) {
        if (b != "") { return " \u{2014} ${sysGraphemeTake(b, 160)}"; }
      }
      ""
    }

    let weaveLine(n: GraphNode): String {
      "  [${n.id.toString()}] ${n.title}${weaveNote(n)}"
    }

    let weaveLoose(nodes: List<GraphNode>, kind: String, label: String): String {
      let lines = new ListBuilder<String>();
      for (let n of nodes) {
        if (n.nodeType == kind) { lines.add(weaveLine(n)); }
      }
      if (lines.length == 0) { "" } else { "\n\n## ${label}\n${sysJoin(lines.toList(), "\n")}" }
    }

What the model is shown: each section's beats with their ids, then the spine,
the threads and the open questions.

    export let weaveInventory(work: Work, sections: List<Section>, nodes: List<GraphNode>): String {
      let blocks = new ListBuilder<String>();
      for (let s of sections) {
        let lines = new ListBuilder<String>();
        for (let n of nodes) {
          if (n.nodeType == "beat" && n.sectionId == s.id) { lines.add(weaveLine(n)); }
        }
        blocks.add("## Section ${s.ordinal.toString()}: ${s.title}\n${sysJoin(lines.toList(), "\n")}");
      }
      let beats = sysJoin(blocks.toList(), "\n\n");
      let intent = anIntent("Intended effect on a reader: ", work.intent);
      let loose = "${weaveLoose(nodes, "spine", "Spine")}${weaveLoose(nodes, "thread", "Threads")}${weaveLoose(nodes, "question", "Open questions")}";
      "Manuscript: ${work.title}\n${intent}\n${beats}${loose}\n"
    }

## Normalising an edge

    class WeaveEdge(public from: Int, public to: Int, public kind: String, public why: String?) {}

`as_id`: an integer as it is; a string with its leading `[` characters
stripped and a leading integer parsed; anything else is nothing.

    export let weaveAsId(t: JsonSyntaxTree?): Int? {
      if (t is JsonInt32) {
        t.content
      } else if (t is JsonString) {
        var s = t.content;
        while (s.hasIndex(String.begin) && s[String.begin] == 91) {
          s = s.slice(s.next(String.begin), s.end);
        }
        anParseInt(s)
      } else {
        null
      }
    }

`why`: whitespace collapsed, trimmed, the first 400 graphemes; not a string or
empty is nothing.

    let weaveWhy(t: JsonSyntaxTree?): String? {
      let w = anStr(t);
      if (w != null) {
        if (w != "") { return sysGraphemeTake(anCollapse(w), 400); }
      }
      null
    }

    let weaveSectionKey(n: GraphNode): Int {
      let s = n.sectionId;
      if (s != null) { s } else { 0 }
    }

    class WeavePositions(public byId: Map<Int, GraphNode>, public pos: Map<Int, Int>) {}

Document position of each beat, for the temporal rule: sorted by section,
ordinal, id. Spine and thread nodes have none.

    let weavePositions(nodes: List<GraphNode>): WeavePositions {
      let byId = new MapBuilder<Int, GraphNode>();
      let beats = new ListBuilder<GraphNode>();
      for (let n of nodes) {
        byId.set(n.id, n);
        if (n.nodeType == "beat") { beats.add(n); }
      }
      let sorted = beats.toList().sorted { (a: GraphNode, b: GraphNode): Int =>
        let sa = weaveSectionKey(a);
        let sb = weaveSectionKey(b);
        if (sa != sb) { sa - sb } else if (a.ordinal != b.ordinal) { a.ordinal - b.ordinal } else { a.id - b.id }
      };
      let pos = new MapBuilder<Int, Int>();
      var i = 0;
      while (i < sorted.length) {
        pos.set(sorted[i].id, i);
        i += 1;
      }
      new WeavePositions(byId.toMap(), pos.toMap())
    }

The edge as stored, or null when it is thrown away: an id missing, the same
id twice, an id that is not a node of this work, a type outside the six. Time
flows forward: between two beats the edge runs earlier to later, so a backwards
one is flipped rather than discarded. `realises` and `asks_about` are exempt,
as they start at a node with no place on the page.

    let weaveNormalise(edge: JsonObject, p: WeavePositions): WeaveEdge? {
      let from = weaveAsId(anField(edge, "from"));
      let to = weaveAsId(anField(edge, "to"));
      let kind = anStr(anField(edge, "type"));
      if (from != null) {
        if (to != null) {
          if (kind != null) {
            return weaveBuild(edge, p, from, to, kind);
          }
        }
      }
      null
    }

    let weaveBuild(edge: JsonObject, p: WeavePositions, from: Int, to: Int, kind: String): WeaveEdge? {
      if (from == to) { return null; }
      if (!p.byId.has(from) || !p.byId.has(to)) { return null; }
      if (!anIn(weaveTypes(), kind)) { return null; }
      let why = weaveWhy(anField(edge, "why"));
      if (kind == "realises" || kind == "asks_about") {
        return new WeaveEdge(from, to, kind, why);
      }
      let a = p.pos.getOr(from, -1);
      let b = p.pos.getOr(to, -1);
      if (a >= 0 && b >= 0 && a > b) { new WeaveEdge(to, from, kind, why) } else { new WeaveEdge(from, to, kind, why) }
    }

Normalise, drop duplicates of (from, to, type), keep the first 160, store each
with ordinal `1000 + i`. The count is of links made, a duplicate of an edge
already in the table included, as the Elixir's `{:ok, _}` was.

    let weaveStore(db: Db, work: Work, nodes: List<GraphNode>, edges: List<JsonSyntaxTree>): Int throws Bubble {
      let p = weavePositions(nodes);
      let seen = new MapBuilder<String, Boolean>();
      let kept = new ListBuilder<WeaveEdge>();
      for (let e of edges) {
        if (e is JsonObject) {
          let n = weaveNormalise(e, p);
          if (n != null) {
            let key = "${n.from.toString()}:${n.to.toString()}:${n.kind}";
            if (!seen.has(key) && kept.length < weaveMaxEdges()) {
              seen.set(key, true);
              kept.add(n);
            }
          }
        }
      }
      var stored = 0;
      var i = 0;
      while (i < kept.length) {
        let k = kept[i];
        let r = worksLink(db, work.id, k.from, k.to, k.kind, 1000 + i, k.why);
        if (r.errors.length == 0) { stored += 1; }
        i += 1;
      }
      stored
    }

## Run

Draw the cross-section connections for a work that has been read. A work with
fewer than two beats has nothing to connect (`ok`, zero). A reply without an
`edges` list is `:no_edges`. A failure here degrades the read, it does not
void it.

    export let weaveRun(db: Db, llm: LlmClient, work: Work): WeaveResult throws Bubble {
      let nodes = worksNodes(db, work.id);
      let sections = worksListSections(db, work.id);
      var beats = 0;
      for (let n of nodes) {
        if (n.nodeType == "beat") { beats += 1; }
      }
      if (beats < 2) { return new WeaveResult(true, 0, null); }
      let call = new LlmCall(
        [new LlmMessage("system", weavePrompt()), new LlmMessage("user", weaveInventory(work, sections, nodes))],
        null,
        "high",
        8000,
        0.4,
        true,
        [],
        null,
        0,
      );
      let r = llm.json(call);
      let data = r.ok;
      if (data != null) {
        let edges = anElements(anField(data, "edges"));
        if (edges != null) {
          new WeaveResult(true, weaveStore(db, work, nodes, edges), null)
        } else {
          new WeaveResult(false, 0, ":no_edges")
        }
      } else {
        let e: LlmError? = r.err;
        new WeaveResult(false, 0, if (e != null) { anInspect(e) } else { "unknown" })
      }
    }
