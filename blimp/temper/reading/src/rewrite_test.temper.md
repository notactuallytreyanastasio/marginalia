# Tests for rewrite

Ported from `test/marginalia/rewrite_test.exs` (30 tests) and
`test/marginalia/apply_rewrite_test.exs`: the one place in the product that
writes prose for the manuscript. The constraints on it are what stop that
swallowing the rest.

The Elixir file never reached a model. These do not either, except in the
tests at the end, which hand the client canned answers shaped as the provider
shapes them.

    let { Db, dbOpen } = import("db/src");
    let { Scope } = import("accounts/src");
    let {
      Work, Section, worksListSections, worksRevisions, worksReplay, worksRevisionCount,
    } = import("works/src");
    let { diff, Part } = import("core/src");
    let { LlmClient, LlmTool, llmFake, llmProvider, llmLastRequest } = import("llm/src");
    let { JsonObject, JsonArray, JsonString, JsonSyntaxTree, parseJson } = import("std/json");
    let { sysJoin } = import("sys/src");

    class RewriteFx(public db: Db, public me: Scope, public work: Work, public section: Section) {}

    let rewriteFixture(): RewriteFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = rdUser(db, "a@example.com");
      let body = "# A draft\n\nThe kettle went cold on the counter, and nobody moved to fill it again.\n\n${rdRepeat("word ", 300)}";
      let work = rdWork(db, me, "W", body);
      new RewriteFx(db, me, work, rdFirst(db, work))
    }

    let noModel(): LlmClient { llmFake([]) }

## The span has to be real

    test("rewrite: a selection that is not in the draft gets nothing") { test =>
      let fx = rewriteFixture();
      let r = rewritePropose(fx.db, noModel(), fx.work, "a sentence nobody wrote", null);
      rdText(test, rdOr(r.error, "ok"), "not_in_draft");
    }

    test("rewrite: a redraft is refused, and says how long it was") { test =>
      let fx = rewriteFixture();
      let r = rewritePropose(fx.db, noModel(), fx.work, rdRepeat("word ", 3000), null);
      rdText(test, rdOr(r.error, "ok"), "span_too_long");
      rdTrue(test, r.words > r.maxWords, "words exceed the limit");
      rdInt(test, r.maxWords, 2500);
    }

400 words used to be refused outright. At a median paragraph of 248 words that
is barely a paragraph and a half. This must get past the length check and go
looking for the span.

    test("rewrite: a long passage is not a redraft any more") { test =>
      let fx = rewriteFixture();
      let r = rewritePropose(fx.db, noModel(), fx.work, rdRepeat("a sentence that is not in this draft. ", 60), null);
      rdText(test, rdOr(r.error, "ok"), "not_in_draft");
    }

deepseek-flash was probed at 27,000, 41,500 and 65,536: all 200. The client adds
reasoning headroom on top of the answer budget, so this is what actually goes
out for the biggest span the check allows.

    test("rewrite: the largest request stays inside what the provider accepts") { test =>
      let biggest = rdRepeat("word ", 2500);
      let total = rewriteAnswerBudget(biggest) + llmProvider("deepseek").headroom;
      rdTrue(test, total <= 65536, "a span at the ceiling must not ask the provider for more than it takes");
      rdInt(test, total, 41500);
    }

    test("rewrite: the answer budget grows with the span, or the reply comes back truncated") { test =>
      rdInt(test, rewriteAnswerBudget(rdRepeat("word ", 40)), 3000);
      // three candidates at about 1.4 tokens a word, and the two labels each
      rdTrue(test, rewriteAnswerBudget(rdRepeat("word ", 2500)) >= 10500, "room for three");
      rdInt(test, rewriteAnswerBudget(rdRepeat("word ", 2500)), 17500);
    }

    test("rewrite: several paragraphs get past the length check") { test =>
      let fx = rewriteFixture();
      let r = rewritePropose(fx.db, noModel(), fx.work, rdRepeat("a sentence that is not in this draft. ", 10), null);
      rdText(test, rdOr(r.error, "ok"), "not_in_draft");
    }

