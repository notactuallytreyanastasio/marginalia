# Cuts

Reading a folder: what a group of drafts says that none of them says alone.
A cut is one reading per folder (unique per user and folder), built from the
members' texts and checked by quote location. Ported from `Marginalia.Cuts`.

A folder of drafts is read over the maps its drafts already have (their
nodes, their quotes), not over their raw text. A folder of folders is read
over its children's readings. Whatever the level, every claim must quote
something that was actually sent and name the member it came from; two
citations are the floor; anything that cannot be located is dropped and
counted.

    let { Db, DbRow } = import("db/src");
    let { Scope, User, scopeFor, accountsGetUser } = import("accounts/src");
    let { Work, worksFindWork, worksListSections, worksNodes } = import("works/src");
    let { Folder, FolderNode, FolderWork, foldersTree, foldersGetFolderOrNull } = import("folders/src");
    let { LlmClient, LlmCall, LlmMessage, LlmError, llmErrorText } = import("llm/src");
    let { versionsBump } = import("runs/src");
    let { FieldError } = import("core/src");
    let { sysStringTrim, sysSha256, sysJoin, sysUtcNow, sysGraphemeTake,
          sysGraphemeLength, sysStringReplace } = import("sys/src");
    let { JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonBoolean, JsonNull,
          JsonNumeric, JsonTextProducer } = import("std/json");

## Quoting

Find `needle` in `haystack` and return the haystack's own wording.

Quoting has to tolerate re-wrapping and nothing else. Prose here is stored
with the line breaks it was written with, and a model asked to cite a
passage reflows it, so a byte-exact test rejects almost every true citation
for a reason that means nothing about whether the model read the text.

The Elixir collapsed whitespace on both sides and mapped the match back to
the original through a per-byte index. A per-character scan over a member's
text is what the interpreter is worst at, so this does the same thing by
words. The needle is split on whitespace; the haystack must hold the first
word, and after each word a run of spaces, newlines, tabs or carriage
returns, then the next word. The first word may start mid-word and the last
may end mid-word, exactly as a substring of the collapsed text could. What
comes back is the slice of the haystack from the first word's start to the
last word's end, line breaks and all.

The needle side folds every ASCII whitespace (`\s` in PCRE, so vertical tab
and form feed too); the haystack side only space, `\n`, `\t`, `\r`. The two
rare characters are therefore not separators in the haystack, as before.

    let cutsVt(): String { "\u{b}" }
    let cutsFf(): String { "\u{c}" }

    let cutsIsWs(c: Int): Boolean { c == 32 || c == 10 || c == 9 || c == 13 }

    let cutsWords(s: String): List<String> {
      let a = sysStringReplace(s, "\n", " ");
      let b = sysStringReplace(a, "\t", " ");
      let c = sysStringReplace(b, "\r", " ");
      let d = sysStringReplace(c, cutsVt(), " ");
      let e = sysStringReplace(d, cutsFf(), " ");
      e.split(" ").filter { (w: String): Boolean => !w.isEmpty }
    }

The index `n` code points on from `at`, or null if the string ends first.

    let cutsAdvance(s: String, at: StringIndex, n: Int): StringIndex? {
      var p = at;
      var k = 0;
      var ok = true;
      while (k < n && ok) {
        if (s.hasIndex(p)) { p = s.next(p); } else { ok = false; }
        k += 1;
      }
      if (ok) { p } else { null }
    }

    let cutsLength(s: String): Int {
      var p = String.begin;
      var n = 0;
      while (s.hasIndex(p)) { p = s.next(p); n += 1; }
      n
    }

The end of the match of `words` starting at `at`, or null. Each word must
follow the one before it across a non-empty run of the four whitespace
characters.

    let cutsChain(hay: String, at: StringIndex, words: List<String>): StringIndex? {
      var p = at;
      var k = 0;
      var ok = true;
      while (k < words.length && ok) {
        if (k > 0) {
          if (hay.hasIndex(p) && cutsIsWs(hay[p])) {
            while (hay.hasIndex(p) && cutsIsWs(hay[p])) { p = hay.next(p); }
          } else {
            ok = false;
          }
        }
        if (ok) {
          let w = words[k];
          let e = cutsAdvance(hay, p, cutsLength(w));
          if (e != null) {
            if (hay.slice(p, e) == w) { p = e; } else { ok = false; }
          } else {
            ok = false;
          }
        }
        k += 1;
      }
      if (ok) { p } else { null }
    }

