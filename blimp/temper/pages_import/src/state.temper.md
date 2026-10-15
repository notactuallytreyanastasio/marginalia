# The wizard's state

`ImportLive` kept the step, the source, the fetched list, the selection and the
folder name in the socket's assigns. There is no socket: they live in the
session's UI state, under keys that start with `import:`, and every request
reads them back.

* `import:wiz`: one JSON object of strings, the small scalars (step, source,
  repo, query, mode, state, pattern, how, order, folder, three flags, the
  sentences that can be showing). Flags are `"1"` and `"0"`; a sentence that is
  not showing is the empty string.
* the fetched pull requests are not in the session but in the table
  `import_pulls` (see "The listing"): up to five hundred rows are too many for
  the session row, which is rewritten on every request.
* `import:token`: the GitHub token the visitor typed, from the find step to the
  import. It is the one secret here. It is stored server-side in the session
  row, never rendered back, and deleted when the import starts.
* `import:result`: how an import ended (see `PimResult`), once it has.

Every top-level name in this library is shared by all of its files and, in the
built program, with every other library's: the private helpers start with `pim`.

    let { Ctx, uiGet, uiPut, uiDelete, uiGetJson } = import("webcore/src");
    let {
      JsonObject, JsonArray, JsonString, JsonSyntaxTree, JsonTextProducer, NullInterchangeContext, parseJson,
    } = import("std/json");
    let { ImporterPull } = import("importer/src");
    let { Db, DbRow, dbTransaction } = import("db/src");
    let { sysJoin, sysSha256, sysGraphemeTake } = import("sys/src");

## Small readers

    let pimOr(s: String?, d: String): String {
      if (s != null) { s } else { d }
    }

An empty string is "not showing".

    let pimSome(s: String): String? {
      if (s == "") { null } else { s }
    }

    let pimInt(s: String, d: Int): Int {
      do { s.toInt32() } orelse d
    }

    let pimFlag(b: Boolean): String { if (b) { "1" } else { "0" } }

    let pimStartsWith(s: String, prefix: String): Boolean {
      if (s == "" || prefix == "") { return false; }
      let parts = s.split(prefix);
      parts.length > 1 && parts.getOr(0, "x") == ""
    }

A string field of a JSON object, or `d`.

    let pimField(o: JsonObject, key: String, d: String): String {
      let v = o.propertyValueOrNull(key);
      if (v is JsonString) { v.content } else { d }
    }

The strings of a JSON array of strings; anything else in it is skipped.

    let pimStrings(t: JsonSyntaxTree?): List<String> {
      let out = new ListBuilder<String>();
      if (t is JsonArray) {
        for (var i = 0; i < t.elements.length; ++i) {
          let e = t.elements.getOr(i, t);
          if (e is JsonString) { out.add(e.content); }
        }
      }
      out.toList()
    }

    let pimPut(p: JsonTextProducer, key: String, value: String): Void {
      p.objectKey(key);
      p.stringValue(value);
    }

## The scalars

    export class PimWiz(
      public var step: String,
      public var source: String,
      public var repo: String,
      public var query: String,
      public var mode: String,
      public var state: String,
      public var pattern: String,
      public var how: String,
      public var order: String,
      public var folder: String,
      public var commits: Boolean,
      public var files: Boolean,
      public var number: Boolean,
      public var patternError: String?,
      public var hintWas: String?,
      public var hintTry: String?,
      public var error: String?,
    ) {}

