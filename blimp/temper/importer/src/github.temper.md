# GitHub

`Marginalia.Import.GitHub`: a repository's pull requests, listed, searched,
ordered into a stack and turned into documents. Every function that fetches
takes the `ImporterHttp` first and the token after it; the token is the
reader's own credential, supplied per request and never stored, and an empty
one is no token (`Authorization: Bearer ` is a 401, checked against the live
API).

    let { JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonBoolean, JsonNumeric, parseJson } = import("std/json");
    let { sysGraphemeLength } = import("sys/src");

    let importerApi = "https://api.github.com";
    let importerPerPage = 100;
    let importerMaxPages = 5;
    let importerFilesShown = 60;
    let importerCommitCap = 7000;

## Reading JSON

    let importerField(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

    let importerStr(t: JsonSyntaxTree?): String? {
      if (t is JsonString) { t.content } else { null }
    }

    let importerIntOf(t: JsonSyntaxTree?): Int? {
      if (t is JsonNumeric) { t.asInt32() orelse null } else { null }
    }

    let importerStrField(t: JsonSyntaxTree?, key: String): String? {
      importerStr(importerField(t, key))
    }

## Names

`owner` and `repo` go into a path, so they are checked rather than escaped: a
name that needs escaping is not a name. `^[A-Za-z0-9._-]{1,100}$`.

    export let importerCheckName(s: String): Boolean {
      let cps = importerCps(s);
      if (cps.length < 1 || cps.length > 100) { return false; }
      var i = 0;
      while (i < cps.length) {
        let c = cps[i];
        let ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
          c == 46 || c == 95 || c == 45;
        if (!ok) { return false; }
        i += 1;
      }
      true
    }

## The request

No token is a real answer, not a missing one: a public repository can be read
without one, at 60 requests an hour rather than 5000.

    let importerHeaders(token: String?): List<String> {
      let base = [
        "accept: application/vnd.github+json",
        "x-github-api-version: 2022-11-28",
        "user-agent: marginalia",
      ];
      let t = if (token != null) { importerTrim(token) } else { "" };
      if (t.isEmpty) { base } else { ["authorization: Bearer ${t}", base[0], base[1], base[2]] }
    }

    class ImporterGot(public ok: Boolean, public tree: JsonSyntaxTree?, public error: ImporterError?) {}

    let importerGotError(e: ImporterError): ImporterGot { new ImporterGot(false, null, e) }

The useful sentence of a 422 is `errors[0].message`; `message` on its own is
"Validation Failed", which is the number in words.

    let importerSaid(tree: JsonSyntaxTree?): String? {
      let errors = importerField(tree, "errors");
      if (errors is JsonArray) {
        if (errors.elements.length > 0) {
          let m = importerStrField(errors.elements[0], "message");
          if (m != null) { return m; }
        }
      }
      importerStrField(tree, "message")
    }

A 403 from this API is usually not "you may not" but "not yet": without a token
the allowance is 60 requests an hour. The two are told apart by the
`x-ratelimit-remaining` header, so it is worth reading rather than guessing.
The interpreter's client does not return response headers, so a real response
arrives with none; then the body decides, because GitHub's rate-limit answer
says "rate limit" in its message. A fake that supplies headers is judged by
them alone.

    let importerRefused(res: ImporterHttpResult): ImporterError {
      let remaining = importerHeader(res.headers, "x-ratelimit-remaining");
      if (remaining == "0") {
        return importerErrorText("rate_limited", importerHeader(res.headers, "x-ratelimit-reset"));
      }
      if (res.headers.length == 0 && importerContains(importerLower(res.body), "rate limit")) {
        return importerErrorText("rate_limited", null);
      }
      importerError("forbidden")
    }

    let importerGhGet(http: ImporterHttp, path: String, token: String?): ImporterGot {
      let res = http.get("${importerApi}${path}", importerHeaders(token));
      let failure = res.failure;
      if (failure != null) {
        return importerGotError(importerErrorText("transport", failure));
      }
      let s = res.status;
      if (s == 200) {
        let tree: JsonSyntaxTree? = parseJson(res.body) orelse null;
        return new ImporterGot(true, tree, null);
      }
      if (s == 401) { return importerGotError(importerError("unauthorized")); }
      if (s == 403 || s == 429) { return importerGotError(importerRefused(res)); }
      if (s == 404) { return importerGotError(importerError("not_found")); }
      if (s == 422) {
        let tree: JsonSyntaxTree? = parseJson(res.body) orelse null;
        return importerGotError(importerErrorText("rejected", importerSaid(tree)));
      }
      importerGotError(importerErrorNumber("http", s))
    }

## A pull request, as the API sends it

The same fields arrive from the pulls listing, the single pull and the search,
in slightly different places (`merged_at` sits under `pull_request` in a
search hit). This reads whichever it finds.

    export class ImporterRaw(public number: Int) {
      public var title: String? = null;
      public var body: String? = null;
      public var url: String? = null;
      public var state: String? = null;
      public var draft: Boolean = false;
      public var baseRef: String? = null;
      public var headRef: String? = null;
      public var updatedAt: String? = null;
      public var createdAt: String? = null;
      public var mergedAt: String? = null;
    }

    let importerRawFrom(p: JsonSyntaxTree?): ImporterRaw {
      let n = importerIntOf(importerField(p, "number"));
      let raw = new ImporterRaw(if (n != null) { n } else { 0 });
      raw.title = importerStrField(p, "title");
      raw.body = importerStrField(p, "body");
      raw.url = importerStrField(p, "html_url");
      raw.state = importerStrField(p, "state");
      let d = importerField(p, "draft");
      if (d is JsonBoolean) { raw.draft = d.content; }
      raw.baseRef = importerStrField(importerField(p, "base"), "ref");
      raw.headRef = importerStrField(importerField(p, "head"), "ref");
      raw.updatedAt = importerStrField(p, "updated_at");
      raw.createdAt = importerStrField(p, "created_at");
      let top = importerStrField(p, "merged_at");
      raw.mergedAt = if (top != null) { top } else {
        importerStrField(importerField(p, "pull_request"), "merged_at")
      };
      raw
    }

A pull request as the stack tests build one: a number, the branch it comes
from and the branch it is based on.

    export let importerPullRaw(
      number: Int, head: String, base: String, title: String?, body: String?, url: String?,
    ): ImporterRaw {
      let raw = new ImporterRaw(number);
      raw.title = title;
      raw.body = body;
      raw.url = url;
      raw.headRef = head;
      raw.baseRef = base;
      raw
    }

`state` is `open` or `closed`; whether a closed one was merged is a different
field, and the difference is the whole point of the filter.

    let importerStateOf(p: ImporterRaw): String {
      if (p.mergedAt != null) { return "merged"; }
      let s = p.state;
      if (s != null) { s } else { "open" }
    }

One row per pull request, for choosing from. A search result and a listing are
two different JSON documents that have to arrive here looking the same.

    export let importerCandidate(repo: String, p: ImporterRaw): ImporterPull {
      new ImporterPull(
        repo, p.number, importerOrEmpty(p.title), p.url, importerStateOf(p), p.draft,
        p.baseRef, p.headRef, p.updatedAt, p.createdAt, p.mergedAt,
      )
    }

## Paging

Stop on an empty page; stop after a page of fewer than 100 (keeping it);
otherwise continue; at most five pages. An error aborts the whole listing.

    export class ImporterRaws(public items: List<ImporterRaw>, public error: ImporterError?) {}

    let importerRawsError(e: ImporterError): ImporterRaws { new ImporterRaws([], e) }

    let importerPulls(
      http: ImporterHttp, owner: String, repo: String, token: String?, state: String,
    ): ImporterRaws {
      let acc = new ListBuilder<ImporterRaw>();
      var page = 1;
      while (page <= importerMaxPages) {
        let got = importerGhGet(
          http,
          "/repos/${owner}/${repo}/pulls?state=${state}&per_page=${importerPerPage.toString()}&page=${page.toString()}",
          token,
        );
        let why = got.error;
        if (why != null) { return importerRawsError(why); }
        let tree = got.tree;
        if (tree is JsonArray) {
          let n = tree.elements.length;
          var i = 0;
          while (i < n) {
            acc.add(importerRawFrom(tree.elements[i]));
            i += 1;
          }
          if (n < importerPerPage) { return new ImporterRaws(acc.toList(), null); }
        } else {
          return importerRawsError(importerErrorText("unexpected", "pulls page ${page.toString()} is not a list"));
        }
        page += 1;
      }
      new ImporterRaws(acc.toList(), null)
    }

    export class ImporterBranch(public name: String?, public error: ImporterError?) {}

    let importerDefaultBranch(
      http: ImporterHttp, owner: String, repo: String, token: String?,
    ): ImporterBranch {
      let got = importerGhGet(http, "/repos/${owner}/${repo}", token);
      let why = got.error;
      if (why != null) { return new ImporterBranch(null, why); }
      let b = importerStrField(got.tree, "default_branch");
      if (b != null) {
        new ImporterBranch(b, null)
      } else {
        new ImporterBranch(null, importerError("no_default_branch"))
      }
    }

## Listing

Every pull request of a repository, in no particular order. `stack` refuses
anything that is not a strict base-to-head chain, which is right for importing
a series and wrong for everything else: most repositories are not stacks.
What comes back is one light row per pull request; bodies and commit trails
are a request each and are only fetched for what somebody picks.

    export class ImporterListed(public pulls: List<ImporterPull>, public error: ImporterError?) {}

    let importerListError(e: ImporterError): ImporterListed { new ImporterListed([], e) }

    export let importerList(
      http: ImporterHttp, owner: String, repo: String, token: String?, state: String,
    ): ImporterListed {
      if (!importerCheckName(owner) || !importerCheckName(repo)) {
        return importerListError(importerError("bad_name"));
      }
      let raws = importerPulls(http, owner, repo, token, state);
      let why = raws.error;
      if (why != null) { return importerListError(why); }
      let out = new ListBuilder<ImporterPull>();
      var i = 0;
      while (i < raws.items.length) {
        out.add(importerCandidate("${owner}/${repo}", raws.items[i]));
        i += 1;
      }
      new ImporterListed(out.toList(), null)
    }

The same, for a repository named the way the rows name it: `owner/name`.

    export let importerListPulls(
      http: ImporterHttp, repo: String, token: String?, state: String,
    ): ImporterListed {
      let parts = importerSplitOnce(repo, "/");
      if (parts.length != 2) { return importerListError(importerError("bad_name")); }
      importerList(http, parts[0], parts[1], token, state)
    }

## Searching

`x-www-form-urlencoded` as `URI.encode_www_form`: letters, digits and `-._~`
stay, a space is `+`, everything else is its UTF-8 bytes in `%XX`.

    let importerHex(n: Int): String {
      let digits = "0123456789ABCDEF";
      importerTake(importerSliceFrom(digits, n), 1)
    }

    let importerPercent(byte: Int): String {
      "%${importerHex(byte / 16)}${importerHex(byte % 16)}"
    }

    export let importerFormEncode(s: String): String {
      let cps = importerCps(s);
      let sb = new StringBuilder();
      var i = 0;
      while (i < cps.length) {
        let c = cps[i];
        if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) ||
            c == 45 || c == 46 || c == 95 || c == 126) {
          sb.append(importerChr(c));
        } else if (c == 32) {
          sb.append("+");
        } else if (c < 128) {
          sb.append(importerPercent(c));
        } else if (c < 2048) {
          sb.append(importerPercent(192 + c / 64));
          sb.append(importerPercent(128 + c % 64));
        } else if (c < 65536) {
          sb.append(importerPercent(224 + c / 4096));
          sb.append(importerPercent(128 + (c / 64) % 64));
          sb.append(importerPercent(128 + c % 64));
        } else {
          sb.append(importerPercent(240 + c / 262144));
          sb.append(importerPercent(128 + (c / 4096) % 64));
          sb.append(importerPercent(128 + (c / 64) % 64));
          sb.append(importerPercent(128 + c % 64));
        }
        i += 1;
      }
      sb.toString()
    }

