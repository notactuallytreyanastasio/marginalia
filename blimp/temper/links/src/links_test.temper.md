# Tests for the links context

Ported from `links_test.exs` in `notes/tests.md` (24 tests), plus the rules the
notes state for `Links` that the Elixir tests did not reach: the status
machine and its 255-character error, `linkable`, `clusters`, the public face,
passages, margin notes.

    let { Work } = import("works/src");
    let { cachePut, cacheGet } = import("runs/src");

    class LinksPairFx(public fx: LinksFx, public link: Link) {}

## The pair

    test("the pair is unordered: linking A to B is the same row as B to A") { test =>
      let f = linksFixture();
      let same = linksGetOrCreate(f.db, f.b.id, f.a.id).ok;
      expectTrue(test, same != null, "found");
      if (same != null) {
        expectInt(test, same.id, f.link.id);
      }
      let found = linksGetFor(f.db, f.b.id, f.a.id);
      expectTrue(test, found != null, "get_for finds it");
      if (found != null) { expectInt(test, found.id, f.link.id); }
    }

    test("a pair is stored lowest id first, whichever way it was asked for") { test =>
      let f = linksFixture();
      let made = linksGetOrCreate(f.db, f.c.id, f.a.id).ok;
      expectTrue(test, made != null, "created");
      if (made != null) {
        expectInt(test, made.aWorkId, f.a.id);
        expectInt(test, made.bWorkId, f.c.id);
        expectText(test, made.status, "pending");
        expectTrue(test, made.summary == null, "no summary");
        expectTrue(test, made.error == null, "no error");
      }
    }

    test("a work cannot be linked to itself") { test =>
      let f = linksFixture();
      let r = linksGetOrCreate(f.db, f.a.id, f.a.id);
      expectTrue(test, r.ok == null, "no link");
      expectText(test, orNone(r.error), "same_work");
    }

    test("a link to a work that does not exist is refused, not raised") { test =>
      let f = linksFixture();
      let r = linksGetOrCreate(f.db, f.a.id, 999999);
      expectTrue(test, r.ok == null, "no link");
      expectText(test, orNone(r.error), "invalid");
    }

    test("it shows up from either side") { test =>
      let f = linksFixture();
      let fromA = linksForWork(f.db, f.a.id);
      expectInt(test, fromA.length, 1);
      expectInt(test, fromA[0].link.id, f.link.id);
      let fromB = linksForWork(f.db, f.b.id);
      expectInt(test, fromB.length, 1);
      expectInt(test, fromB[0].link.id, f.link.id);
      expectInt(test, linksForWork(f.db, f.c.id).length, 0);
    }

    test("the other side is named from whichever end you stand at") { test =>
      let f = linksFixture();
      let lw = linksWorks(f.db, f.link);
      expectInt(test, linksOther(lw, f.a.id).id, f.b.id);
      expectInt(test, linksOther(lw, f.b.id).id, f.a.id);
    }

    test("for_work is newest first, and ties are broken by id") { test =>
      let f = linksFixture();
      let second = linksGetOrCreate(f.db, f.a.id, f.c.id).ok;
      expectTrue(test, second != null, "created");
      let mine = linksForWork(f.db, f.a.id);
      expectInt(test, mine.length, 2);
      if (second != null) {
        expectInt(test, mine[0].link.id, second.id);
        expectInt(test, mine[1].link.id, f.link.id);
      }
    }

    test("find is scoped to the writer's own links") { test =>
      let f = linksFixture();
      let stranger = makeUser(f.db, "stranger@example.com");
      expectTrue(test, linksFind(f.db, f.scope, f.b.id, f.a.id) != null, "mine");
      expectTrue(test, linksFind(f.db, stranger, f.a.id, f.b.id) == null, "not theirs");
      expectTrue(test, linksFind(f.db, f.scope, f.a.id, f.c.id) == null, "no such pair");
    }

    test("linkable is the writer's own read drafts, and not the one asked about") { test =>
      let f = linksFixture();
      let loose = makeWork(f.db, f.scope, "Unread", "# U\n\nA sentence that is long enough to be a section.\n\n${repeated("word ", 100)}");
      let all = linksLinkable(f.db, f.scope, null);
      expectInt(test, all.length, 3);
      let others = linksLinkable(f.db, f.scope, f.a.id);
      expectInt(test, others.length, 2);
      for (let w of others) { expectTrue(test, w.id != f.a.id && w.id != loose.id, "only read, only others"); }
      let stranger = makeUser(f.db, "stranger@example.com");
      expectInt(test, linksLinkable(f.db, stranger, null).length, 0);
    }

    test("for_user lists the links either of whose works is the writer's") { test =>
      let f = linksFixture();
      let stranger = makeUser(f.db, "stranger@example.com");
      let theirs = makeRead(f.db, stranger, "Theirs", "# T\n\nA sentence that is long enough to be a section.\n\n${repeated("word ", 100)}");
      linksGetOrCreate(f.db, f.a.id, theirs.work.id);
      expectInt(test, linksForUser(f.db, f.scope).length, 2);
      expectInt(test, linksForUser(f.db, stranger).length, 1);
    }

