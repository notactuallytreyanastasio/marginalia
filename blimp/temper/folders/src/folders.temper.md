# Folders

Buckets of drafts. A folder is a *place*, not a property: a table with a
`parent_id`, not another string field on `works` beside `collection`. A
collection names something several drafts together *are*, and is public. A
folder is somewhere one writer put some drafts; it nests, and it is nobody
else's business.

Everything here is scoped by the scope's user id, the same discipline as
`works`: no function returns or moves a folder without checking who is asking.

The SQL is built in `core` (`folders.temper.md`, with Alloy) and comes back as
`Statement(text, params)`. This library is the half that runs it: it binds the
parameters as text, decodes rows into `Folder`, and decides what the Elixir
decided (a forged parent becomes the root, a cycle is refused, a name clash
is an error on `name`).

    let {
      Statement, Prepared, FieldError, Param,
      listFolders, getFolder, foldersByIds, folderByName, sibling, createFolder,
      renameFolder, moveFolder, deleteFolder, moveWork, unfiledCount,
      looseWorkCollections, fileWorks, publish, unpublish, publishedBySlug,
      published, slugTaken,
    } = import("core/src");
    let { Db, DbRow, dbTransaction } = import("db/src");
    let { Scope, User } = import("accounts/src");
    let {
      sysStringTrim, sysUtf8Downcase, sysJoin, sysGraphemeTake, sysGraphemeLength,
      sysRandomToken, sysUtcNow, sysByteLength,
    } = import("sys/src");

## Running a statement

Parameters are bound as text. A bool would be `"1"` or `"0"`; `core` binds
none today, but the rule is here so a later statement cannot bind
`"true"` to an INTEGER column.

    let foldersBind(p: Param): String {
      if (p.kind == "bool") {
        if (p.text == "true") { "1" } else { "0" }
      } else {
        p.text
      }
    }

    let foldersParams(s: Statement): List<String?> {
      let out = new ListBuilder<String?>();
      for (let p of s.params) { out.add(foldersBind(p)); }
      out.toList()
    }

    let foldersRows(db: Db, s: Statement): List<DbRow> throws Bubble {
      db.query(s.text, foldersParams(s))
    }

    let foldersFirstFolder(db: Db, s: Statement): Folder? throws Bubble {
      let rows = foldersRows(db, s);
      if (rows.length == 0) { null } else { Folder.fromRow(rows[0]) }
    }

    let foldersAllFolders(db: Db, s: Statement): List<Folder> throws Bubble {
      let out = new ListBuilder<Folder>();
      for (let row of foldersRows(db, s)) { out.add(Folder.fromRow(row)); }
      out.toList()
    }

    let foldersI64(x: Int?): Int64? {
      if (x != null) { x.toInt64() } else { null }
    }

    let foldersNothing(): List<FieldError> { [] }

    let foldersDone(folder: Folder?): FoldersResult {
      new FoldersResult(true, folder, null, null, foldersNothing())
    }

    let foldersFail(code: String): FoldersResult {
      new FoldersResult(false, null, null, code, foldersNothing())
    }

Ecto's wording for the two validations Alloy phrases differently. The
page shows `"name can't be blank"`; the unique-index message is
`"there is already a folder with that name here"`.

    let foldersMessage(m: String): String {
      if (m == "is required") {
        "can't be blank"
      } else if (m == "must be between 1 and 80 characters") {
        "should be at most 80 character(s)"
      } else {
        m
      }
    }

    let foldersInvalid(errors: List<FieldError>): FoldersResult {
      let fixed = errors.map { (e: FieldError): FieldError =>
        new FieldError(e.field, foldersMessage(e.message))
      };
      new FoldersResult(false, null, null, "invalid", fixed)
    }

    let foldersClashMessage = "there is already a folder with that name here";

    let foldersNameTaken(): FoldersResult {
      new FoldersResult(
        false, null, null, "invalid",
        [new FieldError("name", foldersClashMessage)],
      )
    }