A search result does not carry owner/repo as such: it carries the API URL of
the repository it came from, which is the only place to get them.

    let importerRepoOf(item: JsonSyntaxTree?): String {
      let url = importerStrField(item, "repository_url");
      if (url != null) {
        let parts = url.split("/repos/");
        if (parts.length < 2) { url } else { parts[parts.length - 1] }
      } else {
        ""
      }
    }

Pull requests matching a GitHub search query, passed through: `is:pr` is
appended rather than required, because a search that quietly returned issues
would fill a folder with documents that have no diff behind them. The one
thing not passed through verbatim is `@today`, which is this app's syntax:
GitHub answers it with a 422 about ISO 8601, so it is translated first.

    export let importerSearchAt(
      http: ImporterHttp, query: String, token: String?, pages: Int, today: Int,
    ): ImporterListed {
      let trimmed = importerTrim(query);
      if (trimmed.isEmpty) { return importerListError(importerError("empty_query")); }
      let expanded = importerExpandAt(trimmed, today);
      let q = if (importerContains(expanded, "is:pr")) { expanded } else { "${expanded} is:pr" };
      let limit = if (pages < importerMaxPages) { pages } else { importerMaxPages };
      let out = new ListBuilder<ImporterPull>();
      var page = 1;
      while (page <= limit) {
        let got = importerGhGet(
          http,
          "/search/issues?q=${importerFormEncode(q)}&per_page=${importerPerPage.toString()}&page=${page.toString()}",
          token,
        );
        let why = got.error;
        if (why != null) { return importerListError(why); }
        let items = importerField(got.tree, "items");
        if (items is JsonArray) {
          let n = items.elements.length;
          var i = 0;
          while (i < n) {
            let item = items.elements[i];
            out.add(importerCandidate(importerRepoOf(item), importerRawFrom(item)));
            i += 1;
          }
          if (n < importerPerPage) { return new ImporterListed(out.toList(), null); }
        } else {
          return importerListError(importerError("no_results_field"));
        }
        page += 1;
      }
      new ImporterListed(out.toList(), null)
    }

    export let importerSearch(
      http: ImporterHttp, query: String, token: String?, pages: Int,
    ): ImporterListed {
      importerSearchAt(http, query, token, pages, importerToday())
    }