## Storing what the model proposed

    test("a good edge is kept, with its reason") { test =>
      let f = linksFixture();
      let r = linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "answers", "It replies to the claim."), linkerTypes());
      expectInt(test, r.kept, 1);
      expectInt(test, r.dropped, 0);
      let edges = linksEdges(f.db, f.link);
      expectInt(test, edges.length, 1);
      expectText(test, edges[0].edge.edgeType, "answers");
      expectText(test, orNone(edges[0].edge.rationale), "It replies to the claim.");
      expectInt(test, edges[0].from.id, f.aNode.id);
      expectInt(test, edges[0].to.id, f.bNode.id);
    }

    test("an edge inside ONE manuscript is dropped") { test =>
      let f = linksFixture();
      let elsewhere = addNode(f.db, f.a, null, "spine", "elsewhere in the same draft", null);
      let r = linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, elsewhere.id, "develops", "Both in A."), linkerTypes());
      expectInt(test, r.kept, 0);
      expectInt(test, r.dropped, 1);
      expectInt(test, linksEdges(f.db, f.link).length, 0);
    }

    test("an invented id is dropped") { test =>
      let f = linksFixture();
      let r = linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, 999999, "develops", "Points at nothing."), linkerTypes());
      expectInt(test, r.kept, 0);
      expectInt(test, r.dropped, 1);
    }

    test("an id from a third manuscript is dropped") { test =>
      let f = linksFixture();
      let r = linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.cNode.id, "develops", "Reaches outside the pair."), linkerTypes());
      expectInt(test, r.kept, 0);
      expectInt(test, r.dropped, 1);
    }

    test("an unknown relation is dropped") { test =>
      let f = linksFixture();
      let r = linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "vibes_with", "Not a relation."), linkerTypes());
      expectInt(test, r.kept, 0);
      expectInt(test, r.dropped, 1);
    }

    test("an edge with no reason is dropped, the reason being the product") { test =>
      let f = linksFixture();
      let blank = edgeJson(f.aNode.id, f.bNode.id, "develops", "   ");
      let missing = "{\"from\":${f.bNode.id.toString()},\"to\":${f.aNode.id.toString()},\"type\":\"develops\"}";
      let r = linksStoreEdges(f.db, f.link, itemsOf([blank, missing]), linkerTypes());
      expectInt(test, r.kept, 0);
      expectInt(test, r.dropped, 2);
    }

    test("string ids are accepted, because models return both") { test =>
      let f = linksFixture();
      let text = "{\"from\":\"${f.aNode.id.toString()}\",\"to\":\"${f.bNode.id.toString()}\",\"type\":\"echoes\",\"why\":\"Same move.\"}";
      let r = linksStoreEdges(f.db, f.link, itemsOf([text]), linkerTypes());
      expectInt(test, r.kept, 1);
      expectInt(test, r.dropped, 0);
    }

    test("a string id is read by its leading digits, as Integer.parse does") { test =>
      let f = linksFixture();
      let text = "{\"from\":\"${f.aNode.id.toString()}abc\",\"to\":\"${f.bNode.id.toString()}\",\"type\":\"echoes\",\"why\":\"Prefix.\"}";
      let padded = "{\"from\":\" ${f.bNode.id.toString()}\",\"to\":\"${f.aNode.id.toString()}\",\"type\":\"echoes\",\"why\":\"Leading space is not a number.\"}";
      let r = linksStoreEdges(f.db, f.link, itemsOf([text, padded]), linkerTypes());
      expectInt(test, r.kept, 1);
      expectInt(test, r.dropped, 1);
    }

    test("a proposal that is not an object vanishes without being counted") { test =>
      let f = linksFixture();
      let good = edgeJson(f.aNode.id, f.bNode.id, "develops", "Once.");
      let r = linksStoreEdges(f.db, f.link, itemsOf(["\"nonsense\"", "7", "null", good]), linkerTypes());
      expectInt(test, r.kept, 1);
      expectInt(test, r.dropped, 0);
    }

    test("the same edge twice is stored once") { test =>
      let f = linksFixture();
      let e = edgeJson(f.aNode.id, f.bNode.id, "develops", "Once.");
      let r = linksStoreEdges(f.db, f.link, itemsOf([e, e]), linkerTypes());
      expectInt(test, r.kept, 1);
      expectInt(test, r.dropped, 0);
      expectInt(test, linksEdges(f.db, f.link).length, 1);
    }

    test("the same pair with another relation is a second edge, and ordinals follow the order given") { test =>
      let f = linksFixture();
      let first = edgeJson(f.aNode.id, f.bNode.id, "develops", "One.");
      let second = edgeJson(f.aNode.id, f.bNode.id, "tension", "Two.");
      let third = edgeJson(f.bNode.id, f.aNode.id, "answers", "Three.");
      let r = linksStoreEdges(f.db, f.link, itemsOf([first, second, third]), linkerTypes());
      expectInt(test, r.kept, 3);
      let edges = linksEdges(f.db, f.link);
      expectInt(test, edges.length, 3);
      expectText(test, edges[0].edge.edgeType, "develops");
      expectText(test, edges[1].edge.edgeType, "tension");
      expectText(test, edges[2].edge.edgeType, "answers");
      expectInt(test, edges[0].edge.ordinal, 0);
      expectInt(test, edges[2].edge.ordinal, 2);
    }

    test("storing what is already stored keeps nothing new and does not raise") { test =>
      let f = linksFixture();
      let e = oneEdge(f.aNode.id, f.bNode.id, "develops", "Once.");
      linksStoreEdges(f.db, f.link, e, linkerTypes());
      let again = linksStoreEdges(f.db, f.link, e, linkerTypes());
      expectInt(test, again.kept, 0);
      expectInt(test, linksEdgeCount(f.db, f.link.id), 1);
    }

    test("the edge count is capped") { test =>
      let f = linksFixture();
      let proposals = new ListBuilder<String>();
      var i = 1;
      while (i <= 80) {
        let n = addNode(f.db, f.b, null, "beat", "beat ${i.toString()}", null);
        proposals.add(edgeJson(f.aNode.id, n.id, "develops", "Reason ${i.toString()}."));
        i += 1;
      }
      let r = linksStoreEdgesMax(f.db, f.link, itemsOf(proposals.toList()), linkerTypes(), 10);
      expectInt(test, r.kept, 10);
      expectInt(test, r.dropped, 0);
      expectInt(test, linksEdges(f.db, f.link).length, 10);
    }

    test("the default cap is 140") { test =>
      expectInt(test, linksMaxEdges(), 140);
    }

    test("re-linking replaces rather than accumulates") { test =>
      let f = linksFixture();
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "develops", "First."), linkerTypes());
      linksClearEdges(f.db, f.link);
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "tension", "Second."), linkerTypes());
      let edges = linksEdges(f.db, f.link);
      expectInt(test, edges.length, 1);
      expectText(test, edges[0].edge.edgeType, "tension");
    }

    test("edges with both ends come back in the order they were drawn, nodes loaded") { test =>
      let f = linksFixture();
      let more = addNode(f.db, f.b, null, "beat", "a second beat", null);
      linksStoreEdges(f.db, f.link, itemsOf([
        edgeJson(f.aNode.id, more.id, "requires", "Needs it."),
        edgeJson(f.aNode.id, f.bNode.id, "echoes", "Echoes it."),
      ]), linkerTypes());
      let edges = linksEdgesOf(f.db, f.link.id);
      expectInt(test, edges.length, 2);
      expectText(test, edges[0].to.title, "a second beat");
      expectText(test, edges[1].to.title, "a beat in Second");
      expectText(test, edges[1].from.title, "a beat in First");
    }

    test("deleting a node takes its edges with it") { test =>
      let f = linksFixture();
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "develops", "Gone soon."), linkerTypes());
      f.db.exec("DELETE FROM nodes WHERE id = $1", [f.bNode.id.toString()]);
      expectInt(test, linksEdgeCount(f.db, f.link.id), 0);
    }

