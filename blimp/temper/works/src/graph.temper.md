# Nodes, edges and the graph build trace

`Marginalia.Works`, the second half: the map built from a draft. Nodes are
the beats, spine, threads and questions of a read and the seven kinds of the
decision graph; edges link them; events are the trace of a decision-graph
build.

    let { Db, DbRow } = import("db/src");
    let { FieldError } = import("core/src");
    let { sysUtcNow, sysUtf8Downcase, sysJoin } = import("sys/src");
    let { dbTransaction } = import("db/src");

## Nodes

`Node.types/0`, and the statuses a node may have.

    export let graphNodeTypes(): List<String> {
      ["goal", "decision", "option", "observation", "action", "outcome", "revisit", "beat", "spine", "thread", "note", "question"]
    }

    export let graphNodeStatuses(): List<String> {
      ["pending", "chosen", "rejected", "superseded", "completed"]
    }

    let worksDecisionTypes(): List<String> {
      ["goal", "option", "decision", "action", "outcome", "observation", "revisit"]
    }

What `Node.changeset` casts. `ordinal` null means "not given" (0, or the
position in an `worksInsertNodes` batch), `status` null means `"pending"`.

    export class NodeParams(public workId: Int, public nodeType: String, public title: String) {
      public var sectionId: Int? = null;
      public var body: String? = null;
      public var quote: String? = null;
      public var ordinal: Int? = null;
      public var status: String? = null;
      public var narrative: String? = null;
    }

    export class NodeResult(
      public node: GraphNode?,
      public errors: List<FieldError>,
      public notFound: Boolean,
    ) {}

    let worksNodesOf(rows: List<DbRow>): List<GraphNode> throws Bubble {
      let out = new ListBuilder<GraphNode>();
      for (let row of rows) { out.add(GraphNode.fromRow(row)); }
      out.toList()
    }

    let worksNodeErrors(nodeType: String, title: String, status: String?): List<FieldError> {
      let errors = new ListBuilder<FieldError>();
      if (worksIsBlank(nodeType)) {
        errors.add(new FieldError("node_type", "can't be blank"));
      } else if (!worksIn(graphNodeTypes(), nodeType)) {
        errors.add(new FieldError("node_type", "is invalid"));
      }
      if (worksIsBlank(title)) { errors.add(new FieldError("title", "can't be blank")); }
      if (status != null) {
        if (!worksIn(graphNodeStatuses(), status)) {
          errors.add(new FieldError("status", "is invalid"));
        }
      }
      errors.toList()
    }

The nodes of a work ordered by node ordinal then id. That orders by ordinal
first, so a mixed-type list interleaves by ordinal, not by section; document
order of beats is `(section_id, ordinal, id)`. Each filter that is not null
narrows the list: `nodeType` equality, `sectionId`, `narrative`.

    export let worksListNodes(
      db: Db, workId: Int, nodeType: String?, sectionId: Int?, narrative: String?,
    ): List<GraphNode> throws Bubble {
      let holders = ["$2", "$3", "$4"];
      let args = worksArgs().n(workId);
      var sql = "SELECT ${graphNodeColumns} FROM nodes WHERE work_id = $1";
      var next = 0;
      if (nodeType != null) {
        sql = "${sql} AND node_type = ${holders[next]}";
        args.s(nodeType);
        next += 1;
      }
      if (sectionId != null) {
        sql = "${sql} AND section_id = ${holders[next]}";
        args.n(sectionId);
        next += 1;
      }
      if (narrative != null) {
        sql = "${sql} AND narrative = ${holders[next]}";
        args.s(narrative);
        next += 1;
      }
      worksNodesOf(db.query("${sql} ORDER BY ordinal ASC, id ASC", args.build()))
    }

    export let worksNodes(db: Db, workId: Int): List<GraphNode> throws Bubble {
      worksListNodes(db, workId, null, null, null)
    }

A node of this work, or null.

    export let worksGetNode(db: Db, workId: Int, id: Int): GraphNode? throws Bubble {
      let row = db.one(
        "SELECT ${graphNodeColumns} FROM nodes WHERE work_id = $1 AND id = $2",
        worksArgs().n(workId).n(id).build(),
      );
      if (row == null) { null } else { GraphNode.fromRow(row) }
    }

