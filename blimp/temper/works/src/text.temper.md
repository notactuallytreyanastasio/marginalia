# Small text helpers

Temper's `String` has no trim, replace, contains or regex, and the Elixir this
replaces used `String.trim/1` (Unicode whitespace), `String.replace(.., global:
false)` and `String.contains?/2`. These are the ones the works context needs,
written to match. Nothing here is exported: the names are prefixed `works` so
they cannot collide with another library's private helpers either.

    let { sysUtf8Downcase, sysStringReplace, sysJoin, sysGraphemeLength, sysGraphemeTake } = import("sys/src");
    let { JsonTextProducer, JsonSyntaxTree } = import("std/json");

## Whitespace

`\s` in a regex without the `u` flag: tab, newline, vertical tab, form feed,
return, space.

    let worksIsAsciiSpace(cp: Int): Boolean {
      cp == 32 || (cp >= 9 && cp <= 13)
    }

What `String.trim/1` strips: Unicode whitespace.

    let worksIsTrimSpace(cp: Int): Boolean {
      worksIsAsciiSpace(cp) || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    let worksTrim(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && worksIsTrimSpace(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && worksIsTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

    let worksTrimLeading(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && worksIsTrimSpace(s[b])) { b = s.next(b); }
      s.slice(b, s.end)
    }

    let worksTrimTrailing(s: String): String {
      var e = s.end;
      while (e > String.begin && worksIsTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(String.begin, e)
    }

    let worksIsBlank(s: String): Boolean {
      worksTrim(s).isEmpty
    }

## Searching

Whether `hay` contains `needle`. An empty needle is contained in everything,
as `String.contains?/2` has it.

    let worksContains(hay: String, needle: String): Boolean {
      if (needle.isEmpty) { return true; }
      hay.split(needle).length > 1
    }

`String.replace(s, old, new, global: false)`: the first occurrence only. An
`old` that is absent, or empty, leaves `s` as it was.

    let worksReplaceFirst(s: String, old: String, replacement: String): String {
      if (old.isEmpty) { return s; }
      let parts = s.split(old);
      if (parts.length < 2) { return s; }
      let rest = sysJoin(parts.slice(1, parts.length), old);
      "${parts[0]}${replacement}${rest}"
    }

The number of code points in `s`.

    let worksCodePoints(s: String): Int {
      s.countBetween(String.begin, s.end)
    }

`n` code points of `s` from code point `start`.

    let worksSliceCp(s: String, start: Int, n: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < start && s.hasIndex(i)) { i = s.next(i); k += 1; }
      let from = i;
      k = 0;
      while (k < n && s.hasIndex(i)) { i = s.next(i); k += 1; }
      s.slice(from, i)
    }

The first `n` characters (graphemes), as `String.slice(s, 0, n)`.

    let worksTake(s: String, n: Int): String {
      sysGraphemeTake(s, n)
    }

## Whitespace runs

Every ASCII whitespace run becomes one space and the ends are trimmed:
`String.split(s, ~r/\s+/, trim: true) |> Enum.join(" ")`.

    let worksCollapse(s: String): String {
      let flat = worksFlatten(s);
      sysJoin(flat.split(" ").filter { (w: String): Boolean => !w.isEmpty }, " ")
    }

The same with the other kinds of space a quote may carry folded in too: the
no-break space and the zero-width space the anchor matcher also absorbs.

    let worksFlatten(s: String): String {
      let a = sysStringReplace(s, "\n", " ");
      let b = sysStringReplace(a, "\t", " ");
      let c = sysStringReplace(b, "\r", " ");
      let d = sysStringReplace(c, worksVt(), " ");
      sysStringReplace(d, worksFf(), " ")
    }

    let worksVt(): String { "\u{b}" }
    let worksFf(): String { "\u{c}" }

## JSON arrays

A list of strings as the JSON text of an array, for the array columns.

    let worksJsonStrings(xs: List<String>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      var i = 0;
      while (i < xs.length) { p.stringValue(xs[i]); i += 1; }
      p.endArray();
      p.toJsonString()
    }

    let worksJsonInts(xs: List<Int>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      var i = 0;
      while (i < xs.length) { p.int32Value(xs[i]); i += 1; }
      p.endArray();
      p.toJsonString()
    }

A list of parsed items as the JSON text of an array.

    let worksJsonItems(xs: List<JsonSyntaxTree>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      var i = 0;
      while (i < xs.length) { xs[i].produce(p); i += 1; }
      p.endArray();
      p.toJsonString()
    }

## Quotes that still anchor

`Marginalia.Analysis.Anchor.verify/2` answers whether a quote is still in the
text once whitespace, case and typography are folded away. The works context
needs only the yes or no (`supersede_unanchored`), not the source span, so
the fold is done natively on whole strings instead of keeping a per-character
index: lower-case, curly quotes to straight, en and em dashes to a hyphen, the
ellipsis to three dots, every run of whitespace to one space.

    let worksFold(s: String): String {
      let lower = sysUtf8Downcase(s);
      let q1 = sysStringReplace(lower, worksLeftSingle(), "'");
      let q2 = sysStringReplace(q1, worksRightSingle(), "'");
      let q3 = sysStringReplace(q2, worksReversedSingle(), "'");
      let q4 = sysStringReplace(q3, worksLeftDouble(), "\"");
      let q5 = sysStringReplace(q4, worksRightDouble(), "\"");
      let d1 = sysStringReplace(q5, worksEnDash(), "-");
      let d2 = sysStringReplace(d1, worksEmDash(), "-");
      let e1 = sysStringReplace(d2, worksEllipsis(), "...");
      let w1 = sysStringReplace(e1, worksNbsp(), " ");
      let w2 = sysStringReplace(w1, worksZwsp(), " ");
      worksCollapse(w2)
    }

    let worksLeftSingle(): String { "\u{2018}" }
    let worksRightSingle(): String { "\u{2019}" }
    let worksReversedSingle(): String { "\u{201b}" }
    let worksLeftDouble(): String { "\u{201c}" }
    let worksRightDouble(): String { "\u{201d}" }
    let worksEnDash(): String { "\u{2013}" }
    let worksEmDash(): String { "\u{2014}" }
    let worksEllipsis(): String { "\u{2026}" }
    let worksNbsp(): String { "\u{a0}" }
    let worksZwsp(): String { "\u{200b}" }

A quote shorter than eight characters never anchors (a short quote matches
anything). `foldedSource` is `worksFold(source)`, computed once for all the
quotes of a section.

    let worksQuoteHolds(quote: String?, foldedSource: String): Boolean {
      if (quote != null) {
        let q = worksTrim(quote);
        if (sysGraphemeLength(q) < 8) { return false; }
        let needle = worksFold(q);
        if (needle.isEmpty) { false } else { worksContains(foldedSource, needle) }
      } else {
        false
      }
    }