A blank needle is not found. A needle that is in the haystack byte for byte
comes back unchanged. Otherwise the loose match above, first occurrence.

    export let cutsLocate(needle: String, haystack: String): String? {
      if (sysStringTrim(needle).isEmpty) { return null; }
      if (haystack.split(needle).length > 1) { return needle; }
      let words = cutsWords(needle);
      if (words.length == 0) { return null; }
      let first = words[0];
      var result: String? = null;
      var from = String.begin;
      var done = false;
      while (!done) {
        let hit = haystack.indexOf(first, from);
        if (hit is StringIndex) {
          let end = cutsChain(haystack, hit, words);
          if (end != null) {
            result = haystack.slice(hit, end);
            done = true;
          } else {
            from = haystack.next(hit);
          }
        } else {
          done = true;
        }
      }
      result
    }

## Members

One thing being read: a draft (`work`) or a child folder (`folder`), numbered
from 1 in the order the prompt shows them. `read` is whether the work is
read, or the child folder has a finished reading of its own. `text` is what
the member contributes to the prompt and what quotes are located in.

    export class CutMember(
      public n: Int,
      public kind: String,
      public id: Int,
      public label: String,
      public read: Boolean,
      public text: String,
    ) {
      public ref(): CutMemberRef { new CutMemberRef(n, kind, id, label, read) }
    }

    let cutsFindNode(node: FolderNode, id: Int): FolderNode? {
      var found: FolderNode? = null;
      var i = 0;
      while (found == null && i < node.folders.length) {
        let kid = node.folders[i];
        let f = kid.folder;
        if (f != null && f.id == id) {
          found = kid;
        } else {
          found = cutsFindNode(kid, id);
        }
        i += 1;
      }
      found
    }

The map, not the manuscript. `quote` is the draft's own words, which is what
makes a citation checkable later; the node title is what the read thought it
was doing. A draft with no nodes contributes the first 1200 characters of
each section.

    let cutsWorkText(db: Db, work: Work): String throws Bubble {
      let nodes = worksNodes(db, work.id);
      let parts = new ListBuilder<String>();
      if (nodes.length == 0) {
        for (let s of worksListSections(db, work.id)) {
          parts.add(sysGraphemeTake(s.body, 1200));
        }
      } else {
        for (let nd of nodes) {
          let q = nd.quote;
          var quoted = "";
          if (q != null) {
            if (q != "") { quoted = "\n> ${q}"; }
          }
          parts.add("${nd.nodeType}: ${nd.title}${quoted}");
        }
      }
      let body = sysJoin(parts.toList(), "\n\n");
      let impression = work.firstImpression;
      let lead = if (impression != null) { impression } else { "" };
      sysStringTrim("${lead}\n\n${body}")
    }

A read child contributes its thesis and its threads' claims; an unread one
the titles of what is in it, and says so. An unread child is a hole in the
answer and the reader should be able to see where.

    let cutsTitles(child: FolderNode): String {
      let titles = new ListBuilder<String>();
      for (let w of child.works) { titles.add(w.title); }
      for (let f of child.folders) {
        let folder = f.folder;
        if (folder != null) { titles.add(folder.name); }
      }
      sysJoin(titles.toList(), ", ")
    }

    let cutsChildText(cut: Cut?, child: FolderNode): String {
      if (cut != null) {
        if (cut.status == "read") {
          let lines = new ListBuilder<String>();
          for (let t of cut.threads) { lines.add("- ${t.claim}"); }
          let thesis = cut.thesis;
          let lead = if (thesis != null) { thesis } else { "" };
          return sysStringTrim("${lead}\n\n${sysJoin(lines.toList(), "\n")}");
        }
      }
      "(not read yet) holds: ${cutsTitles(child)}"
    }

