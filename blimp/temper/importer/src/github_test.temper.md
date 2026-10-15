# Tests for the GitHub importer

`github_stack_test`, `github_access_test` (without its `:network` tests, which
need the live API and are skipped) and `github_document_test`, ported
assertion for assertion; then the fetching functions against a fake
`ImporterHttp`, which is `FakeHub` with the HTTP boundary moved down: the fake
answers canned `(url pattern, status, body)` and remembers what it was asked.

    let { sysGraphemeLength } = import("sys/src");
    let { Folder, foldersCreateFolder } = import("folders/src");
    let { Db, dbOpen } = import("db/src");

    let api = "https://api.github.com";

## The chain

    let pr(number: Int, head: String, base: String): ImporterRaw {
      importerPullRaw(number, head, base, "PR ${number.toString()}", "body ${number.toString()}", "https://example.invalid/pull/${number.toString()}")
    }

    let orderedNumbers(o: ImporterOrdered): String {
      joinedNums(o.items.map { (i: ImporterItem): Int => i.number })
    }

    let orderedOrdinals(o: ImporterOrdered): String {
      joinedNums(o.items.map { (i: ImporterItem): Int => i.ordinal })
    }

    let errKind(e: ImporterError?): String {
      if (e != null) { e.kind } else { "ok" }
    }

    test("the order comes from the chain, not from the listing") { test =>
      let o = importerOrder([pr(3, "c", "b"), pr(1, "a", "main"), pr(2, "b", "a")], "main");
      expectText(test, errKind(o.error), "ok");
      expectText(test, orderedNumbers(o), "1,2,3");
      expectText(test, orderedOrdinals(o), "1,2,3");
    }

    test("the numbers do not have to agree with the order") { test =>
      let o = importerOrder([pr(90, "b", "a"), pr(12, "a", "main"), pr(7, "c", "b")], "main");
      expectText(test, orderedNumbers(o), "12,90,7");
    }

    test("two pull requests on the default branch are two stacks, and it says so") { test =>
      let o = importerOrder([pr(1, "a", "main"), pr(2, "b", "main")], "main");
      let e = o.error;
      expectText(test, errKind(e), "many_roots");
      expectText(test, joinedNums(if (e != null) { e.numbers } else { [] }), "1,2");
      expectHas(test, importerExplain(if (e != null) { e } else { importerError("x") }), "more than one stack");
    }

    test("a pull request off the chain is named, not dropped") { test =>
      let o = importerOrder([pr(1, "a", "main"), pr(2, "b", "a"), pr(9, "stray", "somewhere-else")], "main");
      let e = o.error;
      expectText(test, errKind(e), "off_chain");
      expectText(test, joinedNums(if (e != null) { e.numbers } else { [] }), "9");
      expectHas(test, importerExplain(importerErrorNumbers("off_chain", [9])), "#9");
      expectText(
        test, importerExplain(importerErrorNumbers("off_chain", [4, 9])),
        "2 pull request(s) are not on the chain: #4, #9. A stack is each one based on the one before it.",
      );
    }

    test("nothing based on the default branch is no start to the chain") { test =>
      let o = importerOrder([pr(1, "a", "zzz")], "main");
      let e = o.error;
      expectText(test, errKind(e), "no_root");
      expectText(test, orNone(if (e != null) { e.text } else { null }), "main");
      expectHas(test, importerExplain(importerErrorText("no_root", "main")), "no start");
      expectText(
        test, importerExplain(importerErrorText("no_root", "main")),
        "No open pull request is based on main, so there is no start to the chain.",
      );
    }

    test("an empty repository is refused rather than imported as nothing") { test =>
      expectText(test, errKind(importerOrder([], "main").error), "no_pull_requests");
    }

    test("two pull requests from one branch is not a stack") { test =>
      let o = importerOrder([pr(1, "a", "main"), pr(2, "b", "a"), pr(3, "a", "b")], "main");
      let e = o.error;
      expectText(test, errKind(e), "duplicate_branches");
      expectText(test, joinedText(if (e != null) { e.texts } else { [] }), "a");
      expectHas(
        test, importerExplain(importerErrorTexts("duplicate_branches", ["a"])),
        "one pull request per branch",
      );
    }

    test("a chain that loops terminates rather than hanging") { test =>
      let o = importerOrder([pr(1, "a", "main"), pr(2, "b", "c"), pr(3, "c", "b")], "main");
      expectText(test, errKind(o.error), "off_chain");
      expectText(test, joinedNums(o.items.map { (i: ImporterItem): Int => i.number }), "");
    }

    test("a chain that points back at itself stops at the repeat") { test =>
      let o = importerOrder([pr(1, "a", "main"), pr(2, "main", "a")], "main");
      expectText(test, orderedNumbers(o), "1,2");
    }

    test("the order of a stack also gives each item its body and address") { test =>
      let o = importerOrder([pr(2, "b", "a"), pr(1, "a", "main")], "main");
      expectText(test, o.items[0].body, "body 1");
      expectText(test, o.items[1].url, "https://example.invalid/pull/2");
      expectText(test, o.items[1].title, "PR 2");
    }

    test("every error explains itself in words someone can act on") { test =>
      let errors = [
        importerError("unauthorized"),
        importerError("forbidden"),
        importerError("not_found"),
        importerError("bad_name"),
        importerError("no_pull_requests"),
        importerError("empty_query"),
        importerError("no_results_field"),
        importerErrorNumber("http", 500),
        importerErrorText("transport", "x"),
        importerErrorText("no_root", "main"),
        importerErrorTexts("duplicate_branches", ["a"]),
        importerErrorNumbers("off_chain", [1]),
        importerErrorNumbers("many_roots", [1, 2]),
        importerErrorText("crashed", "boom"),
        importerErrorText("rejected", null),
        importerError("something_else"),
      ];
      var i = 0;
      while (i < errors.length) {
        let said = importerExplain(errors[i]);
        expectFalse(test, said.isEmpty, "explains ${errors[i].kind}");
        i += 1;
      }
      expectText(test, importerExplain(importerError("unauthorized")), "GitHub rejected the token.");
      expectText(test, importerExplain(importerError("not_found")), "No such repository, or the token cannot see it.");
      expectText(test, importerExplain(importerError("bad_name")), "Owner and repository must look like GitHub names.");
      expectText(test, importerExplain(importerErrorNumber("http", 500)), "GitHub answered 500.");
      expectText(test, importerExplain(importerErrorText("transport", "x")), "Could not reach GitHub.");
      expectText(test, importerExplain(importerError("no_pull_requests")), "That repository has no open pull requests.");
      expectText(test, importerExplain(importerError("empty_query")), "Write a search query first.");
      expectText(test, importerExplain(importerErrorText("crashed", "z")), "That one crashed on the way in.");
      expectText(
        test, importerExplain(importerErrorNumbers("many_roots", [1, 2])),
        "2 pull requests are based on the default branch (#1, #2). That is more than one stack, and this cannot tell which you meant.",
      );
      expectText(
        test, importerExplain(importerErrorTexts("duplicate_branches", ["a", "b"])),
        "More than one open pull request comes from the same branch (a, b). A stack is one pull request per branch.",
      );
      expectText(
        test, importerExplain(importerError("something_else")),
        "Import failed: :something_else",
      );
      expectText(
        test, importerExplain(importerError("no_results_field")),
        "GitHub answered the search with something this does not recognise.",
      );
    }

