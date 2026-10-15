# Runs: work that outlives the request that started it

`Marginalia.Runs` kept one ETS entry per key and ran the work in a task under
a supervisor. The port keeps one row per key in `runs` and runs the work in a
process nothing else owns.

## How the process is made

The server forks a child per request and the child exits when it has
answered. A job that must outlive the request cannot be the request child,
and it cannot be a plain child of it either: when the request child exits the
job would be an orphan with a parent that is about to be gone, and the server
loop reaping children would never see it. So `runsStart` forks twice:

server -> request child -> middle -> job, where the middle process exits at
once and the job is now a child of init.

The request child waits for the middle process (it exits at once, so the wait
is microseconds), then carries on and answers. The job is reparented to init,
which reaps it; nothing in Marginalia has to.

## The database handle is not shared

A SQLite connection must not be used on both sides of a `fork`. The job
therefore never uses the `Db` it inherited: it opens its own from the path
the caller passes. This is why `runsStart` takes `dbPath`, and why an
in-memory database (`:memory:`) is refused: the job would open a different,
empty one.

It must also close the inherited handle first, and this was observed, not
guessed: with the inherited connection still open, `sqlite_open` of the same
file in the child fails with "locking protocol" (SQLite's per-process inode
table is copied by `fork` and still believes the parent's locks are the
child's), and on macOS the system SQLite has been seen to segfault in the
same call. Closing the copy in the child is safe: POSIX locks are not
inherited, and the parent's connection holds the shared lock a WAL database
keeps while it is open, so the child's close cannot checkpoint or delete the
write-ahead log (the file stays after the child exits, as observed). Only
the child's copy of the handle goes; the parent's `Db` is untouched.

    let { Db, DbRow, dbOpen } = import("db/src");
    let { sysFork, sysExit, sysWaitPid, sysExec, sysUtcNow, sysDbOpen, sysStringTrim } = import("sys/src");

## The row

`runs(key, status, progress, detail, pid, started_at, finished_at)`.

- `key`: a string naming what is running, `<kind>:<id>` by convention, for
  example `compare:work:5` or `stack:12`. The Elixir run carried a `kind`
  atom beside the key; here it is the key's text before the first colon
  (`Run.kind()`), so a page that finds a run already going can say what it
  is.
- `status`: `running`, then `done` or `crashed`. These are the Elixir
  messages `started`, `done`, `crashed`; `progress` is not a status, it is
  the column below changing while the status stays `running`.
- `progress`: what a page shows. By convention `"3/12"` (`runsCounts`) or a
  stage name; the Elixir fields `done`, `total` and `stage` all collapse into
  this one string. Null before the first report.
- `detail`: free text. The crash text when `crashed`; whatever the job wants a
  page to show otherwise (the Elixir `done` result, which was meant to be
  small).
- `pid`: the job's process id, written by the job itself as its first act. It
  is what boot recovery and `runsStart` use to tell a job that is running
  from a row whose process is gone. Null until the job has started.

The record, field for field:

    export class Run(
      public key: String,
      public status: String,
      public progress: String?,
      public detail: String?,
      public pid: Int?,
      public startedAt: String?,
      public finishedAt: String?,
    ) {
      public static fromRow(row: DbRow): Run throws Bubble {
        new Run(
          row.str("key"),
          row.str("status"),
          row.strOrNull("progress"),
          row.strOrNull("detail"),
          row.intOrNull("pid"),
          row.strOrNull("started_at"),
          row.strOrNull("finished_at"),
        )
      }

      public isRunning(): Boolean { this.status == "running" }

      /** The text of the key before its first colon, or the whole key. */
      public kind(): String {
        let parts = this.key.split(":");
        parts[0]
      }
    }

    export let runsColumns(): String {
      "key, status, progress, detail, pid, started_at, finished_at"
    }

## Reading

`Runs.get/1`, as a row. A finished run is still there (the Elixir entry was
deleted on completion); ask `Run.isRunning()` or use `runsRunning`.

    export let runsGet(db: Db, key: String): Run? throws Bubble {
      let row = db.one("SELECT ${runsColumns()} FROM runs WHERE key = $1", [key]);
      if (row == null) { null } else { Run.fromRow(row) }
    }

    export let runsRunning(db: Db, key: String): Boolean throws Bubble {
      let run = runsGet(db, key);
      if (run == null) { false } else { run.isRunning() }
    }

The running runs whose key starts with `prefix`, oldest first: the folder
page asks for `stack:` to show which stack passes are going. The comparison
is `substr`, not `LIKE`, so a `_` or `%` in a prefix means itself.

    export let runsActive(db: Db, prefix: String): List<Run> throws Bubble {
      let out = new ListBuilder<Run>();
      let rows = db.query(
        "SELECT ${runsColumns()} FROM runs WHERE status = 'running' AND substr(key, 1, length($1)) = $1 ORDER BY started_at, key",
        [prefix],
      );
      for (let row of rows) { out.add(Run.fromRow(row)); }
      out.toList()
    }

`Runs.forget/1`: drop the row. A job still running is left alone and, when
it finishes, finds no row to update.

    export let runsForget(db: Db, key: String): Void throws Bubble {
      db.exec("DELETE FROM runs WHERE key = $1", [key]);
      versionsBump(db, versionsRunTopic(key));
    }

## Progress and finish

`"3/12"`.

    export let runsCounts(done: Int, total: Int): String {
      "${done.toString()}/${total.toString()}"
    }

`Runs.progress/2`. Callable from inside the job with the job's own `Db`.
Dropped silently, with no bump, when the key has no running row, as the
Elixir cast was.

    export let runsProgress(db: Db, key: String, progress: String, detail: String?): Void throws Bubble {
      let changed = db.exec(
        "UPDATE runs SET progress = $1, detail = $2 WHERE key = $3 AND status = 'running'",
        [progress, detail, key],
      );
      if (changed > 0) { versionsBump(db, versionsRunTopic(key)); }
    }

Mark a running run `done` or `crashed`, stamp `finished_at`, bump the topic.
Only a running row is finished: a row that recovery already marked crashed, or
that `runsForget` removed, is left as it is. A null `detail` keeps whatever
the last progress report left there; the crash text goes here. Answers
whether a row changed. Any other status bubbles: it is a programmer error.

    export let runsFinish(db: Db, key: String, status: String, detail: String?): Boolean throws Bubble {
      if (status != "done" && status != "crashed") {
        console.log("runs: cannot finish a run as ${status}");
        bubble()
      }
      let changed = db.exec(
        "UPDATE runs SET status = $1, detail = COALESCE($2, detail), finished_at = $3 WHERE key = $4 AND status = 'running'",
        [status, detail, sysUtcNow(), key],
      );
      if (changed > 0) { versionsBump(db, versionsRunTopic(key)); }
      changed > 0
    }

## Is a process alive

`kill -0` through the shell's builtin (so there is no `kill` binary to
find): status `0` means the process exists and we may signal it. A pid that
belongs to somebody else answers 1, which is also "not ours", so it counts as
gone. Pids are reused; a long-dead job whose pid now belongs to another
process of ours looks alive. That costs a stuck `running` row, never a wrong
result, and the next boot's recovery has the same limit.

    export let runsPidAlive(pid: Int): Boolean {
      do {
        let r = sysExec(["/bin/sh", "-c", "kill -0 \"\$1\" 2>/dev/null", "sh", pid.toString()], "", null);
        r[0] == "0"
      } orelse false
    }