## Oldest first

By when it landed. This is not a detail of presentation: the order the rows are
created in is the order `Stacks` reads them forwards in, and reading a release
forwards means each document is told only what the ones before it established.
GitHub answers newest first, so taking its order would hand every document the
future. Unmerged pull requests have no landing date and sort by when they were
opened; the number is the last tiebreak so the sort is total.

    let importerSortKey(p: ImporterPull): String {
      let m = p.mergedAt;
      if (m != null) { return m; }
      let c = p.createdAt;
      if (c != null) { c } else { "" }
    }

    export let importerOldestFirst(pulls: List<ImporterPull>): List<ImporterPull> {
      pulls.sorted { (a: ImporterPull, b: ImporterPull): Int =>
        let c = importerCompareText(importerSortKey(a), importerSortKey(b));
        if (c != 0) { c } else if (a.number < b.number) { -1 } else if (a.number > b.number) { 1 } else { 0 }
      }
    }

## The chain

A stack is pull requests each based on the one before it. The order comes from
walking `base` to `head` from the default branch, not from sorting on number;
it is refused by name when it cannot be derived, because a silently
mis-ordered stack would produce a method whose steps are in the wrong order.

What a pull request becomes once it has an ordinal; the commit trail and the
file list fill in later.

    export class ImporterCommit(public sha: String, public message: String) {}

    export class ImporterFile(
      public path: String,
      public was: String?,
      public status: String,
      public added: Int,
      public removed: Int,
    ) {}