The mount of the LiveView: the source step, a repository, everything on.

    export let pimNewWiz(): PimWiz {
      new PimWiz(
        "source", "", "", "", "repo", "all", "", "query", "oldest", "",
        true, true, false, null, null, null, null,
      )
    }

    let pimWizKey(): String { "import:wiz" }
    let pimTokenKey(): String { "import:token" }
    let pimResultKey(): String { "import:result" }

    export let pimWizFrom(o: JsonObject): PimWiz {
      let d = pimNewWiz();
      new PimWiz(
        pimField(o, "step", d.step),
        pimField(o, "source", d.source),
        pimField(o, "repo", d.repo),
        pimField(o, "query", d.query),
        pimField(o, "mode", d.mode),
        pimField(o, "state", d.state),
        pimField(o, "pattern", d.pattern),
        pimField(o, "how", d.how),
        pimField(o, "order", d.order),
        pimField(o, "folder", d.folder),
        pimField(o, "commits", "1") == "1",
        pimField(o, "files", "1") == "1",
        pimField(o, "number", "0") == "1",
        pimSome(pimField(o, "patternError", "")),
        pimSome(pimField(o, "hintWas", "")),
        pimSome(pimField(o, "hintTry", "")),
        pimSome(pimField(o, "error", "")),
      )
    }

    export let pimLoadWiz(ctx: Ctx): PimWiz {
      let t = uiGetJson(ctx, pimWizKey());
      if (t is JsonObject) { pimWizFrom(t) } else { pimNewWiz() }
    }

    export let pimWizJson(w: PimWiz): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      pimPut(p, "step", w.step);
      pimPut(p, "source", w.source);
      pimPut(p, "repo", w.repo);
      pimPut(p, "query", w.query);
      pimPut(p, "mode", w.mode);
      pimPut(p, "state", w.state);
      pimPut(p, "pattern", w.pattern);
      pimPut(p, "how", w.how);
      pimPut(p, "order", w.order);
      pimPut(p, "folder", w.folder);
      pimPut(p, "commits", pimFlag(w.commits));
      pimPut(p, "files", pimFlag(w.files));
      pimPut(p, "number", pimFlag(w.number));
      pimPut(p, "patternError", pimOr(w.patternError, ""));
      pimPut(p, "hintWas", pimOr(w.hintWas, ""));
      pimPut(p, "hintTry", pimOr(w.hintTry, ""));
      pimPut(p, "error", pimOr(w.error, ""));
      p.endObject();
      p.toJsonString()
    }

    export let pimSaveWiz(ctx: Ctx, w: PimWiz): Void throws Bubble {
      uiPut(ctx, pimWizKey(), pimWizJson(w));
    }

## The listing

A pull request's key, `ImportLive.key/1`.

    export let pimKey(c: ImporterPull): String { "${c.repo}#${c.number.toString()}" }

Up to five hundred rows, read on every click, and in the session they cost too
much: the interpreter escapes a string a character at a time, and an 86 KB
string in the session row was a second and a half to save and three seconds to
read on the next request. So the listing is a table of its own, one row per pull
request, keyed by the session, with the two flags the page keeps (`shown`: it
passes the pattern, `chosen`: it is ticked). Clicking a box is one `UPDATE`.

The table is made the first time it is needed (`CREATE TABLE IF NOT EXISTS`):
it belongs to this page and to nothing the schema library migrates. Rows of
sessions that never came back are swept a day later.

    let pimEnsureTable(db: Db): Void throws Bubble {
      db.script("CREATE TABLE IF NOT EXISTS import_pulls (sid TEXT NOT NULL, pos INTEGER NOT NULL, repo TEXT NOT NULL, number INTEGER NOT NULL, title TEXT NOT NULL, url TEXT, state TEXT, draft INTEGER NOT NULL DEFAULT 0, base TEXT, head TEXT, updated_at TEXT, created_at TEXT, merged_at TEXT, shown INTEGER NOT NULL DEFAULT 0, chosen INTEGER NOT NULL DEFAULT 0, made TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')), PRIMARY KEY (sid, pos))");
    }

The session's rows are found by a hash of its id, as the run is: the id is the
secret.

    export let pimSid(ctx: Ctx): String {
      sysGraphemeTake(sysSha256(ctx.session.id), 24)
    }

    let pimPullColumns(): String {
      "repo, number, title, url, state, draft, base, head, updated_at, created_at, merged_at"
    }

    let pimPullFrom(row: DbRow): ImporterPull throws Bubble {
      new ImporterPull(
        row.str("repo"), row.int("number"), row.str("title"), row.strOrNull("url"), row.strOrNull("state"),
        row.bool("draft"), row.strOrNull("base"), row.strOrNull("head"), row.strOrNull("updated_at"),
        row.strOrNull("created_at"), row.strOrNull("merged_at"),
      )
    }

    export let pimSaveCands(ctx: Ctx, cs: List<ImporterPull>): Void throws Bubble {
      pimEnsureTable(ctx.db);
      let sid = pimSid(ctx);
      dbTransaction(ctx.db, fn (): Void throws Bubble {
        ctx.db.exec("DELETE FROM import_pulls WHERE sid = $1 OR made < datetime('now', '-1 day')", [sid]);
        var i = 0;
        while (i < cs.length) {
          let c = cs[i];
          let params = new ListBuilder<String?>();
          params.add(sid);
          params.add(i.toString());
          params.add(c.repo);
          params.add(c.number.toString());
          params.add(c.title);
          params.add(c.url);
          params.add(c.state);
          params.add(pimFlag(c.draft));
          params.add(c.base);
          params.add(c.head);
          params.add(c.updatedAt);
          params.add(c.createdAt);
          params.add(c.mergedAt);
          ctx.db.exec(
            "INSERT INTO import_pulls (sid, pos, repo, number, title, url, state, draft, base, head, updated_at, created_at, merged_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)",
            params.toList(),
          );
          i += 1;
        }
      });
    }

