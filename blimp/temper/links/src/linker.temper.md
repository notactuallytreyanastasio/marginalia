# The linker: the pass that reads a pair

`Marginalia.Analysis.Linker`. `Weave` asks what leads to what inside one
draft. This asks the same question across the boundary between two, using the
same relations, so the answer reads as one graph rather than two graphs and a
legend.

What makes the question answerable at all is that both drafts have already
been read. The model is not handed 8,000 words twice and asked to find
correspondences; it is handed two catalogues of nodes, each with an id, a
type, a section and the sentence it was anchored to, and asked which of those
point at each other. The ids give the answer something to be checked against,
and `linksStoreEdges` does the checking: an invented id, an id from a third
draft, or two ids from one draft (an internal edge passed off as a
relationship between the documents) is thrown away in code.

The Elixir ran this in a detached task (`Linker.start`). Here `linkerRun` is
the body of that task as an ordinary function, to be executed by the `runs`
library in a forked job, and `linkerRunPair` loads the link and runs it.
Progress that was a PubSub broadcast on `"link:<id>"` is
`versionsBump(db, "link:<id>")` at each point the Elixir broadcast.

    let { Db } = import("db/src");
    let { LlmClient, LlmCall, LlmMessage, LlmError, Result, llmErrorText } = import("llm/src");
    let { Work, GraphNode, worksListSections, worksNodes, Section } = import("works/src");
    let { versionsBump, versionsLinkTopic } = import("runs/src");
    let { JsonObject, JsonArray, JsonString, JsonSyntaxTree } = import("std/json");
    let { sysGraphemeTake, sysJoin } = import("sys/src");

The metadata `passes/0` gave the prompts page.

    export let linkerPasses(): List<LinksPass> {
      [new LinksPass(
        "link",
        "Linking — how two graphs relate",
        linksDefaultModel(),
        "once per pair of manuscripts",
        "edges between the nodes of two drafts, plus a summary of the relationship",
        linkerPrompt(),
      )]
    }

## What the model is given

Both maps, in one message. The stable part, the prompt, is the system message
so the provider's prefix cache covers it across every pair.

    let linkerIntent(w: Work): String {
      let i = w.intent;
      if (i != null) {
        if (i != "") { return "Intended effect on a reader: ${i}\n"; }
      }
      ""
    }

    let linkerLabel(kind: String): String {
      if (kind == "beat") {
        "Beats, in document order"
      } else if (kind == "spine") {
        "Spine"
      } else if (kind == "thread") {
        "Threads"
      } else {
        "Open questions"
      }
    }

`  [12] (§2) title — body150\n      "quote180"`

    let linkerLine(n: GraphNode, ordinals: Map<Int, Int>): String {
      let parts = new ListBuilder<String>();
      parts.add("  [${n.id.toString()}]");
      let sectionId = n.sectionId;
      if (sectionId != null) {
        if (ordinals.has(sectionId)) {
          parts.add(" (§${ordinals.getOr(sectionId, 0).toString()})");
        }
      }
      parts.add(" ${n.title}");
      let body = n.body;
      if (body != null) {
        if (body != "") { parts.add(" — ${sysGraphemeTake(body, 150)}"); }
      }
      let quote = n.quote;
      if (quote != null) {
        if (quote != "") { parts.add("\n      \"${linksOneLine(quote, 180)}\""); }
      }
      sysJoin(parts.toList(), "")
    }

For each of beat, spine, thread, question with at least one node: a blank line,
the heading, and the lines. The four chunks are joined by a newline, empty ones
included.

    let linkerSide(db: Db, work: Work, nodes: List<GraphNode>): String throws Bubble {
      let ordinals = new MapBuilder<Int, Int>();
      for (let s of worksListSections(db, work.id)) { ordinals.set(s.id, s.ordinal); }
      let ordinalMap = ordinals.toMap();
      let chunks = new ListBuilder<String>();
      for (let kind of ["beat", "spine", "thread", "question"]) {
        let lines = new ListBuilder<String>();
        for (let n of nodes) {
          if (n.nodeType == kind) { lines.add(linkerLine(n, ordinalMap)); }
        }
        if (lines.length == 0) {
          chunks.add("");
        } else {
          chunks.add("\n## ${linkerLabel(kind)}\n${sysJoin(lines.toList(), "\n")}");
        }
      }
      sysJoin(chunks.toList(), "\n")
    }

    export let linkerCatalogue(
      db: Db, a: Work, b: Work, aNodes: List<GraphNode>, bNodes: List<GraphNode>,
    ): String throws Bubble {
      sysJoin([
        "# MANUSCRIPT A: ${a.title}",
        "${linkerIntent(a)}${linkerSide(db, a, aNodes)}",
        "",
        "# MANUSCRIPT B: ${b.title}",
        "${linkerIntent(b)}${linkerSide(db, b, bNodes)}",
        "",
      ], "\n")
    }

## Asking

