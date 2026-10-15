# Markdown, blocks

Lines in, block HTML out. Each construct is a function that looks at the lines
from `i` on and answers a `Step`: the block it made (null for a block that is
dropped, like raw HTML) and how many lines it used. Containers (quotes, list
items, footnotes) cut their inner lines out and call `parseBlocks` again.

## Line classifiers

An opening code fence, or null. `ch` is the fence character, `n` its length.

    class FenceOpen(public ch: Int, public n: Int, public info: String, public indent: Int) {}

    let fenceOpen(line: String): FenceOpen? {
      let indent = leadSpaces(line);
      if (indent > 3) { return null; }
      let rest = dropSpaces(line, indent);
      if (!rest.hasIndex(String.begin)) { return null; }
      let c = rest[String.begin];
      if (c != 96 && c != 126) { return null; }
      var i = String.begin;
      var n = 0;
      while (rest.hasIndex(i) && rest[i] == c) { n += 1; i = rest.next(i); }
      if (n < 3) { return null; }
      let info = stripWs(rest.slice(i, rest.end));
      if (c == 96 && contains(info, "`")) { return null; }
      new FenceOpen(c, n, info, indent)
    }

    let isFenceClose(line: String, ch: Int, n: Int): Boolean {
      let indent = leadSpaces(line);
      if (indent > 3) { return false; }
      let rest = dropSpaces(line, indent);
      var i = String.begin;
      var k = 0;
      while (rest.hasIndex(i) && rest[i] == ch) { k += 1; i = rest.next(i); }
      k >= n && isBlankLine(rest.slice(i, rest.end))
    }

    let isHr(line: String): Boolean {
      if (leadSpaces(line) > 3) { return false; }
      var ch = 0;
      var n = 0;
      var i = String.begin;
      while (line.hasIndex(i)) {
        let c = line[i];
        if (c == 32 || c == 9) {
          // spaces between marks are allowed
        } else if (c == 42 || c == 45 || c == 95) {
          if (ch == 0) { ch = c; }
          if (c != ch) { return false; }
          n += 1;
        } else {
          return false;
        }
        i = line.next(i);
      }
      n >= 3
    }

    class Atx(public level: Int, public text: String) {}

    let atxHeading(line: String): Atx? {
      let indent = leadSpaces(line);
      if (indent > 3) { return null; }
      let rest = dropSpaces(line, indent);
      var i = String.begin;
      var n = 0;
      while (rest.hasIndex(i) && rest[i] == 35) { n += 1; i = rest.next(i); }
      if (n < 1 || n > 6) { return null; }
      if (rest.hasIndex(i) && !isSpaceCp(rest[i])) { return null; }
      var text = stripWs(rest.slice(i, rest.end));
      var e = text.end;
      while (e > String.begin && text[text.prev(e)] == 35) { e = text.prev(e); }
      if (e < text.end) {
        if (e == String.begin) {
          text = "";
        } else if (isSpaceCp(text[text.prev(e)])) {
          text = stripTrail(text.slice(String.begin, e));
        }
      }
      new Atx(n, text)
    }

    let isQuoteLine(line: String): Boolean {
      let indent = leadSpaces(line);
      indent <= 3 && cpAt(dropSpaces(line, indent), String.begin) == 62
    }

    class Marker(public bullet: Int, public delim: Int, public num: Int, public width: Int,
                 public indent: Int, public empty: Boolean) {}

