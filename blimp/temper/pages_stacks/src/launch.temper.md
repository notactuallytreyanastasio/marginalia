# Starting a pass

A pass over a folder takes minutes to hours and belongs to the folder, not to
the request that pressed the button. The page hands it to `runsStart`, which
forks it away under the key `stack:<folder id>` (`stacksRunKey`), and the page
learns how it is going by polling the `runs` row.

Which pass is a string, the `kind` the page's events carry and the run's
`detail` starts with: `read`, `deepen`, `summarise`, `read_each`, `relate`,
`compose`.

    let { Ctx } = import("webcore/src");
    let { Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Folder, foldersGetFolderOrNull } = import("folders/src");
    let { Work } = import("works/src");
    let { LlmClient, llmFromEnv } = import("llm/src");
    let {
      Run, runsGet, runsStart, runsProgress, runsFinish, runsCounts, runsReclaim,
    } = import("runs/src");
    let {
      stacksRunKey, stacksJobRead, stacksJobDeepen, stacksJobCompose, stacksJobSummarise,
      stacksJobReadEach, stacksJobRelate, StackRelateHooks, StackRelateOutcome,
    } = import("stacks/src");
    let { documentRun } = import("reading/src");
    let { analysisStart } = import("analysis/src");
    let {
      linksBulkSheet, linksBulkPropose, linksBulkRelatePair, linksBulkIneligible, BulkPair,
    } = import("links/src");
    let { ImporterListener, importerImportStack, importerRealHttp, importerExplain } = import("importer/src");

## Relating the documents

`Links.Bulk.run` with the two callbacks the Elixir passed. The links library
has the whole of it as one function with no hooks, so the stages are here:
triage once (`on_stage("choosing the pairs")`), then each pair that has been
read on both sides (`on_pair` with the number of pairs). A pair is eligible
only when both of its documents have been read; the others are counted as not
related and the run says how many.

    export let pagesStacksRelate(
      own: Db, llm: LlmClient, scope: Scope, folderId: Int, hooks: StackRelateHooks,
    ): StackRelateOutcome throws Bubble {
      let folder = foldersGetFolderOrNull(own, scope, folderId);
      if (folder == null) { return new StackRelateOutcome(0, 0, "no_folder"); }
      let sheet = linksBulkSheet(own, scope, folderId);
      if (sheet.length == 0) { return new StackRelateOutcome(0, 0, "empty_folder"); }
      hooks.stage("choosing the pairs");
      let proposed = linksBulkPropose(own, llm, sheet);
      let triage = proposed.ok;
      if (triage != null) {
        let ready = new ListBuilder<BulkPair>();
        let left = new ListBuilder<BulkPair>();
        for (let pair of triage.pairs) {
          if (pair.a.status == "read" && pair.b.status == "read") { ready.add(pair); } else { left.add(pair); }
        }
        let pairs = ready.toList();
        var i = 0;
        while (i < pairs.length) {
          linksBulkRelatePair(own, llm, pairs[i]);
          hooks.pair(pairs.length);
          i += 1;
        }
        new StackRelateOutcome(pairs.length, linksBulkIneligible(left.toList()).length, null)
      } else {
        new StackRelateOutcome(0, 0, pkOr(proposed.error, "no_reply"))
      }
    }

## The body of a job

What `runsStart` runs in the forked process, with the job's own `Db` and a
model client: the library's job for the kind, which ends by finishing the run
as `<kind>|<result>`. `summarise` and `read_each` are given the closures of the
contexts that do the work (the summary of a whole document, the ordinary read),
which the stacks library does not depend on; each answers what the Elixir's
function did, the reason or nothing.

An unknown kind is a bug in the page: it stops with the name in the log.

    export let pagesStacksRun(own: Db, llm: LlmClient, kind: String, scope: Scope, folder: Folder): Void throws Bubble {
      if (kind == "read") {
        stacksJobRead(own, llm, scope, folder.id)
      } else if (kind == "deepen") {
        stacksJobDeepen(own, llm, folder.id, false)
      } else if (kind == "compose") {
        stacksJobCompose(own, llm, folder.id, folder.name)
      } else if (kind == "summarise") {
        stacksJobSummarise(own, scope, folder.id, false, fn (w: Work): String? throws Bubble {
          documentRun(own, llm, w, false).error
        })
      } else if (kind == "read_each") {
        stacksJobReadEach(own, scope, folder.id, false, fn (w: Work): Void throws Bubble {
          analysisStart(own, llm, w);
        })
      } else if (kind == "relate") {
        stacksJobRelate(own, folder.id, fn (hooks: StackRelateHooks): StackRelateOutcome throws Bubble {
          pagesStacksRelate(own, llm, scope, folder.id, hooks)
        })
      } else {
        console.log("pages_stacks: no pass called ${kind}");
        bubble()
      }
    }

