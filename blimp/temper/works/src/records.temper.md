# The records

One class per table of the works context, field for field the Ecto schemas
of `Marginalia.Works.*`, with a `fromRow` that reads a `DbRow` and a
`<name>Columns` SELECT list so that every query decodes the same way. Ids are
`Int`, timestamps are `String` ("YYYY-MM-DD HH:MM:SS", UTC), nullable columns
are `String?` or `Int?`, array columns are lists decoded from their JSON text.

    let { DbRow } = import("db/src");
    let { parseJson, JsonSyntaxTree, JsonArray } = import("std/json");

## Work

`slug` is 22 characters of URL-safe base64, minted once. `wordCount` is the
count of the raw upload until the first edit recomputes it (spec section 10,
hazard 2).

    export class Work(
      public id: Int,
      public userId: Int,
      public slug: String,
      public title: String,
      public intent: String?,
      public sourceUrl: String?,
      public collection: String?,
      public collectionRole: String?,
      public body: String,
      public baselineBody: String?,
      public wordCount: Int,
      public status: String,
      public statusDetail: String?,
      public firstImpression: String?,
      public folderId: Int?,
      public derivedFromId: Int?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Work throws Bubble {
        new Work(
          row.int("id"),
          row.int("user_id"),
          row.str("slug"),
          row.str("title"),
          row.strOrNull("intent"),
          row.strOrNull("source_url"),
          row.strOrNull("collection"),
          row.strOrNull("collection_role"),
          row.str("body"),
          row.strOrNull("baseline_body"),
          row.int("word_count"),
          row.str("status"),
          row.strOrNull("status_detail"),
          row.strOrNull("first_impression"),
          row.intOrNull("folder_id"),
          row.intOrNull("derived_from_id"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let workColumns = "id, user_id, slug, title, intent, source_url, collection, collection_role, body, baseline_body, word_count, status, status_detail, first_impression, folder_id, derived_from_id, inserted_at, updated_at";

## Section

The `summary*` columns are written by the summary context; `summaryCovers`
and `summaryDropped` are JSON string arrays, `summaryFollows` a JSON array of
integers.

    export class Section(
      public id: Int,
      public workId: Int,
      public ordinal: Int,
      public title: String,
      public body: String,
      public wordCount: Int,
      public status: String,
      public summary: String?,
      public summaryFingerprint: String?,
      public summarisedAt: String?,
      public summaryCovers: List<String>,
      public summaryFollows: List<Int>,
      public summarySetsUp: String?,
      public summaryDropped: List<String>,
      public summaryBody: String?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Section throws Bubble {
        new Section(
          row.int("id"),
          row.int("work_id"),
          row.int("ordinal"),
          row.str("title"),
          row.str("body"),
          row.int("word_count"),
          row.str("status"),
          row.strOrNull("summary"),
          row.strOrNull("summary_fingerprint"),
          row.strOrNull("summarised_at"),
          row.strList("summary_covers"),
          row.intList("summary_follows"),
          row.strOrNull("summary_sets_up"),
          row.strList("summary_dropped"),
          row.strOrNull("summary_body"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let sectionColumns = "id, work_id, ordinal, title, body, word_count, status, summary, summary_fingerprint, summarised_at, summary_covers, summary_follows, summary_sets_up, summary_dropped, summary_body, inserted_at, updated_at";

## GraphNode

The `nodes` table. `Node` is a name Temper's own library takes, so the class
is `GraphNode`.

    export class GraphNode(
      public id: Int,
      public workId: Int,
      public sectionId: Int?,
      public nodeType: String,
      public title: String,
      public body: String?,
      public quote: String?,
      public ordinal: Int,
      public status: String,
      public narrative: String?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): GraphNode throws Bubble {
        new GraphNode(
          row.int("id"),
          row.int("work_id"),
          row.intOrNull("section_id"),
          row.str("node_type"),
          row.str("title"),
          row.strOrNull("body"),
          row.strOrNull("quote"),
          row.int("ordinal"),
          row.str("status"),
          row.strOrNull("narrative"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let graphNodeColumns = "id, work_id, section_id, node_type, title, body, quote, ordinal, status, narrative, inserted_at, updated_at";

## GraphEdge

    export class GraphEdge(
      public id: Int,
      public workId: Int,
      public fromId: Int,
      public toId: Int,
      public edgeType: String,
      public ordinal: Int,
      public rationale: String?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): GraphEdge throws Bubble {
        new GraphEdge(
          row.int("id"),
          row.int("work_id"),
          row.int("from_id"),
          row.int("to_id"),
          row.str("edge_type"),
          row.int("ordinal"),
          row.strOrNull("rationale"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let graphEdgeColumns = "id, work_id, from_id, to_id, edge_type, ordinal, rationale, inserted_at, updated_at";

## GraphEvent

One tool call of a decision-graph build and its answer. `nodeId` is a plain
integer, not a foreign key.

    export class GraphEvent(
      public id: Int,
      public workId: Int,
      public narrative: String?,
      public seq: Int,
      public tool: String,
      public args: String?,
      public result: String?,
      public ok: Boolean,
      public nodeId: Int?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): GraphEvent throws Bubble {
        new GraphEvent(
          row.int("id"),
          row.int("work_id"),
          row.strOrNull("narrative"),
          row.int("seq"),
          row.str("tool"),
          row.strOrNull("args"),
          row.strOrNull("result"),
          row.bool("ok"),
          row.intOrNull("node_id"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let graphEventColumns = "id, work_id, narrative, seq, tool, args, result, ok, node_id, inserted_at, updated_at";

## Revision

`before` and `after` are the exact text of a replaced passage. They are
quoted in the column list because SQLite reserves both words in some
positions.

    export class Revision(
      public id: Int,
      public workId: Int,
      public sectionId: Int?,
      public sectionOrdinal: Int?,
      public seq: Int,
      public before: String,
      public after: String,
      public origin: String,
      public note: String?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Revision throws Bubble {
        new Revision(
          row.int("id"),
          row.int("work_id"),
          row.intOrNull("section_id"),
          row.intOrNull("section_ordinal"),
          row.int("seq"),
          row.str("before"),
          row.str("after"),
          row.str("origin"),
          row.strOrNull("note"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let revisionColumns = "id, work_id, section_id, section_ordinal, seq, \"before\", \"after\", origin, note, inserted_at, updated_at";

## Attachment

    export class Attachment(
      public id: Int,
      public workId: Int,
      public name: String,
      public kind: String,
      public content: String,
      public byteSize: Int,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Attachment throws Bubble {
        new Attachment(
          row.int("id"),
          row.int("work_id"),
          row.str("name"),
          row.str("kind"),
          row.str("content"),
          row.int("byte_size"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let attachmentColumns = "id, work_id, name, kind, content, byte_size, inserted_at, updated_at";

## Correction

    export class Correction(
      public id: Int,
      public workId: Int,
      public kind: String,
      public about: String,
      public ruling: String?,
      public sectionOrdinal: Int?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Correction throws Bubble {
        new Correction(
          row.int("id"),
          row.int("work_id"),
          row.str("kind"),
          row.str("about"),
          row.strOrNull("ruling"),
          row.intOrNull("section_ordinal"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let correctionColumns = "id, work_id, kind, about, ruling, section_ordinal, inserted_at, updated_at";

## DocumentSummary

The three item lists are Postgres `jsonb[]` in Elixir: lists of string-keyed
maps. Here each is the JSON text of an array (`movementsJson`, ...) and its
parsed elements (`movements`, ...), one `JsonSyntaxTree` per item.

    export class DocumentSummary(
      public id: Int,
      public workId: Int,
      public summary: String?,
      public throughline: String?,
      public movementsJson: String,
      public movements: List<JsonSyntaxTree>,
      public guidelinesJson: String,
      public guidelines: List<JsonSyntaxTree>,
      public tensionsJson: String,
      public tensions: List<JsonSyntaxTree>,
      public fingerprint: String?,
      public dropped: List<String>,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): DocumentSummary throws Bubble {
        new DocumentSummary(
          row.int("id"),
          row.int("work_id"),
          row.strOrNull("summary"),
          row.strOrNull("throughline"),
          documentItemsJson(row.strOrNull("movements")),
          documentItems(row.strOrNull("movements")),
          documentItemsJson(row.strOrNull("guidelines")),
          documentItems(row.strOrNull("guidelines")),
          documentItemsJson(row.strOrNull("tensions")),
          documentItems(row.strOrNull("tensions")),
          row.strOrNull("fingerprint"),
          row.strList("dropped"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let documentSummaryColumns = "id, work_id, summary, throughline, movements, guidelines, tensions, fingerprint, dropped, inserted_at, updated_at";

A NULL column reads as the empty array, as an Ecto default of `[]` did.

    let documentItemsJson(text: String?): String {
      if (text != null) { text } else { "[]" }
    }

    let documentItems(text: String?): List<JsonSyntaxTree> throws Bubble {
      if (text != null) {
        let tree = parseJson(text);
        if (!(tree is JsonArray)) { bubble() }
        let arr = tree as JsonArray orelse panic();
        arr.elements
      } else {
        []
      }
    }
