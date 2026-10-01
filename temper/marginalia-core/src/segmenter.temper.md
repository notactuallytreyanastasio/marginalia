# Segmenter

Splits a manuscript into analysable sections, deterministically, with no
model involved. Three strategies, in order of how much they can be trusted:
markdown headings, marker lines (`Chapter 7`, `PART TWO`, `VII.`,
`* * *`), and paragraph windows of about 1,800 words. Whichever wins, a
section past 4,000 words is windowed again, keeping its title: a heading is
a boundary, not a promise of brevity. This is `Marginalia.Works.Segmenter`.

    @connected export let graphemePrefix(s: String, n: Int): String;

    @imu export class Section(public title: String, public body: String) {}

    let targetWords = 1800;
    let minWords = 250;
    let maxWords = 4000;

    export let segment(raw: String): List<Section> {
      let text = normalize(raw);
      if (text.isEmpty) { return []; }
      let chunks = byMarkdown(text) ?? byMarker(text) ?? byWindows(text);
      // one sentence per line inside every prose paragraph, after the split:
      // reflowing first would fold "Chapter 2" into its first paragraph
      chunks.map { (c): Section => new Section(c.title, reflow(c.body)) }
    }

Line endings normalised, runs of blank lines collapsed, trimmed.

    let normalize(raw: String): String {
      let unixed = joinWith(joinWith(raw.split("\r\n"), "\n").split("\r"), "\n");
      let out = new StringBuilder();
      var newlines = 0;
      var i = String.begin;
      while (unixed.hasIndex(i)) {
        let cp = unixed[i];
        if (cp == 10) {
          newlines += 1;
        } else {
          // ~r/\n{3,}/ becomes "\n\n"
          if (newlines >= 3) { out.append("\n\n"); } else {
            for (var k = 0; k < newlines; ++k) { out.append("\n"); }
          }
          newlines = 0;
          out.appendCodePoint(cp) orelse panic();
        }
        i = unixed.next(i);
      }
      if (newlines >= 3) { out.append("\n\n"); } else {
        for (var k = 0; k < newlines; ++k) { out.append("\n"); }
      }
      trim(out.toString())
    }

## Markdown headings