`commitsError` and `filesError` are the failure already quoted the way the
document quotes it (`{:error, :forbidden}`); null when the fetch worked.

    export class ImporterItem(
      public ordinal: Int,
      public number: Int,
      public title: String,
      public body: String,
      public url: String,
    ) {
      public var changedFiles: Int? = null;
      public var commits: List<ImporterCommit> = [];
      public var commitsError: String? = null;
      public var files: List<ImporterFile> = [];
      public var filesError: String? = null;
    }

    export class ImporterOrdered(public items: List<ImporterItem>, public error: ImporterError?) {}

    let importerOrderError(e: ImporterError): ImporterOrdered { new ImporterOrdered([], e) }

    let importerBaseOf(p: ImporterRaw): String { importerOrEmpty(p.baseRef) }

    let importerHeadOf(p: ImporterRaw): String { importerOrEmpty(p.headRef) }

The head branches that more than one pull request comes from, sorted. Two pull
requests from one branch is not a stack, and it is the shape that gets through
everything else: the walk terminates, the count comes out right, and the order
it produces is a guess.

    let importerDuplicateRefs(pulls: List<ImporterRaw>): List<String> {
      let seen = new ListBuilder<String>();
      let dups = new ListBuilder<String>();
      var i = 0;
      while (i < pulls.length) {
        let ref = importerHeadOf(pulls[i]);
        if (importerIsOneOf(ref, seen.toList())) {
          if (!importerIsOneOf(ref, dups.toList())) { dups.add(ref); }
        } else {
          seen.add(ref);
        }
        i += 1;
      }
      dups.toList().sorted { (a: String, b: String): Int => importerCompareText(a, b) }
    }

