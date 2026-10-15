# Tests for editing a draft and its history

Ported from `editing_test`, `apply_rewrite_test`, `revisions_test` and the
edit half of `sentences_works_test` in `notes/tests.md`.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { sysJoin } = import("sys/src");
    let { rows, diff, Row, Part, paragraphs } = import("core/src");

    class Edit1(
      public db: Db,
      public scope: Scope,
      public work: Work,
      public section: Section,
      public kettle: GraphNode,
      public window: GraphNode,
    ) {}

The editing fixture: a draft with a window line, a kettle line and a long tail,
and a beat quoting each of the first two.

    let editing(): Edit1 throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "# A draft\n\nShe stood at the window for an hour.\n\nThe kettle went cold on the counter.\n\n${repeated("word ", 300)}";
      let work = makeWork(db, me, "W", body);
      let section = firstSection(db, work);
      let kettle = addBeat(db, work, section, "The kettle", "The kettle went cold on the counter.");
      let window = addBeat(db, work, section, "The window", "She stood at the window for an hour.");
      new Edit1(db, me, work, section, kettle, window)
    }

    let statusOf(db: Db, work: Work, id: Int): String throws Bubble {
      let n = worksGetNode(db, work.id, id);
      if (n != null) { n.status } else { "missing" }
    }

## Editing

    test("an edit lands in the section and in the work") { test =>
      let e = editing();
      let r = worksReplaceBlock(e.db, e.section, "The kettle went cold on the counter.", "The kettle went stone cold.", null, null);
      expectHas(test, r.section.body, "stone cold");
      expectLacks(test, r.section.body, "went cold on the counter");
      expectHas(test, worksGetWork(e.db, e.scope, e.work.id).body, "stone cold");
    }

    test("a note about the line you changed is superseded, not deleted") { test =>
      let e = editing();
      let r = worksReplaceBlock(e.db, e.section, "The kettle went cold on the counter.", "The kettle went stone cold.", null, null);
      expectInt(test, r.superseded, 1);
      expectText(test, statusOf(e.db, e.work, e.kettle.id), "superseded");
      let kept = worksGetNode(e.db, e.work.id, e.kettle.id);
      expectText(test, if (kept != null) { kept.title } else { "none" }, "The kettle");
      expectText(test, statusOf(e.db, e.work, e.window.id), "pending");
      expectInt(test, worksSupersededCount(e.db, e.work.id), 1);
    }

    test("a note still anchored after the edit survives it") { test =>
      let e = editing();
      let r = worksReplaceBlock(e.db, e.section, "The kettle went cold on the counter.", "Nobody moved. The kettle went cold on the counter.", null, null);
      expectInt(test, r.superseded, 0);
      expectText(test, statusOf(e.db, e.work, e.kettle.id), "pending");
    }

    test("section boundaries do not move") { test =>
      let e = editing();
      let before = worksListSections(e.db, e.work.id).length;
      worksReplaceBlock(e.db, e.section, "She stood at the window for an hour.", "She stood there.", null, null);
      let after = worksListSections(e.db, e.work.id);
      expectInt(test, after.length, before);
      expectInt(test, after[0].id, e.section.id);
    }

    test("emptying a paragraph is refused") { test =>
      let e = editing();
      let r = worksReplaceBlock(e.db, e.section, "The kettle went cold on the counter.", "   ", null, null);
      expectText(test, orEmpty(r.error), "empty");
      expectInt(test, worksRevisionCount(e.db, e.work.id), 0);
    }

    test("an edit against a paragraph that has moved is refused") { test =>
      let e = editing();
      let r = worksReplaceBlock(e.db, e.section, "a paragraph that is not there", "new", null, null);
      expectText(test, orEmpty(r.error), "moved");
      expectInt(test, worksRevisionCount(e.db, e.work.id), 0);
    }

    test("saving an unchanged paragraph does nothing") { test =>
      let e = editing();
      let block = "The kettle went cold on the counter.";
      let r = worksReplaceBlock(e.db, e.section, block, block, null, null);
      expectTrue(test, r.error == null, "no error");
      expectInt(test, r.superseded, 0);
      expectTrue(test, r.revision == null, "no revision");
      expectInt(test, worksRevisionCount(e.db, e.work.id), 0);
    }

    test("the word count follows the edit") { test =>
      let e = editing();
      let r = worksReplaceBlock(e.db, e.section, "She stood at the window for an hour.", "She stood.", null, null);
      expectTrue(test, r.section.wordCount < e.section.wordCount, "section shrank");
      expectTrue(test, worksGetWork(e.db, e.scope, e.work.id).wordCount < e.work.wordCount, "work shrank");
    }

    test("a quote shorter than eight characters never anchors, so its note is superseded") { test =>
      let e = editing();
      let short = addBeat(e.db, e.work, e.section, "Short", "kettle");
      let r = worksReplaceBlock(e.db, e.section, "The kettle went cold on the counter.", "Another line entirely.", null, null);
      expectInt(test, r.superseded, 2);
      expectText(test, statusOf(e.db, e.work, short.id), "superseded");
    }

    test("an anchor survives case and spacing changes") { test =>
      let e = editing();
      let loud = addBeat(e.db, e.work, e.section, "Loud", "THE KETTLE   WENT cold on the counter.");
      let r = worksReplaceBlock(e.db, e.section, "She stood at the window for an hour.", "She stood.", null, null);
      expectText(test, statusOf(e.db, e.work, loud.id), "pending");
      expectInt(test, r.superseded, 1);
      expectText(test, statusOf(e.db, e.work, e.window.id), "superseded");
    }

