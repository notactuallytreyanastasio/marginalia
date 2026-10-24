# Tests for db

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated, so
a test never sees another's rows.

    let { sql } = import("orm/src");
    let { sysByteLength, sysUtcNow, sysDbOpen } = import("sys/src");
    let {
      listFolders, getFolder, foldersByIds, folderByName, sibling, createFolder,
      renameFolder, moveFolder, deleteFolder, moveWork, unfiledCount,
      looseWorkCollections, fileWorks, publish, unpublish, publishedBySlug,
      published, slugTaken, Statement, Prepared,
    } = import("core/src");

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

    let joinStrings(xs: List<String>): String {
      xs.join(",") { (x: String): String => x }
    }

    let orNull(s: String?): String {
      if (s != null) { s } else { "NULL" }
    }

    let column(db: Db, query: String, col: String): String throws Bubble {
      let out = new ListBuilder<String>();
      for (let row of db.query(query, [])) { out.add(orNull(row.strOrNull(col))); }
      joinStrings(out.toList())
    }

    let one(db: Db, query: String): String throws Bubble {
      let row = db.one(query, []);
      if (row != null) { orNull(row.cells[0]) } else { "none" }
    }

    let addUser(db: Db, email: String): Int throws Bubble {
      db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email])
    }

    let addWork(db: Db, userId: Int, title: String, slug: String): Int throws Bubble {
      db.insert(
        "INSERT INTO works (user_id, title, body, slug) VALUES ($1, $2, 'body', $3)",
        [userId.toString(), title, slug],
      )
    }

    let didBubble(db: Db, query: String, params: List<String?>): Boolean {
      do { db.exec(query, params); false } orelse true
    }

    let expectBubbles(test: Test, db: Db, query: String, what: String): Void {
      assert(didBubble(db, query, [])) { what }
    }

A string with characters outside ASCII goes through a function, or a
literal escape in a connected call breaks the frontend.

    let accented(): String { "caf\u{e9} \u{4e16}\u{754c} it's \"quoted\"" }

    let expectedTables(): List<String> {
      [
        "conversations", "corrections", "cuts", "document_summaries", "edges",
        "folders", "graph_events", "import_pulls", "link_edges", "links", "messages",
        "mutterings", "nodes", "render_cache", "revisions", "runs", "schema_migrations",
        "sections", "sessions", "stack_steps", "stack_stories", "users",
        "users_tokens", "versions", "work_attachments", "works",
      ]
    }