## What a refusal is called

    let nowAt(): Int { 1760000000 }

    test("a rate limit says when it comes back, not that access was denied") { test =>
      let said = importerExplainAt(importerErrorText("rate_limited", (nowAt() + 600).toString()), nowAt());
      expectHas(test, said, "rate limiting");
      expectHas(test, said, "UTC");
      expectHas(test, said, "in 10m0s");
      expectHas(test, said, "It comes back at 09:03 UTC");
      expectLacks(test, said, "may lack access");
    }

    test("a reset already past reads as a wait of nothing, not a negative one") { test =>
      expectHas(
        test,
        importerExplainAt(importerErrorText("rate_limited", (nowAt() - 60).toString()), nowAt()),
        "in 0m0s",
      );
    }

    test("a rate limit with no header still says something usable") { test =>
      expectHas(test, importerExplainAt(importerErrorText("rate_limited", null), nowAt()), "few minutes");
      expectHas(test, importerExplainAt(importerErrorText("rate_limited", "soon"), nowAt()), "few minutes");
    }

    test("a query GitHub will not run is quoted back in its own words") { test =>
      let said = importerExplain(importerErrorText(
        "rejected", "\"@today-30d\" is not a recognized date/time format",
      ));
      expectHas(test, said, "would not run that search");
      expectHas(test, said, "not a recognized date/time format");
      expectLacks(test, said, "422");
    }

    test("a refusal with nothing to quote still says what to look at") { test =>
      expectHas(test, importerExplain(importerErrorText("rejected", null)), "qualifiers and the dates");
    }

    test("a real refusal still names the two reasons it happens") { test =>
      let said = importerExplain(importerError("forbidden"));
      expectHas(test, said, "may lack access");
      expectHas(test, said, "60 requests an hour");
    }

    test("both mention the allowance, since that is what a bulk import hits") { test =>
      expectHas(
        test,
        importerExplainAt(importerErrorText("rate_limited", (nowAt() + 60).toString()), nowAt()),
        "5000",
      );
    }

## The order the documents land in

    let landed(number: Int, merged: String?, created: String?): ImporterPull {
      new ImporterPull("a/b", number, "PR ${number.toString()}", null, "merged", false, null, null, null, created, merged)
    }

    test("oldest first, by when it landed") { test =>
      let rows = [
        landed(9, "2025-08-01T00:00:00Z", "2025-01-01T00:00:00Z"),
        landed(7, "2025-04-01T00:00:00Z", "2025-01-01T00:00:00Z"),
        landed(8, "2025-06-01T00:00:00Z", "2025-01-01T00:00:00Z"),
      ];
      expectText(test, numbersOf(importerOldestFirst(rows)), "7,8,9");
    }

    test("merge order, not number order, when they disagree") { test =>
      let january = landed(1, "2025-07-01T00:00:00Z", "2025-01-01T00:00:00Z");
      let june = landed(90, "2025-06-01T00:00:00Z", "2025-06-01T00:00:00Z");
      expectText(test, numbersOf(importerOldestFirst([january, june])), "90,1");
    }

    test("an unmerged one sorts by when it was opened") { test =>
      let open = landed(5, null, "2025-05-01T00:00:00Z");
      let merged = landed(4, "2025-09-01T00:00:00Z", "2025-01-01T00:00:00Z");
      expectText(test, numbersOf(importerOldestFirst([merged, open])), "5,4");
    }

    test("the sort is total, so a re-listing does not shuffle") { test =>
      let same = [
        landed(3, "2025-04-01T00:00:00Z", null),
        landed(1, "2025-04-01T00:00:00Z", null),
        landed(2, "2025-04-01T00:00:00Z", null),
      ];
      expectText(test, numbersOf(importerOldestFirst(same)), "1,2,3");
      expectText(test, numbersOf(importerOldestFirst([same[2], same[1], same[0]])), "1,2,3");
    }

