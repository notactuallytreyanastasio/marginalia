# Tests for folders

The assertions of `test/marginalia/folders_test.exs`, ported, then the cases
the Elixir left to the database (name clashes, slugs) and the two pure
helpers from `Import.Bulk` (`foldersNameFor`, `foldersInNameOrder`). Every
check runs in a helper that takes the `test`, or the frontend evaluates it
while compiling. Every database is `:memory:` and migrated. Users and drafts
are inserted directly: `accounts` and `works` are written separately.

    let { Db, dbOpen } = import("db/src");
    let { User, Scope, scopeFor, userColumns } = import("accounts/src");
    let { sysByteLength, sysGraphemeTake } = import("sys/src");

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

    let optText(s: String?): String {
      if (s != null) { s } else { "nil" }
    }

    let optInt(n: Int?): String {
      if (n != null) { n.toString() } else { "nil" }
    }

    let repeatedText(word: String, n: Int): String {
      let parts = new ListBuilder<String>();
      var i = 0;
      while (i < n) { parts.add(word); i += 1; }
      parts.toList().join("") { (p: String): String => p }
    }

    let joined(xs: List<String>): String {
      xs.join(",") { (x: String): String => x }
    }

## Fixtures

    let userOf(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { scopeFor(User.fromRow(row)) } else { bubble() }
    }

    let draft(db: Db, s: Scope, title: String): Int throws Bubble {
      let slug = "slug-${title}-${s.userId.toString()}";
      db.insert(
        "INSERT INTO works (user_id, title, body, slug, word_count) VALUES ($1, $2, 'body', $3, 60)",
        [s.userId.toString(), title, slug],
      )
    }

    let placed(db: Db, s: Scope, title: String, collection: String, role: String): Int throws Bubble {
      let id = draft(db, s, title);
      db.exec(
        "UPDATE works SET collection = $1, collection_role = $2 WHERE id = $3",
        [collection, role, id.toString()],
      );
      id
    }

    let folderIn(db: Db, s: Scope, name: String, parent: Folder?): Folder throws Bubble {
      let parentId = if (parent != null) { parent.id } else { null };
      let r = foldersCreateFolder(db, s, name, parentId);
      let f = r.folder;
      if (f != null) { f } else { bubble() }
    }

    let folderAt(db: Db, s: Scope, name: String): Folder throws Bubble {
      folderIn(db, s, name, null)
    }

    let workFolder(db: Db, workId: Int): String throws Bubble {
      let row = db.one("SELECT folder_id FROM works WHERE id = $1", [workId.toString()]);
      if (row != null) { optText(row.strOrNull("folder_id")) } else { "gone" }
    }

A tree as one line: each node's drafts by title, then each child folder as
`[name#count ...]`.

    let render(node: FolderNode): String {
      let parts = new ListBuilder<String>();
      parts.add(joined(node.works.map { (w: FolderWork): String => w.title }));
      for (let kid of node.folders) {
        let f = kid.folder;
        let name = if (f != null) { f.name } else { "?" };
        parts.add("[${name}#${kid.count.toString()} ${render(kid)}]");
      }
      joined(parts.toList())
    }

    let names(fs: List<Folder>): String {
      joined(fs.map { (f: Folder): String => f.name })
    }

    let bubbled(db: Db, s: Scope, id: Int): Boolean {
      do {
        foldersDeleteFolder(db, s, id);
        false
      } orelse true
    }

