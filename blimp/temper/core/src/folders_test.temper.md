# Tests for the folder statements

These pin the SQL Alloy builds for `Marginalia.Folders`, and the kind each
parameter carries. The app's own tests run these statements against
Postgres; these say what is sent. Each check runs in a helper that takes
the `test`, so the frontend cannot work it out while compiling.

    let paramKinds(s: Statement): String {
      s.params.join(",") { (p): String => "${p.kind}:${p.text}" }
    }

    let statementIs(test: Test, s: Statement, text: String, params: String): Void {
      expectText(test, s.text, text);
      expectText(test, paramKinds(s), params);
    }

    let refused(test: Test, p: Prepared, want: String): Void {
      let isRefusal = p.statement == null;
      assert(isRefusal) { "expected a refusal" }
      expectText(test, p.errors.join("; ") { (e): String => "${e.field} ${e.message}" }, want);
    }

    test("a folder is looked up by owner and id, both bound as integers") { test =>
      statementIs(
        test,
        getFolder(7i64, 3i64),
        "SELECT id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at FROM folders WHERE user_id = $1 AND id = $2",
        "int:7,int:3",
      );
    }

    test("siblings sort by lower(name), selected so Alloy can order by it") { test =>
      statementIs(
        test,
        listFolders(7i64),
        "SELECT folders.id, folders.name, folders.published_at, folders.slug, folders.user_id, folders.parent_id, folders.inserted_at, folders.updated_at, lower(name) AS name_key FROM folders WHERE user_id = $1 ORDER BY name_key ASC, id ASC",
        "int:7",
      );
    }

    test("a new folder's name is trimmed and its timestamps are the database's") { test =>
      let p = createFolder(7i64, "  Notes ", 4i64);
      statementIs(
        test,
        p.statement as Statement orelse panic(),
        "INSERT INTO folders (name, parent_id, user_id, inserted_at, updated_at) VALUES ($1, $2, $3, date_trunc('second', now() at time zone 'utc'), date_trunc('second', now() at time zone 'utc')) RETURNING id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at",
        "text:Notes,int:4,int:7",
      );
    }

    test("a blank name is refused before any SQL") { test =>
      refused(test, createFolder(7i64, "   ", null), "name is required");
    }

    test("a name over 80 characters is refused") { test =>
      refused(test, renameFolder(7i64, 3i64, repeated("x", 81)), "name must be between 1 and 80 characters");
    }

    test("moving a folder to the root sets its parent to NULL, not a parameter") { test =>
      statementIs(
        test,
        moveFolder(7i64, 3i64, null),
        "UPDATE folders SET parent_id = NULL, updated_at = date_trunc('second', now() at time zone 'utc') WHERE user_id = $1 AND id = $2 RETURNING id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at",
        "int:7,int:3",
      );
    }

    test("deleting a folder lifts its drafts and children before it goes") { test =>
      let steps = deleteFolder(3i64, 1i64);
      assert(steps.length == 3);
      statementIs(test, steps[0], "UPDATE works SET folder_id = $1 WHERE folder_id = $2", "int:1,int:3");
      statementIs(test, steps[1], "UPDATE folders SET parent_id = $1 WHERE parent_id = $2", "int:1,int:3");
    }

    test("filing drafts binds each id") { test =>
      let ids = new ListBuilder<Int64>();
      ids.add(1i64);
      ids.add(2i64);
      statementIs(test, fileWorks(ids.toList(), 5i64), "UPDATE works SET folder_id = $1 WHERE id IN ($2, $3)", "int:5,int:1,int:2");
    }

    test("a slug is data, never SQL") { test =>
      statementIs(
        test,
        publishedBySlug("x'; DROP TABLE folders; --"),
        "SELECT id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at FROM folders WHERE slug = $1 AND published_at IS NOT NULL",
        "text:x'; DROP TABLE folders; --",
      );
    }
