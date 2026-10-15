# Starting work that outlives the request

A read takes minutes, a summary of a whole document longer, and a rewrite is a
slow model call. None of them belongs to the request that asked for it. The
page hands the job to a launcher, which forks it away under a key of the
`runs` table (`work:<id>:<what>`), and learns how it is going by looking at
that row on every request: a page with a run going carries `data-poll`.

The launcher is a parameter so the tests can run the job inline (`runsStart`
refuses `:memory:`) with a canned model. Production is `ShowForkLauncher`.

    let { Db } = import("db/src");
    let { Ctx } = import("webcore/src");
    let { Scope } = import("accounts/src");
    let { Work, Section, worksNodes } = import("works/src");
    let { LlmClient, LlmConfig, llmConfigFromEnv, llmProvider, llmWithConfig } = import("llm/src");
    let { Run, runsStart, runsFinish, runsReclaim, runsProgress, runsColumns } = import("runs/src");
    let { analysisStartTracked, decisionGraphBuild } = import("analysis/src");
    let {
      rewritePropose, summaryRun, documentRun, documentCondensation, RewriteResult,
    } = import("reading/src");
    let { linksGetOrCreate, linkerRun, linkerRunPair, Link } = import("links/src");
    let { sysGetEnv, sysUtcNow } = import("sys/src");
    let { JsonTextProducer } = import("std/json");

## The launcher

