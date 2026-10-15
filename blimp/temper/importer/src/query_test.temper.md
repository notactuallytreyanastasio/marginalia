# Tests for the query language

`test/marginalia/import_query_test.exs`, ported assertion for assertion. The
query box on the choosing step runs over rows already fetched. Two things here
are worth more than the rest: an unknown qualifier has to be an error (a typo
that silently means nothing lets somebody import a hundred and forty-seven pull
requests believing they filtered to nine), and a missing date has to fail a
comparison rather than sort before everything.

The clock is injected: today is 2026-10-14.

    let keepNumbers(rows: List<ImporterPull>, q: String): String {
      let r = importerQueryFilterAt(rows, q, testToday());
      let why = r.error;
      if (why != null) { "ERROR ${why}" } else { numbersOf(r.kept) }
    }

    let expectKeep(test: Test, rows: List<ImporterPull>, q: String, want: String): Void {
      expectText(test, keepNumbers(rows, q), want);
    }

    let errorOf(q: String): String {
      let r = importerQueryFilterAt([], q, testToday());
      orNone(r.error)
    }

    let dayText(raw: String): String {
      let d = importerDateAt(raw, testToday());
      if (d != null) { importerIsoDate(d) } else { "error" }
    }

    let dayTextOn(raw: String, y: Int, m: Int, d: Int): String {
      let r = importerDateAt(raw, importerDayNumber(y, m, d));
      if (r != null) { importerIsoDate(r) } else { "error" }
    }

    let isoMinus(days: Int): String { importerIsoDate(testToday() - days) }

    let shapeRows(): List<ImporterPull> {
      let recent = isoMinus(3);
      let old = isoMinus(200);
      [
        prow(1, "Fix the parser", "closed", recent, "2025-02-01T00:00:00Z"),
        prow(2, "Bump eslint", "open", recent, "2025-02-01T00:00:00Z"),
        prow(3, "Old and closed", "closed", old, "2025-02-01T00:00:00Z"),
        prow(4, "Merged lately", "merged", recent, "2025-02-01T00:00:00Z"),
      ]
    }

## The shape people actually type

    test("is:pr state:closed created:>@today-30d") { test =>
      expectKeep(test, shapeRows(), "is:pr state:closed created:>@today-30d", "1");
    }

    test("a bare word is the title, and a minus takes it away") { test =>
      expectKeep(test, shapeRows(), "fix", "1");
      expectKeep(test, shapeRows(), "-bump", "1,3,4");
    }

    test("terms are joined with and") { test =>
      expectKeep(test, shapeRows(), "state:closed created:>@today-30d -fix", "");
    }

    test("an empty query keeps everything") { test =>
      expectKeep(test, shapeRows(), "", "1,2,3,4");
      expectKeep(test, shapeRows(), "   ", "1,2,3,4");
    }

## An unknown qualifier

    test("an unknown qualifier is refused by name rather than ignored") { test =>
      let why = errorOf("stat:closed");
      expectHas(test, why, "stat");
      expectHas(test, why, "do not know");
      let direct = importerQueryFilterAt([prowDefault(1)], "stat:closed", testToday());
      expectTrue(test, direct.error != null, "an error, not an empty match");
    }

    test("the message lists what it does know") { test =>
      let why = errorOf("author:me");
      expectHas(test, why, "created");
      expectHas(test, why, "merged");
      expectText(
        test, why,
        "`author:me` — I do not know the qualifier `author`. I know is, state, draft, repo, base, head, number, created, updated, merged, and a bare word matches the title.",
      );
    }

    test("a bad value for a known qualifier says what the values are") { test =>
      expectHas(test, errorOf("state:draft"), "open, closed or merged");
      expectText(test, errorOf("state:draft"), "`state:draft` — a pull request here is open, closed or merged.");
      expectText(test, errorOf("draft:maybe"), "`draft:maybe` — true or false.");
      expectText(
        test, errorOf("is:locked"),
        "`is:locked` — I know is:pr, is:draft, is:open, is:closed and is:merged.",
      );
      expectText(test, errorOf("number:lots"), "`number:lots` — a number, or >100, <100, 10..20.");
    }

    test("is:issue is refused, because there are none here") { test =>
      expectHas(test, errorOf("is:issue"), "only pull requests");
      expectText(test, errorOf("is:issue"), "`is:issue` — there are only pull requests here.");
    }

    test("is:pr is accepted and does nothing") { test =>
      expectKeep(test, [prowDefault(7)], "is:pr", "7");
      expectKeep(test, [prowDefault(7)], "-is:pr", "7");
    }

