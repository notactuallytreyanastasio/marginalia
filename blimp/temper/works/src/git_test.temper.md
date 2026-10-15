# Tests for a draft's git history

Ported from `git_test` in `notes/tests.md`. They run the real `git` for the
same reason the module does: a reimplementation that agrees with itself proves
nothing, and the point is that the writer can clone the result. Each test
makes its own temporary directory and removes it.

    let { Db, dbOpen } = import("db/src");
    let { Scope, User, userColumns } = import("accounts/src");
    let { sysExec, sysJoin, sysReadFile } = import("sys/src");

    class WorksGitFx(public db: Db, public scope: Scope, public work: Work, public root: String) {}

    let tempRoot(): String throws Bubble {
      let made = sysExec(["mktemp", "-d", "-t", "mg-git"], "", null);
      worksTrim(made[1])
    }

    let cleanUp(root: String): Void {
      do { sysExec(["rm", "-rf", root], "", null); } orelse null;
    }

    let gitFixture(): WorksGitFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let body = "# A draft\n\nALPHA the first paragraph. ${repeated("word ", 120)}\n\nBRAVO the second paragraph. ${repeated("word ", 120)}";
      new WorksGitFx(db, me, makeWork(db, me, "Draft", body), tempRoot())
    }

`git` itself, in a repository, for asserting from the outside.

    let git(dir: String, args: List<String>): String throws Bubble {
      let all = new ListBuilder<String>();
      all.add("git");
      for (let a of args) { all.add(a); }
      let r = sysExec(all.toList(), "", dir);
      if (r[0] == "0") { r[1] } else { "exit ${r[0]}: ${r[2]}" }
    }

    let shaOf(r: GitResult): String { orEmpty(r.ok) }

    let isHex(s: String): Boolean {
      s.countBetween(String.begin, s.end) >= 4 && gitIsSha(s)
    }

    test("the first commit creates a real repository") { test =>
      let f = gitFixture();
      let r = gitCommitWorkAt(f.root, f.work, "First", null);
      expectTrue(test, r.error == null, orNull(r.error));
      expectTrue(test, isHex(shaOf(r)), "a short sha: ${shaOf(r)}");
      let dir = orEmpty(gitPathUnder(f.root, f.work));
      expectTrue(test, gitExists(dir), "there is a .git");
      expectHas(test, git(dir, ["log", "--oneline"]), "First");
      expectText(test, worksTrim(git(dir, ["rev-parse", "--abbrev-ref", "HEAD"])), "main");
      expectText(test, worksTrim(git(dir, ["config", "user.name"])), "Marginalia");
      expectText(test, worksTrim(git(dir, ["config", "user.email"])), "marginalia@localhost");
      cleanUp(f.root);
    }

    test("the repository lives under the root, named by the slug") { test =>
      let f = gitFixture();
      expectText(test, orEmpty(gitPathUnder(f.root, f.work)), "${f.root}/${f.work.slug}");
      expectTrue(test, gitPathUnder(null, f.work) == null, "no root, no path");
      cleanUp(f.root);
    }

    test("the document is in the tree, with the draft identified") { test =>
      let f = gitFixture();
      gitCommitWorkAt(f.root, f.work, "First", null);
      let dir = orEmpty(gitPathUnder(f.root, f.work));
      let contents = orEmpty(sysReadFile("${dir}/draft.md"));
      expectHas(test, contents, "ALPHA the first paragraph.");
      expectHas(test, contents, "slug: ${f.work.slug}");
      expectHas(test, contents, "title: Draft");
      expectText(test, contents, "---\ntitle: Draft\nslug: ${f.work.slug}\nwords: ${f.work.wordCount.toString()}\n---\n\n${f.work.body}\n");
      cleanUp(f.root);
    }

    test("committing an unchanged draft is not a commit") { test =>
      let f = gitFixture();
      gitCommitWorkAt(f.root, f.work, "First", null);
      let again = gitCommitWorkAt(f.root, f.work, "Again", null);
      expectTrue(test, again.unchanged, "unchanged");
      expectTrue(test, again.ok == null, "no sha");
      expectTrue(test, again.error == null, "no error");
      let dir = orEmpty(gitPathUnder(f.root, f.work));
      expectInt(test, worksCountLines(git(dir, ["log", "--oneline"])), 1);
      cleanUp(f.root);
    }

    let worksCountLines(text: String): Int {
      var n = 0;
      for (let line of text.split("\n")) { if (!line.isEmpty) { n += 1; } }
      n
    }

    test("an edit becomes a second commit whose patch is the change") { test =>
      let f = gitFixture();
      gitCommitWorkAt(f.root, f.work, "As it arrived", null);
      let section = firstSection(f.db, f.work);
      let block = blockWith(section, "ALPHA");
      worksReplaceBlock(f.db, section, block, sysJoin(block.split("ALPHA"), "AMENDED"), null, null);
      let work = worksGetBySlug(f.db, f.work.slug);
      expectTrue(test, work != null, "found by slug");
      if (work != null) {
        let r = gitCommitWorkAt(f.root, work, "rewrite: cuts the gloss", null);
        expectTrue(test, isHex(shaOf(r)), "committed");
        let log = gitLogWorkAt(f.root, work, 50);
        expectTrue(test, log.error == null, "log ok");
        expectInt(test, log.entries.length, 2);
        expectText(test, log.entries[0].subject, "rewrite: cuts the gloss");
        expectText(test, log.entries[1].subject, "As it arrived");
        expectText(test, log.entries[0].sha, shaOf(r));
        expectTrue(test, hasText(log.entries[0].date, "-"), "an ISO date: ${log.entries[0].date}");
        let shown = gitShowWorkAt(f.root, work, log.entries[0].sha);
        let patch = orEmpty(shown.ok);
        expectHas(test, patch, "ALPHA");
        expectHas(test, patch, "AMENDED");
        expectHas(test, patch, "-ALPHA the first paragraph.");
        expectHas(test, patch, "+AMENDED the first paragraph.");
        expectHas(test, patch, "rewrite: cuts the gloss");
      }
      cleanUp(f.root);
    }

    test("a multi-line message is reduced to a subject") { test =>
      let f = gitFixture();
      gitCommitWorkAt(f.root, f.work, "line one\nline two\n\nline three", null);
      let log = gitLogWorkAt(f.root, f.work, 50);
      expectInt(test, log.entries.length, 1);
      expectFalse(test, hasText(log.entries[0].subject, "\n"), "one line");
      expectText(test, log.entries[0].subject, "line one line two line three");
      cleanUp(f.root);
    }

    test("a title with quotes in it does not break the commit") { test =>
      let f = gitFixture();
      let odd = makeWork(f.db, f.scope, "A \"quoted\" title; rm -rf /", "# H\n\n${repeated("word ", 300)}");
      let r = gitCommitWorkAt(f.root, odd, "subject with \"quotes\" and $(echo hi)", null);
      expectTrue(test, r.error == null, orNull(r.error));
      let log = gitLogWorkAt(f.root, odd, 50);
      expectInt(test, log.entries.length, 1);
      expectHas(test, log.entries[0].subject, "quotes");
      expectHas(test, log.entries[0].subject, "$(echo hi)");
      let contents = orEmpty(sysReadFile("${orEmpty(gitPathUnder(f.root, odd))}/draft.md"));
      expectHas(test, contents, "title: A \"quoted\" title; rm -rf /");
      cleanUp(f.root);
    }

    test("a bad sha is refused rather than passed to git") { test =>
      let f = gitFixture();
      gitCommitWorkAt(f.root, f.work, "First", null);
      expectText(test, orEmpty(gitShowWorkAt(f.root, f.work, "--not-a-sha").error), "bad_sha");
      expectText(test, orEmpty(gitShowWorkAt(f.root, f.work, "; rm -rf /").error), "bad_sha");
      expectText(test, orEmpty(gitShowWorkAt(f.root, f.work, "abc").error), "bad_sha");
      expectText(test, orEmpty(gitShowWorkAt(f.root, f.work, "ABCDEF12").error), "bad_sha");
      expectText(test, orEmpty(gitShowWorkAt(f.root, f.work, repeated("a", 41)).error), "bad_sha");
      cleanUp(f.root);
    }

    test("a sha git does not know is git's error, not a crash") { test =>
      let f = gitFixture();
      gitCommitWorkAt(f.root, f.work, "First", null);
      let r = gitShowWorkAt(f.root, f.work, "deadbeef");
      expectTrue(test, r.ok == null, "no patch");
      expectTrue(test, startsWithText(orEmpty(r.error), "git: 128:"), orEmpty(r.error));
      cleanUp(f.root);
    }

    let startsWithText(s: String, prefix: String): Boolean {
      worksStartsWith(s, prefix)
    }

    test("a log for a draft with no repository says so") { test =>
      let f = gitFixture();
      expectText(test, orEmpty(gitLogWorkAt(f.root, f.work, 50).error), "no_repo");
      expectText(test, orEmpty(gitShowWorkAt(f.root, f.work, "abcd1234").error), "no_repo");
      cleanUp(f.root);
    }

    test("when the deploy has not configured a root nothing is written and it says why") { test =>
      let f = gitFixture();
      expectText(test, orEmpty(gitCommitWorkAt(null, f.work, "First", null).error), "not_configured");
      expectText(test, orEmpty(gitLogWorkAt(null, f.work, 50).error), "not_configured");
      expectText(test, orEmpty(gitShowWorkAt(null, f.work, "abcd1234").error), "not_configured");
      cleanUp(f.root);
    }

    test("the commit author can be named, and is the repository's own otherwise") { test =>
      let f = gitFixture();
      let dir = orEmpty(gitPathUnder(f.root, f.work));
      gitCommitWorkAt(f.root, f.work, "By default", null);
      expectText(test, worksTrim(git(dir, ["log", "-1", "--format=%an <%ae>"])), "Marginalia <marginalia@localhost>");
      let edited = makeWork(f.db, f.scope, "Draft", "# A draft\n\nsome other words entirely");
      let other = orEmpty(gitPathUnder(f.root, edited));
      gitCommitWorkAt(f.root, edited, "Named", "Ada Lovelace <ada@example.com>");
      expectText(test, worksTrim(git(other, ["log", "-1", "--format=%an <%ae>"])), "Ada Lovelace <ada@example.com>");
      gitCommitWorkAt(f.root, edited, "Empty author", "");
      cleanUp(f.root);
    }

    test("the subject is one line of at most 200 characters, and Edit when empty") { test =>
      expectText(test, gitSubject("  a \n b\t\tc  "), "a b c");
      expectText(test, gitSubject(""), "Edit");
      expectText(test, gitSubject(" \n\t "), "Edit");
      expectInt(test, gitSubject(repeated("x", 500)).countBetween(String.begin, gitSubject(repeated("x", 500)).end), 200);
    }

    test("sha checking wants four to forty lower-case hex digits") { test =>
      expectTrue(test, gitIsSha("abcd"), "four");
      expectTrue(test, gitIsSha("0123456789abcdef0123456789abcdef01234567"), "forty");
      expectFalse(test, gitIsSha("abc"), "three");
      expectFalse(test, gitIsSha(repeated("a", 41)), "forty one");
      expectFalse(test, gitIsSha("abcg"), "not hex");
      expectFalse(test, gitIsSha("ABCD"), "upper case");
      expectFalse(test, gitIsSha("--abcd"), "an option");
      expectFalse(test, gitIsSha(""), "empty");
    }

    test("init is idempotent and an existing history is kept") { test =>
      let f = gitFixture();
      let dir = orEmpty(gitPathUnder(f.root, f.work));
      expectTrue(test, gitInit(dir).error == null, "first init");
      expectTrue(test, gitExists(dir), "exists");
      gitWriteDraft(dir, f.work);
      let first = gitCommit(dir, "Kept");
      expectTrue(test, isHex(shaOf(first)), "committed");
      expectTrue(test, gitInit(dir).error == null, "second init");
      expectInt(test, gitLog(dir, 10).entries.length, 1);
      cleanUp(f.root);
    }

    test("the log limit caps the entries, newest first") { test =>
      let f = gitFixture();
      let dir = orEmpty(gitPathUnder(f.root, f.work));
      gitInit(dir);
      for (let n of [1, 2, 3]) {
        let w = makeWork(f.db, f.scope, "Number ${n.toString()}", "# H\n\nword ${n.toString()}");
        gitWriteDraft(dir, w);
        gitCommit(dir, "commit ${n.toString()}");
      }
      let two = gitLog(dir, 2);
      expectInt(test, two.entries.length, 2);
      expectText(test, two.entries[0].subject, "commit 3");
      expectText(test, two.entries[1].subject, "commit 2");
      cleanUp(f.root);
    }

    test("git failing is reported with its exit status") { test =>
      let f = gitFixture();
      let nowhere = "${f.root}/not/here";
      let r = gitCommit(nowhere, "x");
      expectTrue(test, r.error != null, "an error");
      expectTrue(test, startsWithText(orEmpty(r.error), "git:"), orEmpty(r.error));
      cleanUp(f.root);
    }

    test("record of a work that does not exist is an error, not a crash") { test =>
      let f = gitFixture();
      expectTrue(test, gitRecord(f.db, 99999, "x", null).error != null, "no such work");
      cleanUp(f.root);
    }
