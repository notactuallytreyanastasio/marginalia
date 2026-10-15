# Tests for cases

`Marginalia.Cases` has no unit test of its own in the Elixir suite: its
behaviour is pinned through the LiveView tests, `case_read_test` above all
(`Cases.reading/2`, `default_lead`, the margin that merges two separate links)
and `case_index_test`. These are those assertions at the function level, with
the same fixtures (an owner, "Some v. Case" with an opinion, a dissent and an
argument, three links, and a second case related to the first), then the rules
the notes state for `slug`, `holding`, `kinships`, `ways`, `preview` and the
`A`/`B` substitution.

    let { dbOpen } = import("db/src");
    let { sysMonoMs } = import("sys/src");

## slug and roles

    let slugs(test: Test): Void {
      expectText(test, casesSlug("Some v. Case"), "some-v-case");
      expectText(test, casesSlug("Trump v. Slaughter"), "trump-v-slaughter");
      expectText(test, casesSlug("T. M. v. University of Maryland Medical System"), "t-m-v-university-of-maryland-medical-system");
      expectText(test, casesSlug("  --Hello,   World!--  "), "hello-world");
      expectText(test, casesSlug("Exxon Mobil Corp. v. Corporacion Cimex"), "exxon-mobil-corp-v-corporacion-cimex");
      expectText(test, casesSlug("!!!"), "");
      expectText(test, casesSlug(""), "");
      expectText(test, casesSlug("Ünïcode Café"), "n-code-caf");
      expectText(test, casesSlug("a1 B2"), "a1-b2");
    }

    test("slug: lower, runs of anything else become one dash, trimmed, no fallback") { test => slugs(test); }

    let slugLong(test: Test): Void {
      let name = "${repeated("word ", 40)}end";
      expectTrue(test, casesSlug(name).countBetween(String.begin, casesSlug(name).end) > 60, "no length cap");
    }

    test("slug has no length cap") { test => slugLong(test); }

    let roles(test: Test): Void {
      expectText(test, joined(casesRoles()), "opinion,concurrence,dissent,argument");
      expectInt(test, casesRank("opinion"), 0);
      expectInt(test, casesRank("concurrence"), 1);
      expectInt(test, casesRank("dissent"), 2);
      expectInt(test, casesRank("argument"), 3);
      expectInt(test, casesRank("amicus"), 4);
      expectInt(test, casesRank(null), 4);
      expectInt(test, casesRank(""), 4);
    }

    test("the reading order, and an unknown role sorts last") { test => roles(test); }

## names

    let names(test: Test): Void {
      expectText(test, casesName("Some v. Case — Opinion"), "Opinion");
      expectText(test, casesName("Some v. Case — Dissent (Sotomayor)"), "Dissent (Sotomayor)");
      expectText(test, casesName("Some v. Case — Argument: Amit Agarwal"), "Argument: Amit Agarwal");
      expectText(test, casesName("No dash here"), "No dash here");
      expectText(test, casesName("X — Y — Z"), "Y — Z");
      expectText(test, casesName("Hyphen - not a dash"), "Hyphen - not a dash");
      expectText(test, casesName(""), "");
    }

    test("a document is named by what follows the first em dash") { test => names(test); }