## The vocabulary

    test("the vocabulary is the one a reader already knows, minus what cannot cross") { test =>
      let types = linkerTypes();
      expectInt(test, types.length, 6);
      expectFalse(test, linksIn(types, "realises"), "realises is about a node's own spine");
      expectFalse(test, linksIn(types, "asks_about"), "asks_about is about a node's own spine");
      for (let t of ["develops", "pays_off", "requires", "tension", "answers", "echoes"]) {
        expectTrue(test, linksIn(types, t), t);
      }
    }

    test("every relation in the vocabulary is described in the prompt") { test =>
      for (let t of linkerTypes()) { expectHas(test, linkerPrompt(), t); }
    }

    test("the prompt forbids the same-document edge in words, as well as in code") { test =>
      expectHas(test, linkerPrompt(), "one end in manuscript A and the other in manuscript B");
    }

## Stats

    test("stats count both the edges and how much of each side they touch") { test =>
      let f = linksFixture();
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "answers", "Because."), linkerTypes());
      let s = linksStats(f.db, f.link);
      expectInt(test, s.edges, 1);
      expectInt(test, s.byType.length, 1);
      expectInt(test, s.byType.getOr("answers", 0), 1);
      expectInt(test, s.aNodes, 1);
      expectInt(test, s.bNodes, 1);
    }

    test("stats count distinct nodes, not edge ends") { test =>
      let f = linksFixture();
      let more = addNode(f.db, f.b, null, "beat", "a second beat", null);
      linksStoreEdges(f.db, f.link, itemsOf([
        edgeJson(f.aNode.id, f.bNode.id, "answers", "One."),
        edgeJson(f.aNode.id, more.id, "develops", "Two."),
        edgeJson(f.bNode.id, f.aNode.id, "tension", "Three."),
      ]), linkerTypes());
      let s = linksStats(f.db, f.link);
      expectInt(test, s.edges, 3);
      expectInt(test, s.aNodes, 1);
      expectInt(test, s.bNodes, 2);
      expectInt(test, s.byType.length, 3);
    }

