# The page's state

`WorkLive.Show` kept about sixty assigns on a socket. There is no socket
here: every request builds the same state again, from three places.

* **The database**: the work, its sections and nodes, the revisions, the
  conversations, the links, the document summary, the counts. Read on every
  request, as `load_map/1` did on every message.
* **The runs table**: what is going on in the background (`work:<id>:read`,
  `…:graph`, `…:rewrite`, `…:summarise:<n>`, `…:document`, `…:compare`). The
  Elixir page kept `graph_building`, `doc_running`, `summarising`, `comparing`
  and `rewriting` as flags set by an event and cleared by a message. Here they
  are the question "is the run for that key running?", asked each time, so a
  page that is opened mid-read, or reloaded, shows the truth and not a reset.
* **The session's ui state**: the few assigns that exist only in the page
  (the filter, the open thread, the rewrite panel and what is half-typed
  into it, the paragraph being edited, the drawer's held passage, the
  walkthrough). One JSON object under `show:<slug>` (`ui.temper.md`).

`ShowState` is all of them, with the names of the assigns in camel case. The
fields marked **ui** are written back after an event (`showSaveUi`); the rest
are recomputed. An event handler changes fields of the state it was given and
the dispatcher saves the ui ones, then loads the page again from the
database, so what is rendered is always what is stored.

    let { Work, Section, GraphNode, GraphEvent, Revision, DocumentSummary, WorkCounts, EventStats } = import("works/src");
    let { User } = import("accounts/src");
    let { Conversation, ChatTurn, ChatSummary, ChatThread, ChatQuota, ChatMode } = import("chat/src");
    let { ReadingSection, ReadingFocus, ReadingCite, ReadingPreview, ReadingCache, RewriteCandidate } = import("reading/src");
    let { LinkWorks } = import("links/src");
    let { GraphStats, AnalysisPass } = import("analysis/src");
    let { TourCard, WalkStep } = import("cases/src");
    let { Row } = import("core/src");
    let { Run } = import("runs/src");

## Small records

`add_context`'s passages are `ReadingCite` (text, section title, ordinal), the
drawer's holding card is `ReadingFocus`, a candidate shown inline is
`ReadingPreview`, and a rewrite's candidates are `RewriteCandidate`. The ones
below are the page's own.

What the writer last accepted, shown in place of the paragraph until it is
dismissed.

    export class ShowApplied(public before: String, public after: String) {}

The candidates for a selected span. `sectionOrdinal` is the section the span
was found in (the Elixir kept the section itself; applying it looks it up
fresh by ordinal); `spansBlocks` is true when it crosses paragraphs; `covers`
the refs of every paragraph it touches.

    export class ShowRewrite(
      public reading: String?,
      public original: String,
      public sectionOrdinal: Int?,
      public candidates: List<RewriteCandidate>,
      public spansBlocks: Boolean,
      public covers: List<String>,
    ) {}

`infer_stages/1`: each of `sections`, `spine` and `weave` is `waiting`,
`start`, `done` or `failed`.

    export class ShowStages(public sections: String, public spine: String, public weave: String) {}

    export class ShowDiffStat(public same: Int, public changed: Int, public added: Int, public removed: Int) {}

One backend the deploy has a key for: `LLM.choices/0`.

    export class ShowBackend(public name: String, public label: String, public model: String) {}

## What an event did

An event changes the state it was given, and answers with this: the flash to
show (`level` is `info` or `error`), a page to go to instead of re-rendering
(`push_patch` and `push_navigate` both become one), and the events for the
client hooks (`chat:clear`). `redirect` null means "render the page again".

    export class ShowOutcome(
      public flash: Pair<String, String>?,
      public redirect: String?,
      public events: List<Pair<String, String>>,
    ) {}

    export let showDone(): ShowOutcome { new ShowOutcome(null, null, []) }

    export let showFlashed(level: String, text: String): ShowOutcome {
      new ShowOutcome(new Pair(level, text), null, [])
    }

    export let showInfo(text: String): ShowOutcome { showFlashed("info", text) }

    export let showError(text: String): ShowOutcome { showFlashed("error", text) }

    export let showGoing(path: String): ShowOutcome { new ShowOutcome(null, path, []) }

    export let showGoingFlashed(path: String, level: String, text: String): ShowOutcome {
      new ShowOutcome(new Pair(level, text), path, [])
    }

