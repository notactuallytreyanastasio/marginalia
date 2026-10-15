# Tests for the Read

Ported from `beat_density_test` and `prompts_test`, plus a whole read driven
by `llmFakeScript` with the three kinds of reply the model gives (a beats tool
call, a spine object, a weave object).

    let { Db, dbOpen } = import("db/src");
    let {
      Work, Section, GraphNode, GraphEdge, worksListSections, worksListEdges, worksNodes,
      worksGetById, worksListNodes, worksSetStatus, worksUpdateWork, workParams,
    } = import("works/src");
    let { LlmClient, llmFakeScript, LlmFakeResponse, llmRequests } = import("llm/src");
    let { versionsOf, versionsWorkTopic } = import("runs/src");
    let { sysJoin, sysStringReplace, sysUtf8Downcase, sysGraphemeLength } = import("sys/src");
    let { parseJson, JsonObject, JsonArray, JsonString } = import("std/json");

## Density

    test("the target scales with the section, with a floor and a cap") { test =>
      expectInt(test, analysisBeatTarget(100), 2);
      expectInt(test, analysisBeatTarget(1100), 5);
      expectInt(test, analysisBeatTarget(100000), 14);
    }

    test("the limit leaves room above the target without licensing a list") { test =>
      for (let words of [100, 574, 1309, 5000]) {
        let t = analysisBeatTarget(words);
        let c = analysisBeatCeiling(words);
        expectTrue(test, c > t, "the limit must leave room for a dense section");
        expectTrue(test, c < t * 2, "the limit must not license twice the target");
      }
      expectInt(test, analysisBeatCeiling(100), 3);
      expectInt(test, analysisBeatCeiling(1301), 7);
      expectInt(test, analysisBeatCeiling(100000), 21);
    }

    test("the ceiling of a four- and a five-beat target") { test =>
      expectInt(test, analysisBeatCeiling(880), 6);
      expectInt(test, analysisBeatCeiling(660), 4);
    }

    let beatNames(n: Int): List<String> {
      let out = new ListBuilder<String>();
      var i = 1;
      while (i <= n) {
        out.add("beat ${i.toString()}");
        i += 1;
      }
      out.toList()
    }

    test("thinning keeps the section covered end to end rather than truncating it") { test =>
      let ceiling = analysisBeatCeiling(1301);
      let kept = analysisThin(beatNames(ceiling * 3), ceiling, 1);
      expectInt(test, kept.length, ceiling);
      expectText(test, kept[0], "beat 1");
      expectText(test, kept[kept.length - 1], "beat ${(ceiling * 3).toString()}");
    }

    test("thinning picks evenly spaced beats") { test =>
      let kept = analysisThin(beatNames(10), 4, 1);
      expectText(test, sysJoin(kept, ","), "beat 1,beat 4,beat 7,beat 10");
    }

    test("a normal answer is left alone") { test =>
      let beats = beatNames(3);
      expectText(test, sysJoin(analysisThin(beats, 10, 1), ","), "beat 1,beat 2,beat 3");
    }

    test("the section pass is a tool call, so the shape is enforced not requested") { test =>
      let tool = analysisBeatsTool();
      expectText(test, tool.name, "record_beats");
      let tree = parseJson(tool.parametersJson);
      let beats = anField(anField(tree, "properties"), "beats");
      let required = anElements(anField(anField(beats, "items"), "required"));
      var names = new ListBuilder<String>();
      if (required != null) {
        for (let r of required) { names.add(anOrEmpty(anStr(r))); }
      }
      expectText(test, sysJoin(names.toList(), ","), "title,note,quote");
    }

