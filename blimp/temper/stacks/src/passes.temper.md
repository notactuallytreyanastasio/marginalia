# The passes

Everything of `Marginalia.Stacks` that calls a model or runs for minutes: the
forward read, the second pass that sees forwards, the composition, and the
three passes that wrap other contexts (summarise each document, read each
document, relate them).

None of these forks. The `runs` library owns the process and the `runs` row;
each pass here is the function its body calls, taking the job's own `Db`, and
reporting through a `progress` callback that the caller wires to
`runsProgress` (`stacksReport` does it for the folder's run key; the job bodies at the end of this file wire it).

    let { Db, DbRow } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Folder, foldersGetFolderOrNull } = import("folders/src");
    let { Work, workColumns, worksGetById } = import("works/src");
    let {
      LlmClient, LlmCall, LlmMessage, LlmTool, LlmError, LlmReply, LlmToolCall, Result,
      llmErrorText,
    } = import("llm/src");
    let { Run, runsProgress, runsFinish, runsCounts } = import("runs/src");
    let { sysUtcNow, sysJoin } = import("sys/src");
    let {
      JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonTextProducer, parseJson,
    } = import("std/json");

## What a pass reports

A pass that did not stop for a bubble answers a `StackPassResult`: how many
documents it took through, what failed, and the short text the page's flash
is made from. `detail` is `errors:<n>` for the counted passes.

    export class StackFailure(
      public ordinal: Int,
      public title: String,
      public reason: String,
    ) {}

    export class StackPassResult(
      public done: Int,
      public failures: List<StackFailure>,
      public detail: String,
    ) {}

    let stacksErrorsResult(done: Int, failures: List<StackFailure>): StackPassResult {
      new StackPassResult(done, failures, "errors:${failures.length.toString()}")
    }

## The run, as the page sees it

One run per folder, keyed `stack:<folder id>`, whatever the pass: starting a
second one while a first is going is refused by `runsStart`, which is what
"A read pass is already running on this folder." was.

    export let stacksRunKey(folderId: Int): String { "stack:${folderId.toString()}" }

The `runs` row has one `progress` and one `detail` column, so the Elixir run's
`kind`, `done`, `total` and `stage` are written into them like this, by every
pass, as its first act and then after each unit of work:

- `progress` is always `"<done>/<total>"` (`runsCounts`), `0/0` while the
  composition outlines;
- `detail` is the pass's kind, `read`, `deepen`, `summarise`, `read_each`,
  `relate` or `compose`, optionally followed by `:<stage>`: `compose:outlining`,
  `compose:writing`, `relate:triage`, `relate:relating`.

Reporting is best effort: a progress write that fails must not stop a pass.

    let stacksReport(db: Db, folderId: Int, progress: String, detail: String?): Void {
      let wrote = do { runsProgress(db, stacksRunKey(folderId), progress, detail); true } orelse false;
      if (!wrote) { console.log("stacks: could not report progress for folder ${folderId.toString()}"); }
    }


`from_run/2` of the page: what is running and how far. `null` when nothing is
running (a finished row is history, not a pass in flight).

    export class StackRunView(
      public kind: String,
      public done: Int,
      public total: Int,
      public stage: String?,
    ) {
      /** `Composing — <this>`: `outlining`, or `part d of t` while writing. */
      public stageText(): String? {
        let s = stage;
        if (kind != "compose" || s == null) { return null; }
        if (s == "outlining") { "outlining" } else if (s == "writing") {
          "part ${done.toString()} of ${total.toString()}"
        } else {
          null
        }
      }
    }

    let stacksSplitOnce(s: String, sep: String): List<String> {
      let parts = s.split(sep);
      if (parts.length < 2) { return [s, ""]; }
      [parts[0], sysJoin(parts.slice(1, parts.length), sep)]
    }

    let stacksViewOf(run: Run): StackRunView? {
      if (run.isRunning()) {
        let detail = stacksOrEmpty(run.detail);
        let kindStage = stacksSplitOnce(detail, ":");
        let counts = stacksSplitOnce(stacksOrEmpty(run.progress), "/");
        let done = do { counts[0].toInt32() } orelse 0;
        let total = do { counts[1].toInt32() } orelse 0;
        let stage: String? = if (kindStage[1] == "") { null } else { kindStage[1] };
        new StackRunView(kindStage[0], done, total, stage)
      } else {
        null
      }
    }

    export let stacksRunView(run: Run?): StackRunView? {
      if (run != null) { stacksViewOf(run) } else { null }
    }

The note under the progress bar, per pass, verbatim.

    export let stacksPassNote(kind: String): String {
      if (kind == "read_each") {
        "the ordinary read of each one, sections at a time. This runs on the server: you can close the page."
      } else if (kind == "relate") {
        "one call per pair, three at a time, over both their graphs. This runs on the server: you can close the page."
      } else if (kind == "summarise") {
        "one whole-document summary each, sections six at a time. This runs on the server: you can close the page."
      } else {
        "each document waits on the one before it. This runs on the server: you can close the page."
      }
    }

