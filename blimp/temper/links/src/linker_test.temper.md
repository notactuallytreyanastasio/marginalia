# Tests for the linker

Ported from the Linker parts of `links_test.exs`, `compare_summary_test.exs`
(`Linker.run` on an unread pair fails with `:not_read`) and `prompts_test.exs`
in `notes/tests.md`, plus the whole of `Analysis.Linker.run`, which the Elixir
suite never reached because it called a real model: here a fake one answers
with replies shaped as section 5.4 of `domain-works.md` says.

    let { versionsLinkTopic } = import("runs/src");
    let { worksGetById, worksNodes } = import("works/src");

    class LinkerFx(public f: LinksFx, public topic: String) {}

    let linkerFixture(): LinkerFx throws Bubble {
      let f = linksFixture();
      new LinkerFx(f, versionsLinkTopic(f.link.id))
    }

    let versionOf(x: LinkerFx): Int throws Bubble { versionsOf(x.f.db, x.topic) }

## The prompt, verbatim

    test("the prompt says never a bare A or B, and to name the manuscripts in full") { test =>
      expectHas(test, linkerPrompt(), "Never a bare");
      let p = linkerPrompt();
      expectBefore(test, p, "Manuscript A", "IN FULL");
    }

    test("the prompts are the Elixir heredocs to the character") { test =>
      expectInt(test, sysGraphemeLength(linkerPrompt()), 3712);
      expectInt(test, sysGraphemeLength(linkerCrowded()), 323);
      expectInt(test, sysGraphemeLength(linksChatSystem()), 1347);
      expectInt(test, sysGraphemeLength(linksBulkPrompt()), 696);
    }

    test("each prompt starts and ends as its heredoc does") { test =>
      expectTrue(test, linkerPrompt().split("\n")[0] == "You are given the maps of TWO manuscripts that have already been read. Not the texts —", "first line");
      expectText(test, linkerPrompt().split("\n")[1], "the maps: every beat, the spine, the threads, the open questions, each with a numeric id");
      expectTrue(test, linkerPrompt().split("\n").length == 58, "57 lines and the trailing newline");
      expectHas(test, linkerPrompt(), "has read both and wants to know what sits between them.\n");
      expectText(test, linkerCrowded().split("\n")[0], "");
      expectText(test, linkerCrowded().split("\n")[1], "THIS PAIR IS LARGE AND YOUR LAST ANSWER DID NOT FIT.");
      expectHas(test, linkerCrowded(), "manuscript.\n");
      expectHas(test, linksBulkPrompt(), "You are given a list of documents that belong to one writer, one line each, and must choose which PAIRS");
      expectHas(test, linksBulkPrompt(), "Report by calling propose_links.\n");
    }

    test("the linker pass lists the link prompt") { test =>
      let passes = linkerPasses();
      expectInt(test, passes.length, 1);
      expectText(test, passes[0].id, "link");
      expectText(test, passes[0].name, "Linking — how two graphs relate");
      expectText(test, passes[0].runs, "once per pair of manuscripts");
      expectText(test, passes[0].produces, "edges between the nodes of two drafts, plus a summary of the relationship");
      expectText(test, passes[0].prompt, linkerPrompt());
    }

## What the model is given

    test("the catalogue has both maps, the section, the body and the quote of each node") { test =>
      let f = linksFixture();
      f.db.exec("UPDATE works SET intent = $1 WHERE id = $2", ["to unsettle", f.a.id.toString()]);
      let a = worksGetById(f.db, f.a.id);
      let more = addNode(f.db, f.b, null, "spine", "the claim", "a\n  quoted    line");
      f.db.exec("UPDATE nodes SET body = $1 WHERE id = $2", [repeated("b", 200), more.id.toString()]);
      let aNodes = worksNodes(f.db, f.a.id);
      let bNodes = worksNodes(f.db, f.b.id);
      expectTrue(test, a != null, "work a");
      if (a != null) {
        let cat = linkerCatalogue(f.db, a, f.b, aNodes, bNodes);
        let want = "# MANUSCRIPT A: First\nIntended effect on a reader: to unsettle\n\n## Beats, in document order\n  [${f.aNode.id.toString()}] (§1) a beat in First\n      \"a sentence\"\n\n\n\n\n# MANUSCRIPT B: Second\n\n## Beats, in document order\n  [${f.bNode.id.toString()}] (§1) a beat in Second\n      \"a sentence\"\n\n## Spine\n  [${more.id.toString()}] the claim — ${repeated("b", 150)}\n      \"a quoted line\"\n\n\n";
        expectText(test, cat, want);
      }
    }

    test("a node with no section has no section mark, and the quote is cut at 180") { test =>
      let f = linksFixture();
      let n = addNode(f.db, f.b, null, "question", "why", repeated("q", 300));
      let cat = linkerCatalogue(f.db, f.a, f.b, worksNodes(f.db, f.a.id), worksNodes(f.db, f.b.id));
      expectHas(test, cat, "## Open questions\n  [${n.id.toString()}] why\n      \"${repeated("q", 180)}\"");
      expectLacks(test, cat, repeated("q", 181));
    }

