# Stacks

`Marginalia.Stacks`: reading an ordered folder forwards, as the method it
embodies.

A stack is documents that build one thing, in the order they were written:
fifty-five pull requests that add up to a compiler backend, a course, an
argument made across twelve essays. Read backwards, each document says what
happened. Read *forwards*, each one told only what the ones before it
established, each says what somebody building the same thing must now do.
That second reading is the method, and no single document contains it.

Three fields carry it. `capability` is what the thing can do afterwards that
it could not before. `requires` is which earlier documents this one stands
on. `pitfall` is the obvious approach that is wrong here, taken only when the
document says it outright, with the sentence that says so stored beside it.

This file is the part that needs no model: what a stack is, the order and
text of its documents, the validators that decide what a model answer keeps,
the fingerprints, the guide, the statistics and the draft. The passes that
call the model are in `passes.temper.md`.

    let { Db, DbRow } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Folder } = import("folders/src");
    let {
      Work, Section, workColumns, worksListSections, worksCreateWork, workParams, WorksResult,
    } = import("works/src");
    let { markdownParagraphs } = import("html/src");
    let {
      sysSha256, sysJoin, sysUtcNow, sysGraphemeLength,
    } = import("sys/src");
    let {
      JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonNull, JsonTextProducer, parseJson,
    } = import("std/json");

## Query parameters

A `$1`-style parameter list may hold nulls, and a list literal cannot be typed
`List<String?>` when one element is nullable, so parameters are collected one
at a time.

    class StacksArgs {
      private var items: ListBuilder<String?> = new ListBuilder<String?>();
      public s(v: String?): StacksArgs { items.add(v); this }
      public n(v: Int): StacksArgs { items.add(v.toString()); this }
      public no(v: Int?): StacksArgs {
        if (v != null) { items.add(v.toString()); } else { items.add(null); }
        this
      }
      public build(): List<String?> { items.toList() }
    }

    let stacksArgs(): StacksArgs { new StacksArgs() }

## What a stack is

The body cap: a document's text is its sections joined, then the first 14,000
characters.

    export let stacksBodyCap(): Int { 14000 }

`^\s*(\d+)\s*[.):-]` on the title: the number the author wrote first. Nine
digits at most; a longer number is not read as one.

    export let stacksLeadingNumber(title: String): Int? {
      var i = String.begin;
      while (title.hasIndex(i) && (title[i] == 32 || (title[i] >= 9 && title[i] <= 13))) {
        i = title.next(i);
      }
      var value = 0;
      var digits = 0;
      while (title.hasIndex(i) && title[i] >= 48 && title[i] <= 57) {
        if (digits < 9) { value = value * 10 + (title[i] - 48); }
        digits += 1;
        i = title.next(i);
      }
      if (digits == 0 || digits > 9) { return null; }
      while (title.hasIndex(i) && (title[i] == 32 || (title[i] >= 9 && title[i] <= 13))) {
        i = title.next(i);
      }
      if (!title.hasIndex(i)) { return null; }
      let c = title[i];
      if (c == 46 || c == 41 || c == 58 || c == 45) { value } else { null }
    }

    class StacksNumbered(public work: Work, public n: Int) {}

The works of a folder, in the order they should be read. A leading number in
the title wins when every document has one and the numbers are distinct: that
is the author saying the order out loud, and it survives being re-imported.
Otherwise insertion order (`id`), which is the only other thing that is true.

    export let stacksOrder(works: List<Work>): List<Work> {
      let numbered = new ListBuilder<StacksNumbered>();
      var all = true;
      for (let w of works) {
        let n = stacksLeadingNumber(w.title);
        if (n != null) { numbered.add(new StacksNumbered(w, n)); } else { all = false; }
      }
      var distinct = true;
      if (all) {
        let sortedNumbers = stacksSortedInts(numbered.toList().map { (x: StacksNumbered): Int => x.n });
        var i = 1;
        while (i < sortedNumbers.length) {
          if (sortedNumbers[i] == sortedNumbers[i - 1]) { distinct = false; }
          i += 1;
        }
      }
      if (all && distinct) {
        numbered.toList()
          .sorted { (a: StacksNumbered, b: StacksNumbered): Int => a.n - b.n }
          .map { (x: StacksNumbered): Work => x.work }
      } else {
        works.sorted { (a: Work, b: Work): Int => a.id - b.id }
      }
    }

    let stacksWorksOf(rows: List<DbRow>): List<Work> throws Bubble {
      let out = new ListBuilder<Work>();
      for (let row of rows) { out.add(Work.fromRow(row)); }
      out.toList()
    }