The flash the page shows when a pass ends (`handle_info({:run, :done | :crashed
...})`), from the finished run's `status` and `detail`. The job wrappers below
finish with `<kind>|<result>`: `errors:<n>`, `related:<made>:<skipped>`,
`error:<reason>`, `ok` or `crashed`. `null` is no flash.

    export class StackFlash(public level: String, public text: String) {}

    export let stacksFlashFor(status: String, detail: String?): StackFlash? {
      let parts = stacksSplitOnce(stacksOrEmpty(detail), "|");
      let kind = parts[0];
      let result = parts[1];
      if (status == "crashed" || result == "crashed") {
        return new StackFlash("error", "The ${kind} pass crashed. What finished is saved.");
      }
      let pieces = result.split(":");
      if (pieces[0] == "related" && pieces.length == 3) {
        let made = do { pieces[1].toInt32() } orelse 0;
        let skipped = do { pieces[2].toInt32() } orelse 0;
        let noun = if (made == 1) { "" } else { "s" };
        if (skipped == 0) {
          new StackFlash("info", "Related ${made.toString()} pair${noun}.")
        } else {
          new StackFlash(
            "info",
            "Related ${made.toString()}. ${skipped.toString()} could not be: both documents have to have been read.",
          )
        }
      } else if (pieces[0] == "errors" && pieces.length == 2) {
        let n = do { pieces[1].toInt32() } orelse 0;
        if (n == 0) { null } else { new StackFlash("error", "${n.toString()} document(s) did not read.") }
      } else if (pieces[0] == "error") {
        new StackFlash("error", "The ${kind} pass failed: ${stacksSplitOnce(result, ":")[1]}")
      } else {
        null
      }
    }

The flash when a second pass is started on a folder that already has one.

    export let stacksAlreadyRunning(other: String): StackFlash {
      new StackFlash("error", "A ${other} pass is already running on this folder.")
    }

## One tool call

`LLM.call_tool/1`: `chat` with the one tool, effort `high` (so `tool_choice`
is `auto`, as DeepSeek rejects a forced choice while thinking is on), and the
first tool call's arguments decoded. A reply without a tool call is
`no_tool_call`; arguments that are not a JSON object are `invalid_json`. The
model is the client's own (`LLM_MODEL`, else the provider's).

    let stacksFailed(kind: String, detail: String): Result<JsonObject, LlmError> {
      new Result<JsonObject, LlmError>(null, new LlmError(kind, detail))
    }

    let stacksCallTool(
      llm: LlmClient,
      tool: LlmTool,
      system: String,
      user: String,
      temperature: Float64,
      maxTokens: Int,
    ): Result<JsonObject, LlmError> {
      let call = new LlmCall(
        [new LlmMessage("system", system), new LlmMessage("user", user)],
        null, "high", maxTokens, temperature, false, [tool], null, 0,
      );
      let replied = llm.chat(call);
      let err = replied.err;
      let reply = replied.ok;
      if (err != null) {
        new Result<JsonObject, LlmError>(null, err)
      } else if (reply != null) {
        stacksToolArguments(reply)
      } else {
        stacksFailed("http", "no reply")
      }
    }

    let stacksToolArguments(reply: LlmReply): Result<JsonObject, LlmError> {
      if (reply.toolCalls.length == 0) {
        stacksFailed("no_tool_call", "the model answered without calling the tool")
      } else {
        let args = reply.toolCalls[0].argumentsJson;
        let text = if (args.isEmpty) { "{}" } else { args };
        let parsed: JsonSyntaxTree? = do { parseJson(text) } orelse null;
        if (parsed is JsonObject) {
          new Result<JsonObject, LlmError>(parsed, null)
        } else {
          stacksFailed("invalid_json", "the tool arguments are not a JSON object")
        }
      }
    }

## Reading one document forwards