The index of the last pull request based on `ref`, or -1: a map keyed by base
ref in which a later pull overwrites an earlier one with the same base.

    let importerLastBasedOn(pulls: List<ImporterRaw>, ref: String): Int {
      var i = pulls.length - 1;
      while (i >= 0) {
        if (importerBaseOf(pulls[i]) == ref) { return i; }
        i -= 1;
      }
      -1
    }

    let importerHasNumber(xs: List<Int>, n: Int): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i] == n) { return true; }
        i += 1;
      }
      false
    }

    let importerToItem(p: ImporterRaw, ordinal: Int): ImporterItem {
      new ImporterItem(
        ordinal, p.number, importerOrEmpty(p.title), importerOrEmpty(p.body), importerOrEmpty(p.url),
      )
    }

    export let importerOrder(pulls: List<ImporterRaw>, defaultBranch: String): ImporterOrdered {
      if (pulls.length == 0) { return importerOrderError(importerError("no_pull_requests")); }
      let dups = importerDuplicateRefs(pulls);
      if (dups.length > 0) {
        return importerOrderError(importerErrorTexts("duplicate_branches", dups));
      }
      let roots = new ListBuilder<Int>();
      var i = 0;
      while (i < pulls.length) {
        if (importerBaseOf(pulls[i]) == defaultBranch) { roots.add(i); }
        i += 1;
      }
      if (roots.length == 0) {
        return importerOrderError(importerErrorText("no_root", defaultBranch));
      }
      if (roots.length > 1) {
        let numbers = new ListBuilder<Int>();
        var r = 0;
        while (r < roots.length) {
          numbers.add(pulls[roots[r]].number);
          r += 1;
        }
        return importerOrderError(importerErrorNumbers("many_roots", numbers.toList()));
      }
      let seen = new ListBuilder<Int>();
      let items = new ListBuilder<ImporterItem>();
      var at = roots[0];
      while (at >= 0) {
        let p = pulls[at];
        if (importerHasNumber(seen.toList(), p.number)) {
          at = -1;
        } else {
          seen.add(p.number);
          items.add(importerToItem(p, items.length + 1));
          at = importerLastBasedOn(pulls, importerHeadOf(p));
        }
      }
      let off = new ListBuilder<Int>();
      var k = 0;
      let visited = seen.toList();
      while (k < pulls.length) {
        if (!importerHasNumber(visited, pulls[k].number)) { off.add(pulls[k].number); }
        k += 1;
      }
      if (off.length > 0) {
        return importerOrderError(importerErrorNumbers("off_chain", off.toList()));
      }
      new ImporterOrdered(items.toList(), null)
    }

## Commits and files

The writeup argues; the commits are what was actually done. A stack read from
descriptions alone is a stack read from the author's summary of their own work,
and the sentence that turns out to matter is usually in a commit message
explaining why the obvious version was wrong. A failure does not lose the
import: it is written into the document instead, so a chapter with no commit
trail says so rather than looking like a chapter that had none.

    let importerToCommit(c: JsonSyntaxTree?): ImporterCommit {
      let sha = importerTake(importerOrEmpty(importerStrField(c, "sha")), 8);
      let message = importerTrim(importerOrEmpty(importerStrField(importerField(c, "commit"), "message")));
      new ImporterCommit(sha, message)
    }

    let importerWithCommits(
      http: ImporterHttp, item: ImporterItem, owner: String, repo: String, token: String?,
    ): ImporterItem {
      let got = importerGhGet(
        http,
        "/repos/${owner}/${repo}/pulls/${item.number.toString()}/commits?per_page=${importerPerPage.toString()}",
        token,
      );
      let why = got.error;
      let tree = got.tree;
      if (why != null) {
        item.commitsError = importerInspectError(why);
      } else if (tree is JsonArray) {
        let out = new ListBuilder<ImporterCommit>();
        var i = 0;
        while (i < tree.elements.length) {
          out.add(importerToCommit(tree.elements[i]));
          i += 1;
        }
        item.commits = out.toList();
      } else {
        item.commitsError = importerInspectError(importerErrorText("unexpected", "not a list"));
      }
      item
    }