The ids of a node's drafts in ascending order. The tree lists them newest
first; the members are numbered oldest first.

    let cutsSortedIds(works: List<FolderWork>): List<Int> {
      let out = new ListBuilder<Int>();
      var rank = 0;
      while (rank < works.length) {
        for (let w of works) {
          var below = 0;
          for (let o of works) { if (o.id < w.id) { below += 1; } }
          if (below == rank) { out.add(w.id); }
        }
        rank += 1;
      }
      out.toList()
    }

    let cutsWorkMembers(db: Db, scope: Scope, node: FolderNode): List<CutMember> throws Bubble {
      let out = new ListBuilder<CutMember>();
      var n = 1;
      for (let id of cutsSortedIds(node.works)) {
        let work = worksFindWork(db, scope, id);
        if (work != null) {
          out.add(new CutMember(n, "work", work.id, work.title, work.status == "read",
            cutsWorkText(db, work)));
          n += 1;
        }
      }
      out.toList()
    }

    let cutsChildMembers(db: Db, scope: Scope, node: FolderNode): List<CutMember> throws Bubble {
      let out = new ListBuilder<CutMember>();
      var n = 1;
      for (let child of node.folders) {
        let folder = child.folder;
        if (folder != null) {
          let cut = cutsForFolder(db, scope, folder.id);
          var isRead = false;
          if (cut != null) { isRead = cut.status == "read"; }
          out.add(new CutMember(n, "folder", folder.id, folder.name, isRead,
            cutsChildText(cut, child)));
          n += 1;
        }
      }
      out.toList()
    }

The members of a folder reading, and the text each contributes. Subfolders
win over drafts: a folder holding both is read at the level of its
subfolders, because mixing "what this case held" with "what this paragraph
says" in one prompt gives an answer that is about neither. A folder that is
not the scope's, or not there, has no members; so does no folder at all.

    export let cutsMembers(db: Db, scope: Scope, folderId: Int?): List<CutMember> throws Bubble {
      if (folderId != null) {
        let node = cutsFindNode(foldersTree(db, scope), folderId);
        if (node != null) {
          if (node.folders.length > 0) {
            cutsChildMembers(db, scope, node)
          } else {
            cutsWorkMembers(db, scope, node)
          }
        } else {
          []
        }
      } else {
        []
      }
    }

A fingerprint of what was read, so a stale answer can say so: SHA-256, lower
case hex, of `kind:id:text` lines joined with newlines.

    export let cutsContentSha(members: List<CutMember>): String {
      let lines = new ListBuilder<String>();
      for (let m of members) { lines.add("${m.kind}:${m.id.toString()}:${m.text}"); }
      sysSha256(sysJoin(lines.toList(), "\n"))
    }

## Readings

    export class CutsResult(
      public ok: Cut?,
      public error: String?,
      public errors: List<FieldError>,
    ) {}

    let cutsGood(cut: Cut): CutsResult { new CutsResult(cut, null, []) }

    let cutsFailed(code: String): CutsResult { new CutsResult(null, code, []) }

    let cutsInvalid(errors: List<FieldError>): CutsResult {
      new CutsResult(null, "invalid", errors)
    }

    let cutsOne(db: Db, id: Int): Cut? throws Bubble {
      let row = db.one("SELECT ${cutsColumns} FROM cuts WHERE id = $1", [id.toString()]);
      if (row == null) { null } else { Cut.fromRow(row) }
    }

    let cutsReload(db: Db, id: Int): Cut throws Bubble {
      let cut = cutsOne(db, id);
      if (cut != null) { cut } else { bubble() }
    }

    let cutsMany(rows: List<DbRow>): List<Cut> throws Bubble {
      let out = new ListBuilder<Cut>();
      for (let row of rows) { out.add(Cut.fromRow(row)); }
      out.toList()
    }

The scope's readings, most recently updated first.

    export let cutsList(db: Db, scope: Scope): List<Cut> throws Bubble {
      cutsMany(db.query(
        "SELECT ${cutsColumns} FROM cuts WHERE user_id = $1 ORDER BY updated_at DESC, id DESC",
        [scope.userId.toString()],
      ))
    }

One of the scope's readings, or null. Not another user's.

    export let cutsGet(db: Db, scope: Scope, id: Int): Cut? throws Bubble {
      let row = db.one(
        "SELECT ${cutsColumns} FROM cuts WHERE user_id = $1 AND id = $2",
        [scope.userId.toString(), id.toString()],
      );
      if (row == null) { null } else { Cut.fromRow(row) }
    }