## The tool

    test("rewrite: the tool asks for the move and the cost, not just the words") { test =>
      let tool = rewriteTool();
      rdText(test, tool.name, "propose_rewrites");
      let params = parseJson(tool.parametersJson);
      let props = readingProp(params, "properties");
      let item = readingProp(readingProp(props, "rewrites"), "items");
      let required = readingElements(item, "required").map { (e: JsonSyntaxTree): String => readingInspect(e) };
      rdText(test, sysJoin(required, ","), "\"text\",\"move\",\"cost\"");
      // the writer should see what it thought it was changing
      rdTrue(test, readingProp(props, "reading") != null, "a reading");
    }

    test("rewrite: the pass lists its prompt and what it produces") { test =>
      let passes = rewritePasses();
      rdInt(test, passes.length, 1);
      rdText(test, passes[0].id, "rewrite");
      rdText(test, passes[0].prompt, rewritePrompt());
      rdHas(test, passes[0].produces, "three labelled candidates");
    }

## The word diff

    let joinKinds(parts: List<Part>, skip: String): String {
      let out = new ListBuilder<String>();
      var i = 0;
      while (i < parts.length) {
        if (parts[i].kind != skip) { out.add(parts[i].text); }
        i += 1;
      }
      sysJoin(out.toList(), "")
    }

    let hasPart(parts: List<Part>, kind: String, within: String): Boolean {
      var i = 0;
      while (i < parts.length) {
        if (parts[i].kind == kind && readingContains(parts[i].text, within)) { return true; }
        i += 1;
      }
      false
    }

    test("rewrite: both sides reconstruct exactly") { test =>
      let a = "The kettle went cold on the counter, and nobody moved to fill it again.";
      let b = "The kettle went cold, and nobody moved.";
      let d = rewriteDiff(a, b);
      rdText(test, joinKinds(d, "ins"), a);
      rdText(test, joinKinds(d, "del"), b);
    }

    test("rewrite: identical spans are all one piece") { test =>
      let d = rewriteDiff("a b c", "a b c");
      rdInt(test, d.length, 1);
      rdText(test, d[0].kind, "same");
      rdText(test, d[0].text, "a b c");
    }

    test("rewrite: it finds the shared middle rather than replacing everything") { test =>
      let d = rewriteDiff("the cat sat on the mat", "the dog sat on the mat");
      rdTrue(test, hasPart(d, "same", "sat on the mat"), "the shared stretch");
      rdTrue(test, hasPart(d, "del", "cat"), "cat went");
      rdTrue(test, hasPart(d, "ins", "dog"), "dog arrived");
    }

    test("rewrite: an empty original is all insertion") { test =>
      let d = rewriteDiff("", "new text");
      rdInt(test, d.length, 1);
      rdText(test, d[0].kind, "ins");
      rdText(test, d[0].text, "new text");
    }

## The writer's optional steer

    test("rewrite: no steer adds nothing to the prompt") { test =>
      rdText(test, rewriteSteerBlock(null), "");
      rdText(test, rewriteSteerBlock(""), "");
      // whitespace is not an instruction
      rdText(test, rewriteSteerBlock("   "), "");
    }

    test("rewrite: what they typed goes in, in their words") { test =>
      let block = rewriteSteerBlock("lead with the finding, drop the hedging");
      rdHas(test, block, "lead with the finding, drop the hedging");
      rdHas(test, block, "WHAT THE WRITER ASKED FOR");
    }

    test("rewrite: every candidate must obey it, but they still have to differ") { test =>
      let block = rewriteSteerBlock("make it shorter");
      rdHas(test, block, "Every candidate must do this");
      rdHas(test, block, "differ");
    }

    test("rewrite: a brief is cut to a note") { test =>
      let block = rewriteSteerBlock(rdRepeat("please do the thing. ", 200));
      rdTrue(test, readingLength(block) < rewriteMaxSteerChars() + 300, "bounded");
      rdInt(test, rewriteMaxSteerChars(), 400);
    }

    test("rewrite: the steer block is the template, byte for byte") { test =>
      rdText(
        test, rewriteSteerBlock("  make it shorter  "),
        "\nWHAT THE WRITER ASKED FOR, in their words:\nmake it shorter\n\nEvery candidate must do this. They still differ from each other, but now\nin HOW they do it, not in whether they do it.\n",
      );
    }