## The tree

    test("a draft starts outside every folder and the tree says so") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let w = draft(db, me, "Loose page");
      let tree = foldersTree(db, me);
      expectInt(test, tree.folders.length, 0);
      expectInt(test, tree.works.length, 1);
      expectInt(test, tree.works[0].id, w);
      expectText(test, tree.works[0].title, "Loose page");
    }

    test("filing a draft moves it into the folder's node, not a copy of it") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let w = draft(db, me, "Loose page");
      let f = folderAt(db, me, "Case files");
      let r = foldersMoveWork(db, me, w, f.id);
      expectTrue(test, r.ok, "filed");
      let tree = foldersTree(db, me);
      expectInt(test, tree.works.length, 0);
      expectInt(test, tree.folders.length, 1);
      let node = tree.folders[0];
      let nf = node.folder;
      expectInt(test, if (nf != null) { nf.id } else { -1 }, f.id);
      expectInt(test, node.works.length, 1);
      expectInt(test, node.works[0].id, w);
    }

    test("a folder's count includes what is buried below it") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let outer = folderAt(db, me, "Outer");
      let inner = folderIn(db, me, "Inner", outer);
      foldersMoveWork(db, me, draft(db, me, "One"), outer.id);
      foldersMoveWork(db, me, draft(db, me, "Two"), inner.id);
      foldersMoveWork(db, me, draft(db, me, "Three"), inner.id);
      let tree = foldersTree(db, me);
      expectInt(test, tree.folders.length, 1);
      expectInt(test, tree.folders[0].count, 3);
      expectInt(test, tree.folders[0].folders.length, 1);
      expectInt(test, tree.folders[0].folders[0].count, 2);
      expectInt(test, foldersTreeTotal(tree), 3);
      expectText(test, render(tree), ",[Outer#3 One,[Inner#2 Three,Two]]");
    }

    test("dropping a draft on the root unfiles it") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderAt(db, me, "Case files");
      let w = draft(db, me, "Filed");
      foldersMoveWork(db, me, w, f.id);
      let r = foldersMoveWork(db, me, w, null);
      expectTrue(test, r.ok, "unfiled");
      expectText(test, optInt(r.placedIn), "nil");
      let tree = foldersTree(db, me);
      expectInt(test, tree.works.length, 1);
      expectInt(test, tree.works[0].id, w);
    }

    test("drafts come newest first and folders in lower-case name order") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      draft(db, me, "first");
      draft(db, me, "second");
      draft(db, me, "third");
      folderAt(db, me, "banana");
      folderAt(db, me, "Apple");
      folderAt(db, me, "cherry");
      let tree = foldersTree(db, me);
      expectText(test, joined(tree.works.map { (w: FolderWork): String => w.title }), "third,second,first");
      expectText(test, names(foldersListFolders(db, me)), "Apple,banana,cherry");
    }

    test("an empty tree has a root with no folder and a count of zero") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let tree = foldersTree(db, me);
      expectTrue(test, tree.folder == null, "the root has no folder");
      expectInt(test, tree.count, 0);
    }

## Cycles

    test("a folder cannot be dropped into itself") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderAt(db, me, "Case files");
      let r = foldersMoveFolder(db, me, f.id, f.id);
      expectFalse(test, r.ok, "refused");
      expectText(test, optText(r.error), "cycle");
    }

    test("a folder cannot be dropped into its own descendant, and the tree is unchanged") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let outer = folderAt(db, me, "Outer");
      let inner = folderIn(db, me, "Inner", outer);
      let deeper = folderIn(db, me, "Deeper", inner);
      let r = foldersMoveFolder(db, me, outer.id, deeper.id);
      expectText(test, optText(r.error), "cycle");
      let tree = foldersTree(db, me);
      expectInt(test, tree.folders.length, 1);
      expectText(test, render(tree), ",[Outer#0 ,[Inner#0 ,[Deeper#0 ]]]");
    }

    test("a folder may move under a sibling, and to the root with null") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let a = folderAt(db, me, "A");
      let b = folderAt(db, me, "B");
      let r = foldersMoveFolder(db, me, b.id, a.id);
      expectTrue(test, r.ok, "moved");
      expectText(test, render(foldersTree(db, me)), ",[A#0 ,[B#0 ]]");
      let back = foldersMoveFolder(db, me, b.id, null);
      expectTrue(test, back.ok, "moved back");
      expectText(test, render(foldersTree(db, me)), ",[A#0 ],[B#0 ]");
    }

    test("descendant asks whether an id sits somewhere under another") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let a = folderAt(db, me, "A");
      let b = folderIn(db, me, "B", a);
      let c = folderIn(db, me, "C", b);
      expectTrue(test, foldersIsDescendant(db, me, c.id, a.id), "c under a");
      expectTrue(test, foldersIsDescendant(db, me, b.id, a.id), "b under a");
      expectFalse(test, foldersIsDescendant(db, me, a.id, c.id), "a not under c");
      expectFalse(test, foldersIsDescendant(db, me, a.id, a.id), "not under itself");
      expectFalse(test, foldersIsDescendant(db, me, null, a.id), "nil is under nothing");
    }

