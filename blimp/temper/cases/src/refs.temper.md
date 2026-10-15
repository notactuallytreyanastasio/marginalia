# "A" and "B" in a rationale

The linker writes its reasons with the pair lettered: "B answers A's open
question." On a page about one case that reads as plumbing, so the letters are
turned back into the documents' names. `Links.plain/2` is the Elixir; the case
code needs the same substitution on rationales and summaries it loads itself
(`casesResolveRefs`), so it is here, with `casesName`, rather than called
through `links`.

The Elixir did it with one left-to-right `Regex.replace` and a function
replacement (so a title starting with digits cannot be read as a
backreference, and replaced text is never rescanned). The pattern is, with `u`:
`(\A|\bManuscripts?\s+|[.;:—-]\s+|\s+)([AB])(['’]s)?(?![\p{L}\p{N}'’])`.

For each match `(whole, pre, letter, poss)`:

1. `pre` is "Manuscript " or "Manuscripts ": the word and its space go, and
   the result is `name(letter)` plus `poss`;
2. otherwise a possessive (`'s`): `pre`, `name(letter)`, `poss`;
3. otherwise `pre` is empty (the start of the text) or ends a sentence or
   clause (`. ; : — -` and spaces): `pre` and `name(letter)`;
4. otherwise a bare letter after plain whitespace ("Part A", "Exhibit B")
   is left exactly as it was.

    let { isUnicodeLetter, isUnicodeNumber, isUnicodeSpace } = import("core/src");
    let { sysJoin } = import("sys/src");

## The name of a document

`name(work)`: the part of the title after the first em dash with spaces
around it, else the whole title.

    export let casesName(title: String): String {
      let parts = title.split(" — ");
      if (parts.length < 2) {
        title
      } else {
        let rest = new ListBuilder<String>();
        var i = 1;
        while (i < parts.length) {
          rest.add(parts[i]);
          i += 1;
        }
        sysJoin(rest.toList(), " — ")
      }
    }

## The scan

`pre` is described by its kind: 0 empty (start of text), 1 "Manuscript(s) ",
2 punctuation and spaces, 3 spaces only.

    class CasesRefHit(
      public end: Int,
      public kind: Int,
      public preEnd: Int,
      public letter: Int,
      public possEnd: Int,
    ) {}

    let casesRefWord(cp: Int): Boolean {
      isUnicodeLetter(cp) || isUnicodeNumber(cp) || cp == 95
    }

    let casesRefBlock(cp: Int): Boolean {
      isUnicodeLetter(cp) || isUnicodeNumber(cp) || cp == 39 || cp == 8217
    }

    let casesRefSpaces(cps: List<Int>, from: Int): Int {
      var k = from;
      while (k < cps.length && isUnicodeSpace(cps[k])) { k += 1; }
      k
    }

The part after `pre`: `[AB]`, an optional `'s`, and a character that is not a
letter, a digit or an apostrophe (or the end). With the possessive taken and
the lookahead failing, giving the possessive back cannot help: the next
character would be the apostrophe, which the lookahead refuses.

    let casesRefTail(cps: List<Int>, j: Int, kind: Int, preEnd: Int): CasesRefHit? {
      if (j >= cps.length) { return null; }
      let letter = cps[j];
      if (letter != 65 && letter != 66) { return null; }
      var k = j + 1;
      var possEnd = j + 1;
      if (k + 1 < cps.length && (cps[k] == 39 || cps[k] == 8217) && cps[k + 1] == 115) {
        possEnd = k + 2;
        k = k + 2;
      }
      if (k < cps.length && casesRefBlock(cps[k])) { return null; }
      new CasesRefHit(k, kind, preEnd, letter, possEnd)
    }

    let casesRefLiteral(cps: List<Int>, at: Int, word: List<Int>): Boolean {
      if (at + word.length > cps.length) { return false; }
      var i = 0;
      while (i < word.length) {
        if (cps[at + i] != word[i]) { return false; }
        i += 1;
      }
      true
    }

The alternatives of the first group, in the regex's order, tried at `p`.

    let casesRefAt(cps: List<Int>, p: Int): CasesRefHit? {
      if (p == 0) {
        let head = casesRefTail(cps, 0, 0, 0);
        if (head != null) { return head; }
      }
      let manuscript = [77, 97, 110, 117, 115, 99, 114, 105, 112, 116];
      if ((p == 0 || !casesRefWord(cps[p - 1])) && casesRefLiteral(cps, p, manuscript)) {
        var after = p + manuscript.length;
        if (after < cps.length && cps[after] == 115) { after += 1; }
        let spaced = casesRefSpaces(cps, after);
        if (spaced > after) {
          let hit = casesRefTail(cps, spaced, 1, spaced);
          if (hit != null) { return hit; }
        }
      }
      let c = cps[p];
      if (c == 46 || c == 59 || c == 58 || c == 8212 || c == 45) {
        let spaced = casesRefSpaces(cps, p + 1);
        if (spaced > p + 1) {
          let hit = casesRefTail(cps, spaced, 2, spaced);
          if (hit != null) { return hit; }
        }
      }
      if (isUnicodeSpace(c)) {
        let spaced = casesRefSpaces(cps, p);
        let hit = casesRefTail(cps, spaced, 3, spaced);
        if (hit != null) { return hit; }
      }
      null
    }

    let casesRefCps(s: String): List<Int> {
      let out = new ListBuilder<Int>();
      var i = String.begin;
      while (s.hasIndex(i)) {
        out.add(s[i]);
        i = s.next(i);
      }
      out.toList()
    }

    let casesRefText(cps: List<Int>, from: Int, to: Int): String {
      let parts = new ListBuilder<String>();
      var i = from;
      while (i < to) {
        parts.add(String.fromCodePoint(cps[i]) orelse "");
        i += 1;
      }
      sysJoin(parts.toList(), "")
    }

## `casesResolveRefs`

`aName` and `bName` are what A and B stand for (the display names, i.e.
`casesName` of the two titles). `null` text is the caller's business; a
rationale that is not there is not resolved.

    export let casesResolveRefs(text: String, aName: String, bName: String): String {
      let cps = casesRefCps(text);
      let out = new ListBuilder<String>();
      var copied = 0;
      var p = 0;
      while (p < cps.length) {
        let hit = casesRefAt(cps, p);
        if (hit == null) {
          p += 1;
        } else {
          out.add(casesRefText(cps, copied, p));
          let who = if (hit.letter == 65) { aName } else { bName };
          let pre = casesRefText(cps, p, hit.preEnd);
          let poss = casesRefText(cps, hit.preEnd + 1, hit.possEnd);
          let possessive = hit.possEnd > hit.preEnd + 1;
          if (hit.kind == 1) {
            out.add(who);
            if (possessive) { out.add(poss); }
          } else if (possessive) {
            out.add(pre);
            out.add(who);
            out.add(poss);
          } else if (hit.kind == 0 || hit.kind == 2) {
            out.add(pre);
            out.add(who);
          } else {
            out.add(casesRefText(cps, p, hit.end));
          }
          copied = hit.end;
          p = hit.end;
        }
      }
      out.add(casesRefText(cps, copied, cps.length));
      sysJoin(out.toList(), "")
    }