## What one pull request becomes

    let prItem(): ImporterItem {
      new ImporterItem(
        1, 7, "7. A guard that took too much",
        "The guard was too wide, so three responses came back with no body.",
        "https://github.com/o/r/pull/7",
      )
    }

    let withCommits(commits: List<ImporterCommit>): ImporterItem {
      let i = prItem();
      i.commits = commits;
      i
    }

    let itemFiles(files: List<ImporterFile>, changed: Int?): ImporterItem {
      let i = prItem();
      i.files = files;
      i.changedFiles = changed;
      i
    }

    let itemFilesError(text: String): ImporterItem {
      let i = prItem();
      i.filesError = text;
      i
    }

    let itemCommitsError(text: String): ImporterItem {
      let i = prItem();
      i.commitsError = text;
      i
    }

    let itemBoth(commits: List<ImporterCommit>, files: List<ImporterFile>, changed: Int?): ImporterItem {
      let i = prItem();
      i.commits = commits;
      i.files = files;
      i.changedFiles = changed;
      i
    }

    let bareItem(commits: List<ImporterCommit>): ImporterItem {
      let i = new ImporterItem(1, 7, "7. A guard that took too much", "", "https://github.com/o/r/pull/7");
      i.commits = commits;
      i
    }

    let argumentItem(argument: String, commits: List<ImporterCommit>): ImporterItem {
      let i = new ImporterItem(1, 7, "t", argument, "u");
      i.commits = commits;
      i
    }

    let commit(subject: String, detail: String): ImporterCommit {
      new ImporterCommit(
        "abc12345",
        if (detail.isEmpty) { subject } else { "${subject}\n\n${detail}" },
      )
    }

    let file(path: String, status: String, added: Int, removed: Int): ImporterFile {
      new ImporterFile(path, null, status, added, removed)
    }

    let indexOf(s: String, needle: String): Int {
      let parts = s.split(needle);
      if (parts.length < 2) { -1 } else { importerCpCount(parts[0]) }
    }

    test("the writeup comes first and the commits follow it") { test =>
      let doc = importerDocument(withCommits([commit("be-blimp: narrow the guard", "")]));
      expectHas(test, doc, "The guard was too wide");
      expectHas(test, doc, "## Commits (1)");
      expectHas(test, doc, "be-blimp: narrow the guard");
      expectTrue(
        test, indexOf(doc, "The guard was too wide") < indexOf(doc, "## Commits"),
        "the argument has to survive the window Stacks.text_of/1 reads",
      );
    }

    test("a commit message keeps its body, which is where the reasoning lives") { test =>
      let why = "The obvious version drops the last frame, because the reader is closed first.";
      let doc = importerDocument(withCommits([commit("be-blimp: close the reader last", why)]));
      expectHas(test, doc, why);
      expectHas(test, doc, "### be-blimp: close the reader last  (abc12345)\n\n${why}");
    }

    test("the short sha rides along, so a claim can be chased") { test =>
      let doc = importerDocument(withCommits([commit("be-blimp: narrow the guard", "")]));
      expectHas(test, doc, "(abc12345)");
    }

    test("a pull request with no description still carries its commits") { test =>
      let doc = importerDocument(bareItem([commit("be-blimp: narrow the guard", "")]));
      expectHas(test, doc, "has no description");
      expectHas(test, doc, "be-blimp: narrow the guard");
      expectHas(test, doc, "_This pull request (#7) has no description._\n\nhttps://github.com/o/r/pull/7\n");
    }

    test("no commits adds no section at all") { test =>
      let doc = importerDocument(withCommits([]));
      expectLacks(test, doc, "## Commits");
      expectHas(test, doc, "The guard was too wide");
      expectText(test, doc, "The guard was too wide, so three responses came back with no body.");
    }

    test("a failed commit fetch says so in the document rather than looking empty") { test =>
      let doc = importerDocument(itemCommitsError("{:http, 502}"));
      expectHas(test, doc, "could not be fetched");
      expectHas(test, doc, "502");
      expectLacks(test, doc, "## Commits (0)");
      expectHas(test, doc, "so this chapter is its description alone.");
    }

    test("a very long trail is cut, and says it was cut") { test =>
      let many = new ListBuilder<ImporterCommit>();
      var n = 1;
      while (n <= 400) {
        many.add(commit("commit ${n.toString()}", repeated("detail ", 40)));
        n += 1;
      }
      let doc = importerDocument(withCommits(many.toList()));
      expectHas(test, doc, "commit trail truncated");
      expectHas(test, doc, "## Commits (400)");
      expectTrue(test, sysGraphemeLength(doc) < 14000, "the whole document has to fit the window Stacks.text_of/1 reads");
    }

    test("the writeup is never what gets cut") { test =>
      let argument = "This is the load-bearing sentence of the chapter.";
      let many = new ListBuilder<ImporterCommit>();
      var n = 1;
      while (n <= 400) {
        many.add(commit("commit ${n.toString()}", repeated("detail ", 40)));
        n += 1;
      }
      expectHas(test, importerDocument(argumentItem(argument, many.toList())), argument);
    }

    test("paths and line counts, between the argument and the commits") { test =>
      let doc = importerDocument(itemBoth(
        [commit("narrow the guard", "")],
        [file("lib/a.ex", "modified", 3, 1), file("lib/b.ex", "added", 96, 0)],
        2,
      ));
      expectHas(test, doc, "## Files changed (2)");
      expectHas(test, doc, "- `lib/a.ex` +3 −1");
      expectHas(test, doc, "- `lib/b.ex` +96 — new");
      expectTrue(
        test, indexOf(doc, "The guard was too wide") < indexOf(doc, "## Files changed"),
        "the argument still comes first",
      );
      expectTrue(
        test, indexOf(doc, "## Files changed") < indexOf(doc, "## Commits"),
        "the paths are an index; the commits are the story",
      );
    }

    test("no diff hunks, however the response arrived") { test =>
      let doc = importerDocument(itemFiles([file("lib/a.ex", "modified", 3, 1)], 1));
      expectLacks(test, doc, "@@");
      expectLacks(test, doc, "+++");
      expectLacks(test, doc, "patch");
    }

    test("a rename reads as one, not as two files") { test =>
      let i = itemFiles([new ImporterFile("test/cases_test.exs", "test/case_test.exs", "renamed", 2, 2)], 1);
      expectHas(
        test, importerDocument(i),
        "- `test/case_test.exs` → `test/cases_test.exs` +2 −2",
      );
    }

    test("a file with no line changes says nothing about lines") { test =>
      let doc = importerDocument(itemFiles([file(".formatter.exs", "modified", 0, 0)], null));
      expectTrue(test, hasText(doc, "- `.formatter.exs`\n") || importerEndsWith(doc, "- `.formatter.exs`"), "plain line");
      expectLacks(test, doc, "+0");
    }

    test("a deleted file is not reported as three added lines") { test =>
      let i = itemFiles([file("lib/gone.ex", "removed", 0, 40)], null);
      expectHas(test, importerDocument(i), "- `lib/gone.ex` −40 — deleted");
    }

    test("the header counts what the pull request touched, not what fitted") { test =>
      let many = new ListBuilder<ImporterFile>();
      var n = 1;
      while (n <= 80) {
        many.add(file("lib/f${n.toString()}.ex", "modified", 3, 1));
        n += 1;
      }
      let doc = importerDocument(itemFiles(many.toList(), 326));
      expectHas(test, doc, "## Files changed (326, the first 60 listed)");
      expectHas(test, doc, "`lib/f60.ex`");
      expectLacks(test, doc, "`lib/f61.ex`");
    }

    test("a pull request with no file list is a document without the section") { test =>
      expectLacks(test, importerDocument(withCommits([commit("x", "")])), "Files changed");
    }

    test("a fetch that failed says so rather than looking like no files") { test =>
      let doc = importerDocument(itemFilesError(":forbidden"));
      expectHas(test, doc, "## Files changed");
      expectHas(test, doc, "could not be fetched");
      expectHas(test, doc, "forbidden");
    }

