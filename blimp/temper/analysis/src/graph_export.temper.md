# The graph export

`Marginalia.Graph` and the three downloads of `GraphController`: the work's
nodes and edges as JSON for the explorers, as Graphviz DOT, and the build
trace. The JSON is what `Jason.encode!(pretty: true)` writes: two-space
indent, `"key": value`, and keys in alphabetical order, because Jason writes a
small map's keys in term order. (The notes list the keys in the order the
Elixir source wrote them; the bytes Jason produced are sorted, and these are
those bytes.)

    let { Db } = import("db/src");
    let {
      Work, Section, GraphNode, GraphEdge, GraphEvent, worksListSections, worksNodes, worksListEdges,
      worksListEvents, worksEventStats,
    } = import("works/src");
    let { sysUtcNow, sysStringReplace, sysGraphemeTake, sysUtf8Downcase } = import("sys/src");
    let { JsonTextProducer, JsonSyntaxTree } = import("std/json");

## Types and colours

The deciduous names the explorers know: the read's own types map onto them.

    export let graphDeciduousType(kind: String): String {
      if (kind == "spine") {
        "goal"
      } else if (kind == "beat") {
        "action"
      } else if (kind == "thread") {
        "observation"
      } else if (kind == "question") {
        "decision"
      } else {
        kind
      }
    }

    export let graphColour(kind: String): String {
      if (kind == "goal") {
        "#8a3324"
      } else if (kind == "option") {
        "#b45309"
      } else if (kind == "decision") {
        "#1e3a8a"
      } else if (kind == "action") {
        "#166534"
      } else if (kind == "outcome") {
        "#0891b2"
      } else if (kind == "observation") {
        "#6b665e"
      } else if (kind == "revisit") {
        "#7c2d92"
      } else if (kind == "spine") {
        "#8a3324"
      } else if (kind == "beat") {
        "#166534"
      } else if (kind == "thread") {
        "#0891b2"
      } else if (kind == "question") {
        "#7c2d92"
      } else {
        "#9a948a"
      }
    }

## Times

A stored time, `YYYY-MM-DD HH:MM:SS`, as the ISO 8601 an Ecto `utc_datetime`
encoded to: `YYYY-MM-DDTHH:MM:SSZ`.

    export let graphIso(at: String): String {
      "${sysStringReplace(at, " ", "T")}Z"
    }

The export time, with the microsecond precision `DateTime.utc_now/0` has (the
clock here has seconds, so the fraction is zero).

    export let graphNow(): String {
      "${sysStringReplace(sysUtcNow(), " ", "T")}.000000Z"
    }

## Nodes

`branch` is `section-<ordinal>` for a node in a section, `spine` for a spine
node, else the type with an `s`.

    let graphBranch(n: GraphNode, section: Section?): String {
      if (section != null) {
        "section-${section.ordinal.toString()}"
      } else if (n.nodeType == "spine") {
        "spine"
      } else {
        "${n.nodeType}s"
      }
    }

    let graphAnchored(n: GraphNode): Boolean {
      let q = n.quote;
      if (q != null) { q != "" } else { false }
    }

`metadata_json`: a JSON string holding a JSON object.

    let graphMetadata(n: GraphNode, section: Section?): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("anchored");
      p.booleanValue(graphAnchored(n));
      p.objectKey("branch");
      p.stringValue(graphBranch(n, section));
      p.objectKey("narrative");
      let nar = n.narrative;
      if (nar != null) { p.stringValue(nar); } else { p.nullValue(); }
      p.objectKey("ordinal");
      p.int32Value(n.ordinal);
      p.objectKey("section");
      if (section != null) { p.stringValue(section.title); } else { p.nullValue(); }
      p.objectKey("status");
      p.stringValue(n.status);
      p.endObject();
      p.toJsonString()
    }

