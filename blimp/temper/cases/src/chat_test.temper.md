# Tests for the case chat

`case_read_test`'s chat assertions (`Cases.Chat.card/1` names documents rather
than lettering them; a connection from another case is marked as such), the
prompts test's entry for `case_chat`, and the call as `notes/web-public.md`
and the case-chat section of `notes/domain-accounts-links-stacks.md` specify
it: the messages in order, the options, the three outcomes. The model is
`llmFake`, which answers canned response bodies and records the requests.

    let { LlmClient, LlmMessage, llmFake, llmFakeScript, LlmFakeResponse, llmRequests, llmLastRequest } = import("llm/src");
    let { dbOpen } = import("db/src");

    let lastSent(test: Test, c: LlmClient): String { orNone(llmLastRequest(c)) }

    let sentCount(test: Test, c: LlmClient): Int { llmRequests(c).length }

    let reply(content: String): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"${content}\"},\"finish_reason\":\"stop\"}]}"
    }

    let nullReply(): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null},\"finish_reason\":\"stop\"}]}"
    }

    let turn(role: String, content: String): List<LlmMessage> {
      [new LlmMessage(role, content)]
    }

    let cardOf(fx: CasesFx, lead: Work): String throws Bubble {
      casesChatCard(fx.db, readingOf(fx, theCase(fx), lead))
    }

## The prompt

    let promptCheck(test: Test): Void {
      let p = casesChatSystem();
      expectTrue(test, startsWithText(p, "You are reading one document from a court case with every other document in that case\nlaid against it,"), "opens as the Elixir opens");
      expectHas(test, p, "You do NOT have the full text of anything. Do not\npretend to.");
      expectHas(test, p, "- Name documents the way the reader sees them: \"the dissent\", \"Gen. Sauer's argument\",\n  \"the concurrence\". Never by letter, and never by node number — those are plumbing.");
      expectHas(test, p, "- When a connection comes from a different case, say so. Two cases agreeing is a\n  different claim from two documents in one case agreeing.");
      expectHas(test, p, "WHAT YOU DO NOT DO\n- You do not write prose for any of these documents.");
      expectHas(test, p, "- You do not soften a real disagreement into \"both make good points\".");
      expectTrue(test, endsWithText(p, "- You are not giving legal advice, and you do not pretend the reading is authoritative.\n"), "ends with the heredoc's newline");
      expectInt(test, p.split("\n").length, 29);
    }

    test("the system prompt is the Elixir's, byte for byte") { test => promptCheck(test); }

    let passesCheck(test: Test): Void {
      let ps = casesChatPasses("deepseek-flash");
      expectInt(test, ps.length, 1);
      expectText(test, ps[0].id, "case_chat");
      expectText(test, ps[0].name, "Talking about a case");
      expectText(test, ps[0].model, "deepseek-flash");
      expectText(test, ps[0].runs, "per message, on a case being read");
      expectText(test, ps[0].produces, "answers about how the documents of a case sit together");
      expectText(test, ps[0].prompt, casesChatSystem());
    }

    test("the pass is listed with the others") { test => passesCheck(test); }

## The card