The text a page flashes for a refused write: the first error as
`"<field> <message>"`, or the Elixir's fallback.

    export let foldersFirstError(result: FoldersResult): String {
      if (result.errors.length == 0) {
        "That did not work."
      } else {
        let e = result.errors[0];
        "${e.field} ${e.message}"
      }
    }

## Reading

Every folder this writer has, flat, in sibling order (`lower(name)`, then id).

    export let foldersListFolders(db: Db, scope: Scope): List<Folder> throws Bubble {
      foldersAllFolders(db, listFolders(scope.userId.toInt64()))
    }

A folder this user owns, or null. The Elixir's `get_folder`.

    export let foldersGetFolderOrNull(db: Db, scope: Scope, id: Int): Folder? throws Bubble {
      foldersFirstFolder(db, getFolder(scope.userId.toInt64(), id.toInt64()))
    }

The same, bubbling when there is no such folder: the `!` form.

    export let foldersGetFolder(db: Db, scope: Scope, id: Int): Folder throws Bubble {
      let f = foldersGetFolderOrNull(db, scope, id);
      if (f != null) { f } else { bubble() }
    }

Folders by id whoever owns them, for a preload (`preload(:folder)`).

    export let foldersGetMany(db: Db, ids: List<Int>): List<Folder> throws Bubble {
      if (ids.length == 0) { return []; }
      foldersAllFolders(db, foldersByIds(ids.map { (i: Int): Int64 => i.toInt64() }))
    }

The folder with exactly this name, anywhere in the user's tree, for the
importers. Two folders of one name under different parents are the Elixir's
`Repo.one` raising: so here too, a bubble.

    export let foldersFolderByName(db: Db, scope: Scope, name: String): Folder? throws Bubble {
      let rows = foldersRows(db, folderByName(scope.userId.toInt64(), name));
      if (rows.length == 0) {
        null
      } else if (rows.length == 1) {
        Folder.fromRow(rows[0])
      } else {
        bubble()
      }
    }

A parent the caller does not own is no parent at all: a forged id becomes
the root rather than a map of which ids exist.

    export let foldersOwnedParent(db: Db, scope: Scope, id: Int?): Int? throws Bubble {
      if (id != null) {
        let f = foldersGetFolderOrNull(db, scope, id);
        if (f != null) { f.id } else { null }
      } else {
        null
      }
    }

Forms send ids as text. `""` and `"root"` and anything that is not wholly an
integer are no folder; the Elixir's `cast_id` plus `owned_parent`.

    export let foldersParseId(text: String?): Int? {
      if (text != null) {
        let s = sysStringTrim(text);
        if (s == "" || s == "root") {
          null
        } else {
          var n = 0;
          let ok = do { n = s.toInt32(); true } orelse false;
          if (ok) { n } else { null }
        }
      } else {
        null
      }
    }

Whether `id` sits somewhere under `ancestorId`; null is under nothing. Walks
the owned chain upward.

    export let foldersIsDescendant(db: Db, scope: Scope, id: Int?, ancestorId: Int): Boolean throws Bubble {
      var cur = if (id != null) { id } else { -1 };
      var found = false;
      var steps = 0;
      while (cur >= 0 && steps < 10000) {
        let f = foldersGetFolderOrNull(db, scope, cur);
        if (f != null) {
          let p = f.parentId;
          if (p != null) {
            if (p == ancestorId) {
              found = true;
              cur = -1;
            } else {
              cur = p;
            }
          } else {
            cur = -1;
          }
        } else {
          cur = -1;
        }
        steps += 1;
      }
      found
    }

## The tree

