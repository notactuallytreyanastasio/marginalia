# Tests for runs

Every check runs inside a helper that takes the `test`, or the compiler
evaluates it while compiling. Tests that fork use a file database under
`/tmp` with a random name, because the job opens its own connection and an
in-memory database would be a different, empty one.

    let { sysSleepMs, sysExec, sysRandomHex, sysUtcNow, sysGraphemeLength } = import("sys/src");
    let { LlmClient, llmFake, llmFakeScript, LlmFakeResponse, llmRequests, llmLastRequest } = import("llm/src");

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

    let orNone(s: String?): String { if (s == null) { "<null>" } else { s } }

    let orMinus(n: Int?): Int { if (n == null) { -1 } else { n } }

    let joinWith(xs: List<String>, sep: String): String {
      xs.join(sep) { (x: String): String => x }
    }

    let startInMemory(db: Db): Boolean {
      do { runsStart(":memory:", db, "k:1", jobWrite); false } orelse true
    }

    let finishAs(db: Db, status: String): Boolean {
      do { runsFinish(db, "k:1", status, null); false } orelse true
    }

    let didBubble(bubbled: Boolean): Boolean { bubbled }

    let one(db: Db, query: String): String throws Bubble {
      let row = db.one(query, []);
      if (row != null) { orNone(row.cells[0]) } else { "none" }
    }

    let statusOf(db: Db, key: String): String throws Bubble {
      let run = runsGet(db, key);
      if (run == null) { "none" } else { run.status }
    }

    let memDb(): Db throws Bubble { dbOpen(":memory:") }

    let tempPath(): String { "/tmp/runs-test-${sysRandomHex(6)}.sqlite3" }

    let fileDb(path: String): Db throws Bubble {
      let db = dbOpen(path);
      db.script("CREATE TABLE scratch (v TEXT)");
      db
    }

Left empty on purpose. Removing the files would `sysExec` `rm`, and on macOS
a process that has run an `exec` cannot fork a child that closes a SQLite
connection (the child segfaults inside libsystem_trace; reproduced with a
ten-line Blimp script). The last test removes every scratch file in one go.

    let cleanup(path: String): Void {
      if (path == "") { console.log("no path"); }
    }

Poll until the run leaves `running`: at most 50 tries of 100 ms, the 5 second
cap. Answers the final status (`running` if the cap was hit).

    let waitDone(db: Db, key: String): String throws Bubble {
      var tries = 0;
      while (tries < 50) {
        let s = statusOf(db, key);
        if (s != "running") { return s; }
        sysSleepMs(100);
        tries += 1;
      }
      statusOf(db, key)
    }

    let addUser(db: Db, email: String): Int throws Bubble {
      db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email])
    }

    let addWork(db: Db, userId: Int, slug: String, status: String): Int throws Bubble {
      db.insert(
        "INSERT INTO works (user_id, title, body, slug, status) VALUES ($1, 'T', 'body', $2, $3)",
        [userId.toString(), slug, status],
      )
    }

    let addRun(db: Db, key: String, status: String, pid: Int?): Void throws Bubble {
      let p = if (pid == null) { null } else { pid.toString() };
      db.exec(
        "INSERT INTO runs (key, status, pid, started_at) VALUES ($1, $2, $3, $4)",
        [key, status, p, sysUtcNow()],
      );
    }

## The jobs

Each is a named function so it can be passed as `fn (Db): Void throws Bubble`.

    let note(own: Db, v: String): Void throws Bubble {
      own.exec("INSERT INTO scratch (v) VALUES ($1)", [v]);
    }

    let jobWrite(own: Db): Void throws Bubble {
      note(own, "from job");
      sysSleepMs(100);
    }

    let jobSlow(own: Db): Void throws Bubble {
      sysSleepMs(700);
      note(own, "slow");
    }

    let jobBubble(own: Db): Void throws Bubble {
      note(own, "before");
      bubble()
    }

    let jobProgress(own: Db): Void throws Bubble {
      runsProgress(own, "progress:1", runsCounts(1, 2), "half");
      sysSleepMs(50);
    }

    let jobOpenTx(own: Db): Void throws Bubble {
      own.begin();
      note(own, "uncommitted");
      bubble()
    }

    let jobFinishSelf(own: Db): Void throws Bubble {
      runsFinish(own, "self:1", "done", "result 7");
    }

    let jobPpid(own: Db): Void throws Bubble {
      sysSleepMs(300);
      let r = sysExec(["/bin/sh", "-c", "ps -o ppid= -p \$PPID"], "", null);
      note(own, "ppid ${trimText(r[1])}");
      let mine = runsOwnPid();
      note(own, "pid ${orMinus(mine).toString()}");
    }

    let trimText(s: String): String {
      var out = s;
      var cut = true;
      while (cut) {
        cut = false;
        if (out.hasIndex(String.begin)) {
          let c = out[String.begin];
          if (c == 32 || c == 10) { out = out.slice(out.next(String.begin), out.end); cut = true; }
        }
        if (out.hasIndex(String.begin) && !cut) {
          let c = out[out.prev(out.end)];
          if (c == 32 || c == 10) { out = out.slice(String.begin, out.prev(out.end)); cut = true; }
        }
      }
      out
    }