## What the panel says it is replacing

    test("rewrite: a short selection is still one line") { test =>
      rdText(test, rewriteSpanLabel("a handful of words here"), "Rewrites of one line");
    }

    test("rewrite: four paragraphs are not one line") { test =>
      rdText(test, rewriteSpanLabel(rdRepeat("word ", 1050)), "Rewrites of 1050 words");
    }

    test("rewrite: nothing selected claims nothing") { test =>
      rdText(test, rewriteSpanLabel(null), "Rewrites");
      rdText(test, rewriteSpanLabel(""), "Rewrites");
    }

    test("rewrite: a short span needs no extent line, it is all on screen") { test =>
      rdTrue(test, rewriteSpanExtent("a short selection") == null, "short");
      rdTrue(test, rewriteSpanExtent(null) == null, "nothing");
    }

    test("rewrite: a long span shows its head and its tail, because the rest runs off below") { test =>
      let span = "The beginning of the selection. ${rdRepeat("middle ", 200)}the very end.";
      let extent = rdOr(rewriteSpanExtent(span), "");
      rdHas(test, extent, "The beginning of the selection");
      rdHas(test, extent, "the very end.");
      rdHas(test, extent, "…");
      // it is a label, not the span itself
      rdTrue(test, readingLength(extent) < 200, "short");
    }

    test("rewrite: newlines in a multi-paragraph selection are flattened") { test =>
      let extent = rdOr(rewriteSpanExtent("First para.\n\n${rdRepeat("word ", 60)}\n\nLast para."), "");
      rdLacks(test, extent, "\n");
      rdHas(test, extent, "First para.");
    }

    test("rewrite: the extent is 64 characters, a spaced ellipsis, then 48") { test =>
      let span = "${rdRepeat("a", 100)}${rdRepeat("b", 100)}";
      let extent = rdOr(rewriteSpanExtent(span), "");
      rdText(test, extent, "${rdRepeat("a", 64)} … ${rdRepeat("b", 48)}");
    }

## Putting a candidate back

    test("rewrite: it replaces the span inside the paragraph that holds it") { test =>
      let out = rewritePlace("First sentence. The span to replace. Last sentence.", "The span to replace.", "A better span.");
      rdText(test, rdOr(out, "<not here>"), "First sentence. A better span. Last sentence.");
    }

    test("rewrite: only the first occurrence, so a repeated phrase is not rewritten everywhere") { test =>
      rdText(test, rdOr(rewritePlace("same. same. same.", "same.", "CHANGED."), "<not here>"), "CHANGED. same. same.");
    }

    test("rewrite: a paragraph that does not hold the span is refused, not overwritten") { test =>
      let out = rewritePlace("BRAVO the second paragraph, which has nothing to do with it.", "ALPHA the first paragraph.", "A rewrite of alpha.");
      rdTrue(test, out == null, "not here");
    }

The old behaviour returned the candidate here, so one click destroyed a paragraph
the writer had not selected.

    test("rewrite: the refusal is the whole point: it used to replace the paragraph") { test =>
      let out = rewritePlace("A paragraph worth keeping.", "not in here", "Some rewrite of other text.");
      rdTrue(test, out == null, "refused");
    }

    test("rewrite: with no block or no original there is nothing to refuse, the seed stands") { test =>
      rdText(test, rdOr(rewritePlace(null, "x", "seed"), "<not here>"), "seed");
      rdText(test, rdOr(rewritePlace("block", null, "seed"), "<not here>"), "seed");
    }

## Which paragraphs a span covers

    test("rewrite: a span inside one paragraph covers only it") { test =>
      let fx = rewriteFixture();
      let para = readingSplit(fx.section.body)[1];
      let refs = rewriteCoveredRefs(fx.section, readingSliceCp(para, 10, 40));
      rdInt(test, refs.length, 1);
      rdText(test, refs[0], "s${fx.section.ordinal.toString()}p1");
    }

    test("rewrite: a span across three paragraphs covers all three") { test =>
      let fx = rewriteFixture();
      let ps = readingSplit(fx.section.body);
      let refs = rewriteCoveredRefs(fx.section, "${ps[0]}\n\n${ps[1]}\n\n${ps[2]}");
      let o = fx.section.ordinal.toString();
      rdInt(test, refs.length, 3);
      rdText(test, rdJoin(refs), "s${o}p0|s${o}p1|s${o}p2");
    }