`prior` is the steps already read, in order. They are handed over as their
capabilities alone: the model needs to know what it may rely on, not how any
of it was argued. The last 25 are shown.

    export class StackStepResult(public step: StackStep?, public error: String?) {}

    let stacksBuildingLine(building: String?, anyString: Boolean): String {
      if (building != null) {
        if (!anyString && building.isEmpty) { "" } else { "The series builds: ${building}\n\n" }
      } else {
        ""
      }
    }

    let stacksReadMessage(work: Work, ordinal: Int, prior: List<StackStep>, body: String, building: String?): String {
      var established = "  (nothing — this is the first document)";
      if (prior.length > 0) {
        let from = if (prior.length > 25) { prior.length - 25 } else { 0 };
        let lines = new ListBuilder<String>();
        var i = from;
        while (i < prior.length) {
          lines.add("  ${prior[i].ordinal.toString()}. ${stacksOrEmpty(prior[i].capability)}");
          i += 1;
        }
        established = sysJoin(lines.toList(), "\n");
      }
      "${stacksBuildingLine(building, false)}# Document ${ordinal.toString()}: ${work.title}\n\nWhat the earlier documents established, in order:\n${established}\n\n## The document\n\n${body}\n"
    }

    let stacksNullIfEmpty(s: String?): String? {
      if (s != null) {
        if (s.isEmpty) { null } else { s }
      } else {
        null
      }
    }

    let stacksLoadedStep(db: Db, row: DbRow): StackStep throws Bubble {
      let step = StackStep.fromRow(row);
      step.work = worksGetById(db, step.workId);
      step
    }

    let stacksStepOfWork(db: Db, folderId: Int, workId: Int): StackStep? throws Bubble {
      let row = db.one(
        "SELECT ${stacksStepColumns} FROM stack_steps WHERE folder_id = $1 AND work_id = $2",
        stacksArgs().n(folderId).n(workId).build(),
      );
      if (row != null) { stacksLoadedStep(db, row) } else { null }
    }

The upsert: a re-read overwrites every column but `id` and `inserted_at`, so
the second pass's fields (`mechanism`, `watch_for`, `revised_by`, `revision`,
`revision_quote`, `deep_dropped`, `deepened_at`) go back to their defaults.

    let stacksStoreStep(
      db: Db, folderId: Int, work: Work, ordinal: Int, fingerprint: String, v: StackValidated,
    ): Void throws Bubble {
      let now = sysUtcNow();
      let a = v.attrs;
      db.exec(
        "INSERT INTO stack_steps (folder_id, work_id, ordinal, capability, requires, lesson, pitfall, pitfall_quote, excerpts, fingerprint, dropped, mechanism, watch_for, revised_by, revision, revision_quote, deep_dropped, deepened_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NULL, NULL, NULL, NULL, NULL, '[]', NULL, $12, $12) ON CONFLICT(folder_id, work_id) DO UPDATE SET ordinal = excluded.ordinal, capability = excluded.capability, requires = excluded.requires, lesson = excluded.lesson, pitfall = excluded.pitfall, pitfall_quote = excluded.pitfall_quote, excerpts = excluded.excerpts, fingerprint = excluded.fingerprint, dropped = excluded.dropped, mechanism = NULL, watch_for = NULL, revised_by = NULL, revision = NULL, revision_quote = NULL, deep_dropped = '[]', deepened_at = NULL, updated_at = excluded.updated_at",
        stacksArgs().n(folderId).n(work.id).n(ordinal)
          .s(stacksNullIfEmpty(a.capability)).s(stacksJsonInts(a.requires))
          .s(stacksNullIfEmpty(a.lesson)).s(a.pitfall).s(a.pitfallQuote)
          .s(stacksExcerptsJson(a.excerpts)).s(fingerprint)
          .s(stacksJsonStrings(v.dropped)).s(now).build(),
      );
    }