The whole tree for one writer: every folder and every draft in two queries,
assembled here. A person has tens of folders. The root is a `FolderNode` whose
`folder` is null. Drafts come newest id first (the order of `Works.list_works`),
folders in sibling order.

    let foldersSameParent(a: Int?, b: Int?): Boolean {
      if (a != null) {
        if (b != null) { a == b } else { false }
      } else {
        b == null
      }
    }

    let foldersBuild(
      folder: Folder?,
      parentId: Int?,
      allFolders: List<Folder>,
      allWorks: List<FolderWork>,
    ): FolderNode {
      let kids = allFolders.filter { (f: Folder): Boolean => foldersSameParent(f.parentId, parentId) };
      let works = allWorks.filter { (w: FolderWork): Boolean => foldersSameParent(w.folderId, parentId) };
      let nodes = new ListBuilder<FolderNode>();
      var count = works.length;
      for (let kid of kids) {
        let node = foldersBuild(kid, kid.id, allFolders, allWorks);
        count += node.count;
        nodes.add(node);
      }
      new FolderNode(folder, works, nodes.toList(), count)
    }

    export let foldersListWorks(db: Db, scope: Scope): List<FolderWork> throws Bubble {
      let out = new ListBuilder<FolderWork>();
      let rows = db.query(
        "SELECT ${foldersWorkColumns} FROM works WHERE user_id = $1 ORDER BY id DESC",
        [scope.userId.toString()],
      );
      for (let row of rows) { out.add(FolderWork.fromRow(row)); }
      out.toList()
    }

    export let foldersTree(db: Db, scope: Scope): FolderNode throws Bubble {
      foldersBuild(null, null, foldersListFolders(db, scope), foldersListWorks(db, scope))
    }

The number of drafts under a node, which the works index prints in its
header: its own drafts plus its children's counts.

    export let foldersTreeTotal(node: FolderNode): Int { node.count }

## Writing

A name that is already a sibling's: the unique index is the authority, but
asking first keeps a refused write from being an error in the log. Another
folder than `exceptId` with this name under the same parent (null: the roots).

    let foldersClash(db: Db, userId: Int, name: String, parentId: Int?, exceptId: Int): Boolean throws Bubble {
      var clash = false;
      for (let row of foldersRows(db, sibling(userId.toInt64(), name, foldersI64(parentId)))) {
        if (row.int("id") != exceptId) { clash = true; }
      }
      clash
    }

Make a folder, optionally inside another one. A parent the user does not own
is dropped, not refused. `{:ok, folder}` is `ok` with `folder`; a changeset
error is `error == "invalid"` with `errors`.

    export let foldersCreateFolder(db: Db, scope: Scope, name: String, parentId: Int?): FoldersResult throws Bubble {
      let uid = scope.userId;
      let parent = foldersOwnedParent(db, scope, parentId);
      let prepared = createFolder(uid.toInt64(), name, foldersI64(parent));
      let stmt = prepared.statement;
      if (stmt != null) {
        if (foldersClash(db, uid, sysStringTrim(name), parent, -1)) {
          foldersNameTaken()
        } else {
          foldersDone(foldersFirstFolder(db, stmt))
        }
      } else {
        foldersInvalid(prepared.errors)
      }
    }

    export let foldersRenameFolder(db: Db, scope: Scope, id: Int, name: String): FoldersResult throws Bubble {
      let uid = scope.userId;
      let folder = foldersGetFolderOrNull(db, scope, id);
      if (folder != null) {
        let prepared = renameFolder(uid.toInt64(), id.toInt64(), name);
        let stmt = prepared.statement;
        if (stmt != null) {
          if (foldersClash(db, uid, sysStringTrim(name), folder.parentId, folder.id)) {
            foldersNameTaken()
          } else {
            foldersDone(foldersFirstFolder(db, stmt))
          }
        } else {
          foldersInvalid(prepared.errors)
        }
      } else {
        foldersFail("not_found")
      }
    }