The pid of the calling process. Blimp has no `getpid`; `sh -c 'echo $PPID'`
prints the pid of the shell's parent, which is this process. Null if that
fails.

    export let runsOwnPid(): Int? {
      var out = -1;
      let ok = do {
        let r = sysExec(["/bin/sh", "-c", "echo \$PPID"], "", null);
        out = sysStringTrim(r[1]).toInt32();
        true
      } orelse false;
      if (ok && out > 0) { out } else { null }
    }

## Starting

A `running` row whose recorded pid is gone is a job that was killed (a
reboot, the out-of-memory killer). Nothing will ever finish it, so
`runsStart` first marks it crashed, which frees the key. A running row with a
null pid is a job that has just been started and has not yet written its pid;
it counts as alive.

    export let runsReclaim(db: Db, key: String): Boolean throws Bubble {
      let run = runsGet(db, key);
      if (run != null) {
        let pid = run.pid;
        if (run.isRunning() && pid != null && !runsPidAlive(pid)) {
          return runsFinish(db, key, "crashed", "process gone");
        }
      }
      false
    }

The body of the job, in the grandchild, with the grandchild's own `Db`. It
ends the process: `sysExit(0)` is the last thing it does on every path.

A connection of the job's own, or null.

    export let runsOpenOwn(dbPath: String): Db? {
      var handle = -1;
      let ok = do { handle = sysDbOpen(dbPath); true } orelse false;
      if (ok) { new Db(handle) } else { null }
    }