Read one document, knowing only what came before it. LLM call 5, tool
`report_step`, effort high, temperature 0.2, 3,000 tokens of answer. On a
model error the step is not written and the error comes back (no retry here;
the client's own three attempts already happened).

    export let stacksReadStep(
      db: Db,
      llm: LlmClient,
      folderId: Int,
      work: Work,
      ordinal: Int,
      prior: List<StackStep>,
      building: String?,
    ): StackStepResult throws Bubble {
      let body = stacksTextOf(db, work.id);
      let called = stacksCallTool(
        llm, stacksReportStepTool(), stacksReadPrompt(),
        stacksReadMessage(work, ordinal, prior, body, building), 0.2, 3000,
      );
      let err = called.err;
      let raw = called.ok;
      if (err != null) {
        new StackStepResult(null, llmErrorText(err))
      } else if (raw != null) {
        stacksReadStored(db, folderId, work, ordinal, body, raw)
      } else {
        new StackStepResult(null, "no answer")
      }
    }

    let stacksReadStored(
      db: Db, folderId: Int, work: Work, ordinal: Int, body: String, raw: JsonObject,
    ): StackStepResult throws Bubble {
      let validated = stacksValidate(raw, body, ordinal);
      stacksStoreStep(db, folderId, work, ordinal, stacksFingerprintOfText(body), validated);
      new StackStepResult(stacksStepOfWork(db, folderId, work.id), null)
    }

`read_stack/3`, as the run's body: every document of the folder in order,
sequentially and not for want of trying (each is told what the ones before it
established, so the call for step N cannot be made until N-1 has come back).
`building` is the folder's name. A failed document is skipped, its ordinal
is not reused, and it is not among the `prior` of the next.

    export let stacksReadPass(
      db: Db,
      llm: LlmClient,
      scope: Scope,
      folderId: Int,
      progress: fn (String, String?): Void,
    ): StackPassResult throws Bubble {
      let docs = stacksDocuments(db, scope, folderId);
      let folder = foldersGetFolderOrNull(db, scope, folderId);
      let building: String? = if (folder != null) { folder.name } else { null };
      let total = docs.length;
      progress(runsCounts(0, total), "read");
      let prior = new ListBuilder<StackStep>();
      let failures = new ListBuilder<StackFailure>();
      var i = 1;
      while (i <= total) {
        let work = docs[i - 1];
        let r = stacksReadStep(db, llm, folderId, work, i, prior.toList(), building);
        let step = r.step;
        if (step != null) {
          prior.add(step);
          progress(runsCounts(i, total), "read");
        } else {
          failures.add(new StackFailure(i, work.title, stacksOrEmpty(r.error)));
        }
        i += 1;
      }
      stacksErrorsResult(prior.length, failures.toList())
    }

## The second pass

The chain is given as every step's capability, before and after. A step that
failed the second pass must not look like one nobody asked to deepen:
`deep_dropped` carries `the second pass failed: <reason>` and `deepened_at`
stays empty, which is how `stats` counts it as failed.

    let stacksDeepMessage(step: StackStep, work: Work, body: String, chain: List<StackStep>, building: String?): String {
      let lines = new ListBuilder<String>();
      for (let s of chain) {
        let mark = if (s.ordinal == step.ordinal) { ">> " } else { "   " };
        lines.add("${mark}${s.ordinal.toString()}. ${stacksOrEmpty(s.capability)}");
      }
      let laterBlocks = new ListBuilder<String>();
      for (let s of chain) {
        if (s.ordinal > step.ordinal) {
          let pitfall = s.pitfall;
          let tail = if (pitfall != null) { "\nPitfall: ${pitfall}" } else { "" };
          laterBlocks.add("### Step ${s.ordinal.toString()}: ${stacksOrEmpty(s.capability)}\n${stacksOrEmpty(s.lesson)}${tail}");
        }
      }
      let laterDetail = sysJoin(laterBlocks.toList(), "\n\n");
      let pitfall = step.pitfall;
      let pitfallLine = if (pitfall != null) { "The pitfall it named: ${pitfall}\n" } else { "" };
      let after = if (laterDetail == "") { "(nothing — this is the last step)" } else { laterDetail };
      "${stacksBuildingLine(building, true)}# The whole series (>> marks the step you are re-reading)\n\n${sysJoin(lines.toList(), "\n")}\n\n# Step ${step.ordinal.toString()}: ${work.title}\n\nWhat the first reading said it establishes: ${stacksOrEmpty(step.capability)}\nWhat it said to do: ${stacksOrEmpty(step.lesson)}\n${pitfallLine}\n## The document itself\n\n${body}\n\n## Everything that comes after it\n\n${after}\n"
    }

    let stacksStepById(db: Db, id: Int): StackStep? throws Bubble {
      let row = db.one(
        "SELECT ${stacksStepColumns} FROM stack_steps WHERE id = $1",
        stacksArgs().n(id).build(),
      );
      if (row != null) { stacksLoadedStep(db, row) } else { null }
    }

Read one step again, with the whole chain in hand. LLM call 6, tool
`deepen_step`, effort high, temperature 0.2, 3,000 tokens. `building` is
included in the prompt when it is any string at all, even an empty one;
`stacksDeepenPass` passes none.

    export let stacksDeepenStep(
      db: Db,
      llm: LlmClient,
      step: StackStep,
      chain: List<StackStep>,
      building: String?,
    ): StackStepResult throws Bubble {
      let work = worksGetById(db, step.workId);
      if (work != null) {
        stacksDeepenWith(db, llm, step, work, chain, building)
      } else {
        bubble()
      }
    }

    let stacksDeepenWith(
      db: Db,
      llm: LlmClient,
      step: StackStep,
      work: Work,
      chain: List<StackStep>,
      building: String?,
    ): StackStepResult throws Bubble {
      let body = stacksTextOf(db, work.id);
      let later = chain.filter { (s: StackStep): Boolean => s.ordinal > step.ordinal };
      let called = stacksCallTool(
        llm, stacksDeepenStepTool(), stacksDeepPrompt(),
        stacksDeepMessage(step, work, body, chain, building), 0.2, 3000,
      );
      let now = sysUtcNow();
      let err = called.err;
      let raw = called.ok;
      if (err != null) {
        let reason = llmErrorText(err);
        db.exec(
          "UPDATE stack_steps SET deep_dropped = $1, deepened_at = NULL, updated_at = $2 WHERE id = $3",
          stacksArgs().s(stacksJsonStrings(["the second pass failed: ${reason}"])).s(now).n(step.id).build(),
        );
        new StackStepResult(null, reason)
      } else if (raw != null) {
        let v = stacksValidateDeep(raw, later);
        let a = v.attrs;
        db.exec(
          "UPDATE stack_steps SET mechanism = $1, watch_for = $2, revised_by = $3, revision = $4, revision_quote = $5, deep_dropped = $6, deepened_at = $7, updated_at = $8 WHERE id = $9",
          stacksArgs().s(a.mechanism).s(a.watchFor).no(a.revisedBy).s(a.revision).s(a.revisionQuote)
            .s(stacksJsonStrings(v.dropped)).s(now).s(now).n(step.id).build(),
        );
        new StackStepResult(stacksStepById(db, step.id), null)
      } else {
        new StackStepResult(null, "no answer")
      }
    }

`deepen_stack/2`. Only what has not been deepened, unless `force`: a pass that
half-finished is finishable without paying for the half that worked.
Sequential, deliberately, for the provider's prefix cache over the chain every
call repeats. The count shown is `done + 1` of the whole chain.

    export let stacksDeepenPass(
      db: Db,
      llm: LlmClient,
      folderId: Int,
      force: Boolean,
      progress: fn (String, String?): Void,
    ): StackPassResult throws Bubble {
      let chain = stacksListSteps(db, folderId);
      let todo = if (force) { chain } else {
        chain.filter { (s: StackStep): Boolean => s.deepenedAt == null }
      };
      progress(runsCounts(0, chain.length), "deepen");
      let failures = new ListBuilder<StackFailure>();
      var done = 0;
      var i = 0;
      while (i < todo.length) {
        let step = todo[i];
        let r = stacksDeepenStep(db, llm, step, chain, null);
        if (r.step != null) {
          done += 1;
          progress(runsCounts(done, chain.length), "deepen");
        } else {
          let w = step.work;
          failures.add(new StackFailure(step.ordinal, if (w != null) { w.title } else { "" }, stacksOrEmpty(r.error)));
        }
        i += 1;
      }
      stacksErrorsResult(done, failures.toList())
    }

## Summarise each document

The whole-document summary of each document of the folder. Not the forward
read: a summary is what one document says, and a step is what somebody
building the same thing has to do next. `summarise` is the summary context's
`Document.run`, handed in because that context is not a dependency of this
one; it answers the failure reason, or `null`. Already-summarised documents
(any `document_summaries` row) are skipped unless `force`. `progress` ticks
after every document, failed or not.

    let stacksSummarisedIds(db: Db, docs: List<Work>): List<Int> throws Bubble {
      if (docs.length == 0) { return []; }
      let args = stacksArgs();
      for (let w of docs) { args.n(w.id); }
      let rows = db.query(
        "SELECT work_id FROM document_summaries WHERE work_id IN (${stacksPlaceholders(docs.length, 1)})",
        args.build(),
      );
      let out = new ListBuilder<Int>();
      for (let row of rows) { out.add(row.int("work_id")); }
      out.toList()
    }

    export let stacksSummarisePass(
      db: Db,
      scope: Scope,
      folderId: Int,
      force: Boolean,
      summarise: fn (Work): String? throws Bubble,
      progress: fn (String, String?): Void,
    ): StackPassResult throws Bubble {
      let docs = stacksDocuments(db, scope, folderId);
      var todo = docs;
      if (!force) {
        let have = stacksSummarisedIds(db, docs);
        todo = docs.filter { (w: Work): Boolean => !stacksContainsInt(have, w.id) };
      }
      let total = todo.length;
      progress(runsCounts(0, total), "summarise");
      let failures = new ListBuilder<StackFailure>();
      var i = 0;
      while (i < total) {
        let work = todo[i];
        let reason = summarise(work);
        if (reason != null) { failures.add(new StackFailure(0, work.title, reason)); }
        progress(runsCounts(i + 1, total), "summarise");
        i += 1;
      }
      stacksErrorsResult(total - failures.length, failures.toList())
    }

## Read each document

The ordinary read, in bulk: the one a draft gets on its own page (beats,
spine, the weave between them), not the forward read, which never touches the
documents' own graphs. A folder of nine fully-stepped documents can still have
nothing to relate until this has run. `readOne` is `Analysis.run`, handed in
for the same reason; it is assumed to succeed, as the Elixir assumed, and a
document that comes out with no nodes is the failure, `nothing_read`.
Documents already `read` are skipped unless `force`.

    export let stacksReadEachPass(
      db: Db,
      scope: Scope,
      folderId: Int,
      force: Boolean,
      readOne: fn (Work): Void throws Bubble,
      progress: fn (String, String?): Void,
    ): StackPassResult throws Bubble {
      let docs = stacksDocuments(db, scope, folderId);
      let todo = if (force) { docs } else {
        docs.filter { (w: Work): Boolean => w.status != "read" }
      };
      let total = todo.length;
      progress(runsCounts(0, total), "read_each");
      let failures = new ListBuilder<StackFailure>();
      var i = 0;
      while (i < total) {
        let work = todo[i];
        readOne(work);
        progress(runsCounts(i + 1, total), "read_each");
        let row = db.one("SELECT count(*) AS n FROM nodes WHERE work_id = $1", stacksArgs().n(work.id).build());
        if (row == null || row.int("n") == 0) {
          failures.add(new StackFailure(0, work.title, "nothing_read"));
        }
        i += 1;
      }
      stacksErrorsResult(total - failures.length, failures.toList())
    }

## Relate the documents

The fifth pass, and the only one that reads documents against each other
rather than in order: triage first, then one call per pair it chose. That is
`Links.Bulk.run`, which belongs to the links context and is handed in as
`bulk`. It is given the two callbacks the Elixir passed, as `hooks.stage(name)`
and `hooks.pair(total)`. The pairs finish in whatever order they finish in
Elixir; here the count is the hooks' own, one more at each `pair`.

    export class StackRelateOutcome(public made: Int, public skipped: Int, public error: String?) {}

    export class StackRelateHooks(private progress: fn (String, String?): Void) {
      private var done: Int = 0;
      private var total: Int = 0;

      /** `on_stage`: the counts stand, the stage changes. */
      public stage(name: String): Void {
        progress(runsCounts(done, total), "relate:${name}");
      }

      /** `on_pair`: another pair finished, out of `pairs`. */
      public pair(pairs: Int): Void {
        done += 1;
        total = pairs;
        progress(runsCounts(done, total), "relate:relating");
      }
    }

    export let stacksRelatePass(
      bulk: fn (StackRelateHooks): StackRelateOutcome throws Bubble,
      progress: fn (String, String?): Void,
    ): StackPassResult throws Bubble {
      progress(runsCounts(0, 0), "relate");
      let outcome = bulk(new StackRelateHooks(progress));
      let error = outcome.error;
      if (error != null) {
        new StackPassResult(0, [new StackFailure(0, "", error)], "error:${error}")
      } else {
        new StackPassResult(outcome.made, [], "related:${outcome.made.toString()}:${outcome.skipped.toString()}")
      }
    }

## Compose the longform story

Two stages, because one will not fit. A hundred steps of capability, lesson,
mechanism, pitfall and revision is about fifty thousand tokens of input, and
asking for sixteen thousand of output on top of that exceeds the context. So
the outline is drawn from the capabilities alone, which is small, and each
part's prose is written from only the steps in that part. Every call is
bounded by the size of a part rather than by the size of the stack.

`error` is `not_read` (no steps), the outline call's failure (nothing is
stored), or `null` with the stored `story`.

    export class StackComposed(public story: StackStory?, public error: String?) {
      public detail(): String {
        let e = error;
        if (e != null) { "error:${e}" } else { "ok" }
      }
    }

    let stacksBuilding(building: String?): String {
      if (building != null) { building } else { "the thing this series builds" }
    }

