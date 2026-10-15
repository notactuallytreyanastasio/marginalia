# Tests for the stacks passes

Each pass driven with `llmFake` answers shaped like the tool schemas say the
model answers, over fixtures made through `works` and `folders`. The passes
that wrap other contexts (summarise, read each, relate) are given closures, as
the web layer will give them the real ones. No test forks: the job bodies are
called in-process over a `running` row inserted by hand.

    let { Db, dbOpen } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Work } = import("works/src");
    let { Folder } = import("folders/src");
    let { LlmClient, llmFake, llmFakeScript, LlmFakeResponse, llmRequests } = import("llm/src");
    let { Run } = import("runs/src");
    let { sysJoin } = import("sys/src");

    let stepReply(capability: String, requires: String, pitfall: String, quote: String): String throws Bubble {
      toolReply(
        "report_step",
        "{'capability':'${capability}','requires':${requires},'lesson':'Do ${capability}.','pitfall':'${pitfall}','pitfall_quote':'${quote}','excerpts':[{'quote':'something quotable in it','caption':'the shape'}]}",
      )
    }

    let quotable(): String { "A second paragraph with something quotable in it." }

    let deepReply(mechanism: String, watch: String, revisedBy: Int, revision: String, quote: String): String throws Bubble {
      toolReply(
        "deepen_step",
        "{'mechanism':'${mechanism}','watch_for':'${watch}','revised_by':${revisedBy.toString()},'revision':'${revision}','revision_quote':'${quote}'}",
      )
    }

    let outlineReply(parts: String): String throws Bubble {
      toolReply(
        "outline_story",
        "{'title':'How it is built','opening':'Open.','closing':'Close.','parts':${parts}}",
      )
    }

    let partReply(prose: String, turn: String): String throws Bubble {
      toolReply("write_part", "{'prose':'${prose}','turn':'${turn}'}")
    }

    let failing(status: Int): LlmFakeResponse {
      new LlmFakeResponse(status, "nope")
    }

    let okResponse(body: String): LlmFakeResponse {
      new LlmFakeResponse(200, body)
    }

    let stepsOf(db: Db, f: Folder): List<StackStep> throws Bubble {
      stacksListSteps(db, f.id)
    }

    let capsOf(steps: List<StackStep>): String {
      joined(steps.map { (s: StackStep): String => orEmpty(s.capability) })
    }

    let ordinalsOf(steps: List<StackStep>): String {
      intsText(steps.map { (s: StackStep): Int => s.ordinal })
    }

    let stepAt(steps: List<StackStep>, ordinal: Int): StackStep {
      var found = stacksSketch(0, null, null, null);
      for (let s of steps) {
        if (s.ordinal == ordinal) { found = s; }
      }
      found
    }

    let requestsText(llm: LlmClient, at: Int): String {
      let all = llmRequests(llm);
      if (at < all.length) { all[at] } else { "<no such request>" }
    }

    let runRow(db: Db, folderId: Int): String throws Bubble {
      let row = db.one(
        "SELECT status, progress, detail FROM runs WHERE key = $1",
        [stacksRunKey(folderId)],
      );
      if (row != null) {
        "${row.str("status")}|${orNone(row.strOrNull("progress"))}|${orNone(row.strOrNull("detail"))}"
      } else {
        "none"
      }
    }

A stack of `n` steps made directly: capabilities "cap 1".., lessons "Lesson
1.".., in a folder called "A backend", filed documents "1. Doc 1"..

    class StackFixture(public db: Db, public me: Scope, public folder: Folder) {}

    let stackOf(n: Int): StackFixture throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeStack(db, me, "A backend", n);
      new StackFixture(db, me, f)
    }

    let stepped(n: Int): StackFixture throws Bubble {
      let fx = stackOf(n);
      let docs = stacksDocuments(fx.db, fx.me, fx.folder.id);
      var i = 1;
      while (i <= n) {
        makeStep(fx.db, fx.folder.id, docs[i - 1].id, i, "cap ${i.toString()}", []);
        i += 1;
      }
      fx
    }

