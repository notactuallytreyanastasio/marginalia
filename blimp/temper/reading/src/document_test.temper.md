# Tests for the document summary

Ported from `test/marginalia/document_test.exs` (8 tests), the draft-making
tests of `summaries_to_draft_test.exs` and `compare_summary_test.exs` (the
parts that do not reach `Links` or the read), and the run with the model's
answers canned.

What is tested is the checking and the staleness, not the prose: a citation to
a section that does not exist reads exactly like one that is true, and is the
failure a reader cannot catch without going and looking.

`Document.compare/3` is not ported (see `document.temper.md`); its tests of
`to_draft` and `condensation_of` are here, and its one test of the
`nothing_summarised` refusal is `documentToDraft`'s.

    let { Db, dbOpen } = import("db/src");
    let { Scope } = import("accounts/src");
    let {
      Work, Section, DocumentSummary, DocumentSummaryParams,
      worksListSections, worksReplaceBlock, worksSaveDocumentSummary, worksGetDocumentSummary,
      worksCondensationOf, worksDeleteWork, worksGetById, worksRevisionCount,
    } = import("works/src");
    let { LlmFakeResponse, llmFake, llmFakeScript, llmLastRequest, llmRequests } = import("llm/src");
    let { JsonSyntaxTree, JsonObject } = import("std/json");
    let { versionsOf, versionsWorkTopic } = import("runs/src");
    let { sysJoin } = import("sys/src");

    class DocFx(public db: Db, public me: Scope, public work: Work) {}

    let docFixture(): DocFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = rdUser(db, "a@example.com");
      let parts = new ListBuilder<String>();
      for (var i = 1; i <= 3; ++i) {
        parts.add("# Part ${i.toString()}\n\nSection ${i.toString()} body. ${rdRepeat("word ", 300)}");
      }
      new DocFx(db, me, rdWork(db, me, "Draft", sysJoin(parts.toList(), "\n\n")))
    }

Every section given a summary straight onto its row, with the fingerprint and
source it was made from.

    let summariseAll(fx: DocFx): List<Section> throws Bubble {
      let out = new ListBuilder<Section>();
      for (let s of worksListSections(fx.db, fx.work.id)) {
        out.add(rdSummarise(fx.db, s, "What section ${s.ordinal.toString()} does.", summaryFingerprint(s), s.body));
      }
      out.toList()
    }

    let sectionsText(t: JsonSyntaxTree?): String {
      sysJoin(readingElements(t, "sections").map { (e: JsonSyntaxTree): String => readingInspect(e) }, ",")
    }

    let checkedWith(compJson: String, guideJson: String, sections: List<Section>): DocumentChecked throws Bubble {
      documentValidate(rdJson(compJson), rdJson(guideJson), sections)
    }

## validate

    test("document: a citation to a real section is kept") { test =>
      let fx = docFixture();
      let sections = worksListSections(fx.db, fx.work.id);
      let c = checkedWith(
        "{\"summary\":\"It does a thing.\",\"throughline\":\"One thread.\",\"movements\":[{\"heading\":\"H\",\"sections\":[1,2],\"does\":\"D\"}]}",
        "{}", sections,
      );
      rdInt(test, c.movements.length, 1);
      rdText(test, sectionsText(c.movements[0]), "1,2");
      rdInt(test, c.dropped.length, 0);
      rdText(test, c.summary, "It does a thing.");
      rdText(test, c.throughline, "One thread.");
    }

    test("document: a citation to a section that does not exist is dropped and named") { test =>
      let fx = docFixture();
      let sections = worksListSections(fx.db, fx.work.id);
      let c = checkedWith(
        "{\"summary\":\"s\",\"throughline\":\"t\",\"movements\":[{\"heading\":\"H\",\"sections\":[1,14],\"does\":\"D\"}]}",
        "{}", sections,
      );
      rdText(test, sectionsText(c.movements[0]), "1");
      rdInt(test, c.dropped.length, 1);
      rdHas(test, c.dropped[0], "14");
      rdHas(test, c.dropped[0], "not sections here");
      rdText(test, c.dropped[0], "movement: cites [14], which are not sections here");
    }

