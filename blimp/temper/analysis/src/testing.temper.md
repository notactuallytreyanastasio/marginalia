# What the analysis tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { sysJoin } = import("sys/src");
    let { JsonTextProducer } = import("std/json");
    let {
      Work, Section, GraphNode, worksCreateWork, workParams, worksGetById, worksListSections,
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

    let expectHas(test: Test, s: String, part: String): Void {
      assert(anContains(s, part)) { "expected ${part} in:\n${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!anContains(s, part)) { "did not expect ${part} in:\n${s}" }
    }

    let orNull(s: String?): String {
      if (s != null) { s } else { "<null>" }
    }

`unit` repeated `n` times, by doubling.

    let repeated(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = repeated(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

## Users and works

    let makeUser(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { new Scope(User.fromRow(row)) } else { bubble() }
    }

    let makeWork(db: Db, scope: Scope, title: String, body: String): Work throws Bubble {
      let r = worksCreateWork(db, scope, workParams(title, body));
      let w = r.ok;
      if (w != null) { w } else {
        console.log("makeWork failed: ${orNull(r.error)}");
        bubble()
      }
    }

    let reloaded(db: Db, work: Work): Work throws Bubble {
      let w = worksGetById(db, work.id);
      if (w != null) { w } else { bubble() }
    }

    let sectionsOf(db: Db, work: Work): List<Section> throws Bubble {
      worksListSections(db, work.id)
    }

    let count(db: Db, sql: String): Int throws Bubble {
      let row = db.one(sql, []);
      if (row != null) { row.int("n") } else { -1 }
    }

    let titlesOfNodes(nodes: List<GraphNode>): String {
      sysJoin(nodes.map { (n: GraphNode): String => n.title }, " | ")
    }

## Canned replies

A chat completion carrying `content`, as the provider would send it.

    let fakeContent(content: String): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("finish_reason");
      p.stringValue("stop");
      p.objectKey("index");
      p.int32Value(0);
      p.objectKey("message");
      p.startObject();
      p.objectKey("content");
      p.stringValue(content);
      p.objectKey("role");
      p.stringValue("assistant");
      p.endObject();
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

A chat completion carrying tool calls: `(name, argumentsJson)` pairs.

    class FakeCall(public name: String, public args: String) {}

    let fakeCalls(calls: List<FakeCall>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("choices");
      p.startArray();
      p.startObject();
      p.objectKey("finish_reason");
      p.stringValue("tool_calls");
      p.objectKey("index");
      p.int32Value(0);
      p.objectKey("message");
      p.startObject();
      p.objectKey("content");
      p.nullValue();
      p.objectKey("role");
      p.stringValue("assistant");
      p.objectKey("tool_calls");
      p.startArray();
      var i = 0;
      var k_c = 0;
      while (k_c < calls.length) {
        let c = calls[k_c];
        i += 1;
        p.startObject();
        p.objectKey("function");
        p.startObject();
        p.objectKey("arguments");
        p.stringValue(c.args);
        p.objectKey("name");
        p.stringValue(c.name);
        p.endObject();
        p.objectKey("id");
        p.stringValue("call_${i.toString()}");
        p.objectKey("type");
        p.stringValue("function");
        p.endObject();
        k_c += 1;
      }
      p.endArray();
      p.endObject();
      p.endObject();
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

A reply that was cut off.

    let fakeLength(): String throws Bubble {
      "{\"choices\":[{\"finish_reason\":\"length\",\"index\":0,\"message\":{\"content\":\"{\\\"spine\\\": [\",\"role\":\"assistant\"}}]}"
    }