What a pull request touched, which is a different fact from what its author
says it did and cheaper to check than either the diff or the commits. The
response carries `patch`, the diff hunks, for every file, and it is dropped
here on purpose: a draft is something somebody reads and argues with in the
margin, and forty files of unified diff in it is not that.

    let importerToFile(f: JsonSyntaxTree?): ImporterFile {
      let added = importerIntOf(importerField(f, "additions"));
      let removed = importerIntOf(importerField(f, "deletions"));
      new ImporterFile(
        importerOrEmpty(importerStrField(f, "filename")),
        importerStrField(f, "previous_filename"),
        importerOrEmpty(importerStrField(f, "status")),
        if (added != null) { added } else { 0 },
        if (removed != null) { removed } else { 0 },
      )
    }

    let importerWithFiles(
      http: ImporterHttp, item: ImporterItem, owner: String, repo: String, token: String?,
    ): ImporterItem {
      let got = importerGhGet(
        http,
        "/repos/${owner}/${repo}/pulls/${item.number.toString()}/files?per_page=100",
        token,
      );
      let why = got.error;
      let tree = got.tree;
      if (why != null) {
        item.filesError = importerInspectError(why);
      } else if (tree is JsonArray) {
        let out = new ListBuilder<ImporterFile>();
        var i = 0;
        while (i < tree.elements.length) {
          out.add(importerToFile(tree.elements[i]));
          i += 1;
        }
        item.files = out.toList();
      } else {
        item.filesError = importerInspectError(importerErrorText("unexpected", "not a list"));
      }
      item
    }

## A stack

The open pull requests of a repository as an ordered stack, each with its
commit trail. `state` is `open` unless the caller says otherwise. The files are
not fetched for a stack.

    export class ImporterStack(public items: List<ImporterItem>, public error: ImporterError?) {}

    let importerStackError(e: ImporterError): ImporterStack { new ImporterStack([], e) }

    export let importerStack(
      http: ImporterHttp, owner: String, repo: String, token: String?, state: String,
    ): ImporterStack {
      if (!importerCheckName(owner) || !importerCheckName(repo)) {
        return importerStackError(importerError("bad_name"));
      }
      let branch = importerDefaultBranch(http, owner, repo, token);
      let why = branch.error;
      if (why != null) { return importerStackError(why); }
      let def = importerOrEmpty(branch.name);
      let raws = importerPulls(http, owner, repo, token, state);
      let rawWhy = raws.error;
      if (rawWhy != null) { return importerStackError(rawWhy); }
      let ordered = importerOrder(raws.items, def);
      let orderWhy = ordered.error;
      if (orderWhy != null) { return importerStackError(orderWhy); }
      let out = new ListBuilder<ImporterItem>();
      var i = 0;
      while (i < ordered.items.length) {
        out.add(importerWithCommits(http, ordered.items[i], owner, repo, token));
        i += 1;
      }
      new ImporterStack(out.toList(), null)
    }

## The document one pull request becomes

Its writeup, then the files it touched, then its commit trail. What a chapter
*says* is what every later pass reads, so a document assembled wrongly
produces a plausible step nothing downstream can tell is wrong. A pull request
with an empty body is a document with nothing to read, and every later pass
would quietly produce nothing from it; saying so in the draft is better than
an empty section the writer cannot explain.

    let importerCounts(added: Int, removed: Int): String {
      if (added == 0 && removed == 0) {
        ""
      } else if (removed == 0) {
        " +${added.toString()}"
      } else if (added == 0) {
        " −${removed.toString()}"
      } else {
        " +${added.toString()} −${removed.toString()}"
      }
    }

    let importerFileLine(f: ImporterFile): String {
      let counts = importerCounts(f.added, f.removed);
      if (f.status == "renamed") {
        "- `${importerOrEmpty(f.was)}` → `${f.path}`${counts}"
      } else if (f.status == "added") {
        "- `${f.path}`${counts} — new"
      } else if (f.status == "removed") {
        "- `${f.path}`${counts} — deleted"
      } else {
        "- `${f.path}`${counts}"
      }
    }

