# Tests for kinship

`test/marginalia/kinship_test.exs`, ported assertion for assertion, then the
rules the module states and the test leaves to the reader: the stop list and
the length rule, the plural rules one by one, and the order pairs come out in.

The first attempt scored the read pass's own commentary, which has one author
across every document, so it measured writing style: the top pairs shared
"inversion", "breath" and "demolition". Scoring the anchored quotes instead
scores the judges' own words.

    let bag(text: String): List<String> {
      casesKinshipTerms([text])
    }

    let has(terms: List<String>, term: String): Boolean {
      var i = 0;
      while (i < terms.length) {
        if (terms[i] == term) { return true; }
        i += 1;
      }
      false
    }

    let bagsOf(entries: List<List<String>>): Map<Int, List<String>> {
      let m = new MapBuilder<Int, List<String>>();
      var i = 0;
      while (i < entries.length) {
        m.set(i + 1, entries[i]);
        i += 1;
      }
      m.toMap()
    }

    let sortedIds(p: KinshipScore): String {
      if (p.a < p.b) { "${p.a.toString()},${p.b.toString()}" } else { "${p.b.toString()},${p.a.toString()}" }
    }

    let pairNamed(ps: List<KinshipScore>, ids: String): KinshipScore? {
      var i = 0;
      while (i < ps.length) {
        if (sortedIds(ps[i]) == ids) { return ps[i]; }
        i += 1;
      }
      null
    }

    let pairIds(ps: List<KinshipScore>): List<String> {
      ps.map { (p: KinshipScore): String => sortedIds(p) }
    }

## terms

    let usedOnceCheck(test: Test): Void {
      expectTrue(test, has(bag("removal removal of officers"), "removal"), "twice is about");
      expectFalse(test, has(bag("removal of officers"), "removal"), "once is not about");
    }

    test("a word used once is not what a document is about") { test => usedOnceCheck(test); }

    let pluralsCheck(test: Test): Void {
      expectTrue(test, has(bag("warrants and warrant"), "warrant"), "warrants and warrant are one word");
      expectTrue(test, has(bag("agencies and agency policies policies"), "agency"), "agencies is agency");
    }

    test("plurals and singulars are the same word") { test => pluralsCheck(test); }

    let furnitureCheck(test: Test): Void {
      let terms = bag("the court held that the court held that the opinion says the opinion says");
      expectInt(test, terms.length, 0);
    }

    test("furniture is dropped") { test => furnitureCheck(test); }

    let shortCheck(test: Test): Void {
      expectFalse(test, has(bag("the writ the writ"), "writ"), "four letters is short");
    }

    test("short words are dropped") { test => shortCheck(test); }

The singular rules, one by one: `-ies` over five long becomes `-y`, `-sses`
loses two letters, `-s` after anything but another `s` loses one.

    let singularCheck(test: Test): Void {
      expectText(test, joined(bag("studies studies")), "study");
      expectText(test, joined(bag("classes classes")), "class");
      expectText(test, joined(bag("class class")), "class");
      expectText(test, joined(bag("statutes statutes")), "statute");
      expectText(test, joined(bag("pies pies")), "");
    }

    test("the three plural rules") { test => singularCheck(test); }

    let digitsCheck(test: Test): Void {
      expectText(test, joined(bag("unique_one unique_one")), "unique");
      expectText(test, joined(bag("filler12 filler7 filler")), "filler");
      expectText(test, joined(bag("well-known well-known")), "known");
    }

