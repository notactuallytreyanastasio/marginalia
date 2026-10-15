# Editing, revisions, corrections, attachments and document summaries

`Marginalia.Works`, the third part: how a draft changes and what is kept of
the changes, plus the small tables that hang off a work.

    let { Db, DbRow, dbTransaction } = import("db/src");
    let { FieldError, reflow } = import("core/src");
    let { wordCount } = import("html/src");
    let { sysUtcNow, sysJoin, sysByteLength, sysGraphemeLength } = import("sys/src");
    let { JsonSyntaxTree } = import("std/json");

## Revisions

Every change to a draft's prose, oldest first.

    export let worksRevisions(db: Db, workId: Int): List<Revision> throws Bubble {
      let out = new ListBuilder<Revision>();
      for (let row of db.query(
        "SELECT ${revisionColumns} FROM revisions WHERE work_id = $1 ORDER BY seq ASC",
        worksArgs().n(workId).build(),
      )) {
        out.add(Revision.fromRow(row));
      }
      out.toList()
    }

How many changes a draft has had.

    export let worksRevisionCount(db: Db, workId: Int): Int throws Bubble {
      let row = db.one("SELECT count(*) AS n FROM revisions WHERE work_id = $1", worksArgs().n(workId).build());
      if (row == null) { 0 } else { row.int("n") }
    }

`record_revision`: the next `seq` is the greatest so far plus one, read inside
the transaction of the edit. Two concurrent edits of one work could collide on
the unique `(work_id, seq)` index and one would fail (hazard 13); SQLite
serialises writers, so here the second waits and takes the next number.

    let worksRecordRevision(
      db: Db, section: Section, before: String, after: String, origin: String, note: String?,
    ): Void throws Bubble {
      if (!worksIn(["edit", "rewrite", "summary"], origin)) { bubble() }
      let row = db.one(
        "SELECT coalesce(max(seq), 0) AS top FROM revisions WHERE work_id = $1",
        worksArgs().n(section.workId).build(),
      );
      let top = if (row == null) { 0 } else { row.int("top") };
      db.exec(
        "INSERT INTO revisions (work_id, section_id, section_ordinal, seq, \"before\", \"after\", origin, note) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
        worksArgs().n(section.workId).n(section.id).n(section.ordinal).n(top + 1)
          .s(before).s(after).s(origin).s(note).build(),
      );
    }

The prose as it arrived: the stored `baseline_body` when there is one.
Otherwise it is rebuilt: start from the body and undo the revisions newest
first, each by replacing the first occurrence of its `after` with its `before`;
one whose `after` is no longer present is skipped, so the worst case is a
baseline that is too recent, never one that is invented. A draft with no
revisions and no baseline returns its body.

    export let worksBaseline(db: Db, work: Work): String throws Bubble {
      let stored = work.baselineBody;
      if (stored != null) {
        if (!stored.isEmpty) { return stored; }
      }
      let revisions = worksRevisions(db, work.id);
      var body = work.body;
      var i = revisions.length - 1;
      while (i >= 0) {
        let rev = revisions[i];
        if (worksContains(body, rev.after)) {
          body = worksReplaceFirst(body, rev.after, rev.before);
        }
        i -= 1;
      }
      body
    }

    export class ReplayResult(public ok: String?, public failedSeq: Int?) {}

Replay every revision over the baseline: the property the diff view rests on.
`ok` is the body, or `failedSeq` names the first revision whose `before` is no
longer present, which means the history and the draft have parted company.

    export let worksReplay(db: Db, workId: Int): ReplayResult throws Bubble {
      let work = worksWorkOrBubble(worksGetById(db, workId));
      var body = worksBaseline(db, work);
      let revisions = worksRevisions(db, workId);
      var i = 0;
      while (i < revisions.length) {
        let rev = revisions[i];
        if (!worksContains(body, rev.before)) {
          return new ReplayResult(null, rev.seq);
        }
        body = worksReplaceFirst(body, rev.before, rev.after);
        i += 1;
      }
      new ReplayResult(body, null)
    }

## Editing the draft

`error` is `"empty"` (the new text is blank: a deletion is not a rewrite) or
`"moved"` (the old text is no longer in the section). Otherwise `section` is
the section as it now stands, `superseded` how many notes lost their line, and
`revision` the history row, or null when nothing changed.

    export class ReplaceResult(
      public section: Section,
      public superseded: Int,
      public revision: Revision?,
      public error: String?,
    ) {}

    class WorksEdit {
      public var superseded: Int = 0;
    }

