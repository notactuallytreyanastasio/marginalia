# Kinship: which cases are about the same thing

`Marginalia.Cases.Kinship`, pure. There is no caller in the Elixir `lib/`;
the tests are its only user, so this is a port of the scoring and nothing
else (the moduledoc mentions a `terms_for/1` that was never written; it is
not invented here either).

Each document becomes the bag of terms its own read pass used; pairs are
scored on the distinctive terms they share. Distinctive is doing the work:
a term in one document alone cannot be shared, and a term in more than a
third of them is furniture.

Nothing here calls a model.

    let { isUnicodeLetter } = import("core/src");
    let { sysUtf8Downcase, sysJoin } = import("sys/src");

## Text helpers

Byte-wise comparison of two strings by code point; -1, 0 or 1. Used wherever
a list of strings has to come out in a fixed order.

    export let casesCompareText(a: String, b: String): Int {
      var i = String.begin;
      var j = String.begin;
      while (a.hasIndex(i) && b.hasIndex(j)) {
        let x = a[i];
        let y = b[j];
        if (x < y) { return -1; }
        if (x > y) { return 1; }
        i = a.next(i);
        j = b.next(j);
      }
      if (a.hasIndex(i)) {
        1
      } else if (b.hasIndex(j)) {
        -1
      } else {
        0
      }
    }

## The constants

`@min_df 2`, `@max_share 0.33`, `@min_len 5`, `@min_tf 2`.

    let casesMinDf(): Int { 2 }
    let casesMaxShare(): Float64 { 0.33 }
    let casesMinLen(): Int { 5 }
    let casesMinTf(): Int { 2 }

The stop list, `@stop`, in the Elixir's order.

    let casesStopWords(): List<String> {
      [
        "about", "above", "after", "again", "against", "all", "also", "and", "any", "are", "because", "been", "before",
        "being", "below", "between", "both", "but", "cannot", "could", "did", "does", "doing", "down", "during", "each",
        "few", "for", "from", "further", "had", "has", "have", "having", "her", "here", "hers", "him", "his", "how", "into",
        "its", "itself", "more", "most", "nor", "not", "now", "off", "once", "only", "other", "ought", "our", "out", "over",
        "own", "same", "she", "should", "some", "such", "than", "that", "the", "their", "them", "then", "there", "these",
        "they", "this", "those", "through", "too", "under", "until", "very", "was", "were", "what", "when", "where",
        "which", "while", "who", "whom", "why", "will", "with", "would", "you", "your",
        "court", "courts", "case", "cases", "opinion", "opinions", "held", "holding", "justice", "justices",
        "argument", "arguments", "dissent", "dissents", "concurrence", "majority",
        "section", "sections", "paragraph", "draft", "manuscript", "reader", "writing", "writes",
        "argues", "argued", "argue", "claims", "claim", "point", "points", "question", "questions",
        "says", "said", "say", "reads", "read", "whether", "because", "therefore", "however",
      ]
    }

    let casesStopSet(): Map<String, Boolean> {
      let m = new MapBuilder<String, Boolean>();
      let words = casesStopWords();
      var i = 0;
      while (i < words.length) {
        m.set(words[i], true);
        i += 1;
      }
      m.toMap()
    }

## `terms`

