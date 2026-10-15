# Tests for works, sections and uploads

Ported from `works`, `sentences_works`, `work_upload_fallback` and `guest_upload`
in `notes/tests.md`, plus the rules the notes state for `Work.changeset`.

    let { wordCount } = import("html/src");
    let { FieldError } = import("core/src");
    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { sysJoin, sysUtcNow } = import("sys/src");

    let wrapped(): String {
      "# A draft\n\nShe had been standing at the window for an hour\nbefore anyone noticed. The kettle went cold on\nthe counter. Nobody moved to fill it again.\n\nBy evening the argument had found its real\nsubject, which was not the kettle. It was the\nwindow.\n"
    }

    let errorText(errors: List<FieldError>): String {
      sysJoin(errors.map { (e: FieldError): String => "${e.field} ${e.message}" }, "; ")
    }

## Creating a work

    test("a hard-wrapped upload is stored one sentence per line") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "W", wrapped());
      let sections = worksListSections(db, w.id);
      expectInt(test, sections.length, 1);
      expectText(test, sections[0].body,
        "# A draft\n\nShe had been standing at the window for an hour before anyone noticed.\nThe kettle went cold on the counter.\nNobody moved to fill it again.\n\nBy evening the argument had found its real subject, which was not the kettle.\nIt was the window.");
    }

    test("the baseline is the reflowed body, so the replay starts from what is stored") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "W", wrapped());
      expectText(test, orEmpty(w.baselineBody), w.body);
      expectHas(test, w.body, "before anyone noticed.\nThe kettle");
    }

    test("reflowing does not change the word count") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "W", wrapped());
      expectInt(test, w.wordCount, 47);
      expectInt(test, w.wordCount, wordCount(wrapped()));
    }

    test("a windowed draft's title is its first sentence, not a wrapped fragment") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "The opening\nsentence is the title of this section, whole. Then more. ${repeated("word ", 40)}";
      let w = makeWork(db, me, "W", body);
      let sections = worksListSections(db, w.id);
      expectInt(test, sections.length, 1);
      expectHas(test, sections[0].title, "The opening sentence is the title");
      expectTrue(test, sections[0].title != "Section 1", "not the default title");
    }

    test("a quote spanning two sentences still anchors in the stored text") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "W", wrapped());
      let s = firstSection(db, w);
      expectTrue(test, worksQuoteHolds("went cold on the counter. Nobody moved", worksFold(s.body)), "the flat quote anchors");
      expectFalse(test, worksQuoteHolds("went cold on the stove. Nobody moved", worksFold(s.body)), "a different quote does not");
    }

    test("a work has a 22 character slug, pending status and a word count") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "W", "# H\n\n${repeated("word ", 300)}");
      expectInt(test, w.slug.countBetween(String.begin, w.slug.end), 22);
      expectText(test, w.status, "pending");
      expectInt(test, w.wordCount, 302);
      expectTrue(test, w.statusDetail == null, "no detail");
      expectTrue(test, w.folderId == null, "no folder");
      expectInt(test, w.userId, userIdOf(me));
    }

    test("slugs are url safe and differ between works") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let a = makeWork(db, me, "A", "one two three");
      let b = makeWork(db, me, "B", "one two three");
      expectTrue(test, a.slug != b.slug, "two slugs");
      expectFalse(test, hasText(a.slug, "+"), "no plus");
      expectFalse(test, hasText(a.slug, "/"), "no slash");
      expectFalse(test, hasText(a.slug, "="), "no padding");
    }

    test("sections are numbered from one with their own word counts") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "# The Opening\n\n${repeated("alpha ", 300)}\n\n# The Middle\n\n${repeated("beta ", 300)}\n\n# The End\n\n${repeated("gamma ", 300)}";
      let w = makeWork(db, me, "W", body);
      let sections = worksListSections(db, w.id);
      expectInt(test, sections.length, 3);
      expectText(test, titlesOf(sections), "The Opening | The Middle | The End");
      expectInt(test, sections[0].ordinal, 1);
      expectInt(test, sections[2].ordinal, 3);
      expectInt(test, sections[1].wordCount, 300);
      expectText(test, sections[1].status, "pending");
      expectTrue(test, sections[0].summary == null, "no summary");
      expectInt(test, sections[0].summaryCovers.length, 0);
    }

    test("the body is the sections joined, so headings lifted into titles leave it") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "# The Opening\n\n${repeated("alpha ", 300)}\n\n# The Middle\n\n${repeated("beta ", 300)}";
      let w = makeWork(db, me, "W", body);
      expectLacks(test, w.body, "The Opening");
      expectHas(test, w.body, "alpha");
      expectHas(test, w.body, "\n\nbeta");
      expectInt(test, w.wordCount, 606);
      expectText(test, orEmpty(w.baselineBody), w.body);
    }

    test("chapter markers become sections and the work keeps one row each") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "prologue ${repeated("word ", 300)}\n\nChapter 1\n\n${repeated("one ", 300)}\n\nChapter 2\n\n${repeated("two ", 300)}";
      let w = makeWork(db, me, "W", body);
      let sections = worksListSections(db, w.id);
      expectInt(test, sections.length, 3);
      expectText(test, sections[0].title, "Opening");
      expectText(test, sections[1].title, "Chapter 1");
      expectText(test, sections[2].title, "Chapter 2");
    }