## Versions

    test("a topic never bumped is 0") { test =>
      let db = memDb();
      expectInt(test, versionsOf(db, "work:1"), 0);
    }

    test("bump creates the row at 1 and counts from there") { test =>
      let db = memDb();
      versionsBump(db, "work:1");
      expectInt(test, versionsOf(db, "work:1"), 1);
      versionsBump(db, "work:1");
      versionsBump(db, "work:1");
      expectInt(test, versionsOf(db, "work:1"), 3);
      expectText(test, one(db, "SELECT count(*) FROM versions"), "1");
    }

    test("topics are independent and the sum adds the ones asked for") { test =>
      let db = memDb();
      versionsBump(db, "work:1");
      versionsBump(db, "work:1");
      versionsBump(db, "link:7");
      versionsBump(db, "run:work:1");
      expectInt(test, versionsSum(db, ["work:1", "link:7"]), 3);
      expectInt(test, versionsSum(db, ["work:1"]), 2);
      expectInt(test, versionsSum(db, ["work:1", "link:7", "run:work:1"]), 4);
      expectInt(test, versionsSum(db, ["nothing", "work:1"]), 2);
    }

    test("the sum of no topics, or of none ever bumped, is 0") { test =>
      let db = memDb();
      expectInt(test, versionsSum(db, []), 0);
      expectInt(test, versionsSum(db, ["a", "b"]), 0);
    }

    test("a bump anywhere in the set changes the sum") { test =>
      let db = memDb();
      let topics = ["work:1", "link:2"];
      let before = versionsSum(db, topics);
      versionsBump(db, "link:2");
      expectTrue(test, versionsSum(db, topics) != before, "sum moved");
      versionsBump(db, "work:99");
      expectInt(test, versionsSum(db, topics), before + 1);
    }

    test("the topic helpers spell the Elixir topics") { test =>
      expectText(test, versionsWorkTopic(5), "work:5");
      expectText(test, versionsLinkTopic(9), "link:9");
      expectText(test, versionsRunTopic("compare:work:5"), "run:compare:work:5");
    }

## Runs that fork

    test("a real run: the job writes through its own connection, finishes done, bumps") { test =>
      let path = tempPath();
      let db = fileDb(path);
      let started = runsStart(path, db, "compare:work:1", jobWrite);
      expectTrue(test, started, "started");
      let afterStart = versionsOf(db, "run:compare:work:1");
      expectTrue(test, afterStart >= 1, "started bumped");
      expectText(test, waitDone(db, "compare:work:1"), "done");
      expectText(test, one(db, "SELECT v FROM scratch"), "from job");
      expectInt(test, versionsOf(db, "run:compare:work:1"), 2);
      let run = runsGet(db, "compare:work:1");
      expectTrue(test, run != null, "row");
      if (run != null) {
        expectTrue(test, run.finishedAt != null, "finished_at");
        expectTrue(test, run.startedAt != null, "started_at");
        expectTrue(test, run.pid != null, "the job recorded its pid");
        expectTrue(test, run.progress == null, "no progress reported");
      }
      cleanup(path);
    }

    test("the request sees running first: the job is not waited for") { test =>
      let path = tempPath();
      let db = fileDb(path);
      let started = runsStart(path, db, "slow:1", jobSlow);
      expectTrue(test, started, "started");
      expectText(test, statusOf(db, "slow:1"), "running");
      expectText(test, one(db, "SELECT count(*) FROM scratch"), "0");
      expectText(test, waitDone(db, "slow:1"), "done");
      expectText(test, one(db, "SELECT v FROM scratch"), "slow");
      cleanup(path);
    }

    test("a second start on a key that is running is refused, whatever the kind") { test =>
      let path = tempPath();
      let db = fileDb(path);
      expectTrue(test, runsStart(path, db, "slow:2", jobSlow), "first");
      expectFalse(test, runsStart(path, db, "slow:2", jobWrite), "second refused");
      expectTrue(test, runsRunning(db, "slow:2"), "still running");
      expectText(test, waitDone(db, "slow:2"), "done");
      expectText(test, one(db, "SELECT count(*) FROM scratch"), "1");
      expectText(test, one(db, "SELECT v FROM scratch"), "slow");
      cleanup(path);
    }

    test("other keys are independent") { test =>
      let path = tempPath();
      let db = fileDb(path);
      expectTrue(test, runsStart(path, db, "slow:3", jobSlow), "first key");
      expectTrue(test, runsStart(path, db, "other:3", jobWrite), "second key");
      expectText(test, waitDone(db, "other:3"), "done");
      expectText(test, waitDone(db, "slow:3"), "done");
      expectText(test, one(db, "SELECT count(*) FROM scratch"), "2");
      cleanup(path);
    }

    test("a job that bubbles is crashed, with the text Bubble, and the key is free") { test =>
      let path = tempPath();
      let db = fileDb(path);
      expectTrue(test, runsStart(path, db, "bad:1", jobBubble), "started");
      expectText(test, waitDone(db, "bad:1"), "crashed");
      let run = runsGet(db, "bad:1");
      expectTrue(test, run != null, "row");
      if (run != null) {
        expectTrue(test, hasText(orNone(run.detail), "Bubble"), orNone(run.detail));
        expectTrue(test, run.finishedAt != null, "finished_at");
      }
      expectInt(test, versionsOf(db, "run:bad:1"), 2);
      expectText(test, one(db, "SELECT v FROM scratch"), "before");
      expectTrue(test, runsStart(path, db, "bad:1", jobWrite), "key is free again");
      expectText(test, waitDone(db, "bad:1"), "done");
      cleanup(path);
    }

    test("a restart clears the old row: no progress, no detail, a fresh pid") { test =>
      let path = tempPath();
      let db = fileDb(path);
      expectTrue(test, runsStart(path, db, "progress:1", jobProgress), "first");
      expectText(test, waitDone(db, "progress:1"), "done");
      expectText(test, one(db, "SELECT progress FROM runs WHERE key = 'progress:1'"), "1/2");
      expectText(test, one(db, "SELECT detail FROM runs WHERE key = 'progress:1'"), "half");
      expectTrue(test, runsStart(path, db, "progress:1", jobWrite), "second");
      expectText(test, waitDone(db, "progress:1"), "done");
      expectText(test, one(db, "SELECT COALESCE(progress, 'NULL') FROM runs WHERE key = 'progress:1'"), "NULL");
      expectText(test, one(db, "SELECT COALESCE(detail, 'NULL') FROM runs WHERE key = 'progress:1'"), "NULL");
      cleanup(path);
    }

    test("progress from inside the job reaches the row and the topic") { test =>
      let path = tempPath();
      let db = fileDb(path);
      expectTrue(test, runsStart(path, db, "progress:1", jobProgress), "started");
      expectText(test, waitDone(db, "progress:1"), "done");
      expectText(test, one(db, "SELECT progress FROM runs WHERE key = 'progress:1'"), "1/2");
      expectInt(test, versionsOf(db, "run:progress:1"), 3);
      cleanup(path);
    }

    test("a transaction the job left open is rolled back") { test =>
      let path = tempPath();
      let db = fileDb(path);
      expectTrue(test, runsStart(path, db, "tx:1", jobOpenTx), "started");
      expectText(test, waitDone(db, "tx:1"), "crashed");
      expectText(test, one(db, "SELECT count(*) FROM scratch"), "0");
      cleanup(path);
    }

    test("a job may finish itself with a result, and the wrapper changes nothing") { test =>
      let path = tempPath();
      let db = fileDb(path);
      expectTrue(test, runsStart(path, db, "self:1", jobFinishSelf), "started");
      expectText(test, waitDone(db, "self:1"), "done");
      expectText(test, one(db, "SELECT detail FROM runs WHERE key = 'self:1'"), "result 7");
      expectInt(test, versionsOf(db, "run:self:1"), 2);
      cleanup(path);
    }

