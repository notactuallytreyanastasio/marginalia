# Tests for cuts

The 19 tests of `test/marginalia/cuts_test.exs`, assertion for assertion,
then what the notes say about the read: the prompt (compared with the string
the Elixir builds for the same inputs), the options of the call, the status
machine, what is stored, and `cutsLocate` at its edges. The model is
`llmFake` with replies shaped as the notes give. Every check runs in a helper
that takes the `test`, or the frontend evaluates it while compiling. Every
database is `:memory:` and migrated.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, scopeFor, userColumns } = import("accounts/src");
    let { Work, WorkParams, workParams, worksCreateWork } = import("works/src");
    let { Folder, foldersCreateFolder, foldersMoveWork } = import("folders/src");
    let { LlmClient, llmFake, llmLastRequest, llmRequests } = import("llm/src");
    let { versionsOf } = import("runs/src");
    let { sysByteLength, sysJoin } = import("sys/src");
    let { JsonObject, JsonTextProducer, parseJson } = import("std/json");

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let expectTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let expectFalse(test: Test, got: Boolean, what: String): Void {
      assert(!got) { what }
    }

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "expected ${part} in:\n${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "did not expect ${part} in:\n${s}" }
    }

    let orNil(s: String?): String { if (s != null) { s } else { "nil" } }

    let joined(xs: List<String>): String { sysJoin(xs, ",") }

## Fixtures

    let userOf(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { scopeFor(User.fromRow(row)) } else { bubble() }
    }

    let repeatedWord(n: Int): String {
      var parts = "";
      var i = 0;
      var out = new ListBuilder<String>();
      while (i < n) { out.add("word "); i += 1; }
      sysJoin(out.toList(), "")
    }

The Elixir `draft/3`: a title heading, a first paragraph, a second paragraph
carrying `extra`, and 120 words.

    let draft(db: Db, s: Scope, title: String, extra: String): Work throws Bubble {
      let body = "# ${title}\n\nThe first paragraph of ${title}, which is long enough to stand alone.\n\nA second paragraph. ${extra}\n\n${repeatedWord(120)}";
      let r = worksCreateWork(db, s, workParams(title, body));
      let w = r.ok;
      if (w != null) { w } else { bubble() }
    }

    let folderIn(db: Db, s: Scope, name: String, parent: Folder?): Folder throws Bubble {
      let parentId = if (parent != null) { parent.id } else { null };
      let r = foldersCreateFolder(db, s, name, parentId);
      let f = r.folder;
      if (f != null) { f } else { bubble() }
    }

    let moveTo(db: Db, s: Scope, w: Work, f: Folder): Void throws Bubble {
      let r = foldersMoveWork(db, s, w.id, f.id);
      if (!r.ok) { bubble(); }
    }

    let opened(db: Db, s: Scope, f: Folder, question: String?): Cut throws Bubble {
      let r = cutsOpenFolderReading(db, s, f.id, question);
      let c = r.ok;
      if (c != null) { c } else { bubble() }
    }

    let rawOf(text: String): JsonObject throws Bubble {
      let t = parseJson(text);
      t as JsonObject orelse panic()
    }

    let opinion(): CutMember {
      new CutMember(1, "work", 10, "Opinion", false, "The court held that standing\nwas absent from the start.")
    }

    let dissent(): CutMember {
      new CutMember(2, "work", 11, "Dissent", false, "Standing was plainly present, and the majority says otherwise.")
    }

    let pair(): List<CutMember> { [opinion(), dissent()] }

Whether every member's text contains `part` (an empty `part` asks only that
the text is not empty).

    let allMembers(members: List<CutMember>, part: String): Boolean {
      var all = true;
      for (let m of members) {
        if (part == "") {
          if (m.text == "") { all = false; }
        } else if (!hasText(m.text, part)) {
          all = false;
        }
      }
      all
    }

    let anyRead(members: List<CutMember>): Boolean {
      var any = false;
      for (let m of members) { if (m.read) { any = true; } }
      any
    }

    let threadRaw(evidence: String): String {
      "{\"threads\":[{\"claim\":\"They disagree.\",\"evidence\":${evidence}}]}"
    }

    let labelsOf(picks: List<CutPick>): String {
      sysJoin(picks.map { (p: CutPick): String => p.label }, ",")
    }

    let idsOf(picks: List<CutPick>): String {
      sysJoin(picks.map { (p: CutPick): String => p.id.toString() }, ",")
    }

Reading a fake client's log goes through a helper that takes the `test`, or
the frontend folds it before the read has run.

    let lastSent(test: Test, c: LlmClient): String { orNil(llmLastRequest(c)) }

    let sentCount(test: Test, c: LlmClient): Int { llmRequests(c).length }

    let hasDrop(dropped: List<String>, part: String): Boolean {
      var found = false;
      for (let d of dropped) { if (hasText(d, part)) { found = true; } }
      found
    }

A chat-completion body whose message content is `content`.

    let chatBody(content: String): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("message");
      p.startObject();
      p.objectKey("role"); p.stringValue("assistant");
      p.objectKey("content"); p.stringValue(content);
      p.endObject();
      p.objectKey("finish_reason"); p.stringValue("stop");
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

The result of storing a finished reading with only some fields, as the Elixir
tests did through `result_changeset`.

    let stored(db: Db, cut: Cut, thesis: String?, threads: List<CutThread>, sha: String?): Cut throws Bubble {
      let r = cutsStoreResult(db, cut, new CutResult(thesis, threads, [], null, [], sha, "read", []));
      let c = r.ok;
      if (c != null) { c } else { bubble() }
    }

