# Markdown, inline pass

One paragraph's text in, HTML out. The scanner walks code points once, keeping
the start of the plain text not yet emitted, so plain runs are sliced out whole
and escaped with native split and join.

## Raw HTML tags

Raw HTML is dropped from the output and the text between tags stays, so all that
is needed is where a tag ends. `s[at]` is `<`. The index just past the tag, or null.

    let isNameStart(c: Int): Boolean { isLetterCp(c) }

    let isNameChar(c: Int): Boolean { isAlnumCp(c) || c == 45 }

    let htmlTagEnd(s: String, at: StringIndex): StringIndex? {
      var i = s.next(at);
      if (!s.hasIndex(i)) { return null; }
      let c = s[i];
      if (c == 33) {
        let comment = startsAt(s, i, "!--");
        if (comment != null) {
          let hit = s.indexOf("-->", comment);
          if (hit is StringIndex) { return s.next(s.next(s.next(hit))); }
          return null;
        }
        let cdata = startsAt(s, i, "![CDATA[");
        if (cdata != null) {
          let hit = s.indexOf("]]>", cdata);
          if (hit is StringIndex) { return s.next(s.next(s.next(hit))); }
          return null;
        }
        let nx = s.next(i);
        if (s.hasIndex(nx) && isLetterCp(s[nx])) {
          let hit = s.indexOf(">", nx);
          if (hit is StringIndex) { return s.next(hit); }
        }
        return null;
      }
      if (c == 63) {
        let hit = s.indexOf("?>", s.next(i));
        if (hit is StringIndex) { return s.next(s.next(hit)); }
        return null;
      }
      var closing = false;
      if (c == 47) { closing = true; i = s.next(i); }
      if (!s.hasIndex(i) || !isNameStart(s[i])) { return null; }
      while (s.hasIndex(i) && isNameChar(s[i])) { i = s.next(i); }
      if (closing) {
        i = skipWs(s, i);
        if (s.hasIndex(i) && s[i] == 62) { return s.next(i); }
        return null;
      }
      while (true) {
        let before = i;
        i = skipWs(s, i);
        if (!s.hasIndex(i)) { return null; }
        let d = s[i];
        if (d == 62) { return s.next(i); }
        if (d == 47) {
          let nx = s.next(i);
          if (s.hasIndex(nx) && s[nx] == 62) { return s.next(nx); }
          return null;
        }
        if (i == before) { return null; }
        if (!(isLetterCp(d) || d == 95 || d == 58)) { return null; }
        while (s.hasIndex(i) && (isAlnumCp(s[i]) || s[i] == 95 || s[i] == 58 || s[i] == 46 || s[i] == 45)) {
          i = s.next(i);
        }
        let afterName = i;
        let j = skipWs(s, i);
        if (s.hasIndex(j) && s[j] == 61) {
          i = skipWs(s, s.next(j));
          if (!s.hasIndex(i)) { return null; }
          let q = s[i];
          if (q == 34 || q == 39) {
            i = s.next(i);
            while (s.hasIndex(i) && s[i] != q) { i = s.next(i); }
            if (!s.hasIndex(i)) { return null; }
            i = s.next(i);
          } else {
            let start = i;
            while (s.hasIndex(i) && !isSpaceCp(s[i]) && s[i] != 34 && s[i] != 39 && s[i] != 61 &&
                   s[i] != 60 && s[i] != 62 && s[i] != 96) {
              i = s.next(i);
            }
            if (i == start) { return null; }
          }
        } else {
          i = afterName;
        }
      }
      null
    }

## Autolinks