The one reading a folder has, or null.

    export let cutsForFolder(db: Db, scope: Scope, folderId: Int): Cut? throws Bubble {
      let row = db.one(
        "SELECT ${cutsColumns} FROM cuts WHERE user_id = $1 AND folder_id = $2",
        [scope.userId.toString(), folderId.toString()],
      );
      if (row == null) { null } else { Cut.fromRow(row) }
    }

The folder a reading is of (the Elixir `preload(:folder)`), or null if it has
none or the folder is gone.

    export let cutsFolder(db: Db, scope: Scope, cut: Cut): Folder? throws Bubble {
      let id = cut.folderId;
      if (id != null) { foldersGetFolderOrNull(db, scope, id) } else { null }
    }

Delete a reading. True if a row went.

    export let cutsDelete(db: Db, cut: Cut): Boolean throws Bubble {
      db.exec("DELETE FROM cuts WHERE id = $1", [cut.id.toString()]) > 0
    }

Set the status and its detail, with no validation (`set_status/3` bypassed
the changeset too). The detail is replaced, so a plain status clears it.

    export let cutsSetStatus(db: Db, cut: Cut, status: String, detail: String?): Cut throws Bubble {
      db.exec(
        "UPDATE cuts SET status = $1, status_detail = $2, updated_at = $3 WHERE id = $4",
        [status, detail, sysUtcNow(), cut.id.toString()],
      );
      cutsReload(db, cut.id)
    }

## Writing a reading

What `Cut.changeset` casts: title, question, folder, status, detail, scope.
Empty strings become null, as Ecto's `cast` has it.

    export class CutParams(public title: String?) {
      public var question: String? = null;
      public var folderId: Int? = null;
      public var status: String? = null;
      public var statusDetail: String? = null;
      public var scope: String? = null;
    }

    export let cutParams(title: String?): CutParams { new CutParams(title) }

    let cutsBlankToNull(s: String?): String? {
      if (s != null) {
        if (s == "") { null } else { s }
      } else {
        null
      }
    }

`Cut.changeset` validation, with Ecto's messages: title required, at most 200
characters, status one of the four.

    let cutsKnownStatus(status: String): Boolean {
      var known = false;
      for (let s of cutsStatuses()) { if (s == status) { known = true; } }
      known
    }

    export let cutsChange(params: CutParams): List<FieldError> {
      let errors = new ListBuilder<FieldError>();
      let title = params.title;
      let trimmed = if (title != null) { sysStringTrim(title) } else { "" };
      if (trimmed.isEmpty) {
        errors.add(new FieldError("title", "can't be blank"));
      } else if (sysGraphemeLength(trimmed) > 200) {
        errors.add(new FieldError("title", "should be at most 200 character(s)"));
      }
      let status = params.status;
      if (status != null) {
        if (!cutsKnownStatus(status)) {
          errors.add(new FieldError("status", "is invalid"));
        }
      }
      errors.toList()
    }

Make a reading for the scope. Nothing checks that the folder is the scope's
(the changeset did not); `cutsOpenFolderReading` does. A second reading for
the same folder breaks the unique index and bubbles, as the Elixir raised.

    export let cutsCreate(db: Db, scope: Scope, params: CutParams): CutsResult throws Bubble {
      let errors = cutsChange(params);
      if (errors.length > 0) { return cutsInvalid(errors); }
      let title = params.title;
      let titleText = if (title != null) { sysStringTrim(title) } else { "" };
      let status = params.status;
      let statusText = if (status != null) { status } else { "draft" };
      let scopeName = params.scope;
      let scopeText = if (scopeName != null) { scopeName } else { "folder" };
      let folder = params.folderId;
      let folderText: String? = if (folder != null) { folder.toString() } else { null };
      let now = sysUtcNow();
      let id = db.insert(
        "INSERT INTO cuts (title, question, status, status_detail, user_id, folder_id, scope, threads, tensions, dropped, members, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, '[]', '[]', '[]', '[]', $8, $8)",
        [titleText, cutsBlankToNull(params.question), statusText, cutsBlankToNull(params.statusDetail),
         scope.userId.toString(), folderText, scopeText, now],
      );
      cutsGood(cutsReload(db, id))
    }