## The upload rules

    test("an empty body is refused with the changeset message") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let r = worksCreateWork(db, me, workParams("T", "  \n\t "));
      expectTrue(test, r.ok == null, "nothing created");
      expectText(test, orEmpty(r.error), "empty");
      expectText(test, errorText(r.errors), "body can't be blank");
      expectInt(test, count(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("a missing body is the same as an empty one") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let r = worksCreateWork(db, me, workParams("T", null));
      expectText(test, orEmpty(r.error), "empty");
    }

    test("a draft over the word limit is refused with the sentence to show") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let r = worksCreateWork(db, me, workParams("T", repeated("word ", 131072)));
      expectText(test, orEmpty(r.error), "too_long");
      expectText(test, orEmpty(r.message), "That's 131,072 words, and the limit is 120,000 for now. Split it and upload the first part.");
      expectInt(test, count(db, "SELECT count(*) AS n FROM works"), 0);
    }

    test("a blank title becomes Untitled draft and the title is trimmed") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let a = makeWork(db, me, "   ", "some words here");
      expectText(test, a.title, "Untitled draft");
      let b = makeWork(db, me, "  Anon  ", "some words here");
      expectText(test, b.title, "Anon");
      let c = worksCreateWork(db, me, workParams(null, "some words here")).ok;
      expectText(test, if (c != null) { c.title } else { "none" }, "Untitled draft");
    }

    test("intent is trimmed and blank intent is nothing") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let p = workParams("T", "some words here");
      p.intent = "   make them wait  ";
      let a = worksCreateWork(db, me, p).ok;
      expectText(test, if (a != null) { orNull(a.intent) } else { "none" }, "make them wait");
      let q = workParams("T", "some words here");
      q.intent = "   ";
      let b = worksCreateWork(db, me, q).ok;
      expectText(test, if (b != null) { orNull(b.intent) } else { "none" }, "NULL");
    }

    test("the body is kept untrimmed in the word count and trimmed by the segmenter") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "T", "\n\n  one two three  \n\n");
      expectInt(test, w.wordCount, 3);
      expectText(test, w.body, "one two three");
    }

    test("a title of 200 characters is allowed and 201 is not") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let ok = worksCreateWork(db, me, workParams(repeated("t", 200), "some words here"));
      expectTrue(test, ok.ok != null, "200 is fine");
      let bad = worksCreateWork(db, me, workParams(repeated("t", 201), "some words here"));
      expectTrue(test, bad.ok == null, "201 is not");
      expectText(test, orEmpty(bad.error), "invalid");
      expectText(test, errorText(bad.errors), "title should be at most 200 character(s)");
    }

    test("a status outside the four is invalid") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let p = workParams("T", "some words here");
      p.status = "done";
      let r = worksCreateWork(db, me, p);
      expectText(test, errorText(r.errors), "status is invalid");
    }

    test("optional attributes are cast, an empty string is nothing") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let p = workParams("T", "some words here");
      p.sourceUrl = "https://example.com/a";
      p.collection = "A case";
      p.collectionRole = "";
      let w = worksCreateWork(db, me, p).ok;
      expectText(test, if (w != null) { orNull(w.sourceUrl) } else { "none" }, "https://example.com/a");
      expectText(test, if (w != null) { orNull(w.collection) } else { "none" }, "A case");
      expectText(test, if (w != null) { orNull(w.collectionRole) } else { "none" }, "NULL");
    }

    test("a work can say which draft it condenses") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let long = makeWork(db, me, "The long version", "one two three");
      let p = workParams("The short version", "one two");
      p.derivedFromId = long.id;
      let short = worksCreateWork(db, me, p).ok;
      expectTrue(test, short != null, "created");
      if (short != null) {
        expectInt(test, orZero(short.derivedFromId), long.id);
        let found = worksCondensationOf(db, long.id);
        expectInt(test, if (found != null) { found.id } else { -1 }, short.id);
        expectTrue(test, worksCondensationOf(db, short.id) == null, "a work nobody condenses");
      }
    }

    test("condensation_of takes the newest") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let long = makeWork(db, me, "Long", "one two three");
      let p = workParams("First", "one two");
      p.derivedFromId = long.id;
      worksCreateWork(db, me, p);
      let q = workParams("Second", "one two");
      q.derivedFromId = long.id;
      let second = worksCreateWork(db, me, q).ok;
      let found = worksCondensationOf(db, long.id);
      expectText(test, if (found != null) { found.title } else { "none" }, "Second");
      expectTrue(test, second != null, "created");
    }