## Calling the documents by their names

A numbered stack title, and one whose own text starts with "A ": between them
they are every way this has gone wrong.

    class LinksNamedFx(public db: Db, public link: Link) {}

    let namedFixture(): LinksNamedFx throws Bubble {
      let f = linksFixture();
      worksUpdateWork(f.db, f.a, workParams("1. A page with no script on it", null));
      worksUpdateWork(f.db, f.b, workParams("2. The backend scaffold", null));
      new LinksNamedFx(f.db, f.link)
    }

    test("a title beginning with a digit keeps its number") { test =>
      let f = namedFixture();
      let out = linksPlain(f.db, f.link, "runner. B answers it.");
      expectHas(test, out, "2. The backend scaffold");
      expectLacks(test, out, "runner.. ");
      expectText(test, out, "runner. 2. The backend scaffold answers it.");
    }

    test("a title is never substituted into a second time") { test =>
      let f = namedFixture();
      let out = linksPlain(f.db, f.link, "B answers A's open question.");
      expectText(test, out, "2. The backend scaffold answers 1. A page with no script on it's open question.");
      expectLacks(test, out, "1. 1.");
    }

    test("a possessive letter is resolved wherever it appears") { test =>
      let f = namedFixture();
      expectHas(test, linksPlain(f.db, f.link, "It sits downstream of A's grammar."), "1. A page with no script on it's grammar");
    }

    test("the full form is resolved and loses the word Manuscript") { test =>
      let f = namedFixture();
      let out = linksPlain(f.db, f.link, "Manuscript B extends Manuscript A.");
      expectText(test, out, "2. The backend scaffold extends 1. A page with no script on it.");
      expectLacks(test, out, "Manuscript");
    }

    test("a bare letter mid-sentence is left alone, and so is the article") { test =>
      let f = namedFixture();
      expectHas(test, linksPlain(f.db, f.link, "See Part A and Exhibit B."), "Part A and Exhibit B");
      expectLacks(test, linksPlain(f.db, f.link, "It extends B."), "2. The backend scaffold");
      expectText(test, linksPlain(f.db, f.link, "It extends B."), "It extends B.");
    }

    test("the summary goes through the same substitution") { test =>
      let f = namedFixture();
      let linked = linksSetStatus(f.db, f.link, "linked", linksAttrsSummary("B develops it. A is upstream.")).ok;
      expectTrue(test, linked != null, "set");
      if (linked != null) {
        let s = linksSummary(f.db, linked);
        expectHas(test, orNone(s), "2. The backend scaffold");
        expectHas(test, orNone(s), "1. A page with no script on it");
      }
    }

    test("a link with no summary has none to substitute") { test =>
      let f = namedFixture();
      expectTrue(test, linksSummary(f.db, f.link) == null, "nothing");
    }

    test("the edges of a link come back with the names in their reasons") { test =>
      let f = linksFixture();
      worksUpdateWork(f.db, f.a, workParams("1. A page with no script on it", null));
      worksUpdateWork(f.db, f.b, workParams("2. The backend scaffold", null));
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "answers", "Manuscript B answers Manuscript A."), linkerTypes());
      let named = linksEdges(f.db, f.link);
      expectText(test, orNone(named[0].edge.rationale), "2. The backend scaffold answers 1. A page with no script on it.");
      let raw = linksEdgesOf(f.db, f.link.id);
      expectText(test, orNone(raw[0].edge.rationale), "Manuscript B answers Manuscript A.");
    }

    test("pure substitution: the start of the text is a sentence start") { test =>
      expectText(test, linksPlainWith("A is first. B is second.", "Alpha", "Beta"), "Alpha is first. Beta is second.");
    }

    test("pure substitution: punctuation before a letter makes it a label, a space alone does not") { test =>
      expectText(test, linksPlainWith("x; B and x: A and x — B, but x B", "Alpha", "Beta"), "x; Beta and x: Alpha and x — Beta, but x B");
    }

    test("pure substitution: a letter followed by a letter, digit or apostrophe is not a label") { test =>
      expectText(test, linksPlainWith("AB. A1. A'x. B’s fine.", "Alpha", "Beta"), "AB. A1. A'x. Beta’s fine.");
    }

    test("pure substitution: Manuscripts in the plural and any spacing") { test =>
      expectText(test, linksPlainWith("Manuscripts   A and Manuscript B.", "Alpha", "Beta"), "Alpha and Beta.");
    }

    test("a collection's name is dropped from a title") { test =>
      expectText(test, linksName("Miller v. Alabama — Opinion"), "Opinion");
      expectText(test, linksName("Plain title"), "Plain title");
      expectText(test, linksName("Case — Part — Two"), "Part — Two");
    }

    test("a title with its collection is called by the part after the dash") { test =>
      let f = linksFixture();
      worksUpdateWork(f.db, f.a, workParams("Miller — The opinion", null));
      worksUpdateWork(f.db, f.b, workParams("Miller — The dissent", null));
      expectText(test, linksPlain(f.db, f.link, "B answers. A responds."), "The dissent answers. The opinion responds.");
    }

