# Markdown

What `Marginalia.Markdown.to_html/2` produced: MDEx 0.13.5 (comrak with the
strikethrough, table, autolink, tasklist and footnote extensions, smart
punctuation off, `unsafe: false`) piped through ammonia's default allowlist.
Every output shape below was checked against the real MDEx by running it
(`notes/domain-works.md` section 3 lists a few; the rest came from the same
oracle, one input at a time), not from reading comrak.

The shape of the program: split the document on newlines, classify lines into
blocks (containers recurse on their inner lines), then run an inline pass over
each paragraph's text. No pass walks the whole document one character at a time.

What the sanitiser changes, and so what this file reproduces:

* Raw HTML in the source never reaches the output. Inline tags and comments
  vanish and the text between them stays (`<b>b</b>` gives `b`); an HTML block
  vanishes whole, content included (`<div>\nx\n</div>` gives nothing).
* Text escapes `&`, `<`, `>` and U+00A0 (as `&nbsp;`) and nothing else: the
  quotes are left alone, because ammonia re-serialises them that way.
* Every link carries `rel="noopener noreferrer"`. A `javascript:`, `vbscript:`,
  `file:` or `data:` target gives `href=""`; any other scheme outside ammonia's
  list drops the attribute; images likewise with `src`.
* Task-list checkboxes are stripped and leave one space: `<li> a</li>`.

## State

    class LinkDef(public url: String, public title: String?) {}

    class MdCtx(public hard: Boolean) {
      public defs: MapBuilder<String, LinkDef> = new MapBuilder<String, LinkDef>();
      public notes: MapBuilder<String, List<String>> = new MapBuilder<String, List<String>>();
      public order: ListBuilder<String> = new ListBuilder<String>();
      public refs: MapBuilder<String, Int> = new MapBuilder<String, Int>();
    }

    class Blk(public html: String, public inline: String?) {}

    class Parsed(public blocks: List<Blk>, public spaced: Boolean) {}

    class Step(public blk: Blk?, public used: Int) {}

## Small string tools