A tension whose every citation is invalid is kept with an empty list.

    test("document: guidelines and tensions are checked the same way") { test =>
      let fx = docFixture();
      let sections = worksListSections(fx.db, fx.work.id);
      let c = checkedWith(
        "{}",
        "{\"guidelines\":[{\"guideline\":\"G\",\"because\":\"B\",\"sections\":[2,99]}],\"tensions\":[{\"tension\":\"T\",\"sections\":[40]}]}",
        sections,
      );
      rdText(test, sectionsText(c.guidelines[0]), "2");
      rdInt(test, c.tensions.length, 1);
      rdText(test, sectionsText(c.tensions[0]), "");
      rdInt(test, c.dropped.length, 2);
      rdText(test, c.dropped[0], "guideline: cites [99], which are not sections here");
      rdText(test, c.dropped[1], "tension: cites [40], which are not sections here");
    }

    test("document: no tensions is a real answer and not an error") { test =>
      let fx = docFixture();
      let sections = worksListSections(fx.db, fx.work.id);
      let c = checkedWith("{}", "{\"guidelines\":[],\"tensions\":[]}", sections);
      rdInt(test, c.tensions.length, 0);
      rdInt(test, c.dropped.length, 0);
    }

    test("document: citations are reported in the order movements, guidelines, tensions") { test =>
      let fx = docFixture();
      let sections = worksListSections(fx.db, fx.work.id);
      let c = checkedWith(
        "{\"movements\":[{\"heading\":\"H\",\"sections\":[7]}]}",
        "{\"tensions\":[{\"tension\":\"T\",\"sections\":[8]}],\"guidelines\":[{\"guideline\":\"G\",\"sections\":[9]}]}",
        sections,
      );
      rdInt(test, c.dropped.length, 3);
      rdHas(test, c.dropped[0], "movement:");
      rdHas(test, c.dropped[1], "guideline:");
      rdHas(test, c.dropped[2], "tension:");
    }

    test("document: a citation that is not an integer is not a section, and is shown as it was") { test =>
      let fx = docFixture();
      let sections = worksListSections(fx.db, fx.work.id);
      let c = checkedWith(
        "{\"movements\":[{\"heading\":\"H\",\"sections\":[1,\"2\",2.0,3]}]}", "{}", sections,
      );
      rdText(test, sectionsText(c.movements[0]), "1,3");
      rdText(test, c.dropped[0], "movement: cites [\"2\", 2.0], which are not sections here");
    }

    test("document: items that are not objects are left out, and a missing list is empty") { test =>
      let fx = docFixture();
      let sections = worksListSections(fx.db, fx.work.id);
      let c = checkedWith("{\"summary\":5,\"movements\":[\"x\",3]}", "{}", sections);
      rdInt(test, c.movements.length, 0);
      rdText(test, c.summary, "");
      rdText(test, c.throughline, "");
    }

