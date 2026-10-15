# A forgiving HTML parser

What Floki's default parser (mochiweb) made of a page, for the page importer.
Not a browser's parser: a tree of elements and text, built the way mochiweb
builds it, because the markdown that comes out depends on that tree.

Checked against Floki 0.38 on these inputs, and written to agree with it:

* whitespace-only text between tags is dropped (`<b>a</b> <i>b</i>` loses its
  space) and comments, doctypes and processing instructions are not nodes;
* names and attribute names are lower-cased, attribute values have their
  entities decoded, a bare attribute's value is its own name;
* void elements and `/>` have no children, a stray end tag is ignored, and an
  end tag closes everything up to the nearest open element of that name;
* `li`, `dt`, `dd` and `option` close an open one of the same family when they
  start, but `p` and `td` do not (`<p>one<p>two` nests);
* `script`, `style`, `title` and `textarea` hold raw text up to their end tag,
  and only the raw text of `title` and `textarea` keeps its entities undecoded;
* a `<` that does not start a tag is text.

Where it differs: named entities beyond the table below stay as written
(Floki knows all 2,231), an entity without its `;` is not decoded, and
`<![CDATA[...]]>` is dropped, not kept as text.

    let { sysStringReplace, sysUtf8Downcase } = import("sys/src");

## The tree

A text node has the empty `tag`; the root has the tag `#doc`.

    export class ImporterAttr(public name: String, public value: String) {}

    export class ImporterNode(public tag: String, public text: String) {
      public var attrs: List<ImporterAttr> = [];
      public var kids: ListBuilder<ImporterNode> = new ListBuilder<ImporterNode>();
    }

    let importerAttrOf(node: ImporterNode, wanted: String): String? {
      var i = 0;
      while (i < node.attrs.length) {
        if (node.attrs[i].name == wanted) { return node.attrs[i].value; }
        i += 1;
      }
      null
    }

    let importerIsElement(node: ImporterNode): Boolean { !node.tag.isEmpty }

## Entities

    let importerEntityNames = [
      "amp", "lt", "gt", "quot", "apos", "nbsp", "copy", "reg", "trade", "hellip",
      "mdash", "ndash", "lsquo", "rsquo", "ldquo", "rdquo", "sbquo", "bdquo", "laquo",
      "raquo", "bull", "middot", "times", "divide", "deg", "plusmn", "frac12", "frac14",
      "frac34", "sect", "para", "cent", "pound", "yen", "euro", "larr", "rarr", "uarr",
      "darr", "harr", "shy", "iexcl", "iquest", "szlig", "agrave", "aacute", "acirc",
      "atilde", "auml", "aring", "aelig", "ccedil", "egrave", "eacute", "ecirc", "euml",
      "igrave", "iacute", "icirc", "iuml", "ntilde", "ograve", "oacute", "ocirc", "otilde",
      "ouml", "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "yuml", "Agrave",
      "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute",
      "Ecirc", "Euml", "Igrave", "Iacute", "Icirc", "Iuml", "Ntilde", "Ograve", "Oacute",
      "Ocirc", "Otilde", "Ouml", "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "AMP",
      "LT", "GT", "QUOT", "ensp", "emsp", "thinsp", "zwnj", "zwj", "dagger", "Dagger",
      "permil", "prime", "Prime", "minus", "lowast", "infin", "ne", "le", "ge", "sum",
      "micro", "sup1", "sup2", "sup3", "ordf", "ordm", "not", "macr", "acute", "cedil",
      "uml", "curren", "brvbar", "laquo",
    ];

    let importerEntityCodes = [
      38, 60, 62, 34, 39, 160, 169, 174, 8482, 8230,
      8212, 8211, 8216, 8217, 8220, 8221, 8218, 8222, 171,
      187, 8226, 183, 215, 247, 176, 177, 189, 188,
      190, 167, 182, 162, 163, 165, 8364, 8592, 8594, 8593,
      8595, 8596, 173, 161, 191, 223, 224, 225, 226,
      227, 228, 229, 230, 231, 232, 233, 234, 235,
      236, 237, 238, 239, 241, 242, 243, 244, 245,
      246, 248, 249, 250, 251, 252, 253, 255, 192,
      193, 194, 195, 196, 197, 198, 199, 200, 201,
      202, 203, 204, 205, 206, 207, 209, 210, 211,
      212, 213, 214, 216, 217, 218, 219, 220, 38,
      60, 62, 34, 8194, 8195, 8201, 8204, 8205, 8224, 8225,
      8240, 8242, 8243, 8722, 8727, 8734, 8800, 8804, 8805, 8721,
      181, 185, 178, 179, 170, 186, 172, 175, 180, 184,
      168, 164, 166, 171,
    ];

    let importerEntityIndex(name: String): Int {
      var i = 0;
      while (i < importerEntityNames.length) {
        if (importerEntityNames[i] == name) { return i; }
        i += 1;
      }
      -1
    }

