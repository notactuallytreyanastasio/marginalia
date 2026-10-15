# Tests for stacks: order, validation, readers

The assertions of `test/marginalia/stacks_test.exs`, `stack_leak_test.exs`,
`stack_to_draft_test.exs` and `summarise_folder_test.exs`, ported; then the
rules the spec states that those leave out (locate, leading numbers, the
fingerprints, inspect, the schemas, the guide, the statistics).

    let { Db, dbOpen } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Work, Section, worksListSections, worksListWorks } = import("works/src");
    let { Folder } = import("folders/src");
    let { sysJoin, sysStringReplace } = import("sys/src");
    let { JsonObject, parseJson } = import("std/json");

## The order a stack is read in

    test("a leading number in every title is the author saying the order") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let works = [makeDraft(db, me, "3. Third"), makeDraft(db, me, "1. First"), makeDraft(db, me, "2. Second")];
      let titles = stacksOrder(works).map { (w: Work): String => w.title };
      expectText(test, joined(titles), "1. First,2. Second,3. Third");
    }

    test("numbers well past ten still sort as numbers") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let works = [makeDraft(db, me, "10. Tenth"), makeDraft(db, me, "9. Ninth"), makeDraft(db, me, "1. First")];
      let titles = stacksOrder(works).map { (w: Work): String => stacksTake(w.title, 2) };
      expectText(test, joined(titles), "1.,9.,10");
    }

    test("without numbers it is insertion order, which is the only other true thing") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let a = makeDraft(db, me, "Alpha");
      let b = makeDraft(db, me, "Beta");
      let ids = stacksOrder([b, a]).map { (w: Work): Int => w.id };
      expectText(test, intsText(ids), intsText([a.id, b.id]));
    }

    test("a half-numbered stack falls back rather than guessing") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let a = makeDraft(db, me, "1. First");
      let b = makeDraft(db, me, "Untitled");
      let ids = stacksOrder([b, a]).map { (w: Work): Int => w.id };
      expectText(test, intsText(ids), intsText([a.id, b.id]));
    }

    test("duplicate numbers fall back too") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let a = makeDraft(db, me, "1. First");
      let b = makeDraft(db, me, "1. Also first");
      let ids = stacksOrder([b, a]).map { (w: Work): Int => w.id };
      expectText(test, intsText(ids), intsText([a.id, b.id]));
    }

    test("a title's leading number is digits, then ., ), : or -") { test =>
      expectInt(test, orMinus(stacksLeadingNumber("12. Twelve")), 12);
      expectInt(test, orMinus(stacksLeadingNumber("  7) Seven")), 7);
      expectInt(test, orMinus(stacksLeadingNumber("3: Three")), 3);
      expectInt(test, orMinus(stacksLeadingNumber("4 - Four")), 4);
      expectInt(test, orMinus(stacksLeadingNumber("5 Five")), -1);
      expectInt(test, orMinus(stacksLeadingNumber("Five 5.")), -1);
      expectInt(test, orMinus(stacksLeadingNumber("")), -1);
    }

    test("documents are the works filed in the folder, ordered, subfolders ignored") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A backend");
      let other = makeFolder(db, me, "Elsewhere");
      let second = makeFiled(db, me, f, "2. Second");
      let first = makeFiled(db, me, f, "1. First");
      makeFiled(db, me, other, "1. Not here");
      makeDraft(db, me, "3. Loose");
      let docs = stacksDocuments(db, me, f.id);
      expectText(test, joined(docs.map { (w: Work): String => w.title }), "1. First,2. Second");
      expectInt(test, docs[0].id, first.id);
      expectInt(test, docs[1].id, second.id);
    }

    test("another writer's folder has no documents") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let them = makeUser(db, "b@example.com");
      let f = makeFolder(db, me, "Mine");
      makeFiled(db, me, f, "1. One");
      expectInt(test, stacksDocuments(db, them, f.id).length, 0);
    }

## Where a quote sits

The haystack of the spec's examples, with a real newline between "test" and
"that".

    let locateHay(): String {
      "A Blimp closure can see its caller's locals. `eval.zig` has a test\nthat says so outright, and tail call elimination is written around it."
    }

    test("a quote that is there byte for byte comes back unchanged") { test =>
      expectText(test, orNone(stacksLocate("A Blimp closure", locateHay())), "A Blimp closure");
    }

    test("a quote across a line break comes back in the document's own wording") { test =>
      expectText(
        test,
        orNone(stacksLocate("has a test that says so outright", locateHay())),
        "has a test\nthat says so outright",
      );
    }

    test("words that are not there, or not in that order, are not located") { test =>
      expectText(test, orNone(stacksLocate("A Blimp closure cannot see anything", locateHay())), "<null>");
      expectText(test, orNone(stacksLocate("outright says so that", locateHay())), "<null>");
    }

    test("a blank quote is not located") { test =>
      expectText(test, orNone(stacksLocate("   \n ", locateHay())), "<null>");
      expectText(test, orNone(stacksLocate("", locateHay())), "<null>");
    }

    test("leading whitespace in the haystack does not shift the answer") { test =>
      expectText(test, orNone(stacksLocate("one two", "  \n one\n\n two three")), "one\n\n two");
    }

