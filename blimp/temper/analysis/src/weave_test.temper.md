# Tests for the weave

The rules the notes state for `Weave.run`: what is shown, which edges are
kept, which are flipped, how many, and how it fails.

    let { Db } = import("db/src");
    let {
      Work, Section, GraphNode, GraphEdge, NodeParams, worksInsertNodes, worksListEdges, worksUpdateWork, worksNodes,
      workParams,
    } = import("works/src");
    let { LlmClient, llmFakeScript, LlmFakeResponse, llmRequests } = import("llm/src");
    let { sysJoin } = import("sys/src");
    let { JsonInt32, JsonString, JsonSyntaxTree, parseJson } = import("std/json");

A work with six beats (ids 1 to 6, two per section), two spine nodes (7, 8),
one thread (9) and one question (10).

    let weaveBeat(work: Work, section: Section, title: String, body: String?): NodeParams {
      let p = new NodeParams(work.id, "beat", title);
      p.sectionId = section.id;
      p.body = body;
      p
    }

    let weaveFixture(): AnFx throws Bubble {
      let fx = fxRead();
      let s = fx.sections;
      worksInsertNodes(fx.db, fx.work.id, s[0].id, [
        weaveBeat(fx.work, s[0], "b1", "n1"), weaveBeat(fx.work, s[0], "b2", null),
      ]);
      worksInsertNodes(fx.db, fx.work.id, s[1].id, [
        weaveBeat(fx.work, s[1], "b3", "n3"), weaveBeat(fx.work, s[1], "b4", ""),
      ]);
      worksInsertNodes(fx.db, fx.work.id, s[2].id, [
        weaveBeat(fx.work, s[2], "b5", null), weaveBeat(fx.work, s[2], "b6", "n6"),
      ]);
      let spine1 = new NodeParams(fx.work.id, "spine", "trunk one");
      spine1.body = "the first trunk";
      worksInsertNodes(fx.db, fx.work.id, null, [spine1, new NodeParams(fx.work.id, "spine", "trunk two")]);
      let thread = new NodeParams(fx.work.id, "thread", "a thread");
      thread.body = "carried \u{2014} runs through";
      worksInsertNodes(fx.db, fx.work.id, null, [thread]);
      worksInsertNodes(fx.db, fx.work.id, null, [new NodeParams(fx.work.id, "question", "why?")]);
      fx
    }

    let weaveRaw(edgesJson: String): LlmClient throws Bubble {
      llmFakeScript([ok(fakeContent("{\"edges\":${edgesJson}}"))])
    }

    let storedEdges(fx: AnFx): List<GraphEdge> throws Bubble {
      let out = new ListBuilder<GraphEdge>();
      for (let e of worksListEdges(fx.db, fx.work.id)) {
        if (e.ordinal >= 1000) { out.add(e); }
      }
      out.toList()
    }

    let edgeText(e: GraphEdge): String {
      "${e.fromId.toString()}-${e.edgeType}->${e.toId.toString()}"
    }

    let edgesText(es: List<GraphEdge>): String {
      sysJoin(es.map { (e: GraphEdge): String => edgeText(e) }, " ")
    }

    test("a work with fewer than two beats is not woven and the model is not asked") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([]);
      let r = weaveRun(fx.db, llm, fx.work);
      expectTrue(test, r.ok, "ok");
      expectInt(test, r.edges, 0);
      expectInt(test, llmRequests(llm).length, 0);
    }

    test("the inventory lists beats with ids and notes, then spine, threads and questions") { test =>
      let fx = weaveFixture();
      let want = "Manuscript: The Long Wait\n\n## Section 1: The window\n  [1] b1 \u{2014} n1\n  [2] b2\n\n## Section 2: The thermostat\n  [3] b3 \u{2014} n3\n  [4] b4\n\n## Section 3: The telephone\n  [5] b5\n  [6] b6 \u{2014} n6\n\n## Spine\n  [7] trunk one \u{2014} the first trunk\n  [8] trunk two\n\n## Threads\n  [9] a thread \u{2014} carried \u{2014} runs through\n\n## Open questions\n  [10] why?\n";
      let nodes = worksNodes(fx.db, fx.work.id);
      expectText(test, weaveInventory(fx.work, fx.sections, nodes), want);
    }

    test("an intent changes the label of the first line") { test =>
      let fx = weaveFixture();
      let p = workParams("The Long Wait", readBody());
      p.intent = "Make them wait";
      let w = worksUpdateWork(fx.db, fx.work, p).ok;
      expectTrue(test, w != null, "updated");
      if (w != null) {
        let text = weaveInventory(w, fx.sections, worksNodes(fx.db, fx.work.id));
        expectHas(test, text, "Manuscript: The Long Wait\nIntended effect on a reader: Make them wait\n\n## Section 1");
      }
    }

    test("a note is the first 160 graphemes of the body") { test =>
      let fx = fxRead();
      let p = new NodeParams(fx.work.id, "beat", "long");
      p.sectionId = fx.sections[0].id;
      p.body = repeated("x", 200);
      let nodes = worksInsertNodes(fx.db, fx.work.id, fx.sections[0].id, [p]);
      let text = weaveInventory(fx.work, fx.sections, nodes);
      expectHas(test, text, "  [1] long ${anDash()} ${repeated("x", 160)}\n");
      expectLacks(test, text, repeated("x", 161));
    }

    test("edges are normalised, flipped forward in time, de-duplicated and stored after 1000") { test =>
      let fx = weaveFixture();
      let edges = "[{\"from\":4,\"to\":2,\"type\":\"develops\",\"why\":\"  a\\n b  \"},{\"from\":\"[3]\",\"to\":5,\"type\":\"pays_off\",\"why\":\"later\"},{\"from\":7,\"to\":2,\"type\":\"realises\"},{\"from\":10,\"to\":6,\"type\":\"asks_about\",\"why\":\"q\"},{\"from\":6,\"to\":1,\"type\":\"tension\",\"why\":\"pull\"},{\"from\":2,\"to\":2,\"type\":\"develops\"},{\"from\":99,\"to\":2,\"type\":\"develops\"},{\"from\":1,\"to\":2,\"type\":\"echoes\"},{\"from\":2,\"to\":4,\"type\":\"develops\",\"why\":\"again\"},{\"from\":7,\"to\":3,\"type\":\"develops\"},\"junk\",{\"from\":1.5,\"to\":2,\"type\":\"develops\"}]";
      let r = weaveRun(fx.db, weaveRaw(edges), fx.work);
      expectTrue(test, r.ok, "ok");
      expectInt(test, r.edges, 6);
      let stored = storedEdges(fx);
      expectText(test, edgesText(stored), "2-develops->4 3-pays_off->5 7-realises->2 10-asks_about->6 1-tension->6 7-develops->3");
      expectInt(test, stored[0].ordinal, 1000);
      expectInt(test, stored[5].ordinal, 1005);
      expectText(test, orNull(stored[0].rationale), "a b");
      expectText(test, orNull(stored[1].rationale), "later");
      expectTrue(test, stored[2].rationale == null, "no why");
    }

    test("a why is cut to 400 graphemes") { test =>
      let fx = weaveFixture();
      let edges = "[{\"from\":1,\"to\":3,\"type\":\"develops\",\"why\":\"${repeated("w", 500)}\"}]";
      weaveRun(fx.db, weaveRaw(edges), fx.work);
      expectText(test, orNull(storedEdges(fx)[0].rationale), repeated("w", 400));
    }

    let weaveGrid(): String {
      let parts = new ListBuilder<String>();
      let kinds = ["realises", "asks_about", "requires"];
      var k = 0;
      while (k < kinds.length) {
        var i = 1;
        while (i <= 10) {
          var j = 1;
          while (j <= 10) {
            if (i != j) { parts.add("{\"from\":${i.toString()},\"to\":${j.toString()},\"type\":\"${kinds[k]}\"}"); }
            j += 1;
          }
          i += 1;
        }
        k += 1;
      }
      "[${sysJoin(parts.toList(), ",")}]"
    }

    test("at most 160 edges are kept") { test =>
      let fx = weaveFixture();
      let r = weaveRun(fx.db, weaveRaw(weaveGrid()), fx.work);
      expectInt(test, r.edges, 160);
      expectInt(test, storedEdges(fx).length, 160);
      expectInt(test, storedEdges(fx)[159].ordinal, 1159);
    }

    test("a reply without an edge list is :no_edges") { test =>
      let fx = weaveFixture();
      let r = weaveRun(fx.db, llmFakeScript([ok(fakeContent("{\"edges\":\"none\"}"))]), fx.work);
      expectFalse(test, r.ok, "not ok");
      expectText(test, orNull(r.error), ":no_edges");
      let r2 = weaveRun(fx.db, llmFakeScript([ok(fakeContent("{}"))]), fx.work);
      expectText(test, orNull(r2.error), ":no_edges");
    }

    test("a failing call is returned as its reason") { test =>
      let fx = weaveFixture();
      let r = weaveRun(fx.db, llmFakeScript([ok(fakeLength())]), fx.work);
      expectFalse(test, r.ok, "not ok");
      expectText(test, orNull(r.error), ":truncated");
      let r2 = weaveRun(fx.db, llmFakeScript([ok(fakeContent("nope"))]), fx.work);
      expectText(test, orNull(r2.error), ":invalid_json");
    }

    test("the weave asks for JSON at high effort with the weave prompt") { test =>
      let fx = weaveFixture();
      let llm = weaveRaw("[]");
      weaveRun(fx.db, llm, fx.work);
      let sent = llmRequests(llm)[0];
      expectHas(test, sent, "\"response_format\":{\"type\":\"json_object\"}");
      expectHas(test, sent, "\"reasoning_effort\":\"high\"");
      expectHas(test, sent, "\"max_tokens\":32000");
      expectHas(test, sent, "\"temperature\":0.4");
      expectHas(test, sent, "Your job is the part the earlier passes could not do: say what leads to what.");
    }

    test("as_id takes integers and strings with brackets, and nothing else") { test =>
      expectInt(test, orMinus(weaveAsId(parseJson("5"))), 5);
      expectInt(test, orMinus(weaveAsId(parseJson("\"[3]\""))), 3);
      expectInt(test, orMinus(weaveAsId(parseJson("\"[[4]x\""))), 4);
      expectInt(test, orMinus(weaveAsId(parseJson("\"12abc\""))), 12);
      expectInt(test, orMinus(weaveAsId(parseJson("\"-2\""))), -2);
      expectInt(test, orMinus(weaveAsId(parseJson("\"x\""))), -1);
      expectInt(test, orMinus(weaveAsId(parseJson("\" 5\""))), -1);
      expectInt(test, orMinus(weaveAsId(parseJson("3.5"))), -1);
      expectInt(test, orMinus(weaveAsId(parseJson("null"))), -1);
      expectInt(test, orMinus(weaveAsId(null)), -1);
    }

    let orMinus(n: Int?): Int { if (n != null) { n } else { -1 } }

    test("the weave edge types are the six of the vocabulary") { test =>
      expectText(test, sysJoin(weaveTypes(), ","), "develops,pays_off,requires,tension,realises,asks_about");
      expectText(test, weavePass().id, "weave");
      expectText(test, weavePass().name, "Pass 3 \u{2014} what leads to what");
    }