`&#65;` and `&#x41;`: the digits up to a `;`. Zero, a surrogate or a value past
U+10FFFF is U+FFFD.

    let importerNumericEntity(body: String): Int {
      let cps = importerCps(body);
      if (cps.length < 1) { return -1; }
      var hex = false;
      var i = 0;
      if (cps[0] == 120 || cps[0] == 88) {
        hex = true;
        i = 1;
      }
      if (i >= cps.length || cps.length - i > 8) { return -1; }
      var n = 0;
      while (i < cps.length) {
        let c = cps[i];
        var d = -1;
        if (c >= 48 && c <= 57) { d = c - 48; }
        if (hex && c >= 65 && c <= 70) { d = c - 55; }
        if (hex && c >= 97 && c <= 102) { d = c - 87; }
        if (d < 0) { return -1; }
        if (n > 0x10FFFF) { return 0xFFFD; }
        n = n * (if (hex) { 16 } else { 10 }) + d;
        i += 1;
      }
      if (n == 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF)) { 0xFFFD } else { n }
    }

    let importerDecode(text: String): String {
      let pieces = text.split("&");
      if (pieces.length < 2) { return text; }
      let sb = new StringBuilder();
      sb.append(pieces[0]);
      var k = 1;
      while (k < pieces.length) {
        let p = pieces[k];
        let semi = p.split(";");
        var done = false;
        if (semi.length > 1) {
          let name = semi[0];
          let rest = importerJoin(semi.slice(1, semi.length), ";");
          if (importerStartsWith(name, "#")) {
            let cp = importerNumericEntity(importerSliceFrom(name, 1));
            if (cp >= 0) {
              sb.append(importerChr(cp));
              sb.append(rest);
              done = true;
            }
          } else {
            let at = importerEntityIndex(name);
            if (at >= 0) {
              sb.append(importerChr(importerEntityCodes[at]));
              sb.append(rest);
              done = true;
            }
          }
        }
        if (!done) {
          sb.append("&");
          sb.append(p);
        }
        k += 1;
      }
      sb.toString()
    }

## The builder

    let importerVoid = [
      "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
      "param", "source", "track", "wbr", "command", "keygen",
    ];

    let importerRawTags = ["script", "style", "title", "textarea"];

    let importerImplied = ["li", "dt", "dd", "option"];

    class ImporterBuilder {
      public stack: ListBuilder<ImporterNode> = new ListBuilder<ImporterNode>();
      public var pending: ListBuilder<String> = new ListBuilder<String>();
      public var raw: String = "";

      public top(): ImporterNode { stack[stack.length - 1] }

      public addText(s: String): Void {
        if (!s.isEmpty) { pending.add(s); }
      }

Whitespace-only text is dropped; the rest is decoded unless the open element
holds raw text.

      public flush(): Void {
        if (pending.length > 0) {
          let text = importerJoin(pending.toList(), "");
          pending = new ListBuilder<String>();
          if (!importerBlankMarkup(text)) {
            let t = top();
            let keep = if (importerIsOneOf(t.tag, importerRawTags)) { text } else { importerDecode(text) };
            t.kids.add(new ImporterNode("", keep));
          }
        }
      }

      public open(tag: String, attrs: List<ImporterAttr>, selfClosing: Boolean): Void {
        flush();
        if (importerIsOneOf(tag, importerImplied)) {
          let t = top();
          if (importerSameFamily(t.tag, tag)) { stack.removeLast(); }
        }
        let node = new ImporterNode(tag, "");
        node.attrs = attrs;
        top().kids.add(node);
        if (!selfClosing && !importerIsOneOf(tag, importerVoid)) {
          stack.add(node);
          if (importerIsOneOf(tag, importerRawTags)) { raw = tag; }
        }
      }

      public close(tag: String): Void {
        flush();
        var i = stack.length - 1;
        while (i >= 1) {
          if (stack[i].tag == tag) {
            while (stack.length > i) { stack.removeLast(); }
            return;
          }
          i -= 1;
        }
      }
    }

    let importerBlankMarkup(s: String): Boolean {
      var i = String.begin;
      while (s.hasIndex(i)) {
        let c = s[i];
        if (c != 32 && c != 9 && c != 10 && c != 13) { return false; }
        i = s.next(i);
      }
      true
    }

    let importerSameFamily(open: String, next: String): Boolean {
      if (next == "li" || next == "option") { return open == next; }
      open == "dt" || open == "dd"
    }

