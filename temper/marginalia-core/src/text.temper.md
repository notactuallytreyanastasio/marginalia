# Text helpers

Temper's core `String` has no trim, replace or regex, so the handful this
library needs are here, written to match Elixir's exactly: the Elixir code
this replaces used `String.trim/1` (Unicode whitespace) and the regexes
`\s` and `\S` without the `u` flag (ASCII whitespace only). The two
definitions differ, and keeping them apart is what keeps the output the same.

    /** `\s` in a regex without the `u` flag: tab, newline, vertical tab, form feed, return, space. */
    let isRegexSpace(cp: Int): Boolean {
      cp == 32 || (cp >= 9 && cp <= 13)
    }

    /** What `String.trim/1` strips: Unicode whitespace. */
    let isTrimSpace(cp: Int): Boolean {
      isRegexSpace(cp) || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    /** `String.trim/1`. */
    let trim(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && isTrimSpace(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && isTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

    /** Where `String.trim_trailing/1` would cut: the start of the trailing whitespace. */
    let trailingStart(s: String): StringIndex {
      var e = s.end;
      while (e > String.begin && isTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      e
    }

    /** Where `String.trim_leading/1` would cut: the end of the leading whitespace. */
    let leadingEnd(s: String): StringIndex {
      var b = String.begin;
      while (s.hasIndex(b) && isTrimSpace(s[b])) { b = s.next(b); }
      b
    }

    let trimLeading(s: String): String { s.slice(leadingEnd(s), s.end) }

    let trimTrailing(s: String): String { s.slice(String.begin, trailingStart(s)) }

    /** Whether `s` begins with `prefix`. */
    let startsWith(s: String, prefix: String): Boolean {
      var i = String.begin;
      var j = String.begin;
      while (prefix.hasIndex(j)) {
        if (!s.hasIndex(i) || s[i] != prefix[j]) { return false; }
        i = s.next(i);
        j = prefix.next(j);
      }
      true
    }

    /** Whether `s` ends with `suffix`, the suffix ending at `end`. */
    let endsWithAt(s: String, end: StringIndex, suffix: String): Boolean {
      var i = end;
      var j = suffix.end;
      while (j > String.begin) {
        if (i <= String.begin) { return false; }
        i = s.prev(i);
        j = suffix.prev(j);
        if (s[i] != suffix[j]) { return false; }
      }
      true
    }

    let joinWith(parts: List<String>, sep: String): String {
      parts.join(sep) { (p): String => p }
    }