## Names

    test("two siblings may not share a name, but cousins may") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let outer = folderAt(db, me, "Outer");
      folderIn(db, me, "Notes", outer);
      let again = foldersCreateFolder(db, me, "Notes", outer.id);
      expectFalse(test, again.ok, "refused");
      expectText(test, optText(again.error), "invalid");
      expectText(test, again.errors[0].field, "name");
      expectText(test, again.errors[0].message, "there is already a folder with that name here");
      expectText(test, foldersFirstError(again), "name there is already a folder with that name here");
      let cousin = foldersCreateFolder(db, me, "Notes", null);
      expectTrue(test, cousin.ok, "same name at the root is fine");
    }

    test("two roots may not share a name either") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      folderAt(db, me, "Notes");
      let again = foldersCreateFolder(db, me, "Notes", null);
      expectFalse(test, again.ok, "refused");
      expectText(test, again.errors[0].message, "there is already a folder with that name here");
    }

    test("names are case sensitive and trimmed") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      folderAt(db, me, "Notes");
      expectTrue(test, foldersCreateFolder(db, me, "notes", null).ok, "case differs");
      let padded = foldersCreateFolder(db, me, "  Spaced  ", null);
      let f = padded.folder;
      expectText(test, if (f != null) { f.name } else { "none" }, "Spaced");
      expectFalse(test, foldersCreateFolder(db, me, "  Notes ", null).ok, "trimmed, so a clash");
    }

    test("a blank name is refused with the Elixir's message") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let r = foldersCreateFolder(db, me, "   ", null);
      expectFalse(test, r.ok, "refused");
      expectText(test, foldersFirstError(r), "name can't be blank");
      expectInt(test, foldersListFolders(db, me).length, 0);
    }

    test("a name over 80 characters is refused, 80 is not") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let r = foldersCreateFolder(db, me, repeatedText("x", 81), null);
      expectFalse(test, r.ok, "81 refused");
      expectText(test, foldersFirstError(r), "name should be at most 80 character(s)");
      expectTrue(test, foldersCreateFolder(db, me, repeatedText("x", 80), null).ok, "80 fine");
    }

    test("rename changes the name and keeps the place") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let outer = folderAt(db, me, "Outer");
      let inner = folderIn(db, me, "Inner", outer);
      let r = foldersRenameFolder(db, me, inner.id, " Renamed ");
      expectTrue(test, r.ok, "renamed");
      let f = r.folder;
      expectText(test, if (f != null) { f.name } else { "none" }, "Renamed");
      expectText(test, optInt(if (f != null) { f.parentId } else { null }), outer.id.toString());
    }

    test("rename to a sibling's name is an error on name; to its own name is fine") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      folderAt(db, me, "A");
      let b = folderAt(db, me, "B");
      let clash = foldersRenameFolder(db, me, b.id, "A");
      expectFalse(test, clash.ok, "refused");
      expectText(test, foldersFirstError(clash), "name there is already a folder with that name here");
      expectTrue(test, foldersRenameFolder(db, me, b.id, "B").ok, "same name");
      expectText(test, foldersFirstError(foldersRenameFolder(db, me, b.id, "")), "name can't be blank");
    }

    test("rename of a folder that is not yours is not_found") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = folderAt(db, other, "Theirs");
      expectText(test, optText(foldersRenameFolder(db, me, theirs.id, "Mine").error), "not_found");
      expectText(test, optText(foldersRenameFolder(db, me, 9999, "Mine").error), "not_found");
    }

    test("moving a folder where its name already is refuses, as a name error") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let a = folderAt(db, me, "A");
      folderIn(db, me, "Notes", a);
      let rootNotes = folderAt(db, me, "Notes");
      let r = foldersMoveFolder(db, me, rootNotes.id, a.id);
      expectFalse(test, r.ok, "refused");
      expectText(test, foldersFirstError(r), "name there is already a folder with that name here");
    }