The works of a folder, ordered. Subfolders are not a stack.

    export let stacksDocuments(db: Db, scope: Scope, folderId: Int): List<Work> throws Bubble {
      stacksOrder(stacksWorksOf(db.query(
        "SELECT ${workColumns} FROM works WHERE user_id = $1 AND folder_id = $2 ORDER BY id ASC",
        stacksArgs().n(scope.userId).n(folderId).build(),
      )))
    }

## Steps and the story

The works the steps point at, loaded in one query and attached, as
`preload(:work)` did.

    let stacksAttachWorks(db: Db, steps: List<StackStep>): List<StackStep> throws Bubble {
      if (steps.length == 0) { return steps; }
      let args = stacksArgs();
      for (let s of steps) { args.n(s.workId); }
      let rows = db.query(
        "SELECT ${workColumns} FROM works WHERE id IN (${stacksPlaceholders(steps.length, 1)})",
        args.build(),
      );
      let byId = new MapBuilder<Int, Work>();
      for (let row of rows) {
        let w = Work.fromRow(row);
        byId.set(w.id, w);
      }
      for (let s of steps) {
        if (byId.has(s.workId)) { s.work = byId.get(s.workId); }
      }
      steps
    }

    let stacksStepsOf(rows: List<DbRow>): List<StackStep> throws Bubble {
      let out = new ListBuilder<StackStep>();
      for (let row of rows) { out.add(StackStep.fromRow(row)); }
      out.toList()
    }

`list_steps(folder_id)`: by ordinal, with the work.

    export let stacksListSteps(db: Db, folderId: Int): List<StackStep> throws Bubble {
      stacksAttachWorks(db, stacksStepsOf(db.query(
        "SELECT ${stacksStepColumns} FROM stack_steps WHERE folder_id = $1 ORDER BY ordinal ASC, id ASC",
        stacksArgs().n(folderId).build(),
      )))
    }

`get_step(folder_id, ordinal)`.

    export let stacksGetStep(db: Db, folderId: Int, ordinal: Int): StackStep? throws Bubble {
      let steps = stacksAttachWorks(db, stacksStepsOf(db.query(
        "SELECT ${stacksStepColumns} FROM stack_steps WHERE folder_id = $1 AND ordinal = $2 LIMIT 1",
        stacksArgs().n(folderId).n(ordinal).build(),
      )));
      if (steps.length == 0) { null } else { steps[0] }
    }

`get_story(folder_id)`.

    export let stacksGetStory(db: Db, folderId: Int): StackStory? throws Bubble {
      let row = db.one(
        "SELECT ${stacksStoryColumns} FROM stack_stories WHERE folder_id = $1",
        stacksArgs().n(folderId).build(),
      );
      if (row == null) { null } else { StackStory.fromRow(row) }
    }

The names the pages use, over a folder.

    export let stacksSteps(db: Db, folder: Folder): List<StackStep> throws Bubble {
      stacksListSteps(db, folder.id)
    }

    export let stacksStep(db: Db, folder: Folder, ordinal: Int): StackStep? throws Bubble {
      stacksGetStep(db, folder.id, ordinal)
    }

    export let stacksStory(db: Db, folder: Folder): StackStory? throws Bubble {
      stacksGetStory(db, folder.id)
    }