## Locating a quote

    let hay(): String {
      "A Blimp closure can see its caller's locals. `eval.zig` has a test\nthat says so outright, and tail call elimination is written around it."
    }

    let locateText(needle: String, haystack: String): String { orNil(cutsLocate(needle, haystack)) }

    test("an exact quote comes back unchanged") { test =>
      expectText(test, locateText("A Blimp closure", hay()), "A Blimp closure");
    }

    test("a re-wrapped quote is found anyway") { test =>
      let found = cutsLocate("has a test that says so outright", hay());
      expectTrue(test, found != null, "found");
      let f = orNil(found);
      expectHas(test, f, "\n");
      expectHas(test, hay(), f);
      expectText(test, f, "has a test\nthat says so outright");
    }

    test("what comes back is the draft's wording, not the model's") { test =>
      let found = locateText("has a test that says so outright", hay());
      expectFalse(test, found == "has a test that says so outright", "the model's wording came back");
    }

    test("a fabricated quote is not found") { test =>
      expectText(test, locateText("A Blimp closure cannot see anything", hay()), "nil");
    }

    test("reordered words are not found") { test =>
      expectText(test, locateText("locals caller's its see", hay()), "nil");
    }

    test("blank is not found") { test =>
      expectText(test, locateText("   \n ", hay()), "nil");
      expectText(test, locateText("", hay()), "nil");
    }

    test("a quote may start and end inside words, as a substring of the flattened text would") { test =>
      expectText(test, locateText("closure can see its", hay()), "closure can see its");
      expectText(test, locateText("ure can  see\nits cal", hay()), "ure can see its cal");
    }

    test("a loose quote returns the source's spacing: a tab and a carriage return are folded") { test =>
      let source = "alpha\t\tbeta\r\ngamma delta";
      expectText(test, locateText("beta gamma", source), "beta\r\ngamma");
      expectText(test, locateText("alpha beta gamma delta", source), "alpha\t\tbeta\r\ngamma delta");
    }

    test("the needle's own whitespace is folded however it is written") { test =>
      expectText(test, locateText("  has   a\ntest\tthat says  ", hay()), "has a test\nthat says");
    }

    test("the first word occurring earlier does not hide a later match") { test =>
      let source = "the cat sat. the cat sat on the mat\nand slept";
      expectText(test, locateText("the cat sat on the mat and", source), "the cat sat on the mat\nand");
    }

    test("a middle word must be a whole word") { test =>
      expectText(test, locateText("closure can se its", hay()), "nil");
    }

    test("a quote cannot run past the end of the text") { test =>
      expectText(test, locateText("written around it. and more", hay()), "nil");
      expectText(test, locateText("written around it.", hay()), "written around it.");
    }

    test("the other whitespace (vertical tab, form feed) does not separate words in the source") { test =>
      let source = "one\u{b}two three";
      expectText(test, locateText("one two three", source), "nil");
      expectText(test, locateText("two three", source), "two three");
    }

    test("non-ASCII text is located by characters") { test =>
      let source = "Die Straße\nführt über den Fluß";
      expectText(test, locateText("Straße führt über", source), "Straße\nführt über");
    }

