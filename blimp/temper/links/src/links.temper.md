# Links

`Marginalia.Links`: relationships between the knowledge graphs of two
manuscripts. A draft that has been read has a graph of nodes (beats, spine,
threads, questions). Two drafts that are about each other have the same kind
of structure between them, and this is where it is kept.

The discipline that makes it worth trusting is the one anchoring gives a
single draft, moved up a level: **an edge whose ends are not both real nodes
in the two named manuscripts, on opposite sides of the pair, is dropped before
it is stored** (`linksStoreEdges`). The model is handed a catalogue of ids and
can only point at those.

Functions take the `Db` first, then the `Scope` where the Elixir took a
`user_id`. A bang function bubbles; the others answer `null` or a result
class.

    let { Db, DbRow, dbTransaction } = import("db/src");
    let { Scope, accountsOwner } = import("accounts/src");
    let { isUnicodeLetter, isUnicodeNumber } = import("core/src");
    let { markdownParagraphs } = import("html/src");
    let { cacheInvalidate } = import("runs/src");
    let {
      Work, Section, GraphNode, workColumns, graphNodeColumns,
      worksGetById, worksListSections, worksNodes,
    } = import("works/src");
    let {
      JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonNull, JsonBoolean,
      JsonInt32, JsonInt64, JsonFloat64,
    } = import("std/json");
    let {
      sysUtcNow, sysStringTrim, sysGraphemeTake, sysJoin,
    } = import("sys/src");

## Constants

Two manuscripts have far more possible pairs than one does, so there is a
cap on edges, but it is a backstop against a runaway answer, not a target.

    export let linksMaxEdges(): Int { 140 }

The four states of a link, in the order a pass moves through them.

    export let linksStatuses(): List<String> { ["pending", "linking", "linked", "failed"] }

The vocabulary a stored edge may use: the same relations as inside a draft,
minus `realises` and `asks_about`, which are about a node's place in its OWN
document's spine and cannot mean anything across a boundary. This is
`Analysis.Linker.types/0`.

    export let linkerTypes(): List<String> {
      ["develops", "pays_off", "requires", "tension", "answers", "echoes"]
    }

`links.error` was `varchar(255)` and was written with `inspect(reason)`, which
can be longer, and then the status update raised inside the Linker task and
the link stayed `linking` forever. SQLite would store any length, but a
reader sees the first 255 characters either way.

    export let linksErrorLimit(): Int { 255 }

## Small tools

    class LinksArgs {
      private var items: ListBuilder<String?> = new ListBuilder<String?>();
      public s(v: String?): LinksArgs { items.add(v); this }
      public n(v: Int): LinksArgs { items.add(v.toString()); this }
      public build(): List<String?> { items.toList() }
    }

    let linksArgs(): LinksArgs { new LinksArgs() }

`$first, $first+1, ...`, `count` of them, comma separated.

    let linksMarks(count: Int, first: Int): String {
      let marks = new ListBuilder<String>();
      var i = 0;
      while (i < count) {
        marks.add("\$${(first + i).toString()}");
        i += 1;
      }
      sysJoin(marks.toList(), ",")
    }

    let linksHas(s: String, part: String): Boolean { s.split(part).length > 1 }

    let linksOrEmpty(s: String?): String {
      if (s != null) { s } else { "" }
    }

    let linksUserId(scope: Scope): Int? {
      let user = scope.user;
      if (user != null) { user.id } else { null }
    }

