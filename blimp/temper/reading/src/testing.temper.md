# What the reading tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated, so a
test never sees another's rows. The helpers carry an `rd` prefix: the names of
every library share one namespace once built.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let {
      Work, Section, NodeParams, GraphNode, WorkParams, workParams,
      worksCreateWork, worksListSections, worksInsertNode, worksInsertNodes, worksLink,
      worksSectionById, worksGetById,
    } = import("works/src");
    let { LlmClient, llmFake, llmRequests, llmLastRequest } = import("llm/src");
    let { JsonTextProducer, JsonSyntaxTree, JsonObject, JsonArray, JsonString, parseJson } = import("std/json");
    let { sysJoin } = import("sys/src");

## Assertions

    let rdText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let rdInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let rdTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let rdFalse(test: Test, got: Boolean, what: String): Void {
      assert(!got) { what }
    }

    let rdHas(test: Test, s: String, part: String): Void {
      assert(readingContains(s, part)) { "expected ${part} in:\n${s}" }
    }

    let rdLacks(test: Test, s: String, part: String): Void {
      assert(!readingContains(s, part)) { "did not expect ${part} in:\n${s}" }
    }

    let rdOr(s: String?, fallback: String): String {
      if (s != null) { s } else { fallback }
    }

    let rdJoin(xs: List<String>): String { sysJoin(xs, "|") }

`unit` repeated `n` times, by doubling, since a loop of appends is quadratic.

    let rdRepeat(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = rdRepeat(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

## Fixtures

A user row of the minimal kind, and the scope for it.

    let rdUser(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { new Scope(User.fromRow(row)) } else { bubble() }
    }

A draft created through the public function; a failure to create is a test
failure.

    let rdWork(db: Db, scope: Scope, title: String, body: String): Work throws Bubble {
      let r = worksCreateWork(db, scope, workParams(title, body));
      let w = r.ok;
      if (w != null) { w } else {
        console.log("rdWork failed: ${rdOr(r.error, "?")}");
        bubble()
      }
    }

    let rdFirst(db: Db, work: Work): Section throws Bubble {
      worksListSections(db, work.id)[0]
    }

    let rdSection(db: Db, id: Int): Section throws Bubble {
      let s = worksSectionById(db, id);
      if (s != null) { s } else { bubble() }
    }

A beat in a section, with a quote.

    let rdBeat(db: Db, work: Work, section: Section, title: String, quote: String?): GraphNode throws Bubble {
      let p = new NodeParams(work.id, "beat", title);
      p.sectionId = section.id;
      p.quote = quote;
      let node = worksInsertNode(db, p).node;
      if (node != null) { node } else { bubble() }
    }

The section with a summary written straight onto the row, the way the Elixir
tests did with `Ecto.Changeset.change |> Repo.update`.

    let rdSummarise(
      db: Db, section: Section, summary: String, fingerprint: String?, body: String?,
    ): Section throws Bubble {
      db.exec(
        "UPDATE sections SET summary = $1, summary_fingerprint = $2, summary_body = $3 WHERE id = $4",
        readingArgs().s(summary).s(fingerprint).s(body).n(section.id).build(),
      );
      rdSection(db, section.id)
    }

A section as the struct it was with some fields changed. The record is
immutable, so this is its constructor spelled out.

    let rdWithBody(s: Section, body: String): Section {
      new Section(
        s.id, s.workId, s.ordinal, s.title, body, s.wordCount, s.status, s.summary,
        s.summaryFingerprint, s.summarisedAt, s.summaryCovers, s.summaryFollows,
        s.summarySetsUp, s.summaryDropped, s.summaryBody, s.insertedAt, s.updatedAt,
      )
    }

    let rdWithSummary(s: Section, summary: String?): Section {
      new Section(
        s.id, s.workId, s.ordinal, s.title, s.body, s.wordCount, s.status, summary,
        s.summaryFingerprint, s.summarisedAt, s.summaryCovers, s.summaryFollows,
        s.summarySetsUp, s.summaryDropped, s.summaryBody, s.insertedAt, s.updatedAt,
      )
    }

    let rdWithTitle(s: Section, title: String): Section {
      new Section(
        s.id, s.workId, s.ordinal, title, s.body, s.wordCount, s.status, s.summary,
        s.summaryFingerprint, s.summarisedAt, s.summaryCovers, s.summaryFollows,
        s.summarySetsUp, s.summaryDropped, s.summaryBody, s.insertedAt, s.updatedAt,
      )
    }

The paragraph of `section` that holds `lead`, from the splitter the page uses.

    let rdBlockWith(section: Section, lead: String): String {
      let ps = readingSplit(section.body);
      var i = 0;
      while (i < ps.length) {
        if (readingContains(ps[i], lead)) { return ps[i]; }
        i += 1;
      }
      ""
    }

## The model's side of a call

The body of a chat-completions answer in which the model called `name` with
`argsJson`. The arguments are a string inside the JSON, so the producer does
the escaping.

    let rdToolReply(name: String, argsJson: String): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("message");
      p.startObject();
      p.objectKey("role");
      p.stringValue("assistant");
      p.objectKey("content");
      p.nullValue();
      p.objectKey("tool_calls");
      p.startArray();
      p.startObject();
      p.objectKey("id");
      p.stringValue("call_1");
      p.objectKey("type");
      p.stringValue("function");
      p.objectKey("function");
      p.startObject();
      p.objectKey("name");
      p.stringValue(name);
      p.objectKey("arguments");
      p.stringValue(argsJson);
      p.endObject();
      p.endObject();
      p.endArray();
      p.endObject();
      p.objectKey("finish_reason");
      p.stringValue("tool_calls");
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

An answer in which the model said something and called nothing.

    let rdTextReply(content: String): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("message");
      p.startObject();
      p.objectKey("role");
      p.stringValue("assistant");
      p.objectKey("content");
      p.stringValue(content);
      p.endObject();
      p.objectKey("finish_reason");
      p.stringValue("stop");
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

A JSON object parsed from text, for the validators.

    let rdJson(text: String): JsonSyntaxTree throws Bubble {
      parseJson(text)
    }

What the client was sent. Each reads the client inside a helper that takes the
`test`: the frontend folds a call on an object built at compile time, so state
inspected from the test body itself would be the state before the call.

    let rdCalls(test: Test, llm: LlmClient, want: Int): Void {
      rdInt(test, llmRequests(llm).length, want);
    }

    let rdSent(test: Test, llm: LlmClient, part: String): Void {
      rdHas(test, rdOr(llmLastRequest(llm), ""), part);
    }

    let rdSentNot(test: Test, llm: LlmClient, part: String): Void {
      rdLacks(test, rdOr(llmLastRequest(llm), ""), part);
    }

    let rdSentAt(test: Test, llm: LlmClient, index: Int, part: String): Void {
      let all = llmRequests(llm);
      rdTrue(test, index < all.length, "request ${index.toString()} was sent");
      if (index < all.length) { rdHas(test, all[index], part); }
    }

    let rdSentNotAt(test: Test, llm: LlmClient, index: Int, part: String): Void {
      let all = llmRequests(llm);
      rdTrue(test, index < all.length, "request ${index.toString()} was sent");
      if (index < all.length) { rdLacks(test, all[index], part); }
    }

A JSON property as text, for asserting on what was stored.

    let rdSectionsOf(item: JsonObject): String {
      let v = item.propertyValueOrNull("sections");
      if (v is JsonArray) {
        sysJoin(v.elements.map { (e: JsonSyntaxTree): String => readingInspect(e) }, ",")
      } else {
        "none"
      }
    }