## The prompts

    let gendered(text: String): Boolean {
      let lower = text.split(" ").map { (w: String): String => anTrim(w) };
      for (let w of lower) {
        let bare = sysStringReplace(sysStringReplace(sysStringReplace(w, ",", ""), ".", ""), ";", "");
        if (bare == "he" || bare == "him" || bare == "his" || bare == "she" || bare == "her" || bare == "hers") {
          return true;
        }
      }
      false
    }

    let ruleStated(text: String): Boolean {
      anContains(sysUtf8Downcase(text), "never assume anyone's gender")
    }

    test("a prompt may use a gendered pronoun only if it also says not to assume") { test =>
      let prompts = [
        analysisBeatsPrompt(), analysisSpinePrompt(), weavePrompt(),
        decisionGraphNarrativePrompt(), decisionGraphPrompt(),
      ];
      for (let p of prompts) {
        expectTrue(test, !gendered(p) || ruleStated(p), "a prompt models a pronoun without the rule");
      }
    }

    test("the beats pass states the rule outright") { test =>
      expectTrue(test, ruleStated(analysisBeatsPrompt()), "beats states the rule");
    }

    test("the beats prompt shows the writer as they, since the example is the format") { test =>
      expectHas(test, analysisBeatsPrompt(), "They set June 2020 as the baseline");
      expectLacks(test, analysisBeatsPrompt(), "He sets");
    }

    test("the rule covers characters as well as the writer") { test =>
      expectHas(test, sysUtf8Downcase(analysisBeatsPrompt()), "calls her she");
    }

    test("every pass lists a model, a cadence and a prompt") { test =>
      let passes = analysisPasses();
      expectInt(test, passes.length, 3);
      expectText(test, passes[0].id, "beats");
      expectText(test, passes[1].id, "spine");
      expectText(test, passes[2].id, "weave");
      expectText(test, passes[0].runs, "once per section, 3 at a time");
      expectText(test, passes[1].produces, "first impression, spine, threads, open questions");
      expectText(test, passes[0].name, "Pass 1 \u{2014} read each section");
      for (let p of passes) { expectTrue(test, p.prompt != "", "a prompt"); }
      expectInt(test, decisionGraphPasses().length, 2);
      expectText(test, decisionGraphPasses()[0].id, "narratives");
      expectText(test, decisionGraphPasses()[1].id, "decision_graph");
    }

    test("the prompts end in a newline and open as the Elixir did") { test =>
      expectTrue(test, analysisBeatsPrompt().split("\n").length > 30, "multi-line");
      expectText(test, analysisBeatsPrompt().split("\n")[0], "You are reading one section of a manuscript for a structural map. You are not editing it");
      expectText(test, analysisSpinePrompt().split("\n")[0], "You are given the beat-by-beat map of a whole manuscript, in order. You have not been given");
      expectText(test, weavePrompt().split("\n")[0], "You are given the complete map of a manuscript: every beat in document order, plus the");
      expectText(test, decisionGraphPrompt().split("\n")[0], "You are building a decision graph of a manuscript, using the tools provided. Work narrative by");
      let tail = analysisBeatsPrompt().split("\n"); expectText(test, tail[tail.length - 1], "");
    }

## The user messages

    test("the beats user message states the target and the hard limit") { test =>
      let fx = fxRead();
      let s = fx.sections[0];
      let user = analysisBeatsUser(fx.work, s);
      expectHas(test, user, "Manuscript: The Long Wait\n\nSection 1: The window\n");
      expectHas(test, user, " words. Aim for about 2 beats.\nHARD LIMIT: return at most 3. More than that is refused.\n\n---\nShe had been standing");
    }

    test("an intent adds its line, and a blank line follows") { test =>
      let fx = fxRead();
      let p = workParams("The Long Wait", readBody());
      p.intent = "Make them wait too";
      let r = worksUpdateWork(fx.db, fx.work, p);
      let w = r.ok;
      expectTrue(test, w != null, "updated");
      if (w != null) {
        expectHas(test, analysisBeatsUser(w, fx.sections[0]), "Manuscript: The Long Wait\nWhat it is meant to do to a reader: Make them wait too\n\nSection 1");
      }
    }

