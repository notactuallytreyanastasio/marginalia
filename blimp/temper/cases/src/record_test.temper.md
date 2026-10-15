# Tests for the record of a case

`Marginalia.Cases.Record` has no test of its own in the Elixir suite; what
the notes pin is the data (`notes/domain-accounts-links-stacks.md`, section 8):
sixteen cases, each with a docket and two dates, and a question on four of
them. These are those facts, and the one rule the page relies on: a collection
with no entry has none of it.

    let recordOf(name: String): CaseRecord? { casesRecordFor(name) }

    let sixteen(test: Test): Void {
      let names = casesRecordNames();
      expectInt(test, names.length, 16);
      expectText(test, names[0], "Blanche v. Lau");
      expectText(test, names[15], "Wolford v. Lopez");
      var i = 1;
      while (i < names.length) {
        expectTrue(test, casesCompareText(names[i - 1], names[i]) < 0, "${names[i - 1]} sorts before ${names[i]}");
        i += 1;
      }
    }

    test("sixteen cases, alphabetical") { test => sixteen(test); }

    let everyFact(test: Test): Void {
      for (let n of casesRecordNames()) {
        let r = recordOf(n);
        if (r != null) {
          expectText(test, r.name, n);
          expectTrue(test, r.docket != "", "${n} has a docket");
          expectTrue(test, r.argued != "", "${n} has an argued date");
          expectTrue(test, r.decided != "", "${n} has a decided date");
          expectHas(test, r.docket, "No. ");
          expectHas(test, r.decided, "2026");
        } else {
          expectTrue(test, false, "${n} is named but has no record");
        }
      }
    }

    test("every case has a docket, an argued date and a decided date") { test => everyFact(test); }

    let blanche(test: Test): Void {
      let r = recordOf("Blanche v. Lau");
      if (r != null) {
        expectText(test, r.docket, "No. 25-429");
        expectText(test, r.argued, "April 22, 2026");
        expectText(test, r.decided, "June 23, 2026");
        expectTrue(test, r.question == null, "no question where the holding says it");
      } else {
        expectTrue(test, false, "Blanche v. Lau");
      }
    }

    test("a record is docket, argued and decided") { test => blanche(test); }

    let questions(test: Test): Void {
      let asked = new ListBuilder<String>();
      for (let n of casesRecordNames()) {
        let r = recordOf(n);
        if (r != null) {
          if (r.question != null) { asked.add(n); }
        }
      }
      expectText(test, joined(asked.toList()), "Chatrie v. United States,Landor v. Louisiana,Trump v. Slaughter,West Virginia v. B. P. J.");
      let slaughter = recordOf("Trump v. Slaughter");
      if (slaughter != null) {
        expectText(test, slaughter.docket, "No. 25-332");
        expectText(test, slaughter.argued, "December 8, 2025");
        expectText(test, slaughter.decided, "June 29, 2026");
        expectText(test, orNone(slaughter.question), "Whether a President may remove a Federal Trade Commission commissioner before the end of their term, and whether Humphrey's Executor survives.");
      }
      let chatrie = recordOf("Chatrie v. United States");
      if (chatrie != null) {
        expectText(test, orNone(chatrie.question), "Whether a geofence warrant compelling Google to disclose the Location History of every device in an area is a Fourth Amendment search.");
      }
      let landor = recordOf("Landor v. Louisiana");
      if (landor != null) {
        expectText(test, landor.argued, "November 10, 2025");
        expectText(test, orNone(landor.question), "Whether RLUIPA, enacted under the Spending Clause, lets a prisoner sue a state official for damages in their individual capacity.");
      }
      let bpj = recordOf("West Virginia v. B. P. J.");
      if (bpj != null) {
        expectText(test, orNone(bpj.question), "Whether Title IX or the Equal Protection Clause bars a State from limiting girls' school sports teams to students assigned female at birth.");
      }
    }

    test("the question is written only where it says something the holding does not") { test => questions(test); }

    let unknown(test: Test): Void {
      expectTrue(test, recordOf("Some v. Case") == null, "a collection that is not a court case has no record");
      expectTrue(test, recordOf("") == null, "empty");
      expectTrue(test, recordOf("blanche v. lau") == null, "names are exact");
    }

    test("a collection with no entry has none of this") { test => unknown(test); }

    let argued(test: Test): Void {
      let early = ["Landor v. Louisiana", "National Republican Senatorial Committee v. FEC", "Trump v. Slaughter"];
      for (let n of early) {
        let r = recordOf(n);
        if (r != null) { expectHas(test, r.argued, "2025"); }
      }
      let wolford = recordOf("Wolford v. Lopez");
      if (wolford != null) { expectHas(test, wolford.argued, "2026"); }
    }

    test("the three cases argued in the autumn say 2025") { test => argued(test); }

    let viaCase(test: Test): Void throws Bubble {
      let fx = casesFixtureAs("Trump v. Slaughter");
      let c = casesGetFor(fx.db, fx.ownerId, "trump-v-slaughter");
      expectTrue(test, c != null, "the case is there");
      if (c != null) {
        let r = casesRecord(fx.db, c);
        expectTrue(test, r != null, "and has a record");
        if (r != null) { expectText(test, r.docket, "No. 25-332"); }
      }
      let plain = casesFixtureAs("Some v. Case");
      let p = casesGetFor(plain.db, plain.ownerId, "some-v-case");
      if (p != null) {
        expectTrue(test, casesRecord(plain.db, p) == null, "Some v. Case has no record");
      } else {
        expectTrue(test, false, "the case is there");
      }
    }

    test("casesRecord reads the record of a case by its name") { test =>
      do { viaCase(test); } orelse expectTrue(test, false, "bubbled");
    }

    class CasesOne(public db: Db, public ownerId: Int) {}

    let casesFixtureAs(collection: String): CasesOne throws Bubble {
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      makeDoc(db, owner, "${collection} — Opinion", collection, "opinion");
      new CasesOne(db, owner.userId)
    }