Digits and underscores and punctuation vanish: they split a word, they do
not belong to it. "well-known" is "well" (four letters, short) and "known"
(five).

    test("digits, underscores and punctuation separate words") { test => digitsCheck(test); }

    let partsCheck(test: Test): Void {
      let parts = new ListBuilder<String?>();
      parts.add(null);
      parts.add("");
      parts.add("removal removal");
      parts.add(null);
      parts.add("");
      parts.add("removal");
      expectText(test, joined(casesKinshipTerms(parts.toList())), "removal");
      expectInt(test, casesKinshipTerms(new ListBuilder<String?>().toList()).length, 0);
      let blanks = new ListBuilder<String?>();
      blanks.add(null);
      blanks.add("");
      expectInt(test, casesKinshipTerms(blanks.toList()).length, 0);
    }

    test("empty and missing parts are dropped before the join") { test => partsCheck(test); }

    let caseCheck(test: Test): Void {
      expectText(test, joined(bag("Removal REMOVAL removal")), "removal");
      expectText(test, joined(bag("naïveté Naïveté")), "naïveté");
    }

    test("case is folded, and accented letters are letters") { test => caseCheck(test); }

    let orderCheck(test: Test): Void {
      expectText(test, joined(bag("zebra zebra apple apple middle middle")), "apple,middle,zebra");
    }

    test("terms come out in code point order") { test => orderCheck(test); }

    let stopCheck(test: Test): Void {
      let stopped = [
        "court", "opinion", "dissent", "concurrence", "majority", "argument", "whether", "therefore",
        "however", "justice", "holding", "section", "draft", "manuscript", "reader", "question",
      ];
      var i = 0;
      while (i < stopped.length) {
        expectFalse(test, has(bag("${stopped[i]} ${stopped[i]}"), stopped[i]), "stop word ${stopped[i]}");
        i += 1;
      }
    }

    test("the stop list is the one the Elixir had") { test => stopCheck(test); }

## pairs