Between the argument and the commits. The paths answer "what is this actually
about" in one glance, which the writeup sometimes does not and a hundred commit
subjects never do. Two caps can bite: GitHub pages the response at 100, and
this lists 60 of whatever came back. The header counts what is on the page
against what the pull request says it touched, so either one being hit reads
the same and neither is silent.

    let importerFileList(item: ImporterItem): String {
      let failed = item.filesError;
      if (failed != null) {
        return "\n\n---\n\n## Files changed\n\n_The file list could not be fetched (${failed}), so this says nothing about what was touched._\n";
      }
      if (item.files.length == 0) { return ""; }
      let changed = item.changedFiles;
      let total = if (changed != null) { changed } else { item.files.length };
      let shownCount = if (item.files.length < importerFilesShown) { item.files.length } else { importerFilesShown };
      let lines = new ListBuilder<String>();
      var i = 0;
      while (i < shownCount) {
        lines.add(importerFileLine(item.files[i]));
        i += 1;
      }
      let head = if (shownCount < total) {
        "${total.toString()}, the first ${shownCount.toString()} listed"
      } else {
        total.toString()
      };
      "\n\n---\n\n## Files changed (${head})\n\n${importerJoin(lines.toList(), "\n")}"
    }

Bounded, and after the writeup, so that a chapter with a long history can never
push its own argument out of the window `Stacks.text_of/1` reads.

    let importerCommitTrail(item: ImporterItem): String {
      let failed = item.commitsError;
      if (failed != null) {
        return "\n\n---\n\n## Commits\n\n_The commit trail could not be fetched (${failed}), so this chapter is its description alone._\n";
      }
      if (item.commits.length == 0) { return ""; }
      let entries = new ListBuilder<String>();
      var i = 0;
      while (i < item.commits.length) {
        let c = item.commits[i];
        let lines = c.message.split("\n");
        let subject = lines[0];
        let rest = if (lines.length > 1) { importerTrim(importerJoin(lines.slice(1, lines.length), "\n")) } else { "" };
        let detail = if (rest.isEmpty) { "" } else { "\n\n${rest}" };
        entries.add("### ${subject}  (${c.sha})${detail}");
        i += 1;
      }
      let joined = importerJoin(entries.toList(), "\n\n");
      let trail = if (sysGraphemeLength(joined) <= importerCommitCap) {
        joined
      } else {
        "${importerTake(joined, importerCommitCap)}\n\n_[commit trail truncated]_"
      };
      "\n\n---\n\n## Commits (${item.commits.length.toString()})\n\n${trail}\n"
    }

    export let importerDocument(item: ImporterItem): String {
      let body = importerTrim(item.body);
      let writeup = if (body.isEmpty) {
        "_This pull request (#${item.number.toString()}) has no description._\n\n${item.url}\n"
      } else {
        body
      };
      "${writeup}${importerFileList(item)}${importerCommitTrail(item)}"
    }

## One pull request, in full

`GET /repos/{o}/{r}/pulls/{n}`: the title, the body, the address and how many
files it touched. `title`, `body` and `url` are null when the API left them
out, so the caller can fall back to the row it chose from.

    export class ImporterFull(
      public title: String?,
      public body: String?,
      public url: String?,
      public changedFiles: Int?,
    ) {}

    export class ImporterFetched(public full: ImporterFull?, public error: ImporterError?) {}

    export let importerFetchPull(
      http: ImporterHttp, token: String?, repo: String, number: Int,
    ): ImporterFetched {
      let parts = importerSplitOnce(repo, "/");
      if (parts.length != 2) {
        return new ImporterFetched(null, importerError("bad_name"));
      }
      if (!importerCheckName(parts[0]) || !importerCheckName(parts[1])) {
        return new ImporterFetched(null, importerError("bad_name"));
      }
      let got = importerGhGet(http, "/repos/${parts[0]}/${parts[1]}/pulls/${number.toString()}", token);
      let why = got.error;
      if (why != null) { return new ImporterFetched(null, why); }
      let t = got.tree;
      if (t is JsonObject) {
        new ImporterFetched(
          new ImporterFull(
            importerStrField(t, "title"),
            importerStrField(t, "body"),
            importerStrField(t, "html_url"),
            importerIntOf(importerField(t, "changed_files")),
          ),
          null,
        )
      } else {
        new ImporterFetched(null, importerErrorText("unexpected", "not a pull request"))
      }
    }

