# Recovery: work that was in flight when the machine went away

`Marginalia.Recovery.sweep/0` marked every `reading` work and every
`linking` link failed at boot, because a restart killed the tasks. The
statuses and the text are the Elixir's, byte for byte.

One thing differs, and it is the process model. A job here is a process of
its own, reparented to init, so a restart of the server does not kill it. A
`runs` row whose pid is still alive is therefore left alone; only a row whose
process is gone (or that never recorded one) is marked `crashed`. The
`reading` and `linking` rows are still marked failed unconditionally, as in
Elixir: this library cannot know which run key a read used, and a read that
survived the restart and finishes later will overwrite `failed` with `read`
itself, which is the right end state. A server that wants to be stricter
passes through `runsActive` before calling `recoveryRun`.

Called once by the server at boot, before it accepts a connection.

    let { Db } = import("db/src");
    let { sysUtcNow } = import("sys/src");

    export let recoveryNote(): String { "interrupted by a restart" }

The ids of rows in `table` with status `from`, as text.

    let recoveryIds(db: Db, table: String, from: String): List<Int> throws Bubble {
      let out = new ListBuilder<Int>();
      for (let row of db.query("SELECT id FROM ${table} WHERE status = $1", [from])) {
        out.add(row.int("id"));
      }
      out.toList()
    }

`UPDATE works SET status = 'failed', status_detail = 'interrupted by a
restart' WHERE status = 'reading'`. Answers how many. Each work's
`work:<id>` topic is bumped so a page that is waiting on it re-fetches.

    export let recoveryWorks(db: Db): Int throws Bubble {
      let ids = recoveryIds(db, "works", "reading");
      let n = db.exec(
        "UPDATE works SET status = 'failed', status_detail = $1, updated_at = $2 WHERE status = 'reading'",
        [recoveryNote(), sysUtcNow()],
      );
      for (let id of ids) { versionsBump(db, versionsWorkTopic(id)); }
      n
    }

`UPDATE links SET status = 'failed', error = 'interrupted by a restart'
WHERE status = 'linking'`.

    export let recoveryLinks(db: Db): Int throws Bubble {
      let ids = recoveryIds(db, "links", "linking");
      let n = db.exec(
        "UPDATE links SET status = 'failed', error = $1, updated_at = $2 WHERE status = 'linking'",
        [recoveryNote(), sysUtcNow()],
      );
      for (let id of ids) { versionsBump(db, versionsLinkTopic(id)); }
      n
    }

Every `running` run whose pid is gone, or null, becomes `crashed` with the
detail `interrupted by a restart`.

    export let recoveryRuns(db: Db): Int throws Bubble {
      var n = 0;
      for (let row of db.query("SELECT key, pid FROM runs WHERE status = 'running'", [])) {
        let pid = row.intOrNull("pid");
        let alive = if (pid == null) { false } else { runsPidAlive(pid) };
        if (!alive) {
          if (runsFinish(db, row.str("key"), "crashed", recoveryNote())) { n += 1; }
        }
      }
      n
    }

The whole sweep: runs first, so a run that is dead is dead before anything
asks; then works and links. Answers the total number of rows changed, and
logs the Elixir's warning when it is not zero.

    export let recoveryRun(db: Db): Int throws Bubble {
      let runs = recoveryRuns(db);
      let links = recoveryLinks(db);
      let works = recoveryWorks(db);
      if (links + works > 0) {
        console.log("marginalia: ${links.toString()} links and ${works.toString()} reads were interrupted by a restart, marked failed");
      }
      if (runs > 0) {
        console.log("marginalia: ${runs.toString()} runs were interrupted by a restart, marked crashed");
      }
      runs + links + works
    }