## The state

    export class ShowState(
      public var work: Work,
      public user: User?,
      public view: String,
    ) {

Who is looking. `mine` is the owner of the draft; `owner` the account the
deploy belongs to; `admin` is assigned and never drawn.

      public var mine: Boolean = false;
      public var owner: Boolean = false;
      public var admin: Boolean = false;

The URL: `?chat=1` opens the drawer.

      public var chatOpen: Boolean = false;

The backend. `provider` is the owner's chosen one, or null for the deploy
default; `llmReady` is whether a key exists for it; `backends` those with a key.

      public var provider: String? = null;
      public var llmReady: Boolean = false;
      public var backends: List<ShowBackend> = [];

What `load_map` assigns: the sections, the nodes by type, the counts, the
revisions (newest first) and how many there are.

      public var sections: List<Section> = [];
      public var beats: List<GraphNode> = [];
      public var spine: List<GraphNode> = [];
      public var threads: List<GraphNode> = [];
      public var questions: List<GraphNode> = [];
      public var counts: WorkCounts = new WorkCounts(0, 0, 0, 0, 0, 0);
      public var revisions: List<Revision> = [];
      public var revisionCount: Int = 0;

The read view's page: `Reading.page`, null until the read view loads.

      public var page: List<ReadingSection>? = null;

**ui**: the note filter (`beats`, `connections`, `tensions`, or null for
everything).

      public var only: String? = null;

The chat drawer's own assigns, which `chat.temper.md` fills in. `conversation`
is the whole-draft conversation in use (its id is **ui**), `history` its last
messages, `mode`/`modes` the stance, `threadsList` the strip, `quota` the
questions left. **ui**: `focus` (what the chat is holding), `cited` (passages
carried into the next question), `loading` (a question is in flight).

      public var conversation: Conversation? = null;
      public var savedConversation: Int? = null;
      public var history: List<ChatTurn> = [];
      public var mode: String = "read";
      public var modes: List<ChatMode> = [];
      public var threadsList: List<ChatSummary> = [];
      public var quota: ChatQuota = new ChatQuota(true, 0);
      public var focus: ReadingFocus? = null;
      public var cited: List<ReadingCite> = [];
      public var loading: Boolean = false;

Threads pinned to a paragraph: the marker on every block (`blockThreads`), the
thread open under its paragraph (**ui**, by id, or the walkthrough's unsaved
one), and its messages. `threadLoading` is **ui**.

      public var blockThreads: Map<String, ChatThread> = new MapBuilder<String, ChatThread>().toMap();
      public var openThread: Conversation? = null;
      public var threadHistory: List<ChatTurn> = [];
      public var threadLoading: Boolean = false;

The wait: lines to show in front of the dots. **ui**.

      public var mutter: List<String> = [];
      public var mutterSeen: List<Int> = [];

The rewrite panel. **ui**: `rewrite` (the candidates), `rewriteSpan` (the
selected text), `rewriteRef` (the paragraph the panel sits under), `steer` (the
writer's note), `preview` (a candidate shown in the prose), `editing` (the ref
of the paragraph open for editing) and `editText` (what the box starts with),
`applied` (the last accepted change). `rewriting` is read off the run.

      public var rewrite: ShowRewrite? = null;
      public var rewriting: Boolean = false;
      public var rewritePending: Boolean = false;
      public var rewriteSpan: String? = null;
      public var rewriteRef: String? = null;
      public var steer: String? = null;
      public var preview: ReadingPreview? = null;
      public var editing: String? = null;
      public var editText: String? = null;
      public var applied: ShowApplied? = null;

**ui**: the read view shows the change rail instead of the notes.

      public var changesOn: Boolean = false;

Summaries. `summarising` is the ordinals whose run is going, `docRunning` and
`comparing` likewise (`comparing` is the button's text: `Drafting the summary`,
`Reading the summary`, `Relating`). `summaryLink` is the id of the link
between this draft and its condensation.

      public var summarising: List<Int> = [];
      public var docRunning: Boolean = false;
      public var comparing: String? = null;
      public var summaryLink: Int? = null;
      public var document: DocumentSummary? = null;

The other views' data, loaded only for the view that shows it
(`load.temper.md`): the Changes tab's rows and stat, the Graph tab's JSON (the
pretty-printed export) and stats, the Trace tab's events and stats.

      public var diffRows: List<Row> = [];
      /// The rendered blocks the read view found in `render_cache`, set by
      /// `renderReadView` for the request and never saved anywhere.
      public var renderCache: ReadingCache? = null;
      public var diffStat: ShowDiffStat? = null;
      public var graphJson: String? = null;
      public var graphStats: GraphStats? = null;
      public var events: List<GraphEvent> = [];
      public var eventStats: EventStats? = null;
      public var graphBuilding: Boolean = false;
      public var passes: List<AnalysisPass> = [];

The read in progress: the stages, and when it started (unix seconds).

      public var stages: ShowStages = new ShowStages("waiting", "waiting", "waiting");
      public var startedAt: Int? = null;

Links: the ones this draft is in, the drafts it could still be linked to
(loaded for the owner of a read draft), and whether the menu is open (**ui**).

      public var links: List<LinkWorks> = [];
      public var linkable: List<Work> = [];
      public var linking: Boolean = false;

The tour card (**ui**: by view), and the walkthrough: `demo` is **ui**, `walk`
its steps.

      public var tour: TourCard? = null;
      public var walk: List<WalkStep> = [];
      public var demo: Boolean = false;

The runs of this work that were going when the page was read. Any of them
makes the page poll.

      public var running: List<Run> = [];

Where this request stands: `fresh` is a plain page load (not a poll, not an
event), the one time the tour is decided.

      public var fresh: Boolean = true;
    }