## Documents for the pull requests somebody picked

One request per pull request for the body, one more for the commits and one for
the files. They run one at a time here: the interpreter has one thread, and a
request that is waited on is a request that is finished. A pull request that
cannot be fetched is returned beside the ones that worked rather than failing
the batch. Forty documents and a named failure is worth more than nothing and a
reason.

`number` and `repo` ride along so a page can say which pull request a document
came from.

    export class ImporterDoc(
      public title: String,
      public body: String,
      public sourceUrl: String?,
    ) {
      public var number: Int = 0;
      public var repo: String = "";
    }

    export class ImporterFailed(public pull: ImporterPull, public error: ImporterError) {}

    export class ImporterDocuments(
      public documents: List<ImporterDoc>,
      public failed: List<ImporterFailed>,
    ) {}

Called as each document lands (`title`, its place, and the total), so a page
showing nothing for a minute is not a page somebody reloads.

    export interface ImporterListener {
      public item(title: String, index: Int, total: Int): Void;
    }

    export class ImporterSilent extends ImporterListener {
      public item(title: String, index: Int, total: Int): Void {}
    }

    export class ImporterDocumented(public doc: ImporterDoc?, public error: ImporterError?) {}

    let importerOneDocument(
      http: ImporterHttp, c: ImporterPull, token: String?, commits: Boolean, files: Boolean,
    ): ImporterDocumented {
      let parts = importerSplitOnce(c.repo, "/");
      if (parts.length != 2) {
        return new ImporterDocumented(null, importerError("bad_name"));
      }
      if (!importerCheckName(parts[0]) || !importerCheckName(parts[1])) {
        return new ImporterDocumented(null, importerError("bad_name"));
      }
      let fetched = importerFetchPull(http, token, c.repo, c.number);
      let why = fetched.error;
      let full = fetched.full;
      if (why != null) { return new ImporterDocumented(null, why); }
      if (full != null) {
        let title = if (full.title != null) { importerOrEmpty(full.title) } else { c.title };
        let url = if (full.url != null) { importerOrEmpty(full.url) } else { importerOrEmpty(c.url) };
        var item = new ImporterItem(0, c.number, title, importerOrEmpty(full.body), url);
        item.changedFiles = full.changedFiles;
        if (commits) { item = importerWithCommits(http, item, parts[0], parts[1], token); }
        if (files) { item = importerWithFiles(http, item, parts[0], parts[1], token); }
        let doc = new ImporterDoc(item.title, importerDocument(item), item.url);
        doc.number = c.number;
        doc.repo = c.repo;
        new ImporterDocumented(doc, null)
      } else {
        new ImporterDocumented(null, importerError("bad_name"))
      }
    }

    export let importerDocuments(
      http: ImporterHttp,
      pulls: List<ImporterPull>,
      token: String?,
      commits: Boolean,
      files: Boolean,
      listener: ImporterListener,
    ): ImporterDocuments {
      let docs = new ListBuilder<ImporterDoc>();
      let failed = new ListBuilder<ImporterFailed>();
      var i = 0;
      while (i < pulls.length) {
        let c = pulls[i];
        let r = importerOneDocument(http, c, token, commits, files);
        let d = r.doc;
        let why = r.error;
        if (d != null) {
          docs.add(d);
        } else if (why != null) {
          failed.add(new ImporterFailed(c, why));
        }
        listener.item(c.title, i + 1, pulls.length);
        i += 1;
      }
      new ImporterDocuments(docs.toList(), failed.toList())
    }