## Keeping only what can be checked

    test("a claim with two locatable quotes survives") { test =>
      let raw = rawOf(threadRaw("[{\"member\":1,\"quote\":\"standing was absent\"},{\"member\":2,\"quote\":\"Standing was plainly present\"}]"));
      let v = cutsValidate(raw, pair());
      expectInt(test, v.dropped.length, 0);
      expectInt(test, v.threads.length, 1);
      expectText(test, v.threads[0].claim, "They disagree.");
      expectText(test, labelsOf(v.threads[0].evidence), "Opinion,Dissent");
      expectText(test, idsOf(v.threads[0].evidence), "10,11");
      expectText(test, v.threads[0].evidence[0].kind, "work");
      expectInt(test, v.threads[0].evidence[1].member, 2);
    }

    test("the stored quote is the member's wording, not the model's") { test =>
      let raw = rawOf(threadRaw("[{\"member\":1,\"quote\":\"held that standing was absent\"},{\"member\":2,\"quote\":\"Standing was plainly present\"}]"));
      let v = cutsValidate(raw, pair());
      expectInt(test, v.dropped.length, 0);
      expectHas(test, v.threads[0].evidence[0].quote, "\n");
      expectText(test, v.threads[0].evidence[0].quote, "held that standing\nwas absent");
    }

    test("a fabricated quote takes the claim down with it") { test =>
      let raw = rawOf(threadRaw("[{\"member\":1,\"quote\":\"standing was absent\"},{\"member\":2,\"quote\":\"the court never reached the question\"}]"));
      let v = cutsValidate(raw, pair());
      expectInt(test, v.threads.length, 0);
      expectTrue(test, hasDrop(v.dropped, "quote is not in member 2"), joined(v.dropped));
      expectTrue(test, hasDrop(v.dropped, "needs 2"), joined(v.dropped));
      expectText(test, v.dropped[0], "thread \"They disagree.\": quote is not in member 2");
      expectText(test, v.dropped[1], "thread \"They disagree.\": 1 verifiable citation(s), needs 2");
    }

    test("a claim resting on one member is not a finding about the group") { test =>
      let raw = rawOf(threadRaw("[{\"member\":1,\"quote\":\"standing was absent\"}]"));
      let v = cutsValidate(raw, pair());
      expectInt(test, v.threads.length, 0);
      expectTrue(test, hasDrop(v.dropped, "1 verifiable citation"), joined(v.dropped));
      expectInt(test, v.dropped.length, 1);
    }

    test("a member number that is not in the group is refused") { test =>
      let raw = rawOf(threadRaw("[{\"member\":1,\"quote\":\"standing was absent\"},{\"member\":7,\"quote\":\"standing was absent\"}]"));
      let v = cutsValidate(raw, pair());
      expectTrue(test, hasDrop(v.dropped, "member 7 is not in this group"), joined(v.dropped));
    }

    test("the older key name still parses, so a prompt tweak cannot silently void everything") { test =>
      let raw = rawOf(threadRaw("[{\"document\":1,\"quote\":\"standing was absent\"},{\"document\":2,\"quote\":\"Standing was plainly present\"}]"));
      let v = cutsValidate(raw, pair());
      expectInt(test, v.dropped.length, 0);
      expectInt(test, v.threads.length, 1);
    }

    test("tensions are checked exactly as threads are") { test =>
      let raw = rawOf("{\"tensions\":[{\"claim\":\"One says the opposite of the other.\",\"evidence\":[{\"member\":1,\"quote\":\"standing was absent\"},{\"member\":2,\"quote\":\"made this up entirely\"}]}]}");
      let v = cutsValidate(raw, pair());
      expectInt(test, v.tensions.length, 0);
      expectTrue(test, v.dropped.length != 0, "something was dropped");
      expectTrue(test, hasDrop(v.dropped, "tension \"One says the opposite of the other.\": quote is not in member 2"), joined(v.dropped));
    }

    test("a surviving tension is kept, and the order of drops is threads then tensions") { test =>
      let raw = rawOf("{\"threads\":[{\"claim\":\"\",\"evidence\":[]}],\"tensions\":[{\"claim\":\"They split.\",\"evidence\":[{\"member\":1,\"quote\":\"standing\\nwas absent\"},{\"member\":2,\"quote\":\"Standing was plainly present\"}]},{\"claim\":\"\"}]}");
      let v = cutsValidate(raw, pair());
      expectInt(test, v.threads.length, 0);
      expectInt(test, v.tensions.length, 1);
      expectText(test, v.tensions[0].claim, "They split.");
      expectText(test, joined(v.dropped), "thread: no claim,tension: no claim");
    }

    test("a claim with no evidence list, or a non-list, is dropped with its reason") { test =>
      let raw = rawOf("{\"threads\":[{\"claim\":\"Alone\"},{\"claim\":\"Odd\",\"evidence\":\"x\"}]}");
      let v = cutsValidate(raw, pair());
      expectInt(test, v.threads.length, 0);
      expectText(test, joined(v.dropped),
        "thread \"Alone\": no evidence,thread \"Alone\": 0 verifiable citation(s), needs 2,thread \"Odd\": no evidence,thread \"Odd\": 0 verifiable citation(s), needs 2");
    }

    test("threads or tensions that are not lists are nothing, with no message") { test =>
      let raw = rawOf("{\"threads\":\"none\",\"tensions\":{\"a\":1},\"thesis\":\"T\"}");
      let v = cutsValidate(raw, pair());
      expectInt(test, v.threads.length, 0);
      expectInt(test, v.tensions.length, 0);
      expectInt(test, v.dropped.length, 0);
    }

    test("thesis and not_supported are trimmed text, else empty") { test =>
      let a = cutsValidate(rawOf("{\"thesis\":\"  Standing split them.  \",\"not_supported\":\"\\nNo remedy.\\n\"}"), pair());
      expectText(test, a.thesis, "Standing split them.");
      expectText(test, a.notSupported, "No remedy.");
      let b = cutsValidate(rawOf("{\"thesis\":3,\"not_supported\":null}"), pair());
      expectText(test, b.thesis, "");
      expectText(test, b.notSupported, "");
    }

    test("a member given as a string is read by its leading digits; a float is not a number") { test =>
      let ok = rawOf(threadRaw("[{\"member\":\"1\",\"quote\":\"standing was absent\"},{\"member\":\"2nd\",\"quote\":\"Standing was plainly present\"}]"));
      let a = cutsValidate(ok, pair());
      expectInt(test, a.threads.length, 1);
      let bad = rawOf(threadRaw("[{\"member\":1.0,\"quote\":\"standing was absent\"},{\"member\":\"x\",\"quote\":\"standing was absent\"},{\"quote\":\"standing was absent\"}]"));
      let b = cutsValidate(bad, pair());
      expectText(test, joined(b.dropped),
        "thread \"They disagree.\": member 1.0 is not in this group,thread \"They disagree.\": member \"x\" is not in this group,thread \"They disagree.\": member nil is not in this group,thread \"They disagree.\": 0 verifiable citation(s), needs 2");
    }

    test("the claim in a message is quoted and cut at 40 characters, with escapes") { test =>
      let long = "A \\\"quoted\\\" claim that goes on well past the fortieth character of the sentence";
      let raw = rawOf("{\"threads\":[{\"claim\":\"${long}\",\"evidence\":[]}]}");
      let v = cutsValidate(raw, pair());
      expectText(test, v.dropped[0], "thread \"A \\\"quoted\\\" claim that goes on well past \": 0 verifiable citation(s), needs 2");
    }

    test("a blank quote cites nothing") { test =>
      let raw = rawOf(threadRaw("[{\"member\":1,\"quote\":\"  \"},{\"member\":2,\"quote\":\"Standing was plainly present\"}]"));
      let v = cutsValidate(raw, pair());
      expectInt(test, v.threads.length, 0);
      expectTrue(test, hasDrop(v.dropped, "quote is not in member 1"), joined(v.dropped));
    }