Every row, in the order the list stands.

    export let pimLoadCands(ctx: Ctx): List<ImporterPull> throws Bubble {
      pimEnsureTable(ctx.db);
      let rows = ctx.db.query("SELECT ${pimPullColumns()} FROM import_pulls WHERE sid = $1 ORDER BY pos", [pimSid(ctx)]);
      let out = new ListBuilder<ImporterPull>();
      var i = 0;
      while (i < rows.length) {
        out.add(pimPullFrom(rows[i]));
        i += 1;
      }
      out.toList()
    }

    export let pimForgetCands(ctx: Ctx): Void throws Bubble {
      pimEnsureTable(ctx.db);
      ctx.db.exec("DELETE FROM import_pulls WHERE sid = $1", [pimSid(ctx)]);
    }

What a pattern leaves: the rows at these positions are shown and ticked, the rest
are neither.

    export let pimSetShown(ctx: Ctx, positions: List<Int>): Void throws Bubble {
      pimEnsureTable(ctx.db);
      let sid = pimSid(ctx);
      ctx.db.exec("UPDATE import_pulls SET shown = 0, chosen = 0 WHERE sid = $1", [sid]);
      if (positions.length > 0) {
        let list = positions.map { (n: Int): String => n.toString() };
        ctx.db.exec("UPDATE import_pulls SET shown = 1, chosen = 1 WHERE sid = $1 AND pos IN (${sysJoin(list, ",")})", [sid]);
      }
    }

A box clicked: the key is `owner/name#number`, cut at the last `#`.

    export let pimToggleKey(ctx: Ctx, key: String): Void throws Bubble {
      pimEnsureTable(ctx.db);
      let parts = key.split("#");
      if (parts.length >= 2) {
        let number = parts.getOr(parts.length - 1, "");
        let repo = sysJoin(parts.slice(0, parts.length - 1), "#");
        ctx.db.exec(
          "UPDATE import_pulls SET chosen = 1 - chosen WHERE sid = $1 AND repo = $2 AND number = $3",
          [pimSid(ctx), repo, number],
        );
      }
    }

`all` ticks what is shown and `none` clears what is shown: the rows the pattern
hides keep their ticks.

    export let pimTickShown(ctx: Ctx, on: Boolean): Void throws Bubble {
      pimEnsureTable(ctx.db);
      ctx.db.exec("UPDATE import_pulls SET chosen = $2 WHERE sid = $1 AND shown = 1", [pimSid(ctx), pimFlag(on)]);
    }

The rows the list shows, each with whether it is ticked.

    export class PimRow(public pull: ImporterPull, public chosen: Boolean) {}

    export let pimLoadRows(ctx: Ctx): List<PimRow> throws Bubble {
      pimEnsureTable(ctx.db);
      let rows = ctx.db.query(
        "SELECT ${pimPullColumns()}, chosen FROM import_pulls WHERE sid = $1 AND shown = 1 ORDER BY pos",
        [pimSid(ctx)],
      );
      let out = new ListBuilder<PimRow>();
      var i = 0;
      while (i < rows.length) {
        out.add(new PimRow(pimPullFrom(rows[i]), rows[i].bool("chosen")));
        i += 1;
      }
      out.toList()
    }

How many are listed, shown and ticked.

    export class PimCounts(public total: Int, public shown: Int, public chosen: Int) {}

    export let pimLoadCounts(ctx: Ctx): PimCounts throws Bubble {
      pimEnsureTable(ctx.db);
      let row = ctx.db.one(
        "SELECT count(*) AS total, coalesce(sum(shown), 0) AS shown, coalesce(sum(chosen), 0) AS chosen FROM import_pulls WHERE sid = $1",
        [pimSid(ctx)],
      );
      if (row != null) {
        new PimCounts(row.int("total"), row.int("shown"), row.int("chosen"))
      } else {
        new PimCounts(0, 0, 0)
      }
    }