A list marker: a bullet, or up to nine digits and `.` or `)`, followed by space,
tab or the end of the line. `width` is where the item's content starts.

    let parseMarker(line: String): Marker? {
      let indent = leadSpaces(line);
      if (indent > 3) { return null; }
      let rest = dropSpaces(line, indent);
      if (!rest.hasIndex(String.begin)) { return null; }
      var i = String.begin;
      let c = rest[i];
      var bullet = 0;
      var delim = 0;
      var num = 0;
      if (c == 42 || c == 43 || c == 45) {
        bullet = c;
        i = rest.next(i);
      } else if (c >= 48 && c <= 57) {
        var digits = 0;
        while (rest.hasIndex(i) && rest[i] >= 48 && rest[i] <= 57 && digits < 10) {
          num = num * 10 + (rest[i] - 48);
          digits += 1;
          i = rest.next(i);
        }
        if (digits > 9 || !rest.hasIndex(i) || (rest[i] != 46 && rest[i] != 41)) { return null; }
        delim = rest[i];
        i = rest.next(i);
      } else {
        return null;
      }
      let markLen = if (bullet != 0) { 1 } else { rest.countBetween(String.begin, i) };
      if (rest.hasIndex(i) && rest[i] != 32 && rest[i] != 9) { return null; }
      let after = rest.slice(i, rest.end);
      if (isBlankLine(after)) {
        return new Marker(bullet, delim, num, indent + markLen + 1, indent, true);
      }
      let sp = leadSpaces(after);
      let width = if (sp >= 5 || sp == 0) { indent + markLen + 1 } else { indent + markLen + sp };
      new Marker(bullet, delim, num, width, indent, false)
    }

    let sameList(a: Marker, b: Marker): Boolean {
      if (a.bullet != 0) { a.bullet == b.bullet } else { b.bullet == 0 && a.delim == b.delim }
    }

## HTML blocks

An HTML block is dropped whole, but it leaves an empty line behind where it stood
(comrak writes a comment there and ammonia deletes the comment). The start types are CommonMark's: 1 script, pre,
style, textarea; 2 comment; 3 processing instruction; 4 declaration; 5 CDATA;
6 a block-level tag name; 7 any complete tag alone on its line.

    let blockTags = " address article aside base basefont blockquote body caption center col colgroup dd details dialog dir div dl dt fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hr html iframe legend li link main menu menuitem nav noframes ol optgroup option p param section source summary table tbody td tfoot th thead title tr track ul ";

    let termAt(s: String, i: StringIndex): Boolean {
      !s.hasIndex(i) || s[i] == 32 || s[i] == 9 || s[i] == 62
    }

    let htmlStartType(line: String, canInterrupt: Boolean): Int {
      let indent = leadSpaces(line);
      if (indent > 3) { return 0; }
      let t = dropSpaces(line, indent);
      if (cpAt(t, String.begin) != 60) { return 0; }
      let lp = lowerAscii(takeChars(t, 12));
      let body = lowerAscii(takeChars(t, 24));
      let tags1 = ["<script", "<pre", "<style", "<textarea"];
      for (var k = 0; k < tags1.length; ++k) {
        let hit = startsAt(body, String.begin, tags1[k]);
        if (hit != null) { if (termAt(body, hit)) { return 1; } }
      }
      if (startsAt(lp, String.begin, "<!--") != null) { return 2; }
      if (startsAt(lp, String.begin, "<?") != null) { return 3; }
      if (startsAt(lp, String.begin, "<![cdata[") != null) { return 5; }
      if (startsAt(lp, String.begin, "<!") != null && isLetterCp(cpAt(lp, lp.next(lp.next(String.begin))))) { return 4; }
      var i = t.next(String.begin);
      if (cpAt(t, i) == 47) { i = t.next(i); }
      let nameStart = i;
      while (t.hasIndex(i) && (isAlnumCp(t[i]))) { i = t.next(i); }
      if (i > nameStart) {
        let name = lowerAscii(t.slice(nameStart, i));
        if (contains(blockTags, " ${name} ")) {
          let c = cpAt(t, i);
          if (c < 0 || c == 32 || c == 9 || c == 62) { return 6; }
          if (c == 47 && cpAt(t, t.next(i)) == 62) { return 6; }
        }
      }
      if (!canInterrupt) {
        let te = htmlTagEnd(t, String.begin);
        if (te != null) {
          if (isBlankLine(t.slice(te, t.end))) { return 7; }
        }
      }
      0
    }

    let htmlEndsHere(line: String, kind: Int): Boolean {
      let l = lowerAscii(line);
      if (kind == 1) {
        contains(l, "</script>") || contains(l, "</pre>") || contains(l, "</style>") || contains(l, "</textarea>")
      } else if (kind == 2) {
        contains(l, "-->")
      } else if (kind == 3) {
        contains(l, "?>")
      } else if (kind == 4) {
        contains(l, ">")
      } else {
        contains(l, "]]>")
      }
    }

    let tryHtml(lines: List<String>, i: Int): Step? {
      let kind = htmlStartType(lines[i], false);
      if (kind == 0) { return null; }
      let n = lines.length;
      var j = i;
      if (kind >= 6) {
        while (j < n && !isBlankLine(lines[j])) { j += 1; }
        return new Step(new Blk("", null), j - i);
      }
      var done = false;
      while (!done && j < n) {
        if (htmlEndsHere(lines[j], kind)) { done = true; }
        j += 1;
      }
      new Step(new Blk("", null), j - i)
    }

