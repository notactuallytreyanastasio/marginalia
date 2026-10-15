# The Read

`Marginalia.Analysis`: turn a confirmed manuscript into a map. One call per
section from the fast model (the beats), one call over the whole map from the
good model (the spine, the first impression, the questions), then the weave.

The Elixir read sections three at a time inside a detached task. Here the
whole read is one job body (`analysisStart`) and the sections are read one
after another: the interpreter has no threads, and the `runs` library gives the
body a process of its own. A read therefore takes about three times as long
on a draft with many sections, which is the whole cost of the port.

    let { Db } = import("db/src");
    let {
      Work, Section, GraphNode, NodeParams, worksListSections, worksListNodes, worksInsertNodes,
      worksLink, worksSetStatus, worksSetSectionStatus, worksResetRead, worksUpdateWork,
      workParams, worksGetById,
    } = import("works/src");
    let { versionsBump, versionsWorkTopic, runsProgress, runsCounts } = import("runs/src");
    let {
      LlmClient, LlmCall, LlmMessage, LlmTool, LlmError, LlmReply, Result,
      llmConfigFromEnv, llmProvider,
    } = import("llm/src");
    let { sysGraphemeTake, sysJoin } = import("sys/src");
    let { JsonSyntaxTree, JsonObject } = import("std/json");

## Topics and broadcasts

`Analysis.topic/1`.

    export let analysisTopic(workId: Int): String { versionsWorkTopic(workId) }

Every `Phoenix.PubSub.broadcast` becomes one bump of the work's counter. A
bump that fails is not a reason to abandon a read.

    export let analysisBump(db: Db, workId: Int): Void {
      let done = do {
        versionsBump(db, versionsWorkTopic(workId));
        true
      } orelse false;
      if (!done) { console.log("marginalia: could not bump work ${workId.toString()}"); }
    }

## Density

About one move per 220 words, floored at 2 and capped at 14.

    export let analysisBeatTarget(words: Int): Int {
      let t = words / 220;
      let floored = if (t < 2) { 2 } else { t };
      if (floored > 14) { 14 } else { floored }
    }

The limit sits a little above the target: `t < ceiling < 2t`.

    export let analysisBeatCeiling(words: Int): Int {
      let t = analysisBeatTarget(words);
      let half = t / 2;
      t + (if (half < 1) { 1 } else { half })
    }

An over-long answer is thinned to `ceiling` evenly spaced items, first and
last kept, so the section stays covered end to end. The index of item `i` is
`round(i * (n - 1) / (ceiling - 1))`, half away from zero, done in integers.

    export let analysisThin<T>(beats: List<T>, ceiling: Int, sectionId: Int): List<T> throws Bubble {
      let n = beats.length;
      if (n <= ceiling) { return beats; }
      console.log("marginalia: section ${sectionId.toString()} returned ${n.toString()} beats, thinning to ${ceiling.toString()}");
      let out = new ListBuilder<T>();
      let denom = 2 * (ceiling - 1);
      var last = -1;
      var i = 0;
      while (i < ceiling) {
        let at = (2 * i * (n - 1) + (ceiling - 1)) / denom;
        if (at != last) { out.add(beats[at]); }
        last = at;
        i += 1;
      }
      out.toList()
    }

## The beats tool

    export let analysisBeatsTool(): LlmTool {
      new LlmTool(
        "record_beats",
        "Record the beats of this section, in the order they happen on the page.",
        analysisBeatsToolParameters(),
      )
    }

`tool_choice` forced to one function, as `LLM.call_tool` does when the effort
is `none`.

    export let analysisForcedChoice(fname: String): String {
      "{\"type\":\"function\",\"function\":{\"name\":\"${fname}\"}}"
    }

The provider's fast model for the configured provider.

    export let analysisFastModel(): String {
      llmProvider(llmConfigFromEnv().provider).fastModel
    }

    export let analysisDefaultModel(): String {
      llmProvider(llmConfigFromEnv().provider).model
    }

The user message of one section.

    export let analysisBeatsUser(work: Work, section: Section): String {
      let intent = anIntent("What it is meant to do to a reader: ", work.intent);
      "Manuscript: ${work.title}\n${intent}\nSection ${section.ordinal.toString()}: ${section.title}\n${section.wordCount.toString()} words. Aim for about ${analysisBeatTarget(section.wordCount).toString()} beats.\nHARD LIMIT: return at most ${analysisBeatCeiling(section.wordCount).toString()}. More than that is refused.\n\n---\n${sysGraphemeTake(section.body, 24000)}\n"
    }

