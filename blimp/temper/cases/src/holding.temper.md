# What the Court held, in the Court's own words

`Marginalia.Cases.holding/1`. Not the syllabus: the Reporter's headnote is
the obvious source and the wrong one. It is not part of the opinion and
carries no authority; every slip opinion says so on its first page. So the
holding is lifted from the opinion, verbatim, and shown as a quotation.
Three of sixteen opinions never state it in one sentence, and those get
nothing at all: a passage that cannot be found is not shown.

The Elixir did this with four regular expressions over the opinion with its
whitespace collapsed. There is no regex engine worth running over an 80 KB
opinion here, so each expression is matched by hand, in a way that never
looks at more of the document than a handful of keyword occurrences:

    let { isUnicodeLetter, isUnicodeNumber } = import("core/src");
    let { sysStringReplace, sysStringTrim, sysJoin } = import("sys/src");
    let { Work } = import("works/src");

The four, in the order the phrasings actually commit to a holding
("Accordingly, ..." is not among them because it is as often a transition as
a conclusion). The first one that matches wins, wherever it sits in the text;
within one, the leftmost match wins.

1. `\b[Ww]e (?:therefore |accordingly |now )?hold that\b[^.]{20,300}\.`
2. `\b[Ww]e (?:therefore |accordingly |now )?conclude that\b[^.]{20,300}\.`
3. `\b[Ww]e (?:hold|conclude)\b[^.]{20,300}\.`
4. `\bWe (?:therefore |accordingly )?(?:reverse|affirm|vacate)\b[^.]{10,300}\.`

## Small pieces

    let casesCodePoints(s: String): List<Int> {
      let out = new ListBuilder<Int>();
      var i = String.begin;
      while (s.hasIndex(i)) {
        out.add(s[i]);
        i = s.next(i);
      }
      out.toList()
    }

    let casesFromCps(cps: List<Int>, from: Int, to: Int): String {
      let parts = new ListBuilder<String>();
      var i = from;
      while (i < to) {
        parts.add(String.fromCodePoint(cps[i]) orelse "");
        i += 1;
      }
      sysJoin(parts.toList(), "")
    }

    let casesIsWordCp(cp: Int): Boolean {
      isUnicodeLetter(cp) || isUnicodeNumber(cp) || cp == 95
    }

PCRE's `\s` without the `u` flag, which is how the Elixir wrote these:
space, tab, newline, vertical tab, form feed, carriage return.

    let casesIsAsciiSpace(cp: Int): Boolean {
      cp == 32 || (cp >= 9 && cp <= 13)
    }

`String.replace(body, ~r/\s+/, " ")`: every run of whitespace becomes one
space, including at the two ends (a body that starts with a newline starts
with a space).

    export let casesFlat(body: String): String {
      var s = body;
      s = sysStringReplace(s, "\r", " ");
      s = sysStringReplace(s, "\n", " ");
      s = sysStringReplace(s, "\t", " ");
      s = sysStringReplace(s, String.fromCodePoint(11) orelse " ", " ");
      s = sysStringReplace(s, String.fromCodePoint(12) orelse " ", " ");
      let kept = new ListBuilder<String>();
      let forList7 = s.split(" ");
      var forIdx7 = 0;
      while (forIdx7 < forList7.length) {
        let part = forList7[forIdx7];
        forIdx7 += 1;
        if (!part.isEmpty) { kept.add(part); }
      }
      let core = sysJoin(kept.toList(), " ");
      let leads = s.hasIndex(String.begin) && s[String.begin] == 32;
      let last = s.prev(s.end);
      let trails = s.hasIndex(last) && s[last] == 32;
      if (kept.length == 0) {
        if (leads) { " " } else { "" }
      } else if (leads && trails) {
        " ${core} "
      } else if (leads) {
        " ${core}"
      } else if (trails) {
        "${core} "
      } else {
        core
      }
    }

Where `tail` ends `s`, the index in `s` where it starts; none if `s` does not
end with it.

    let casesTailStart(s: String, tail: String): StringIndexOption {
      var i = s.end;
      var j = tail.end;
      while (j > String.begin) {
        if (i <= String.begin) { return StringIndex.none; }
        i = s.prev(i);
        j = tail.prev(j);
        if (s[i] != tail[j]) { return StringIndex.none; }
      }
      i
    }

## One keyword

What a match is: the text before the match (for widening to the start of the
sentence) and the match itself, `We hold that ... .`

    class CaseHit(public before: String, public matched: String) {}

