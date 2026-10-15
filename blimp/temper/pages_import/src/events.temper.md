# Events

`ImportLive.handle_event/3`, one event at a time: each loads the wizard from the
session, changes it, saves it, and leaves it to the page to render. Fifteen
events: `source`, `back`, `restart`, `form`, `find`, `pattern`, `toggle`, `all`,
`none`, `order`, `settings`, `import`, and the three that belonged to the live
upload (`validate`, `drop_file`, `import_files`), which a JSON event can not
carry a file for. See `files.temper.md` for what stands in for them.

    let { Ctx } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { sysStringTrim, sysGraphemeTake, sysJoin } = import("sys/src");
    let {
      ImporterPull, ImporterHttp, ImporterListed, ImporterFiltered, ImporterHint,
      importerListPulls, importerSearch, importerOldestFirst, importerQueryFilter, importerTitleFilter,
      importerQueryHint, importerExplain,
    } = import("importer/src");

## The ceiling

Two hundred pull requests in one go.

    let pimMaxPick(): Int { 200 }

## The token

Only what the visitor typed. A blank box is an unauthenticated request to
GitHub, as it was in the Elixir; the server's environment lends no token to
anyone. It is handed to the importer and to nothing else.

    export let pimEffectiveToken(typed: String): String { typed }

    let pimTokenOrNull(typed: String): String? {
      if (typed == "") { null } else { typed }
    }

## Sorting

`sorted(_, "newest") = reverse(oldest_first(...))`; anything else is the order
the folder is read forwards in.

    export let pimSorted(cands: List<ImporterPull>, order: String): List<ImporterPull> {
      let oldest = importerOldestFirst(cands);
      if (order == "newest") {
        let out = new ListBuilder<ImporterPull>();
        var i = oldest.length - 1;
        while (i >= 0) {
          out.add(oldest[i]);
          i -= 1;
        }
        out.toList()
      } else { oldest }
    }

## Narrowing

`refilter(pattern)`: always over every candidate. A good pattern replaces what is
shown and ticks all of it (the manual ticks are forgotten); a bad one is named
and leaves the last good list and selection as they were.

    export let pimRefilter(ctx: Ctx, w: PimWiz, pattern: String, cands: List<ImporterPull>): Void throws Bubble {
      let narrowed: ImporterFiltered = if (w.how == "regex") {
        importerTitleFilter(pattern, cands)
      } else {
        importerQueryFilter(cands, pattern)
      };
      let why = narrowed.error;
      w.pattern = pattern;
      if (why != null) {
        w.patternError = why;
        return;
      }
      let kept = narrowed.kept;
      let shown = new ListBuilder<Int>();
      var i = 0;
      var k = 0;
      while (i < cands.length && k < kept.length) {
        if (pimKey(cands[i]) == pimKey(kept[k])) {
          shown.add(i);
          k += 1;
        }
        i += 1;
      }
      w.patternError = null;
      let hint: ImporterHint? = if (shown.length == 0) { importerQueryHint(pattern) } else { null };
      if (hint != null) {
        w.hintWas = hint.was;
        w.hintTry = hint.tryThis;
      } else {
        w.hintWas = null;
        w.hintTry = null;
      }
      pimSetShown(ctx, shown.toList());
    }

## Finding

`default_folder`: the repository, or the search, or a word.

    let pimDefaultFolder(w: PimWiz): String {
      if (w.mode == "repo" && w.repo != "") {
        w.repo
      } else if (w.query != "") {
        "Search: ${sysGraphemeTake(w.query, 60)}"
      } else { "Imported" }
    }

The request itself is made here, inside the one that asked for it: five pages of
a hundred at the most, and the child that answers is the visitor's alone. What
came back replaces the listing, or is named in `error`.

    let pimFound(ctx: Ctx, w: PimWiz, listed: ImporterListed): Void throws Bubble {
      let why = listed.error;
      if (why != null) {
        w.error = importerExplain(why);
      } else if (listed.pulls.length == 0) {
        w.error = "Nothing matched.";
      } else {
        let cands = pimSorted(listed.pulls, w.order);
        pimSaveCands(ctx, cands);
        w.error = null;
        w.step = "pick";
        w.folder = pimDefaultFolder(w);
        pimRefilter(ctx, w, w.pattern, cands);
      }
    }

`owner/name` with both halves present.

    let pimRepoWritten(repo: String): Boolean {
      let at = repo.split("/");
      if (at.length < 2) { return false; }
      at.getOr(0, "") != "" && sysJoin(at.slice(1, at.length), "/") != ""
    }

    let pimFind(ctx: Ctx, w: PimWiz, http: ImporterHttp, payload: JsonObject): Void throws Bubble {
      let typed = sysStringTrim(pimStr(payload, "token"));
      let mode = pimStrOr(payload, "mode", "repo");
      w.repo = sysStringTrim(pimStr(payload, "repo"));
      w.query = sysStringTrim(pimStr(payload, "query"));
      w.mode = mode;
      w.state = pimStrOr(payload, "state", "all");
      pimStoreToken(ctx, typed);
      if (mode == "search") {
        if (w.query == "") {
          w.error = "Write a search query first.";
        } else {
          w.error = null;
          pimFound(ctx, w, importerSearch(http, w.query, pimTokenOrNull(typed), 5));
        }
      } else if (mode == "repo") {
        if (pimRepoWritten(w.repo)) {
          w.error = null;
          pimFound(ctx, w, importerListPulls(http, w.repo, pimTokenOrNull(typed), w.state));
        } else {
          w.error = "Write the repository as owner/name.";
        }
      } else {
        console.log("pages_import: no search mode called ${mode}");
        bubble()
      }
    }