## Staleness

    test("document: a document with no summary is not current") { test =>
      let fx = docFixture();
      rdFalse(test, documentCurrent(fx.db, fx.work), "nothing stored");
      rdTrue(test, documentGet(fx.db, fx.work.id) == null, "no row");
    }

    test("document: the fingerprint is over the section summaries") { test =>
      let fx = docFixture();
      let summarised = summariseAll(fx);
      let a = documentFingerprint(summarised);
      rdText(test, documentFingerprint(summarised), a);
      // re-summarised: same text, different words for it
      let reworded = [rdWithSummary(summarised[0], "Different words."), summarised[1], summarised[2]];
      rdFalse(test, documentFingerprint(reworded) == a, "reworded");
      // edited: same summary, different text under it
      let edited = [rdWithBody(summarised[0], "${summarised[0].body} and more."), summarised[1], summarised[2]];
      rdFalse(test, documentFingerprint(edited) == a, "edited");
      // not the same as a draft nobody has summarised
      let bare = [rdWithSummary(summarised[0], null), summarised[1], summarised[2]];
      rdFalse(test, documentFingerprint(bare) == a, "unsummarised");
      rdInt(test, readingLength(a), 64);
    }

    test("document: editing a section makes the document summary stale") { test =>
      let fx = docFixture();
      let summarised = summariseAll(fx);
      let p = new DocumentSummaryParams(fx.work.id);
      p.summary = "The whole thing.";
      p.fingerprint = documentFingerprint(summarised);
      worksSaveDocumentSummary(fx.db, p);
      rdTrue(test, documentCurrent(fx.db, fx.work), "current");
      let first = summarised[0];
      let block = rdBlockWith(first, "Section 1");
      worksReplaceBlock(fx.db, first, block, readingReplaceFirst(block, "Section 1", "AMENDED"), null, null);
      // a document summary built on a section that has since changed is out of date
      rdFalse(test, documentCurrent(fx.db, fx.work), "stale");
    }

    test("document: a work with no sections is refused before any call") { test =>
      let fx = docFixture();
      fx.db.exec("DELETE FROM sections WHERE work_id = $1", [fx.work.id.toString()]);
      let llm = llmFake([]);
      let r = documentRun(fx.db, llm, fx.work, false);
      rdText(test, rdOr(r.error, "ok"), "no_sections");
      rdCalls(test, llm, 0);
    }