## One sentence per line, on every edit

    let wrappedDraft(): String {
      "# A draft\n\nShe had been standing at the window for an hour\nbefore anyone noticed. The kettle went cold on\nthe counter. Nobody moved to fill it again.\n\nBy evening the argument had found its real\nsubject, which was not the kettle. It was the\nwindow.\n"
    }

    class Edit2(public db: Db, public scope: Scope, public work: Work, public section: Section) {}

    let wrappedFixture(): Edit2 throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let work = makeWork(db, me, "W", wrappedDraft());
      new Edit2(db, me, work, firstSection(db, work))
    }

    test("editing one sentence supersedes only the note on that sentence") { test =>
      let f = wrappedFixture();
      let kettle = addBeat(f.db, f.work, f.section, "The kettle", "The kettle went cold on the counter.");
      let window = addBeat(f.db, f.work, f.section, "The window", "It was the window.");
      let ps = paragraphs(f.section.body);
      let first = ps[1];
      let edited = sysJoin(first.split("The kettle went cold on the counter."), "The kettle boiled dry.");
      let r = worksReplaceBlock(f.db, f.section, first, edited, null, null);
      expectInt(test, r.superseded, 1);
      expectText(test, statusOf(f.db, f.work, kettle.id), "superseded");
      expectFalse(test, statusOf(f.db, f.work, window.id) == "superseded", "the window note stays");
    }

    test("an edit of one sentence is one changed paragraph, and the diff names only that sentence") { test =>
      let f = wrappedFixture();
      let first = paragraphs(f.section.body)[1];
      let edited = sysJoin(first.split("Nobody moved to fill it again."), "Nobody moved.");
      worksReplaceBlock(f.db, f.section, first, edited, null, null);
      let work = worksGetWork(f.db, f.scope, f.work.id);
      let r = rows(worksBaseline(f.db, work), work.body);
      expectInt(test, r.length, 3);
      expectText(test, r[0].kind, "same");
      expectText(test, r[1].kind, "change");
      expectText(test, r[2].kind, "same");
      let parts = diff(orEmpty(r[1].left), orEmpty(r[1].right));
      let changed = new ListBuilder<String>();
      for (let p of parts) {
        if (p.kind != "same") { changed.add(worksTrim(p.text)); }
      }
      let said = sysJoin(changed.toList(), " ");
      expectHas(test, said, "to fill it again");
      expectLacks(test, said, "standing at the window");
    }

    test("the stored form survives an edit pasted as one long line") { test =>
      let f = wrappedFixture();
      let second = paragraphs(f.section.body)[2];
      let pasted = "By evening the argument had found its real subject. It was the window. It always was.";
      let r = worksReplaceBlock(f.db, f.section, second, pasted, null, null);
      let want = "By evening the argument had found its real subject.\nIt was the window.\nIt always was.";
      expectHas(test, r.section.body, want);
      let revisions = worksRevisions(f.db, f.work.id);
      expectInt(test, revisions.length, 1);
      expectText(test, revisions[0].after, want);
    }

    test("an edit that only re-wraps a paragraph is no edit at all") { test =>
      let f = wrappedFixture();
      let first = paragraphs(f.section.body)[1];
      let flat = sysJoin(first.split("\n"), " ");
      let rewrapped = sysJoin(flat.split("hour before"), "hour\nbefore");
      let r = worksReplaceBlock(f.db, f.section, first, rewrapped, null, null);
      expectInt(test, r.superseded, 0);
      expectInt(test, worksRevisions(f.db, f.work.id).length, 0);
    }

