# Paragraph diff

Two versions of a draft, aligned into rows a reader can put side by side.
Paragraphs are the unit: prose here is one paragraph per line, and a line
diff marks a whole paragraph changed because a comma moved. A paragraph
that changed carries a word diff inside it (`words.temper.md`).

A row's `kind` is `"same"`, `"change"`, `"del"` or `"ins"`; `del` has only
a left side and `ins` only a right.

    @imu export class Row(
      public kind: String,
      public left: String?,
      public right: String?,
    ) {}

## Paragraphs

Split on runs of two or more newlines, after turning `\r\n` into `\n`;
trim each piece and drop the empty ones. The Elixir this replaces did that
with `String.split(~r/\n{2,}/, trim: true)` and `String.trim/1`.

    export let paragraphs(text: String): List<String> {
      let out = new ListBuilder<String>();
      let piece = new StringBuilder();
      var newlines = 0;
      var i = String.begin;
      while (text.hasIndex(i)) {
        var cp = text[i];
        let after = text.next(i);
        // \r\n is one newline
        if (cp == 13 && text.hasIndex(after) && text[after] == 10) {
          i = after;
          cp = 10;
        }
        if (cp == 10) {
          newlines += 1;
        } else {
          if (newlines >= 2) {
            flushParagraph(piece, out);
          } else if (newlines == 1) {
            piece.append("\n");
          }
          newlines = 0;
          piece.appendCodePoint(cp) orelse panic();
        }
        i = text.next(i);
      }
      if (newlines == 1) { piece.append("\n"); }
      flushParagraph(piece, out);
      out.toList()
    }

    let flushParagraph(piece: StringBuilder, out: ListBuilder<String>): Void {
      let p = trim(piece.toString());
      if (!p.isEmpty) { out.add(p); }
      piece.clear();
    }

A paragraph's identity for alignment ignores how it is wrapped: runs of
whitespace become one space, then trim. A rewrap is not an edit.

    let alignmentKey(p: String): String {
      let out = new StringBuilder();
      var inSpace = false;
      var i = String.begin;
      while (p.hasIndex(i)) {
        let cp = p[i];
        if (isRegexSpace(cp)) {
          inSpace = true;
        } else {
          if (inSpace) { out.append(" "); }
          inSpace = false;
          out.appendCodePoint(cp) orelse panic();
        }
        i = p.next(i);
      }
      if (inSpace) { out.append(" "); }
      trim(out.toString())
    }

## Rows

A longest-common-subsequence over the paragraphs' keys, then each run of
deletes and inserts between two matches is paired up positionally: an edit
to one sentence reads as a change of one paragraph, not a paragraph thrown
away and another written.

    export let rows(before: String, after: String): List<Row> {
      let a = paragraphs(before);
      let b = paragraphs(after);
      let ak = a.map { (p): String => alignmentKey(p) };
      let bk = b.map { (p): String => alignmentKey(p) };
      let n = a.length;
      let m = b.length;
      let width = m + 1;

The table is (n + 1) × (m + 1), flat, filled from the end.

      let table = new ListBuilder<Int>();
      for (var k = 0; k < (n + 1) * width; ++k) { table.add(0); }
      for (var i = n - 1; i >= 0; --i) {
        for (var j = m - 1; j >= 0; --j) {
          let value = if (ak[i] == bk[j]) {
            1 + table[(i + 1) * width + j + 1]
          } else {
            let down = table[(i + 1) * width + j];
            let across = table[i * width + j + 1];
            if (down > across) { down } else { across }
          };
          table[i * width + j] = value;
        }
      }

Walk it from the start. Inserts are taken before deletes when either would
do, as the Elixir walk did.

      let out = new ListBuilder<Row>();
      let dels = new ListBuilder<String>();
      let ins = new ListBuilder<String>();
      var i = 0;
      var j = 0;
      while (i < n || j < m) {
        if (i < n && j < m && ak[i] == bk[j]) {
          flushRun(dels, ins, out);
          out.add(new Row("same", a[i], a[i]));
          i += 1;
          j += 1;
        } else if (j < m && (i >= n || table[i * width + j + 1] >= table[(i + 1) * width + j])) {
          ins.add(b[j]);
          j += 1;
        } else {
          dels.add(a[i]);
          i += 1;
        }
      }
      flushRun(dels, ins, out);
      out.toList()
    }

A run's deletes and inserts pair up in order; what is left over on either
side stays a delete or an insert.

    let flushRun(dels: ListBuilder<String>, ins: ListBuilder<String>, out: ListBuilder<Row>): Void {
      let longer = if (dels.length > ins.length) { dels.length } else { ins.length };
      for (var k = 0; k < longer; ++k) {
        if (k < dels.length && k < ins.length) {
          out.add(new Row("change", dels[k], ins[k]));
        } else if (k < dels.length) {
          out.add(new Row("del", dels[k], null));
        } else {
          out.add(new Row("ins", null, ins[k]));
        }
      }
      dels.clear();
      ins.clear();
    }