## Reading works

    test("a user finds their own work and nobody else's") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let them = makeUser(db, "b@example.com");
      let w = makeWork(db, me, "Mine", "one two three");
      let mine = worksFindWork(db, me, w.id);
      expectText(test, if (mine != null) { mine.title } else { "none" }, "Mine");
      expectTrue(test, worksFindWork(db, them, w.id) == null, "not theirs");
      expectTrue(test, worksFindWork(db, new Scope(null), w.id) == null, "not a visitor's");
      let bubbled = do { worksGetWork(db, them, w.id); false } orelse true;
      expectTrue(test, bubbled, "the bang form bubbles");
      expectText(test, worksGetWork(db, me, w.id).title, "Mine");
    }

    test("list_works is the user's own, newest first") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let them = makeUser(db, "b@example.com");
      makeWork(db, me, "First", "one two three");
      makeWork(db, them, "Theirs", "one two three");
      makeWork(db, me, "Second", "one two three");
      let titles = worksListWorks(db, me).map { (w: Work): String => w.title };
      expectText(test, sysJoin(titles, ","), "Second,First");
      expectInt(test, worksListWorks(db, new Scope(null)).length, 0);
      expectInt(test, worksCountByUser(db, userIdOf(me)), 2);
      expectInt(test, worksCountByUser(db, userIdOf(them)), 1);
    }

    test("the slug is the permission to read") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "Mine", "one two three");
      let found = worksGetBySlug(db, w.slug);
      expectInt(test, if (found != null) { found.id } else { -1 }, w.id);
      expectTrue(test, worksGetBySlug(db, "nope") == null, "unknown slug");
      expectTrue(test, worksGetBySlug(db, null) == null, "non-binary slug");
    }

    test("only the owner's account has public drafts") { test =>
      let db = dbOpen(":memory:");
      let owner = makeUser(db, "owner@example.com");
      let visitor = makeUser(db, "visitor@example.com");
      let mine = makeWork(db, owner, "Mine", "one two three");
      let theirs = makeWork(db, visitor, "Theirs", "one two three");
      expectInt(test, worksPublicDrafts(db, null).length, 0);
      let drafts = worksPublicDrafts(db, userIdOf(owner));
      expectInt(test, drafts.length, 1);
      expectText(test, drafts[0].title, "Mine");
      expectTrue(test, worksPublicDraft(db, userIdOf(owner), theirs.slug) == null, "not an owner's draft");
      expectTrue(test, worksPublicDraft(db, null, mine.slug) == null, "no owner configured");
      let found = worksPublicDraft(db, userIdOf(owner), mine.slug);
      expectInt(test, if (found != null) { found.id } else { -1 }, mine.id);
    }

    test("owner? is true only for the owner, and a nobody owns nothing") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let them = makeUser(db, "b@example.com");
      let w = makeWork(db, me, "Mine", "one two three");
      expectTrue(test, worksIsOwner(w, me.user), "owner");
      expectFalse(test, worksIsOwner(w, them.user), "other");
      expectFalse(test, worksIsOwner(w, null), "nobody");
    }