## Runs without forking

    test("runsGet is null for a key nobody started") { test =>
      let db = memDb();
      expectTrue(test, runsGet(db, "work:1") == null, "no run");
      expectFalse(test, runsRunning(db, "work:1"), "not running");
    }

    test("a running key is refused and its row is left as it was") { test =>
      let path = tempPath();
      let db = fileDb(path);
      addRun(db, "compare:work:1", "running", null);
      db.exec("UPDATE runs SET progress = '2/9' WHERE key = 'compare:work:1'", []);
      let started = runsStart(path, db, "compare:work:1", jobWrite);
      expectFalse(test, started, "refused");
      let run = runsGet(db, "compare:work:1");
      expectTrue(test, run != null, "row kept");
      if (run != null) {
        expectText(test, orNone(run.progress), "2/9");
        expectTrue(test, run.isRunning(), "still running");
      }
      expectInt(test, versionsOf(db, "run:compare:work:1"), 0);
      expectText(test, one(db, "SELECT count(*) FROM scratch"), "0");
      cleanup(path);
    }

    test("a database that is not a file cannot host a job") { test =>
      let db = memDb();
      expectTrue(test, didBubble(startInMemory(db)), "memory refused");
      expectFalse(test, runsRunning(db, "k:1"), "no row left behind");
    }

    test("kind is the key up to the first colon") { test =>
      let r = new Run("compare:work:5", "running", null, null, null, null, null);
      expectText(test, r.kind(), "compare");
      let s = new Run("solo", "running", null, null, null, null, null);
      expectText(test, s.kind(), "solo");
    }

    test("runsActive lists running runs under a prefix, oldest first") { test =>
      let db = memDb();
      addRun(db, "stack:2", "running", null);
      addRun(db, "stack:1", "running", null);
      addRun(db, "stack:3", "done", null);
      addRun(db, "compare:work:1", "running", null);
      db.exec("UPDATE runs SET started_at = '2024-01-01 00:00:00' WHERE key = 'stack:2'", []);
      let got = runsActive(db, "stack:");
      expectInt(test, got.length, 2);
      expectText(test, got[0].key, "stack:2");
      expectText(test, got[1].key, "stack:1");
      expectInt(test, runsActive(db, "").length, 3);
      expectInt(test, runsActive(db, "nothing").length, 0);
    }

    test("a prefix is not a LIKE pattern") { test =>
      let db = memDb();
      addRun(db, "stack:2", "running", null);
      expectInt(test, runsActive(db, "st_ck").length, 0);
      expectInt(test, runsActive(db, "%").length, 0);
    }

    test("progress updates a running row and bumps the topic") { test =>
      let db = memDb();
      addRun(db, "stack:1", "running", null);
      runsProgress(db, "stack:1", runsCounts(3, 12), "reading");
      let run = runsGet(db, "stack:1");
      expectTrue(test, run != null, "row");
      if (run != null) {
        expectText(test, orNone(run.progress), "3/12");
        expectText(test, orNone(run.detail), "reading");
      }
      expectInt(test, versionsOf(db, "run:stack:1"), 1);
      runsProgress(db, "stack:1", "relating", null);
      expectInt(test, versionsOf(db, "run:stack:1"), 2);
      expectText(test, one(db, "SELECT progress FROM runs WHERE key = 'stack:1'"), "relating");
      expectText(test, one(db, "SELECT COALESCE(detail, 'NULL') FROM runs WHERE key = 'stack:1'"), "NULL");
    }

    test("progress for a key with no running row is dropped without a bump") { test =>
      let db = memDb();
      runsProgress(db, "nothing:1", "1/2", null);
      expectTrue(test, runsGet(db, "nothing:1") == null, "no row made");
      addRun(db, "old:1", "done", null);
      runsProgress(db, "old:1", "9/9", null);
      expectText(test, one(db, "SELECT COALESCE(progress, 'NULL') FROM runs WHERE key = 'old:1'"), "NULL");
      expectInt(test, versionsSum(db, ["run:nothing:1", "run:old:1"]), 0);
    }

    test("finish marks a running row, stamps it and bumps once") { test =>
      let db = memDb();
      addRun(db, "k:1", "running", null);
      expectTrue(test, runsFinish(db, "k:1", "done", "all good"), "changed");
      let run = runsGet(db, "k:1");
      expectTrue(test, run != null, "row");
      if (run != null) {
        expectText(test, run.status, "done");
        expectText(test, orNone(run.detail), "all good");
        expectTrue(test, run.finishedAt != null, "finished_at");
      }
      expectInt(test, versionsOf(db, "run:k:1"), 1);
    }

    test("a null detail keeps the last progress detail") { test =>
      let db = memDb();
      addRun(db, "k:1", "running", null);
      runsProgress(db, "k:1", "2/2", "last words");
      runsFinish(db, "k:1", "done", null);
      expectText(test, one(db, "SELECT detail FROM runs WHERE key = 'k:1'"), "last words");
    }

    test("only a running row is finished") { test =>
      let db = memDb();
      addRun(db, "k:1", "crashed", null);
      expectFalse(test, runsFinish(db, "k:1", "done", null), "already crashed stays so");
      expectText(test, statusOf(db, "k:1"), "crashed");
      expectFalse(test, runsFinish(db, "missing:1", "done", null), "no row");
      expectInt(test, versionsOf(db, "run:k:1"), 0);
    }

    test("finishing with any other status is a bubble") { test =>
      let db = memDb();
      addRun(db, "k:1", "running", null);
      expectTrue(test, didBubble(finishAs(db, "running")), "running refused");
      expectTrue(test, didBubble(finishAs(db, "failed")), "failed refused");
      expectText(test, statusOf(db, "k:1"), "running");
    }

    test("forget drops the row and bumps") { test =>
      let db = memDb();
      addRun(db, "k:1", "running", null);
      runsForget(db, "k:1");
      expectTrue(test, runsGet(db, "k:1") == null, "gone");
      expectInt(test, versionsOf(db, "run:k:1"), 1);
    }

    test("runsPidAlive knows a dead pid from this process") { test =>
      expectFalse(test, runsPidAlive(999999), "pid 999999 is gone");
      let mine = runsOwnPid();
      expectTrue(test, mine != null, "own pid");
      if (mine != null) {
        expectTrue(test, mine > 1, "a real pid");
        expectTrue(test, runsPidAlive(mine), "we are alive");
      }
    }