Stage one, the spine only: one line per step, so a stack of any length fits in
a prompt that does not grow with the detail of its steps. LLM call 7, tool
`outline_story`, temperature 0.4, 6,000 tokens.

    let stacksSpine(steps: List<StackStep>): String {
      let lines = new ListBuilder<String>();
      for (let s of steps) {
        let marks = new ListBuilder<String>();
        if (s.pitfall != null) { marks.add("pitfall"); }
        let rev = s.revisedBy;
        if (rev != null) { marks.add("revised by ${rev.toString()}"); }
        let tail = if (marks.length == 0) { "" } else { "   [${sysJoin(marks.toList(), ", ")}]" };
        lines.add("${s.ordinal.toString()}. ${stacksOrEmpty(s.capability)}${tail}");
      }
      sysJoin(lines.toList(), "\n")
    }

    let stacksOutline(llm: LlmClient, steps: List<StackStep>, building: String?): Result<JsonObject, LlmError> throws Bubble {
      stacksCallTool(
        llm, stacksOutlineStoryTool(), stacksComposePrompt(),
        "What is being built: ${stacksBuilding(building)}\n${steps.length.toString()} steps, in order. Divide them into parts.\n\n${stacksSpine(steps)}\n",
        0.4, 6000,
      )
    }

Stage two, one part and only the steps in it. LLM call 8, tool `write_part`,
temperature 0.4, 4,000 tokens. A part that would not write has prose `""`, so
the validator drops it and the coverage check then names every step it was
carrying; the error itself is swallowed.

    let stacksStepDetail(s: StackStep): String {
      let lines = new ListBuilder<String>();
      lines.add("## Step ${s.ordinal.toString()}: ${stacksOrEmpty(s.capability)}");
      if (s.requires.length > 0) { lines.add("Stands on: ${stacksJoinInts(s.requires, ", ")}"); }
      lines.add("What to do: ${stacksOrEmpty(s.lesson)}");
      let mechanism = s.mechanism;
      if (mechanism != null) { lines.add("How it works: ${mechanism}"); }
      let pitfall = s.pitfall;
      if (pitfall != null) { lines.add("The obvious version is wrong: ${pitfall}"); }
      let watch = s.watchFor;
      if (watch != null) { lines.add("Get right now: ${watch}"); }
      let rev = s.revisedBy;
      if (rev != null) { lines.add("Walked back by step ${rev.toString()}: ${stacksOrEmpty(s.revision)}"); }
      sysJoin(lines.toList(), "\n")
    }

    let stacksPartOrdinals(part: JsonSyntaxTree): List<Int> {
      let out = new ListBuilder<Int>();
      for (let x of stacksElements(stacksProp(part, "steps"))) {
        let n = stacksAsInt(x);
        if (n != null) { out.add(n); }
      }
      out.toList()
    }