The word is a list of code points while it is being judged: all of its
characters are letters, so its length in code points is its length in
graphemes except where a combining mark follows a letter, and a combining
mark is not a letter (the Elixir's `\p{L}`), so it ends the word in both.

`singular`: `-ies` (over five long) becomes `-y`, `-sses` loses two,
`-s` not after another `s` loses one. A stemmer is more machinery than the
difference is worth.

    let casesEndsWith(cps: List<Int>, suffix: List<Int>): Boolean {
      if (cps.length < suffix.length) { return false; }
      var k = 0;
      while (k < suffix.length) {
        if (cps[cps.length - suffix.length + k] != suffix[k]) { return false; }
        k += 1;
      }
      true
    }

    let casesWordText(cps: List<Int>, count: Int, tail: String): String {
      let parts = new ListBuilder<String>();
      var i = 0;
      while (i < count) {
        parts.add(String.fromCodePoint(cps[i]) orelse "");
        i += 1;
      }
      parts.add(tail);
      sysJoin(parts.toList(), "")
    }

    let casesSingular(cps: List<Int>): String {
      let n = cps.length;
      if (casesEndsWith(cps, [105, 101, 115]) && n > 5) {
        casesWordText(cps, n - 3, "y")
      } else if (casesEndsWith(cps, [115, 115, 101, 115])) {
        casesWordText(cps, n - 2, "")
      } else if (casesEndsWith(cps, [115]) && !casesEndsWith(cps, [115, 115])) {
        casesWordText(cps, n - 1, "")
      } else {
        casesWordText(cps, n, "")
      }
    }

`terms(text_parts)`: drop null and empty parts, join with a space, lower-case,
treat anything that is not a letter as a space (digits, underscores and
punctuation vanish), singular each word, drop words shorter than five or on
the stop list, keep words used at least twice. The result is a set, here a
list of distinct terms in code-point order.

    export let casesKinshipTerms(parts: List<String?>): List<String> {
      let kept = new ListBuilder<String>();
      let forList1 = parts;
      var forIdx1 = 0;
      while (forIdx1 < forList1.length) {
        let part = forList1[forIdx1];
        forIdx1 += 1;
        if (part != null) {
          if (part != "") { kept.add(part); }
        }
      }
      let text = sysUtf8Downcase(sysJoin(kept.toList(), " "));
      let stop = casesStopSet();
      let counts = new MapBuilder<String, Int>();
      let order = new ListBuilder<String>();
      let cps = new ListBuilder<Int>();
      var i = String.begin;
      var more = true;
      while (more) {
        let atEnd = !text.hasIndex(i);
        var letter = false;
        if (!atEnd) { letter = isUnicodeLetter(text[i]); }
        if (letter) {
          cps.add(text[i]);
        } else if (cps.length > 0) {
          let word = casesSingular(cps.toList());
          cps.clear();
          if (!stop.has(word)) {
            var len = 0;
            var j = String.begin;
            while (word.hasIndex(j)) { len += 1; j = word.next(j); }
            if (len >= casesMinLen()) {
              if (counts.has(word)) {
                counts.set(word, counts.getOr(word, 0) + 1);
              } else {
                counts.set(word, 1);
                order.add(word);
              }
            }
          }
        }
        if (atEnd) {
          more = false;
        } else {
          i = text.next(i);
        }
      }
      let out = new ListBuilder<String>();
      let forList2 = order.toList();
      var forIdx2 = 0;
      while (forIdx2 < forList2.length) {
        let w = forList2[forIdx2];
        forIdx2 += 1;
        if (counts.getOr(w, 0) >= casesMinTf()) { out.add(w); }
      }
      out.toList().sorted { (a: String, b: String): Int => casesCompareText(a, b) }
    }

## `pairs`

    export class KinshipScore(
      public a: Int,
      public b: Int,
      public score: Float64,
      public shared: List<String>,
    ) {}

    class KinshipTerm(public term: String, public weight: Float64) {}

`bags` is `id -> terms` (the lists `casesKinshipTerms` returns; a term is
counted once per bag, so a caller passing duplicates should not).
`n` is the number of bags; `df[t]` the number containing `t`;
`max_df = max(trunc(n * 0.33), 2)`; a term is kept when
`2 <= df <= max_df` and weighs `ln(n / df)`. For every pair of ids `a < b`,
`weight` is the sum over the kept terms both share, `size` is
`sqrt(|a| * |b|)` (the bags' sizes before filtering) and `score` is
`weight / size`. A zero score is no pair. Best first, at most `limit`;
`shared` is the shared terms by weight descending (ties by term, which the
Elixir left unspecified), the first eight.

    export let casesKinshipPairs(bags: Map<Int, List<String>>, limit: Int): List<KinshipScore> throws Bubble {
      let n = bags.length;
      let ids = bags.keys().toList().sorted { (x: Int, y: Int): Int => x - y };
      let df = new MapBuilder<String, Int>();
      let members = new MapBuilder<Int, Map<String, Boolean>>();
      let forList3 = ids;
      var forIdx3 = 0;
      while (forIdx3 < forList3.length) {
        let id = forList3[forIdx3];
        forIdx3 += 1;
        let terms = bags.getOr(id, []);
        let set = new MapBuilder<String, Boolean>();
        let forList4 = terms;
        var forIdx4 = 0;
        while (forIdx4 < forList4.length) {
          let t = forList4[forIdx4];
          forIdx4 += 1;
          set.set(t, true);
          df.set(t, df.getOr(t, 0) + 1);
        }
        members.set(id, set.toMap());
      }
      let share = (n.toFloat64() * casesMaxShare()).toInt32Unsafe();
      let maxDf = if (share > casesMinDf()) { share } else { casesMinDf() };
      let keep = new MapBuilder<String, Float64>();
      let forList5 = df.keys().toList();
      var forIdx5 = 0;
      while (forIdx5 < forList5.length) {
        let t = forList5[forIdx5];
        forIdx5 += 1;
        let c = df.getOr(t, 0);
        if (c >= casesMinDf() && c <= maxDf) {
          keep.set(t, (n.toFloat64() / c.toFloat64()).log());
        }
      }
      let out = new ListBuilder<KinshipScore>();
      var x = 0;
      while (x < ids.length) {
        var y = x + 1;
        while (y < ids.length) {
          let a = ids[x];
          let b = ids[y];
          let termsA = bags.getOr(a, []);
          let inB = members.getOr(b, new MapBuilder<String, Boolean>().toMap());
          let shared = new ListBuilder<KinshipTerm>();
          var weight = 0.0;
          let forList6 = termsA;
          var forIdx6 = 0;
          while (forIdx6 < forList6.length) {
            let t = forList6[forIdx6];
            forIdx6 += 1;
            if (inB.has(t) && keep.has(t)) {
              let w = keep.getOr(t, 0.0);
              shared.add(new KinshipTerm(t, w));
              weight += w;
            }
          }
          let sizeB = bags.getOr(b, []).length;
          let size = (termsA.length.toFloat64() * sizeB.toFloat64()).sqrt();
          let score = if (size > 0.0) { weight / size } else { 0.0 };
          if (score != 0.0) {
            let ranked = shared.toList().sorted { (p: KinshipTerm, q: KinshipTerm): Int =>
              if (p.weight > q.weight) { -1 } else if (p.weight < q.weight) { 1 } else { casesCompareText(p.term, q.term) }
            };
            let names = new ListBuilder<String>();
            var k = 0;
            while (k < ranked.length && k < 8) {
              names.add(ranked[k].term);
              k += 1;
            }
            out.add(new KinshipScore(a, b, score, names.toList()));
          }
          y += 1;
        }
        x += 1;
      }
      let best = out.toList().sorted { (p: KinshipScore, q: KinshipScore): Int =>
        if (p.score > q.score) {
          -1
        } else if (p.score < q.score) {
          1
        } else if (p.a != q.a) {
          p.a - q.a
        } else {
          p.b - q.b
        }
      };
      let top = new ListBuilder<KinshipScore>();
      var m = 0;
      while (m < best.length && m < limit) {
        top.add(best[m]);
        m += 1;
      }
      top.toList()
    }