## Dates

    test("@today and its offsets") { test =>
      expectText(test, dayText("@today"), importerIsoDate(testToday()));
      expectText(test, dayText("@today-30d"), isoMinus(30));
      expectText(test, dayText("@today-2w"), isoMinus(14));
      expectText(test, dayText("@today+7d"), isoMinus(-7));
    }

    test("a month offset is calendar months, clamped to a real day") { test =>
      expectText(test, dayTextOn("@today-1m", 2025, 3, 31), "2025-02-28");
      expectText(test, dayTextOn("@today-6m", 2025, 8, 5), "2025-02-05");
      expectText(test, dayTextOn("@today-1y", 2025, 8, 5), "2024-08-05");
      expectText(test, dayTextOn("@today-1y", 2024, 2, 29), "2023-02-28");
      expectText(test, dayTextOn("@today+1m", 2025, 12, 31), "2026-01-31");
      expectText(test, dayTextOn("@today-3m", 2025, 1, 15), "2024-10-15");
    }

    test("an absolute date, and something that is not one") { test =>
      expectText(test, dayText("2025-08-05"), "2025-08-05");
      expectText(test, dayText("last tuesday"), "error");
      expectText(test, dayText("@today-3fortnights"), "error");
      expectText(test, dayText("2025-02-30"), "error");
      expectText(test, dayText("2025-8-5"), "error");
      expectText(test, dayText("@Today"), "error");
      expectText(test, dayText("  2025-08-05  "), "2025-08-05");
    }

    test("a date that will not parse is named in the error") { test =>
      let why = errorOf("created:>yesterday");
      expectHas(test, why, "yesterday");
      expectHas(test, why, "@today-30d");
      expectText(
        test, why,
        "`created:>yesterday` — yesterday is not a date. Write 2025-08-05, or @today, or @today-30d, and compare with > < >= <= or a .. range.",
      );
      expectHas(test, errorOf("merged:2025-01-01..never"), "never is not a date");
    }

    test("ranges, open at either end") { test =>
      let rows = [
        prow(1, "A", "merged", null, "2025-03-01T00:00:00Z"),
        prow(2, "B", "merged", null, "2025-06-01T00:00:00Z"),
        prow(3, "C", "merged", null, "2025-09-01T00:00:00Z"),
      ];
      expectKeep(test, rows, "merged:2025-04-01..2025-08-01", "2");
      expectKeep(test, rows, "merged:2025-04-01..*", "2,3");
      expectKeep(test, rows, "merged:*..2025-04-01", "1");
      expectKeep(test, rows, "merged:2025-06-01", "2");
      expectKeep(test, rows, "merged:>=2025-06-01", "2,3");
      expectKeep(test, rows, "merged:<=2025-06-01", "1,2");
      expectKeep(test, rows, "merged:<2025-06-01", "1");
    }

    test("a pull request that was never merged fails every merged comparison") { test =>
      let rows = [
        prow(1, "A", "open", null, null),
        prow(2, "B", "merged", null, "2025-06-01T00:00:00Z"),
      ];
      expectKeep(test, rows, "merged:>2020-01-01", "2");
      expectKeep(test, rows, "merged:<2030-01-01", "2");
      expectKeep(test, rows, "-merged:>2020-01-01", "1");
    }

    test("a date is the first ten characters of the stored timestamp") { test =>
      let rows = [prow(1, "A", "merged", "2025-06-01T23:59:59Z", null)];
      expectKeep(test, rows, "created:2025-06-01", "1");
      expectKeep(test, rows, "created:2025-06-02", "");
      expectKeep(test, [prow(2, "B", "merged", "garbage", null)], "created:>2000-01-01", "");
    }