## The pass

    test("a pair of read drafts is related: edges stored, summary set, status linked") { test =>
      let x = linkerFixture();
      let f = x.f;
      let fake = llmFake([linkerReply("Manuscript B answers Manuscript A.", [
        edgeJson(f.aNode.id, f.bNode.id, "answers", "Manuscript B replies to the claim in Manuscript A."),
      ])]);
      let r = linkerRun(f.db, fake, f.link);
      expectTrue(test, r.ok, "ok");
      expectInt(test, r.kept, 1);
      expectInt(test, r.dropped, 0);
      expectTrue(test, r.error == null, "no error");
      let link = linksGet(f.db, f.link.id);
      expectTrue(test, link != null, "reloaded");
      if (link != null) {
        expectText(test, link.status, "linked");
        expectText(test, orNone(link.summary), "Manuscript B answers Manuscript A.");
        expectTrue(test, link.error == null, "no error stored");
      }
      let edges = linksEdges(f.db, f.link);
      expectInt(test, edges.length, 1);
      expectText(test, orNone(edges[0].edge.rationale), "Second replies to the claim in First.");
      expectText(test, orNone(linksEdgesOf(f.db, f.link.id)[0].edge.rationale), "Manuscript B replies to the claim in Manuscript A.");
      let result = r.link;
      expectTrue(test, result != null, "the link comes back");
      if (result != null) { expectText(test, result.status, "linked"); }
    }

    test("the call is effort high, temperature 0.4, 24000 tokens, JSON mode, prompt then catalogue") { test =>
      let x = linkerFixture();
      let f = x.f;
      let fake = llmFake([linkerReply("S.", [])]);
      linkerRun(f.db, fake, f.link);
      expectInt(test, requestCount(test, fake), 1);
      let body = lastRequest(test, fake);
      expectHas(test, body, "\"reasoning_effort\":\"high\"");
      expectHas(test, body, "\"temperature\":0.4");
      expectHas(test, body, "\"max_tokens\":48000");
      expectHas(test, body, "\"response_format\":{\"type\":\"json_object\"}");
      expectLacks(test, body, "\"tools\"");
      expectBefore(test, body, "You are given the maps of TWO manuscripts", "# MANUSCRIPT A: First");
      expectBefore(test, body, "# MANUSCRIPT A: First", "# MANUSCRIPT B: Second");
      expectLacks(test, body, "THIS PAIR IS LARGE");
    }

    test("an answer that was cut off is asked again with the addendum, once") { test =>
      let x = linkerFixture();
      let f = x.f;
      let fake = llmFake([replyCutOff(), linkerReply("Second try.", [edgeJson(f.aNode.id, f.bNode.id, "echoes", "Same move.")])]);
      let r = linkerRun(f.db, fake, f.link);
      expectTrue(test, r.ok, "ok after the retry");
      expectInt(test, r.kept, 1);
      expectInt(test, requestCount(test, fake), 2);
      expectLacks(test, requestsOf(test, fake)[0], "THIS PAIR IS LARGE AND YOUR LAST ANSWER DID NOT FIT.");
      expectHas(test, requestsOf(test, fake)[1], "THIS PAIR IS LARGE AND YOUR LAST ANSWER DID NOT FIT.");
      expectHas(test, requestsOf(test, fake)[1], "Return AT MOST 45 edges");
      expectBefore(test, requestsOf(test, fake)[1], "has read both and wants to know what sits between them.", "THIS PAIR IS LARGE");
      let link = linksGet(f.db, f.link.id);
      if (link != null) { expectText(test, orNone(link.summary), "Second try."); }
    }

    test("two cut-off answers in a row fail the link, with the second as the reason") { test =>
      let x = linkerFixture();
      let f = x.f;
      let fake = llmFake([replyCutOff(), replyCutOff()]);
      let r = linkerRun(f.db, fake, f.link);
      expectFalse(test, r.ok, "failed");
      expectInt(test, requestCount(test, fake), 2);
      expectHas(test, orNone(r.error), "length");
      let link = linksGet(f.db, f.link.id);
      if (link != null) { expectText(test, link.status, "failed"); }
    }

    test("a reply with no content is a failed link, and is not retried") { test =>
      let x = linkerFixture();
      let f = x.f;
      let fake = llmFake([replyNothing()]);
      let r = linkerRun(f.db, fake, f.link);
      expectFalse(test, r.ok, "failed");
      expectInt(test, requestCount(test, fake), 1);
      let link = linksGet(f.db, f.link.id);
      expectTrue(test, link != null, "reloaded");
      if (link != null) {
        expectText(test, link.status, "failed");
        expectHas(test, orNone(link.error), "invalid_json");
        expectText(test, orNone(link.error), orNone(r.error));
      }
    }

    test("a malformed reply fails the link with the client's error, verbatim") { test =>
      let x = linkerFixture();
      let f = x.f;
      let fake = llmFake([replyText("Here are some edges: not json at all")]);
      let r = linkerRun(f.db, fake, f.link);
      expectFalse(test, r.ok, "failed");
      expectText(test, orNone(r.error), "invalid_json: the reply is not a JSON object: Here are some edges: not json at all");
      let link = linksGet(f.db, f.link.id);
      if (link != null) { expectText(test, orNone(link.error), "invalid_json: the reply is not a JSON object: Here are some edges: not json at all"); }
    }

    test("an object without an edges list fails the link as no_edges") { test =>
      let x = linkerFixture();
      let f = x.f;
      let r = linkerRun(f.db, llmFake([replyText("{\"summary\":\"nothing to say\"}")]), f.link);
      expectFalse(test, r.ok, "failed");
      expectText(test, orNone(r.error), ":no_edges");
      let link = linksGet(f.db, f.link.id);
      if (link != null) {
        expectText(test, link.status, "failed");
        expectText(test, orNone(link.error), ":no_edges");
      }
    }

    test("edges that is not a list is no_edges too") { test =>
      let x = linkerFixture();
      let f = x.f;
      let r = linkerRun(f.db, llmFake([replyText("{\"summary\":\"s\",\"edges\":\"many\"}")]), f.link);
      expectText(test, orNone(r.error), ":no_edges");
    }

    test("an empty edges list is a real answer: linked, with nothing stored") { test =>
      let x = linkerFixture();
      let f = x.f;
      let r = linkerRun(f.db, llmFake([linkerReply("They have nothing to do with each other.", [])]), f.link);
      expectTrue(test, r.ok, "ok");
      expectInt(test, r.kept, 0);
      let link = linksGet(f.db, f.link.id);
      if (link != null) { expectText(test, link.status, "linked"); }
    }

    test("the edges the model invented are dropped and counted") { test =>
      let x = linkerFixture();
      let f = x.f;
      let fake = llmFake([linkerReply("S.", [
        edgeJson(f.aNode.id, f.bNode.id, "answers", "Real."),
        edgeJson(f.aNode.id, 999999, "answers", "Invented."),
        edgeJson(f.aNode.id, f.cNode.id, "answers", "Third manuscript."),
        edgeJson(f.aNode.id, f.bNode.id, "realises", "Not a cross-document relation."),
      ])]);
      let r = linkerRun(f.db, fake, f.link);
      expectInt(test, r.kept, 1);
      expectInt(test, r.dropped, 3);
      expectInt(test, linksEdgeCount(f.db, f.link.id), 1);
    }

    test("running again replaces the previous edges rather than adding to them") { test =>
      let x = linkerFixture();
      let f = x.f;
      linkerRun(f.db, llmFake([linkerReply("One.", [edgeJson(f.aNode.id, f.bNode.id, "develops", "First.")])]), f.link);
      expectInt(test, linksEdgeCount(f.db, f.link.id), 1);
      linkerRun(f.db, llmFake([linkerReply("Two.", [edgeJson(f.aNode.id, f.bNode.id, "tension", "Second.")])]), f.link);
      let edges = linksEdges(f.db, f.link);
      expectInt(test, edges.length, 1);
      expectText(test, edges[0].edge.edgeType, "tension");
    }

    test("a failed second run leaves the first run's edges alone") { test =>
      let x = linkerFixture();
      let f = x.f;
      linkerRun(f.db, llmFake([linkerReply("One.", [edgeJson(f.aNode.id, f.bNode.id, "develops", "First.")])]), f.link);
      let r = linkerRun(f.db, llmFake([replyNothing()]), f.link);
      expectFalse(test, r.ok, "failed");
      expectInt(test, linksEdgeCount(f.db, f.link.id), 1);
      let link = linksGet(f.db, f.link.id);
      if (link != null) {
        expectText(test, link.status, "failed");
        expectText(test, orNone(link.summary), "One.");
      }
    }

    test("a run clears the error of the run before it") { test =>
      let x = linkerFixture();
      let f = x.f;
      linkerRun(f.db, llmFake([replyNothing()]), f.link);
      linkerRun(f.db, llmFake([linkerReply("Fine now.", [])]), f.link);
      let link = linksGet(f.db, f.link.id);
      if (link != null) {
        expectText(test, link.status, "linked");
        expectTrue(test, link.error == null, "cleared");
      }
    }

    test("a draft nobody has read fails the link as not_read, before any model call") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "writer@example.com");
      let a = makeWork(db, me, "Opinion", "# O\n\n${repeated("word ", 100)}");
      let b = makeWork(db, me, "Summary", "# S\n\n${repeated("word ", 100)}");
      let link = linksLinkOrBubble(linksGetOrCreate(db, a.id, b.id).ok);
      let fake = llmFake([]);
      let r = linkerRun(db, fake, link);
      expectFalse(test, r.ok, "failed");
      expectText(test, orNone(r.error), ":not_read");
      expectInt(test, requestCount(test, fake), 0);
      let reread = linksGet(db, link.id);
      if (reread != null) {
        expectText(test, reread.status, "failed");
        expectText(test, orNone(reread.error), ":not_read");
      }
    }

    test("one side without nodes is enough to fail") { test =>
      let f = linksFixture();
      let bare = makeWork(f.db, f.scope, "Bare", "# B\n\n${repeated("word ", 100)}");
      let link = linksLinkOrBubble(linksGetOrCreate(f.db, f.a.id, bare.id).ok);
      let r = linkerRun(f.db, llmFake([]), link);
      expectText(test, orNone(r.error), ":not_read");
    }

    test("an error longer than 255 characters is stored cut, not raised") { test =>
      let x = linkerFixture();
      let f = x.f;
      let fake = llmFakeScript([new LlmFakeResponse(400, repeated("e", 600))]);
      let r = linkerRun(f.db, fake, f.link);
      expectFalse(test, r.ok, "failed");
      expectTrue(test, sysGraphemeLength(orNone(r.error)) > 255, "the reason itself is long");
      let link = linksGet(f.db, f.link.id);
      expectTrue(test, link != null, "reloaded");
      if (link != null) {
        expectText(test, link.status, "failed");
        expectInt(test, sysGraphemeLength(orNone(link.error)), 255);
      }
    }

    test("a provider that is down is a failed link with the status in the error") { test =>
      let x = linkerFixture();
      let f = x.f;
      let r = linkerRun(f.db, llmFakeScript([new LlmFakeResponse(401, "bad key")]), f.link);
      expectFalse(test, r.ok, "failed");
      expectHas(test, orNone(r.error), "http: status 401");
    }

