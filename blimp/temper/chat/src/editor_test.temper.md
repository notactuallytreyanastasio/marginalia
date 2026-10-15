# Tests for the editor assistant

The prompt, the cards, the messages of a turn, the tool loop against a
scripted model, and the whole question as the page asks it. No network: the
model is `llmFakeScript`.

    let { sysByteLength, sysUtf8Downcase, sysStringReplace } = import("sys/src");
    let { LlmConfig, llmFakeWithConfig, llmFakeConfig } = import("llm/src");
    let { accountsOwnerEmail } = import("accounts/src");
    let { worksGetById } = import("works/src");

    let fixture(db: Db): Work throws Bubble {
      let me = makeUser(db, "a@example.com");
      makeWork(db, me, "Draft", fixtureBody())
    }

    let reload(db: Db, work: Work): Work throws Bubble {
      let w = worksGetById(db, work.id);
      if (w != null) { w } else { bubble() }
    }

    let begins(s: String, prefix: String): Boolean {
      let parts = s.split(prefix);
      parts.length > 1 && parts[0] == ""
    }

    let ends(s: String, suffix: String): Boolean {
      let parts = s.split(suffix);
      parts.length > 1 && parts[parts.length - 1] == ""
    }

    let first(xs: List<LlmMessage>): LlmMessage { xs[0] }

    let contents(xs: List<LlmMessage>): String {
      sysJoin(xs.map { (m: LlmMessage): String => "${m.role}: ${m.content}" }, "\n--\n")
    }

## The system prompt

    test("the prompt is the 10,200-character one, verbatim") { test =>
      let p = editorSystemPrompt();
      expectInt(test, sysByteLength(p), 10221);
      expectTrue(test, begins(p, "You are Marginalia. You read one writer's manuscript with them.\n"), "opening");
      expectTrue(test, ends(p, "If they keep circling one chapter across four\nsessions, that is worth naming.\n"), "closing");
    }

    test("the prompt carries every section the product depends on") { test =>
      let p = editorSystemPrompt();
      for (let heading of [
        "YOU DO NOT WRITE THE BOOK", "NEVER INVENT THEIR TEXT", "WHAT THE GRAPH CONTAINS",
        "HOW YOU TALK", "THE DRAFT IS A DRAFT", "WHEN THEY SAY YOU ARE WRONG",
        "YOU HAVE BEEN HERE BEFORE",
      ]) {
        expectHas(test, p, heading);
      }
    }

    test("the editor, which talks about characters most, carries the pronoun rule") { test =>
      expectHas(test, sysUtf8Downcase(editorSystemPrompt()), "never assume anyone's gender");
    }

`call X` and `calling X` in the prompt name a tool; the first word after it,
with an optional backtick, if it is four letters or more.

    let wordAfter(part: String): String {
      var i = String.begin;
      while (part.hasIndex(i) && part[i] == 32) { i = part.next(i); }
      if (part.hasIndex(i)) {
        if (part[i] == 96) { i = part.next(i); }
      }
      let start = i;
      var going = true;
      while (going && part.hasIndex(i)) {
        let c = part[i];
        if ((c >= 97 && c <= 122) || c == 95) { i = part.next(i); } else { going = false; }
      }
      part.slice(start, i)
    }

    let calledNames(prompt: String): List<String> {
      let out = new ListBuilder<String>();
      let flat = sysStringReplace(prompt, "\n", " ");
      for (let needle of ["call ", "calling "]) {
        let parts = flat.split(needle);
        var k = 1;
        while (k < parts.length) {
          let w = wordAfter(parts[k]);
          if (sysByteLength(w) >= 4) { out.add(w); }
          k += 1;
        }
      }
      out.toList()
    }

    let isIn(xs: List<String>, x: String): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i] == x) { return true; }
        i += 1;
      }
      false
    }

    test("every tool the prompt tells the model to call actually exists") { test =>
      let names = editorToolNames("owner");
      let called = calledNames(editorSystemPrompt());
      expectTrue(test, called.length >= 2, "the prompt names tools after call");
      for (let c of called) {
        expectTrue(test, isIn(names, c), "the prompt says to call ${c} but there is no such tool");
      }
      for (let n of ["search_manuscript", "find_exact", "read_passage", "record_correction", "recall_sessions", "connections"]) {
        expectHas(test, editorSystemPrompt(), n);
      }
    }