The paragraph does not contain the span, but the span covers it.

    test("rewrite: a span starting mid-paragraph still covers that paragraph") { test =>
      let fx = rewriteFixture();
      let ps = readingSplit(fx.section.body);
      let tail = readingSliceCp(ps[0], readingLength(ps[0]) - 5, 5);
      let refs = rewriteCoveredRefs(fx.section, "${tail}\n\n${ps[1]}");
      let o = fx.section.ordinal.toString();
      rdText(test, rdJoin(refs), "s${o}p0|s${o}p1");
    }

    test("rewrite: a span that is not in the section covers nothing") { test =>
      let fx = rewriteFixture();
      rdInt(test, rewriteCoveredRefs(fx.section, "a sentence nobody wrote").length, 0);
    }

A ref the page never renders dims nothing.

    test("rewrite: the refs are the ones the page builds") { test =>
      let fx = rewriteFixture();
      let ps = readingSplit(fx.section.body);
      let page = readingEntries(fx.db, fx.work);
      let refs = rewriteCoveredRefs(fx.section, "${ps[0]}\n\n${ps[1]}");
      rdInt(test, refs.length, 2);
      for (let ref of refs) {
        var found = false;
        for (let b of page) {
          if (b.ref == ref) { found = true; }
        }
        rdTrue(test, found, "${ref} is a ref the page renders");
      }
    }

    test("rewrite: touching at a boundary is not overlapping") { test =>
      let fx = rewriteFixture();
      let ps = readingSplit(fx.section.body);
      // the second paragraph alone: it ends where the blank line begins
      let refs = rewriteCoveredRefs(fx.section, ps[1]);
      rdText(test, rdJoin(refs), "s${fx.section.ordinal.toString()}p1");
    }

## Cleaning the candidates

    let rawList(json: String): List<JsonSyntaxTree> throws Bubble {
      let t = parseJson(json);
      if (t is JsonArray) { t.elements } else { [] }
    }

    let candidateTexts(cs: List<RewriteCandidate>): String {
      rdJoin(cs.map { (c: RewriteCandidate): String => c.text })
    }

    test("rewrite: clean strips a label, wrapping quotes and the original itself") { test =>
      let raw = rawList("[{\"text\":\"Option 2: \\\"Nobody moved.\\\"\",\"move\":\"Cuts it.\",\"cost\":\"Loses the kettle.\"},{\"text\":\"“A curly one.”\",\"move\":\"m\",\"cost\":\"c\"},{\"text\":\"The kettle went cold!\"},{\"text\":\"\"},{\"move\":\"no text\"},\"not a map\"]");
      let cs = rewriteClean(raw, "the kettle went COLD");
      rdText(test, candidateTexts(cs), "Nobody moved.|A curly one.");
      rdText(test, rdOr(cs[0].move, "?"), "Cuts it.");
      rdText(test, rdOr(cs[0].cost, "?"), "Loses the kettle.");
    }

    test("rewrite: clean drops repeats of the same words and keeps four") { test =>
      let raw = rawList("[{\"text\":\"One two.\"},{\"text\":\"one, TWO\"},{\"text\":\"Three.\"},{\"text\":\"Four.\"},{\"text\":\"Five.\"},{\"text\":\"Six.\"}]");
      let cs = rewriteClean(raw, "original");
      rdText(test, candidateTexts(cs), "One two.|Three.|Four.|Five.");
    }

    test("rewrite: clean puts the move and cost on one line, cut to 160") { test =>
      let long = rdRepeat("x", 200);
      let raw = rawList("[{\"text\":\"T\",\"move\":\"a\\n  b\\tc\",\"cost\":\"${long}\"}]");
      let cs = rewriteClean(raw, "original");
      rdText(test, rdOr(cs[0].move, "?"), "a b c");
      rdInt(test, readingLength(rdOr(cs[0].cost, "")), 160);
    }

    test("rewrite: a label that is not a label is left alone") { test =>
      let raw = rawList("[{\"text\":\"Optional: keep this\"},{\"text\":\"version - a name\"},{\"text\":\"Candidate 3. the third\"}]");
      let cs = rewriteClean(raw, "original");
      rdText(test, candidateTexts(cs), "Optional: keep this|a name|the third");
    }