## The forward read

    test("a read pass reads every document in order, each told what the earlier ones established") { test =>
      let fx = stackOf(2);
      let llm = llmFake([
        stepReply("one", "[]", "Skipping it breaks.", quotable()),
        stepReply("two", "[1,7]", "", ""),
      ]);
      let probe = new StackProbe();
      let r = stacksReadPass(fx.db, llm, fx.me, fx.folder.id, fn (p: String, d: String?): Void { probe.record(p, d); });
      expectInt(test, r.done, 2);
      expectInt(test, r.failures.length, 0);
      expectText(test, r.detail, "errors:0");
      expectText(test, probe.text(), "0/2|read,1/2|read,2/2|read");
      let steps = stepsOf(fx.db, fx.folder);
      expectText(test, ordinalsOf(steps), "1,2");
      expectText(test, capsOf(steps), "one,two");
      expectText(test, intsText(steps[1].requires), "1");
      expectTrue(test, anyHas(steps[1].dropped, "requires 7: not an earlier document"), "7 named");
      expectText(test, orNone(steps[0].pitfall), "Skipping it breaks.");
      expectText(test, orNone(steps[0].pitfallQuote), quotable());
      expectText(test, orNone(steps[1].pitfall), "<null>");
      expectInt(test, steps[0].excerpts.length, 1);
      expectText(test, steps[0].excerpts[0].caption, "the shape");
      expectText(test, steps[0].excerpts[0].text, quotable());
      expectText(test, orNone(steps[0].lesson), "Do one.");
      let docs = stacksDocuments(fx.db, fx.me, fx.folder.id);
      expectText(test, orNone(steps[0].fingerprint), stacksFingerprint(fx.db, docs[0].id));
      expectInt(test, steps[1].workId, docs[1].id);
      let first = requestsText(llm, 0);
      let second = requestsText(llm, 1);
      expectInt(test, llmRequests(llm).length, 2);
      expectHas(test, first, "The series builds: A backend");
      expectHas(test, first, "# Document 1: 1. Doc 1");
      expectHas(test, first, "this is the first document");
      expectHas(test, first, "\"name\":\"report_step\"");
      expectHas(test, first, "\"temperature\":0.2");
      expectHas(test, second, "# Document 2: 2. Doc 2");
      expectHas(test, second, "  1. one");
      expectLacks(test, second, "this is the first document");
      expectHas(test, second, "## The document");
    }

    test("a document the model could not read is skipped, its ordinal is not reused, and the next is not told of it") { test =>
      let fx = stackOf(3);
      let llm = llmFakeScript([
        okResponse(stepReply("one", "[]", "", "")),
        failing(400),
        okResponse(stepReply("three", "[1]", "", "")),
      ]);
      let probe = new StackProbe();
      let r = stacksReadPass(fx.db, llm, fx.me, fx.folder.id, fn (p: String, d: String?): Void { probe.record(p, d); });
      expectInt(test, r.done, 2);
      expectInt(test, r.failures.length, 1);
      expectInt(test, r.failures[0].ordinal, 2);
      expectText(test, r.failures[0].title, "2. Doc 2");
      expectHas(test, r.failures[0].reason, "http");
      expectText(test, r.detail, "errors:1");
      expectText(test, probe.text(), "0/3|read,1/3|read,3/3|read");
      let steps = stepsOf(fx.db, fx.folder);
      expectText(test, ordinalsOf(steps), "1,3");
      let third = requestsText(llm, 2);
      expectHas(test, third, "  1. one");
      expectLacks(test, third, "  2. ");
      expectHas(test, third, "# Document 3: 3. Doc 3");
    }

    test("a reply that calls no tool is a failure, not an empty step") { test =>
      let fx = stackOf(1);
      let llm = llmFake([proseReply()]);
      let r = stacksReadPass(fx.db, llm, fx.me, fx.folder.id, fn (p: String, d: String?): Void { });
      expectInt(test, r.done, 0);
      expectHas(test, r.failures[0].reason, "no_tool_call");
      expectInt(test, stepsOf(fx.db, fx.folder).length, 0);
    }

    test("a rate limited reply is retried by the client, then a failure of the document") { test =>
      let fx = stackOf(1);
      let llm = llmFakeScript([failing(429), failing(429), failing(429)]);
      let r = stacksReadPass(fx.db, llm, fx.me, fx.folder.id, fn (p: String, d: String?): Void { });
      expectInt(test, r.done, 0);
      expectHas(test, r.failures[0].reason, "rate_limited");
      expectInt(test, llmRequests(llm).length, 3);
    }

    test("a re-read overwrites every column, the second pass's included, and keeps the row") { test =>
      let fx = stepped(1);
      let docs = stacksDocuments(fx.db, fx.me, fx.folder.id);
      fx.db.exec(
        "UPDATE stack_steps SET mechanism = 'm', watch_for = 'w', revised_by = 3, revision = 'r', revision_quote = 'q', deep_dropped = '[\"x\"]', deepened_at = '2026-01-01 00:00:00', inserted_at = '2020-02-02 02:02:02' WHERE folder_id = $1",
        [fx.folder.id.toString()],
      );
      let before = stepsOf(fx.db, fx.folder)[0];
      let llm = llmFake([stepReply("fresh", "[]", "", "")]);
      stacksReadPass(fx.db, llm, fx.me, fx.folder.id, fn (p: String, d: String?): Void { });
      let steps = stepsOf(fx.db, fx.folder);
      expectInt(test, steps.length, 1);
      let after = steps[0];
      expectInt(test, after.id, before.id);
      expectText(test, orNone(after.capability), "fresh");
      expectText(test, orNone(after.mechanism), "<null>");
      expectText(test, orNone(after.watchFor), "<null>");
      expectInt(test, orMinus(after.revisedBy), -1);
      expectText(test, orNone(after.revision), "<null>");
      expectText(test, orNone(after.revisionQuote), "<null>");
      expectInt(test, after.deepDropped.length, 0);
      expectText(test, orNone(after.deepenedAt), "<null>");
      expectText(test, after.insertedAt, "2020-02-02 02:02:02");
      expectInt(test, docs.length, 1);
    }

    test("reading the folder again does not add rows") { test =>
      let fx = stackOf(2);
      let again = llmFake([stepReply("a", "[]", "", ""), stepReply("b", "[]", "", ""), stepReply("c", "[]", "", ""), stepReply("d", "[]", "", "")]);
      stacksReadPass(fx.db, again, fx.me, fx.folder.id, fn (p: String, d: String?): Void { });
      stacksReadPass(fx.db, again, fx.me, fx.folder.id, fn (p: String, d: String?): Void { });
      expectText(test, capsOf(stepsOf(fx.db, fx.folder)), "c,d");
    }

    test("only the last twenty-five capabilities are handed on") { test =>
      let fx = stackOf(1);
      let docs = stacksDocuments(fx.db, fx.me, fx.folder.id);
      let prior = new ListBuilder<StackStep>();
      var i = 1;
      while (i <= 30) {
        prior.add(stacksSketch(i, "capability ${i.toString()}.", null, null));
        i += 1;
      }
      let llm = llmFake([stepReply("x", "[]", "", "")]);
      stacksReadStep(fx.db, llm, fx.folder.id, docs[0], 31, prior.toList(), null);
      let sent = requestsText(llm, 0);
      expectHas(test, sent, "  6. capability 6.");
      expectLacks(test, sent, "  5. capability 5.");
      expectHas(test, sent, "  30. capability 30.");
      expectLacks(test, sent, "The series builds");
    }

    test("a leaking capability is stored cut, and the cut is recorded on the step") { test =>
      let fx = stackOf(1);
      let leakText = leakJson();
      let llm = llmFake([toolReply("report_step", "{'capability':'A real one. ${leakText}','requires':[],'lesson':'Do it.','pitfall':'','pitfall_quote':'','excerpts':[]}")]);
      stacksReadPass(fx.db, llm, fx.me, fx.folder.id, fn (p: String, d: String?): Void { });
      let step = stepsOf(fx.db, fx.folder)[0];
      expectText(test, orNone(step.capability), "A real one.");
      expectTrue(test, anyHas(step.dropped, "capability: the model leaked"), "reported");
    }

    test("an empty capability is stored as no capability, as cast does") { test =>
      let fx = stackOf(1);
      let llm = llmFake([toolReply("report_step", "{'capability':'  ','requires':[],'lesson':'','pitfall':'','pitfall_quote':'','excerpts':[]}")]);
      stacksReadPass(fx.db, llm, fx.me, fx.folder.id, fn (p: String, d: String?): Void { });
      let step = stepsOf(fx.db, fx.folder)[0];
      expectText(test, orNone(step.capability), "<null>");
      expectText(test, orNone(step.lesson), "<null>");
    }

    test("an empty folder reads nothing and calls nobody") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "Empty");
      let llm = llmFake([]);
      let probe = new StackProbe();
      let r = stacksReadPass(db, llm, me, f.id, fn (p: String, d: String?): Void { probe.record(p, d); });
      expectInt(test, r.done, 0);
      expectInt(test, llmRequests(llm).length, 0);
      expectText(test, probe.text(), "0/0|read");
    }

    test("another writer's folder is not read") { test =>
      let fx = stackOf(2);
      let them = makeUser(fx.db, "b@example.com");
      let llm = llmFake([]);
      let r = stacksReadPass(fx.db, llm, them, fx.folder.id, fn (p: String, d: String?): Void { });
      expectInt(test, r.done, 0);
      expectInt(test, llmRequests(llm).length, 0);
    }