The pull requests ticked, in the order of the list as sorted, not the order they
were clicked in.

    export let pimLoadPicked(ctx: Ctx): List<ImporterPull> throws Bubble {
      pimEnsureTable(ctx.db);
      let rows = ctx.db.query(
        "SELECT ${pimPullColumns()} FROM import_pulls WHERE sid = $1 AND chosen = 1 ORDER BY pos",
        [pimSid(ctx)],
      );
      let out = new ListBuilder<ImporterPull>();
      var i = 0;
      while (i < rows.length) {
        out.add(pimPullFrom(rows[i]));
        i += 1;
      }
      out.toList()
    }

## The token

    export let pimStoredToken(ctx: Ctx): String { pimOr(uiGet(ctx, pimTokenKey()), "") }

    export let pimStoreToken(ctx: Ctx, token: String): Void {
      if (token == "") { uiDelete(ctx, pimTokenKey()); } else { uiPut(ctx, pimTokenKey(), token); }
    }

## How an import ended

The job writes this as the run's `detail`; the page reads it once, keeps it in
`import:result` for the results step, and shows it. Every number is a string.

    export class PimMissed(public number: Int, public title: String, public reason: String) {}

    export class PimResult(
      public folderId: Int?,
      public created: Int,
      public skipped: List<String>,
      public failed: List<Pair<String, String>>,
      public missed: List<PimMissed>,
    ) {}

    export let pimResultJson(r: PimResult): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      let id = r.folderId;
      pimPut(p, "folder", if (id != null) { id.toString() } else { "" });
      pimPut(p, "created", r.created.toString());
      p.objectKey("skipped");
      p.startArray();
      for (var i = 0; i < r.skipped.length; ++i) { p.stringValue(r.skipped.getOr(i, "")); }
      p.endArray();
      p.objectKey("failed");
      p.startArray();
      for (var i = 0; i < r.failed.length; ++i) {
        let f = r.failed.getOr(i, new Pair("", ""));
        p.startArray();
        p.stringValue(f.key);
        p.stringValue(f.value);
        p.endArray();
      }
      p.endArray();
      p.objectKey("missed");
      p.startArray();
      for (var i = 0; i < r.missed.length; ++i) {
        let m = r.missed.getOr(i, new PimMissed(0, "", ""));
        p.startArray();
        p.stringValue(m.number.toString());
        p.stringValue(m.title);
        p.stringValue(m.reason);
        p.endArray();
      }
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

The result a run's `detail` holds, or null when it is not one (a crash text, a
progress phase).

    export let pimResultFrom(text: String): PimResult? {
      let t: JsonSyntaxTree? = parseJson(text) orelse null;
      if (t is JsonObject) {
        let folder = pimField(t, "folder", "");
        let failed = new ListBuilder<Pair<String, String>>();
        let fs = t.propertyValueOrNull("failed");
        if (fs is JsonArray) {
          for (var i = 0; i < fs.elements.length; ++i) {
            let row = pimStrings(fs.elements.getOr(i, fs));
            failed.add(new Pair(row.getOr(0, ""), row.getOr(1, "")));
          }
        }
        let missed = new ListBuilder<PimMissed>();
        let ms = t.propertyValueOrNull("missed");
        if (ms is JsonArray) {
          for (var i = 0; i < ms.elements.length; ++i) {
            let row = pimStrings(ms.elements.getOr(i, ms));
            missed.add(new PimMissed(pimInt(row.getOr(0, "0"), 0), row.getOr(1, ""), row.getOr(2, "")));
          }
        }
        new PimResult(
          if (folder == "") { null } else { pimInt(folder, 0) },
          pimInt(pimField(t, "created", "0"), 0),
          pimStrings(t.propertyValueOrNull("skipped")),
          failed.toList(),
          missed.toList(),
        )
      } else { null }
    }

    export let pimLoadResult(ctx: Ctx): PimResult? {
      let s = uiGet(ctx, pimResultKey());
      if (s != null) { pimResultFrom(s) } else { null }
    }

    export let pimSaveResult(ctx: Ctx, text: String): Void {
      uiPut(ctx, pimResultKey(), text);
    }

## Starting over

A page load that is not a poll starts the wizard again, as the mount did.

    export let pimClear(ctx: Ctx): Void throws Bubble {
      pimForgetCands(ctx);
      uiDelete(ctx, pimWizKey());
      uiDelete(ctx, pimTokenKey());
      uiDelete(ctx, pimResultKey());
    }