`flat` is searched for `keyword`, each occurrence preceded by one of
`leaders` (each ending in a space) and followed by a non-word character; the
sentence must reach a full stop within `minRun` to `maxRun` characters of the
keyword. The first occurrence that qualifies is the leftmost match, because
occurrences are in text order and a leader holds no keyword.

    let casesFindHold(
      flat: String, leaders: List<String>, keyword: String, minRun: Int, maxRun: Int,
    ): CaseHit? {
      let pieces = flat.split(keyword);
      var j = 0;
      while (j + 1 < pieces.length) {
        let left = pieces[j];
        let rest = pieces[j + 1];
        var afterOk = true;
        if (rest.hasIndex(String.begin)) {
          afterOk = !casesIsWordCp(rest[String.begin]);
        } else if (j + 2 < pieces.length) {
          afterOk = false;
        }
        if (afterOk) {
          var run = rest;
          var k = j + 1;
          while (run.split(".").length < 2 && k + 1 < pieces.length) {
            run = "${run}${keyword}${pieces[k + 1]}";
            k += 1;
          }
          let dotted = run.split(".");
          if (dotted.length >= 2) {
            let first = dotted[0];
            let span = first.countBetween(String.begin, first.end);
            if (span >= minRun && span <= maxRun) {
              var li = 0;
              while (li < leaders.length) {
                let leader = leaders[li];
                li += 1;
                let at = casesTailStart(left, leader);
                if (at is StringIndex) {
                  var leftOk = true;
                  if (at > String.begin) {
                    leftOk = !casesIsWordCp(left[left.prev(at)]);
                  } else if (j > 0) {
                    leftOk = false;
                  }
                  if (leftOk) {
                    let head = new ListBuilder<String>();
                    var h = 0;
                    while (h < j) {
                      head.add(pieces[h]);
                      h += 1;
                    }
                    head.add(left.slice(String.begin, at));
                    let before = if (j == 0) {
                      left.slice(String.begin, at)
                    } else {
                      sysJoin(head.toList(), keyword)
                    };
                    return new CaseHit(before, "${leader}${keyword}${first}.");
                  }
                }
              }
            }
          }
        }
        j += 1;
      }
      null
    }

The leftmost of several keywords' first matches (pattern 3 has two).

    let casesLeftmost(hits: List<CaseHit?>): CaseHit? {
      var best: CaseHit? = null;
      var bestAt = -1;
      let forList8 = hits;
      var forIdx8 = 0;
      while (forIdx8 < forList8.length) {
        let hit = forList8[forIdx8];
        forIdx8 += 1;
        if (hit != null) {
          let at = hit.before.countBetween(String.begin, hit.before.end);
          if (best == null || at < bestAt) {
            best = hit;
            bestAt = at;
          }
        }
      }
      best
    }

    let casesLeaders(subject: List<String>, advs: List<String>): List<String> {
      let out = new ListBuilder<String>();
      var i = 0;
      while (i < subject.length) {
        var j = 0;
        while (j < advs.length) {
          out.add("${subject[i]} ${advs[j]}");
          j += 1;
        }
        i += 1;
      }
      out.toList()
    }

The first pattern of the four that matches anywhere.

    let casesFirstPattern(flat: String): CaseHit? {
      let advs = ["", "therefore ", "accordingly ", "now "];
      let both = ["We", "we"];
      let one = casesFindHold(flat, casesLeaders(both, advs), "hold that", 20, 300);
      if (one != null) { return one; }
      let two = casesFindHold(flat, casesLeaders(both, advs), "conclude that", 20, 300);
      if (two != null) { return two; }
      let plain = casesLeaders(both, [""]);
      let three = casesLeftmost([
        casesFindHold(flat, plain, "hold", 20, 300),
        casesFindHold(flat, plain, "conclude", 20, 300),
      ]);
      if (three != null) { return three; }
      casesLeftmost([
        casesFindHold(flat, casesLeaders(["We"], ["", "therefore ", "accordingly "]), "reverse", 10, 300),
        casesFindHold(flat, casesLeaders(["We"], ["", "therefore ", "accordingly "]), "affirm", 10, 300),
        casesFindHold(flat, casesLeaders(["We"], ["", "therefore ", "accordingly "]), "vacate", 10, 300),
      ])
    }

## Widening to the start of the sentence