## The requests

A fake answering the way GitHub does.

    let jpull(number: Int, title: String, head: String, base: String, state: String, merged: String?): String {
      let m = if (merged != null) { "\"${merged}\"" } else { "null" };
      "{\"number\":${number.toString()},\"title\":\"${title}\",\"body\":\"body ${number.toString()}\",\"html_url\":\"https://example.invalid/pull/${number.toString()}\",\"state\":\"${state}\",\"draft\":false,\"base\":{\"ref\":\"${base}\"},\"head\":{\"ref\":\"${head}\"},\"created_at\":\"2025-01-01T00:00:00Z\",\"updated_at\":\"2025-02-01T00:00:00Z\",\"merged_at\":${m},\"changed_files\":2}"
    }

    let jarray(items: List<String>): String { "[${sysJoin(items, ",")}]" }

    let jcommits(): String {
      "[{\"sha\":\"abcdef0123456789\",\"commit\":{\"message\":\"first subject\\n\\nwhy it was done\"}},{\"sha\":\"1234567890abcdef\",\"commit\":{\"message\":\"second subject\"}}]"
    }

    let hundred(): String {
      let items = new ListBuilder<String>();
      var n = 1;
      while (n <= 100) {
        items.add("{\"number\":${n.toString()}}");
        n += 1;
      }
      jarray(items.toList())
    }

    let listedNumbers(l: ImporterListed): String {
      let e = l.error;
      if (e != null) { "ERROR ${e.kind}" } else { numbersOf(l.pulls) }
    }

    test("a listing asks for every state and names its rows") { test =>
      let http = importerFake([
        importerRoute(
          "/repos/o/r/pulls?state=all&per_page=100&page=1", 200,
          jarray([
            jpull(9, "Fix the parser", "b9", "main", "closed", "2025-04-01T00:00:00Z"),
            jpull(8, "Revert the fix", "b8", "main", "open", null),
          ]),
        ),
      ]);
      let l = importerListPulls(http, "o/r", "t", "all");
      expectText(test, listedNumbers(l), "9,8");
      expectText(test, l.pulls[0].repo, "o/r");
      expectText(test, orNone(l.pulls[0].state), "merged");
      expectText(test, orNone(l.pulls[1].state), "open");
      expectText(test, orNone(l.pulls[0].base), "main");
      expectText(test, orNone(l.pulls[0].head), "b9");
      expectText(test, orNone(l.pulls[0].url), "https://example.invalid/pull/9");
      expectText(test, orNone(l.pulls[0].mergedAt), "2025-04-01T00:00:00Z");
      expectTrue(test, l.pulls[1].mergedAt == null, "not merged");
      expectInt(test, http.sent().length, 1);
      expectText(test, http.sent()[0], "${api}/repos/o/r/pulls?state=all&per_page=100&page=1");
    }

    test("the token goes out as a bearer, and an empty one does not") { test =>
      let routes = [importerRoute("/pulls", 200, "[]")];
      let a = importerFake(routes);
      importerList(a, "o", "r", "secret", "all");
      expectHas(test, a.sentHeaders()[0], "authorization: Bearer secret");
      expectHas(test, a.sentHeaders()[0], "accept: application/vnd.github+json");
      expectHas(test, a.sentHeaders()[0], "x-github-api-version: 2022-11-28");
      expectHas(test, a.sentHeaders()[0], "user-agent: marginalia");
      let b = importerFake(routes);
      importerList(b, "o", "r", "", "all");
      expectLacks(test, b.sentHeaders()[0], "authorization");
      let c = importerFake(routes);
      importerList(c, "o", "r", null, "all");
      expectLacks(test, c.sentHeaders()[0], "authorization");
      let d = importerFake(routes);
      importerList(d, "o", "r", "   ", "all");
      expectLacks(test, d.sentHeaders()[0], "authorization");
      let e = importerFake(routes);
      importerList(e, "o", "r", "  padded  ", "all");
      expectHas(test, e.sentHeaders()[0], "authorization: Bearer padded");
    }

    test("owner and repository are checked, not escaped") { test =>
      let http = importerFake([importerRoute("/", 200, "[]")]);
      expectText(test, listedNumbers(importerList(http, "o/x", "r", null, "all")), "ERROR bad_name");
      expectText(test, listedNumbers(importerList(http, "o", "r r", null, "all")), "ERROR bad_name");
      expectText(test, listedNumbers(importerList(http, "", "r", null, "all")), "ERROR bad_name");
      expectText(test, listedNumbers(importerListPulls(http, "just-one-part", null, "all")), "ERROR bad_name");
      expectInt(test, http.sent().length, 0);
      expectTrue(test, importerCheckName("a.b_c-d9"), "legal characters");
      expectFalse(test, importerCheckName(repeated("x", 101)), "too long");
      expectTrue(test, importerCheckName(repeated("x", 100)), "just long enough");
    }

    test("a full page asks for the next one, a short page stops") { test =>
      let http = importerFake([
        importerRoute("&page=1", 200, hundred()),
        importerRoute("&page=2", 200, jarray([jpull(101, "last", "h101", "main", "open", null)])),
        importerRoute("&page=3", 200, "[]"),
      ]);
      let l = importerList(http, "o", "r", null, "open");
      expectInt(test, l.pulls.length, 101);
      expectInt(test, http.sent().length, 2);
    }

    test("an empty page stops the listing and keeps what came before") { test =>
      let http = importerFake([
        importerRoute("&page=1", 200, hundred()),
        importerRoute("&page=2", 200, "[]"),
      ]);
      let l = importerList(http, "o", "r", null, "open");
      expectInt(test, l.pulls.length, 100);
      expectInt(test, http.sent().length, 2);
    }

    test("a listing stops at five pages however many there are") { test =>
      let http = importerFake([importerRoute("&page=", 200, hundred())]);
      let l = importerList(http, "o", "r", null, "open");
      expectInt(test, l.pulls.length, 500);
      expectInt(test, http.sent().length, 5);
    }

    test("an error on a later page aborts the whole listing") { test =>
      let http = importerFake([
        importerRoute("&page=1", 200, hundred()),
        importerRoute("&page=2", 500, "boom"),
      ]);
      expectText(test, listedNumbers(importerList(http, "o", "r", null, "open")), "ERROR http");
    }

    let kindFor(status: Int, body: String, headers: List<String>): String {
      let http = importerFake([importerRouteWith("/pulls", status, body, headers)]);
      let l = importerList(http, "o", "r", null, "all");
      let e = l.error;
      if (e != null) { "${e.kind}:${orNone(e.text)}:${e.number.toString()}" } else { "ok" }
    }

    test("each status becomes the error it is") { test =>
      expectText(test, kindFor(401, "{}", []), "unauthorized:<none>:0");
      expectText(test, kindFor(404, "{}", []), "not_found:<none>:0");
      expectText(test, kindFor(403, "{\"message\":\"Forbidden\"}", []), "forbidden:<none>:0");
      expectText(test, kindFor(429, "{}", []), "forbidden:<none>:0");
      expectText(test, kindFor(500, "oops", []), "http:<none>:500");
      expectText(test, kindFor(418, "", []), "http:<none>:418");
      expectText(test, kindFor(200, "[]", []), "ok");
    }

    test("a 422 quotes GitHub's own sentence") { test =>
      expectText(
        test,
        kindFor(422, "{\"message\":\"Validation Failed\",\"errors\":[{\"message\":\"The listed users cannot be searched\"}]}", []),
        "rejected:The listed users cannot be searched:0",
      );
      expectText(test, kindFor(422, "{\"message\":\"Validation Failed\"}", []), "rejected:Validation Failed:0");
      expectText(test, kindFor(422, "nonsense", []), "rejected:<none>:0");
    }

    test("a 403 with the allowance spent is a rate limit, and the reset rides along") { test =>
      expectText(
        test,
        kindFor(403, "{}", ["X-RateLimit-Remaining: 0", "X-RateLimit-Reset: 1760000600"]),
        "rate_limited:1760000600:0",
      );
      expectText(test, kindFor(403, "{}", ["x-ratelimit-remaining: 0"]), "rate_limited:<none>:0");
      expectText(test, kindFor(429, "{}", ["x-ratelimit-remaining: 0"]), "rate_limited:<none>:0");
      expectText(
        test, kindFor(403, "{}", ["x-ratelimit-remaining: 12"]),
        "forbidden:<none>:0",
      );
    }

    test("with no headers to read, GitHub's rate limit message is what gives it away") { test =>
      expectText(
        test,
        kindFor(403, "{\"message\":\"API rate limit exceeded for 1.2.3.4.\"}", []),
        "rate_limited:<none>:0",
      );
      expectText(
        test,
        kindFor(403, "{\"message\":\"API rate limit exceeded\"}", ["x-ratelimit-remaining: 3"]),
        "forbidden:<none>:0",
      );
    }

    test("a request that never got an answer is a transport error") { test =>
      let http = importerFake([importerRouteFail("/pulls", "timeout")]);
      let l = importerList(http, "o", "r", null, "all");
      let e = l.error;
      expectText(test, errKind(e), "transport");
      expectText(test, orNone(if (e != null) { e.text } else { null }), "timeout");
      let none = importerFake([]);
      expectText(test, errKind(importerList(none, "o", "r", null, "all").error), "transport");
    }

    test("a listing that is not a list is refused by name") { test =>
      let http = importerFake([importerRoute("/pulls", 200, "{\"message\":\"hello\"}")]);
      expectText(test, errKind(importerList(http, "o", "r", null, "all").error), "unexpected");
    }

