# Tests for the editor's tools

Ported from `editor_tools_test` in `notes/tests.md` ("The system prompt names
tools by hand. For three releases it named two that did not exist, so every
promise to remember a ruling was empty. This pins prompt and tool surface
together"), then each of the eleven tools applied once against a fixture work,
and the edges the notes list. No model is called: tools are invoked directly.

    let { worksListCorrections } = import("works/src");
    let { FieldError } = import("core/src");
    let { LlmToolCall } = import("llm/src");

    let setupTools(db: Db): Work throws Bubble {
      let me = makeUser(db, "a@example.com");
      makeWork(db, me, "Draft", fixtureBody())
    }

A work with a read: two sections, beats with quotes, a spine, a thread, a
question, a connection between the beats, and an intent.

    let readWork(db: Db): Work throws Bubble {
      let me = makeUser(db, "a@example.com");
      let body = "# Chapter 1\n\nShe stood at the window. ${repeated("word ", 400)}\n\n# Chapter 2\n\nThe kettle went cold. ${repeated("word ", 400)}";
      let w0 = makeWork(db, me, "Draft", body);
      db.exec("UPDATE works SET intent = 'make them wait', first_impression = 'It holds still.' WHERE id = $1", [w0.id.toString()]);
      let work = worksGetById(db, w0.id);
      if (work != null) { work } else { bubble() }
    }

    let sectionTwo(db: Db, work: Work): Section throws Bubble {
      worksListSections(db, work.id)[1]
    }

    let seed(db: Db, work: Work): List<GraphNode> throws Bubble {
      let s1 = firstSection(db, work);
      let s2 = sectionTwo(db, work);
      let promise = addNode(db, work, s1, "beat", "The promise", "She waits at the window", "She stood at the window.");
      let payoff = addNode(db, work, s2, "beat", "The payoff", "The kettle goes cold", "The kettle went cold.");
      addNode(db, work, s1, "spine", "The wait", "Everything waits", null);
      addNode(db, work, s1, "thread", "The kettle", "carried", null);
      addNode(db, work, s1, "question", "Who is she waiting for?", null, null);
      worksLink(db, work.id, promise.id, payoff.id, "pays_off", 0, "the opening promise lands here");
      [promise, payoff]
    }

## The prompt and the tools agree

    test("the tool list names what the connections pass added") { test =>
      expectTrue(test, isIn(editorToolNames("owner"), "connections"), "connections");
      expectTrue(test, isIn(editorToolNames("owner"), "record_correction"), "record_correction");
      expectTrue(test, isIn(editorToolNames("owner"), "recall_sessions"), "recall_sessions");
    }

## record_correction

    test("a misread is stored and comes back from recall") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      let out = called(db, work, "record_correction", "{\"kind\":\"misread\",\"about\":\"Del leaves in ch 3\"}");
      expectText(test, jstr(out, "recorded"), "misread");
      expectText(test, jstr(out, "about"), "Del leaves in ch 3");
      expectText(test, jstr(out, "note"), "this will be in front of you next time");
      let recalled = called(db, work, "recall_sessions", "{}");
      let cs = jfield(recalled, "corrections");
      expectInt(test, jlen(cs), 1);
      expectText(test, jstr(jat(cs, 0), "kind"), "misread");
      expectText(test, jstr(jat(cs, 0), "about"), "Del leaves in ch 3");
    }

    test("a ruling keeps the writer's own words") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      called(db, work, "record_correction", "{\"kind\":\"ruling\",\"about\":\"the prologue should go\",\"ruling\":\"I want the prologue. It stays.\"}");
      let all = worksListCorrections(db, work.id);
      expectInt(test, all.length, 1);
      expectText(test, all[0].kind, "ruling");
      expectText(test, orEmpty(all[0].ruling), "I want the prologue. It stays.");
    }

    test("an unknown kind is refused rather than stored") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      let out = called(db, work, "record_correction", "{\"kind\":\"vibes\",\"about\":\"x\"}");
      expectHas(test, jstr(out, "error"), "not recorded");
      expectText(test, jstr(out, "error"), "not recorded: %{kind: [\"is invalid\"]}");
      expectInt(test, worksListCorrections(db, work.id).length, 0);
    }

    test("a missing field is named, fields alphabetical") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      let out = called(db, work, "record_correction", "{}");
      expectText(test, jstr(out, "error"), "not recorded: %{about: [\"can't be blank\"], kind: [\"can't be blank\"]}");
    }

    test("the section arrives as a number or a string, and is -1 when missing") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      called(db, work, "record_correction", "{\"kind\":\"ruling\",\"about\":\"a\",\"section\":2}");
      called(db, work, "record_correction", "{\"kind\":\"ruling\",\"about\":\"b\",\"section\":\"3rd\"}");
      called(db, work, "record_correction", "{\"kind\":\"ruling\",\"about\":\"c\"}");
      let all = worksListCorrections(db, work.id);
      expectInt(test, all.length, 3);
      expectInt(test, intOr(all[0].sectionOrdinal, 0), -1);
      expectInt(test, intOr(all[1].sectionOrdinal, 0), 3);
      expectInt(test, intOr(all[2].sectionOrdinal, 0), 2);
    }

    test("the error text is Ecto's inspect of the errors map") { test =>
      expectText(test, editorInspectErrors([new FieldError("kind", "is invalid")]), "%{kind: [\"is invalid\"]}");
      expectText(test, editorInspectErrors([new FieldError("kind", "is invalid"), new FieldError("about", "can't be blank")]),
        "%{about: [\"can't be blank\"], kind: [\"is invalid\"]}");
      expectText(test, editorInspectErrors([new FieldError("a", "x"), new FieldError("a", "y")]), "%{a: [\"x\", \"y\"]}");
    }