One movement as the validator reads it: `{"heading", "steps", "prose",
"turn"}`, each value as the model gave it. A part that would not write has the
empty prose and turn.

    let stacksWriteEmpty(p: JsonTextProducer): Void {
      p.stringValue("");
      p.objectKey("turn");
      p.stringValue("");
    }

    let stacksWritePart(
      llm: LlmClient,
      part: JsonSyntaxTree,
      steps: List<StackStep>,
      title: JsonSyntaxTree?,
      building: String?,
      p: JsonTextProducer,
    ): Void throws Bubble {
      let ordinals = stacksPartOrdinals(part);
      let mine = steps.filter { (s: StackStep): Boolean => stacksContainsInt(ordinals, s.ordinal) };
      let detail = sysJoin(mine.map { (s: StackStep): String => stacksStepDetail(s) }, "\n\n");
      let heading = stacksProp(part, "heading");
      let written = stacksCallTool(
        llm, stacksWritePartTool(), stacksComposePrompt(),
        "What is being built: ${stacksBuilding(building)}\nThe telling is called: ${stacksStringOf(title)}\n\nYou are writing one part of it: **${stacksStringOf(heading)}**\nIt covers steps ${stacksJoinInts(ordinals, ", ")} and nothing else.\n\n${detail}\n",
        0.4, 4000,
      );
      p.startObject();
      p.objectKey("heading");
      if (heading != null) { heading.produce(p); } else { p.nullValue(); }
      p.objectKey("steps");
      p.startArray();
      for (let n of ordinals) { p.int32Value(n); }
      p.endArray();
      p.objectKey("prose");
      let w = written.ok;
      if (w != null) {
        let prose = w.propertyValueOrNull("prose");
        if (prose != null) {
          prose.produce(p);
          p.objectKey("turn");
          let turn = w.propertyValueOrNull("turn");
          if (turn != null) { turn.produce(p); } else { p.nullValue(); }
        } else {
          stacksWriteEmpty(p);
        }
      } else {
        stacksWriteEmpty(p);
      }
      p.endObject();
    }