## The tool surface

    test("eleven tools, in the Elixir's order") { test =>
      expectText(test, sysJoin(editorToolNames("owner"), ","),
        "search_manuscript,find_exact,read_passage,list_sections,section_beats,manuscript_spine,open_threads,connections,record_correction,recall_sessions,stated_intent");
    }

    test("a visitor is offered nine: the two that touch the owner's record are not") { test =>
      let names = editorToolNames("public");
      expectInt(test, names.length, 9);
      expectFalse(test, isIn(names, "record_correction"), "no record_correction");
      expectFalse(test, isIn(names, "recall_sessions"), "no recall_sessions");
      expectTrue(test, isIn(names, "connections"), "connections stays");
      expectText(test, sysJoin(editorUnsafeTools(), ","), "record_correction,recall_sessions");
    }

    test("every tool's parameters are a JSON object schema") { test =>
      for (let t of editorTools("owner")) {
        let tree = treeOf(t.parametersJson);
        expectText(test, jstr(tree, "type"), "object");
        expectTrue(test, t.description != "", "description of ${t.name}");
      }
    }

    test("the required parameters are the ones the Elixir required") { test =>
      for (let t of editorTools("owner")) {
        if (t.name == "search_manuscript") { expectHas(test, t.parametersJson, "\"required\":[\"query\"]"); }
        if (t.name == "find_exact") { expectHas(test, t.parametersJson, "\"required\":[\"phrase\"]"); }
        if (t.name == "read_passage") { expectHas(test, t.parametersJson, "\"required\":[\"ordinal\"]"); }
        if (t.name == "record_correction") { expectHas(test, t.parametersJson, "\"required\":[\"kind\",\"about\"]"); }
        if (t.name == "connections") { expectHas(test, t.parametersJson, "develops"); }
      }
    }

## The cards

    test("the manuscript card for a draft that has not been read and has no intent") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let sections = worksListSections(db, work.id).length;
      expectText(test, editorManuscriptCard(db, work),
        "THIS MANUSCRIPT\n\nTitle: Draft\nLength: ${work.wordCount.toString()} words in ${sections.toString()} sections\nRead so far: 0 beats, 0 spine nodes, 0 threads, 0 open questions\nThe writer did not state an intent.\n\n");
    }

    test("the manuscript card with an intent, an impression and a read") { test =>
      let db = dbOpen(":memory:");
      let w0 = fixture(db);
      db.exec("UPDATE works SET intent = 'make them wait', first_impression = 'It holds still.' WHERE id = $1", [w0.id.toString()]);
      let work = reload(db, w0);
      let s = firstSection(db, work);
      addNode(db, work, s, "beat", "b1", null, null);
      addNode(db, work, s, "beat", "b2", null, null);
      addNode(db, work, s, "spine", "sp", null, null);
      addNode(db, work, s, "thread", "t", null, null);
      addNode(db, work, s, "question", "q", null, null);
      let sections = worksListSections(db, work.id).length;
      expectText(test, editorManuscriptCard(db, work),
        "THIS MANUSCRIPT\n\nTitle: Draft\nLength: ${work.wordCount.toString()} words in ${sections.toString()} sections\nRead so far: 2 beats, 1 spine nodes, 1 threads, 1 open questions\nWhat the writer says it should do to a reader: make them wait\n\nThe first impression from the read:\nIt holds still.\n");
    }

    test("an empty intent is no intent") { test =>
      let db = dbOpen(":memory:");
      let w0 = fixture(db);
      db.exec("UPDATE works SET intent = '' WHERE id = $1", [w0.id.toString()]);
      expectHas(test, editorManuscriptCard(db, reload(db, w0)), "The writer did not state an intent.");
    }

    test("the focus card for a bare note on one section") { test =>
      let focus = new ChatFocus("beat", "The promise", null, null, [new ChatFocusSection(2, "Two", "Body two.")]);
      expectText(test, editorFocusCard(focus),
        "THE WRITER CLICKED A NOTE. This is what they are pointing at, and they expect you to\nalready have it. Do not go and search for it, and do not ask them which part they mean.\n\nNote (beat): The promise\n\n\nThe section it touches, in full:\n\n### Section 2: Two\nBody two.\n\nOpen on this. One or two sentences on what you see, then the question that moves it.\n");
    }

    test("the focus card with a body, a quote and two sections") { test =>
      let focus = new ChatFocus("pays_off", "A  —pays off→  B", "Because.", "The kettle went cold",
        [new ChatFocusSection(1, "One", "First."), new ChatFocusSection(3, "Three", "Third.")]);
      expectText(test, editorFocusCard(focus),
        "THE WRITER CLICKED A NOTE. This is what they are pointing at, and they expect you to\nalready have it. Do not go and search for it, and do not ask them which part they mean.\n\nNote (pays off): A  —pays off→  B\n\nBecause.\n\nAnchored to their line: \"The kettle went cold\"\n\nThe sections it touches, in full:\n\n### Section 1: One\nFirst.\n\n### Section 3: Three\nThird.\n\nOpen on this. One or two sentences on what you see, then the question that moves it.\n");
    }

    test("the cited card quotes each passage with where it came from") { test =>
      let cited = [new ChatCited("The kettle went cold", "One", 1), new ChatCited("Nobody moved", "Two", 2)];
      expectText(test, editorCitedCard(cited),
        "THE WRITER SELECTED THESE PASSAGES and attached them to the question below. They are\nverbatim from the draft — you may quote them back exactly without going to look them up.\nThis is what they are asking about. Answer about these, not about the draft in general.\n\nFrom section 1 (One):\n\"The kettle went cold\"\n\nFrom section 2 (Two):\n\"Nobody moved\"\n");
    }

