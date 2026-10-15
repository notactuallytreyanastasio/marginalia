# Text and calendar helpers

Temper's `String` has no trim, contains, regex or code-point constructor, and
the importers lean on all of them. Everything here is private to the library
and prefixed `importer` so it cannot collide with another library's private
helpers.

    let { sysUtf8Downcase, sysStringReplace, sysJoin, sysGraphemeLength, sysGraphemeTake, sysUtcNow } = import("sys/src");

## Code points

    let importerChr(cp: Int): String { String.fromCodePoint(cp) orelse "" }

    let importerCps(s: String): List<Int> {
      let out = new ListBuilder<Int>();
      var i = String.begin;
      while (s.hasIndex(i)) {
        out.add(s[i]);
        i = s.next(i);
      }
      out.toList()
    }

The code points `from` up to (not including) `to`, as a string.

    let importerSlice(cps: List<Int>, from: Int, to: Int): String {
      let sb = new StringBuilder();
      var i = from;
      while (i < to) {
        sb.append(importerChr(cps[i]));
        i += 1;
      }
      sb.toString()
    }

    let importerCpCount(s: String): Int {
      s.countBetween(String.begin, s.end)
    }

## Whitespace

`\s` in a PCRE without the `u` flag: tab, newline, vertical tab, form feed,
return, space.

    let importerIsSpace(cp: Int): Boolean {
      cp == 32 || (cp >= 9 && cp <= 13)
    }

