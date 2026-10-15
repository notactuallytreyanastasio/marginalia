# Markdown: definitions, footnotes, exports

The pieces are in `markdown_text.temper.md` (strings, escaping, URLs, tokens),
`markdown_inline.temper.md` (the inline scanner) and `markdown_blocks.temper.md`
(line classification and containers). This file ties them together.

## Deviations

Everything the notes show, and everything in the 875 random documents but 16, is
byte for byte what MDEx printed. Where this differs, or does less:

* Footnote definitions: a footnote that is defined twice, one whose body is the
  only place it is referenced, and the odd list structure comrak builds when
  several definitions run into list markers are not reproduced. A definition body
  is its first line, any following 4-space-indented lines, and lazy plain-text
  lines.
* Link reference definitions are found on top-level lines only (not inside quotes
  or list items), single-line, and a definition that sits between two list items
  does not split the list the way comrak does.
* A tab after a list marker is one space (`-\ttext` is fine; `-  \t- tab` does not
  open a nested list). Leading tabs elsewhere count as four columns and are kept
  inside fenced code.
* Unicode punctuation for emphasis flanking is an approximation (ASCII, Latin-1,
  General Punctuation and CJK punctuation); named entities decode from a table of
  thirty-odd names, anything else stays as text.
* Autolinks: `http://`, `https://`, `ftp://`, `www.` and bare addresses, with
  GFM's trailing-punctuation rules, but no check that a `www.` host is a plausible
  domain.
* Table cells are split on `|` unless escaped; a `|` inside a code span still
  splits, as in GFM.
* The mark U+E0FF is used internally to tag lazy-continuation lines; a document
  containing it literally can lose it. (U+E000..U+E005 are the app's and pass
  through.)
* A document is parsed by function recursion; deeply nested quotes or lists
  (hundreds of levels) can reach the interpreter's call depth limit. A paragraph
  with thousands of delimiter tokens, or a document of thousands of top-level
  blocks, is quadratic (the builders copy on every add).
* Anything not listed in the notes and not covered above follows CommonMark as
  comrak implements it; the fuzz run is the evidence.

## Reference and footnote definitions