Temper strings have no length, trim, lower-case or replace. These are the few
this file needs. Indices walk code points.

    let joinStr(parts: List<String>, sep: String): String {
      parts.join(sep) { (p): String => p }
    }

    let contains(s: String, part: String): Boolean { s.split(part).length > 1 }

    let repeatStr(s: String, n: Int): String {
      let parts = new ListBuilder<String>();
      for (var k = 0; k < n; ++k) { parts.add(s); }
      joinStr(parts.toList(), "")
    }

    let isSpaceCp(cp: Int): Boolean { cp == 32 || (cp >= 9 && cp <= 13) }

    let isUniWs(cp: Int): Boolean {
      isSpaceCp(cp) || cp == 0xA0 || cp == 0x1680 || (cp >= 0x2000 && cp <= 0x200A) ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    let isAsciiPunct(cp: Int): Boolean {
      (cp >= 33 && cp <= 47) || (cp >= 58 && cp <= 64) || (cp >= 91 && cp <= 96) || (cp >= 123 && cp <= 126)
    }

An approximation of Unicode punctuation: ASCII, Latin-1 punctuation, general
punctuation and CJK punctuation. Letters, digits, symbols and the private-use
sentinels count as neither space nor punctuation.

    let isPunctCp(cp: Int): Boolean {
      isAsciiPunct(cp) || cp == 0xA1 || cp == 0xA7 || cp == 0xAB || cp == 0xB6 || cp == 0xB7 ||
        cp == 0xBB || cp == 0xBF || (cp >= 0x2010 && cp <= 0x2027) || (cp >= 0x2030 && cp <= 0x205E) ||
        (cp >= 0x3001 && cp <= 0x3003)
    }

    let isAlnumCp(cp: Int): Boolean {
      (cp >= 48 && cp <= 57) || (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122)
    }

    let isLetterCp(cp: Int): Boolean { (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) }

    let lowerAscii(s: String): String {
      var upper = false;
      var i = String.begin;
      while (s.hasIndex(i)) {
        let c = s[i];
        if (c >= 65 && c <= 90) { upper = true; }
        i = s.next(i);
      }
      if (!upper) { return s; }
      let parts = new ListBuilder<String>();
      i = String.begin;
      while (s.hasIndex(i)) {
        let c = s[i];
        parts.add(cpStr(if (c >= 65 && c <= 90) { c + 32 } else { c }));
        i = s.next(i);
      }
      joinStr(parts.toList(), "")
    }

    let leadSpaces(s: String): Int {
      var n = 0;
      var i = String.begin;
      while (s.hasIndex(i) && s[i] == 32) { n += 1; i = s.next(i); }
      n
    }

    let dropSpaces(s: String, n: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < n && s.hasIndex(i) && s[i] == 32) { k += 1; i = s.next(i); }
      s.slice(i, s.end)
    }

    let dropChars(s: String, n: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < n && s.hasIndex(i)) { k += 1; i = s.next(i); }
      s.slice(i, s.end)
    }

    let takeChars(s: String, n: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < n && s.hasIndex(i)) { k += 1; i = s.next(i); }
      s.slice(String.begin, i)
    }

    let stripLead(s: String): String {
      var i = String.begin;
      while (s.hasIndex(i) && isSpaceCp(s[i])) { i = s.next(i); }
      s.slice(i, s.end)
    }

    let stripTrail(s: String): String {
      var e = s.end;
      while (e > String.begin && isSpaceCp(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(String.begin, e)
    }

    let stripWs(s: String): String { stripTrail(stripLead(s)) }

    let isBlankLine(s: String): Boolean {
      var i = String.begin;
      while (s.hasIndex(i)) {
        if (!isSpaceCp(s[i])) { return false; }
        i = s.next(i);
      }
      true
    }

    let skipSpaces(s: String, from: StringIndex): StringIndex {
      var i = from;
      while (s.hasIndex(i) && (s[i] == 32 || s[i] == 9)) { i = s.next(i); }
      i
    }

    let skipWs(s: String, from: StringIndex): StringIndex {
      var i = from;
      while (s.hasIndex(i) && isSpaceCp(s[i])) { i = s.next(i); }
      i
    }

    let cpAt(s: String, i: StringIndex): Int { if (s.hasIndex(i)) { s[i] } else { -1 } }

The index after `lit` if `s` has it at `at`, else null.

    let startsAt(s: String, at: StringIndex, lit: String): StringIndex? {
      var i = at;
      var j = String.begin;
      while (lit.hasIndex(j)) {
        if (!s.hasIndex(i) || s[i] != lit[j]) { return null; }
        i = s.next(i);
        j = lit.next(j);
      }
      i
    }

    let cpStr(cp: Int): String { String.fromCodePoint(cp) orelse "" }

A line's leading tabs become spaces (tab stops of four), so that indentation is
only ever counted in spaces.

    let expandTabs(line: String): String {
      if (!contains(line, "\t")) { return line; }
      var col = 0;
      var i = String.begin;
      while (line.hasIndex(i) && (line[i] == 32 || line[i] == 9)) {
        if (line[i] == 9) { col = (col / 4 + 1) * 4; } else { col += 1; }
        i = line.next(i);
      }
      "${repeatStr(" ", col)}${line.slice(i, line.end)}"
    }

## Escaping

    let nbsp = cpStr(160);

    let mdEsc(s: String): String {
      replaceAll(replaceAll(replaceAll(replaceAll(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), nbsp, "&nbsp;")
    }

    let attrEsc(s: String): String {
      replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(s, "&", "&amp;"), "\"", "&quot;"), "<", "&lt;"), ">", "&gt;"), nbsp, "&nbsp;")
    }

    let unescapeBackslash(s: String): String {
      if (!contains(s, "\\")) { return s; }
      let parts = new ListBuilder<String>();
      var i = String.begin;
      while (s.hasIndex(i)) {
        let c = s[i];
        let nx = s.next(i);
        if (c == 92 && s.hasIndex(nx) && isAsciiPunct(s[nx])) {
          parts.add(cpStr(s[nx]));
          i = s.next(nx);
        } else {
          parts.add(cpStr(c));
          i = nx;
        }
      }
      joinStr(parts.toList(), "")
    }

    let hexDigit(d: Int): String { cpStr(if (d < 10) { 48 + d } else { 55 + d }) }

    let pct(b: Int): String { "%${hexDigit(b / 16)}${hexDigit(b % 16)}" }

comrak's href escaping: percent-encode everything but a safe set, as UTF-8; `&`
is entity-escaped; `%` stays so an escape already there is not doubled.

    let hrefSafe(c: Int): Boolean {
      isAlnumCp(c) || c == 45 || c == 95 || c == 46 || c == 43 || c == 33 || c == 42 || c == 39 ||
        c == 40 || c == 41 || c == 44 || c == 37 || c == 35 || c == 64 || c == 63 || c == 61 ||
        c == 59 || c == 58 || c == 47 || c == 36 || c == 126
    }

    let hrefEncode(url: String): String {
      let parts = new ListBuilder<String>();
      var i = String.begin;
      while (url.hasIndex(i)) {
        let c = url[i];
        if (c == 38) { parts.add("&amp;"); } else if (hrefSafe(c)) { parts.add(cpStr(c)); } else if (c < 128) { parts.add(pct(c)); } else if (c < 2048) { parts.add(pct(192 + c / 64)); parts.add(pct(128 + c % 64)); } else if (c < 65536) {
          parts.add(pct(224 + c / 4096)); parts.add(pct(128 + (c / 64) % 64)); parts.add(pct(128 + c % 64));
        } else {
          parts.add(pct(240 + c / 262144)); parts.add(pct(128 + (c / 4096) % 64));
          parts.add(pct(128 + (c / 64) % 64)); parts.add(pct(128 + c % 64));
        }
        i = url.next(i);
      }
      joinStr(parts.toList(), "")
    }

