# Document

`Marginalia.Document`: the whole draft, read two ways at once.

A document is not the sum of its sections and it is not a single long
paragraph either, and asking one model call to produce both readings gets a
blend of the two that is neither. So there are two prongs, and they are given
different material on purpose.

**Composing, upward.** Built from the section summaries, never from the full
text, so the prompt does not grow with section length. It answers: what does
this document do, in what order, and what single thread runs through it.

**Decomposing, downward.** Given the shape of the document rather than a
reading of it: title, intent, the section titles, and what each section does.
It answers a different question: what rules is this working under. It is
deliberately NOT handed the other prong's throughline; that would anchor the
second reading to the first, and two prongs that agree because one was told
what the other said are one prong.

Every ordinal either prong cites is checked against the sections that actually
exist. A guideline attributed to section 14 of a 12-section draft is worse than
no guideline: it is a claim a reader cannot check without going and looking.

The Elixir ran the section summaries six at a time and the two prongs in two
tasks. There is no second thread here: the summaries run one after another in
section order, then the composition, then the guidelines. The calls are the
same calls.

    let { Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { FieldError } = import("core/src");
    let {
      Work, Section, DocumentSummary, DocumentSummaryParams, WorkParams, WorksResult,
      worksListSections, worksGetDocumentSummary, worksSaveDocumentSummary, worksCreateWork,
      worksCondensationOf,
    } = import("works/src");
    let { LlmClient, LlmTool } = import("llm/src");
    let { JsonObject, JsonArray, JsonSyntaxTree } = import("std/json");
    let { versionsBump, versionsWorkTopic } = import("runs/src");
    let { sysSha256, sysJoin } = import("sys/src");

## The tools

    export let documentComposeTool(): LlmTool {
      new LlmTool(
        documentComposeToolName(), documentComposeToolDescription(), documentComposeToolParameters(),
      )
    }

    export let documentGuideTool(): LlmTool {
      new LlmTool(
        documentGuideToolName(), documentGuideToolDescription(), documentGuideToolParameters(),
      )
    }

## Checking

Drop every citation to a section that does not exist, and say so. `comp` is
the composition's reply, `guide` the guidelines'; either may be an empty
object. Movements, guidelines and tensions are lists of objects; each object
is kept with its `sections` replaced by the ones that exist (an item whose
every citation is invalid is kept with an empty list), and a reason is added
for each item that lost some:
`movement: cites [14], which are not sections here`, in the order movements,
guidelines, tensions.

Public because it is pure and because it is the part that can be wrong
invisibly.

    export let documentValidate(
      comp: JsonSyntaxTree?, guide: JsonSyntaxTree?, sections: List<Section>,
    ): DocumentChecked {
      let ordinals = new ListBuilder<Int>();
      for (let s of sections) { ordinals.add(s.ordinal); }
      let known = ordinals.toList();
      let dropped = new ListBuilder<String>();
      let movements = documentCheckList(readingElements(comp, "movements"), known, "movement", dropped);
      let rules = documentCheckList(readingElements(guide, "guidelines"), known, "guideline", dropped);
      let tensions = documentCheckList(readingElements(guide, "tensions"), known, "tension", dropped);
      new DocumentChecked(
        readingTrimmed(readingProp(comp, "summary")),
        readingTrimmed(readingProp(comp, "throughline")),
        movements, rules, tensions, dropped.toList(),
      )
    }

    let documentCheckList(
      items: List<JsonSyntaxTree>, ordinals: List<Int>, label: String, dropped: ListBuilder<String>,
    ): List<JsonObject> {
      let out = new ListBuilder<JsonObject>();
      for (let item of items) {
        if (item is JsonObject) {
          let good = new ListBuilder<JsonSyntaxTree>();
          let missing = new ListBuilder<JsonSyntaxTree>();
          for (let cited of readingElements(item, "sections")) {
            let n = readingJsonInt(cited);
            if (n != null && documentKnows(ordinals, n)) {
              good.add(cited);
            } else {
              missing.add(cited);
            }
          }
          if (!missing.isEmpty) {
            dropped.add("${label}: cites ${readingInspectList(missing.toList())}, which are not sections here");
          }
          out.add(documentWithSections(item, good.toList()));
        }
      }
      out.toList()
    }

    let documentKnows(ordinals: List<Int>, n: Int): Boolean {
      for (let o of ordinals) {
        if (o == n) { return true; }
      }
      false
    }

The object with its `sections` replaced, every other key as it was, in order.

    let documentWithSections(item: JsonObject, good: List<JsonSyntaxTree>): JsonObject {
      let props = new MapBuilder<String, List<JsonSyntaxTree>>();
      item.properties.forEach { (k: String, vs: List<JsonSyntaxTree>): Void =>
        if (k == "sections") {
          props.set(k, [new JsonArray(good)]);
        } else {
          props.set(k, vs);
        }
      };
      if (!item.properties.has("sections")) {
        props.set("sections", [new JsonArray(good)]);
      }
      new JsonObject(props.toMap())
    }

## Staleness

What a document summary is current against: each section's ordinal, the hash
of its text, and a hash of the summary written for it, joined and hashed. The
text covers an edit; the summary covers a re-run that reworded it.

The Elixir hashed the summary with `:erlang.phash2/1`, Erlang's portable term
hash, which has no counterpart here. This takes `sysSha256` of the summary
instead (a missing summary hashes as itself, `nil`), so every fingerprint
stored before the port reads as stale once, which is harmless.

    export let documentFingerprint(sections: List<Section>): String {
      let parts = sections.map { (s: Section): String =>
        let summary = s.summary;
        let hashed = if (summary != null) { sysSha256("s:${summary}") } else { "nil" };
        "${s.ordinal.toString()}:${summaryFingerprint(s)}:${hashed}"
      };
      sysSha256(sysJoin(parts, "|"))
    }

The stored document summary, or null.

    export let documentGet(db: Db, workId: Int): DocumentSummary? throws Bubble {
      worksGetDocumentSummary(db, workId)
    }

Whether the document summary still matches the sections underneath it.

    export let documentCurrent(db: Db, work: Work): Boolean throws Bubble {
      let doc = worksGetDocumentSummary(db, work.id);
      if (doc != null) {
        let stored = doc.fingerprint;
        if (stored != null) {
          stored == documentFingerprint(worksListSections(db, work.id))
        } else {
          false
        }
      } else {
        false
      }
    }

## The two prongs

The sections that have a summary. The Elixir kept any non-nil one, an empty
string included.

    export let documentSummarised(sections: List<Section>): List<Section> {
      let out = new ListBuilder<Section>();
      for (let s of sections) {
        if (s.summary != null) { out.add(s); }
      }
      out.toList()
    }

Composing: one entry per summarised section, `N. Title` and the summary, with
`(sets up: ...)` when the section has one, joined by a blank line.

    export let documentComposeWith(
      llm: LlmClient, work: Work, summarised: List<Section>,
    ): ReadingToolReply {
      let entries = summarised.map { (s: Section): String =>
        let summary = s.summary;
        let body = if (summary != null) { summary } else { "" };
        let setsUp = s.summarySetsUp;
        let tail = if (setsUp != null) { "\n(sets up: ${setsUp})" } else { "" };
        "${s.ordinal.toString()}. ${s.title}\n${body}${tail}"
      };
      let user = promptsComposeUser(work.title, work.intent, summarised.length, sysJoin(entries, "\n\n"));
      readingCallTool(
        llm, documentComposeTool(), null, "high", 0.3, 3000, documentComposePrompt(), user,
      )
    }

Decomposing: every section's title, then what each summarised section does.

    export let documentGuidelinesWith(
      llm: LlmClient, work: Work, sections: List<Section>, summarised: List<Section>,
    ): ReadingToolReply {
      let titles = sections.map { (s: Section): String => "${s.ordinal.toString()}. ${s.title}" };
      let what = summarised.map { (s: Section): String =>
        let summary = s.summary;
        let line = if (summary != null) { summary } else { "" };
        "${s.ordinal.toString()}. ${line}"
      };
      let user = promptsGuideUser(work.title, work.intent, sysJoin(titles, "\n"), sysJoin(what, "\n"));
      readingCallTool(
        llm, documentGuideTool(), null, "high", 0.3, 2500, documentGuidePrompt(), user,
      )
    }

The composition of the draft as it stands: the summaries it has.

    export let documentCompose(db: Db, llm: LlmClient, work: Work): ReadingToolReply throws Bubble {
      documentComposeWith(llm, work, documentSummarised(worksListSections(db, work.id)))
    }

The guidelines of the draft as it stands.

    export let documentGuidelines(db: Db, llm: LlmClient, work: Work): ReadingToolReply throws Bubble {
      let sections = worksListSections(db, work.id);
      documentGuidelinesWith(llm, work, sections, documentSummarised(sections))
    }

## Running both

Summarise the whole document. Fans out the section summaries that are missing
or stale (`force` re-summarises every section), then composes, then reads the
rules. Both prongs landing is stored whole; the composition without the
guidelines is stored as half, with `the guidelines pass failed: ...` among the
`dropped`; no composition is the error. Refused before any call for a work
with no sections (`no_sections`) or none summarised (`no_summaries`).

    export let documentRun(
      db: Db, llm: LlmClient, work: Work, force: Boolean,
    ): DocumentResult throws Bubble {
      let first = worksListSections(db, work.id);
      if (first.isEmpty) { return new DocumentResult(null, "no_sections", null); }
      for (let s of first) {
        if (force || !summaryCurrent(s)) {
          summaryAsk(db, llm, work, s);
        }
      }
      let sections = worksListSections(db, work.id);
      let summarised = documentSummarised(sections);
      if (summarised.isEmpty) { return new DocumentResult(null, "no_summaries", null); }
      let comp = documentComposeWith(llm, work, summarised);
      let guide = documentGuidelinesWith(llm, work, sections, summarised);
      let composed = comp.ok;
      if (composed == null) {
        return new DocumentResult(null, readingOrUnknown(comp.error), comp.detail);
      }
      let guided = guide.ok;
      let stored = if (guided != null) {
        let checked = documentValidate(composed, guided, sections);
        documentUpsert(db, work, sections, checked, [])
      } else {
        let checked = documentValidate(composed, null, sections);
        let reason = "the guidelines pass failed: ${documentReason(guide.error, guide.detail)}";
        documentUpsert(db, work, sections, checked, [reason])
      };
      versionsBump(db, versionsWorkTopic(work.id));
      new DocumentResult(stored, null, null)
    }

    let readingOrUnknown(e: String?): String { if (e != null) { e } else { "unknown" } }

An error as Elixir would have inspected it, near enough to read: the atom's
name, or for an HTTP failure its status and body.

    let documentReason(kind: String?, detail: String?): String {
      let k = readingOrUnknown(kind);
      let d = if (detail != null) { detail } else { "" };
      if (k == "length") {
        ":truncated"
      } else if (k == "no_key") {
        ":no_api_key"
      } else if (k == "http") {
        "{:http, ${d}}"
      } else {
        ":${k}"
      }
    }

The row, inserted or updated: the checked fields, the fingerprint of the
sections as fetched after the fan-out, and what was dropped (the checker's
reasons followed by `extra`).

    let documentUpsert(
      db: Db, work: Work, sections: List<Section>, checked: DocumentChecked, extra: List<String>,
    ): DocumentSummary throws Bubble {
      let p = new DocumentSummaryParams(work.id);
      p.summary = checked.summary;
      p.throughline = checked.throughline;
      p.movementsJson = readingItemsText(checked.movements);
      p.guidelinesJson = readingItemsText(checked.guidelines);
      p.tensionsJson = readingItemsText(checked.tensions);
      p.fingerprint = documentFingerprint(sections);
      let all = new ListBuilder<String>();
      all.addAll(checked.dropped);
      all.addAll(extra);
      p.dropped = all.toList();
      worksSaveDocumentSummary(db, p)
    }

## The summaries as a draft

Turn what has been summarised into a draft of its own: a condensed version of
the draft, in order, with what the document does at the top and the rules it
works under at the end. Each section summary becomes a `##` heading, which the
segmenter divides on, so the heading becomes the section's title and is gone
from the body. Not filed into any folder: a condensation sitting in the folder
it condenses becomes document N+1 of the thing it summarises.

`error` is `nothing_summarised` when no section has a summary (an empty one
does not count), and nothing is created.

    export let documentToDraft(
      db: Db, scope: Scope, work: Work,
    ): DocumentDraftResult throws Bubble {
      let sections = worksListSections(db, work.id);
      let summarised = new ListBuilder<Section>();
      for (let s of sections) {
        let text = s.summary;
        if (text != null) {
          if (!text.isEmpty) { summarised.add(s); }
        }
      }
      let used = summarised.toList();
      if (used.isEmpty) {
        return new DocumentDraftResult(null, "nothing_summarised", [], null);
      }
      let doc = worksGetDocumentSummary(db, work.id);
      let params = new WorkParams(
        "${work.title} — in summary",
        documentDraftBody(work, doc, used),
      );
      params.derivedFromId = work.id;
      params.intent = "A condensation of ${work.title}: ${used.length.toString()} of its ${sections.length.toString()} sections, in order. It is meant to read as an argument in its own right, so the test of any part is whether it stands without the section it came from.";
      let r = worksCreateWork(db, scope, params);
      new DocumentDraftResult(r.ok, r.error, r.errors, r.message)
    }

The draft already made from this one, if any, otherwise a new one. Asking
twice does not make a second condensation.

    export let documentCondensation(
      db: Db, scope: Scope, work: Work,
    ): DocumentDraftResult throws Bubble {
      let existing = worksCondensationOf(db, work.id);
      if (existing != null) {
        new DocumentDraftResult(existing, null, [], null)
      } else {
        documentToDraft(db, scope, work)
      }
    }

The body: the opening (the document summary and its throughline, or a plain
line), one part per summarised section, and the rules the document works
under, joined by blank lines and trimmed.

    export let documentDraftBody(
      work: Work, doc: DocumentSummary?, summarised: List<Section>,
    ): String {
      let parts = new ListBuilder<String>();
      parts.add(documentOpening(work, doc));
      for (let s of summarised) {
        let lines = new ListBuilder<String>();
        lines.add("## ${s.ordinal.toString()}. ${s.title}");
        lines.add("");
        let text = s.summary;
        lines.add(if (text != null) { text } else { "" });
        if (!s.summaryCovers.isEmpty) {
          lines.add("\nIt deals with: ${sysJoin(s.summaryCovers, ", ")}.");
        }
        let setsUp = s.summarySetsUp;
        if (setsUp != null) {
          if (!setsUp.isEmpty) { lines.add("\nIt leaves in place: ${setsUp}"); }
        }
        parts.add(sysJoin(lines.toList(), "\n"));
      }
      let rules = documentRules(doc);
      if (rules != null) { parts.add(rules); }
      readingTrim(sysJoin(parts.toList(), "\n\n"))
    }

    let documentOpening(work: Work, doc: DocumentSummary?): String {
      if (doc != null) {
        let summary = doc.summary;
        if (summary != null) {
          if (!summary.isEmpty) {
            let pieces = new ListBuilder<String>();
            pieces.add(summary);
            let through = doc.throughline;
            if (through != null) {
              if (!through.isEmpty) { pieces.add(through); }
            }
            return sysJoin(pieces.toList(), "\n\n");
          }
        }
      }
      "A condensation of ${work.title}, section by section."
    }

    let documentRules(doc: DocumentSummary?): String? {
      if (doc != null) {
        if (!doc.guidelines.isEmpty) {
          let lines = doc.guidelines.map { (rule: JsonSyntaxTree): String =>
            let g = readingStr(rule, "guideline");
            let b = readingStr(rule, "because");
            let guideline = if (g != null) { g } else { "" };
            let because = if (b != null) { b } else { "" };
            "${guideline} ${because}"
          };
          "## What it is working under\n\n${sysJoin(lines, "\n\n")}"
        } else {
          null
        }
      } else {
        null
      }
    }