## A whole read

    test("a whole read stores beats, a spine, threads, questions and a weave") { test =>
      let fx = fxRead();
      expectInt(test, fx.sections.length, 3);
      let llm = fullScript();
      let r = analysisStart(fx.db, llm, fx.work);
      expectText(test, r.status, "read");
      expectTrue(test, r.detail == null, "whole, not degraded");
      expectInt(test, r.sectionsRead, 3);
      expectInt(test, r.sectionsFailed, 0);
      expectInt(test, r.beats, 6);
      expectInt(test, r.edges, 3);
      let w = reloaded(fx.db, fx.work);
      expectText(test, w.status, "read");
      expectTrue(test, w.statusDetail == null, "no detail");
      expectText(test, orNull(w.firstImpression), "A household waits for news it dreads.");
      expectInt(test, nodesOfType(fx.db, w, "beat").length, 6);
      expectInt(test, nodesOfType(fx.db, w, "spine").length, 3);
      expectInt(test, nodesOfType(fx.db, w, "thread").length, 3);
      expectInt(test, nodesOfType(fx.db, w, "question").length, 2);
      for (let s of sectionsOf(fx.db, w)) { expectText(test, s.status, "read"); }
    }

    let inDocumentOrder(beats: List<GraphNode>): List<GraphNode> {
      beats.sorted { (a: GraphNode, b: GraphNode): Int =>
        if (weaveSectionKey(a) != weaveSectionKey(b)) { weaveSectionKey(a) - weaveSectionKey(b) } else { a.ordinal - b.ordinal }
      }
    }

    test("beats are anchored to the section's own wording and chained with follows") { test =>
      let fx = fxRead();
      analysisStart(fx.db, fullScript(), fx.work);
      let beats = inDocumentOrder(nodesOfType(fx.db, fx.work, "beat"));
      expectText(test, beats[0].title, "They set the scene at the window");
      expectText(test, orNull(beats[0].quote), q1());
      expectText(test, orNull(beats[0].body), "Opens on stillness.");
      expectTrue(test, beats[0].sectionId == fx.sections[0].id, "in section one");
      expectTrue(test, beats[5].sectionId == fx.sections[2].id, "in section three");
      expectInt(test, beats[0].ordinal, 0);
      expectInt(test, beats[1].ordinal, 1);
      expectInt(test, beats[2].ordinal, 0);
      let follows = new ListBuilder<GraphEdge>();
      for (let e of worksListEdges(fx.db, fx.work.id)) {
        if (e.edgeType == "follows") { follows.add(e); }
      }
      expectInt(test, follows.length, 3);
      expectInt(test, follows[0].fromId, beats[0].id);
      expectInt(test, follows[0].toId, beats[1].id);
      expectInt(test, follows[0].ordinal, 0);
    }

    test("the spine is chained with leads_to, threads carry their status, questions are bare") { test =>
      let fx = fxRead();
      analysisStart(fx.db, fullScript(), fx.work);
      let spine = nodesOfType(fx.db, fx.work, "spine");
      let leads = new ListBuilder<GraphEdge>();
      for (let e of worksListEdges(fx.db, fx.work.id)) {
        if (e.edgeType == "leads_to") { leads.add(e); }
      }
      expectInt(test, leads.length, 2);
      expectInt(test, leads[0].fromId, spine[0].id);
      expectInt(test, leads[1].toId, spine[2].id);
      expectInt(test, leads[1].ordinal, 1);
      expectTrue(test, spine[0].sectionId == null, "work-level");
      expectText(test, orNull(spine[0].body), "Establishes the stillness.");
      let threads = nodesOfType(fx.db, fx.work, "thread");
      expectText(test, orNull(threads[0].body), "carried \u{2014} Cold in section one, filled in section three.");
      expectText(test, orNull(threads[1].body), "thin \u{2014} Appears in section two only.");
      expectText(test, orNull(threads[2].body), "carried \u{2014} Set early, answered at the end.");
      let questions = nodesOfType(fx.db, fx.work, "question");
      expectText(test, questions[1].title, "Why is her name never given?");
      expectTrue(test, questions[1].body == null, "no body");
      expectTrue(test, questions[1].quote == null, "no quote");
    }

    test("the weave stores its edges after 1000, with the reason shown to the writer") { test =>
      let fx = fxRead();
      analysisStart(fx.db, fullScript(), fx.work);
      let woven = new ListBuilder<GraphEdge>();
      for (let e of worksListEdges(fx.db, fx.work.id)) {
        if (e.ordinal >= 1000) { woven.add(e); }
      }
      expectInt(test, woven.length, 3);
      expectText(test, woven[0].edgeType, "pays_off");
      expectInt(test, woven[0].ordinal, 1000);
      expectInt(test, woven[2].ordinal, 1002);
      expectText(test, orNull(woven[1].rationale), "The thermostat is introduced, then explained.");
    }

    test("a read that completes bumps the work's version many times") { test =>
      let fx = fxRead();
      expectInt(test, bumps(fx.db, fx.work), 0);
      analysisStart(fx.db, fullScript(), fx.work);
      expectInt(test, bumps(fx.db, fx.work), 19);
    }

    test("the beats call is forced to record_beats with the fast model and no reasoning") { test =>
      let fx = fxRead();
      let llm = fullScript();
      analysisStart(fx.db, llm, fx.work);
      let sent = llmRequests(llm);
      expectInt(test, sent.length, 5);
      expectHas(test, sent[0], "\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"record_beats\"}}");
      expectHas(test, sent[0], "\"reasoning_effort\":\"none\"");
      expectHas(test, sent[0], "\"temperature\":0.3");
      expectHas(test, sent[0], "\"max_tokens\":28000");
      expectHas(test, sent[0], "\"model\":\"deepseek-flash\"");
      expectHas(test, sent[0], "HARD LIMIT: return at most 3.");
    }

    test("the spine and the weave ask for JSON at high effort") { test =>
      let fx = fxRead();
      let llm = fullScript();
      analysisStart(fx.db, llm, fx.work);
      let sent = llmRequests(llm);
      expectHas(test, sent[3], "\"response_format\":{\"type\":\"json_object\"}");
      expectHas(test, sent[3], "\"reasoning_effort\":\"high\"");
      expectHas(test, sent[3], "\"temperature\":0.5");
      expectHas(test, sent[3], "\"max_tokens\":30000");
      expectHas(test, sent[3], "3 sections, ");
      expectHas(test, sent[3], "## 1. The window (");
      expectHas(test, sent[3], "  - They set the scene at the window");
      expectHas(test, sent[4], "\"temperature\":0.4");
      expectHas(test, sent[4], "\"max_tokens\":32000");
      expectHas(test, sent[4], "## Section 1: The window\\n  [1] They set the scene at the window \u{2014} Opens on stillness.");
      expectHas(test, sent[4], "## Spine\\n  [7] The household waits at the window");
      expectHas(test, sent[4], "## Threads\\n");
      expectHas(test, sent[4], "## Open questions\\n");
    }

    test("a beat whose quote is not in the section is dropped, and the rest stand") { test =>
      let fx = fxRead();
      let first = beatsReply([
        new FxBeat("They set the scene at the window", "Opens on stillness.", q1()),
        new FxBeat("They invent a scream", "Not on the page.", "She screamed at the top of her lungs and ran."),
        new FxBeat("They let the kettle go cold", "A small domestic failure.", q2()),
      ]);
      let llm = llmFakeScript([
        ok(first), ok(sectionTwoReply()), ok(sectionThreeReply()), ok(spineReply()), ok(weaveReply()),
      ]);
      let r = analysisStart(fx.db, llm, fx.work);
      expectInt(test, r.beats, 6);
      let beats = inDocumentOrder(nodesOfType(fx.db, fx.work, "beat"));
      expectText(test, titlesOfNodes(beats), "They set the scene at the window | They let the kettle go cold | They introduce the father and his distrust of the thermostat | They say what the thermostat can and cannot know | They have the brother answer the telephone | They close on the kettle being filled");
    }

    test("a quote across the draft's hard wraps is stored as the section holds it (reflowed)") { test =>
      let body = "# One\n\nShe kept them in the\nfreezer, which she never\nexplained to anyone, and by then it hardly mattered.\n";
      let fx = fxWith("W", body);
      let reply = beatsReply([new FxBeat("They hide the food", "A small secret.", "She kept them in the freezer, which she never explained")]);
      let llm = llmFakeScript([ok(reply), ok(fakeContent("{}"))]);
      analysisStart(fx.db, llm, fx.work);
      let beats = nodesOfType(fx.db, fx.work, "beat");
      expectInt(test, beats.length, 1);
      expectText(test, orNull(beats[0].quote), "She kept them in the freezer, which she never explained");
    }

    test("more beats than the ceiling are thinned to it") { test =>
      let fx = fxRead();
      let many = new ListBuilder<FxBeat>();
      var i = 0;
      while (i < 8) {
        many.add(new FxBeat("beat ${i.toString()}", "n", q1()));
        i += 1;
      }
      let llm = llmFakeScript([ok(beatsReply(many.toList())), ok(sectionTwoReply()), ok(sectionThreeReply()), ok(spineReply()), ok(weaveReply())]);
      analysisStart(fx.db, llm, fx.work);
      let beats = inDocumentOrder(nodesOfType(fx.db, fx.work, "beat"));
      expectInt(test, beats.length, 3 + 2 + 2);
      expectText(test, beats[0].title, "beat 0");
      expectText(test, beats[1].title, "beat 4");
      expectText(test, beats[2].title, "beat 7");
    }

    test("an item without a title is dropped and a title is made one line") { test =>
      let fx = fxRead();
      let reply = beatsReply([
        new FxBeat("   ", "no title", q1()),
        new FxBeat("They   set\nthe scene", "n", q2()),
      ]);
      let llm = llmFakeScript([ok(reply), ok(sectionTwoReply()), ok(sectionThreeReply()), ok(spineReply()), ok(weaveReply())]);
      analysisStart(fx.db, llm, fx.work);
      let beats = nodesOfType(fx.db, fx.work, "beat");
      expectText(test, beats[0].title, "They set the scene");
    }