What ammonia does with a URL's scheme: 0 keep, 1 an empty attribute (comrak's
own refusal of `javascript:` and friends), 2 drop the attribute.

    let urlKind(url: String): Int {
      var i = String.begin;
      if (!url.hasIndex(i) || !isLetterCp(url[i])) { return 0; }
      while (url.hasIndex(i) && (isAlnumCp(url[i]) || url[i] == 43 || url[i] == 45 || url[i] == 46)) {
        i = url.next(i);
      }
      if (!url.hasIndex(i) || url[i] != 58) { return 0; }
      let scheme = lowerAscii(url.slice(String.begin, i));
      if (scheme == "javascript" || scheme == "vbscript" || scheme == "file") { return 1; }
      if (scheme == "data") {
        let rest = lowerAscii(takeChars(url, 16));
        if (contains(rest, "data:image/")) { return 2; }
        return 1;
      }
      let allowed = " http https mailto ftp ftps tel bitcoin geo im irc ircs magnet mms news nntp openpgp4fpr sip sms smsto ssh url webcal wtai xmpp ";
      if (contains(allowed, " ${scheme} ")) { 0 } else { 2 }
    }

    let linkOpen(url: String, title: String?): String {
      let k = urlKind(url);
      let href = if (k == 0) { " href=\"${hrefEncode(url)}\"" } else if (k == 1) { " href=\"\"" } else { "" };
      let t = if (title == null) { "" } else { " title=\"${attrEsc(title)}\"" };
      "<a${href}${t} rel=\"noopener noreferrer\">"
    }

    let imgTag(url: String, title: String?, alt: String): String {
      let k = urlKind(url);
      let src = if (k == 0) { " src=\"${hrefEncode(url)}\"" } else if (k == 1) { " src=\"\"" } else { "" };
      let t = if (title == null) { "" } else { " title=\"${attrEsc(title)}\"" };
      "<img${src} alt=\"${attrEsc(alt)}\"${t}>"
    }

## Entities

Named references decode to a code point; unknown names stay as written (and so
come out as `&amp;name;`). A packed table is searched instead of a constant map.

    let entityTable = ";amp=38;lt=60;gt=62;quot=34;apos=39;nbsp=160;copy=169;reg=174;trade=8482;hellip=8230;mdash=8212;ndash=8211;lsquo=8216;rsquo=8217;ldquo=8220;rdquo=8221;bull=8226;middot=183;laquo=171;raquo=187;times=215;divide=247;deg=176;plusmn=177;euro=8364;pound=163;yen=165;cent=162;sect=167;para=182;larr=8592;rarr=8594;uarr=8593;darr=8595;hearts=9829;check=10003;";

    let entityCode(name: String): Int {
      let hit = entityTable.split(";${name}=");
      if (hit.length < 2) { return -1; }
      let tail = hit[1].split(";")[0];
      tail.toInt32() orelse -1
    }

    class Ent(public cp: Int, public end: StringIndex) {}

    let digitVal(c: Int): Int {
      if (c >= 48 && c <= 57) { c - 48 } else if (c >= 97 && c <= 102) { c - 87 } else if (c >= 65 && c <= 70) { c - 55 } else { -1 }
    }

`s[at]` is `&`. A numeric reference of up to seven digits (six hex) or a known
name, closed by `;`.

    let parseEntity(s: String, at: StringIndex): Ent? {
      var i = s.next(at);
      if (!s.hasIndex(i)) { return null; }
      if (s[i] == 35) {
        i = s.next(i);
        var hex = false;
        if (s.hasIndex(i) && (s[i] == 120 || s[i] == 88)) { hex = true; i = s.next(i); }
        var v = 0;
        var n = 0;
        while (s.hasIndex(i) && digitVal(s[i]) >= 0 && (hex || digitVal(s[i]) < 10) && n < 8) {
          v = v * (if (hex) { 16 } else { 10 }) + digitVal(s[i]);
          n += 1;
          i = s.next(i);
        }
        if (n == 0 || !s.hasIndex(i) || s[i] != 59) { return null; }
        var cp = v;
        if (cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) { cp = 0xFFFD; }
        return new Ent(cp, s.next(i));
      }
      let start = i;
      var n = 0;
      while (s.hasIndex(i) && isAlnumCp(s[i]) && n < 32) { n += 1; i = s.next(i); }
      if (n == 0 || !s.hasIndex(i) || s[i] != 59) { return null; }
      let code = entityCode(s.slice(start, i));
      if (code < 0) { return null; }
      new Ent(code, s.next(i))
    }

