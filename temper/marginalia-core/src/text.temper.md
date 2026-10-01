# Text helpers

Temper's core `String` has no trim, replace or regex, so the handful this
library needs are here, written to match Elixir's exactly: the Elixir code
this replaces used `String.trim/1` (Unicode whitespace) and the regexes
`\s` and `\S` without the `u` flag (ASCII whitespace only). The two
definitions differ, and keeping them apart is what keeps the output the same.

    /** `\s` in a regex without the `u` flag: tab, newline, vertical tab, form feed, return, space. */
    export let isRegexSpace(cp: Int): Boolean {
      cp == 32 || (cp >= 9 && cp <= 13)
    }

    /** What `String.trim/1` strips: Unicode whitespace. */
    export let isTrimSpace(cp: Int): Boolean {
      isRegexSpace(cp) || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    /** `String.trim/1`. */
    export let trim(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && isTrimSpace(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && isTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

    /** Where `String.trim_trailing/1` would cut: the start of the trailing whitespace. */
    export let trailingStart(s: String): StringIndex {
      var e = s.end;
      while (e > String.begin && isTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      e
    }