## The other qualifiers

    test("state and is agree with each other") { test =>
      let rows = [prow(1, "A", "open", null, null), prow(2, "B", "merged", null, null)];
      expectKeep(test, rows, "is:open", "1");
      expectKeep(test, rows, "state:open", "1");
      expectKeep(test, rows, "is:merged", "2");
      expectKeep(test, rows, "IS:merged", "2");
      expectHas(test, keepNumbers(rows, "is:Merged"), "ERROR");
    }

    test("a pull request with no state counts as open") { test =>
      let unset = new ImporterPull("a/b", 5, "T", null, null, false, null, null, null, null, null);
      expectKeep(test, [unset], "state:open", "5");
      expectKeep(test, [unset], "state:closed", "");
    }

    test("draft, both ways round") { test =>
      let rows = [
        new ImporterPull("a/b", 1, "A", null, "open", true, "main", "x", null, null, null),
        new ImporterPull("a/b", 2, "B", null, "open", false, "main", "y", null, null, null),
      ];
      expectKeep(test, rows, "is:draft", "1");
      expectKeep(test, rows, "draft:true", "1");
      expectKeep(test, rows, "draft:yes", "1");
      expectKeep(test, rows, "draft:false", "2");
      expectKeep(test, rows, "draft:no", "2");
      expectKeep(test, rows, "-is:draft", "2");
    }

    test("repo, base and head are exact and case insensitive") { test =>
      let rows = [
        new ImporterPull("phoenixframework/phoenix", 1, "A", null, "open", false, "main", "x", null, null, null),
        new ImporterPull("elixir-lang/elixir", 2, "B", null, "open", false, "v1.19", "y", null, null, null),
      ];
      expectKeep(test, rows, "repo:PhoenixFramework/Phoenix", "1");
      expectKeep(test, rows, "base:v1.19", "2");
      expectKeep(test, rows, "head:Y", "2");
      expectKeep(test, rows, "repo:phoenix", "");
    }

    test("number compares as a number, not as a string") { test =>
      let rows = [prowDefault(9), prowDefault(100), prowDefault(1000)];
      expectKeep(test, rows, "number:>90", "100,1000");
      expectKeep(test, rows, "number:9..100", "9,100");
      expectKeep(test, rows, "number:1000", "1000");
      expectKeep(test, rows, "number:<=100", "9,100");
      expectKeep(test, rows, "number:*..100", "9,100");
      expectKeep(test, rows, "number:100..*", "100,1000");
    }

    test("the value of a qualifier may be quoted") { test =>
      expectKeep(test, [prowDefault(3)], "state:\"merged\"", "3");
    }

    test("a colon at the start makes the whole token a word") { test =>
      let rows = [prow(1, "a :colon here", "open", null, null), prow(2, "no", "open", null, null)];
      expectKeep(test, rows, ":colon", "1");
    }

    test("a bare dash is a word that nothing contains") { test =>
      let rows = [prow(1, "a", "open", null, null)];
      expectKeep(test, rows, "-", "");
    }

    test("a quoted phrase is one term") { test =>
      let rows = [
        prow(1, "add a precommit alias", "open", null, null),
        prow(2, "alias the precommit hook", "open", null, null),
        prow(3, "add a guide", "open", null, null),
      ];
      expectKeep(test, rows, "\"precommit alias\"", "1");
      expectKeep(test, rows, "precommit alias", "1,2");
      expectKeep(test, rows, "\"\" add", "1,3");
    }

    test("the parse is a list of terms, and an empty one is no terms") { test =>
      let q = importerQueryParseAt("is:pr fix -bump state:open", testToday());
      expectInt(test, q.terms.length, 3);
      expectTrue(test, q.error == null, "parses");
      expectTrue(test, q.terms[1].negated, "the minus is kept");
      expectInt(test, importerQueryParseAt("", testToday()).terms.length, 0);
      expectTrue(test, importerQueryParseAt("nope:1", testToday()).error != null, "unknown key");
    }

    test("a parsed query matches one row at a time") { test =>
      let q = importerQueryParseAt("repo:phoenixframework/phoenix number:>50", testToday());
      expectTrue(test, importerQueryMatch(q, prowDefault(100)), "100 matches");
      expectFalse(test, importerQueryMatch(q, prowDefault(7)), "7 does not");
    }