## Deleting

    test("deleting a folder keeps the drafts and lifts them one level") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let outer = folderAt(db, me, "Outer");
      let inner = folderIn(db, me, "Inner", outer);
      let w = draft(db, me, "Buried");
      foldersMoveWork(db, me, w, inner.id);
      let grand = folderIn(db, me, "Grandchild", inner);
      let r = foldersDeleteFolder(db, me, inner.id);
      expectTrue(test, r.ok, "deleted");
      expectText(test, workFolder(db, w), outer.id.toString());
      let tree = foldersTree(db, me);
      expectInt(test, tree.folders.length, 1);
      let node = tree.folders[0];
      expectInt(test, node.works.length, 1);
      expectInt(test, node.works[0].id, w);
      expectInt(test, node.folders.length, 1);
      let g = node.folders[0].folder;
      expectInt(test, if (g != null) { g.id } else { -1 }, grand.id);
    }

    test("deleting a root folder drops its contents to the root") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderAt(db, me, "Case files");
      let w = draft(db, me, "Filed");
      foldersMoveWork(db, me, w, f.id);
      expectTrue(test, foldersDeleteFolder(db, me, f.id).ok, "deleted");
      let tree = foldersTree(db, me);
      expectInt(test, tree.folders.length, 0);
      expectInt(test, tree.works.length, 1);
      expectInt(test, tree.works[0].id, w);
    }

    test("a delete that would collide on a lifted name rolls back whole") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let outer = folderAt(db, me, "Outer");
      folderIn(db, me, "X", outer);
      let inner = folderIn(db, me, "Inner", outer);
      folderIn(db, me, "X", inner);
      let w = draft(db, me, "Held");
      foldersMoveWork(db, me, w, inner.id);
      expectTrue(test, bubbled(db, me, inner.id), "the unique index raises");
      expectText(test, workFolder(db, w), inner.id.toString());
      expectTrue(test, foldersGetFolderOrNull(db, me, inner.id) != null, "inner is still there");
      expectFalse(test, db.inTransaction(), "closed");
    }