## Schema

    test("opening migrates and every table exists") { test =>
      let db = dbOpen(":memory:");
      let got = column(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name", "name");
      expectText(test, got, joinStrings(expectedTables()));
      expectInt(test, expectedTables().length, 26);
    }

    test("the partial and unique indexes are there") { test =>
      let db = dbOpen(":memory:");
      let got = column(db, "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE '%folders%' AND sql IS NOT NULL ORDER BY name", "name");
      expectText(test, got, "folders_parent_id_index,folders_published_at_index,folders_root_name_index,folders_sibling_name_index,folders_slug_index,folders_user_id_index");
      let partial = one(db, "SELECT sql FROM sqlite_master WHERE name = 'conversations_work_block_index'");
      expectTrue(test, hasText(partial, "WHERE block_ref IS NOT NULL"), partial);
      let cuts = one(db, "SELECT sql FROM sqlite_master WHERE name = 'cuts_one_per_folder_index'");
      expectTrue(test, hasText(cuts, "WHERE folder_id IS NOT NULL"), cuts);
    }

    test("dbSchemaVersions is ordered and starts at 1") { test =>
      let versions = dbSchemaVersions();
      expectInt(test, versions.length, 3);
      expectInt(test, versions[0].key, 1);
      expectInt(test, versions[1].key, 2);
      expectInt(test, versions[2].key, 3);
      expectTrue(test, hasText(versions[0].value, "CREATE TABLE works"), "works in the script");
      expectTrue(test, hasText(versions[1].value, "CREATE TABLE import_pulls"), "import_pulls in version 2");
    }

    test("migrating twice applies nothing the second time") { test =>
      let db = new Db(sysDbOpen(":memory:"));
      expectInt(test, dbMigrate(db), 3);
      expectInt(test, dbMigrate(db), 0);
      expectInt(test, dbMigrate(db), 0);
      expectText(test, column(db, "SELECT version FROM schema_migrations ORDER BY version", "version"), "1,2,3");
      let stamp = one(db, "SELECT inserted_at FROM schema_migrations ORDER BY version LIMIT 1");
      expectInt(test, sysByteLength(stamp), 19);
    }

    test("a migration that fails leaves no trace") { test =>
      let db = new Db(sysDbOpen(":memory:"));
      db.script("CREATE TABLE users (id INTEGER PRIMARY KEY)");
      let failed = do { dbMigrate(db); false } orelse true;
      expectTrue(test, failed, "version 1 collides with the existing users table");
      expectText(test, column(db, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name", "name"), "schema_migrations,users");
      expectText(test, one(db, "SELECT count(*) FROM schema_migrations"), "0");
      expectFalse(test, db.inTransaction(), "no transaction left open");
    }

    test("timestamps default to a UTC second") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      let row = db.one("SELECT inserted_at, updated_at FROM users WHERE id = $1", [uid.toString()]);
      expectTrue(test, row != null, "user row");
      if (row != null) {
        let at = row.str("inserted_at");
        expectInt(test, sysByteLength(at), 19);
        expectText(test, one(db, "SELECT substr(inserted_at, 1, 4) = strftime('%Y', 'now') FROM users"), "1");
        expectText(test, one(db, "SELECT inserted_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]' FROM users"), "1");
        expectTrue(test, row.str("updated_at") == at || sysByteLength(row.str("updated_at")) == 19, "updated_at set");
      }
    }

## Rows, keys and cascades

    test("a user, a work and a section; deleting the user takes them") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      let wid = addWork(db, uid, "A draft", "slug-1");
      let sid = db.insert(
        "INSERT INTO sections (work_id, ordinal, title, body) VALUES ($1, 1, 'One', 'text')",
        [wid.toString()],
      );
      expectInt(test, uid, 1);
      expectInt(test, wid, 1);
      expectInt(test, sid, 1);
      expectText(test, one(db, "SELECT count(*) FROM sections"), "1");
      expectInt(test, db.exec("DELETE FROM users WHERE id = $1", [uid.toString()]), 1);
      expectText(test, one(db, "SELECT count(*) FROM works"), "0");
      expectText(test, one(db, "SELECT count(*) FROM sections"), "0");
    }

    test("the cascade reaches nodes, edges, conversations and messages") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      let wid = addWork(db, uid, "A draft", "slug-1");
      let w = wid.toString();
      let n1 = db.insert("INSERT INTO nodes (work_id, node_type, title) VALUES ($1, 'goal', 'g')", [w]);
      let n2 = db.insert("INSERT INTO nodes (work_id, node_type, title) VALUES ($1, 'option', 'o')", [w]);
      db.exec("INSERT INTO edges (work_id, from_id, to_id) VALUES ($1, $2, $3)", [w, n1.toString(), n2.toString()]);
      let cid = db.insert("INSERT INTO conversations (work_id) VALUES ($1)", [w]);
      db.exec("INSERT INTO messages (conversation_id, role, content) VALUES ($1, 'user', 'hi')", [cid.toString()]);
      expectText(test, one(db, "SELECT edge_type FROM edges"), "leads_to");
      expectText(test, one(db, "SELECT mode || '/' || anchor_kind FROM conversations"), "read/work");
      db.exec("DELETE FROM works WHERE id = $1", [w]);
      expectText(test, one(db, "SELECT (SELECT count(*) FROM nodes) + (SELECT count(*) FROM edges) + (SELECT count(*) FROM conversations) + (SELECT count(*) FROM messages)"), "0");
    }

    test("deleting a node deletes its edges; deleting a folder nils the work's folder") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      let wid = addWork(db, uid, "A draft", "slug-1");
      let w = wid.toString();
      let n1 = db.insert("INSERT INTO nodes (work_id, node_type, title) VALUES ($1, 'goal', 'g')", [w]);
      let n2 = db.insert("INSERT INTO nodes (work_id, node_type, title) VALUES ($1, 'option', 'o')", [w]);
      db.exec("INSERT INTO edges (work_id, from_id, to_id) VALUES ($1, $2, $3)", [w, n1.toString(), n2.toString()]);
      db.exec("DELETE FROM nodes WHERE id = $1", [n2.toString()]);
      expectText(test, one(db, "SELECT count(*) FROM edges"), "0");
      let fid = db.insert("INSERT INTO folders (name, user_id) VALUES ('F', $1)", [uid.toString()]);
      db.exec("UPDATE works SET folder_id = $1", [fid.toString()]);
      expectText(test, one(db, "SELECT folder_id FROM works"), fid.toString());
      db.exec("DELETE FROM folders WHERE id = $1", [fid.toString()]);
      expectText(test, one(db, "SELECT folder_id FROM works"), "NULL");
      expectText(test, one(db, "SELECT count(*) FROM works"), "1");
    }

    test("a child folder survives its parent with a null parent") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com").toString();
      let parent = db.insert("INSERT INTO folders (name, user_id) VALUES ('P', $1)", [uid]);
      db.exec("INSERT INTO folders (name, user_id, parent_id) VALUES ('C', $1, $2)", [uid, parent.toString()]);
      db.exec("DELETE FROM folders WHERE id = $1", [parent.toString()]);
      expectText(test, one(db, "SELECT name || ':' || ifnull(parent_id, 'none') FROM folders"), "C:none");
    }

    test("a row that points at nothing is refused") { test =>
      let db = dbOpen(":memory:");
      expectBubbles(test, db, "INSERT INTO works (user_id, title, body, slug) VALUES (99, 't', 'b', 's')", "no such user");
      expectBubbles(test, db, "INSERT INTO sections (work_id, ordinal, title, body) VALUES (5, 1, 't', 'b')", "no such work");
    }

    test("a unique index violation bubbles, and the email index ignores case") { test =>
      let db = dbOpen(":memory:");
      addUser(db, "Reader@Example.com");
      expectTrue(test, didBubble(db, "INSERT INTO users (email) VALUES ($1)", ["reader@example.com"]), "NOCASE duplicate");
      expectText(test, one(db, "SELECT count(*) FROM users WHERE email = 'READER@EXAMPLE.COM'"), "1");
      let uid = addUser(db, "b@example.com");
      addWork(db, uid, "One", "same");
      expectTrue(test, didBubble(db, "INSERT INTO works (user_id, title, body, slug) VALUES ($1, 't', 'b', 'same')", [uid.toString()]), "slug");
    }

    test("folder names are unique among siblings and among roots") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com").toString();
      let a = db.insert("INSERT INTO folders (name, user_id) VALUES ('A', $1)", [uid]).toString();
      let b = db.insert("INSERT INTO folders (name, user_id) VALUES ('B', $1)", [uid]).toString();
      expectTrue(test, didBubble(db, "INSERT INTO folders (name, user_id) VALUES ('A', $1)", [uid]), "two roots named A");
      db.exec("INSERT INTO folders (name, user_id, parent_id) VALUES ('X', $1, $2)", [uid, a]);
      db.exec("INSERT INTO folders (name, user_id, parent_id) VALUES ('X', $1, $2)", [uid, b]);
      expectTrue(test, didBubble(db, "INSERT INTO folders (name, user_id, parent_id) VALUES ('X', $1, $2)", [uid, a]), "two children named X under A");
      expectText(test, one(db, "SELECT count(*) FROM folders WHERE name = 'X'"), "2");
    }

    test("a link is between two different works") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      let w1 = addWork(db, uid, "One", "s1").toString();
      let w2 = addWork(db, uid, "Two", "s2").toString();
      expectTrue(test, didBubble(db, "INSERT INTO links (a_work_id, b_work_id) VALUES ($1, $1)", [w1]), "self link");
      db.exec("INSERT INTO links (a_work_id, b_work_id) VALUES ($1, $2)", [w1, w2]);
      expectText(test, one(db, "SELECT status FROM links"), "pending");
      expectTrue(test, didBubble(db, "INSERT INTO links (a_work_id, b_work_id) VALUES ($1, $2)", [w1, w2]), "duplicate pair");
    }

    test("sessions, runs, versions and mutterings") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      let tok = db.insert("INSERT INTO users_tokens (user_id, token, context) VALUES ($1, 'abcd', 'session')", [uid.toString()]);
      db.exec("INSERT INTO sessions (id, user_token_id) VALUES ('s1', $1)", [tok.toString()]);
      expectText(test, one(db, "SELECT data FROM sessions WHERE id = 's1'"), "{}");
      db.exec("DELETE FROM users_tokens WHERE id = $1", [tok.toString()]);
      expectText(test, one(db, "SELECT ifnull(user_token_id, 'nil') FROM sessions"), "nil");
      db.exec("INSERT INTO versions (topic) VALUES ('work:1') ON CONFLICT(topic) DO UPDATE SET n = n + 1", []);
      db.exec("INSERT INTO versions (topic) VALUES ('work:1') ON CONFLICT(topic) DO UPDATE SET n = n + 1", []);
      expectText(test, one(db, "SELECT n FROM versions WHERE topic = 'work:1'"), "1");
      db.exec("INSERT INTO runs (key, status) VALUES ('read:1', 'running')", []);
      expectTrue(test, didBubble(db, "INSERT INTO runs (key, status) VALUES ('read:1', 'running')", []), "run key is unique");
      db.exec("INSERT INTO mutterings (text) VALUES ('hm')", []);
      expectText(test, one(db, "SELECT source FROM mutterings"), "cron");
      expectTrue(test, didBubble(db, "INSERT INTO mutterings (text) VALUES ('hm')", []), "muttering text is unique");
    }

    test("boolean and JSON defaults") { test =>
      let db = dbOpen(":memory:");
      addUser(db, "a@example.com");
      let row = db.one("SELECT is_admin, is_guest, seen_tours FROM users", []);
      expectTrue(test, row != null, "row");
      if (row != null) {
        expectFalse(test, row.bool("is_admin"), "is_admin");
        expectFalse(test, row.bool("is_guest"), "is_guest");
        expectInt(test, row.strList("seen_tours").length, 0);
      }
    }