`<scheme:rest>` and `<user@host>`. The index of the closing `>`, or null.

    class AutoRes(public url: String, public text: String, public end: StringIndex) {}

    let angleAutolink(s: String, at: StringIndex): AutoRes? {
      let start = s.next(at);
      var i = start;
      while (s.hasIndex(i) && s[i] != 62) {
        let c = s[i];
        if (isSpaceCp(c) || c == 60) { return null; }
        i = s.next(i);
      }
      if (!s.hasIndex(i) || i == start) { return null; }
      let body = s.slice(start, i);
      let end = s.next(i);
      var j = String.begin;
      if (isLetterCp(cpAt(body, j))) {
        var n = 0;
        while (body.hasIndex(j) && (isAlnumCp(body[j]) || body[j] == 43 || body[j] == 45 || body[j] == 46)) {
          n += 1;
          j = body.next(j);
        }
        if (n >= 2 && n <= 32 && body.hasIndex(j) && body[j] == 58) { return new AutoRes(body, body, end); }
      }
      let parts = body.split("@");
      if (parts.length == 2 && !parts[0].isEmpty && !parts[1].isEmpty && contains(parts[1], ".") == true) {
        return new AutoRes("mailto:${body}", body, end);
      }
      null
    }

Bare URLs, as the GFM autolink extension finds them. After the scheme or `www.`
the URL runs to whitespace or `<`, minus trailing punctuation and an unbalanced
closing parenthesis.

    let trimmedUrlEnd(s: String, from: StringIndex, to: StringIndex): StringIndex {
      var e = to;
      var going = true;
      while (going && e > from) {
        let c = s[s.prev(e)];
        if (c == 63 || c == 33 || c == 46 || c == 44 || c == 58 || c == 42 || c == 95 || c == 126 ||
            c == 39 || c == 34 || c == 59) {
          e = s.prev(e);
        } else if (c == 41) {
          var opens = 0;
          var closes = 0;
          var k = from;
          while (k < e) {
            if (s[k] == 40) { opens += 1; }
            if (s[k] == 41) { closes += 1; }
            k = s.next(k);
          }
          if (closes > opens) { e = s.prev(e); } else { going = false; }
        } else {
          going = false;
        }
      }
      e
    }

    class BareUrl(public text: String, public href: String, public end: StringIndex) {}

    let bareUrl(s: String, at: StringIndex): BareUrl? {
      let https = startsAt(s, at, "https://");
      let http = startsAt(s, at, "http://");
      let ftp = startsAt(s, at, "ftp://");
      let wwwEnd = startsAt(s, at, "www.");
      var bs: StringIndex = at;
      var www = false;
      if (https != null) {
        bs = https;
      } else if (http != null) {
        bs = http;
      } else if (ftp != null) {
        bs = ftp;
      } else if (wwwEnd != null) {
        bs = wwwEnd;
        www = true;
      } else {
        return null;
      }
      if (!s.hasIndex(bs) || !isAlnumCp(s[bs])) { return null; }
      var i = bs;
      while (s.hasIndex(i) && !isSpaceCp(s[i]) && s[i] != 60) { i = s.next(i); }
      let e = trimmedUrlEnd(s, at, i);
      if (e <= bs) { return null; }
      let text = s.slice(at, e);
      new BareUrl(text, if (www) { "http://${text}" } else { text }, e)
    }

    let isEmailLocal(c: Int): Boolean {
      isAlnumCp(c) || c == 46 || c == 33 || c == 35 || c == 36 || c == 37 || c == 38 || c == 39 ||
        c == 42 || c == 43 || c == 47 || c == 61 || c == 63 || c == 94 || c == 95 || c == 96 ||
        c == 123 || c == 124 || c == 125 || c == 126 || c == 45
    }

The host of a bare email address: labels joined by dots, at least one dot, not
ending in `-` or `_`. The index past it, or null.

    let emailHostEnd(s: String, at: StringIndex): StringIndex? {
      var i = at;
      var dots = 0;
      while (s.hasIndex(i) && (isAlnumCp(s[i]) || s[i] == 45 || s[i] == 95 || s[i] == 46)) {
        if (s[i] == 46) { dots += 1; }
        i = s.next(i);
      }
      var e = i;
      var going = true;
      while (going && e > at) {
        let c = s[s.prev(e)];
        if (c == 46 || c == 45 || c == 95) {
          if (c == 46) { dots -= 1; }
          e = s.prev(e);
        } else {
          going = false;
        }
      }
      if (e <= at || dots < 1) { return null; }
      e
    }