## Reading integers the way the Elixir did

    test("Integer.parse reads a sign and leading digits and nothing else") { test =>
      expectInt(test, orZero(linksParseIntPrefix("12abc")), 12);
      expectInt(test, orZero(linksParseIntPrefix("-7")), -7);
      expectInt(test, orZero(linksParseIntPrefix("+7")), 7);
      expectTrue(test, linksParseIntPrefix("abc") == null, "no digits");
      expectTrue(test, linksParseIntPrefix(" 12") == null, "a leading space is not a digit");
      expectTrue(test, linksParseIntPrefix("") == null, "empty");
      expectTrue(test, linksParseIntPrefix("99999999999") == null, "past any id");
    }

    let orZero(n: Int?): Int {
      if (n != null) { n } else { -999 }
    }

## The status machine

    test("a new link is pending, with no summary and no error") { test =>
      let f = linksFixture();
      expectText(test, f.link.status, "pending");
    }

    test("set_status moves through the four states and keeps what it was not told to change") { test =>
      let f = linksFixture();
      let linking = linksSetStatus(f.db, f.link, "linking", linksAttrsError(null)).ok;
      expectTrue(test, linking != null, "linking");
      if (linking != null) {
        expectText(test, linking.status, "linking");
        let linked = linksSetStatus(f.db, linking, "linked", linksAttrsBoth("They agree.", null)).ok;
        expectTrue(test, linked != null, "linked");
        if (linked != null) {
          expectText(test, linked.status, "linked");
          expectText(test, orNone(linked.summary), "They agree.");
          let failed = linksSetStatus(f.db, linked, "failed", linksAttrsError(":no_edges")).ok;
          expectTrue(test, failed != null, "failed");
          if (failed != null) {
            expectText(test, failed.status, "failed");
            expectText(test, orNone(failed.error), ":no_edges");
            expectText(test, orNone(failed.summary), "They agree.");
            let again = linksSetStatus(f.db, failed, "linking", linksAttrsError(null)).ok;
            if (again != null) { expectTrue(test, again.error == null, "the error is cleared"); }
          }
        }
      }
    }

    test("a status outside the four is refused and nothing is written") { test =>
      let f = linksFixture();
      let r = linksSetStatus(f.db, f.link, "done", linksAttrsNone());
      expectTrue(test, r.ok == null, "refused");
      expectText(test, orNone(r.error), "status is invalid");
      let reread = linksGet(f.db, f.link.id);
      if (reread != null) { expectText(test, reread.status, "pending"); }
    }

    test("an error longer than 255 characters is cut there, not refused") { test =>
      let f = linksFixture();
      let long = repeated("é", 400);
      let r = linksSetStatus(f.db, f.link, "failed", linksAttrsError(long)).ok;
      expectTrue(test, r != null, "stored");
      if (r != null) {
        expectInt(test, sysGraphemeLength(orNone(r.error)), 255);
      }
    }

    test("listing the linked ones leaves out the others") { test =>
      let f = linksFixture();
      let other = linksGetOrCreate(f.db, f.a.id, f.c.id).ok;
      linksSetStatus(f.db, f.link, "linked", linksAttrsNone());
      expectTrue(test, other != null, "second");
      expectInt(test, linksListLinked(f.db, f.scope).length, 1);
    }