## The second pass

    test("a deepen pass reads each step with the whole chain, and keeps what it can check") { test =>
      let fx = stepped(3);
      fx.db.exec("UPDATE stack_steps SET pitfall = 'p1' WHERE ordinal = 1", []);
      let llm = llmFake([
        deepReply("It works.", "Step 2 leans on it.", 3, "Step 3 changes it.", "Lesson 3."),
        deepReply("m2", "", 0, "", ""),
        deepReply("", "", 0, "", ""),
      ]);
      let probe = new StackProbe();
      let r = stacksDeepenPass(fx.db, llm, fx.folder.id, false, fn (p: String, d: String?): Void { probe.record(p, d); });
      expectInt(test, r.done, 3);
      expectText(test, r.detail, "errors:0");
      expectText(test, probe.text(), "0/3|deepen,1/3|deepen,2/3|deepen,3/3|deepen");
      let steps = stepsOf(fx.db, fx.folder);
      let one = stepAt(steps, 1);
      expectText(test, orNone(one.mechanism), "It works.");
      expectText(test, orNone(one.watchFor), "Step 2 leans on it.");
      expectInt(test, orMinus(one.revisedBy), 3);
      expectText(test, orNone(one.revision), "Step 3 changes it.");
      expectText(test, orNone(one.revisionQuote), "Lesson 3.");
      expectTrue(test, one.deepenedAt != null, "stamped");
      expectInt(test, one.deepDropped.length, 0);
      let two = stepAt(steps, 2);
      expectText(test, orNone(two.mechanism), "m2");
      expectText(test, orNone(two.watchFor), "<null>");
      let three = stepAt(steps, 3);
      expectText(test, orNone(three.mechanism), "<null>");
      expectText(test, joined(three.deepDropped), "mechanism: empty");
      expectTrue(test, three.deepenedAt != null, "an empty mechanism is still a second pass");
      let st = stacksStats(fx.db, fx.me, fx.folder.id);
      expectInt(test, st.deepened, 3);
      expectInt(test, st.revisions, 1);
      expectInt(test, st.deepDropped, 1);
      expectInt(test, st.deepFailed, 0);
    }

    test("the deepen prompt shows the chain with the step marked, the document and everything after it") { test =>
      let fx = stepped(3);
      fx.db.exec("UPDATE stack_steps SET pitfall = 'p3' WHERE ordinal = 3", []);
      fx.db.exec("UPDATE stack_steps SET pitfall = 'p1' WHERE ordinal = 1", []);
      let llm = llmFake([deepReply("a", "", 0, "", ""), deepReply("b", "", 0, "", ""), deepReply("c", "", 0, "", "")]);
      stacksDeepenPass(fx.db, llm, fx.folder.id, false, fn (p: String, d: String?): Void { });
      let first = requestsText(llm, 0);
      expectHas(test, first, "# The whole series (>> marks the step you are re-reading)");
      expectHas(test, first, ">> 1. cap 1\\n   2. cap 2\\n   3. cap 3");
      expectHas(test, first, "# Step 1: 1. Doc 1");
      expectHas(test, first, "What the first reading said it establishes: cap 1\\nWhat it said to do: Lesson 1.\\nThe pitfall it named: p1\\n\\n## The document itself");
      expectHas(test, first, "## Everything that comes after it\\n\\n### Step 2: cap 2\\nLesson 2.\\n\\n### Step 3: cap 3\\nLesson 3.\\nPitfall: p3\\n");
      expectLacks(test, first, "The series builds");
      expectHas(test, first, "\"name\":\"deepen_step\"");
      let second = requestsText(llm, 1);
      expectHas(test, second, "   1. cap 1\\n>> 2. cap 2\\n   3. cap 3");
      expectHas(test, second, "Lesson 2.\\n\\n## The document itself");
      let third = requestsText(llm, 2);
      expectHas(test, third, "this is the last step");
    }

    test("a second deepen pass touches only what is not deepened, unless forced") { test =>
      let fx = stepped(2);
      let first = llmFake([deepReply("a", "", 0, "", ""), deepReply("b", "", 0, "", "")]);
      stacksDeepenPass(fx.db, first, fx.folder.id, false, fn (p: String, d: String?): Void { });
      let none = llmFake([]);
      let probe = new StackProbe();
      let r = stacksDeepenPass(fx.db, none, fx.folder.id, false, fn (p: String, d: String?): Void { probe.record(p, d); });
      expectInt(test, r.done, 0);
      expectInt(test, llmRequests(none).length, 0);
      expectText(test, probe.text(), "0/2|deepen");
      let forced = llmFake([deepReply("c", "", 0, "", ""), deepReply("d", "", 0, "", "")]);
      let again = stacksDeepenPass(fx.db, forced, fx.folder.id, true, fn (p: String, d: String?): Void { });
      expectInt(test, again.done, 2);
      expectInt(test, llmRequests(forced).length, 2);
      expectText(test, orNone(stepAt(stepsOf(fx.db, fx.folder), 1).mechanism), "c");
    }

    test("a step that failed the second pass says so, counts as failed, and is retried alone") { test =>
      let fx = stepped(2);
      let llm = llmFakeScript([okResponse(deepReply("a", "", 0, "", "")), failing(400)]);
      let r = stacksDeepenPass(fx.db, llm, fx.folder.id, false, fn (p: String, d: String?): Void { });
      expectInt(test, r.done, 1);
      expectInt(test, r.failures.length, 1);
      expectInt(test, r.failures[0].ordinal, 2);
      expectText(test, r.detail, "errors:1");
      let bad = stepAt(stepsOf(fx.db, fx.folder), 2);
      expectText(test, orNone(bad.deepenedAt), "<null>");
      expectTrue(test, anyHas(bad.deepDropped, "the second pass failed: http"), "recorded on the step");
      let st = stacksStats(fx.db, fx.me, fx.folder.id);
      expectInt(test, st.deepFailed, 1);
      expectInt(test, st.deepened, 1);
      let retry = llmFake([deepReply("b", "", 0, "", "")]);
      let again = stacksDeepenPass(fx.db, retry, fx.folder.id, false, fn (p: String, d: String?): Void { });
      expectInt(test, again.done, 1);
      expectInt(test, llmRequests(retry).length, 1);
      let fixed = stepAt(stepsOf(fx.db, fx.folder), 2);
      expectText(test, orNone(fixed.mechanism), "b");
      expectInt(test, fixed.deepDropped.length, 0);
      expectInt(test, stacksStats(fx.db, fx.me, fx.folder.id).deepFailed, 0);
    }

    test("a revision pointing nowhere is refused and named on the step") { test =>
      let fx = stepped(2);
      let llm = llmFake([deepReply("a", "", 2, "Step 2 undoes it.", "invented words"), deepReply("b", "", 0, "", "")]);
      stacksDeepenPass(fx.db, llm, fx.folder.id, false, fn (p: String, d: String?): Void { });
      let one = stepAt(stepsOf(fx.db, fx.folder), 1);
      expectInt(test, orMinus(one.revisedBy), -1);
      expectText(test, joined(one.deepDropped), "revision: quote is not in step 2's summary");
    }

