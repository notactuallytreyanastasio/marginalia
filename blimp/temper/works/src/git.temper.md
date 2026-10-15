# A draft's history as a git repository

`Marginalia.Git`: not a metaphor and not a reimplementation: `git` on the
PATH, a working tree per draft, one commit per accepted change. The revisions
table already holds the paragraph-level patches and is what the Changes tab
reads; this is the whole document, in a format the writer can clone,
`git log -p`, bisect, or hand to anything that understands a repository.

Commands run through `sysExec` with an argument list, never a shell string: a
draft's title goes into a commit message and titles contain quotes.

    let { sysExec, sysWriteFile, sysGetEnv, sysFileSize, sysJoin, sysGraphemeTake } = import("sys/src");
    let { Db } = import("db/src");

## Where repositories live

`MARGINALIA_GIT_ROOT` names the directory that holds one repository per draft.
Unset, it is `var/git` (relative to the working directory of the server). Set
to the empty string, history is off: every call answers `not_configured` and
the page says so rather than showing a log that will be empty tomorrow. Tests
point it at a temporary directory; the `repoDir` functions below take the
directory directly so they never read the variable at all.

    export let gitRoot(): String? {
      let set = sysGetEnv("MARGINALIA_GIT_ROOT");
      if (set != null) {
        if (set.isEmpty) { null } else { set }
      } else {
        "var/git"
      }
    }

    export let gitEnabled(): Boolean { gitRoot() != null }

The working tree of one draft: `<root>/<slug>`. The slug rather than the id,
as the Elixir: a draft id can be handed out again after the last draft is
deleted, a slug never is, and a new draft must not inherit an old history.

    export let gitPath(work: Work): String? {
      gitPathUnder(gitRoot(), work)
    }

The same under a root the caller names (null is "not configured"), so a test
or a caller with its own root never reads the environment.

    export let gitPathUnder(root: String?, work: Work): String? {
      if (root == null) { null } else { "${root}/${work.slug}" }
    }

## Results

`ok` is the answer (a short sha, or the text of a patch); `unchanged` is a
commit that was not made because nothing differed. `error` is one of
`not_configured`, `no_repo`, `bad_sha`, or `git: <exit code>: <first 300
characters of what git said>`.

    export class GitResult(public ok: String?, public unchanged: Boolean, public error: String?) {}

    export class GitEntry(public sha: String, public date: String, public subject: String) {}

    export class GitLog(public entries: List<GitEntry>, public error: String?) {}

    let gitFail(error: String): GitResult { new GitResult(null, false, error) }

    let gitDraftFile(): String { "draft.md" }

## Running git

    class GitRun(public ok: Boolean, public out: String, public error: String) {}

    let gitArgv(args: List<String>): List<String> {
      let all = new ListBuilder<String>();
      all.add("git");
      for (let a of args) { all.add(a); }
      all.toList()
    }

Exit 0 is the output of git; any other status is its status and the start of
whatever it printed, stdout then stderr.

    let gitRun(dir: String, args: List<String>): GitRun {
      var reply: List<String> = ["-1", "", ""];
      let started = do { reply = sysExec(gitArgv(args), "", dir); true } orelse false;
      if (!started) { return new GitRun(false, "", "git: could not run git"); }
      if (reply[0] == "0") { return new GitRun(true, reply[1], ""); }
      let said = worksTake("${reply[1]}${reply[2]}", 300);
      console.log("marginalia: git failed (${reply[0]}): ${said}");
      new GitRun(false, "", "git: ${reply[0]}: ${said}")
    }

## The repository

Whether `dir` is a repository already.

    export let gitExists(repoDir: String): Boolean {
      sysFileSize("${repoDir}/.git/HEAD") >= 0
    }

Make the repository if it is not there: `git init` on branch `main`, and a
committer identity in its own config, so a commit never depends on the machine
having one.

    export let gitInit(repoDir: String): GitResult {
      if (gitExists(repoDir)) { return new GitResult(repoDir, false, null); }
      do { sysExec(["mkdir", "-p", repoDir], "", null); } orelse null;
      let init = gitRun(repoDir, ["init", "--quiet", "--initial-branch=main"]);
      if (!init.ok) { return gitFail(init.error); }
      let name = gitRun(repoDir, ["config", "user.name", "Marginalia"]);
      if (!name.ok) { return gitFail(name.error); }
      let email = gitRun(repoDir, ["config", "user.email", "marginalia@localhost"]);
      if (!email.ok) { return gitFail(email.error); }
      new GitResult(repoDir, false, null)
    }

The document, plus the front matter that says which draft this is: a bare
repository of untitled markdown is hard to identify a year later.

    export let gitWriteDraft(repoDir: String, work: Work): GitResult {
      let contents = "---\ntitle: ${work.title}\nslug: ${work.slug}\nwords: ${work.wordCount}\n---\n\n${work.body}\n";
      if (sysWriteFile("${repoDir}/${gitDraftFile()}", contents)) {
        new GitResult(repoDir, false, null)
      } else {
        gitFail("git: could not write ${gitDraftFile()}")
      }
    }

## Committing

One line. A commit subject carrying a paragraph of prose is a commit subject
nothing will render: whitespace runs become one space, the ends are trimmed,
200 characters are kept, and nothing at all is "Edit".

    export let gitSubject(message: String): String {
      let one = worksCollapse(message);
      let cut = worksTake(one, 200);
      if (cut.isEmpty) { "Edit" } else { cut }
    }

