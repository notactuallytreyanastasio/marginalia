# Anchor: is this quote in the writer's text

`Marginalia.Analysis.Anchor`. A model-supplied quote is checked against the
source after whitespace, case and typography are folded away, and the answer
is the source's own span, newlines and curly quotes intact. There is no fuzzy
matching: a reordered, shortened or reworded quote is refused.

    let { NodeParams } = import("works/src");
    let { sysUtf8Downcase, sysGraphemeLength } = import("sys/src");

The shortest quote that is allowed to match; a shorter one matches anything.

    export let anchorMinChars(): Int { 8 }

## Result

`ok` false means `:error`; `span` is then empty. A match whose span came out
empty is also not ok, as the callers treat an empty span as failure.

    export class AnchorResult(public ok: Boolean, public span: String) {}

    let anchorFail(): AnchorResult { new AnchorResult(false, "") }

## The normalised copy

`text` is the folded copy. For each of its code points, `starts` and `ends`
give the code point range, in the original, of the grapheme cluster it came
from. (The Elixir kept one index per grapheme; the host here is code points,
and a cluster's code points all map to the cluster, which gives the same
spans.)

    export class AnchorIndex(
      public text: String,
      public starts: List<Int>,
      public ends: List<Int>,
    ) {}

Extending code points that stay with the one before: combining marks, the
variation selectors, skin tones, tags. A ZWJ takes the next code point with
it, and CR LF is one cluster. That is the part of UAX 29 that matters for
prose; Hangul jamo and regional-indicator pairs are not joined, which only
matters for where a span may end, never for what matches.

    let anchorExtends(c: Int): Boolean {
      (c >= 0x300 && c <= 0x36F) || (c >= 0x1AB0 && c <= 0x1AFF) ||
        (c >= 0x1DC0 && c <= 0x1DFF) || (c >= 0x20D0 && c <= 0x20FF) ||
        (c >= 0xFE00 && c <= 0xFE0F) || (c >= 0xFE20 && c <= 0xFE2F) ||
        (c >= 0x1F3FB && c <= 0x1F3FF) || (c >= 0xE0020 && c <= 0xE007F) ||
        c == 0x200C || c == 0x200D
    }

The whitespace set, exactly: space, newline, return, tab, no-break space,
zero-width space. (A CR LF cluster is none of them and is kept.)

    let anchorIsSpace(c: Int): Boolean {
      c == 32 || c == 10 || c == 13 || c == 9 || c == 0xA0 || c == 0x200B
    }

`fold` of a one-code-point cluster, or null for "just downcase it".

    let anchorFoldSpecial(c: Int): String? {
      if (c == 0x2018 || c == 0x2019 || c == 0x201B) {
        "'"
      } else if (c == 0x201C || c == 0x201D) {
        "\""
      } else if (c == 0x2013 || c == 0x2014) {
        "-"
      } else if (c == 0x2026) {
        "..."
      } else {
        null
      }
    }

`normalize_indexed`: leading whitespace is dropped, a run of whitespace is one
space, everything else is folded. With `withIndex` false the two index lists
are left empty (a quote needs only its text).

    export let anchorNormalize(text: String, withIndex: Boolean): AnchorIndex {
      let out = new StringBuilder();
      let starts = new ListBuilder<Int>();
      let ends = new ListBuilder<Int>();
      var prevSpace = true;
      var i = String.begin;
      var cp = 0;
      while (text.hasIndex(i)) {
        let c = text[i];
        var j = text.next(i);
        var n = 1;
        if (c == 13 && text.hasIndex(j) && text[j] == 10) {
          j = text.next(j);
          n += 1;
        } else {
          var more = true;
          while (more && text.hasIndex(j)) {
            let d = text[j];
            if (anchorExtends(d)) {
              j = text.next(j);
              n += 1;
              if (d == 0x200D && text.hasIndex(j)) {
                j = text.next(j);
                n += 1;
              }
            } else {
              more = false;
            }
          }
        }
        if (n == 1 && anchorIsSpace(c)) {
          if (!prevSpace) {
            out.append(" ");
            if (withIndex) {
              starts.add(cp);
              ends.add(cp + 1);
            }
          }
          prevSpace = true;
        } else {
          var folded: String = "";
          var count = 1;
          let special = if (n == 1) { anchorFoldSpecial(c) } else { null };
          if (special != null) {
            folded = special;
            count = if (special == "...") { 3 } else { 1 };
            out.append(folded);
          } else if (n == 1 && c < 128) {
            if (c >= 65 && c <= 90) {
              out.append(sysUtf8Downcase(text.slice(i, j)));
            } else {
              out.appendBetween(text, i, j);
            }
          } else {
            folded = sysUtf8Downcase(text.slice(i, j));
            count = folded.countBetween(String.begin, folded.end);
            out.append(folded);
          }
          if (withIndex) {
            var k = 0;
            while (k < count) {
              starts.add(cp);
              ends.add(cp + n);
              k += 1;
            }
          }
          prevSpace = false;
        }
        cp += n;
        i = j;
      }
      new AnchorIndex(out.toString(), starts.toList(), ends.toList())
    }

## Verify

The index of a source, built once and used for every quote of a section.

    export let anchorPrepare(source: String): AnchorIndex {
      anchorNormalize(source, true)
    }

`verify` against a prepared source.

    export let anchorVerifyIn(quote: String?, source: String, prepared: AnchorIndex): AnchorResult {
      if (quote != null) {
        anchorVerifyTrimmed(anTrim(quote), source, prepared)
      } else {
        anchorFail()
      }
    }

    let anchorVerifyTrimmed(q: String, source: String, prepared: AnchorIndex): AnchorResult {
      if (sysGraphemeLength(q) < anchorMinChars()) { return anchorFail(); }
      let needle = anchorNormalize(q, false).text;
      if (needle.isEmpty) { return anchorFail(); }
      let parts = prepared.text.split(needle);
      if (parts.length < 2) { return anchorFail(); }
      let from = anCodePoints(parts[0]);
      let to = from + anCodePoints(needle) - 1;
      if (to >= prepared.starts.length) { return anchorFail(); }
      let start = prepared.starts[from];
      let stop = prepared.ends[to];
      if (stop <= start) { return anchorFail(); }
      let span = anSliceCp(source, start, stop);
      if (span.isEmpty) { anchorFail() } else { new AnchorResult(true, span) }
    }

`Anchor.verify/2`. A null quote or source is an error; so is a quote under
eight graphemes once trimmed; so is anything that is not there word for word.

    export let anchorVerify(quote: String?, source: String?): AnchorResult {
      if (quote != null) {
        if (source != null) {
          return anchorVerifyIn(quote, source, anchorPrepare(source));
        }
      }
      anchorFail()
    }

## Filter

    export class AnchorFiltered(public kept: List<NodeParams>, public dropped: Int) {}

`Anchor.filter/2`: keep the candidates whose quote verifies, each rewritten to
the source's wording, in order; count the rest. The candidates are changed in
place (a quote is replaced, as `Map.put` did on a copy).

    export let anchorFilter(nodes: List<NodeParams>, source: String): AnchorFiltered {
      let prepared = anchorPrepare(source);
      let kept = new ListBuilder<NodeParams>();
      var dropped = 0;
      for (let node of nodes) {
        let r = anchorVerifyIn(node.quote, source, prepared);
        if (r.ok) {
          node.quote = r.span;
          kept.add(node);
        } else {
          dropped += 1;
        }
      }
      new AnchorFiltered(kept.toList(), dropped)
    }
