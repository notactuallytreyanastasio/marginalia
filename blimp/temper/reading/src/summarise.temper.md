# Summarising one section

`Marginalia.Summary`: what one section of a draft says, read knowing what
surrounds it.

Not a review and not a note in the margin: this answers the duller and more
often needed question. I am looking at section seven of twelve, what is in it?

## Why the neighbours are in the prompt

A summary written from the section alone re-establishes its own setup, because
nothing told it the setup was three sections ago, and it cannot say what the
section is *for*. So the call is given the spine of the whole draft (every
section's ordinal and title, one line each) and the summary already written for
the section before it, when there is one.

## Why `covers` is checked

Prose is not quote-checkable the way a claim is, so the summary itself is taken
on trust. Its nouns are not: each term in `covers` has to appear in the
section, and one that does not is dropped and said so.

    let { Db } = import("db/src");
    let { Work, Section, worksGetById, worksListSections, worksSectionById } = import("works/src");
    let { rows, Row } = import("core/src");
    let { LlmClient, LlmTool } = import("llm/src");
    let { JsonObject, JsonSyntaxTree, JsonString, JsonNumeric } = import("std/json");
    let { versionsBump, versionsWorkTopic } = import("runs/src");
    let { sysSha256, sysUtcNow, sysUtf8Downcase, sysJoin } = import("sys/src");

The body handed to the model is capped here.

    let summaryBodyCap(): Int { 12000 }

## Fingerprints

What a summary is current against: the lower-case hex SHA-256 of the section
body. Nothing else about the section matters, so a new title does not make a
summary stale.

    export let summaryFingerprint(section: Section): String {
      sysSha256(section.body)
    }

Whether this section's summary still describes its text. A section with no
summary is not current; a summary with no fingerprint is not either.

    export let summaryCurrent(section: Section): Boolean {
      if (section.summary == null) { return false; }
      let stored = section.summaryFingerprint;
      if (stored != null) { stored == summaryFingerprint(section) } else { false }
    }

What has moved under a stale summary, as side-by-side rows (`core`'s paragraph
`rows`, so the caller runs the word diff on the changed pair only). Empty when
the summary is current, and empty for one written before the source was kept:
there is nothing to compare it against, and inventing a baseline would draw a
diff that never happened.

    export let summaryDrift(section: Section): List<Row> {
      if (summaryCurrent(section)) { return []; }
      let before = section.summaryBody;
      if (before != null) { rows(before, section.body) } else { [] }
    }

## The prompt's two pieces of context

One line per section: it lets the model place this one without being handed
the text of eleven others, and costs the same at twelve sections or a hundred
and eleven. The section being summarised is marked.

    export let summarySpine(siblings: List<Section>, section: Section): String {
      let lines = siblings.map { (s: Section): String =>
        let mark = if (s.ordinal == section.ordinal) { "  <- THIS ONE" } else { "" };
        "${s.ordinal.toString()}. ${s.title}${mark}"
      };
      sysJoin(lines, "\n")
    }

The section before, in the words already used for it, so consecutive summaries
read as a sequence. Empty when there is no section before or it has no summary;
otherwise it starts and ends with a newline. It does not need to be current.

    export let summaryPreviousBlock(siblings: List<Section>, section: Section): String {
      var found: Section? = null;
      for (let s of siblings) {
        if (s.ordinal == section.ordinal - 1) { found = s; }
      }
      let prev = found;
      if (prev != null) {
        let text = prev.summary;
        if (text != null) {
          if (text.isEmpty) {
            ""
          } else {
            "\nThe section before this one (${prev.ordinal.toString()}. ${prev.title}) was summarised as:\n${text}\n"
          }
        } else {
          ""
        }
      } else {
        ""
      }
    }

## The tool

    export let summaryTool(): LlmTool {
      new LlmTool(summaryToolName(), summaryToolDescription(), summaryToolParameters())
    }

## Validating

Normalise and check what came back: `{attrs, dropped}` as a `SummaryChecked`.

- `summary` is the trimmed text (anything but a string is empty).
- `covers`: trimmed, empties removed, duplicates collapsed, and each kept only
  if its lower-cased form is in the lower-cased body (the capped one). Each one
  dropped says `covers: "term" is not in the section`. At most six are kept.
- `follows_from`: an integer, or a string that starts with one, from 1 up to
  but not including `ordinal`; another integer says `follows_from 5: not an
  earlier section`, anything else `follows_from "x": not a number`.
- `sets_up` is trimmed, and nothing is null.

Public because it is pure and because it is the part that can be wrong in a
way a reader cannot see.

    export let summaryValidate(raw: JsonSyntaxTree, body: String, ordinal: Int): SummaryChecked {
      let summary = readingTrimmed(readingProp(raw, "summary"));
      let haystack = sysUtf8Downcase(body);
      let dropped = new ListBuilder<String>();

      let seen = new ListBuilder<String>();
      let keep = new ListBuilder<String>();
      for (let item of readingElements(raw, "covers")) {
        let term = readingTrimmed(item);
        if (!term.isEmpty && !summaryHas(seen.toList(), term)) {
          seen.add(term);
          if (readingContains(haystack, sysUtf8Downcase(term))) {
            keep.add(term);
          } else {
            dropped.add("covers: ${readingInspectString(term)} is not in the section");
          }
        }
      }

      let follows = new ListBuilder<Int>();
      for (let item of readingElements(raw, "follows_from")) {
        let n = summaryAsInt(item);
        if (n != null) {
          if (n >= 1 && n < ordinal) {
            follows.add(n);
          } else {
            dropped.add("follows_from ${n.toString()}: not an earlier section");
          }
        } else {
          dropped.add("follows_from ${readingInspect(item)}: not a number");
        }
      }

      let setsUp = readingTrimmed(readingProp(raw, "sets_up"));
      let covers = keep.toList();
      let top = if (covers.length > 6) { covers.slice(0, 6) } else { covers };
      let distinct = new ListBuilder<Int>();
      for (let n of follows.toList()) {
        var present = false;
        for (let m of distinct.toList()) {
          if (m == n) { present = true; }
        }
        if (!present) { distinct.add(n); }
      }
      new SummaryChecked(
        summary, top, distinct.toList(),
        if (setsUp.isEmpty) { null } else { setsUp },
        dropped.toList(),
      )
    }

    let summaryHas(xs: List<String>, x: String): Boolean {
      for (let y of xs) {
        if (y == x) { return true; }
      }
      false
    }

An integer; or a string read with `Integer.parse/1` after a trim (an optional
sign, digits, whatever follows ignored); anything else is not a number.

    let summaryAsInt(t: JsonSyntaxTree): Int? {
      let n = readingJsonInt(t);
      if (n != null) { return n; }
      if (t is JsonString) { readingParseInt(readingTrim(t.content)) } else { null }
    }

## Storing

The section row gets the summary and everything that says what it was made
from: the fingerprint of the body as given, the full body (for the drift
view), the time, the covers, follows, sets-up, and what was dropped. An empty
summary is `no_summary` and stores nothing.

    export let summaryStore(
      db: Db, section: Section, checked: SummaryChecked,
    ): SummaryResult throws Bubble {
      if (checked.summary.isEmpty) {
        return new SummaryResult(null, "no_summary", null, checked.dropped);
      }
      let now = sysUtcNow();
      db.exec(
        "UPDATE sections SET summary = $1, summary_covers = $2, summary_follows = $3, summary_sets_up = $4, summary_fingerprint = $5, summary_body = $6, summarised_at = $7, summary_dropped = $8, updated_at = $9 WHERE id = $10",
        readingArgs()
          .s(checked.summary)
          .s(readingJsonStrings(checked.covers))
          .s(readingJsonInts(checked.follows))
          .s(checked.setsUp)
          .s(summaryFingerprint(section))
          .s(section.body)
          .s(now)
          .s(readingJsonStrings(checked.dropped))
          .s(now)
          .n(section.id)
          .build(),
      );
      let stored = worksSectionById(db, section.id);
      new SummaryResult(stored, null, null, checked.dropped)
    }

## Asking

Summarise one section and store it. The first twelve thousand characters of the
body go to the model; a section that is blank is `empty` and no call is made.
The sections of the draft give the spine and the section before; the model is
asked once, with `effort` low, temperature 0.2 and 1,200 tokens of answer.

The work's version counter is bumped when a summary is stored, so a page that is
waiting on the draft reloads (the Elixir page re-read the section itself).

Owner-scoped by the caller: this spends money, so it is reached only from a
path that has already established whose draft it is.

    export let summaryAsk(
      db: Db, llm: LlmClient, work: Work, section: Section,
    ): SummaryResult throws Bubble {
      let body = readingTake(section.body, summaryBodyCap());
      if (readingIsBlank(body)) {
        return new SummaryResult(null, "empty", null, []);
      }
      let siblings = worksListSections(db, section.workId);
      let user = promptsSummaryUser(
        work.title, work.intent, summarySpine(siblings, section),
        summaryPreviousBlock(siblings, section),
        section.ordinal, section.title, body,
      );
      let reply = readingCallTool(
        llm, summaryTool(), readingFastModel(), "low", 0.2, 1200, summaryPrompt(), user,
      );
      let raw = reply.ok;
      if (raw != null) {
        let stored = summaryStore(db, section, summaryValidate(raw, body, section.ordinal));
        if (stored.ok != null) {
          versionsBump(db, versionsWorkTopic(section.workId));
        }
        stored
      } else {
        new SummaryResult(null, reply.error, reply.detail, [])
      }
    }

`Summary.run/2`: the same, for a caller that has only the section. The work is
read for its title and intent.

    export let summaryRun(db: Db, llm: LlmClient, section: Section): SummaryResult throws Bubble {
      let work = worksGetById(db, section.workId);
      if (work != null) {
        summaryAsk(db, llm, work, section)
      } else {
        bubble()
      }
    }

The fingerprint check: ask only when the summary has stopped describing the
text. A section whose summary is current comes back as it is, with no call.

    export let summaryEnsure(
      db: Db, llm: LlmClient, work: Work, section: Section,
    ): SummaryResult throws Bubble {
      if (summaryCurrent(section)) {
        new SummaryResult(section, null, null, [])
      } else {
        summaryAsk(db, llm, work, section)
      }
    }

A section by ordinal, for a work the caller has already established is theirs.

    export let summarySection(db: Db, workId: Int, ordinal: Int): Section? throws Bubble {
      var found: Section? = null;
      for (let s of worksListSections(db, workId)) {
        if (s.ordinal == ordinal) { found = s; }
      }
      found
    }