## Running both prongs

    let sectionAnswer(): String throws Bubble {
      rdToolReply("report_section", "{\"summary\":\"It does its part.\",\"covers\":[],\"follows_from\":[],\"sets_up\":\"\"}")
    }

    let composeAnswer(): String throws Bubble {
      rdToolReply("report_composition", "{\"summary\":\"  It does a thing.  \",\"throughline\":\"One thread.\",\"movements\":[{\"heading\":\"Whole\",\"sections\":[1,2,3],\"does\":\"All of it.\"},{\"heading\":\"Bad\",\"sections\":[2,14],\"does\":\"Some.\"}]}")
    }

    let guideAnswer(): String throws Bubble {
      rdToolReply("report_guidelines", "{\"guidelines\":[{\"guideline\":\"Name the failing case first.\",\"because\":\"It locates the fix.\",\"sections\":[1,99]}],\"tensions\":[]}")
    }

    test("document: run summarises what is stale, composes, reads the rules and stores the whole") { test =>
      let fx = docFixture();
      let llm = llmFake([sectionAnswer(), sectionAnswer(), sectionAnswer(), composeAnswer(), guideAnswer()]);
      let r = documentRun(fx.db, llm, fx.work, false);
      rdText(test, rdOr(r.error, "ok"), "ok");
      rdCalls(test, llm, 5);
      let doc = r.ok;
      rdTrue(test, doc != null, "stored");
      if (doc != null) {
        rdText(test, rdOr(doc.summary, "<none>"), "It does a thing.");
        rdText(test, rdOr(doc.throughline, "<none>"), "One thread.");
        rdInt(test, doc.movements.length, 2);
        rdText(test, sectionsText(doc.movements[0]), "1,2,3");
        rdText(test, sectionsText(doc.movements[1]), "2");
        rdText(test, sectionsText(doc.guidelines[0]), "1");
        rdInt(test, doc.tensions.length, 0);
        rdText(test, rdJoin(doc.dropped), "movement: cites [14], which are not sections here|guideline: cites [99], which are not sections here");
      }
      for (let s of worksListSections(fx.db, fx.work.id)) {
        rdText(test, rdOr(s.summary, "<none>"), "It does its part.");
      }
      rdTrue(test, documentCurrent(fx.db, fx.work), "current against the sections it was made from");
      rdTrue(test, versionsOf(fx.db, versionsWorkTopic(fx.work.id)) >= 1, "the page is told");
    }

    test("document: the composition is asked of the summaries, the rules of the titles and summaries") { test =>
      let fx = docFixture();
      summariseAll(fx);
      let llm = llmFake([composeAnswer(), guideAnswer()]);
      let r = documentRun(fx.db, llm, fx.work, false);
      rdText(test, rdOr(r.error, "ok"), "ok");
      rdCalls(test, llm, 2);
      rdSentAt(test, llm, 0, "Document: Draft\\n\\n3 sections, summarised, in order:\\n\\n1. Part 1\\nWhat section 1 does.\\n\\n2. Part 2");
      rdSentAt(test, llm, 0, "report_composition");
      rdSentAt(test, llm, 0, "\"temperature\":0.3");
      rdSentAt(test, llm, 0, "\"max_tokens\":27000");
      rdSentAt(test, llm, 1, "Its sections:\\n1. Part 1\\n2. Part 2\\n3. Part 3\\n\\nWhat each section does:\\n1. What section 1 does.\\n2. What section 2 does.");
      rdSentAt(test, llm, 1, "report_guidelines");
      rdSentAt(test, llm, 1, "\"max_tokens\":26500");
      // the composition's throughline is deliberately not handed to the second prong
      rdSentNotAt(test, llm, 1, "One thread.");
      rdSentNotAt(test, llm, 1, "throughline");
    }

    test("document: a second run asks only the two prongs, and force asks everything again") { test =>
      let fx = docFixture();
      let llm = llmFake([
        sectionAnswer(), sectionAnswer(), sectionAnswer(), composeAnswer(), guideAnswer(),
        composeAnswer(), guideAnswer(),
        sectionAnswer(), sectionAnswer(), sectionAnswer(), composeAnswer(), guideAnswer(),
      ]);
      documentRun(fx.db, llm, fx.work, false);
      rdCalls(test, llm, 5);
      documentRun(fx.db, llm, fx.work, false);
      rdCalls(test, llm, 7);
      let again = documentRun(fx.db, llm, fx.work, true);
      rdCalls(test, llm, 12);
      rdTrue(test, again.ok != null, "stored again over the same row");
      rdInt(test, fx.db.query("SELECT id FROM document_summaries WHERE work_id = $1", [fx.work.id.toString()]).length, 1);
    }

The composing prong landed and the decomposing one did not. Keeping half is
right, but it is recorded as half rather than presented as whole.

    test("document: guidelines failing keeps the composition and says so") { test =>
      let fx = docFixture();
      summariseAll(fx);
      let llm = llmFakeScript([
        new LlmFakeResponse(200, composeAnswer()),
        new LlmFakeResponse(400, "{\"error\":\"nope\"}"),
      ]);
      let r = documentRun(fx.db, llm, fx.work, false);
      rdText(test, rdOr(r.error, "ok"), "ok");
      let doc = r.ok;
      rdTrue(test, doc != null, "stored");
      if (doc != null) {
        rdText(test, rdOr(doc.summary, "<none>"), "It does a thing.");
        rdInt(test, doc.guidelines.length, 0);
        rdInt(test, doc.dropped.length, 2);
        rdHas(test, doc.dropped[1], "the guidelines pass failed: {:http,");
      }
    }

    test("document: a composition that fails is the error and stores nothing") { test =>
      let fx = docFixture();
      summariseAll(fx);
      let llm = llmFake([rdTextReply("I would rather talk."), guideAnswer()]);
      let r = documentRun(fx.db, llm, fx.work, false);
      rdText(test, rdOr(r.error, "ok"), "no_tool_call");
      rdTrue(test, documentGet(fx.db, fx.work.id) == null, "no row");
    }

    test("document: nothing summarised after the fan-out is no_summaries") { test =>
      let fx = docFixture();
      let bad = new LlmFakeResponse(400, "{}");
      let llm = llmFakeScript([bad, bad, bad]);
      let r = documentRun(fx.db, llm, fx.work, false);
      rdText(test, rdOr(r.error, "ok"), "no_summaries");
      rdCalls(test, llm, 3);
    }

    test("document: compose and guidelines can be asked on their own") { test =>
      let fx = docFixture();
      summariseAll(fx);
      let llm = llmFake([composeAnswer(), guideAnswer()]);
      let comp = documentCompose(fx.db, llm, fx.work);
      let guide = documentGuidelines(fx.db, llm, fx.work);
      rdTrue(test, comp.ok != null, "composition");
      rdTrue(test, guide.ok != null, "guidelines");
      rdCalls(test, llm, 2);
    }