## Who may do what

    test("another writer's folder is not a place you can put anything") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = folderAt(db, other, "Theirs");
      let mine = folderAt(db, me, "Mine");
      let w = draft(db, me, "Mine too");
      foldersMoveWork(db, me, w, mine.id);
      let moved = foldersMoveWork(db, me, w, theirs.id);
      expectTrue(test, moved.ok, "not an error");
      expectText(test, optInt(moved.placedIn), "nil");
      expectText(test, workFolder(db, w), "nil");
      let movedFolder = foldersMoveFolder(db, me, mine.id, theirs.id);
      expectTrue(test, movedFolder.ok, "not an error");
      let mf = movedFolder.folder;
      expectText(test, optInt(if (mf != null) { mf.parentId } else { -1 }), "nil");
      expectInt(test, foldersTree(db, other).works.length, 0);
      expectInt(test, foldersTree(db, other).folders[0].count, 0);
    }

    test("another writer's draft cannot be filed by me, nor their folder deleted") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = draft(db, other, "Theirs");
      let mine = folderAt(db, me, "Mine");
      expectText(test, optText(foldersMoveWork(db, me, theirs, mine.id).error), "not_found");
      expectText(test, workFolder(db, theirs), "nil");
      let nope = folderAt(db, other, "Nope");
      expectText(test, optText(foldersDeleteFolder(db, me, nope.id).error), "not_found");
      expectTrue(test, foldersGetFolderOrNull(db, other, nope.id) != null, "still theirs");
    }

    test("a folder of another writer is not got, and the bang form bubbles") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = folderAt(db, other, "Theirs");
      expectTrue(test, foldersGetFolderOrNull(db, me, theirs.id) == null, "null");
      let threw = do { foldersGetFolder(db, me, theirs.id); false } orelse true;
      expectTrue(test, threw, "bubbles");
      expectText(test, foldersGetFolder(db, other, theirs.id).name, "Theirs");
    }

    test("two writers may each have a folder of the same name") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      folderAt(db, me, "Notes");
      expectTrue(test, foldersCreateFolder(db, other, "Notes", null).ok, "fine");
    }

    test("a forged parent on create lands the folder at the root") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = folderAt(db, other, "Theirs");
      let r = foldersCreateFolder(db, me, "Mine", theirs.id);
      let f = r.folder;
      expectTrue(test, r.ok, "created");
      expectText(test, optInt(if (f != null) { f.parentId } else { -1 }), "nil");
    }

    test("move_work to a missing work is not_found") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      expectText(test, optText(foldersMoveWork(db, me, 424242, null).error), "not_found");
    }

    test("moving a draft reports where it landed") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderAt(db, me, "F");
      let w = draft(db, me, "W");
      expectText(test, optInt(foldersMoveWork(db, me, w, f.id).placedIn), f.id.toString());
    }

    test("ids from forms: blank, root and junk are no folder") { test =>
      expectText(test, optInt(foldersParseId("12")), "12");
      expectText(test, optInt(foldersParseId(" 12 ")), "12");
      expectText(test, optInt(foldersParseId("")), "nil");
      expectText(test, optInt(foldersParseId("root")), "nil");
      expectText(test, optInt(foldersParseId("12abc")), "nil");
      expectText(test, optInt(foldersParseId("abc")), "nil");
      expectText(test, optInt(foldersParseId(null)), "nil");
    }

    test("folders are found by name for the importers, and two of a name are a bubble") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let a = folderAt(db, me, "A");
      let notes = folderIn(db, me, "Notes", a);
      let found = foldersFolderByName(db, me, "Notes");
      expectInt(test, if (found != null) { found.id } else { -1 }, notes.id);
      expectTrue(test, foldersFolderByName(db, me, "Nothing") == null, "none");
      folderAt(db, me, "Notes");
      let threw = do { foldersFolderByName(db, me, "Notes"); false } orelse true;
      expectTrue(test, threw, "ambiguous");
    }

    test("folders can be fetched by id, whoever owns them") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let a = folderAt(db, me, "A");
      let b = folderAt(db, other, "B");
      expectText(test, joined(foldersGetMany(db, [a.id, b.id]).map { (f: Folder): String => f.name }), "A,B");
      expectInt(test, foldersGetMany(db, []).length, 0);
    }

## Filing in bulk

    test("fileWorks files exactly the ids it is given") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderAt(db, me, "F");
      let a = draft(db, me, "a");
      let b = draft(db, me, "b");
      let c = draft(db, me, "c");
      expectInt(test, foldersFileWorks(db, [a, c], f.id), 2);
      expectText(test, workFolder(db, a), f.id.toString());
      expectText(test, workFolder(db, b), "nil");
      expectText(test, workFolder(db, c), f.id.toString());
      expectInt(test, foldersFileWorks(db, [], f.id), 0);
    }

