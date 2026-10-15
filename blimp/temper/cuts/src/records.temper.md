# Cut records

A `cut` is the one reading a folder has. The table keeps its structured
parts as JSON text: `threads` and `tensions` are arrays of claims with their
evidence, `dropped` is an array of strings, `members` is an array of the
members that were read. The Elixir stored JSON arrays of string-keyed maps,
and the notes give their exact shape, so each is a typed class here and
`fromRow` decodes through `DbRow.json`.

    let { DbRow } = import("db/src");
    let { JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonBoolean,
          JsonNumeric } = import("std/json");

## Reading JSON the tolerant way

A stored row may come from an older build, so a missing key is the empty
value, not a bubble. These are the only places a stored tree is looked into.

    let cutsProp(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

    let cutsStr(t: JsonSyntaxTree?, key: String): String {
      let v = cutsProp(t, key);
      if (v is JsonString) { v.content } else { "" }
    }

    let cutsIntOf(t: JsonSyntaxTree?, key: String): Int {
      let v = cutsProp(t, key);
      if (v is JsonNumeric) { do { v.asInt32() } orelse 0 } else { 0 }
    }

    let cutsBoolOf(t: JsonSyntaxTree?, key: String): Boolean {
      let v = cutsProp(t, key);
      if (v is JsonBoolean) { v.content } else { false }
    }

    let cutsElements(t: JsonSyntaxTree?): List<JsonSyntaxTree> {
      if (t is JsonArray) { t.elements } else { [] }
    }

## CutPick

One citation: the member it came from, and the member's own wording (not the
model's). `kind` is `work` or `folder`, `id` the work's or folder's id.

    export class CutPick(
      public member: Int,
      public kind: String,
      public id: Int,
      public label: String,
      public quote: String,
    ) {
      public static fromTree(t: JsonSyntaxTree): CutPick {
        new CutPick(
          cutsIntOf(t, "member"), cutsStr(t, "kind"), cutsIntOf(t, "id"),
          cutsStr(t, "label"), cutsStr(t, "quote"),
        )
      }
    }

    let cutsPicksOf(t: JsonSyntaxTree?): List<CutPick> {
      let out = new ListBuilder<CutPick>();
      for (let el of cutsElements(t)) { out.add(CutPick.fromTree(el)); }
      out.toList()
    }

## CutThread and CutTension

A thread is something true across two or more members that no single one
states; a tension is a place the members disagree. Same shape, two names, so
a page cannot hand one where the other is wanted.

    export class CutThread(public claim: String, public evidence: List<CutPick>) {
      public static fromTree(t: JsonSyntaxTree): CutThread {
        new CutThread(cutsStr(t, "claim"), cutsPicksOf(cutsProp(t, "evidence")))
      }
    }

    export class CutTension(public claim: String, public evidence: List<CutPick>) {
      public static fromTree(t: JsonSyntaxTree): CutTension {
        new CutTension(cutsStr(t, "claim"), cutsPicksOf(cutsProp(t, "evidence")))
      }
    }

## CutMemberRef

What is stored about a member after a read: `n`, `kind`, `id`, `label` and
`read?` (the key keeps its question mark, as the Elixir wrote it). The text
is not stored; see `CutMember` in `cuts.temper.md` for the live thing.

    export class CutMemberRef(
      public n: Int,
      public kind: String,
      public id: Int,
      public label: String,
      public read: Boolean,
    ) {
      public static fromTree(t: JsonSyntaxTree): CutMemberRef {
        new CutMemberRef(
          cutsIntOf(t, "n"), cutsStr(t, "kind"), cutsIntOf(t, "id"),
          cutsStr(t, "label"), cutsBoolOf(t, "read?"),
        )
      }
    }

## Cut

Mirrors the `cuts` table column for column. `scope` is `folder` (the only
value anything writes). A cut that was never read has no `thesis`.

    export class Cut(
      public id: Int,
      public title: String,
      public question: String?,
      public status: String,
      public statusDetail: String?,
      public thesis: String?,
      public threads: List<CutThread>,
      public tensions: List<CutTension>,
      public notSupported: String?,
      public dropped: List<String>,
      public contentSha: String?,
      public userId: Int,
      public folderId: Int?,
      public scope: String,
      public members: List<CutMemberRef>,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Cut throws Bubble {
        let threads = new ListBuilder<CutThread>();
        for (let el of cutsElements(row.json("threads"))) { threads.add(CutThread.fromTree(el)); }
        let tensions = new ListBuilder<CutTension>();
        for (let el of cutsElements(row.json("tensions"))) { tensions.add(CutTension.fromTree(el)); }
        let members = new ListBuilder<CutMemberRef>();
        for (let el of cutsElements(row.json("members"))) { members.add(CutMemberRef.fromTree(el)); }
        new Cut(
          row.int("id"),
          row.str("title"),
          row.strOrNull("question"),
          row.str("status"),
          row.strOrNull("status_detail"),
          row.strOrNull("thesis"),
          threads.toList(),
          tensions.toList(),
          row.strOrNull("not_supported"),
          row.strList("dropped"),
          row.strOrNull("content_sha"),
          row.int("user_id"),
          row.intOrNull("folder_id"),
          row.str("scope"),
          members.toList(),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let cutsColumns = "id, title, question, status, status_detail, thesis, threads, tensions, not_supported, dropped, content_sha, user_id, folder_id, scope, members, inserted_at, updated_at";

The statuses a cut may hold (`Cut.changeset` validates against these).

    export let cutsStatuses(): List<String> { ["draft", "reading", "read", "failed"] }
