# Orm

## SQLite

Alloy came from a Postgres project. This copy emits SQL that SQLite runs
(checked against `sqlite3` 3.51; nothing below needs more than 3.35). Every
dialect decision, in one place:

- **`SqlDefault` is omitted from INSERT.** SQLite has no `DEFAULT` in a
  `VALUES` list. `toInsertSql` leaves such a column out; if no column is left
  it writes `INSERT INTO t DEFAULT VALUES`. The column's own `DEFAULT` in the
  `CREATE TABLE` fills it. A hand-built fragment containing `SqlDefault` still
  renders the text `DEFAULT`, which SQLite rejects.
- **`timestamps()` defaults to `strftime('%Y-%m-%d %H:%M:%S','now')`**
  (exported as `sqliteNow`), a `SqlSource`, so INSERT writes the expression
  and `toUpdateSql` / `toUpdateSqlWhere` set `updated_at` to it unless the
  changeset sets `updated_at` itself. Alloy never contained `now()` or
  `date_trunc`; the timestamp was the `SqlDefault` above. Put the same
  expression in the DDL as the column default for rows written by hand.
- **`whereILike` renders `LIKE`.** SQLite's `LIKE` ignores case, but for ASCII
  letters only: `'e' LIKE 'E'` is true, `'é' LIKE 'É'` is false. Postgres
  `ILIKE` folded all of Unicode. A search that must match accented capitals has
  to be done in Temper or with a custom collation.
- **`lock(ForUpdate | ForShare)` renders nothing.** SQLite has no row locks.
  The types and the method stay so callers compile. Use `BEGIN IMMEDIATE`.
- **`toUpdateSql(id)` and `toUpdateSqlWhere(where)`.** The second takes any
  `SqlFragment` predicate and puts it after `WHERE`; the values in it are
  escaped or parameterized like any other.
- **`toInsertSqlReturning()`** is `toInsertSql()` plus ` RETURNING <pk>`
  (SQLite 3.35, 2021). The db layer gets the new id from the same statement.
- **Booleans are `1` and `0`**, not `TRUE`/`FALSE` (3.23+ only), in both
  `toString` and `toParameterized`. Dates are quoted ISO text.
- **`toParameterized()`** numbers placeholders `$1, $2, ...` in order of
  appearance and returns every parameter as a string. SQLite parses `$1` as a
  named parameter and numbers such parameters by first appearance, so binding
  by position in `params` is right. A driver binding text relies on column
  affinity when comparing with an integer column. See `ParameterizedSql`.
- **OFFSET without LIMIT** renders `LIMIT -1 OFFSET n`: SQLite rejects a bare
  `OFFSET`.
- **Identifiers are not quoted.** None of Marginalia's column or table names is
  a reserved word in SQLite: every one was run unquoted through CREATE, INSERT,
  UPDATE, WHERE and ORDER BY on 3.51 (`role`, `key`, `ordinal`, `text`,
  `source`, `scope`, `mode`, `kind`, `result`, `error`, `from_id`, `to_id`
  included). Only `order`, `from`, `to`, `group` and `index` fail, and none is
  a column here. `safeIdentifier` still accepts them, so choosing one as a name
  fails in SQLite, loudly, rather than being quoted silently.
- **Not supported, not changed:** `NULLS FIRST/LAST` needs 3.30, `RIGHT` and
  `FULL OUTER JOIN` need 3.39, and `UPDATE ... LIMIT` / `DELETE ... LIMIT`
  work only when SQLite is built with `SQLITE_ENABLE_UPDATE_DELETE_LIMIT`.
  Alloy emits them if asked.

Top-level helpers.

## Imports

All types (SqlFragment, SqlBuilder, TableDef) are available from other
files in the same module without explicit imports.

## deleteSql

Generates `DELETE FROM … WHERE id = ?`.

`appendSafe` is called only with: (a) the string literal `"DELETE FROM "` /
`" WHERE id = "`, and (b) `tableDef.tableName.sqlValue` which is the
`.sqlValue` of a `SafeIdentifier` — validated at `TableDef` construction
time. The `id` is rendered as `SqlInt32` (a bare integer, never quoted).

No raw runtime string ever touches `appendSafe` here.

    export let deleteSql(tableDef: TableDef, id: Int): SqlFragment {
      let b = new SqlBuilder();
      b.appendSafe("DELETE FROM ");
      b.appendSafe(tableDef.tableName.sqlValue);
      b.appendSafe(" WHERE ");
      b.appendSafe(tableDef.pkName());
      b.appendSafe(" = ");
      b.appendInt32(id);
      b.accumulated
    }