## Composing the telling

    let composeFixture(): StackFixture throws Bubble {
      let fx = stepped(4);
      fx.db.exec("UPDATE stack_steps SET pitfall = 'p2' WHERE ordinal = 2", []);
      fx.db.exec("UPDATE stack_steps SET requires = '[1,2]', mechanism = 'It lifts the tail.', watch_for = 'Mind the exit.' WHERE ordinal = 3", []);
      fx.db.exec("UPDATE stack_steps SET revised_by = 4, revision = 'Step 4 replaces it.' WHERE ordinal = 1", []);
      fx
    }

    let twoPartOutline(): String throws Bubble {
      outlineReply("[{'heading':'Groundwork','steps':[1,2]},{'heading':'The hard part','steps':[3,4]}]")
    }

    test("compose outlines from the spine, writes each part from its own steps, and stores the telling") { test =>
      let fx = composeFixture();
      let llm = llmFake([twoPartOutline(), partReply("Prose one.", "A turn."), partReply("Prose two.", "")]);
      let probe = new StackProbe();
      let r = stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { probe.record(p, d); });
      expectText(test, orNone(r.error), "<null>");
      expectText(test, r.detail(), "ok");
      expectText(test, probe.text(), "0/0|compose:outlining,0/2|compose:writing,1/2|compose:writing,2/2|compose:writing");
      let story = stacksGetStory(fx.db, fx.folder.id);
      expectTrue(test, story != null, "stored");
      let s = orStory(story);
      expectText(test, orNone(s.title), "How it is built");
      expectText(test, orNone(s.opening), "Open.");
      expectText(test, orNone(s.closing), "Close.");
      expectInt(test, s.movements.length, 2);
      expectText(test, s.movements[0].heading, "Groundwork");
      expectText(test, s.movements[0].prose, "Prose one.");
      expectText(test, s.movements[0].turn, "A turn.");
      expectText(test, intsText(s.movements[1].steps), "3,4");
      expectText(test, s.movements[1].turn, "");
      expectInt(test, s.uncovered.length, 0);
      expectInt(test, s.dropped.length, 0);
      expectTrue(test, s.isComplete(), "complete");
      expectTrue(test, stacksStoryCurrent(fx.db, s, fx.folder.id), "composed from the steps as they stand");
      expectText(test, orNone(s.fingerprint), stacksStoryFingerprint(stepsOf(fx.db, fx.folder)));
      expectInt(test, llmRequests(llm).length, 3);
    }

    let orStory(s: StackStory?): StackStory throws Bubble {
      if (s != null) { s } else { bubble() }
    }

    test("the outline prompt carries one line per step with its marks") { test =>
      let fx = composeFixture();
      let llm = llmFake([twoPartOutline(), partReply("a", ""), partReply("b", "")]);
      stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { });
      let outline = requestsText(llm, 0);
      expectHas(test, outline, "What is being built: A backend\\n4 steps, in order. Divide them into parts.\\n\\n");
      expectHas(test, outline, "1. cap 1   [revised by 4]\\n2. cap 2   [pitfall]\\n3. cap 3\\n4. cap 4\\n");
      expectHas(test, outline, "\"name\":\"outline_story\"");
      expectHas(test, outline, "\"temperature\":0.4");
    }

    test("a part is written from only its steps, with everything the notes know about them") { test =>
      let fx = composeFixture();
      let llm = llmFake([twoPartOutline(), partReply("a", ""), partReply("b", "")]);
      stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { });
      let one = requestsText(llm, 1);
      expectHas(test, one, "What is being built: A backend\\nThe telling is called: How it is built\\n\\nYou are writing one part of it: **Groundwork**\\nIt covers steps 1, 2 and nothing else.\\n\\n");
      expectHas(test, one, "## Step 1: cap 1\\nWhat to do: Lesson 1.\\nWalked back by step 4: Step 4 replaces it.\\n\\n## Step 2: cap 2\\nWhat to do: Lesson 2.\\nThe obvious version is wrong: p2\\n");
      expectLacks(test, one, "## Step 3");
      expectHas(test, one, "\"name\":\"write_part\"");
      let two = requestsText(llm, 2);
      expectHas(test, two, "## Step 3: cap 3\\nStands on: 1, 2\\nWhat to do: Lesson 3.\\nHow it works: It lifts the tail.\\nGet right now: Mind the exit.\\n\\n## Step 4: cap 4\\nWhat to do: Lesson 4.\\n");
      expectLacks(test, two, "## Step 1");
    }

    test("with no building named the prompt says what it can") { test =>
      let fx = composeFixture();
      let llm = llmFake([twoPartOutline(), partReply("a", ""), partReply("b", "")]);
      stacksCompose(fx.db, llm, fx.folder.id, null, fn (p: String, d: String?): Void { });
      expectHas(test, requestsText(llm, 0), "What is being built: the thing this series builds");
    }

    test("composing again replaces the telling, and an edit to a step makes it stale") { test =>
      let fx = composeFixture();
      let llm = llmFake([twoPartOutline(), partReply("a", ""), partReply("b", ""), twoPartOutline(), partReply("c", ""), partReply("d", "")]);
      stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { });
      let first = orStory(stacksGetStory(fx.db, fx.folder.id));
      stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { });
      let second = orStory(stacksGetStory(fx.db, fx.folder.id));
      expectInt(test, second.id, first.id);
      expectText(test, second.movements[0].prose, "c");
      expectInt(test, fx.db.query("SELECT id FROM stack_stories", []).length, 1);
      expectTrue(test, stacksStoryCurrent(fx.db, second, fx.folder.id), "fresh");
      fx.db.exec("UPDATE stack_steps SET capability = 'changed' WHERE ordinal = 4", []);
      expectFalse(test, stacksStoryCurrent(fx.db, second, fx.folder.id), "stale");
    }

    test("a folder with no steps cannot be composed") { test =>
      let fx = stackOf(2);
      let llm = llmFake([]);
      let probe = new StackProbe();
      let r = stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { probe.record(p, d); });
      expectText(test, orNone(r.error), "not_read");
      expectText(test, r.detail(), "error:not_read");
      expectInt(test, probe.count(), 0);
      expectInt(test, llmRequests(llm).length, 0);
    }

    test("an outline that will not come stores nothing and says why") { test =>
      let fx = composeFixture();
      let llm = llmFakeScript([failing(400)]);
      let probe = new StackProbe();
      let r = stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { probe.record(p, d); });
      expectHas(test, orNone(r.error), "http");
      expectTrue(test, r.story == null, "no story");
      expectTrue(test, stacksGetStory(fx.db, fx.folder.id) == null, "nothing stored");
      expectText(test, probe.text(), "0/0|compose:outlining");
    }

    test("a part that will not write is dropped and every step it carried is named") { test =>
      let fx = composeFixture();
      let llm = llmFakeScript([okResponse(twoPartOutline()), okResponse(partReply("Prose one.", "")), failing(400)]);
      let r = stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { });
      expectText(test, orNone(r.error), "<null>");
      let s = orStory(stacksGetStory(fx.db, fx.folder.id));
      expectInt(test, s.movements.length, 1);
      expectText(test, intsText(s.uncovered), "3,4");
      expectFalse(test, s.isComplete(), "incomplete");
      expectTrue(test, anyHas(s.dropped, "a part with no prose"), "named");
      expectTrue(test, anyHas(s.dropped, "2 step(s) appear in no part: 3, 4"), "coverage");
    }

    test("a part reply without prose is a part that did not write") { test =>
      let fx = composeFixture();
      let llm = llmFake([twoPartOutline(), toolReply("write_part", "{'turn':'x'}"), partReply("Prose two.", "")]);
      stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { });
      let s = orStory(stacksGetStory(fx.db, fx.folder.id));
      expectText(test, intsText(s.uncovered), "1,2");
      expectText(test, s.movements[0].heading, "The hard part");
    }

    test("an outline with no parts stores a telling that covers nothing") { test =>
      let fx = composeFixture();
      let llm = llmFake([toolReply("outline_story", "{'title':'T','opening':'O','closing':'C'}")]);
      let probe = new StackProbe();
      stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { probe.record(p, d); });
      let s = orStory(stacksGetStory(fx.db, fx.folder.id));
      expectInt(test, s.movements.length, 0);
      expectText(test, intsText(s.uncovered), "1,2,3,4");
      expectText(test, probe.text(), "0/0|compose:outlining,0/0|compose:writing");
    }

    test("a part that repeats a step is refused the second telling, and the leak guard runs on the prose") { test =>
      let fx = composeFixture();
      let outline = outlineReply("[{'heading':'A','steps':[1,2,3]},{'heading':'B','steps':[3,4]}]");
      let leaking = partReply("Good prose.\\n\\n${leakJson()}", "");
      let llm = llmFake([outline, leaking, partReply("Prose two.", "")]);
      stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { });
      let s = orStory(stacksGetStory(fx.db, fx.folder.id));
      expectText(test, s.movements[0].prose, "Good prose.");
      expectTrue(test, anyHas(s.dropped, "part \"B\": step 3 is told twice"), "named");
      expectTrue(test, anyHas(s.dropped, "leaked its own tool-call markup"), "cut reported");
      expectText(test, intsText(s.movements[1].steps), "4");
    }

    test("a composed telling becomes a draft") { test =>
      let fx = composeFixture();
      let llm = llmFake([twoPartOutline(), partReply(longProse("First part."), "A turn."), partReply(longProse("Second part."), "")]);
      stacksCompose(fx.db, llm, fx.folder.id, "A backend", fn (p: String, d: String?): Void { });
      let d = stacksToDraft(fx.db, fx.me, fx.folder.id);
      let work = d.work;
      expectTrue(test, work != null, orNone(d.error));
      expectText(test, orNone(if (work != null) { work.title } else { null }), "How it is built");
      expectHas(test, orEmpty(if (work != null) { work.intent } else { null }), "in 2 parts");
      expectHas(test, orEmpty(if (work != null) { work.intent } else { null }), "out of 4 documents");
    }

