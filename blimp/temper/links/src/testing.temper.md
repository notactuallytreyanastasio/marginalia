# What the links tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated, so a
test never sees another's rows. Users are inserted with SQL; drafts go through
`worksCreateWork`.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns, accountsOwnerEmail } = import("accounts/src");
    let {
      Work, Section, GraphNode, NodeParams, workParams, worksCreateWork, worksSetStatus,
      worksListSections, worksInsertNode, worksUpdateWork,
    } = import("works/src");
    let { versionsOf } = import("runs/src");
    let { llmFake, llmFakeScript, LlmFakeResponse, llmRequests, LlmClient } = import("llm/src");
    let {
      JsonSyntaxTree, JsonArray, JsonObject, JsonTextProducer, NullInterchangeContext, parseJson,
    } = import("std/json");
    let { sysJoin, sysGraphemeLength } = import("sys/src");

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

    let orNone(s: String?): String {
      if (s != null) { s } else { "<none>" }
    }

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "expected ${part} in:\n${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "did not expect ${part} in:\n${s}" }
    }

`first` appears before `second` in `s`.

    let expectBefore(test: Test, s: String, first: String, second: String): Void {
      let head = s.split(second)[0];
      assert(hasText(s, second) && hasText(head, first)) { "expected ${first} before ${second} in:\n${s}" }
    }

`unit` repeated `n` times, by doubling, since a loop of appends is quadratic.

    let repeated(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = repeated(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

## Users and drafts

    let makeUser(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { new Scope(User.fromRow(row)) } else { bubble() }
    }

    let userIdOf(scope: Scope): Int throws Bubble { scope.userId }

A draft created through the public function; a failure to create is a test
failure.

    let makeWork(db: Db, scope: Scope, title: String, body: String): Work throws Bubble {
      let w = worksCreateWork(db, scope, workParams(title, body)).ok;
      if (w != null) { w } else { bubble() }
    }

    let readWork(db: Db, work: Work): Work throws Bubble {
      worksSetStatus(db, work, "read", null)
    }

    let firstSection(db: Db, work: Work): Section throws Bubble {
      worksListSections(db, work.id)[0]
    }

A node of a work, in a section when `section` is given.

    let addNode(db: Db, work: Work, section: Section?, kind: String, title: String, quote: String?): GraphNode throws Bubble {
      let p = new NodeParams(work.id, kind, title);
      if (section != null) { p.sectionId = section.id; }
      p.quote = quote;
      let node = worksInsertNode(db, p).node;
      if (node != null) { node } else { bubble() }
    }

    class LinksMade(public work: Work, public node: GraphNode) {}

The `make` of the Elixir tests: a read draft with one anchored beat.

    let makeRead(db: Db, scope: Scope, title: String, body: String): LinksMade throws Bubble {
      let w = readWork(db, makeWork(db, scope, title, body));
      new LinksMade(w, addNode(db, w, firstSection(db, w), "beat", "a beat in ${title}", "a sentence"))
    }

    class LinksFx(
      public db: Db,
      public scope: Scope,
      public a: Work,
      public b: Work,
      public c: Work,
      public aNode: GraphNode,
      public bNode: GraphNode,
      public cNode: GraphNode,
      public link: Link,
    ) {}

Three read drafts, First, Second and Third, each with a beat, and the link
between First and Second.

    let linksFixture(): LinksFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "writer@example.com");
      let a = makeRead(db, me, "First", "# One\n\nA sentence that is long enough to be a section.\n\n${repeated("word ", 200)}");
      let b = makeRead(db, me, "Second", "# Two\n\nAnother sentence that is long enough here.\n\n${repeated("word ", 200)}");
      let c = makeRead(db, me, "Third", "# Three\n\nA third sentence, also long enough for this.\n\n${repeated("word ", 200)}");
      let made = linksGetOrCreate(db, a.work.id, b.work.id).ok;
      if (made == null) { bubble() }
      new LinksFx(db, me, a.work, b.work, c.work, a.node, b.node, c.node, linksLinkOrBubble(made))
    }

## Edges as the model proposes them

One proposed edge as JSON text, and a list of them as the parsed items
`linksStoreEdges` takes.

    let edgeJson(from: Int, to: Int, kind: String, why: String): String {
      "{\"from\":${from.toString()},\"to\":${to.toString()},\"type\":\"${kind}\",\"why\":\"${why}\"}"
    }

    let itemsOf(texts: List<String>): List<JsonSyntaxTree> throws Bubble {
      let tree = parseJson("[${sysJoin(texts, ",")}]");
      if (tree is JsonArray) { tree.elements } else { bubble() }
    }

    let oneEdge(from: Int, to: Int, kind: String, why: String): List<JsonSyntaxTree> throws Bubble {
      itemsOf([edgeJson(from, to, kind, why)])
    }

    let objectOf(text: String): JsonObject throws Bubble {
      let tree = parseJson(text);
      if (tree is JsonObject) { tree } else { bubble() }
    }

## Replies the fake model gives

The raw chat-completions body, as the provider would send it. The model's
answer is `content`; a tool call carries its arguments as a JSON string.

    let replyBody(finish: String, content: String?, toolName: String?, toolArgs: String?): String {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("finish_reason");
      p.stringValue(finish);
      p.objectKey("message");
      p.startObject();
      p.objectKey("role");
      p.stringValue("assistant");
      p.objectKey("content");
      if (content != null) { p.stringValue(content); } else { p.nullValue(); }
      if (toolName != null) {
        if (toolArgs != null) {
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
          p.stringValue(toolName);
          p.objectKey("arguments");
          p.stringValue(toolArgs);
          p.endObject();
          p.endObject();
          p.endArray();
        }
      }
      p.endObject();
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString() orelse panic()
    }

    let replyText(content: String): String { replyBody("stop", content, null, null) }

    let replyTool(name: String, args: String): String { replyBody("stop", null, name, args) }

The answer was cut off: `finish_reason` is `length`.

    let replyCutOff(): String { replyBody("length", "{\"summary\":\"cut", null, null) }

No content and no tool call.

    let replyNothing(): String { replyBody("stop", null, null, null) }

What the linker is told: a summary and the edges.

    let linkerReply(summary: String, edges: List<String>): String {
      replyText("{\"summary\":\"${summary}\",\"edges\":[${sysJoin(edges, ",")}]}")
    }

    let lastRequest(test: Test, c: LlmClient): String {
      let all = llmRequests(c);
      if (all.length == 0) { "" } else { all[all.length - 1] }
    }

    let requestCount(test: Test, c: LlmClient): Int { llmRequests(c).length }

    let countOf(db: Db, sql: String): Int throws Bubble {
      let row = db.one(sql, []);
      if (row != null) { row.int("n") } else { -1 }
    }

    let requestsOf(test: Test, c: LlmClient): List<String> { llmRequests(c) }