Replace one passage of a section with new text. Everything in the app is
anchored: a beat, a connection, a thread quote is a literal substring of the
draft, so editing a paragraph can leave notes pointing at a sentence that no
longer exists. Those are marked `superseded` rather than deleted: the
observation may still be true. The section keeps its boundaries; re-splitting
would renumber every section and detach every note.

The new text is reflowed to one sentence per line before anything is compared
(so a pasted one-liner is stored the way the draft is, and a re-wrap alone is
no edit), `origin` is `"edit"`, `"rewrite"` or `"summary"` (null means edit),
and `old` may be any substring of the section body, a span across paragraphs
included. The revision, the section and the work's rebuilt body commit
together or not at all.

    export let worksReplaceBlock(
      db: Db, section: Section, old: String, newText: String, origin: String?, note: String?,
    ): ReplaceResult throws Bubble {
      let text = reflow(worksTrimTrailing(newText));
      if (worksIsBlank(text)) { return new ReplaceResult(section, 0, null, "empty"); }
      if (text == old) { return new ReplaceResult(section, 0, null, null); }
      if (!worksContains(section.body, old)) { return new ReplaceResult(section, 0, null, "moved"); }
      let kind = if (origin != null) { origin } else { "edit" };
      let body = worksReplaceFirst(section.body, old, text);
      let edit = new WorksEdit();
      dbTransaction(db, fn (): Void throws Bubble {
        db.exec(
          "UPDATE sections SET body = $1, word_count = $2, updated_at = $3 WHERE id = $4",
          worksArgs().s(body).n(wordCount(body)).s(sysUtcNow()).n(section.id).build(),
        );
        let changed = worksSectionOrBubble(worksSectionById(db, section.id));
        edit.superseded = worksSupersedeUnanchored(db, changed);
        worksRecordRevision(db, changed, old, text, kind, note);
        worksRebuildWorkBody(db, section.workId);
      });
      let stored = worksSectionOrBubble(worksSectionById(db, section.id));
      let rev = db.one(
        "SELECT ${revisionColumns} FROM revisions WHERE work_id = $1 ORDER BY seq DESC LIMIT 1",
        worksArgs().n(section.workId).build(),
      );
      new ReplaceResult(stored, edit.superseded, if (rev == null) { null } else { Revision.fromRow(rev) }, null)
    }

The name the porting brief used for the same thing.

    export let worksUpdateSectionBody(
      db: Db, section: Section, old: String, newText: String, origin: String?, note: String?,
    ): ReplaceResult throws Bubble {
      worksReplaceBlock(db, section, old, newText, origin, note)
    }

A note whose quote is no longer in the section is marked, not removed. A node
with no quote, or one already superseded, is left alone. Answers how many were
marked.

    let worksSupersedeUnanchored(db: Db, section: Section): Int throws Bubble {
      let folded = worksFold(section.body);
      var marked = 0;
      for (let n of worksListNodes(db, section.workId, null, section.id, null)) {
        let quote = n.quote;
        if (quote != null) {
          if (!quote.isEmpty && n.status != "superseded") {
            if (!worksQuoteHolds(quote, folded)) {
              let r = worksSetNodeStatus(db, section.workId, n.id, "superseded");
              if (r.node != null) { marked += 1; }
            }
          }
        }
      }
      marked
    }

The work's body is the sections joined back up, so an export or a re-read sees
what the writer sees; the word count is recomputed from it.

    let worksRebuildWorkBody(db: Db, workId: Int): Void throws Bubble {
      let bodies = new ListBuilder<String>();
      for (let row of db.query(
        "SELECT body FROM sections WHERE work_id = $1 ORDER BY ordinal ASC",
        worksArgs().n(workId).build(),
      )) {
        bodies.add(row.str("body"));
      }
      let joined = sysJoin(bodies.toList(), "\n\n");
      db.exec(
        "UPDATE works SET body = $1, word_count = $2, updated_at = $3 WHERE id = $4",
        worksArgs().s(joined).n(wordCount(joined)).s(sysUtcNow()).n(workId).build(),
      );
    }

## Corrections