## Reading a folder: who the members are

    test("a leaf folder is read over its drafts") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      let a = draft(db, me, "Opinion", "");
      let b = draft(db, me, "Dissent", "");
      moveTo(db, me, a, f);
      moveTo(db, me, b, f);
      let members = cutsMembers(db, me, f.id);
      expectInt(test, members.length, 2);
      expectText(test, joined(members.map { (m: CutMember): String => m.kind }), "work,work");
      expectText(test, joined(members.map { (m: CutMember): String => m.n.toString() }), "1,2");
      expectTrue(test, allMembers(members, ""), "every member has text");
      expectText(test, joined(members.map { (m: CutMember): String => m.label }), "Opinion,Dissent");
    }

    test("members are numbered oldest draft first") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      let later = draft(db, me, "Zeta", "");
      let earlier = draft(db, me, "Alpha", "");
      moveTo(db, me, earlier, f);
      moveTo(db, me, later, f);
      let members = cutsMembers(db, me, f.id);
      expectText(test, joined(members.map { (m: CutMember): String => m.label }), "Zeta,Alpha");
      expectText(test, joined(members.map { (m: CutMember): String => m.id.toString() }),
        "${later.id.toString()},${earlier.id.toString()}");
    }

    test("a folder of folders is read over its children, not their drafts") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let top = folderIn(db, me, "Cases", null);
      let one = folderIn(db, me, "Case one", top);
      let two = folderIn(db, me, "Case two", top);
      moveTo(db, me, draft(db, me, "Opinion", ""), one);
      moveTo(db, me, draft(db, me, "Dissent", ""), two);
      let members = cutsMembers(db, me, top.id);
      expectText(test, joined(members.map { (m: CutMember): String => m.kind }), "folder,folder");
      expectText(test, joined(members.map { (m: CutMember): String => m.label }), "Case one,Case two");
      expectTrue(test, allMembers(members, "not read yet"),
        "neither child has been read, and the text says so");
      expectFalse(test, anyRead(members), "none is read");
      expectText(test, members[0].text, "(not read yet) holds: Opinion");
    }

    test("a folder holding drafts and folders is read at the level of its folders") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let top = folderIn(db, me, "Cases", null);
      let one = folderIn(db, me, "Case one", top);
      moveTo(db, me, draft(db, me, "Opinion", ""), one);
      moveTo(db, me, draft(db, me, "Loose", ""), top);
      let members = cutsMembers(db, me, top.id);
      expectInt(test, members.length, 1);
      expectText(test, members[0].kind, "folder");
      let nested = folderIn(db, me, "Nested", one);
      let again = cutsMembers(db, me, one.id);
      expectText(test, again[0].text, "(not read yet) holds: ");
      expectText(test, joined(again.map { (m: CutMember): String => m.label }), "Nested");
      expectInt(test, nested.id, nested.id);
    }

    test("a read child contributes its reading, not its drafts") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let top = folderIn(db, me, "Cases", null);
      let one = folderIn(db, me, "Case one", top);
      moveTo(db, me, draft(db, me, "Opinion", ""), one);
      let cut = opened(db, me, one, null);
      stored(db, cut, "The court split on standing.", [new CutThread("Both turn on the same footnote.", [])], null);
      let members = cutsMembers(db, me, top.id);
      expectInt(test, members.length, 1);
      expectTrue(test, members[0].read, "read");
      expectHas(test, members[0].text, "The court split on standing.");
      expectHas(test, members[0].text, "Both turn on the same footnote.");
      expectText(test, members[0].text, "The court split on standing.\n\n- Both turn on the same footnote.");
    }

    test("a child whose reading is not finished is still not read") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let top = folderIn(db, me, "Cases", null);
      let one = folderIn(db, me, "Case one", top);
      moveTo(db, me, draft(db, me, "Opinion", ""), one);
      opened(db, me, one, null);
      let members = cutsMembers(db, me, top.id);
      expectFalse(test, members[0].read, "a draft cut is not a reading");
      expectHas(test, members[0].text, "not read yet");
    }

    test("a folder that is not the scope's, or not there, has no members") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = folderIn(db, other, "Theirs", null);
      moveTo(db, other, draft(db, other, "Opinion", ""), theirs);
      expectInt(test, cutsMembers(db, me, theirs.id).length, 0);
      expectInt(test, cutsMembers(db, me, 9999).length, 0);
      expectInt(test, cutsMembers(db, me, null).length, 0);
      expectInt(test, cutsMembers(db, other, theirs.id).length, 1);
    }

    test("a draft with nodes contributes its map: first impression, then each node and its quote") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      let w = draft(db, me, "Opinion", "");
      moveTo(db, me, w, f);
      db.exec("UPDATE works SET first_impression = $1, status = 'read' WHERE id = $2", ["It argues one thing.", w.id.toString()]);
      db.insert("INSERT INTO nodes (work_id, node_type, title, quote, ordinal) VALUES ($1, 'claim', 'Standing is absent', 'the court held', 1)", [w.id.toString()]);
      db.insert("INSERT INTO nodes (work_id, node_type, title, quote, ordinal) VALUES ($1, 'question', 'Who may sue', '', 2)", [w.id.toString()]);
      db.insert("INSERT INTO nodes (work_id, node_type, title, ordinal) VALUES ($1, 'aside', 'A detour', 3)", [w.id.toString()]);
      let members = cutsMembers(db, me, f.id);
      expectText(test, members[0].text,
        "It argues one thing.\n\nclaim: Standing is absent\n> the court held\n\nquestion: Who may sue\n\naside: A detour");
      expectTrue(test, members[0].read, "the draft is read");
    }

    test("a draft with no nodes contributes at most 1200 characters of each section") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      let w = draft(db, me, "Opinion", "");
      moveTo(db, me, w, f);
      db.exec("UPDATE sections SET body = $1 WHERE work_id = $2", [repeatedWord(600), w.id.toString()]);
      let members = cutsMembers(db, me, f.id);
      let sections = db.query("SELECT id FROM sections WHERE work_id = $1", [w.id.toString()]);
      expectTrue(test, sysByteLength(members[0].text) <= 1200 * sections.length + 2 * sections.length, "cut at 1200 each: ${sysByteLength(members[0].text).toString()}");
      expectFalse(test, members[0].text.isEmpty, "something");
    }

    test("the fingerprint is the SHA-256 of kind:id:text lines") { test =>
      let a = new CutMember(1, "work", 3, "A", false, "x");
      let b = new CutMember(2, "folder", 4, "B", true, "y");
      expectText(test, cutsContentSha([a, b]), "d59578166f26611f201d3a5ed66206acc710ef8f4726e921a89019a32b14e66d");
    }