The three things the job does not let fail the exit: a statement, a rollback and
the final status, each a no-op on a bubble.

    let runsTry(db: Db, sql: String, params: List<String?>): Boolean {
      do { db.exec(sql, params); true } orelse false
    }

    let runsTryRollback(db: Db): Boolean {
      do { db.rollback(); true } orelse false
    }

    let runsTryFinish(db: Db, key: String, status: String, detail: String?): Boolean {
      do { runsFinish(db, key, status, detail) } orelse false
    }

    let runsJobWith(own: Db, key: String, body: fn (Db): Void throws Bubble): Void {
      let pid = runsOwnPid();
      if (pid != null) {
        runsTry(own, "UPDATE runs SET pid = $1 WHERE key = $2 AND status = 'running'", [pid.toString(), key]);
      }
      let ok = do { body(own); true } orelse false;
      var guard = 0;
      while (own.inTransaction() && guard < 8) {
        runsTryRollback(own);
        guard += 1;
      }
      let why = if (own.lastError == "") { "Bubble" } else { "Bubble: ${own.lastError}" };
      runsTryFinish(own, key, if (ok) { "done" } else { "crashed" }, if (ok) { null } else { why });
      sysExit(0);
    }

    let runsJob(dbPath: String, inherited: Db, key: String, body: fn (Db): Void throws Bubble): Void {
      inherited.close();
      let own = runsOpenOwn(dbPath);
      if (own != null) {
        runsJobWith(own, key, body);
      } else {
        console.log("runs: the job for ${key} could not open ${dbPath}");
        sysExit(1);
      }
    }

`Runs.start/3`. Answers `false`, starting nothing, when `key` already has a
running run (any kind, as in Elixir). Otherwise:

1. upserts the row as `running` (one statement that does nothing to a row
   that is already running, so two requests racing for a key cannot both
   win), clears `progress`, `detail`, `pid` and `finished_at`, and bumps
   `run:<key>`;
2. forks twice, as described at the top; the request child returns `true`
   after the middle process has exited;
3. in the job: opens `dbPath` itself, records its pid, runs `body(ownDb)`,
   then marks the row `done`, or `crashed` with the text `Bubble` (Temper
   cannot read a bubble; the last database error, if any, is appended), bumps
   the topic, and exits with status 0. A transaction the body left open is
   rolled back first.

`dbPath` is the same path `db` was opened with; the caller (the server) knows
it. `body` receives the job's own `Db` and must use only that; anything it
captured that holds the request's `Db` must not be used. The body may call
`runsProgress` and may itself call `runsFinish` (for example to leave a
result in `detail`): the wrapper's finish then changes nothing.

    export let runsStart(dbPath: String, db: Db, key: String, body: fn (Db): Void throws Bubble): Boolean throws Bubble {
      if (dbPath == ":memory:" || dbPath == "") {
        console.log("runs: a job needs a database file, not '${dbPath}'");
        bubble()
      }
      runsReclaim(db, key);
      let now = sysUtcNow();
      let claimed = db.exec(
        "INSERT INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ($1, 'running', NULL, NULL, NULL, $2, NULL) ON CONFLICT(key) DO UPDATE SET status = 'running', progress = NULL, detail = NULL, pid = NULL, started_at = $2, finished_at = NULL WHERE runs.status <> 'running'",
        [key, now],
      );
      if (claimed == 0) { return false; }
      versionsBump(db, versionsRunTopic(key));
      let middle = sysFork();
      if (middle == 0) {
        let job = sysFork();
        if (job == 0) {
          runsJob(dbPath, db, key, body);
        }
        sysExit(0);
      } else if (middle < 0) {
        runsFinish(db, key, "crashed", "fork failed");
        bubble()
      } else {
        sysWaitPid(middle, false);
      }
      true
    }