Insert one node. The changeset errors come back rather than being swallowed.

    export let worksInsertNode(db: Db, p: NodeParams): NodeResult throws Bubble {
      worksInsertNodeAt(db, p.workId, p.sectionId, p, p.ordinal)
    }

    let worksInsertNodeAt(db: Db, workId: Int, sectionId: Int?, p: NodeParams, ordinal: Int?): NodeResult throws Bubble {
      let errors = worksNodeErrors(p.nodeType, p.title, p.status);
      if (errors.length > 0) { return new NodeResult(null, errors, false); }
      let status = if (p.status != null) { p.status } else { "pending" };
      let place = if (ordinal != null) { ordinal } else { 0 };
      let id = db.insert(
        "INSERT INTO nodes (work_id, section_id, node_type, title, body, quote, ordinal, status, narrative) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
        worksArgs().n(workId).no(sectionId).s(p.nodeType).s(p.title).s(p.body).s(p.quote)
          .n(place).s(status).s(p.narrative).build(),
      );
      new NodeResult(worksGetNode(db, workId, id), [], false)
    }

Mark an option chosen or rejected, or a node superseded. Scoped to the work.
A missing node is `notFound`; a status outside the five is a changeset error
(`status is invalid`) and the node is unchanged.

    export let worksSetNodeStatus(db: Db, workId: Int, nodeId: Int, status: String): NodeResult throws Bubble {
      let node = worksGetNode(db, workId, nodeId);
      if (node != null) {
        let errors = worksNodeErrors(node.nodeType, node.title, status);
        if (errors.length > 0) { return new NodeResult(null, errors, false); }
        db.exec(
          "UPDATE nodes SET status = $1, updated_at = $2 WHERE id = $3",
          worksArgs().s(status).s(sysUtcNow()).n(nodeId).build(),
        );
        new NodeResult(worksGetNode(db, workId, nodeId), [], false)
      } else {
        new NodeResult(null, [], true)
      }
    }

Insert a batch for one section. Each node's ordinal is its position (from 0)
unless it names one. A rejected node is logged and skipped, and its position
is still used. Answers the inserted nodes in order.

    export let worksInsertNodes(db: Db, workId: Int, sectionId: Int?, batch: List<NodeParams>): List<GraphNode> throws Bubble {
      let out = new ListBuilder<GraphNode>();
      var i = 0;
      while (i < batch.length) {
        let p = batch[i];
        let ordinal = if (p.ordinal != null) { p.ordinal } else { i };
        let r = worksInsertNodeAt(db, workId, sectionId, p, ordinal);
        let node = r.node;
        if (node != null) {
          out.add(node);
        } else {
          console.log("marginalia: node rejected: ${worksErrorText(r.errors)}");
        }
        i += 1;
      }
      out.toList()
    }

    let worksErrorText(errors: List<FieldError>): String {
      let parts = new ListBuilder<String>();
      for (let e of errors) { parts.add("${e.field} ${e.message}"); }
      sysJoin(parts.toList(), ", ")
    }

How many notes were marked superseded because the line under them changed.

    export let worksSupersededCount(db: Db, workId: Int): Int throws Bubble {
      let row = db.one(
        "SELECT count(*) AS n FROM nodes WHERE work_id = $1 AND status = 'superseded'",
        worksArgs().n(workId).build(),
      );
      if (row == null) { 0 } else { row.int("n") }
    }

## Edges

    export class EdgeResult(
      public edge: GraphEdge?,
      public duplicate: Boolean,
      public errors: List<FieldError>,
    ) {}

    let worksEdgesOf(rows: List<DbRow>): List<GraphEdge> throws Bubble {
      let out = new ListBuilder<GraphEdge>();
      for (let row of rows) { out.add(GraphEdge.fromRow(row)); }
      out.toList()
    }

`Works.link/6`. An edge type of null is `"leads_to"`; the type is not checked
against a list. The unique index is on (from, to, type): a second link of the
same kind is silently not stored, and the result says `duplicate` with no
edge, where the Elixir answered `{:ok, struct_with_nil_id}`.

    export let worksLink(
      db: Db, workId: Int, fromId: Int, toId: Int, edgeType: String?, ordinal: Int, rationale: String?,
    ): EdgeResult throws Bubble {
      let kind = if (edgeType != null) { edgeType } else { "leads_to" };
      if (worksIsBlank(kind)) {
        return new EdgeResult(null, false, [new FieldError("edge_type", "can't be blank")]);
      }
      let rows = db.query(
        "INSERT INTO edges (work_id, from_id, to_id, edge_type, ordinal, rationale) VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT DO NOTHING RETURNING id",
        worksArgs().n(workId).n(fromId).n(toId).s(kind).n(ordinal).s(rationale).build(),
      );
      if (rows.length == 0) { return new EdgeResult(null, true, []); }
      let row = db.one(
        "SELECT ${graphEdgeColumns} FROM edges WHERE id = $1",
        worksArgs().n(rows[0].int("id")).build(),
      );
      if (row != null) {
        new EdgeResult(GraphEdge.fromRow(row), false, [])
      } else {
        bubble()
      }
    }

