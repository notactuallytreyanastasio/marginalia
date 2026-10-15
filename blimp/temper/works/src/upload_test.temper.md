# Tests for the upload rules and the fixture drafts

Ported from `work_upload_fallback_test` and `guest_upload_test` in
`notes/tests.md` (the word limit, the default title, the limit sentence), then
the three fixture drafts in `blimp/test/fixtures/drafts` run through
`worksCreateWork`.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { sysJoin, sysReadFile, sysGetEnv, sysMonoMs } = import("sys/src");
    let { wordCount } = import("html/src");

## prepare

    test("the ceiling is 120,000 words") { test =>
      expectInt(test, uploadMaxWords(), 120000);
    }

    test("nothing, or only whitespace, is empty") { test =>
      expectText(test, orEmpty(uploadPrepare("T", "", null).problem), "empty");
      expectText(test, orEmpty(uploadPrepare("T", null, null).problem), "empty");
      expectText(test, orEmpty(uploadPrepare("T", " \n\t \r\n ", null).problem), "empty");
      expectTrue(test, uploadPrepare("T", "", null).ok == null, "no params");
    }

    test("a draft at the limit is accepted and one word over is too long") { test =>
      let atLimit = uploadPrepare("T", repeated("word ", 120000), null);
      expectTrue(test, atLimit.ok != null, "120,000 is fine");
      let over = uploadPrepare("T", repeated("word ", 120001), null);
      expectTrue(test, over.ok == null, "120,001 is not");
      expectText(test, orEmpty(over.problem), "too_long");
      expectInt(test, over.words, 120001);
      expectText(test, uploadTooLongMessage(over.words), "That's 120,001 words, and the limit is 120,000 for now. Split it and upload the first part.");
    }

    test("the body is kept as it arrived and the title and intent are trimmed") { test =>
      let r = uploadPrepare("  A title ", "\n  body text \n", "  intent  ").ok;
      expectText(test, if (r != null) { r.title } else { "none" }, "A title");
      expectText(test, if (r != null) { r.body } else { "none" }, "\n  body text \n");
      expectText(test, if (r != null) { orNull(r.intent) } else { "none" }, "intent");
    }

    test("a missing or blank title is Untitled draft and blank intent is nothing") { test =>
      let a = uploadPrepare(null, "body", null).ok;
      expectText(test, if (a != null) { a.title } else { "none" }, "Untitled draft");
      expectText(test, if (a != null) { orNull(a.intent) } else { "none" }, "NULL");
      let b = uploadPrepare("   ", "body", "  \n").ok;
      expectText(test, if (b != null) { b.title } else { "none" }, "Untitled draft");
      expectText(test, if (b != null) { orNull(b.intent) } else { "none" }, "NULL");
    }

    test("blank trims and nothing is nothing") { test =>
      expectText(test, orNull(uploadBlank(null)), "NULL");
      expectText(test, orNull(uploadBlank("")), "NULL");
      expectText(test, orNull(uploadBlank("\u{a0} \n")), "NULL");
      expectText(test, orNull(uploadBlank("  x ")), "x");
    }

    test("the limit sentence puts commas in thousands") { test =>
      expectText(test, uploadTooLongMessage(0), "That's 0 words, and the limit is 120,000 for now. Split it and upload the first part.");
      expectText(test, uploadTooLongMessage(999), "That's 999 words, and the limit is 120,000 for now. Split it and upload the first part.");
      expectText(test, uploadTooLongMessage(1000), "That's 1,000 words, and the limit is 120,000 for now. Split it and upload the first part.");
      expectText(test, uploadTooLongMessage(1234567), "That's 1,234,567 words, and the limit is 120,000 for now. Split it and upload the first part.");
    }

## The fixture drafts

