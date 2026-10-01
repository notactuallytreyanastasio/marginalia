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