## Keeping only what the document says

    let validateBody(): String {
      "Blimp has no variadic call.\n\nSo the fix has to be a list, packed at the call site\nand unpacked in the handler."
    }

    test("a locatable pitfall quote is kept, with the document's own wording") { test =>
      let raw = rawOf("{'capability':'a rest formal becomes one parameter holding a list','requires':[1],'lesson':'Pack at the call site.','pitfall':'Do not try a variadic call.','pitfall_quote':'the fix has to be a list, packed at the call site and unpacked','excerpts':[]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectInt(test, v.dropped.length, 0);
      expectText(test, orNone(v.attrs.pitfall), "Do not try a variadic call.");
      expectHas(test, orEmpty(v.attrs.pitfallQuote), "\n");
      expectText(test, intsText(v.attrs.requires), "1");
      expectText(test, v.attrs.capability, "a rest formal becomes one parameter holding a list");
      expectText(test, v.attrs.lesson, "Pack at the call site.");
    }

    test("a pitfall the document does not state is dropped, not softened") { test =>
      let raw = rawOf("{'pitfall':'Blimp secretly supports varargs.','pitfall_quote':'Blimp secretly supports varargs.','requires':[],'excerpts':[]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectText(test, orNone(v.attrs.pitfall), "<null>");
      expectTrue(test, anyHas(v.dropped, "quote is not in the document"), "named");
      expectText(test, orNone(v.attrs.pitfallQuote), "<null>");
    }

    test("a located quote with no pitfall text keeps the quote and says nothing") { test =>
      let raw = rawOf("{'pitfall':'','pitfall_quote':'Blimp has no variadic call.','requires':[],'excerpts':[]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectText(test, orNone(v.attrs.pitfall), "<null>");
      expectText(test, orNone(v.attrs.pitfallQuote), "Blimp has no variadic call.");
      expectInt(test, v.dropped.length, 0);
    }

    test("requires must name an earlier document") { test =>
      let raw = rawOf("{'requires':[2,5,9,'x'],'excerpts':[]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectText(test, intsText(v.attrs.requires), "2");
      expectTrue(test, anyHas(v.dropped, "requires 5"), "5 is not earlier than 5");
      expectTrue(test, anyHas(v.dropped, "requires 9"), "9 is later");
      expectTrue(test, anyHas(v.dropped, "not a number"), "x");
      expectTrue(test, anyHas(v.dropped, "requires \"x\": not a number"), "inspect quotes the string");
    }

    test("requires are sorted and deduplicated, and a numeric string counts") { test =>
      let raw = rawOf("{'requires':[3,'1',3,2,0,-1],'excerpts':[]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectText(test, intsText(v.attrs.requires), "1,2,3");
      expectTrue(test, anyHas(v.dropped, "requires 0: not an earlier document"), "zero");
      expectTrue(test, anyHas(v.dropped, "requires -1: not an earlier document"), "negative");
    }

    test("an excerpt is the paragraph around the quote, from the document") { test =>
      let raw = rawOf("{'requires':[],'excerpts':[{'quote':'packed at the call site','caption':'the shape'}]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectInt(test, v.dropped.length, 0);
      expectInt(test, v.attrs.excerpts.length, 1);
      let x = v.attrs.excerpts[0];
      expectText(test, x.caption, "the shape");
      expectHas(test, x.text, "unpacked in the handler");
      expectHas(test, validateBody(), x.text);
    }

    test("an invented excerpt is dropped") { test =>
      let raw = rawOf("{'requires':[],'excerpts':[{'quote':'fn apply(args: List)','caption':'x'}]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectInt(test, v.attrs.excerpts.length, 0);
      expectTrue(test, anyHas(v.dropped, "is not in the document"), "named");
      expectTrue(test, anyHas(v.dropped, "excerpt: \"fn apply(args: List)\" is not in the document"), "quoted");
    }

    test("an excerpt with no quote is named") { test =>
      let raw = rawOf("{'requires':[],'excerpts':[{'quote':'  ','caption':'x'},'nope']}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectInt(test, v.attrs.excerpts.length, 0);
      expectInt(test, countHas(v.dropped, "excerpt: no quote"), 2);
    }

    test("at most two excerpts survive") { test =>
      let raw = rawOf("{'requires':[],'excerpts':[{'quote':'Blimp has no variadic','caption':'c'},{'quote':'packed at the call site','caption':'c'},{'quote':'unpacked in the handler','caption':'c'}]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectInt(test, v.dropped.length, 0);
      expectInt(test, v.attrs.excerpts.length, 2);
    }

    test("a long invented excerpt quote is cut to fifty characters in the message") { test =>
      let long = repeated("zq ", 40);
      let raw = rawOf("{'requires':[],'excerpts':[{'quote':'${long}','caption':'x'}]}");
      let v = stacksValidate(raw, validateBody(), 5);
      expectInt(test, v.dropped.length, 1);
      expectInt(test, stacksCodePoints(v.dropped[0]), 84);
    }

## The second pass, which can see forwards

The forward pass is told only what came before each step, so it cannot say
"step 9 walks this back". That claim is the one the second pass can make and
the one that can do damage, so it has to name a later step and quote that
step's own summary.

    let laterSteps(): List<StackStep> {
      [
        stacksSketch(8, "holes type-check", "Emit a hole operator.", null),
        stacksSketch(9, "casts are checked", "Replace the unchecked cast with a real test.", "The earlier cast compiled to nothing at all."),
      ]
    }

    test("a revision naming a later step and quoting it is kept") { test =>
      let raw = rawOf("{'mechanism':'It splits the body at the first exit and lifts the tail.','watch_for':'Step 9 leans on the cast being a real test.','revised_by':9,'revision':'Step 9 replaces the unchecked cast.','revision_quote':'Replace the unchecked cast with a real test.'}");
      let v = stacksValidateDeep(raw, laterSteps());
      expectInt(test, v.dropped.length, 0);
      expectInt(test, orMinus(v.attrs.revisedBy), 9);
      expectText(test, orNone(v.attrs.revisionQuote), "Replace the unchecked cast with a real test.");
      expectHas(test, orEmpty(v.attrs.watchFor), "Step 9");
      expectText(test, orNone(v.attrs.revision), "Step 9 replaces the unchecked cast.");
      expectText(test, orNone(v.attrs.mechanism), "It splits the body at the first exit and lifts the tail.");
    }

    test("a revision may quote the pitfall of the later step") { test =>
      let raw = rawOf("{'mechanism':'x','revised_by':9,'revision':'Step 9 fixes it.','revision_quote':'The earlier cast compiled to nothing'}");
      let v = stacksValidateDeep(raw, laterSteps());
      expectInt(test, orMinus(v.attrs.revisedBy), 9);
      expectInt(test, v.dropped.length, 0);
    }

    test("a revision pointing at a step that is not later is refused") { test =>
      let raw = rawOf("{'mechanism':'x','revised_by':3,'revision':'Step 3 changed it.','revision_quote':'anything'}");
      let v = stacksValidateDeep(raw, laterSteps());
      expectInt(test, orMinus(v.attrs.revisedBy), -1);
      expectTrue(test, anyHas(v.dropped, "step 3 is not a later step"), "named");
      expectTrue(test, anyHas(v.dropped, "revision: step 3 is not a later step"), "whole message");
    }

    test("a revision whose quote is not in that step's summary is refused") { test =>
      let raw = rawOf("{'mechanism':'x','revised_by':9,'revision':'Step 9 deletes the whole translator.','revision_quote':'Step 9 deletes the whole translator.'}");
      let v = stacksValidateDeep(raw, laterSteps());
      expectInt(test, orMinus(v.attrs.revisedBy), -1);
      expectText(test, orNone(v.attrs.revision), "<null>");
      expectTrue(test, anyHas(v.dropped, "quote is not in step 9"), "named");
      expectTrue(test, anyHas(v.dropped, "revision: quote is not in step 9's summary"), "whole message");
    }

    test("no revision is a normal answer") { test =>
      let raw = rawOf("{'mechanism':'x','watch_for':'','revised_by':0,'revision':'','revision_quote':''}");
      let v = stacksValidateDeep(raw, laterSteps());
      expectInt(test, orMinus(v.attrs.revisedBy), -1);
      expectText(test, orNone(v.attrs.watchFor), "<null>");
      expectInt(test, v.dropped.length, 0);
    }

    test("a revision with no text is none, whatever step it names") { test =>
      let raw = rawOf("{'mechanism':'x','revised_by':9,'revision':'','revision_quote':'Replace the unchecked cast with a real test.'}");
      let v = stacksValidateDeep(raw, laterSteps());
      expectInt(test, orMinus(v.attrs.revisedBy), -1);
      expectInt(test, v.dropped.length, 0);
    }

    test("an empty mechanism is the one thing this pass must not return") { test =>
      let v = stacksValidateDeep(rawOf("{'revised_by':0}"), laterSteps());
      expectText(test, orNone(v.attrs.mechanism), "<null>");
      expectTrue(test, anyHas(v.dropped, "mechanism"), "named");
      expectTrue(test, anyHas(v.dropped, "mechanism: empty"), "whole message");
    }

    test("the mechanism message comes after the revision messages") { test =>
      let raw = rawOf("{'revised_by':3,'revision':'r','revision_quote':'q'}");
      let v = stacksValidateDeep(raw, laterSteps());
      expectInt(test, v.dropped.length, 2);
      expectText(test, v.dropped[0], "revision: step 3 is not a later step");
      expectText(test, v.dropped[1], "mechanism: empty");
    }

    test("the last step has nothing after it and that is fine") { test =>
      let raw = rawOf("{'mechanism':'x','revised_by':4,'revision':'later','revision_quote':'q'}");
      let v = stacksValidateDeep(raw, []);
      expectInt(test, orMinus(v.attrs.revisedBy), -1);
      expectTrue(test, anyHas(v.dropped, "not a later step"), "named");
    }

## Composing the telling

Prose is not quote-checkable the way a claim is, so the thing that can be
checked is whether the composition actually carries every step. A telling that
covers four of ten has thrown the method away, and it is the failure least
likely to look like one.

    let fourSteps(): List<StackStep> {
      [
        stacksSketch(1, "does 1", null, null), stacksSketch(2, "does 2", null, null),
        stacksSketch(3, "does 3", null, null), stacksSketch(4, "does 4", null, null),
      ]
    }

    let part(heading: String, steps: String): String {
      "{'heading':'${heading}','prose':'Some prose.','steps':${steps},'turn':''}"
    }

    let headingsOf(v: StackStoryValidated): String {
      joined(v.attrs.movements.map { (m: StoryMovement): String => m.heading })
    }

    test("a telling covering every step keeps all of it") { test =>
      let raw = rawOf("{'title':'How it is built','opening':'op','closing':'cl','movements':[${part("Groundwork", "[1,2]")},${part("The hard part", "[3,4]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectInt(test, v.dropped.length, 0);
      expectInt(test, v.uncovered.length, 0);
      expectText(test, headingsOf(v), "Groundwork,The hard part");
      expectText(test, v.attrs.title, "How it is built");
      expectText(test, v.attrs.opening, "op");
      expectText(test, v.attrs.closing, "cl");
    }

    test("a step left out of every part is named, not waved through") { test =>
      let raw = rawOf("{'movements':[${part("Only the start", "[1,2]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectText(test, intsText(v.uncovered), "3,4");
      expectTrue(test, anyHas(v.dropped, "appear in no part: 3, 4"), "named");
      expectText(test, v.dropped[0], "2 step(s) appear in no part: 3, 4");
    }

    test("a step told twice is refused the second time") { test =>
      let raw = rawOf("{'movements':[${part("A", "[1,2]")},${part("B", "[2,3,4]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectInt(test, v.uncovered.length, 0);
      expectTrue(test, anyHas(v.dropped, "step 2 is told twice"), "named");
      expectTrue(test, anyHas(v.dropped, "part \"B\": step 2 is told twice"), "whole message");
      expectText(test, sysJoin(v.attrs.movements.map { (m: StoryMovement): String => intsText(m.steps) }, "|"), "1,2|3,4");
    }

    test("a step that is not in this stack is refused") { test =>
      let raw = rawOf("{'movements':[${part("A", "[1,2,3,4,9]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectTrue(test, anyHas(v.dropped, "step 9 is not in this stack"), "named");
      expectText(test, intsText(v.attrs.movements[0].steps), "1,2,3,4");
    }

    test("parts are ordered by the work, not by what came back") { test =>
      let raw = rawOf("{'movements':[${part("Later", "[3,4]")},${part("Earlier", "[1,2]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectInt(test, v.dropped.length, 0);
      expectInt(test, v.uncovered.length, 0);
      expectText(test, headingsOf(v), "Earlier,Later");
    }

    test("a part with no prose is not a part") { test =>
      let raw = rawOf("{'movements':[{'heading':'Empty','prose':'  ','steps':[1,2]},${part("Real", "[3,4]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectInt(test, v.attrs.movements.length, 1);
      expectText(test, intsText(v.uncovered), "1,2");
      expectTrue(test, anyHas(v.dropped, "no prose"), "named");
      expectTrue(test, anyHas(v.dropped, "a part with no prose"), "whole message");
    }

    test("a part with no heading is not a part, and its steps stay free") { test =>
      let raw = rawOf("{'movements':[{'heading':' ','prose':'Prose.','steps':[1,2]},${part("Real", "[1,2,3,4]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectTrue(test, anyHas(v.dropped, "a part with no heading"), "named");
      expectInt(test, v.attrs.movements.length, 1);
      expectText(test, intsText(v.attrs.movements[0].steps), "1,2,3,4");
      expectInt(test, v.uncovered.length, 0);
    }

    test("a step that is not a number is named") { test =>
      let raw = rawOf("{'movements':[{'heading':'A','prose':'P','steps':[1,'x',2.5,null,3,4]}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectTrue(test, anyHas(v.dropped, "part \"A\": \"x\" is not a step number"), "string");
      expectTrue(test, anyHas(v.dropped, "part \"A\": 2.5 is not a step number"), "float");
      expectTrue(test, anyHas(v.dropped, "part \"A\": nil is not a step number"), "null");
      expectText(test, intsText(v.attrs.movements[0].steps), "1,3,4");
      expectText(test, intsText(v.uncovered), "2");
    }

    test("a step repeated within one part is accepted twice") { test =>
      let raw = rawOf("{'movements':[${part("A", "[1,1,2,3,4]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectText(test, intsText(v.attrs.movements[0].steps), "1,1,2,3,4");
      expectInt(test, v.dropped.length, 0);
    }

    test("the turn is kept, trimmed") { test =>
      let raw = rawOf("{'movements':[{'heading':'A','prose':'P','steps':[1,2,3,4],'turn':'  It surprised me.  '}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectText(test, v.attrs.movements[0].turn, "It surprised me.");
    }

    test("a part that is not an object is named and dropped") { test =>
      let raw = rawOf("{'movements':['nope',${part("A", "[1,2,3,4]")}]}");
      let v = stacksValidateStory(raw, fourSteps());
      expectInt(test, v.attrs.movements.length, 1);
      expectTrue(test, anyHas(v.dropped, "a part with no heading"), "named");
    }

    test("completeness is a property the story carries") { test =>
      expectFalse(test, stacksSketchStory([3]).isComplete(), "a step is left out");
      expectTrue(test, stacksSketchStory([]).isComplete(), "nothing is left out");
    }

## The model leaking its own markup into the answer

From the composed telling of a 111-step stack: one part of eleven wrote
12,668 good characters, then emitted a tool-call preamble and the literal word
"placeholder", and stopped. It validated clean, was stored, and went out on the
public page, where it read as a code block somebody had failed to format. The
real thing, fullwidth pipes and all (U+FF5C).

    let bar(): String { "\u{FF5C}" }

    let leak(): String {
      "<${bar()}${bar()}DSML${bar()}${bar()} calls>\n<${bar()}${bar()}DSML${bar()}${bar()} invoke name=\"write_part\">\n<${bar()}${bar()}DSML${bar()}${bar()} parameter name=\"prose\" string=\"true\">placeholder"
    }

    let leakJson(): String {
      sysStringReplace(sysStringReplace(leak(), "\"", "\\\""), "\n", "\\n")
    }

    test("ordinary prose is left exactly alone") { test =>
      let text = "The backend declares Blimp's syntax in one out-grammar file.";
      let s = stacksScrub(text, "part");
      expectText(test, s.text, text);
      expectText(test, orNone(s.leak), "<null>");
    }

    test("prose that mentions angle brackets or pipes is not a false positive") { test =>
      let text = "A generic `List<Int>` and a shell pipe `a | b` are both ordinary prose.";
      let s = stacksScrub(text, "part");
      expectText(test, s.text, text);
      expectText(test, orNone(s.leak), "<null>");
    }

    test("the good prose is kept and the leak is cut") { test =>
      let s = stacksScrub("Real prose here.\n\n${leak()}", "part \"Five\"");
      expectText(test, s.text, "Real prose here.");
      expectLacks(test, s.text, "DSML");
      expectLacks(test, s.text, "placeholder");
      expectHas(test, orEmpty(s.leak), "leaked its own tool-call markup");
      expectHas(test, orEmpty(s.leak), "part \"Five\"");
      expectText(test, orNone(s.leak), "part \"Five\": the model leaked its own tool-call markup; the text was cut there");
    }

    test("twelve thousand good characters are not thrown away over a corrupt tail") { test =>
      let long = repeated("real sentence. ", 800);
      let s = stacksScrub("${long}${leak()}", "part");
      expectTrue(test, stacksCodePoints(s.text) > 11000, "most of it kept");
      expectTrue(test, s.leak != null, "reported");
    }

    test("a leak with nothing before it leaves nothing behind") { test =>
      let s = stacksScrub(leak(), "part");
      expectText(test, s.text, "");
      expectTrue(test, s.leak != null, "reported");
    }

    test("a leaking part is cut and the cut is reported, not swallowed") { test =>
      let steps = [stacksSketch(1, null, null, null), stacksSketch(2, null, null, null)];
      let raw = rawOf("{'title':'A telling','opening':'The opening.','closing':'The closing.','movements':[{'heading':'One','prose':'Good prose.\\n\\n${leakJson()}','steps':[1,2]}]}");
      let v = stacksValidateStory(raw, steps);
      expectInt(test, v.uncovered.length, 0);
      expectInt(test, v.attrs.movements.length, 1);
      expectText(test, v.attrs.movements[0].prose, "Good prose.");
      expectLacks(test, v.attrs.movements[0].prose, "DSML");
      expectTrue(test, anyHas(v.dropped, "leaked its own tool-call markup"), "the page renders dropped, so a silent cut is the one thing this must not do");
      expectTrue(test, anyHas(v.dropped, "part \"One\": the model leaked"), "labelled");
    }

    test("a leak in the opening or the closing is caught too") { test =>
      let steps = [stacksSketch(1, null, null, null)];
      let raw = rawOf("{'title':'A telling','opening':'Fine so far. ${leakJson()}','closing':'Also fine. ${leakJson()}','movements':[{'heading':'One','prose':'Prose.','steps':[1]}]}");
      let v = stacksValidateStory(raw, steps);
      expectLacks(test, v.attrs.opening, "DSML");
      expectLacks(test, v.attrs.closing, "DSML");
      expectText(test, v.attrs.opening, "Fine so far.");
      expectInt(test, countHas(v.dropped, "leaked"), 2);
      expectTrue(test, hasText(v.dropped[0], "opening: "), "opening first");
      expectTrue(test, hasText(v.dropped[1], "closing: "), "then the closing");
    }

    test("a clean telling reports nothing") { test =>
      let steps = [stacksSketch(1, null, null, null)];
      let raw = rawOf("{'title':'A telling','opening':'The opening.','closing':'The closing.','movements':[{'heading':'One','prose':'Prose.','steps':[1]}]}");
      let v = stacksValidateStory(raw, steps);
      expectInt(test, countHas(v.dropped, "leaked"), 0);
      expectInt(test, v.dropped.length, 0);
    }

    test("a leaking capability or lesson is cut and reported") { test =>
      let body = "The document body, which contains the quote.";
      let raw = rawOf("{'capability':'A real capability. ${leakJson()}','lesson':'Do the thing. ${leakJson()}','requires':[],'pitfall':'','pitfall_quote':'','excerpts':[]}");
      let v = stacksValidate(raw, body, 2);
      expectLacks(test, v.attrs.capability, "DSML");
      expectLacks(test, v.attrs.lesson, "DSML");
      expectText(test, v.attrs.capability, "A real capability.");
      expectInt(test, countHas(v.dropped, "leaked"), 2);
      expectTrue(test, hasText(v.dropped[0], "capability: "), "capability first");
      expectTrue(test, hasText(v.dropped[1], "lesson: "), "then the lesson");
    }

## inspect

    test("a string is shown the way the messages quote it") { test =>
      expectText(test, stacksInspect("plain"), "\"plain\"");
      expectText(test, stacksInspect("say \"hi\""), "\"say \\\"hi\\\"\"");
      expectText(test, stacksInspect("a\nb"), "\"a\\nb\"");
      expectText(test, stacksInspect("a\\b"), "\"a\\\\b\"");
      expectText(test, stacksInspect(""), "\"\"");
    }

## Fingerprints

    test("a work's fingerprint is the sha256 of its text, lowercase hex") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeDraft(db, me, "1. One");
      let f = stacksFingerprint(db, w.id);
      expectInt(test, stacksCodePoints(f), 64);
      expectText(test, f, stacksFingerprintOfText(stacksTextOf(db, w.id)));
      expectText(test, stacksFingerprintOfText(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    }

    test("a document's text is its sections joined and cut at fourteen thousand characters") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeDraftWith(db, me, "Long", "# Long\n\n${repeated("word ", 4000)}");
      expectInt(test, stacksCodePoints(stacksTextOf(db, w.id)), 14000);
      let short = makeDraft(db, me, "Short");
      expectTrue(test, stacksCodePoints(stacksTextOf(db, short.id)) < 14000, "short stays whole");
    }

    test("a step is current while the document is as it was read, and stale after an edit") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "S");
      let w = makeFiled(db, me, f, "1. One");
      let step = makeStep(db, f.id, w.id, 1, "does one", []);
      expectFalse(test, stacksStepCurrent(db, step), "no fingerprint yet");
      db.exec("UPDATE stack_steps SET fingerprint = $1 WHERE id = $2", [stacksFingerprint(db, w.id), step.id.toString()]);
      let again = stacksGetStep(db, f.id, 1);
      expectTrue(test, again != null, "found");
      expectTrue(test, stacksStepCurrent(db, orBlank(again)), "current");
      db.exec("UPDATE sections SET body = body || ' and more' WHERE work_id = $1", [w.id.toString()]);
      expectTrue(test, stacksIsStale(db, orBlank(again)), "stale now");
    }

    let orBlank(s: StackStep?): StackStep {
      if (s != null) { s } else { stacksSketch(0, null, null, null) }
    }

    test("the story fingerprint covers ordinal, capability, lesson, mechanism, pitfall and revised_by") { test =>
      let a = stacksSketch(1, "cap", "lesson", "pit");
      let want = stacksFingerprintOfText("1|cap|lesson||pit|");
      expectText(test, stacksStoryFingerprint([a]), want);
      let deeper = new StackStep(0, 0, 0, 1, "cap", [], "lesson", "pit", null, [], null, [], "how", null, 3, null, null, [], null, "", "");
      expectText(test, stacksStoryFingerprint([deeper]), stacksFingerprintOfText("1|cap|lesson|how|pit|3"));
      expectText(test, stacksStoryFingerprint([]), stacksFingerprintOfText(""));
      let b = stacksSketch(2, "two", null, null);
      expectText(test, stacksStoryFingerprint([stacksSketch(1, "one", null, null), b]), stacksFingerprintOfText("1|one||||\n2|two||||"));
    }

## The guide

    test("links run both ways, and the ends know they are ends") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A backend");
      let w1 = makeFiled(db, me, f, "1. One");
      let w2 = makeFiled(db, me, f, "2. Two");
      let w3 = makeFiled(db, me, f, "3. Three");
      makeStep(db, f.id, w1.id, 1, "does thing 1", []);
      makeStep(db, f.id, w2.id, 2, "does thing 2", [1]);
      makeStep(db, f.id, w3.id, 3, "does thing 3", [1, 2]);
      let g = stacksGuide(db, f.id);
      expectInt(test, g.length, 3);
      let one = g[0];
      let two = g[1];
      let three = g[2];
      expectTrue(test, one.previous == null, "nothing before the first");
      expectInt(test, one.requires.length, 0);
      expectText(test, intsText(one.requiredBy.map { (s: StackStep): Int => s.ordinal }), "2,3");
      let beforeTwo = two.previous;
      expectInt(test, if (beforeTwo != null) { beforeTwo.ordinal } else { -1 }, 1);
      expectText(test, intsText(two.requires.map { (s: StackStep): Int => s.ordinal }), "1");
      expectTrue(test, three.next == null, "nothing after the last");
      expectText(test, intsText(three.requires.map { (s: StackStep): Int => s.ordinal }), "1,2");
      expectInt(test, three.requiredBy.length, 0);
    }

    test("a requirement on a step that is not there is left out of the guide") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A backend");
      let w1 = makeFiled(db, me, f, "1. One");
      makeStep(db, f.id, w1.id, 1, "does thing 1", [4]);
      let g = stacksGuide(db, f.id);
      expectInt(test, g[0].requires.length, 0);
    }

    test("steps come back by ordinal, with their work, and one is found by ordinal") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A backend");
      let w1 = makeFiled(db, me, f, "1. One");
      let w2 = makeFiled(db, me, f, "2. Two");
      makeStep(db, f.id, w2.id, 2, "does thing 2", []);
      makeStep(db, f.id, w1.id, 1, "does thing 1", []);
      let steps = stacksListSteps(db, f.id);
      expectText(test, intsText(steps.map { (s: StackStep): Int => s.ordinal }), "1,2");
      let firstWork = steps[0].work;
      expectText(test, orNone(if (firstWork != null) { firstWork.title } else { null }), "1. One");
      let two = stacksGetStep(db, f.id, 2);
      expectTrue(test, two != null, "found");
      expectText(test, orNone(if (two != null) { two.capability } else { null }), "does thing 2");
      expectTrue(test, stacksGetStep(db, f.id, 3) == null, "no step 3");
      expectInt(test, stacksSteps(db, f).length, 2);
    }

    test("steps by work: one map for the whole tree") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let them = makeUser(db, "b@example.com");
      let f = makeFolder(db, me, "A backend");
      let w1 = makeFiled(db, me, f, "1. One");
      let w2 = makeFiled(db, me, f, "2. Two");
      let theirF = makeFolder(db, them, "Theirs");
      let theirW = makeFiled(db, them, theirF, "1. Theirs");
      makeStep(db, f.id, w1.id, 1, "a", []);
      makeStep(db, f.id, w2.id, 2, "b", []);
      makeStep(db, theirF.id, theirW.id, 1, "c", []);
      let m = stacksStepsByWork(db, me);
      expectTrue(test, m.has(w1.id) && m.has(w2.id), "mine are there");
      expectFalse(test, m.has(theirW.id), "theirs are not");
      expectInt(test, m.get(w2.id).ordinal, 2);
      expectInt(test, m.get(w2.id).folderId, f.id);
    }

## Statistics

    test("stats count what is there") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A backend");
      makeFiled(db, me, f, "1. One");
      let st = stacksStats(db, me, f.id);
      expectInt(test, st.documents, 1);
      expectInt(test, st.read, 0);
    }

    let summaryFolder(db: Db, me: Scope): Folder throws Bubble {
      let f = makeFolder(db, me, "Imported");
      makeFiled(db, me, f, "1. One");
      makeFiled(db, me, f, "2. Two");
      makeFiled(db, me, f, "3. Three");
      f
    }

    let summarised(db: Db, workId: Int, text: String): Void throws Bubble {
      db.exec(
        "INSERT INTO document_summaries (work_id, summary, fingerprint) VALUES ($1, $2, 'f')",
        [workId.toString(), text],
      );
    }

    test("the count is part of the folder's stats") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = summaryFolder(db, me);
      expectInt(test, stacksStats(db, me, f.id).summarised, 0);
      let docs = stacksDocuments(db, me, f.id);
      summarised(db, docs[0].id, "what it says");
      summarised(db, docs[1].id, "what it says");
      let st = stacksStats(db, me, f.id);
      expectInt(test, st.documents, 3);
      expectInt(test, st.summarised, 2);
      expectInt(test, st.documents - st.summarised, 1);
    }

    test("a row with an empty summary does not count as summarised") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = summaryFolder(db, me);
      summarised(db, stacksDocuments(db, me, f.id)[0].id, "");
      expectInt(test, stacksStats(db, me, f.id).summarised, 0);
    }

    test("the count the page shows is what would actually be worked on") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = summaryFolder(db, me);
      summarised(db, stacksDocuments(db, me, f.id)[0].id, "what it says");
      let st = stacksStats(db, me, f.id);
      expectInt(test, st.documents - st.summarised, 2);
    }

    test("related counts only pairs with both ends inside the folder") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = summaryFolder(db, me);
      let docs = stacksDocuments(db, me, f.id);
      expectInt(test, stacksStats(db, me, f.id).related, 0);
      db.exec("INSERT INTO links (a_work_id, b_work_id) VALUES ($1, $2)", [docs[0].id.toString(), docs[1].id.toString()]);
      expectInt(test, stacksStats(db, me, f.id).related, 1);
      let outside = makeDraft(db, me, "Elsewhere");
      db.exec("INSERT INTO links (a_work_id, b_work_id) VALUES ($1, $2)", [docs[0].id.toString(), outside.id.toString()]);
      expectInt(test, stacksStats(db, me, f.id).related, 1);
    }

    test("an empty folder has no related pairs rather than raising") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let empty = makeFolder(db, me, "Empty");
      let st = stacksStats(db, me, empty.id);
      expectInt(test, st.related, 0);
      expectInt(test, st.documents, 0);
      expectInt(test, st.summarised, 0);
    }

    test("mapped counts documents with a graph, not documents with a step") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = summaryFolder(db, me);
      let docs = stacksDocuments(db, me, f.id);
      let st = stacksStats(db, me, f.id);
      expectInt(test, st.documents, 3);
      expectInt(test, st.mapped, 0);
      makeStep(db, f.id, docs[0].id, 1, "x", []);
      let st2 = stacksStats(db, me, f.id);
      expectInt(test, st2.read, 1);
      expectInt(test, st2.mapped, 0);
      db.exec("UPDATE works SET status = 'read' WHERE id = $1", [docs[0].id.toString()]);
      expectInt(test, stacksStats(db, me, f.id).mapped, 1);
    }

    test("stats count pitfalls, excerpts, links, dropped claims, deepening and revisions") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = summaryFolder(db, me);
      let docs = stacksDocuments(db, me, f.id);
      let s1 = makeStep(db, f.id, docs[0].id, 1, "one", []);
      let s2 = makeStep(db, f.id, docs[1].id, 2, "two", [1]);
      let s3 = makeStep(db, f.id, docs[2].id, 3, "three", [1, 2]);
      db.exec("UPDATE stack_steps SET pitfall = 'p', excerpts = '[{\"caption\":\"c\",\"text\":\"t\"},{\"caption\":\"d\",\"text\":\"u\"}]', dropped = '[\"a\",\"b\"]' WHERE id = $1", [s1.id.toString()]);
      db.exec("UPDATE stack_steps SET pitfall = '' , deepened_at = '2026-01-01 00:00:00', revised_by = 3, deep_dropped = '[\"x\"]' WHERE id = $1", [s2.id.toString()]);
      db.exec("UPDATE stack_steps SET deep_dropped = '[\"the second pass failed: rate_limited\"]' WHERE id = $1", [s3.id.toString()]);
      let st = stacksStats(db, me, f.id);
      expectInt(test, st.read, 3);
      expectInt(test, st.pitfalls, 1);
      expectInt(test, st.excerpts, 2);
      expectInt(test, st.links, 3);
      expectInt(test, st.dropped, 2);
      expectInt(test, st.deepened, 1);
      expectInt(test, st.deepFailed, 1);
      expectInt(test, st.revisions, 1);
      expectInt(test, st.deepDropped, 2);
    }

    test("stale counts documents whose step was read from different text") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = summaryFolder(db, me);
      let docs = stacksDocuments(db, me, f.id);
      let s1 = makeStep(db, f.id, docs[0].id, 1, "one", []);
      let s2 = makeStep(db, f.id, docs[1].id, 2, "two", []);
      db.exec("UPDATE stack_steps SET fingerprint = $1 WHERE id = $2", [stacksFingerprint(db, docs[0].id), s1.id.toString()]);
      db.exec("UPDATE stack_steps SET fingerprint = 'old' WHERE id = $1", [s2.id.toString()]);
      expectInt(test, stacksStats(db, me, f.id).stale, 1);
    }

    test("stats are scoped to the owner") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let them = makeUser(db, "b@example.com");
      let f = summaryFolder(db, me);
      expectInt(test, stacksStats(db, them, f.id).documents, 0);
    }

## Back into the reader as a draft

    let storyOf(db: Db, folderId: Int, movements: List<StoryMovement>): Void throws Bubble {
      db.exec(
        "INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, dropped) VALUES ($1, $2, $3, $4, $5, '[]', '[]')",
        [folderId.toString(), "Half of building it is fixing the thing underneath", "Nothing here is hand-written at the level you would expect.", stacksMovementsJson(movements), "That is the method."],
      );
    }

    let longProse(lead: String): String {
      "${lead} ${repeated("word ", 320)}"
    }

    let twoParts(): List<StoryMovement> {
      [
        new StoryMovement("Get it running first", longProse("Emit one module."), [1], ""),
        new StoryMovement("Lowering is where the semantics live", longProse("Every construct needs a shape."), [2, 3], "This is the part that surprised me."),
      ]
    }

    test("each movement becomes a section, so a note lands on the part it is about") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A stack");
      storyOf(db, f.id, twoParts());
      let d = stacksToDraft(db, me, f.id);
      let work = d.work;
      expectTrue(test, work != null, orNone(d.error));
      expectText(test, orNone(if (work != null) { work.title } else { null }), "Half of building it is fixing the thing underneath");
      let sections = worksListSections(db, orWork(work).id);
      expectTrue(test, sections.length >= 3, "an opening and two parts at least");
      let titles = sections.map { (s: Section): String => s.title };
      expectTrue(test, anyHas(titles, "1. Get it running first"), "first part");
      expectTrue(test, anyHas(titles, "2. Lowering is where the semantics live"), "second part");
      expectHas(test, orWork(work).body, "That is the method.");
    }

    let orWork(w: Work?): Work throws Bubble {
      if (w != null) { w } else { bubble() }
    }

    test("the opening, the turns and the closing all survive") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A stack");
      storyOf(db, f.id, twoParts());
      let work = orWork(stacksToDraft(db, me, f.id).work);
      expectHas(test, work.body, "Nothing here is hand-written");
      expectHas(test, work.body, "This is the part that surprised me.");
      expectHas(test, work.body, "That is the method.");
    }

    test("it is not filed into the stack's own folder") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A stack");
      storyOf(db, f.id, twoParts());
      let work = orWork(stacksToDraft(db, me, f.id).work);
      expectTrue(test, work.folderId != f.id, "a draft in the stack's folder becomes document N+1 of the series it summarises, re-read as a chapter and shifting every ordinal after it");
      expectInt(test, stacksDocuments(db, me, f.id).length, 0);
    }

    test("the intent says what the draft is for, so the read is not generic") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A stack");
      storyOf(db, f.id, twoParts());
      let work = orWork(stacksToDraft(db, me, f.id).work);
      expectHas(test, orEmpty(work.intent), "2 parts");
      expectHas(test, orEmpty(work.intent), "could be acted on");
      expectText(test, orEmpty(work.intent), stacksIntent(0, 2));
    }

    test("a stack with no telling yet says so rather than making an empty draft") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A stack");
      let d = stacksToDraft(db, me, f.id);
      expectText(test, orNone(d.error), "not_composed");
      expectTrue(test, d.work == null, "no work");
      expectInt(test, worksListWorks(db, me).length, 0);
    }

    test("a movement with no turn does not leave a stray quote marker") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A stack");
      storyOf(db, f.id, [new StoryMovement("One", longProse("Just prose."), [1], "")]);
      let work = orWork(stacksToDraft(db, me, f.id).work);
      expectLacks(test, work.body, ">");
    }

    test("the draft body is built the way the Elixir joined it, closing and all") { test =>
      let story = stacksSketchStory([]);
      let full = new StackStory(
        1, 1, "T", "Opening.",
        [new StoryMovement("H", "Prose.", [1], "Turn."), new StoryMovement("G", "More.", [2], "")],
        "Closing.", [], [], null, "", "",
      );
      expectText(
        test,
        stacksDraftBody(full),
        "Opening.\n\n## 1. H\n\nProse.\n\n> Turn.\n\n## 2. G\n\nMore.\n\n## Closing\n\n\n\nClosing.",
      );
      expectText(test, stacksDraftBody(story), "## Closing");
    }

    test("the intent counts steps and parts") { test =>
      expectText(
        test,
        stacksIntent(12, 3),
        "The method read out of 12 documents, in 3 parts. It is meant to tell somebody building the same thing what to do and in what order, so the test of any paragraph is whether it could be acted on.",
      );
    }