## Reading a tag

`head` is everything between `<` and `>`: the name, then attributes.

    let importerIsNameChar(cp: Int): Boolean {
      !(importerIsSpace(cp) || cp == 47 || cp == 62 || cp == 61)
    }

    class ImporterHead(public tag: String, public attrs: List<ImporterAttr>, public selfClosing: Boolean) {}

    let importerReadHead(head: String): ImporterHead {
      let cps = importerCps(head);
      var i = 0;
      while (i < cps.length && importerIsNameChar(cps[i])) { i += 1; }
      let tag = importerLower(importerSlice(cps, 0, i));
      let attrs = new ListBuilder<ImporterAttr>();
      var selfClosing = false;
      while (i < cps.length) {
        let c = cps[i];
        if (importerIsSpace(c)) {
          i += 1;
        } else if (c == 47) {
          if (i == cps.length - 1) { selfClosing = true; }
          i += 1;
        } else {
          var j = i;
          while (j < cps.length && importerIsNameChar(cps[j])) { j += 1; }
          if (j == i) { j = i + 1; }
          let name = importerLower(importerSlice(cps, i, j));
          i = j;
          while (i < cps.length && importerIsSpace(cps[i])) { i += 1; }
          var value = name;
          if (i < cps.length && cps[i] == 61) {
            i += 1;
            while (i < cps.length && importerIsSpace(cps[i])) { i += 1; }
            if (i < cps.length && (cps[i] == 34 || cps[i] == 39)) {
              let q = cps[i];
              var k = i + 1;
              while (k < cps.length && cps[k] != q) { k += 1; }
              value = importerDecode(importerSlice(cps, i + 1, k));
              i = if (k < cps.length) { k + 1 } else { k };
            } else {
              var k = i;
              while (k < cps.length && !importerIsSpace(cps[k])) { k += 1; }
              value = importerDecode(importerSlice(cps, i, k));
              i = k;
            }
          }
          attrs.add(new ImporterAttr(name, value));
        }
      }
      new ImporterHead(tag, attrs.toList(), selfClosing)
    }

The index of the `>` that ends the tag in `p`, skipping quoted attribute
values, as a code point offset; -1 when there is none.

    let importerTagEnd(p: String): Int {
      var i = String.begin;
      var n = 0;
      var quote = 0;
      while (p.hasIndex(i)) {
        let c = p[i];
        if (quote != 0) {
          if (c == quote) { quote = 0; }
        } else if (c == 34 || c == 39) {
          quote = c;
        } else if (c == 62) {
          return n;
        }
        i = p.next(i);
        n += 1;
      }
      -1
    }

Whether `p` (the text after a `<`) is the end tag of `tag`.

    let importerEndsRaw(p: String, tag: String): Boolean {
      if (!importerStartsWith(p, "/")) { return false; }
      let want = "/${tag}";
      let head = importerLower(importerPrefix(p, 1 + importerCpCount(tag)));
      if (head != want) { return false; }
      let next = importerSliceFrom(p, 1 + importerCpCount(tag));
      if (next.isEmpty) { return true; }
      let c = next[String.begin];
      importerIsSpace(c) || c == 62 || c == 47
    }

The first `n` code points of `s`.

    let importerPrefix(s: String, n: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < n && s.hasIndex(i)) {
        i = s.next(i);
        k += 1;
      }
      s.slice(String.begin, i)
    }

    let importerIsLetter(cp: Int): Boolean {
      (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122)
    }

