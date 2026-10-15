# Tests for corrections, attachments, document summaries and the small helpers

Ported from `editor_tools_test` (corrections), `document_test` and
`summarise_folder_test` (document summaries), and the `Attachment` rules of
the spec (section 1.9), plus the text helpers the context is built on.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { sysJoin, sysByteLength } = import("sys/src");
    let { FieldError } = import("core/src");

    class WorksRecFx(public db: Db, public scope: Scope, public work: Work) {}

    let recFixture(): WorksRecFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      new WorksRecFx(db, me, makeWork(db, me, "W", "one two three"))
    }

    let fieldText(errors: List<FieldError>): String {
      sysJoin(errors.map { (e: FieldError): String => "${e.field} ${e.message}" }, "; ")
    }

    let kindOf(r: AttachmentResult): String {
      let a = r.attachment;
      if (a != null) { a.kind } else { "none" }
    }

## Corrections

    test("a misread is stored and comes back first from the list") { test =>
      let f = recFixture();
      let r = worksRecordCorrection(f.db, new CorrectionParams(f.work.id, "misread", "Del leaves in ch 3"));
      let c = r.correction;
      expectText(test, if (c != null) { c.kind } else { "none" }, "misread");
      expectText(test, if (c != null) { c.about } else { "none" }, "Del leaves in ch 3");
      expectTrue(test, if (c != null) { c.ruling == null } else { false }, "no ruling");
      let p = new CorrectionParams(f.work.id, "ruling", "the prologue should go");
      p.ruling = "I want the prologue. It stays.";
      p.sectionOrdinal = 1;
      worksRecordCorrection(f.db, p);
      let all = worksListCorrections(f.db, f.work.id);
      expectInt(test, all.length, 2);
      expectText(test, all[0].kind, "ruling");
      expectText(test, orNull(all[0].ruling), "I want the prologue. It stays.");
      expectInt(test, orZero(all[0].sectionOrdinal), 1);
      expectText(test, all[1].kind, "misread");
    }

    test("an unknown kind is refused rather than stored") { test =>
      let f = recFixture();
      let r = worksRecordCorrection(f.db, new CorrectionParams(f.work.id, "vibes", "x"));
      expectTrue(test, r.correction == null, "refused");
      expectText(test, fieldText(r.errors), "kind is invalid");
      expectInt(test, worksListCorrections(f.db, f.work.id).length, 0);
    }

    test("a correction needs a kind and something said, and neither runs past 1000") { test =>
      let f = recFixture();
      expectText(test, fieldText(worksRecordCorrection(f.db, new CorrectionParams(f.work.id, "", " ")).errors), "kind can't be blank; about can't be blank");
      expectText(test, fieldText(worksRecordCorrection(f.db, new CorrectionParams(f.work.id, "misread", repeated("x", 1001))).errors), "about should be at most 1000 character(s)");
      let p = new CorrectionParams(f.work.id, "ruling", "x");
      p.ruling = repeated("y", 1001);
      expectText(test, fieldText(worksRecordCorrection(f.db, p).errors), "ruling should be at most 1000 character(s)");
      expectTrue(test, worksRecordCorrection(f.db, new CorrectionParams(f.work.id, "misread", repeated("x", 1000))).correction != null, "1000 is allowed");
    }