## The messages of a turn

    test("system prompt, card, stance, the history, then the focus and the passages") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let focus = new ChatFocus("beat", "T", null, null, []);
      let history = [new ChatTurn("user", "hello"), new ChatTurn("assistant", "hi")];
      let ms = editorMessages(db, work, history, "bounce", focus, [new ChatCited("x", "S", 1)], "owner");
      expectInt(test, ms.length, 7);
      expectText(test, ms[0].content, editorSystemPrompt());
      expectHas(test, ms[1].content, "THIS MANUSCRIPT");
      expectHas(test, ms[2].content, "MODE: BOUNCE.");
      expectText(test, ms[3].role, "user");
      expectText(test, ms[3].content, "hello");
      expectText(test, ms[4].role, "assistant");
      expectHas(test, ms[5].content, "THE WRITER CLICKED A NOTE.");
      expectHas(test, ms[6].content, "THE WRITER SELECTED THESE PASSAGES");
      for (let m of [ms[0], ms[1], ms[2], ms[5], ms[6]]) { expectText(test, m.role, "system"); }
    }

    test("no focus and no passages add nothing; an unknown mode is read") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let ms = editorMessages(db, work, [], "nonsense", null, [], "owner");
      expectInt(test, ms.length, 3);
      expectHas(test, ms[2].content, "MODE: READ.");
      expectHas(test, editorMessages(db, work, [], null, null, [], "owner")[2].content, "MODE: READ.");
      expectHas(test, editorMessages(db, work, [], "provoke", null, [], "owner")[2].content, "MODE: PROVOKE.");
    }

    test("a visitor's turn carries the note that two tools are gone") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let owner = editorMessages(db, work, [], null, null, [], "owner");
      let visitor = editorMessages(db, work, [], null, null, [], "public");
      expectInt(test, visitor.length, owner.length + 1);
      expectHas(test, visitor[3].content, "THIS READER IS A VISITOR.");
      expectLacks(test, contents(owner), "VISITOR");
    }

