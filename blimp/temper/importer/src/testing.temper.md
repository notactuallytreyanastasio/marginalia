# What the importer tests share

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
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

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let expectHas(test: Test, s: String, part: String): Void {
      assert(hasText(s, part)) { "expected ${part} in:\n${s}" }
    }

    let expectLacks(test: Test, s: String, part: String): Void {
      assert(!hasText(s, part)) { "did not expect ${part} in:\n${s}" }
    }

    let orNone(s: String?): String { if (s != null) { s } else { "<none>" } }

    let orZero(n: Int?): Int { if (n != null) { n } else { -1 } }

    let joinedNums(xs: List<Int>): String {
      sysJoin(xs.map { (n: Int): String => n.toString() }, ",")
    }

    let joinedText(xs: List<String>): String { sysJoin(xs, "|") }

`word ` repeated `n` times, by doubling, since a loop of appends is quadratic.

    let repeated(unit: String, n: Int): String {
      if (n <= 0) { return ""; }
      if (n == 1) { return unit; }
      let half = repeated(unit, n / 2);
      if (n % 2 == 0) { "${half}${half}" } else { "${half}${half}${unit}" }
    }

## Users

    let makeUser(db: Db, email: String): Scope throws Bubble {
      let id = db.insert("INSERT INTO users (email, hashed_password) VALUES ($1, 'x')", [email]);
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { new Scope(User.fromRow(row)) } else { bubble() }
    }

## Pull request rows

The defaults of the Elixir's `pr/1`: `phoenixframework/phoenix`, `A change`,
merged, not a draft, `main` from `topic`, created 2025-01-01 and merged
2025-02-01.

    let prow(number: Int, title: String, state: String, created: String?, merged: String?): ImporterPull {
      new ImporterPull(
        "phoenixframework/phoenix", number, title, null, state, false, "main", "topic",
        "2025-02-01T00:00:00Z", created, merged,
      )
    }

    let prowDefault(number: Int): ImporterPull {
      prow(number, "A change", "merged", "2025-01-01T00:00:00Z", "2025-02-01T00:00:00Z")
    }

    let numbersOf(pulls: List<ImporterPull>): String {
      joinedNums(pulls.map { (p: ImporterPull): Int => p.number })
    }

    let titlesOf(pulls: List<ImporterPull>): String {
      joinedText(pulls.map { (p: ImporterPull): String => p.title })
    }

## The clock

The tests run on a fixed day, so `@today` is something to assert about.

    let testToday(): Int { importerDayNumber(2026, 10, 14) }