## Telling whoever is watching

    test("a successful run bumps the link's topic at each step the Elixir broadcast") { test =>
      let x = linkerFixture();
      let f = x.f;
      expectInt(test, versionOf(x), 0);
      linkerRun(f.db, llmFake([linkerReply("S.", [])]), f.link);
      expectInt(test, versionOf(x), 5);
    }

    test("a failed run bumps it for the start and for the failure") { test =>
      let x = linkerFixture();
      let f = x.f;
      linkerRun(f.db, llmFake([replyNothing()]), f.link);
      expectInt(test, versionOf(x), 4);
    }

    test("a run that never gets to ask bumps it twice: start, failed") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "writer@example.com");
      let a = makeWork(db, me, "Opinion", "# O\n\n${repeated("word ", 100)}");
      let b = makeWork(db, me, "Summary", "# S\n\n${repeated("word ", 100)}");
      let link = linksLinkOrBubble(linksGetOrCreate(db, a.id, b.id).ok);
      linkerRun(db, llmFake([]), link);
      expectInt(test, versionsOf(db, "link:${link.id.toString()}"), 2);
    }

    test("another link's topic is not touched") { test =>
      let x = linkerFixture();
      let f = x.f;
      linkerRun(f.db, llmFake([linkerReply("S.", [])]), f.link);
      expectInt(test, versionsOf(f.db, "link:${(f.link.id + 1).toString()}"), 0);
    }

## The wrapper a job runs

    test("run_pair loads the link by id and reads it") { test =>
      let x = linkerFixture();
      let f = x.f;
      let r = linkerRunPair(f.db, llmFake([linkerReply("S.", [edgeJson(f.aNode.id, f.bNode.id, "echoes", "Same move.")])]), f.link.id);
      expectTrue(test, r.ok, "ok");
      expectInt(test, r.kept, 1);
    }

    test("run_pair on a link that is not there fails without writing anything") { test =>
      let x = linkerFixture();
      let f = x.f;
      let r = linkerRunPair(f.db, llmFake([]), 999999);
      expectFalse(test, r.ok, "failed");
      expectText(test, orNone(r.error), ":no_link");
      expectTrue(test, r.link == null, "no link");
    }

    test("a link whose works are deleted goes with them") { test =>
      let x = linkerFixture();
      let f = x.f;
      f.db.exec("DELETE FROM works WHERE id = $1", [f.a.id.toString()]);
      expectTrue(test, linksGet(f.db, f.link.id) == null, "cascade");
    }