## Search

    let hit(repo: String, number: Int, title: String): String {
      "{\"number\":${number.toString()},\"title\":\"${title}\",\"html_url\":\"https://github.com/${repo}/pull/${number.toString()}\",\"state\":\"closed\",\"repository_url\":\"${api}/repos/${repo}\",\"created_at\":\"2025-03-01T00:00:00Z\",\"pull_request\":{\"merged_at\":\"2025-03-02T00:00:00Z\"}}"
    }

    test("a search puts is:pr on the end and writes @today as a date") { test =>
      let http = importerFake([
        importerRoute("/search/issues", 200, "{\"items\":[${hit("found/elsewhere", 4, "Fix")}]}"),
      ]);
      let l = importerSearchAt(http, "  repo:o/r state:closed created:>@today-30d ", "t", 5, testToday());
      expectText(test, listedNumbers(l), "4");
      expectText(
        test, http.sent()[0],
        "${api}/search/issues?q=repo%3Ao%2Fr+state%3Aclosed+created%3A%3E${isoMinus(30)}+is%3Apr&per_page=100&page=1",
      );
    }

    test("a search that already says is:pr is not told twice") { test =>
      let http = importerFake([importerRoute("/search/issues", 200, "{\"items\":[]}")]);
      importerSearchAt(http, "is:pr label:design", null, 5, testToday());
      expectText(test, http.sent()[0], "${api}/search/issues?q=is%3Apr+label%3Adesign&per_page=100&page=1");
    }

    test("a search result names its repository and reads merged_at from pull_request") { test =>
      let http = importerFake([
        importerRoute("/search/issues", 200, "{\"items\":[${hit("found/elsewhere", 4, "Fix")}]}"),
      ]);
      let l = importerSearchAt(http, "x", null, 5, testToday());
      expectText(test, l.pulls[0].repo, "found/elsewhere");
      expectText(test, orNone(l.pulls[0].state), "merged");
      expectText(test, orNone(l.pulls[0].mergedAt), "2025-03-02T00:00:00Z");
      expectText(test, l.pulls[0].title, "Fix");
      expectTrue(test, l.pulls[0].base == null, "a search hit has no base");
    }

    test("a blank search is refused without asking GitHub") { test =>
      let http = importerFake([]);
      expectText(test, listedNumbers(importerSearchAt(http, "   ", null, 5, testToday())), "ERROR empty_query");
      expectInt(test, http.sent().length, 0);
    }

    test("a search answered with something else is refused") { test =>
      let http = importerFake([importerRoute("/search/issues", 200, "{\"total_count\":0}")]);
      expectText(test, listedNumbers(importerSearchAt(http, "x", null, 5, testToday())), "ERROR no_results_field");
    }

    test("a search GitHub rejects says why") { test =>
      let http = importerFake([
        importerRoute(
          "/search/issues", 422,
          "{\"message\":\"Validation Failed\",\"errors\":[{\"message\":\"bad date\"}]}",
        ),
      ]);
      let l = importerSearchAt(http, "created:>whenever", null, 5, testToday());
      let e = l.error;
      expectText(test, errKind(e), "rejected");
      expectText(
        test, importerExplain(if (e != null) { e } else { importerError("x") }),
        "GitHub would not run that search: bad date",
      );
    }

    test("a search asks for no more pages than it is allowed") { test =>
      let items = new ListBuilder<String>();
      var n = 1;
      while (n <= 100) {
        items.add("{\"number\":${n.toString()}}");
        n += 1;
      }
      let page = "{\"items\":[${sysJoin(items.toList(), ",")}]}";
      let http = importerFake([importerRoute("/search/issues", 200, page)]);
      expectInt(test, importerSearchAt(http, "x", null, 2, testToday()).pulls.length, 200);
      expectInt(test, http.sent().length, 2);
      let again = importerFake([importerRoute("/search/issues", 200, page)]);
      expectInt(test, importerSearchAt(again, "x", null, 99, testToday()).pulls.length, 500);
      expectInt(test, again.sent().length, 5);
    }

    test("form encoding as URI.encode_www_form has it") { test =>
      expectText(test, importerFormEncode("a b&c=d"), "a+b%26c%3Dd");
      expectText(test, importerFormEncode("keep-._~09azAZ"), "keep-._~09azAZ");
      expectText(test, importerFormEncode("é"), "%C3%A9");
      expectText(test, importerFormEncode("€"), "%E2%82%AC");
      expectText(test, importerFormEncode("a:\"b\""), "a%3A%22b%22");
    }