Get or make the reading for a folder, and mark it queued (`draft`). One per
folder: re-reading replaces what was there, and a re-opened reading keeps its
thesis, threads and the rest until the next read overwrites them. The
question is replaced only when one is given. A folder the scope does not own
is `error == "not_found"`.

    export let cutsOpenFolderReading(db: Db, scope: Scope, folderId: Int, question: String?): CutsResult throws Bubble {
      let folder = foldersGetFolderOrNull(db, scope, folderId);
      if (folder != null) {
        let existing = cutsForFolder(db, scope, folderId);
        if (existing != null) {
          cutsReopen(db, folder, existing, question)
        } else {
          let params = new CutParams(folder.name);
          params.question = question;
          params.folderId = folder.id;
          params.scope = "folder";
          params.status = "draft";
          cutsCreate(db, scope, params)
        }
      } else {
        cutsFailed("not_found")
      }
    }

    let cutsReopen(db: Db, folder: Folder, existing: Cut, question: String?): CutsResult throws Bubble {
      let errors = cutsChange(cutParams(folder.name));
      if (errors.length > 0) { return cutsInvalid(errors); }
      let now = sysUtcNow();
      if (question != null) {
        db.exec(
          "UPDATE cuts SET title = $1, folder_id = $2, scope = 'folder', status = 'draft', question = $3, updated_at = $4 WHERE id = $5",
          [sysStringTrim(folder.name), folder.id.toString(), cutsBlankToNull(question), now, existing.id.toString()],
        );
      } else {
        db.exec(
          "UPDATE cuts SET title = $1, folder_id = $2, scope = 'folder', status = 'draft', updated_at = $3 WHERE id = $4",
          [sysStringTrim(folder.name), folder.id.toString(), now, existing.id.toString()],
        );
      }
      cutsGood(cutsReload(db, existing.id))
    }

Whether a stored reading is still about what the folder now holds. A reading
with no fingerprint or no folder is not.

    export let cutsCurrent(db: Db, scope: Scope, cut: Cut): Boolean throws Bubble {
      let sha = cut.contentSha;
      let folder = cut.folderId;
      if (sha == null) { return false; }
      if (folder == null) { return false; }
      sha == cutsContentSha(cutsMembers(db, scope, folder))
    }

What the page shows as "stale": a finished reading that is no longer current.

    export let cutsIsStale(db: Db, scope: Scope, cut: Cut): Boolean throws Bubble {
      cut.status == "read" && !cutsCurrent(db, scope, cut)
    }

## Storing a result