## The text of a document and its fingerprint

`text_of(work)`: the section bodies in order, joined, the first 14,000
characters.

    let stacksCapText(joined: String): String {
      stacksTake(joined, stacksBodyCap())
    }

    export let stacksTextOf(db: Db, workId: Int): String throws Bubble {
      let sections = worksListSections(db, workId);
      stacksCapText(sysJoin(sections.map { (s: Section): String => s.body }, "\n\n"))
    }

The same for many works in one query: `work_id -> text`.

    let stacksTexts(db: Db, workIds: List<Int>): Map<Int, String> throws Bubble {
      let out = new MapBuilder<Int, String>();
      if (workIds.length == 0) { return out.toMap(); }
      let args = stacksArgs();
      for (let id of workIds) { args.n(id); }
      let rows = db.query(
        "SELECT work_id, body FROM sections WHERE work_id IN (${stacksPlaceholders(workIds.length, 1)}) ORDER BY work_id ASC, ordinal ASC",
        args.build(),
      );
      var current = -1;
      var bodies = new ListBuilder<String>();
      for (let row of rows) {
        let id = row.int("work_id");
        if (id != current) {
          if (current >= 0) { out.set(current, stacksCapText(sysJoin(bodies.toList(), "\n\n"))); }
          current = id;
          bodies = new ListBuilder<String>();
        }
        bodies.add(row.str("body"));
      }
      if (current >= 0) { out.set(current, stacksCapText(sysJoin(bodies.toList(), "\n\n"))); }
      out.toMap()
    }

Lowercase hex SHA-256 of the text.

    export let stacksFingerprintOfText(text: String): String {
      sysSha256(text)
    }

    export let stacksFingerprint(db: Db, workId: Int): String throws Bubble {
      stacksFingerprintOfText(stacksTextOf(db, workId))
    }

`current?(step, work)`: whether a step was read from the document as it now
stands.

    export let stacksStepCurrent(db: Db, step: StackStep): Boolean throws Bubble {
      let f = step.fingerprint;
      f != null && f == stacksFingerprint(db, step.workId)
    }

    export let stacksIsStale(db: Db, step: StackStep): Boolean throws Bubble {
      !stacksStepCurrent(db, step)
    }

The telling's fingerprint: the steps' ordinal, capability, lesson, mechanism,
pitfall and `revised_by`, one `|`-separated line each, nil as empty.

    export let stacksStoryFingerprint(steps: List<StackStep>): String {
      let lines = steps.map { (s: StackStep): String =>
        let rev = s.revisedBy;
        let revText = if (rev != null) { rev.toString() } else { "" };
        "${s.ordinal.toString()}|${stacksOrEmpty(s.capability)}|${stacksOrEmpty(s.lesson)}|${stacksOrEmpty(s.mechanism)}|${stacksOrEmpty(s.pitfall)}|${revText}"
      };
      sysSha256(sysJoin(lines, "\n"))
    }

`story_current?(story, folder_id)`: whether the telling was composed from the
steps as they now stand.

    export let stacksStoryCurrent(db: Db, story: StackStory, folderId: Int): Boolean throws Bubble {
      let f = story.fingerprint;
      f != null && f == stacksStoryFingerprint(stacksListSteps(db, folderId))
    }

## Validation, first pass