Two pairs that share something, and filler. A term has to be in at least two
documents to be shared at all and in no more than a third of them to be
distinctive, so the fixtures have to be a corpus rather than a handful.

    let corpus(): Map<Int, List<String>> {
      bagsOf([
        bag("alien alien border border unique_one unique_one"),
        bag("alien alien border border unique_two unique_two"),
        bag("glyphosate glyphosate labeling labeling unique_three unique_three"),
        bag("glyphosate glyphosate labeling labeling unique_four unique_four"),
        bag("citizenship citizenship unique_five unique_five"),
        bag("sovereign sovereign unique_six unique_six"),
      ])
    }

    let findCheck(test: Test): Void throws Bubble {
      let found = pairIds(casesKinshipPairs(corpus(), 10));
      expectTrue(test, has(found, "1,2"), "alien and border tie 1 and 2");
      expectTrue(test, has(found, "3,4"), "glyphosate and labeling tie 3 and 4");
      expectFalse(test, has(found, "1,5") || has(found, "5,6") || has(found, "2,6") || has(found, "4,5"), "filler ties nothing");
      expectInt(test, found.length, 2);
    }

    test("documents about the same thing find each other") { test =>
      do { findCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

    let sharedCheck(test: Test): Void throws Bubble {
      let pairs = casesKinshipPairs(corpus(), 10);
      let top = pairNamed(pairs, "1,2");
      expectTrue(test, top != null, "the pair is there");
      if (top != null) {
        expectTrue(test, has(top.shared, "alien"), "alien shared");
        expectTrue(test, has(top.shared, "border"), "border shared");
        expectTrue(test, top.score > 0.0, "a positive score");
        expectInt(test, top.shared.length, 2);
      }
    }

    test("each pair names what it is that they share") { test =>
      do { sharedCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

    let nothingCheck(test: Test): Void throws Bubble {
      let bags = bagsOf([
        bag("glyphosate glyphosate labeling labeling"),
        bag("citizenship citizenship jurisdiction jurisdiction"),
      ]);
      expectInt(test, casesKinshipPairs(bags, 10).length, 0);
    }

    test("a pair with nothing distinctive in common is not a pair") { test =>
      do { nothingCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

The longest document had the most chances to coincide, and came out as
everyone's nearest relation. (`filler12 filler12` is the same word as
`filler7 filler7` once digits are gone, so the long document is longer in
words but not in terms; the check is still the Elixir's.)

    let lengthCheck(test: Test): Void throws Bubble {
      let longParts = new ListBuilder<String>();
      var i = 1;
      while (i <= 400) {
        longParts.add("filler${i.toString()} filler${i.toString()}");
        i += 1;
      }
      let long = sysJoin(longParts.toList(), " ");
      let bags = bagsOf([
        bag("alien alien border border ${long}"),
        bag("alien alien border border"),
        bag("glyphosate glyphosate labeling labeling"),
        bag("glyphosate glyphosate labeling labeling"),
      ]);
      let pairs = casesKinshipPairs(bags, 10);
      expectTrue(test, pairs.length > 0, "there are pairs");
      expectText(test, sortedIds(pairs[0]), "3,4");
    }

    test("length is divided out, so the biggest document is not everyone's kin") { test =>
      do { lengthCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

A document with a long bag of distinct terms is divided out properly: the same
two shared terms score lower against 25 terms than against 2.

    let sizeCheck(test: Test): Void throws Bubble {
      let wordsA = ["alien", "border", "aaaaa", "bbbbb", "ccccc", "ddddd", "eeeee", "fffff", "ggggg", "hhhhh"];
      let small = bagsOf([
        ["alien", "border"], ["alien", "border"], ["other"], ["another"], ["third"], ["fourth"],
      ]);
      let big = bagsOf([
        wordsA, ["alien", "border"], ["other"], ["another"], ["third"], ["fourth"],
      ]);
      let s = casesKinshipPairs(small, 10);
      let b = casesKinshipPairs(big, 10);
      expectTrue(test, s.length == 1 && b.length == 1, "one pair each");
      expectTrue(test, s[0].score > b[0].score, "a bigger bag scores lower");
    }

    test("the score is the shared weight over the geometric mean of the sizes") { test =>
      do { sizeCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

`score = weight / size` exactly: two bags of two terms, both shared, in a
corpus of six where each term is in two documents: weight is 2 * ln(6/2),
size is sqrt(2*2) = 2, so the score is ln(3).

    let exactCheck(test: Test): Void throws Bubble {
      let bags = bagsOf([
        ["alien", "border"], ["alien", "border"], ["other"], ["another"], ["third"], ["fourth"],
      ]);
      let pairs = casesKinshipPairs(bags, 10);
      expectInt(test, pairs.length, 1);
      let three = 3.0;
      let want = three.log();
      let off = pairs[0].score - want;
      expectTrue(test, off < 0.000001 && off > -0.000001, "score is ln 3, got ${pairs[0].score.toString()}");
    }

    test("the score of a clean pair is ln(n / df)") { test =>
      do { exactCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

    let limitCheck(test: Test): Void throws Bubble {
      let bags = bagsOf([
        bag("alien alien border border"), bag("alien alien border border"),
        bag("glyphosate glyphosate labeling labeling"), bag("glyphosate glyphosate labeling labeling"),
        bag("tariff tariff import import"), bag("tariff tariff import import"),
        bag("alpha alpha"), bag("bravo bravo"), bag("charlie charlie"),
      ]);
      expectInt(test, casesKinshipPairs(bags, 10).length, 3);
      expectInt(test, casesKinshipPairs(bags, 2).length, 2);
      expectInt(test, casesKinshipPairs(bags, 0).length, 0);
    }

    test("limit cuts the list") { test =>
      do { limitCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

Equal scores keep the order the pairs were made in (lower ids first), where the
Elixir's sort was stable and left the rest unspecified.

    let tieCheck(test: Test): Void throws Bubble {
      let bags = bagsOf([
        bag("alien alien border border"), bag("alien alien border border"),
        bag("glyphosate glyphosate labeling labeling"), bag("glyphosate glyphosate labeling labeling"),
        bag("tariff tariff import import"), bag("tariff tariff import import"),
        bag("alpha alpha"), bag("bravo bravo"), bag("charlie charlie"),
      ]);
      let found = pairIds(casesKinshipPairs(bags, 10));
      expectText(test, joined(found), "1,2,3,4,5,6");
    }

    test("equal scores come out in id order") { test =>
      do { tieCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

    let emptyCheck(test: Test): Void throws Bubble {
      expectInt(test, casesKinshipPairs(bagsOf([]), 10).length, 0);
      expectInt(test, casesKinshipPairs(bagsOf([bag("alien alien")]), 10).length, 0);
    }

    test("no bags and one bag make no pairs") { test =>
      do { emptyCheck(test); } orelse expectTrue(test, false, "bubbled");
    }

The words shared come out best-weighted first, ties by term.

    let orderedCheck(test: Test): Void throws Bubble {
      let bags = bagsOf([
        ["zebra", "apple", "common"], ["zebra", "apple", "common"], ["common"], ["common"],
        ["x1"], ["x2"], ["x3"], ["x4"], ["x5"], ["x6"],
      ]);
      let pairs = casesKinshipPairs(bags, 10);
      let top = pairNamed(pairs, "1,2");
      expectTrue(test, top != null, "the pair is there");
      if (top != null) {
        expectText(test, joined(top.shared), "apple,zebra");
      }
    }

    test("shared terms are ordered by weight, then by term") { test =>
      do { orderedCheck(test); } orelse expectTrue(test, false, "bubbled");
    }