## Db

    test("query returns rows by column name; none for an empty result") { test =>
      let db = dbOpen(":memory:");
      addUser(db, "a@example.com");
      addUser(db, "b@example.com");
      let rows = db.query("SELECT id, email FROM users ORDER BY id", []);
      expectInt(test, rows.length, 2);
      expectText(test, joinStrings(rows[0].columns), "id,email");
      expectText(test, rows[1].str("email"), "b@example.com");
      expectInt(test, rows[1].int("id"), 2);
      expectInt(test, db.query("SELECT id FROM users WHERE id > 9", []).length, 0);
      expectTrue(test, db.one("SELECT id FROM users WHERE id > 9", []) == null, "one of none is null");
    }

    test("exec counts changes and insert returns the id") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      let w1 = addWork(db, uid, "One", "s1");
      let w2 = addWork(db, uid, "Two", "s2");
      expectInt(test, w2, w1 + 1);
      expectInt(test, db.exec("UPDATE works SET status = 'ready'", []), 2);
      expectInt(test, db.exec("UPDATE works SET status = 'ready' WHERE id = 99", []), 0);
    }

    test("parameters keep text and quotes intact, and null is NULL") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      let params = new ListBuilder<String?>();
      params.add(uid.toString());
      params.add(accented());
      params.add("slug");
      params.add(null);
      let wid = db.insert("INSERT INTO works (user_id, title, body, slug, intent) VALUES ($1, $2, 'b', $3, $4)", params.toList());
      let row = db.one("SELECT title, intent FROM works WHERE id = $1", [wid.toString()]);
      expectTrue(test, row != null, "row");
      if (row != null) {
        expectText(test, row.str("title"), accented());
        expectTrue(test, row.strOrNull("intent") == null, "NULL comes back as null");
      }
    }

    test("a failing statement bubbles with the first 80 characters of its SQL") { test =>
      let db = dbOpen(":memory:");
      let long = "SELECT nothing, at_all, from_nowhere FROM a_table_that_is_not_there WHERE the_name_is_long = 1";
      let failed = do { db.query(long, []); false } orelse true;
      expectTrue(test, failed, "bubbled");
      expectText(test, db.lastError, "query failed: SELECT nothing, at_all, from_nowhere FROM a_table_that_is_not_there WHERE the_na");
      let short = do { db.exec("SELEKT 1", []); false } orelse true;
      expectTrue(test, short, "bubbled");
      expectText(test, db.lastError, "query failed: SELEKT 1");
    }

    test("a script that fails midway says so") { test =>
      let db = dbOpen(":memory:");
      let failed = do { db.script("CREATE TABLE t1 (a); CREATE TABLE t1 (a);"); false } orelse true;
      expectTrue(test, failed, "bubbled");
      expectTrue(test, hasText(db.lastError, "script failed: CREATE TABLE t1"), db.lastError);
    }