## Summarise, read each, relate

    test("a summarise pass skips what is summarised, reports failures, and ticks after every document") { test =>
      let fx = stackOf(3);
      let docs = stacksDocuments(fx.db, fx.me, fx.folder.id);
      summarised(fx.db, docs[0].id, "what it says");
      let seen = new ListBuilder<String>();
      let probe = new StackProbe();
      let r = stacksSummarisePass(
        fx.db, fx.me, fx.folder.id, false,
        fn (w: Work): String? throws Bubble {
          seen.add(w.title);
          if (w.title == "3. Doc 3") { "boom" } else { null }
        },
        fn (p: String, d: String?): Void { probe.record(p, d); },
      );
      expectText(test, joined(seen.toList()), "2. Doc 2,3. Doc 3");
      expectInt(test, r.done, 1);
      expectInt(test, r.failures.length, 1);
      expectText(test, r.failures[0].title, "3. Doc 3");
      expectText(test, r.failures[0].reason, "boom");
      expectText(test, r.detail, "errors:1");
      expectText(test, probe.text(), "0/2|summarise,1/2|summarise,2/2|summarise");
    }

    test("a summarise pass with force takes every document") { test =>
      let fx = stackOf(3);
      let docs = stacksDocuments(fx.db, fx.me, fx.folder.id);
      summarised(fx.db, docs[0].id, "what it says");
      let seen = new ListBuilder<String>();
      let r = stacksSummarisePass(
        fx.db, fx.me, fx.folder.id, true,
        fn (w: Work): String? throws Bubble { seen.add(w.title); null },
        fn (p: String, d: String?): Void { },
      );
      expectInt(test, seen.length, 3);
      expectInt(test, r.done, 3);
    }

    test("a folder already summarised does nothing and calls nobody") { test =>
      let fx = stackOf(3);
      for (let w of stacksDocuments(fx.db, fx.me, fx.folder.id)) { summarised(fx.db, w.id, "what it says"); }
      let calls = new ListBuilder<String>();
      let probe = new StackProbe();
      let r = stacksSummarisePass(
        fx.db, fx.me, fx.folder.id, false,
        fn (w: Work): String? throws Bubble { calls.add(w.title); null },
        fn (p: String, d: String?): Void { probe.record(p, d); },
      );
      expectInt(test, r.done, 0);
      expectInt(test, r.failures.length, 0);
      expectInt(test, calls.length, 0);
      expectText(test, probe.text(), "0/0|summarise");
    }

    test("an empty folder is not an error, and another writer's folder yields nothing") { test =>
      let fx = stackOf(2);
      let empty = makeFolder(fx.db, fx.me, "Nothing in it");
      let them = makeUser(fx.db, "b@example.com");
      let calls = new ListBuilder<String>();
      let one = stacksSummarisePass(fx.db, fx.me, empty.id, false, fn (w: Work): String? throws Bubble { calls.add(w.title); null }, fn (p: String, d: String?): Void { });
      let two = stacksSummarisePass(fx.db, them, fx.folder.id, false, fn (w: Work): String? throws Bubble { calls.add(w.title); null }, fn (p: String, d: String?): Void { });
      expectInt(test, one.done, 0);
      expectInt(test, two.done, 0);
      expectInt(test, calls.length, 0);
    }

    test("a read-each pass takes the unmapped documents and fails those that come out with no nodes") { test =>
      let fx = stackOf(3);
      let docs = stacksDocuments(fx.db, fx.me, fx.folder.id);
      fx.db.exec("UPDATE works SET status = 'read' WHERE id = $1", [docs[0].id.toString()]);
      let seen = new ListBuilder<String>();
      let probe = new StackProbe();
      let db = fx.db;
      let r = stacksReadEachPass(
        fx.db, fx.me, fx.folder.id, false,
        fn (w: Work): Void throws Bubble {
          seen.add(w.title);
          if (w.title == "2. Doc 2") {
            db.exec("INSERT INTO nodes (work_id, node_type, title) VALUES ($1, 'beat', 'b')", [w.id.toString()]);
          }
        },
        fn (p: String, d: String?): Void { probe.record(p, d); },
      );
      expectText(test, joined(seen.toList()), "2. Doc 2,3. Doc 3");
      expectInt(test, r.done, 1);
      expectInt(test, r.failures.length, 1);
      expectText(test, r.failures[0].title, "3. Doc 3");
      expectText(test, r.failures[0].reason, "nothing_read");
      expectText(test, probe.text(), "0/2|read_each,1/2|read_each,2/2|read_each");
    }

    test("a folder whose documents are all mapped has nothing to read") { test =>
      let fx = stackOf(3);
      for (let w of stacksDocuments(fx.db, fx.me, fx.folder.id)) {
        fx.db.exec("UPDATE works SET status = 'read' WHERE id = $1", [w.id.toString()]);
      }
      let calls = new ListBuilder<String>();
      let r = stacksReadEachPass(fx.db, fx.me, fx.folder.id, false, fn (w: Work): Void throws Bubble { calls.add(w.title); }, fn (p: String, d: String?): Void { });
      expectInt(test, r.done, 0);
      expectInt(test, calls.length, 0);
      let them = makeUser(fx.db, "b@example.com");
      let theirs = stacksReadEachPass(fx.db, them, fx.folder.id, false, fn (w: Work): Void throws Bubble { calls.add(w.title); }, fn (p: String, d: String?): Void { });
      expectInt(test, theirs.done, 0);
      expectInt(test, calls.length, 0);
    }

    test("a relate pass counts pairs as they finish and keeps the stage in the detail") { test =>
      let probe = new StackProbe();
      let r = stacksRelatePass(
        fn (h: StackRelateHooks): StackRelateOutcome throws Bubble {
          h.stage("triage");
          h.pair(2);
          h.pair(2);
          new StackRelateOutcome(2, 1, null)
        },
        fn (p: String, d: String?): Void { probe.record(p, d); },
      );
      expectText(test, probe.text(), "0/0|relate,0/0|relate:triage,1/2|relate:relating,2/2|relate:relating");
      expectInt(test, r.done, 2);
      expectText(test, r.detail, "related:2:1");
    }

    test("a relate pass that fails reports why") { test =>
      let r = stacksRelatePass(
        fn (h: StackRelateHooks): StackRelateOutcome throws Bubble { new StackRelateOutcome(0, 0, "no_links") },
        fn (p: String, d: String?): Void { },
      );
      expectText(test, r.detail, "error:no_links");
      expectInt(test, r.failures.length, 1);
    }