## Lazy continuation

A line that is not marked as part of a quote or list item still continues the
paragraph that item or quote ends in, unless it starts a block of its own. In
that case the container is not a paragraph, so every block start counts: any
list marker, an HTML block of type 7, a footnote definition. A continuation line
is tagged with a private-use mark so that the recursive parse cannot take it
for a setext underline or a table row; the paragraph strips the tag again.

    let lazyMark = cpStr(0xE0FF);

    let startsBlock(line: String): Boolean {
      if (leadSpaces(line) > 3) { return false; }
      fenceOpen(line) != null || atxHeading(line) != null || isHr(line) || isQuoteLine(line) ||
        parseMarker(line) != null || htmlStartType(line, false) != 0 || parseNoteDef(line) != null
    }

Whether a line, once its quote and list markers are taken off, is paragraph text.

    let plainTextLine(line: String): Boolean {
      var t = stripLead(line);
      var going = true;
      while (going) {
        if (cpAt(t, String.begin) == 62) {
          t = stripLead(dropChars(t, 1));
        } else {
          let m = parseMarker(t);
          if (m != null) {
            if (isHr(t)) { going = false; } else { t = stripLead(dropChars(t, m.width)); }
          } else {
            going = false;
          }
        }
      }
      !isBlankLine(t) && atxHeading(t) == null && !isHr(t) && fenceOpen(t) == null &&
        htmlStartType(t, false) == 0 && setextLevel(t) == 0
    }

    let insideFence(lines: ListBuilder<String>): Boolean {
      var open = false;
      var ch = 0;
      var n = 0;
      for (var k = 0; k < lines.length; ++k) {
        let line = lines[k];
        if (open) {
          if (isFenceClose(line, ch, n)) { open = false; }
        } else {
          let f = fenceOpen(line);
          if (f != null) { open = true; ch = f.ch; n = f.n; }
        }
      }
      open
    }

    let lazyOk(inner: ListBuilder<String>, line: String): Boolean {
      inner.length > 0 && !isBlankLine(line) && !startsBlock(line) && plainTextLine(inner[inner.length - 1]) &&
        !insideFence(inner)
    }

## Does a line start something that ends a paragraph?

A bullet item or an ordered item numbered 1 can interrupt a paragraph if it has
content; an HTML block can unless it is the type-7 kind.

    let interruptsParagraph(line: String): Boolean {
      if (leadSpaces(line) > 3) { return false; }
      if (fenceOpen(line) != null) { return true; }
      if (atxHeading(line) != null) { return true; }
      if (isHr(line)) { return true; }
      if (isQuoteLine(line)) { return true; }
      let m = parseMarker(line);
      if (m != null) {
        if (!m.empty && (m.bullet != 0 || m.num == 1)) { return true; }
      }
      htmlStartType(line, true) != 0
    }

    let setextLevel(line: String): Int {
      let indent = leadSpaces(line);
      if (indent > 3) { return 0; }
      let t = stripTrail(dropSpaces(line, indent));
      if (t.isEmpty) { return 0; }
      let c = t[String.begin];
      if (c != 61 && c != 45) { return 0; }
      var i = String.begin;
      while (t.hasIndex(i)) {
        if (t[i] != c) { return 0; }
        i = t.next(i);
      }
      if (c == 61) { 1 } else { 2 }
    }

## Tables

    let splitRow(line: String): List<String> {
      var t = stripWs(line);
      if (cpAt(t, String.begin) == 124) { t = dropChars(t, 1); }
      let pieces = t.split("|");
      let out = new ListBuilder<String>();
      var carry: String? = null;
      for (var k = 0; k < pieces.length; ++k) {
        let p = pieces[k];
        let c = carry;
        let whole = if (c == null) { p } else { "${c}|${p}" };
        if (whole.hasIndex(String.begin) && whole[whole.prev(whole.end)] == 92 && k < pieces.length - 1) {
          carry = whole.slice(String.begin, whole.prev(whole.end));
        } else {
          carry = null;
          out.add(stripWs(whole));
        }
      }
      let cells = out.toList();
      if (cells.length > 0 && cells[cells.length - 1].isEmpty && t.hasIndex(String.begin) &&
          t[t.prev(t.end)] == 124) {
        return cells.slice(0, cells.length - 1);
      }
      cells
    }