## Replacing a span

    class Span(public db: Db, public scope: Scope, public work: Work, public section: Section) {}

    let spanFixture(): Span throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "# One\n\nALPHA the first paragraph. ${repeated("word ", 120)}\n\nBRAVO the second paragraph. ${repeated("word ", 120)}\n\nCHARLIE the third paragraph. ${repeated("word ", 120)}";
      let work = makeWork(db, me, "Draft", body);
      new Span(db, me, work, firstSection(db, work))
    }

    let spanAcrossTwo(section: Section): String {
      "${blockWith(section, "ALPHA")}\n\n${blockWith(section, "BRAVO")}"
    }

    test("a span crossing two paragraphs is replaced whole") { test =>
      let s = spanFixture();
      let span = spanAcrossTwo(s.section);
      expectTrue(test, hasText(s.section.body, span), "the span is in the section");
      let r = worksReplaceBlock(s.db, s.section, span, "ONE SENTENCE INSTEAD OF BOTH.", "rewrite", null);
      expectTrue(test, r.error == null, "replaced");
      let body = worksGetWork(s.db, s.scope, s.work.id).body;
      expectHas(test, body, "ONE SENTENCE INSTEAD OF BOTH.");
      expectLacks(test, body, "ALPHA the first paragraph.");
      expectLacks(test, body, "BRAVO the second paragraph.");
      expectHas(test, body, "CHARLIE the third paragraph.");
    }

    test("it records one revision, so the replacement is undoable") { test =>
      let s = spanFixture();
      let span = spanAcrossTwo(s.section);
      worksReplaceBlock(s.db, s.section, span, "A SHORTER VERSION.", "rewrite", "cuts the gloss");
      let revisions = worksRevisions(s.db, s.work.id);
      expectInt(test, revisions.length, 1);
      expectText(test, revisions[0].origin, "rewrite");
      expectText(test, orNull(revisions[0].note), "cuts the gloss");
      expectHas(test, revisions[0].before, "ALPHA");
      expectHas(test, revisions[0].before, "BRAVO");
      expectText(test, revisions[0].after, "A SHORTER VERSION.");
    }

    test("replaying the history reproduces the draft after a multi-paragraph replace") { test =>
      let s = spanFixture();
      worksReplaceBlock(s.db, s.section, spanAcrossTwo(s.section), "A SHORTER VERSION.", "rewrite", null);
      let replayed = worksReplay(s.db, s.work.id);
      expectText(test, orEmpty(replayed.ok), worksGetWork(s.db, s.scope, s.work.id).body);
    }

    test("a passage that has changed underneath is refused rather than guessed at") { test =>
      let s = spanFixture();
      let span = spanAcrossTwo(s.section);
      let first = blockWith(s.section, "ALPHA");
      let moved = worksReplaceBlock(s.db, s.section, first, "REWRITTEN ALREADY.", null, null);
      let late = worksReplaceBlock(s.db, moved.section, span, "TOO LATE.", null, null);
      expectText(test, orEmpty(late.error), "moved");
      expectLacks(test, worksGetWork(s.db, s.scope, s.work.id).body, "TOO LATE.");
    }

    test("an empty replacement is refused: a deletion is not a rewrite") { test =>
      let s = spanFixture();
      let r = worksReplaceBlock(s.db, s.section, spanAcrossTwo(s.section), "   ", null, null);
      expectText(test, orEmpty(r.error), "empty");
    }

