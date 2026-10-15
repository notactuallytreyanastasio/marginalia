# Folder records

`Folder` mirrors the `folders` table column for column. A folder is a
place, not a property: it has a name, an owner and maybe a parent.

    let { DbRow } = import("db/src");
    let { FieldError } = import("core/src");

    export class Folder(
      public id: Int,
      public name: String,
      public publishedAt: String?,
      public slug: String?,
      public userId: Int,
      public parentId: Int?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Folder throws Bubble {
        new Folder(
          row.int("id"),
          row.str("name"),
          row.strOrNull("published_at"),
          row.strOrNull("slug"),
          row.int("user_id"),
          row.intOrNull("parent_id"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

The columns of `Folder`, in the order `core`'s statements select them.

    export let foldersColumns = "id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at";

## FolderWork

The works library owns `Work`. The works index only needs a few of its
columns to draw a row in the tree, so this context selects those into its
own small record rather than depend on `works`: the id, the title, the slug
for the link, the word count and status for the badges, where it is filed,
and the collection it was imported under (the backfill reads it).

    export class FolderWork(
      public id: Int,
      public title: String,
      public slug: String,
      public wordCount: Int,
      public status: String,
      public folderId: Int?,
      public collection: String?,
      public collectionRole: String?,
      public insertedAt: String,
    ) {
      public static fromRow(row: DbRow): FolderWork throws Bubble {
        new FolderWork(
          row.int("id"),
          row.str("title"),
          row.str("slug"),
          row.int("word_count"),
          row.str("status"),
          row.intOrNull("folder_id"),
          row.strOrNull("collection"),
          row.strOrNull("collection_role"),
          row.str("inserted_at"),
        )
      }
    }

    export let foldersWorkColumns = "id, title, slug, word_count, status, folder_id, collection, collection_role, inserted_at";

## FolderNode

One node of `foldersTree`: the folder (null for the root), the drafts filed
directly in it (newest id first), its child nodes in sibling order, and
`count`, the drafts in it and below it.

    export class FolderNode(
      public folder: Folder?,
      public works: List<FolderWork>,
      public folders: List<FolderNode>,
      public count: Int,
    ) {}

## FoldersResult

What the Elixir returned as `{:ok, x} | {:error, reason}`. `error` is one of
`"not_found"`, `"cycle"`, `"not_owner"`, `"slug_taken"`, `"invalid"`; for
`"invalid"` the `errors` carry the field errors (`name` plus Ecto's message).
`folder` is the folder written; `placedIn` is only set by `foldersMoveWork`:
the folder the draft now sits in, null for the root (the Elixir's
`moved.folder_id`).

    export class FoldersResult(
      public ok: Boolean,
      public folder: Folder?,
      public placedIn: Int?,
      public error: String?,
      public errors: List<FieldError>,
    ) {}