`store_story`: validate, then upsert on `folder_id`, overwriting every column
but `id` and `inserted_at`.

    let stacksStoreStory(db: Db, folderId: Int, steps: List<StackStep>, raw: JsonObject): StackStory? throws Bubble {
      let v = stacksValidateStory(raw, steps);
      let a = v.attrs;
      let now = sysUtcNow();
      db.exec(
        "INSERT INTO stack_stories (folder_id, title, opening, movements, closing, uncovered, dropped, fingerprint, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $9) ON CONFLICT(folder_id) DO UPDATE SET title = excluded.title, opening = excluded.opening, movements = excluded.movements, closing = excluded.closing, uncovered = excluded.uncovered, dropped = excluded.dropped, fingerprint = excluded.fingerprint, updated_at = excluded.updated_at",
        stacksArgs().n(folderId).s(stacksNullIfEmpty(a.title)).s(stacksNullIfEmpty(a.opening))
          .s(stacksMovementsJson(a.movements)).s(stacksNullIfEmpty(a.closing))
          .s(stacksJsonInts(v.uncovered)).s(stacksJsonStrings(v.dropped))
          .s(stacksStoryFingerprint(steps)).s(now).build(),
      );
      stacksGetStory(db, folderId)
    }

`compose/2`. `progress` is told `outlining` first (`0/0`, `compose:outlining`),
then `writing` before each part (`i-1` of `n`) and once more at `n` of `n`.

    export let stacksCompose(
      db: Db,
      llm: LlmClient,
      folderId: Int,
      building: String?,
      progress: fn (String, String?): Void,
    ): StackComposed throws Bubble {
      let steps = stacksListSteps(db, folderId);
      if (steps.length == 0) {
        new StackComposed(null, "not_read")
      } else {
        progress(runsCounts(0, 0), "compose:outlining");
        let outlined = stacksOutline(llm, steps, building);
        let err = outlined.err;
        let outline = outlined.ok;
        if (err != null) {
          new StackComposed(null, llmErrorText(err))
        } else if (outline != null) {
          stacksComposeParts(db, llm, folderId, steps, outline, building, progress)
        } else {
          new StackComposed(null, "no answer")
        }
      }
    }

    let stacksComposeParts(
      db: Db,
      llm: LlmClient,
      folderId: Int,
      steps: List<StackStep>,
      outline: JsonObject,
      building: String?,
      progress: fn (String, String?): Void,
    ): StackComposed throws Bubble {
      let parts = stacksElements(outline.propertyValueOrNull("parts"));
      let title = outline.propertyValueOrNull("title");
      let p = new JsonTextProducer();
      p.startObject();
      for (let key of ["title", "opening", "closing"]) {
        let v = outline.propertyValueOrNull(key);
        if (v != null) {
          p.objectKey(key);
          v.produce(p);
        }
      }
      p.objectKey("movements");
      p.startArray();
      var i = 1;
      while (i <= parts.length) {
        progress(runsCounts(i - 1, parts.length), "compose:writing");
        stacksWritePart(llm, parts[i - 1], steps, title, building, p);
        i += 1;
      }
      progress(runsCounts(parts.length, parts.length), "compose:writing");
      p.endArray();
      p.endObject();
      let parsed = parseJson(p.toJsonString());
      if (parsed is JsonObject) {
        new StackComposed(stacksStoreStory(db, folderId, steps, parsed), null)
      } else {
        bubble()
      }
    }