## Constellations

    test("clusters group drafts that can be reached from each other, and name the pairs not linked yet") { test =>
      let f = linksFixture();
      linksGetOrCreate(f.db, f.b.id, f.c.id);
      let d = makeRead(f.db, f.scope, "Fourth", "# Four\n\nA sentence that is long enough to be a section.\n\n${repeated("word ", 100)}");
      let e = makeRead(f.db, f.scope, "Fifth", "# Five\n\nA sentence that is long enough to be a section.\n\n${repeated("word ", 100)}");
      linksGetOrCreate(f.db, d.work.id, e.work.id);
      let groups = linksClusters(f.db, f.scope);
      expectInt(test, groups.length, 2);
      expectInt(test, groups[0].works.length, 3);
      expectInt(test, groups[0].links.length, 2);
      expectInt(test, groups[0].missing.length, 1);
      expectText(test, groups[0].works[0].title, "First");
      expectText(test, groups[0].works[2].title, "Third");
      expectText(test, groups[0].missing[0].a.title, "First");
      expectText(test, groups[0].missing[0].b.title, "Third");
      expectInt(test, groups[1].works.length, 2);
      expectInt(test, groups[1].missing.length, 0);
    }

    test("a writer with no links has no clusters") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "writer@example.com");
      expectInt(test, linksClusters(db, me).length, 0);
    }

