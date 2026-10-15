# Tests for landing a pile

`test/marginalia/import_bulk_test.exs`, ported assertion for assertion, with
`Marginalia.Import.Bulk.by_title/2` against its regex engine and the cases the
Elixir leaves to `PCRE`. The behaviour worth pinning down is what happens to
the batch when one of it is bad, and what counts as already having something. A
bulk import that rolls back thirty-nine good documents because the fortieth was
empty is an import nobody uses twice, and one that has no idea it already ran
doubles the folder every time somebody presses the button again.

    let { Db, DbRow, dbOpen } = import("db/src");
    let { Folder, foldersCreateFolder, foldersListFolders } = import("folders/src");
    let { Work } = import("works/src");

    let doc(title: String): ImporterDoc {
      new ImporterDoc(title, "# ${title}\n\n${repeated("word ", 80)}", null)
    }

    let docBody(title: String, body: String): ImporterDoc {
      new ImporterDoc(title, body, null)
    }

    let workTitles(db: Db): String throws Bubble {
      let rows = db.query("SELECT title FROM works ORDER BY title", []);
      let titles = new ListBuilder<String>();
      var i = 0;
      while (i < rows.length) {
        titles.add(rows[i].str("title"));
        i += 1;
      }
      joinedText(titles.toList())
    }

    let createdTitles(r: ImporterLandResult): String {
      joinedText(r.created.map { (w: Work): String => w.title })
    }

    let folderName(f: Folder?): String {
      if (f != null) { f.name } else { "none" }
    }

    let sortedText(xs: List<String>): String {
      joinedText(xs.sorted { (a: String, b: String): Int => importerCompareText(a, b) })
    }

    test("each document becomes a draft in the folder") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let out = importerLand(db, me, "Pile", [doc("One"), doc("Two")]);
      expectInt(test, out.created.length, 2);
      expectInt(test, out.failed.length, 0);
      expectInt(test, out.skipped.length, 0);
      expectText(test, folderName(out.folder), "Pile");
      expectText(test, workTitles(db), "One|Two");
      let loose = db.query("SELECT id FROM works WHERE folder_id IS NULL", []);
      expectInt(test, loose.length, 0);
      let f = out.folder;
      let inFolder = db.query(
        "SELECT id FROM works WHERE folder_id = $1",
        [if (f != null) { f.id.toString() } else { "0" }],
      );
      expectInt(test, inFolder.length, 2);
    }

    test("running it twice does not double the folder") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      importerLand(db, me, "Pile", [doc("One"), doc("Two")]);
      let again = importerLand(db, me, "Pile", [doc("One"), doc("Two"), doc("Three")]);
      expectInt(test, again.created.length, 1);
      expectText(test, sortedText(again.skipped), "One|Two");
      expectInt(test, db.query("SELECT id FROM works", []).length, 3);
    }

    test("the same title in a different folder is a different document") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      importerLand(db, me, "Pile", [doc("One")]);
      let other = importerLand(db, me, "Other pile", [doc("One")]);
      expectInt(test, other.created.length, 1);
      expectInt(test, db.query("SELECT id FROM works", []).length, 2);
    }

    test("one bad document does not take the batch with it") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let out = importerLand(db, me, "Pile", [doc("Good"), docBody("Empty", "   "), doc("Also good")]);
      expectInt(test, out.created.length, 2);
      expectInt(test, out.failed.length, 1);
      expectText(test, out.failed[0].title, "Empty");
      expectHas(test, importerLandExplain(out.failed[0]), "no text");
      expectText(test, importerLandExplain(out.failed[0]), "there is no text in it");
    }

    test("an over-long document is named rather than swallowed") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let huge = docBody("Huge", repeated("word ", 130000));
      let out = importerLand(db, me, "Pile", [doc("Fine"), huge]);
      expectInt(test, out.created.length, 1);
      expectInt(test, out.failed.length, 1);
      expectText(test, out.failed[0].title, "Huge");
      expectHas(test, importerLandExplain(out.failed[0]), "over the limit");
      expectText(test, importerLandExplain(out.failed[0]), "130000 words, over the limit");
    }

    test("titles are not numbered unless asked") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      importerLand(db, me, "Plain", [doc("Alpha"), doc("Beta")]);
      expectText(test, workTitles(db), "Alpha|Beta");
    }

    test("numbering follows the order given, and leaves an existing number alone") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let out = importerLandWith(
        db, me, null, true, new ImporterSilent(),
        [doc("Alpha"), doc("2. Beta"), doc("Gamma")],
      );
      expectText(test, createdTitles(out), "1. Alpha|2. Beta|3. Gamma");
    }

    test("with no folder the drafts land loose") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let out = importerLand(db, me, null, [doc("Loose")]);
      expectTrue(test, out.folder == null, "no folder");
      let rows = db.query("SELECT folder_id FROM works", []);
      expectInt(test, rows.length, 1);
      expectTrue(test, rows[0].strOrNull("folder_id") == null, "loose");
    }

    test("a blank folder name is loose too, not a folder called nothing") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      expectTrue(test, importerLand(db, me, "   ", [doc("A")]).folder == null, "blank");
      expectTrue(test, importerLand(db, me, "", [doc("B")]).folder == null, "empty");
      expectInt(test, db.query("SELECT id FROM folders", []).length, 0);
    }

    test("an existing folder is reused, not duplicated") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let made = foldersCreateFolder(db, me, "Mine", null);
      let mine = made.folder;
      let out = importerLand(db, me, "Mine", [doc("One")]);
      let landed = out.folder;
      expectInt(test, if (landed != null) { landed.id } else { -1 }, if (mine != null) { mine.id } else { -2 });
      expectInt(test, foldersListFolders(db, me).length, 1);
    }

    test("the folder name is trimmed before it is looked up") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      importerLand(db, me, "Mine", [doc("One")]);
      importerLand(db, me, "  Mine  ", [doc("Two")]);
      expectInt(test, foldersListFolders(db, me).length, 1);
    }

    class ImporterTestLog extends ImporterListener {
      public var seen: ListBuilder<String> = new ListBuilder<String>();
      public item(title: String, index: Int, total: Int): Void {
        seen.add("${title}@${index.toString()}/${total.toString()}");
      }
    }

    test("progress is reported per document as it goes") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let log = new ImporterTestLog();
      importerLandWith(db, me, "Pile", false, log, [doc("One"), doc("Two")]);
      expectText(test, joinedText(log.seen.toList()), "One@1/2|Two@2/2");
    }

    test("progress is reported for skipped and failed documents too") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      importerLand(db, me, "Pile", [doc("One")]);
      let log = new ImporterTestLog();
      importerLandWith(db, me, "Pile", false, log, [doc("One"), docBody("Two", " "), doc("Three")]);
      expectText(test, joinedText(log.seen.toList()), "One@1/3|Two@2/3|Three@3/3");
    }

    test("duplicates inside one batch are not noticed, only those already in the folder") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let out = importerLand(db, me, "Pile", [doc("Same"), doc("Same")]);
      expectInt(test, out.created.length, 2);
      expectInt(test, out.skipped.length, 0);
    }

    test("the address a document came from is kept") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let d = new ImporterDoc("Linked", "# Linked\n\n${repeated("word ", 80)}", "https://example.com/a");
      importerLand(db, me, "Pile", [d, doc("Plain")]);
      let rows = db.query("SELECT title, source_url FROM works ORDER BY title", []);
      expectText(test, rows[0].str("source_url"), "https://example.com/a");
      expectTrue(test, rows[1].strOrNull("source_url") == null, "none for a file");
    }

    test("a title is cleaned: whitespace runs, blanks, and 200 characters") { test =>
      expectText(test, importerCleanTitle("  a \n\t b  "), "a b");
      expectText(test, importerCleanTitle(""), "Untitled");
      expectText(test, importerCleanTitle(" \n "), "Untitled");
      expectInt(test, importerCpCount(importerCleanTitle(repeated("x", 300))), 200);
    }

    test("a number is recognised however it is written") { test =>
      expectTrue(test, importerNumbered("1. First"), "dot");
      expectTrue(test, importerNumbered("  12) Twelve"), "paren, indented");
      expectTrue(test, importerNumbered("3: Three"), "colon");
      expectTrue(test, importerNumbered("4 - Four"), "dash");
      expectFalse(test, importerNumbered("1 First"), "no mark");
      expectFalse(test, importerNumbered("First 1."), "not at the front");
      expectFalse(test, importerNumbered("1"), "nothing after");
      expectFalse(test, importerNumbered(""), "empty");
    }

    test("an explanation for every kind of failure") { test =>
      expectText(test, importerLandExplain(new ImporterLandFailure("t", "empty", "")), "there is no text in it");
      expectText(
        test, importerLandExplain(new ImporterLandFailure("t", "no_sections", "")),
        "no text that could be split into sections",
      );
      expectText(test, importerLandExplain(new ImporterLandFailure("t", "text", "title can't be blank")), "title can't be blank");
      expectText(test, importerLandExplain(new ImporterLandFailure("t", "invalid", "")), ":invalid");
    }