## The loop

    test("a plain answer is one request and no effects") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let llm = script([replyText("It holds still.")]);
      let r = editorAsk(db, llm, work, [new ChatTurn("user", "what is it")], null, null, [], "owner");
      expectText(test, orEmpty(r.text), "It holds still.");
      expectTrue(test, r.error == null, "no error");
      expectInt(test, r.effects.length, 0);
      let sent = llmRequests(llm);
      expectInt(test, sent.length, 1);
      expectHas(test, sent[0], "\"tool_choice\":\"auto\"");
      expectHas(test, sent[0], "\"temperature\":0.7");
      expectHas(test, sent[0], "\"max_tokens\":26000");
      expectHas(test, sent[0], "\"name\":\"stated_intent\"");
      expectHas(test, sent[0], "\"reasoning_effort\":\"low\"");
    }

    test("a reply with no content is '(no response)'") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let llm = script(["{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null},\"finish_reason\":\"stop\"}]}"]);
      let r = editorAsk(db, llm, work, [], null, null, [], "owner");
      expectText(test, orEmpty(r.text), "(no response)");
    }

    test("the model calls report_section, which is not a tool here, then answers") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let llm = script([
        replyCalls([callJson("c1", "report_section", "{\"summary\":\"x\"}")]),
        replyText("Then I will answer without it."),
      ]);
      let r = editorAsk(db, llm, work, [new ChatTurn("user", "q")], null, null, [], "owner");
      expectText(test, orEmpty(r.text), "Then I will answer without it.");
      expectInt(test, r.effects.length, 1);
      expectText(test, r.effects[0].tool, "report_section");
      expectText(test, r.effects[0].resultJson, "{\"error\":\"unknown tool\"}");
      expectFalse(test, r.effects[0].ok, "not ok");
      let sent = llmRequests(llm);
      expectInt(test, sent.length, 2);
      expectHas(test, sent[1], "\"tool_call_id\":\"c1\"");
      expectHas(test, sent[1], "\"tool_calls\":[{\"function\":{\"arguments\":\"{\\\"summary\\\":\\\"x\\\"}\",\"name\":\"report_section\"},\"id\":\"c1\",\"type\":\"function\"}]");
      expectHas(test, sent[1], "\"content\":null,\"role\":\"assistant\"");
      expectHas(test, sent[1], "\"content\":\"{\\\"error\\\":\\\"unknown tool\\\"}\",\"role\":\"tool\",\"tool_call_id\":\"c1\"");
    }

    test("a tool that works hands its answer back to the model") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let llm = script([
        replyCalls([callJson("c1", "list_sections", "{}")]),
        replyText("One section, then."),
      ]);
      let r = editorAsk(db, llm, work, [], null, null, [], "owner");
      expectText(test, orEmpty(r.text), "One section, then.");
      expectInt(test, r.effects.length, 1);
      expectTrue(test, r.effects[0].ok, "ok");
      expectHas(test, r.effects[0].resultJson, "\"title\":\"Section 1\"");
      expectHas(test, llmRequests(llm)[1], "Section 1");
    }

    test("two calls in one reply are both applied, in order") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let llm = script([
        replyCalls([callJson("a", "manuscript_spine", "{}"), callJson("b", "stated_intent", "{}")]),
        replyText("done"),
      ]);
      let r = editorAsk(db, llm, work, [], null, null, [], "owner");
      expectInt(test, r.effects.length, 2);
      expectText(test, r.effects[0].tool, "manuscript_spine");
      expectText(test, r.effects[1].tool, "stated_intent");
      expectHas(test, llmRequests(llm)[1], "\"tool_call_id\":\"a\"");
      expectHas(test, llmRequests(llm)[1], "\"tool_call_id\":\"b\"");
    }

    test("seven rounds of tools and then an answer is fine") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let bodies = new ListBuilder<String>();
      var i = 0;
      while (i < 7) {
        bodies.add(replyCalls([callJson("c${i.toString()}", "list_sections", "{}")]));
        i += 1;
      }
      bodies.add(replyText("finally"));
      let llm = script(bodies.toList());
      let r = editorAsk(db, llm, work, [], null, null, [], "owner");
      expectText(test, orEmpty(r.text), "finally");
      expectInt(test, r.effects.length, 7);
      expectInt(test, llmRequests(llm).length, 8);
    }

    test("eight rounds of tools and the ninth is given up on, without a ninth request") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let bodies = new ListBuilder<String>();
      var i = 0;
      while (i < 10) {
        bodies.add(replyCalls([callJson("c${i.toString()}", "list_sections", "{}")]));
        i += 1;
      }
      let llm = script(bodies.toList());
      let r = editorAsk(db, llm, work, [], null, null, [], "owner");
      expectTrue(test, r.text == null, "no reply");
      expectText(test, orEmpty(r.error), "gave up after too many tool calls");
      expectInt(test, llmRequests(llm).length, 8);
      expectInt(test, r.effects.length, 8);
      expectInt(test, editorMaxRounds(), 8);
    }

    test("a model that stops mid-sentence is told to ask something narrower") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let r = editorAsk(db, script([replyCutOff()]), work, [], null, null, [], "owner");
      expectText(test, orEmpty(r.error), "the reply was cut off — try a narrower question");
    }

    test("no key, and a rate limit that outlasts three attempts, have their own words") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let base = llmFakeConfig();
      let keyless = llmFakeWithConfig(new LlmConfig(base.provider, "", base.endpoint, 0, 1000, ""), []);
      expectText(test, orEmpty(editorAsk(db, keyless, work, [], null, null, [], "owner").error),
        "no OpenAI key is configured on this deploy");
      let busy = llmFakeScript([new LlmFakeResponse(429, "slow down"), new LlmFakeResponse(429, "slow down"), new LlmFakeResponse(429, "slow down")]);
      expectText(test, orEmpty(editorAsk(db, busy, work, [], null, null, [], "owner").error),
        "OpenAI is rate limiting us; give it a moment");
    }

    test("any other failure is the error as the client names it") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let bad = llmFakeScript([new LlmFakeResponse(400, "no")]);
      let e = orEmpty(editorAsk(db, bad, work, [], null, null, [], "owner").error);
      expectHas(test, e, "http: status 400");
    }

    test("asking stores nothing; the caller persists the turns") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      makeConvo(db, work);
      editorAsk(db, script([replyText("x")]), work, [new ChatTurn("user", "q")], null, null, [], "owner");
      expectInt(test, rowCount(db, "SELECT count(*) AS n FROM messages"), 0);
    }

