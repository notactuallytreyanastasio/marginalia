# A pattern language for title filters

The title-regex box takes a PCRE from the reader: `Regex.compile(pattern, "i")`
in the Elixir. Temper's `std/regex` builds expressions from a node DSL and
cannot read one from a string, so this is a small backtracking matcher for
the part of PCRE that a title filter uses, with the same error contract: a
half-typed pattern is the normal state of a regex box, and the page has to be
able to say what is wrong with it rather than crash.

Supported: literals, `.`, `[...]` with ranges and `^`, `\d \D \w \W \s \S`
(`\D \W \S` outside a class only), `\b \B ^ $ \A \z \Z`, `\n \t \r \f \e \a`,
`\xHH` and `\x{H...}`, escaped punctuation, `|`, `( )` and `(?: )`, and the
quantifiers `* + ? {n} {n,} {n,m}` with a lazy `?`. Always case-insensitive.

Refused by name, with the position, as PCRE refuses what it cannot parse:
back-references, lookaround and other `(?` groups, possessive quantifiers,
`\p`, POSIX classes. Where PCRE would match them, this says it cannot.

It differs from `:re` in two ways. It works on code points, not bytes, so `.`
is one character and a non-ASCII letter folds to its other case. And the match
is bounded by a step budget: a pattern that backtracks without end fails to
match rather than hanging, which is what truncating the title to 200
characters was for in the first place.

    let { sysUtf8Downcase } = import("sys/src");

## The tree

`kind` is one of `char` (`ch`, already folded), `any`, `set` (`ranges` as
lo/hi pairs, `negate`), `seq` and `alt` (`kids`), `group` (one kid), `rep`
(one kid, `min`, `max` with -1 for none, `greedy`), `bol`, `eol`, `wordb`,
`nwordb` and `empty`.

    export class ImporterRx(public kind: String) {
      public var ch: Int = 0;
      public var negate: Boolean = false;
      public var ranges: List<Int> = [];
      public var kids: List<ImporterRx> = [];
      public var min: Int = 0;
      public var max: Int = 0;
      public var greedy: Boolean = true;
    }

    let importerFoldCp(c: Int): Int {
      if (c >= 65 && c <= 90) {
        c + 32
      } else if (c < 128) {
        c
      } else {
        let lowered = importerCps(sysUtf8Downcase(importerChr(c)));
        if (lowered.length == 1) { lowered[0] } else { c }
      }
    }

    let importerRxChar(c: Int): ImporterRx {
      let n = new ImporterRx("char");
      n.ch = importerFoldCp(c);
      n
    }

    let importerRxSet(ranges: List<Int>, negate: Boolean): ImporterRx {
      let n = new ImporterRx("set");
      n.ranges = ranges;
      n.negate = negate;
      n
    }

    let importerDigitRanges(): List<Int> { [48, 57] }

    let importerWordRanges(): List<Int> { [48, 57, 65, 90, 95, 95, 97, 122] }

    let importerSpaceRanges(): List<Int> { [9, 13, 32, 32] }

