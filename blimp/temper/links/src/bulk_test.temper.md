# Tests for the bulk pairing

Ported from `bulk_links_test.exs` in `notes/tests.md` (14 tests), plus the
triage call itself and a run through a fake model, which the Elixir test
never reached.

Choosing which documents to relate, before paying to relate any. What is
tested is that the triage cannot propose a pair that does not exist, and that
it does not quietly skip the documents it is not allowed to relate.

    let { worksGetById, worksMoveToFolder, worksListSections } = import("works/src");
    let { sysJoin, sysGraphemeLength } = import("sys/src");

    class LinksBulkFx(
      public db: Db,
      public scope: Scope,
      public folderId: Int,
      public works: List<Work>,
    ) {}

A user, a folder named "A series", and four drafts "1. Chapter 1" to
"4. Chapter 4" filed in it.

    let bulkFixture(): LinksBulkFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "writer@example.com");
      let uid = userIdOf(me);
      let folderId = db.insert("INSERT INTO folders (name, user_id) VALUES ($1, $2)", ["A series", uid.toString()]);
      let works = new ListBuilder<Work>();
      var i = 1;
      while (i <= 4) {
        let w = makeWork(db, me, "${i.toString()}. Chapter ${i.toString()}", "# H${i.toString()}\n\n${repeated("word ", 300)}");
        worksMoveToFolder(db, me, w.id, folderId);
        works.add(w);
        i += 1;
      }
      new LinksBulkFx(db, me, folderId, works.toList())
    }

    let sheetOf(f: LinksBulkFx): List<BulkLine> throws Bubble {
      linksBulkSheet(f.db, f.scope, f.folderId)
    }

## The sheet handed to the model

    test("one numbered line per document in the folder") { test =>
      let f = bulkFixture();
      let s = sheetOf(f);
      expectInt(test, s.length, 4);
      expectInt(test, s[0].n, 1);
      expectInt(test, s[3].n, 4);
      var i = 0;
      while (i < 4) {
        expectText(test, s[i].work.title, f.works[i].title);
        i += 1;
      }
    }

    test("a document outside the folder is not on the sheet") { test =>
      let f = bulkFixture();
      makeWork(f.db, f.scope, "Loose", "# L\n\n${repeated("word ", 300)}");
      expectInt(test, sheetOf(f).length, 4);
    }

    test("a document with nothing written about it still gets a line") { test =>
      let f = bulkFixture();
      for (let entry of sheetOf(f)) { expectText(test, entry.line, ""); }
    }

    test("a section summary is used when there is one") { test =>
      let f = bulkFixture();
      let w = f.works[0];
      f.db.exec("UPDATE sections SET summary = $1 WHERE id = $2", ["It establishes the doorway.", firstSection(f.db, w).id.toString()]);
      expectText(test, linksBulkDescribe(f.db, w), "It establishes the doorway.");
    }

    test("two section summaries are joined, and no more than two") { test =>
      let f = bulkFixture();
      let w = makeWork(f.db, f.scope, "Three sections", "# One\n\n${repeated("word ", 500)}\n\n# Two\n\n${repeated("word ", 500)}\n\n# Three\n\n${repeated("word ", 500)}");
      let sections = worksListSections(f.db, w.id);
      expectInt(test, sections.length, 3);
      var i = 0;
      while (i < 3) {
        f.db.exec("UPDATE sections SET summary = $1 WHERE id = $2", ["Summary ${(i + 1).toString()}.", sections[i].id.toString()]);
        i += 1;
      }
      expectText(test, linksBulkDescribe(f.db, w), "Summary 1. Summary 2.");
    }

    test("a stack step beats a section summary, being the better description") { test =>
      let f = bulkFixture();
      let w = f.works[0];
      f.db.exec("UPDATE sections SET summary = $1 WHERE id = $2", ["A summary.", firstSection(f.db, w).id.toString()]);
      f.db.exec("INSERT INTO stack_steps (folder_id, work_id, ordinal, capability) VALUES ($1, $2, 1, $3)", [f.folderId.toString(), w.id.toString(), "The thing emits a file that runs."]);
      expectText(test, linksBulkDescribe(f.db, w), "The thing emits a file that runs.");
    }

    test("the first impression is the last resort") { test =>
      let f = bulkFixture();
      let w = f.works[0];
      f.db.exec("UPDATE works SET first_impression = $1 WHERE id = $2", ["It opens on a doorway.", w.id.toString()]);
      let fresh = worksGetById(f.db, w.id);
      expectTrue(test, fresh != null, "reloaded");
      if (fresh != null) { expectText(test, linksBulkDescribe(f.db, fresh), "It opens on a doorway."); }
    }

    test("a description is collapsed to single spaces and cut at 220 characters") { test =>
      let f = bulkFixture();
      let w = f.works[0];
      f.db.exec("INSERT INTO stack_steps (folder_id, work_id, ordinal, capability) VALUES ($1, $2, 1, $3)", [f.folderId.toString(), w.id.toString(), "  spaced \n\n   out  ${repeated("x", 400)}"]);
      let line = linksBulkDescribe(f.db, w);
      expectInt(test, sysGraphemeLength(line), 220);
      expectTrue(test, line.split("  ").length == 1, "no double spaces");
      expectTrue(test, line.split("\n").length == 1, "no newlines");
    }

    test("the listing is the numbered title, then a dash and the line when there is one") { test =>
      let f = bulkFixture();
      f.db.exec("INSERT INTO stack_steps (folder_id, work_id, ordinal, capability) VALUES ($1, $2, 1, $3)", [f.folderId.toString(), f.works[1].id.toString(), "It emits a file."]);
      let listing = linksBulkListing(sheetOf(f));
      expectText(test, listing, "1. 1. Chapter 1\n2. 2. Chapter 2 — It emits a file.\n3. 3. Chapter 3\n4. 4. Chapter 4");
    }