## Reparenting

The double fork: the job's parent is not the request process (the middle
process exited and the job was reparented), and the job's own pid, as it
reports it, is the pid recorded in the row and is not ours. The request's own
pid is asked for only after the run, because asking uses `exec`.

    test("the job is reparented away from the request and records its own pid") { test =>
      let path = tempPath();
      let db = fileDb(path);
      expectTrue(test, runsStart(path, db, "ppid:1", jobPpid), "started");
      expectText(test, waitDone(db, "ppid:1"), "done");
      let mine = runsOwnPid();
      let ppid = one(db, "SELECT v FROM scratch WHERE v LIKE 'ppid %'");
      let pid = one(db, "SELECT v FROM scratch WHERE v LIKE 'pid %'");
      expectTrue(test, mine != null, "own pid");
      if (mine != null) {
        expectFalse(test, ppid == "ppid ${mine.toString()}", "the job's parent is not the request: ${ppid} vs ${mine.toString()}");
        expectFalse(test, pid == "pid ${mine.toString()}", "the job is not the request");
      }
      let recorded = one(db, "SELECT pid FROM runs WHERE key = 'ppid:1'");
      expectText(test, "pid ${recorded}", pid);
      expectFalse(test, waitExited(recorded.toInt32() orelse 999999), "the job has exited");
    }

## After the forks