`Cut.result_changeset`: thesis, threads, tensions, not_supported, dropped,
content_sha, status, members, written together. Every field is replaced (the
Elixir only wrote the keys it was given; every caller gave them all).

    export class CutResult(
      public thesis: String?,
      public threads: List<CutThread>,
      public tensions: List<CutTension>,
      public notSupported: String?,
      public dropped: List<String>,
      public contentSha: String?,
      public status: String,
      public members: List<CutMemberRef>,
    ) {}

    let cutsPicksJson(p: JsonTextProducer, picks: List<CutPick>): Void {
      p.startArray();
      for (let e of picks) {
        p.startObject();
        p.objectKey("member"); p.int32Value(e.member);
        p.objectKey("kind"); p.stringValue(e.kind);
        p.objectKey("id"); p.int32Value(e.id);
        p.objectKey("label"); p.stringValue(e.label);
        p.objectKey("quote"); p.stringValue(e.quote);
        p.endObject();
      }
      p.endArray();
    }

    let cutsThreadsJson(xs: List<CutThread>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      for (let x of xs) {
        p.startObject();
        p.objectKey("claim"); p.stringValue(x.claim);
        p.objectKey("evidence"); cutsPicksJson(p, x.evidence);
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

    let cutsTensionsJson(xs: List<CutTension>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      for (let x of xs) {
        p.startObject();
        p.objectKey("claim"); p.stringValue(x.claim);
        p.objectKey("evidence"); cutsPicksJson(p, x.evidence);
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

    let cutsDroppedJson(xs: List<String>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      for (let x of xs) { p.stringValue(x); }
      p.endArray();
      p.toJsonString()
    }

    let cutsMembersJson(xs: List<CutMemberRef>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      for (let m of xs) {
        p.startObject();
        p.objectKey("n"); p.int32Value(m.n);
        p.objectKey("kind"); p.stringValue(m.kind);
        p.objectKey("id"); p.int32Value(m.id);
        p.objectKey("label"); p.stringValue(m.label);
        p.objectKey("read?"); p.booleanValue(m.read);
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

    export let cutsStoreResult(db: Db, cut: Cut, r: CutResult): CutsResult throws Bubble {
      if (!cutsKnownStatus(r.status)) {
        return cutsInvalid([new FieldError("status", "is invalid")]);
      }
      db.exec(
        "UPDATE cuts SET thesis = $1, threads = $2, tensions = $3, not_supported = $4, dropped = $5, content_sha = $6, status = $7, members = $8, updated_at = $9 WHERE id = $10",
        [r.thesis, cutsThreadsJson(r.threads), cutsTensionsJson(r.tensions), r.notSupported,
         cutsDroppedJson(r.dropped), r.contentSha, r.status, cutsMembersJson(r.members),
         sysUtcNow(), cut.id.toString()],
      );
      cutsGood(cutsReload(db, cut.id))
    }

## Validation

Keep only what can be checked, and say what was thrown away. Public because
it is the half of this module worth testing: the prompt can be re-tuned
freely, but a change that lets an unlocatable quote through makes every
reading untrustworthy.

    export class CutValidation(
      public thesis: String,
      public threads: List<CutThread>,
      public tensions: List<CutTension>,
      public notSupported: String,
      public dropped: List<String>,
    ) {}

`text(v)`: a trimmed string, else empty.

    let cutsText(v: JsonSyntaxTree?): String {
      if (v is JsonString) { sysStringTrim(v.content) } else { "" }
    }

`inspect/1` of the string a message quotes: double quotes, with backslash,
quote, newline, tab and return escaped. The Elixir also wrote `\#{` for a
literal interpolation opener and `\e`, `\0`, `\x..` for control characters;
the first cannot be written in a Blimp string literal (the interpreter
interpolates it) and a model's claim carries none of them.

    let cutsInspectString(s: String): String {
      let a = sysStringReplace(s, "\\", "\\\\");
      let b = sysStringReplace(a, "\"", "\\\"");
      let c = sysStringReplace(b, "\n", "\\n");
      let d = sysStringReplace(c, "\t", "\\t");
      let e = sysStringReplace(d, "\r", "\\r");
      "\"${e}\""
    }

    let cutsShort(s: String): String { cutsInspectString(sysGraphemeTake(s, 40)) }

`inspect/1` of whatever the model put under `member`: `nil` for absent or
null, an integer or float as written, a string quoted. Arrays and objects
(never seen) print as their JSON text.

    let cutsInspect(v: JsonSyntaxTree?): String throws Bubble {
      if (v is JsonNull) {
        "nil"
      } else if (v is JsonString) {
        cutsInspectString(v.content)
      } else if (v is JsonBoolean) {
        if (v.content) { "true" } else { "false" }
      } else if (v is JsonNumeric) {
        v.asJsonNumericToken()
      } else if (v != null) {
        let p = new JsonTextProducer();
        v.produce(p);
        p.toJsonString()
      } else {
        "nil"
      }
    }

`Integer.parse/1`: an optional sign and the digits that follow, ignoring
whatever comes after; nothing to parse is null.

    let cutsParseInt(s: String): Int? {
      var p = String.begin;
      var negative = false;
      if (s.hasIndex(p)) {
        if (s[p] == 45) {
          negative = true;
          p = s.next(p);
        } else if (s[p] == 43) {
          p = s.next(p);
        }
      }
      var n = 0;
      var digits = 0;
      var more = true;
      while (more && s.hasIndex(p)) {
        let c = s[p];
        if (c >= 48 && c <= 57 && digits < 9) {
          n = n * 10 + (c - 48);
          digits += 1;
          p = s.next(p);
        } else {
          more = false;
        }
      }
      if (digits == 0) { null } else if (negative) { 0 - n } else { n }
    }

`as_int/1`: an integer as itself (a float is not one), a string by prefix,
anything else null.

    let cutsAsInt(v: JsonSyntaxTree?): Int? {
      if (v is JsonNumeric) {
        let token = v.asJsonNumericToken();
        let integral = token.split(".").length == 1 && token.split("e").length == 1
          && token.split("E").length == 1;
        if (integral) {
          var r: Int? = null;
          let ok = do { r = token.toInt32(); true } orelse false;
          if (ok) { r } else { null }
        } else {
          null
        }
      } else if (v is JsonString) {
        cutsParseInt(v.content)
      } else {
        null
      }
    }

`ev["member"] || ev["document"]`: the older key is read when `member` is
absent, null or false.

    let cutsMemberKey(ev: JsonSyntaxTree): JsonSyntaxTree? {
      let m = cutsProp(ev, "member");
      var usable = m != null;
      if (m is JsonNull) { usable = false; }
      if (m is JsonBoolean) { if (!m.content) { usable = false; } }
      if (usable) { m } else { cutsProp(ev, "document") }
    }

    let cutsMemberByN(members: List<CutMember>, n: Int?): CutMember? {
      if (n == null) { return null; }
      var i = 0;
      var found: CutMember? = null;
      while (i < members.length && found == null) {
        if (members[i].n == n) { found = members[i]; }
        i += 1;
      }
      found
    }

The evidence of one claim that can be checked. Drops are appended to `bad`.

    let cutsCheckEvidence(
      evidence: JsonSyntaxTree?, members: List<CutMember>, label: String, claim: String,
      bad: ListBuilder<String>,
    ): List<CutPick> throws Bubble {
      let kept = new ListBuilder<CutPick>();
      if (evidence is JsonArray) {
        for (let ev of evidence.elements) {
          let n = cutsAsInt(cutsMemberKey(ev));
          let quoted = cutsText(cutsProp(ev, "quote"));
          let member = cutsMemberByN(members, n);
          if (member == null) {
            bad.add("${label} ${cutsShort(claim)}: member ${cutsInspect(cutsProp(ev, "member"))} is not in this group");
          } else {
            let found = if (quoted == "") { null } else { cutsLocate(quoted, member.text) };
            if (found != null) {
              kept.add(new CutPick(member.n, member.kind, member.id, member.label, found));
            } else {
              bad.add("${label} ${cutsShort(claim)}: quote is not in member ${member.n.toString()}");
            }
          }
        }
      } else {
        bad.add("${label} ${cutsShort(claim)}: no evidence");
      }
      kept.toList()
    }

    class CutGroup(public kept: List<CutThread>, public dropped: List<String>) {}

One list (`threads` or `tensions`) of claims. A claim with no text is
dropped; a claim with fewer than two checkable citations is dropped, with
every citation problem named and then the count. Not a list is nothing, with
no message.

    let cutsCheckGroup(items: JsonSyntaxTree?, members: List<CutMember>, label: String): CutGroup throws Bubble {
      let kept = new ListBuilder<CutThread>();
      let dropped = new ListBuilder<String>();
      if (items is JsonArray) {
        for (let item of items.elements) {
          let claim = cutsText(cutsProp(item, "claim"));
          if (claim == "") {
            dropped.add("${label}: no claim");
          } else {
            let bad = new ListBuilder<String>();
            let evidence = cutsCheckEvidence(cutsProp(item, "evidence"), members, label, claim, bad);
            if (evidence.length >= 2) {
              kept.add(new CutThread(claim, evidence));
              for (let b of bad.toList()) { dropped.add(b); }
            } else {
              for (let b of bad.toList()) { dropped.add(b); }
              dropped.add("${label} ${cutsShort(claim)}: ${evidence.length.toString()} verifiable citation(s), needs 2");
            }
          }
        }
      }
      new CutGroup(kept.toList(), dropped.toList())
    }

    export let cutsValidate(raw: JsonObject, members: List<CutMember>): CutValidation throws Bubble {
      let threads = cutsCheckGroup(raw.propertyValueOrNull("threads"), members, "thread");
      let tensions = cutsCheckGroup(raw.propertyValueOrNull("tensions"), members, "tension");
      let asTensions = new ListBuilder<CutTension>();
      for (let t of tensions.kept) { asTensions.add(new CutTension(t.claim, t.evidence)); }
      let dropped = new ListBuilder<String>();
      for (let d of threads.dropped) { dropped.add(d); }
      for (let d of tensions.dropped) { dropped.add(d); }
      new CutValidation(
        cutsText(raw.propertyValueOrNull("thesis")),
        threads.kept,
        asTensions.toList(),
        cutsText(raw.propertyValueOrNull("not_supported")),
        dropped.toList(),
      )
    }

## The read

The user message: the question if there is one, the group, the members, and
the report asked for. `kind` is `sub-groups` when every member is a folder.

    export let cutsPrompt(cut: Cut, members: List<CutMember>): String {
      var asked = "";
      let question = cut.question;
      if (question != null) {
        if (!sysStringTrim(question).isEmpty) { asked = "The reader asks: ${question}\n\n"; }
      }
      var allFolders = true;
      for (let m of members) { if (m.kind != "folder") { allFolders = false; } }
      let kind = if (allFolders) { "sub-groups" } else { "documents" };
      let parts = new ListBuilder<String>();
      for (let m of members) {
        parts.add("### Member ${m.n.toString()}: ${m.label}\n\n${m.text}\n");
      }
      cutsUserPrompt(asked, cut.title, kind, sysJoin(parts.toList(), "\n"))
    }

The topic a page watches to learn a read moved.

    export let cutsTopic(cutId: Int): String { "cut:${cutId.toString()}" }

The page's step before a read: mark the cut `reading` and tell watchers.

    export let cutsStartRead(db: Db, cut: Cut): Cut throws Bubble {
      let started = cutsSetStatus(db, cut, "reading", null);
      versionsBump(db, cutsTopic(cut.id));
      started
    }

Read a folder, and store only what could be checked. Slow: one model call
(effort high, temperature 0.3, 8000 tokens, JSON), no retry of a bad answer.
The runs library calls this inside a job; it never forks itself.

An empty folder fails with `this folder holds nothing to read`; a model
failure fails with the error's text. Both leave the cut `failed` and are
returned as `ok` (the stored cut) with `error` set to the same text; on
success `error` is null and `status_detail` is not cleared. Watchers of
`cutsTopic` are told when the cut stops being `reading`.

    export let cutsRead(db: Db, llm: LlmClient, cut: Cut): CutsResult throws Bubble {
      let user = accountsGetUser(db, cut.userId);
      let scope = scopeFor(user);
      let members = cutsMembers(db, scope, cut.folderId);
      if (members.length == 0) {
        let text = "this folder holds nothing to read";
        let failed = cutsSetStatus(db, cut, "failed", text);
        versionsBump(db, cutsTopic(cut.id));
        return new CutsResult(failed, text, []);
      }
      let call = new LlmCall(
        [new LlmMessage("system", cutsSystemPrompt()),
         new LlmMessage("user", cutsPrompt(cut, members))],
        null, "high", 8000, 0.3, true, [], null, 0,
      );
      let reply = llm.json(call);
      let raw = reply.ok;
      var outcome: CutsResult = new CutsResult(null, "no reply", []);
      if (raw != null) {
        let v = cutsValidate(raw, members);
        let refs = new ListBuilder<CutMemberRef>();
        for (let m of members) { refs.add(m.ref()); }
        outcome = cutsStoreResult(db, cut, new CutResult(
          v.thesis, v.threads, v.tensions, v.notSupported, v.dropped,
          cutsContentSha(members), "read", refs.toList(),
        ));
      } else {
        let e = reply.err;
        let text = if (e != null) { llmErrorText(e) } else { "no reply" };
        let failed = cutsSetStatus(db, cut, "failed", text);
        outcome = new CutsResult(failed, text, []);
      }
      versionsBump(db, cutsTopic(cut.id));
      outcome
    }

A restart mid-read leaves `reading` forever; the Elixir recovery did not sweep
cuts. This does, for the recovery in `runs` to call at boot: every cut still
`reading` becomes `failed` with `interrupted by a restart`. Returns how many.

    export let cutsSweepReading(db: Db): Int throws Bubble {
      db.exec(
        "UPDATE cuts SET status = 'failed', status_detail = 'interrupted by a restart', updated_at = $1 WHERE status = 'reading'",
        [sysUtcNow()],
      )
    }