## validate

    test("a real pair is kept with its hypothesis") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"pairs\":[{\"a\":1,\"b\":4,\"why\":\"one sets up four\",\"expect\":\"pays_off\"}]}"), sheetOf(f));
      expectInt(test, out.pairs.length, 1);
      expectText(test, out.pairs[0].why, "one sets up four");
      expectText(test, out.pairs[0].expect, "pays_off");
      expectInt(test, out.pairs[0].a.id, f.works[0].id);
      expectInt(test, out.pairs[0].b.id, f.works[3].id);
      expectInt(test, out.dropped.length, 0);
    }

    test("a document that is not in the folder is dropped and named") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"pairs\":[{\"a\":1,\"b\":140}]}"), sheetOf(f));
      expectInt(test, out.pairs.length, 0);
      expectInt(test, out.dropped.length, 1);
      expectHas(test, out.dropped[0], "140");
      expectHas(test, out.dropped[0], "not in this folder");
      expectText(test, out.dropped[0], "[140] is not in this folder");
    }

    test("both missing numbers are named") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"pairs\":[{\"a\":7,\"b\":140}]}"), sheetOf(f));
      expectText(test, out.dropped[0], "[7, 140] is not in this folder");
    }

    test("a document paired with itself is refused") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"pairs\":[{\"a\":2,\"b\":2}]}"), sheetOf(f));
      expectInt(test, out.pairs.length, 0);
      expectInt(test, out.dropped.length, 1);
      expectHas(test, out.dropped[0], "itself");
      expectText(test, out.dropped[0], "2 paired with itself");
    }

    test("the same pair twice is only one pair") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"pairs\":[{\"a\":1,\"b\":3},{\"a\":3,\"b\":1}]}"), sheetOf(f));
      expectInt(test, out.pairs.length, 1);
      expectInt(test, out.dropped.length, 1);
      expectHas(test, out.dropped[0], "twice");
      expectText(test, out.dropped[0], "3–1 proposed twice");
    }

    test("what it chose not to propose is carried through") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"pairs\":[],\"skipped\":\"  2 and 3 are adjacent.  \"}"), sheetOf(f));
      expectText(test, out.skipped, "2 and 3 are adjacent.");
    }

    test("a pair without two numbers is named with what it did have") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"pairs\":[{\"a\":1},{\"a\":\"x\",\"b\":2},{\"why\":\"no numbers\"}]}"), sheetOf(f));
      expectInt(test, out.pairs.length, 0);
      expectInt(test, out.dropped.length, 3);
      expectText(test, out.dropped[0], "a pair without two numbers: %{\"a\" => 1}");
      expectText(test, out.dropped[1], "a pair without two numbers: %{\"a\" => \"x\", \"b\" => 2}");
      expectText(test, out.dropped[2], "a pair without two numbers: %{}");
    }

    test("numbers may arrive as strings, and a missing why is the empty string") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"pairs\":[{\"a\":\" 2 \",\"b\":\"4x\",\"why\":7}]}"), sheetOf(f));
      expectInt(test, out.pairs.length, 1);
      expectInt(test, out.pairs[0].a.id, f.works[1].id);
      expectInt(test, out.pairs[0].b.id, f.works[3].id);
      expectText(test, out.pairs[0].why, "");
      expectText(test, out.pairs[0].expect, "");
    }

    test("no more than 24 pairs are kept") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "writer@example.com");
      let folderId = db.insert("INSERT INTO folders (name, user_id) VALUES ($1, $2)", ["Big", userIdOf(me).toString()]);
      var i = 1;
      while (i <= 9) {
        let w = makeWork(db, me, "Doc ${i.toString()}", "# H\n\n${repeated("word ", 60)}");
        worksMoveToFolder(db, me, w.id, folderId);
        i += 1;
      }
      let sheet = linksBulkSheet(db, me, folderId);
      let pairs = new ListBuilder<String>();
      var a = 1;
      while (a <= 9) {
        var b = a + 1;
        while (b <= 9) {
          pairs.add("{\"a\":${a.toString()},\"b\":${b.toString()}}");
          b += 1;
        }
        a += 1;
      }
      let out = linksBulkValidate(objectOf("{\"pairs\":[${sysJoin(pairs.toList(), ",")}]}"), sheet);
      expectInt(test, out.pairs.length, 24);
      expectInt(test, out.dropped.length, 0);
    }

    test("no pairs key is no pairs, not a crash") { test =>
      let f = bulkFixture();
      let out = linksBulkValidate(objectOf("{\"skipped\":\"nothing\"}"), sheetOf(f));
      expectInt(test, out.pairs.length, 0);
      expectText(test, out.skipped, "nothing");
    }