The context names documents rather than lettering them. The pairwise chat
labels its two documents A and B and the answers came back full of
"A:[4030]"; with four documents that is useless.

    let namesCheck(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let card = cardOf(fx, fx.op.work);
      expectHas(test, card, "Dissent");
      expectHas(test, card, "Argument: Counsel");
      expectLacks(test, card, "A:[");
      expectLacks(test, card, "B:[");
      expectLacks(test, card, "\nA: ");
      expectLacks(test, card, "Some v. Case");
    }

    test("the context names documents rather than lettering them") { test =>
      do { namesCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

    let exactCard(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let card = cardOf(fx, fx.op.work);
      let want = sysJoin([
        "# THE DOCUMENT BEING READ",
        "",
        "Opinion — ${fx.op.work.wordCount.toString()} words",
        "",
        "# READ AGAINST (2)",
        "",
        "- Dissent — ${fx.di.work.wordCount.toString()} words",
        "    tension between them.",
        "- Argument: Counsel — ${fx.ar.work.wordCount.toString()} words",
        "    answers between them.",
        "",
        "# THE CONNECTIONS (2)",
        "",
        "- Opinion — a beat in the opinion --tension--> Dissent — a beat in the dissent",
        "    They part on consent.",
        "- Opinion — a beat in the opinion --answers--> Argument: Counsel — a beat in the argument",
        "    The lectern already settled this.",
        "",
        "# MAP OF OPINION",
        "",
        "## beat",
        "- a beat in the opinion (§1)",
        "    \"A sentence long enough\"",
        "",
        "# MAP OF DISSENT",
        "",
        "## beat",
        "- a beat in the dissent (§1)",
        "    \"A sentence long enough\"",
        "",
        "# MAP OF ARGUMENT: COUNSEL",
        "",
        "## beat",
        "- a beat in the argument (§1)",
        "    \"A sentence long enough\"",
        "",
      ], "\n");
      expectText(test, card, want);
    }

    test("the card is laid out exactly as the model was tuned against it") { test =>
      do { exactCard(test); } orelse expectTrue(test, false, "bubbled");
    }

    let otherCaseCard(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let far = casesFar(fx);
      let card = cardOf(fx, fx.op.work);
      expectHas(test, card, "a different case");
      expectHas(test, card, "- Opinion — ${far.far.work.wordCount.toString()} words (from Other v. Matter, a different case)");
      expectHas(test, card, "\n    echoes between them.");
      expectHas(test, card, "# READ AGAINST (3)");
      expectHas(test, card, "# THE CONNECTIONS (3)");
      expectHas(test, card, "# MAP OF OPINION (from Other v. Matter, a different case)\n\n## beat\n- a beat in the opinion (§1)");
      expectHas(test, card, "- Opinion — a beat in the opinion --echoes--> Opinion — a beat in the opinion\n    The same Court on the same clause, three weeks apart.");
    }

    test("a connection from another case is marked as such in the context") { test =>
      do { otherCaseCard(test); } orelse expectTrue(test, false, "bubbled");
    }

    let letterCard(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let l = linkOf(linksGetOrCreate(fx.db, fx.op.work.id, fx.di.work.id).ok);
      linksSetStatus(fx.db, l, "linked", linksAttrsSummary("B answers A's open question."));
      fx.db.exec("UPDATE link_edges SET rationale = 'B answers A''s point.' WHERE link_id = $1", [l.id.toString()]);
      let card = cardOf(fx, fx.op.work);
      expectHas(test, card, "    Dissent answers Opinion's open question.");
      expectHas(test, card, "    Dissent answers Opinion's point.");
      expectLacks(test, card, "B answers");
    }

    test("a summary and a rationale arrive with their letters resolved") { test =>
      do { letterCard(test); } orelse expectTrue(test, false, "bubbled");
    }

    let noSummary(test: Test): Void throws Bubble {
      let fx = casesFixture();
      fx.db.exec("UPDATE links SET summary = NULL WHERE id = $1", [fx.opDi.id.toString()]);
      let card = cardOf(fx, fx.op.work);
      expectHas(test, card, "- Dissent — ${fx.di.work.wordCount.toString()} words\n- Argument: Counsel");
    }

    test("a source with no summary has no second line") { test =>
      do { noSummary(test); } orelse expectTrue(test, false, "bubbled");
    }

    let chatFromTheArgument(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let card = cardOf(fx, fx.ar.work);
      expectHas(test, card, "Argument: Counsel — ");
      expectHas(test, card, "# READ AGAINST (2)");
      expectHas(test, card, "- Opinion — a beat in the opinion --answers--> Argument: Counsel — a beat in the argument");
      expectHas(test, card, "- Dissent — a beat in the dissent --echoes--> Argument: Counsel — a beat in the argument");
      expectBefore(test, card, "# MAP OF ARGUMENT: COUNSEL", "# MAP OF OPINION");
      expectBefore(test, card, "# MAP OF OPINION", "# MAP OF DISSENT");
    }

    test("read from the argument, the lead's map comes first, then the sources in reading order") { test =>
      do { chatFromTheArgument(test); } orelse expectTrue(test, false, "bubbled");
    }

    let nodeLines(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let s = worksListSections(fx.db, fx.op.work.id)[0];
      let p = new NodeParams(fx.op.work.id, "thread", "a thread with no anchor");
      worksInsertNode(fx.db, p);
      let q = new NodeParams(fx.op.work.id, "beat", "a second beat");
      q.sectionId = s.id;
      q.quote = "  spaced\n\n out    quote  ";
      worksInsertNode(fx.db, q);
      let card = cardOf(fx, fx.op.work);
      expectHas(test, card, "\n## thread\n- a thread with no anchor\n");
      expectHas(test, card, "- a second beat (§1)\n    \" spaced out quote \"");
      expectBefore(test, card, "## beat\n- a beat in the opinion", "## thread");
    }

    test("a map groups nodes by type in key order, and puts the quote on its own line") { test =>
      do { nodeLines(test); } orelse expectTrue(test, false, "bubbled");
    }

    let longQuote(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let p = new NodeParams(fx.op.work.id, "beat", "a long one");
      p.quote = repeated("abcdefghij", 30);
      worksInsertNode(fx.db, p);
      let card = cardOf(fx, fx.op.work);
      expectHas(test, card, "- a long one\n    \"${repeated("abcdefghij", 16)}\"");
      expectLacks(test, card, repeated("abcdefghij", 17));
    }

    test("a quote is cut to its first 160 characters") { test =>
      do { longQuote(test); } orelse expectTrue(test, false, "bubbled");
    }

## The cited passages

    let citedCheck(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let edges = casesChatEdges(fx.db, r);
      expectInt(test, edges.length, 2);
      let tension = edges[0].ends.edge.id;
      let msg = casesChatCited(fx.db, r, [tension]);
      expectTrue(test, msg != null, "a message");
      if (msg != null) {
        expectText(test, msg.role, "system");
        expectTrue(test, startsWithText(msg.content, "The reader is pointing at these connections and wants to talk about them. Both passages are given in full — quote from them freely.\n\n"), "the preamble");
        expectHas(test, msg.content, "## TENSION\nWhy it was drawn: They part on consent.\n\n### Opinion — a beat in the opinion\n");
        expectHas(test, msg.content, "### Dissent — a beat in the dissent\n");
        expectHas(test, msg.content, "A sentence long enough to be a section.");
        expectLacks(test, msg.content, "ANSWERS");
        expectTrue(test, endsWithText(msg.content, "\n"), "each block ends with a newline");
      }
    }

    test("the cited message holds the passages behind the connections pointed at") { test =>
      do { citedCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

    let citedMany(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let edges = casesChatEdges(fx.db, r);
      let msg = casesChatCited(fx.db, r, [edges[0].ends.edge.id, edges[1].ends.edge.id]);
      if (msg != null) {
        expectHas(test, msg.content, "## TENSION\n");
        expectHas(test, msg.content, "## ANSWERS\n");
        expectHas(test, msg.content, "\n\n## ANSWERS");
        expectBefore(test, msg.content, "## TENSION", "## ANSWERS");
      } else {
        expectTrue(test, false, "a message");
      }
    }

    test("two cited connections are joined by a blank line") { test =>
      do { citedMany(test); } orelse expectTrue(test, false, "bubbled");
    }

    let citedNone(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      expectTrue(test, casesChatCited(fx.db, r, []) == null, "no ids, no message");
      expectTrue(test, casesChatCited(fx.db, r, [999999]) == null, "an id that is not an edge of this reading, no message");
      let others = fx.diAr.id;
      let edgeOfOther = linksStoreEdgesIds(fx);
      expectTrue(test, casesChatCited(fx.db, r, [edgeOfOther]) == null, "an edge of a link the opinion is not on is not cited");
      expectTrue(test, others > 0, "fixture sanity");
    }

    let linksStoreEdgesIds(fx: CasesFx): Int throws Bubble {
      let row = fx.db.one("SELECT id FROM link_edges WHERE link_id = $1", [fx.diAr.id.toString()]);
      if (row != null) { row.int("id") } else { -1 }
    }

    test("no ids, or ids that are not in the reading, make no message") { test =>
      do { citedNone(test); } orelse expectTrue(test, false, "bubbled");
    }

    let citedElsewhere(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let far = casesFar(fx);
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let edges = casesChatEdges(fx.db, r);
      expectInt(test, edges.length, 3);
      let msg = casesChatCited(fx.db, r, [edges[2].ends.edge.id]);
      if (msg != null) {
        expectHas(test, msg.content, "## ECHOES (from Other v. Matter, a different case)\nWhy it was drawn: The same Court on the same clause, three weeks apart.");
      } else {
        expectTrue(test, false, "a message");
      }
    }

    test("a cited connection from another case says so") { test =>
      do { citedElsewhere(test); } orelse expectTrue(test, false, "bubbled");
    }

    let underscores(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let l = linkOf(linksGetOrCreate(fx.db, fx.op.work.id, fx.di.work.id).ok);
      let stored = linksStoreEdges(fx.db, l, [proposal(fx.op.node.id, fx.di.node.id, "pays_off", "It is paid.")], linkerTypes());
      expectInt(test, stored.kept, 1);
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let edges = casesChatEdges(fx.db, r);
      let paid = edges[1].ends.edge.id;
      let msg = casesChatCited(fx.db, r, [paid]);
      if (msg != null) {
        expectHas(test, msg.content, "## PAYS OFF\n");
      } else {
        expectTrue(test, false, "a message");
      }
    }

    test("an edge type's underscores become spaces, in capitals") { test =>
      do { underscores(test); } orelse expectTrue(test, false, "bubbled");
    }

## The messages

    let messagesCheck(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let history = [
        new LlmMessage("user", "What did the dissent say?"),
        new LlmMessage("assistant", "It parted on consent."),
        new LlmMessage("user", "And the argument?"),
      ];
      let edges = casesChatEdges(fx.db, r);
      let ms = casesChatMessages(fx.db, r, history, [edges[0].ends.edge.id]);
      expectInt(test, ms.length, 6);
      expectText(test, ms[0].role, "system");
      expectText(test, ms[0].content, casesChatSystem());
      expectText(test, ms[1].role, "system");
      expectText(test, ms[1].content, casesChatCard(fx.db, r));
      expectText(test, ms[2].content, "What did the dissent say?");
      expectText(test, ms[3].role, "assistant");
      expectText(test, ms[4].content, "And the argument?");
      expectText(test, ms[5].role, "system");
      expectHas(test, ms[5].content, "The reader is pointing at these connections");
      let plain = casesChatMessages(fx.db, r, history, []);
      expectInt(test, plain.length, 5);
    }

    test("the messages are prompt, card, history, then the cited passages") { test =>
      do { messagesCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

## Asking

    let askCheck(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let llm = llmFake([reply("The dissent parted on consent, and the argument had already conceded it.")]);
      let res = casesChatAsk(fx.db, llm, r, turn("user", "Who conceded what?"), []);
      expectText(test, orNone(res.text), "The dissent parted on consent, and the argument had already conceded it.");
      expectTrue(test, res.error == null, "no error");
      let sent = lastSent(test, llm);
      expectHas(test, sent, "Who conceded what?");
      expectHas(test, sent, "THE DOCUMENT BEING READ");
      expectHas(test, sent, "You are reading one document from a court case");
      expectHas(test, sent, "\"temperature\":0.5");
      expectLacks(test, sent, "A:[");
      expectInt(test, sentCount(test, llm), 1);
    }

    test("asking returns the model's text") { test =>
      do { askCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

    let askOptions(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let llm = llmFake([reply("ok")]);
      casesChatAsk(fx.db, llm, r, turn("user", "Hello?"), []);
      let sent = lastSent(test, llm);
      expectHas(test, sent, "\"max_tokens\":28000");
      expectHas(test, sent, "\"reasoning_effort\":\"low\"");
      expectHas(test, sent, "\"model\":\"deepseek-flash\"");
      expectHas(test, sent, "\"role\":\"system\"");
    }

    test("low effort, temperature 0.5, 4000 tokens of answer (and the provider's headroom)") { test =>
      do { askOptions(test); } orelse expectTrue(test, false, "bubbled");
    }

    let askCited(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let edges = casesChatEdges(fx.db, r);
      let llm = llmFake([reply("ok")]);
      casesChatAsk(fx.db, llm, r, turn("user", "Why that one?"), [edges[0].ends.edge.id]);
      let sent = lastSent(test, llm);
      expectHas(test, sent, "The reader is pointing at these connections");
      expectHas(test, sent, "Why it was drawn: They part on consent.");
      expectBefore(test, sent, "Why that one?", "The reader is pointing at these connections");
    }

    test("cited passages go last in the request") { test =>
      do { askCited(test); } orelse expectTrue(test, false, "bubbled");
    }

    let emptyReply(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let a = casesChatAsk(fx.db, llmFake([reply("")]), r, turn("user", "Hm?"), []);
      expectTrue(test, a.text == null, "no text");
      expectText(test, orNone(a.error), "empty_reply");
      let b = casesChatAsk(fx.db, llmFake([nullReply()]), r, turn("user", "Hm?"), []);
      expectText(test, orNone(b.error), "empty_reply");
    }

    test("an empty reply is an error, not an empty answer") { test =>
      do { emptyReply(test); } orelse expectTrue(test, false, "bubbled");
    }

    let failures(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let llm = llmFakeScript([new LlmFakeResponse(401, "{\"error\":\"nope\"}")]);
      let res = casesChatAsk(fx.db, llm, r, turn("user", "Hello?"), []);
      expectTrue(test, res.text == null, "no text");
      expectHas(test, orNone(res.error), "http");
      expectHas(test, orNone(res.error), "401");
    }

    test("a failed call passes its error through") { test =>
      do { failures(test); } orelse expectTrue(test, false, "bubbled");
    }

    let throttled(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let busy = new LlmFakeResponse(429, "{}");
      let llm = llmFakeScript([busy, busy, busy]);
      let res = casesChatAsk(fx.db, llm, r, turn("user", "Hello?"), []);
      expectHas(test, orNone(res.error), "rate_limited");
    }

    test("a model that is too busy is an error after three tries") { test =>
      do { throttled(test); } orelse expectTrue(test, false, "bubbled");
    }

    let askLead(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let c = theCase(fx);
      let llm = llmFake([reply("Three tight paragraphs.")]);
      let history = [new LlmMessage("user", "First"), new LlmMessage("assistant", "Second")];
      let res = casesChatAskLead(fx.db, llm, c, fx.op.work.id, history, "Third?", []);
      expectText(test, orNone(res.text), "Three tight paragraphs.");
      let sent = lastSent(test, llm);
      expectBefore(test, sent, "First", "Second");
      expectBefore(test, sent, "Second", "Third?");
      let none = casesChatAskLead(fx.db, llmFake([reply("x")]), c, 0, [], "Hello?", []);
      expectText(test, orNone(none.error), "no_lead");
      expectTrue(test, none.text == null, "and no text");
    }

    test("asking by case and lead builds the reading and appends the question") { test =>
      do { askLead(test); } orelse expectTrue(test, false, "bubbled");
    }

    let forCase(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let c = theCase(fx);
      let lead = casesDefaultLead(c);
      expectTrue(test, lead != null, "there is a lead");
      if (lead != null) {
        let r = casesChatForCase(fx.db, c, lead.id);
        expectTrue(test, r != null, "a reading");
        if (r != null) { expectInt(test, r.sources.length, 2); }
      }
    }

    test("for_case is the reading, so the prompts page can list the chat with the others") { test =>
      do { forCase(test); } orelse expectTrue(test, false, "bubbled");
    }