## A and B in a rationale

    let refs(test: Test, text: String, want: String): Void {
      expectText(test, casesResolveRefs(text, "One", "Two"), want);
    }

    let refsCheck(test: Test): Void {
      refs(test, "B answers A's open question.", "Two answers One's open question.");
      refs(test, "Manuscript B extends Manuscript A.", "Two extends One.");
      refs(test, "See Part A and Exhibit B.", "See Part A and Exhibit B.");
      refs(test, "It extends B.", "It extends B.");
      refs(test, "tension: B disagrees; A agrees", "tension: Two disagrees; One agrees");
      refs(test, "Apple and Banana", "Apple and Banana");
      refs(test, "A story: B tells it.", "One story: Two tells it.");
      refs(test, "B answers A’s question.", "Two answers One’s question.");
      refs(test, "", "");
      refs(test, "A", "One");
      refs(test, "B.", "Two.");
      refs(test, "- A: yes", "- One: yes");
      refs(test, "A1 and B2", "A1 and B2");
      refs(test, "A' alone", "A' alone");
      refs(test, "Where A and B differ, B wins.", "Where A and B differ, B wins.");
      refs(test, "x.  B y", "x.  Two y");
      refs(test, "Manuscripts A and B", "One and B");
      refs(test, "the Manuscript  B point", "the Two point");
      refs(test, "Both A and B", "Both A and B");
      refs(test, "one — B says so", "one — Two says so");
      refs(test, "no letters here", "no letters here");
    }

    test("A and B become the documents' names where they are references") { test => refsCheck(test); }

    let refsTitles(test: Test): Void {
      let a = "1. A page with no script on it";
      let b = "2. The backend scaffold";
      expectText(test, casesResolveRefs("B answers A's open question.", a, b), "2. The backend scaffold answers 1. A page with no script on it's open question.");
      expectText(test, casesResolveRefs("Manuscript B extends Manuscript A.", a, b), "2. The backend scaffold extends 1. A page with no script on it.");
      expectText(test, casesResolveRefs("See Part A and Exhibit B.", a, b), "See Part A and Exhibit B.");
      expectText(test, casesResolveRefs("It extends B.", a, b), "It extends B.");
    }

    test("a title that begins with digits or holds an A is never rescanned") { test => refsTitles(test); }

    let refsNoRescan(test: Test): Void {
      expectText(test, casesResolveRefs("A is first, and then: B", "B plus A", "A plus B"), "B plus A is first, and then: A plus B");
    }

    test("replaced text is not scanned again") { test => refsNoRescan(test); }