## Links

    class LinkDest(public url: String, public title: String?, public end: StringIndex) {}

`(` at `open`: a destination, an optional title, `)`.

    let parseDest(s: String, open: StringIndex): LinkDest? {
      var i = skipWs(s, s.next(open));
      var url = "";
      if (s.hasIndex(i) && s[i] == 60) {
        let start = s.next(i);
        var j = start;
        var found = false;
        while (!found && s.hasIndex(j)) {
          let c = s[j];
          if (c == 62) {
            found = true;
          } else if (c == 10 || c == 60) {
            return null;
          } else if (c == 92 && s.hasIndex(s.next(j)) && isAsciiPunct(s[s.next(j)])) {
            j = s.next(s.next(j));
          } else {
            j = s.next(j);
          }
        }
        if (!found) { return null; }
        url = decodeEntities(unescapeBackslash(s.slice(start, j)));
        i = s.next(j);
      } else {
        let start = i;
        var depth = 0;
        var j = i;
        var going = true;
        while (going && s.hasIndex(j)) {
          let c = s[j];
          if (c == 92 && s.hasIndex(s.next(j)) && isAsciiPunct(s[s.next(j)])) {
            j = s.next(s.next(j));
          } else if (c == 40) {
            depth += 1;
            j = s.next(j);
          } else if (c == 41) {
            if (depth == 0) { going = false; } else { depth -= 1; j = s.next(j); }
          } else if (isSpaceCp(c) || c < 32) {
            going = false;
          } else {
            j = s.next(j);
          }
        }
        if (depth != 0) { return null; }
        url = decodeEntities(unescapeBackslash(s.slice(start, j)));
        i = j;
      }
      var k = skipWs(s, i);
      var title: String? = null;
      if (k > i && s.hasIndex(k) && (s[k] == 34 || s[k] == 39 || s[k] == 40)) {
        let q = s[k];
        let closer = if (q == 40) { 41 } else { q };
        let start = s.next(k);
        var j = start;
        var found = false;
        while (!found && s.hasIndex(j)) {
          let c = s[j];
          if (c == closer) {
            found = true;
          } else if (c == 92 && s.hasIndex(s.next(j))) {
            j = s.next(s.next(j));
          } else {
            j = s.next(j);
          }
        }
        if (!found) { return null; }
        title = decodeEntities(unescapeBackslash(s.slice(start, j)));
        k = skipWs(s, s.next(j));
      }
      if (!s.hasIndex(k) || s[k] != 41) { return null; }
      new LinkDest(url, title, s.next(k))
    }

A reference label is matched case-insensitively with whitespace collapsed.

    let normLabel(label: String): String {
      let flat = replaceAll(replaceAll(replaceAll(label, "\n", " "), "\t", " "), "\r", " ");
      let words = flat.split(" ").filter { (w): Boolean => !w.isEmpty };
      lowerAscii(joinStr(words, " "))
    }

    let lookupDef(ctx: MdCtx, label: String): LinkDef? {
      let key = normLabel(label);
      if (key.isEmpty) { return null; }
      if (ctx.defs.has(key)) { ctx.defs.getOr(key, new LinkDef("", null)) } else { null }
    }