## Asking, with the model's answer canned

    let proposeReply(): String throws Bubble {
      rdToolReply("propose_rewrites", "{\"reading\":\"It states the scene flatly.\",\"rewrites\":[{\"text\":\"The kettle went cold; nobody refilled it.\",\"move\":\"Cuts the gloss.\",\"cost\":\"Loses the again.\"},{\"text\":\"Option 2: \\\"Nobody moved, and the kettle went cold.\\\"\",\"move\":\"Puts people first.\",\"cost\":\"Buries the kettle.\"},{\"text\":\"The kettle went cold on the counter, and nobody moved to fill it again.\",\"move\":\"Nothing.\",\"cost\":\"Nothing.\"}]}")
    }

    test("rewrite: propose locates the span, asks once and cleans what comes back") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([proposeReply()]);
      let r = rewritePropose(fx.db, llm, fx.work, "The kettle went cold on the counter", null);
      rdText(test, rdOr(r.error, "ok"), "ok");
      rdText(test, rdOr(r.reading, "?"), "It states the scene flatly.");
      rdText(test, r.original, "The kettle went cold on the counter");
      // the third candidate is the original sentence's words only if the span were the sentence
      rdInt(test, r.candidates.length, 3);
      rdText(test, r.candidates[1].text, "Nobody moved, and the kettle went cold.");
      // the span sits inside one paragraph, so a candidate can be dropped into it
      rdTrue(test, !r.spansBlocks, "inside one paragraph");
      rdText(test, rdJoin(r.covers), "s1p1");
      rdCalls(test, llm, 1);
    }

    test("rewrite: the request carries the span, its paragraph, the steer and the limits") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([proposeReply()]);
      rewritePropose(fx.db, llm, fx.work, "The kettle went cold on the counter", "lead with the people");
      rdSent(test, llm, "Manuscript: W");
      rdSent(test, llm, "THE SELECTED SPAN, to be replaced:");
      rdSent(test, llm, "The paragraph it sits in, for context");
      rdSent(test, llm, "WHAT THE WRITER ASKED FOR, in their words:\\nlead with the people");
      rdSent(test, llm, "propose_rewrites");
      rdSent(test, llm, "\"temperature\":0.7");
      rdSent(test, llm, "\"reasoning_effort\":\"high\"");
      rdSent(test, llm, "\"max_tokens\":27000");
    }

A selection across paragraphs sits in none of them: no context is sent, and a
candidate cannot be dropped into a paragraph.

    test("rewrite: a span across paragraphs has no paragraph around it") { test =>
      let fx = rewriteFixture();
      let ps = readingSplit(fx.section.body);
      let tail = readingSliceCp(ps[1], readingLength(ps[1]) - 30, 30);
      let llm = llmFake([proposeReply()]);
      let r = rewritePropose(fx.db, llm, fx.work, "${tail}\n\n${readingSliceCp(ps[2], 0, 20)}", null);
      rdText(test, rdOr(r.error, "ok"), "ok");
      rdTrue(test, r.spansBlocks, "no single paragraph holds it");
      rdSentNot(test, llm, "The paragraph it sits in");
      rdInt(test, r.covers.length, 2);
    }

