# Reflow

Puts the paragraphs back into text that came out of a PDF. `pdftotext`
hands back one line per line of the page, hyphens and all, and the reading
view works in paragraphs, so with no breaks a whole section is one block
with every note piled beside it. The indentation that marked a paragraph is
gone, so the break is recovered from line length: a page has a consistent
measure, and the line that ends a paragraph is the short one. When it is
wrong it splits a paragraph in two, which a reader survives. This is
`Marginalia.Works.Reflow`.

Unicode letters and numbers, case and grapheme counts come from the host
(`_connected.ex`), where the original used `\p{L}`, `\p{N}`,
`String.upcase`/`downcase` and `String.length`.

    @connected export let isUnicodeLetter(cp: Int): Boolean;
    @connected export let isUnicodeNumber(cp: Int): Boolean;
    @connected export let isUpcaseFixed(cp: Int): Boolean;
    @connected export let downcase(s: String): String;
    @connected export let graphemeLength(s: String): Int;

## Does it need it

Many lines, almost no blank ones: at least 12 non-blank lines, and at most
one blank gap per 12. A gap is what `~r/\n\s*\n/` matches: a run of ASCII
space holding two or more newlines.

    export let isWrapped(text: String): Boolean {
      let lines = text.split("\n");
      var nonBlank = 0;
      for (var k = 0; k < lines.length; ++k) {
        if (!trim(lines[k]).isEmpty) { nonBlank += 1; }
      }
      var gaps = 0;
      var i = String.begin;
      while (text.hasIndex(i)) {
        if (isRegexSpace(text[i])) {
          var newlines = 0;
          while (text.hasIndex(i) && isRegexSpace(text[i])) {
            if (text[i] == 10) { newlines += 1; }
            i = text.next(i);
          }
          if (newlines >= 2) { gaps += 1; }
        } else {
          i = text.next(i);
        }
      }
      nonBlank >= 12 && gaps <= nonBlank / 12
    }

    export let reflowPage(text: String): String {
      if (!isWrapped(text)) { return text; }
      let keep = intactHyphens(text);
      let raw = normalizeNewlines(text).split("\n");
      let lines = new ListBuilder<String>();
      for (var k = 0; k < raw.length; ++k) {
        let line = trim(raw[k]);
        if (!isFurniture(line) && !line.isEmpty) { lines.add(line); }
      }
      let all = lines.toList();
      let paragraphs = chunkParagraphs(all, measure(all));
      let out = new ListBuilder<String>();
      for (var k = 0; k < paragraphs.length; ++k) {
        let p = join(paragraphs[k], keep);
        if (!p.isEmpty) { out.add(p); }
      }
      joinWith(out.toList(), "\n\n")
    }

`String.replace(text, "\r\n", "\n")`.

    let normalizeNewlines(text: String): String {
      joinWith(text.split("\r\n"), "\n")
    }

## The measure

The usual line length, in graphemes: the line two thirds of the way up the
sorted lengths, so a handful of one-word lines cannot drag it down.

    let measure(lines: List<String>): Int {
      if (lines.isEmpty) { return 0; }
      let lengths = lines.map { (l): Int => graphemeLength(l) }.sorted { (a, b): Int => a - b };
      lengths[lengths.length * 2 / 3]
    }

A paragraph runs until a line under 78% of the measure, or a heading, which
stands alone. Compared in floats, as the original was.

    let chunkParagraphs(lines: List<String>, measure: Int): List<List<String>> {
      let done = new ListBuilder<List<String>>();
      let current = new ListBuilder<String>();
      for (var k = 0; k < lines.length; ++k) {
        let line = lines[k];
        if (isHeading(line)) {
          done.add(current.toList());
          done.add([line]);
          current.clear();
        } else if (graphemeLength(line).toFloat64() < measure.toFloat64() * 0.78) {
          current.add(line);
          done.add(current.toList());
          current.clear();
        } else {
          current.add(line);
        }
      }
      done.add(current.toList());
      done.toList().filter { (p): Boolean => !p.isEmpty }
    }