## The run, as the page sees it

    let runOf(status: String, progress: String?, detail: String?): Run {
      new Run("stack:1", status, progress, detail, null, null, null)
    }

    test("a page that arrives mid-read shows the read") { test =>
      let v = stacksRunView(runOf("running", "4/12", "read"));
      expectTrue(test, v != null, "a view");
      if (v != null) {
        expectText(test, v.kind, "read");
        expectInt(test, v.done, 4);
        expectInt(test, v.total, 12);
        expectText(test, orNone(v.stageText()), "<null>");
      }
    }

    test("a page that arrives mid-compose says which part it is on") { test =>
      let v = stacksRunView(runOf("running", "2/5", "compose:writing"));
      expectText(test, orNone(if (v != null) { v.stageText() } else { null }), "part 2 of 5");
      let o = stacksRunView(runOf("running", "0/0", "compose:outlining"));
      expectText(test, orNone(if (o != null) { o.stageText() } else { null }), "outlining");
    }

    test("a relate run's stage is carried, but only composing words it") { test =>
      let v = stacksRunView(runOf("running", "2/5", "relate:relating"));
      expectText(test, orNone(if (v != null) { v.stage } else { null }), "relating");
      expectText(test, orNone(if (v != null) { v.stageText() } else { null }), "<null>");
    }

    test("no run, or a finished one, is no view; a run before its first report is zero of zero") { test =>
      expectTrue(test, stacksRunView(null) == null, "none");
      expectTrue(test, stacksRunView(runOf("done", "3/3", "read")) == null, "finished");
      expectTrue(test, stacksRunView(runOf("crashed", null, "boom")) == null, "crashed");
      let fresh = stacksRunView(runOf("running", null, null));
      expectInt(test, if (fresh != null) { fresh.total } else { -1 }, 0);
    }

    test("each pass has its own sentence under the bar") { test =>
      expectHas(test, stacksPassNote("summarise"), "one whole-document summary each");
      expectHas(test, stacksPassNote("relate"), "one call per pair");
      expectHas(test, stacksPassNote("read_each"), "the ordinary read of each one");
      expectHas(test, stacksPassNote("read"), "waits on the one before it");
      expectLacks(test, stacksPassNote("summarise"), "waits on the one before it");
      expectLacks(test, stacksPassNote("relate"), "waits on the one before it");
      expectHas(test, stacksPassNote("deepen"), "This runs on the server: you can close the page.");
    }

    test("pressing a button while a pass is running is told, not started") { test =>
      let f = stacksAlreadyRunning("read");
      expectText(test, f.level, "error");
      expectText(test, f.text, "A read pass is already running on this folder.");
    }

    test("the flash a finished run leaves") { test =>
      let none = stacksFlashFor("done", "read|errors:0");
      expectTrue(test, none == null, "nothing to say");
      let some = stacksFlashFor("done", "summarise|errors:3");
      expectText(test, if (some != null) { some.text } else { "" }, "3 document(s) did not read.");
      expectText(test, if (some != null) { some.level } else { "" }, "error");
      let crashed = stacksFlashFor("crashed", "compose|crashed");
      expectText(test, if (crashed != null) { crashed.text } else { "" }, "The compose pass crashed. What finished is saved.");
      let failed = stacksFlashFor("done", "compose|error:not_read");
      expectText(test, if (failed != null) { failed.text } else { "" }, "The compose pass failed: not_read");
      let ok = stacksFlashFor("done", "compose|ok");
      expectTrue(test, ok == null, "composed is silent");
    }

    test("relating says how many pairs, and how many could not be") { test =>
      let five = stacksFlashFor("done", "relate|related:5:0");
      expectText(test, if (five != null) { five.text } else { "" }, "Related 5 pairs.");
      expectText(test, if (five != null) { five.level } else { "" }, "info");
      let one = stacksFlashFor("done", "relate|related:1:0");
      expectText(test, if (one != null) { one.text } else { "" }, "Related 1 pair.");
      let some = stacksFlashFor("done", "relate|related:3:2");
      expectText(test, if (some != null) { some.text } else { "" }, "Related 3. 2 could not be: both documents have to have been read.");
    }

