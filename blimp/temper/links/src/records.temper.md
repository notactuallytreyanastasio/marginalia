# The records

`Link` and `LinkEdge`, field for field the Ecto schemas
(`lib/marginalia/links/link.ex`, `link_edge.ex`), with a `fromRow` each and a
column list so every query decodes the same way.

    let { DbRow } = import("db/src");
    let { Work, GraphNode } = import("works/src");

## Link

Two manuscripts, stored lowest id first (`aWorkId < bWorkId`, kept by
`linksGetOrCreate`), and the state of the pass that relates them. `status` is
one of `pending linking linked failed`. `error` was `varchar(255)` in the
Postgres schema; `linksSetStatus` still cuts it at 255 characters so the text
a reader sees is the one the original could store.

    export class Link(
      public id: Int,
      public aWorkId: Int,
      public bWorkId: Int,
      public status: String,
      public summary: String?,
      public error: String?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Link throws Bubble {
        new Link(
          row.int("id"),
          row.int("a_work_id"),
          row.int("b_work_id"),
          row.str("status"),
          row.strOrNull("summary"),
          row.strOrNull("error"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let linkColumns = "id, a_work_id, b_work_id, status, summary, error, inserted_at, updated_at";

## LinkEdge

One directed relation between a node of one manuscript and a node of the
other. `edgeType` is one of `develops pays_off requires tension answers echoes`
(checked when storing, by `linksStoreEdges`).

    export class LinkEdge(
      public id: Int,
      public linkId: Int,
      public fromId: Int,
      public toId: Int,
      public edgeType: String,
      public rationale: String?,
      public ordinal: Int,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): LinkEdge throws Bubble {
        new LinkEdge(
          row.int("id"),
          row.int("link_id"),
          row.int("from_id"),
          row.int("to_id"),
          row.str("edge_type"),
          row.strOrNull("rationale"),
          row.int("ordinal"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let linkEdgeColumns = "id, link_id, from_id, to_id, edge_type, rationale, ordinal, inserted_at, updated_at";

## Joined views

Ecto preloaded `a_work`/`b_work` on a link and `from`/`to` on an edge. Here
the preload is a class: the record and what it points at, loaded together.

    export class LinkWorks(public link: Link, public aWork: Work, public bWork: Work) {}

    export class LinkEdgeEnds(public edge: LinkEdge, public from: GraphNode, public to: GraphNode) {}