## holding

    let hold(test: Test, body: String, want: String): Void {
      let got = casesHoldingText(body);
      expectText(test, orNone(got), want);
    }

    let holdCheck(test: Test): Void {
      hold(test, "Intro sentence here. We hold that the statute preempts the state claim as a matter of law. More text.", "We hold that the statute preempts the state claim as a matter of law.");
      hold(test, "We therefore hold that the statute preempts the state claim as a matter of law.", "We therefore hold that the statute preempts the state claim as a matter of law.");
      hold(test, "We accordingly hold that the statute preempts the state claim as a matter of law.", "We accordingly hold that the statute preempts the state claim as a matter of law.");
      hold(test, "Then we now hold that the statute preempts the state claim as a matter of law.", "Then we now hold that the statute preempts the state claim as a matter of law.");
      hold(test, "A. We conclude that the statute preempts the state claim as a matter of law.", "We conclude that the statute preempts the state claim as a matter of law.");
    }

    test("the Court's own sentence is lifted from the opinion") { test => holdCheck(test); }

    let holdWiden(test: Test): Void {
      hold(test, "Because we conclude that Durnell's claim is preempted by federal law, we need not consider the rest. Other.", "Because we conclude that Durnell's claim is preempted by federal law, we need not consider the rest.");
      hold(test, "He said “No.” We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "He said \"No.\" We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Is it so? We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Stop! We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
    }

    test("a match is widened back to where its sentence began") { test => holdWiden(test); }

    let holdMarkers(test: Test): Void {
      hold(test, "The judgment is affirmed in part. III We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Done. * * * We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Done. A. We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Done. 2. We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Done. IV. We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Done. I. A. We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Done. 12 We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
    }

    test("a division heading is not part of the quotation") { test => holdMarkers(test); }

    let holdKeeps(test: Test): Void {
      hold(test, "Done. Later we hold that the rule applies to every case of this kind.", "Later we hold that the rule applies to every case of this kind.");
      hold(test, "Done. Lastly we hold that the rule applies to every case of this kind.", "Lastly we hold that the rule applies to every case of this kind.");
      hold(test, "Done. In sum we hold that the rule applies to every case of this kind.", "In sum we hold that the rule applies to every case of this kind.");
    }

    test("a sentence that merely begins with a capital is not a heading") { test => holdKeeps(test); }

    let holdOrder(test: Test): Void {
      hold(test, "We conclude that the first thing is long enough to count here. Later we hold that the second thing is long enough to count too.", "Later we hold that the second thing is long enough to count too.");
      hold(test, "We conclude the narrow question presented in the case at hand. We hold the broader one is not before us today.", "We conclude the narrow question presented in the case at hand.");
      hold(test, "We hold the broader one is not before us today. We conclude the narrow question presented in the case at hand.", "We hold the broader one is not before us today.");
      hold(test, "We reverse the judgment below and send it back for more. We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
    }

    test("the first of the four phrasings that matches wins, then the leftmost") { test => holdOrder(test); }

    let holdFour(test: Test): Void {
      hold(test, "The petition is granted. We reverse the judgment of the Court of Appeals and remand.", "We reverse the judgment of the Court of Appeals and remand.");
      hold(test, "We therefore affirm the judgment of the Court of Appeals in full today.", "We therefore affirm the judgment of the Court of Appeals in full today.");
      hold(test, "We accordingly vacate the judgment and remand the case for more work.", "We accordingly vacate the judgment and remand the case for more work.");
      hold(test, "We affirm the judgment as to the first claim, and we vacate the rest of it.", "We affirm the judgment as to the first claim, and we vacate the rest of it.");
    }

    test("a disposition is the last phrasing tried") { test => holdFour(test); }

    let holdNone(test: Test): Void {
      expectTrue(test, casesHoldingText("This opinion concerns standing. It is brief.") == null, "no phrasing, no holding");
      expectTrue(test, casesHoldingText("We hold that it is so.") == null, "too short to be a sentence of holding");
      expectTrue(test, casesHoldingText("") == null, "empty");
      expectTrue(test, casesHoldingText("   ") == null, "blank");
      expectTrue(test, casesHoldingText("We holdings of the court are shown in the following long list.") == null, "hold is a whole word");
      expectTrue(test, casesHoldingText("Sowe hold that the rule applies to every case of this kind.") == null, "we is a whole word");
      expectTrue(test, casesHoldingText("We hold that the rule applies to every case of this kind without a full stop") == null, "no full stop");
      expectTrue(test, casesHoldingText("we reverse the judgment of the Court of Appeals and remand.") == null, "reverse wants a capital We");
      expectTrue(test, casesHolding(null) == null, "no opinion");
    }

    test("no phrasing, no holding, and no fallback") { test => holdNone(test); }

    let holdBounds(test: Test): Void {
      let edge = 9;
      expectTrue(test, casesHoldingText("We reverse ${repeated("x", edge)}.") != null, "a run of ten is enough (space and nine)");
      expectTrue(test, casesHoldingText("We reverse ${repeated("x", edge - 1)}.") == null, "nine is too short");
      expectTrue(test, casesHoldingText("We reverse ${repeated("x", 299)}.") != null, "three hundred is the most");
      expectTrue(test, casesHoldingText("We reverse ${repeated("x", 300)}.") == null, "three hundred and one is too long");
      expectTrue(test, casesHoldingText("We hold that ${repeated("x", 19)}.") != null, "twenty after the keyword");
    }

    test("the length of the run is checked at both ends") { test => holdBounds(test); }

    let holdSpace(test: Test): Void {
      hold(test, "Preface.\n\nWe hold\nthat the\n\nrule applies   to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "Preface.\tWe hold that\tthe rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
      hold(test, "  \n  We hold that the rule applies to every case of this kind.", "We hold that the rule applies to every case of this kind.");
    }

    test("whitespace runs are one space before anything is matched") { test => holdSpace(test); }

    let holdFlat(test: Test): Void {
      expectText(test, casesFlat("a\n\nb\t c"), "a b c");
      expectText(test, casesFlat("\n a b \n"), " a b ");
      expectText(test, casesFlat("   "), " ");
      expectText(test, casesFlat(""), "");
      expectText(test, casesFlat("one"), "one");
    }

    test("the collapse keeps one space at an end that had whitespace") { test => holdFlat(test); }

## speed

An opinion is twelve thousand words. The holding is looked for in all sixteen
on every contents page, so it cannot walk the text a character at a time.

    let holdSpeed(test: Test): Void {
      let t0 = sysMonoMs();
      let body = "${repeated("household word ", 6000)}\n\nDone. We hold that the rule applies to every case of this kind.";
      let got = casesHoldingText(body);
      let t1 = sysMonoMs();
      console.log("holding of ${body.countBetween(String.begin, body.end).toString()} characters: ${(t1 - t0).toString()} ms");
      expectText(test, orNone(got), "We hold that the rule applies to every case of this kind.");
      expectTrue(test, t1 - t0 < 4000, "took ${(t1 - t0).toString()} ms");
    }

    test("the holding of a long opinion is found without a scan of the text") { test => holdSpeed(test); }

## placing a draft

    let place(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let w = fx.op.work;
      expectText(test, orNone(w.collection), "Some v. Case");
      expectText(test, orNone(w.collectionRole), "opinion");
      let moved = casesPlace(fx.db, w, "Other v. Matter", "concurrence");
      expectText(test, orNone(moved.collection), "Other v. Matter");
      expectText(test, orNone(moved.collectionRole), "concurrence");
      expectInt(test, moved.id, w.id);
      let gone = casesPlace(fx.db, moved, "", "");
      expectTrue(test, gone.collection == null, "the empty string is NULL");
      expectTrue(test, gone.collectionRole == null, "the empty role is NULL");
      let odd = casesPlace(fx.db, gone, "Anything", "amicus");
      expectText(test, orNone(odd.collectionRole), "amicus");
      let cleared = casesPlace(fx.db, odd, null, null);
      expectTrue(test, cleared.collection == null && cleared.collectionRole == null, "null clears both");
    }

    test("place puts a draft in a collection with a role, and takes it out again") { test =>
      do { place(test); } orelse expectTrue(test, false, "bubbled");
    }

    let notPublished(test: Test): Void throws Bubble {
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      let made = makeDoc(db, owner, "Some v. Case — Opinion", "Some v. Case", "opinion");
      expectInt(test, casesList(db).length, 1);
      casesPlace(db, made.work, null, null);
      expectInt(test, casesList(db).length, 0);
    }

    test("nothing is published until a draft is put in a named collection") { test =>
      do { notPublished(test); } orelse expectTrue(test, false, "bubbled");
    }

## listing

    let listing(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let all = casesList(fx.db);
      expectInt(test, all.length, 1);
      let c = all[0];
      expectText(test, c.name, "Some v. Case");
      expectText(test, c.slug, "some-v-case");
      expectText(test, titlesOf(c.works), "Some v. Case — Opinion | Some v. Case — Dissent | Some v. Case — Argument: Counsel");
      expectInt(test, c.read, 3);
      expectInt(test, c.links.length, 3);
      expectInt(test, c.edges, 3);
      expectTrue(test, c.holding == null, "no phrasing, no holding");
      expectTrue(test, c.kin.length == 0, "no other case");
      expectInt(test, c.missing.length, 0);
      let words = fx.op.work.wordCount + fx.di.work.wordCount + fx.ar.work.wordCount;
      expectInt(test, c.words, words);
      expectTrue(test, words > 600, "three drafts of two hundred words");
    }

    test("a case is its drafts in reading order, with their links and counts") { test =>
      do { listing(test); } orelse expectTrue(test, false, "bubbled");
    }

    let getBySlug(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let c = casesGet(fx.db, "some-v-case");
      expectTrue(test, c != null, "found");
      expectTrue(test, casesGet(fx.db, "nothing-here") == null, "an unknown slug is nil");
      expectTrue(test, casesGet(fx.db, "") == null, "the empty slug is nil");
      let again = casesGetFor(fx.db, fx.owner.userId, "some-v-case");
      expectTrue(test, again != null, "found by user too");
      expectTrue(test, casesGetFor(fx.db, fx.owner.userId + 100, "some-v-case") == null, "another user has none");
    }

    test("get finds a case by its slug") { test =>
      do { getBySlug(test); } orelse expectTrue(test, false, "bubbled");
    }

    let twoCases(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let far = casesFar(fx);
      let all = casesList(fx.db);
      expectInt(test, all.length, 2);
      expectText(test, all[0].name, "Other v. Matter");
      expectText(test, all[1].name, "Some v. Case");
      expectInt(test, all[0].links.length, 0);
      expectInt(test, all[0].edges, 0);
      expectInt(test, all[1].links.length, 3);
    }

    test("cases are sorted by name, and a link that leaves one is in neither") { test =>
      do { twoCases(test); } orelse expectTrue(test, false, "bubbled");
    }

    let unlinked(test: Test): Void throws Bubble {
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      let op = makeDoc(db, owner, "Some v. Case — Opinion", "Some v. Case", "opinion");
      let di = makeDoc(db, owner, "Some v. Case — Dissent", "Some v. Case", "dissent");
      let ar = makeDoc(db, owner, "Some v. Case — Argument: Counsel", "Some v. Case", "argument");
      joinDocs(db, op, di, "tension", "They part on consent.");
      let c = casesList(db)[0];
      expectInt(test, c.missing.length, 2);
      expectText(test, "${c.missing[0].a.title}|${c.missing[0].b.title}", "Some v. Case — Opinion|Some v. Case — Argument: Counsel");
      expectText(test, "${c.missing[1].a.title}|${c.missing[1].b.title}", "Some v. Case — Dissent|Some v. Case — Argument: Counsel");
      expectTrue(test, c.missing[0].a.id < c.missing[0].b.id, "the lower id first");
    }

    test("missing is every pair of drafts with no link between them") { test =>
      do { unlinked(test); } orelse expectTrue(test, false, "bubbled");
    }

    let published(test: Test): Void throws Bubble {
      let db = dbOpen(":memory:");
      expectInt(test, casesPublished(db).length, 0);
      let someone = makeUser(db, "someone@example.com");
      makeDoc(db, someone, "Mine v. Yours — Opinion", "Mine v. Yours", "opinion");
      expectInt(test, casesPublished(db).length, 0);
      let owner = makeUser(db, accountsOwnerEmail());
      makeDoc(db, owner, "Some v. Case — Opinion", "Some v. Case", "opinion");
      let shown = casesPublished(db);
      expectInt(test, shown.length, 1);
      expectText(test, shown[0].name, "Some v. Case");
      expectInt(test, casesListFor(db, someone.userId).length, 1);
    }

    test("the front of the site is the owner's collections, whoever is looking") { test =>
      do { published(test); } orelse expectTrue(test, false, "bubbled");
    }

    let heldInCase(test: Test): Void throws Bubble {
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      let body = "# Holding\n\nThe Court granted review. We hold that the statute preempts the state claim as a matter of law. Further text.\n\n${repeated("word ", 200)}";
      let made = workOf(worksCreateWork(db, owner, workParams("Held v. Case — Opinion", body)).ok);
      casesPlace(db, made, "Held v. Case", "opinion");
      let other = workOf(worksCreateWork(db, owner, workParams("Held v. Case — Dissent", body)).ok);
      casesPlace(db, other, "Held v. Case", "dissent");
      let c = casesList(db)[0];
      expectText(test, orNone(c.holding), "We hold that the statute preempts the state claim as a matter of law.");
    }

    test("the holding is lifted from the opinion, not the dissent") { test =>
      do { heldInCase(test); } orelse expectTrue(test, false, "bubbled");
    }

    let dissentOnly(test: Test): Void throws Bubble {
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      let body = "# Holding\n\nWe hold that the statute preempts the state claim as a matter of law.\n\n${repeated("word ", 200)}";
      let made = workOf(worksCreateWork(db, owner, workParams("Held v. Case — Dissent", body)).ok);
      casesPlace(db, made, "Held v. Case", "dissent");
      let c = casesList(db)[0];
      expectTrue(test, c.holding == null, "a dissent holds nothing");
    }

    test("a case with no opinion has no holding") { test =>
      do { dissentOnly(test); } orelse expectTrue(test, false, "bubbled");
    }

## ways, preview, kin, default lead

    let ways(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let c = theCase(fx);
      let w = casesWays(c);
      expectInt(test, w.length, 3);
      expectText(test, casesName(w[0].lead.title), "Opinion");
      expectText(test, casesName(w[0].other.title), "Dissent");
      expectText(test, casesName(w[1].lead.title), "Opinion");
      expectText(test, casesName(w[1].other.title), "Argument: Counsel");
      expectText(test, casesName(w[2].lead.title), "Dissent");
      expectText(test, casesName(w[2].other.title), "Argument: Counsel");
      expectInt(test, w[0].edges, 1);
    }

    test("the ways into a case are pairings, the opinion's first") { test =>
      do { ways(test); } orelse expectTrue(test, false, "bubbled");
    }

    let waysFilter(test: Test): Void throws Bubble {
      let fx = casesFixture();
      linksSetStatus(fx.db, fx.diAr, "pending", linksAttrsSummary(null));
      let c = theCase(fx);
      expectInt(test, casesWays(c).length, 2);
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      let a = makeDoc(db, owner, "Some v. Case — Opinion", "Some v. Case", "opinion");
      let b = makeDoc(db, owner, "Some v. Case — Dissent", "Some v. Case", "dissent");
      let l = linkOf(linksGetOrCreate(db, a.work.id, b.work.id).ok);
      linksSetStatus(db, l, "linked", linksAttrsSummary("no edges"));
      expectInt(test, casesWays(casesList(db)[0]).length, 0);
    }

    test("a pairing counts only when it is linked and has an edge") { test =>
      do { waysFilter(test); } orelse expectTrue(test, false, "bubbled");
    }

    let waysLead(test: Test): Void throws Bubble {
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      let di = makeDoc(db, owner, "Some v. Case — Dissent", "Some v. Case", "dissent");
      let op = makeDoc(db, owner, "Some v. Case — Opinion", "Some v. Case", "opinion");
      joinDocs(db, di, op, "tension", "They part on consent.");
      let w = casesWays(casesList(db)[0]);
      expectInt(test, w.length, 1);
      expectText(test, casesName(w[0].lead.title), "Opinion");
    }

    test("the lead of a pairing is the one a reader would start with, whichever was created first") { test =>
      do { waysLead(test); } orelse expectTrue(test, false, "bubbled");
    }

    let preview(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let p = casesPreview(theCase(fx));
      expectText(test, orNone(p.summary), "tension between them.");
      expectInt(test, p.sharpest.length, 3);
      expectText(test, p.sharpest[0].edge.edgeType, "tension");
      expectText(test, p.sharpest[1].edge.edgeType, "answers");
      expectText(test, p.sharpest[2].edge.edgeType, "echoes");
      expectInt(test, p.kinds.length, 3);
      expectText(test, "${p.kinds[0].edgeType}:${p.kinds[0].count.toString()}", "answers:1");
      expectText(test, "${p.kinds[1].edgeType}:${p.kinds[1].count.toString()}", "echoes:1");
      expectText(test, "${p.kinds[2].edgeType}:${p.kinds[2].count.toString()}", "tension:1");
      expectTrue(test, p.impression == null, "no first impression yet");
    }

    test("a preview leads with the disagreement") { test =>
      do { preview(test); } orelse expectTrue(test, false, "bubbled");
    }

    let previewMore(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let l = linkOf(linksGetOrCreate(fx.db, fx.op.work.id, fx.di.work.id).ok);
      linksSetStatus(fx.db, l, "linked", linksAttrsSummary("B answers A's open question."));
      let p = casesPreview(theCase(fx));
      expectText(test, orNone(p.summary), "Dissent answers Opinion's open question.");
      fx.db.exec("UPDATE works SET first_impression = 'It reads as a shrug.' WHERE id = $1", [fx.op.work.id.toString()]);
      let q = casesPreview(theCase(fx));
      expectText(test, orNone(q.impression), "It reads as a shrug.");
    }

    test("the summary has A and B resolved, and the impression is the opinion's") { test =>
      do { previewMore(test); } orelse expectTrue(test, false, "bubbled");
    }

    let previewMany(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let c = theCase(fx);
      let l = linkOf(linksGetOrCreate(fx.db, fx.op.work.id, fx.di.work.id).ok);
      let extra = linksStoreEdges(fx.db, l, [
        proposal(fx.op.node.id, fx.di.node.id, "requires", "It needs it."),
        proposal(fx.di.node.id, fx.op.node.id, "tension", "And back again."),
        proposal(fx.op.node.id, fx.di.node.id, "develops", "Further."),
      ], linkerTypes());
      expectInt(test, extra.kept, 3);
      let p = casesPreview(theCase(fx));
      expectInt(test, p.sharpest.length, 3);
      expectText(test, p.sharpest[0].edge.edgeType, "tension");
      expectText(test, p.sharpest[1].edge.edgeType, "tension");
      expectText(test, p.sharpest[2].edge.edgeType, "answers");
      expectText(test, "${p.kinds[0].edgeType}:${p.kinds[0].count.toString()}", "tension:2");
      expectInt(test, theCase(fx).edges, 6);
    }

    test("the three sharpest edges are chosen by rank, and the kinds count them all") { test =>
      do { previewMany(test); } orelse expectTrue(test, false, "bubbled");
    }

    let defaults(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let lead = casesDefaultLead(theCase(fx));
      expectTrue(test, lead != null, "there is one");
      if (lead != null) { expectText(test, casesName(lead.title), "Opinion"); }
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      makeDoc(db, owner, "Some v. Case — Argument: Counsel", "Some v. Case", "argument");
      makeDoc(db, owner, "Some v. Case — Dissent", "Some v. Case", "dissent");
      let first = casesDefaultLead(casesList(db)[0]);
      if (first != null) {
        expectText(test, casesName(first.title), "Dissent");
      } else {
        expectTrue(test, false, "a lead");
      }
    }

    test("the default lead is the opinion, else whatever sorts first") { test =>
      do { defaults(test); } orelse expectTrue(test, false, "bubbled");
    }

    let kin(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let far = casesFar(fx);
      let mine = theCase(fx);
      expectInt(test, mine.kin.length, 1);
      let k = casesKin(mine)[0];
      expectText(test, k.caseName, "Other v. Matter");
      expectText(test, casesName(k.lead.title), "Opinion");
      expectInt(test, k.lead.id, fx.op.work.id);
      expectInt(test, k.other.id, far.far.work.id);
      expectInt(test, k.edges, 1);
      expectInt(test, k.linkId, far.link.id);
      let theirs = casesGetFor(fx.db, fx.owner.userId, "other-v-matter");
      if (theirs != null) {
        expectInt(test, theirs.kin.length, 1);
        expectText(test, theirs.kin[0].caseName, "Some v. Case");
        expectInt(test, theirs.kin[0].lead.id, far.far.work.id);
        expectInt(test, theirs.kin[0].other.id, fx.op.work.id);
      } else {
        expectTrue(test, false, "the other case");
      }
    }

    test("a link that leaves a case is kin to both of them") { test =>
      do { kin(test); } orelse expectTrue(test, false, "bubbled");
    }

    let kinFilter(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let far = casesFar(fx);
      linksSetStatus(fx.db, far.link, "pending", linksAttrsSummary(null));
      expectInt(test, theCase(fx).kin.length, 0);
      linksSetStatus(fx.db, far.link, "linked", linksAttrsSummary(null));
      expectInt(test, theCase(fx).kin.length, 1);
      fx.db.exec("DELETE FROM link_edges WHERE link_id = $1", [far.link.id.toString()]);
      expectInt(test, theCase(fx).kin.length, 0);
    }

    test("kin needs a linked link with an edge") { test =>
      do { kinFilter(test); } orelse expectTrue(test, false, "bubbled");
    }

    let kinOrder(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let far = casesFar(fx);
      let third = makeDoc(fx.db, fx.owner, "Third v. Thing — Opinion", "Third v. Thing", "opinion");
      let l = joinDocs(fx.db, fx.di, third, "tension", "One.");
      linksStoreEdges(fx.db, l, [
        proposal(fx.di.node.id, third.node.id, "answers", "Two."),
        proposal(third.node.id, fx.di.node.id, "requires", "Three."),
      ], linkerTypes());
      let k = theCase(fx).kin;
      expectInt(test, k.length, 2);
      expectText(test, k[0].caseName, "Third v. Thing");
      expectInt(test, k[0].edges, 3);
      expectText(test, k[1].caseName, "Other v. Matter");
      expectInt(test, k[1].edges, 1);
    }

    test("kin is strongest first") { test =>
      do { kinOrder(test); } orelse expectTrue(test, false, "bubbled");
    }

## reading a case

    let merged(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let c = theCase(fx);
      let r = readingOf(fx, c, fx.op.work);
      expectInt(test, r.lead.id, fx.op.work.id);
      expectText(test, sourceNames(r), "Dissent | Argument: Counsel");
      expectInt(test, r.notes.length, 2);
      let bodies = noteBodies(r);
      expectHas(test, bodies, "They part on consent.");
      expectHas(test, bodies, "The lectern already settled this.");
      expectLacks(test, bodies, "Dissent and counsel agree here.");
    }

    test("the opinion is read with both other documents in one margin") { test =>
      do { merged(test); } orelse expectTrue(test, false, "bubbled");
    }

    let stamped(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let first = r.notes[0];
      expectInt(test, first.fromWork, fx.di.work.id);
      expectText(test, first.fromTitle, "Some v. Case — Dissent");
      expectText(test, orNone(first.fromRole), "dissent");
      expectText(test, orNone(first.fromCase), "Some v. Case");
      expectInt(test, first.linkId, fx.opDi.id);
      expectText(test, first.kind, "tension");
      expectText(test, first.quote, quoteText());
      expectText(test, orNone(first.farQuote), quoteText());
      expectText(test, first.farKind, "beat");
      expectText(test, first.farTitle, "a beat in the dissent");
      expectText(test, first.title, "→ a beat in the dissent");
      expectInt(test, orZero(first.farSection), 1);
      expectText(test, first.key, "link:${first.edgeId.toString()}");
      expectFalse(test, first.stale, "fresh");
      expectInt(test, first.peer, fx.di.node.id);
      let second = r.notes[1];
      expectText(test, orNone(second.fromRole), "argument");
      expectText(test, second.kind, "answers");
    }

    let orZero(n: Int?): Int { if (n != null) { n } else { -1 } }

    test("each note says which document it came from, and the far passage travels with it") { test =>
      do { stamped(test); } orelse expectTrue(test, false, "bubbled");
    }

    let fromTheArgument(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.ar.work);
      let bodies = noteBodies(r);
      expectText(test, sourceNames(r), "Opinion | Dissent");
      expectHas(test, bodies, "The lectern already settled this.");
      expectHas(test, bodies, "Dissent and counsel agree here.");
      expectLacks(test, bodies, "They part on consent.");
      let arrow = r.notes[0];
      expectText(test, arrow.title, "← a beat in the opinion");
    }

    test("any document in the case can be the one you read") { test =>
      do { fromTheArgument(test); } orelse expectTrue(test, false, "bubbled");
    }

    let notInCase(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let far = casesFar(fx);
      expectTrue(test, casesReading(fx.db, theCase(fx), far.far.work.id) == null, "a draft of another case is not a lead here");
      expectTrue(test, casesReading(fx.db, theCase(fx), 0) == null, "nor is nothing");
    }

    test("a lead that is not in the collection reads as nil") { test =>
      do { notInCase(test); } orelse expectTrue(test, false, "bubbled");
    }

    let elsewhere(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let far = casesFar(fx);
      let r = readingOf(fx, theCase(fx), fx.op.work);
      expectText(test, sourceNames(r), "Dissent | Argument: Counsel | Opinion");
      let last = r.sources[2];
      expectText(test, orNone(last.elsewhere), "Other v. Matter");
      expectTrue(test, r.sources[0].elsewhere == null, "inside the case is not elsewhere");
      expectInt(test, r.notes.length, 3);
      let note = r.notes[2];
      expectHas(test, note.body, "The same Court on the same clause");
      expectText(test, orNone(note.fromCase), "Other v. Matter");
      expectInt(test, note.fromWork, far.far.work.id);
    }

    test("another case's notes appear in the margin, saying where they are from") { test =>
      do { elsewhere(test); } orelse expectTrue(test, false, "bubbled");
    }

    let unlinkedSource(test: Test): Void throws Bubble {
      let fx = casesFixture();
      linksSetStatus(fx.db, fx.opAr, "failed", linksAttrsSummary(null));
      let r = readingOf(fx, theCase(fx), fx.op.work);
      expectText(test, sourceNames(r), "Dissent");
      expectInt(test, r.notes.length, 1);
    }

    test("a link that is not linked contributes nothing") { test =>
      do { unlinkedSource(test); } orelse expectTrue(test, false, "bubbled");
    }

    let rationaleWords(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let l = linkOf(linksGetOrCreate(fx.db, fx.op.work.id, fx.di.work.id).ok);
      fx.db.exec("UPDATE link_edges SET rationale = 'B answers A''s point.' WHERE link_id = $1", [l.id.toString()]);
      let r = readingOf(fx, theCase(fx), fx.op.work);
      expectHas(test, noteBodies(r), "Dissent answers Opinion's point.");
      expectLacks(test, noteBodies(r), "B answers A");
    }

    test("a rationale's A and B are the documents' names") { test =>
      do { rationaleWords(test); } orelse expectTrue(test, false, "bubbled");
    }

    let noQuote(test: Test): Void throws Bubble {
      let fx = casesFixture();
      fx.db.exec("UPDATE nodes SET quote = NULL WHERE id = $1", [fx.op.node.id.toString()]);
      let r = readingOf(fx, theCase(fx), fx.op.work);
      expectInt(test, r.notes.length, 0);
      expectInt(test, r.sources.length, 2);
    }

    test("an edge whose near end has no quote has nowhere to sit on the page") { test =>
      do { noQuote(test); } orelse expectTrue(test, false, "bubbled");
    }

    let passages(test: Test): Void throws Bubble {
      let fx = casesFixture();
      let r = readingOf(fx, theCase(fx), fx.op.work);
      let nodes = worksNodes(fx.db, fx.op.work.id);
      expectInt(test, nodes.length, 1);
      expectHas(test, casesPassage(fx.db, nodes[0]), "A sentence long enough to be a section.");
      fx.db.exec("UPDATE nodes SET section_id = NULL WHERE id = $1", [nodes[0].id.toString()]);
      let bare = worksNodes(fx.db, fx.op.work.id);
      expectText(test, casesPassage(fx.db, bare[0]), quoteText());
      fx.db.exec("UPDATE nodes SET quote = NULL WHERE id = $1", [nodes[0].id.toString()]);
      let titled = worksNodes(fx.db, fx.op.work.id);
      expectText(test, casesPassage(fx.db, titled[0]), "a beat in the opinion");
    }

    test("a passage is the paragraph, else the quote, else the title") { test =>
      do { passages(test); } orelse expectTrue(test, false, "bubbled");
    }