"Because we conclude that Durnell's claim is preempted, we need not
consider..." matches at "we conclude", and quoting from there gives a
fragment that opens lowercase in the middle of a sentence. A verbatim quote
that starts mid-sentence undercuts the one thing it is for, so the match is
widened back to where the sentence began: just after the last
`[.!?]["”]?\s+` in what comes before.

    let casesIsStop(cp: Int): Boolean { cp == 46 || cp == 33 || cp == 63 }

    let casesIsQuote(cp: Int): Boolean { cp == 34 || cp == 8221 }

    let casesSentenceStart(before: String): StringIndex {
      var e = before.end;
      while (e > String.begin) {
        let p1 = before.prev(e);
        if (before[p1] == 32 && p1 > String.begin) {
          let p2 = before.prev(p1);
          let c2 = before[p2];
          if (casesIsStop(c2)) { return e; }
          if (casesIsQuote(c2) && p2 > String.begin) {
            if (casesIsStop(before[before.prev(p2)])) { return e; }
          }
        }
        e = p1;
      }
      String.begin
    }

## Division headings

A division heading has no full stop after it, so walking back to the sentence
start walks straight past "III" or "* * *" and takes it into the quotation.
A leading marker is stripped, again and again until none is left, with
`^\s*(?:[IVXL]{1,5}|[A-Z]|\d{1,2}|\*(?:\s*\*)*)[\s.]+`; if stripping would
leave nothing, the text before the last strip stands.

    let casesIsSep(cps: List<Int>, at: Int): Boolean {
      at < cps.length && (casesIsAsciiSpace(cps[at]) || cps[at] == 46)
    }

    let casesAfterSep(cps: List<Int>, from: Int): Int {
      var k = from;
      while (casesIsSep(cps, k)) { k += 1; }
      k
    }

    let casesIsRoman(cp: Int): Boolean { cp == 73 || cp == 86 || cp == 88 || cp == 76 }

Where the text after one marker and its separator begins, or -1 when `cps`
does not start (after optional whitespace) with a marker.

    let casesMarkerEnd(cps: List<Int>, from: Int): Int {
      var p = from;
      while (p < cps.length && casesIsAsciiSpace(cps[p])) { p += 1; }
      if (p >= cps.length) { return -1; }
      var r = 0;
      while (p + r < cps.length && casesIsRoman(cps[p + r])) { r += 1; }
      if (r >= 1 && r <= 5 && casesIsSep(cps, p + r)) { return casesAfterSep(cps, p + r); }
      if (cps[p] >= 65 && cps[p] <= 90 && casesIsSep(cps, p + 1)) { return casesAfterSep(cps, p + 1); }
      var d = 0;
      while (p + d < cps.length && cps[p + d] >= 48 && cps[p + d] <= 57) { d += 1; }
      if (d >= 1 && d <= 2 && casesIsSep(cps, p + d)) { return casesAfterSep(cps, p + d); }
      if (cps[p] == 42) {
        var q = p + 1;
        var more = true;
        while (more) {
          var t = q;
          while (t < cps.length && casesIsAsciiSpace(cps[t])) { t += 1; }
          if (t < cps.length && cps[t] == 42) { q = t + 1; } else { more = false; }
        }
        if (casesIsSep(cps, q)) { return casesAfterSep(cps, q); }
      }
      -1
    }

    let casesStripMarkers(text: String): String {
      let cps = casesCodePoints(text);
      var from = 0;
      var go = true;
      while (go) {
        let next = casesMarkerEnd(cps, from);
        if (next < 0 || next >= cps.length) { go = false; } else { from = next; }
      }
      if (from == 0) { text } else { casesFromCps(cps, from, cps.length) }
    }

## The holding

`holding(nil)` is nil. The opinion's whitespace is collapsed, the first of the
four patterns that matches is found, widened back to the start of its
sentence, stripped of division markers and trimmed. No match is nil: there is
no fallback.

    let casesHoldingFrom(hit: CaseHit): String {
      let before = hit.before;
      let start = casesSentenceStart(before);
      let text = "${before.slice(start, before.end)}${hit.matched}";
      sysStringTrim(casesStripMarkers(text))
    }

    export let casesHoldingText(body: String): String? {
      let hit = casesFirstPattern(casesFlat(body));
      if (hit != null) { casesHoldingFrom(hit) } else { null }
    }

    export let casesHolding(work: Work?): String? {
      if (work != null) { casesHoldingText(work.body) } else { null }
    }