## recall_sessions

    test("finds what was said in an earlier conversation") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      let c = makeConvo(db, work);
      chatAppend(db, c.id, "user", "I am worried the prologue is doing nothing");
      chatAppend(db, c.id, "assistant", "The prologue introduces nobody who returns");
      let out = called(db, work, "recall_sessions", "{\"query\":\"prologue\"}");
      let talk = jfield(out, "earlier_talk");
      expectInt(test, jlen(talk), 2);
      expectText(test, jstr(jat(talk, 0), "who"), "assistant");
      expectText(test, jstr(jat(talk, 1), "who"), "user");
      expectText(test, jstr(jat(talk, 1), "said"), "I am worried the prologue is doing nothing");
    }

    test("no query returns the corrections alone") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      let c = makeConvo(db, work);
      chatAppend(db, c.id, "user", "I am worried the prologue is doing nothing");
      let out = called(db, work, "recall_sessions", "{}");
      expectInt(test, jlen(jfield(out, "earlier_talk")), 0);
      expectInt(test, jlen(jfield(out, "corrections")), 0);
    }

    test("corrections come newest first, with what they said and the section") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      called(db, work, "record_correction", "{\"kind\":\"misread\",\"about\":\"first\",\"section\":1}");
      called(db, work, "record_correction", "{\"kind\":\"ruling\",\"about\":\"second\",\"ruling\":\"mine\"}");
      let cs = jfield(called(db, work, "recall_sessions", "{}"), "corrections");
      expectText(test, jstr(jat(cs, 0), "about"), "second");
      expectText(test, jstr(jat(cs, 0), "they_said"), "mine");
      expectText(test, jstr(jat(cs, 1), "about"), "first");
      expectHas(test, calledRaw(db, work, "recall_sessions", "{}"), "\"they_said\":null");
    }

## connections

    test("reports the cross-section edges with their reasons") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      let out = called(db, work, "connections", "{}");
      expectInt(test, jlen(out), 1);
      expectText(test, jstr(jat(out, 0), "type"), "pays_off");
      expectText(test, jstr(jat(out, 0), "why"), "the opening promise lands here");
      expectText(test, jstr(jat(out, 0), "from"), "The promise");
      expectText(test, jstr(jat(out, 0), "to"), "The payoff");
      expectText(test, calledRaw(db, work, "connections", "{\"type\":\"tension\"}"),
        "{\"result\":\"no cross-section connections were drawn for this draft yet\"}");
    }

    test("a search term narrows connections by their words") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      expectInt(test, jlen(called(db, work, "connections", "{\"about\":\"payoff\"}")), 1);
      expectInt(test, jlen(called(db, work, "connections", "{\"about\":\"opening promise\"}")), 1);
      expectHas(test, calledRaw(db, work, "connections", "{\"about\":\"zebra\"}"), "no cross-section connections");
      expectInt(test, jlen(called(db, work, "connections", "{\"about\":\"\"}")), 1);
      expectInt(test, jlen(called(db, work, "connections", "{\"about\":\"a\"}")), 1);
    }

    test("an empty type keeps nothing, as the Elixir's truthiness did") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      expectHas(test, calledRaw(db, work, "connections", "{\"type\":\"\"}"), "no cross-section connections");
      expectInt(test, jlen(called(db, work, "connections", "{\"type\":\"pays_off\"}")), 1);
    }