Move a folder under another one, or to the root with null. Not owned is
`not_found`; into itself or into one of its own descendants is `cycle`. The
name is checked again in its new place, so a clash is an error on `name`.

    export let foldersMoveFolder(db: Db, scope: Scope, id: Int, parentId: Int?): FoldersResult throws Bubble {
      let uid = scope.userId;
      let folder = foldersGetFolderOrNull(db, scope, id);
      if (folder != null) {
        let parent = foldersOwnedParent(db, scope, parentId);
        var cycle = false;
        if (parent != null) {
          if (parent == folder.id) { cycle = true; }
          if (foldersIsDescendant(db, scope, parent, folder.id)) { cycle = true; }
        }
        if (cycle) {
          foldersFail("cycle")
        } else if (foldersClash(db, uid, folder.name, parent, folder.id)) {
          foldersNameTaken()
        } else {
          foldersDone(foldersFirstFolder(db, moveFolder(uid.toInt64(), id.toInt64(), foldersI64(parent))))
        }
      } else {
        foldersFail("not_found")
      }
    }

Put a draft in a folder, or take it out of one with null. Someone else's draft
is `not_found`; a folder that is not the user's unfiles the draft too
(`placedIn` is null then).

    export let foldersMoveWork(db: Db, scope: Scope, workId: Int, folderId: Int?): FoldersResult throws Bubble {
      let uid = scope.userId;
      let row = db.one(
        "SELECT id FROM works WHERE user_id = $1 AND id = $2",
        [uid.toString(), workId.toString()],
      );
      if (row != null) {
        let target = foldersOwnedParent(db, scope, folderId);
        foldersRows(db, moveWork(uid.toInt64(), workId.toInt64(), foldersI64(target)));
        new FoldersResult(true, null, target, null, foldersNothing())
      } else {
        foldersFail("not_found")
      }
    }

File these drafts in this folder, in one statement. No ownership check: the
caller passes ids it just read as the user's own (the backfill). Answers how
many rows changed.

    export let foldersFileWorks(db: Db, workIds: List<Int>, folderId: Int): Int throws Bubble {
      if (workIds.length == 0) { return 0; }
      let s = fileWorks(workIds.map { (i: Int): Int64 => i.toInt64() }, folderId.toInt64());
      db.exec(s.text, foldersParams(s))
    }

Delete a folder and lift everything it held into its parent, in one
transaction: its drafts, then its child folders, then the folder. If a lifted
child collides by name with a sibling in the new parent the unique index
raises and the whole delete rolls back, as the Elixir's did (a bubble).

    export let foldersDeleteFolder(db: Db, scope: Scope, id: Int): FoldersResult throws Bubble {
      let folder = foldersGetFolderOrNull(db, scope, id);
      if (folder != null) {
        let steps = deleteFolder(folder.id.toInt64(), foldersI64(folder.parentId));
        dbTransaction(db, fn (): Void throws Bubble {
          for (let s of steps) { foldersRows(db, s); }
        });
        foldersDone(folder)
      } else {
        foldersFail("not_found")
      }
    }

## The backfill

How many drafts the backfill would move right now.

    export let foldersUnfiledCount(db: Db, scope: Scope): Int throws Bubble {
      let rows = foldersRows(db, unfiledCount(scope.userId.toInt64()));
      if (rows.length == 0) { 0 } else { rows[0].int(rows[0].columns[0]) }
    }

The user's drafts that name a collection and are in no folder, as
`(id, collection)` pairs in two parallel lists would be awkward; they come
back as `FolderWork` records with only `id` and `collection` meaningful.

    export let foldersLooseWorkCollections(db: Db, scope: Scope): List<FolderWork> throws Bubble {
      let out = new ListBuilder<FolderWork>();
      let s = looseWorkCollections(scope.userId.toInt64());
      for (let row of foldersRows(db, s)) {
        out.add(new FolderWork(
          row.int("id"), "", "", 0, "", null,
          row.strOrNull("collection"), null, "",
        ));
      }
      out.toList()
    }

Insert, or take the one already there. The Elixir inserted and rescued the
unique index; asking first is the same thing without a failed statement.

    let foldersGetOrCreate(db: Db, scope: Scope, name: String, parentId: Int?): Folder throws Bubble {
      let made = foldersCreateFolder(db, scope, name, parentId);
      let folder = made.folder;
      if (folder != null) { return folder; }
      let rows = foldersRows(db, sibling(scope.userId.toInt64(), name, foldersI64(parentId)));
      if (rows.length == 0) { bubble() }
      Folder.fromRow(rows[0])
    }