## A stack, end to end

    let stackRoutes(): List<ImporterFakeRoute> {
      [
        importerRoute(
          "/repos/o/r/pulls?state=open", 200,
          jarray([
            jpull(3, "Third", "c", "b", "open", null),
            jpull(1, "First", "a", "main", "open", null),
            jpull(2, "Second", "b", "a", "open", null),
          ]),
        ),
        importerRoute("/pulls/1/commits", 200, jcommits()),
        importerRoute("/pulls/2/commits", 200, "[]"),
        importerRoute("/pulls/3/commits", 404, "{}"),
        importerRoute("https://api.github.com/repos/o/r", 200, "{\"default_branch\":\"main\"}"),
      ]
    }

    test("a stack is the chain from the default branch, each with its commits") { test =>
      let http = importerFake(stackRoutes());
      let s = importerStack(http, "o", "r", "t", "open");
      expectText(test, errKind(s.error), "ok");
      expectText(test, joinedNums(s.items.map { (i: ImporterItem): Int => i.number }), "1,2,3");
      expectText(test, joinedText(s.items.map { (i: ImporterItem): String => i.title }), "First|Second|Third");
      expectInt(test, s.items[0].commits.length, 2);
      expectText(test, s.items[0].commits[0].sha, "abcdef01");
      expectText(test, s.items[0].commits[0].message, "first subject\n\nwhy it was done");
      expectInt(test, s.items[1].commits.length, 0);
      expectTrue(test, s.items[1].commitsError == null, "an empty trail is not a failed one");
      expectText(test, orNone(s.items[2].commitsError), "{:error, :not_found}");
      let doc = importerDocument(s.items[2]);
      expectHas(test, doc, "The commit trail could not be fetched ({:error, :not_found})");
      expectHas(test, importerDocument(s.items[0]), "### first subject  (abcdef01)\n\nwhy it was done");
      expectHas(test, importerDocument(s.items[0]), "### second subject  (12345678)");
      expectInt(test, http.sent().length, 5);
    }

    test("a stack that is not one is refused by name") { test =>
      let http = importerFake([
        importerRoute(
          "/repos/o/r/pulls?state=open", 200,
          jarray([jpull(1, "a", "a", "main", "open", null), jpull(2, "b", "b", "main", "open", null)]),
        ),
        importerRoute("https://api.github.com/repos/o/r", 200, "{\"default_branch\":\"main\"}"),
      ]);
      let s = importerStack(http, "o", "r", null, "open");
      expectText(test, errKind(s.error), "many_roots");
    }

    test("a repository with no default branch in the answer is refused") { test =>
      let http = importerFake([importerRoute("https://api.github.com/repos/o/r", 200, "{\"name\":\"r\"}")]);
      expectText(test, errKind(importerStack(http, "o", "r", null, "open").error), "no_default_branch");
      let missing = importerFake([importerRoute("https://api.github.com/repos/o/r", 404, "{}")]);
      expectText(test, errKind(importerStack(missing, "o", "r", null, "open").error), "not_found");
      let bad = importerFake([]);
      expectText(test, errKind(importerStack(bad, "o/", "r", null, "open").error), "bad_name");
    }