## Transactions

    test("a transaction commits when the body returns") { test =>
      let db = dbOpen(":memory:");
      dbTransaction(db, fn (): Void throws Bubble {
        addUser(db, "a@example.com");
        addUser(db, "b@example.com");
      });
      expectText(test, one(db, "SELECT count(*) FROM users"), "2");
      expectFalse(test, db.inTransaction(), "closed");
    }

    test("a transaction rolls back when the body bubbles") { test =>
      let db = dbOpen(":memory:");
      addUser(db, "keep@example.com");
      let failed = do {
        dbTransaction(db, fn (): Void throws Bubble {
          addUser(db, "gone@example.com");
          db.exec("INSERT INTO nope VALUES (1)", []);
        });
        false
      } orelse true;
      expectTrue(test, failed, "the bubble comes out");
      expectText(test, column(db, "SELECT email FROM users", "email"), "keep@example.com");
      expectFalse(test, db.inTransaction(), "closed");
      addUser(db, "after@example.com");
      expectText(test, one(db, "SELECT count(*) FROM users"), "2");
    }

    test("begin, commit and rollback by hand") { test =>
      let db = dbOpen(":memory:");
      db.begin();
      addUser(db, "a@example.com");
      db.rollback();
      expectText(test, one(db, "SELECT count(*) FROM users"), "0");
      db.begin();
      addUser(db, "a@example.com");
      db.commit();
      expectText(test, one(db, "SELECT count(*) FROM users"), "1");
      let stray = do { db.commit(); false } orelse true;
      expectTrue(test, stray, "commit outside a transaction bubbles");
    }

    test("an inner transaction rolls back alone") { test =>
      let db = dbOpen(":memory:");
      dbTransaction(db, fn (): Void throws Bubble {
        addUser(db, "outer@example.com");
        let innerFailed = do {
          dbTransaction(db, fn (): Void throws Bubble {
            addUser(db, "inner@example.com");
            db.exec("INSERT INTO nope VALUES (1)", []);
          });
          false
        } orelse true;
        assert(innerFailed) { "inner should have failed" };
      });
      expectText(test, column(db, "SELECT email FROM users", "email"), "outer@example.com");
    }

