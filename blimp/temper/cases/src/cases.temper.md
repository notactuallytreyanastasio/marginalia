# Cases

`Marginalia.Cases`: a collection of drafts that are one thing.

A Supreme Court case arrives as three or four separate documents (the opinion
of the Court, each dissent, the argument that produced them) and every one is
a draft in its own right with its own map. What the reader wants is neither one
document nor a flat list of twelve: it is the case, with its pieces in the
order you would read them and the relationships between them already drawn.

`works.collection` names the group and `works.collection_role` orders it. Both
are plain columns rather than a table, because a collection has no properties
of its own: it is a name several drafts agree on. Nothing is published by
accident: a draft has to be put in a named collection by the person who owns
it before it appears on the front of the site, and the front of the site is
the owner's collections only (`casesPublished`).

Folders are not involved. A folder is a place a writer put some drafts;
`foldersPublished` publishes stacks under `/reading`. Reusing `collection` for
both would have published every draft dropped in "Reading pile" on `/cases`,
which is why the two are separate columns (`lib/marginalia/folders.ex`).

    let { Db, DbRow } = import("db/src");
    let { accountsOwner } = import("accounts/src");
    let {
      Work, GraphNode, workColumns, graphNodeColumns, worksListSections,
    } = import("works/src");
    let {
      Link, LinkEdge, LinkEdgeEnds, linkColumns, linkEdgeColumns, linksPassage,
    } = import("links/src");
    let { slugPlain, markdownParagraphs } = import("html/src");
    let { cacheInvalidate } = import("runs/src");
    let { sysUtcNow, sysStringTrim } = import("sys/src");

## Reading order

`@order`. The order a case is read in, which is not the order it was written
in. A role that is none of these sorts last rather than being refused, since
a collection of something other than a court case will want its own words.

    export let casesRoles(): List<String> {
      ["opinion", "concurrence", "dissent", "argument"]
    }

    export let casesRank(role: String?): Int {
      let order = casesRoles();
      if (role == null) { return order.length; }
      var i = 0;
      while (i < order.length) {
        if (order[i] == role) { return i; }
        i += 1;
      }
      order.length
    }

`slug(name)`: a stable URL-safe name for a collection. Lower-case, every run
of characters outside `a-z0-9` becomes one `-`, no leading or trailing `-`,
no length cap and no fallback (a name of nothing but punctuation is the empty
string).

    export let casesSlug(name: String): String { slugPlain(name) }

## Small helpers

    let casesIds(ids: List<Int>): String {
      ids.map { (i: Int): String => i.toString() }.join(",") { (s: String): String => s }
    }

    let casesColl(w: Work): String {
      let c = w.collection;
      if (c != null) { c } else { "" }
    }

    let casesWorkMap(works: List<Work>): Map<Int, Work> {
      let m = new MapBuilder<Int, Work>();
      for (let w of works) { m.set(w.id, w); }
      m.toMap()
    }

    let casesWorksOf(rows: List<DbRow>): List<Work> throws Bubble {
      let out = new ListBuilder<Work>();
      for (let row of rows) { out.add(Work.fromRow(row)); }
      out.toList()
    }

    let casesWorkById(m: Map<Int, Work>, id: Int): Work? {
      if (m.has(id)) { m.getOr(id, casesNoWork()) } else { null }
    }

`getOr` wants a fallback of the right type even when it is never used; the
work with id 0 stands in and is never returned.

    let casesNoWork(): Work {
      new Work(0, 0, "", "", null, null, null, null, "", null, 0, "", null, null, null, null, "", "")
    }

## Loading

Every draft this writer has put in a collection, by collection then id.

    export let casesLoadWorks(db: Db, userId: Int): List<Work> throws Bubble {
      casesWorksOf(db.query(
        "SELECT ${workColumns} FROM works WHERE user_id = $1 AND collection IS NOT NULL ORDER BY collection ASC, id ASC",
        [userId.toString()],
      ))
    }