## Changing works

    test("change_work shows the changeset errors with Ecto's messages") { test =>
      expectText(test, errorText(worksChangeWork(null, workParams("", ""))), "title can't be blank; body can't be blank");
      expectText(test, errorText(worksChangeWork(null, workParams(null, null))), "title can't be blank; body can't be blank");
      expectText(test, errorText(worksChangeWork(null, workParams("  ", "text"))), "title can't be blank");
      expectText(test, errorText(worksChangeWork(null, workParams("T", "text"))), "");
      let p = workParams("T", "text");
      p.status = "bogus";
      expectText(test, errorText(worksChangeWork(null, p)), "status is invalid");
    }

    test("update_work changes what is given, recounts words, keeps the slug") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "Old", "one two three");
      let p = workParams("New", null);
      p.intent = "to land softly";
      let r = worksUpdateWork(db, w, p).ok;
      expectText(test, if (r != null) { r.title } else { "none" }, "New");
      expectText(test, if (r != null) { orNull(r.intent) } else { "none" }, "to land softly");
      expectText(test, if (r != null) { r.body } else { "none" }, w.body);
      let q = workParams(null, "one two three four five");
      let r2 = worksUpdateWork(db, w, q).ok;
      expectInt(test, if (r2 != null) { r2.wordCount } else { -1 }, 5);
      expectText(test, if (r2 != null) { r2.slug } else { "none" }, w.slug);
      let clear = workParams(null, null);
      clear.intent = "";
      let r3 = worksUpdateWork(db, w, clear).ok;
      expectText(test, if (r3 != null) { orNull(r3.intent) } else { "none" }, "NULL");
    }

    test("update_work validates like create") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "Old", "one two three");
      let r = worksUpdateWork(db, w, workParams("", null));
      expectTrue(test, r.ok == null, "refused");
      expectText(test, errorText(r.errors), "title can't be blank");
      let s = workParams(null, null);
      s.status = "weird";
      expectText(test, errorText(worksUpdateWork(db, w, s).errors), "status is invalid");
      expectText(test, worksGetWork(db, me, w.id).title, "Old");
    }

    test("set_status sets status and detail, unvalidated, and the detail replaces the last") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "W", "one two three");
      let reading = worksSetStatus(db, w, "reading", null);
      expectText(test, reading.status, "reading");
      let read = worksSetStatus(db, reading, "read", "spine unavailable: :no_beats");
      expectText(test, read.status, "read");
      expectText(test, orNull(read.statusDetail), "spine unavailable: :no_beats");
      let clean = worksSetStatus(db, read, "read", null);
      expectText(test, orNull(clean.statusDetail), "NULL");
      let odd = worksSetStatus(db, clean, "anything at all", null);
      expectText(test, odd.status, "anything at all");
    }

    test("a status detail longer than 255 characters is cut to 255") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "W", "one two three");
      let long = "spine unavailable: {:http, 500, ${repeated("x", 300)}}";
      let r = worksSetStatus(db, w, "read", long);
      let kept = orEmpty(r.statusDetail);
      expectInt(test, kept.countBetween(String.begin, kept.end), 255);
      expectTrue(test, hasText(long, kept), "it is a prefix of what was said");
      expectText(test, r.status, "read");
    }

    test("deleting a work takes its sections, nodes and history, and frees the condensation") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let long = makeWork(db, me, "Long", "# H\n\n${repeated("word ", 300)}");
      let p = workParams("Short", "one two");
      p.derivedFromId = long.id;
      let short = worksCreateWork(db, me, p).ok;
      let s = firstSection(db, long);
      addBeat(db, long, s, "A beat", null);
      worksRecordCorrection(db, new CorrectionParams(long.id, "misread", "a fact"));
      worksAttach(db, long.id, "a.txt", null, "text");
      expectTrue(test, worksDeleteWork(db, long), "deleted");
      expectInt(test, count(db, "SELECT count(*) AS n FROM sections WHERE work_id = ${long.id.toString()}"), 0);
      expectInt(test, count(db, "SELECT count(*) AS n FROM nodes"), 0);
      expectInt(test, count(db, "SELECT count(*) AS n FROM corrections"), 0);
      expectInt(test, count(db, "SELECT count(*) AS n FROM work_attachments"), 0);
      expectTrue(test, worksGetById(db, long.id) == null, "gone");
      if (short != null) {
        let kept = worksGetById(db, short.id);
        expectTrue(test, kept != null, "the condensation survives");
        expectTrue(test, if (kept != null) { kept.derivedFromId == null } else { false }, "and stands alone");
      }
    }

    test("deleting a user takes their works") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      makeWork(db, me, "W", "one two three");
      db.exec("DELETE FROM users", []);
      expectInt(test, count(db, "SELECT count(*) AS n FROM works"), 0);
      expectInt(test, count(db, "SELECT count(*) AS n FROM sections"), 0);
    }

    test("move_to_folder files a work, and a stranger's folder lands it at the top") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let them = makeUser(db, "b@example.com");
      let w = makeWork(db, me, "W", "one two three");
      let mine = db.insert("INSERT INTO folders (name, user_id) VALUES ('Mine', $1)", [userIdOf(me).toString()]);
      let theirs = db.insert("INSERT INTO folders (name, user_id) VALUES ('Theirs', $1)", [userIdOf(them).toString()]);
      let moved = worksMoveToFolder(db, me, w.id, mine);
      expectInt(test, if (moved != null) { orZero(moved.folderId) } else { -1 }, mine);
      let forged = worksMoveToFolder(db, me, w.id, theirs);
      expectTrue(test, if (forged != null) { forged.folderId == null } else { false }, "a forged parent lands at the root");
      let again = worksMoveToFolder(db, me, w.id, mine);
      let out = worksMoveToFolder(db, me, w.id, null);
      expectTrue(test, if (out != null) { out.folderId == null } else { false }, "moved out");
      expectTrue(test, again != null, "moved in again");
      expectTrue(test, worksMoveToFolder(db, them, w.id, theirs) == null, "not their work");
    }