`description`: the body, then (when there is a quote) a `Sources:` footnote
with the quote on one line.

    export let graphDescription(n: GraphNode): String? {
      let q = n.quote;
      if (q != null) {
        if (q != "") {
          let parts = new ListBuilder<String>();
          let b = n.body;
          if (b != null) {
            if (b != "") { parts.add(b); }
          }
          parts.add("Sources:");
          parts.add("- \"${sysStringReplace(q, "\n", " ")}\"");
          return parts.toList().join("\n\n") { (s: String): String => s };
        }
      }
      n.body
    }

    let graphSectionOf(sections: List<Section>, id: Int?): Section? {
      if (id == null) { return null; }
      for (let s of sections) {
        if (s.id == id) { return s; }
      }
      null
    }

    let graphWriteNode(w: AnPretty, n: GraphNode, section: Section?): Void throws Bubble {
      w.pBeginObject();
      w.pKey("body");
      w.pStrOrNull(n.body);
      w.pKey("created_at");
      w.pStr(graphIso(n.insertedAt));
      w.pKey("description");
      w.pStrOrNull(graphDescription(n));
      w.pKey("id");
      w.pInt(n.id);
      w.pKey("marginalia_type");
      w.pStr(n.nodeType);
      w.pKey("metadata_json");
      w.pStr(graphMetadata(n, section));
      w.pKey("narrative");
      w.pStrOrNull(n.narrative);
      w.pKey("node_type");
      w.pStr(graphDeciduousType(n.nodeType));
      w.pKey("quote");
      w.pStrOrNull(n.quote);
      w.pKey("section");
      if (section != null) { w.pStr(section.title); } else { w.pRaw("null"); }
      w.pKey("section_ordinal");
      if (section != null) { w.pInt(section.ordinal); } else { w.pRaw("null"); }
      w.pKey("status");
      w.pStr(n.status);
      w.pKey("title");
      w.pStr(n.title);
      w.pEndObject();
    }

    let graphWriteEdge(w: AnPretty, e: GraphEdge): Void throws Bubble {
      w.pBeginObject();
      w.pKey("created_at");
      w.pStr(graphIso(e.insertedAt));
      w.pKey("edge_type");
      w.pStr(e.edgeType);
      w.pKey("from_node_id");
      w.pInt(e.fromId);
      w.pKey("id");
      w.pInt(e.id);
      w.pKey("rationale");
      w.pStrOrNull(e.rationale);
      w.pKey("to_node_id");
      w.pInt(e.toId);
      w.pKey("weight");
      w.pRaw("1.0");
      w.pEndObject();
    }

## graph.json

`Graph.to_json/1` with the export time supplied, so a test can compare bytes.
Nodes are in `list_nodes` order (ordinal, then id), edges in `list_edges`
order.

    export let graphJsonAt(db: Db, work: Work, exportedAt: String): String throws Bubble {
      let sections = worksListSections(db, work.id);
      let nodes = worksNodes(db, work.id);
      let edges = worksListEdges(db, work.id);
      let w = new AnPretty();
      w.pBeginObject();
      w.pKey("edges");
      w.pBeginArray();
      for (let e of edges) { graphWriteEdge(w, e); }
      w.pEndArray();
      w.pKey("node_themes");
      w.pBeginArray();
      w.pEndArray();
      w.pKey("nodes");
      w.pBeginArray();
      for (let n of nodes) { graphWriteNode(w, n, graphSectionOf(sections, n.sectionId)); }
      w.pEndArray();
      w.pKey("themes");
      w.pBeginArray();
      w.pEndArray();
      w.pKey("work");
      w.pBeginObject();
      w.pKey("exported_at");
      w.pStr(exportedAt);
      w.pKey("first_impression");
      w.pStrOrNull(work.firstImpression);
      w.pKey("id");
      w.pInt(work.id);
      w.pKey("intent");
      w.pStrOrNull(work.intent);
      w.pKey("sections");
      w.pInt(sections.length);
      w.pKey("status");
      w.pStr(work.status);
      w.pKey("title");
      w.pStr(work.title);
      w.pKey("words");
      w.pInt(work.wordCount);
      w.pEndObject();
      w.pEndObject();
      w.toString()
    }

    export let graphJson(db: Db, work: Work): String throws Bubble {
      graphJsonAt(db, work, graphNow())
    }

## graph.dot

Backslash, quote, newline, then the first 90 characters (after escaping).

    export let graphEscape(title: String): String {
      let a = sysStringReplace(title, "\\", "\\\\");
      let b = sysStringReplace(a, "\"", "\\\"");
      let c = sysStringReplace(b, "\n", " ");
      sysGraphemeTake(c, 90)
    }

    export let graphDot(db: Db, work: Work): String throws Bubble {
      let nodes = worksNodes(db, work.id);
      let edges = worksListEdges(db, work.id);
      let lines = new ListBuilder<String>();
      lines.add("digraph marginalia {");
      lines.add("  rankdir=TB;");
      lines.add("  node [shape=box, style=rounded];");
      let ids = new MapBuilder<Int, Boolean>();
      for (let n of nodes) {
        ids.set(n.id, true);
        lines.add("  n${n.id.toString()} [label=\"${graphEscape(n.title)}\", color=\"${graphColour(n.nodeType)}\"];");
      }
      for (let e of edges) {
        if (ids.has(e.fromId) && ids.has(e.toId)) {
          let style = if (e.edgeType == "follows") { "solid" } else { "dashed" };
          lines.add("  n${e.fromId.toString()} -> n${e.toId.toString()} [style=${style}, label=\"${e.edgeType}\"];");
        }
      }
      lines.add("}");
      lines.toList().join("\n") { (s: String): String => s }
    }