Every edge of the given links, ordered `ordinal` then `id`, with the two
nodes each joins: two queries for the lot, not one per link.

    let casesLoadEdges(db: Db, linkIds: List<Int>): List<LinkEdgeEnds> throws Bubble {
      if (linkIds.length == 0) { return []; }
      let edges = new ListBuilder<LinkEdge>();
      let wanted = new MapBuilder<Int, Boolean>();
      let order = new ListBuilder<Int>();
      for (let row of db.query(
        "SELECT ${linkEdgeColumns} FROM link_edges WHERE link_id IN (${casesIds(linkIds)}) ORDER BY ordinal ASC, id ASC",
        [],
      )) {
        let e = LinkEdge.fromRow(row);
        edges.add(e);
        if (!wanted.has(e.fromId)) { wanted.set(e.fromId, true); order.add(e.fromId); }
        if (!wanted.has(e.toId)) { wanted.set(e.toId, true); order.add(e.toId); }
      }
      if (edges.length == 0) { return []; }
      let nodes = new MapBuilder<Int, GraphNode>();
      for (let row of db.query(
        "SELECT ${graphNodeColumns} FROM nodes WHERE id IN (${casesIds(order.toList())})",
        [],
      )) {
        let n = GraphNode.fromRow(row);
        nodes.set(n.id, n);
      }
      let out = new ListBuilder<LinkEdgeEnds>();
      for (let e of edges.toList()) {
        out.add(new LinkEdgeEnds(e, nodes.get(e.fromId), nodes.get(e.toId)));
      }
      out.toList()
    }

`kinships(works)`: the links that leave each collection. Links with status
`linked` that touch the works; for those whose two ends are both in the set,
in different collections, and which have at least one edge, one entry per
collection, each naming the draft inside it as `lead`. Strongest first
(stable, so equal links stay in link order).

    let casesKinships(db: Db, works: List<Work>): Map<String, List<CaseKin>> throws Bubble {
      let out = new MapBuilder<String, ListBuilder<CaseKin>>();
      let empty = new MapBuilder<String, List<CaseKin>>().toMap();
      if (works.length == 0) { return empty; }
      let byId = casesWorkMap(works);
      let ids = casesIds(works.map { (w: Work): Int => w.id });
      let linkIds = new ListBuilder<Int>();
      let ends = new ListBuilder<List<Int>>();
      for (let row of db.query(
        "SELECT id, a_work_id, b_work_id FROM links WHERE status = 'linked' AND (a_work_id IN (${ids}) OR b_work_id IN (${ids})) ORDER BY id",
        [],
      )) {
        let aId = row.int("a_work_id");
        let bId = row.int("b_work_id");
        if (byId.has(aId) && byId.has(bId)) {
          if (casesColl(byId.get(aId)) != casesColl(byId.get(bId))) {
            linkIds.add(row.int("id"));
            ends.add([row.int("id"), aId, bId]);
          }
        }
      }
      if (linkIds.length == 0) { return empty; }
      let counts = new MapBuilder<Int, Int>();
      for (let row of db.query(
        "SELECT link_id, count(id) AS n FROM link_edges WHERE link_id IN (${casesIds(linkIds.toList())}) GROUP BY link_id",
        [],
      )) {
        counts.set(row.int("link_id"), row.int("n"));
      }
      for (let e of ends.toList()) {
        let n = counts.getOr(e[0], 0);
        if (n > 0) {
          let a = byId.get(e[1]);
          let b = byId.get(e[2]);
          let nameA = casesColl(a);
          let nameB = casesColl(b);
          if (!out.has(nameA)) { out.set(nameA, new ListBuilder<CaseKin>()); }
          out.get(nameA).add(new CaseKin(e[0], a, b, nameB, n));
          if (!out.has(nameB)) { out.set(nameB, new ListBuilder<CaseKin>()); }
          out.get(nameB).add(new CaseKin(e[0], b, a, nameA, n));
        }
      }
      let done = new MapBuilder<String, List<CaseKin>>();
      for (let name of out.keys().toList()) {
        done.set(name, out.get(name).toList().sorted { (x: CaseKin, y: CaseKin): Int => y.edges - x.edges });
      }
      done.toMap()
    }

