# db

A thin wrapper over the `sys` database builtins. `sysDbQuery` answers a list
of lists of text: the column names first, then one list per row, every cell
text, NULL as null. `DbRow` pairs a row with the names so a caller asks for a
column by name and gets a typed value, and a wrong guess is a bubble, not a
quiet default.

    let { parseJson, JsonSyntaxTree, JsonArray, JsonString, JsonNumeric } = import("std/json");
    let {
      sysDbOpen, sysDbExec, sysDbQuery, sysDbLastId, sysDbChanges, sysDbClose, sysUtcNow,
    } = import("sys/src");
    let { SqlFragment } = import("orm/src");

## Errors

Temper's `bubble()` carries no message. Every failure of the database layer
therefore does two things before it bubbles: it stores the message in
`Db.lastError`, and it prints it to the console, so a failing statement can
be found in a log. The message is the first 80 characters of the SQL.

    let clip(sql: String): String {
      var i = String.begin;
      var n = 0;
      while (sql.hasIndex(i) && n < 80) { i = sql.next(i); n += 1; }
      if (!sql.hasIndex(i)) { return sql; }
      sql.slice(String.begin, i)
    }

## DbRow

A row of a result. Columns are found by name, first match; a name that is
not in the result bubbles, and `DbRow.fail` prints which one.

    export class DbRow(public columns: List<String>, public cells: List<String?>) {

      private fail(what: String): Void throws Bubble {
        console.log("db row: ${what}");
        bubble()
      }

The index of a column, or a bubble naming it.

      public indexOf(col: String): Int throws Bubble {
        var i = 0;
        while (i < columns.length) {
          if (columns[i] == col) { return i; }
          i += 1;
        }
        fail("no column ${col} in (${columns.join(", ") { (c: String): String => c }})");
        bubble()
      }

      public has(col: String): Boolean {
        var i = 0;
        while (i < columns.length) {
          if (columns[i] == col) { return true; }
          i += 1;
        }
        false
      }

The cell as text, or null. A missing column bubbles.

      public strOrNull(col: String): String? throws Bubble {
        let i = indexOf(col);
        cells[i]
      }

      public isNull(col: String): Boolean throws Bubble {
        strOrNull(col) == null
      }

      public str(col: String): String throws Bubble {
        let v = strOrNull(col);
        if (v != null) { return v; }
        fail("column ${col} is NULL");
        bubble()
      }

      public int(col: String): Int throws Bubble {
        let s = str(col);
        var n = 0;
        let ok = do { n = s.toInt32(); true } orelse false;
        if (!ok) { fail("column ${col} is not an integer: ${s}"); }
        n
      }

      public intOrNull(col: String): Int? throws Bubble {
        let v = strOrNull(col);
        if (v == null) { return null; }
        int(col)
      }

`1` and `0` are what SQLite stores for a boolean. `true` and `false` are
accepted too, for a value that came through text.

      public bool(col: String): Boolean throws Bubble {
        let s = str(col);
        if (s == "1" || s == "true") { return true; }
        if (s == "0" || s == "false") { return false; }
        fail("column ${col} is not a boolean: ${s}");
        bubble()
      }

      public float(col: String): Float64 throws Bubble {
        let s = str(col);
        var f = 0.0;
        let ok = do { f = s.toFloat64(); true } orelse false;
        if (!ok) { fail("column ${col} is not a number: ${s}"); }
        f
      }

The JSON tree of a text column, or null for NULL. Text that is not JSON
bubbles.

      public json(col: String): JsonSyntaxTree? throws Bubble {
        let v = strOrNull(col);
        if (v != null) {
          var tree: JsonSyntaxTree? = null;
          let ok = do { tree = parseJson(v); true } orelse false;
          if (!ok) { fail("column ${col} is not JSON: ${v}"); }
          return tree;
        }
        null
      }

A JSON array column as a list. A NULL column is the empty list: the array
columns default to `'[]'`, and Postgres let them be NULL too.

      public strList(col: String): List<String> throws Bubble {
        let tree = json(col);
        if (tree == null) { return []; }
        if (!(tree is JsonArray)) {
          fail("column ${col} is not a JSON array");
        }
        let arr = tree as JsonArray orelse panic();
        let out = new ListBuilder<String>();
        for (let el of arr.elements) {
          if (!(el is JsonString)) {
            fail("column ${col} holds a non-string element");
          }
          let s = el as JsonString orelse panic();
          out.add(s.content);
        }
        out.toList()
      }

      public intList(col: String): List<Int> throws Bubble {
        let tree = json(col);
        if (tree == null) { return []; }
        if (!(tree is JsonArray)) {
          fail("column ${col} is not a JSON array");
        }
        let arr = tree as JsonArray orelse panic();
        let out = new ListBuilder<Int>();
        for (let el of arr.elements) {
          if (!(el is JsonNumeric)) {
            fail("column ${col} holds a non-number element");
          }
          let n = el as JsonNumeric orelse panic();
          out.add(n.asInt32());
        }
        out.toList()
      }
    }

## Db

