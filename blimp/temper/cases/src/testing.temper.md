# What the cases tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated, so a
test never sees another's rows. Users are inserted with SQL; drafts, nodes and
links go through the public functions of `works` and `links`.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns, accountsOwnerEmail } = import("accounts/src");
    let {
      Work, Section, GraphNode, NodeParams, workParams, worksCreateWork, worksSetStatus,
      worksListSections, worksInsertNode,
    } = import("works/src");
    let {
      Link, linksGetOrCreate, linksSetStatus, linksAttrsSummary, linksStoreEdges, linkerTypes,
    } = import("links/src");
    let { JsonSyntaxTree, parseJson } = import("std/json");
    let { sysJoin } = import("sys/src");

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let expectTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let expectFalse(test: Test, got: Boolean, what: String): Void {
      assert(!got) { what }
    }

    let orNone(s: String?): String {
      if (s != null) { s } else { "<none>" }
    }

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "expected ${part} in:\n${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "did not expect ${part} in:\n${s}" }
    }

    let startsWithText(s: String, part: String): Boolean {
      let parts = s.split(part);
      parts.length > 1 && parts[0] == ""
    }

    let endsWithText(s: String, part: String): Boolean {
      let parts = s.split(part);
      parts.length > 1 && parts[parts.length - 1] == ""
    }

    let expectBefore(test: Test, s: String, first: String, second: String): Void {
      let head = s.split(second)[0];
      assert(hasText(s, second) && hasText(head, first)) { "expected ${first} before ${second} in:\n${s}" }
    }

    let joined(xs: List<String>): String {
      sysJoin(xs, ",")
    }

    let titlesOf(ws: List<Work>): String {
      sysJoin(ws.map { (w: Work): String => w.title }, " | ")
    }

`unit` repeated `n` times, by doubling, since a loop of appends is quadratic.

    let repeated(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = repeated(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

## Users and drafts

    let makeUser(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { new Scope(User.fromRow(row)) } else { bubble() }
    }

The sentence every anchored beat quotes.

    let quoteText(): String { "A sentence long enough" }

The `mk` of the Elixir tests: a read draft placed in a collection with one
anchored beat. The body makes one section whose first paragraph holds the
quote.

    class CasesMade(public work: Work, public node: GraphNode) {}

    let workOf(w: Work?): Work throws Bubble { if (w != null) { w } else { bubble() } }

    let linkOf(l: Link?): Link throws Bubble { if (l != null) { l } else { bubble() } }

    let nodeOf(n: GraphNode?): GraphNode throws Bubble { if (n != null) { n } else { bubble() } }

    let makeDoc(db: Db, scope: Scope, title: String, collection: String, role: String): CasesMade throws Bubble {
      let body = "# ${title}\n\n${quoteText()} to be a section.\n\n${repeated("word ", 200)}";
      let made = workOf(worksCreateWork(db, scope, workParams(title, body)).ok);
      let work = worksSetStatus(db, made, "read", null);
      let placed = casesPlace(db, work, collection, role);
      let section = worksListSections(db, placed.id)[0];
      let p = new NodeParams(placed.id, "beat", "a beat in the ${role}");
      p.sectionId = section.id;
      p.body = "what the ${role} is doing here";
      p.quote = quoteText();
      new CasesMade(placed, nodeOf(worksInsertNode(db, p).node))
    }

`join` of the Elixir tests: link two drafts, mark the link linked with a
summary, and store one edge between their beats.

    let proposal(from: Int, to: Int, kind: String, why: String): JsonSyntaxTree throws Bubble {
      parseJson("{\"from\": ${from.toString()}, \"to\": ${to.toString()}, \"type\": \"${kind}\", \"why\": \"${why}\"}")
    }

    let joinDocs(
      db: Db, a: CasesMade, b: CasesMade, kind: String, why: String,
    ): Link throws Bubble {
      let made = linkOf(linksGetOrCreate(db, a.work.id, b.work.id).ok);
      let linked = linkOf(linksSetStatus(db, made, "linked", linksAttrsSummary("${kind} between them.")).ok);
      let stored = linksStoreEdges(db, linked, [proposal(a.node.id, b.node.id, kind, why)], linkerTypes());
      if (stored.kept != 1) { bubble() }
      linked
    }

## The case of `case_read_test`

An owner, and "Some v. Case" with its opinion, dissent and argument (created
in the order argument, opinion, dissent, so reading order is not id order),
and three links: opinion with dissent (tension), opinion with argument
(answers), and the dissent with the argument (echoes), which does not touch
the opinion.

    class CasesFx(
      public db: Db,
      public owner: Scope,
      public op: CasesMade,
      public di: CasesMade,
      public ar: CasesMade,
      public opDi: Link,
      public opAr: Link,
      public diAr: Link,
    ) {}

    let casesFixture(): CasesFx throws Bubble {
      let db = dbOpen(":memory:");
      let owner = makeUser(db, accountsOwnerEmail());
      let ar = makeDoc(db, owner, "Some v. Case — Argument: Counsel", "Some v. Case", "argument");
      let op = makeDoc(db, owner, "Some v. Case — Opinion", "Some v. Case", "opinion");
      let di = makeDoc(db, owner, "Some v. Case — Dissent", "Some v. Case", "dissent");
      let opDi = joinDocs(db, op, di, "tension", "They part on consent.");
      let opAr = joinDocs(db, op, ar, "answers", "The lectern already settled this.");
      let diAr = joinDocs(db, di, ar, "echoes", "Dissent and counsel agree here.");
      new CasesFx(db, owner, op, di, ar, opDi, opAr, diAr)
    }

The second collection of "a case related to another case": one opinion in
"Other v. Matter", linked to this case's opinion.

    class CasesFar(public far: CasesMade, public link: Link) {}

    let casesFar(fx: CasesFx): CasesFar throws Bubble {
      let far = makeDoc(fx.db, fx.owner, "Other v. Matter — Opinion", "Other v. Matter", "opinion");
      let link = joinDocs(fx.db, fx.op, far, "echoes", "The same Court on the same clause, three weeks apart.");
      new CasesFar(far, link)
    }

    let theCase(fx: CasesFx): CaseStudy throws Bubble {
      let c = casesGet(fx.db, "some-v-case");
      if (c != null) { c } else { bubble() }
    }

    let readingOf(fx: CasesFx, c: CaseStudy, lead: Work): CaseReading throws Bubble {
      let r = casesReading(fx.db, c, lead.id);
      if (r != null) { r } else { bubble() }
    }

    let noteBodies(r: CaseReading): String {
      sysJoin(r.notes.map { (n: CaseNote): String => n.body }, " | ")
    }

    let sourceNames(r: CaseReading): String {
      sysJoin(r.sources.map { (s: CaseSource): String => casesName(s.work.title) }, " | ")
    }