The alignment of each column ("" none, "left", "center", "right") if `line` is a
delimiter row, else null.

    let delimRow(line: String): List<String>? {
      if (!contains(line, "|") && !contains(line, "-")) { return null; }
      if (leadSpaces(line) > 3) { return null; }
      let cells = splitRow(line);
      if (cells.length == 0) { return null; }
      let out = new ListBuilder<String>();
      for (var k = 0; k < cells.length; ++k) {
        let c = cells[k];
        if (c.isEmpty) { return null; }
        let left = c[String.begin] == 58;
        let right = c[c.prev(c.end)] == 58;
        var core = c;
        if (left) { core = dropChars(core, 1); }
        if (right && core.hasIndex(String.begin)) { core = core.slice(String.begin, core.prev(core.end)); }
        if (core.isEmpty) { return null; }
        var i = String.begin;
        while (core.hasIndex(i)) {
          if (core[i] != 45) { return null; }
          i = core.next(i);
        }
        out.add(if (left && right) { "center" } else if (left) { "left" } else if (right) { "right" } else { "" });
      }
      out.toList()
    }

    let tableStartAt(lines: List<String>, j: Int): Boolean {
      if (j + 1 >= lines.length) { return false; }
      if (!contains(lines[j], "|") || !contains(lines[j + 1], "|")) { return false; }
      let d = delimRow(lines[j + 1]);
      if (d != null) { splitRow(lines[j]).length == d.length } else { false }
    }

    let alignAttr(a: String): String { if (a.isEmpty) { "" } else { " align=\"${a}\"" } }

    let tableRow(ctx: MdCtx, cells: List<String>, aligns: List<String>, tag: String): String {
      let out = new ListBuilder<String>();
      out.add("<tr>");
      for (var k = 0; k < aligns.length; ++k) {
        let text = if (k < cells.length) { cells[k] } else { "" };
        out.add("<${tag}${alignAttr(aligns[k])}>${inlineHtml(ctx, text)}</${tag}>");
      }
      out.add("</tr>");
      joinStr(out.toList(), "\n")
    }

    let tryTable(ctx: MdCtx, lines: List<String>, i: Int): Step? {
      if (!tableStartAt(lines, i)) { return null; }
      let aligns = delimRow(lines[i + 1]);
      if (aligns != null) { tableFrom(ctx, lines, i, aligns) } else { null }
    }

    let tableFrom(ctx: MdCtx, lines: List<String>, i: Int, aligns: List<String>): Step {
      let out = new ListBuilder<String>();
      out.add("<table>\n<thead>\n${tableRow(ctx, splitRow(lines[i]), aligns, "th")}\n</thead>");
      var j = i + 2;
      let rows = new ListBuilder<String>();
      while (j < lines.length && !isBlankLine(lines[j]) && !interruptsParagraph(lines[j])) {
        rows.add(tableRow(ctx, splitRow(lines[j]), aligns, "td"));
        j += 1;
      }
      if (rows.length > 0) {
        out.add("<tbody>\n${joinStr(rows.toList(), "\n")}\n</tbody>");
      }
      out.add("</table>");
      new Step(new Blk(joinStr(out.toList(), "\n"), null), j - i)
    }