`\s` under the `u` flag of Elixir's regexes: ASCII whitespace plus the Unicode
spaces.

    let linksIsSpace(cp: Int): Boolean {
      (cp >= 9 && cp <= 13) || cp == 32 || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

`\w` under `u`: letters, numbers and the underscore.

    let linksIsWord(cp: Int): Boolean {
      cp == 95 || isUnicodeLetter(cp) || isUnicodeNumber(cp)
    }

`String.replace(~r/\s+/u, " ")`: every run of whitespace becomes one space.
`asciiOnly` is the same without the `u` flag, where `\s` is only the ASCII
whitespace (the bulk pass's `describe` uses that one).

    export let linksCollapse(q: String, asciiOnly: Boolean): String {
      let out = new ListBuilder<String>();
      var i = String.begin;
      var start = String.begin;
      var inSpace = false;
      while (q.hasIndex(i)) {
        let cp = q[i];
        let space = if (asciiOnly) { (cp >= 9 && cp <= 13) || cp == 32 } else { linksIsSpace(cp) };
        if (space) {
          if (!inSpace) {
            out.add(q.slice(start, i));
            out.add(" ");
            inSpace = true;
          }
          i = q.next(i);
          start = i;
        } else {
          inSpace = false;
          i = q.next(i);
        }
      }
      out.add(q.slice(start, i));
      sysJoin(out.toList(), "")
    }

The collapse, then the first `n` graphemes: `one_line` in the chat card and in
the catalogue.

    export let linksOneLine(q: String, n: Int): String {
      sysGraphemeTake(linksCollapse(q, false), n)
    }

`Integer.parse/1`: an optional sign and digits at the start, whatever follows
ignored; null when there are none. Ten digits or more is more than any id
could be and is answered as null rather than wrapped around.

    export let linksParseIntPrefix(s: String): Int? {
      var i = String.begin;
      var negative = false;
      if (s.hasIndex(i)) {
        if (s[i] == 45 || s[i] == 43) {
          negative = s[i] == 45;
          i = s.next(i);
        }
      }
      var digits = 0;
      var value = 0;
      while (s.hasIndex(i) && s[i] >= 48 && s[i] <= 57 && digits < 10) {
        value = value * 10 + (s[i] - 48);
        digits += 1;
        i = s.next(i);
      }
      if (digits == 0 || digits >= 10) {
        null
      } else if (negative) {
        0 - value
      } else {
        value
      }
    }

An integer in a JSON reply: a JSON integer passes, and `fromString` says
whether a string is read (the Elixir `int/1` in `store_edges` and `as_int/1` in
the bulk pass both read strings; the bulk one trims first).

    export let linksJsonInt(t: JsonSyntaxTree?, trimFirst: Boolean): Int? {
      if (t is JsonInt32) {
        t.content
      } else if (t is JsonString) {
        let text = t.content;
        if (trimFirst) { linksParseIntPrefix(sysStringTrim(text)) } else { linksParseIntPrefix(text) }
      } else {
        null
      }
    }

    export let linksJsonField(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

A JSON string, trimmed; anything else is the empty string (`trimmed/1` in the
bulk pass).

    export let linksJsonTrimmed(t: JsonSyntaxTree?): String {
      if (t is JsonString) { sysStringTrim(t.content) } else { "" }
    }

## Results

`ok` is set, or `error` says why not: `same_work`, `invalid`, or a status
error.

    export class LinksResult(public ok: Link?, public error: String?) {}

    let linksOk(link: Link?): LinksResult { new LinksResult(link, null) }

    let linksFail(error: String): LinksResult { new LinksResult(null, error) }

    let linksLookup<K, V>(m: Map<K, V>, k: K): V? {
      if (m.has(k)) { m.get(k) orelse null } else { null }
    }

    let linksLookupB<K, V>(m: MapBuilder<K, V>, k: K): V? {
      if (m.has(k)) { m.get(k) orelse null } else { null }
    }

    let linksLinkOrBubble(link: Link?): Link throws Bubble {
      if (link != null) { link } else { bubble() }
    }

    let linksWorkOrBubble(work: Work?): Work throws Bubble {
      if (work != null) { work } else { bubble() }
    }

    let linksNodeOrBubble(node: GraphNode?): GraphNode throws Bubble {
      if (node != null) { node } else { bubble() }
    }

## The pair

    export let linksGet(db: Db, id: Int): Link? throws Bubble {
      let row = db.one("SELECT ${linkColumns} FROM links WHERE id = $1", linksArgs().n(id).build());
      if (row == null) { null } else { Link.fromRow(row) }
    }

`get_for/2`: the canonical pair, either order.

    export let linksGetFor(db: Db, workAId: Int, workBId: Int): Link? throws Bubble {
      let lo = if (workAId < workBId) { workAId } else { workBId };
      let hi = if (workAId < workBId) { workBId } else { workAId };
      let row = db.one(
        "SELECT ${linkColumns} FROM links WHERE a_work_id = $1 AND b_work_id = $2",
        linksArgs().n(lo).n(hi).build(),
      );
      if (row == null) { null } else { Link.fromRow(row) }
    }

The same, but only a link the user has a work in (`for_user`'s rule).

    export let linksFind(db: Db, scope: Scope, workAId: Int, workBId: Int): Link? throws Bubble {
      let userId = linksUserId(scope);
      let link = linksGetFor(db, workAId, workBId);
      if (userId != null) {
        if (link != null) {
          let row = db.one(
            "SELECT l.id FROM links l JOIN works a ON a.id = l.a_work_id JOIN works b ON b.id = l.b_work_id WHERE l.id = $1 AND (a.user_id = $2 OR b.user_id = $2)",
            linksArgs().n(link.id).n(userId).build(),
          );
          if (row != null) { return link; }
        }
      }
      null
    }

The link between two works, creating the row if this pair is new. The pair is
unordered, so it is stored lowest id first and looked up the same way;
otherwise linking A to B and then B to A makes two rows that disagree. A work
cannot be linked to itself (`error` is `same_work`). A new pair changes the
public lists, so the caches are dropped; finding an existing one does not.

    export let linksGetOrCreate(db: Db, workAId: Int, workBId: Int): LinksResult throws Bubble {
      if (workAId == workBId) { return linksFail("same_work"); }
      let existing = linksGetFor(db, workAId, workBId);
      if (existing != null) { return linksOk(existing); }
      let lo = if (workAId < workBId) { workAId } else { workBId };
      let hi = if (workAId < workBId) { workBId } else { workAId };
      linksInvalidate(db);
      var id = 0;
      let stored = do {
        id = db.insert(
          "INSERT INTO links (a_work_id, b_work_id) VALUES ($1, $2)",
          linksArgs().n(lo).n(hi).build(),
        );
        true
      } orelse false;
      if (!stored) { return linksFail("invalid"); }
      linksOk(linksGet(db, id))
    }

The delegating brief names this one `linksMake`.

    export let linksMake(db: Db, workAId: Int, workBId: Int): LinksResult throws Bubble {
      linksGetOrCreate(db, workAId, workBId)
    }

    let linksInvalidate(db: Db): Void throws Bubble {
      cacheInvalidate(db, "public_links");
      cacheInvalidate(db, "published_cases");
    }

## Status

`Link.changeset` casts `status`, `summary` and `error`. Only the attributes
named here are written, as an Ecto update writes only what changed.

    export class LinkAttrs(
      public setSummary: Boolean,
      public summary: String?,
      public setError: Boolean,
      public error: String?,
    ) {}

    export let linksAttrsNone(): LinkAttrs { new LinkAttrs(false, null, false, null) }

    export let linksAttrsSummary(summary: String?): LinkAttrs { new LinkAttrs(true, summary, false, null) }

    export let linksAttrsError(error: String?): LinkAttrs { new LinkAttrs(false, null, true, error) }

    export let linksAttrsBoth(summary: String?, error: String?): LinkAttrs {
      new LinkAttrs(true, summary, true, error)
    }

    let linksIn(list: List<String>, s: String): Boolean {
      var i = 0;
      while (i < list.length) {
        if (list[i] == s) { return true; }
        i += 1;
      }
      false
    }

`set_status/3`. A status outside the four is the changeset error
`status is invalid` and nothing is written. An error text is cut at 255
characters.

    export let linksSetStatus(db: Db, link: Link, status: String, attrs: LinkAttrs): LinksResult throws Bubble {
      if (!linksIn(linksStatuses(), status)) { return linksFail("status is invalid"); }
      let args = linksArgs().s(status).s(sysUtcNow());
      var sql = "UPDATE links SET status = $1, updated_at = $2";
      var next = 3;
      if (attrs.setSummary) {
        sql = "${sql}, summary = $${next.toString()}";
        args.s(attrs.summary);
        next += 1;
      }
      if (attrs.setError) {
        sql = "${sql}, error = $${next.toString()}";
        let e = attrs.error;
        if (e != null) { args.s(sysGraphemeTake(e, linksErrorLimit())); } else { args.s(null); }
        next += 1;
      }
      args.n(link.id);
      db.exec("${sql} WHERE id = $${next.toString()}", args.build());
      linksOk(linksGet(db, link.id))
    }

## Loading works with links

Ecto's `preload: [:a_work, :b_work]`.

    let linksWorksByIds(db: Db, ids: List<Int>): Map<Int, Work> throws Bubble {
      let out = new MapBuilder<Int, Work>();
      if (ids.length > 0) {
        let args = linksArgs();
        var i = 0;
        while (i < ids.length) {
          args.n(ids[i]);
          i += 1;
        }
        for (let row of db.query(
          "SELECT ${workColumns} FROM works WHERE id IN (${linksMarks(ids.length, 1)})",
          args.build(),
        )) {
          let w = Work.fromRow(row);
          out.set(w.id, w);
        }
      }
      out.toMap()
    }

    let linksWithWorks(db: Db, links: List<Link>): List<LinkWorks> throws Bubble {
      let ids = new ListBuilder<Int>();
      let seen = new MapBuilder<Int, Boolean>();
      for (let l of links) {
        if (!seen.has(l.aWorkId)) { seen.set(l.aWorkId, true); ids.add(l.aWorkId); }
        if (!seen.has(l.bWorkId)) { seen.set(l.bWorkId, true); ids.add(l.bWorkId); }
      }
      let works = linksWorksByIds(db, ids.toList());
      let out = new ListBuilder<LinkWorks>();
      for (let l of links) {
        out.add(new LinkWorks(
          l,
          linksWorkOrBubble(linksLookup(works, l.aWorkId)),
          linksWorkOrBubble(linksLookup(works, l.bWorkId)),
        ));
      }
      out.toList()
    }

    let linksLinksOf(rows: List<DbRow>): List<Link> throws Bubble {
      let out = new ListBuilder<Link>();
      for (let row of rows) { out.add(Link.fromRow(row)); }
      out.toList()
    }

`works/1`: both works of a link.

    export let linksWorks(db: Db, link: Link): LinkWorks throws Bubble {
      new LinkWorks(
        link,
        linksWorkOrBubble(worksGetById(db, link.aWorkId)),
        linksWorkOrBubble(worksGetById(db, link.bWorkId)),
      )
    }

`other/2`: the other manuscript, from the point of view of this one.

    export let linksOther(lw: LinkWorks, workId: Int): Work {
      if (lw.link.aWorkId == workId) { lw.bWork } else { lw.aWork }
    }

## Lists

Drafts this one can be linked to: the writer's own, read, and not this one.
"Read" is the hard requirement: linking relates two graphs, and a draft that
has not been read has no nodes. `exceptWorkId` null is `linkable/1`.

    export let linksLinkable(db: Db, scope: Scope, exceptWorkId: Int?): List<Work> throws Bubble {
      let userId = linksUserId(scope);
      if (userId != null) {
        linksLinkableOf(db, userId, exceptWorkId)
      } else {
        []
      }
    }

    let linksLinkableOf(db: Db, userId: Int, exceptWorkId: Int?): List<Work> throws Bubble {
      let rows = if (exceptWorkId != null) {
        db.query(
          "SELECT ${workColumns} FROM works WHERE user_id = $1 AND id != $2 AND status = 'read' ORDER BY inserted_at DESC, id DESC",
          linksArgs().n(userId).n(exceptWorkId).build(),
        )
      } else {
        db.query(
          "SELECT ${workColumns} FROM works WHERE user_id = $1 AND status = 'read' ORDER BY inserted_at DESC, id DESC",
          linksArgs().n(userId).build(),
        )
      };
      let out = new ListBuilder<Work>();
      for (let row of rows) { out.add(Work.fromRow(row)); }
      out.toList()
    }

Every link this writer has, newest first, both works loaded.

    export let linksForUser(db: Db, scope: Scope): List<LinkWorks> throws Bubble {
      let userId = linksUserId(scope);
      if (userId != null) { linksForUserId(db, userId) } else { [] }
    }

    let linksForUserId(db: Db, userId: Int): List<LinkWorks> throws Bubble {
      linksWithWorks(db, linksLinksOf(db.query(
        "SELECT l.id, l.a_work_id, l.b_work_id, l.status, l.summary, l.error, l.inserted_at, l.updated_at FROM links l JOIN works a ON a.id = l.a_work_id JOIN works b ON b.id = l.b_work_id WHERE a.user_id = $1 OR b.user_id = $1 ORDER BY l.updated_at DESC, l.id DESC",
        linksArgs().n(userId).build(),
      )))
    }

Only the links whose pass has finished.

    export let linksListLinked(db: Db, scope: Scope): List<LinkWorks> throws Bubble {
      let out = new ListBuilder<LinkWorks>();
      for (let lw of linksForUser(db, scope)) {
        if (lw.link.status == "linked") { out.add(lw); }
      }
      out.toList()
    }

Every link either side of this work, newest first. `updated_at` has second
precision, so two links touched in the same second tie; the id breaks the tie
and makes this a total order.

    export let linksForWork(db: Db, workId: Int): List<LinkWorks> throws Bubble {
      linksWithWorks(db, linksLinksOf(db.query(
        "SELECT ${linkColumns} FROM links WHERE a_work_id = $1 OR b_work_id = $1 ORDER BY updated_at DESC, id DESC",
        linksArgs().n(workId).build(),
      )))
    }

## Edges

Nodes by id, in one query.

    let linksNodeMap(db: Db, ids: List<Int>): Map<Int, GraphNode> throws Bubble {
      let out = new MapBuilder<Int, GraphNode>();
      if (ids.length > 0) {
        let args = linksArgs();
        var i = 0;
        while (i < ids.length) {
          args.n(ids[i]);
          i += 1;
        }
        for (let row of db.query(
          "SELECT ${graphNodeColumns} FROM nodes WHERE id IN (${linksMarks(ids.length, 1)})",
          args.build(),
        )) {
          let n = GraphNode.fromRow(row);
          out.set(n.id, n);
        }
      }
      out.toMap()
    }

`edges(link_id)`: the raw rows with both ends loaded, in the order they were
drawn.

    export let linksEdgesOf(db: Db, linkId: Int): List<LinkEdgeEnds> throws Bubble {
      let edges = new ListBuilder<LinkEdge>();
      let ids = new ListBuilder<Int>();
      for (let row of db.query(
        "SELECT ${linkEdgeColumns} FROM link_edges WHERE link_id = $1 ORDER BY ordinal ASC, id ASC",
        linksArgs().n(linkId).build(),
      )) {
        let e = LinkEdge.fromRow(row);
        edges.add(e);
        ids.add(e.fromId);
        ids.add(e.toId);
      }
      let nodes = linksNodeMap(db, ids.toList());
      let out = new ListBuilder<LinkEdgeEnds>();
      for (let e of edges.toList()) {
        out.add(new LinkEdgeEnds(
          e,
          linksNodeOrBubble(linksLookup(nodes, e.fromId)),
          linksNodeOrBubble(linksLookup(nodes, e.toId)),
        ));
      }
      out.toList()
    }

`edges(%Link{})`: the same, with each rationale passed through `plain`, so
nothing that renders a reason has to remember to.

    export let linksEdges(db: Db, link: Link): List<LinkEdgeEnds> throws Bubble {
      let raw = linksEdgesOf(db, link.id);
      if (raw.length == 0) { return raw; }
      let names = linksNamesOf(db, link);
      let out = new ListBuilder<LinkEdgeEnds>();
      for (let e of raw) {
        let r = e.edge.rationale;
        if (r != null) {
          let edge = e.edge;
          out.add(new LinkEdgeEnds(
            new LinkEdge(edge.id, edge.linkId, edge.fromId, edge.toId, edge.edgeType,
              linksPlainWith(r, names.a, names.b), edge.ordinal, edge.insertedAt, edge.updatedAt),
            e.from,
            e.to,
          ));
        } else {
          out.add(e);
        }
      }
      out.toList()
    }

    export let linksEdgeCount(db: Db, linkId: Int): Int throws Bubble {
      let row = db.one("SELECT count(id) AS n FROM link_edges WHERE link_id = $1", linksArgs().n(linkId).build());
      if (row == null) { 0 } else { row.int("n") }
    }

`clear_edges/1`: a second answer to the same question is a correction, not
more data.

    export let linksClearEdges(db: Db, link: Link): Void throws Bubble {
      linksInvalidate(db);
      db.exec("DELETE FROM link_edges WHERE link_id = $1", linksArgs().n(link.id).build());
    }

## Storing what the model proposed

Which manuscript each node belongs to, for the two in this link only.

    let linksNodeSides(db: Db, link: Link): Map<Int, Int> throws Bubble {
      let out = new MapBuilder<Int, Int>();
      for (let row of db.query(
        "SELECT id, work_id FROM nodes WHERE work_id IN ($1, $2)",
        linksArgs().n(link.aWorkId).n(link.bWorkId).build(),
      )) {
        out.set(row.int("id"), row.int("work_id"));
      }
      out.toMap()
    }

    export class LinksStored(public kept: Int, public dropped: Int) {}

    class LinksRow(public fromId: Int, public toId: Int, public edgeType: String, public rationale: String) {}

`to_string(raw["why"])` then `String.trim`: a string is itself, a number is its
digits, null or missing is nothing. A list or a map would raise in Elixir; here
it is empty, and so dropped.

    let linksWhy(t: JsonSyntaxTree?): String {
      if (t is JsonString) {
        sysStringTrim(t.content)
      } else if (t is JsonInt32) {
        t.content.toString()
      } else if (t is JsonInt64) {
        t.content.toString()
      } else if (t is JsonFloat64) {
        t.content.toString()
      } else if (t is JsonBoolean) {
        if (t.content) { "true" } else { "false" }
      } else {
        ""
      }
    }

The rules, in order; the first failing one drops the edge:

- an end is not a node of this pair (invented, or a third manuscript's);
- both ends are in one manuscript (that is `Weave`'s job, and passing one off
  as a connection between the documents would make the feature a lie);
- the type is not in `types`;
- no reason: the reason is the product.

The check, as one function per stage:

    let linksNormalise(raw: JsonSyntaxTree, sides: Map<Int, Int>, types: List<String>): LinksRow? {
      let fromId = linksJsonInt(linksJsonField(raw, "from"), false);
      let toId = linksJsonInt(linksJsonField(raw, "to"), false);
      let typeTree = linksJsonField(raw, "type");
      let typeText = if (typeTree is JsonString) { typeTree.content } else { "" };
      let typeIsText = typeTree is JsonString;
      let why = linksWhy(linksJsonField(raw, "why"));
      if (fromId != null) {
        if (toId != null) {
          return linksNormaliseIds(fromId, toId, typeIsText, typeText, why, sides, types);
        }
      }
      null
    }

    let linksNormaliseIds(
      fromId: Int, toId: Int, typeIsText: Boolean, typeText: String, why: String,
      sides: Map<Int, Int>, types: List<String>,
    ): LinksRow? {
      if (!sides.has(fromId) || !sides.has(toId)) { return null; }
      if (sides.getOr(fromId, -1) == sides.getOr(toId, -2)) { return null; }
      if (!typeIsText) { return null; }
      if (!linksIn(types, typeText)) { return null; }
      if (why == "") { return null; }
      new LinksRow(fromId, toId, typeText, why)
    }

    class LinksCounter { public var n: Int = 0; }

`store_edges/4`. Returns how many were kept and how many were rejected by the
rules above. Items that are not objects vanish without being counted; a
duplicate, or one past `max`, is not counted as dropped either. The rejection
count is the number worth watching: a pass that suddenly starts failing the
check has begun inventing ids.

    export let linksStoreEdgesMax(db: Db, link: Link, proposed: List<JsonSyntaxTree>, types: List<String>, max: Int): LinksStored throws Bubble {
      linksInvalidate(db);
      let sides = linksNodeSides(db, link);
      let rows = new ListBuilder<LinksRow>();
      let seen = new MapBuilder<String, Boolean>();
      var dropped = 0;
      for (let item of proposed) {
        if (item is JsonObject) {
          let row = linksNormalise(item, sides, types);
          if (row != null) {
            let key = "${row.fromId.toString()}:${row.toId.toString()}:${row.edgeType}";
            if (!seen.has(key) && rows.length < max) {
              seen.set(key, true);
              rows.add(row);
            }
          } else {
            dropped += 1;
          }
        }
      }
      let counter = new LinksCounter();
      let kept = rows.toList();
      dbTransaction(db, fn (): Void throws Bubble {
        var ordinal = 0;
        for (let r of kept) {
          let changed = db.exec(
            "INSERT OR IGNORE INTO link_edges (link_id, from_id, to_id, edge_type, rationale, ordinal) VALUES ($1, $2, $3, $4, $5, $6)",
            linksArgs().n(link.id).n(r.fromId).n(r.toId).s(r.edgeType).s(r.rationale).n(ordinal).build(),
          );
          if (changed > 0) { counter.n += 1; }
          ordinal += 1;
        }
      });
      new LinksStored(counter.n, dropped)
    }

    export let linksStoreEdges(db: Db, link: Link, proposed: List<JsonSyntaxTree>, types: List<String>): LinksStored throws Bubble {
      linksStoreEdgesMax(db, link, proposed, types, linksMaxEdges())
    }

## Passages

The paragraph a node sits in, not just the sentence it was anchored to. The
anchor is one sentence because that is what can be verified; handed to a
conversation, the sentence alone is what people misread.

    export let linksPassage(db: Db, node: GraphNode): String throws Bubble {
      let quote = node.quote;
      if (quote != null) {
        if (quote != "") {
          let sectionId = node.sectionId;
          if (sectionId != null) {
            let row = db.one("SELECT body FROM sections WHERE id = $1", linksArgs().n(sectionId).build());
            if (row != null) {
              let paras = markdownParagraphs(row.str("body"));
              var i = 0;
              while (i < paras.length) {
                if (linksHas(paras[i], quote)) { return paras[i]; }
                i += 1;
              }
            }
          }
          return quote;
        }
      }
      node.title
    }

## Stats

Counts for the header of a linked graph. `byType` is the frequency of each
relation; `aNodes` and `bNodes` are how many distinct nodes of each side the
edges touch.

    export class LinkStats(
      public edges: Int,
      public byType: Map<String, Int>,
      public aNodes: Int,
      public bNodes: Int,
    ) {}

    export let linksStats(db: Db, link: Link): LinkStats throws Bubble {
      let edges = linksEdges(db, link);
      let byType = new MapBuilder<String, Int>();
      let aSeen = new MapBuilder<Int, Boolean>();
      let bSeen = new MapBuilder<Int, Boolean>();
      var aCount = 0;
      var bCount = 0;
      for (let e of edges) {
        byType.set(e.edge.edgeType, byType.getOr(e.edge.edgeType, 0) + 1);
        for (let n of [e.from, e.to]) {
          if (n.workId == link.aWorkId && !aSeen.has(n.id)) { aSeen.set(n.id, true); aCount += 1; }
          if (n.workId == link.bWorkId && !bSeen.has(n.id)) { bSeen.set(n.id, true); bCount += 1; }
        }
      }
      new LinkStats(edges.length, byType.toMap(), aCount, bCount)
    }

## Margin notes

A link's edges as notes for one side of it, the shape `Reading` builds from a
draft's own graph, so the same placement code can find the quote in the
paragraph. What is different is `peer`: the node on the OTHER side, so a click
in one column can move the other.

An edge whose near end is not an anchored beat has nowhere to sit on the page,
so it is left out here and shown in the list instead.

`farTitle`, `farBody`, `farQuote`, `farKind` and `farSection` are filled by
`linksMargin`: the far end whole, so whoever renders the note does not have to
go back for the graph.

    export class LinkNote(
      public key: String,
      public edgeId: Int,
      public nearId: Int,
      public sectionId: Int,
      public kind: String,
      public quote: String,
      public title: String,
      public body: String,
      public peer: Int,
    ) {
      public var stale: Boolean = false;
      public var farTitle: String? = null;
      public var farBody: String? = null;
      public var farQuote: String? = null;
      public var farKind: String? = null;
      public var farSection: Int? = null;
    }

    export let linksNotesFor(db: Db, link: Link, workId: Int): List<LinkNote> throws Bubble {
      let out = new ListBuilder<LinkNote>();
      for (let e of linksEdges(db, link)) {
        let nearIsFrom = e.from.workId == workId;
        let near = if (nearIsFrom) { e.from } else { e.to };
        let far = if (nearIsFrom) { e.to } else { e.from };
        let sectionId = near.sectionId;
        let quote = near.quote;
        if (near.workId == workId) {
          if (sectionId != null) {
            if (quote != null) {
              if (quote != "") {
                let arrow = if (e.edge.fromId == near.id) { "→ " } else { "← " };
                out.add(new LinkNote(
                  "link:${e.edge.id.toString()}",
                  e.edge.id,
                  near.id,
                  sectionId,
                  e.edge.edgeType,
                  quote,
                  "${arrow}${far.title}",
                  linksOrEmpty(e.edge.rationale),
                  far.id,
                ));
              }
            }
          }
        }
      }
      out.toList()
    }

`margin/2`: those notes, plus the far end of each.

    export let linksMargin(db: Db, link: Link, leadId: Int): List<LinkNote> throws Bubble {
      let lw = linksWorks(db, link);
      let other = linksOther(lw, leadId);
      let ordinals = new MapBuilder<Int, Int>();
      for (let s of worksListSections(db, other.id)) { ordinals.set(s.id, s.ordinal); }
      let byEdge = new MapBuilder<Int, LinkEdgeEnds>();
      for (let e of linksEdges(db, link)) { byEdge.set(e.edge.id, e); }
      let out = new ListBuilder<LinkNote>();
      for (let note of linksNotesFor(db, link, leadId)) {
        let e = linksLookupB(byEdge, note.edgeId);
        if (e != null) {
          let far = if (e.from.workId == leadId) { e.to } else { e.from };
          note.farTitle = far.title;
          note.farBody = far.body;
          note.farQuote = far.quote;
          note.farKind = far.nodeType;
          let farSection = far.sectionId;
          if (farSection != null) { note.farSection = ordinals.getOr(farSection, -1); }
        }
        out.add(note);
      }
      out.toList()
    }

## Calling the documents by their names

The pass is handed the two drafts as "Manuscript A" and "Manuscript B", which
is right for the prompt (it stops the model reasoning from a title instead of
from the text) and wrong for every page that shows the answer. So any of the
pass's prose is substituted with the real titles on the way out.

The title of a work as it is called inside a collection: the part after the
first " — " if there is one, else the whole title. The collection's name is
repeated on every document and is already on the page.

    export let linksName(title: String): String {
      let parts = title.split(" — ");
      if (parts.length < 2) { title } else { sysJoin(parts.slice(1, parts.length), " — ") }
    }

    class LinksNames(public a: String, public b: String) {}

    let linksNamesOf(db: Db, link: Link): LinksNames throws Bubble {
      let lw = linksWorks(db, link);
      new LinksNames(linksName(lw.aWork.title), linksName(lw.bWork.title))
    }

One left-to-right pass over the Elixir regex
`(\A|\bManuscripts?\s+|[.;:—-]\s+|\s+)([AB])(['’]s)?(?![\p{L}\p{N}'’])`
with a function for the replacement, written by hand because Temper's regex
has neither lookahead nor Unicode classes. The pass count is the load-bearing
part: done as one replacement per form, a title substituted by an early pass is
ordinary English by the time a later one reads it, and the later one
substitutes inside it ("B answers A's open question" became a sentence with
the same title spliced through itself). One pass resumes after the match it
just made, in the original string, so replaced text is never rescanned. And a
function rather than a template, so a title that begins with a digit (every
chapter of a numbered stack) is never read as a backreference.

`kind` is which alternative of the prefix matched: 0 the start of the text,
1 the word Manuscript, 2 sentence punctuation, 3 plain spaces.

    class LinksRef(
      public pre: String,
      public letter: String,
      public poss: String,
      public kind: Int,
      public end: StringIndex,
    ) {}

    let linksSkipSpaces(text: String, from: StringIndex): StringIndex {
      var i = from;
      while (text.hasIndex(i) && linksIsSpace(text[i])) { i = text.next(i); }
      i
    }

Not followed by a letter, a number, or an apostrophe.

    let linksLookaheadOk(text: String, i: StringIndex): Boolean {
      if (!text.hasIndex(i)) {
        true
      } else {
        let c = text[i];
        !(isUnicodeLetter(c) || isUnicodeNumber(c) || c == 39 || c == 0x2019)
      }
    }

The letter, its optional possessive, and the lookahead, after a prefix that
ends at `q`.

    let linksTailAt(text: String, q: StringIndex, pre: String, kind: Int): LinksRef? {
      if (!text.hasIndex(q)) { return null; }
      let c = text[q];
      if (c != 65 && c != 66) { return null; }
      let r = text.next(q);
      let letter = text.slice(q, r);
      if (text.hasIndex(r)) {
        if (text[r] == 39 || text[r] == 0x2019) {
          let s = text.next(r);
          if (text.hasIndex(s)) {
            if (text[s] == 115) {
              let e = text.next(s);
              if (linksLookaheadOk(text, e)) {
                return new LinksRef(pre, letter, text.slice(r, e), kind, e);
              }
            }
          }
          return null;
        }
      }
      if (linksLookaheadOk(text, r)) { return new LinksRef(pre, letter, "", kind, r); }
      null
    }

`text` continues with `word` at `i`: the index after it, or null.

    let linksWordAt(text: String, i: StringIndex, word: String): StringIndex? {
      var w = String.begin;
      var j = i;
      while (word.hasIndex(w)) {
        if (!text.hasIndex(j)) { return null; }
        if (text[j] != word[w]) { return null; }
        w = word.next(w);
        j = text.next(j);
      }
      j
    }

`\b` before a word character: the previous character is not one.

    let linksWordStartsAt(text: String, i: StringIndex): Boolean {
      if (i > String.begin) { !linksIsWord(text[text.prev(i)]) } else { true }
    }

    let linksIsStop(cp: Int): Boolean {
      cp == 46 || cp == 59 || cp == 58 || cp == 0x2014 || cp == 45
    }

The match starting exactly at `p`, trying the four prefixes in the order the
alternation does.

    let linksMatchAt(text: String, p: StringIndex): LinksRef? {
      if (!(p > String.begin)) {
        let m = linksTailAt(text, p, "", 0);
        if (m != null) { return m; }
      }
      if (text.hasIndex(p)) {
        if (text[p] == 77 && linksWordStartsAt(text, p)) {
          let word = linksWordAt(text, p, "Manuscript");
          if (word != null) {
            var e: StringIndex = word;
            if (text.hasIndex(e)) {
              if (text[e] == 115) { e = text.next(e); }
            }
            let after = linksSkipSpaces(text, e);
            if (after > e) {
              let m = linksTailAt(text, after, text.slice(p, after), 1);
              if (m != null) { return m; }
            }
          }
        }
        if (linksIsStop(text[p])) {
          let start = text.next(p);
          let after = linksSkipSpaces(text, start);
          if (after > start) {
            let m = linksTailAt(text, after, text.slice(p, after), 2);
            if (m != null) { return m; }
          }
        }
        if (linksIsSpace(text[p])) {
          let after = linksSkipSpaces(text, p);
          let m = linksTailAt(text, after, text.slice(p, after), 3);
          if (m != null) { return m; }
        }
      }
      null
    }

The four branches, in the order the Elixir tries them:

- "Manuscript A", "Manuscript A's": the unambiguous form. The word goes, the
  title replaces both.
- "A's": safe anywhere. English has no possessive indefinite article.
- the start of the text or of a sentence (". A"): the convention the older
  summaries were written to.
- " A": left alone. "Part A" and "Exhibit B" live here, and so does the
  indefinite article. Telling the label from the article needs to know whether
  the next word is a verb, and turning "A page with no script on it" into a
  manuscript title is a worse failure than leaving a letter on the page.

The substitution itself:

    export let linksPlainWith(text: String, nameA: String, nameB: String): String {
      let out = new ListBuilder<String>();
      var copy = String.begin;
      var p = String.begin;
      while (text.hasIndex(p)) {
        let m = linksMatchAt(text, p);
        if (m != null) {
          out.add(text.slice(copy, p));
          let title = if (m.letter == "A") { nameA } else { nameB };
          if (m.kind == 1) {
            out.add("${title}${m.poss}");
          } else if (m.poss != "") {
            out.add("${m.pre}${title}${m.poss}");
          } else if (m.kind == 0 || m.kind == 2) {
            out.add("${m.pre}${title}");
          } else {
            out.add("${m.pre}${m.letter}${m.poss}");
          }
          copy = m.end;
          p = m.end;
        } else {
          p = text.next(p);
        }
      }
      out.add(text.slice(copy, p));
      sysJoin(out.toList(), "")
    }

`plain/2`: any of the pass's prose, with the documents called by their names.

    export let linksPlain(db: Db, link: Link, text: String): String throws Bubble {
      let names = linksNamesOf(db, link);
      linksPlainWith(text, names.a, names.b)
    }

`summary/1`: null when there is none yet.

    export let linksSummary(db: Db, link: Link): String? throws Bubble {
      let s = link.summary;
      if (s != null) { linksPlain(db, link, s) } else { null }
    }

## Constellations

The writer's links, grouped into the groups they actually form: connected
components, every set of drafts that can be reached from each other through
links. Each group also carries the pairs inside it that are NOT linked yet,
which is the useful part: in a group of three with two links, the third pair
is the obvious next question.

    export class LinkMissing(public a: Work, public b: Work) {}

    export class LinkCluster(
      public works: List<Work>,
      public links: List<LinkWorks>,
      public missing: List<LinkMissing>,
    ) {}

    let linksRoot(parent: MapBuilder<Int, Int>, id: Int): Int {
      var cur = id;
      var up = parent.getOr(cur, cur);
      while (up != cur) {
        cur = up;
        up = parent.getOr(cur, cur);
      }
      cur
    }

Stable insertion sorts; the lists are a writer's own drafts.

    let linksSortWorks(works: List<Work>): List<Work> {
      let out = new ListBuilder<Work>();
      for (let w of works) {
        var at = out.length;
        while (at > 0 && w.title < out[at - 1].title) { at -= 1; }
        out.add(w, at);
      }
      out.toList()
    }

    export let linksClusters(db: Db, scope: Scope): List<LinkCluster> throws Bubble {
      let links = linksForUser(db, scope);
      let works = new MapBuilder<Int, Work>();
      let order = new ListBuilder<Int>();
      let parent = new MapBuilder<Int, Int>();
      for (let lw of links) {
        for (let w of [lw.aWork, lw.bWork]) {
          if (!works.has(w.id)) {
            works.set(w.id, w);
            order.add(w.id);
            parent.set(w.id, w.id);
          }
        }
      }
      for (let lw of links) {
        let ra = linksRoot(parent, lw.link.aWorkId);
        let rb = linksRoot(parent, lw.link.bWorkId);
        if (ra != rb) { parent.set(ra, rb); }
      }
      let ids = order.toList().sorted { (a: Int, b: Int): Int => a - b };
      let groups = new MapBuilder<Int, ListBuilder<Int>>();
      let roots = new ListBuilder<Int>();
      for (let id of ids) {
        let root = linksRoot(parent, id);
        if (!groups.has(root)) {
          groups.set(root, new ListBuilder<Int>());
          roots.add(root);
        }
        let g = linksLookupB(groups, root);
        if (g != null) { g.add(id); }
      }
      let built = new ListBuilder<LinkCluster>();
      for (let root of roots.toList()) {
        let g = linksLookupB(groups, root);
        if (g != null) {
          let member = new MapBuilder<Int, Boolean>();
          let ws = new ListBuilder<Work>();
          for (let id of g.toList()) {
            member.set(id, true);
            let w = linksLookupB(works, id);
            if (w != null) { ws.add(w); }
          }
          let inside = new ListBuilder<LinkWorks>();
          let linked = new MapBuilder<String, Boolean>();
          for (let lw of links) {
            if (member.has(lw.link.aWorkId)) {
              inside.add(lw);
              linked.set("${lw.link.aWorkId.toString()}:${lw.link.bWorkId.toString()}", true);
            }
          }
          let members = linksSortWorks(ws.toList());
          let missing = new ListBuilder<LinkMissing>();
          for (let a of members) {
            for (let b of members) {
              if (a.id < b.id && !linked.has("${a.id.toString()}:${b.id.toString()}")) {
                missing.add(new LinkMissing(a, b));
              }
            }
          }
          built.add(new LinkCluster(members, inside.toList(), missing.toList()));
        }
      }
      let out = new ListBuilder<LinkCluster>();
      for (let c of built.toList()) {
        var at = out.length;
        while (at > 0 && out[at - 1].works.length < c.works.length) { at -= 1; }
        out.add(c, at);
      }
      out.toList()
    }

## The public face

A link with no edges is a pass that ran and reported nothing: a real answer,
and on the writer's own page, but a public index of empty comparisons is an
index of nothing.

    export class PublicLink(public link: LinkWorks, public edges: Int, public tensions: Int) {}

Counts of edges per link, in one grouped query rather than one per link (393
queries to draw one page was the cost of asking `edge_count` inside a filter).

    let linksCountsBy(db: Db, ids: List<Int>, edgeType: String?): Map<Int, Int> throws Bubble {
      let out = new MapBuilder<Int, Int>();
      if (ids.length > 0) {
        let args = linksArgs();
        var i = 0;
        while (i < ids.length) {
          args.n(ids[i]);
          i += 1;
        }
        var sql = "SELECT link_id, count(id) AS n FROM link_edges WHERE link_id IN (${linksMarks(ids.length, 1)})";
        if (edgeType != null) {
          sql = "${sql} AND edge_type = $${(ids.length + 1).toString()}";
          args.s(edgeType);
        }
        for (let row of db.query("${sql} GROUP BY link_id", args.build())) {
          out.set(row.int("link_id"), row.int("n"));
        }
      }
      out.toMap()
    }

`public_links/0`: the owner's links that found something, strongest first
(most tensions, then most edges). Not cached: the Elixir held the answer for
five minutes, but a forked child has no memory to hold it in, and the answer
is two grouped queries.

    export let linksPublicLinks(db: Db): List<PublicLink> throws Bubble {
      let owner = accountsOwner(db);
      if (owner != null) { linksPublicOf(db, owner.id) } else { [] }
    }

    let linksPublicOf(db: Db, ownerId: Int): List<PublicLink> throws Bubble {
      let links = linksForUserId(db, ownerId);
      let ids = new ListBuilder<Int>();
      for (let lw of links) { ids.add(lw.link.id); }
      let totals = linksCountsBy(db, ids.toList(), null);
      let tensions = linksCountsBy(db, ids.toList(), "tension");
      let out = new ListBuilder<PublicLink>();
      for (let lw of links) {
        let total = totals.getOr(lw.link.id, 0);
        if (total > 0) {
          let item = new PublicLink(lw, total, tensions.getOr(lw.link.id, 0));
          var at = out.length;
          while (at > 0 && linksStronger(item, out[at - 1])) { at -= 1; }
          out.add(item, at);
        }
      }
      out.toList()
    }

    let linksStronger(a: PublicLink, b: PublicLink): Boolean {
      if (a.tensions != b.tensions) { a.tensions > b.tensions } else { a.edges > b.edges }
    }

`public_link/1`: a link anybody may read: the owner's, and only if it found
something. BOTH works must belong to the owner. This page reads two drafts at
once, so a check that passes on one of them exposes somebody else's work
alongside the owner's.

    export let linksPublicLink(db: Db, id: Int): LinkWorks? throws Bubble {
      let owner = accountsOwner(db);
      let link = linksGet(db, id);
      if (owner != null) {
        if (link != null) {
          let lw = linksWorks(db, link);
          if (lw.aWork.userId == owner.id && lw.bWork.userId == owner.id && linksEdgeCount(db, id) > 0) {
            return lw;
          }
        }
      }
      null
    }
