# Percent coding and query strings

    let hexVal(cp: Int): Int {
      if (cp >= 48 && cp <= 57) { cp - 48 } else if (cp >= 65 && cp <= 70) { cp - 55 } else if (cp >= 97 && cp <= 102) { cp - 87 } else { -1 }
    }

    let hexChar(n: Int): String {
      cpStr(if (n < 10) { 48 + n } else { 55 + n })
    }

Decoded `%XX` bytes are UTF-8: `%C3%A9` is one code point. A run of bytes is
collected and decoded together. Bytes that are not valid UTF-8 become U+FFFD,
one per bad byte; the text is never left half-decoded.

    let utf8Decode(bytes: List<Int>): String {
      let out = new ListBuilder<String>();
      var i = 0;
      while (i < bytes.length) {
        let b = bytes.getOr(i, 0);
        var need = -1;
        var cp = 0;
        var floor = 0;
        if (b < 0x80) { need = 0; cp = b; } else if (b >= 0xC2 && b < 0xE0) { need = 1; cp = b - 0xC0; floor = 0x80; } else if (b >= 0xE0 && b < 0xF0) { need = 2; cp = b - 0xE0; floor = 0x800; } else if (b >= 0xF0 && b < 0xF5) { need = 3; cp = b - 0xF0; floor = 0x10000; }
        var ok = need >= 0 && i + need < bytes.length;
        if (ok) {
          for (var k = 1; k <= need; ++k) {
            let c = bytes.getOr(i + k, 0);
            if (c >= 0x80 && c < 0xC0) { cp = cp * 64 + (c - 0x80); } else { ok = false; }
          }
        }
        if (ok && need > 0 && (cp < floor || cp > 0x10FFFF || (cp >= 0xD800 && cp < 0xE000))) {
          ok = false;
        }
        if (ok) {
          out.add(cpStr(cp));
          i += need + 1;
        } else {
          out.add(cpStr(0xFFFD));
          i += 1;
        }
      }
      out.toList().join("") { (x: String): String => x }
    }

The byte a piece starts with, when the piece begins with two hex digits (the
text after a `%`); -1 when it does not.

    let leadingByte(piece: String): Int {
      var i = String.begin;
      if (!piece.hasIndex(i)) { return -1; }
      let h = hexVal(piece[i]);
      i = piece.next(i);
      if (!piece.hasIndex(i)) { return -1; }
      let l = hexVal(piece[i]);
      if (h < 0 || l < 0) { -1 } else { h * 16 + l }
    }

    let afterTwo(piece: String): String {
      piece.slice(piece.next(piece.next(String.begin)), piece.end)
    }

    let plusToSpace(s: String): String {
      s.split("+").join(" ") { (x: String): String => x }
    }

    let literal(s: String, plus: Boolean): String {
      if (plus) { plusToSpace(s) } else { s }
    }

    let decodeWith(s: String, plus: Boolean): String {
      let pieces = s.split("%");
      if (pieces.length == 1) {
        return literal(s, plus);
      }
      let out = new ListBuilder<String>();
      var pending = new ListBuilder<Int>();
      for (var k = 0; k < pieces.length; ++k) {
        let piece = pieces.getOr(k, "");
        let b = if (k == 0) { -1 } else { leadingByte(piece) };
        if (k == 0) {
          out.add(literal(piece, plus));
        } else if (b < 0) {
          out.add(utf8Decode(pending.toList()));
          pending = new ListBuilder<Int>();
          out.add("%");
          out.add(literal(piece, plus));
        } else {
          pending.add(b);
          let rest = afterTwo(piece);
          if (rest != "") {
            out.add(utf8Decode(pending.toList()));
            pending = new ListBuilder<Int>();
            out.add(literal(rest, plus));
          }
        }
      }
      out.add(utf8Decode(pending.toList()));
      out.toList().join("") { (x: String): String => x }
    }

`+` is a space, as in a form or query string. A path is decoded with
`decodeWith(path, false)`, where `+` stays. A `%` not followed by two hex
digits is kept as it is.

    export let urlDecode(s: String): String {
      decodeWith(s, true)
    }

RFC 3986 unreserved characters (letters, digits, `-._~`) are kept; everything
else is its UTF-8 bytes as `%XX`, upper-case hex. A space is `%20`.

    let encodeCp(cp: Int, out: ListBuilder<String>): Void {
      if (
        (cp >= 48 && cp <= 57) || (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) ||
        cp == 45 || cp == 46 || cp == 95 || cp == 126
      ) {
        out.add(cpStr(cp));
        return;
      }
      let bytes = new ListBuilder<Int>();
      if (cp < 0x80) { bytes.add(cp); } else if (cp < 0x800) {
        bytes.add(0xC0 + cp / 64);
        bytes.add(0x80 + cp % 64);
      } else if (cp < 0x10000) {
        bytes.add(0xE0 + cp / 4096);
        bytes.add(0x80 + (cp / 64) % 64);
        bytes.add(0x80 + cp % 64);
      } else {
        bytes.add(0xF0 + cp / 262144);
        bytes.add(0x80 + (cp / 4096) % 64);
        bytes.add(0x80 + (cp / 64) % 64);
        bytes.add(0x80 + cp % 64);
      }
      let list = bytes.toList();
      for (var k = 0; k < list.length; ++k) {
        let b = list.getOr(k, 0);
        out.add("%");
        out.add(hexChar(b / 16));
        out.add(hexChar(b % 16));
      }
    }

    export let urlEncode(s: String): String {
      let out = new ListBuilder<String>();
      var i = String.begin;
      while (s.hasIndex(i)) {
        encodeCp(s[i], out);
        i = s.next(i);
      }
      out.toList().join("") { (x: String): String => x }
    }

## Query strings

`a=1&b=two%20words&flag`. A key with no `=` has the value "". Empty keys are
dropped. When a key repeats, the last one wins. Used for the URL query and for
urlencoded bodies alike.

    export let queryParse(s: String): Map<String, String> {
      let out = new MapBuilder<String, String>();
      let pairs = s.split("&");
      for (var k = 0; k < pairs.length; ++k) {
        let pair = pairs.getOr(k, "");
        if (pair != "") {
          let kv = splitOnce(pair, "=");
          let key = urlDecode(kv.head);
          if (key != "") { out.set(key, urlDecode(kv.tail)); }
        }
      }
      out.toMap()
    }