File every draft that already belongs to a named collection into a folder
for it, gathered under one parent (`parentName`, null for no parent). Drafts
with no collection stay at the root. Idempotent; a draft already in a folder
stays where it was put. Answers the number of drafts filed.

    export let foldersBackfillFromCollections(db: Db, scope: Scope, parentName: String?): Int throws Bubble {
      let loose = foldersLooseWorkCollections(db, scope);
      if (loose.length == 0) { return 0; }
      let names = new ListBuilder<String>();
      let groups = new ListBuilder<ListBuilder<Int>>();
      for (let w of loose) {
        let c = w.collection;
        if (c != null) {
          var at = -1;
          var i = 0;
          while (i < names.length) {
            if (names[i] == c) { at = i; }
            i += 1;
          }
          if (at < 0) {
            let g = new ListBuilder<Int>();
            g.add(w.id);
            names.add(c);
            groups.add(g);
          } else {
            groups[at].add(w.id);
          }
        }
      }
      let filed = new ListBuilder<Int>();
      dbTransaction(db, fn (): Void throws Bubble {
        var parentId: Int? = null;
        if (parentName != null) {
          parentId = foldersGetOrCreate(db, scope, parentName, null).id;
        }
        var k = 0;
        while (k < names.length) {
          let folder = foldersGetOrCreate(db, scope, names[k], parentId);
          filed.add(foldersFileWorks(db, groups[k].toList(), folder.id));
          k += 1;
        }
      });
      var total = 0;
      for (let n of filed.toList()) { total += n; }
      total
    }

`backfill_from_collections(user_id)` with the Elixir's default parent.

    export let foldersBackfill(db: Db, scope: Scope): Int throws Bubble {
      foldersBackfillFromCollections(db, scope, "Cases")
    }

## Publishing

`mint_slug(name)`: lower-case, every run of characters outside `a-z0-9`
becomes one `-`, leading and trailing `-` go, the first 60 kept, nothing left
means `"stack"`. If any folder (any user) already has that slug, a four
character random suffix is added.

    let foldersSlugBase(name: String): String {
      let s = sysUtf8Downcase(name);
      let parts = new ListBuilder<String>();
      var pendingDash = false;
      var i = String.begin;
      while (s.hasIndex(i)) {
        let c = s[i];
        let next = s.next(i);
        if ((c >= 97 && c <= 122) || (c >= 48 && c <= 57)) {
          if (pendingDash && parts.length > 0) { parts.add("-"); }
          pendingDash = false;
          parts.add(s.slice(i, next));
        } else {
          pendingDash = true;
        }
        i = next;
      }
      let base = sysGraphemeTake(sysJoin(parts.toList(), ""), 60);
      if (base == "") { "stack" } else { base }
    }

    export let foldersSlugTaken(db: Db, slug: String): Boolean throws Bubble {
      foldersRows(db, slugTaken(slug)).length > 0
    }

    export let foldersMintSlug(db: Db, name: String): String throws Bubble {
      let base = foldersSlugBase(name);
      if (foldersSlugTaken(db, base)) {
        "${base}-${sysGraphemeTake(sysRandomToken(), 4)}"
      } else {
        base
      }
    }

Make a folder readable by somebody with no account. The folder keeps a slug it
already has, even after a rename, so a link already sent still works;
otherwise `slug` is used. A slug another folder holds is `slug_taken`.

    export let foldersPublish(db: Db, scope: Scope, id: Int, slug: String): FoldersResult throws Bubble {
      let folder = foldersGetFolderOrNull(db, scope, id);
      if (folder != null) {
        let kept = folder.slug;
        let chosen = if (kept != null) { kept } else { slug };
        if (kept == null && foldersSlugTaken(db, chosen)) {
          foldersFail("slug_taken")
        } else {
          foldersDone(foldersFirstFolder(db, publish(scope.userId.toInt64(), id.toInt64(), chosen)))
        }
      } else {
        foldersFail("not_found")
      }
    }