One call, `effort: high, temperature: 0.4, max_tokens: 24000`, JSON mode. The
only call that decides what the relationship is. Asking it to sweep both
documents instead of picking highlights tripled the answer, and 8k cut it off
mid-array.

    let linkerAsk(
      llm: LlmClient, system: String, catalogue: String,
    ): Result<JsonObject, LlmError> {
      llm.json(new LlmCall(
        [new LlmMessage("system", system), new LlmMessage("user", catalogue)],
        null, "high", 24000, 0.4, true, [], null, 0,
      ))
    }

Two large maps can produce more edges than the budget holds, and a truncated
answer is not a short answer: it is a cut-off JSON array, which parses as
nothing and stores nothing. Raising the ceiling only moves the wall. The fix
is to ask for less of the thing that overflowed, once, by appending the
addendum to the system prompt. The client reports a `finish_reason` of
`length` as an error of kind `length`.

    let linkerAskWithRetry(llm: LlmClient, catalogue: String): Result<JsonObject, LlmError> {
      let first = linkerAsk(llm, linkerPrompt(), catalogue);
      let e = first.err;
      if (e != null) {
        if (e.kind == "length") {
          console.log("marginalia: link overflowed, asking again for the strongest only");
          return linkerAsk(llm, "${linkerPrompt()}${linkerCrowded()}", catalogue);
        }
      }
      first
    }

## Running

`ok` with how many edges were kept and dropped, or not `ok` with the `error`
the link was left with. `link` is the link as it stands afterwards.

    export class LinkerResult(
      public ok: Boolean,
      public kept: Int,
      public dropped: Int,
      public error: String?,
      public link: Link?,
    ) {}

A failure leaves the link `failed` with the reason as its error (cut at 255
characters by `linksSetStatus`, where Postgres refused a longer one and the
status update raised inside the task), and wakes whoever is watching.

    let linkerFail(db: Db, link: Link, reason: String): LinkerResult throws Bubble {
      let set = linksSetStatus(db, link, "failed", linksAttrsError(reason));
      console.log("marginalia: link ${link.id.toString()} failed: ${reason}");
      versionsBump(db, versionsLinkTopic(link.id));
      new LinkerResult(false, 0, 0, reason, set.ok)
    }

    let linkerBump(db: Db, link: Link): Void throws Bubble {
      versionsBump(db, versionsLinkTopic(link.id));
    }

Relate the two manuscripts of `link`. Re-running replaces the previous edges
rather than adding to them: the second answer to the same question is a
correction, not more data.

The steps, and the broadcast the Elixir made at each: status `linking` with the
error cleared (`start`); a pair with no nodes on either side fails with
`:not_read`; otherwise `reading` and `asking`, the call, then `checking`, the
previous edges cleared and the new ones stored, status `linked` with the
summary (`done`). A reply without an `edges` list fails with `:no_edges`; a
client error fails with its text.

    export let linkerRun(db: Db, llm: LlmClient, link: Link): LinkerResult throws Bubble {
      let lw = linksWorks(db, link);
      let a = lw.aWork;
      let b = lw.bWork;
      let started = linksSetStatus(db, link, "linking", linksAttrsError(null));
      let current = linksLinkOrBubble(started.ok);
      linkerBump(db, current);
      let aNodes = worksNodes(db, a.id);
      let bNodes = worksNodes(db, b.id);
      if (aNodes.length == 0 || bNodes.length == 0) {
        return linkerFail(db, current, ":not_read");
      }
      linkerBump(db, current);
      linkerBump(db, current);
      let catalogue = linkerCatalogue(db, a, b, aNodes, bNodes);
      let answered = linkerAskWithRetry(llm, catalogue);
      let out = answered.ok;
      if (out != null) {
        let edges = out.propertyValueOrNull("edges");
        if (edges is JsonArray) {
          linkerBump(db, current);
          linksClearEdges(db, current);
          let stored = linksStoreEdges(db, current, edges.elements, linkerTypes());
          console.log("marginalia: linked ${a.id.toString()}↔${b.id.toString()} — ${stored.kept.toString()} edges kept, ${stored.dropped.toString()} dropped");
          let summary = out.propertyValueOrNull("summary");
          let text = if (summary is JsonString) { summary.content } else { null };
          let done = linksSetStatus(db, current, "linked", linksAttrsBoth(text, null));
          linkerBump(db, current);
          return new LinkerResult(true, stored.kept, stored.dropped, null, done.ok);
        }
        return linkerFail(db, current, ":no_edges");
      }
      let e = answered.err;
      linkerFail(db, current, if (e != null) { llmErrorText(e) } else { ":no_reply" })
    }

The wrapper a job runs: load the link by id and read it. A link that is not
there is a failure with nothing to write to.

    export let linkerRunPair(db: Db, llm: LlmClient, linkId: Int): LinkerResult throws Bubble {
      let link = linksGet(db, linkId);
      if (link != null) {
        linkerRun(db, llm, link)
      } else {
        new LinkerResult(false, 0, 0, ":no_link", null)
      }
    }