## Backfilling from collections

    test("each collection becomes a folder under one parent") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      placed(db, me, "Opinion", "Miller v. Alabama", "opinion");
      placed(db, me, "Dissent", "Miller v. Alabama", "dissent");
      placed(db, me, "Brief", "Dauch", "opinion");
      let loose = draft(db, me, "A loose page");
      expectInt(test, foldersUnfiledCount(db, me), 3);
      expectInt(test, foldersBackfill(db, me), 3);
      let tree = foldersTree(db, me);
      expectInt(test, tree.works.length, 1);
      expectInt(test, tree.works[0].id, loose);
      expectInt(test, tree.folders.length, 1);
      let cases = tree.folders[0];
      let cf = cases.folder;
      expectText(test, if (cf != null) { cf.name } else { "none" }, "Cases");
      expectInt(test, cases.count, 3);
      expectText(test, joined(cases.folders.map { (n: FolderNode): String =>
        let f = n.folder;
        if (f != null) { f.name } else { "?" }
      }), "Dauch,Miller v. Alabama");
      expectText(test, joined(cases.folders.map { (n: FolderNode): String => n.count.toString() }), "1,2");
      expectInt(test, foldersUnfiledCount(db, me), 0);
    }

    test("running it twice files nothing the second time") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      placed(db, me, "Opinion", "Miller v. Alabama", "opinion");
      expectInt(test, foldersBackfill(db, me), 1);
      expectInt(test, foldersBackfill(db, me), 0);
      expectInt(test, foldersListFolders(db, me).length, 2);
    }

    test("it reuses folders that are already there rather than failing on the name") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let cases = folderAt(db, me, "Cases");
      folderIn(db, me, "Miller v. Alabama", cases);
      placed(db, me, "Opinion", "Miller v. Alabama", "opinion");
      expectInt(test, foldersBackfill(db, me), 1);
      expectInt(test, foldersListFolders(db, me).length, 2);
    }

    test("a draft the writer already filed is left where they put it") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let w = placed(db, me, "Opinion", "Miller v. Alabama", "opinion");
      let mine = folderAt(db, me, "Reading pile");
      foldersMoveWork(db, me, w, mine.id);
      expectInt(test, foldersBackfill(db, me), 0);
      expectText(test, workFolder(db, w), mine.id.toString());
    }

    test("with no collections anywhere it makes no folders at all") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      draft(db, me, "A loose page");
      expectInt(test, foldersBackfill(db, me), 0);
      expectInt(test, foldersListFolders(db, me).length, 0);
    }

    test("it never reaches into another writer's drafts") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = placed(db, other, "Theirs", "Miller v. Alabama", "opinion");
      placed(db, me, "Mine", "Miller v. Alabama", "dissent");
      expectInt(test, foldersBackfill(db, me), 1);
      expectInt(test, foldersListFolders(db, other).length, 0);
      expectText(test, workFolder(db, theirs), "nil");
    }

    test("a null parent name files collections straight at the root") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      placed(db, me, "Opinion", "Miller v. Alabama", "opinion");
      expectInt(test, foldersBackfillFromCollections(db, me, null), 1);
      expectText(test, render(foldersTree(db, me)), ",[Miller v. Alabama#1 Opinion]");
    }

    test("loose collections lists only unfiled drafts that name one") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let a = placed(db, me, "A", "Dauch", "opinion");
      draft(db, me, "plain");
      let filed = placed(db, me, "B", "Dauch", "dissent");
      foldersMoveWork(db, me, filed, folderAt(db, me, "F").id);
      let loose = foldersLooseWorkCollections(db, me);
      expectInt(test, loose.length, 1);
      expectInt(test, loose[0].id, a);
      expectText(test, optText(loose[0].collection), "Dauch");
    }