## Starting

`Runs.start/3` answered `{:error, {:already_running, other}}` when the key was
taken; `runsStart` answers `false`. `total` is what the page showed the moment
the button was pressed (documents, steps, the ones left): the job reports its
own as its first act, and until it has, the row says `0/<total>` so the page
that answers the click already shows the pass. Only a row that has reported
nothing is written, so a job that is already further on is not set back.

    let pkFirstReport(ctx: Ctx, key: String, kind: String, total: Int): Void throws Bubble {
      ctx.db.exec(
        "UPDATE runs SET progress = $1, detail = $2 WHERE key = $3 AND status = 'running' AND progress IS NULL",
        [runsCounts(0, total), kind, key],
      );
    }

    export let pagesStacksLaunch(ctx: Ctx, kind: String, folder: Folder, total: Int): Boolean throws Bubble {
      let key = stacksRunKey(folder.id);
      let scope = ctx.scope;
      let started = runsStart(ctx.dbPath, ctx.db, key) { (own: Db): Void throws Bubble =>
        pagesStacksRun(own, llmFromEnv(), kind, scope, folder)
      };
      if (started) { pkFirstReport(ctx, key, kind, total); }
      started
    }

## The import

`GitHub.import_stack` under a run of its own, `stack-import:<user id>`: the
fetch is one request per pull request and takes as long as a pass. The token
exists only in the job's memory (a closure over the forked process); it is
never written to the database, the session or a log. The listener writes the
count of drafts saved after each one, which the page shows.

    export let pagesStacksImportKey(userId: Int): String { "stack-import:${userId.toString()}" }

    class PagesStacksTally(private db: Db, private key: String) extends ImporterListener {
      public item(title: String, index: Int, total: Int): Void {
        let wrote = do { runsProgress(db, key, runsCounts(index, total), "import"); true } orelse false;
        if (!wrote) { console.log("pages_stacks: could not report the import's progress"); }
      }
    }

The run ends `done` with `import|ok:<folder id>:<made>:<total>` or
`import|error:<what to tell the reader>`; a job that bubbled is `crashed`.

    export let pagesStacksImportJob(
      own: Db, scope: Scope, owner: String, repo: String, token: String, folder: String, state: String,
    ): Void throws Bubble {
      let key = pagesStacksImportKey(scope.userId);
      let done = importerImportStack(
        own, scope, importerRealHttp(1), owner, repo,
        if (token == "") { null } else { token },
        if (folder == "") { null } else { folder },
        state, new PagesStacksTally(own, key),
      );
      let why = done.error;
      let filed = done.folder;
      if (why != null) {
        runsFinish(own, key, "done", "import|error:${importerExplain(why)}");
      } else if (filed != null) {
        runsFinish(own, key, "done", "import|ok:${filed.id.toString()}:${done.created.toString()}:${done.total.toString()}");
      } else {
        bubble()
      }
    }

    export let pagesStacksLaunchImport(
      ctx: Ctx, owner: String, repo: String, token: String, folder: String, state: String,
    ): Boolean throws Bubble {
      let scope = ctx.scope;
      let key = pagesStacksImportKey(scope.userId);
      let started = runsStart(ctx.dbPath, ctx.db, key) { (own: Db): Void throws Bubble =>
        pagesStacksImportJob(own, scope, owner, repo, token, folder, state)
      };
      if (started) { pkFirstReport(ctx, key, "import", 0); }
      started
    }

The run that is there, after a job whose process died has been given up on.
`runsReclaim` marks a `running` row whose pid is gone as crashed, which frees
the key and stops a page from polling for ever.

    export let pagesStacksRunOf(ctx: Ctx, key: String): Run? throws Bubble {
      runsReclaim(ctx.db, key);
      runsGet(ctx.db, key)
    }