## Settings

`folder`, and each flag is whether its box said `true`. A box that is absent is
off, as `params["x"] == "true"` was.

    let pimSettings(w: PimWiz, payload: JsonObject): Void {
      w.folder = pimStrOr(payload, "folder", w.folder);
      w.commits = pimStr(payload, "commits") == "true";
      w.files = pimStr(payload, "files") == "true";
      w.number = pimStr(payload, "number") == "true";
    }

## Importing

    let pimImport(
      ctx: Ctx, w: PimWiz, payload: JsonObject,
      launch: fn (Ctx, String, PimJob): Boolean throws Bubble,
    ): Void throws Bubble {
      if (pimHas(payload, "folder")) { pimSettings(w, payload); }
      let picked = pimLoadPicked(ctx);
      if (picked.length == 0) {
        w.error = "Nothing is selected.";
      } else if (picked.length > pimMaxPick()) {
        w.error = "That is ${picked.length.toString()} pull requests, and the ceiling is ${pimMaxPick().toString()} in one go. Narrow it and run it again — importing twice into the same folder skips what is already there.";
      } else {
        let job = new PimJob(pimEffectiveToken(pimStoredToken(ctx)), picked, w.commits, w.files, w.folder, w.number);
        if (launch(ctx, pimRunKey(ctx), job)) {
          w.step = "running";
          w.error = null;
          pimStoreToken(ctx, "");
        } else {
          w.error = "An import is already running.";
        }
      }
    }

## Moving between steps

    let pimBack(w: PimWiz): Void {
      if (w.step == "pick") {
        w.step = "find";
      } else if (w.step == "find" || w.step == "files") {
        w.step = "source";
      }
      w.error = null;
    }

`restart` keeps the repository, the query, the flags, the language and the
order, and forgets the list, the selection and the result.

    let pimRestart(ctx: Ctx, w: PimWiz): Void throws Bubble {
      w.step = "source";
      w.source = "";
      w.pattern = "";
      w.patternError = null;
      w.hintWas = null;
      w.hintTry = null;
      w.error = null;
      pimForgetCands(ctx);
      pimSaveResult(ctx, "");
    }

## One event

`http` and `launch` are the two seams of the page: the real ones are
`importerRealHttp` and `pagesImportLaunch`; the tests give a canned GitHub and a
launcher that does not fork.

    export let pimHandle(
      ctx: Ctx, event: String, payload: JsonObject, http: ImporterHttp,
      launch: fn (Ctx, String, PimJob): Boolean throws Bubble,
    ): Void throws Bubble {
      let w = pimLoadWiz(ctx);
      if (event == "source") {
        let to = pimStr(payload, "to");
        if (to == "github") {
          w.source = "github";
          w.step = "find";
          w.error = null;
        } else if (to == "files") {
          w.source = "files";
          w.step = "files";
          w.error = null;
        }
      } else if (event == "back") {
        pimBack(w);
      } else if (event == "restart") {
        pimRestart(ctx, w);
      } else if (event == "form") {
        w.repo = pimStrOr(payload, "repo", w.repo);
        w.query = pimStrOr(payload, "query", w.query);
        w.mode = pimStrOr(payload, "mode", w.mode);
        w.state = pimStrOr(payload, "state", w.state);
        w.error = null;
      } else if (event == "find") {
        pimFind(ctx, w, http, payload);
      } else if (event == "pattern") {
        w.how = pimStrOr(payload, "how", w.how);
        pimRefilter(ctx, w, pimStrOr(payload, "pattern", w.pattern), pimLoadCands(ctx));
      } else if (event == "toggle") {
        pimToggleKey(ctx, pimStr(payload, "key"));
      } else if (event == "all") {
        pimTickShown(ctx, true);
      } else if (event == "none") {
        pimTickShown(ctx, false);
      } else if (event == "order") {
        w.order = pimStrOr(payload, "order", w.order);
        let sorted = pimSorted(pimLoadCands(ctx), w.order);
        pimSaveCands(ctx, sorted);
        pimRefilter(ctx, w, w.pattern, sorted);
      } else if (event == "settings") {
        pimSettings(w, payload);
      } else if (event == "import") {
        pimImport(ctx, w, payload, launch);
      } else if (event == "validate" || event == "drop_file") {
        // The live upload's bookkeeping: nothing is listed before the form is posted.
      } else if (event == "import_files") {
        w.error = "No files yet — drop some in.";
      } else {
        pimUnhandledEvent("/import", event);
      }
      pimSaveWiz(ctx, w);
    }