At least two lines matching `^\#{1,3}\s+\S`; the title is the line with
`^#+\s*` removed, trimmed.

    let isMarkdownHead(line: String): Boolean {
      var i = String.begin;
      var hashes = 0;
      while (line.hasIndex(i) && line[i] == 35) {
        hashes += 1;
        i = line.next(i);
      }
      if (hashes < 1 || hashes > 3 || !line.hasIndex(i) || !isRegexSpace(line[i])) { return false; }
      while (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
      line.hasIndex(i)
    }

    let markdownTitle(line: String): String {
      var i = String.begin;
      while (line.hasIndex(i) && line[i] == 35) { i = line.next(i); }
      while (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
      trim(line.slice(i, line.end))
    }

    let byMarkdown(text: String): List<Section>? {
      let lines = text.split("\n");
      if (lines.filter { (l): Boolean => isMarkdownHead(l) }.length < 2) { return null; }
      finish(chunkOn(lines, true))
    }

## Marker lines

At least two lines, each under 90 graphemes trimmed, matching

```text
^\s*(?:(?:chapter|part|book|act|section)\s+(?:[0-9]+|[ivxlc]+|[a-z]+)
     |[ivxlc]{1,7}\.|\*\s*\*\s*\*|—{3,}|-{3,})\s*[:.\-—]?\s*(.{0,80})$
```

case-insensitively and without the `u` flag. Without it, PCRE reads the
pattern and the line as bytes, and that decides two things here:

- `—{3,}` repeats only the last byte of the em dash, a sequence valid UTF-8
  never contains, so that alternative never matches: `———` is not a
  marker, while `---` is.
- `[:.\-—]` is a set of bytes, so it matches the first byte of any
  character in U+2000 to U+2FFF, and `.{0,80}` is 80 bytes, not
  characters.

The parse below takes each part as far as it goes, which is the best case
for the 80-byte tail; the alternatives cannot do better by backtracking.

    let isMarker(line: String): Boolean {
      if (graphemeLength(trim(line)) >= 90) { return false; }
      var i = String.begin;
      while (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
      let head = markerHead(line, i);
      if (head == null) { return false; }
      i = head as StringIndex orelse panic();
      while (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
      var spare = 0;
      if (line.hasIndex(i)) {
        let cp = line[i];
        if (cp == 58 || cp == 46 || cp == 45) {
          i = line.next(i);
          while (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
        } else if (cp >= 0x2000 && cp <= 0x2FFF) {
          // the set matched this character's first byte, 0xE2
          spare = 1;
        }
      }
      utf8Length(line, i) - spare <= 80
    }

    let utf8Length(s: String, from: StringIndex): Int {
      var n = 0;
      var i = from;
      while (s.hasIndex(i)) {
        let cp = s[i];
        n += if (cp < 0x80) { 1 } else if (cp < 0x800) { 2 } else if (cp < 0x10000) { 3 } else { 4 };
        i = s.next(i);
      }
      n
    }

Where the head alternatives end, or null.

    let markerHead(line: String, at: StringIndex): StringIndex? {
      let keywords = ["chapter", "part", "book", "act", "section"];
      for (var k = 0; k < keywords.length; ++k) {
        let after = asciiCaselessPrefix(line, at, keywords[k]);
        if (after != null) {
          var i = after;
          var spaces = 0;
          while (line.hasIndex(i) && isRegexSpace(line[i])) {
            spaces += 1;
            i = line.next(i);
          }
          if (spaces >= 1 && line.hasIndex(i)) {
            let cp = line[i];
            if (cp >= 48 && cp <= 57) {
              while (line.hasIndex(i) && line[i] >= 48 && line[i] <= 57) { i = line.next(i); }
              return i;
            }
            if (isAsciiLetter(cp)) {
              while (line.hasIndex(i) && isAsciiLetter(line[i])) { i = line.next(i); }
              return i;
            }
          }
        }
      }
      // [ivxlc]{1,7}\.
      var r = at;
      var romans = 0;
      while (line.hasIndex(r) && isRomanLetter(line[r])) {
        romans += 1;
        r = line.next(r);
      }
      if (romans >= 1 && romans <= 7 && line.hasIndex(r) && line[r] == 46) { return line.next(r); }
      // \*\s*\*\s*\*
      if (line.hasIndex(at) && line[at] == 42) {
        var s = line.next(at);
        var stars = 1;
        while (stars < 3) {
          while (line.hasIndex(s) && isRegexSpace(line[s])) { s = line.next(s); }
          if (!line.hasIndex(s) || line[s] != 42) { break; }
          stars += 1;
          s = line.next(s);
        }
        if (stars == 3) { return s; }
      }
      // -{3,}
      var d = at;
      var dashes = 0;
      while (line.hasIndex(d) && line[d] == 45) {
        dashes += 1;
        d = line.next(d);
      }
      if (dashes >= 3) { return d; }
      null
    }

    let isAsciiLetter(cp: Int): Boolean { (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) }

    let isRomanLetter(cp: Int): Boolean {
      cp == 73 || cp == 86 || cp == 88 || cp == 76 || cp == 67 ||
        cp == 105 || cp == 118 || cp == 120 || cp == 108 || cp == 99
    }

    /** Where `word` ends if `line` has it at `at`, ASCII case ignored; else null. */
    let asciiCaselessPrefix(line: String, at: StringIndex, word: String): StringIndex? {
      var i = at;
      var j = String.begin;
      while (word.hasIndex(j)) {
        if (!line.hasIndex(i)) { return null; }
        var cp = line[i];
        if (cp >= 65 && cp <= 90) { cp = cp + 32; }
        if (cp != word[j]) { return null; }
        i = line.next(i);
        j = word.next(j);
      }
      i
    }

    let byMarker(text: String): List<Section>? {
      let lines = text.split("\n");
      if (lines.filter { (l): Boolean => isMarker(l) }.length < 2) { return null; }
      finish(chunkOn(lines, false))
    }

## Chunking on heads

Prose before the first head is its own section, "Opening".

    class HeadChunk(public title: String, public lines: ListBuilder<String>) {}

    let chunkOn(lines: List<String>, markdown: Boolean): List<Section> {
      let chunks = new ListBuilder<HeadChunk>();
      for (var k = 0; k < lines.length; ++k) {
        let line = lines[k];
        let isHead = if (markdown) { isMarkdownHead(line) } else { isMarker(line) };
        if (isHead) {
          let title = if (markdown) { markdownTitle(line) } else { trim(line) };
          chunks.add(new HeadChunk(title, new ListBuilder<String>()));
        } else if (chunks.isEmpty) {
          let first = new ListBuilder<String>();
          first.add(line);
          chunks.add(new HeadChunk("Opening", first));
        } else {
          chunks[chunks.length - 1].lines.add(line);
        }
      }
      chunks.toList().map { (c): Section =>
        new Section(untitledIfBlank(c.title), trim(joinWith(c.lines.toList(), "\n")))
      }
    }

    let untitledIfBlank(title: String): String {
      if (title.isEmpty) { "Untitled" } else { graphemePrefix(title, 120) }
    }

## Paragraph windows

Paragraphs packed into windows of about 1,800 words, never split: one
longer than that is its own window, too big, but cutting a sentence in half
would break every quote anchored into it.

    let byWindows(text: String): List<Section> {
      let bodies = window(text);
      let out = new ListBuilder<Section>();
      for (var k = 0; k < bodies.length; ++k) {
        let body = reflow(bodies[k]);
        out.add(new Section(deriveTitle(body, k + 1), body));
      }
      finish(out.toList()) ?? []
    }

`String.split(~r/\n\s*\n/, trim: true)`, each piece trimmed: a paragraph
ends at a run of ASCII space holding two newlines.

    let paragraphPieces(text: String): List<String> {
      let out = new ListBuilder<String>();
      var start = String.begin;
      var i = String.begin;
      while (text.hasIndex(i)) {
        if (isRegexSpace(text[i])) {
          let runStart = i;
          var newlines = 0;
          var lastNewline = i;
          while (text.hasIndex(i) && isRegexSpace(text[i])) {
            if (text[i] == 10) {
              newlines += 1;
              lastNewline = i;
            }
            i = text.next(i);
          }
          if (newlines >= 2) {
            // the match runs from the run's first newline to its last
            var firstNewline = runStart;
            while (text[firstNewline] != 10) { firstNewline = text.next(firstNewline); }
            let piece = text.slice(start, firstNewline);
            if (!piece.isEmpty) { out.add(piece); }
            start = text.next(lastNewline);
          }
        } else {
          i = text.next(i);
        }
      }
      let last = text.slice(start, text.end);
      if (!last.isEmpty) { out.add(last); }
      out.toList()
    }

    class Window(public paras: ListBuilder<String>, public words: Int) {}

    let window(text: String): List<String> {
      let pieces = paragraphPieces(text);
      let windows = new ListBuilder<Window>();
      for (var k = 0; k < pieces.length; ++k) {
        let para = trim(pieces[k]);
        let words = wordCount(para);
        let n = windows.length;
        if (n > 0 && windows[n - 1].words < targetWords) {
          let head = windows[n - 1];
          head.paras.add(para);
          windows[n - 1] = new Window(head.paras, head.words + words);
        } else {
          let paras = new ListBuilder<String>();
          paras.add(para);
          windows.add(new Window(paras, words));
        }
      }
      windows.toList().map { (w): String => joinWith(w.paras.toList(), "\n\n") }
    }

`length(String.split(s, ~r/\s+/, trim: true))`: runs of non-space.

    let wordCount(s: String): Int {
      var n = 0;
      var inWord = false;
      var i = String.begin;
      while (s.hasIndex(i)) {
        if (isRegexSpace(s[i])) {
          inWord = false;
        } else {
          if (!inWord) { n += 1; }
          inWord = true;
        }
        i = s.next(i);
      }
      n
    }

The window's first line, as a label, with markdown stripped: titles go in
a contents list, a minimap and a breadcrumb, none of which render it.

    let deriveTitle(body: String, i: Int): String {
      var first = body.split("\n")[0];
      // ^\#{1,6}\s+
      var h = String.begin;
      var hashes = 0;
      while (first.hasIndex(h) && first[h] == 35 && hashes < 7) {
        hashes += 1;
        h = first.next(h);
      }
      if (hashes >= 1 && hashes <= 6 && first.hasIndex(h) && isRegexSpace(first[h])) {
        while (first.hasIndex(h) && isRegexSpace(first[h])) { h = first.next(h); }
        first = first.slice(h, first.end);
      }
      // ~r/[*_`]+/ removed
      let plain = new StringBuilder();
      var k = String.begin;
      while (first.hasIndex(k)) {
        let cp = first[k];
        if (cp != 42 && cp != 95 && cp != 96) { plain.appendCodePoint(cp) orelse panic(); }
        k = first.next(k);
      }
      let label = graphemePrefix(trim(plain.toString()), 60);
      if (graphemeLength(label) > 12) { "${i.toString()}. ${label}…" } else { "Section ${i.toString()}" }
    }

## Finishing

Empty sections dropped; a runt (under 250 words) folded into the section
before it when that one is under 1,800; then any section over 4,000 words
windowed, keeping its title. Nothing left is null, so the next strategy is
tried.

    let finish(chunks: List<Section>): List<Section>? {
      let kept = new ListBuilder<Section>();
      for (var k = 0; k < chunks.length; ++k) {
        let chunk = chunks[k];
        if (trim(chunk.body).isEmpty) { continue; }
        let n = kept.length;
        if (n > 0 && wordCount(chunk.body) < minWords && wordCount(kept[n - 1].body) < targetWords) {
          let prev = kept[n - 1];
          kept[n - 1] = new Section(prev.title, "${prev.body}\n\n${chunk.body}");
        } else {
          kept.add(chunk);
        }
      }
      let out = new ListBuilder<Section>();
      let all = kept.toList();
      for (var k = 0; k < all.length; ++k) { out.addAll(subdivide(all[k])); }
      if (out.isEmpty) { null } else { out.toList() }
    }

    let subdivide(chunk: Section): List<Section> {
      if (wordCount(chunk.body) <= maxWords) { return [chunk]; }
      let parts = window(chunk.body);
      let n = parts.length;
      if (n < 2) { return [chunk]; }
      let out = new ListBuilder<Section>();
      for (var k = 0; k < n; ++k) {
        out.add(new Section("${chunk.title} (${(k + 1).toString()}/${n.toString()})", parts[k]));
      }
      out.toList()
    }