What the writer has already told us. `misread` is a fact the reader got wrong
(never assert it again); `ruling` is the writer's decision.

    export class CorrectionParams(public workId: Int, public kind: String, public about: String) {
      public var ruling: String? = null;
      public var sectionOrdinal: Int? = null;
    }

    export class CorrectionResult(public correction: Correction?, public errors: List<FieldError>) {}

    export let worksRecordCorrection(db: Db, p: CorrectionParams): CorrectionResult throws Bubble {
      let errors = new ListBuilder<FieldError>();
      if (worksIsBlank(p.kind)) {
        errors.add(new FieldError("kind", "can't be blank"));
      } else if (!worksIn(["misread", "ruling"], p.kind)) {
        errors.add(new FieldError("kind", "is invalid"));
      }
      if (worksIsBlank(p.about)) {
        errors.add(new FieldError("about", "can't be blank"));
      } else if (sysGraphemeLength(p.about) > 1000) {
        errors.add(new FieldError("about", "should be at most 1000 character(s)"));
      }
      let ruling = p.ruling;
      if (ruling != null) {
        if (sysGraphemeLength(ruling) > 1000) {
          errors.add(new FieldError("ruling", "should be at most 1000 character(s)"));
        }
      }
      if (errors.length > 0) { return new CorrectionResult(null, errors.toList()); }
      let id = db.insert(
        "INSERT INTO corrections (work_id, kind, about, ruling, section_ordinal) VALUES ($1, $2, $3, $4, $5)",
        worksArgs().n(p.workId).s(p.kind).s(p.about).s(ruling).no(p.sectionOrdinal).build(),
      );
      let row = db.one(
        "SELECT ${correctionColumns} FROM corrections WHERE id = $1",
        worksArgs().n(id).build(),
      );
      if (row != null) {
        new CorrectionResult(Correction.fromRow(row), [])
      } else {
        bubble()
      }
    }

Newest first.

    export let worksListCorrections(db: Db, workId: Int): List<Correction> throws Bubble {
      let out = new ListBuilder<Correction>();
      for (let row of db.query(
        "SELECT ${correctionColumns} FROM corrections WHERE work_id = $1 ORDER BY id DESC",
        worksArgs().n(workId).build(),
      )) {
        out.add(Correction.fromRow(row));
      }
      out.toList()
    }

## Attachments

Something a draft carries besides its prose, that can be quoted from: usually
a patch.

    export class AttachmentResult(public attachment: Attachment?, public errors: List<FieldError>) {}

The kind is detected rather than declared. A kind of `"text"` (or none) becomes
`"diff"` when the content, leading whitespace aside, starts with `diff --git`
or the name ends in `.patch` or `.diff`; any other kind is left alone and must
be `diff` or `text`. `byte_size` is the UTF-8 length of the content. A second
attachment with the same name on the same work is refused with
`has already been taken` on `work_id`, where Ecto's `unique_constraint` puts
it.

    let worksKindOr(kind: String?): String {
      if (kind != null) {
        if (kind.isEmpty) { "text" } else { kind }
      } else {
        "text"
      }
    }

    export let worksAttach(db: Db, workId: Int, name: String, kind: String?, content: String): AttachmentResult throws Bubble {
      var chosen = worksKindOr(kind);
      if (chosen == "text") {
        if (worksStartsWith(worksTrimLeading(content), "diff --git")) {
          chosen = "diff";
        } else if (worksEndsWith(name, ".patch") || worksEndsWith(name, ".diff")) {
          chosen = "diff";
        }
      }
      let errors = new ListBuilder<FieldError>();
      if (worksIsBlank(name)) { errors.add(new FieldError("name", "can't be blank")); }
      if (worksIsBlank(content)) { errors.add(new FieldError("content", "can't be blank")); }
      if (!worksIn(["diff", "text"], chosen)) { errors.add(new FieldError("kind", "is invalid")); }
      if (errors.length > 0) { return new AttachmentResult(null, errors.toList()); }
      let taken = db.one(
        "SELECT 1 AS taken FROM work_attachments WHERE work_id = $1 AND name = $2",
        worksArgs().n(workId).s(name).build(),
      );
      if (taken != null) {
        return new AttachmentResult(null, [new FieldError("work_id", "has already been taken")]);
      }
      let id = db.insert(
        "INSERT INTO work_attachments (work_id, name, kind, content, byte_size) VALUES ($1, $2, $3, $4, $5)",
        worksArgs().n(workId).s(name).s(chosen).s(content).n(sysByteLength(content)).build(),
      );
      let row = db.one(
        "SELECT ${attachmentColumns} FROM work_attachments WHERE id = $1",
        worksArgs().n(id).build(),
      );
      if (row != null) {
        new AttachmentResult(Attachment.fromRow(row), [])
      } else {
        bubble()
      }
    }