## Job bodies

What `runsStart` is given: the pass, then `runsFinish` with `<kind>|<result>` so
the page can word its flash (`stacksFlashFor`). A pass that bubbles leaves
`<kind>|crashed`. `own` is the job's own `Db`.

    let stacksFinish(own: Db, folderId: Int, kind: String, ran: Boolean, result: String): Void {
      let status = if (ran) { "done" } else { "crashed" };
      let text = if (ran) { result } else { "crashed" };
      let wrote = do { runsFinish(own, stacksRunKey(folderId), status, "${kind}|${text}"); true } orelse false;
      if (!wrote) { console.log("stacks: could not finish the ${kind} run of folder ${folderId.toString()}"); }
    }

    export let stacksJobRead(own: Db, llm: LlmClient, scope: Scope, folderId: Int): Void {
      var detail = "";
      let ran = do {
        let r = stacksReadPass(own, llm, scope, folderId, fn (p: String, d: String?): Void { stacksReport(own, folderId, p, d); });
        detail = r.detail;
        true
      } orelse false;
      stacksFinish(own, folderId, "read", ran, detail);
    }

    export let stacksJobDeepen(own: Db, llm: LlmClient, folderId: Int, force: Boolean): Void {
      var detail = "";
      let ran = do {
        let r = stacksDeepenPass(own, llm, folderId, force, fn (p: String, d: String?): Void { stacksReport(own, folderId, p, d); });
        detail = r.detail;
        true
      } orelse false;
      stacksFinish(own, folderId, "deepen", ran, detail);
    }

    export let stacksJobCompose(own: Db, llm: LlmClient, folderId: Int, building: String?): Void {
      var detail = "";
      let ran = do {
        let r = stacksCompose(own, llm, folderId, building, fn (p: String, d: String?): Void { stacksReport(own, folderId, p, d); });
        detail = r.detail();
        true
      } orelse false;
      stacksFinish(own, folderId, "compose", ran, detail);
    }

    export let stacksJobSummarise(
      own: Db, scope: Scope, folderId: Int, force: Boolean,
      summarise: fn (Work): String? throws Bubble,
    ): Void {
      var detail = "";
      let ran = do {
        let r = stacksSummarisePass(own, scope, folderId, force, summarise, fn (p: String, d: String?): Void { stacksReport(own, folderId, p, d); });
        detail = r.detail;
        true
      } orelse false;
      stacksFinish(own, folderId, "summarise", ran, detail);
    }

    export let stacksJobReadEach(
      own: Db, scope: Scope, folderId: Int, force: Boolean,
      readOne: fn (Work): Void throws Bubble,
    ): Void {
      var detail = "";
      let ran = do {
        let r = stacksReadEachPass(own, scope, folderId, force, readOne, fn (p: String, d: String?): Void { stacksReport(own, folderId, p, d); });
        detail = r.detail;
        true
      } orelse false;
      stacksFinish(own, folderId, "read_each", ran, detail);
    }

    export let stacksJobRelate(
      own: Db, folderId: Int,
      bulk: fn (StackRelateHooks): StackRelateOutcome throws Bubble,
    ): Void {
      var detail = "";
      let ran = do {
        let r = stacksRelatePass(bulk, fn (p: String, d: String?): Void { stacksReport(own, folderId, p, d); });
        detail = r.detail;
        true
      } orelse false;
      stacksFinish(own, folderId, "relate", ran, detail);
    }