The name the porting brief used for the same thing.

    export let worksInsertEdge(
      db: Db, workId: Int, fromId: Int, toId: Int, edgeType: String?, ordinal: Int, rationale: String?,
    ): EdgeResult throws Bubble {
      worksLink(db, workId, fromId, toId, edgeType, ordinal, rationale)
    }

    export let worksListEdges(db: Db, workId: Int): List<GraphEdge> throws Bubble {
      worksEdgesOf(db.query(
        "SELECT ${graphEdgeColumns} FROM edges WHERE work_id = $1 ORDER BY ordinal ASC, id ASC",
        worksArgs().n(workId).build(),
      ))
    }

## Counts, search

    export class WorkCounts(
      public beats: Int,
      public spine: Int,
      public notes: Int,
      public questions: Int,
      public threads: Int,
      public total: Int,
    ) {}

`total` counts every type, the decision-graph ones too.

    export let worksCounts(db: Db, workId: Int): WorkCounts throws Bubble {
      var beats = 0;
      var spine = 0;
      var notes = 0;
      var questions = 0;
      var threads = 0;
      var total = 0;
      for (let row of db.query(
        "SELECT node_type, count(*) AS n FROM nodes WHERE work_id = $1 GROUP BY node_type",
        worksArgs().n(workId).build(),
      )) {
        let kind = row.str("node_type");
        let n = row.int("n");
        total += n;
        if (kind == "beat") { beats = n; }
        if (kind == "spine") { spine = n; }
        if (kind == "note") { notes = n; }
        if (kind == "question") { questions = n; }
        if (kind == "thread") { threads = n; }
      }
      new WorkCounts(beats, spine, notes, questions, threads, total)
    }