## Filtering by title

    let cand(title: String): ImporterPull {
      new ImporterPull("a/b", 1, title, null, "open", false, null, null, null, null, null)
    }

    let kept(pattern: String?, titles: List<String>): String {
      let r = importerTitleFilter(pattern, titles.map { (t: String): ImporterPull => cand(t) });
      let why = r.error;
      if (why != null) { "ERROR ${why}" } else { titlesOf(r.kept) }
    }

    test("an empty pattern keeps everything") { test =>
      expectText(test, kept("", ["one", "two"]), "one|two");
      expectText(test, kept(null, ["one", "two"]), "one|two");
      expectText(test, kept("   ", ["one", "two"]), "one|two");
    }

    test("it matches anywhere in the title, ignoring case") { test =>
      expectText(test, kept("fix", ["Fix the parser", "Revert the fix", "Add a test"]), "Fix the parser|Revert the fix");
      expectText(test, kept("FIX", ["Fix the parser", "Add a test"]), "Fix the parser");
    }

    test("it is a real regex") { test =>
      expectText(test, kept("^\\d+\\.", ["1. First", "Later", "2. Second"]), "1. First|2. Second");
      expectText(test, kept("(first|later)$", ["1. First", "Later", "2. Second"]), "1. First|Later");
      expectText(test, kept("colou?r", ["color", "colour", "colr"]), "color|colour");
      expectText(test, kept("^a{2,3}$", ["a", "aa", "aaa", "aaaa"]), "aa|aaa");
      expectText(test, kept("^a{2}$", ["a", "aa", "aaa"]), "aa");
      expectText(test, kept("^a{2,}$", ["a", "aa", "aaaaa"]), "aa|aaaaa");
      expectText(test, kept("[a-c]+z", ["abcz", "xyz", "az"]), "abcz|az");
      expectText(test, kept("^[^a-c]", ["apple", "dog"]), "dog");
      expectText(test, kept("\\bfix\\b", ["prefix", "a fix here", "fix"]), "a fix here|fix");
      expectText(test, kept("\\Bfix", ["prefix", "fix"]), "prefix");
      expectText(test, kept("a.c", ["abc", "ac", "a\nc"]), "abc");
      expectText(test, kept("(ab)+c", ["ababc", "bc", "abc"]), "ababc|abc");
      expectText(test, kept("(?:ab)+c", ["ababc", "bc"]), "ababc");
      expectText(test, kept("a.*?b", ["a x b", "a x"]), "a x b");
      expectText(test, kept("\\.md$", ["notes.md", "notes.mdx"]), "notes.md");
      expectText(test, kept("\\x41", ["A", "B"]), "A");
      expectText(test, kept("\\x{42}", ["A", "B"]), "B");
      expectText(test, kept("a{,3}", ["a{,3}", "a"]), "a{,3}");
      expectText(test, kept("\\s", ["a b", "ab"]), "a b");
      expectText(test, kept("^\\S+$", ["a b", "ab"]), "ab");
      expectText(test, kept("\\w+@\\w+", ["me@here", "me at here"]), "me@here");
      expectText(test, kept("[\\d.]+", ["v1.2", "vx"]), "v1.2");
      expectText(test, kept("^[-a]+$", ["a-a", "ab"]), "a-a");
      expectText(test, kept("[]a]", ["]", "b"]), "]");
    }

    test("case folding reaches beyond ASCII") { test =>
      expectText(test, kept("é", ["CAFÉ", "cafe"]), "CAFÉ");
      expectText(test, kept("[a-c]", ["B"]), "B");
    }

    test("a pattern that will not compile says so rather than raising") { test =>
      let r = importerTitleFilter("(unclosed", [cand("x")]);
      let why = r.error;
      expectTrue(test, why != null, "an error");
      expectText(test, orNone(why), "missing ) at character 9");
      expectFalse(test, orNone(why).isEmpty, "not empty");
      expectInt(test, r.kept.length, 0);
    }

    test("each kind of half-typed pattern names what is wrong and where") { test =>
      expectText(test, kept(")", ["x"]), "ERROR unmatched parentheses at character 0");
      expectText(test, kept("a)", ["x"]), "ERROR unmatched parentheses at character 1");
      expectText(test, kept("[abc", ["x"]), "ERROR missing terminating ] for character class at character 4");
      expectText(test, kept("*a", ["x"]), "ERROR quantifier does not follow a repeatable item at character 0");
      expectText(test, kept("a**", ["x"]), "ERROR quantifier does not follow a repeatable item at character 2");
      expectText(test, kept("a\\", ["x"]), "ERROR \\ at end of pattern at character 2");
      expectText(test, kept("[z-a]", ["x"]), "ERROR range out of order in character class at character 3");
      expectText(test, kept("a{3,2}", ["x"]), "ERROR numbers out of order in {} quantifier at character 6");
    }

    test("what this engine cannot do is refused by name, never matched wrongly") { test =>
      expectHas(test, kept("(a)\\1", ["x"]), "back-references are not supported");
      expectHas(test, kept("(?=a)", ["x"]), "unrecognized character after (?");
      expectHas(test, kept("(?i)a", ["x"]), "unrecognized character after (?");
      expectHas(test, kept("a++", ["x"]), "possessive quantifiers are not supported");
      expectHas(test, kept("\\p{L}", ["x"]), "unsupported or unrecognized escape");
      expectHas(test, kept("[[:alpha:]]", ["x"]), "POSIX character classes are not supported");
      expectHas(test, kept("[\\D]", ["x"]), "negated shorthand classes inside [] are not supported");
    }

    test("a very long title cannot make the match run away") { test =>
      let long = "${repeated("a", 100000)}needle";
      expectText(test, kept("needle", [long]), "");
    }

    test("a pattern that backtracks without end fails to match instead of hanging") { test =>
      expectText(test, kept("(a+)+$", ["${repeated("a", 40)}b"]), "");
      expectText(test, kept("(a+)+$", ["${repeated("a", 6)}"]), repeated("a", 6));
    }

    test("the title is cut to 200 characters before matching") { test =>
      let title = "${repeated("a", 200)}needle";
      expectText(test, kept("needle", [title]), "");
      expectText(test, kept("a$", [title]), title);
    }