The Elixir's `publish(user_id, id)` whole: the owner check first (`owner` is
`Accounts.owner()`, passed in since this library does not depend on the
accounts functions), then the folder, then a slug minted from its name.

    export let foldersPublishAsOwner(db: Db, scope: Scope, owner: User?, id: Int): FoldersResult throws Bubble {
      let uid = scope.userId;
      if (owner != null) {
        if (owner.id == uid) {
          let folder = foldersGetFolderOrNull(db, scope, id);
          if (folder != null) {
            foldersPublish(db, scope, id, foldersMintSlug(db, folder.name))
          } else {
            foldersFail("not_found")
          }
        } else {
          foldersFail("not_owner")
        }
      } else {
        foldersFail("not_owner")
      }
    }

Take it back off the public site. The slug is kept, so publishing again
restores the same URL.

    export let foldersUnpublish(db: Db, scope: Scope, id: Int): FoldersResult throws Bubble {
      let folder = foldersGetFolderOrNull(db, scope, id);
      if (folder != null) {
        foldersDone(foldersFirstFolder(db, unpublish(scope.userId.toInt64(), id.toInt64())))
      } else {
        foldersFail("not_found")
      }
    }

A published folder by its slug, for anybody, or null.

    export let foldersPublishedBySlug(db: Db, slug: String): Folder? throws Bubble {
      foldersFirstFolder(db, publishedBySlug(slug))
    }

Every published folder, newest first.

    export let foldersPublished(db: Db): List<Folder> throws Bubble {
      foldersAllFolders(db, published())
    }

## Names for an import

These two live in `Import.Bulk` in the Elixir and are pure. They are here,
not in `import`, because a folder name is this context's business and
`import` can then call them without either depending on the other.

`foldersNameFor(titles)`: the longest common prefix of the titles (by
grapheme), with trailing whitespace, digits, `.`, `_` and `-` stripped and
trimmed; if that is three or more graphemes it is the folder's name, else
`"Imported YYYY-MM-DD HH:MM"` of the current time. One title is its own prefix:
`"chapter-01"` gives `"chapter"`.

    let foldersCommonPrefix(titles: List<String>): String {
      if (titles.length == 0) { return ""; }
      let first = titles[0];
      var best = sysGraphemeLength(first);
      var t = 1;
      while (t < titles.length) {
        let other = titles[t];
        var n = 0;
        let limit = best;
        var more = true;
        while (more && n < limit) {
          if (sysGraphemeTake(first, n + 1) == sysGraphemeTake(other, n + 1)) {
            n += 1;
          } else {
            more = false;
          }
        }
        best = n;
        t += 1;
      }
      sysGraphemeTake(first, best)
    }

Whitespace, digit, `.`, `_`, `-`: the characters `[\s\d._-]` strips from the
end. `\s` is ASCII whitespace and the no-break space.

    let foldersIsTrailer(c: Int): Boolean {
      c == 32 || (c >= 9 && c <= 13) || c == 160 || (c >= 48 && c <= 57) ||
        c == 46 || c == 95 || c == 45
    }

    let foldersStripTrailer(s: String): String {
      var keep = String.begin;
      var i = String.begin;
      while (s.hasIndex(i)) {
        let next = s.next(i);
        if (!foldersIsTrailer(s[i])) { keep = next; }
        i = next;
      }
      s.slice(String.begin, keep)
    }

`now` is `YYYY-MM-DD HH:MM:SS` UTC, as `sysUtcNow` gives.

    export let foldersNameForAt(titles: List<String>, now: String): String {
      let stem = sysStringTrim(foldersStripTrailer(foldersCommonPrefix(titles)));
      if (sysGraphemeLength(stem) >= 3) {
        stem
      } else {
        "Imported ${sysGraphemeTake(now, 16)}"
      }
    }

    export let foldersNameFor(titles: List<String>): String {
      foldersNameForAt(titles, sysUtcNow())
    }