What `String.trim/1` strips: Unicode whitespace.

    let importerIsTrimSpace(cp: Int): Boolean {
      importerIsSpace(cp) || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    let importerTrim(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && importerIsTrimSpace(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && importerIsTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

`String.trim(s, "\"")`: every leading and trailing double quote.

    let importerTrimQuotes(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && s[b] == 34) { b = s.next(b); }
      var e = s.end;
      while (e > b && s[s.prev(e)] == 34) { e = s.prev(e); }
      s.slice(b, e)
    }

## Searching

An empty needle is in everything, as `String.contains?/2` has it.

    let importerContains(hay: String, needle: String): Boolean {
      if (needle.isEmpty) { return true; }
      hay.split(needle).length > 1
    }

    let importerStartsWith(s: String, prefix: String): Boolean {
      var i = String.begin;
      var j = String.begin;
      while (prefix.hasIndex(j)) {
        if (!s.hasIndex(i) || s[i] != prefix[j]) { return false; }
        i = s.next(i);
        j = prefix.next(j);
      }
      true
    }

    let importerEndsWith(s: String, suffix: String): Boolean {
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

The text after the first `sep`, or null when `sep` is not there.

    let importerAfterFirst(s: String, sep: String): String? {
      let parts = s.split(sep);
      if (parts.length < 2) { return null; }
      sysJoin(parts.slice(1, parts.length), sep)
    }

`String.split(s, sep, parts: 2)` as a list of one or two strings.

    let importerSplitOnce(s: String, sep: String): List<String> {
      let parts = s.split(sep);
      if (parts.length < 2) { return [s]; }
      [parts[0], sysJoin(parts.slice(1, parts.length), sep)]
    }

    let importerLower(s: String): String { sysUtf8Downcase(s) }

    let importerReplaceAll(s: String, from: String, to: String): String {
      sysStringReplace(s, from, to)
    }

    let importerJoin(parts: List<String>, sep: String): String {
      sysJoin(parts, sep)
    }

The first `n` graphemes, as `String.slice(s, 0, n)`.

    let importerTake(s: String, n: Int): String { sysGraphemeTake(s, n) }

    let importerGraphemes(s: String): Int { sysGraphemeLength(s) }

Code point order, which is also UTF-8 byte order, as Erlang compares binaries.

    let importerCompareText(a: String, b: String): Int {
      var i = String.begin;
      var j = String.begin;
      while (a.hasIndex(i) && b.hasIndex(j)) {
        let x = a[i];
        let y = b[j];
        if (x < y) { return -1; }
        if (x > y) { return 1; }
        i = a.next(i);
        j = b.next(j);
      }
      if (a.hasIndex(i)) { 1 } else if (b.hasIndex(j)) { -1 } else { 0 }
    }

    let importerIsDigit(cp: Int): Boolean { cp >= 48 && cp <= 57 }

    let importerIsWordChar(cp: Int): Boolean {
      importerIsDigit(cp) || (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) || cp == 95
    }

`Integer.parse(s)` read as a whole string: optional sign, then digits and
nothing else. Nine digits at most; the importers deal in pull request numbers
and a longer run is not one.

    let importerParseInt(s: String): Int? {
      let cps = importerCps(s);
      var i = 0;
      var sign = 1;
      if (cps.length > 0 && (cps[0] == 43 || cps[0] == 45)) {
        if (cps[0] == 45) { sign = -1; }
        i = 1;
      }
      if (i >= cps.length) { return null; }
      if (cps.length - i > 9) { return null; }
      var n = 0;
      while (i < cps.length) {
        if (!importerIsDigit(cps[i])) { return null; }
        n = n * 10 + (cps[i] - 48);
        i += 1;
      }
      sign * n
    }

The leading digits of `s` as a number, whatever follows (`Integer.parse/1`
with a remainder), or null when there are none.

    let importerParseIntPrefix(s: String): Int? {
      let cps = importerCps(s);
      var i = 0;
      var n = 0;
      var seen = 0;
      while (i < cps.length && importerIsDigit(cps[i]) && seen < 12) {
        n = n * 10 + (cps[i] - 48);
        seen += 1;
        i += 1;
      }
      if (seen == 0) { null } else { n }
    }

## Padding

    let importerPad(n: Int, width: Int): String {
      var digits = n.toString();
      while (importerCpCount(digits) < width) { digits = "0${digits}"; }
      digits
    }

## Calendar

A date is a day number: days since 1970-01-01, which makes `Date.add` an
addition and `Date.compare` an integer comparison. The conversions are
Howard Hinnant's `days_from_civil` and `civil_from_days`.

    class ImporterCivil(public year: Int, public month: Int, public day: Int) {}

    let importerIsLeap(y: Int): Boolean {
      (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    }

    let importerLastDay(y: Int, m: Int): Int {
      if (m == 2) {
        if (importerIsLeap(y)) { 29 } else { 28 }
      } else if (m == 4 || m == 6 || m == 9 || m == 11) {
        30
      } else {
        31
      }
    }

    export let importerDayNumber(y: Int, m: Int, d: Int): Int {
      let yy = if (m <= 2) { y - 1 } else { y };
      let era = if (yy >= 0) { yy / 400 } else { (yy - 399) / 400 };
      let yoe = yy - era * 400;
      let mp = if (m > 2) { m - 3 } else { m + 9 };
      let doy = (153 * mp + 2) / 5 + d - 1;
      let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
      era * 146097 + doe - 719468
    }

    let importerCivilOf(days: Int): ImporterCivil {
      let z = days + 719468;
      let era = if (z >= 0) { z / 146097 } else { (z - 146096) / 146097 };
      let doe = z - era * 146097;
      let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
      let y = yoe + era * 400;
      let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
      let mp = (5 * doy + 2) / 153;
      let d = doy - (153 * mp + 2) / 5 + 1;
      let m = if (mp < 10) { mp + 3 } else { mp - 9 };
      new ImporterCivil(if (m <= 2) { y + 1 } else { y }, m, d)
    }

`Date.to_iso8601/1`.

    export let importerIsoDate(days: Int): String {
      let c = importerCivilOf(days);
      "${importerPad(c.year, 4)}-${importerPad(c.month, 2)}-${importerPad(c.day, 2)}"
    }

`Date.from_iso8601/1` for the four-digit-year form: `YYYY-MM-DD`, a real day,
nothing else.

    export let importerParseIso(text: String): Int? {
      let cps = importerCps(text);
      if (cps.length != 10) { return null; }
      var i = 0;
      while (i < 10) {
        if (i == 4 || i == 7) {
          if (cps[i] != 45) { return null; }
        } else {
          if (!importerIsDigit(cps[i])) { return null; }
        }
        i += 1;
      }
      let y = (cps[0] - 48) * 1000 + (cps[1] - 48) * 100 + (cps[2] - 48) * 10 + (cps[3] - 48);
      let m = (cps[5] - 48) * 10 + (cps[6] - 48);
      let d = (cps[8] - 48) * 10 + (cps[9] - 48);
      if (m < 1 || m > 12) { return null; }
      if (d < 1 || d > importerLastDay(y, m)) { return null; }
      importerDayNumber(y, m, d)
    }

Calendar months, clamped: `@today-1m` on the 31st of March is the 28th of
February, not an error and not the 3rd of March.

    let importerShiftMonths(days: Int, n: Int): Int {
      let c = importerCivilOf(days);
      let months = c.year * 12 + (c.month - 1) + n;
      let year = if (months >= 0) { months / 12 } else { (months - 11) / 12 };
      let month = months - year * 12 + 1;
      let last = importerLastDay(year, month);
      importerDayNumber(year, month, if (c.day < last) { c.day } else { last })
    }

Today in UTC, as a day number.

    export let importerToday(): Int {
      let day = importerParseIso(sysGraphemeTake(sysUtcNow(), 10));
      if (day != null) { day } else { 0 }
    }
