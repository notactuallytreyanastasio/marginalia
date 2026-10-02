# Marginalia's text logic, in Temper

Marginalia is a Phoenix app for reading and revising long-form writing. The
text logic at its core is written once in [Temper](https://github.com/temperlang/temper)
and generated into Elixir by an Elixir/BEAM backend for Temper,
[be-elixir](https://bobbby.online/be-elixir):

| Temper source (`marginalia-core/src/`) | Replaces | What it does |
|---|---|---|
| `diff.temper.md` | `Marginalia.Diff` | aligns two versions of a draft paragraph by paragraph |
| `words.temper.md` | `Marginalia.Rewrite.diff/2` | the word diff inside an edited paragraph (Myers) |
| `blocks.temper.md` | `Marginalia.Reading.split/1` | a draft's blocks, fenced code kept whole |
| `sentences.temper.md` | `Marginalia.Works.Sentences` | one sentence per line, prose only |
| `reflow.temper.md` | `Marginalia.Works.Reflow` | paragraphs recovered from PDF page text, hyphens mended |
| `segmenter.temper.md` | `Marginalia.Works.Segmenter` | a manuscript split into sections |
| `text.temper.md` | | trim and friends, matching Elixir's exactly |

The Elixir modules keep their APIs as thin facades over the generated
`Temper.MarginaliaCore`, so nothing that calls them changed, and the app's
1,158 tests run against the Temper code.

## The pipeline

```
temper/marginalia-core/   Temper source: literate .temper.md, plus _connected.ex
        │  bin/temper-gen (mix temper.gen)
        ▼
temper/out/               generated Elixir, committed
  marginalia-core/        the library: Temper.MarginaliaCore
  temper-core/            be-elixir's runtime
  TEMPER_COMMIT           the temper build that generated it
        │  mix.exs: {:temper_marginalia_core, path: "temper/out/marginalia-core"}
        ▼
lib/marginalia/...        facades with the old APIs
```

- **The generated code is committed.** Building, testing and deploying
  Marginalia needs no JVM and no Temper; only regenerating does. The
  Dockerfile copies `temper/out` in before `mix deps.get`, and the release
  carries it like any dependency.
- **It cannot go stale.** `bin/temper-gen --check` (`mix temper.check`, the
  first step of `mix precommit`) regenerates into a scratch directory and
  fails if the result differs from `temper/out` by a byte. Generation is
  deterministic.
- **`TEMPER` picks the compiler.** The default is a be-elixir build of the
  `temper` CLI in `~/code/temper-elixir`. If it is missing, the script says
  how to build it.

A function in Temper and what is generated from it:

```temper
let moveRight(p: Path, b: List<String>): Path {
  if (p.j < b.length) {
    new Path(p.y, p.i, p.j + 1, new Edit(INS, b[p.j], p.edits))
  } else {
    p
  }
}
```

```elixir
def moveRight__489(p, b) do
  if Temper.MarginaliaCore.Path.get_j(p) < TemperCore.List.length(b) do
    Temper.MarginaliaCore.Path.new(Temper.MarginaliaCore.Path.get_y(p), Temper.MarginaliaCore.Path.get_i(p),
      TemperCore.int32(Temper.MarginaliaCore.Path.get_j(p) + 1),
      Temper.MarginaliaCore.Edit.new(2, TemperCore.List.get(b, Temper.MarginaliaCore.Path.get_j(p)),
        Temper.MarginaliaCore.Path.get_edits(p)))
  else
    p
  end
end
```

`Path` and `Edit` are `@imu` classes, so they are Elixir structs. The
linked list of edits is shared between paths exactly as Elixir's own
`List.myers_difference/2` shares it. The generated library compiles
without warnings.

## Working on it live

`mix phx.server` runs `bin/temper-watch` alongside esbuild and tailwind.
Save a `.temper.md` file, and the page in the browser reloads running the
new code, about a second later:

```
[temper] watching temper/ (temper watch -b elixir)
[temper] build 0 in 2.584s: 0 file(s) changed in temper/out
[temper] build 1 in 759.708ms: 1 file(s) changed in temper/out
[debug] Live reload: temper/out/marginalia-core/lib/temper_main.ex
Generated temper_marginalia_core app
```

1. `temper watch -b elixir -w temper` keeps a JVM warm and rebuilds on
   every save, in well under a second. `temper/.temperignore` keeps it from
   watching its own output.
2. The script copies the build into `temper/out`, comparing contents, so
   only files that changed get a new mtime.
3. If anything changed, it runs the Temper tests (below) and prints the
   summary, plus each failure's Temper line and message.
4. Live reload sees `temper/out/**/*.ex` change (`config/runtime.exs`) and
   refreshes the page.
5. That request runs the code reloader. `reloadable_apps` in
   `config/dev.exs` lists the generated libraries, so it recompiles the
   path dependency, not only the app.

A build with a diagnostic is not copied. The page keeps running the last
good build, and the diagnostic appears in the server's output as Temper
wrote it:

```
161: let broken(): Int { "no" }
                         ┗━━┛
[-work/marginalia-core/src/diff.temper.md:161+24-28]@G: Cannot assign to Int32 from String
[temper] build 2 has diagnostics; temper/out keeps the last good build
```

What a session leaves in `temper/out` is exactly what `bin/temper-gen`
makes, so `mix temper.check` passes and the result can be committed. With
no temper CLI, the watcher says so and exits, and the app serves the
committed code. Run `bin/temper-watch` in a terminal to watch without the
server, for example while running `mix test`. Ctrl-C stops it.

### Moving an Elixir module into Temper

1. **Write it.** Add `temper/marginalia-core/src/<name>.temper.md`. Every
   file in the library's `src/` becomes part of `Temper.MarginaliaCore`,
   so there is nothing to register. `export` what Elixir will call, and
   only that, because an exported function pays the library's entry on
   every call. When Temper can't answer something about a character,
   declare a `@connected` function and implement it in
   `src/_connected.ex`.
2. **Point the Elixir module at it.** Keep the module and its API, and
   replace its body with calls into `Temper.MarginaliaCore`. Convert the
   results back into what callers already match on, as
   `Marginalia.Diff.rows/2` does. This step is deliberately written by
   hand: it is the boundary between Temper's types and the app's.
3. **Port its tests.** Put them in `src/<name>_test.temper.md`, with every
   check inside a helper that takes the `test` (see below).
4. **Prove it is the same.** Copy the old module into
   `temper/verify/old_<name>.exs` under `Old.`, and add a harness that
   runs old and new on random inputs and counts which rules the inputs
   reach. `bin/temper-verify <name>` runs it.
5. **Commit the source and `temper/out` together.** `mix precommit`
   refuses a `temper/out` that the sources would not generate.

## Temper tests

`src/*_test.temper.md` holds 26 tests, ported from the app's Elixir tests
for the diffs, the segmenter, sentences and PDF reflow. be-elixir turns
each test file into an ExUnit file in `temper/out/marginalia-core/test/`.
`bin/temper-test` (`mix temper.test`, in `mix precommit`) runs them, and
a failure names its Temper line:

```
  1) test identical spans are all one piece (Temper.MarginaliaCore.WordsTest)
     test/words_test.exs:17
     src/words_test.temper.md:37: got:
     same:a b c
     want:
     same:a b d
```

The tests aren't part of the library. They, their helpers and std (for
std/testing) live in the generated `test/support/` and are compiled only
under `MIX_ENV=test`. The app never compiles any of them, in any
environment.

**Every check runs inside a helper that takes the `test`.** The Temper
frontend evaluates anything whose inputs are known while compiling, on
every backend. `assert(kinds(rows("a", "b")) == "same")` would come out as
`assert(false)`, already decided, and test the compiler instead of the
generated code. A function that takes the `test` is never evaluated early:

```temper
let diffIs(test: Test, a: String, b: String, want: String): Void {
  expectText(test, render(diff(a, b)), want);
}

test("identical spans are all one piece") { test =>
  diffIs(test, "a b c", "a b c", "same:a b c");
}
```

`src/testing.temper.md` has the shared helpers. The test source travels
with the Temper code, so another backend's build of this library gets
the same tests.

## A whole Temper library: Alloy runs the folders

`temper/alloy/` is [Alloy](https://github.com/notactuallytreyanastasio/alloy),
a Temper ORM (schemas, Ecto-style changesets, and a query builder that
produces parameterized SQL), vendored with `git archive` at the commit in
`temper/alloy/ALLOY_COMMIT`. `bin/temper-gen` builds it beside
`marginalia-core`, as the library `orm` (`Temper.Orm`), and
`marginalia-core` imports it like any Temper library:

```temper
let { from, sql, update, changeset, TableDef, ... } = import("orm/src");
```

The Folders context no longer uses Ecto. `marginalia-core/src/folders.temper.md`
builds every statement it sends, with Alloy's builder and its `sql` tag;
`Marginalia.Alloy` runs them through `Repo.query/3`; `Marginalia.Folders`
decides what to run and makes rows into a plain `%Folder{}`. Ecto still
owns the connection pool, transactions, migrations and the test sandbox,
and every other context.

```elixir
iex> Temper.MarginaliaCore.getFolder(7, 3)
%Temper.MarginaliaCore.Statement{
  text: "SELECT id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at FROM folders WHERE user_id = $1 AND id = $2",
  params: #TemperCore.Vec<[
    %Temper.MarginaliaCore.Param{kind: "int", text: "7"},
    %Temper.MarginaliaCore.Param{kind: "int", text: "3"}
  ]>
}
```

Two things about the BEAM shaped the boundary:

- Alloy's objects are ordinary Temper classes, which be-elixir keeps on a
  per-process heap. Returned to a LiveView, they would pile up in its
  process. So the Temper side finishes each statement and returns `@imu`
  values, plain structs, and every Alloy object is freed when the call
  returns.
- Alloy's own `toParameterized` gives every value as text. Postgrex
  encodes parameters in binary by type and refuses a string for a
  `bigint`. Each parameter therefore carries its kind, read from Alloy's
  typed parts, and `Marginalia.Alloy` decodes it.

What changed for callers: `Folder` is a struct, not a schema, so
`Work`, `Cut`, `Story` and `Step` hold `folder_id` as a plain column and
`Cuts` fills `cut.folder` itself where it used `preload(:folder)`. A
refused write is `{:error, %Folders.Invalid{errors: %{name: [...]}}}`.
Alloy's messages replace Ecto's ("is required", "must be between 1 and 80
characters"), and Alloy counts a name's length in code points where Ecto
counted graphemes. The unique sibling-name rule is still Postgres's,
reported as before.

## What the host answers

Temper's core strings carry no Unicode character data. The few questions
that need it are `@connected` declarations in Temper, answered by
`marginalia-core/src/_connected.ex`. Each answer comes from the same engine
the original code used:

- `\s`, `\d`, `\p{Lu}`, `\p{L}`, `\p{N}` under PCRE's `u` flag
- case: `String.upcase` of a code point, `String.downcase` of a whole word
  (whole, so final sigma comes out as before)
- `String.length` and `String.slice`, which count graphemes where Temper
  counts code points

Every decision is in Temper. These only say what a character is.

## How it was verified

Each port had to be **equivalent**, not similar: on every input, the same
output as the Elixir it replaces. `temper/verify/` keeps those originals
(`old_*.exs`) and a harness per port. The harness generates random inputs
built to reach every rule, runs old and new side by side, and stops at
the first difference:

```
$ bin/temper-verify
diff       2000 word diffs and 2000 paragraph diffs: old and new identical
sentences  2000 documents: blocks, reflow, reflow_block and reflow twice all identical
reflow     2000 pages: wrapped?, reflow and align identical (wrapped 1359, with a split to mend 1309, with a split to keep 1358)
segmenter  200 manuscripts: split identical (headings 31, markers 15, windows 118, subdivided 12, with a ——— line 12)
```

Over the course of the port, 24,000 diffs, 23,000 documents, 38,000 PDF
pages and 1,900 manuscripts of up to 12,000 words matched with no
difference. The counts in brackets show the harness reaching the paths
that matter, not just passing.

Equivalence meant reproducing what the originals did, not what they
appeared to say:

- **Two kinds of whitespace.** A regex without the `u` flag means ASCII
  `\s`. `String.trim` means Unicode whitespace, NBSP included. The originals
  used both, so `text.temper.md` keeps them apart.
- **Myers' tie-breaks.** Two minimal diffs can differ. `words.temper.md`
  ports `List.myers_difference/2` step for step, compaction included, so it
  picks the one Elixir picked.
- **Floats where the original used floats.** "Unrelated" means
  `shared < 0.05 * smaller`. The integer form, `20 * shared < smaller`,
  disagrees at boundaries like 100 words, where `0.05 * 100` rounds above 5.
- **Bytes where PCRE read bytes.** The segmenter's marker regex has no `u`
  flag, so its `.{0,80}` is 80 bytes (40 `é` pass, 41 fail), and
  `[:.\-—]` is a set of bytes.

## What it costs

`bin/temper-verify bench` times the Elixir each port replaced against the
generated code (median of 15 runs):

```
                                              Elixir    Temper   ratio
word diff, 2,000-word section, 4% edited        4 ms     13 ms   3.2x
paragraph diff, 60 paragraphs                   8 ms     10 ms   1.2x
sentences reflow, 5,400 words                   2 ms      2 ms   1.1x
PDF page reflow, 400 lines                     11 ms      2 ms   0.2x
segmenter, 11,700-word manuscript              20 ms     30 ms   1.5x
```

Every one is a few milliseconds on a whole document, against an app that
waits seconds on a language model. The first numbers were worse, 3x to 5x.
Four causes were cheap to fix:

- Internal helpers had been exported, and an exported function runs
  through the library's entry check once per character.
- The Unicode predicates asked PCRE about every character. ASCII is now
  answered directly, checked against PCRE on all 128 code points.
- In be-elixir's runtime, every `StringBuilder` append was a field-map
  update plus a write barrier. It is now a single `:erlang.put`
  ([temper-blimp#146](https://github.com/notactuallytreyanastasio/temper-blimp/pull/146)).
- The ports built strings a code point at a time, because that is how a
  regex replacement reads. Five functions (`normalize`, `squeezeBlanks`,
  `breakSentences`, `paragraphs`, `alignmentKey`) now copy each run of
  unchanged text with `appendBetween` and only append what they change.
  That cut the segmenter's appends from 375,000 to a few thousand.

The word diff is what remains. Its time is spread over the Myers loop's
list and integer operations, with no single cause, where Elixir's
`List.myers_difference/2` walks native lists.

## A bug the port found

The segmenter's marker regex meant `—{3,}` as three or more em dashes.
Without the `u` flag, PCRE reads it as bytes, and `{3,}` repeats only the
em dash's last byte, a sequence valid UTF-8 never contains. So `———` was
never a section break, while `---` was. The port first reproduced this
exactly. The next commit fixes it in the Temper source and adds a test
that fails before the fix and passes after. That is the only intentional
behaviour change here, and the verify fixture for the segmenter carries
the same fix (`(?:—){3,}`).

## The backend

be-elixir is a Temper backend for Elixir and the BEAM, built in the open:
the journal and guide are at <https://bobbby.online/be-elixir>, and the code
is in the be-elixir chapters of
[temper-blimp](https://github.com/notactuallytreyanastasio/temper-blimp).
It passes all 65 of Temper's functional tests. This build relies on several
of its features:

- `@imu` classes as structs, everything else as refs into a per-process heap
- a generational collector at each exported function's edge, so a
  LiveView or GenServer calling in does not grow its heap
- self-initializing libraries: Elixir code calls in without setup
- `@connected` functions in a library's own `_connected.ex`
- deterministic, warning-free output
