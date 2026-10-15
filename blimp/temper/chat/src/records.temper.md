# The records

`conversations` and `messages`, field for field the Ecto schemas
`Marginalia.Chat.Conversation` and `Marginalia.Chat.Message`.

`anchorKind` is `work` (the whole-draft chat), `block` (a thread pinned to one
paragraph) or `span` (pinned to a passage selected inside one). The Elixir
changeset allows exactly those three. There is no `link_id` column: it was
added and fully removed again in migration 20260916010000, and the pairwise
link chat keeps nothing in these tables.

    let { DbRow } = import("db/src");

    export class Conversation(
      public id: Int,
      public workId: Int,
      public title: String?,
      public mode: String,
      public anchorKind: String,
      public sectionId: Int?,
      public blockRef: String?,
      public quote: String?,
      public resolvedAt: String?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Conversation throws Bubble {
        new Conversation(
          row.int("id"),
          row.int("work_id"),
          row.strOrNull("title"),
          row.str("mode"),
          row.str("anchor_kind"),
          row.intOrNull("section_id"),
          row.strOrNull("block_ref"),
          row.strOrNull("quote"),
          row.strOrNull("resolved_at"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let chatConversationColumns = "id, work_id, title, mode, anchor_kind, section_id, block_ref, quote, resolved_at, inserted_at, updated_at";

`messages` has `inserted_at` only.

    export class Message(
      public id: Int,
      public conversationId: Int,
      public role: String,
      public content: String,
      public insertedAt: String,
    ) {
      public static fromRow(row: DbRow): Message throws Bubble {
        new Message(
          row.int("id"),
          row.int("conversation_id"),
          row.str("role"),
          row.str("content"),
          row.str("inserted_at"),
        )
      }
    }

    export let chatMessageColumns = "id, conversation_id, role, content, inserted_at";