These use `exec` (pid checks) and so must come after every test that forks.

    test("a running row whose pid is gone is reclaimed: crashed, and the key is free") { test =>
      let db = memDb();
      addRun(db, "stale:1", "running", 999999);
      expectTrue(test, runsReclaim(db, "stale:1"), "reclaimed");
      expectText(test, statusOf(db, "stale:1"), "crashed");
      expectText(test, one(db, "SELECT detail FROM runs WHERE key = 'stale:1'"), "process gone");
      expectFalse(test, runsReclaim(db, "stale:1"), "nothing left to reclaim");
      expectFalse(test, runsReclaim(db, "nothing:1"), "no row");
    }

    test("a running row whose pid is alive is not reclaimed") { test =>
      let path = tempPath();
      let db = fileDb(path);
      let mine = runsOwnPid();
      expectTrue(test, mine != null, "own pid");
      if (mine != null) {
        addRun(db, "live:1", "running", mine);
        expectFalse(test, runsStart(path, db, "live:1", jobWrite), "refused");
        expectText(test, statusOf(db, "live:1"), "running");
      }
      cleanup(path);
    }

## Recovery

    test("a reading work becomes failed with the Elixir's text") { test =>
      let db = memDb();
      let u = addUser(db, "a@example.com");
      let w = addWork(db, u, "w-1", "reading");
      expectInt(test, recoveryRun(db), 1);
      expectText(test, one(db, "SELECT status FROM works WHERE id = ${w.toString()}"), "failed");
      expectText(test, one(db, "SELECT status_detail FROM works WHERE id = ${w.toString()}"), "interrupted by a restart");
      expectInt(test, versionsOf(db, "work:${w.toString()}"), 1);
    }

    test("a linking link becomes failed with an error naming the restart") { test =>
      let db = memDb();
      let u = addUser(db, "a@example.com");
      let a = addWork(db, u, "w-1", "read");
      let b = addWork(db, u, "w-2", "read");
      let l = db.insert("INSERT INTO links (a_work_id, b_work_id, status) VALUES ($1, $2, 'linking')", [a.toString(), b.toString()]);
      expectInt(test, recoveryLinks(db), 1);
      expectText(test, one(db, "SELECT status FROM links WHERE id = ${l.toString()}"), "failed");
      expectTrue(test, hasText(one(db, "SELECT error FROM links WHERE id = ${l.toString()}"), "restart"), "error names the restart");
      expectInt(test, versionsOf(db, "link:${l.toString()}"), 1);
    }

    test("linked and read rows are untouched and nothing in flight is 0") { test =>
      let db = memDb();
      let u = addUser(db, "a@example.com");
      let a = addWork(db, u, "w-1", "read");
      let b = addWork(db, u, "w-2", "pending");
      addWork(db, u, "w-3", "failed");
      db.insert("INSERT INTO links (a_work_id, b_work_id, status) VALUES ($1, $2, 'linked')", [a.toString(), b.toString()]);
      expectInt(test, recoveryRun(db), 0);
      expectText(test, one(db, "SELECT group_concat(status) FROM (SELECT status FROM works ORDER BY id)"), "read,pending,failed");
      expectText(test, one(db, "SELECT status FROM links"), "linked");
      expectInt(test, versionsSum(db, ["work:1", "work:2", "work:3", "link:1"]), 0);
    }

    test("a running run with a dead pid is crashed") { test =>
      let db = memDb();
      addRun(db, "stack:1", "running", 999999);
      expectInt(test, recoveryRun(db), 1);
      expectText(test, statusOf(db, "stack:1"), "crashed");
      expectText(test, one(db, "SELECT detail FROM runs WHERE key = 'stack:1'"), "interrupted by a restart");
      expectTrue(test, runsGet(db, "stack:1") != null, "row kept");
      expectInt(test, versionsOf(db, "run:stack:1"), 1);
    }

    test("a running run with no pid recorded is crashed too") { test =>
      let db = memDb();
      addRun(db, "stack:2", "running", null);
      expectInt(test, recoveryRuns(db), 1);
      expectText(test, statusOf(db, "stack:2"), "crashed");
    }

    test("a running run whose process is alive is left alone, and finished runs are not touched") { test =>
      let db = memDb();
      let mine = runsOwnPid();
      expectTrue(test, mine != null, "own pid");
      if (mine != null) { addRun(db, "stack:3", "running", mine); }
      addRun(db, "stack:4", "done", 999999);
      addRun(db, "stack:5", "crashed", 999999);
      expectInt(test, recoveryRun(db), 0);
      expectText(test, statusOf(db, "stack:3"), "running");
      expectText(test, statusOf(db, "stack:4"), "done");
      expectText(test, statusOf(db, "stack:5"), "crashed");
    }

    test("recoveryRun adds up works, links and runs") { test =>
      let db = memDb();
      let u = addUser(db, "a@example.com");
      let a = addWork(db, u, "w-1", "reading");
      let b = addWork(db, u, "w-2", "reading");
      let c = addWork(db, u, "w-3", "read");
      db.insert("INSERT INTO links (a_work_id, b_work_id, status) VALUES ($1, $2, 'linking')", [a.toString(), c.toString()]);
      addRun(db, "r:1", "running", 999999);
      addRun(db, "r:2", "running", 999998);
      expectInt(test, recoveryRun(db), 5);
      expectInt(test, recoveryRun(db), 0);
      expectTrue(test, b > 0, "fixtures");
    }