In the order they were attached.

    export let worksListAttachments(db: Db, workId: Int): List<Attachment> throws Bubble {
      let out = new ListBuilder<Attachment>();
      for (let row of db.query(
        "SELECT ${attachmentColumns} FROM work_attachments WHERE work_id = $1 ORDER BY id ASC",
        worksArgs().n(workId).build(),
      )) {
        out.add(Attachment.fromRow(row));
      }
      out.toList()
    }

    export let worksGetAttachment(db: Db, workId: Int, name: String): Attachment? throws Bubble {
      let row = db.one(
        "SELECT ${attachmentColumns} FROM work_attachments WHERE work_id = $1 AND name = $2",
        worksArgs().n(workId).s(name).build(),
      );
      if (row == null) { null } else { Attachment.fromRow(row) }
    }

    let worksStartsWith(s: String, prefix: String): Boolean {
      var i = String.begin;
      var j = String.begin;
      while (prefix.hasIndex(j)) {
        if (!s.hasIndex(i) || s[i] != prefix[j]) { return false; }
        i = s.next(i);
        j = prefix.next(j);
      }
      true
    }

    let worksEndsWith(s: String, suffix: String): Boolean {
      var i = s.end;
      var j = suffix.end;
      while (j > String.begin) {
        if (i <= String.begin) { return false; }
        i = s.prev(i);
        j = suffix.prev(j);
        if (s[i] != suffix[j]) { return false; }
      }
      true
    }

## Document summaries

One row per work, written with `insert_or_update`. A field left null is not
changed (on a new row, it takes the column default). The three item lists are
JSON arrays of objects, given as JSON text.

    export class DocumentSummaryParams(public workId: Int) {
      public var summary: String? = null;
      public var throughline: String? = null;
      public var movementsJson: String? = null;
      public var guidelinesJson: String? = null;
      public var tensionsJson: String? = null;
      public var fingerprint: String? = null;
      public var dropped: List<String>? = null;
    }

    export let worksGetDocumentSummary(db: Db, workId: Int): DocumentSummary? throws Bubble {
      let row = db.one(
        "SELECT ${documentSummaryColumns} FROM document_summaries WHERE work_id = $1",
        worksArgs().n(workId).build(),
      );
      if (row == null) { null } else { DocumentSummary.fromRow(row) }
    }

    export let worksSaveDocumentSummary(db: Db, p: DocumentSummaryParams): DocumentSummary throws Bubble {
      let dropped = p.dropped;
      let droppedJson = if (dropped != null) { worksJsonStrings(dropped) } else { null };
      let existing = worksGetDocumentSummary(db, p.workId);
      if (existing == null) {
        db.exec(
          "INSERT INTO document_summaries (work_id, summary, throughline, movements, guidelines, tensions, fingerprint, dropped) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
          worksArgs().n(p.workId).s(p.summary).s(p.throughline)
            .s(worksOr(p.movementsJson, "[]")).s(worksOr(p.guidelinesJson, "[]"))
            .s(worksOr(p.tensionsJson, "[]")).s(p.fingerprint).s(worksOr(droppedJson, "[]")).build(),
        );
      } else {
        db.exec(
          "UPDATE document_summaries SET summary = $1, throughline = $2, movements = $3, guidelines = $4, tensions = $5, fingerprint = $6, dropped = $7, updated_at = $8 WHERE work_id = $9",
          worksArgs().s(worksOr(p.summary, existing.summary))
            .s(worksOr(p.throughline, existing.throughline))
            .s(worksOr(p.movementsJson, existing.movementsJson))
            .s(worksOr(p.guidelinesJson, existing.guidelinesJson))
            .s(worksOr(p.tensionsJson, existing.tensionsJson))
            .s(worksOr(p.fingerprint, existing.fingerprint))
            .s(worksOr(droppedJson, worksJsonStrings(existing.dropped)))
            .s(sysUtcNow()).n(p.workId).build(),
        );
      }
      let saved = worksGetDocumentSummary(db, p.workId);
      if (saved != null) { saved } else { bubble() }
    }

    let worksOr(provided: String?, fallback: String?): String? {
      if (provided != null) { provided } else { fallback }
    }