`]` at `at`: close the nearest open bracket if what follows makes a link or
image. Returns the index to resume at, or null when the bracket is literal.

    let closeBracket(ctx: MdCtx, toks: ListBuilder<Tok>, s: String, at: StringIndex): StringIndex? {
      var oi = toks.length - 1;
      while (oi >= 0 && toks[oi].kind != 2) { oi -= 1; }
      if (oi < 0) { return null; }
      let op = toks[oi];
      if (!op.active) {
        op.kind = 3;
        return null;
      }
      let label = s.slice(op.pos, at);
      let after = s.next(at);
      var url = "";
      var title: String? = null;
      var end = after;
      var ok = false;
      if (s.hasIndex(after) && s[after] == 40) {
        let d = parseDest(s, after);
        if (d != null) {
          url = d.url;
          title = d.title;
          end = d.end;
          ok = true;
        }
      }
      if (!ok) {
        var key = label;
        var refEnd = after;
        if (s.hasIndex(after) && s[after] == 91) {
          var j = s.next(after);
          while (s.hasIndex(j) && s[j] != 93 && s[j] != 91) { j = s.next(j); }
          if (s.hasIndex(j) && s[j] == 93) {
            let l2 = s.slice(s.next(after), j);
            if (!l2.isEmpty) { key = l2; }
            refEnd = s.next(j);
          }
        }
        let d1 = lookupDef(ctx, key);
        let d2 = if (d1 == null && refEnd != after) { lookupDef(ctx, label) } else { null };
        if (d1 != null) {
          url = d1.url;
          title = d1.title;
          end = refEnd;
          ok = true;
        } else if (d2 != null) {
          url = d2.url;
          title = d2.title;
          end = after;
          ok = true;
        }
      }
      if (!ok) {
        op.kind = 3;
        return null;
      }
      processEmphasis(toks, oi + 1);
      var k = oi + 1;
      while (k < toks.length) {
        let t = toks[k];
        if (t.kind == 1) { t.canOpen = false; t.canClose = false; }
        k += 1;
      }
      if (op.image) {
        let alts = new ListBuilder<String>();
        k = oi + 1;
        while (k < toks.length) { alts.add(plainTok(toks[k])); k += 1; }
        while (toks.length > oi + 1) { toks.removeLast(); }
        op.html = imgTag(url, title, joinStr(alts.toList(), ""));
        op.kind = 4;
      } else {
        op.html = linkOpen(url, title);
        op.kind = 4;
        toks.add(textTok("</a>", ""));
        k = 0;
        while (k < oi) {
          let t = toks[k];
          if (t.kind == 2 && !t.image) { t.active = false; }
          k += 1;
        }
      }
      end
    }

## The scan

Characters that can start something. A paragraph with none of them is just
escaped text.

    let hasSpecial(s: String): Boolean {
      contains(s, "\\") || contains(s, "`") || contains(s, "*") || contains(s, "_") ||
        contains(s, "[") || contains(s, "<") || contains(s, "&") || contains(s, "~") ||
        contains(s, "\n") || contains(s, "://") || contains(s, "www.") || contains(s, "@")
    }

    let insideLink(toks: ListBuilder<Tok>): Boolean {
      var k = 0;
      while (k < toks.length) {
        let t = toks[k];
        if (t.kind == 2 && !t.image) { return true; }
        k += 1;
      }
      false
    }

    let linkTok(href: String, text: String): Tok {
      textTok("<a href=\"${hrefEncode(href)}\" rel=\"noopener noreferrer\">${mdEsc(text)}</a>", text)
    }

    let boundaryBefore(c: Int): Boolean { c < 0 || isSpaceCp(c) || c == 42 || c == 95 || c == 126 || c == 40 }

    let minHit(s: String, lit: String, from: StringIndex, best: StringIndex): StringIndex {
      let hit = s.indexOf(lit, from);
      if (hit is StringIndex) { if (hit < best) { hit } else { best } } else { best }
    }

