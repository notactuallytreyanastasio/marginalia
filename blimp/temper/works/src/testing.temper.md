# What the works tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated, so a
test never sees another's rows.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { paragraphs } = import("core/src");
    let { sysByteLength, sysJoin } = import("sys/src");

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

    let orZero(n: Int?): Int { if (n != null) { n } else { 0 } }

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let orEmpty(s: String?): String {
      if (s != null) { s } else { "" }
    }

    let orNull(s: String?): String {
      if (s != null) { s } else { "NULL" }
    }

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "expected ${part} in:\n${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "did not expect ${part} in:\n${s}" }
    }

`word ` repeated `n` times, by doubling, since a loop of appends is quadratic.

    let repeated(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = repeated(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

    let titlesOf(sections: List<Section>): String {
      sysJoin(sections.map { (s: Section): String => s.title }, " | ")
    }

## Users

A user row of the minimal kind, and the scope for it.

    let makeUser(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { new Scope(User.fromRow(row)) } else { bubble() }
    }

    let userIdOf(scope: Scope): Int throws Bubble { scope.userId }

## Works

A draft created through the public function; a failure to create is a test
failure.

    let makeWork(db: Db, scope: Scope, title: String, body: String): Work throws Bubble {
      let r = worksCreateWork(db, scope, workParams(title, body));
      let w = r.ok;
      if (w != null) { w } else {
        console.log("makeWork failed: ${orNull(r.error)}");
        bubble()
      }
    }

The first section of a work.

    let firstSection(db: Db, work: Work): Section throws Bubble {
      worksListSections(db, work.id)[0]
    }

The paragraph of `section` that contains `lead`.

    let blockWith(section: Section, lead: String): String {
      let ps = paragraphs(section.body);
      var i = 0;
      while (i < ps.length) {
        if (hasText(ps[i], lead)) { return ps[i]; }
        i += 1;
      }
      ""
    }

A beat in a section, with a quote.

    let addBeat(db: Db, work: Work, section: Section, title: String, quote: String?): GraphNode throws Bubble {
      let p = new NodeParams(work.id, "beat", title);
      p.sectionId = section.id;
      p.quote = quote;
      let node = worksInsertNode(db, p).node;
      if (node != null) { node } else { bubble() }
    }

    let didBubble(db: Db, sql: String): Boolean {
      do { db.exec(sql, []); false } orelse true
    }

    let count(db: Db, sql: String): Int throws Bubble {
      let row = db.one(sql, []);
      if (row != null) { row.int("n") } else { -1 }
    }