A reply without a `rewrites` list used to come back as the raw reply map and
fall through the caller's pattern match. It is an error here, never the raw text.

    test("rewrite: a reply with no rewrites is an error, not the raw reply") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([rdToolReply("propose_rewrites", "{\"reading\":\"x\"}")]);
      let r = rewritePropose(fx.db, llm, fx.work, "The kettle went cold on the counter", null);
      rdText(test, rdOr(r.error, "ok"), "no_candidates");
      rdInt(test, r.candidates.length, 0);
    }

    test("rewrite: candidates that all clean away are no_candidates") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([rdToolReply("propose_rewrites", "{\"reading\":\"x\",\"rewrites\":[{\"text\":\"the kettle WENT cold on the counter\"}]}")]);
      let r = rewritePropose(fx.db, llm, fx.work, "The kettle went cold on the counter", null);
      rdText(test, rdOr(r.error, "ok"), "no_candidates");
    }

    test("rewrite: a reply that called no tool is no_tool_call") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([rdTextReply("Here are some ideas.")]);
      let r = rewritePropose(fx.db, llm, fx.work, "The kettle went cold on the counter", null);
      rdText(test, rdOr(r.error, "ok"), "no_tool_call");
    }

    test("rewrite: arguments that are not an object are invalid_json") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([rdToolReply("propose_rewrites", "[1, 2]")]);
      let r = rewritePropose(fx.db, llm, fx.work, "The kettle went cold on the counter", null);
      rdText(test, rdOr(r.error, "ok"), "invalid_json");
    }

    test("rewrite: ask works from a block's ref and does not locate it again") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([proposeReply()]);
      let r = rewriteAsk(fx.db, llm, fx.work, fx.section, "s1p1");
      rdText(test, rdOr(r.error, "ok"), "ok");
      rdText(test, r.original, readingSplit(fx.section.body)[1]);
      rdTrue(test, !r.spansBlocks, "the block is its own paragraph");
      rdText(test, rdJoin(r.covers), "s1p1");
      let gone = rewriteAsk(fx.db, llm, fx.work, fx.section, "s1p99");
      rdText(test, rdOr(gone.error, "ok"), "no_such_block");
    }

    test("rewrite: steer asks again with the writer's words in the prompt") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([proposeReply()]);
      let r = rewriteSteer(fx.db, llm, fx.work, fx.section, "s1p1", "make it plainer");
      rdText(test, rdOr(r.error, "ok"), "ok");
      rdSent(test, llm, "make it plainer");
    }

## Applying

The writer picks a candidate; it goes in through the draft's own edit, recorded
as a revision of origin `rewrite` with the move as its note.

    test("rewrite: applying a candidate replaces the block and records why") { test =>
      let fx = rewriteFixture();
      let llm = llmFake([proposeReply()]);
      let r = rewriteAsk(fx.db, llm, fx.work, fx.section, "s1p1");
      let pick = r.candidates[0];
      let applied = rewriteApply(fx.db, fx.work, fx.section, "s1p1", pick);
      rdTrue(test, applied.error == null, "applied");
      rdHas(test, applied.section.body, "The kettle went cold; nobody refilled it.");
      rdLacks(test, applied.section.body, "and nobody moved to fill it again");
      let revisions = worksRevisions(fx.db, fx.work.id);
      rdInt(test, revisions.length, 1);
      rdText(test, revisions[0].origin, "rewrite");
      rdText(test, rdOr(revisions[0].note, "?"), "Cuts the gloss.");
      let replay = worksReplay(fx.db, fx.work.id);
      rdTrue(test, replay.ok != null, "history replays");
    }

    test("rewrite: applying to a span replaces just the span") { test =>
      let fx = rewriteFixture();
      let pick = new RewriteCandidate("The kettle went cold", "Trims", "Loses the counter");
      let applied = rewriteApplySpan(fx.db, fx.section, "The kettle went cold on the counter", pick);
      rdTrue(test, applied.error == null, "applied");
      rdHas(test, applied.section.body, "The kettle went cold, and nobody moved to fill it again.");
    }

    test("rewrite: a block that has moved is refused, not guessed at") { test =>
      let fx = rewriteFixture();
      let pick = new RewriteCandidate("Anything.", null, null);
      let first = rewriteApplySpan(fx.db, fx.section, "The kettle went cold on the counter", pick);
      rdTrue(test, first.error == null, "applied");
      // the old text is gone now
      let again = rewriteApplySpan(fx.db, fx.section, "The kettle went cold on the counter", pick);
      rdText(test, rdOr(again.error, "ok"), "moved");
      let blank = rewriteApplySpan(fx.db, fx.section, "Anything.", new RewriteCandidate("   ", null, null));
      rdText(test, rdOr(blank.error, "ok"), "empty");
      let none = rewriteApply(fx.db, fx.work, fx.section, "s1p77", pick);
      rdText(test, rdOr(none.error, "ok"), "no_such_block");
    }