## Sections

    test("sections are listed in order, found by ordinal, and their status changes") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "# One\n\n${repeated("alpha ", 300)}\n\n# Two\n\n${repeated("beta ", 300)}";
      let w = makeWork(db, me, "W", body);
      let two = worksGetSection(db, w.id, 2);
      expectText(test, if (two != null) { two.title } else { "none" }, "Two");
      expectTrue(test, worksGetSection(db, w.id, 3) == null, "no third");
      if (two != null) {
        let reading = worksSetSectionStatus(db, two, "reading");
        expectText(test, reading.status, "reading");
        let again = worksGetSection(db, w.id, 2);
        expectText(test, if (again != null) { again.status } else { "none" }, "reading");
        let byId = worksSectionById(db, two.id);
        expectInt(test, if (byId != null) { byId.ordinal } else { -1 }, 2);
      }
    }

    test("ordinals are unique per work") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let w = makeWork(db, me, "W", "one two three");
      expectTrue(test, didBubble(db, "INSERT INTO sections (work_id, ordinal, title, body) VALUES (${w.id.toString()}, 1, 'x', 'y')"), "duplicate ordinal refused");
    }

## Atomicity and page text

    test("a failure while writing the sections leaves no work behind") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      db.script("CREATE TRIGGER no_boom BEFORE INSERT ON sections WHEN NEW.title = 'boom' BEGIN SELECT RAISE(ABORT, 'boom'); END");
      let body = "# boom\n\n${repeated("alpha ", 300)}\n\n# other\n\n${repeated("beta ", 300)}";
      let failed = do { worksCreateWork(db, me, workParams("T", body)); false } orelse true;
      expectTrue(test, failed, "the bubble comes out");
      expectInt(test, count(db, "SELECT count(*) AS n FROM works"), 0);
      expectInt(test, count(db, "SELECT count(*) AS n FROM sections"), 0);
      expectFalse(test, db.inTransaction(), "the transaction is closed");
      let again = makeWork(db, me, "T", "# fine\n\n${repeated("alpha ", 300)}\n\n# other\n\n${repeated("beta ", 300)}");
      expectInt(test, worksListSections(db, again.id).length, 2);
    }

    let pdfLines(): String {
      let long = "aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddddd eeeeeeeeee ffffffffff";
      let paragraph = "${long}\n${long}\n${long}\ntail words here.\n";
      repeated(paragraph, 4)
    }

    test("page text is reflowed into paragraphs only when asked") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let plain = makeWork(db, me, "Plain", pdfLines());
      expectLacks(test, plain.body, "\n\n");
      let p = workParams("Pdf", pdfLines());
      p.reflowWrapped = true;
      let reflowed = worksCreateWork(db, me, p).ok;
      expectTrue(test, reflowed != null, "created");
      if (reflowed != null) {
        expectHas(test, reflowed.body, "\n\n");
        expectInt(test, reflowed.body.split("\n\n").length, 4);
      }
    }