## The other eight, once each

    test("search_manuscript finds nodes by their words and can be held to a layer") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      let out = called(db, work, "search_manuscript", "{\"query\":\"kettle\"}");
      expectInt(test, jlen(out), 2);
      let beats = called(db, work, "search_manuscript", "{\"query\":\"kettle\",\"type\":\"beat\"}");
      expectInt(test, jlen(beats), 1);
      expectText(test, jstr(jat(beats, 0), "type"), "beat");
      expectText(test, jstr(jat(beats, 0), "title"), "The payoff");
      expectText(test, jstr(jat(beats, 0), "quote"), "The kettle went cold.");
      expectText(test, jstr(jat(beats, 0), "note"), "The kettle goes cold");
      expectInt(test, jlen(called(db, work, "search_manuscript", "{\"query\":\"kettle\",\"type\":\"\"}")), 2);
      expectInt(test, jlen(called(db, work, "search_manuscript", "{\"query\":\"kettle\",\"type\":\"thread\"}")), 1);
    }

    test("search_manuscript says so when nothing matches") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      expectText(test, calledRaw(db, work, "search_manuscript", "{\"query\":\"zebra\"}"),
        "{\"result\":\"nothing matching that in the read\"}");
      expectText(test, calledRaw(db, work, "search_manuscript", "{}"),
        "{\"result\":\"nothing matching that in the read\"}");
    }

    test("find_exact reads the writer's own text and says where") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      let out = called(db, work, "find_exact", "{\"phrase\":\"The KETTLE went cold\"}");
      expectInt(test, jlen(out), 1);
      expectText(test, jstr(jat(out, 0), "section"), "Chapter 2");
      expectHas(test, jstr(jat(out, 0), "window"), "The kettle went cold.");
      expectHas(test, calledRaw(db, work, "find_exact", "{\"phrase\":\"a sentence nobody wrote\"}"),
        "that phrase does not appear in the draft");
      expectHas(test, calledRaw(db, work, "find_exact", "{}"), "find_exact needs a phrase");
    }

    test("read_passage returns a whole section by number, string or integer") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      let out = called(db, work, "read_passage", "{\"ordinal\":2}");
      expectText(test, jstr(out, "title"), "Chapter 2");
      expectHas(test, jstr(out, "text"), "The kettle went cold.");
      let viaString = called(db, work, "read_passage", "{\"ordinal\":\"2\"}");
      expectText(test, jstr(viaString, "title"), "Chapter 2");
      expectText(test, calledRaw(db, work, "read_passage", "{\"ordinal\":9}"), "{\"error\":\"no section with that number\"}");
      expectText(test, calledRaw(db, work, "read_passage", "{}"), "{\"error\":\"no section with that number\"}");
      expectText(test, calledRaw(db, work, "read_passage", "{\"ordinal\":\"two\"}"), "{\"error\":\"no section with that number\"}");
    }

    test("list_sections counts beats per section") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      let out = called(db, work, "list_sections", "{}");
      expectInt(test, jlen(out), 2);
      expectText(test, jstr(jat(out, 0), "title"), "Chapter 1");
      expectHas(test, calledRaw(db, work, "list_sections", "{}"), "\"beats\":1,\"ordinal\":1,\"title\":\"Chapter 1\"");
      expectHas(test, calledRaw(db, work, "list_sections", "{}"), "\"beats\":1,\"ordinal\":2,\"title\":\"Chapter 2\"");
    }

    test("list_sections on an unread draft says zero beats") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      expectHas(test, calledRaw(db, work, "list_sections", "{}"), "\"beats\":0");
    }

    test("section_beats gives one section's beats, or says why not") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      let out = called(db, work, "section_beats", "{\"ordinal\":1}");
      expectInt(test, jlen(out), 1);
      expectText(test, jstr(jat(out, 0), "title"), "The promise");
      expectText(test, calledRaw(db, work, "section_beats", "{\"ordinal\":7}"), "{\"error\":\"no section with that number\"}");
    }

    test("section_beats on a section nothing was read from") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      expectText(test, calledRaw(db, work, "section_beats", "{\"ordinal\":1}"),
        "{\"result\":\"that section has no beats — it may have failed to read\"}");
    }

    test("manuscript_spine and open_threads list their layer, or say it is empty") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      expectText(test, calledRaw(db, work, "manuscript_spine", "{}"),
        "{\"result\":\"the spine pass has not produced anything for this draft\"}");
      expectText(test, calledRaw(db, work, "open_threads", "{}"), "{\"result\":\"no threads were identified\"}");
      seed(db, work);
      let spine = called(db, work, "manuscript_spine", "{}");
      expectInt(test, jlen(spine), 1);
      expectText(test, jstr(jat(spine, 0), "title"), "The wait");
      expectText(test, jstr(jat(spine, 0), "type"), "spine");
      let threads = called(db, work, "open_threads", "{}");
      expectInt(test, jlen(threads), 1);
      expectText(test, jstr(jat(threads, 0), "title"), "The kettle");
    }

    test("stated_intent is the writer's own words, the impression and the open questions") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      let out = called(db, work, "stated_intent", "{}");
      expectText(test, jstr(out, "title"), "Draft");
      expectText(test, jstr(out, "stated_intent"), "make them wait");
      expectText(test, jstr(out, "first_impression"), "It holds still.");
      let qs = jfield(out, "questions");
      expectInt(test, jlen(qs), 1);
    }

    test("stated_intent without an intent is null, not an empty promise") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      expectText(test, calledRaw(db, work, "stated_intent", "{}"),
        "{\"first_impression\":null,\"questions\":[],\"stated_intent\":null,\"title\":\"Draft\"}");
    }