The links inside each collection, and their edges. Elixir loaded every link
touching any of the drafts and every edge of those links, then threw away the
links that left a collection; the edges of a link that leaves one are never
used by a case, so only the others are loaded.

    class CasesBulk(public links: List<Link>, public byLink: Map<Int, List<LinkEdgeEnds>>) {}

    let casesBulk(db: Db, works: List<Work>): CasesBulk throws Bubble {
      let none = new MapBuilder<Int, List<LinkEdgeEnds>>().toMap();
      if (works.length == 0) { return new CasesBulk([], none); }
      let byId = casesWorkMap(works);
      let ids = casesIds(works.map { (w: Work): Int => w.id });
      let inside = new ListBuilder<Link>();
      for (let row of db.query(
        "SELECT ${linkColumns} FROM links WHERE a_work_id IN (${ids}) OR b_work_id IN (${ids}) ORDER BY id",
        [],
      )) {
        let l = Link.fromRow(row);
        if (byId.has(l.aWorkId) && byId.has(l.bWorkId)) {
          if (casesColl(byId.get(l.aWorkId)) == casesColl(byId.get(l.bWorkId))) { inside.add(l); }
        }
      }
      let linkIds = inside.toList().map { (l: Link): Int => l.id };
      let grouped = new MapBuilder<Int, ListBuilder<LinkEdgeEnds>>();
      for (let e of casesLoadEdges(db, linkIds)) {
        if (!grouped.has(e.edge.linkId)) { grouped.set(e.edge.linkId, new ListBuilder<LinkEdgeEnds>()); }
        grouped.get(e.edge.linkId).add(e);
      }
      let byLink = new MapBuilder<Int, List<LinkEdgeEnds>>();
      for (let id of linkIds) {
        byLink.set(id, if (grouped.has(id)) { grouped.get(id).toList() } else { [] });
      }
      new CasesBulk(inside.toList(), byLink.toMap())
    }

## Assembling a case

The unlinked pairs: every two drafts of the case (in reading order, the
lower id first) with no link between them.

    let casesUnlinked(works: List<Work>, links: List<Link>): List<CasePair> {
      let have = new MapBuilder<String, Boolean>();
      for (let l of links) { have.set("${l.aWorkId.toString()}:${l.bWorkId.toString()}", true); }
      let out = new ListBuilder<CasePair>();
      for (let a of works) {
        for (let b of works) {
          if (a.id < b.id) {
            if (!have.has("${a.id.toString()}:${b.id.toString()}")) { out.add(new CasePair(a, b)); }
          }
        }
      }
      out.toList()
    }

    let casesAssemble(
      name: String, members: List<Work>, allLinks: List<Link>, all: Map<Int, List<LinkEdgeEnds>>,
      kin: List<CaseKin>,
    ): CaseStudy {
      let works = members.sorted { (x: Work, y: Work): Int =>
        casesRank(x.collectionRole) - casesRank(y.collectionRole)
      };
      let inCase = new MapBuilder<Int, Boolean>();
      for (let w of works) { inCase.set(w.id, true); }
      let links = new ListBuilder<Link>();
      for (let l of allLinks) {
        if (inCase.has(l.aWorkId) && inCase.has(l.bWorkId)) { links.add(l); }
      }
      let byLink = new MapBuilder<Int, List<LinkEdgeEnds>>();
      var edges = 0;
      for (let l of links.toList()) {
        let es = all.getOr(l.id, []);
        byLink.set(l.id, es);
        edges += es.length;
      }
      var opinion: Work? = null;
      for (let w of works) {
        if (opinion == null && w.collectionRole == "opinion") { opinion = w; }
      }
      var read = 0;
      var words = 0;
      for (let w of works) {
        if (w.status == "read") { read += 1; }
        words += w.wordCount;
      }
      new CaseStudy(
        name, casesSlug(name), works, links.toList(), byLink.toMap(), casesHolding(opinion),
        read, words, edges, casesUnlinked(works, links.toList()), kin,
      )
    }