## DbRow

    let rowOf(cols: List<String>, cells: List<String?>): DbRow { new DbRow(cols, cells) }

    let nullableRow(): DbRow {
      let cells = new ListBuilder<String?>();
      cells.add("hello");
      cells.add(null);
      cells.add("42");
      cells.add("-7");
      cells.add("1");
      cells.add("0");
      cells.add("true");
      cells.add("false");
      cells.add("2.5");
      cells.add("[\"a\",\"b\",\"c\"]");
      cells.add("[3,1,2]");
      cells.add("{\"k\": [1, 2]}");
      cells.add("not json");
      cells.add("12x");
      rowOf(
        ["s", "n", "i", "neg", "t", "f", "tt", "ff", "fl", "sl", "il", "js", "bad", "badint"],
        cells.toList(),
      )
    }

    let bubbles(r: DbRow, which: String): Boolean {
      if (which == "str") { return do { r.str("n"); false } orelse true; }
      if (which == "missing") { return do { r.str("nope"); false } orelse true; }
      if (which == "int") { return do { r.int("s"); false } orelse true; }
      if (which == "intnull") { return do { r.int("n"); false } orelse true; }
      if (which == "badint") { return do { r.int("badint"); false } orelse true; }
      if (which == "bool") { return do { r.bool("i"); false } orelse true; }
      if (which == "float") { return do { r.float("s"); false } orelse true; }
      if (which == "json") { return do { r.json("bad"); false } orelse true; }
      if (which == "strlist") { return do { r.strList("js"); false } orelse true; }
      if (which == "strlistint") { return do { r.strList("il"); false } orelse true; }
      if (which == "intlist") { return do { r.intList("sl"); false } orelse true; }
      false
    }

    test("str and strOrNull") { test =>
      let r = nullableRow();
      expectText(test, r.str("s"), "hello");
      expectTrue(test, r.strOrNull("n") == null, "null cell");
      expectTrue(test, r.isNull("n"), "isNull");
      expectFalse(test, r.isNull("s"), "not isNull");
      expectTrue(test, bubbles(r, "str"), "str of NULL bubbles");
      expectTrue(test, bubbles(r, "missing"), "an unknown column bubbles");
      expectTrue(test, r.has("s") && !r.has("nope"), "has");
    }

    test("int and intOrNull") { test =>
      let r = nullableRow();
      expectInt(test, r.int("i"), 42);
      expectInt(test, r.int("neg"), -7);
      expectInt(test, r.int("t"), 1);
      expectTrue(test, r.intOrNull("n") == null, "NULL");
      expectTrue(test, r.intOrNull("i") == 42, "42");
      expectTrue(test, bubbles(r, "int"), "text is not an integer");
      expectTrue(test, bubbles(r, "badint"), "12x is not an integer");
      expectTrue(test, bubbles(r, "intnull"), "int of NULL bubbles");
    }

    test("a minus one is still an integer") { test =>
      let r = rowOf(["a"], ["-1"]);
      expectInt(test, r.int("a"), -1);
      let f = rowOf(["a"], ["-1.0"]);
      expectTrue(test, f.float("a") == -1.0, "float -1");
    }

    test("bool takes 1 0 true false and nothing else") { test =>
      let r = nullableRow();
      expectTrue(test, r.bool("t"), "1");
      expectFalse(test, r.bool("f"), "0");
      expectTrue(test, r.bool("tt"), "true");
      expectFalse(test, r.bool("ff"), "false");
      expectTrue(test, bubbles(r, "bool"), "42 is not a boolean");
    }

    test("float") { test =>
      let r = nullableRow();
      expectTrue(test, r.float("fl") == 2.5, "2.5");
      expectTrue(test, r.float("i") == 42.0, "an integer text is a float");
      expectTrue(test, bubbles(r, "float"), "text is not a float");
    }

    test("strList and intList parse a JSON array column") { test =>
      let r = nullableRow();
      expectText(test, joinStrings(r.strList("sl")), "a,b,c");
      expectText(test, r.intList("il").join(",") { (n: Int): String => n.toString() }, "3,1,2");
      expectInt(test, r.strList("n").length, 0);
      expectInt(test, r.intList("n").length, 0);
      expectTrue(test, bubbles(r, "strlist"), "an object is not an array of strings");
      expectTrue(test, bubbles(r, "strlistint"), "numbers are not strings");
      expectTrue(test, bubbles(r, "intlist"), "strings are not numbers");
    }

    test("json returns the tree, null for NULL, a bubble for text that is not JSON") { test =>
      let r = nullableRow();
      expectTrue(test, r.json("n") == null, "NULL");
      expectTrue(test, r.json("js") != null, "an object parses");
      expectTrue(test, bubbles(r, "json"), "not json");
    }

    test("a JSON array stored by the database reads back") { test =>
      let db = dbOpen(":memory:");
      db.exec("INSERT INTO users (email, seen_tours) VALUES ('a@example.com', $1)", ["[\"landing\",\"work\"]"]);
      let row = db.one("SELECT seen_tours FROM users", []);
      expectTrue(test, row != null, "row");
      if (row != null) { expectText(test, joinStrings(row.strList("seen_tours")), "landing,work"); }
      db.exec("INSERT INTO stack_steps (folder_id, work_id, ordinal, requires) SELECT 1, 1, 1, '[2,3]' WHERE 0", []);
    }