What `validate/3` returns: the attributes to store and what was thrown out.
`capability` and `lesson` are the trimmed, scrubbed strings (the store turns
an empty one into NULL, as Ecto's `cast` does).

    export class StackStepAttrs(
      public capability: String,
      public requires: List<Int>,
      public lesson: String,
      public pitfall: String?,
      public pitfallQuote: String?,
      public excerpts: List<StackExcerpt>,
    ) {}

    export class StackValidated(public attrs: StackStepAttrs, public dropped: List<String>) {}

The block a quote sits in, or `null`. A located line alone is usually too
little to learn from and the whole document is far too much, so the unit is
the paragraph, the one `Reading.split/1` already uses everywhere else.

    export let stacksPassageAround(body: String, quote: String): String? {
      let found = stacksLocate(quote, body);
      if (found != null) {
        let blocks = markdownParagraphs(body);
        var i = 0;
        var passage: String = found;
        var hit = false;
        while (i < blocks.length && !hit) {
          if (stacksContains(blocks[i], found)) {
            passage = blocks[i];
            hit = true;
          }
          i += 1;
        }
        passage
      } else {
        null
      }
    }

Keep what can be checked against the document, and name what was thrown out.
Public for the same reason `Cuts.validate/2` is: the prompt and the schema can
be re-tuned freely, but a change that lets an unlocatable quote through makes
every step untrustworthy, and nothing else would notice.

    export let stacksValidate(raw: JsonObject, body: String, ordinal: Int): StackValidated throws Bubble {
      let dropped = new ListBuilder<String>();
      let kept = new ListBuilder<Int>();
      for (let r of stacksElements(raw.propertyValueOrNull("requires"))) {
        let n = stacksAsInt(r);
        if (n != null) {
          if (n >= 1 && n < ordinal) {
            kept.add(n);
          } else {
            dropped.add("requires ${n.toString()}: not an earlier document");
          }
        } else {
          dropped.add("requires ${stacksInspectJson(r)}: not a number");
        }
      }
      let pitfallText = stacksTrimmed(raw.propertyValueOrNull("pitfall"));
      let cap = stacksScrub(stacksTrimmed(raw.propertyValueOrNull("capability")), "capability");
      let les = stacksScrub(stacksTrimmed(raw.propertyValueOrNull("lesson")), "lesson");
      let capLeak = cap.leak;
      if (capLeak != null) { dropped.add(capLeak); }
      let lesLeak = les.leak;
      if (lesLeak != null) { dropped.add(lesLeak); }

      let quote = stacksTrimmed(raw.propertyValueOrNull("pitfall_quote"));
      let found: String? = if (quote != "") { stacksLocate(quote, body) } else { null };
      var pitfall: String? = null;
      if (pitfallText != "") {
        if (found != null) {
          pitfall = pitfallText;
        } else {
          dropped.add("pitfall: quote is not in the document");
        }
      }

      let excerpts = new ListBuilder<StackExcerpt>();
      for (let e of stacksElements(raw.propertyValueOrNull("excerpts"))) {
        let q = if (stacksIsObject(e)) { stacksTrimmed(stacksProp(e, "quote")) } else { "" };
        if (q == "") {
          dropped.add("excerpt: no quote");
        } else {
          let passage = stacksPassageAround(body, q);
          if (passage == null) {
            dropped.add("excerpt: ${stacksInspect(stacksTake(q, 50))} is not in the document");
          } else {
            excerpts.add(new StackExcerpt(stacksTrimmed(stacksProp(e, "caption")), passage));
          }
        }
      }
      let firstTwo = new ListBuilder<StackExcerpt>();
      var k = 0;
      while (k < excerpts.length && k < 2) {
        firstTwo.add(excerpts[k]);
        k += 1;
      }

      new StackValidated(
        new StackStepAttrs(
          cap.text,
          stacksSortedUniqInts(kept.toList()),
          les.text,
          pitfall,
          found,
          firstTwo.toList(),
        ),
        dropped.toList(),
      )
    }

## Validation, second pass

A revision claim is the one here that can do damage: "step 14 walks this back"
sends a reader off to read something that may not say that at all. So it has
to name a later step and quote that step's own summary.

    export class StackDeepAttrs(
      public mechanism: String?,
      public watchFor: String?,
      public revisedBy: Int?,
      public revision: String?,
      public revisionQuote: String?,
    ) {}

    export class StackDeepValidated(public attrs: StackDeepAttrs, public dropped: List<String>) {}

    let stacksStepWithOrdinal(later: List<StackStep>, n: Int): StackStep? {
      var found: StackStep? = null;
      for (let s of later) {
        if (s.ordinal == n) { found = s; }
      }
      found
    }

    export let stacksValidateDeep(raw: JsonObject, later: List<StackStep>): StackDeepValidated {
      let dropped = new ListBuilder<String>();
      let mechanismText = stacksTrimmed(raw.propertyValueOrNull("mechanism"));
      let watchText = stacksTrimmed(raw.propertyValueOrNull("watch_for"));
      let n = stacksAsInt(raw.propertyValueOrNull("revised_by"));
      let revisionText = stacksTrimmed(raw.propertyValueOrNull("revision"));
      let quote = stacksTrimmed(raw.propertyValueOrNull("revision_quote"));
      let target: StackStep? = if (n != null) { stacksStepWithOrdinal(later, n) } else { null };
      var haystack = "";
      if (target != null) {
        haystack = sysJoin(
          [stacksOrEmpty(target.capability), stacksOrEmpty(target.lesson), stacksOrEmpty(target.pitfall)],
          "\n",
        );
      }
      let found: String? = if (quote != "" && haystack != "") { stacksLocate(quote, haystack) } else { null };
      let num = if (n != null) { n } else { 0 };

      var revisedBy: Int? = null;
      var revision: String? = null;
      var revisionQuote: String? = null;
      if (n == null || num == 0 || revisionText == "") {
        // nothing claimed
      } else if (target == null) {
        dropped.add("revision: step ${num.toString()} is not a later step");
      } else if (found == null) {
        dropped.add("revision: quote is not in step ${num.toString()}'s summary");
      } else {
        revisedBy = num;
        revision = revisionText;
        revisionQuote = found;
      }

      var mechanism: String? = null;
      if (mechanismText == "") {
        dropped.add("mechanism: empty");
      } else {
        mechanism = mechanismText;
      }
      new StackDeepValidated(
        new StackDeepAttrs(
          mechanism,
          if (watchText == "") { null } else { watchText },
          revisedBy,
          revision,
          revisionQuote,
        ),
        dropped.toList(),
      )
    }

## Validation, the telling

Keep the telling only if it accounts for the whole stack. The coverage check
is the point. Prose is not quote-checkable the way a claim is, so the thing
that can be checked is whether the composition actually carries every step.

    export class StackStoryAttrs(
      public title: String,
      public opening: String,
      public movements: List<StoryMovement>,
      public closing: String,
    ) {}

    export class StackStoryValidated(
      public attrs: StackStoryAttrs,
      public dropped: List<String>,
      public uncovered: List<Int>,
    ) {}

`List.wrap(is_map(m) && m["steps"])`: a part that is not an object wraps
`false`; a missing or null `steps` is none; a scalar is a list of one.

    let stacksStepItems(m: JsonSyntaxTree): List<JsonSyntaxTree> {
      let steps = stacksProp(m, "steps");
      if (steps != null) {
        if (steps is JsonArray) {
          steps.elements
        } else if (steps is JsonNull) {
          []
        } else {
          [steps]
        }
      } else {
        []
      }
    }

    class StacksPartKept(public movement: StoryMovement, public first: Int) {}

    export let stacksValidateStory(raw: JsonObject, steps: List<StackStep>): StackStoryValidated throws Bubble {
      let ordinals = steps.map { (s: StackStep): Int => s.ordinal };
      let dropped = new ListBuilder<String>();
      let kept = new ListBuilder<StacksPartKept>();
      let seen = new ListBuilder<Int>();
      for (let m of stacksElements(raw.propertyValueOrNull("movements"))) {
        let isMap = stacksIsObject(m);
        let heading = if (isMap) { stacksTrimmed(stacksProp(m, "heading")) } else { "" };
        let label = "part ${stacksInspect(heading)}";
        let scrubbed = stacksScrub(if (isMap) { stacksTrimmed(stacksProp(m, "prose")) } else { "" }, label);
        let leak = scrubbed.leak;
        if (leak != null) { dropped.add(leak); }
        let prose = scrubbed.text;

        let mine = new ListBuilder<Int>();
        if (!isMap) {
          dropped.add("${label}: false is not a step number");
        } else {
          let items = stacksStepItems(m);
          var j = 0;
          while (j < items.length) {
            let n = stacksAsInt(items[j]);
            if (n != null) {
              if (!stacksContainsInt(ordinals, n)) {
                dropped.add("${label}: step ${n.toString()} is not in this stack");
              } else if (stacksContainsInt(seen.toList(), n)) {
                dropped.add("${label}: step ${n.toString()} is told twice");
              } else {
                mine.add(n);
              }
            } else {
              dropped.add("${label}: ${stacksInspectJson(items[j])} is not a step number");
            }
            j += 1;
          }
        }

        if (heading == "" || prose == "") {
          dropped.add(if (heading == "") { "a part with no heading" } else { "a part with no prose" });
        } else {
          let minePlain = mine.toList();
          kept.add(new StacksPartKept(
            new StoryMovement(heading, prose, minePlain, stacksTrimmed(stacksProp(m, "turn"))),
            if (minePlain.length > 0) { minePlain[0] } else { 9999 },
          ));
          for (let n of minePlain) { seen.add(n); }
        }
      }

      let seenList = seen.toList();
      let uncoveredAll = new ListBuilder<Int>();
      for (let o of ordinals) {
        if (!stacksContainsInt(seenList, o)) { uncoveredAll.add(o); }
      }
      let uncovered = stacksSortedUniqInts(uncoveredAll.toList());
      if (uncovered.length > 0) {
        dropped.add("${uncovered.length.toString()} step(s) appear in no part: ${stacksJoinInts(uncovered, ", ")}");
      }

Parts are told in the order the work is done, so they sort by their first
step rather than by whatever order they came back in. The sort is stable.

      let ordered = kept.toList().sorted { (a: StacksPartKept, b: StacksPartKept): Int => a.first - b.first };
      let opening = stacksScrub(stacksTrimmed(raw.propertyValueOrNull("opening")), "opening");
      let closing = stacksScrub(stacksTrimmed(raw.propertyValueOrNull("closing")), "closing");
      let openLeak = opening.leak;
      if (openLeak != null) { dropped.add(openLeak); }
      let closeLeak = closing.leak;
      if (closeLeak != null) { dropped.add(closeLeak); }
      new StackStoryValidated(
        new StackStoryAttrs(
          stacksTrimmed(raw.propertyValueOrNull("title")),
          opening.text,
          ordered.map { (k: StacksPartKept): StoryMovement => k.movement },
          closing.text,
        ),
        dropped.toList(),
        uncovered,
      )
    }

## The guide

The stack as a reading path: each step, what it needs, and what needs it.
Derived rather than asked for.

    export class StackGuideEntry(
      public step: StackStep,
      public requires: List<StackStep>,
      public requiredBy: List<StackStep>,
      public previous: StackStep?,
      public next: StackStep?,
    ) {}

    export let stacksGuide(db: Db, folderId: Int): List<StackGuideEntry> throws Bubble {
      stacksGuideOf(stacksListSteps(db, folderId))
    }

    export let stacksGuideOf(steps: List<StackStep>): List<StackGuideEntry> throws Bubble {
      let byOrdinal = new MapBuilder<Int, StackStep>();
      for (let s of steps) { byOrdinal.set(s.ordinal, s); }
      let out = new ListBuilder<StackGuideEntry>();
      for (let step of steps) {
        let needs = new ListBuilder<StackStep>();
        for (let r of step.requires) {
          if (byOrdinal.has(r)) { needs.add(byOrdinal.get(r)); }
        }
        let needed = new ListBuilder<StackStep>();
        for (let other of steps) {
          if (stacksContainsInt(other.requires, step.ordinal)) { needed.add(other); }
        }
        out.add(new StackGuideEntry(
          step,
          needs.toList(),
          needed.toList().sorted { (a: StackStep, b: StackStep): Int => a.ordinal - b.ordinal },
          if (byOrdinal.has(step.ordinal - 1)) { byOrdinal.get(step.ordinal - 1) } else { null },
          if (byOrdinal.has(step.ordinal + 1)) { byOrdinal.get(step.ordinal + 1) } else { null },
        ));
      }
      out.toList()
    }

Which step each of this writer's documents became, if any: `work_id ->
(folder_id, ordinal)`, in one query for the whole tree.

    export class StackStepRef(public workId: Int, public folderId: Int, public ordinal: Int) {}

    export let stacksStepsByWork(db: Db, scope: Scope): Map<Int, StackStepRef> throws Bubble {
      let rows = db.query(
        "SELECT s.work_id AS work_id, s.folder_id AS folder_id, s.ordinal AS ordinal FROM stack_steps s JOIN works w ON w.id = s.work_id WHERE w.user_id = $1 ORDER BY s.id ASC",
        stacksArgs().n(scope.userId).build(),
      );
      let out = new MapBuilder<Int, StackStepRef>();
      for (let row of rows) {
        let ref = new StackStepRef(row.int("work_id"), row.int("folder_id"), row.int("ordinal"));
        out.set(ref.workId, ref);
      }
      out.toMap()
    }

## Statistics

How much of a folder has been read forwards, and how sound it is.

    export class StackStats(
      public documents: Int,
      public read: Int,
      public stale: Int,
      public pitfalls: Int,
      public excerpts: Int,
      public links: Int,
      public dropped: Int,
      public summarised: Int,
      public mapped: Int,
      public related: Int,
      public deepened: Int,
      public deepFailed: Int,
      public revisions: Int,
      public deepDropped: Int,
    ) {}

Pairs with both ends inside this folder. A link from one of these documents
to something outside it is a real link and not this folder's business.

    let stacksRelatedCount(db: Db, docs: List<Work>): Int throws Bubble {
      if (docs.length == 0) { return 0; }
      let args = stacksArgs();
      for (let w of docs) { args.n(w.id); }
      for (let w of docs) { args.n(w.id); }
      let row = db.one(
        "SELECT count(*) AS n FROM links WHERE a_work_id IN (${stacksPlaceholders(docs.length, 1)}) AND b_work_id IN (${stacksPlaceholders(docs.length, docs.length + 1)})",
        args.build(),
      );
      if (row == null) { 0 } else { row.int("n") }
    }

One query for the folder rather than one per document.

    let stacksSummarisedCount(db: Db, docs: List<Work>): Int throws Bubble {
      if (docs.length == 0) { return 0; }
      let args = stacksArgs();
      for (let w of docs) { args.n(w.id); }
      let row = db.one(
        "SELECT count(*) AS n FROM document_summaries WHERE work_id IN (${stacksPlaceholders(docs.length, 1)}) AND summary IS NOT NULL AND summary != ''",
        args.build(),
      );
      if (row == null) { 0 } else { row.int("n") }
    }

    export let stacksStats(db: Db, scope: Scope, folderId: Int): StackStats throws Bubble {
      let docs = stacksDocuments(db, scope, folderId);
      let steps = stacksListSteps(db, folderId);
      let stepOf = new MapBuilder<Int, StackStep>();
      for (let s of steps) { stepOf.set(s.workId, s); }
      let stepIds = new ListBuilder<Int>();
      for (let d of docs) {
        if (stepOf.has(d.id)) { stepIds.add(d.id); }
      }
      let texts = stacksTexts(db, stepIds.toList());
      var stale = 0;
      var mapped = 0;
      for (let d of docs) {
        if (stepOf.has(d.id)) {
          let fp = stepOf.get(d.id).fingerprint;
          let text = if (texts.has(d.id)) { texts.get(d.id) } else { "" };
          if (fp == null || fp != stacksFingerprintOfText(text)) { stale += 1; }
        }
        if (d.status == "read") { mapped += 1; }
      }
      var pitfalls = 0;
      var excerpts = 0;
      var links = 0;
      var dropped = 0;
      var deepened = 0;
      var deepFailed = 0;
      var revisions = 0;
      var deepDropped = 0;
      for (let s of steps) {
        if (stacksOrEmpty(s.pitfall) != "") { pitfalls += 1; }
        excerpts += s.excerpts.length;
        links += s.requires.length;
        dropped += s.dropped.length;
        if (s.deepenedAt != null) { deepened += 1; }
        if (s.deepenedAt == null) {
          var failed = false;
          for (let d of s.deepDropped) {
            if (stacksStartsWith(d, "the second pass failed")) { failed = true; }
          }
          if (failed) { deepFailed += 1; }
        }
        if (s.revisedBy != null) { revisions += 1; }
        deepDropped += s.deepDropped.length;
      }
      new StackStats(
        docs.length, steps.length, stale, pitfalls, excerpts, links, dropped,
        stacksSummarisedCount(db, docs), mapped, stacksRelatedCount(db, docs),
        deepened, deepFailed, revisions, deepDropped,
      )
    }

    let stacksStartsWith(s: String, prefix: String): Boolean {
      let parts = s.split(prefix);
      parts.length > 1 && parts[0].isEmpty
    }

## Back into the reader as a draft

Turn the composed telling into an ordinary draft, so it can be read. Each
movement becomes a `##` heading, which is what the segmenter divides on, so
the parts of the telling become the sections of the draft and a note lands on
the movement it is about.

Deliberately not filed into the stack's own folder: a folder is the unit a
stack is read from, and a draft sitting in it would become document 112 of
111, re-read as a chapter of the series it is a summary of.

`work` is the created draft; otherwise `error` is `"not_composed"` (no
telling yet) or the works context's reason (`invalid`, `empty`, `too_long`,
`no_sections`).

    export class StackDraft(public work: Work?, public error: String?) {}

    export let stacksIntent(steps: Int, parts: Int): String {
      "The method read out of ${steps.toString()} documents, in ${parts.toString()} parts. It is meant to tell somebody building the same thing what to do and in what order, so the test of any paragraph is whether it could be acted on."
    }