## The parser

    class ImporterRxParser(public cps: List<Int>) {
      public var pos: Int = 0;
      public var error: String = "";
      public var depth: Int = 0;

      public fail(message: String, position: Int): ImporterRx {
        if (error.isEmpty) {
          error = "${message} at character ${position.toString()}";
        }
        new ImporterRx("empty")
      }

      public peek(): Int {
        if (pos < cps.length) { cps[pos] } else { -1 }
      }

      public parseAlt(): ImporterRx {
        let branches = new ListBuilder<ImporterRx>();
        branches.add(parseSeq());
        while (error.isEmpty && peek() == 124) {
          pos += 1;
          branches.add(parseSeq());
        }
        if (branches.length == 1) {
          branches[0]
        } else {
          let n = new ImporterRx("alt");
          n.kids = branches.toList();
          n
        }
      }

      public parseSeq(): ImporterRx {
        let items = new ListBuilder<ImporterRx>();
        var going = true;
        while (going && error.isEmpty && pos < cps.length && peek() != 124) {
          if (peek() == 41) {
            if (depth == 0) { fail("unmatched parentheses", pos); }
            going = false;
          } else {
            items.add(parseQuantified());
          }
        }
        let n = new ImporterRx("seq");
        n.kids = items.toList();
        n
      }

      public parseQuantified(): ImporterRx {
        let atom = parseAtom();
        if (!error.isEmpty || pos >= cps.length) { return atom; }
        let c = peek();
        var min = -1;
        var max = -1;
        if (c == 42) {
          min = 0;
          pos += 1;
        } else if (c == 43) {
          min = 1;
          pos += 1;
        } else if (c == 63) {
          min = 0;
          max = 1;
          pos += 1;
        } else if (c == 123) {
          let q = braceQuantifier(pos);
          if (q.length == 3) {
            if (q[0] > q[1] && q[1] >= 0) {
              return fail("numbers out of order in {} quantifier", q[2]);
            }
            if (q[0] > 1000 || q[1] > 1000) {
              return fail("number too big in {} quantifier", q[2]);
            }
            min = q[0];
            max = q[1];
            pos = q[2];
          }
        }
        if (min < 0) { return atom; }
        let rep = new ImporterRx("rep");
        rep.kids = [atom];
        rep.min = min;
        rep.max = max;
        if (peek() == 63) {
          rep.greedy = false;
          pos += 1;
        } else if (peek() == 43) {
          return fail("possessive quantifiers are not supported", pos);
        }
        let d = peek();
        if (d == 42 || d == 43 || d == 63) {
          return fail("quantifier does not follow a repeatable item", pos);
        }
        rep
      }

`{n}`, `{n,}` or `{n,m}` at `at`: the minimum, the maximum (-1 for none) and the
position after the `}`; an empty list when it is not a quantifier, and then
the brace is a literal.

      public braceQuantifier(at: Int): List<Int> {
        var i = at + 1;
        var lo = 0;
        var digits = 0;
        while (i < cps.length && importerIsDigit(cps[i]) && digits < 6) {
          lo = lo * 10 + (cps[i] - 48);
          digits += 1;
          i += 1;
        }
        if (digits == 0) { return []; }
        if (i >= cps.length) { return []; }
        if (cps[i] == 125) { return [lo, lo, i + 1]; }
        if (cps[i] != 44) { return []; }
        i += 1;
        var hi = 0;
        var hiDigits = 0;
        while (i < cps.length && importerIsDigit(cps[i]) && hiDigits < 6) {
          hi = hi * 10 + (cps[i] - 48);
          hiDigits += 1;
          i += 1;
        }
        if (i >= cps.length || cps[i] != 125) { return []; }
        if (hiDigits == 0) { [lo, -1, i + 1] } else { [lo, hi, i + 1] }
      }

      public parseAtom(): ImporterRx {
        let c = cps[pos];
        let at = pos;
        if (c == 40) {
          pos += 1;
          if (peek() == 63) {
            pos += 1;
            if (peek() == 58) {
              pos += 1;
            } else {
              return fail("unrecognized character after (? or (?-", pos);
            }
          }
          depth += 1;
          let inner = parseAlt();
          depth -= 1;
          if (!error.isEmpty) { return inner; }
          if (peek() != 41) { return fail("missing )", cps.length); }
          pos += 1;
          let g = new ImporterRx("group");
          g.kids = [inner];
          return g;
        }
        if (c == 91) { return parseClass(); }
        if (c == 46) {
          pos += 1;
          return new ImporterRx("any");
        }
        if (c == 94) {
          pos += 1;
          return new ImporterRx("bol");
        }
        if (c == 36) {
          pos += 1;
          return new ImporterRx("eol");
        }
        if (c == 92) { return parseEscape(); }
        if (c == 42 || c == 43 || c == 63) {
          return fail("quantifier does not follow a repeatable item", at);
        }
        if (c == 123) {
          if (braceQuantifier(pos).length == 3) {
            return fail("quantifier does not follow a repeatable item", at);
          }
        }
        pos += 1;
        importerRxChar(c)
      }

      public hexValue(c: Int): Int {
        if (c >= 48 && c <= 57) { return c - 48; }
        if (c >= 65 && c <= 70) { return c - 55; }
        if (c >= 97 && c <= 102) { return c - 87; }
        -1
      }

`\xHH` or `\x{H...}`, `pos` just after the `x`; the code point, or -1.

      public parseHexEscape(): Int {
        var n = 0;
        if (peek() == 123) {
          pos += 1;
          var digits = 0;
          while (pos < cps.length && hexValue(cps[pos]) >= 0 && digits < 6) {
            n = n * 16 + hexValue(cps[pos]);
            digits += 1;
            pos += 1;
          }
          if (digits == 0 || peek() != 125) { return -1; }
          pos += 1;
          return n;
        }
        var digits = 0;
        while (pos < cps.length && hexValue(cps[pos]) >= 0 && digits < 2) {
          n = n * 16 + hexValue(cps[pos]);
          digits += 1;
          pos += 1;
        }
        n
      }

      public parseEscape(): ImporterRx {
        let start = pos;
        if (pos + 1 >= cps.length) { return fail("\\ at end of pattern", cps.length); }
        let e = cps[pos + 1];
        pos += 2;
        if (e == 100) { return importerRxSet(importerDigitRanges(), false); }
        if (e == 68) { return importerRxSet(importerDigitRanges(), true); }
        if (e == 119) { return importerRxSet(importerWordRanges(), false); }
        if (e == 87) { return importerRxSet(importerWordRanges(), true); }
        if (e == 115) { return importerRxSet(importerSpaceRanges(), false); }
        if (e == 83) { return importerRxSet(importerSpaceRanges(), true); }
        if (e == 98) { return new ImporterRx("wordb"); }
        if (e == 66) { return new ImporterRx("nwordb"); }
        if (e == 65) { return new ImporterRx("bol"); }
        if (e == 122 || e == 90) { return new ImporterRx("eol"); }
        if (e == 110) { return importerRxChar(10); }
        if (e == 116) { return importerRxChar(9); }
        if (e == 114) { return importerRxChar(13); }
        if (e == 102) { return importerRxChar(12); }
        if (e == 101) { return importerRxChar(27); }
        if (e == 97) { return importerRxChar(7); }
        if (e == 120) {
          let v = parseHexEscape();
          if (v < 0) { return fail("invalid \\x escape", pos); }
          return importerRxChar(v);
        }
        if (e >= 49 && e <= 57) { return fail("back-references are not supported", start + 1); }
        if (importerIsWordChar(e)) {
          return fail("unsupported or unrecognized escape \\${importerChr(e)}", start + 1);
        }
        importerRxChar(e)
      }

      public parseClass(): ImporterRx {
        let open = pos;
        pos += 1;
        var negate = false;
        if (peek() == 94) {
          negate = true;
          pos += 1;
        }
        let ranges = new ListBuilder<Int>();
        var first = true;
        var closed = false;
        while (!closed && error.isEmpty && pos < cps.length) {
          let c = cps[pos];
          if (c == 93 && !first) {
            closed = true;
            pos += 1;
          } else {
            first = false;
            if (c == 91 && pos + 1 < cps.length && cps[pos + 1] == 58) {
              return fail("POSIX character classes are not supported", pos);
            }
            var lo = c;
            pos += 1;
            if (c == 92) {
              if (pos >= cps.length) { return fail("\\ at end of pattern", cps.length); }
              let e = cps[pos];
              pos += 1;
              if (e == 100) {
                addAll(ranges, importerDigitRanges());
                lo = -1;
              } else if (e == 119) {
                addAll(ranges, importerWordRanges());
                lo = -1;
              } else if (e == 115) {
                addAll(ranges, importerSpaceRanges());
                lo = -1;
              } else if (e == 68 || e == 87 || e == 83) {
                return fail("negated shorthand classes inside [] are not supported", pos - 2);
              } else if (e == 110) {
                lo = 10;
              } else if (e == 116) {
                lo = 9;
              } else if (e == 114) {
                lo = 13;
              } else if (e == 102) {
                lo = 12;
              } else if (e == 98) {
                lo = 8;
              } else if (importerIsWordChar(e)) {
                return fail("unsupported or unrecognized escape \\${importerChr(e)}", pos - 1);
              } else {
                lo = e;
              }
            }
            if (lo >= 0) {
              var hi = lo;
              if (peek() == 45 && pos + 1 < cps.length && cps[pos + 1] != 93) {
                pos += 1;
                hi = cps[pos];
                pos += 1;
                if (hi == 92 && pos < cps.length) {
                  hi = cps[pos];
                  pos += 1;
                }
                if (hi < lo) { return fail("range out of order in character class", pos - 1); }
              }
              ranges.add(lo);
              ranges.add(hi);
            }
          }
        }
        if (!closed && error.isEmpty) {
          return fail("missing terminating ] for character class", cps.length);
        }
        importerRxSet(ranges.toList(), negate)
      }

      public addAll(into: ListBuilder<Int>, more: List<Int>): Void {
        var i = 0;
        while (i < more.length) {
          into.add(more[i]);
          i += 1;
        }
      }
    }