## Code

    let tryIndented(lines: List<String>, i: Int): Step? {
      let n = lines.length;
      let body = new ListBuilder<String>();
      var j = i;
      var lastCode = i;
      while (j < n && (isBlankLine(lines[j]) || leadSpaces(lines[j]) >= 4)) {
        body.add(dropSpaces(lines[j], 4));
        if (!isBlankLine(lines[j])) { lastCode = j; }
        j += 1;
      }
      let kept = body.toList().slice(0, lastCode - i + 1);
      let text = "${joinStr(kept, "\n")}\n";
      new Step(new Blk("<pre><code>${mdEsc(text)}</code></pre>", null), lastCode - i + 1)
    }

    let tryFence(lines: List<String>, i: Int): Step? {
      let f = fenceOpen(lines[i]);
      if (f != null) { fenceFrom(lines, i, f) } else { null }
    }

    let fenceFrom(lines: List<String>, i: Int, f: FenceOpen): Step {
      let n = lines.length;
      let body = new ListBuilder<String>();
      var j = i + 1;
      var closed = false;
      while (!closed && j < n) {
        if (isFenceClose(lines[j], f.ch, f.n)) {
          closed = true;
        } else {
          body.add(dropSpaces(lines[j], f.indent));
        }
        j += 1;
      }
      var text = joinStr(body.toList(), "\n");
      if (closed && body.length > 0) { text = "${text}\n"; }
      var cls = "";
      if (!f.info.isEmpty) {
        let word = decodeEntities(unescapeBackslash(f.info.split(" ")[0].split("\t")[0]));
        cls = " class=\"language-${attrEsc(word)}\"";
      }
      new Step(new Blk("<pre><code${cls}>${mdEsc(text)}</code></pre>", null), j - i)
    }

## Quotes, headings, paragraphs

    let tryAtx(ctx: MdCtx, line: String): Step? {
      let a = atxHeading(line);
      if (a != null) {
        new Step(new Blk("<h${a.level}>${inlineHtml(ctx, a.text)}</h${a.level}>", null), 1)
      } else {
        null
      }
    }

    let tryQuote(ctx: MdCtx, lines: List<String>, i: Int): Step? {
      if (!isQuoteLine(lines[i])) { return null; }
      let n = lines.length;
      let inner = new ListBuilder<String>();
      var j = i;
      var going = true;
      while (going && j < n) {
        let ln = lines[j];
        if (isQuoteLine(ln)) {
          var t = dropSpaces(ln, leadSpaces(ln));
          t = dropChars(t, 1);
          if (cpAt(t, String.begin) == 32) { t = dropChars(t, 1); }
          inner.add(t);
          j += 1;
        } else if (lazyOk(inner, ln)) {
          inner.add("${lazyMark}${stripLead(ln)}");
          j += 1;
        } else {
          going = false;
        }
      }
      let parsed = parseBlocks(ctx, inner.toList());
      let htmls = parsed.blocks.map { (b): String => b.html };
      let body = if (htmls.isEmpty) { "<blockquote>\n</blockquote>" } else {
        "<blockquote>\n${joinStr(htmls, "\n")}\n</blockquote>"
      };
      new Step(new Blk(body, null), j - i)
    }

    let tryParagraph(ctx: MdCtx, lines: List<String>, i: Int): Step {
      let n = lines.length;
      var j = i + 1;
      var level = 0;
      var going = true;
      while (going && j < n) {
        let ln = lines[j];
        if (isBlankLine(ln)) {
          going = false;
        } else if (setextLevel(ln) != 0) {
          level = setextLevel(ln);
          going = false;
        } else if (interruptsParagraph(ln) || tableStartAt(lines, j)) {
          going = false;
        } else {
          j += 1;
        }
      }
      let text = stripTrail(replaceAll(joinStr(lines.slice(i, j).map { (l): String => stripLead(l) }, "\n"), lazyMark, ""));
      let html = inlineHtml(ctx, text);
      if (level != 0) {
        return new Step(new Blk("<h${level}>${html}</h${level}>", null), j - i + 1);
      }
      new Step(new Blk("<p>${html}</p>", html), j - i)
    }