## Failures

    test("a section whose call fails is marked failed and the read goes on") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([
        new LlmFakeResponse(400, "{\"error\":\"nope\"}"),
        ok(sectionTwoReply()), ok(sectionThreeReply()), ok(spineReply()), ok(weaveReply()),
      ]);
      let r = analysisStart(fx.db, llm, fx.work);
      expectInt(test, r.sectionsFailed, 1);
      expectInt(test, r.sectionsRead, 2);
      expectText(test, r.status, "read");
      let sections = sectionsOf(fx.db, fx.work);
      expectText(test, sections[0].status, "failed");
      expectText(test, sections[1].status, "read");
      expectInt(test, nodesOfType(fx.db, fx.work, "beat").length, 4);
    }

    test("a reply with no tool call fails the section") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([
        ok(fakeContent("Here are some beats in prose.")),
        ok(sectionTwoReply()), ok(sectionThreeReply()), ok(spineReply()), ok(weaveReply()),
      ]);
      let one = analysisReadSection(fx.db, llm, fx.work, fx.sections[0]);
      expectText(test, one.status, "failed");
      expectText(test, orNull(one.detail), ":no_tool_call");
    }

    test("a tool call without a beats list fails the section with a reason") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(fakeCalls([new FakeCall("record_beats", "{\"other\":1}")]))]);
      let one = analysisReadSection(fx.db, llm, fx.work, fx.sections[0]);
      expectText(test, one.status, "failed");
      expectText(test, orNull(one.detail), "no beats returned");
    }

    test("tool arguments that are not an object fail the section") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(fakeCalls([new FakeCall("record_beats", "[1,2")]))]);
      let one = analysisReadSection(fx.db, llm, fx.work, fx.sections[0]);
      expectText(test, one.status, "failed");
      expectText(test, orNull(one.detail), ":invalid_json");
    }

    test("a truncated beats reply fails the section and is not asked again") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(fakeLength())]);
      let one = analysisReadSection(fx.db, llm, fx.work, fx.sections[0]);
      expectText(test, one.status, "failed");
      expectText(test, orNull(one.detail), ":truncated");
      expectInt(test, llmRequests(llm).length, 1);
    }

    test("every section failing leaves a read with spine unavailable: :no_beats") { test =>
      let fx = fxRead();
      let bad = new LlmFakeResponse(400, "{}");
      let llm = llmFakeScript([bad, bad, bad]);
      let r = analysisStart(fx.db, llm, fx.work);
      expectText(test, r.status, "read");
      expectText(test, orNull(r.detail), "spine unavailable: :no_beats");
      expectText(test, orNull(reloaded(fx.db, fx.work).statusDetail), "spine unavailable: :no_beats");
      expectInt(test, r.sectionsFailed, 3);
      expectInt(test, llmRequests(llm).length, 3);
    }

    test("a truncated spine degrades the read and skips the weave") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(sectionOneReply()), ok(sectionTwoReply()), ok(sectionThreeReply()), ok(fakeLength())]);
      let r = analysisStart(fx.db, llm, fx.work);
      expectText(test, r.status, "read");
      expectText(test, orNull(r.detail), "spine unavailable: :truncated");
      expectInt(test, llmRequests(llm).length, 4);
      expectInt(test, nodesOfType(fx.db, fx.work, "beat").length, 6);
      expectInt(test, nodesOfType(fx.db, fx.work, "spine").length, 0);
    }

    test("a spine reply that is not JSON degrades the read with :invalid_json") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(sectionOneReply()), ok(sectionTwoReply()), ok(sectionThreeReply()), ok(fakeContent("not json"))]);
      let r = analysisStart(fx.db, llm, fx.work);
      expectText(test, orNull(r.detail), "spine unavailable: :invalid_json");
    }

    test("a spine reply with keys missing still counts as success") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(sectionOneReply()), ok(sectionTwoReply()), ok(sectionThreeReply()), ok(fakeContent("{}")), ok(weaveReply())]);
      let r = analysisStart(fx.db, llm, fx.work);
      expectTrue(test, r.detail == null, "whole");
      expectInt(test, nodesOfType(fx.db, fx.work, "spine").length, 0);
      expectTrue(test, reloaded(fx.db, fx.work).firstImpression == null, "no impression");
    }

    test("a failed weave does not void the read") { test =>
      let fx = fxRead();
      let llm = llmFakeScript([ok(sectionOneReply()), ok(sectionTwoReply()), ok(sectionThreeReply()), ok(spineReply()), new LlmFakeResponse(400, "{}")]);
      let r = analysisStart(fx.db, llm, fx.work);
      expectText(test, r.status, "read");
      expectTrue(test, r.detail == null, "whole");
      expectInt(test, r.edges, 0);
    }

    test("a long reason is cut to 255 characters in the detail") { test =>
      let fx = fxRead();
      let work = reloaded(fx.db, fx.work);
      let long = repeated("x", 400);
      let w = worksSetStatus(fx.db, work, "read", long);
      expectInt(test, sysGraphemeLength(orNull(w.statusDetail)), 255);
    }

    test("a database error ends the read failed, with the error as the detail") { test =>
      let fx = fxRead();
      fx.db.exec("DROP TABLE edges", []);
      let r = analysisStart(fx.db, fullScript(), fx.work);
      expectText(test, r.status, "failed");
      expectText(test, reloaded(fx.db, fx.work).status, "failed");
      expectHas(test, orNull(reloaded(fx.db, fx.work).statusDetail), "the read stopped");
    }