## Opening, listing, staleness

    test("a folder has one reading, and re-opening replaces it") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      moveTo(db, me, draft(db, me, "Opinion", ""), f);
      let first = opened(db, me, f, "why?");
      let again = opened(db, me, f, "why really?");
      expectInt(test, first.id, again.id);
      expectText(test, orNil(again.question), "why really?");
      expectInt(test, cutsList(db, me).length, 1);
    }

    test("a new reading is a draft titled for its folder, scoped to the folder") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      let c = opened(db, me, f, null);
      expectText(test, c.title, "A case");
      expectText(test, c.status, "draft");
      expectText(test, c.scope, "folder");
      expectText(test, orNil(c.question), "nil");
      expectText(test, orNil(c.thesis), "nil");
      expectInt(test, c.threads.length, 0);
      expectInt(test, c.members.length, 0);
      expectInt(test, c.userId, me.userId);
      expectText(test, orNil(if (c.folderId != null) { f.id.toString() } else { null }), f.id.toString());
    }

    test("re-opening keeps the question when none is given and keeps the old reading, but resets the status") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      moveTo(db, me, draft(db, me, "Opinion", ""), f);
      let c = opened(db, me, f, "why?");
      stored(db, c, "A thesis.", [new CutThread("A claim.", [])], "abc");
      cutsSetStatus(db, c, "failed", "boom");
      let again = opened(db, me, f, null);
      expectText(test, again.status, "draft");
      expectText(test, orNil(again.question), "why?");
      expectText(test, orNil(again.thesis), "A thesis.");
      expectInt(test, again.threads.length, 1);
      expectText(test, orNil(again.contentSha), "abc");
      expectText(test, orNil(again.statusDetail), "boom");
    }

    test("another writer's folder cannot be read") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = folderIn(db, other, "Theirs", null);
      let r = cutsOpenFolderReading(db, me, theirs.id, null);
      expectText(test, orNil(r.error), "not_found");
      expectTrue(test, r.ok == null, "no cut");
      expectInt(test, cutsList(db, me).length, 0);
      expectInt(test, cutsList(db, other).length, 0);
    }

    test("a reading is stale once the folder holds something else") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      moveTo(db, me, draft(db, me, "Opinion", ""), f);
      let cut = opened(db, me, f, null);
      let read = stored(db, cut, null, [], cutsContentSha(cutsMembers(db, me, f.id)));
      expectTrue(test, cutsCurrent(db, me, read), "current");
      expectFalse(test, cutsIsStale(db, me, read), "not stale");
      moveTo(db, me, draft(db, me, "Late arrival", ""), f);
      expectFalse(test, cutsCurrent(db, me, read), "no longer current");
      expectTrue(test, cutsIsStale(db, me, read), "stale");
    }

    test("a reading with no fingerprint is not current, and is not stale unless read") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      moveTo(db, me, draft(db, me, "Opinion", ""), f);
      let cut = opened(db, me, f, null);
      expectFalse(test, cutsCurrent(db, me, cut), "no sha");
      expectFalse(test, cutsIsStale(db, me, cut), "a draft is not stale");
    }

    test("a reading whose folder is gone is not current") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      moveTo(db, me, draft(db, me, "Opinion", ""), f);
      let cut = opened(db, me, f, null);
      let read = stored(db, cut, null, [], "abc");
      db.exec("DELETE FROM folders WHERE id = $1", [f.id.toString()]);
      let after = cutsGet(db, me, read.id);
      expectTrue(test, after != null, "the cut outlives its folder");
      expectText(test, orNil(if (after != null) { if (after.folderId == null) { "no folder" } else { "folder" } } else { null }), "no folder");
      if (after != null) { expectFalse(test, cutsCurrent(db, me, after), "not current"); }
    }

    test("list is newest-updated first and scoped; get and forFolder are scoped") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let f1 = folderIn(db, me, "One", null);
      let f2 = folderIn(db, me, "Two", null);
      let c1 = opened(db, me, f1, null);
      let c2 = opened(db, me, f2, null);
      db.exec("UPDATE cuts SET updated_at = '2020-01-01 00:00:00' WHERE id = $1", [c2.id.toString()]);
      expectText(test, joined(cutsList(db, me).map { (c: Cut): String => c.title }), "One,Two");
      db.exec("UPDATE cuts SET updated_at = '2020-01-02 00:00:00' WHERE id = $1", [c2.id.toString()]);
      db.exec("UPDATE cuts SET updated_at = '2020-01-01 00:00:00' WHERE id = $1", [c1.id.toString()]);
      expectText(test, joined(cutsList(db, me).map { (c: Cut): String => c.title }), "Two,One");
      expectInt(test, cutsList(db, other).length, 0);
      expectTrue(test, cutsGet(db, me, c1.id) != null, "mine");
      expectTrue(test, cutsGet(db, other, c1.id) == null, "not theirs");
      expectTrue(test, cutsGet(db, me, 9999) == null, "none");
      expectTrue(test, cutsForFolder(db, me, f1.id) != null, "for folder");
      expectTrue(test, cutsForFolder(db, other, f1.id) == null, "for folder, not theirs");
      let fo = cutsFolder(db, me, c1);
      expectText(test, if (fo != null) { fo.name } else { "nil" }, "One");
    }

    test("delete removes the reading") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      let c = opened(db, me, f, null);
      expectTrue(test, cutsDelete(db, c), "deleted");
      expectInt(test, cutsList(db, me).length, 0);
      expectFalse(test, cutsDelete(db, c), "nothing left to delete");
    }

    test("set status replaces the status and its detail, without validation") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      let c = opened(db, me, f, null);
      let failed = cutsSetStatus(db, c, "failed", "why");
      expectText(test, failed.status, "failed");
      expectText(test, orNil(failed.statusDetail), "why");
      let odd = cutsSetStatus(db, failed, "whatever", null);
      expectText(test, odd.status, "whatever");
      expectText(test, orNil(odd.statusDetail), "nil");
    }

    test("deleting the user removes the readings") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      opened(db, me, f, null);
      db.exec("DELETE FROM users WHERE id = $1", [me.userId.toString()]);
      let rows = db.query("SELECT id FROM cuts", []);
      expectInt(test, rows.length, 0);
    }