`list(user_id)`: every collection this writer has, with its drafts and their
links, sorted by name.

    export let casesListFor(db: Db, userId: Int): List<CaseStudy> throws Bubble {
      let works = casesLoadWorks(db, userId);
      let kin = casesKinships(db, works);
      let bulk = casesBulk(db, works);
      let groups = new MapBuilder<String, ListBuilder<Work>>();
      let names = new ListBuilder<String>();
      for (let w of works) {
        let name = casesColl(w);
        if (!groups.has(name)) { groups.set(name, new ListBuilder<Work>()); names.add(name); }
        groups.get(name).add(w);
      }
      let sortedNames = names.toList().sorted { (a: String, b: String): Int => casesCompareText(a, b) };
      let out = new ListBuilder<CaseStudy>();
      for (let name of sortedNames) {
        out.add(casesAssemble(
          name, groups.get(name).toList(), bulk.links, bulk.byLink, kin.getOr(name, []),
        ));
      }
      out.toList()
    }

`get(user_id, slug)`: one collection by its slug, or null.

    export let casesGetFor(db: Db, userId: Int, slug: String): CaseStudy? throws Bubble {
      let all = casesListFor(db, userId);
      for (let c of all) {
        if (c.slug == slug) { return c; }
      }
      null
    }

The collections on the front of the site, whoever is looking: the owner's. A
draft is private to whoever holds its link; a collection is the exception,
and deliberately so, because these particular documents are public records
of the United States courts. The Elixir kept the answer for five minutes; a
child per request has nothing to keep it in, so it is computed each time. Use
`runs`' cache around it if it proves slow.

    export let casesPublished(db: Db): List<CaseStudy> throws Bubble {
      let owner = accountsOwner(db);
      if (owner == null) { [] } else { casesListFor(db, owner.id) }
    }

    export let casesList(db: Db): List<CaseStudy> throws Bubble { casesPublished(db) }

    export let casesGet(db: Db, slug: String): CaseStudy? throws Bubble {
      let all = casesPublished(db);
      for (let c of all) {
        if (c.slug == slug) { return c; }
      }
      null
    }

## Putting a draft in a case