## Parsing

    export let importerParseHtml(html: String): ImporterNode {
      let root = new ImporterNode("#doc", "");
      let b = new ImporterBuilder();
      b.stack.add(root);
      let pieces = html.split("<");
      b.addText(pieces[0]);
      var k = 1;
      while (k < pieces.length) {
        let p = pieces[k];
        k += 1;
        if (!b.raw.isEmpty) {
          if (importerEndsRaw(p, b.raw)) {
            b.flush();
            b.stack.removeLast();
            b.raw = "";
            let gt = importerTagEnd(p);
            if (gt >= 0) { b.addText(importerSliceFrom(p, gt + 1)); }
          } else {
            b.addText("<${p}");
          }
        } else if (importerStartsWith(p, "!--")) {
          var body = importerSliceFrom(p, 3);
          var found = importerContains(body, "-->");
          while (!found && k < pieces.length) {
            body = "<${pieces[k]}";
            k += 1;
            found = importerContains(body, "-->");
          }
          if (found) {
            let after = importerAfterFirst(body, "-->");
            if (after != null) { b.addText(after); }
          }
        } else if (importerStartsWith(p, "!") || importerStartsWith(p, "?")) {
          let gt = importerTagEnd(p);
          if (gt >= 0) { b.addText(importerSliceFrom(p, gt + 1)); }
        } else if (importerStartsWith(p, "/") && p.countBetween(String.begin, p.end) > 1 &&
                   importerIsLetter(p[p.next(String.begin)])) {
          let gt = importerTagEnd(p);
          if (gt >= 0) {
            let head = importerReadHead(importerSliceFrom(importerPrefix(p, gt), 1));
            b.close(head.tag);
            b.addText(importerSliceFrom(p, gt + 1));
          } else {
            b.addText("<${p}");
          }
        } else if (p.hasIndex(String.begin) && importerIsLetter(p[String.begin])) {
          let gt = importerTagEnd(p);
          if (gt >= 0) {
            let head = importerReadHead(importerPrefix(p, gt));
            b.open(head.tag, head.attrs, head.selfClosing);
            b.addText(importerSliceFrom(p, gt + 1));
          } else {
            b.addText("<${p}");
          }
        } else {
          b.addText("<${p}");
        }
      }
      b.flush();
      root
    }

## Walking the tree

Every element below `node` in document order, `node` itself left out.

    let importerCollect(node: ImporterNode, out: ListBuilder<ImporterNode>): Void {
      var i = 0;
      while (i < node.kids.length) {
        let kid = node.kids[i];
        if (importerIsElement(kid)) {
          out.add(kid);
          importerCollect(kid, out);
        }
        i += 1;
      }
    }

    let importerElements(node: ImporterNode): List<ImporterNode> {
      let out = new ListBuilder<ImporterNode>();
      importerCollect(node, out);
      out.toList()
    }

The text nodes below `node`, in document order. `Floki.text` leaves out the
content of `script` (its `js: false` default).

    let importerCollectText(node: ImporterNode, out: ListBuilder<String>): Void {
      var i = 0;
      while (i < node.kids.length) {
        let kid = node.kids[i];
        if (importerIsElement(kid)) {
          if (kid.tag != "script") { importerCollectText(kid, out); }
        } else {
          out.add(kid.text);
        }
        i += 1;
      }
    }

    let importerTextParts(node: ImporterNode): List<String> {
      let out = new ListBuilder<String>();
      importerCollectText(node, out);
      out.toList()
    }

    let importerTextOf(node: ImporterNode): String {
      importerJoin(importerTextParts(node), "")
    }

Remove every element whose tag is in `tags`, wherever it is
(`Floki.filter_out/2`), in place.

    let importerStrip(node: ImporterNode, tags: List<String>): Void {
      let kept = new ListBuilder<ImporterNode>();
      var i = 0;
      while (i < node.kids.length) {
        let kid = node.kids[i];
        if (importerIsElement(kid)) {
          if (!importerIsOneOf(kid.tag, tags)) {
            importerStrip(kid, tags);
            kept.add(kid);
          }
        } else {
          kept.add(kid);
        }
        i += 1;
      }
      node.kids = kept;
    }