## The summaries as a draft

    let sameDraft(a: Work?, b: Work?): Boolean {
      if (a != null) {
        if (b != null) { a.id == b.id } else { false }
      } else {
        false
      }
    }

    let sectionHolding(db: Db, work: Work, text: String): Section throws Bubble {
      let all = worksListSections(db, work.id);
      for (let s of all) {
        if (readingContains(s.body, text)) { return s; }
      }
      all[0]
    }

    class QuietFx(public db: Db, public me: Scope, public work: Work, public sections: List<Section>) {}

    let quietFixture(): QuietFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = rdUser(db, "a@example.com");
      let parts = new ListBuilder<String>();
      for (var i = 1; i <= 3; ++i) {
        parts.add("# Part ${i.toString()}\n\nSection ${i.toString()} body. ${rdRepeat("word ", 300)}");
      }
      let work = rdWork(db, me, "The Quiet House", sysJoin(parts.toList(), "\n\n"));
      new QuietFx(db, me, work, worksListSections(db, work.id))
    }

    let longSummary(lead: String): String { "${lead} ${rdRepeat("word ", 280)}" }

    let draftTitles(fx: QuietFx, draft: Work): String throws Bubble {
      rdJoin(worksListSections(fx.db, draft.id).map { (s: Section): String => s.title })
    }

    test("to_draft: nothing summarised makes no draft") { test =>
      let fx = quietFixture();
      let r = documentToDraft(fx.db, fx.me, fx.work);
      rdText(test, rdOr(r.error, "ok"), "nothing_summarised");
      rdTrue(test, r.ok == null, "no draft");
      rdInt(test, fx.db.query("SELECT id FROM works", []).length, 1);
    }

    test("to_draft: each summarised section becomes a part of the new draft") { test =>
      let fx = quietFixture();
      for (let s of fx.sections) {
        rdSummarise(fx.db, s, longSummary("What section ${s.ordinal.toString()} does, at length."), summaryFingerprint(s), s.body);
      }
      let r = documentToDraft(fx.db, fx.me, fx.work);
      let draft = r.ok;
      rdTrue(test, draft != null, "a draft");
      if (draft != null) {
        rdText(test, draft.title, "The Quiet House — in summary");
        rdHas(test, draft.body, "What section 1 does");
        rdHas(test, draft.body, "What section 3 does");
        rdTrue(test, worksListSections(fx.db, draft.id).length >= 2, "split on the headings");
        rdTrue(test, draft.derivedFromId == fx.work.id, "knows what it condenses");
      }
    }

    test("to_draft: a section nobody summarised is left out rather than blank") { test =>
      let fx = quietFixture();
      rdSummarise(fx.db, fx.sections[0], longSummary("Only this one."), null, null);
      let draft = documentToDraft(fx.db, fx.me, fx.work).ok;
      rdTrue(test, draft != null, "a draft");
      if (draft != null) {
        rdHas(test, draft.body, "Only this one.");
        rdLacks(test, draftTitles(fx, draft), "2. Part 2");
        rdHas(test, rdOr(draft.intent, ""), "1 of its 3 sections");
      }
    }

    test("to_draft: the covers and what it sets up ride along") { test =>
      let fx = quietFixture();
      let s = rdSummarise(fx.db, fx.sections[0], longSummary("A summary."), null, null);
      fx.db.exec(
        "UPDATE sections SET summary_covers = $1, summary_sets_up = $2 WHERE id = $3",
        [readingJsonStrings(["the out-grammar", "kcodegen"]), "a module that runs", s.id.toString()],
      );
      let draft = documentToDraft(fx.db, fx.me, fx.work).ok;
      rdTrue(test, draft != null, "a draft");
      if (draft != null) {
        rdHas(test, draft.body, "It deals with: the out-grammar, kcodegen.");
        rdHas(test, draft.body, "It leaves in place: a module that runs");
      }
    }

    test("to_draft: the document summary opens it and the guidelines close it") { test =>
      let fx = quietFixture();
      rdSummarise(fx.db, fx.sections[0], longSummary("A summary."), null, null);
      let p = new DocumentSummaryParams(fx.work.id);
      p.summary = "It builds a thing and then fixes what is underneath it.";
      p.throughline = "Nothing runs until the emitter is generated.";
      p.guidelinesJson = "[{\"guideline\":\"Name the failing case first.\",\"because\":\"It locates the fix.\"}]";
      worksSaveDocumentSummary(fx.db, p);
      let draft = documentToDraft(fx.db, fx.me, fx.work).ok;
      rdTrue(test, draft != null, "a draft");
      if (draft != null) {
        rdHas(test, draft.body, "It builds a thing and then fixes what is underneath it.");
        rdHas(test, draft.body, "Nothing runs until the emitter is generated.");
        // the ## itself is gone from the body: the segmenter lifts a heading into the section title
        rdHas(test, draft.body, "Name the failing case first.");
        rdHas(test, draft.body, "It locates the fix.");
        let titles = draftTitles(fx, draft);
        rdTrue(test, readingContains(titles, "working under") || readingContains(titles, "Part 1"), titles);
      }
    }