## One document per pull request

    class ImporterTestTally extends ImporterListener {
      public var titles: ListBuilder<String> = new ListBuilder<String>();
      public var totals: ListBuilder<Int> = new ListBuilder<Int>();
      public item(title: String, index: Int, total: Int): Void {
        titles.add("${index.toString()}:${title}");
        totals.add(total);
      }
    }

    let candidate(repo: String, number: Int, title: String): ImporterPull {
      new ImporterPull(repo, number, title, "https://example.invalid/${repo}/pull/${number.toString()}", "open", false, "main", "b", null, null, null)
    }

    let docRoutes(): List<ImporterFakeRoute> {
      [
        importerRoute("/repos/o/r/pulls/5/commits", 200, jcommits()),
        importerRoute("/repos/o/r/pulls/5/files", 200, "[{\"filename\":\"lib/a.ex\",\"status\":\"modified\",\"additions\":3,\"deletions\":1,\"patch\":\"@@ -1 +1 @@\"},{\"filename\":\"lib/b.ex\",\"previous_filename\":\"lib/c.ex\",\"status\":\"renamed\",\"additions\":0,\"deletions\":0}]"),
        importerRoute("/repos/o/r/pulls/5", 200, "{\"number\":5,\"title\":\"Full title\",\"body\":\"The writeup.\",\"html_url\":\"https://github.com/o/r/pull/5\",\"changed_files\":2}"),
        importerRoute("/repos/o/r/pulls/7", 404, "{}"),
        importerRoute("/repos/o/r/pulls/8", 200, "{\"number\":8,\"body\":null}"),
      ]
    }

    test("a pull request that cannot be fetched is named beside the ones that worked") { test =>
      let http = importerFake(docRoutes());
      let tally = new ImporterTestTally();
      let got = importerDocuments(
        http,
        [candidate("o/r", 5, "Row title"), candidate("o/r", 7, "Gone"), candidate("o/r", 8, "Kept row title")],
        "t", true, true, tally,
      );
      expectInt(test, got.documents.length, 2);
      expectInt(test, got.failed.length, 1);
      expectInt(test, got.failed[0].pull.number, 7);
      expectText(test, got.failed[0].error.kind, "not_found");
      expectText(test, got.documents[0].title, "Full title");
      expectInt(test, got.documents[0].number, 5);
      expectText(test, got.documents[0].repo, "o/r");
      expectText(test, orNone(got.documents[0].sourceUrl), "https://github.com/o/r/pull/5");
      expectText(test, got.documents[1].title, "Kept row title");
      expectText(
        test, orNone(got.documents[1].sourceUrl),
        "https://example.invalid/o/r/pull/8",
      );
      expectText(test, joinedText(tally.titles.toList()), "1:Row title|2:Gone|3:Kept row title");
      expectText(test, joinedNums(tally.totals.toList()), "3,3,3");
    }

    test("a document carries the writeup, the files and the commits, in that order") { test =>
      let http = importerFake(docRoutes());
      let got = importerDocuments(http, [candidate("o/r", 5, "Row")], "t", true, true, new ImporterSilent());
      let body = got.documents[0].body;
      expectHas(test, body, "The writeup.");
      expectHas(test, body, "## Files changed (2)");
      expectHas(test, body, "- `lib/a.ex` +3 −1");
      expectHas(test, body, "- `lib/c.ex` → `lib/b.ex`");
      expectHas(test, body, "## Commits (2)");
      expectLacks(test, body, "@@");
      expectTrue(test, indexOf(body, "The writeup.") < indexOf(body, "## Files changed"), "writeup first");
      expectTrue(test, indexOf(body, "## Files changed") < indexOf(body, "## Commits"), "files before commits");
    }

    test("commits and files are fetched only when asked for") { test =>
      let http = importerFake(docRoutes());
      let got = importerDocuments(http, [candidate("o/r", 5, "Row")], "t", false, false, new ImporterSilent());
      expectText(test, got.documents[0].body, "The writeup.");
      expectInt(test, http.sent().length, 1);
      let more = importerFake(docRoutes());
      importerDocuments(more, [candidate("o/r", 5, "Row")], "t", true, false, new ImporterSilent());
      expectInt(test, more.sent().length, 2);
    }

    test("a pull request with no body in the answer says it has no description") { test =>
      let http = importerFake(docRoutes());
      let got = importerDocuments(http, [candidate("o/r", 8, "Row")], "t", false, false, new ImporterSilent());
      expectHas(test, got.documents[0].body, "_This pull request (#8) has no description._");
    }

    test("a row whose repository is not a name is a failure, not a request") { test =>
      let http = importerFake(docRoutes());
      let got = importerDocuments(
        http,
        [candidate("not a repo", 5, "x"), candidate("", 5, "y"), candidate("a/b/c", 5, "z")],
        null, true, true, new ImporterSilent(),
      );
      expectInt(test, got.documents.length, 0);
      expectInt(test, got.failed.length, 3);
      expectText(test, got.failed[0].error.kind, "bad_name");
      expectInt(test, http.sent().length, 0);
    }

    test("a commit trail that fails is written into the document") { test =>
      let http = importerFake([
        importerRoute("/pulls/5/commits", 502, "bad gateway"),
        importerRoute("/pulls/5/files", 403, "{}"),
        importerRoute("/pulls/5", 200, "{\"title\":\"T\",\"body\":\"B\",\"html_url\":\"u\"}"),
      ]);
      let got = importerDocuments(http, [candidate("o/r", 5, "Row")], null, true, true, new ImporterSilent());
      let body = got.documents[0].body;
      expectHas(test, body, "The commit trail could not be fetched ({:error, {:http, 502}})");
      expectHas(test, body, "The file list could not be fetched ({:error, :forbidden})");
    }

    test("one pull request, as GitHub describes it") { test =>
      let http = importerFake(docRoutes());
      let f = importerFetchPull(http, "t", "o/r", 5);
      let full = f.full;
      expectText(test, orNone(if (full != null) { full.title } else { null }), "Full title");
      expectText(test, orNone(if (full != null) { full.body } else { null }), "The writeup.");
      expectInt(test, orZero(if (full != null) { full.changedFiles } else { null }), 2);
      expectText(test, errKind(importerFetchPull(http, null, "o/r", 7).error), "not_found");
      expectText(test, errKind(importerFetchPull(http, null, "nope", 7).error), "bad_name");
    }

