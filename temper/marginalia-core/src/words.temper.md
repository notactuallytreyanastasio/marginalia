# Word diff

A word-level diff of two spans: parts of `kind` `"same"`, `"del"` or `"ins"`,
neighbours of one kind merged. Each word keeps the whitespace that followed
it, so the parts joined back up are the text.

    @imu export class Part(public kind: String, public text: String) {}

A word is a run of non-space with the space after it: `\S+\s*`, ASCII
space, as the regex this replaces had it. Space before the first word is
not part of any word.

    let wordsOf(text: String): List<String> {
      let out = new ListBuilder<String>();
      var i = String.begin;
      while (text.hasIndex(i) && isRegexSpace(text[i])) { i = text.next(i); }
      while (text.hasIndex(i)) {
        let start = i;
        while (text.hasIndex(i) && !isRegexSpace(text[i])) { i = text.next(i); }
        while (text.hasIndex(i) && isRegexSpace(text[i])) { i = text.next(i); }
        out.add(text.slice(start, i));
      }
      out.toList()
    }

## The diff

Myers compares the trimmed words, so a word is the same word whatever
whitespace followed it; the whitespace each word carried comes back from
the original lists as the script is walked.

    export let diff(a: String, b: String): List<Part> {
      let aw = wordsOf(a);
      let bw = wordsOf(b);
      let ak = aw.map { (w): String => trim(w) };
      let bk = bw.map { (w): String => trim(w) };
      let parts = new ListBuilder<Part>();
      if (unrelated(ak, bk)) {
        for (var k = 0; k < aw.length; ++k) { parts.add(new Part("del", aw[k])); }
        for (var k = 0; k < bw.length; ++k) { parts.add(new Part("ins", bw[k])); }
      } else {
        attach(myers(ak, bk), aw, bw, parts);
      }
      merge(parts.toList())
    }

Myers is linear when two texts are alike and quadratic when they share
nothing, and two long spans that share nothing is the one case where a word
diff says nothing anyway. Two spans of 200 words or more that share under
5% of their vocabulary are shown as one deletion and one insertion. The
comparison is in floats, as the original was: `20 * shared < smaller` would
disagree with it where `0.05 * smaller` rounds above a whole number.

    let unrelated(ak: List<String>, bk: List<String>): Boolean {
      if (ak.length < 200 || bk.length < 200) { return false; }
      let a = distinct(ak).toMap();
      let b = distinct(bk).toMap();
      let bKeys = b.keys();
      var shared = 0;
      for (var k = 0; k < bKeys.length; ++k) {
        if (a.has(bKeys[k])) { shared += 1; }
      }
      let aSize = a.keys().length;
      let bSize = bKeys.length;
      let smaller = if (aSize < bSize) { aSize } else { bSize };
      shared.toFloat64() < 0.05 * smaller.toFloat64()
    }

    let distinct(words: List<String>): MapBuilder<String, Boolean> {
      let set = new MapBuilder<String, Boolean>();
      for (var k = 0; k < words.length; ++k) { set.set(words[k], true); }
      set
    }


## Myers, as Elixir's `List.myers_difference/2` does it

Ported step for step, so that where two minimal scripts tie, this picks the
one Elixir picked: the paths of each envelope are walked in the same order,
`moveRight` and `moveDown` choose as `move_right` and `move_down` did, and
the compaction keeps the rule that moves an insertion ahead of an equal
run it duplicates. Each path's edits are a linked list that later paths
share, newest first, as they were in Elixir.

    @imu class Edit(public kind: Int, public word: String, public before: Edit?) {}

    @imu class Path(public y: Int, public i: Int, public j: Int, public edits: Edit?) {}

    let EQ = 0;
    let DEL = 1;
    let INS = 2;

    let moveRight(p: Path, b: List<String>): Path {
      if (p.j < b.length) {
        new Path(p.y, p.i, p.j + 1, new Edit(INS, b[p.j], p.edits))
      } else {
        p
      }
    }

    let moveDown(p: Path, a: List<String>): Path {
      if (p.i < a.length) {
        new Path(p.y + 1, p.i + 1, p.j, new Edit(DEL, a[p.i], p.edits))
      } else {
        new Path(p.y + 1, p.i, p.j, p.edits)
      }
    }

    let followSnake(p: Path, a: List<String>, b: List<String>): Path {
      var y = p.y;
      var i = p.i;
      var j = p.j;
      var edits = p.edits;
      while (i < a.length && j < b.length && a[i] == b[j]) {
        edits = new Edit(EQ, a[i], edits);
        y += 1;
        i += 1;
        j += 1;
      }
      new Path(y, i, j, edits)
    }