A condensation sitting in the folder it condenses becomes document N+1 of the
thing it summarises.

    test("to_draft: it is not filed in the folder of the draft it condenses") { test =>
      let fx = quietFixture();
      rdSummarise(fx.db, fx.sections[0], longSummary("A summary."), null, null);
      let draft = documentToDraft(fx.db, fx.me, fx.work).ok;
      rdTrue(test, draft != null, "a draft");
      if (draft != null) { rdTrue(test, draft.folderId == null, "no folder"); }
    }

    test("to_draft: the new draft is an ordinary one, editable, with its own history") { test =>
      let fx = quietFixture();
      rdSummarise(fx.db, fx.sections[0], longSummary("A summary worth editing."), null, null);
      let draft = documentToDraft(fx.db, fx.me, fx.work).ok;
      rdTrue(test, draft != null, "a draft");
      if (draft != null) {
        rdInt(test, worksRevisionCount(fx.db, draft.id), 0);
        let section = sectionHolding(fx.db, draft, "worth editing");
        let block = rdBlockWith(section, "worth editing");
        worksReplaceBlock(fx.db, section, block, readingReplaceFirst(block, "worth editing", "EDITED"), null, null);
        rdInt(test, worksRevisionCount(fx.db, draft.id), 1);
        let reloaded = worksGetById(fx.db, draft.id);
        rdHas(test, if (reloaded != null) { reloaded.body } else { "" }, "EDITED");
      }
    }

    test("to_draft: the draft body is the opening, the parts, then the rules") { test =>
      let fx = quietFixture();
      let s = rdSummarise(fx.db, fx.sections[0], "Short one.", null, null);
      fx.db.exec(
        "UPDATE sections SET summary_covers = $1, summary_sets_up = $2 WHERE id = $3",
        [readingJsonStrings(["a", "b"]), "an end", s.id.toString()],
      );
      let sections = worksListSections(fx.db, fx.work.id);
      rdText(
        test, documentDraftBody(fx.work, null, [sections[0]]),
        "A condensation of The Quiet House, section by section.\n\n## 1. Part 1\n\nShort one.\n\nIt deals with: a, b.\n\nIt leaves in place: an end",
      );
    }