## stats

The header of the graph view.

    export class GraphStats(
      public nodes: Int,
      public edges: Int,
      public anchored: Int,
      public byType: Map<String, Int>,
    ) {}

    export let graphStats(db: Db, work: Work): GraphStats throws Bubble {
      let nodes = worksNodes(db, work.id);
      let edges = worksListEdges(db, work.id);
      var anchored = 0;
      let by = new MapBuilder<String, Int>();
      for (let n of nodes) {
        if (graphAnchored(n)) { anchored += 1; }
        by.set(n.nodeType, by.getOr(n.nodeType, 0) + 1);
      }
      new GraphStats(nodes.length, edges.length, anchored, by.toMap())
    }

## trace.json

Every tool call and the server's answer, refusals included: the work, the
counts, and each event with its stored `args` and `result` parsed back (or the
raw text when it does not parse, or null).

    let graphWriteStored(w: AnPretty, text: String?): Void throws Bubble {
      if (text == null) {
        w.pRaw("null");
      } else {
        let tree = anParse(text);
        if (tree != null) { w.pTree(tree); } else { w.pStr(text); }
      }
    }

    let graphWriteCounts(w: AnPretty, counts: Map<String, Int>): Void throws Bubble {
      w.pBeginObject();
      for (let k of dgSorted(counts.keys().toList())) {
        w.pKey(k);
        w.pInt(counts.getOr(k, 0));
      }
      w.pEndObject();
    }

    export let graphTrace(db: Db, work: Work): String throws Bubble {
      let stats = worksEventStats(db, work.id);
      let events = worksListEvents(db, work.id);
      let w = new AnPretty();
      w.pBeginObject();
      w.pKey("events");
      w.pBeginArray();
      for (let e of events) {
        w.pBeginObject();
        w.pKey("args");
        graphWriteStored(w, e.args);
        w.pKey("at");
        w.pStr(graphIso(e.insertedAt));
        w.pKey("narrative");
        w.pStrOrNull(e.narrative);
        w.pKey("ok");
        w.pBool(e.ok);
        w.pKey("result");
        graphWriteStored(w, e.result);
        w.pKey("seq");
        w.pInt(e.seq);
        w.pKey("tool");
        w.pStr(e.tool);
        w.pEndObject();
      }
      w.pEndArray();
      w.pKey("stats");
      w.pBeginObject();
      w.pKey("by_tool");
      graphWriteCounts(w, stats.byTool);
      w.pKey("calls");
      w.pInt(stats.calls);
      w.pKey("refusals");
      graphWriteCounts(w, stats.refusals);
      w.pKey("refused");
      w.pInt(stats.refused);
      w.pEndObject();
      w.pKey("work");
      w.pBeginObject();
      w.pKey("id");
      w.pInt(work.id);
      w.pKey("title");
      w.pStr(work.title);
      w.pEndObject();
      w.pEndObject();
      w.toString()
    }

## The download name

`slug(work)` of the controller: lower-cased, every run of characters outside
`a-z0-9` one hyphen, hyphens trimmed from the ends, cut to 50, `draft` if
nothing is left. The three files are `<slug>-graph.json`, `<slug>-graph.dot`
and `<slug>-trace.json`.

    export let graphSlug(title: String): String {
      let lower = sysUtf8Downcase(title);
      let out = new StringBuilder();
      var inRun = false;
      var i = String.begin;
      while (lower.hasIndex(i)) {
        let c = lower[i];
        let keep = (c >= 97 && c <= 122) || (c >= 48 && c <= 57);
        if (keep) {
          out.appendBetween(lower, i, lower.next(i));
          inRun = false;
        } else if (!inRun) {
          out.append("-");
          inRun = true;
        }
        i = lower.next(i);
      }
      var s = out.toString();
      while (s.hasIndex(String.begin) && s[String.begin] == 45) {
        s = s.slice(s.next(String.begin), s.end);
      }
      while (s.end > String.begin && s[s.prev(s.end)] == 45) {
        s = s.slice(String.begin, s.prev(s.end));
      }
      let cut = sysGraphemeTake(s, 50);
      if (cut.isEmpty) { "draft" } else { cut }
    }
