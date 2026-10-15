# Small text tools

Temper has no `trim`, `toLowerCase`, `startsWith` or `length`. These are the
ones the HTTP layer needs, written on `split` and code points. None is exported:
names are shared by every library, and `core` already exports a `trim`.

    let cpStr(cp: Int): String {
      String.fromCodePoint(cp) orelse "?"
    }

    let isSpaceCp(cp: Int): Boolean { cp == 32 || cp == 9 }

Both ends, spaces and tabs only, which is what HTTP header values allow.

    let trimWs(s: String): String {
      var start = String.begin;
      while (s.hasIndex(start) && isSpaceCp(s[start])) { start = s.next(start); }
      var stop = start;
      var i = start;
      while (s.hasIndex(i)) {
        let after = s.next(i);
        if (!isSpaceCp(s[i])) { stop = after; }
        i = after;
      }
      s.slice(start, stop)
    }

ASCII only: header names, content types and file extensions.

    let lowerAscii(s: String): String {
      let out = new ListBuilder<String>();
      var i = String.begin;
      while (s.hasIndex(i)) {
        let cp = s[i];
        out.add(cpStr(if (cp >= 65 && cp <= 90) { cp + 32 } else { cp }));
        i = s.next(i);
      }
      out.toList().join("") { (x: String): String => x }
    }

    let startsWith(s: String, prefix: String): Boolean {
      let parts = s.split(prefix);
      parts.length > 1 && parts.getOr(0, "x") == ""
    }

Splitting at the first occurrence only. `found` is false when `sep` is absent,
and then `tail` is empty. The tail is rejoined natively, so a large body is
copied, not scanned.

    class Halves(public head: String, public tail: String, public found: Boolean) {}

    let splitOnce(s: String, sep: String): Halves {
      let parts = s.split(sep);
      if (parts.length < 2) {
        new Halves(s, "", false)
      } else {
        new Halves(
          parts.getOr(0, ""),
          parts.slice(1, parts.length).join(sep) { (x: String): String => x },
          true,
        )
      }
    }

UTF-8 length of a string in bytes, from its code points.

    let utf8Length(s: String): Int {
      var n = 0;
      var i = String.begin;
      while (s.hasIndex(i)) {
        let cp = s[i];
        if (cp < 0x80) { n += 1; } else if (cp < 0x800) { n += 2; } else if (cp < 0x10000) { n += 3; } else { n += 4; }
        i = s.next(i);
      }
      n
    }
