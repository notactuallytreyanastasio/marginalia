# Sentences

Prose stored one sentence per line: blank lines still separate paragraphs,
and inside a prose paragraph each sentence gets its own line, so diffs by
line mark a sentence changed rather than a 300-word paragraph. Anything that
is not a prose paragraph (headings, code, tables, lists, HTML) is left as it
came: a poem reflowed into sentences is a poem destroyed. This is
`Marginalia.Works.Sentences`. Reflowing reflowed text changes nothing.

## Unicode classes

The sentence rules came from regexes with the `u` flag, where `\s`, `\d`
and `\p{Lu}` are Unicode classes. Temper's core strings carry no Unicode
character data, so these three are answered by the host, which asks PCRE
the same question (`_connected.ex`).

    @connected export let isUnicodeSpace(cp: Int): Boolean;
    @connected export let isUnicodeUpper(cp: Int): Boolean;
    @connected export let isUnicodeDigit(cp: Int): Boolean;

Closing marks that may follow a sentence's last character, and opening
marks that may come before the next sentence's first.

    let isCloser(cp: Int): Boolean {
      cp == 34 || cp == 39 || cp == 0x201D || cp == 0x2019 || cp == 41 || cp == 93
    }

    let isOpener(cp: Int): Boolean {
      cp == 34 || cp == 39 || cp == 0x201C || cp == 0x2018 || cp == 40 || cp == 91 ||
        cp == 42 || cp == 95 || cp == 96
    }

## Reflow

    export let reflow(text: String): String {
      if (text.isEmpty) { return ""; }
      joinWith(blocks(text).map { (b): String => reflowBlock(b) }, "\n\n")
    }

    export let reflowBlock(block: String): String {
      if (!isProse(block)) { return block; }
      if (isQuoted(block)) { return reflowQuote(block); }
      splitSentences(trim(squeezeBlanks(unwrap(block))))
    }

A quote can hold paragraphs of its own, separated by a bare `>` line, so
the stripped text goes through the whole reflow, and an empty line comes
back as a bare `>`.

    let reflowQuote(block: String): String {
      let lines = block.split("\n");
      let stripped = joinWith(lines.map { (l): String => stripQuoteMark(l) }, "\n");
      let back = reflow(stripped).split("\n");
      joinWith(back.map { (l): String => if (l.isEmpty) { ">" } else { "> ${l}" } }, "\n")
    }