Where the next character that could start something is, found with native
`indexOf` scans instead of testing every character in the interpreter (about
thirty times faster on plain prose). Past the end of the text when there is none.

    let specialLits = ["\\", "`", "*", "_", "[", "]", "<", "&", "~", "\n", "!"];

    let nextSpecial(s: String, from: StringIndex, hasUrl: Boolean, hasAt: Boolean): StringIndex {
      var best = s.end;
      for (var k = 0; k < specialLits.length; ++k) { best = minHit(s, specialLits[k], from, best); }
      if (hasUrl) {
        best = minHit(s, "http", from, best);
        best = minHit(s, "ftp://", from, best);
        best = minHit(s, "www.", from, best);
      }
      if (hasAt) { best = minHit(s, "@", from, best); }
      best
    }

    let inlineHtml(ctx: MdCtx, s: String): String {
      if (!hasSpecial(s)) { return mdEsc(s); }
      let toks = new ListBuilder<Tok>();
      var i = String.begin;
      var textStart = String.begin;
      let hasUrl = contains(s, "://") || contains(s, "www.");
      let hasAt = contains(s, "@");
      while (s.hasIndex(i)) {
        let jump = nextSpecial(s, i, hasUrl, hasAt);
        if (jump > i) {
          i = jump;
        } else {
          let c = s[i];
          var adv = s.next(i);
          if (c == 92) {
            let nx = s.next(i);
            if (s.hasIndex(nx)) {
              let d = s[nx];
              if (d == 10) {
                addText(toks, s, textStart, i);
                toks.add(textTok("<br>\n", " "));
                adv = skipSpaces(s, s.next(nx));
                textStart = adv;
              } else if (isAsciiPunct(d)) {
                addText(toks, s, textStart, i);
                toks.add(textTok(mdEsc(cpStr(d)), cpStr(d)));
                adv = s.next(nx);
                textStart = adv;
              }
            }
          } else if (c == 96) {
            var runEnd = i;
            var n = 0;
            while (s.hasIndex(runEnd) && s[runEnd] == 96) { n += 1; runEnd = s.next(runEnd); }
            var k = runEnd;
            var found = false;
            var closeStart = runEnd;
            var closeEnd = runEnd;
            while (!found && s.hasIndex(k)) {
              if (s[k] == 96) {
                var e = k;
                var m = 0;
                while (s.hasIndex(e) && s[e] == 96) { m += 1; e = s.next(e); }
                if (m == n) { found = true; closeStart = k; closeEnd = e; } else { k = e; }
              } else {
                k = s.next(k);
              }
            }
            if (found) {
              addText(toks, s, textStart, i);
              var body = replaceAll(s.slice(runEnd, closeStart), "\n", " ");
              if (body.hasIndex(body.next(String.begin)) && body[String.begin] == 32 &&
                  body[body.prev(body.end)] == 32 && !isBlankLine(body)) {
                body = body.slice(body.next(String.begin), body.prev(body.end));
              }
              toks.add(textTok("<code>${mdEsc(body)}</code>", body));
              adv = closeEnd;
              textStart = adv;
            } else {
              adv = runEnd;
            }
          } else if (c == 60) {
            let auto = angleAutolink(s, i);
            if (auto != null) {
              addText(toks, s, textStart, i);
              toks.add(linkTok(auto.url, auto.text));
              adv = auto.end;
              textStart = adv;
            } else {
              let te = htmlTagEnd(s, i);
              if (te != null) {
                addText(toks, s, textStart, i);
                adv = te;
                textStart = adv;
              }
            }
          } else if (c == 38) {
            let ent = parseEntity(s, i);
            if (ent != null) {
              addText(toks, s, textStart, i);
              toks.add(textTok(mdEsc(cpStr(ent.cp)), cpStr(ent.cp)));
              adv = ent.end;
              textStart = adv;
            }
          } else if (c == 10) {
            var e = i;
            var sp = 0;
            while (e > textStart && s[s.prev(e)] == 32) { e = s.prev(e); sp += 1; }
            addText(toks, s, textStart, e);
            toks.add(textTok(if (sp >= 2 || ctx.hard) { "<br>\n" } else { "\n" }, " "));
            adv = skipSpaces(s, s.next(i));
            textStart = adv;
          } else if (c == 42 || c == 95 || c == 126) {
            var e = i;
            var n = 0;
            while (s.hasIndex(e) && s[e] == c) { n += 1; e = s.next(e); }
            let before = if (i == String.begin) { 10 } else { s[s.prev(i)] };
            let afterCp = if (s.hasIndex(e)) { s[e] } else { 10 };
            let left = !isUniWs(afterCp) && (!isPunctCp(afterCp) || isUniWs(before) || isPunctCp(before));
            let right = !isUniWs(before) && (!isPunctCp(before) || isUniWs(afterCp) || isPunctCp(afterCp));
            var canOpen = left;
            var canClose = right;
            if (c == 95) {
              canOpen = left && (!right || isPunctCp(before));
              canClose = right && (!left || isPunctCp(afterCp));
            }
            if (c == 126 && n > 2) {
              canOpen = false;
              canClose = false;
            }
            if (canOpen || canClose) {
              addText(toks, s, textStart, i);
              let t = new Tok(1, "", "");
              t.ch = c;
              t.count = n;
              t.orig = n;
              t.canOpen = canOpen;
              t.canClose = canClose;
              toks.add(t);
              textStart = e;
            }
            adv = e;
          } else if (c == 91) {
            let nx = s.next(i);
            var done = false;
            if (s.hasIndex(nx) && s[nx] == 94) {
              let hit = s.indexOf("]", nx);
              if (hit is StringIndex) {
                let label = s.slice(s.next(nx), hit);
                if (!label.isEmpty && ctx.notes.has(label) && !contains(label, " ")) {
                  addText(toks, s, textStart, i);
                  if (!ctx.refs.has(label)) {
                    ctx.order.add(label);
                    ctx.refs.set(label, 1);
                  } else {
                    ctx.refs.set(label, ctx.refs.getOr(label, 0) + 1);
                  }
                  var num = 0;
                  var q = 0;
                  let ords = ctx.order.toList();
                  while (q < ords.length) {
                    if (ords[q] == label) { num = q + 1; }
                    q += 1;
                  }
                  toks.add(textTok("<sup><a href=\"#fn-${attrEsc(label)}\" rel=\"noopener noreferrer\">${num}</a></sup>", ""));
                  adv = s.next(hit);
                  textStart = adv;
                  done = true;
                }
              }
            }
            if (!done) {
              addText(toks, s, textStart, i);
              let t = new Tok(2, "", "");
              t.pos = nx;
              toks.add(t);
              textStart = nx;
              adv = nx;
            }
          } else if (c == 33) {
            let nx = s.next(i);
            if (s.hasIndex(nx) && s[nx] == 91) {
              addText(toks, s, textStart, i);
              let t = new Tok(2, "", "");
              t.image = true;
              t.pos = s.next(nx);
              toks.add(t);
              adv = s.next(nx);
              textStart = adv;
            }
          } else if (c == 93) {
            addText(toks, s, textStart, i);
            textStart = i;
            let res = closeBracket(ctx, toks, s, i);
            if (res != null) {
              adv = res;
              textStart = adv;
            }
          } else if (c == 104 || c == 119 || c == 102) {
            let prev = if (i == String.begin) { -1 } else { s[s.prev(i)] };
            if (boundaryBefore(prev)) {
              let bu = bareUrl(s, i);
              if (bu != null) {
                if (!insideLink(toks)) {
                  addText(toks, s, textStart, i);
                  toks.add(linkTok(bu.href, bu.text));
                  adv = bu.end;
                  textStart = adv;
                }
              }
            }
          } else if (c == 64) {
            var b = i;
            while (b > textStart && isEmailLocal(s[s.prev(b)])) { b = s.prev(b); }
            if (b < i) {
              let he = emailHostEnd(s, s.next(i));
              if (he != null) {
                if (!insideLink(toks)) {
                  addText(toks, s, textStart, b);
                  let addr = s.slice(b, he);
                  toks.add(linkTok("mailto:${addr}", addr));
                  adv = he;
                  textStart = adv;
                }
              }
            }
          }
          i = adv;
        }
      }
      addText(toks, s, textStart, s.end);
      processEmphasis(toks, 0);
      joinStr(toks.toList().map { (t): String => renderTok(t) }, "")
    }