## Creating and validating

    test("create validates the title and the status as the changeset did") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let blank = cutsCreate(db, me, cutParams("  "));
      expectText(test, orNil(blank.error), "invalid");
      expectText(test, blank.errors[0].field, "title");
      expectText(test, blank.errors[0].message, "can't be blank");
      let missing = cutsCreate(db, me, cutParams(null));
      expectText(test, missing.errors[0].message, "can't be blank");
      let long = cutsCreate(db, me, cutParams(repeatedWord(41)));
      expectText(test, long.errors[0].message, "should be at most 200 character(s)");
      let p = cutParams("Ok");
      p.status = "done";
      let bad = cutsCreate(db, me, p);
      expectText(test, bad.errors[0].field, "status");
      expectText(test, bad.errors[0].message, "is invalid");
      expectInt(test, cutsList(db, me).length, 0);
    }

    test("create stores a folderless reading with its defaults, and trims the title") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let p = cutParams("  Loose  ");
      p.question = "";
      let r = cutsCreate(db, me, p);
      let c = r.ok;
      expectTrue(test, c != null, "created");
      if (c != null) {
        expectText(test, c.title, "Loose");
        expectText(test, c.status, "draft");
        expectText(test, c.scope, "folder");
        expectText(test, orNil(c.question), "nil");
        expectTrue(test, c.folderId == null, "no folder");
      }
    }

    test("two readings of one folder are refused by the index") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      opened(db, me, f, null);
      let p = cutParams("Again");
      p.folderId = f.id;
      let r = do { cutsCreate(db, me, p); "created" } orelse "refused";
      expectText(test, r, "refused");
      expectInt(test, cutsList(db, me).length, 1);
    }

    test("store result round-trips threads, tensions, dropped and members as JSON") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "A case", null);
      let c = opened(db, me, f, null);
      let pick = new CutPick(2, "work", 11, "Dissent \"quoted\"", "line one\nline two");
      let r = cutsStoreResult(db, c, new CutResult(
        "Thesis.", [new CutThread("T claim", [pick, pick])], [new CutTension("X claim", [pick])],
        "Nothing on remedy.", ["thread \"a\": no evidence"], "sha1", "read",
        [new CutMemberRef(1, "work", 10, "Opinion", true), new CutMemberRef(2, "folder", 11, "Dissent", false)],
      ));
      let got = r.ok;
      expectTrue(test, got != null, "stored");
      if (got != null) {
        expectText(test, got.status, "read");
        expectText(test, orNil(got.thesis), "Thesis.");
        expectInt(test, got.threads.length, 1);
        expectInt(test, got.threads[0].evidence.length, 2);
        expectText(test, got.threads[0].evidence[0].quote, "line one\nline two");
        expectText(test, got.threads[0].evidence[0].label, "Dissent \"quoted\"");
        expectInt(test, got.threads[0].evidence[0].member, 2);
        expectInt(test, got.threads[0].evidence[0].id, 11);
        expectText(test, got.tensions[0].claim, "X claim");
        expectText(test, orNil(got.notSupported), "Nothing on remedy.");
        expectText(test, joined(got.dropped), "thread \"a\": no evidence");
        expectText(test, orNil(got.contentSha), "sha1");
        expectInt(test, got.members.length, 2);
        expectTrue(test, got.members[0].read, "member 1 read");
        expectFalse(test, got.members[1].read, "member 2 not read");
        expectText(test, got.members[1].kind, "folder");
      }
      let bad = cutsStoreResult(db, c, new CutResult(null, [], [], null, [], null, "nope", []));
      expectText(test, orNil(bad.error), "invalid");
      expectText(test, bad.errors[0].field, "status");
    }

## The prompt and the options of the call

    test("the system prompt is the Elixir's, byte for byte") { test =>
      expectText(test, cutsSystemPrompt(),
        "You are given several members of one group — documents, or the readings of sub-groups — and nothing else. Say what they amount to together.\n\nYou have not been shown anything but what is below. Do not reach for context you do not have, and do not summarise the members back one at a time: the reader can already see them. Say what is true across them that no single member states.\n\nEvery piece of evidence must quote one of the members and name it by its number. A program checks each quote against that member's text and drops what it cannot find, so an approximate quote is a discarded claim.\n\nAn empty list is a real answer. If the members have nothing in common, say so in the thesis and return no threads.\n\nReply with one JSON object and nothing else.\n");
    }