## Cache

    test("a put is read back") { test =>
      let db = memDb();
      expectTrue(test, cacheGet(db, "public_links") == null, "empty at first");
      cachePut(db, "public_links", "[1,2,3]", 300);
      expectText(test, orNone(cacheGet(db, "public_links")), "[1,2,3]");
    }

    test("a ttl of 0 is already expired") { test =>
      let db = memDb();
      cachePut(db, "k", "v", 0);
      expectTrue(test, cacheGet(db, "k") == null, "expired at once");
    }

    test("a later put replaces the value and the expiry") { test =>
      let db = memDb();
      cachePut(db, "k", "old", 0);
      cachePut(db, "k", "new", 60);
      expectText(test, orNone(cacheGet(db, "k")), "new");
      cachePut(db, "k", "gone", 0);
      expectTrue(test, cacheGet(db, "k") == null, "replaced with an expired one");
      expectText(test, one(db, "SELECT count(*) FROM cache"), "1");
    }

    test("an empty string is a value, not a miss") { test =>
      let db = memDb();
      cachePut(db, "k", "", 60);
      expectText(test, orNone(cacheGet(db, "k")), "");
    }

    test("keys are independent and invalidate removes one") { test =>
      let db = memDb();
      cachePut(db, "a", "1", 60);
      cachePut(db, "b", "2", 60);
      cacheInvalidate(db, "a");
      expectTrue(test, cacheGet(db, "a") == null, "a gone");
      expectText(test, orNone(cacheGet(db, "b")), "2");
      cacheInvalidate(db, "never");
    }

    test("invalidate all removes everything") { test =>
      let db = memDb();
      cachePut(db, "a", "1", 60);
      cachePut(db, "b", "2", 60);
      cacheInvalidateAll(db);
      expectTrue(test, cacheGet(db, "a") == null, "a gone");
      expectTrue(test, cacheGet(db, "b") == null, "b gone");
    }

    test("the table is created on first use and the default ttl is five minutes") { test =>
      let db = memDb();
      expectText(test, one(db, "SELECT count(*) FROM sqlite_master WHERE name = 'cache'"), "0");
      expectTrue(test, cacheGet(db, "k") == null, "miss");
      expectText(test, one(db, "SELECT count(*) FROM sqlite_master WHERE name = 'cache'"), "1");
      expectInt(test, cacheDefaultTtl(), 300);
    }

## Mutterings: parsing

    let quoted(): String { "\u{201C}Curly quotes.\u{201D}" }

    let bullet(): String { "\u{2022} A bullet." }

    let parsed(text: String): String {
      joinWith(mutteringsParse(text), "|")
    }

    test("bare lines come through in order") { test =>
      expectText(test, parsed("One.\nTwo.\nThree."), "One.|Two.|Three.");
    }

    test("a null reply is no lines") { test =>
      expectInt(test, mutteringsParse(null).length, 0);
    }

    test("numbers and bullets are stripped, one marker per line") { test =>
      expectText(test, parsed("1. First\n2) Second\n- Third\n* Fourth\n12. Twelfth"), "First|Second|Third|Fourth|Twelfth");
      expectText(test, parsed(bullet()), "A bullet.");
      expectText(test, parsed("- - twice"), "- twice");
    }

    test("digits that are not a marker stay") { test =>
      expectText(test, parsed("3 pigeons"), "3 pigeons");
      expectText(test, parsed("1984 was a year"), "1984 was a year");
    }

    test("quotes are stripped from both ends") { test =>
      expectText(test, parsed("\"Straight.\""), "Straight.");
      expectText(test, parsed(quoted()), "Curly quotes.");
      expectText(test, parsed("'Single.'"), "Single.");
      expectText(test, parsed("1. \"Numbered and quoted.\""), "Numbered and quoted.");
      expectText(test, parsed("it's fine"), "it's fine");
    }

    test("a line that ends in a colon is the model introducing the list") { test =>
      expectText(test, parsed("Here are ten:\nOne.\nTwo."), "One.|Two.");
    }

    test("empty and whitespace lines go, and CRLF is a line break") { test =>
      expectText(test, parsed("One.\r\n\r\n   \r\nTwo.\r\n"), "One.|Two.");
    }

    test("a line over 240 characters is the model explaining, exactly 240 is kept") { test =>
      var s241 = "x";
      var s240 = "x";
      var i = 1;
      while (i < 241) {
        s241 = "${s241}x";
        if (i < 240) { s240 = "${s240}x"; }
        i += 1;
      }
      expectInt(test, sysGraphemeLength(s241), 241);
      expectInt(test, sysGraphemeLength(s240), 240);
      expectText(test, parsed("${s241}\nshort"), "short");
      expectText(test, parsed("${s240}\nshort"), "${s240}|short");
    }

    test("duplicates are dropped, keeping the first") { test =>
      expectText(test, parsed("A\nB\nA\n1. B\nC"), "A|B|C");
    }

## Mutterings: the table

    let okBody(content: String): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"${content}\"},\"finish_reason\":\"stop\"}]}"
    }