Record what is in `repoDir` as it now stands, as one commit of `draft.md`.
Idempotent in the way git is: nothing to commit is not an error and not a
commit, it is `unchanged`, the honest answer when a writer saves a paragraph
they did not alter. The answer is the new short sha.

    export let gitCommit(repoDir: String, message: String): GitResult {
      gitCommitAs(repoDir, message, null)
    }

`author` is `Name <email>` for `--author`; null or empty leaves the repository's
own identity.

    export let gitCommitAs(repoDir: String, message: String, author: String?): GitResult {
      let status = gitRun(repoDir, ["status", "--porcelain"]);
      if (!status.ok) { return gitFail(status.error); }
      if (status.out.isEmpty) { return new GitResult(null, true, null); }
      let added = gitRun(repoDir, ["add", gitDraftFile()]);
      if (!added.ok) { return gitFail(added.error); }
      let args = new ListBuilder<String>();
      args.add("commit");
      args.add("--quiet");
      args.add("--message");
      args.add(gitSubject(message));
      if (author != null) {
        if (!author.isEmpty) {
          args.add("--author");
          args.add(author);
        }
      }
      let committed = gitRun(repoDir, args.toList());
      if (!committed.ok) { return gitFail(committed.error); }
      let sha = gitRun(repoDir, ["rev-parse", "--short", "HEAD"]);
      if (!sha.ok) { return gitFail(sha.error); }
      new GitResult(worksTrim(sha.out), false, null)
    }

The whole of `Git.commit(work, message, opts)`: make the repository under the
configured root, write the draft, commit. Called after a change the writer
accepted, once the database transaction has returned, never inside it: a
commit is a side effect on a filesystem and cannot be rolled back with the
database, so the database is the record and git follows it.

    export let gitCommitWork(work: Work, message: String, author: String?): GitResult {
      gitCommitWorkAt(gitRoot(), work, message, author)
    }

    export let gitCommitWorkAt(root: String?, work: Work, message: String, author: String?): GitResult {
      let dir = gitPathUnder(root, work);
      if (dir != null) {
        let made = gitInit(dir);
        if (made.error != null) { return made; }
        let written = gitWriteDraft(dir, work);
        if (written.error != null) { return written; }
        gitCommitAs(dir, message, author)
      } else {
        gitFail("not_configured")
      }
    }

`Git.record(work_id, message, opts)`: the same for a work named by id, read
fresh so the commit is of what the database holds.

    export let gitRecord(db: Db, workId: Int, message: String, author: String?): GitResult {
      if (!gitEnabled()) { return gitFail("not_configured"); }
      let found = do { worksGetById(db, workId) } orelse null;
      if (found != null) {
        gitCommitWork(found, message, author)
      } else {
        gitFail("git: no such work ${workId}")
      }
    }

## Reading the history

The commits of a draft, newest first, at most `limit`. A repository that is
not there is `no_repo`. A line that does not split into three fields is
dropped.

    export let gitLog(repoDir: String, limit: Int): GitLog {
      if (!gitExists(repoDir)) { return new GitLog([], "no_repo"); }
      let out = gitRun(repoDir, ["log", "--max-count=${limit}", "--pretty=format:%h%x1f%ad%x1f%s", "--date=iso"]);
      if (!out.ok) { return new GitLog([], out.error); }
      let entries = new ListBuilder<GitEntry>();
      for (let line of out.out.split("\n")) {
        if (!line.isEmpty) {
          let fields = line.split(gitUnitSeparator());
          if (fields.length == 3) { entries.add(new GitEntry(fields[0], fields[1], fields[2])); }
        }
      }
      new GitLog(entries.toList(), null)
    }

    let gitUnitSeparator(): String { "\u{1f}" }

    export let gitLogWork(work: Work, limit: Int): GitLog {
      gitLogWorkAt(gitRoot(), work, limit)
    }

    export let gitLogWorkAt(root: String?, work: Work, limit: Int): GitLog {
      let dir = gitPathUnder(root, work);
      if (dir != null) { gitLog(dir, limit) } else { new GitLog([], "not_configured") }
    }

A sha goes on a command line, so it is checked rather than escaped: four to
forty lower-case hex digits.

    export let gitIsSha(sha: String): Boolean {
      var n = 0;
      var i = String.begin;
      while (sha.hasIndex(i)) {
        let c = sha[i];
        if (!((c >= 48 && c <= 57) || (c >= 97 && c <= 102))) { return false; }
        n += 1;
        i = sha.next(i);
      }
      n >= 4 && n <= 40
    }

The patch for one commit, as git prints it: the short sha and date, the
subject, then the diff.

    export let gitShow(repoDir: String, sha: String): GitResult {
      if (!gitIsSha(sha)) { return gitFail("bad_sha"); }
      if (!gitExists(repoDir)) { return gitFail("no_repo"); }
      let shown = gitRun(repoDir, ["show", "--format=%h %ad%n%s%n", "--date=iso", sha]);
      if (!shown.ok) { return gitFail(shown.error); }
      new GitResult(shown.out, false, null)
    }

    export let gitShowWork(work: Work, sha: String): GitResult {
      gitShowWorkAt(gitRoot(), work, sha)
    }

    export let gitShowWorkAt(root: String?, work: Work, sha: String): GitResult {
      let dir = gitPathUnder(root, work);
      if (dir != null) { gitShow(dir, sha) } else { gitFail("not_configured") }
    }