## The public face

    class LinksPublicFx(public f: LinksFx, public owner: Scope) {}

The deploy's owner is the account with the owner email; its links are public
once they found something.

    let publicFixture(): LinksPublicFx throws Bubble {
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      let a = makeRead(db, owner, "First", "# One\n\nA sentence that is long enough to be a section.\n\n${repeated("word ", 200)}");
      let b = makeRead(db, owner, "Second", "# Two\n\nAnother sentence that is long enough here.\n\n${repeated("word ", 200)}");
      let c = makeRead(db, owner, "Third", "# Three\n\nA third sentence, also long enough for this.\n\n${repeated("word ", 200)}");
      let link = linksLinkOrBubble(linksGetOrCreate(db, a.work.id, b.work.id).ok);
      new LinksPublicFx(new LinksFx(db, owner, a.work, b.work, c.work, a.node, b.node, c.node, link), owner)
    }

    test("a link with no edges is not on the public list, and has no public page") { test =>
      let p = publicFixture();
      expectInt(test, linksPublicLinks(p.f.db).length, 0);
      expectTrue(test, linksPublicLink(p.f.db, p.f.link.id) == null, "no edges, no page");
    }

    test("the public list is strongest first: tensions, then edges") { test =>
      let p = publicFixture();
      let f = p.f;
      let second = linksLinkOrBubble(linksGetOrCreate(f.db, f.a.id, f.c.id).ok);
      let more = addNode(f.db, f.c, null, "beat", "another", null);
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "echoes", "Same move."), linkerTypes());
      linksStoreEdges(f.db, second, itemsOf([
        edgeJson(f.aNode.id, f.cNode.id, "tension", "They part."),
        edgeJson(f.aNode.id, more.id, "answers", "It replies."),
      ]), linkerTypes());
      let listed = linksPublicLinks(f.db);
      expectInt(test, listed.length, 2);
      expectInt(test, listed[0].link.link.id, second.id);
      expectInt(test, listed[0].edges, 2);
      expectInt(test, listed[0].tensions, 1);
      expectInt(test, listed[1].link.link.id, f.link.id);
      expectInt(test, listed[1].tensions, 0);
      expectTrue(test, linksPublicLink(f.db, f.link.id) != null, "has a page");
    }

    test("a public page needs BOTH works to belong to the owner") { test =>
      let p = publicFixture();
      let f = p.f;
      let stranger = makeUser(f.db, "stranger@example.com");
      let theirs = makeRead(f.db, stranger, "Theirs", "# T\n\nA sentence that is long enough to be a section.\n\n${repeated("word ", 100)}");
      let mixed = linksLinkOrBubble(linksGetOrCreate(f.db, f.a.id, theirs.work.id).ok);
      linksStoreEdges(f.db, mixed, oneEdge(f.aNode.id, theirs.node.id, "echoes", "Same move."), linkerTypes());
      expectTrue(test, linksPublicLink(f.db, mixed.id) == null, "one of the two is somebody else's");
    }

    test("with no owner account there is nothing public") { test =>
      let f = linksFixture();
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "echoes", "Same move."), linkerTypes());
      expectInt(test, linksPublicLinks(f.db).length, 0);
      expectTrue(test, linksPublicLink(f.db, f.link.id) == null, "no owner");
    }