## The condensation of a draft

    let compareFixture(): QuietFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = rdUser(db, "a@example.com");
      let body = "# One\n\nThe kettle went cold on the counter. ${rdRepeat("word ", 90)}\n\n# Two\n\nNobody moved to fill it again. ${rdRepeat("other ", 90)}";
      let work = rdWork(db, me, "The long version", body);
      var i = 1;
      for (let s of worksListSections(db, work.id)) {
        rdSummarise(db, s, "Section ${i.toString()}, in short.", null, null);
        i += 1;
      }
      new QuietFx(db, me, work, worksListSections(db, work.id))
    }

    test("condensation: a draft of its own that says what it condenses") { test =>
      let fx = compareFixture();
      let summary = documentToDraft(fx.db, fx.me, fx.work).ok;
      rdTrue(test, summary != null, "a draft");
      if (summary != null) {
        rdTrue(test, summary.id != fx.work.id, "another draft");
        rdTrue(test, summary.derivedFromId == fx.work.id, "derived");
        rdHas(test, summary.body, "Section 1, in short.");
        // and the original is untouched, which is the whole difference from replacing it
        let original = worksGetById(fx.db, fx.work.id);
        rdHas(test, if (original != null) { original.body } else { "" }, "The kettle went cold on the counter");
      }
    }

    test("condensation: the original is found from the condensation and back again") { test =>
      let fx = compareFixture();
      let summary = documentToDraft(fx.db, fx.me, fx.work).ok;
      if (summary != null) {
        rdTrue(test, sameDraft(worksCondensationOf(fx.db, fx.work.id), summary), "found from the original");
        rdTrue(test, worksCondensationOf(fx.db, summary.id) == null, "a condensation is not a source");
      } else {
        rdTrue(test, false, "a draft");
      }
    }

to_draft on its own always makes a new draft; condensation reuses the one there
is, so asking twice does not make two.

    test("condensation: asking twice reuses the condensation rather than making a second") { test =>
      let fx = compareFixture();
      let first = documentCondensation(fx.db, fx.me, fx.work).ok;
      let again = documentCondensation(fx.db, fx.me, fx.work).ok;
      rdTrue(test, first != null, "a first draft");
      rdTrue(test, sameDraft(first, again), "the same draft");
      let third = documentToDraft(fx.db, fx.me, fx.work).ok;
      rdTrue(test, third != null, "a third draft");
      rdFalse(test, sameDraft(third, first), "to_draft always makes one");
      rdTrue(test, sameDraft(worksCondensationOf(fx.db, fx.work.id), third), "the newest is the condensation");
    }

    test("condensation: a draft with nothing summarised cannot be condensed") { test =>
      let fx = compareFixture();
      let bare = rdWork(fx.db, fx.me, "Nothing summarised", "# X\n\n${rdRepeat("word ", 90)}");
      let r = documentCondensation(fx.db, fx.me, bare);
      rdText(test, rdOr(r.error, "ok"), "nothing_summarised");
      rdTrue(test, worksCondensationOf(fx.db, bare.id) == null, "nothing made");
    }

The condensation is somebody's draft now, not an appendix.

    test("condensation: deleting the long version leaves the condensation alone") { test =>
      let fx = compareFixture();
      let summary = documentToDraft(fx.db, fx.me, fx.work).ok;
      if (summary != null) {
        worksDeleteWork(fx.db, fx.work);
        let kept = worksGetById(fx.db, summary.id);
        rdTrue(test, kept != null, "kept");
        if (kept != null) { rdTrue(test, kept.derivedFromId == null, "detached"); }
      } else {
        rdTrue(test, false, "a draft");
      }
    }
