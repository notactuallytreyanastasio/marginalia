# Results and pass descriptions

The Elixir returned tuples; here each outcome is a small class. Exactly one
story per class, and no field is nullable unless the story can be told
without it.

    let { Work } = import("works/src");

## The Read

What `Analysis.run` leaves behind. `status` is the work's final status
(`read`, or `failed` when something other than a model error stopped it);
`detail` its `status_detail` (`spine unavailable: ...` when the read is
degraded, null when whole). The counts are what the run did, not what the
database now holds.

    export class AnalysisResult(
      public work: Work,
      public status: String,
      public detail: String?,
      public sectionsRead: Int,
      public sectionsFailed: Int,
      public beats: Int,
      public edges: Int,
    ) {}

What one section's beats pass did. `status` is `read` or `failed`; `beats` is
how many were stored; `dropped` how many the anchor refused; `detail` the
reason when failed (the Elixir logged `inspect(reason)`).

    export class AnalysisSectionResult(
      public status: String,
      public beats: Int,
      public dropped: Int,
      public detail: String?,
    ) {}

The spine pass: `ok`, or the reason (`:no_beats`, or the model's failure as
the Elixir would `inspect` it).

    export class AnalysisStep(public ok: Boolean, public error: String?) {}

`Weave.run`: `ok` with the number of edges stored, or `error` (`:no_edges`
when the reply had no edge list, or the model's failure).

    export class WeaveResult(public ok: Boolean, public edges: Int, public error: String?) {}

The decision graph build: the number of narratives built, or the reason Pass A
failed. `nodes` and `events` are what the work holds when it ends.

    export class DecisionGraphResult(
      public ok: Boolean,
      public narratives: Int,
      public error: String?,
      public nodes: Int,
      public events: Int,
    ) {}

## The Prompts view

`passes/0`: the model, the cadence and the prompt of each pass.

    export class AnalysisPass(
      public id: String,
      public name: String,
      public model: String,
      public runs: String,
      public produces: String,
      public prompt: String,
    ) {}