## Expanding @today for GitHub

    test("the query from the report, which GitHub answers 422") { test =>
      expectText(
        test,
        importerExpandAt("repo:phoenixframework/phoenix state:closed created:>@today-30d", testToday()),
        "repo:phoenixframework/phoenix state:closed created:>${isoMinus(30)}",
      );
    }

    test("every unit, and more than one in a query") { test =>
      expectText(
        test,
        importerExpandAt("created:>@today-7d merged:<@today", testToday()),
        "created:>${isoMinus(7)} merged:<${isoMinus(0)}",
      );
      expectText(test, importerExpandAt("@today-2w", testToday()), isoMinus(14));
      expectText(test, importerExpandAt("@today+1d", testToday()), isoMinus(-1));
      expectText(test, importerExpandAt("@today-1y", testToday()), "2025-10-14");
      expectText(test, importerExpandAt("@today-1m", testToday()), "2026-09-14");
    }

    test("a range with both ends relative") { test =>
      expectText(
        test,
        importerExpandAt("merged:@today-60d..@today-30d", testToday()),
        "merged:${isoMinus(60)}..${isoMinus(30)}",
      );
    }

    test("everything else is left exactly as it was") { test =>
      let queries = [
        "repo:phoenixframework/phoenix is:pr",
        "created:>2025-08-05",
        "label:\"needs review\" -Bump",
        "",
      ];
      var i = 0;
      while (i < queries.length) {
        expectText(test, importerExpandAt(queries[i], testToday()), queries[i]);
        i += 1;
      }
    }

    test("something that looks like @today but is not is left alone") { test =>
      expectHas(test, importerExpandAt("@today-3fortnights", testToday()), "@today-3fortnights");
      expectHas(test, importerExpandAt("@todays", testToday()), "@today");
      expectText(test, importerExpandAt("@todays", testToday()), "@todays");
      expectText(test, importerExpandAt("@today_x", testToday()), "@today_x");
    }

    test("the expression is case insensitive, and a trailing plus is not part of it") { test =>
      expectText(test, importerExpandAt("@TODAY-1D", testToday()), isoMinus(1));
      expectText(test, importerExpandAt("@today+7dx", testToday()), "${isoMinus(0)}+7dx");
      expectText(test, importerExpandAt("a @today b", testToday()), "a ${isoMinus(0)} b");
    }

    test("expand with the real clock is a date of the right shape") { test =>
      let out = importerExpand("@today");
      expectInt(test, out.countBetween(String.begin, out.end), 10);
      expectText(test, importerIsoDate(orZero(importerParseIso(out))), out);
    }

## Why nothing matched

    test("a bare relative date is the trap, and it is named") { test =>
      let h = importerQueryHint("created:@today-90d");
      expectText(test, if (h != null) { h.was } else { "none" }, "created:@today-90d");
      expectText(test, if (h != null) { h.tryThis } else { "none" }, "created:>@today-90d");
    }

    test("an absolute one too") { test =>
      let h = importerQueryHint("merged:2025-08-05");
      expectText(test, if (h != null) { h.tryThis } else { "none" }, "merged:>2025-08-05");
    }

    test("nothing to say about a query that already compares") { test =>
      expectTrue(test, importerQueryHint("created:>@today-90d") == null, "greater");
      expectTrue(test, importerQueryHint("created:>=2025-01-01") == null, "greater or equal");
      expectTrue(test, importerQueryHint("created:<2025-01-01") == null, "less");
    }

    test("nothing to say about a range either") { test =>
      expectTrue(test, importerQueryHint("merged:2025-04-01..2025-08-05") == null, "absolute");
      expectTrue(test, importerQueryHint("merged:@today-60d..@today-30d") == null, "relative");
    }

    test("nothing to say when there is no date in it at all") { test =>
      expectTrue(test, importerQueryHint("state:closed -Bump") == null, "no date");
      expectTrue(test, importerQueryHint("") == null, "empty");
    }

    test("the date is found among other terms") { test =>
      let h = importerQueryHint("is:pr state:closed created:@today-90d -Bump");
      expectText(test, if (h != null) { h.tryThis } else { "none" }, "created:>@today-90d");
      expectTrue(test, importerQueryHint("xcreated:2025-01-01") == null, "a word boundary is needed");
    }