Link reference definitions (`[label]: url "title"`) and footnote definitions
(`[^label]: text`) have to be known before the first use, so a pre-pass takes
them out of the document's top-level lines (fences skipped) and files them in the
context. Only a document that contains `]:` pays for it.

    class DefParse(public label: String, public url: String, public title: String?) {}

    let findFrom(s: String, needle: String, from: StringIndex): StringIndex? {
      let hit = s.indexOf(needle, from);
      if (hit is StringIndex) { hit } else { null }
    }

    let parseLinkDef(line: String): DefParse? {
      let t = dropSpaces(line, leadSpaces(line));
      if (cpAt(t, String.begin) != 91) { return null; }
      let close = findFrom(t, "]", t.next(String.begin));
      if (close != null) { linkDefAfter(t, close) } else { null }
    }

    let linkDefAfter(t: String, close: StringIndex): DefParse? {
      let label = t.slice(t.next(String.begin), close);
      if (isBlankLine(label) || cpAt(label, String.begin) == 94 || contains(label, "[")) { return null; }
      let colon = t.next(close);
      if (cpAt(t, colon) != 58) { return null; }
      var i = skipSpaces(t, t.next(colon));
      if (!t.hasIndex(i)) { return null; }
      var url = "";
      if (t[i] == 60) {
        let gt = findFrom(t, ">", t.next(i));
        if (gt != null) {
          url = decodeEntities(unescapeBackslash(t.slice(t.next(i), gt)));
          i = t.next(gt);
        } else {
          return null;
        }
      } else {
        let start = i;
        while (t.hasIndex(i) && !isSpaceCp(t[i])) { i = t.next(i); }
        url = decodeEntities(unescapeBackslash(t.slice(start, i)));
      }
      let k = skipSpaces(t, i);
      if (!t.hasIndex(k)) { return new DefParse(label, url, null); }
      if (k == i) { return null; }
      let q = t[k];
      if (q != 34 && q != 39 && q != 40) { return null; }
      let closer = if (q == 40) { 41 } else { q };
      let rest = stripTrail(t.slice(t.next(k), t.end));
      if (!rest.hasIndex(String.begin) || rest[rest.prev(rest.end)] != closer) { return null; }
      new DefParse(label, url, unescapeBackslash(rest.slice(String.begin, rest.prev(rest.end))))
    }

    class NoteStart(public label: String, public first: String) {}

    let parseNoteDef(line: String): NoteStart? {
      let t = dropSpaces(line, leadSpaces(line));
      if (startsAt(t, String.begin, "[^") == null) { return null; }
      let from = t.next(t.next(String.begin));
      let close = findFrom(t, "]:", from);
      if (close != null) { noteDefAfter(t, from, close) } else { null }
    }

    let noteDefAfter(t: String, from: StringIndex, close: StringIndex): NoteStart? {
      let label = t.slice(from, close);
      if (label.isEmpty || contains(label, " ") || contains(label, "]")) { return null; }
      new NoteStart(label, stripWs(t.slice(t.next(t.next(close)), t.end)))
    }

    let collectDefs(ctx: MdCtx, lines: List<String>): List<String> {
      let out = new ListBuilder<String>();
      let n = lines.length;
      var i = 0;
      var inPara = false;
      var inFence = false;
      var fch = 0;
      var fn = 0;
      while (i < n) {
        let line = lines[i];
        if (inFence) {
          out.add(line);
          if (isFenceClose(line, fch, fn)) { inFence = false; }
          i += 1;
          inPara = false;
        } else {
          let f = fenceOpen(line);
          if (f != null) {
            inFence = true;
            fch = f.ch;
            fn = f.n;
            out.add(line);
            i += 1;
            inPara = false;
          } else {
            var taken = false;
            if (leadSpaces(line) <= 3) {
              let note = parseNoteDef(line);
              if (note != null) {
                let body = new ListBuilder<String>();
                body.add(note.first);
                var j = i + 1;
                var go = true;
                while (go && j < n) {
                  if (isBlankLine(lines[j])) {
                    var look = j;
                    while (look < n && isBlankLine(lines[look])) { look += 1; }
                    if (look < n && leadSpaces(lines[look]) >= 4) {
                      while (j < look) {
                        body.add("");
                        j += 1;
                      }
                    } else {
                      go = false;
                    }
                  } else if (leadSpaces(lines[j]) >= 4) {
                    body.add(dropSpaces(lines[j], 4));
                    j += 1;
                  } else if (!startsBlock(lines[j])) {
                    body.add(stripLead(lines[j]));
                    j += 1;
                  } else {
                    go = false;
                  }
                }
                if (!ctx.notes.has(note.label)) { ctx.notes.set(note.label, body.toList()); }
                i = j;
                taken = true;
              } else if (!inPara) {
                let d = parseLinkDef(line);
                if (d != null) {
                  let key = normLabel(d.label);
                  if (!ctx.defs.has(key)) { ctx.defs.set(key, new LinkDef(d.url, d.title)); }
                  i += 1;
                  taken = true;
                }
              }
            }
            if (taken) {
              inPara = false;
            } else {
              out.add(line);
              if (isBlankLine(line)) {
                inPara = false;
              } else if (inPara && setextLevel(line) != 0) {
                inPara = false;
              } else {
                inPara = plainTextLine(line) || (inPara && leadSpaces(line) >= 4);
              }
              i += 1;
            }
          }
        }
      }
      out.toList()
    }

Footnotes appear after the document in the order they were first referenced,
the last paragraph of each carrying its back-references.

    let footnoteSection(ctx: MdCtx): String {
      let items = new ListBuilder<String>();
      var idx = 0;
      while (idx < ctx.order.length) {
        let id = ctx.order[idx];
        let parsed = parseBlocks(ctx, ctx.notes.getOr(id, []));
        let htmls = new ListBuilder<String>();
        for (var b = 0; b < parsed.blocks.length; ++b) { htmls.add(parsed.blocks[b].html); }
        let times = ctx.refs.getOr(id, 1);
        let back = new ListBuilder<String>();
        back.add(" <a href=\"#fnref-${attrEsc(id)}\" rel=\"noopener noreferrer\">↩</a>");
        for (var r = 2; r <= times; ++r) {
          back.add(" <a href=\"#fnref-${attrEsc(id)}-${r}\" rel=\"noopener noreferrer\">↩<sup>${r}</sup></a>");
        }
        let backs = joinStr(back.toList(), "");
        let all = htmls.toList();
        if (all.isEmpty) {
          htmls.add("<p>${backs}</p>");
        } else {
          let last = all[all.length - 1];
          let parts = last.split("</p>");
          if (parts.length > 1 && parts[parts.length - 1].isEmpty) {
            htmls.removeLast();
            htmls.add("${joinStr(parts.slice(0, parts.length - 1), "</p>")}${backs}</p>");
          } else {
            htmls.add("<p>${backs}</p>");
          }
        }
        items.add("<li>\n${joinStr(htmls.toList(), "\n")}\n</li>");
        idx += 1;
      }
      if (items.length == 0) { "" } else { "\n\n<ol>\n${joinStr(items.toList(), "\n")}\n</ol>" }
    }

## The exports