`handle` is the `sys` handle. Statements take `$1`-style parameters, every
parameter text, `null` for NULL.

    export class Db(public var handle: Int) {
      public var lastError: String = "";
      private var depth: Int = 0;

      public fail(sql: String, why: String): Void throws Bubble {
        lastError = "${why}: ${clip(sql)}";
        console.log("db: ${lastError}");
        bubble()
      }

The raw result: the header row, then the rows.

      public raw(sql: String, params: List<String?>): List<List<String?>> throws Bubble {
        var result: List<List<String?>> = [];
        let ok = do { result = sysDbQuery(handle, sql, params); true } orelse false;
        if (!ok) { fail(sql, "query failed"); }
        result
      }

      public query(sql: String, params: List<String?>): List<DbRow> throws Bubble {
        let result = raw(sql, params);
        let out = new ListBuilder<DbRow>();
        if (result.length == 0) { return out.toList(); }
        let header = result[0].map { (c: String?): String => if (c != null) { c } else { "" } };
        var i = 1;
        while (i < result.length) {
          out.add(new DbRow(header, result[i]));
          i += 1;
        }
        out.toList()
      }

Rows changed by a write.

      public exec(sql: String, params: List<String?>): Int throws Bubble {
        raw(sql, params);
        sysDbChanges(handle)
      }

The new row's id after an `INSERT`.

      public insert(sql: String, params: List<String?>): Int throws Bubble {
        raw(sql, params);
        sysDbLastId(handle)
      }

The first row, or null.

      public one(sql: String, params: List<String?>): DbRow? throws Bubble {
        let rows = query(sql, params);
        if (rows.length == 0) { null } else { rows[0] }
      }

A script of several statements, no parameters: DDL.

      public script(sql: String): Void throws Bubble {
        let ok = do { sysDbExec(handle, sql); true } orelse false;
        if (!ok) { fail(sql, "script failed"); }
      }

Transactions. `begin` takes the write lock now (`BEGIN IMMEDIATE`), so two
writers queue instead of failing at their first write; a begin inside a
begin is a savepoint, and its rollback undoes only itself.

      public begin(): Void throws Bubble {
        if (depth == 0) {
          script("BEGIN IMMEDIATE");
        } else {
          script("SAVEPOINT sp${depth.toString()}");
        }
        depth += 1;
      }

      public commit(): Void throws Bubble {
        if (depth == 0) { fail("COMMIT", "no transaction"); }
        depth -= 1;
        if (depth == 0) {
          script("COMMIT");
        } else {
          script("RELEASE sp${depth.toString()}");
        }
      }

      public rollback(): Void throws Bubble {
        if (depth == 0) { fail("ROLLBACK", "no transaction"); }
        depth -= 1;
        if (depth == 0) {
          script("ROLLBACK");
        } else {
          script("ROLLBACK TO sp${depth.toString()}");
          script("RELEASE sp${depth.toString()}");
        }
      }

      public inTransaction(): Boolean { depth > 0 }

      public close(): Void {
        sysDbClose(handle);
      }
    }

Run `body` in a transaction: commit when it returns, roll back and bubble
when it bubbles. This is the contract's `Db.transaction`, as a function
because Blimp's closure types do not carry a type parameter through a
method: see the tests.

    export let dbTransaction(db: Db, body: fn (): Void throws Bubble): Void throws Bubble {
      db.begin();
      let ok = do { body(); true } orelse false;
      if (!ok) {
        db.rollback();
        bubble()
      }
      db.commit();
    }

## Alloy

An Alloy fragment as `$1`-style text and string parameters, ready for
`Db.query`.

    export let dbStatement(fragment: SqlFragment): Pair<String, List<String?>> {
      let p = fragment.toParameterized();
      let params = new ListBuilder<String?>();
      for (let v of p.params) { params.add(v); }
      new Pair<String, List<String?>>(p.text, params.toList())
    }

## Open and migrate

`dbMigrate` creates `schema_migrations` if it is missing, then applies, in
order, every script in `dbSchemaVersions()` whose version is not recorded,
each in its own transaction with its record. It returns how many it
applied; a second call returns 0.

    export let dbMigrate(db: Db): Int throws Bubble {
      db.script("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, inserted_at TEXT)");
      let done = new ListBuilder<Int>();
      for (let row of db.query("SELECT version FROM schema_migrations", [])) {
        done.add(row.int("version"));
      }
      let applied = done.toList();
      var count = 0;
      for (let entry of dbSchemaVersions()) {
        let version = entry.key;
        var seen = false;
        for (let v of applied) { if (v == version) { seen = true; } }
        if (!seen) {
          db.begin();
          let ok = do {
            db.script(entry.value);
            db.exec(
              "INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, $2)",
              [version.toString(), sysUtcNow()],
            );
            true
          } orelse false;
          if (!ok) {
            db.rollback();
            bubble()
          }
          db.commit();
          count += 1;
        }
      }
      count
    }

Opens (creating) the database, migrates it, and returns the handle.

    export let dbOpen(path: String): Db throws Bubble {
      var handle = -1;
      let ok = do { handle = sysDbOpen(path); true } orelse false;
      if (!ok) {
        console.log("db: cannot open ${path}");
        bubble()
      }
      let db = new Db(handle);
      dbMigrate(db);
      db
    }