The expected user message below was produced by running the Elixir heredoc
of `Cuts.prompt/2` on these inputs.

    test("the user prompt is the Elixir's, byte for byte") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let p = cutParams("Cases");
      p.question = "why?";
      let c = cutsCreate(db, me, p).ok;
      let members = [
        new CutMember(1, "work", 1, "Opinion", false, "alpha\nbeta"),
        new CutMember(2, "work", 2, "Dissent", false, "gamma"),
      ];
      if (c != null) {
        expectText(test, cutsPrompt(c, members),
          "The reader asks: why?\n\nGroup: Cases\nIts members are documents.\n\n### Member 1: Opinion\n\nalpha\nbeta\n\n### Member 2: Dissent\n\ngamma\n\n---\n\nReport:\n\n- `thesis`: one or two sentences. What these members, together, establish.\n  If they establish nothing together, say that.\n- `threads`: things true across two or more members that no single one\n  states. Each: `claim` (one sentence) and `evidence` — two or more entries,\n  each `{\"member\": N, \"quote\": \"...\"}` quoted from that member.\n- `tensions`: places the members disagree, or where one revises another.\n  Same shape. `[]` if there are none.\n- `not_supported`: one sentence naming something a reader might expect this\n  group to show but which these members do not support. `\"\"` if none.\n\nShape:\n\n{\"thesis\": \"...\",\n \"threads\": [{\"claim\": \"...\", \"evidence\": [{\"member\": 1, \"quote\": \"...\"}]}],\n \"tensions\": [],\n \"not_supported\": \"...\"}\n");
      } else {
        expectTrue(test, false, "cut created");
      }
    }

    test("no question, no 'The reader asks'; folders make 'sub-groups'") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let p = cutParams("Cases");
      p.question = "   ";
      let c = cutsCreate(db, me, p).ok;
      if (c != null) {
        let folders = [new CutMember(1, "folder", 1, "One", false, "x"), new CutMember(2, "folder", 2, "Two", true, "y")];
        let text = cutsPrompt(c, folders);
        expectLacks(test, text, "The reader asks");
        expectHas(test, text, "Group: Cases\nIts members are sub-groups.\n\n### Member 1: One\n\nx\n\n### Member 2: Two\n\ny\n\n---");
        let mixed = cutsPrompt(c, [new CutMember(1, "folder", 1, "One", false, "x"), new CutMember(2, "work", 2, "Two", true, "y")]);
        expectHas(test, mixed, "Its members are documents.");
      } else {
        expectTrue(test, false, "cut created");
      }
    }