`markdownToHtml` breaks lines hard, as `Markdown.to_html/1` did by default (chat
replies). `markdownToHtmlSoft` is the `breaks: :soft` of `Reading.render_block`:
a newline inside a paragraph stays a newline.

Leading tabs become spaces everywhere but inside a fenced code block, where
they are content.

    let expandOutsideFences(lines: List<String>): List<String> {
      if (!contains(joinStr(lines, "\n"), "\t")) { return lines; }
      let out = new ListBuilder<String>();
      var open = false;
      var ch = 0;
      var n = 0;
      for (var k = 0; k < lines.length; ++k) {
        let line = lines[k];
        if (open) {
          out.add(line);
          if (isFenceClose(line, ch, n)) { open = false; }
        } else {
          let f = fenceOpen(line);
          if (f != null) {
            open = true;
            ch = f.ch;
            n = f.n;
            out.add(line);
          } else {
            out.add(expandTabs(line));
          }
        }
      }
      out.toList()
    }

    let trimNewlines(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && s[b] == 10) { b = s.next(b); }
      var e = s.end;
      while (e > b && s[s.prev(e)] == 10) { e = s.prev(e); }
      s.slice(b, e)
    }

    let renderMarkdown(md: String, hard: Boolean): String {
      if (md.isEmpty) { return ""; }
      let ctx = new MdCtx(hard);
      let raw = expandOutsideFences(replaceAll(md, "\r\n", "\n").split("\n"));
      let lines = if (contains(md, "]:")) { collectDefs(ctx, raw) } else { raw };
      let parsed = parseBlocks(ctx, lines);
      let body = trimNewlines(joinStr(parsed.blocks.map { (b): String => b.html }, "\n"));
      "${body}${footnoteSection(ctx)}"
    }

    export let markdownToHtml(md: String): String { renderMarkdown(md, true) }

    export let markdownToHtmlSoft(md: String): String { renderMarkdown(md, false) }

A newline becomes `<br>` and the newline. For text that is already escaped.

    export let nl2br(s: String): String { replaceAll(replaceAll(s, "\r\n", "\n"), "\n", "<br>\n") }

## Paragraphs

`Marginalia.Reading.split/1`: blocks are what blank lines separate, except that
a fenced code block is one block however many blank lines it holds. This is the
same logic as `core`'s `blocks`, kept here rather than imported: the `core`
library is named `marginalia-core` for now and its helpers are private to it.

    let isTrimSpace(cp: Int): Boolean {
      isSpaceCp(cp) || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    let trimUni(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && isTrimSpace(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && isTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

    let trimUniTrailing(s: String): String {
      var e = s.end;
      while (e > String.begin && isTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(String.begin, e)
    }

    let trimUniLeading(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && isTrimSpace(s[b])) { b = s.next(b); }
      s.slice(b, s.end)
    }

    let flushBlock(current: ListBuilder<String>, out: ListBuilder<String>): Void {
      if (!current.isEmpty) {
        out.add(joinStr(current.toList(), "\n"));
        current.clear();
      }
    }

The fence a line opens: three or more backticks or tildes after optional space,
the whole run.

    let fenceRun(line: String): String? {
      var i = String.begin;
      while (line.hasIndex(i) && isSpaceCp(line[i])) { i = line.next(i); }
      if (!line.hasIndex(i)) { return null; }
      let mark = line[i];
      if (mark != 96 && mark != 126) { return null; }
      let start = i;
      var count = 0;
      while (line.hasIndex(i) && line[i] == mark) {
        count += 1;
        i = line.next(i);
      }
      if (count >= 3) { line.slice(start, i) } else { null }
    }

    export let markdownParagraphs(md: String): List<String> {
      let out = new ListBuilder<String>();
      let current = new ListBuilder<String>();
      var fence: String? = null;
      let lines = md.split("\n");
      for (var k = 0; k < lines.length; ++k) {
        let line = lines[k];
        let open = fence;
        if (open != null) {
          current.add(line);
          if (startsAt(trimUniLeading(line), String.begin, open) != null) {
            flushBlock(current, out);
            fence = null;
          }
        } else {
          let opener = fenceRun(line);
          if (opener != null) {
            flushBlock(current, out);
            current.add(line);
            fence = opener;
          } else if (trimUni(line).isEmpty) {
            flushBlock(current, out);
          } else {
            current.add(line);
          }
        }
      }
      flushBlock(current, out);
      let kept = new ListBuilder<String>();
      let all = out.toList();
      for (var k = 0; k < all.length; ++k) {
        let block = trimUniTrailing(all[k]);
        if (!trimUni(block).isEmpty) { kept.add(block); }
      }
      kept.toList()
    }