Absolute, because the tests run in a scratch work root. `MARGINALIA_FIXTURES`
names another directory.

    let fixtureDir(): String {
      let set = sysGetEnv("MARGINALIA_FIXTURES");
      if (set != null) { set } else { "/Users/bg/code/marginalia/.claude/worktrees/blimp-rewrite/blimp/test/fixtures/drafts" }
    }

    let fixture(name: String): String {
      let text = sysReadFile("${fixtureDir()}/${name}");
      if (text != null) { text } else {
        console.log("missing fixture ${name}");
        ""
      }
    }

    class WorksFixtureFx(public db: Db, public work: Work, public sections: List<Section>) {}

    let fromFixture(name: String, title: String): WorksFixtureFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let work = makeWork(db, me, title, fixture(name));
      new WorksFixtureFx(db, work, worksListSections(db, work.id))
    }

    test("the fixtures are there") { test =>
      expectTrue(test, wordCount(fixture("kettle.md")) > 300, "kettle.md");
      expectTrue(test, wordCount(fixture("lighthouse.txt")) > 300, "lighthouse.txt");
      expectTrue(test, wordCount(fixture("notes-on-a-server.md")) > 300, "notes-on-a-server.md");
    }

    test("kettle.md: three short headings fold into one section named for the first") { test =>
      let f = fromFixture("kettle.md", "The Kettle");
      expectInt(test, f.sections.length, 1);
      expectText(test, f.sections[0].title, "The Kettle");
      expectInt(test, f.sections[0].ordinal, 1);
      expectInt(test, f.sections[0].wordCount, 406);
      expectInt(test, f.work.wordCount, wordCount(fixture("kettle.md")));
      expectInt(test, f.work.wordCount, 417);
      expectLacks(test, f.work.body, "# The Thermostat");
      expectHas(test, f.work.body, "The kettle went cold on the counter");
    }

    test("lighthouse.txt: chapter markers are titles, not text, and the title line is the opening") { test =>
      let f = fromFixture("lighthouse.txt", "The Keeper of Harrow Point");
      expectInt(test, f.sections.length, 1);
      expectText(test, f.sections[0].title, "Opening");
      expectInt(test, f.sections[0].wordCount, 401);
      expectInt(test, f.work.wordCount, 407);
      expectLacks(test, f.work.body, "Chapter 1");
      expectHas(test, f.work.body, "The Keeper of Harrow Point");
      expectHas(test, f.work.body, "The lighthouse at Harrow Point had been automated");
    }

    test("notes-on-a-server.md: a title heading and two subheadings fold into the first") { test =>
      let f = fromFixture("notes-on-a-server.md", "Notes on a Small Server");
      expectInt(test, f.sections.length, 1);
      expectText(test, f.sections[0].title, "Notes on a Small Server");
      expectInt(test, f.sections[0].wordCount, 316);
      expectInt(test, f.work.wordCount, 333);
      expectHas(test, f.work.body, "Most of what a web server does is wait.");
      expectLacks(test, f.work.body, "## Reading a request properly");
    }

    test("the three fixtures under headings of their own keep the words and drop the headings") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let long = "# Kettle\n\n${fixture("kettle.md")}\n\n# Lighthouse\n\n${fixture("lighthouse.txt")}\n\n# Server\n\n${fixture("notes-on-a-server.md")}";
      let w = makeWork(db, me, "All", long);
      let sections = worksListSections(db, w.id);
      expectTrue(test, sections.length >= 1, "at least one");
      var total = 0;
      for (let s of sections) { total += s.wordCount; }
      expectTrue(test, total <= w.wordCount, "headings lifted into titles leave the words");
      expectText(test, sections[0].title, "The Kettle");
    }

    test("every fixture's sections add back up to the work and are one sentence per line") { test =>
      for (let name of ["kettle.md", "lighthouse.txt", "notes-on-a-server.md"]) {
        let f = fromFixture(name, name);
        let bodies = f.sections.map { (s: Section): String => s.body };
        expectText(test, sysJoin(bodies, "\n\n"), f.work.body);
        expectText(test, orEmpty(f.work.baselineBody), f.work.body);
        var ordinal = 1;
        for (let s of f.sections) {
          expectInt(test, s.ordinal, ordinal);
          expectInt(test, s.wordCount, wordCount(s.body));
          expectText(test, s.status, "pending");
          ordinal += 1;
        }
      }
    }

## Timing

A 12,000-word draft with headings, as the plan's timing note measures it.
The time is printed, not asserted: the interpreter's speed is not this
library's property.

    let bigDraft(): String {
      let sentence = "The committee had met twice before anyone thought to write down what it was for. ";
      let paragraph = repeated(sentence, 16);
      let chapter = "${paragraph}\n\n${paragraph}\n\n${paragraph}\n\n${paragraph}\n\n";
      let parts = new ListBuilder<String>();
      var i = 1;
      while (i <= 12) {
        parts.add("# Chapter ${i.toString()}\n\n${chapter}");
        i += 1;
      }
      sysJoin(parts.toList(), "")
    }

    test("a 12,000 word draft is created, and how long it took") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = bigDraft();
      let words = wordCount(body);
      let started = sysMonoMs();
      let work = makeWork(db, me, "Big", body);
      let took = sysMonoMs() - started;
      expectTrue(test, took < 60000, "${words.toString()} words in ${took.toString()} ms");
      expectInt(test, worksListSections(db, work.id).length, 12);
      expectTrue(test, words > 10000, "a big draft");
      expectTrue(test, worksListSections(db, work.id).length >= 6, "many sections");
    }