## Publishing

    test("publishing sets the time and the slug, and unpublishing keeps the slug") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderAt(db, me, "My Stack");
      expectTrue(test, f.publishedAt == null, "private to begin with");
      let r = foldersPublish(db, me, f.id, "my-stack");
      expectTrue(test, r.ok, "published");
      let p = r.folder;
      expectText(test, optText(if (p != null) { p.slug } else { null }), "my-stack");
      expectInt(test, sysByteLength(optText(if (p != null) { p.publishedAt } else { null })), 19);
      let found = foldersPublishedBySlug(db, "my-stack");
      expectInt(test, if (found != null) { found.id } else { -1 }, f.id);
      let un = foldersUnpublish(db, me, f.id);
      let u = un.folder;
      expectTrue(test, un.ok, "unpublished");
      expectText(test, optText(if (u != null) { u.publishedAt } else { "x" }), "nil");
      expectText(test, optText(if (u != null) { u.slug } else { null }), "my-stack");
      expectTrue(test, foldersPublishedBySlug(db, "my-stack") == null, "gone from the public site");
    }

    test("the slug is minted once: rename and republish keep the link that was sent") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderAt(db, me, "Old Name");
      foldersPublish(db, me, f.id, "old-name");
      foldersRenameFolder(db, me, f.id, "New Name");
      foldersUnpublish(db, me, f.id);
      let again = foldersPublish(db, me, f.id, "new-name");
      let a = again.folder;
      expectText(test, optText(if (a != null) { a.slug } else { null }), "old-name");
    }

    test("published lists every published folder, any owner") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let a = folderAt(db, me, "A");
      let b = folderAt(db, other, "B");
      folderAt(db, me, "Private");
      foldersPublish(db, me, a.id, "a");
      foldersPublish(db, other, b.id, "b");
      expectInt(test, foldersPublished(db).length, 2);
      foldersUnpublish(db, me, a.id);
      expectText(test, names(foldersPublished(db)), "B");
    }

    test("publish and unpublish check ownership") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let theirs = folderAt(db, other, "Theirs");
      expectText(test, optText(foldersPublish(db, me, theirs.id, "t").error), "not_found");
      expectText(test, optText(foldersUnpublish(db, me, theirs.id).error), "not_found");
      expectTrue(test, foldersPublishedBySlug(db, "t") == null, "nothing published");
    }

    test("a slug another folder holds is slug_taken") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let a = folderAt(db, me, "A");
      let b = folderAt(db, other, "B");
      foldersPublish(db, me, a.id, "same");
      expectTrue(test, foldersSlugTaken(db, "same"), "taken");
      expectFalse(test, foldersSlugTaken(db, "free"), "free");
      expectText(test, optText(foldersPublish(db, other, b.id, "same").error), "slug_taken");
    }

    test("only the owner publishes, by name, and the slug comes from the name") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let other = userOf(db, "b@example.com");
      let f = folderAt(db, me, "Hello, World!");
      expectText(test, optText(foldersPublishAsOwner(db, me, null, f.id).error), "not_owner");
      expectText(test, optText(foldersPublishAsOwner(db, me, other.user, f.id).error), "not_owner");
      let r = foldersPublishAsOwner(db, me, me.user, f.id);
      expectTrue(test, r.ok, "published");
      let p = r.folder;
      expectText(test, optText(if (p != null) { p.slug } else { null }), "hello-world");
      expectText(test, optText(foldersPublishAsOwner(db, me, me.user, 4242).error), "not_found");
    }

    test("a minted slug is lower-case ascii, dashed, 60 long, and never empty") { test =>
      let db = dbOpen(":memory:");
      expectText(test, foldersMintSlug(db, "  A Stack -- of Things  "), "a-stack-of-things");
      expectText(test, foldersMintSlug(db, "!!!"), "stack");
      expectText(test, foldersMintSlug(db, ""), "stack");
      expectText(test, foldersMintSlug(db, "Ünï"), "n");
      expectInt(test, sysByteLength(foldersMintSlug(db, repeatedText("abc ", 40))), 60);
    }

    test("a second folder that slugs the same gets a four character suffix") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(db, "a@example.com");
      let f = folderAt(db, me, "Notes");
      foldersPublish(db, me, f.id, "notes");
      let slug = foldersMintSlug(db, "Notes");
      expectInt(test, sysByteLength(slug), 10);
      expectText(test, sysGraphemeTake(slug, 6), "notes-");
      expectFalse(test, foldersSlugTaken(db, slug), "free");
    }