The terms of a query: lower-cased, split on anything but `a-z`, `0-9` and the
apostrophe, terms under three characters dropped.

    let worksTerms(query: String?): List<String> {
      let lower = sysUtf8Downcase(if (query != null) { query } else { "" });
      let out = new ListBuilder<String>();
      var start = String.begin;
      var inTerm = false;
      var i = String.begin;
      while (lower.hasIndex(i)) {
        let c = lower[i];
        let keep = (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 39;
        if (keep && !inTerm) { start = i; inTerm = true; }
        if (!keep && inTerm) {
          worksAddTerm(out, lower.slice(start, i));
          inTerm = false;
        }
        i = lower.next(i);
      }
      if (inTerm) { worksAddTerm(out, lower.slice(start, lower.end)); }
      out.toList()
    }

    let worksAddTerm(out: ListBuilder<String>, term: String): Void {
      if (worksCodePoints(term) >= 3) { out.add(term); }
    }

    class WorksScored(public node: GraphNode, public score: Int) {}

Token-scored search across this work's nodes: a node scores one for each term
that is a substring of its lower-cased `"title body quote"`. Best first, ties
by id, `limit` at most.

    export let worksSearch(db: Db, workId: Int, query: String?, limit: Int): List<GraphNode> throws Bubble {
      let terms = worksTerms(query);
      if (terms.length == 0) { return []; }
      let scored = new ListBuilder<WorksScored>();
      for (let n of worksNodes(db, workId)) {
        let b = if (n.body != null) { n.body } else { "" };
        let q = if (n.quote != null) { n.quote } else { "" };
        let text = sysUtf8Downcase("${n.title} ${b} ${q}");
        var score = 0;
        for (let t of terms) { if (worksContains(text, t)) { score += 1; } }
        if (score > 0) { scored.add(new WorksScored(n, score)); }
      }
      let ranked = scored.toList().sorted { (a: WorksScored, b: WorksScored): Int =>
        if (a.score != b.score) { b.score - a.score } else { a.node.id - b.node.id }
      };
      let out = new ListBuilder<GraphNode>();
      var k = 0;
      while (k < ranked.length && k < limit) {
        out.add(ranked[k].node);
        k += 1;
      }
      out.toList()
    }

    export class SourceHit(public section: String, public ordinal: Int, public window: String) {}

Exact-ish lookup in the writer's own text: a short window around the first
hit in each section, at most `limit` hits. The window starts 160 characters
before the hit and is the hit's length plus 320 long. Positions are found in
the lower-cased text and applied to the original, in code points; they agree
for text whose case change does not change its length (the Elixir mixed bytes
and graphemes and agreed only for ASCII).

    export let worksFindInSource(db: Db, workId: Int, phrase: String, limit: Int): List<SourceHit> throws Bubble {
      let needle = worksTrim(sysUtf8Downcase(phrase));
      if (needle.isEmpty) { return []; }
      let out = new ListBuilder<SourceHit>();
      for (let s of worksListSections(db, workId)) {
        if (out.length < limit) {
          let parts = sysUtf8Downcase(s.body).split(needle);
          if (parts.length > 1) {
            let pos = worksCodePoints(parts[0]);
            let start = if (pos > 160) { pos - 160 } else { 0 };
            let len = worksCodePoints(needle);
            out.add(new SourceHit(s.title, s.ordinal, worksSliceCp(s.body, start, len + 320)));
          }
        }
      }
      out.toList()
    }

## Connections

The edge types the weave draws.

    export let graphWeaveTypes(): List<String> {
      ["develops", "pays_off", "requires", "tension", "realises", "asks_about"]
    }

    export class Connection(public edgeType: String, public why: String?, public node: GraphNode) {}

    export class Connections(public out: List<Connection>, public into: List<Connection>) {}

    export class FullConnection(
      public edgeType: String,
      public why: String?,
      public from: GraphNode,
      public to: GraphNode,
    ) {}

What leaves and what arrives at a node, over the weave's six edge types, each
with the node on the other end. An edge whose other end no longer exists is
dropped.

    export let worksConnections(db: Db, workId: Int, nodeId: Int): Connections throws Bubble {
      let nodes = worksNodes(db, workId);
      let out = new ListBuilder<Connection>();
      let into = new ListBuilder<Connection>();
      for (let e of worksListEdges(db, workId)) {
        if (worksIn(graphWeaveTypes(), e.edgeType)) {
          if (e.fromId == nodeId) {
            let other = worksNodeIn(nodes, e.toId);
            if (other != null) { out.add(new Connection(e.edgeType, e.rationale, other)); }
          }
          if (e.toId == nodeId) {
            let other = worksNodeIn(nodes, e.fromId);
            if (other != null) { into.add(new Connection(e.edgeType, e.rationale, other)); }
          }
        }
      }
      new Connections(out.toList(), into.toList())
    }

    let worksNodeIn(nodes: List<GraphNode>, id: Int): GraphNode? {
      var i = 0;
      while (i < nodes.length) {
        if (nodes[i].id == id) { return nodes[i]; }
        i += 1;
      }
      null
    }

Every cross-section connection in the work, in edge order, for a whole-draft
view.

    export let worksAllConnections(db: Db, workId: Int): List<FullConnection> throws Bubble {
      let nodes = worksNodes(db, workId);
      let out = new ListBuilder<FullConnection>();
      for (let e of worksListEdges(db, workId)) {
        if (worksIn(graphWeaveTypes(), e.edgeType)) {
          let a = worksNodeIn(nodes, e.fromId);
          let b = worksNodeIn(nodes, e.toId);
          if (a != null) {
            if (b != null) { out.add(new FullConnection(e.edgeType, e.rationale, a, b)); }
          }
        }
      }
      out.toList()
    }

## The build trace

What `GraphEvent.changeset` casts. `seq` defaults to 0 and `ok` to true.

    export class EventParams(public workId: Int, public tool: String) {
      public var narrative: String? = null;
      public var seq: Int = 0;
      public var args: String? = null;
      public var result: String? = null;
      public var ok: Boolean = true;
      public var nodeId: Int? = null;
    }

Record one tool call and its answer. Never bubbles and never blocks the build:
a trace that fails to write is a lost line in a log, not a reason to abandon a
graph that is half-built. Answers null when it was not recorded.

    export let worksRecordEvent(db: Db, p: EventParams): GraphEvent? {
      if (worksIsBlank(p.tool)) { return null; }
      do {
        let id = db.insert(
          "INSERT INTO graph_events (work_id, narrative, seq, tool, args, result, ok, node_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
          worksArgs().n(p.workId).s(p.narrative).n(p.seq).s(p.tool).s(p.args).s(p.result)
            .s(if (p.ok) { "1" } else { "0" }).no(p.nodeId).build(),
        );
        let row = db.one(
          "SELECT ${graphEventColumns} FROM graph_events WHERE id = $1",
          worksArgs().n(id).build(),
        );
        if (row == null) { null } else { GraphEvent.fromRow(row) }
      } orelse null
    }

    export let worksListEvents(db: Db, workId: Int): List<GraphEvent> throws Bubble {
      let out = new ListBuilder<GraphEvent>();
      for (let row of db.query(
        "SELECT ${graphEventColumns} FROM graph_events WHERE work_id = $1 ORDER BY id ASC",
        worksArgs().n(workId).build(),
      )) {
        out.add(GraphEvent.fromRow(row));
      }
      out.toList()
    }

The name the porting brief used for the same thing.

    export let worksGraphEvents(db: Db, workId: Int): List<GraphEvent> throws Bubble {
      worksListEvents(db, workId)
    }

Clear the trace, so a rebuild's log is not read as one run.

    export let worksClearEvents(db: Db, workId: Int): Void throws Bubble {
      db.exec("DELETE FROM graph_events WHERE work_id = $1", worksArgs().n(workId).build());
    }

    export class EventStats(
      public calls: Int,
      public refused: Int,
      public byTool: Map<String, Int>,
      public refusals: Map<String, Int>,
    ) {}

What the run refused, and why. A refused event's kind is, in order: no result
is "unknown"; a result containing "character for character" is "quote not in
draft"; "flow rule" or "not a step in" is "flow rule"; "unknown node id" is
itself; anything else is "other".

    export let worksEventStats(db: Db, workId: Int): EventStats throws Bubble {
      let events = worksListEvents(db, workId);
      let byTool = new MapBuilder<String, Int>();
      let refusals = new MapBuilder<String, Int>();
      var refused = 0;
      for (let e of events) {
        byTool.set(e.tool, byTool.getOr(e.tool, 0) + 1);
        if (!e.ok) {
          refused += 1;
          let kind = worksRefusalKind(e.result);
          refusals.set(kind, refusals.getOr(kind, 0) + 1);
        }
      }
      new EventStats(events.length, refused, byTool.toMap(), refusals.toMap())
    }

    let worksRefusalKind(result: String?): String {
      if (result != null) {
        if (worksContains(result, "character for character")) {
          "quote not in draft"
        } else if (worksContains(result, "flow rule") || worksContains(result, "not a step in")) {
          "flow rule"
        } else if (worksContains(result, "unknown node id")) {
          "unknown node id"
        } else {
          "other"
        }
      } else {
        "unknown"
      }
    }

## Throwing a read away

Everything a read produced, so it can be run again from clean: the nodes, the
edges touching them, the trace, and every section back to pending. The work's
status, first impression and the section summaries are not touched. A read
that failed part-way leaves nodes behind; without this a retry stacks a second
set on top.

    export let worksResetRead(db: Db, workId: Int): Void throws Bubble {
      dbTransaction(db, fn (): Void throws Bubble {
        let w = worksArgs().n(workId).build();
        db.exec("DELETE FROM edges WHERE from_id IN (SELECT id FROM nodes WHERE work_id = $1) OR to_id IN (SELECT id FROM nodes WHERE work_id = $1)", w);
        db.exec("DELETE FROM nodes WHERE work_id = $1", w);
        db.exec("DELETE FROM graph_events WHERE work_id = $1", w);
        db.exec("UPDATE sections SET status = 'pending' WHERE work_id = $1", w);
      });
    }

The name the porting brief used for the same thing.

    export let worksResetGraph(db: Db, workId: Int): Void throws Bubble {
      worksResetRead(db, workId)
    }

Throw away the decision-graph layer and leave the read: the goals, options,
decisions, actions, outcomes, observations and revisits, the edges touching
them, and the trace. Answers how many nodes were deleted. The beats, spine,
threads and questions, and the edges between survivors, remain.

    export let worksResetDecisionGraph(db: Db, workId: Int): Int throws Bubble {
      let holder = new WorksCount();
      dbTransaction(db, fn (): Void throws Bubble {
        let w = worksArgs().n(workId).build();
        let kinds = "('goal', 'option', 'decision', 'action', 'outcome', 'observation', 'revisit')";
        let row = db.one("SELECT count(*) AS n FROM nodes WHERE work_id = $1 AND node_type IN ${kinds}", w);
        if (row != null) { holder.n = row.int("n"); }
        db.exec("DELETE FROM edges WHERE from_id IN (SELECT id FROM nodes WHERE work_id = $1 AND node_type IN ${kinds}) OR to_id IN (SELECT id FROM nodes WHERE work_id = $1 AND node_type IN ${kinds})", w);
        db.exec("DELETE FROM nodes WHERE work_id = $1 AND node_type IN ${kinds}", w);
        db.exec("DELETE FROM graph_events WHERE work_id = $1", w);
      });
      holder.n
    }

    class WorksCount { public var n: Int = 0; }
