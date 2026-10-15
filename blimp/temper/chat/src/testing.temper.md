# What the chat tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { sysJoin, sysGraphemeTake } = import("sys/src");
    let { LlmClient, LlmFakeResponse, llmFakeScript, llmFake, llmRequests } = import("llm/src");
    let { JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonTextProducer,
          NullInterchangeContext, parseJson } = import("std/json");
    let {
      Work, Section, NodeParams, GraphNode, workParams, worksCreateWork,
      worksListSections, worksInsertNode, worksLink,
    } = import("works/src");

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

    let intOr(n: Int?, d: Int): Int { if (n != null) { n } else { d } }

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "expected ${part} in:\n${sysGraphemeTake(s, 400)}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "did not expect ${part} in:\n${sysGraphemeTake(s, 400)}" }
    }

    let orEmpty(s: String?): String { if (s != null) { s } else { "<null>" } }

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

    let userOf(scope: Scope): User throws Bubble {
      let u = scope.user;
      if (u != null) { u } else { bubble() }
    }

`Chapter 1`, one sentence, three hundred words.

    let fixtureBody(): String {
      "Chapter 1\n\nShe stood at the window. ${repeated("word ", 300)}"
    }

    let makeWork(db: Db, scope: Scope, title: String, body: String): Work throws Bubble {
      let r = worksCreateWork(db, scope, workParams(title, body));
      let w = r.ok;
      if (w != null) { w } else { bubble() }
    }

    let firstSection(db: Db, work: Work): Section throws Bubble {
      worksListSections(db, work.id)[0]
    }

    let addNode(db: Db, work: Work, section: Section, kind: String, title: String, body: String?, quote: String?): GraphNode throws Bubble {
      let p = new NodeParams(work.id, kind, title);
      p.sectionId = section.id;
      p.body = body;
      p.quote = quote;
      let node = worksInsertNode(db, p).node;
      if (node != null) { node } else { bubble() }
    }

## Conversations

    let makeConvo(db: Db, work: Work): Conversation throws Bubble {
      let c = chatGetOrCreateConversation(db, work.id).conversation;
      if (c != null) { c } else { bubble() }
    }

    let newConvo(db: Db, work: Work, mode: String?): Conversation throws Bubble {
      let c = chatCreateConversation(db, work.id, mode).conversation;
      if (c != null) { c } else { bubble() }
    }

    let thread(db: Db, work: Work, section: Section, ref: String, quote: String?): Conversation throws Bubble {
      let c = chatThreadForBlock(db, work.id, section.id, ref, quote, null).conversation;
      if (c != null) { c } else { bubble() }
    }

`n` questions, "question 1" onward.

    let askMany(db: Db, convo: Conversation, n: Int): Void throws Bubble {
      var i = 1;
      while (i <= n) {
        chatAppend(db, convo.id, "user", "question ${i.toString()}");
        i += 1;
      }
    }

    let rowCount(db: Db, sql: String): Int throws Bubble {
      let row = db.one(sql, []);
      if (row != null) { row.int("n") } else { -1 }
    }

## Replies the model could send

    let quoted(s: String): String {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.stringValue(s);
      p.toJsonString() orelse panic()
    }

    let replyText(content: String): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":${quoted(content)}},\"finish_reason\":\"stop\"}]}"
    }

    let callJson(id: String, name: String, argumentsJson: String): String {
      "{\"id\":${quoted(id)},\"type\":\"function\",\"function\":{\"name\":${quoted(name)},\"arguments\":${quoted(argumentsJson)}}}"
    }

    let replyCalls(calls: List<String>): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[${sysJoin(calls, ",")}]},\"finish_reason\":\"tool_calls\"}]}"
    }

    let replyCutOff(): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"partial\"},\"finish_reason\":\"length\"}]}"
    }

    let script(bodies: List<String>): LlmClient {
      let rs = new ListBuilder<LlmFakeResponse>();
      var i = 0;
      while (i < bodies.length) {
        rs.add(new LlmFakeResponse(200, bodies[i]));
        i += 1;
      }
      llmFakeScript(rs.toList())
    }

## Reading JSON back

    let treeOf(text: String): JsonSyntaxTree throws Bubble { parseJson(text) }

    let jfield(t: JsonSyntaxTree, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

A string field, or `<none>`.

    let jstr(t: JsonSyntaxTree, key: String): String {
      let v = jfield(t, key);
      if (v is JsonString) { v.content } else { "<none>" }
    }

    let jlen(t: JsonSyntaxTree?): Int {
      if (t is JsonArray) { t.elements.length } else { -1 }
    }

    let jat(t: JsonSyntaxTree?, i: Int): JsonSyntaxTree throws Bubble {
      if (t is JsonArray) { t.elements[i] } else { bubble() }
    }

    let isObject(t: JsonSyntaxTree): Boolean { t is JsonObject }

`name` applied once, the way `run_call` does, the answer decoded.

    let called(db: Db, work: Work, name: String, argumentsJson: String): JsonSyntaxTree throws Bubble {
      parseJson(editorRunTool(db, work, name, argumentsJson, "owner"))
    }

    let calledRaw(db: Db, work: Work, name: String, argumentsJson: String): String throws Bubble {
      editorRunTool(db, work, name, argumentsJson, "owner")
    }