## Attachments

    test("an attachment keeps its content and knows its size in bytes") { test =>
      let f = recFixture();
      let r = worksAttach(f.db, f.work.id, "notes.txt", null, "caf\u{e9}");
      let a = r.attachment;
      expectText(test, if (a != null) { a.kind } else { "none" }, "text");
      expectInt(test, if (a != null) { a.byteSize } else { -1 }, 5);
      expectText(test, if (a != null) { a.name } else { "none" }, "notes.txt");
      expectText(test, if (a != null) { a.content } else { "none" }, "caf\u{e9}");
    }

    test("a patch is detected by its content or its name") { test =>
      let f = recFixture();
      let byContent = worksAttach(f.db, f.work.id, "change", null, "\n  diff --git a/x b/x\n+one");
      expectText(test, kindOf(byContent), "diff");
      let byPatch = worksAttach(f.db, f.work.id, "fix.patch", "text", "plain words");
      expectText(test, kindOf(byPatch), "diff");
      let byDiff = worksAttach(f.db, f.work.id, "fix.diff", "", "plain words");
      expectText(test, kindOf(byDiff), "diff");
      let plain = worksAttach(f.db, f.work.id, "readme", "text", "diff is a word here");
      expectText(test, kindOf(plain), "text");
      let declared = worksAttach(f.db, f.work.id, "declared", "diff", "no markers");
      expectText(test, kindOf(declared), "diff");
    }

    test("a kind other than diff or text is invalid, and a blank name or content") { test =>
      let f = recFixture();
      expectText(test, fieldText(worksAttach(f.db, f.work.id, "x", "image", "y").errors), "kind is invalid");
      expectText(test, fieldText(worksAttach(f.db, f.work.id, " ", "text", "y").errors), "name can't be blank");
      expectText(test, fieldText(worksAttach(f.db, f.work.id, "x", "text", "  ").errors), "content can't be blank");
      expectInt(test, worksListAttachments(f.db, f.work.id).length, 0);
    }

    test("a name is unique within a work and free in another") { test =>
      let f = recFixture();
      let other = makeWork(f.db, f.scope, "Other", "one two three");
      expectTrue(test, worksAttach(f.db, f.work.id, "a.txt", null, "one").attachment != null, "first");
      let again = worksAttach(f.db, f.work.id, "a.txt", null, "two");
      expectTrue(test, again.attachment == null, "refused");
      expectText(test, fieldText(again.errors), "work_id has already been taken");
      expectTrue(test, worksAttach(f.db, other.id, "a.txt", null, "two").attachment != null, "another work");
      let listed = worksListAttachments(f.db, f.work.id);
      expectInt(test, listed.length, 1);
      expectText(test, listed[0].content, "one");
      let found = worksGetAttachment(f.db, f.work.id, "a.txt");
      expectText(test, if (found != null) { found.content } else { "none" }, "one");
      expectTrue(test, worksGetAttachment(f.db, f.work.id, "b.txt") == null, "no such name");
    }

    test("attachments are listed in the order they came") { test =>
      let f = recFixture();
      worksAttach(f.db, f.work.id, "b", null, "1");
      worksAttach(f.db, f.work.id, "a", null, "2");
      let names = worksListAttachments(f.db, f.work.id).map { (a: Attachment): String => a.name };
      expectText(test, sysJoin(names, ","), "b,a");
    }

## Document summaries

    test("a work has no document summary until one is saved") { test =>
      let f = recFixture();
      expectTrue(test, worksGetDocumentSummary(f.db, f.work.id) == null, "none yet");
    }

    test("saving a document summary stores the lists and a second save updates the one row") { test =>
      let f = recFixture();
      let p = new DocumentSummaryParams(f.work.id);
      p.summary = "The whole thing.";
      p.throughline = "Nothing runs until the emitter is generated.";
      p.fingerprint = "f1";
      p.movementsJson = "[{\"heading\":\"One\",\"sections\":[1,2],\"does\":\"sets up\"}]";
      p.guidelinesJson = "[{\"guideline\":\"Name the failing case first.\",\"because\":\"It locates the fix.\",\"sections\":[2]}]";
      p.dropped = ["a citation to section 9: not a section here"];
      let saved = worksSaveDocumentSummary(f.db, p);
      expectText(test, orNull(saved.summary), "The whole thing.");
      expectText(test, orNull(saved.fingerprint), "f1");
      expectInt(test, saved.movements.length, 1);
      expectInt(test, saved.guidelines.length, 1);
      expectInt(test, saved.tensions.length, 0);
      expectText(test, saved.tensionsJson, "[]");
      expectInt(test, saved.dropped.length, 1);
      let q = new DocumentSummaryParams(f.work.id);
      q.summary = "Reworded.";
      q.fingerprint = "f2";
      let again = worksSaveDocumentSummary(f.db, q);
      expectInt(test, again.id, saved.id);
      expectText(test, orNull(again.summary), "Reworded.");
      expectText(test, orNull(again.throughline), "Nothing runs until the emitter is generated.");
      expectInt(test, again.movements.length, 1);
      expectInt(test, again.dropped.length, 1);
      expectInt(test, count(f.db, "SELECT count(*) AS n FROM document_summaries"), 1);
    }

    test("there is one document summary per work, and it goes with the work") { test =>
      let f = recFixture();
      let p = new DocumentSummaryParams(f.work.id);
      p.summary = "x";
      worksSaveDocumentSummary(f.db, p);
      expectTrue(test, didBubble(f.db, "INSERT INTO document_summaries (work_id) VALUES (${f.work.id.toString()})"), "unique per work");
      worksDeleteWork(f.db, f.work);
      expectInt(test, count(f.db, "SELECT count(*) AS n FROM document_summaries"), 0);
    }

    test("items given as JSON text come back as parsed items, and as text") { test =>
      let f = recFixture();
      let p = new DocumentSummaryParams(f.work.id);
      p.tensionsJson = "[{\"tension\":\"speed against care\",\"sections\":[1]}, {\"tension\":\"x\",\"sections\":[]}]";
      let saved = worksSaveDocumentSummary(f.db, p);
      expectInt(test, saved.tensions.length, 2);
      expectText(test, worksJsonItems(saved.tensions), "[{\"tension\":\"speed against care\",\"sections\":[1]},{\"tension\":\"x\",\"sections\":[]}]");
    }