Lines `word <from>` to `word <to - 1>`, as the content of a reply (the
newline is the JSON escape).

    let linesBody(prefix: String, from: Int, to: Int): String {
      let out = new ListBuilder<String>();
      var i = from;
      while (i < to) {
        out.add("${prefix} ${i.toString()} at the counter");
        i += 1;
      }
      okBody(joinWith(out.toList(), "\\n"))
    }

    let ids(xs: List<Mutter>): List<Int> {
      let out = new ListBuilder<Int>();
      for (let m of xs) { out.add(m.id); }
      out.toList()
    }

    let idText(xs: List<Int>): String {
      joinWith(xs.map { (i: Int): String => i.toString() }, ",")
    }

    let fill(db: Db, n: Int): Void throws Bubble {
      var i = 0;
      while (i < n) {
        db.exec("INSERT INTO mutterings (text) VALUES ($1)", ["line ${i.toString()}"]);
        i += 1;
      }
    }

    test("the prompt is verbatim, typo and all") { test =>
      expectTrue(test, hasText(mutteringsPrompt(), "working alone at teh sandwich counter. Keep it 240 characters or less."), "teh");
      expectTrue(test, hasText(mutteringsPrompt(), "grilled cheese sandwich factory in Menlo Park, CA."), "factory");
      expectText(test, mutteringsAsk(10), "Give 10 of them. One per line. No numbering, no quotation marks, no introduction and no commentary: nothing but the words themselves.");
    }

    test("store inserts what parses, skips lines the table has, and keeps the source") { test =>
      let db = memDb();
      let first = mutteringsStore(db, "One.\nTwo.\nThree.", 10, "seed");
      expectInt(test, first.added, 3);
      expectTrue(test, first.error == null, "no error");
      let second = mutteringsStore(db, "Two.\nFour.", 10, "cron");
      expectInt(test, second.added, 1);
      expectInt(test, mutteringsCount(db), 4);
      expectText(test, one(db, "SELECT source FROM mutterings WHERE text = 'Two.'"), "seed");
      expectText(test, one(db, "SELECT source FROM mutterings WHERE text = 'Four.'"), "cron");
    }

    test("store takes at most n lines") { test =>
      let db = memDb();
      let r = mutteringsStore(db, "A\nB\nC\nD", 2, "cron");
      expectInt(test, r.added, 2);
      expectText(test, one(db, "SELECT group_concat(text) FROM (SELECT text FROM mutterings ORDER BY id)"), "A,B");
    }

    test("nothing usable is an error, not a row") { test =>
      let db = memDb();
      let r = mutteringsStore(db, "Here are some:\n\n", 5, "cron");
      expectText(test, orNone(r.error), "nothing_usable");
      expectInt(test, mutteringsCount(db), 0);
    }

    test("generate asks with the prompt, the n, and the model settings") { test =>
      let db = memDb();
      let llm = llmFake([okBody("Hello.\\nWorld.")]);
      let r = mutteringsGenerate(db, llm, 2, "cron");
      expectInt(test, r.added, 2);
      let req = lastRequest(test, llm);
      expectTrue(test, hasText(req, "teh sandwich counter"), "system prompt sent: ${req}");
      expectTrue(test, hasText(req, "Give 2 of them. One per line."), "user message sent");
      expectTrue(test, hasText(req, "deepseek-chat"), "cheap model");
      expectTrue(test, hasText(req, "1.2"), "temperature");
      expectTrue(test, hasText(req, "180"), "max tokens 40 * 2 + 100");
    }

    test("a failed call comes back as the error, with nothing added") { test =>
      let db = memDb();
      let llm = llmFakeScript([new LlmFakeResponse(400, "{}")]);
      let r = mutteringsGenerate(db, llm, 5, "cron");
      expectTrue(test, r.error != null, "error");
      expectInt(test, r.added, 0);
      expectInt(test, mutteringsCount(db), 0);
    }

    test("a reply with no text is no_content") { test =>
      let db = memDb();
      let llm = llmFake(["{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null},\"finish_reason\":\"stop\"}]}"]);
      let r = mutteringsGenerate(db, llm, 5, "cron");
      expectTrue(test, r.error != null, "error");
    }

    test("seed asks again for what is missing and stops when the table is full") { test =>
      let db = memDb();
      let llm = llmFake([linesBody("a", 0, 57), linesBody("b", 0, 43), linesBody("c", 0, 10)]);
      expectInt(test, mutteringsSeed(db, llm), 100);
      expectInt(test, mutteringsCount(db), 100);
      expectInt(test, llmRequests(llm).length, 2);
      expectTrue(test, hasText(lastRequest(test, llm), "Give 43 of them"), "the second round asked for the missing 43");
      expectText(test, one(db, "SELECT count(*) FROM mutterings WHERE source = 'seed'"), "100");
    }

    test("seed counts duplicates as not added and asks again, at most four rounds") { test =>
      let db = memDb();
      let same = linesBody("a", 0, 30);
      let llm = llmFake([same, same, same, same, same]);
      expectInt(test, mutteringsSeed(db, llm), 30);
      expectInt(test, llmRequests(llm).length, 4);
    }

    test("a seed that fails on its first round is an error and adds nothing") { test =>
      let db = memDb();
      let llm = llmFakeScript([new LlmFakeResponse(400, "{}")]);
      let r = mutteringsSeedResult(db, llm);
      expectTrue(test, r.error != null, "error");
      expectInt(test, mutteringsSeed(db, llmFakeScript([new LlmFakeResponse(400, "{}")])), 0);
    }

    test("a seed that fails after adding some returns what it added") { test =>
      let db = memDb();
      let llm = llmFakeScript([new LlmFakeResponse(200, linesBody("a", 0, 40)), new LlmFakeResponse(400, "{}")]);
      let r = mutteringsSeedResult(db, llm);
      expectTrue(test, r.error == null, "no error");
      expectInt(test, r.added, 40);
    }

    test("a seed on a full table asks nothing") { test =>
      let db = memDb();
      fill(db, 100);
      let llm = llmFake([linesBody("a", 0, 10)]);
      expectInt(test, mutteringsSeed(db, llm), 0);
      expectInt(test, llmRequests(llm).length, 0);
    }

    test("a tick on a short table seeds, on a full one adds ten with source cron") { test =>
      let db = memDb();
      let llm = llmFake([linesBody("a", 0, 100), linesBody("b", 0, 12)]);
      expectInt(test, mutteringsTick(db, llm), 100);
      expectInt(test, mutteringsCount(db), 100);
      expectInt(test, mutteringsTick(db, llm), 10);
      expectInt(test, mutteringsCount(db), 110);
      expectText(test, one(db, "SELECT count(*) FROM mutterings WHERE source = 'cron'"), "10");
      expectTrue(test, hasText(lastRequest(test, llm), "Give 10 of them"), "a batch of ten");
    }

    test("a tick whose call fails is 0 and does not throw") { test =>
      let db = memDb();
      let llm = llmFakeScript([new LlmFakeResponse(400, "{}")]);
      expectInt(test, mutteringsTick(db, llm), 0);
      expectInt(test, mutteringsCount(db), 0);
    }

    let clockLlm(): LlmClient {
      llmFake([linesBody("a", 0, 100), linesBody("b", 0, 10)])
    }

    test("the clock loop runs the ticks it is told to, on its own connection") { test =>
      let path = tempPath();
      let db = fileDb(path);
      mutteringsClockLoop(path, clockLlm, 0, 0, 1);
      expectInt(test, mutteringsCount(db), 100);
      cleanup(path);
    }