`foldersInNameOrder(names)`: the names in the order they say, not the order a
browser handed them over: lower-cased, split at runs of ASCII digits, digit
runs compared as numbers and sorting before text. The part list is the
Elixir's, empty strings at the ends included, because the comparison of
`{0, n, ""}` with `{1, 0, text}` depends on them. Equal keys keep their
input order.

    class FoldersNamePart(public isText: Boolean, public text: String) {}

    class FoldersNameKey(public index: Int, public name: String, public parts: List<FoldersNamePart>) {}

    let foldersSplitDigits(s: String): List<FoldersNamePart> {
      let out = new ListBuilder<FoldersNamePart>();
      var runStart = String.begin;
      var inDigits = false;
      var i = String.begin;
      while (s.hasIndex(i)) {
        let c = s[i];
        let isDigit = c >= 48 && c <= 57;
        if (isDigit != inDigits) {
          out.add(new FoldersNamePart(!inDigits, s.slice(runStart, i)));
          runStart = i;
          inDigits = isDigit;
        }
        i = s.next(i);
      }
      out.add(new FoldersNamePart(!inDigits, s.slice(runStart, s.end)));
      if (inDigits) { out.add(new FoldersNamePart(true, "")); }
      out.toList()
    }

Code point order, which is also UTF-8 byte order, as Erlang compares binaries.

    let foldersCompareText(a: String, b: String): Int {
      var i = String.begin;
      var j = String.begin;
      while (a.hasIndex(i) && b.hasIndex(j)) {
        let x = a[i];
        let y = b[j];
        if (x < y) { return -1; }
        if (x > y) { return 1; }
        i = a.next(i);
        j = b.next(j);
      }
      if (a.hasIndex(i)) { 1 } else if (b.hasIndex(j)) { -1 } else { 0 }
    }

Digit runs as numbers of any size: drop leading zeros, then the longer is
larger, then compare as text.

    let foldersStripZeros(s: String): String {
      var i = String.begin;
      while (s.hasIndex(i) && s[i] == 48) { i = s.next(i); }
      if (s.hasIndex(i)) { s.slice(i, s.end) } else { "0" }
    }

    let foldersCompareNumbers(a: String, b: String): Int {
      let x = foldersStripZeros(a);
      let y = foldersStripZeros(b);
      let lx = sysByteLength(x);
      let ly = sysByteLength(y);
      if (lx < ly) { -1 } else if (lx > ly) { 1 } else { foldersCompareText(x, y) }
    }

    let foldersCompareParts(a: FoldersNamePart, b: FoldersNamePart): Int {
      if (a.isText == b.isText) {
        if (a.isText) {
          foldersCompareText(a.text, b.text)
        } else {
          foldersCompareNumbers(a.text, b.text)
        }
      } else if (a.isText) {
        1
      } else {
        -1
      }
    }

    let foldersCompareKeys(a: FoldersNameKey, b: FoldersNameKey): Int {
      var i = 0;
      while (i < a.parts.length && i < b.parts.length) {
        let c = foldersCompareParts(a.parts[i], b.parts[i]);
        if (c != 0) { return c; }
        i += 1;
      }
      if (a.parts.length < b.parts.length) {
        -1
      } else if (a.parts.length > b.parts.length) {
        1
      } else if (a.index < b.index) {
        -1
      } else if (a.index > b.index) {
        1
      } else {
        0
      }
    }

    export let foldersInNameOrder(names: List<String>): List<String> {
      let keys = new ListBuilder<FoldersNameKey>();
      var i = 0;
      while (i < names.length) {
        keys.add(new FoldersNameKey(i, names[i], foldersSplitDigits(sysUtf8Downcase(names[i]))));
        i += 1;
      }
      let sorted = keys.toList().sorted { (a: FoldersNameKey, b: FoldersNameKey): Int =>
        foldersCompareKeys(a, b)
      };
      sorted.map { (k: FoldersNameKey): String => k.name }
    }
