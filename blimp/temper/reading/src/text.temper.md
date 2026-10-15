# Small text helpers

Temper's `String` has no trim, replace, regex or byte offsets, and the Elixir
this replaces used `String.trim/1` (Unicode whitespace), `String.contains?/2`,
`:binary.match/2` and `String.slice/3`. The ones the reading contexts need are
here, written to match. Nothing is exported; the names carry a `reading`
prefix because every name in the built file shares one namespace.

Positions are code points throughout. The Elixir mixed graphemes (`String.slice`,
`String.length`) with bytes (`:binary.match`); the two only disagree for
combining marks and emoji sequences, which the matchers here do not treat
specially.

    let { isUnicodeSpace, isUnicodeLetter, isUnicodeNumber } = import("core/src");
    let { sysUtf8Downcase, sysJoin, sysGraphemeLength, sysGraphemeTake } = import("sys/src");
    let { JsonTextProducer } = import("std/json");

## Whitespace

`\s` in a regex without the `u` flag: tab, newline, vertical tab, form feed,
return, space.

    let readingIsAsciiSpace(cp: Int): Boolean {
      cp == 32 || (cp >= 9 && cp <= 13)
    }

What `String.trim/1` strips: Unicode whitespace.

    let readingIsTrimSpace(cp: Int): Boolean {
      readingIsAsciiSpace(cp) || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    let readingTrim(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && readingIsTrimSpace(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && readingIsTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

    let readingTrimLeading(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && readingIsTrimSpace(s[b])) { b = s.next(b); }
      s.slice(b, s.end)
    }

    let readingTrimTrailing(s: String): String {
      var e = s.end;
      while (e > String.begin && readingIsTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(String.begin, e)
    }

    let readingIsBlank(s: String): Boolean { readingTrim(s).isEmpty }

Every run of whitespace becomes one space. `unicode` chooses `~r/\s+/u` (true)
or `~r/\s+/` (false).

    let readingCollapse(s: String, unicode: Boolean): String {
      let out = new StringBuilder();
      var inSpace = false;
      var runStart = String.begin;
      var i = String.begin;
      while (s.hasIndex(i)) {
        let cp = s[i];
        let space = if (unicode) { isUnicodeSpace(cp) } else { readingIsAsciiSpace(cp) };
        if (space) {
          if (!inSpace) {
            out.appendBetween(s, runStart, i);
            out.append(" ");
          }
          inSpace = true;
        } else {
          if (inSpace) { runStart = i; }
          inSpace = false;
        }
        i = s.next(i);
      }
      if (!inSpace) { out.appendBetween(s, runStart, s.end); }
      out.toString()
    }

`Selection.squash/1`: `\s+` (u flag) to one space, then `String.trim/1`.

    let readingSquash(s: String): String {
      readingTrim(readingCollapse(s, true))
    }

## Searching and cutting

The number of code points in `s`.

    let readingLength(s: String): Int {
      s.countBetween(String.begin, s.end)
    }

The code point index of the first occurrence of `needle` in `hay`, or -1. An
empty needle is not found: the Elixir `:binary.match/2` raises on one, and no
caller wants a match of nothing.

    let readingIndexOf(hay: String, needle: String): Int {
      if (needle.isEmpty) { return -1; }
      let parts = hay.split(needle);
      if (parts.length < 2) { return -1; }
      readingLength(parts[0])
    }

    let readingContains(hay: String, needle: String): Boolean {
      if (needle.isEmpty) { return true; }
      hay.split(needle).length > 1
    }

`String.replace(s, old, new, global: false)`: the first occurrence only.

    let readingReplaceFirst(s: String, old: String, replacement: String): String {
      if (old.isEmpty) { return s; }
      let parts = s.split(old);
      if (parts.length < 2) { return s; }
      let rest = sysJoin(parts.slice(1, parts.length), old);
      "${parts[0]}${replacement}${rest}"
    }

    let readingStartsWith(s: String, prefix: String): Boolean {
      var i = String.begin;
      var j = String.begin;
      while (prefix.hasIndex(j)) {
        if (!s.hasIndex(i)) { return false; }
        if (s[i] != prefix[j]) { return false; }
        i = s.next(i);
        j = prefix.next(j);
      }
      true
    }

    let readingEndsWith(s: String, suffix: String): Boolean {
      var i = s.end;
      var j = suffix.end;
      while (j > String.begin) {
        if (i <= String.begin) { return false; }
        i = s.prev(i);
        j = suffix.prev(j);
        if (s[i] != suffix[j]) { return false; }
      }
      true
    }

The first `n` characters: `String.slice(s, 0, n)`.

    let readingTake(s: String, n: Int): String {
      sysGraphemeTake(s, n)
    }

The code points of `s` as a list, and a run of them back as a string.

    let readingCodePoints(s: String): List<Int> {
      let out = new ListBuilder<Int>();
      var i = String.begin;
      while (s.hasIndex(i)) {
        out.add(s[i]);
        i = s.next(i);
      }
      out.toList()
    }

`cps[from]` up to but not including `cps[until]`.

    let readingStringOf(cps: List<Int>, from: Int, until: Int): String {
      let sb = new StringBuilder();
      var k = from;
      while (k < until) {
        sb.appendCodePoint(cps[k]) orelse panic();
        k += 1;
      }
      sb.toString()
    }

`n` code points of `s` starting at code point `start`.

    let readingSliceCp(s: String, start: Int, n: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < start && s.hasIndex(i)) { i = s.next(i); k += 1; }
      let from = i;
      k = 0;
      while (k < n && s.hasIndex(i)) { i = s.next(i); k += 1; }
      s.slice(from, i)
    }

## Letters and numbers

`[^\p{L}\p{N}]+` becomes one space, after a downcase and before a trim:
`Rewrite`'s `squash`, which decides whether two candidates are the same words.

    let readingLetters(s: String): String {
      let lower = sysUtf8Downcase(s);
      let out = new StringBuilder();
      var gap = false;
      var i = String.begin;
      while (lower.hasIndex(i)) {
        let cp = lower[i];
        if (isUnicodeLetter(cp) || isUnicodeNumber(cp)) {
          out.appendCodePoint(cp) orelse panic();
          gap = false;
        } else if (!gap) {
          out.append(" ");
          gap = true;
        }
        i = lower.next(i);
      }
      readingTrim(out.toString())
    }

## Elixir's `inspect`

Just enough to write the reasons the validators report: a string in double
quotes, an integer, a float, a list.

    let readingInspectString(s: String): String {
      let sb = new StringBuilder();
      sb.append("\"");
      var i = String.begin;
      while (s.hasIndex(i)) {
        let cp = s[i];
        if (cp == 34) {
          sb.append("\\\"");
        } else if (cp == 92) {
          sb.append("\\\\");
        } else if (cp == 10) {
          sb.append("\\n");
        } else if (cp == 9) {
          sb.append("\\t");
        } else if (cp == 13) {
          sb.append("\\r");
        } else {
          sb.appendCodePoint(cp) orelse panic();
        }
        i = s.next(i);
      }
      sb.append("\"");
      sb.toString()
    }

## JSON arrays

A list of strings, or of integers, as the JSON text of an array, for the
array columns.

    let readingJsonStrings(xs: List<String>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      var i = 0;
      while (i < xs.length) {
        p.stringValue(xs[i]);
        i += 1;
      }
      p.endArray();
      p.toJsonString()
    }

    let readingJsonInts(xs: List<Int>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      var i = 0;
      while (i < xs.length) {
        p.int32Value(xs[i]);
        i += 1;
      }
      p.endArray();
      p.toJsonString()
    }

## Query parameters

A `$1`-style parameter list may hold nulls, and a list literal cannot be typed
`List<String?>` when one element is nullable, so parameters are collected one
at a time.

    class ReadingArgs {
      private var items: ListBuilder<String?> = new ListBuilder<String?>();
      public s(v: String?): ReadingArgs { items.add(v); this }
      public n(v: Int): ReadingArgs { items.add(v.toString()); this }
      public build(): List<String?> { items.toList() }
    }

    let readingArgs(): ReadingArgs { new ReadingArgs() }

## Grapheme counts

    let readingGraphemes(s: String): Int { sysGraphemeLength(s) }