A chunk of the script: a kind and its words, in order.

    class Chunk(public kind: Int, public words: ListBuilder<String>) {}

    let myers(a: List<String>, b: List<String>): List<Chunk> {
      var paths: List<Path> = [new Path(0, 0, 0, null)];
      var envelope = 0;
      while (true) {
        let next = new ListBuilder<Path>();
        var at = 0;
        var diag = -envelope;
        while (diag <= envelope) {
          let left = paths.length - at;
          var path = paths[at];
          if (diag == 0 && envelope == 0) {
            at += 1;
          } else if (diag == -envelope) {
            path = moveDown(path, a);
          } else if (diag == envelope && left == 1) {
            path = moveRight(path, b);
            at += 1;
          } else {
            let second = paths[at + 1];
            path = if (path.y > second.y) { moveRight(path, b) } else { moveDown(second, a) };
            at += 1;
          }
          path = followSnake(path, a, b);
          if (path.i == a.length && path.j == b.length) {
            return compact(path.edits);
          }
          next.add(path);
          diag += 2;
        }
        paths = next.toList();
        envelope += 1;
      }
    }

`compact_reverse/2`: walk the edits newest first and build the chunks front
to back. `out` holds them in reverse, its last element the frontmost chunk,
and each chunk's words are in reverse too, so both are turned round at the
end.

    let compact(edits: Edit?): List<Chunk> {
      let out = new ListBuilder<Chunk>();
      var e = edits;
      while (e != null) {
        let edit = e as Edit orelse panic();
        let n = out.length;
        if (n > 0 && out[n - 1].kind == edit.kind) {
          out[n - 1].words.add(edit.word);
          e = edit.before;
        } else if (
          n >= 3 && out[n - 1].kind == EQ && out[n - 2].kind == INS && out[n - 3].kind == EQ &&
            sameWords(out[n - 1].words, out[n - 2].words)
        ) {
          // [eq X, ins X, eq Y | rest] becomes [ins X, eq X ++ Y | rest];
          // the edit is not consumed, as in Elixir
          let x = out.removeLast();
          let ins = out.removeLast();
          let y = out.removeLast();
          let merged = new ListBuilder<String>();
          merged.addAll(y.words);
          merged.addAll(x.words);
          out.add(new Chunk(EQ, merged));
          out.add(ins);
        } else {
          let words = new ListBuilder<String>();
          words.add(edit.word);
          out.add(new Chunk(edit.kind, words));
          e = edit.before;
        }
      }
      out.reverse();
      for (var k = 0; k < out.length; ++k) { out[k].words.reverse(); }
      out.toList()
    }

    let sameWords(x: ListBuilder<String>, y: ListBuilder<String>): Boolean {
      if (x.length != y.length) { return false; }
      for (var k = 0; k < x.length; ++k) {
        if (x[k] != y[k]) { return false; }
      }
      true
    }

## Putting the whitespace back

A word both sides share is shown on both, so it carries the new side's
whitespace; where the new side has none, because the word ends its
paragraph there, it takes the old side's, or the old side would read
"word38only118" where two words met.

    let attach(script: List<Chunk>, aw: List<String>, bw: List<String>, parts: ListBuilder<Part>): Void {
      var ai = 0;
      var bi = 0;
      for (var c = 0; c < script.length; ++c) {
        let chunk = script[c];
        let count = chunk.words.length;
        for (var k = 0; k < count; ++k) {
          if (chunk.kind == EQ) {
            let ta = aw[ai];
            let tb = bw[bi];
            let cut = trailingStart(tb);
            let token = if (cut == tb.end) {
              "${trim(tb)}${ta.slice(trailingStart(ta), ta.end)}"
            } else {
              tb
            };
            parts.add(new Part("same", token));
            ai += 1;
            bi += 1;
          } else if (chunk.kind == DEL) {
            parts.add(new Part("del", aw[ai]));
            ai += 1;
          } else {
            parts.add(new Part("ins", bw[bi]));
            bi += 1;
          }
        }
      }
    }

Neighbouring parts of one kind become one.

    let merge(parts: List<Part>): List<Part> {
      let out = new ListBuilder<Part>();
      var k = 0;
      while (k < parts.length) {
        let kind = parts[k].kind;
        let text = new StringBuilder();
        while (k < parts.length && parts[k].kind == kind) {
          text.append(parts[k].text);
          k += 1;
        }
        out.add(new Part(kind, text.toString()));
      }
      out.toList()
    }