## Passages and margin notes

    test("a passage is the paragraph the anchored sentence sits in") { test =>
      let f = linksFixture();
      let section = firstSection(f.db, f.a);
      let n = addNode(f.db, f.a, section, "beat", "the sentence", "long enough to be a section");
      expectText(test, linksPassage(f.db, n), "A sentence that is long enough to be a section.");
    }

    test("a passage falls back to the quote when it is not in the section, and to the title with no quote") { test =>
      let f = linksFixture();
      let section = firstSection(f.db, f.a);
      let lost = addNode(f.db, f.a, section, "beat", "lost", "words that are nowhere in it");
      expectText(test, linksPassage(f.db, lost), "words that are nowhere in it");
      let loose = addNode(f.db, f.a, null, "beat", "no section", "a quote without a section");
      expectText(test, linksPassage(f.db, loose), "a quote without a section");
      let bare = addNode(f.db, f.a, null, "spine", "A claim about the whole draft", null);
      expectText(test, linksPassage(f.db, bare), "A claim about the whole draft");
    }

    test("notes are the edges whose near end is an anchored beat, with the arrow for the direction") { test =>
      let f = linksFixture();
      let spine = addNode(f.db, f.b, null, "spine", "a claim about the whole of Second", null);
      linksStoreEdges(f.db, f.link, itemsOf([
        edgeJson(f.aNode.id, f.bNode.id, "answers", "It replies."),
        edgeJson(f.bNode.id, f.aNode.id, "tension", "It pushes back."),
        edgeJson(f.aNode.id, spine.id, "develops", "Unanchored on the far side."),
      ]), linkerTypes());
      let aNotes = linksNotesFor(f.db, f.link, f.a.id);
      expectInt(test, aNotes.length, 3);
      expectText(test, aNotes[0].title, "→ a beat in Second");
      expectText(test, aNotes[1].title, "← a beat in Second");
      expectText(test, aNotes[0].kind, "answers");
      expectText(test, aNotes[0].quote, "a sentence");
      expectInt(test, aNotes[0].peer, f.bNode.id);
      expectInt(test, aNotes[0].nearId, f.aNode.id);
      expectText(test, aNotes[0].body, "It replies.");
      let bNotes = linksNotesFor(f.db, f.link, f.b.id);
      expectInt(test, bNotes.length, 2);
      expectText(test, bNotes[0].title, "← a beat in First");
      expectInt(test, bNotes[0].peer, f.aNode.id);
    }

    test("margin carries the far end whole: its title, quote, kind and section") { test =>
      let f = linksFixture();
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "answers", "It replies."), linkerTypes());
      let notes = linksMargin(f.db, f.link, f.a.id);
      expectInt(test, notes.length, 1);
      expectText(test, orNone(notes[0].farTitle), "a beat in Second");
      expectText(test, orNone(notes[0].farQuote), "a sentence");
      expectText(test, orNone(notes[0].farKind), "beat");
      expectInt(test, orZero(notes[0].farSection), 1);
    }

## Invalidating the public caches

    test("a new pair drops the cached public lists, finding one does not") { test =>
      let f = linksFixture();
      cachePut(f.db, "public_links", "[1]", 300);
      cachePut(f.db, "published_cases", "[2]", 300);
      linksGetOrCreate(f.db, f.a.id, f.b.id);
      expectText(test, orNone(cacheGet(f.db, "public_links")), "[1]");
      linksGetOrCreate(f.db, f.a.id, f.c.id);
      expectTrue(test, cacheGet(f.db, "public_links") == null, "dropped by a new pair");
      expectTrue(test, cacheGet(f.db, "published_cases") == null, "and the cases with it");
    }

    test("storing and clearing edges drops them too") { test =>
      let f = linksFixture();
      cachePut(f.db, "public_links", "[1]", 300);
      linksStoreEdges(f.db, f.link, oneEdge(f.aNode.id, f.bNode.id, "echoes", "Same move."), linkerTypes());
      expectTrue(test, cacheGet(f.db, "public_links") == null, "dropped by storing");
      cachePut(f.db, "public_links", "[1]", 300);
      linksClearEdges(f.db, f.link);
      expectTrue(test, cacheGet(f.db, "public_links") == null, "dropped by clearing");
    }