## Filing a stack

    test("a stack imports as numbered drafts in a folder named for the repository") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let routes = [
        importerRoute(
          "/repos/o/r/pulls?state=open", 200,
          jarray([
            jpull(2, "Second", "b", "a", "open", null),
            jpull(1, "First", "a", "main", "open", null),
          ]),
        ),
        importerRoute("/commits", 200, "[]"),
        importerRoute("https://api.github.com/repos/o/r", 200, "{\"default_branch\":\"main\"}"),
      ];
      let tally = new ImporterTestTally();
      let done = importerImportStack(db, me, importerFake(routes), "o", "r", "t", null, "open", tally);
      expectText(test, errKind(done.error), "ok");
      expectInt(test, done.created, 2);
      expectInt(test, done.total, 2);
      let folder = done.folder;
      expectText(test, if (folder != null) { folder.name } else { "none" }, "o/r");
      let rows = db.query("SELECT title, source_url, folder_id FROM works ORDER BY id", []);
      expectInt(test, rows.length, 2);
      expectText(test, rows[0].str("title"), "1. First");
      expectText(test, rows[1].str("title"), "2. Second");
      expectText(test, rows[0].str("source_url"), "https://example.invalid/pull/1");
      expectText(test, joinedText(tally.titles.toList()), "1:1. First|2:2. Second");
      expectText(test, joinedNums(tally.totals.toList()), "2,2");
    }

    test("importing a stack twice does not duplicate it") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let routes = [
        importerRoute("/repos/o/r/pulls?state=open", 200, jarray([jpull(1, "First", "a", "main", "open", null)])),
        importerRoute("/commits", 200, "[]"),
        importerRoute("https://api.github.com/repos/o/r", 200, "{\"default_branch\":\"main\"}"),
      ];
      let first = importerImportStack(db, me, importerFake(routes), "o", "r", null, "Mine", "open", new ImporterSilent());
      expectInt(test, first.created, 1);
      let again = importerImportStack(db, me, importerFake(routes), "o", "r", null, "Mine", "open", new ImporterSilent());
      expectInt(test, again.created, 0);
      expectInt(test, again.total, 1);
      expectInt(test, db.query("SELECT id FROM works", []).length, 1);
      expectInt(test, db.query("SELECT id FROM folders", []).length, 1);
    }

    test("a title that already carries its number is not numbered twice") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let routes = [
        importerRoute("/repos/o/r/pulls?state=open", 200, jarray([jpull(1, "1. Already", "a", "main", "open", null)])),
        importerRoute("/commits", 200, "[]"),
        importerRoute("https://api.github.com/repos/o/r", 200, "{\"default_branch\":\"main\"}"),
      ];
      importerImportStack(db, me, importerFake(routes), "o", "r", null, null, "open", new ImporterSilent());
      expectText(test, db.query("SELECT title FROM works", [])[0].str("title"), "1. Already");
    }

    test("a stack that is refused creates nothing") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let routes = [
        importerRoute("/repos/o/r/pulls?state=open", 200, "[]"),
        importerRoute("https://api.github.com/repos/o/r", 200, "{\"default_branch\":\"main\"}"),
      ];
      let done = importerImportStack(db, me, importerFake(routes), "o", "r", null, null, "open", new ImporterSilent());
      expectText(test, errKind(done.error), "no_pull_requests");
      expectInt(test, db.query("SELECT id FROM folders", []).length, 0);
      expectInt(test, db.query("SELECT id FROM works", []).length, 0);
    }

    test("the folder of a stack is the user's own folder of that name, wherever it is") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let routes = [
        importerRoute("/repos/o/r/pulls?state=open", 200, jarray([jpull(1, "First", "a", "main", "open", null)])),
        importerRoute("/commits", 200, "[]"),
        importerRoute("https://api.github.com/repos/o/r", 200, "{\"default_branch\":\"main\"}"),
      ];
      let parent = foldersCreateFolder(db, me, "Archive", null);
      let pf = parent.folder;
      let child = foldersCreateFolder(db, me, "o/r", if (pf != null) { pf.id } else { null });
      let done = importerImportStack(db, me, importerFake(routes), "o", "r", null, null, "open", new ImporterSilent());
      let cf = child.folder;
      let df = done.folder;
      expectInt(test, if (df != null) { df.id } else { -1 }, if (cf != null) { cf.id } else { -2 });
      expectInt(test, db.query("SELECT id FROM folders", []).length, 2);
    }