Entities inside a link destination or title decode too.

    let decodeEntities(s: String): String {
      if (!contains(s, "&")) { return s; }
      let parts = new ListBuilder<String>();
      var i = String.begin;
      while (s.hasIndex(i)) {
        let c = s[i];
        if (c == 38) {
          let e = parseEntity(s, i);
          if (e != null) {
            parts.add(cpStr(e.cp));
            i = e.end;
          } else {
            parts.add("&");
            i = s.next(i);
          }
        } else {
          parts.add(cpStr(c));
          i = s.next(i);
        }
      }
      joinStr(parts.toList(), "")
    }

## Inline tokens

Inline text becomes a list of tokens; delimiter runs (`*`, `_`, `~`) and
brackets are resolved afterwards by CommonMark's delimiter algorithm. A token is
a mutable object, so resolving a pair edits the opener and closer in place and
nothing is copied.

kind: 0 finished html, 1 delimiter run, 2 open bracket, 3 bracket that turned
out literal, 4 bracket that became a link or image.

    class Tok(public var kind: Int, public var html: String, public var plain: String) {
      public var ch: Int = 0;
      public var count: Int = 0;
      public var orig: Int = 0;
      public var canOpen: Boolean = false;
      public var canClose: Boolean = false;
      public var active: Boolean = true;
      public var image: Boolean = false;
      public var pos: StringIndex = String.begin;
      public var openTags: String = "";
      public var closeTags: String = "";
    }

    let textTok(html: String, plain: String): Tok { new Tok(0, html, plain) }

    let renderTok(t: Tok): String {
      if (t.kind == 1) { "${t.closeTags}${repeatStr(cpStr(t.ch), t.count)}${t.openTags}" } else if (t.kind == 2 || t.kind == 3) { if (t.image) { "![" } else { "[" } } else { t.html }
    }

    let plainTok(t: Tok): String {
      if (t.kind == 1) { repeatStr(cpStr(t.ch), t.count) } else if (t.kind == 2 || t.kind == 3) { if (t.image) { "![" } else { "[" } } else { t.plain }
    }

    let addText(toks: ListBuilder<Tok>, s: String, a: StringIndex, b: StringIndex): Void {
      if (a < b) {
        let raw = s.slice(a, b);
        toks.add(textTok(mdEsc(raw), raw));
      }
    }

Whether a rule of three forbids pairing these runs.

    let ruleOk(op: Tok, cl: Tok): Boolean {
      if (op.ch == 126) { return op.count == cl.count; }
      !((op.canClose || cl.canOpen) && (op.orig + cl.orig) % 3 == 0 && !(op.orig % 3 == 0 && cl.orig % 3 == 0))
    }

The delimiter algorithm over the tokens from `from` on. Tags go on the opener
(outermost first) and the closer (innermost first); what a run has left over
prints as literal characters between them and its neighbours.

    let processEmphasis(toks: ListBuilder<Tok>, from: Int): Void {
      let all = toks.toList();
      let n = all.length;
      var ci = from;
      while (ci < n) {
        let cl = all[ci];
        if (cl.kind == 1 && cl.canClose && cl.count > 0) {
          var again = true;
          while (again && cl.count > 0) {
            var found = -1;
            var oj = ci - 1;
            while (oj >= from && found < 0) {
              let op = all[oj];
              if (op.kind == 1 && op.ch == cl.ch && op.canOpen && op.count > 0 && ruleOk(op, cl)) { found = oj; }
              oj -= 1;
            }
            if (found < 0) {
              again = false;
            } else {
              let op = all[found];
              let use = if (cl.ch == 126) { cl.count } else if (op.count >= 2 && cl.count >= 2) { 2 } else { 1 };
              let tag = if (cl.ch == 126) { "del" } else if (use == 2) { "strong" } else { "em" };
              op.openTags = "<${tag}>${op.openTags}";
              cl.closeTags = "${cl.closeTags}</${tag}>";
              op.count = op.count - use;
              cl.count = cl.count - use;
              var k = found + 1;
              while (k < ci) {
                let mid = all[k];
                if (mid.kind == 1) { mid.canOpen = false; mid.canClose = false; }
                k += 1;
              }
            }
          }
        }
        ci += 1;
      }
    }