## The edges of the dispatch

    test("an unknown tool is an error the model can read") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      expectText(test, calledRaw(db, work, "write_the_next_scene", "{}"), "{\"error\":\"unknown tool\"}");
    }

    test("arguments that are not an object are treated as none") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      expectText(test, calledRaw(db, work, "list_sections", "[1,2]"), calledRaw(db, work, "list_sections", "{}"));
      expectText(test, calledRaw(db, work, "list_sections", "not json"), calledRaw(db, work, "list_sections", "{}"));
      expectHas(test, calledRaw(db, work, "search_manuscript", "\"query\""), "nothing matching");
      let none: String? = null;
      expectText(test, editorRunTool(db, work, "list_sections", none, "owner"), calledRaw(db, work, "list_sections", "{}"));
    }

    test("a tool call becomes the tool-role message the model is sent") { test =>
      let db = dbOpen(":memory:");
      let work = setupTools(db);
      let m = editorRunCall(db, work, new LlmToolCall("call_9", "manuscript_spine", "{}"), "owner");
      expectText(test, m.role, "tool");
      expectText(test, orEmpty(m.toolCallId), "call_9");
      expectHas(test, m.content, "the spine pass has not produced anything");
    }

    test("arg_int takes an integer, the leading integer of a string, or -1") { test =>
      expectInt(test, editorLeadingInt("12"), 12);
      expectInt(test, editorLeadingInt("3rd"), 3);
      expectInt(test, editorLeadingInt("-2"), -2);
      expectInt(test, editorLeadingInt("+4"), 4);
      expectInt(test, editorLeadingInt("abc"), -1);
      expectInt(test, editorLeadingInt(""), -1);
      expectInt(test, editorLeadingInt(" 3"), -1);
    }

## A visitor

    test("a visitor can read the draft through every safe tool") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      seed(db, work);
      for (let name of editorToolNames("public")) {
        let out = editorRunTool(db, work, name, "{\"query\":\"kettle\",\"phrase\":\"kettle\",\"ordinal\":1}", "public");
        expectLacks(test, out, "not available");
      }
    }

    test("public mode refuses the two unsafe tools by name and writes nothing") { test =>
      let db = dbOpen(":memory:");
      let work = readWork(db);
      let c = makeConvo(db, work);
      chatAppend(db, c.id, "user", "private: the prologue worries me");
      let refused = editorRunTool(db, work, "record_correction", "{\"kind\":\"misread\",\"about\":\"x\"}", "public");
      expectText(test, refused, "{\"error\":\"record_correction is not available on a public draft\"}");
      let recall = editorRunTool(db, work, "recall_sessions", "{\"query\":\"prologue\"}", "public");
      expectText(test, recall, "{\"error\":\"recall_sessions is not available on a public draft\"}");
      expectLacks(test, recall, "private");
      expectInt(test, worksListCorrections(db, work.id).length, 0);
    }