## Relating

    test("an unread pair is reported by name, not skipped in silence") { test =>
      let f = bulkFixture();
      let a = f.works[0];
      let b = f.works[1];
      let messages = linksBulkIneligible([new BulkPair(a, b, "w", "develops")]);
      expectInt(test, messages.length, 1);
      expectHas(test, messages[0], a.title);
      expectHas(test, messages[0], b.title);
      expectHas(test, messages[0], "has not been read");
      expectText(test, messages[0], "1. Chapter 1 ↔ 2. Chapter 2: 1. Chapter 1 and 2. Chapter 2 has not been read");
    }

    test("a pair is eligible only when BOTH sides have been read") { test =>
      let f = bulkFixture();
      let a = readWork(f.db, f.works[0]);
      var b = f.works[1];
      let one = linksBulkIneligible([new BulkPair(a, b, "w", "develops")]);
      expectInt(test, one.length, 1);
      expectHas(test, one[0], b.title);
      expectFalse(test, hasText(one[0], "${a.title} has not been read"), "the read side is not named as unread");
      expectText(test, one[0], "1. Chapter 1 ↔ 2. Chapter 2: 2. Chapter 2 has not been read");
      b = readWork(f.db, b);
      expectInt(test, linksBulkIneligible([new BulkPair(a, b, "w", "develops")]).length, 0);
    }

    test("a folder with nothing in it says so rather than calling the model") { test =>
      let f = bulkFixture();
      let empty = f.db.insert("INSERT INTO folders (name, user_id) VALUES ($1, $2)", ["Nothing here", userIdOf(f.scope).toString()]);
      let fake = llmFake([]);
      let r = linksBulkRun(f.db, fake, f.scope, empty, false);
      expectText(test, orNone(r.error), "empty_folder");
      expectInt(test, requestCount(test, fake), 0);
    }

    test("somebody else's folder is not readable") { test =>
      let f = bulkFixture();
      let stranger = makeUser(f.db, "stranger@example.com");
      let fake = llmFake([]);
      let r = linksBulkRun(f.db, fake, stranger, f.folderId, false);
      expectText(test, orNone(r.error), "no_folder");
      expectInt(test, requestCount(test, fake), 0);
    }

    test("no one at all has no folder") { test =>
      let f = bulkFixture();
      let r = linksBulkRun(f.db, llmFake([]), new Scope(null), f.folderId, false);
      expectText(test, orNone(r.error), "no_folder");
    }

    test("linkable is what the real pass needs, and unread drafts are not it") { test =>
      let f = bulkFixture();
      expectInt(test, linksLinkable(f.db, f.scope, null).length, 0);
    }

