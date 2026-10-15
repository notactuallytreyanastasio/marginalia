# Landing a pile

`Marginalia.Import.Bulk` and `Import.GitHub.import_stack`: documents arrive
from GitHub or from files dropped on the page, and by the time they reach this
file they have nothing in common but a title, some markdown and maybe the
address they came from. Everything about where a document came from is finished
before the landing starts, so there is one place that decides what an import
*means*: what counts as a duplicate, what a bad document does to the rest of
the batch, and what the writer is told afterwards.

Nothing is all-or-nothing. A batch of forty in which three are empty imports
thirty-seven and names the three. Duplicates are decided by title, inside the
folder: importing the same search twice should not double the folder, and the
same pull request landing in two folders is two documents, which is what
somebody doing that meant. Numbering is asked for, not assumed: a stack is an
order, a pile is not.

    let { Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Work, WorkParams, workParams, worksCreateWork, uploadPrepare } = import("works/src");
    let {
      Folder, foldersFolderByName, foldersCreateFolder, foldersMoveWork, foldersFirstError,
      foldersNameForAt, foldersNameFor, foldersInNameOrder,
    } = import("folders/src");

## What a failure is

`kind` is `empty`, `too_long` (`words`), `no_sections`, `invalid` (a changeset
with nothing to say) or `text` (the first changeset error as `"field message"`,
which is its own explanation).

    export class ImporterLandFailure(public title: String, public kind: String, public text: String) {
      public var words: Int = 0;
    }

A failure reason, in words. The reasons come from three layers (the word gate,
the changeset and the segmenter) and a page that printed them raw would tell a
writer their file failed with `{:too_long, 143_204}`.

    export let importerLandExplain(f: ImporterLandFailure): String {
      if (f.kind == "empty") {
        "there is no text in it"
      } else if (f.kind == "too_long") {
        "${f.words.toString()} words, over the limit"
      } else if (f.kind == "no_sections") {
        "no text that could be split into sections"
      } else if (f.kind == "invalid") {
        ":invalid"
      } else {
        f.text
      }
    }

    export class ImporterLandResult(
      public folder: Folder?,
      public created: List<Work>,
      public skipped: List<String>,
      public failed: List<ImporterLandFailure>,
    ) {}

## Titles

`clean`: whitespace runs become one space, the ends are trimmed, nothing left is
`Untitled`, and 200 characters are kept.

    let importerWhitespaceToSpace(s: String): String {
      var out = s;
      var i = 9;
      while (i <= 13) {
        out = importerReplaceAll(out, importerChr(i), " ");
        i += 1;
      }
      importerCollapse(out)
    }

    export let importerCleanTitle(title: String): String {
      let t = importerTrim(importerWhitespaceToSpace(title));
      if (t.isEmpty) { "Untitled" } else { importerTake(t, 200) }
    }

`^\s*\d+\s*[.):-]`: a title that already carries its number.

    export let importerNumbered(title: String): Boolean {
      let cps = importerCps(title);
      var i = 0;
      while (i < cps.length && importerIsSpace(cps[i])) { i += 1; }
      var digits = 0;
      while (i < cps.length && importerIsDigit(cps[i])) {
        i += 1;
        digits += 1;
      }
      if (digits == 0) { return false; }
      while (i < cps.length && importerIsSpace(cps[i])) { i += 1; }
      if (i >= cps.length) { return false; }
      let c = cps[i];
      c == 46 || c == 41 || c == 58 || c == 45
    }

With `number`: unchanged if it already carries one, else `"{i}. title"`, `i`
being the position in the list.

    export let importerLandTitle(doc: ImporterDoc, i: Int, number: Boolean): String {
      let title = importerCleanTitle(doc.title);
      if (!number) { return title; }
      if (importerNumbered(title)) { title } else { "${i.toString()}. ${title}" }
    }

## The folder