## Revisions and the baseline

    class Hist(public db: Db, public scope: Scope, public work: Work, public section: Section) {}

    let histFixture(): Hist throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "# A draft\n\nALPHA the first paragraph. ${repeated("word ", 120)}\n\nBRAVO the second paragraph. ${repeated("word ", 120)}";
      let work = makeWork(db, me, "Draft", body);
      new Hist(db, me, work, firstSection(db, work))
    }

    let swap(text: String, from: String, to: String): String {
      sysJoin(text.split(from), to)
    }

    test("the baseline is captured when the draft arrives") { test =>
      let h = histFixture();
      expectText(test, orEmpty(h.work.baselineBody), h.work.body);
      expectText(test, worksBaseline(h.db, h.work), h.work.body);
    }

    test("an edit records one revision") { test =>
      let h = histFixture();
      let b = blockWith(h.section, "ALPHA");
      worksReplaceBlock(h.db, h.section, b, swap(b, "ALPHA", "AMENDED"), null, null);
      let revisions = worksRevisions(h.db, h.work.id);
      expectInt(test, revisions.length, 1);
      expectInt(test, revisions[0].seq, 1);
      expectText(test, revisions[0].origin, "edit");
      expectHas(test, revisions[0].before, "ALPHA");
      expectHas(test, revisions[0].after, "AMENDED");
      expectInt(test, orZero(revisions[0].sectionOrdinal), h.section.ordinal);
      expectInt(test, orZero(revisions[0].sectionId), h.section.id);
    }

    test("a rewrite says so, and carries the candidate's label") { test =>
      let h = histFixture();
      let b = blockWith(h.section, "BRAVO");
      worksReplaceBlock(h.db, h.section, b, swap(b, "BRAVO", "BETTER"), "rewrite", "cuts the gloss");
      let revisions = worksRevisions(h.db, h.work.id);
      expectInt(test, revisions.length, 1);
      expectText(test, revisions[0].origin, "rewrite");
      expectText(test, orNull(revisions[0].note), "cuts the gloss");
    }

    test("an origin outside edit, rewrite and summary is refused and nothing is written") { test =>
      let h = histFixture();
      let b = blockWith(h.section, "ALPHA");
      let refused = do { worksReplaceBlock(h.db, h.section, b, swap(b, "ALPHA", "AMENDED"), "vibes", null); false } orelse true;
      expectTrue(test, refused, "the bubble comes out");
      expectInt(test, worksRevisionCount(h.db, h.work.id), 0);
      let unchanged = worksSectionById(h.db, h.section.id);
      expectText(test, if (unchanged != null) { unchanged.body } else { "none" }, h.section.body);
    }

    test("replaying every patch over the baseline reproduces the body") { test =>
      let h = histFixture();
      let b1 = blockWith(h.section, "ALPHA");
      let one = worksReplaceBlock(h.db, h.section, b1, swap(b1, "ALPHA", "ONE"), null, null);
      let b2 = blockWith(one.section, "BRAVO");
      worksReplaceBlock(h.db, one.section, b2, swap(b2, "BRAVO", "TWO"), null, null);
      let replayed = worksReplay(h.db, h.work.id);
      expectText(test, orEmpty(replayed.ok), worksGetWork(h.db, h.scope, h.work.id).body);
      expectInt(test, worksRevisionCount(h.db, h.work.id), 2);
    }

    test("seq is per work and does not skip") { test =>
      let h = histFixture();
      var section = h.section;
      for (let lead of ["ALPHA", "BRAVO"]) {
        let b = blockWith(section, lead);
        let r = worksReplaceBlock(h.db, section, b, swap(b, lead, "${lead}!"), null, null);
        section = r.section;
      }
      let seqs = worksRevisions(h.db, h.work.id).map { (r: Revision): String => r.seq.toString() };
      expectText(test, sysJoin(seqs, ","), "1,2");
    }

    test("seq counts separately for each work") { test =>
      let h = histFixture();
      let other = makeWork(h.db, h.scope, "Other", "# A draft\n\nALPHA the other paragraph. ${repeated("word ", 120)}");
      let otherSection = firstSection(h.db, other);
      let b = blockWith(h.section, "ALPHA");
      worksReplaceBlock(h.db, h.section, b, swap(b, "ALPHA", "ONE"), null, null);
      let c = blockWith(otherSection, "ALPHA");
      worksReplaceBlock(h.db, otherSection, c, swap(c, "ALPHA", "TWO"), null, null);
      expectInt(test, worksRevisions(h.db, other.id)[0].seq, 1);
      expectInt(test, worksRevisions(h.db, h.work.id)[0].seq, 1);
    }

    test("an edit that changes nothing records nothing") { test =>
      let h = histFixture();
      let b = blockWith(h.section, "ALPHA");
      let r = worksReplaceBlock(h.db, h.section, b, b, null, null);
      expectInt(test, r.superseded, 0);
      expectInt(test, worksRevisions(h.db, h.work.id).length, 0);
    }

    test("a draft from before any history still has a baseline") { test =>
      let h = histFixture();
      let stripped = new Work(
        h.work.id, h.work.userId, h.work.slug, h.work.title, h.work.intent, h.work.sourceUrl,
        h.work.collection, h.work.collectionRole, h.work.body, null, h.work.wordCount, h.work.status,
        h.work.statusDetail, h.work.firstImpression, h.work.folderId, h.work.derivedFromId,
        h.work.insertedAt, h.work.updatedAt,
      );
      expectText(test, worksBaseline(h.db, stripped), h.work.body);
    }

    test("the baseline is reconstructed from the revisions rather than the body") { test =>
      let h = histFixture();
      let b = blockWith(h.section, "ALPHA");
      worksReplaceBlock(h.db, h.section, b, swap(b, "ALPHA", "AMENDED"), null, null);
      h.db.exec("UPDATE works SET baseline_body = NULL WHERE id = $1", [h.work.id.toString()]);
      let work = worksGetWork(h.db, h.scope, h.work.id);
      let baseline = worksBaseline(h.db, work);
      expectHas(test, baseline, "ALPHA");
      expectLacks(test, baseline, "AMENDED");
      expectFalse(test, baseline == work.body, "falling back to the body would report no changes");
    }

    test("the reconstructed baseline actually diffs") { test =>
      let h = histFixture();
      let b = blockWith(h.section, "BRAVO");
      worksReplaceBlock(h.db, h.section, b, swap(b, "BRAVO", "BETTER"), null, null);
      h.db.exec("UPDATE works SET baseline_body = NULL WHERE id = $1", [h.work.id.toString()]);
      let work = worksGetWork(h.db, h.scope, h.work.id);
      let r = rows(worksBaseline(h.db, work), work.body);
      var changed = 0;
      for (let row of r) { if (row.kind == "change") { changed += 1; } }
      expectInt(test, changed, 1);
    }

    test("a stored baseline is still preferred over reconstructing one") { test =>
      let h = histFixture();
      expectText(test, worksBaseline(h.db, h.work), orEmpty(h.work.baselineBody));
    }

    test("an edit is stored one sentence per line, and the replay still holds") { test =>
      let h = histFixture();
      let b = blockWith(h.section, "ALPHA");
      let typed = "ALPHA was rewritten. It came back\nwrapped, as pasted text does. Two sentences became three.";
      let r = worksReplaceBlock(h.db, h.section, b, typed, null, null);
      let want = "ALPHA was rewritten.\nIt came back wrapped, as pasted text does.\nTwo sentences became three.";
      expectHas(test, r.section.body, want);
      let revisions = worksRevisions(h.db, h.work.id);
      expectText(test, revisions[0].after, want);
      let work = worksGetWork(h.db, h.scope, h.work.id);
      var body = worksBaseline(h.db, work);
      for (let rev of revisions) { body = worksReplaceFirst(body, rev.before, rev.after); }
      expectText(test, body, work.body);
    }

    test("replay names the first revision whose before has gone") { test =>
      let h = histFixture();
      let b = blockWith(h.section, "ALPHA");
      worksReplaceBlock(h.db, h.section, b, swap(b, "ALPHA", "AMENDED"), null, null);
      h.db.exec("UPDATE revisions SET \"before\" = 'nothing like it' WHERE work_id = $1", [h.work.id.toString()]);
      let replayed = worksReplay(h.db, h.work.id);
      expectTrue(test, replayed.ok == null, "no body");
      expectInt(test, orZero(replayed.failedSeq), 1);
    }