## The helpers

    test("trim is Unicode trim and replace_first replaces one occurrence") { test =>
      expectText(test, worksTrim("\u{a0} a b \n\u{3000}"), "a b");
      expectText(test, worksTrimLeading("  a "), "a ");
      expectText(test, worksTrimTrailing(" a  \n"), " a");
      expectText(test, worksReplaceFirst("a-b-a", "a", "X"), "X-b-a");
      expectText(test, worksReplaceFirst("abc", "z", "X"), "abc");
      expectText(test, worksReplaceFirst("abc", "", "X"), "abc");
      expectText(test, worksReplaceFirst("a\n\nb\n\nc", "\n\n", "|"), "a|b\n\nc");
      expectTrue(test, worksContains("abc", ""), "empty is contained");
      expectTrue(test, worksContains("abc", "bc"), "contained");
      expectFalse(test, worksContains("abc", "bd"), "not contained");
    }

    test("collapse folds ASCII whitespace runs") { test =>
      expectText(test, worksCollapse("  a \n\t b\r\n\u{b}c  "), "a b c");
      expectText(test, worksCollapse("   "), "");
    }

    test("fold absorbs case, typography and spacing") { test =>
      expectText(test, worksFold("It\u{2019}s \u{201c}Fine\u{201d} \u{2014} yes\u{2026}  ok\u{a0}now"), "it's \"fine\" - yes... ok now");
    }

    test("a quote must be eight characters and in the text") { test =>
      let folded = worksFold("The kettle went cold on the counter.\nNobody moved.");
      expectTrue(test, worksQuoteHolds("kettle went cold", folded), "inside");
      expectTrue(test, worksQuoteHolds("  THE KETTLE went cold ", folded), "case and edges");
      expectTrue(test, worksQuoteHolds("counter. Nobody", folded), "across a line break");
      expectFalse(test, worksQuoteHolds("kettle", folded), "too short");
      expectFalse(test, worksQuoteHolds("went hot on the counter", folded), "not there");
      expectFalse(test, worksQuoteHolds(null, folded), "no quote");
      expectFalse(test, worksQuoteHolds("Nobody moved. Then", folded), "paraphrase");
    }

    test("code points are sliced by position") { test =>
      expectText(test, worksSliceCp("abcdef", 2, 3), "cde");
      expectText(test, worksSliceCp("abc", 5, 3), "");
      expectText(test, worksSliceCp("abc", 1, 99), "bc");
      expectInt(test, worksCodePoints("caf\u{e9}"), 4);
      expectText(test, worksTake("abcdef", 3), "abc");
      expectText(test, worksTake("ab", 3), "ab");
    }

    test("JSON arrays are written with escapes") { test =>
      expectText(test, worksJsonStrings(["a", "b\"c", "d\ne"]), "[\"a\",\"b\\\"c\",\"d\\ne\"]");
      expectText(test, worksJsonStrings([]), "[]");
      expectText(test, worksJsonInts([1, 22, 3]), "[1,22,3]");
    }

    test("a section reads its summary columns as lists") { test =>
      let f = recFixture();
      let s = firstSection(f.db, f.work);
      f.db.exec(
        "UPDATE sections SET summary = 'x', summary_covers = $1, summary_follows = '[1,2]', summary_dropped = $2 WHERE id = $3",
        [worksJsonStrings(["the out-grammar", "kcodegen"]), worksJsonStrings(["a"]), s.id.toString()],
      );
      let again = worksSectionById(f.db, s.id);
      if (again != null) {
        expectText(test, sysJoin(again.summaryCovers, ","), "the out-grammar,kcodegen");
        expectInt(test, again.summaryFollows.length, 2);
        expectInt(test, again.summaryFollows[1], 2);
        expectInt(test, again.summaryDropped.length, 1);
        expectText(test, orNull(again.summary), "x");
      } else {
        expectTrue(test, false, "the section is there");
      }
    }