## The read

    let leafWithTwo(db: Db, me: Scope): Folder throws Bubble {
      let f = folderIn(db, me, "A case", null);
      moveTo(db, me, draft(db, me, "Opinion", ""), f);
      moveTo(db, me, draft(db, me, "Dissent", ""), f);
      f
    }

    let goodReply(): String {
      "{\"thesis\":\"  Both papers turn on one paragraph.  \",\"threads\":[{\"claim\":\"Each opens with a first paragraph.\",\"evidence\":[{\"member\":1,\"quote\":\"first paragraph of Opinion\"},{\"member\":2,\"quote\":\"first paragraph of Dissent\"}]},{\"claim\":\"Made up.\",\"evidence\":[{\"member\":1,\"quote\":\"nothing like this\"},{\"member\":2,\"quote\":\"first paragraph of Dissent\"}]}],\"tensions\":[],\"not_supported\":\"Nothing on remedy.\"}"
    }

    test("a read stores only what could be checked, with the fingerprint and the members") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = leafWithTwo(db, me);
      let cut = cutsStartRead(db, opened(db, me, f, "what do they share?"));
      expectText(test, cut.status, "reading");
      let llm = llmFake([chatBody(goodReply())]);
      let r = cutsRead(db, llm, cut);
      expectTrue(test, r.error == null, "no error");
      let done = r.ok;
      expectTrue(test, done != null, "a cut");
      if (done != null) {
        expectText(test, done.status, "read");
        expectText(test, orNil(done.thesis), "Both papers turn on one paragraph.");
        expectInt(test, done.threads.length, 1);
        expectText(test, done.threads[0].claim, "Each opens with a first paragraph.");
        expectText(test, labelsOf(done.threads[0].evidence), "Opinion,Dissent");
        expectText(test, done.threads[0].evidence[0].quote, "first paragraph of Opinion");
        expectInt(test, done.tensions.length, 0);
        expectText(test, orNil(done.notSupported), "Nothing on remedy.");
        expectText(test, joined(done.dropped), "thread \"Made up.\": quote is not in member 1,thread \"Made up.\": 1 verifiable citation(s), needs 2");
        expectInt(test, done.members.length, 2);
        expectText(test, done.members[0].label, "Opinion");
        expectInt(test, done.members[1].n, 2);
        expectText(test, orNil(done.contentSha), cutsContentSha(cutsMembers(db, me, f.id)));
        expectTrue(test, cutsCurrent(db, me, done), "current");
        let again = cutsGet(db, me, done.id);
        expectText(test, if (again != null) { again.status } else { "nil" }, "read");
      }
    }

    test("the call is one json request: effort high, temperature 0.3, system then user") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = leafWithTwo(db, me);
      let cut = opened(db, me, f, "why?");
      let llm = llmFake([chatBody(goodReply())]);
      cutsRead(db, llm, cut);
      expectInt(test, sentCount(test, llm), 1);
      let sent = lastSent(test, llm);
      expectHas(test, sent, "\"response_format\":{\"type\":\"json_object\"}");
      expectHas(test, sent, "\"reasoning_effort\":\"high\"");
      expectHas(test, sent, "\"temperature\":0.3");
      expectHas(test, sent, "\"max_tokens\":32000");
      expectHas(test, sent, "You are given several members of one group");
      expectHas(test, sent, "The reader asks: why?");
      expectHas(test, sent, "### Member 1: Opinion");
      expectHas(test, sent, "### Member 2: Dissent");
      expectHas(test, sent, "Group: A case");
    }

    test("a model failure leaves the cut failed with the error's text, and is not retried") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = leafWithTwo(db, me);
      let cut = cutsStartRead(db, opened(db, me, f, null));
      let llm = llmFake([chatBody("Sure, here you go."), chatBody(goodReply())]);
      let r = cutsRead(db, llm, cut);
      expectInt(test, sentCount(test, llm), 1);
      let failed = r.ok;
      expectTrue(test, failed != null, "the stored cut");
      if (failed != null) {
        expectText(test, failed.status, "failed");
        expectHas(test, orNil(failed.statusDetail), "invalid_json");
        expectText(test, orNil(r.error), orNil(failed.statusDetail));
        expectTrue(test, failed.thesis == null, "nothing stored");
      }
    }

    test("an empty folder fails without asking the model") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderIn(db, me, "Empty", null);
      let cut = cutsStartRead(db, opened(db, me, f, null));
      let llm = llmFake([chatBody(goodReply())]);
      let r = cutsRead(db, llm, cut);
      expectInt(test, sentCount(test, llm), 0);
      let failed = r.ok;
      if (failed != null) {
        expectText(test, failed.status, "failed");
        expectText(test, orNil(failed.statusDetail), "this folder holds nothing to read");
      } else {
        expectTrue(test, false, "a cut");
      }
      expectText(test, orNil(r.error), "this folder holds nothing to read");
    }

    test("a cut with no folder holds nothing to read") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let cut = cutsCreate(db, me, cutParams("Loose")).ok;
      let llm = llmFake([chatBody(goodReply())]);
      if (cut != null) {
        let r = cutsRead(db, llm, cut);
        expectText(test, orNil(r.error), "this folder holds nothing to read");
        expectInt(test, sentCount(test, llm), 0);
      } else {
        expectTrue(test, false, "created");
      }
    }

    test("a read where nothing can be checked still finishes: read, with every claim dropped") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = leafWithTwo(db, me);
      let cut = opened(db, me, f, null);
      let reply = "{\"thesis\":\"Nothing in common.\",\"threads\":[],\"tensions\":[],\"not_supported\":\"\"}";
      let r = cutsRead(db, llmFake([chatBody(reply)]), cut);
      let done = r.ok;
      if (done != null) {
        expectText(test, done.status, "read");
        expectText(test, orNil(done.thesis), "Nothing in common.");
        expectInt(test, done.threads.length, 0);
        expectInt(test, done.dropped.length, 0);
        expectText(test, orNil(done.notSupported), "");
      } else {
        expectTrue(test, false, "a cut");
      }
    }

    test("status_detail is not cleared by a successful read") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = leafWithTwo(db, me);
      let cut = opened(db, me, f, null);
      let failed = cutsSetStatus(db, cut, "failed", "earlier trouble");
      let r = cutsRead(db, llmFake([chatBody(goodReply())]), failed);
      let done = r.ok;
      if (done != null) {
        expectText(test, done.status, "read");
        expectText(test, orNil(done.statusDetail), "earlier trouble");
      } else {
        expectTrue(test, false, "a cut");
      }
    }

    test("a re-read replaces the earlier reading") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = leafWithTwo(db, me);
      let cut = opened(db, me, f, null);
      let first = cutsRead(db, llmFake([chatBody(goodReply())]), cut).ok;
      let again = opened(db, me, f, "again?");
      expectText(test, again.status, "draft");
      expectText(test, orNil(again.thesis), "Both papers turn on one paragraph.");
      let reply = "{\"thesis\":\"Second.\",\"threads\":[],\"tensions\":[],\"not_supported\":\"x\"}";
      let second = cutsRead(db, llmFake([chatBody(reply)]), again).ok;
      if (second != null) {
        expectText(test, orNil(second.thesis), "Second.");
        expectInt(test, second.threads.length, 0);
        expectInt(test, second.dropped.length, 0);
        expectInt(test, cutsList(db, me).length, 1);
      } else {
        expectTrue(test, false, "a cut");
      }
      expectTrue(test, first != null, "first read");
    }

    test("a folder of folders is read over its children's readings, and says sub-groups") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let top = folderIn(db, me, "Cases", null);
      let one = folderIn(db, me, "Case one", top);
      let two = folderIn(db, me, "Case two", top);
      moveTo(db, me, draft(db, me, "Opinion", ""), one);
      moveTo(db, me, draft(db, me, "Dissent", ""), two);
      let cOne = opened(db, me, one, null);
      stored(db, cOne, "Case one turned on standing.", [new CutThread("Standing was contested.", [])], null);
      let cTop = opened(db, me, top, null);
      let reply = "{\"thesis\":\"Both are about standing.\",\"threads\":[{\"claim\":\"Standing recurs.\",\"evidence\":[{\"member\":1,\"quote\":\"turned on standing\"},{\"member\":2,\"quote\":\"not read yet\"}]}],\"tensions\":[],\"not_supported\":\"\"}";
      let llm = llmFake([chatBody(reply)]);
      let r = cutsRead(db, llm, cTop);
      expectHas(test, lastSent(test, llm), "Its members are sub-groups.");
      let done = r.ok;
      if (done != null) {
        expectText(test, done.status, "read");
        expectInt(test, done.threads.length, 1);
        expectText(test, idsOf(done.threads[0].evidence), "${one.id.toString()},${two.id.toString()}");
        expectText(test, done.threads[0].evidence[1].kind, "folder");
        expectTrue(test, done.members[0].read, "child one read");
        expectFalse(test, done.members[1].read, "child two not read");
      } else {
        expectTrue(test, false, "a cut");
      }
    }

    test("watchers of the cut's topic are told when a read starts and when it ends") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = leafWithTwo(db, me);
      let cut = opened(db, me, f, null);
      let topic = cutsTopic(cut.id);
      expectText(test, topic, "cut:${cut.id.toString()}");
      expectInt(test, versionsOf(db, topic), 0);
      let started = cutsStartRead(db, cut);
      expectInt(test, versionsOf(db, topic), 1);
      cutsRead(db, llmFake([chatBody(goodReply())]), started);
      expectInt(test, versionsOf(db, topic), 2);
    }

    test("a restart mid-read: the sweep fails every reading and leaves the others") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f1 = folderIn(db, me, "One", null);
      let f2 = folderIn(db, me, "Two", null);
      let c1 = cutsStartRead(db, opened(db, me, f1, null));
      let c2 = opened(db, me, f2, null);
      expectInt(test, cutsSweepReading(db), 1);
      let after1 = cutsGet(db, me, c1.id);
      let after2 = cutsGet(db, me, c2.id);
      if (after1 != null) {
        expectText(test, after1.status, "failed");
        expectText(test, orNil(after1.statusDetail), "interrupted by a restart");
      } else {
        expectTrue(test, false, "cut one");
      }
      expectText(test, if (after2 != null) { after2.status } else { "nil" }, "draft");
      expectInt(test, cutsSweepReading(db), 0);
    }