## Job bodies

The pass, then the run row finished with `<kind>|<result>`.

    test("the read job leaves the run done, with the count and the kind") { test =>
      let fx = stackOf(2);
      startRun(fx.db, fx.folder.id);
      let llm = llmFake([stepReply("one", "[]", "", ""), stepReply("two", "[1]", "", "")]);
      stacksJobRead(fx.db, llm, fx.me, fx.folder.id);
      expectText(test, runRow(fx.db, fx.folder.id), "done|2/2|read|errors:0");
      expectInt(test, stepsOf(fx.db, fx.folder).length, 2);
    }

    test("a job whose documents failed finishes with the error count") { test =>
      let fx = stackOf(2);
      startRun(fx.db, fx.folder.id);
      let llm = llmFakeScript([failing(400), failing(400)]);
      stacksJobRead(fx.db, llm, fx.me, fx.folder.id);
      expectText(test, runRow(fx.db, fx.folder.id), "done|0/2|read|errors:2");
      let flash = stacksFlashFor("done", "read|errors:2");
      expectText(test, if (flash != null) { flash.text } else { "" }, "2 document(s) did not read.");
    }

    test("the deepen job and the compose job report under their own kind") { test =>
      let fx = composeFixture();
      startRun(fx.db, fx.folder.id);
      let deep = llmFake([deepReply("a", "", 0, "", ""), deepReply("b", "", 0, "", ""), deepReply("c", "", 0, "", ""), deepReply("d", "", 0, "", "")]);
      stacksJobDeepen(fx.db, deep, fx.folder.id, false);
      expectText(test, runRow(fx.db, fx.folder.id), "done|4/4|deepen|errors:0");
      fx.db.exec("DELETE FROM runs", []);
      startRun(fx.db, fx.folder.id);
      let compose = llmFake([twoPartOutline(), partReply("a", ""), partReply("b", "")]);
      stacksJobCompose(fx.db, compose, fx.folder.id, "A backend");
      expectText(test, runRow(fx.db, fx.folder.id), "done|2/2|compose|ok");
    }

    test("the summarise, read-each and relate jobs finish the same way") { test =>
      let fx = stackOf(2);
      startRun(fx.db, fx.folder.id);
      stacksJobSummarise(fx.db, fx.me, fx.folder.id, false, fn (w: Work): String? throws Bubble { null });
      expectText(test, runRow(fx.db, fx.folder.id), "done|2/2|summarise|errors:0");
      fx.db.exec("DELETE FROM runs", []);
      startRun(fx.db, fx.folder.id);
      stacksJobReadEach(fx.db, fx.me, fx.folder.id, true, fn (w: Work): Void throws Bubble { });
      expectText(test, runRow(fx.db, fx.folder.id), "done|2/2|read_each|errors:2");
      fx.db.exec("DELETE FROM runs", []);
      startRun(fx.db, fx.folder.id);
      stacksJobRelate(fx.db, fx.folder.id, fn (h: StackRelateHooks): StackRelateOutcome throws Bubble { new StackRelateOutcome(4, 0, null) });
      expectText(test, runRow(fx.db, fx.folder.id), "done|0/0|relate|related:4:0");
    }

    test("a pass that bubbles leaves the run crashed under its kind") { test =>
      let fx = stackOf(1);
      startRun(fx.db, fx.folder.id);
      stacksJobRelate(fx.db, fx.folder.id, fn (h: StackRelateHooks): StackRelateOutcome throws Bubble { bubble() });
      expectText(test, runRow(fx.db, fx.folder.id), "crashed|0/0|relate|crashed");
      let flash = stacksFlashFor("crashed", "relate|crashed");
      expectText(test, if (flash != null) { flash.text } else { "" }, "The relate pass crashed. What finished is saved.");
    }

    test("progress written with no run row is dropped, not an error") { test =>
      let fx = stackOf(1);
      let llm = llmFake([stepReply("one", "[]", "", "")]);
      stacksJobRead(fx.db, llm, fx.me, fx.folder.id);
      expectText(test, runRow(fx.db, fx.folder.id), "none");
      expectInt(test, stepsOf(fx.db, fx.folder).length, 1);
    }