## Names for an import

    test("a run of numbered files is named for what they share") { test =>
      let names = ["chapter-01", "chapter-02", "chapter-03", "chapter-04", "chapter-05", "chapter-06", "chapter-07"];
      expectText(test, foldersNameForAt(names, "2026-09-22 14:54:10"), "chapter");
    }

    test("one file is named for itself, less its number") { test =>
      expectText(test, foldersNameForAt(["chapter-01"], "2026-09-22 14:54:10"), "chapter");
      expectText(test, foldersNameForAt(["Notes 2"], "2026-09-22 14:54:10"), "Notes");
    }

    test("a short stem falls back to the time") { test =>
      expectText(test, foldersNameForAt(["alpha", "omega"], "2026-09-22 14:54:10"), "Imported 2026-09-22 14:54");
      expectText(test, foldersNameForAt(["ab 1", "ab 2"], "2026-09-22 14:54:10"), "Imported 2026-09-22 14:54");
      expectText(test, foldersNameForAt([], "2026-01-02 03:04:05"), "Imported 2026-01-02 03:04");
    }

    test("a shared prefix of three or more survives its trailing number") { test =>
      expectText(test, foldersNameForAt(["Part 1", "Part 2"], "2026-09-22 14:54:10"), "Part");
      expectText(test, foldersNameForAt(["Part 1 - Intro", "Part 2 - Body"], "2026-09-22 14:54:10"), "Part");
      expectText(test, foldersNameForAt(["a.b_c-1", "a.b_c-2"], "2026-09-22 14:54:10"), "a.b_c");
      expectText(test, foldersNameForAt(["The Method: one", "The Method: two"], "2026-09-22 14:54:10"), "The Method:");
    }

    test("the prefix is taken by grapheme, not byte") { test =>
      expectText(test, foldersNameForAt(["naïve 1", "naïve 2"], "2026-09-22 14:54:10"), "naïve");
    }

    test("the current time is the default fallback") { test =>
      let name = foldersNameFor(["alpha", "omega"]);
      expectText(test, sysGraphemeTake(name, 9), "Imported ");
      expectInt(test, sysByteLength(name), 25);
    }

    test("natural order puts 2 before 10") { test =>
      expectText(test, joined(foldersInNameOrder(["chapter-10", "chapter-2", "chapter-1"])), "chapter-1,chapter-2,chapter-10");
    }

    test("a drop that arrived backwards is read from the start") { test =>
      let backwards = ["chapter-07", "chapter-06", "chapter-05", "chapter-04", "chapter-03", "chapter-02", "chapter-01"];
      expectText(
        test,
        joined(foldersInNameOrder(backwards)),
        "chapter-01,chapter-02,chapter-03,chapter-04,chapter-05,chapter-06,chapter-07",
      );
    }

    test("case does not decide the order, and ties keep the order given") { test =>
      expectText(test, joined(foldersInNameOrder(["b", "A", "a", "B"])), "A,a,b,B");
    }

    test("digits sort before text, and leading zeros are only zeros") { test =>
      expectText(test, joined(foldersInNameOrder(["alpha", "10", "2"])), "2,10,alpha");
      expectText(test, joined(foldersInNameOrder(["a10", "a007", "a2", "a1"])), "a1,a2,a007,a10");
      expectText(test, joined(foldersInNameOrder(["x02", "x2", "x01"])), "x01,x02,x2");
    }

    test("a number too big for an integer still compares as a number") { test =>
      expectText(
        test,
        joined(foldersInNameOrder(["n99999999999999999999", "n100000000000000000000", "n9"])),
        "n9,n99999999999999999999,n100000000000000000000",
      );
    }

    test("a prefix sorts before what extends it") { test =>
      expectText(test, joined(foldersInNameOrder(["a1b", "a1", "a"])), "a,a1,a1b");
      expectInt(test, foldersInNameOrder([]).length, 0);
    }