A markdown heading (`^\#{1,6}\s+\S`), or the bare Roman numeral or capital
an opinion divides on (`^[IVXL]{1,5}$`, `^[A-Z]$`).

    let isHeading(line: String): Boolean {
      var i = String.begin;
      var hashes = 0;
      while (line.hasIndex(i) && line[i] == 35) {
        hashes += 1;
        i = line.next(i);
      }
      if (hashes >= 1 && hashes <= 6 && line.hasIndex(i) && isRegexSpace(line[i])) {
        while (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
        if (line.hasIndex(i)) { return true; }
      }
      let n = line.countBetween(String.begin, line.end);
      if (n >= 1 && n <= 5 && allIn(line, "IVXL")) { return true; }
      n == 1 && line[String.begin] >= 65 && line[String.begin] <= 90
    }

    let allIn(s: String, chars: String): Boolean {
      var i = String.begin;
      while (s.hasIndex(i)) {
        if (!contains(chars, s[i])) { return false; }
        i = s.next(i);
      }
      true
    }

    let contains(chars: String, cp: Int): Boolean {
      var i = String.begin;
      while (chars.hasIndex(i)) {
        if (chars[i] == cp) { return true; }
        i = chars.next(i);
      }
      false
    }

## Page furniture

The running head and foot of a slip opinion.

    let isFurniture(line: String): Boolean {
      startsWith(line, "Cite as:") || line == "Opinion of the Court" || line == "Syllabus" ||
        line == "Per Curiam" || isJudgeLine(line) || isPageNumber(line) || isCaption(line)
    }

`^\d{1,3}$`.

    let isPageNumber(line: String): Boolean {
      let n = line.countBetween(String.begin, line.end);
      n >= 1 && n <= 3 && allAsciiDigits(line, String.begin, line.end)
    }

    let allAsciiDigits(s: String, from: StringIndex, to: StringIndex): Boolean {
      var i = from;
      while (i < to) {
        if (s[i] < 48 || s[i] > 57) { return false; }
        i = s.next(i);
      }
      true
    }

`^(?:[A-Z]+, )+(?:C\. )?J\.,\s+(?:concurring|dissenting)`: "GORSUCH, J.,
dissenting", "ROBERTS, C. J., concurring in part". The repeated group can
never swallow `C. ` or `J.,`, which hold a period, so a greedy parse
decides it.

    let isJudgeLine(line: String): Boolean {
      var i = String.begin;
      var names = 0;
      while (true) {
        var j = i;
        var caps = 0;
        while (line.hasIndex(j) && line[j] >= 65 && line[j] <= 90) {
          caps += 1;
          j = line.next(j);
        }
        if (caps == 0 || !line.hasIndex(j) || line[j] != 44) { break; }
        let space = line.next(j);
        if (!line.hasIndex(space) || line[space] != 32) { break; }
        names += 1;
        i = line.next(space);
      }
      if (names == 0) { return false; }
      let rest = line.slice(i, line.end);
      var at = String.begin;
      if (startsWith(rest, "C. ")) { at = rest.step(at, 3); }
      let tail = rest.slice(at, rest.end);
      if (!startsWith(tail, "J.,")) { return false; }
      var k = tail.step(String.begin, 3);
      var spaces = 0;
      while (tail.hasIndex(k) && isRegexSpace(tail[k])) {
        spaces += 1;
        k = tail.next(k);
      }
      let word = tail.slice(k, tail.end);
      spaces >= 1 && (startsWith(word, "concurring") || startsWith(word, "dissenting"))
    }

The running head is the case caption in capitals, with a page number on
one side: "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND". Not quite all
capitals (the "v." never is), so it is counted: at least 8 letters, 75% of
them unchanged by upcasing. The page number goes first, as
`~r/^\d{1,3}\s+|\s+\d{1,3}$/` removed it.

    let isCaption(line: String): Boolean {
      let body = withoutPageNumbers(line);
      var letters = 0;
      var upper = 0;
      var i = String.begin;
      while (body.hasIndex(i)) {
        let cp = body[i];
        if (isUnicodeLetter(cp)) {
          letters += 1;
          if (isUpcaseFixed(cp)) { upper += 1; }
        }
        i = body.next(i);
      }
      if (letters < 8) { return false; }
      // letters is at least 8 here, so the division cannot fail
      let ratio = upper.toFloat64() / letters.toFloat64() orelse panic();
      ratio >= 0.75
    }

    let withoutPageNumbers(line: String): String {
      var s = line;
      // ^\d{1,3}\s+
      var i = String.begin;
      var digits = 0;
      while (s.hasIndex(i) && s[i] >= 48 && s[i] <= 57 && digits < 4) {
        digits += 1;
        i = s.next(i);
      }
      if (digits >= 1 && digits <= 3 && s.hasIndex(i) && isRegexSpace(s[i])) {
        while (s.hasIndex(i) && isRegexSpace(s[i])) { i = s.next(i); }
        s = s.slice(i, s.end);
      }
      // \s+\d{1,3}$
      var e = s.end;
      var tailDigits = 0;
      while (e > String.begin && s[s.prev(e)] >= 48 && s[s.prev(e)] <= 57 && tailDigits < 4) {
        tailDigits += 1;
        e = s.prev(e);
      }
      if (tailDigits >= 1 && tailDigits <= 3 && e > String.begin && isRegexSpace(s[s.prev(e)])) {
        while (e > String.begin && isRegexSpace(s[s.prev(e)])) { e = s.prev(e); }
        s = s.slice(String.begin, e);
      }
      s
    }

## Hyphens

`capaci-\nties` should become one word and `for-\ncause` keep its hyphen,
and nothing about the two looks different. So the document is asked: if
`for-cause` appears somewhere else in it, intact within a line, the hyphen
is real. These are the matches of `~r/[\p{L}\p{N}’']+-[\p{L}\p{N}’']+/u`,
lowercased.

    let isWordChar(cp: Int): Boolean {
      cp == 0x2019 || cp == 39 || isUnicodeLetter(cp) || isUnicodeNumber(cp)
    }

    let intactHyphens(text: String): MapBuilder<String, Boolean> {
      let found = new MapBuilder<String, Boolean>();
      var i = String.begin;
      while (text.hasIndex(i)) {
        if (!isWordChar(text[i])) {
          i = text.next(i);
          continue;
        }
        let start = i;
        while (text.hasIndex(i) && isWordChar(text[i])) { i = text.next(i); }
        // a match starts where a run of word characters does, or nowhere in it
        if (text.hasIndex(i) && text[i] == 45) {
          let after = text.next(i);
          if (text.hasIndex(after) && isWordChar(text[after])) {
            var e = after;
            while (text.hasIndex(e) && isWordChar(text[e])) { e = text.next(e); }
            found.set(downcase(text.slice(start, e)), true);
            i = e;
          }
        }
      }
      found
    }

Lines joined with spaces, a trailing hyphen mended or kept.

    let join(lines: List<String>, keep: MapBuilder<String, Boolean>): String {
      var acc = "";
      for (var k = 0; k < lines.length; ++k) {
        let line = lines[k];
        if (acc.isEmpty) {
          acc = line;
        } else if (endsWithAt(acc, acc.end, "-")) {
          acc = mend(acc, line, keep);
        } else {
          acc = "${acc} ${line}";
        }
      }
      trim(acc)
    }

`capaci-` and `ties`: one word or two?

    let mend(acc: String, line: String, keep: MapBuilder<String, Boolean>): String {
      let unhyphened = withoutTrailingHyphens(acc);
      let stem = lastAsciiSpaceField(unhyphened);
      let head = firstAsciiSpaceField(line);
      let word = downcase("${stem}-${stripTrailingPunct(head)}");
      if (keep.has(word)) { "${acc}${line}" } else { "${unhyphened}${line}" }
    }

`String.trim_trailing(acc, "-")`: every trailing hyphen.

    let withoutTrailingHyphens(s: String): String {
      var e = s.end;
      while (e > String.begin && s[s.prev(e)] == 45) { e = s.prev(e); }
      s.slice(String.begin, e)
    }

`String.split(s, ~r/\s/) |> List.last()`: after the last ASCII space.

    let lastAsciiSpaceField(s: String): String {
      var b = s.end;
      while (b > String.begin && !isRegexSpace(s[s.prev(b)])) { b = s.prev(b); }
      s.slice(b, s.end)
    }

`String.split(line, ~r/\s/, parts: 2) |> hd()`: before the first.

    let firstAsciiSpaceField(s: String): String {
      var e = String.begin;
      while (s.hasIndex(e) && !isRegexSpace(s[e])) { e = s.next(e); }
      s.slice(String.begin, e)
    }

`~r/[^\p{L}\p{N}'’-]+$/u` removed: the trailing run of anything else.

    let stripTrailingPunct(word: String): String {
      var e = word.end;
      while (e > String.begin && !isWordChar(word[word.prev(e)]) && word[word.prev(e)] != 45) {
        e = word.prev(e);
      }
      word.slice(String.begin, e)
    }

## A quote, through the same joining

A quote anchored into reflowed text must be mended the same way, or one
spanning a mended hyphen would keep its `capaci-` and never verify again.
Hyphens are decided against the whole source.

    export let align(quote: String, source: String): String {
      let raw = normalizeNewlines(quote).split("\n");
      let lines = new ListBuilder<String>();
      for (var k = 0; k < raw.length; ++k) {
        let line = trim(raw[k]);
        if (!line.isEmpty) { lines.add(line); }
      }
      join(lines.toList(), intactHyphens(source))
    }
