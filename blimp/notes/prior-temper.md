# Prior Temper work in Marginalia (branch temper/alloy-slice)

Source: worktree /Users/bg/code/marginalia-temper, branch temper/alloy-slice, 15 commits
ahead of main (6eb9c32 .. 594abc8). Not modified. Written for a Blimp backend effort.
The trial build was done on a scratch copy; results are in section 5.

## 0. Layout

    temper/README.md                    pipeline, verification, costs (accurate; read it)
    temper/marginalia-core/config.temper.md   `export let name = "marginalia-core";`
    temper/marginalia-core/src/*.temper.md    library + *_test files
    temper/marginalia-core/src/_connected.ex  Elixir half of the @connected declarations (be-elixir only)
    temper/alloy/                       Alloy, vendored by git archive at 8a5207377a62... (ALLOY_COMMIT)
    temper/verify/{old_*.exs,*.exs,bench.exs}  equivalence + bench harnesses
    temper/out/                         generated Elixir, committed (not useful to Blimp)
    bin/temper-{gen,test,watch,verify,check}    pipeline scripts

All sources are literate Temper (.temper.md, code indented 4 spaces).

## 1. marginalia-core modules

Facades in the Elixir app kept the old API and convert generated `@imu` classes back to tuples/maps.
"Tests" are Temper `test(...)` blocks in src/*_test.temper.md. Total 35 (26 before folders, +9 folders).

| Temper module | Lines | Replaced | Exports | Temper tests |
|---|---|---|---|---|
| diff.temper.md | 161 | Marginalia.Diff | `paragraphs(text: String): List<String>`; `rows(before: String, after: String): List<Row>`; `@imu Row(kind, left: String?, right: String?)`, kind in same/change/del/ins | diff_test: 5 |
| words.temper.md | 261 | Marginalia.Rewrite.diff/2 | `diff(a: String, b: String): List<Part>`; `@imu Part(kind: String, text: String)`. Myers on whitespace-trimmed words, ported step for step from List.myers_difference/2 including compaction | words_test: 6 |
| blocks.temper.md | 69 | Marginalia.Reading.split/1 | `blocks(body: String): List<String>` (blank-line blocks, fenced code kept whole) | none of its own (exercised via sentences) |
| sentences.temper.md | 382 | Marginalia.Works.Sentences | `reflow(text: String): String`, `reflowBlock(block: String): String` (one sentence per line, prose only, idempotent) | sentences_test: 6 |
| reflow.temper.md | 373 | Marginalia.Works.Reflow | `isWrapped(text): Boolean`, `reflowPage(text): String`, `align(quote, source): String` (PDF page text to paragraphs, hyphen mending) | reflow_test: 4 |
| segmenter.temper.md | 425 | Marginalia.Works.Segmenter | `segment(raw: String): List<Section>`; `@imu Section(title, body)` (headings, then marker lines, then ~1800-word windows) | segmenter_test: 5 |
| text.temper.md | 75 | (helpers) | none exported: `isRegexSpace` (ASCII \s), `isTrimSpace` (Unicode, String.trim), `trim`, ... | none |
| folders.temper.md | 358 | Marginalia.Folders' Ecto queries | 18 exports, section 2 | folders_test: 9 |
| testing.temper.md | 24 | | test helpers `repeated`, `includes`, `expectText` | |
| _connected.ex | 33 | | Elixir implementations of the @connected functions | |

Equivalence evidence (temper/verify): 4 harnesses (diff, sentences, reflow, segmenter) run the verbatim old
Elixir (old_*.exs, renamed under Old.) against the generated code on random inputs and stop at the first
difference. Totals quoted in commits/README: 24,000 diffs, 23,000 documents, 38,000 PDF pages, 1,900
manuscripts, zero differences. `bin/temper-verify` runs all (about 30 s); `bin/temper-verify bench` times
old vs new on BEAM (word diff 3.2x slower, PDF reflow 5x faster, others 1.1-1.5x). The oracle is Elixir/PCRE,
so the .exs files cannot run on Blimp, but old_*.exs plus the harness input generators are the behaviour spec,
bug-for-bug cases included.

Imports: marginalia-core imports only `import("orm/src")` (folders.temper.md). No std/regex, no std/strings.
Temper's core String has no trim/replace/regex, so everything is hand-written scans over code points
(`s.hasIndex`, `s.next`, `s[i]`, `slice`, `StringBuilder.appendCodePoint`, `appendBetween`). The only `import`
in all of Alloy is `import("std/temporal")` for `Date` (sql_imports.temper.md). Tests use std/testing implicitly.

Behaviour quirks preserved: ASCII `\s` vs Unicode trim kept separate; "unrelated" is the float test
`shared < 0.05 * smaller`; the segmenter marker regex read bytes in PCRE (no /u), reproduced, then the
`---`-works-but-`———`-does-not bug was fixed in commit bddf726 with a test that fails before the fix.

### Elixir-specific dependencies (the important part)

9 `@connected` functions, answered in `_connected.ex` (module TemperConnected), across 3 files:

- sentences.temper.md: `isUnicodeSpace(cp: Int): Boolean`, `isUnicodeUpper`, `isUnicodeDigit` (PCRE \s \p{Lu} \d with /u)
- reflow.temper.md: `isUnicodeLetter`, `isUnicodeNumber`, `isUpcaseFixed` (all `cp: Int -> Boolean`),
  `downcase(s: String): String`, `graphemeLength(s: String): Int`
- segmenter.temper.md: `graphemePrefix(s: String, n: Int): String`

Each has an ASCII fast path in Elixir and asks PCRE or String.* for non-ASCII. Real semantics needed: Unicode
classes, whole-word downcase (final sigma), grapheme (not code point) counts. The Temper tests use ASCII only,
so they cannot tell stubs from real implementations; the verify harnesses can.
Nothing else is Elixir-only. folders.temper.md has no @connected; its output is plain @imu data.

BEAM-driven design that does not apply to Blimp: @imu everywhere, exports minimised (each export costs a GC
entry check), `appendBetween` run-copying for speed. Harmless to keep.

## 2. folders.temper.md: "runs SQL that Temper builds"

It is a pure SQL builder. No connection, no connected `exec`. Each export returns a value; the host executes it.

    @imu export class Param(public kind: String, public text: String) {}   // kind: text|int|bool|float|date
    @imu export class Statement(public text: String, public params: List<Param>) {}
    @imu export class FieldError(public field: String, public message: String) {}
    @imu export class Prepared(public statement: Statement?, public errors: List<FieldError>) {}

`statementOf(fragment: SqlFragment): Statement` walks `fragment.parts`: value parts (SqlString, SqlInt64,
SqlInt32, SqlBoolean, SqlFloat64, SqlDate) become `$1,$2,...` plus a typed `Param`; everything else
(SqlSource, identifiers, DEFAULT) stays in the text via `part.formatTo`. Kind exists because Postgrex binds
binary by type and refused text for bigint. Note booleans become real params here, whereas plain
`toParameterized()` inlines them as TRUE/FALSE.

Exports (Int64 ids; `parentId: Int64?`):
- Statement: listFolders(userId), getFolder(userId, folderId), foldersByIds(ids), folderByName(userId, name),
  sibling(userId, name, parentId), moveFolder(userId, folderId, parentId), moveWork(userId, workId, folderId),
  fileWorks(workIds, folderId), publish(userId, folderId, slug), unpublish, publishedBySlug(slug), published(),
  slugTaken(slug), unfiledCount(userId), looseWorkCollections(userId)
- Prepared (changeset: cast, validateRequired, validateLength 1..80, name trimmed): createFolder(userId, name, parentId),
  renameFolder(userId, folderId, name)
- List<Statement>: deleteFolder(folderId, parentId) (3 statements; the host runs them in one transaction)

Sample (README): `SELECT id, name, ... FROM folders WHERE user_id = $1 AND id = $2`, params `[{int,"7"},{int,"3"}]`.

Host side (lib/marginalia/alloy.ex in that worktree, 80 lines): `query(%Statement{text, params})` decodes each Param
by kind (`"int" -> String.to_integer`, `"bool" -> text == "true"`, `"float"`, `"date" -> Date.from_iso8601!`),
calls `Repo.query(text, decoded)`, turns `columns/rows` into maps keyed by atom, optionally wraps in a SAVEPOINT.
The interface is `run(sql_text, [typed params]) -> rows`, which is the same shape as an SQLite
`query(sql, params)` primitive. So yes, the design works with an SQLite executor.

SQLite portability of folders.temper.md specifically: the SQL is mostly generic (WHERE/AND, `ORDER BY name_key ASC`,
`LIMIT 1`, `IN (...)`, `IS NULL`) but has Postgres bits: `now = "date_trunc('second', now() at time zone 'utc')"`
used as column default and in UPDATEs (SQLite: `strftime('%Y-%m-%d %H:%M:%S','now')`), `RETURNING` (SQLite >= 3.35),
`lower(name) AS name_key` (fine). It hardcodes Marginalia's folders/works schema.

## 3. Alloy (temper/alloy, library name `orm`, 225 tests)

Files: schema 125 lines, changeset 470, query 792, sql_model 241, sql_builder 129, orm 30, sql_imports 3.
Tests: changeset_test 88, query_test 103, schema_test 15, sql_tests 19 = 225. Upstream:
github.com/notactuallytreyanastasio/alloy @ 8a52073.

Schema DSL (plain classes, no macros):

    let folders = new TableDef(
      id("folders"),                                   // SafeIdentifier, validated [a-zA-Z_][a-zA-Z0-9_]*
      [
        new FieldDef(id("name"), new StringField(), false, null, false),
        //           name        type               nullable default virtual
        new FieldDef(id("inserted_at"), new DateField(), false, new SqlSource(now), false),
      ],
      null,                                            // primaryKey, default "id"
    );

Field types: StringField, IntField, Int64Field, FloatField, BoolField, DateField. `timestamps()` gives
inserted_at/updated_at with `SqlDefault` (renders the keyword DEFAULT). `safeIdentifier(name)` bubbles on bad
names; identifiers are the only strings that reach `appendSafe`.

SQL values: `sql"age > ${18}"` builds `SqlFragment(parts: List<SqlPart>)`; parts are SqlSource, SqlString,
SqlInt32, SqlInt64, SqlFloat64, SqlBoolean, SqlDate, SqlDefault. Two renderings: `toString()` (values inlined as
escaped literals, strings `'...'` with `''` doubling, booleans TRUE/FALSE, dates as quoted ISO text) and
`toParameterized(): ParameterizedSql(text, params: List<String>)` (numbered `$1,$2`, every param a string;
booleans/DEFAULT/NULL stay in the text). Its doc comment says SQLite reads `$1` as a named parameter numbered in
the same order. Placeholders are never `?` and never reused.

Changesets (Ecto-style): `changeset(tableDef, params: Map<String,String>)`, then chain `cast(allowed)`,
`validateRequired`, `validateLength(f,min,max)`, `validateInt`, `validateFloat`, `validateBool`,
`validateInclusion`, `validateExclusion`, `validateNumber(f, NumberValidationOpts)`, `validateAcceptance`,
`validateConfirmation`, `validateContains`, `validateStartsWith`, `validateEndsWith`, `putChange`, `getChange`,
`deleteChange`; read `.isValid`, `.errors` (ChangesetError(field, message)), `.changes`.
Output: `toInsertSql(): SqlFragment throws Bubble` (`INSERT INTO t (cols) VALUES (...)`, adds columns that have a
defaultValue when absent) and `toUpdateSql(id: Int)` (`UPDATE t SET ... WHERE pk = <int32 literal>`).
No RETURNING from changesets (folders.temper.md appends it by hand). Messages: "is required",
"must be between 1 and 80 characters". Lengths count code points.

Query builder (immutable, chainable, `from(table: SafeIdentifier): Query`): select, selectExpr, where, orWhere,
whereNot, whereNull, whereNotNull, whereIn(field, List<SqlPart>), whereInSubquery, whereBetween, whereLike,
whereILike, orderBy(field, asc), orderByNulls, limit, offset (both `throws Bubble`, inlined as Int32 literals),
innerJoin/leftJoin/rightJoin/fullJoin/crossJoin, groupBy, having/orHaving, distinct, lock (ForUpdate/ForShare),
`toSql()`, `countSql()`, `safeToSql(defaultLimit)`. Also `col(table, col)`, aggregates (countAll, countCol,
sumCol, avgCol, minCol, maxCol), set ops (unionSql, unionAllSql, intersectSql, exceptSql), `subquery`,
`existsSql`, `update(table).set(f, SqlPart).where(..).limit(..).toSql()`, `deleteFrom(table).where(..).toSql()`,
and `deleteSql(tableDef, id)` in orm.temper.md. orderBy takes columns, not expressions.

Dialect: ANSI-leaning with Postgres flavour. Items that matter for SQLite:
- `ILIKE` (whereILike): not in SQLite. LIKE is already ASCII case-insensitive there; map to LIKE.
- `FOR UPDATE` / `FOR SHARE` (lock): invalid in SQLite; drop.
- `NULLS FIRST/LAST` needs SQLite >= 3.30, RIGHT/FULL OUTER JOIN >= 3.39, TRUE/FALSE literals >= 3.23.
- `DEFAULT` keyword in INSERT VALUES (SqlDefault, used by `timestamps()` and by any FieldDef default that is
  SqlDefault): NOT valid in SQLite. The one real blocker for changeset.toInsertSql on tables with timestamps().
  Fix: omit the column and use a column default, or render a literal.
- UPDATE/DELETE `LIMIT` only works if SQLite is built with SQLITE_ENABLE_UPDATE_DELETE_LIMIT.
- RETURNING is not emitted by Alloy itself (folders.temper.md adds it); SQLite >= 3.35.
No arrays, no jsonb, no `::` casts, no `ANY(...)`, no identifier quoting. String escaping only doubles single quotes.

What a backend must supply to Alloy: nothing. Alloy has no database driver and no `exec`. Its output is
SqlFragment / ParameterizedSql and the host owns connections. A Blimp host needs one primitive,
`query(sql_text, params) -> rows`, plus a decision on parameter typing (the `Param.kind` trick from
folders.temper.md, or bind all as text; SQLite's type affinity usually coerces '7' for an integer column compare
but do not rely on it).

Verdict: usable on SQLite with a `query(sql, params)` primitive for select/where/order/limit/offset/joins/
aggregates/update/delete/changeset validation. It compiles and its 225 tests pass on the new Blimp (section 5).
Changes needed: (a) SqlDefault in INSERT; (b) ILIKE and lock; (c) timestamp defaults (Postgres `now()` strings);
(d) `toUpdateSql(id: Int)` and limit/offset use Int32 literals, so use `where(sql"id = ${int64}")` as
folders.temper.md does; (e) result decoding does not exist (no row mapper, preload, associations, migrations):
Alloy is write-side SQL construction and validation only.

## 4. Build / test workflow there (pattern worth repeating)

- `bin/temper-gen` (`mix temper.gen`): rsync each temper/*/ that has a config.temper.md (excluding temper.out) into
  a temp dir, run `temper build -b elixir -w .`, delete `*.map`, copy into `temper/out`, record the temper commit
  in `temper/out/TEMPER_COMMIT`. Fails on any build error and prints the log. Env: `TEMPER`, `TEMPER_BLIMP`,
  `JAVA_HOME` (/opt/homebrew/opt/openjdk@21).