## folder_name_for

    test("files that share a stem are named for it") { test =>
      expectText(
        test, importerFolderNameFor([doc("chapter-01"), doc("chapter-02"), doc("chapter-03"), doc("chapter-07")]),
        "chapter",
      );
      expectText(test, importerFolderNameFor([doc("Part 1"), doc("Part 2")]), "Part");
      expectText(test, importerFolderNameFor([doc("notes_2024.1"), doc("notes_2024.2")]), "notes");
    }

    test("files with nothing in common are named for the moment") { test =>
      expectText(
        test, importerFolderNameForAt([doc("alpha"), doc("omega")], "2026-09-22 14:54:46"),
        "Imported 2026-09-22 14:54",
      );
      expectText(test, importerFolderNameForAt([], "2026-09-22 14:54:46"), "Imported 2026-09-22 14:54");
    }

    test("a stem too short to mean anything is not a name") { test =>
      expectText(
        test, importerFolderNameForAt([doc("a1"), doc("a2")], "2026-01-01 00:00:00"),
        "Imported 2026-01-01 00:00",
      );
    }

    test("one file is its own folder") { test =>
      expectText(test, importerFolderNameFor([doc("chapter-01")]), "chapter");
    }

## in_name_order

    let titleList(docs: List<ImporterDoc>): String {
      joinedText(docs.map { (d: ImporterDoc): String => d.title })
    }

    test("the order the names say, whatever order they arrived in") { test =>
      expectText(
        test,
        titleList(importerInNameOrder([doc("chapter-07"), doc("chapter-01"), doc("chapter-10"), doc("chapter-02")])),
        "chapter-01|chapter-02|chapter-07|chapter-10",
      );
    }

    test("digits compare as numbers and case does not matter") { test =>
      expectText(
        test,
        titleList(importerInNameOrder([doc("Part 10"), doc("part 9"), doc("Part 1")])),
        "Part 1|part 9|Part 10",
      );
    }

    test("numbering then follows the names") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let ordered = importerInNameOrder([doc("chapter-02"), doc("chapter-01")]);
      let out = importerLandWith(db, me, "chapter", true, new ImporterSilent(), ordered);
      expectText(test, createdTitles(out), "1. chapter-01|2. chapter-02");
    }

    test("equal names keep their order, and every document survives the sort") { test =>
      let a = new ImporterDoc("same", "first", null);
      let b = new ImporterDoc("same", "second", null);
      let sorted = importerInNameOrder([b, a, doc("alpha")]);
      expectInt(test, sorted.length, 3);
      expectText(test, sorted[0].title, "alpha");
      expectText(test, sorted[1].body, "second");
      expectText(test, sorted[2].body, "first");
    }

    test("a file's title is its name without the extension") { test =>
      expectText(test, importerRootname("chapter-01.md"), "chapter-01");
      expectText(test, importerRootname("a.b.txt"), "a.b");
      expectText(test, importerRootname("noext"), "noext");
      expectText(test, importerRootname(".hidden"), ".hidden");
      expectText(test, importerRootname("dir.d/file"), "dir.d/file");
    }
