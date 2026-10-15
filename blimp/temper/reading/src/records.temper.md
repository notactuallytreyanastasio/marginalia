# The records

The shapes the reading contexts hand back. The Elixir returned maps and
tagged tuples; here a map is a class with the same field names in camelCase,
and `{:ok, x} | {:error, reason}` is a class with `ok` and an `error` string
(the atom's name, `"empty"` for `:empty`) plus a `detail` where the reason
carried more than an atom.

    let { Section, DocumentSummary, Work } = import("works/src");
    let { FieldError } = import("core/src");
    let { JsonObject, JsonSyntaxTree } = import("std/json");

## The reading page

A margin note: a beat, or a connection shown on the beat it starts from. The
Elixir note's `id` was a tuple (`{:beat, 12}`); `key` is its string form
(`"beat:12"`, `"conn:12:13:tension"`), which is also what `focus` takes.

    export class ReadingNote(
      public key: String,
      public sectionId: Int?,
      public kind: String,
      public quote: String?,
      public title: String,
      public body: String?,
      public stale: Boolean,
    ) {}

One block of a section: the paragraph, the span of it to highlight (the first
quote found in it), the notes anchored inside it, and its ref `s<ordinal>p<index>`
(zero-based, headings and code included).

    export class ReadingBlock(
      public text: String,
      public mark: String?,
      public notes: List<ReadingNote>,
      public ref: String,
    ) {}

    export class ReadingSection(
      public section: Section,
      public blocks: List<ReadingBlock>,
      public unplaced: List<ReadingNote>,
    ) {}

`only` is `"beats"`, `"connections"` or `"tensions"` (anything else shows
both); `section` keeps one section by ordinal; `notes`, when given, replaces
the work's own notes (the linked view builds them out of the edges between two
drafts).

    export class ReadingOptions(
      public only: String?,
      public section: Int?,
      public notes: List<ReadingNote>?,
    ) {}

    export let readingNoOptions(): ReadingOptions { new ReadingOptions(null, null, null) }

A rewrite shown in place of the paragraph it would replace.

    export class ReadingPreview(public original: String, public text: String) {}

What `focus` answers: the note, and the sections the chat needs in full.

    export class ReadingFocus(
      public kind: String,
      public title: String,
      public body: String?,
      public quote: String?,
      public sections: List<Section>,
    ) {}

A row of the rail: a run of blocks with no note, closed by the block that has
them.

    export class ReadingRow(public blocks: List<ReadingBlock>, public notes: List<ReadingNote>) {}

An entry of the outline.

    export class ReadingOutline(
      public id: String,
      public level: Int,
      public title: String,
      public words: Int?,
    ) {}

A selection quoted back as a citation.

    export class ReadingCite(public text: String, public section: String, public ordinal: Int) {}

## Selection

Where a selection lives: the section, the block that holds it (the whole
section body when it ran across blocks), and the exact source text.

    export class SelectionHit(
      public section: Section,
      public block: String,
      public span: String,
    ) {}

## The model's answer

A tool call, decoded. Exactly one of `ok` (the arguments object) or `error`
is set; `error` is the `LlmError` kind (`length` is the truncated reply),
`no_tool_call` for a reply that made no call, `invalid_json` for arguments
that are not an object.

    export class ReadingToolReply(
      public ok: JsonObject?,
      public error: String?,
      public detail: String?,
    ) {}

## Summary

`ok` is the section as stored. `error` is `"empty"` (nothing to summarise),
`"no_summary"` (the model reported an empty summary), or the failure of the
call. `dropped` is what validation discarded, which is also stored on the row.

    export class SummaryResult(
      public ok: Section?,
      public error: String?,
      public detail: String?,
      public dropped: List<String>,
    ) {}

    export class SummaryChecked(
      public summary: String,
      public covers: List<String>,
      public follows: List<Int>,
      public setsUp: String?,
      public dropped: List<String>,
    ) {}

## Rewrite

    export class RewriteCandidate(
      public text: String,
      public move: String?,
      public cost: String?,
    ) {}

`error` is `"span_too_long"` (`words` and `maxWords` say how long),
`"not_in_draft"`, `"no_candidates"`, or the failure of the call (`length`,
`no_tool_call`, `invalid_json`, `rate_limited`, `http`, `no_key`, ...).
A reply without a `rewrites` list is `"no_candidates"`, never the raw reply.

    export class RewriteResult(
      public reading: String?,
      public original: String,
      public section: Section?,
      public candidates: List<RewriteCandidate>,
      public spansBlocks: Boolean,
      public covers: List<String>,
      public error: String?,
      public detail: String?,
      public words: Int,
      public maxWords: Int,
    ) {}

`error` is `"empty"` (the new text is blank), `"moved"` (the old text is no
longer in the section) or null.

    export class RewriteApplied(
      public section: Section,
      public superseded: Int,
      public error: String?,
    ) {}

## Document

    export class DocumentChecked(
      public summary: String,
      public throughline: String,
      public movements: List<JsonObject>,
      public guidelines: List<JsonObject>,
      public tensions: List<JsonObject>,
      public dropped: List<String>,
    ) {}

`ok` is the stored row. `error` is `"no_sections"`, `"no_summaries"`, or the
failure of the composing call.

    export class DocumentResult(
      public ok: DocumentSummary?,
      public error: String?,
      public detail: String?,
    ) {}

`ok` is the new draft; `error` is `"nothing_summarised"`, `"invalid"` (the
create was refused; `errors` are the changeset's) or a create failure.

    export class DocumentDraftResult(
      public ok: Work?,
      public error: String?,
      public errors: List<FieldError>,
      public message: String?,
    ) {}