The body, with the Elixir's join reproduced literally: because the three
closing strings are joined with a blank line too, `## Closing` is followed by
four newlines and then the closing.

    export let stacksDraftBody(story: StackStory): String {
      let blocks = new ListBuilder<String>();
      blocks.add(stacksOrEmpty(story.opening));
      var i = 1;
      while (i <= story.movements.length) {
        let m = story.movements[i - 1];
        let lines = new ListBuilder<String>();
        lines.add("## ${i.toString()}. ${m.heading}");
        lines.add("");
        lines.add(m.prose);
        if (m.turn != "") { lines.add("\n> ${m.turn}"); }
        blocks.add(sysJoin(lines.toList(), "\n"));
        i += 1;
      }
      blocks.add("## Closing");
      blocks.add("");
      blocks.add(stacksOrEmpty(story.closing));
      stacksTrim(sysJoin(blocks.toList(), "\n\n"))
    }

    let stacksDraftOf(db: Db, scope: Scope, folderId: Int, story: StackStory): StackDraft throws Bubble {
      let steps = stacksListSteps(db, folderId);
      let title = story.title;
      let params = workParams(if (title != null) { title } else { "A reading" }, stacksDraftBody(story));
      params.intent = stacksIntent(steps.length, story.movements.length);
      let result = worksCreateWork(db, scope, params);
      new StackDraft(result.ok, result.error)
    }

    export let stacksToDraft(db: Db, scope: Scope, folderId: Int): StackDraft throws Bubble {
      let story = stacksGetStory(db, folderId);
      if (story != null) {
        stacksDraftOf(db, scope, folderId, story)
      } else {
        new StackDraft(null, "not_composed")
      }
    }