## The triage call

    let triageArgs(): String {
      "{\"pairs\":[{\"a\":1,\"b\":2,\"why\":\"one sets up two\",\"expect\":\"develops\"},{\"a\":1,\"b\":3,\"why\":\"three walks one back\",\"expect\":\"tension\"},{\"a\":2,\"b\":9,\"why\":\"nine is not there\",\"expect\":\"echoes\"}],\"skipped\":\"3 and 4 are adjacent.\"}"
    }

    test("propose sends the listing and the tool, and validates what comes back") { test =>
      let f = bulkFixture();
      let fake = llmFake([replyTool("propose_links", triageArgs())]);
      let proposed = linksBulkPropose(f.db, fake, sheetOf(f));
      let triage = proposed.ok;
      expectTrue(test, triage != null, "a triage");
      if (triage != null) {
        expectInt(test, triage.pairs.length, 2);
        expectText(test, triage.pairs[1].expect, "tension");
        expectInt(test, triage.dropped.length, 1);
        expectText(test, triage.dropped[0], "[9] is not in this folder");
        expectText(test, triage.skipped, "3 and 4 are adjacent.");
      }
      let body = lastRequest(test, fake);
      expectHas(test, body, "4 documents:");
      expectHas(test, body, "1. 1. Chapter 1\\n2. 2. Chapter 2");
      expectHas(test, body, "\"name\":\"propose_links\"");
      expectHas(test, body, "\"tool_choice\":\"auto\"");
      expectHas(test, body, "\"reasoning_effort\":\"high\"");
      expectHas(test, body, "\"temperature\":0.3");
      expectHas(test, body, "\"max_tokens\":27000");
      expectHas(test, body, "Report by calling propose_links.");
    }

    test("a model that answers in prose is no_tool_call, and a broken argument string is invalid_json") { test =>
      let f = bulkFixture();
      let prose = linksBulkPropose(f.db, llmFake([replyText("I would pair one and two.")]), sheetOf(f));
      expectTrue(test, prose.ok == null, "no triage");
      expectHas(test, orNone(prose.error), "no_tool_call");
      let broken = linksBulkPropose(f.db, llmFake([replyTool("propose_links", "{not json")]), sheetOf(f));
      expectHas(test, orNone(broken.error), "invalid_json");
    }

    test("propose-only stops after the cheap stage") { test =>
      let f = bulkFixture();
      let fake = llmFake([replyTool("propose_links", triageArgs())]);
      let r = linksBulkRun(f.db, fake, f.scope, f.folderId, true);
      expectTrue(test, r.error == null, "no error");
      expectInt(test, r.started.length, 0);
      let triage = r.triage;
      expectTrue(test, triage != null, "a triage");
      if (triage != null) { expectInt(test, triage.pairs.length, 2); }
      expectInt(test, requestCount(test, fake), 1);
      expectInt(test, countOf(f.db, "SELECT count(*) AS n FROM links"), 0);
    }

    test("a run relates the eligible pairs and names the unread ones") { test =>
      let f = bulkFixture();
      let one = readWork(f.db, f.works[0]);
      let two = readWork(f.db, f.works[1]);
      let n1 = addNode(f.db, one, firstSection(f.db, one), "beat", "setup", "sets up");
      let n2 = addNode(f.db, two, firstSection(f.db, two), "beat", "payoff", "pays off");
      let fake = llmFake([
        replyTool("propose_links", triageArgs()),
        linkerReply("Two pays off one.", [edgeJson(n1.id, n2.id, "pays_off", "Manuscript B pays off the setup in Manuscript A.")]),
      ]);
      let r = linksBulkRun(f.db, fake, f.scope, f.folderId, false);
      expectTrue(test, r.error == null, "no error");
      expectInt(test, r.started.length, 1);
      expectInt(test, r.notRead.length, 1);
      expectText(test, r.notRead[0], "1. Chapter 1 ↔ 3. Chapter 3: 3. Chapter 3 has not been read");
      let id = r.started[0].linkId;
      expectTrue(test, id != null, "a link id");
      if (id != null) {
        let link = linksGet(f.db, id);
        expectTrue(test, link != null, "stored");
        if (link != null) {
          expectText(test, link.status, "linked");
          expectInt(test, linksEdgeCount(f.db, link.id), 1);
        }
      }
      expectInt(test, requestCount(test, fake), 2);
    }

    test("a pair whose link fails still comes back with its link id and the link says why") { test =>
      let f = bulkFixture();
      let one = readWork(f.db, f.works[0]);
      let two = readWork(f.db, f.works[1]);
      let pair = new BulkPair(one, two, "w", "develops");
      let related = linksBulkRelate(f.db, llmFake([replyNothing()]), [pair]);
      expectInt(test, related.started.length, 1);
      expectInt(test, related.notRead.length, 0);
      let id = pair.linkId;
      expectTrue(test, id != null, "a link id");
      if (id != null) {
        let link = linksGet(f.db, id);
        if (link != null) { expectText(test, link.status, "failed"); }
      }
    }

    test("the triage tool schema is the one the model was shown") { test =>
      let schema = linksBulkToolParameters();
      expectHas(test, schema, "\"maxItems\":24");
      expectHas(test, schema, "\"required\":[\"a\",\"b\",\"why\",\"expect\"]");
      expectHas(test, schema, "\"enum\":[\"develops\",\"pays_off\",\"requires\",\"tension\",\"answers\",\"echoes\"]");
      expectHas(test, schema, "\\\"Nine sets up the promise that fourteen pays off\\\"");
    }