## A visitor's chat

    test("the public chat offers nine tools and says why two are gone") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let llm = script([replyText("hello")]);
      let r = editorPublicAsk(db, llm, work, [new ChatTurn("user", "hi")], null, null, []);
      expectText(test, orEmpty(r.text), "hello");
      let body = llmRequests(llm)[0];
      expectLacks(test, body, "\"name\":\"record_correction\"");
      expectLacks(test, body, "\"name\":\"recall_sessions\"");
      expectHas(test, body, "\"name\":\"find_exact\"");
      expectHas(test, body, "THIS READER IS A VISITOR.");
    }

    test("a visitor whose model calls the unsafe tools anyway is refused and nothing is written") { test =>
      let db = dbOpen(":memory:");
      let work = fixture(db);
      let llm = script([
        replyCalls([
          callJson("a", "record_correction", "{\"kind\":\"misread\",\"about\":\"x\"}"),
          callJson("b", "recall_sessions", "{\"query\":\"prologue\"}"),
          callJson("c", "stated_intent", "{}"),
        ]),
        replyText("ok"),
      ]);
      let r = editorPublicAsk(db, llm, work, [], null, null, []);
      expectInt(test, r.effects.length, 3);
      expectFalse(test, r.effects[0].ok, "record_correction refused");
      expectFalse(test, r.effects[1].ok, "recall_sessions refused");
      expectTrue(test, r.effects[2].ok, "stated_intent allowed");
      expectText(test, r.effects[0].resultJson, "{\"error\":\"record_correction is not available on a public draft\"}");
      expectInt(test, rowCount(db, "SELECT count(*) AS n FROM corrections"), 0);
    }

