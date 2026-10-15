# The import as a run

`ImportLive` ran the import with `start_async` and learned how it went from
messages: a tick per fetched pull request, a phase change, then the result. An
import of a hundred pull requests is three hundred requests and a hundred
drafts; it cannot be the request that asked for it. Here it is a run of its own
(`runsStart`), forked away under a key made from the session, and the page
polls its `runs` row:

* `progress` is `"done/total"` and `detail` is the phase, `fetching` or
  `landing`, while the run is going;
* `detail` is the result (`PimResult` as JSON) once it is `done`, or the crash
  text once it is `crashed`.

The token exists in the job's memory (a closure over the forked process) and in
the session until the import starts. It is never written to the `runs` row, and
never to a log.

    let { Ctx } = import("webcore/src");
    let { Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Run, runsGet, runsStart, runsProgress, runsFinish, runsCounts, runsReclaim } = import("runs/src");
    let {
      ImporterPull, ImporterHttp, ImporterListener, ImporterDocuments, ImporterFailed, ImporterLandResult,
      ImporterLandFailure, importerDocuments, importerLandWith, importerLandExplain, importerExplain,
      importerRealHttp,
    } = import("importer/src");
    let { sysSha256, sysGraphemeTake, sysStringTrim } = import("sys/src");

## What a job is

The pull requests picked, in the order the list showed them, and the three
settings the form held.

    export class PimJob(
      public token: String,
      public picked: List<ImporterPull>,
      public commits: Boolean,
      public files: Boolean,
      public folder: String,
      public number: Boolean,
    ) {}

## The key

Per session: the cookie is the secret, so the key carries its hash. Two tabs of
one visitor share an import, as two pages of one LiveView user did not, and a
second import while one is going is refused.

    export let pimRunKey(ctx: Ctx): String {
      "import:${sysGraphemeTake(sysSha256(ctx.session.id), 24)}"
    }

## Ticks

`on_item` of both halves writes the count; the phase is the `detail`.

    class PimTally(private db: Db, private key: String, private phase: String) extends ImporterListener {
      public item(title: String, index: Int, total: Int): Void {
        let wrote = do { runsProgress(db, key, runsCounts(index, total), phase); true } orelse false;
        if (!wrote) { console.log("pages_import: could not report the import's progress"); }
      }
    }

## The body

The documents are fetched, then filed. A pull request that could not be
fetched is not a failure of the batch: it goes beside the result as `missed`.
`Bulk.land` is given the folder box as it stands (blank is loose: the GitHub
path never got the dropped-files naming).

    export let pimFailedPairs(f: List<ImporterLandFailure>): List<Pair<String, String>> {
      f.map { (x: ImporterLandFailure): Pair<String, String> => new Pair(x.title, importerLandExplain(x)) }
    }

    export let pimMissedList(m: List<ImporterFailed>): List<PimMissed> {
      m.map { (x: ImporterFailed): PimMissed => new PimMissed(x.pull.number, x.pull.title, importerExplain(x.error)) }
    }

    export let pimResultOf(landed: ImporterLandResult, missed: List<ImporterFailed>): PimResult {
      let folder = landed.folder;
      new PimResult(
        if (folder != null) { folder.id } else { null },
        landed.created.length,
        landed.skipped,
        pimFailedPairs(landed.failed),
        pimMissedList(missed),
      )
    }

    export let pagesImportJob(own: Db, scope: Scope, key: String, http: ImporterHttp, job: PimJob): Void throws Bubble {
      let token: String? = if (job.token == "") { null } else { job.token };
      let got = importerDocuments(http, job.picked, token, job.commits, job.files, new PimTally(own, key, "fetching"));
      runsProgress(own, key, runsCounts(0, got.documents.length), "landing");
      let landed = importerLandWith(
        own, scope, sysStringTrim(job.folder), job.number, new PimTally(own, key, "landing"), got.documents,
      );
      runsFinish(own, key, "done", pimResultJson(pimResultOf(landed, got.failed)));
    }

## Starting

`false`, starting nothing, when this session's import is still going. Until the
job has reported, the row says `0/<picked>` so the page that answers the click
already shows the bar.

    let pimFirstReport(ctx: Ctx, key: String, total: Int): Void throws Bubble {
      ctx.db.exec(
        "UPDATE runs SET progress = $1, detail = $2 WHERE key = $3 AND status = 'running' AND progress IS NULL",
        [runsCounts(0, total), "fetching", key],
      );
    }

    export let pagesImportLaunch(ctx: Ctx, key: String, job: PimJob): Boolean throws Bubble {
      let scope = ctx.scope;
      let started = runsStart(ctx.dbPath, ctx.db, key) { (own: Db): Void throws Bubble =>
        pagesImportJob(own, scope, key, importerRealHttp(1), job)
      };
      if (started) { pimFirstReport(ctx, key, job.picked.length); }
      started
    }

The run that is there, after one whose process died has been given up on:
`runsReclaim` marks a `running` row whose pid is gone as crashed, which stops a
page from polling for ever.

    export let pimRunOf(ctx: Ctx, key: String): Run? throws Bubble {
      runsReclaim(ctx.db, key);
      runsGet(ctx.db, key)
    }
