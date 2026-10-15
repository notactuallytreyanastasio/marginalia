# What the stacks tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated, so a
test never sees another's rows. Users and drafts are made through the
accounts rows and `worksCreateWork`; folders through `foldersCreateFolder`.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { Folder, foldersCreateFolder, foldersMoveWork } = import("folders/src");
    let { Work, WorksResult, worksCreateWork, workParams } = import("works/src");
    let { LlmClient, llmFake } = import("llm/src");
    let { sysJoin, sysStringReplace } = import("sys/src");
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

    let orEmpty(s: String?): String {
      if (s != null) { s } else { "" }
    }

    let orNone(s: String?): String {
      if (s != null) { s } else { "<null>" }
    }

    let orMinus(n: Int?): Int {
      if (n != null) { n } else { -1 }
    }

Whether any of the strings contains the part: `Enum.any?(dropped, &(&1 =~ part))`.

    let anyHas(xs: List<String>, part: String): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (hasText(xs[i], part)) { return true; }
        i += 1;
      }
      false
    }

    let countHas(xs: List<String>, part: String): Int {
      var n = 0;
      var i = 0;
      while (i < xs.length) {
        if (hasText(xs[i], part)) { n += 1; }
        i += 1;
      }
      n
    }

    let joined(xs: List<String>): String {
      sysJoin(xs, ",")
    }

    let intsText(xs: List<Int>): String {
      sysJoin(xs.map { (x: Int): String => x.toString() }, ",")
    }

`unit` repeated `n` times, by doubling, since a loop of appends is quadratic.

    let repeated(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = repeated(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

## Fixtures

    let makeUser(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { new Scope(User.fromRow(row)) } else { bubble() }
    }

The default body of `draft/3` in the Elixir test: a heading, two paragraphs
with something quotable in the second, and a hundred and twenty words.

    let defaultBody(title: String): String {
      "# ${title}\n\nThe first paragraph of ${title}, long enough to stand alone.\n\nA second paragraph with something quotable in it.\n\n${repeated("word ", 120)}"
    }

    let madeWork(r: WorksResult): Work throws Bubble {
      let w = r.ok;
      if (w != null) { w } else { bubble() }
    }

    let makeDraftWith(db: Db, s: Scope, title: String, body: String): Work throws Bubble {
      madeWork(worksCreateWork(db, s, workParams(title, body)))
    }

    let makeDraft(db: Db, s: Scope, title: String): Work throws Bubble {
      makeDraftWith(db, s, title, defaultBody(title))
    }

    let makeFolder(db: Db, s: Scope, name: String): Folder throws Bubble {
      let r = foldersCreateFolder(db, s, name, null);
      let f = r.folder;
      if (f != null) { f } else { bubble() }
    }

    let fileWork(db: Db, s: Scope, w: Work, f: Folder): Void throws Bubble {
      let r = foldersMoveWork(db, s, w.id, f.id);
      if (!r.ok) { bubble() }
    }

A draft filed into a folder.

    let makeFiled(db: Db, s: Scope, f: Folder, title: String): Work throws Bubble {
      let w = makeDraft(db, s, title);
      fileWork(db, s, w, f);
      w
    }

A folder of `n` numbered documents, "1. Doc 1" onwards, filed.

    let makeStack(db: Db, s: Scope, name: String, n: Int): Folder throws Bubble {
      let f = makeFolder(db, s, name);
      var i = 1;
      while (i <= n) {
        makeFiled(db, s, f, "${i.toString()}. Doc ${i.toString()}");
        i += 1;
      }
      f
    }

A step row inserted directly, as the Elixir tests did with `Repo.insert!`.

    let makeStep(db: Db, folderId: Int, workId: Int, ordinal: Int, capability: String, requires: List<Int>): StackStep throws Bubble {
      let id = db.insert(
        "INSERT INTO stack_steps (folder_id, work_id, ordinal, capability, requires, lesson) VALUES ($1, $2, $3, $4, $5, $6)",
        [folderId.toString(), workId.toString(), ordinal.toString(), capability, stacksJsonInts(requires), "Lesson ${ordinal.toString()}."],
      );
      let step = stacksStepById(db, id);
      if (step != null) { step } else { bubble() }
    }

## Raw model answers

JSON written with single quotes (so the tests are readable), parsed into the
object the validators take. A test text never contains an apostrophe.

    let rawOf(text: String): JsonObject throws Bubble {
      let tree = parseJson(sysStringReplace(text, "'", "\""));
      if (tree is JsonObject) { tree } else { bubble() }
    }

A chat completion whose one tool call is `name` with `args` (single-quoted
JSON) as its arguments.

    let toolReply(name: String, args: String): String throws Bubble {
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
      p.stringValue(sysStringReplace(args, "'", "\""));
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

A chat completion that answers in prose and calls nothing.

    let proseReply(): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"I would rather not.\"},\"finish_reason\":\"stop\"}]}"
    }

What a pass reports, collected.

    class StackProbe {
      public var calls: ListBuilder<String> = new ListBuilder<String>();
      public record(progress: String, detail: String?): Void {
        calls.add("${progress}|${orEmpty(detail)}");
      }
      public text(): String { sysJoin(calls.toList(), ",") }
      public count(): Int { calls.length }
    }

## Runs

A `running` row for the folder's key, as `runsStart` would have made it, so
that `runsProgress` and `runsFinish` have something to update.

    let startRun(db: Db, folderId: Int): Void throws Bubble {
      db.exec(
        "INSERT INTO runs (key, status, started_at) VALUES ($1, 'running', '2026-01-01 00:00:00')",
        [stacksRunKey(folderId)],
      );
    }
