# Anchoring a quote

`Marginalia.Analysis.Anchor.verify/2`: does this quote occur in this
paragraph, once whitespace, case and typography are folded away, and if so
what is the paragraph's own wording of it?

The analysis context owns this module in the Elixir. The reading page needs
it to put each note beside its paragraph, and `reading` may not import
`analysis`, so the matcher is here, ported from the same spec (notes section
2.6) and kept private to the reading contexts by its `reading` prefix. When
the analysis library exports its own, the page can switch to it.

Matching is case-insensitive, whitespace-run-insensitive and
curly-quote/dash/ellipsis-insensitive, and nothing else: no fuzzy matching.
The returned span is always a literal substring of the source.

Differences from the Elixir, both harmless: positions are code points where
the Elixir counted graphemes, and `\r\n` is two whitespace characters here
where it was one non-space grapheme there.

    let { sysUtf8Downcase } = import("sys/src");

A quote shorter than this is never anchored (a short quote matches anything).

    let readingAnchorMinChars(): Int { 8 }

## Normalising

The normalised copy of a text and, for each normalised character, the
position in the original it came from.

    class ReadingNorm(public text: String, public index: List<Int>) {}

Whitespace: space, newline, return, tab, no-break space, zero-width space.

    let readingAnchorSpace(cp: Int): Boolean {
      cp == 32 || cp == 10 || cp == 13 || cp == 9 || cp == 0xA0 || cp == 0x200B
    }

Append the folded form of one character and say how many characters that was:
curly single quotes to `'`, curly double quotes to `"`, en and em dashes to
`-`, the ellipsis to three dots, everything else lower-cased.

    let readingAnchorFold(out: StringBuilder, cp: Int): Int {
      if (cp < 128) {
        let lower = if (cp >= 65 && cp <= 90) { cp + 32 } else { cp };
        out.appendCodePoint(lower) orelse panic();
        1
      } else if (cp == 0x2018 || cp == 0x2019 || cp == 0x201B) {
        out.append("'");
        1
      } else if (cp == 0x201C || cp == 0x201D) {
        out.append("\"");
        1
      } else if (cp == 0x2013 || cp == 0x2014) {
        out.append("-");
        1
      } else if (cp == 0x2026) {
        out.append("...");
        3
      } else {
        let one = String.fromCodePoint(cp) orelse "";
        let lower = sysUtf8Downcase(one);
        out.append(lower);
        readingLength(lower)
      }
    }

Leading whitespace is dropped and a run of it becomes one space.

    let readingNormalize(text: String): ReadingNorm {
      let out = new StringBuilder();
      let index = new ListBuilder<Int>();
      var previousSpace = true;
      var position = 0;
      var i = String.begin;
      while (text.hasIndex(i)) {
        let cp = text[i];
        if (readingAnchorSpace(cp)) {
          if (!previousSpace) {
            out.append(" ");
            index.add(position);
          }
          previousSpace = true;
        } else {
          let n = readingAnchorFold(out, cp);
          var k = 0;
          while (k < n) {
            index.add(position);
            k += 1;
          }
          previousSpace = false;
        }
        position += 1;
        i = text.next(i);
      }
      new ReadingNorm(out.toString(), index.toList())
    }

## Verifying

The normalised form of a quote, or the empty string when the quote cannot
anchor anything (too short, or nothing left after folding). Computed once
per note so a page of paragraphs does not redo it.

    let readingAnchorQuote(quote: String?): String {
      if (quote != null) {
        let trimmed = readingTrim(quote);
        if (readingGraphemes(trimmed) < readingAnchorMinChars()) {
          ""
        } else {
          readingNormalize(trimmed).text
        }
      } else {
        ""
      }
    }

The span of `source` that the normalised quote `needle` stands for in the
normalised source `norm`, or null.

    let readingAnchorSpan(source: String, norm: ReadingNorm, needle: String): String? {
      if (needle.isEmpty) { return null; }
      let pos = readingIndexOf(norm.text, needle);
      if (pos < 0) { return null; }
      let from = pos;
      let to = pos + readingLength(needle) - 1;
      if (from >= norm.index.length) { return null; }
      let start = norm.index[from];
      let stop = if (to < norm.index.length) { norm.index[to] } else { start };
      if (stop < start) { return null; }
      readingStringOf(readingCodePoints(source), start, stop + 1)
    }

`{:ok, span}` as the span, `:error` (and the empty span the Elixir treated as
failure) as null.

    export let readingAnchorVerify(quote: String?, source: String?): String? {
      if (source != null) {
        let needle = readingAnchorQuote(quote);
        if (needle.isEmpty) { return null; }
        let span = readingAnchorSpan(source, readingNormalize(source), needle);
        if (span != null) {
          if (span.isEmpty) { null } else { span }
        } else {
          null
        }
      } else {
        null
      }
    }