`start` runs `body` in the background under `key` and answers whether it did:
`false` means a run under that key is already going and nothing was started.
`body` is given the job's own `Db` and must use only that. `llm` is the model
client for a provider (null is the deploy's default); `ready` is whether that
provider has a key, which decides whether the controls are offered at all.

    export interface ShowLauncher {
      public start(ctx: Ctx, key: String, body: fn (Db): Void throws Bubble): Boolean throws Bubble;
      public llm(provider: String?): LlmClient;
      public ready(provider: String?): Boolean;
    }

## Backends

`LLM.choices/0`: the providers that have a key on this deploy, by label.

    export let showKeyVar(provider: String): String {
      if (provider == "openai") { "OPENAI_API_KEY" } else { "DEEPSEEK_API_KEY" }
    }

    export let showProviderName(provider: String?): String {
      if (provider != null && provider != "") {
        if (provider == "openai") { "openai" } else { "deepseek" }
      } else {
        llmConfigFromEnv().provider
      }
    }

    export let showKeyConfigured(provider: String?): Boolean {
      let v = sysGetEnv(showKeyVar(showProviderName(provider)));
      v != null && v != ""
    }

    export let showBackendNamed(name: String): ShowBackend {
      let p = llmProvider(name);
      new ShowBackend(p.name, p.label, p.model)
    }

    export let showBackends(): List<ShowBackend> {
      let out = new ListBuilder<ShowBackend>();
      if (showKeyConfigured("deepseek")) { out.add(showBackendNamed("deepseek")); }
      if (showKeyConfigured("openai")) { out.add(showBackendNamed("openai")); }
      out.toList()
    }

The client for a provider: the environment's configuration with the provider
(and so the key) swapped when the owner chose another.

    export let showLlmFor(provider: String?): LlmClient {
      let base = llmConfigFromEnv();
      let want = showProviderName(provider);
      if (want == base.provider) {
        llmWithConfig(base)
      } else {
        let key = showOr(sysGetEnv(showKeyVar(want)), "");
        llmWithConfig(new LlmConfig(want, key, base.endpoint, base.backoffMs, base.timeoutMs, base.model))
      }
    }

## The production launcher

    export class ShowForkLauncher extends ShowLauncher {
      public start(ctx: Ctx, key: String, body: fn (Db): Void throws Bubble): Boolean throws Bubble {
        runsStart(ctx.dbPath, ctx.db, key, body)
      }
      public llm(provider: String?): LlmClient { showLlmFor(provider) }
      public ready(provider: String?): Boolean { showKeyConfigured(provider) }
    }

## The inline launcher

The tests': the run row is claimed as `runsStart` claims it, then the body runs
in this process on the page's own `Db` with one canned client, and the run is
finished (`crashed` when the body bubbled). A body that finished its own run
(with a result in `detail`) is left as it finished it.

    export class ShowInlineLauncher(private client: LlmClient, private keyed: Boolean) extends ShowLauncher {
      public start(ctx: Ctx, key: String, body: fn (Db): Void throws Bubble): Boolean throws Bubble {
        runsReclaim(ctx.db, key);
        let claimed = ctx.db.exec(
          "INSERT INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ($1, 'running', NULL, NULL, NULL, $2, NULL) ON CONFLICT(key) DO UPDATE SET status = 'running', progress = NULL, detail = NULL, pid = NULL, started_at = $2, finished_at = NULL WHERE runs.status <> 'running'",
          [key, sysUtcNow()],
        );
        if (claimed == 0) { return false; }
        let ok = do { body(ctx.db); true } orelse false;
        runsFinish(ctx.db, key, if (ok) { "done" } else { "crashed" }, null);
        true
      }
      public llm(provider: String?): LlmClient { client }
      public ready(provider: String?): Boolean { keyed }
    }

A launcher that starts nothing and says it started: the run is claimed and
stays `running`, which is how a page mid-pass is shown.

    export class ShowQueueLauncher extends ShowLauncher {
      public start(ctx: Ctx, key: String, body: fn (Db): Void throws Bubble): Boolean throws Bubble {
        runsReclaim(ctx.db, key);
        let claimed = ctx.db.exec(
          "INSERT INTO runs (key, status, progress, detail, pid, started_at, finished_at) VALUES ($1, 'running', NULL, NULL, NULL, $2, NULL) ON CONFLICT(key) DO UPDATE SET status = 'running', progress = NULL, detail = NULL, pid = NULL, started_at = $2, finished_at = NULL WHERE runs.status <> 'running'",
          [key, sysUtcNow()],
        );
        claimed > 0
      }
      public llm(provider: String?): LlmClient { showLlmFor(provider) }
      public ready(provider: String?): Boolean { true }
    }

## What a job leaves behind

A job's answer is JSON in its run's `detail`: `{"ok": true}`, or `{"error":
"<kind>", "detail": "<text>"}`, or a result's own fields. The page reads it
once, when it first sees the run finished.

    let psAnswer(error: String?, detail: String?): String throws Bubble {
      let p = showProducer();
      p.startObject();
      if (error == null) {
        showKeyBool(p, "ok", true);
      } else {
        showKeyStr(p, "error", error);
        showKeyStr(p, "detail", detail);
      }
      p.endObject();
      p.toJsonString()
    }

    export let showAnswerOk(): String throws Bubble { psAnswer(null, null) }

    export let showAnswerError(error: String, detail: String?): String throws Bubble {
      psAnswer(error, detail)
    }

The text a failure is shown as: the kind, and the detail after it when there
is one (`inspect(reason)` of the Elixir, near enough to read).

    export let showReason(error: String?, detail: String?): String {
      let kind = showOr(error, "unknown");
      if (detail != null && detail != "") { "${kind}: ${detail}" } else { kind }
    }

## The jobs

Each is what `runsStart` runs in the forked process, given the job's own
`Db`, the model client, and what it needs by value (never the request's `Db`).

The read, reporting `n/total` sections to its run as it goes.

    export let showJobRead(own: Db, llm: LlmClient, work: Work, key: String): Void throws Bubble {
      analysisStartTracked(own, llm, work, key);
    }

The decision graph pass.

    export let showJobGraph(own: Db, llm: LlmClient, work: Work, key: String): Void throws Bubble {
      let r = decisionGraphBuild(own, llm, work, null);
      let why = r.error;
      if (why != null) {
        runsFinish(own, key, "done", showAnswerError("graph", why));
      } else {
        runsFinish(own, key, "done", showAnswerOk());
      }
    }

Rewrites of a selected span. The answer is the candidates, or the reason there
are none.

    export let showJobRewrite(
      own: Db, llm: LlmClient, work: Work, span: String, steer: String?, key: String,
    ): Void throws Bubble {
      let r = rewritePropose(own, llm, work, span, steer);
      let why = r.error;
      if (why != null) {
        let p = showProducer();
        p.startObject();
        showKeyStr(p, "error", why);
        showKeyStr(p, "detail", r.detail);
        showKeyInt(p, "words", r.words);
        showKeyInt(p, "max", r.maxWords);
        p.endObject();
        runsFinish(own, key, "done", p.toJsonString());
      } else {
        let section = r.section;
        let found = new ShowRewrite(
          r.reading, r.original, if (section != null) { section.ordinal } else { null },
          r.candidates, r.spansBlocks, r.covers,
        );
        runsFinish(own, key, "done", showRewriteJson(found));
      }
    }

One section's summary.

    export let showJobSummarise(own: Db, llm: LlmClient, section: Section, key: String): Void throws Bubble {
      let r = summaryRun(own, llm, section);
      let why = r.error;
      if (why != null) {
        runsFinish(own, key, "done", showAnswerError(why, r.detail));
      } else {
        runsFinish(own, key, "done", showAnswerOk());
      }
    }

The whole document: every section's summary that is missing or stale, the
composition and the rules.

    export let showJobDocument(own: Db, llm: LlmClient, work: Work, key: String): Void throws Bubble {
      let r = documentRun(own, llm, work, false);
      let why = r.error;
      if (why != null) {
        runsFinish(own, key, "done", showAnswerError(why, r.detail));
      } else {
        runsFinish(own, key, "done", showAnswerOk());
      }
    }

`Document.compare`: draft the summaries as a draft of their own (or find the
one already made), read it if it has not been read, and relate the two. The
run's progress says which. The answer is `{"compared": <link id>}`.

    let psCompareLink(own: Db, llm: LlmClient, link: Link, key: String): Void throws Bubble {
      runsProgress(own, key, "Relating", null);
      let related = linkerRun(own, llm, link);
      if (related.ok) {
        let p = showProducer();
        p.startObject();
        showKeyInt(p, "compared", link.id);
        p.endObject();
        runsFinish(own, key, "done", p.toJsonString());
      } else {
        runsFinish(own, key, "done", showAnswerError("linker", related.error));
      }
    }

    let psCompareWith(own: Db, llm: LlmClient, work: Work, draft: Work, key: String): Void throws Bubble {
      if (worksNodes(own, draft.id).length == 0) {
        runsProgress(own, key, "Reading the summary", null);
        analysisStartTracked(own, llm, draft, null);
      }
      let link = linksGetOrCreate(own, work.id, draft.id).ok;
      if (link != null) {
        psCompareLink(own, llm, link, key);
      } else {
        runsFinish(own, key, "done", showAnswerError("link", null));
      }
    }

    export let showJobCompare(own: Db, llm: LlmClient, scope: Scope, work: Work, key: String): Void throws Bubble {
      runsProgress(own, key, "Drafting the summary", null);
      let made = documentCondensation(own, scope, work);
      let draft = made.ok;
      if (draft != null) {
        psCompareWith(own, llm, work, draft, key);
      } else {
        runsFinish(own, key, "done", showAnswerError(showOr(made.error, "unknown"), made.message));
      }
    }

The pass that reads a link between two drafts, under the key the links pages
use (`link:<id>`), so a page for the pair sees it going.

    export let showLinkKey(linkId: Int): String { "link:${linkId.toString()}" }

    export let showJobLink(own: Db, llm: LlmClient, linkId: Int): Void throws Bubble {
      linkerRunPair(own, llm, linkId);
    }

## Which runs are going

The runs of a work, going or finished, by key prefix. `LIKE` would treat a `_`
or `%` in a prefix as a pattern; `substr` does not.

    export let showRunsOf(ctx: Ctx, workId: Int): List<Run> throws Bubble {
      let prefix = showKeyPrefix(workId);
      let out = new ListBuilder<Run>();
      for (let row of ctx.db.query(
        "SELECT ${runsColumns()} FROM runs WHERE substr(key, 1, $1) = $2 ORDER BY started_at ASC, key ASC",
        [prefix.split("").length.toString(), prefix],
      )) {
        out.add(Run.fromRow(row));
      }
      out.toList()
    }