`place(work, collection, role)`. `role` is one of the reading-order names, or
anything else, which sorts last. Anything given as the empty string is stored
as NULL (Ecto's `cast`); null clears it. Returns the stored draft.

    export let casesPlace(db: Db, work: Work, collection: String?, role: String?): Work throws Bubble {
      let c = casesBlankToNull(collection);
      let r = casesBlankToNull(role);
      cacheInvalidate(db, "published_cases");
      db.exec(
        "UPDATE works SET collection = $1, collection_role = $2, updated_at = $3 WHERE id = $4",
        casesPlaceArgs(c, r, sysUtcNow(), work.id),
      );
      let row = db.one("SELECT ${workColumns} FROM works WHERE id = $1", [work.id.toString()]);
      if (row == null) { bubble() } else { Work.fromRow(row) }
    }

    let casesBlankToNull(s: String?): String? {
      if (s == null) { null } else if (s.isEmpty) { null } else { s }
    }

    let casesPlaceArgs(c: String?, r: String?, now: String, id: Int): List<String?> {
      let out = new ListBuilder<String?>();
      out.add(c);
      out.add(r);
      out.add(now);
      out.add(id.toString());
      out.toList()
    }

## Ways in

`ways(c)`: the pairings of a case, best first. A case is read as one document
against another, so the contents page offers the actual pairings: the opinion
against the dissent, the opinion against the advocate it is answering, each
with how many edges the two have, because that number is the honest signal of
which one to open. A link counts when it is `linked`, both its drafts are in
the case and it has an edge; the lead is the one a reader would start with
(the lower reading rank, the first on a tie).

    export let casesWays(c: CaseStudy): List<CaseWay> {
      let byId = casesWorkMap(c.works);
      let out = new ListBuilder<CaseWay>();
      for (let l of c.links) {
        if (l.status == "linked") {
          let a = casesWorkById(byId, l.aWorkId);
          let b = casesWorkById(byId, l.bWorkId);
          if (a != null) {
            if (b != null) {
              let n = c.byLink.getOr(l.id, []).length;
              if (n > 0) {
                if (casesRank(a.collectionRole) <= casesRank(b.collectionRole)) {
                  out.add(new CaseWay(l, a, b, n));
                } else {
                  out.add(new CaseWay(l, b, a, n));
                }
              }
            }
          }
        }
      }
      out.toList().sorted { (x: CaseWay, y: CaseWay): Int =>
        let rx = casesRank(x.lead.collectionRole);
        let ry = casesRank(y.lead.collectionRole);
        if (rx != ry) { rx - ry } else { y.edges - x.edges }
      }
    }

## What a case looks like on a contents page

Not counts: counts tell a reader nothing about whether a case is worth
opening. What does is the disagreement between the documents, in the words
the pass used, and a couple of the sharpest places they collide. A
disagreement is the thing worth leading with: tension, then answers, then
requires, then everything else.

    let casesRankEdge(edgeType: String): Int {
      if (edgeType == "tension") {
        0
      } else if (edgeType == "answers") {
        1
      } else if (edgeType == "requires") {
        2
      } else {
        3
      }
    }

`preview(c)`. `summary` is the first link's summary that exists, with A and B
resolved. `sharpest` is the first three edges by that rank (stable, edges in
link order). `kinds` counts the edge types, most first, ties in type order.
`impression` is the opinion's first impression.

    let casesSummaryOf(s: String, a: Work?, b: Work?): String {
      if (a != null) {
        if (b != null) {
          return casesResolveRefs(s, casesName(a.title), casesName(b.title));
        }
      }
      s
    }

    export let casesPreview(c: CaseStudy): CasePreview {
      let byId = casesWorkMap(c.works);
      var summary: String? = null;
      for (let l of c.links) {
        let s = l.summary;
        if (summary == null) {
          if (s != null) {
            summary = casesSummaryOf(s, casesWorkById(byId, l.aWorkId), casesWorkById(byId, l.bWorkId));
          }
        }
      }
      let edges = new ListBuilder<LinkEdgeEnds>();
      for (let l of c.links) {
        for (let e of c.byLink.getOr(l.id, [])) { edges.add(e); }
      }
      let ranked = edges.toList().sorted { (x: LinkEdgeEnds, y: LinkEdgeEnds): Int =>
        casesRankEdge(x.edge.edgeType) - casesRankEdge(y.edge.edgeType)
      };
      let sharpest = new ListBuilder<LinkEdgeEnds>();
      var i = 0;
      while (i < ranked.length && i < 3) {
        sharpest.add(ranked[i]);
        i += 1;
      }
      let counts = new MapBuilder<String, Int>();
      let types = new ListBuilder<String>();
      for (let e of ranked) {
        let t = e.edge.edgeType;
        if (!counts.has(t)) { counts.set(t, 0); types.add(t); }
        counts.set(t, counts.getOr(t, 0) + 1);
      }
      let ordered = types.toList().sorted { (a: String, b: String): Int => casesCompareText(a, b) };
      let kinds = ordered
        .map { (t: String): CaseKind => new CaseKind(t, counts.getOr(t, 0)) }
        .sorted { (x: CaseKind, y: CaseKind): Int => y.count - x.count };
      var impression: String? = null;
      for (let w of c.works) {
        if (impression == null && w.collectionRole == "opinion") { impression = w.firstImpression; }
      }
      new CasePreview(summary, sharpest.toList(), kinds, impression)
    }

`kin(c)`: the other cases this one is related to, with a way into each
reading. Everything else on a case's card is the case arguing with itself;
this is the term arguing with itself.

    export let casesKin(c: CaseStudy): List<CaseKin> { c.kin }

`default_lead(c)`: the document a case should open on. The opinion, if there
is one: it is the thing that happened. Failing that, whatever sorts first.

    export let casesDefaultLead(c: CaseStudy): Work? {
      for (let w of c.works) {
        if (w.collectionRole == "opinion") { return w; }
      }
      if (c.works.length > 0) { c.works[0] } else { null }
    }

`record(c)` is `Cases.Record.for(c.name)`: the docket, dates and question of
a case, or null for a collection that is not a court case. `db` is unused; it
is in the signature so every function of the context reads alike.

    export let casesRecord(db: Db, c: CaseStudy): CaseRecord? { casesRecordFor(c.name) }

## Links and their words

The summary of a link with A and B resolved to the names of its two drafts
(`Links.summary/1`): null if there is no summary.

    export let casesLinkSummary(link: Link, a: Work, b: Work): String? {
      let s = link.summary;
      if (s == null) { null } else { casesResolveRefs(s, casesName(a.title), casesName(b.title)) }
    }

An edge with its rationale resolved (`Links.edges/1`).

    let casesPlainEdge(e: LinkEdgeEnds, a: Work, b: Work): LinkEdgeEnds {
      let r = e.edge.rationale;
      if (r == null) {
        e
      } else {
        let x = e.edge;
        new LinkEdgeEnds(
          new LinkEdge(
            x.id, x.linkId, x.fromId, x.toId, x.edgeType,
            casesResolveRefs(r, casesName(a.title), casesName(b.title)),
            x.ordinal, x.insertedAt, x.updatedAt,
          ),
          e.from,
          e.to,
        )
      }
    }

`Links.passage(node)`: what the reader would be shown for a node. With a
quote and a section, the first paragraph of the section that contains the
quote, or the quote itself if none does. With a quote and no section, the
quote. With neither, the node's title.

    export let casesPassage(db: Db, node: GraphNode): String throws Bubble {
      linksPassage(db, node)
    }

## One document, read with every other in its margin

`reading(c, lead_id)`. `Links.reading/2` is pairwise: one draft on the left,
one in the margin. That is the wrong shape for a case: an opinion is not
answering one thing, it is answering the dissent and the advocate who was
asked about it at the lectern, and the interesting moments are where those two
land on the same paragraph. So: every link in the collection that touches
`lead_id`, merged into one margin, each note stamped with the document it came
from, in the reading order of the source.

Null if the lead is not in the collection.

    export let casesReading(db: Db, c: CaseStudy, leadId: Int): CaseReading? throws Bubble {
      let byId = casesWorkMap(c.works);
      let lead = casesWorkById(byId, leadId);
      if (lead != null) { casesReadingOf(db, c, byId, lead) } else { null }
    }

    let casesReadingOf(db: Db, c: CaseStudy, byId: Map<Int, Work>, lead: Work): CaseReading throws Bubble {
      let inside = new ListBuilder<CaseSource>();
      for (let l of c.links) {
        if (l.status == "linked" && (l.aWorkId == lead.id || l.bWorkId == lead.id)) {
          let otherId = if (l.aWorkId == lead.id) { l.bWorkId } else { l.aWorkId };
          let other = casesWorkById(byId, otherId);
          if (other != null) { inside.add(new CaseSource(l, other, null)); }
        }
      }
      let ordered = inside.toList().sorted { (x: CaseSource, y: CaseSource): Int =>
        casesRank(x.work.collectionRole) - casesRank(y.work.collectionRole)
      };
      let sources = new ListBuilder<CaseSource>();
      for (let s of ordered) { sources.add(s); }
      for (let s of casesElsewhere(db, lead, c.name)) { sources.add(s); }
      let notes = new ListBuilder<CaseNote>();
      for (let s of sources.toList()) {
        for (let n of casesMargin(db, s.link, lead, s.work)) { notes.add(n); }
      }
      new CaseReading(lead, sources.toList(), notes.toList())
    }

The lead's links that reach outside this collection, each stamped with the
case it comes from. A term is one Court reasoning sixteen times, and the
places two of those readings touch are not visible from inside either case:
they are the reason to have a term rather than a pile of cases. They come
last, by case name, and say where they are from.

    let casesElsewhere(db: Db, lead: Work, caseName: String): List<CaseSource> throws Bubble {
      let links = new ListBuilder<Link>();
      for (let row of db.query(
        "SELECT ${linkColumns} FROM links WHERE (a_work_id = $1 OR b_work_id = $2) AND status = 'linked' ORDER BY updated_at DESC, id DESC",
        [lead.id.toString(), lead.id.toString()],
      )) {
        links.add(Link.fromRow(row));
      }
      if (links.length == 0) { return []; }
      let otherIds = links.toList().map { (l: Link): Int =>
        if (l.aWorkId == lead.id) { l.bWorkId } else { l.aWorkId }
      };
      let others = casesWorkMap(casesWorksOf(db.query(
        "SELECT ${workColumns} FROM works WHERE id IN (${casesIds(otherIds)})",
        [],
      )));
      let out = new ListBuilder<CaseSource>();
      for (let l of links.toList()) {
        let otherId = if (l.aWorkId == lead.id) { l.bWorkId } else { l.aWorkId };
        let other = casesWorkById(others, otherId);
        if (other != null) {
          let coll = other.collection;
          if (coll != null) {
            if (coll != caseName) { out.add(new CaseSource(l, other, coll)); }
          }
        }
      }
      out.toList().sorted { (x: CaseSource, y: CaseSource): Int =>
        casesCompareText(casesColl(x.work), casesColl(y.work))
      }
    }

`Links.margin(link, lead_id)` stamped with `from_work`, `from_title`,
`from_role`, `from_case` and `link_id`. For each edge (rationale resolved) the
near end is the one in the lead; a note is made only when the near node is in
the lead, has a section, and has a non-empty quote. The far end's section
ordinal is looked up in the other draft's sections.

    let casesOrdinal(m: Map<Int, Int>, id: Int?): Int? {
      if (id != null) {
        if (m.has(id)) { return m.getOr(id, -1); }
      }
      null
    }

    let casesMakeNote(
      link: Link, e: LinkEdgeEnds, near: GraphNode, far: GraphNode, nearSection: Int, quote: String,
      ordinals: Map<Int, Int>, other: Work,
    ): CaseNote {
      let body = e.edge.rationale;
      let arrow = if (e.edge.fromId == near.id) { "→ " } else { "← " };
      new CaseNote(
        "link:${e.edge.id.toString()}",
        nearSection,
        e.edge.edgeType,
        quote,
        "${arrow}${far.title}",
        if (body != null) { body } else { "" },
        false,
        e.edge.id,
        far.id,
        far.title,
        far.body,
        far.quote,
        far.nodeType,
        casesOrdinal(ordinals, far.sectionId),
        other.id,
        other.title,
        other.collectionRole,
        other.collection,
        link.id,
      )
    }

    let casesMargin(db: Db, link: Link, lead: Work, other: Work): List<CaseNote> throws Bubble {
      let a = if (link.aWorkId == lead.id) { lead } else { other };
      let b = if (link.aWorkId == lead.id) { other } else { lead };
      let ordinals = new MapBuilder<Int, Int>();
      for (let s of worksListSections(db, other.id)) { ordinals.set(s.id, s.ordinal); }
      let out = new ListBuilder<CaseNote>();
      for (let raw of casesLoadEdges(db, [link.id])) {
        let e = casesPlainEdge(raw, a, b);
        let fromHere = e.from.workId == lead.id;
        let near = if (fromHere) { e.from } else { e.to };
        let far = if (fromHere) { e.to } else { e.from };
        let nearSection = near.sectionId;
        let quote = near.quote;
        if (near.workId == lead.id) {
          if (nearSection != null) {
            if (quote != null) {
              if (!quote.isEmpty) {
                out.add(casesMakeNote(link, e, near, far, nearSection, quote, ordinals.toMap(), other));
              }
            }
          }
        }
      }
      out.toList()
    }