## Re-reading

    test("a work that was read is reset before it is read again") { test =>
      let fx = fxRead();
      analysisStart(fx.db, fullScript(), fx.work);
      let again = reloaded(fx.db, fx.work);
      expectText(test, again.status, "read");
      let r = analysisStart(fx.db, fullScript(), again);
      expectText(test, r.status, "read");
      expectInt(test, nodesOfType(fx.db, fx.work, "beat").length, 6);
      expectInt(test, nodesOfType(fx.db, fx.work, "spine").length, 3);
    }

    test("a work left failed is not reset, so a retry stacks a second set") { test =>
      let fx = fxRead();
      analysisStart(fx.db, fullScript(), fx.work);
      let w = worksSetStatus(fx.db, reloaded(fx.db, fx.work), "failed", "boom");
      analysisStart(fx.db, fullScript(), w);
      expectInt(test, nodesOfType(fx.db, fx.work, "beat").length, 12);
    }

    test("progress is reported to a run key that is running") { test =>
      let fx = fxRead();
      fx.db.exec("INSERT INTO runs (key, status) VALUES ('read:1', 'running')", []);
      analysisStartTracked(fx.db, fullScript(), fx.work, "read:1");
      let row = fx.db.one("SELECT progress, detail FROM runs WHERE key = 'read:1'", []);
      expectTrue(test, row != null, "row");
      if (row != null) {
        expectText(test, orNull(row.strOrNull("progress")), "3/3");
        expectText(test, orNull(row.strOrNull("detail")), "the weave");
      }
    }