## Lists

    let startsTask(first: String): Boolean {
      let hit = startsAt(first, String.begin, "[");
      if (hit != null) {
        let mid = cpAt(first, hit);
        let close = first.next(hit);
        let after = first.next(close);
        (mid == 32 || mid == 120 || mid == 88) && cpAt(first, close) == 93 &&
          (!first.hasIndex(after) || first[after] == 32 || first[after] == 9)
      } else {
        false
      }
    }

    let tryList(ctx: MdCtx, lines: List<String>, i: Int): Step? {
      let first = parseMarker(lines[i]);
      if (first != null) { listFrom(ctx, lines, i, first) } else { null }
    }

    let listFrom(ctx: MdCtx, lines: List<String>, i: Int, first: Marker): Step {
      let n = lines.length;
      let items = new ListBuilder<Parsed>();
      let tasks = new ListBuilder<Boolean>();
      var m: Marker = first;
      var j = i;
      var loose = false;
      var endLine = i;
      var more = true;
      while (more) {
        var head = if (m.empty) { "" } else { dropChars(lines[j], m.width) };
        var task = false;
        if (startsTask(head)) {
          task = true;
          head = dropChars(head, 3);
        }
        let itemLines = new ListBuilder<String>();
        itemLines.add(head);
        var k = j + 1;
        var blanks = 0;
        var go = true;
        while (go && k < n) {
          let ln = lines[k];
          if (isBlankLine(ln)) {
            blanks += 1;
            k += 1;
          } else if (leadSpaces(ln) >= m.width) {
            while (blanks > 0) { itemLines.add(""); blanks -= 1; }
            itemLines.add(dropSpaces(ln, m.width));
            k += 1;
          } else if (blanks == 0 && lazyOk(itemLines, ln)) {
            itemLines.add("${lazyMark}${stripLead(ln)}");
            k += 1;
          } else {
            go = false;
          }
        }
        let parsed = parseBlocks(ctx, itemLines.toList());
        items.add(parsed);
        tasks.add(task);
        if (parsed.spaced) { loose = true; }
        endLine = k - blanks;
        more = false;
        if (k < n) {
          let nm = parseMarker(lines[k]);
          if (nm != null) {
            if (sameList(m, nm) && !isHr(lines[k])) {
              if (blanks > 0) { loose = true; }
              m = nm;
              j = k;
              more = true;
            }
          }
        }
      }
      let tag = if (first.bullet != 0) { "ul" } else { "ol" };
      let startAttr = if (first.bullet == 0 && first.num != 1) { " start=\"${first.num}\"" } else { "" };
      let lis = new ListBuilder<String>();
      let all = items.toList();
      let taskFlags = tasks.toList();
      for (var q = 0; q < all.length; ++q) {
        let blocks = all[q].blocks;
        let pre = if (taskFlags[q]) { " " } else { "" };
        if (blocks.isEmpty) {
          lis.add("<li>${pre}</li>");
        } else if (loose) {
          lis.add("<li>${pre}\n${joinStr(blocks.map { (b): String => b.html }, "\n")}\n</li>");
        } else {
          let parts = new ListBuilder<String>();
          parts.add("<li>");
          parts.add(pre);
          var lastPara = false;
          for (var b = 0; b < blocks.length; ++b) {
            let inl = blocks[b].inline;
            if (inl != null) {
              parts.add(inl);
              lastPara = true;
            } else {
              parts.add("\n${blocks[b].html}");
              lastPara = false;
            }
          }
          if (!lastPara) { parts.add("\n"); }
          parts.add("</li>");
          lis.add(joinStr(parts.toList(), ""));
        }
      }
      new Step(new Blk("<${tag}${startAttr}>\n${joinStr(lis.toList(), "\n")}\n</${tag}>", null), endLine - i)
    }

## Blocks

    let parseBlocks(ctx: MdCtx, lines: List<String>): Parsed {
      let out = new ListBuilder<Blk>();
      let n = lines.length;
      var spaced = false;
      var sawBlank = false;
      var count = 0;
      var i = 0;
      while (i < n) {
        let line = lines[i];
        if (isBlankLine(line)) {
          sawBlank = true;
          i += 1;
        } else {
          if (sawBlank && count > 0) { spaced = true; }
          sawBlank = false;
          var step: Step? = null;
          if (leadSpaces(line) >= 4) { step = tryIndented(lines, i); }
          if (step == null) { step = tryFence(lines, i); }
          if (step == null) { step = tryAtx(ctx, line); }
          if (step == null && isHr(line)) { step = new Step(new Blk("<hr>", null), 1); }
          if (step == null) { step = tryQuote(ctx, lines, i); }
          if (step == null) { step = tryList(ctx, lines, i); }
          if (step == null) { step = tryHtml(lines, i); }
          if (step == null) { step = tryTable(ctx, lines, i); }
          let st = step;
          let done = if (st == null) { tryParagraph(ctx, lines, i) } else { st };
          let b = done.blk;
          if (b != null) { out.add(b); }
          count += 1;
          i += done.used;
        }
      }
      new Parsed(out.toList(), spaced)
    }