## Compiling

    export class ImporterRegex(public root: ImporterRx?, public error: String) {}

PCRE's message shape, which the page shows as-is: `reason at character N`.

    export let importerRegexCompile(pattern: String): ImporterRegex {
      let parser = new ImporterRxParser(importerCps(pattern));
      let root = parser.parseAlt();
      if (parser.error.isEmpty && parser.pos < parser.cps.length) {
        parser.fail("unmatched parentheses", parser.pos);
      }
      if (parser.error.isEmpty) {
        new ImporterRegex(root, "")
      } else {
        new ImporterRegex(null, parser.error)
      }
    }

## Matching

The text twice: as it is, for classes and word boundaries, and folded, for
literals. `steps` counts every node visited; past `limit` everything fails.

    class ImporterRxMatcher(public orig: List<Int>, public folded: List<Int>) {
      public var steps: Int = 0;
      public var limit: Int = 50000;

      public isWord(i: Int): Boolean {
        i >= 0 && i < orig.length && importerIsWordChar(orig[i])
      }

      public inRanges(ranges: List<Int>, c: Int): Boolean {
        var i = 0;
        while (i + 1 < ranges.length) {
          if (c >= ranges[i] && c <= ranges[i + 1]) { return true; }
          i += 2;
        }
        false
      }

A set matches when the character, its lower case or its upper case is in it.

      public setHas(node: ImporterRx, i: Int): Boolean {
        let c = orig[i];
        var hit = inRanges(node.ranges, c) || inRanges(node.ranges, folded[i]);
        if (!hit && folded[i] >= 97 && folded[i] <= 122) {
          hit = inRanges(node.ranges, folded[i] - 32);
        }
        hit != node.negate
      }

      public m(node: ImporterRx, i: Int, k: fn (Int): Boolean): Boolean {
        steps += 1;
        if (steps > limit) { return false; }
        let kind = node.kind;
        let n = orig.length;
        if (kind == "char") {
          return i < n && folded[i] == node.ch && k(i + 1);
        }
        if (kind == "any") { return i < n && orig[i] != 10 && k(i + 1); }
        if (kind == "set") { return i < n && setHas(node, i) && k(i + 1); }
        if (kind == "bol") { return i == 0 && k(i); }
        if (kind == "eol") { return i == n && k(i); }
        if (kind == "wordb") { return isWord(i - 1) != isWord(i) && k(i); }
        if (kind == "nwordb") { return isWord(i - 1) == isWord(i) && k(i); }
        if (kind == "group") { return m(node.kids[0], i, k); }
        if (kind == "alt") {
          var a = 0;
          while (a < node.kids.length) {
            if (m(node.kids[a], i, k)) { return true; }
            a += 1;
          }
          return false;
        }
        if (kind == "seq") { return seq(node.kids, 0, i, k); }
        if (kind == "rep") { return rep(node, 0, i, k); }
        k(i)
      }

      public seq(kids: List<ImporterRx>, at: Int, i: Int, k: fn (Int): Boolean): Boolean {
        if (at >= kids.length) {
          k(i)
        } else {
          m(kids[at], i, fn (j: Int): Boolean { seq(kids, at + 1, j, k) })
        }
      }

An iteration that consumed nothing ends the loop, as PCRE's does, so `(a*)*`
terminates.

      public rep(node: ImporterRx, count: Int, i: Int, k: fn (Int): Boolean): Boolean {
        steps += 1;
        if (steps > limit) { return false; }
        let canMore = node.max < 0 || count < node.max;
        if (node.greedy) {
          if (canMore) {
            let more = m(node.kids[0], i, fn (j: Int): Boolean {
              if (j == i) {
                count + 1 >= node.min && k(j)
              } else {
                rep(node, count + 1, j, k)
              }
            });
            if (more) { return true; }
          }
          count >= node.min && k(i)
        } else {
          if (count >= node.min && k(i)) { return true; }
          if (!canMore) { return false; }
          m(node.kids[0], i, fn (j: Int): Boolean {
            if (j == i) {
              count + 1 >= node.min && k(j)
            } else {
              rep(node, count + 1, j, k)
            }
          })
        }
      }
    }

`Regex.match?/2`: whether the pattern matches anywhere in `text`.

    export let importerRegexMatches(re: ImporterRegex, text: String): Boolean {
      let root = re.root;
      if (root != null) {
        importerSearchRx(root, text)
      } else {
        false
      }
    }

    let importerSearchRx(root: ImporterRx, text: String): Boolean {
      let orig = importerCps(text);
      let folded = new ListBuilder<Int>();
      var i = 0;
      while (i < orig.length) {
        folded.add(importerFoldCp(orig[i]));
        i += 1;
      }
      let matcher = new ImporterRxMatcher(orig, folded.toList());
      var start = 0;
      while (start <= orig.length && matcher.steps <= matcher.limit) {
        if (matcher.m(root, start, fn (j: Int): Boolean { true })) { return true; }
        start += 1;
      }
      false
    }
