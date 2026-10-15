# Brief for a domain library (Phase 2)

You are porting one Elixir context of Marginalia to Temper on Blimp. Read, in
this order: `blimp/PLAN.md` (all of it; §6 and §6a are the rules that bite),
this file, then the sections of `blimp/notes/domain-*.md` and
`blimp/notes/tests.md` named in your assignment. The Elixir source under
`lib/marginalia/` is the truth when the notes are silent or ambiguous; read
it, do not guess.

## Shape

One Temper library per context, under `blimp/temper/<context>/`:

    config.temper.md            export let name = "<context>";
    src/<context>.temper.md     the context's functions (the Elixir module's public API)
    src/records.temper.md       the record classes with fromRow
    src/prompts.temper.md       prompt constants, verbatim (only if the context calls a model)
    src/<context>_test.temper.md

Imports you may use: `import("sys")`, `import("db")`, `import("orm/src")`,
`import("core")`, `import("html")`, `import("llm")`, `import("std/json")`,
`import("std/regex")`, and the context libraries your assignment lists as
dependencies (already written; read their `src/*.temper.md` for the API).
Never import a context that is not in your dependency list; post on the
message board if you need one.

## Conventions

- Every function takes the `Db` first, then the `Scope` (a `User?` plus flags)
  where the Elixir took `scope`, then the arguments in the Elixir's order.
  Function names are the Elixir names in camelCase prefixed with the context
  noun: `Works.get_work!(scope, id)` becomes `worksGet(db, scope, id)`;
  bang functions bubble (`throws Bubble`), non-bang ones return `null` or an
  `Outcome`.
- Records are plain classes mirroring the Ecto schema, field for field, same
  names in camelCase, `Int` ids, `String` timestamps, `String?` for nullable
  columns, `List<String>`/`List<Int>` for array columns (JSON text in SQLite,
  decoded by `Row.strList`/`intList`), `JsonSyntaxTree?` for `:map` columns
  unless a typed class is clearly better. Each has
  `static fromRow(row: Row): T` and the context has `<context>Columns`, the
  SELECT column list, so every query uses the same decoding.
- Changesets: validation lives in the context as functions returning
  `List<FieldError>` (from `core`'s folders module shape: `FieldError(field,
  message)`), with the Elixir's exact error messages. Alloy's `changeset` is
  available if it fits; hand-written validation is fine too. Writes go through
  Alloy fragments (`sql"..."`) turned into text and params by `dbStatement`,
  or through `db.exec`/`db.insert`/`db.query` with `$1` placeholders and
  string params. Never interpolate user text into SQL.
- Timestamps: `sysUtcNow()`. Ids: `db.insert` returns the new id.
- Results that the Elixir returned as `{:ok, x} | {:error, reason}` become a
  class `<Context>Result` with `ok: T?` and `error: String?`, or a bubble for
  programmer errors. Flash texts and error strings are copied verbatim.
- Background work: do not fork from a context. Expose the unit of work as a
  function (`analysisReadSection(db, workId, ordinal)`) and the state
  transitions as functions; the `runs` library owns forking and the `runs`
  table. If your context started a Task in Elixir, write the function the
  task body would call and say so in your report.
- PubSub broadcasts become `versionsBump(db, topic)` from the `runs` library
  (a row per topic; pages poll it). Call it exactly where the Elixir
  broadcast.
- LLM calls: `LlmClient` is passed in (`llm: LlmClient` parameter right after
  `db`), never created inside a context, so tests pass `llmFake([...])`.
  Prompts are verbatim from the notes (they were extracted byte for byte) in
  `src/prompts.temper.md` as functions returning `String`, with the Elixir's
  interpolations as parameters. The call options (model, effort, max tokens,
  temperature, json, tools) are exactly the notes' table for that call.
- Markdown and text: `html` for `markdownToHtml`, `slug`, `wordCount`,
  `esc`; `core` for segment, sentences, reflow, diff; `sys` for trim,
  replace, hashing, random tokens.
- Performance: no ListBuilder/StringBuilder loop over more than ~2,000 items;
  no per-character scans over documents; word diff per paragraph only; prefer
  one SQL query with a join over N queries in a loop; keep `Map` tiny.

## Tests

`src/<context>_test.temper.md`, assertions through a helper taking `test`.
Port every assertion for your context from `blimp/notes/tests.md` (the
`test/marginalia/<context>*_test.exs` parts): same inputs, same expected
strings. Use `dbOpen(":memory:")` per test (it migrates), insert fixtures with
your own context functions (and the dependency contexts' functions for users
and works), use `llmFake` with canned replies shaped like the notes say the
model answers. Expect 30-100 tests depending on the context.

Build and test in isolation:
`/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad/tb.sh <context> sys db orm core html llm <deps...>`
(read the script first; it rsyncs the named libraries from the worktree into
a scratch root, builds with the 115 toolchain, and runs `--library <context>`).
Edit only in the worktree, only in your library's directory. Do not commit.

## Report

The API as implemented (every export with its signature), the pass line
verbatim, every deviation from the Elixir with the reason, every Elixir
function you did not port (by name) and why, and what does not work.