Nil or blank is loose. Otherwise the user's folder with that exact name in any
parent (several of one name is the Elixir's `Repo.one` raising: a bubble here),
else a new one at the root, falling back to loose when it cannot be made.

    export let importerFolderFor(db: Db, scope: Scope, name: String?): Folder? throws Bubble {
      if (name != null) {
        importerFolderNamed(db, scope, importerTrim(name))
      } else {
        null
      }
    }

    let importerFolderNamed(db: Db, scope: Scope, trimmed: String): Folder? throws Bubble {
      if (trimmed.isEmpty) { return null; }
      let found = foldersFolderByName(db, scope, trimmed);
      if (found != null) { return found; }
      let made = foldersCreateFolder(db, scope, trimmed, null);
      made.folder
    }

The titles of the drafts in a folder, once: duplicates within one batch are not
detected.

    export let importerTitlesIn(db: Db, folder: Folder?): List<String> throws Bubble {
      if (folder != null) {
        let rows = db.query("SELECT title FROM works WHERE folder_id = $1", [folder.id.toString()]);
        let out = new ListBuilder<String>();
        var i = 0;
        while (i < rows.length) {
          out.add(rows[i].str("title"));
          i += 1;
        }
        out.toList()
      } else {
        []
      }
    }

## land

Create a draft per document, in `folder`, one at a time, in order. The same word
gate the upload form uses, so a file dropped in a batch of thirty gets the answer
it would have got on its own. `listener` is called after every document, skipped
and failed ones too.

    class ImporterMade(public work: Work?, public failure: ImporterLandFailure?) {}

    let importerFailed(title: String, kind: String, words: Int): ImporterMade {
      let f = new ImporterLandFailure(title, kind, "");
      f.words = words;
      new ImporterMade(null, f)
    }

    let importerCreate(
      db: Db, scope: Scope, folder: Folder?, doc: ImporterDoc, title: String,
    ): ImporterMade throws Bubble {
      let prepared = uploadPrepare(title, doc.body, null);
      let accepted = prepared.ok;
      if (accepted != null) {
        let params = workParams(accepted.title, accepted.body);
        params.sourceUrl = doc.sourceUrl;
        let r = worksCreateWork(db, scope, params);
        let work = r.ok;
        if (work != null) {
          if (folder != null) { foldersMoveWork(db, scope, work.id, folder.id); }
          new ImporterMade(work, null)
        } else if (r.error == "no_sections") {
          importerFailed(title, "no_sections", 0)
        } else if (r.error == "too_long") {
          importerFailed(title, "too_long", prepared.words)
        } else if (r.error == "empty") {
          importerFailed(title, "empty", 0)
        } else if (r.errors.length > 0) {
          let e = r.errors[0];
          new ImporterMade(null, new ImporterLandFailure(title, "text", "${e.field} ${e.message}"))
        } else {
          importerFailed(title, "invalid", 0)
        }
      } else if (prepared.problem == "too_long") {
        importerFailed(title, "too_long", prepared.words)
      } else {
        importerFailed(title, "empty", 0)
      }
    }

    export let importerLandWith(
      db: Db,
      scope: Scope,
      folderName: String?,
      number: Boolean,
      listener: ImporterListener,
      docs: List<ImporterDoc>,
    ): ImporterLandResult throws Bubble {
      let folder = importerFolderFor(db, scope, folderName);
      let have = importerTitlesIn(db, folder);
      let created = new ListBuilder<Work>();
      let skipped = new ListBuilder<String>();
      let failed = new ListBuilder<ImporterLandFailure>();
      var i = 0;
      while (i < docs.length) {
        let title = importerLandTitle(docs[i], i + 1, number);
        if (importerIsOneOf(title, have)) {
          skipped.add(title);
        } else {
          let made = importerCreate(db, scope, folder, docs[i], title);
          let work = made.work;
          let failure = made.failure;
          if (work != null) {
            created.add(work);
          } else if (failure != null) {
            failed.add(failure);
          }
        }
        listener.item(title, i + 1, docs.length);
        i += 1;
      }
      new ImporterLandResult(folder, created.toList(), skipped.toList(), failed.toList())
    }

Without numbering and without a listener.

    export let importerLand(
      db: Db, scope: Scope, folder: String?, docs: List<ImporterDoc>,
    ): ImporterLandResult throws Bubble {
      importerLandWith(db, scope, folder, false, new ImporterSilent(), docs)
    }

## Filtering by title

Keep the pull requests whose title matches `regex`, a case-insensitive pattern.
An empty pattern keeps everything. A pattern that will not compile says why
rather than raising: a half-typed regex is the normal state of a regex box. The
title is truncated to 200 characters before matching, so a pattern that
backtracks has 200 characters to do it in rather than a megabyte.

    export let importerTitleFilter(regex: String?, items: List<ImporterPull>): ImporterFiltered {
      let pattern = if (regex != null) { importerTrim(regex) } else { "" };
      if (pattern.isEmpty) { return new ImporterFiltered(items, null); }
      let re = importerRegexCompile(pattern);
      if (!re.error.isEmpty) { return new ImporterFiltered([], re.error); }
      let kept = new ListBuilder<ImporterPull>();
      var i = 0;
      while (i < items.length) {
        if (importerRegexMatches(re, importerTake(items[i].title, 200))) { kept.add(items[i]); }
        i += 1;
      }
      new ImporterFiltered(kept.toList(), null)
    }

## Files dropped on the page

A folder name for a pile of files that were not given one: the stem they share
(`chapter-01` to `chapter-07` give `chapter`), else the moment. The pure part
lives in the folders library as `foldersNameFor`.

    export let importerFolderNameFor(docs: List<ImporterDoc>): String {
      foldersNameFor(docs.map { (d: ImporterDoc): String => d.title })
    }

    export let importerFolderNameForAt(docs: List<ImporterDoc>, now: String): String {
      foldersNameForAt(docs.map { (d: ImporterDoc): String => d.title }, now)
    }

The documents in the order their names say, not the order a browser handed them
over: a drop of seven files once arrived backwards and the folder read the book
from the end. `foldersInNameOrder` sorts names; this puts the documents back
under them.

    export let importerInNameOrder(docs: List<ImporterDoc>): List<ImporterDoc> {
      let ordered = foldersInNameOrder(docs.map { (d: ImporterDoc): String => d.title });
      let used = new ListBuilder<Boolean>();
      var u = 0;
      while (u < docs.length) {
        used.add(false);
        u += 1;
      }
      let out = new ListBuilder<ImporterDoc>();
      var i = 0;
      while (i < ordered.length) {
        var j = 0;
        var placed = false;
        while (!placed && j < docs.length) {
          if (!used[j] && docs[j].title == ordered[i]) {
            used.set(j, true);
            out.add(docs[j]);
            placed = true;
          }
          j += 1;
        }
        i += 1;
      }
      out.toList()
    }

`Path.rootname/1` of an uploaded file's name: the last extension off.

    export let importerRootname(filename: String): String {
      let cps = importerCps(filename);
      var dot = -1;
      var i = 0;
      while (i < cps.length) {
        if (cps[i] == 47) { dot = -1; }
        if (cps[i] == 46 && i > 0 && cps[i - 1] != 47) { dot = i; }
        i += 1;
      }
      if (dot < 0) { filename } else { importerSlice(cps, 0, dot) }
    }

## A stack, filed

`import_stack`: fetch a stack and file it as drafts in a folder. Idempotent on
title, so a failed run can simply be run again. The folder is named
`folderName` or `owner/repo`; the user's folder of that exact name in any
parent, else a new one at the root, and a folder that cannot be made is the
error. `listener` is called per draft created. A draft that cannot be created
bubbles, as the Elixir's `{:ok, work} =` match raised.

    export class ImporterImported(
      public folder: Folder?,
      public created: Int,
      public total: Int,
      public error: ImporterError?,
    ) {}

    let importerImportError(e: ImporterError): ImporterImported {
      new ImporterImported(null, 0, 0, e)
    }

The ordinal goes in the title because that is where `Stacks` looks for the order,
and because a reader opening the folder should see it too.

    export let importerStackTitle(item: ImporterItem): String {
      if (importerNumbered(item.title)) { item.title } else { "${item.ordinal.toString()}. ${item.title}" }
    }

    class ImporterFiling(public folder: Folder?, public error: ImporterError?) {}

The folder a stack is filed in: the user's folder of that exact name in any
parent, else a new one at the root.

    let importerFilingFolder(db: Db, scope: Scope, name: String): ImporterFiling throws Bubble {
      let found = foldersFolderByName(db, scope, name);
      if (found != null) { return new ImporterFiling(found, null); }
      let made = foldersCreateFolder(db, scope, name, null);
      let folder = made.folder;
      if (folder != null) {
        new ImporterFiling(folder, null)
      } else {
        new ImporterFiling(null, importerErrorText("other", foldersFirstError(made)))
      }
    }

    let importerFileItem(
      db: Db, scope: Scope, folder: Folder, item: ImporterItem, title: String,
    ): Void throws Bubble {
      let params = workParams(title, importerDocument(item));
      params.sourceUrl = item.url;
      let work = worksCreateWork(db, scope, params).ok;
      if (work != null) {
        let moved = foldersMoveWork(db, scope, work.id, folder.id);
        if (!moved.ok) { bubble() }
      } else {
        bubble()
      }
    }

    export let importerImportStack(
      db: Db,
      scope: Scope,
      http: ImporterHttp,
      owner: String,
      repo: String,
      token: String?,
      folderName: String?,
      state: String,
      listener: ImporterListener,
    ): ImporterImported throws Bubble {
      let stack = importerStack(http, owner, repo, token, state);
      let why = stack.error;
      if (why != null) { return importerImportError(why); }
      let name = if (folderName != null) { folderName } else { "${owner}/${repo}" };
      let filing = importerFilingFolder(db, scope, name);
      let folder = filing.folder;
      if (folder != null) {
        let have = importerTitlesIn(db, folder);
        var created = 0;
        var i = 0;
        while (i < stack.items.length) {
          let item = stack.items[i];
          let title = importerStackTitle(item);
          if (!importerIsOneOf(title, have)) {
            importerFileItem(db, scope, folder, item, title);
            created += 1;
            listener.item(title, created, stack.items.length);
          }
          i += 1;
        }
        new ImporterImported(folder, created, stack.items.length, null)
      } else {
        let problem = filing.error;
        if (problem != null) {
          importerImportError(problem)
        } else {
          importerImportError(importerError("bad_name"))
        }
      }
    }
