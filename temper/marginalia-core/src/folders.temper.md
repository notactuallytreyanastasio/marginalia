# Folders, in SQL built by Alloy

Every statement the Folders context sends to Postgres is built here, with
[Alloy](https://github.com/notactuallytreyanastasio/alloy), a Temper ORM:
its query builder, its `sql` tag, which keeps each value a typed part
rather than text, and its changesets. `Marginalia.Folders` runs what this
returns and turns rows into structs. Nothing here touches a connection.

    let {
      from, sql, col, safeIdentifier, update, deleteFrom, changeset,
      Changeset, Query, TableDef, FieldDef, StringField, Int64Field, DateField,
      SqlFragment, SqlPart, SqlSource, SqlString, SqlInt32, SqlInt64,
      SqlBoolean, SqlFloat64, SqlDate, SqlBuilder, SafeIdentifier,
    } = import("orm/src");

## What crosses to Elixir

Alloy's objects are ordinary Temper classes, which be-elixir keeps on a
per-process heap. If they reached Elixir, every LiveView process that
opened a folder would collect them until it remembered to `collect/1`. So
each function here finishes the statement inside Temper and hands back
`@imu` values, which are plain Elixir structs: the SQL text with `$1`,
`$2`, ... and the parameters, each with its kind.

Alloy's own `toParameterized` gives every value as text. Postgres would
accept that for text parameters, but Postgrex encodes each parameter in
binary by its type, so a string sent for a `bigint` column is refused. The
kind is what lets `Marginalia.Alloy` hand Postgrex an integer for an
integer.

    @imu export class Param(public kind: String, public text: String) {}
    @imu export class Statement(public text: String, public params: List<Param>) {}
    @imu export class FieldError(public field: String, public message: String) {}

A write that a changeset may refuse comes back as one of these: a
statement, or the errors that stopped it.

    @imu export class Prepared(public statement: Statement?, public errors: List<FieldError>) {}

`statementOf` walks a fragment's parts. Values become placeholders and
parameters; everything Alloy already knows is safe (identifiers, keywords,
`DEFAULT`, our own SQL source) stays in the text, as Alloy writes it.

    let statementOf(fragment: SqlFragment): Statement {
      let text = new StringBuilder();
      let params = new ListBuilder<Param>();
      for (let part of fragment.parts) {
        let param = paramOf(part);
        if (param == null) {
          part.formatTo(text);
        } else {
          params.add(param);
          text.append("$");
          text.append(params.length.toString());
        }
      }
      new Statement(text.toString(), params.toList())
    }

    let paramOf(part: SqlPart): Param? {
      if (part is SqlString) {
        return new Param("text", (part as SqlString orelse panic()).value);
      }
      if (part is SqlInt64) {
        return new Param("int", (part as SqlInt64 orelse panic()).value.toString());
      }
      if (part is SqlInt32) {
        return new Param("int", (part as SqlInt32 orelse panic()).value.toString());
      }
      if (part is SqlBoolean) {
        return new Param("bool", if ((part as SqlBoolean orelse panic()).value) { "true" } else { "false" });
      }
      if (part is SqlFloat64) {
        return new Param("float", (part as SqlFloat64 orelse panic()).value.toString());
      }
      if (part is SqlDate) {
        return new Param("date", (part as SqlDate orelse panic()).value.toString());
      }
      null
    }

## The table

    let id(name: String): SafeIdentifier { safeIdentifier(name) orelse panic() }

Every column the struct has, in one place, so a `SELECT` and a
`RETURNING` can never disagree about what a folder is.

    let columns = [
      "id", "name", "published_at", "slug", "user_id", "parent_id",
      "inserted_at", "updated_at",
    ];

    let columnIds(): List<SafeIdentifier> { columns.map { (c): SafeIdentifier => id(c) } }

The timestamps are `timestamp(0)` columns that Ecto used to fill in from
the application, truncated to the second, in UTC. They have no database
default, so their default here is that same expression as SQL.

    let now = "date_trunc('second', now() at time zone 'utc')";

    let folders = new TableDef(
      id("folders"),
      [
        new FieldDef(id("name"), new StringField(), false, null, false),
        new FieldDef(id("parent_id"), new Int64Field(), true, null, false),
        new FieldDef(id("user_id"), new Int64Field(), false, null, false),
        new FieldDef(id("inserted_at"), new DateField(), false, new SqlSource(now), false),
        new FieldDef(id("updated_at"), new DateField(), false, new SqlSource(now), false),
      ],
      null,
    );

`returning` closes an `INSERT` or `UPDATE` with the whole row.

    let returning(statement: SqlFragment): Statement {
      let b = new SqlBuilder();
      b.appendFragment(statement);
      b.appendSafe(" RETURNING ");
      b.appendSafe(columns.join(", ") { (c): String => c });
      statementOf(b.accumulated)
    }

    let nullable(value: Int64?): SqlPart {
      if (value == null) { new SqlSource("NULL") } else { new SqlInt64(value) }
    }

## Reading

Sibling order is case-insensitive, by Postgres's `lower`, then by id.
Alloy orders by columns, not expressions, so the lowered name is selected
as `name_key` and ordered by that. Sorting in Elixir instead would order
non-ASCII names by a different rule than the database does.

    export let listFolders(userId: Int64): Statement {
      let exprs = new ListBuilder<SqlFragment>();
      for (let c of columns) { exprs.add(col(id("folders"), id(c))); }
      exprs.add(sql"lower(name) AS name_key");
      statementOf(
        from(id("folders"))
          .selectExpr(exprs.toList())
          .where(sql"user_id = ${userId}")
          .orderBy(id("name_key"), true)
          .orderBy(id("id"), true)
          .toSql()
      )
    }

    export let getFolder(userId: Int64, folderId: Int64): Statement {
      statementOf(
        from(id("folders")).select(columnIds())
          .where(sql"user_id = ${userId}")
          .where(sql"id = ${folderId}")
          .toSql()
      )
    }

For a preload: folders by id, whoever owns them, as `preload(:folder)` was.

    export let foldersByIds(ids: List<Int64>): Statement {
      statementOf(
        from(id("folders")).select(columnIds())
          .whereIn(id("id"), ids.map { (i): SqlPart => new SqlInt64(i) })
          .toSql()
      )
    }

The importers find a folder by name anywhere in the tree.

    export let folderByName(userId: Int64, name: String): Statement {
      statementOf(
        from(id("folders")).select(columnIds())
          .where(sql"user_id = ${userId}")
          .where(sql"name = ${name}")
          .toSql()
      )
    }

The folder a unique index says is already there, beside where a new one
was meant to go.

    export let sibling(userId: Int64, name: String, parentId: Int64?): Statement {
      let q = from(id("folders")).select(columnIds())
        .where(sql"user_id = ${userId}")
        .where(sql"name = ${name}");
      let scoped = if (parentId == null) {
        q.whereNull(id("parent_id"))
      } else {
        q.where(sql"parent_id = ${parentId}")
      };
      statementOf(scoped.toSql())
    }

## Writing

A folder's name is trimmed, then required and at most 80 characters.
Alloy counts code points where Ecto counted graphemes, so a name built
from combining characters can be a little shorter than it used to be.
The unique sibling-name index is enforced by Postgres, as before;
`Marginalia.Folders` turns its violation into an error on `name`.

    let nameErrors(cs: Changeset): List<FieldError> {
      cs.errors.map { (e): FieldError => new FieldError(e.field, e.message) }
    }

    export let createFolder(userId: Int64, name: String, parentId: Int64?): Prepared {
      let params = new MapBuilder<String, String>();
      params.set("name", trim(name));
      params.set("user_id", userId.toString());
      if (parentId != null) { params.set("parent_id", parentId.toString()); }
      let cs = changeset(folders, params.toMap())
        .cast([id("name"), id("parent_id"), id("user_id")])
        .validateRequired([id("name")])
        .validateLength(id("name"), 1, 80);
      if (!cs.isValid) { return new Prepared(null, nameErrors(cs)); }
      new Prepared(returning(cs.toInsertSql() orelse panic()), [])
    }

    export let renameFolder(userId: Int64, folderId: Int64, name: String): Prepared {
      let params = new MapBuilder<String, String>();
      params.set("name", trim(name));
      let cs = changeset(folders, params.toMap())
        .cast([id("name")])
        .validateRequired([id("name")])
        .validateLength(id("name"), 1, 80);
      if (!cs.isValid) { return new Prepared(null, nameErrors(cs)); }
      new Prepared(
        returning(
          update(id("folders"))
            .set(id("name"), new SqlString(trim(name)))
            .set(id("updated_at"), new SqlSource(now))
            .where(sql"user_id = ${userId}")
            .where(sql"id = ${folderId}")
            .toSql() orelse panic()
        ),
        [],
      )
    }

    export let moveFolder(userId: Int64, folderId: Int64, parentId: Int64?): Statement {
      returning(
        update(id("folders"))
          .set(id("parent_id"), nullable(parentId))
          .set(id("updated_at"), new SqlSource(now))
          .where(sql"user_id = ${userId}")
          .where(sql"id = ${folderId}")
          .toSql() orelse panic()
      )
    }

Deleting a folder is three statements, which `Marginalia.Folders` runs in
one transaction: its drafts and its child folders move up to its parent,
then it goes.

    export let deleteFolder(folderId: Int64, parentId: Int64?): List<Statement> {
      [
        statementOf(
          update(id("works")).set(id("folder_id"), nullable(parentId))
            .where(sql"folder_id = ${folderId}").toSql() orelse panic()
        ),
        statementOf(
          update(id("folders")).set(id("parent_id"), nullable(parentId))
            .where(sql"parent_id = ${folderId}").toSql() orelse panic()
        ),
        returning(deleteFrom(id("folders")).where(sql"id = ${folderId}").toSql() orelse panic()),
      ]
    }

Filing a draft touches the `works` table, which belongs to `Works`; the
statement updates the one column this context owns there, and the
timestamp Ecto would have bumped.

    export let moveWork(userId: Int64, workId: Int64, folderId: Int64?): Statement {
      statementOf(
        update(id("works"))
          .set(id("folder_id"), nullable(folderId))
          .set(id("updated_at"), new SqlSource(now))
          .where(sql"user_id = ${userId}")
          .where(sql"id = ${workId}")
          .toSql() orelse panic()
      )
    }

## The backfill

    export let unfiledCount(userId: Int64): Statement {
      statementOf(looseWorks(userId).countSql())
    }

    let looseWorks(userId: Int64): Query {
      from(id("works"))
        .where(sql"user_id = ${userId}")
        .whereNotNull(id("collection"))
        .whereNull(id("folder_id"))
    }

    export let looseWorkCollections(userId: Int64): Statement {
      statementOf(looseWorks(userId).select([id("id"), id("collection")]).toSql())
    }

    export let fileWorks(workIds: List<Int64>, folderId: Int64): Statement {
      statementOf(
        update(id("works"))
          .set(id("folder_id"), new SqlInt64(folderId))
          .where(sql"id IN (${workIds})")
          .toSql() orelse panic()
      )
    }

## Publishing

The slug is minted in Elixir; these write and read what it decided.

    export let publish(userId: Int64, folderId: Int64, slug: String): Statement {
      returning(
        update(id("folders"))
          .set(id("published_at"), new SqlSource(now))
          .set(id("slug"), new SqlString(slug))
          .set(id("updated_at"), new SqlSource(now))
          .where(sql"user_id = ${userId}")
          .where(sql"id = ${folderId}")
          .toSql() orelse panic()
      )
    }

    export let unpublish(userId: Int64, folderId: Int64): Statement {
      returning(
        update(id("folders"))
          .set(id("published_at"), new SqlSource("NULL"))
          .set(id("updated_at"), new SqlSource(now))
          .where(sql"user_id = ${userId}")
          .where(sql"id = ${folderId}")
          .toSql() orelse panic()
      )
    }

    export let publishedBySlug(slug: String): Statement {
      statementOf(
        from(id("folders")).select(columnIds())
          .where(sql"slug = ${slug}")
          .whereNotNull(id("published_at"))
          .toSql()
      )
    }

    export let published(): Statement {
      statementOf(
        from(id("folders")).select(columnIds())
          .whereNotNull(id("published_at"))
          .orderBy(id("published_at"), false)
          .toSql()
      )
    }

    export let slugTaken(slug: String): Statement {
      let q = from(id("folders")).select([id("id")]).where(sql"slug = ${slug}");
      statementOf((q.limit(1) orelse panic()).toSql())
    }