## Records

    test("a story round-trips its movements through the column") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let f = makeFolder(db, me, "A stack");
      storyOf(db, f.id, twoParts());
      let story = stacksGetStory(db, f.id);
      expectTrue(test, story != null, "stored");
      let ms = stacksMovementsOf(stacksMovementsJson(twoParts()));
      expectInt(test, ms.length, 2);
      expectText(test, ms[1].heading, "Lowering is where the semantics live");
      expectText(test, intsText(ms[1].steps), "2,3");
      expectText(test, ms[1].turn, "This is the part that surprised me.");
      expectText(test, ms[0].turn, "");
    }

    test("a stored movement without a turn has the empty turn") { test =>
      let ms = stacksMovementsOf("[{\"heading\":\"A\",\"prose\":\"P\",\"steps\":[1]},{\"heading\":\"B\",\"prose\":\"Q\",\"steps\":[2],\"turn\":null}]");
      expectText(test, ms[0].turn, "");
      expectText(test, ms[1].turn, "");
    }

    test("excerpts round-trip, and a missing column reads as none") { test =>
      let xs = stacksExcerptsOf(stacksExcerptsJson([new StackExcerpt("cap", "text \"quoted\"")]));
      expectInt(test, xs.length, 1);
      expectText(test, xs[0].text, "text \"quoted\"");
      expectInt(test, stacksExcerptsOf(null).length, 0);
    }