## Mutterings: picking

    test("some on an empty table is nothing") { test =>
      let db = memDb();
      expectInt(test, mutteringsSome(db, 3, []).length, 0);
      expectTrue(test, mutteringsOne(db) == null, "no one");
    }

    test("some answers up to n distinct lines") { test =>
      let db = memDb();
      fill(db, 5);
      let got = mutteringsSome(db, 3, []);
      expectInt(test, got.length, 3);
      let seen = ids(got);
      expectTrue(test, seen[0] != seen[1] && seen[1] != seen[2] && seen[0] != seen[2], "distinct");
      expectInt(test, mutteringsSome(db, 50, []).length, 5);
      expectInt(test, mutteringsSome(db, 0, []).length, 0);
    }

    test("some leaves out what the page has recently shown") { test =>
      let db = memDb();
      fill(db, 5);
      let got = mutteringsSome(db, 10, [1, 2, 3]);
      expectInt(test, got.length, 2);
      expectText(test, idText(ids(got)).split(",").length.toString(), "2");
      for (let m of got) {
        expectTrue(test, m.id == 4 || m.id == 5, "only 4 and 5 are left, got ${m.id.toString()}");
      }
    }

    test("a page that has seen everything forgets, rather than getting nothing") { test =>
      let db = memDb();
      fill(db, 3);
      let got = mutteringsSome(db, 2, [1, 2, 3]);
      expectInt(test, got.length, 2);
    }

    test("the remembered ids are the new ones first, at most forty") { test =>
      let db = memDb();
      fill(db, 3);
      let all = mutteringsSome(db, 3, []);
      let old = new ListBuilder<Int>();
      var i = 100;
      while (i < 150) { old.add(i); i += 1; }
      let next = mutteringsRemembered(all, old.toList());
      expectInt(test, next.length, 40);
      expectInt(test, next[0], all[0].id);
      expectInt(test, next[3], 100);
      expectInt(test, mutteringsRemembered([], [7, 8]).length, 2);
    }

    test("one picks a line and a record carries its columns") { test =>
      let db = memDb();
      fill(db, 1);
      let m = mutteringsOne(db);
      expectTrue(test, m != null, "a line");
      if (m != null) {
        expectText(test, m.text, "line 0");
        expectText(test, m.source, "cron");
        expectInt(test, sysGraphemeLength(m.insertedAt), 19);
      }
    }

## Cleanup

    test("remove the scratch databases") { test =>
      let r = sysExec(["/bin/sh", "-c", "rm -f /tmp/runs-test-*.sqlite3 /tmp/runs-test-*.sqlite3-wal /tmp/runs-test-*.sqlite3-shm"], "", null);
      expectText(test, r[0], "0");
    }

## Helper

The last request body the fake saw, or `<null>`.

    let lastRequest(test: Test, llm: LlmClient): String {
      let all = llmRequests(llm);
      if (all.length == 0) { "<null>" } else { all[all.length - 1] }
    }

Wait up to two seconds for a process to exit (the row says done a moment before the job exits). Answers whether it is still alive.

    let waitExited(pid: Int): Boolean {
      var tries = 0;
      while (tries < 20 && runsPidAlive(pid)) {
        sysSleepMs(100);
        tries += 1;
      }
      runsPidAlive(pid)
    }