`^\s*>\s?` removed: leading ASCII space, the `>`, one space after it. A line
with no `>` comes back as it was.

    let stripQuoteMark(line: String): String {
      var i = String.begin;
      while (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
      if (!line.hasIndex(i) || line[i] != 62) { return line; }
      i = line.next(i);
      if (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
      line.slice(i, line.end)
    }

    let isQuoted(block: String): Boolean {
      var i = String.begin;
      while (block.hasIndex(i) && isRegexSpace(block[i])) { i = block.next(i); }
      block.hasIndex(i) && block[i] == 62
    }

The hard wraps go: `String.split(~r/\s*\n\s*/)` joined with spaces, which
drops the ASCII space either side of every newline.

    let unwrap(block: String): String {
      let lines = block.split("\n");
      let last = lines.length - 1;
      let pieces = new ListBuilder<String>();
      for (var k = 0; k <= last; ++k) {
        let line = lines[k];
        var b = String.begin;
        var e = line.end;
        if (k > 0) {
          while (line.hasIndex(b) && isRegexSpace(line[b])) { b = line.next(b); }
        }
        if (k < last) {
          while (e > b && isRegexSpace(line[line.prev(e)])) { e = line.prev(e); }
        }
        pieces.add(line.slice(b, e));
      }
      joinWith(pieces.toList(), " ")
    }

`~r/[ \t]+/` to one space.

    let squeezeBlanks(text: String): String {
      let out = new StringBuilder();
      // everything between blank runs is copied a run at a time
      var runStart = String.begin;
      var i = String.begin;
      while (text.hasIndex(i)) {
        if (text[i] == 32 || text[i] == 9) {
          out.appendBetween(text, runStart, i);
          out.append(" ");
          while (text.hasIndex(i) && (text[i] == 32 || text[i] == 9)) { i = text.next(i); }
          runStart = i;
        } else {
          i = text.next(i);
        }
      }
      out.appendBetween(text, runStart, text.end);
      out.toString()
    }

## Sentence ends

A sentence ends at `.`, `!` or `?`, any closing marks, then Unicode space,
when what follows (past any opening marks) is a capital or a digit. The
space is replaced by a newline. This is
`~r/([.!?]["'”’)\]]*)\s+(?=["'“‘(\[*_`]*(?:\p{Lu}|\d))/u` replaced with
`"\1\n"`; its quantifiers never need to give anything back, so one greedy
pass decides each candidate. The scan resumes after the space, as the
regex's did.

    let breakSentences(text: String): String {
      let out = new StringBuilder();
      // text up to each break is copied a run at a time
      var runStart = String.begin;
      var i = String.begin;
      while (text.hasIndex(i)) {
        let cp = text[i];
        if (cp == 46 || cp == 33 || cp == 63) {
          var j = text.next(i);
          while (text.hasIndex(j) && isCloser(text[j])) { j = text.next(j); }
          var k = j;
          while (text.hasIndex(k) && isUnicodeSpace(text[k])) { k = text.next(k); }
          var m = k;
          while (text.hasIndex(m) && isOpener(text[m])) { m = text.next(m); }
          if (k > j && text.hasIndex(m) && (isUnicodeUpper(text[m]) || isUnicodeDigit(text[m]))) {
            out.appendBetween(text, runStart, j);
            out.append("\n");
            i = k;
            runStart = k;
            continue;
          }
        }
        i = text.next(i);
      }
      out.appendBetween(text, runStart, text.end);
      out.toString()
    }

One line per sentence, except where the "sentence" ended on an
abbreviation, which is rejoined with the next.

    let splitSentences(joined: String): String {
      let lines = breakSentences(joined).split("\n");
      let out = new ListBuilder<String>();
      for (var k = 0; k < lines.length; ++k) {
        let n = out.length;
        if (n > 0 && endsOnAbbreviation(out[n - 1])) {
          out[n - 1] = "${out[n - 1]} ${lines[k]}";
        } else {
          out.add(lines[k]);
        }
      }
      joinWith(out.toList(), "\n")
    }

A period after one of these is not a sentence end; single capitals cover
initials ("J. K. Rowling"). The list is short by design: a missed
abbreviation costs one wrong break, a wrong entry costs a missed boundary on
every draft. This is
`~r/(?:^|\s)(?:e\.g|i\.e|vs|...|[A-Z])\.["'”’)\]]*$/u`.

    let abbreviations = [
      "e.g", "i.e", "vs", "etc", "cf", "viz", "ca", "Mr", "Mrs", "Ms", "Dr", "Prof",
      "St", "No", "Fig", "Jr", "Sr", "Inc", "Ltd", "Co",
    ];

    let endsOnAbbreviation(line: String): Boolean {
      var e = line.end;
      while (e > String.begin && isCloser(line[line.prev(e)])) { e = line.prev(e); }
      if (e <= String.begin || line[line.prev(e)] != 46) { return false; }
      let dot = line.prev(e);
      for (var k = 0; k < abbreviations.length; ++k) {
        if (abbreviationAt(line, dot, abbreviations[k])) { return true; }
      }
      // [A-Z]: one ASCII capital
      if (dot > String.begin) {
        let c = line.prev(dot);
        let cp = line[c];
        if (cp >= 65 && cp <= 90 && startsAWord(line, c)) { return true; }
      }
      false
    }

    let abbreviationAt(line: String, dot: StringIndex, word: String): Boolean {
      if (!endsWithAt(line, dot, word)) { return false; }
      var start = dot;
      for (var k = 0; k < word.countBetween(String.begin, word.end); ++k) { start = line.prev(start); }
      startsAWord(line, start)
    }

    /** `(?:^|\s)` before `at`, with the `u` flag's `\s`. */
    let startsAWord(line: String, at: StringIndex): Boolean {
      at <= String.begin || isUnicodeSpace(line[line.prev(at)])
    }

## What counts as prose

Everything markdown gives line breaks a meaning in is left alone. These
are the original's tests in order, each regex spelled out; ASCII `\s`
throughout, since none of them had the `u` flag.

    let isProse(block: String): Boolean {
      let lines = block.split("\n");
      let first = trimLeading(lines[0]);
      let second = if (lines.length > 1) { trim(lines[1]) } else { "" };
      if (isUnderline(second)) { return false; }
      if (isTableDelimiter(second)) { return false; }
      if (startsWith(first, "```") || startsWith(first, "~~~")) { return false; }
      if (isAtxHeading(first)) { return false; }
      if (isIndentedCode(block)) { return false; }
      if (isListItem(first)) { return false; }
      if (isHtml(first)) { return false; }
      if (isLoneLinkOrImage(block)) { return false; }
      if (isRule(first)) { return false; }
      var allPiped = true;
      for (var k = 0; k < lines.length; ++k) {
        if (!startsWith(trimLeading(lines[k]), "|")) { allPiped = false; }
      }
      !allPiped
    }

`^(=+|-+)$`: a setext underline.

    let isUnderline(s: String): Boolean {
      if (s.isEmpty) { return false; }
      let mark = s[String.begin];
      if (mark != 61 && mark != 45) { return false; }
      allOf(s, String.begin, s.end, mark)
    }

    let allOf(s: String, from: StringIndex, to: StringIndex, cp: Int): Boolean {
      var i = from;
      while (i < to) {
        if (s[i] != cp) { return false; }
        i = s.next(i);
      }
      true
    }

`^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?$`: a table's delimiter row.

    let isTableDelimiter(s: String): Boolean {
      var i = String.begin;
      if (s.hasIndex(i) && s[i] == 124) { i = s.next(i); }
      let first = delimiterCell(s, i);
      if (first == null) { return false; }
      i = first as StringIndex orelse panic();
      while (true) {
        if (!s.hasIndex(i)) { return true; }
        if (s[i] != 124) { return false; }
        let after = s.next(i);
        let cell = delimiterCell(s, after);
        if (cell == null) {
          // the closing pipe, which must end the row
          return !s.hasIndex(after);
        }
        i = cell as StringIndex orelse panic();
      }
    }

`\s*:?-{3,}:?\s*` from `at`; where it ends, or null.

    let delimiterCell(s: String, at: StringIndex): StringIndex? {
      var i = at;
      while (s.hasIndex(i) && isRegexSpace(s[i])) { i = s.next(i); }
      if (s.hasIndex(i) && s[i] == 58) { i = s.next(i); }
      var dashes = 0;
      while (s.hasIndex(i) && s[i] == 45) {
        dashes += 1;
        i = s.next(i);
      }
      if (dashes < 3) { return null; }
      if (s.hasIndex(i) && s[i] == 58) { i = s.next(i); }
      while (s.hasIndex(i) && isRegexSpace(s[i])) { i = s.next(i); }
      i
    }

`^\#{1,6}\s`.

    let isAtxHeading(s: String): Boolean {
      var i = String.begin;
      var hashes = 0;
      while (s.hasIndex(i) && s[i] == 35) {
        hashes += 1;
        i = s.next(i);
      }
      hashes >= 1 && hashes <= 6 && s.hasIndex(i) && isRegexSpace(s[i])
    }

`^(\s{4,}|\t)`: indented code.

    let isIndentedCode(block: String): Boolean {
      if (block.hasIndex(String.begin) && block[String.begin] == 9) { return true; }
      var i = String.begin;
      var spaces = 0;
      while (block.hasIndex(i) && isRegexSpace(block[i]) && spaces < 4) {
        spaces += 1;
        i = block.next(i);
      }
      spaces >= 4
    }

`^[-*+]\s|^\d+[.)]\s`.

    let isListItem(s: String): Boolean {
      if (!s.hasIndex(String.begin)) { return false; }
      let c = s[String.begin];
      let after = s.next(String.begin);
      if ((c == 45 || c == 42 || c == 43) && s.hasIndex(after) && isRegexSpace(s[after])) { return true; }
      var i = String.begin;
      var digits = 0;
      while (s.hasIndex(i) && s[i] >= 48 && s[i] <= 57) {
        digits += 1;
        i = s.next(i);
      }
      if (digits == 0 || !s.hasIndex(i) || (s[i] != 46 && s[i] != 41)) { return false; }
      let next = s.next(i);
      s.hasIndex(next) && isRegexSpace(s[next])
    }

`^<[a-zA-Z!\/]`.

    let isHtml(s: String): Boolean {
      if (!s.hasIndex(String.begin) || s[String.begin] != 60) { return false; }
      let next = s.next(String.begin);
      if (!s.hasIndex(next)) { return false; }
      let c = s[next];
      (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 33 || c == 47
    }

`^!?\[[^\]]*\]\([^)]*\)\s*$`: the whole block one image or link, whose
bracketed "sentence" is a caption.

    let isLoneLinkOrImage(block: String): Boolean {
      var i = String.begin;
      if (block.hasIndex(i) && block[i] == 33) { i = block.next(i); }
      if (!block.hasIndex(i) || block[i] != 91) { return false; }
      i = block.next(i);
      while (block.hasIndex(i) && block[i] != 93) { i = block.next(i); }
      if (!block.hasIndex(i)) { return false; }
      i = block.next(i);
      if (!block.hasIndex(i) || block[i] != 40) { return false; }
      i = block.next(i);
      while (block.hasIndex(i) && block[i] != 41) { i = block.next(i); }
      if (!block.hasIndex(i)) { return false; }
      i = block.next(i);
      while (block.hasIndex(i) && isRegexSpace(block[i])) { i = block.next(i); }
      !block.hasIndex(i)
    }

`^(-{3,}|\*{3,}|_{3,})\s*$`: a thematic break.

    let isRule(s: String): Boolean {
      if (!s.hasIndex(String.begin)) { return false; }
      let mark = s[String.begin];
      if (mark != 45 && mark != 42 && mark != 95) { return false; }
      var i = String.begin;
      var count = 0;
      while (s.hasIndex(i) && s[i] == mark) {
        count += 1;
        i = s.next(i);
      }
      while (s.hasIndex(i) && isRegexSpace(s[i])) { i = s.next(i); }
      count >= 3 && !s.hasIndex(i)
    }