## Alloy

    test("dbStatement gives $1-style text and string params") { test =>
      let id = 7;
      let name = "O'Brien";
      let p = dbStatement(sql"SELECT * FROM users WHERE id = ${id} AND email = ${name}");
      expectText(test, p.key, "SELECT * FROM users WHERE id = $1 AND email = $2");
      expectInt(test, p.value.length, 2);
      expectText(test, orNull(p.value[0]), "7");
      expectText(test, orNull(p.value[1]), "O'Brien");
    }

    test("a statement from dbStatement runs") { test =>
      let db = dbOpen(":memory:");
      let uid = addUser(db, "who@example.com");
      let email = "WHO@example.com";
      let p = dbStatement(sql"SELECT id FROM users WHERE id = ${uid} AND email = ${email}");
      let row = db.one(p.key, p.value);
      expectTrue(test, row != null, "found by integer parameter and NOCASE text");
      if (row != null) { expectInt(test, row.int("id"), uid); }
    }

## The Folders statements against this schema

`core`'s `folders.temper.md` was written for Postgres. Each statement it
builds is run here, against the migrated schema, with a user and a folder
and a work in place, to see whether the SQL text is SQLite's. A statement
that fails is listed by name in `foldersFailures`, and the list is asserted
to be empty. Seven of them once failed together, because `now` in
`folders.temper.md` was Postgres's `date_trunc('second', now() at time zone
'utc')`; it is now `strftime('%Y-%m-%d %H:%M:%S','now')`.

    let paramText(s: Statement): List<String?> {
      let out = new ListBuilder<String?>();
      for (let p of s.params) { out.add(p.text); }
      out.toList()
    }

    let seeded(): Db throws Bubble {
      let db = dbOpen(":memory:");
      let uid = addUser(db, "a@example.com");
      addWork(db, uid, "A draft", "slug-1");
      db.exec("INSERT INTO folders (name, user_id, slug, published_at) VALUES ('F', 1, 'fs', '2026-01-01 00:00:00')", []);
      db
    }

Runs one statement, answers "" when SQLite accepts it, and the failing SQL
text otherwise.

    let attempt(label: String, s: Statement): String throws Bubble {
      let db = seeded();
      let ok = do { db.query(s.text, paramText(s)); true } orelse false;
      if (ok) { "" } else { label }
    }

    let preparedStatement(p: Prepared): Statement {
      let s = p.statement;
      if (s != null) { s } else { new Statement("", []) }
    }

    let o = 1.toInt64();

    let foldersFailures(): List<String> throws Bubble {
      let all = [
        attempt("listFolders", listFolders(o)),
        attempt("getFolder", getFolder(o, o)),
        attempt("foldersByIds", foldersByIds([o, o])),
        attempt("folderByName", folderByName(o, "F")),
        attempt("sibling root", sibling(o, "F", null)),
        attempt("sibling child", sibling(o, "F", o)),
        attempt("createFolder", preparedStatement(createFolder(o, "New", null))),
        attempt("createFolder child", preparedStatement(createFolder(o, "New", o))),
        attempt("renameFolder", preparedStatement(renameFolder(o, o, "Renamed"))),
        attempt("moveFolder", moveFolder(o, o, null)),
        attempt("deleteFolder 1", deleteFolder(o, null)[0]),
        attempt("deleteFolder 2", deleteFolder(o, null)[0]),
        attempt("deleteFolder 3", deleteFolder(o, null)[1]),
        attempt("moveWork", moveWork(o, o, o)),
        attempt("unfiledCount", unfiledCount(o)),
        attempt("looseWorkCollections", looseWorkCollections(o)),
        attempt("fileWorks", fileWorks([o], o)),
        attempt("publish", publish(o, o, "a-slug")),
        attempt("unpublish", unpublish(o, o)),
        attempt("publishedBySlug", publishedBySlug("fs")),
        attempt("published", published()),
        attempt("slugTaken", slugTaken("fs")),
      ];
      let failed = new ListBuilder<String>();
      var i = 0;
      while (i < all.length) {
        if (all[i] != "") { failed.add(all[i]); }
        i += 1;
      }
      failed.toList()
    }

    test("every Folders statement from core runs on SQLite") { test =>
      expectText(
        test,
        joinStrings(foldersFailures()),
        "",
      );
    }