## The prompts and the tools

    test("the report_step tool has its six required fields in the order the model was shown") { test =>
      let schema = stacksReportStepSchema();
      expectHas(test, schema, "\"required\":[\"capability\",\"requires\",\"lesson\",\"pitfall\",\"pitfall_quote\",\"excerpts\"]");
      expectHas(test, schema, "\"maxItems\":2");
      expectHas(test, schema, "(\\\"a class becomes an actor\\\")");
      expectText(test, stacksReportStepTool().name, "report_step");
      expectText(test, stacksReportStepTool().description, "Report what this document contributes to building the thing the series builds.");
    }

    test("the deepen_step tool") { test =>
      let schema = stacksDeepenStepSchema();
      expectHas(test, schema, "\"required\":[\"mechanism\",\"watch_for\",\"revised_by\",\"revision\",\"revision_quote\"]");
      expectHas(test, schema, "\"revised_by\":{\"description\":\"The number of a LATER step");
      expectText(test, stacksDeepenStepTool().name, "deepen_step");
    }

    test("the outline_story and write_part tools") { test =>
      let outline = stacksOutlineStorySchema();
      expectHas(test, outline, "\"required\":[\"title\",\"opening\",\"closing\",\"parts\"]");
      expectHas(test, outline, "\"required\":[\"heading\",\"steps\"]");
      expectText(test, stacksOutlineStoryTool().name, "outline_story");
      let part = stacksWritePartSchema();
      expectHas(test, part, "\"required\":[\"prose\",\"turn\"]");
      expectText(test, stacksWritePartTool().name, "write_part");
    }

    test("every schema is JSON an object") { test =>
      let all = [stacksReportStepSchema(), stacksDeepenStepSchema(), stacksOutlineStorySchema(), stacksWritePartSchema()];
      var i = 0;
      while (i < all.length) {
        expectTrue(test, parseJson(all[i]) is JsonObject, "schema ${i.toString()}");
        i += 1;
      }
    }

    test("the system prompts end where the Elixir heredocs end") { test =>
      expectHas(test, stacksReadPrompt(), "Report by calling report_step.\n");
      expectHas(test, stacksDeepPrompt(), "Report by calling deepen_step.\n");
      expectHas(test, stacksComposePrompt(), "no emoji.\n");
      expectTrue(test, stacksReadPrompt().split("\n").length == 8, "four paragraphs");
    }