## The question as the page asks it

    test("a question is stored, answered with what was said before, and the answer is stored") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = makeConvo(db, work);
      chatAppend(db, convo.id, "user", "earlier question");
      chatAppend(db, convo.id, "assistant", "earlier answer");
      let llm = script([replyText("Here is what I see.")]);
      let r = chatEditorAsk(db, llm, scope, convo, "  what is the prologue doing  ", null);
      expectText(test, orEmpty(r.text), "Here is what I see.");
      let h = chatHistory(db, convo.id);
      expectInt(test, h.length, 4);
      expectText(test, h[2].content, "what is the prologue doing");
      expectText(test, h[2].role, "user");
      expectText(test, h[3].content, "Here is what I see.");
      expectText(test, h[3].role, "assistant");
      let body = llmRequests(llm)[0];
      expectHas(test, body, "\"content\":\"earlier answer\"");
      expectHas(test, body, "\"content\":\"what is the prologue doing\"");
    }

    test("only the last twenty turns are sent") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = makeConvo(db, work);
      askMany(db, convo, 30);
      let llm = script([replyText("ok")]);
      chatEditorAsk(db, llm, scope, convo, "one more", null);
      let body = llmRequests(llm)[0];
      expectLacks(test, body, "\"content\":\"question 1\"");
      expectLacks(test, body, "\"content\":\"question 11\"");
      expectHas(test, body, "\"content\":\"question 12\"");
      expectHas(test, body, "\"content\":\"one more\"");
    }

    test("a failed ask keeps the question and stores no reply") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = makeConvo(db, work);
      let r = chatEditorAsk(db, script([replyCutOff()]), scope, convo, "q", null);
      expectTrue(test, r.error != null, "error");
      let h = chatHistory(db, convo.id);
      expectInt(test, h.length, 1);
      expectText(test, h[0].role, "user");
    }

    test("an exhausted account asks nothing and spends nothing") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = makeConvo(db, work);
      askMany(db, convo, chatMessageLimit());
      let llm = script([replyText("never")]);
      let r = chatEditorAsk(db, llm, scope, convo, "one too many", null);
      expectTrue(test, r.quotaExhausted, "quota");
      expectTrue(test, r.text == null, "no reply");
      expectInt(test, llmRequests(llm).length, 0);
      expectInt(test, chatMessages(db, convo.id).length, chatMessageLimit());
    }

    test("the owner of the deploy is never exhausted") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, accountsOwnerEmail());
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = makeConvo(db, work);
      askMany(db, convo, chatMessageLimit() + 1);
      let r = chatEditorAsk(db, script([replyText("fine")]), scope, convo, "again", null);
      expectFalse(test, r.quotaExhausted, "not exhausted");
      expectText(test, orEmpty(r.text), "fine");
    }

    test("a visitor with no account cannot spend the owner's questions") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = makeConvo(db, work);
      let llm = script([replyText("never")]);
      let r = chatEditorAsk(db, llm, new Scope(null), convo, "let me in", null);
      expectTrue(test, r.quotaExhausted, "refused");
      expectInt(test, llmRequests(llm).length, 0);
      expectInt(test, chatHistory(db, convo.id).length, 0);
    }

    test("a blank question is no question") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = makeConvo(db, work);
      let llm = script([replyText("never")]);
      let r = chatEditorAsk(db, llm, scope, convo, "  \n ", null);
      expectTrue(test, r.text == null && r.error == null && !r.quotaExhausted, "nothing happened");
      expectInt(test, llmRequests(llm).length, 0);
    }

    test("the conversation's own stance is used unless the page names one") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = newConvo(db, work, "provoke");
      let llm = script([replyText("a"), replyText("b")]);
      chatEditorAsk(db, llm, scope, convo, "q1", null);
      chatEditorAsk(db, llm, scope, convo, "q2", "bounce");
      expectHas(test, llmRequests(llm)[0], "MODE: PROVOKE.");
      expectHas(test, llmRequests(llm)[1], "MODE: BOUNCE.");
    }

    test("a pinned thread asks with its paragraph as the focus") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let section = firstSection(db, work);
      let t = thread(db, work, section, "s1p1", "went cold");
      let focus = new ChatFocus("paragraph", "this paragraph", null, "went cold",
        [new ChatFocusSection(section.ordinal, section.title, section.body)]);
      let llm = script([replyText("holding the room still")]);
      let r = chatEditorAskWith(db, llm, scope, t, "what is this doing", t.mode, focus, []);
      expectText(test, orEmpty(r.text), "holding the room still");
      expectHas(test, llmRequests(llm)[0], "THE WRITER CLICKED A NOTE.");
      expectHas(test, llmRequests(llm)[0], "Anchored to their line: \\\"went cold\\\"");
      expectInt(test, chatHistory(db, t.id).length, 2);
      let pinned = chatThreadAt(db, work.id, "s1p1");
      expectInt(test, if (pinned != null) { pinned.messages } else { -1 }, 2);
    }

    test("passages the writer carried in reach the model once") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "Draft", fixtureBody());
      let convo = makeConvo(db, work);
      let llm = script([replyText("ok")]);
      chatEditorAskWith(db, llm, scope, convo, "about these", null, null, [new ChatCited("She stood at the window.", "Section 1", 1)]);
      expectHas(test, llmRequests(llm)[0], "From section 1 (Section 1):");
      expectHas(test, llmRequests(llm)[0], "She stood at the window.");
    }