- `bin/temper-gen --check` (`mix temper.check`, first step of `mix precommit`): regenerate to scratch and
  `diff -r` against committed temper/out. Generated code is committed so deploys need no JVM.
- `bin/temper-test` (`mix temper.test`): for each temper/out/*/ with a test/ dir, run `mix test` with
  MIX_BUILD_ROOT under _build/temper. Failures name the Temper source line.
- `bin/temper-watch`: `temper watch -b elixir -w temper`; rsync -r -c (content compare, no mtimes) into temper/out;
  does not copy a build that has diagnostics (watch still writes garbage output for broken code);
  `temper/.temperignore` stops it watching its own output; exits when stdin closes. Runs as a Phoenix watcher.
- `bin/temper-verify [name|bench]`: equivalence harness against old Elixir.
- Test authoring rule (commit 5ec802b): put every assertion in a helper that takes `test`; otherwise the Temper
  frontend constant-folds `assert(f("lit") == "x")` at compile time into `assert(true/false)` and tests the
  compiler. Calls to @connected functions are never folded.
For Blimp, `temper build -b blimp -w .` and `temper test -b blimp -w . --library NAME` are enough. The CLI runs the
`blimp` found on PATH by name (BlimpSpecifics.kt `cliNames = listOf("blimp")`), which here was
/opt/homebrew/bin/blimp, the older temper-blimp build, until PATH was overridden.

## 5. Trial: marginalia-core + alloy on temper-blimp-114's Blimp

Setup: copied temper/marginalia-core and temper/alloy to
/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad/prior/
(side by side, unchanged at first). Wrapper
/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad/tb.sh sets
JAVA_HOME=/opt/homebrew/opt/openjdk@21, prepends scratchpad/bin (a `blimp` symlink to
/Users/bg/code/temper-blimp-114/blimp/chunks/lang/zig-out/bin/blimp), and runs
/Users/bg/code/temper-blimp-114/temper/cli/build/install/temper/bin/temper in the `prior` directory.

### 5a. Unmodified copy

`temper build -b blimp -w .`: exit 0, six warnings, no errors, about 6 s. Produced
temper.out/blimp/{std,marginalia-core,orm}/main.blimp (282 KB, 900 KB, 592 KB). Every module of all three
libraries (including Alloy and std/temporal) compiles for Blimp. The diagnostics, verbatim (all in
folders.temper.md `paramOf`; harmless redundancy):

    [-work/marginalia-core/src/folders.temper.md:62+34-51]@G: Unnecessary type check to SqlString from expression with type SqlString which is a subtype
    [-work/marginalia-core/src/folders.temper.md:65+33-49]@G: Unnecessary type check to SqlInt64 from expression with type SqlInt64 which is a subtype
    [-work/marginalia-core/src/folders.temper.md:68+33-49]@G: Unnecessary type check to SqlInt32 from expression with type SqlInt32 which is a subtype
    [-work/marginalia-core/src/folders.temper.md:71+38-56]@G: Unnecessary type check to SqlBoolean from expression with type SqlBoolean which is a subtype
    [-work/marginalia-core/src/folders.temper.md:74+35-53]@G: Unnecessary type check to SqlFloat64 from expression with type SqlFloat64 which is a subtype
    [-work/marginalia-core/src/folders.temper.md:77+34-49]@G: Unnecessary type check to SqlDate from expression with type SqlDate which is a subtype

The build does NOT complain about the 9 `@connected` declarations. be-blimp emits calls to
`connected_isUnicodeSpace(cp)` and the other eight (e.g. main.blimp line 22780) but defines none of them;
`_connected.ex` is ignored. The missing functions fail at runtime only.

`temper test -b blimp -w .` (both libraries, no --library): exit 1, stops after orm.
- orm: with the new blimp, `Tests passed: 225 of 225`. With the PATH (old) blimp it was 175 of 225, with
  `Test failed (blimp): validateFloat passes for valid float - should be valid`; the old blimp's stderr for
  marginalia-core was `I don't know a function called 'join'` (it lacks builtins the new one has).
- marginalia-core: `Tests passed: 23 of 35`, 12 failures each reported only as `test raised`
  (`Test failed (blimp): the typesetter's hyphens are closed up, and the running head is dropped - test raised`).
  Running `blimp main.blimp` directly in temper.out/blimp/marginalia-core lists them:
  PASS: diff 5/5, words 6/6, folders 9/9, reflow 2/4 (hardWrappedTextWithNoBlankLinesIsPageText,
        textThatAlreadyHasParagraphsIsLeftAlone), segmenter 1/5 (emptyInputYieldsNothing), sentences 0/6.
  FAIL: reflow theTypesetterSHyphensAreClosedUpAndTheRunningHeadIsDropped, theDivisionNumeralStandsAlone;
        segmenter aBlogPostWithNoStructureIsOneSection, markdownHeadingsWinWhenTheWriterSuppliedThem,
        chapterMarkersAreFoundWhenThereIsNoMarkdown, aRunOfEmDashesIsASectionMarkerAsHyphensAre;
        sentences: all six.
  Cause (confirmed by 5b): the tests that reach a @connected call. Blimp's failure output gives no cause beyond
  "test raised", which made this slow to diagnose. A build-time error for an @connected function with no
  definition would be better than a dangling call.

### 5b. Scratch copy with @connected replaced by Temper code

Changes, scratch copy only (scratchpad/prior/marginalia-core/src): deleted _connected.ex; replaced the 9
`@connected export let` declarations with plain `export let` Temper bodies, ASCII-only:
isUnicodeSpace = `cp == 32 || (cp >= 9 && cp <= 13)`; isUnicodeUpper = A-Z; isUnicodeDigit and isUnicodeNumber = 0-9;
isUnicodeLetter = a-zA-Z; isUpcaseFixed = `!(a-z)`; downcase = ASCII fold per code point;
graphemeLength = `s.countBetween(String.begin, s.end)` (code points); graphemePrefix = first n code points via
`s.next` and `s.slice`.
Result: `temper test -b blimp -w . --library marginalia-core` -> `Tests passed: 35 of 35`, no diagnostics.
With `--library orm`: 225 of 225. So 260/260 pass on Blimp once the 9 host functions exist.
Caveats: the stubs are ASCII-only and the tests are ASCII-only, so 35/35 says nothing about Unicode
equivalence (non-ASCII letters, final sigma, grapheme clusters). Not measured: speed on the 12,000-word segmenter
and 2,000-word diff inputs. The verify harnesses were not ported.

## 6. Recommendations

1. diff, words, blocks, text, folders compile and pass unchanged. sentences, reflow and segmenter need the 9
   connected functions. Reuse the sources, and use old_*.exs plus the harness generators as the oracle for a port.
2. Decide how Blimp answers the 9 functions: Blimp builtins (upcase, downcase, split exist) plus a Unicode-class
   primitive, or tables written in Temper. be-blimp should reject an `@connected` function that has no definition.
3. Alloy needs only small SQL changes for SQLite (SqlDefault in INSERT, ILIKE, lock) and a result decoder; keep
   the folders.temper.md boundary where Temper returns `Statement`/`Param` and the host runs `query(text, params)`.
4. Reuse the workflow: gen, `--check` against committed output, assertions inside a helper that takes `test`.