## One section

What a forced tool call gave back: the arguments as an object, or why not.
`:no_tool_call` is a reply without one, `:invalid_json` arguments that are not
an object.

    class AnalysisArgs(public args: JsonObject?, public reason: String) {}

    let analysisToolArgs(r: Result<LlmReply, LlmError>): AnalysisArgs {
      let reply = r.ok;
      if (reply != null) {
        if (reply.toolCalls.length == 0) {
          new AnalysisArgs(null, ":no_tool_call")
        } else {
          let tree = anParse(reply.toolCalls[0].argumentsJson);
          if (tree is JsonObject) {
            new AnalysisArgs(tree, "")
          } else {
            new AnalysisArgs(null, ":invalid_json")
          }
        }
      } else {
        let e = r.err;
        new AnalysisArgs(null, if (e != null) { anInspect(e) } else { "unknown" })
      }
    }

    let analysisFailSection(db: Db, work: Work, section: Section, reason: String): AnalysisSectionResult throws Bubble {
      console.log("marginalia: section ${section.id.toString()} failed: ${reason}");
      worksSetSectionStatus(db, section, "failed");
      analysisBump(db, work.id);
      new AnalysisSectionResult("failed", 0, 0, reason)
    }

Pass 1 for one section: mark it reading, ask for its beats with a forced tool
call, keep the beats whose quotes are in the section word for word (each
rewritten to the section's own wording), thin them to the limit, store them,
chain them with `follows` edges, mark the section read. Any failure marks the
section failed and the read goes on.

    export let analysisReadSection(db: Db, llm: LlmClient, work: Work, section: Section): AnalysisSectionResult throws Bubble {
      worksSetSectionStatus(db, section, "reading");
      analysisBump(db, work.id);
      let call = new LlmCall(
        [new LlmMessage("system", analysisBeatsPrompt()), new LlmMessage("user", analysisBeatsUser(work, section))],
        analysisFastModel(),
        "none",
        4000,
        0.3,
        false,
        [analysisBeatsTool()],
        analysisForcedChoice("record_beats"),
        0,
      );
      let got = analysisToolArgs(llm.chat(call));
      if (got.args == null) { return analysisFailSection(db, work, section, got.reason); }
      let beats = anElements(anField(got.args, "beats"));
      if (beats != null) {
        analysisStoreBeats(db, work, section, beats)
      } else {
        analysisFailSection(db, work, section, "no beats returned")
      }
    }

    let analysisStoreBeats(db: Db, work: Work, section: Section, beats: List<JsonSyntaxTree>): AnalysisSectionResult throws Bubble {
      let candidates = new ListBuilder<NodeParams>();
      for (let b of beats) {
        if (b is JsonObject) {
          let title = anToLine(anStr(anField(b, "title")));
          if (title != null) {
            if (title != "") {
              let p = new NodeParams(work.id, "beat", title);
              p.body = anStr(anField(b, "note"));
              p.quote = anStr(anField(b, "quote"));
              candidates.add(p);
            }
          }
        }
      }
      let filtered = anchorFilter(candidates.toList(), section.body);
      let kept = analysisThin(filtered.kept, analysisBeatCeiling(section.wordCount), section.id);
      if (filtered.dropped > 0) {
        console.log("marginalia: dropped ${filtered.dropped.toString()}/${candidates.length.toString()} unanchored beats in section ${section.id.toString()}");
      }
      let nodes = worksInsertNodes(db, work.id, section.id, kept);
      var i = 0;
      while (i + 1 < nodes.length) {
        worksLink(db, work.id, nodes[i].id, nodes[i + 1].id, "follows", i, null);
        i += 1;
      }
      worksSetSectionStatus(db, section, "read");
      analysisBump(db, work.id);
      analysisBump(db, work.id);
      new AnalysisSectionResult("read", nodes.length, filtered.dropped, null)
    }

## The spine

The beat titles section by section, as the second pass is shown them.

    let analysisOutline(sections: List<Section>, beats: List<GraphNode>): String {
      let blocks = new ListBuilder<String>();
      for (let s of sections) {
        let lines = new ListBuilder<String>();
        for (let b of beats) {
          if (b.sectionId == s.id) { lines.add("  - ${b.title}"); }
        }
        blocks.add("## ${s.ordinal.toString()}. ${s.title} (${s.wordCount.toString()} words)\n${sysJoin(lines.toList(), "\n")}");
      }
      sysJoin(blocks.toList(), "\n\n")
    }

    export let analysisSpineUser(work: Work, sections: List<Section>, beats: List<GraphNode>): String {
      let intent = anIntent("What it is meant to do to a reader: ", work.intent);
      "Manuscript: ${work.title}\n${intent}\n${sections.length.toString()} sections, ${work.wordCount.toString()} words.\n\n${analysisOutline(sections, beats)}\n"
    }

    let analysisStepFail(e: LlmError?): AnalysisStep {
      new AnalysisStep(false, if (e != null) { anInspect(e) } else { "unknown" })
    }

Pass 2: the first impression, the spine, the threads and the questions, from
the beat titles alone. No beats is `:no_beats`. A reply that lacks a key is
treated as having none of that kind and still counts as success.

    export let analysisSynthesize(db: Db, llm: LlmClient, work: Work): AnalysisStep throws Bubble {
      let beats = worksListNodes(db, work.id, "beat", null, null);
      if (beats.length == 0) { return new AnalysisStep(false, ":no_beats"); }
      let sections = worksListSections(db, work.id);
      let call = new LlmCall(
        [new LlmMessage("system", analysisSpinePrompt()), new LlmMessage("user", analysisSpineUser(work, sections, beats))],
        null,
        "high",
        6000,
        0.5,
        true,
        [],
        null,
        0,
      );
      let r = llm.json(call);
      let data = r.ok;
      if (data != null) {
        analysisStoreSynthesis(db, work, data);
        new AnalysisStep(true, null)
      } else {
        analysisStepFail(r.err)
      }
    }

    let analysisSpineNodes(work: Work, items: List<JsonSyntaxTree>?, kind: String): List<NodeParams> {
      let out = new ListBuilder<NodeParams>();
      if (items != null) {
        for (let it of items) {
          if (it is JsonObject) {
            let title = anToLine(anStr(anField(it, "title")));
            if (title != null) {
              if (title != "") {
                let p = new NodeParams(work.id, kind, title);
                if (kind == "thread") {
                  let status = anStr(anField(it, "status"));
                  let note = anOrEmpty(anStr(anField(it, "note")));
                  let word = if (status != null) { status } else { "carried" };
                  p.body = "${word} \u{2014} ${note}";
                } else {
                  p.body = anStr(anField(it, "note"));
                }
                out.add(p);
              }
            }
          }
        }
      }
      out.toList()
    }

    let analysisQuestionNodes(work: Work, items: List<JsonSyntaxTree>?): List<NodeParams> {
      let out = new ListBuilder<NodeParams>();
      if (items != null) {
        for (let it of items) {
          let line = anToLine(anStr(it));
          if (line != null) {
            if (line != "") { out.add(new NodeParams(work.id, "question", line)); }
          }
        }
      }
      out.toList()
    }

    let analysisStoreSynthesis(db: Db, work: Work, data: JsonObject): Void throws Bubble {
      let spine = analysisSpineNodes(work, anElements(anField(data, "spine")), "spine");
      let threads = analysisSpineNodes(work, anElements(anField(data, "threads")), "thread");
      let questions = analysisQuestionNodes(work, anElements(anField(data, "questions")));
      let spineNodes = worksInsertNodes(db, work.id, null, spine);
      worksInsertNodes(db, work.id, null, threads);
      worksInsertNodes(db, work.id, null, questions);
      var i = 0;
      while (i + 1 < spineNodes.length) {
        worksLink(db, work.id, spineNodes[i].id, spineNodes[i + 1].id, "leads_to", i, null);
        i += 1;
      }
      let impression = anStr(anField(data, "first_impression"));
      if (impression != null) {
        let p = workParams(work.title, work.body);
        p.firstImpression = impression;
        worksUpdateWork(db, work, p);
      }
      analysisBump(db, work.id);
      analysisBump(db, work.id);
    }

## The whole read

The job body. If the work was already read, the old read is thrown away
first (the event handler did this before calling `start`, and only for a
`read` work: a `failed` or `reading` one is not reset, so a retry after a
crash stacks a second set of nodes, exactly as the Elixir did). Then:
status reading; every section; the spine; the weave; status read.

A model failure in the spine does not void the read: the beats are stored and
useful, so the work ends `read` with `spine unavailable: <reason>`. Anything
else that stops the body (a database error) ends it `failed`, with the last
database error, cut to 255 characters by `worksSetStatus`.

    export let analysisStart(db: Db, llm: LlmClient, work: Work): AnalysisResult throws Bubble {
      analysisStartTracked(db, llm, work, null)
    }

The same, reporting `n/total` sections to the `runs` row `runKey` as it goes
(through `runsProgress`; a key with no running row is ignored).

    export let analysisStartTracked(db: Db, llm: LlmClient, work: Work, runKey: String?): AnalysisResult throws Bubble {
      if (work.status == "read") { worksResetRead(db, work.id); }
      let outcome: AnalysisResult? = do { analysisRun(db, llm, work, runKey) } orelse null;
      if (outcome != null) { return outcome; }
      let why = db.lastError;
      let fresh = worksGetById(db, work.id);
      let base = if (fresh != null) { fresh } else { work };
      let detail = if (why == "") { "the read stopped" } else { "the read stopped: ${why}" };
      let failed = worksSetStatus(db, base, "failed", detail);
      analysisBump(db, work.id);
      new AnalysisResult(failed, "failed", failed.statusDetail, 0, 0, 0, 0)
    }

    let analysisProgress(db: Db, runKey: String?, done: Int, total: Int, stage: String): Void {
      if (runKey != null) {
        let ok = do {
          runsProgress(db, runKey, runsCounts(done, total), stage);
          true
        } orelse false;
        if (!ok) { console.log("marginalia: no progress for ${runKey}"); }
      }
    }

    let analysisRun(db: Db, llm: LlmClient, start: Work, runKey: String?): AnalysisResult throws Bubble {
      let work = worksSetStatus(db, start, "reading", null);
      analysisBump(db, work.id);
      let sections = worksListSections(db, work.id);
      analysisBump(db, work.id);
      var read = 0;
      var failed = 0;
      var beats = 0;
      var i = 0;
      analysisProgress(db, runKey, 0, sections.length, "reading sections");
      while (i < sections.length) {
        let r = analysisReadSection(db, llm, work, sections[i]);
        if (r.status == "read") { read += 1; } else { failed += 1; }
        beats += r.beats;
        i += 1;
        analysisProgress(db, runKey, i, sections.length, "reading sections");
      }
      analysisBump(db, work.id);
      analysisBump(db, work.id);
      analysisProgress(db, runKey, sections.length, sections.length, "the spine");
      let spine = analysisSynthesize(db, llm, work);
      if (spine.ok) {
        analysisProgress(db, runKey, sections.length, sections.length, "the weave");
        analysisBump(db, work.id);
        let woven = weaveRun(db, llm, work);
        var edges = 0;
        if (woven.ok) {
          edges = woven.edges;
          analysisBump(db, work.id);
          console.log("marginalia: wove ${edges.toString()} cross-section edges for work ${work.id.toString()}");
          analysisBump(db, work.id);
        } else {
          console.log("marginalia: weave failed for work ${work.id.toString()}: ${anOrEmpty(woven.error)}");
          analysisBump(db, work.id);
        }
        let done = worksSetStatus(db, work, "read", null);
        analysisBump(db, work.id);
        new AnalysisResult(done, "read", null, read, failed, beats, edges)
      } else {
        let detail = "spine unavailable: ${anOrEmpty(spine.error)}";
        let done = worksSetStatus(db, work, "read", detail);
        analysisBump(db, work.id);
        new AnalysisResult(done, "read", done.statusDetail, read, failed, beats, 0)
      }
    }

## The Prompts view

    export let analysisPasses(): List<AnalysisPass> {
      [
        new AnalysisPass(
          "beats",
          "Pass 1 \u{2014} read each section",
          analysisFastModel(),
          "once per section, 3 at a time",
          "beats, each anchored to a verbatim quote",
          analysisBeatsPrompt(),
        ),
        new AnalysisPass(
          "spine",
          "Pass 2 \u{2014} the whole draft",
          analysisDefaultModel(),
          "once, after every section is read",
          "first impression, spine, threads, open questions",
          analysisSpinePrompt(),
        ),
        weavePass(),
      ]
    }
