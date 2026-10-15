# Works and sections

`Marginalia.Works`, the first half: the manuscripts and their sections.
Everything here is scoped by the user: a writer's draft is theirs, and no path
in this file returns a work without checking who is asking, except
`worksGetBySlug`, where holding the 128-bit link is the permission to read.

Functions take the `Db` first, then the `Scope` where the Elixir took a
`user_id`. A bang function (`worksGetWork`) bubbles; the others answer `null`
or a result class.

    let { Db, DbRow, dbTransaction } = import("db/src");
    let { Scope, User } = import("accounts/src");
    let { segment, Segment, reflowPage, isWrapped, FieldError } = import("core/src");
    let { wordCount } = import("html/src");
    let {
      sysUtcNow, sysRandomToken, sysGraphemeTake, sysGraphemeLength, sysJoin,
    } = import("sys/src");

## Query parameters

A `$1`-style parameter list may hold nulls, and a list literal cannot be typed
`List<String?>` when one element is nullable, so parameters are collected one
at a time.

    class WorksArgs {
      private var items: ListBuilder<String?> = new ListBuilder<String?>();
      public s(v: String?): WorksArgs { items.add(v); this }
      public n(v: Int): WorksArgs { items.add(v.toString()); this }
      public no(v: Int?): WorksArgs {
        if (v != null) { items.add(v.toString()); } else { items.add(null); }
        this
      }
      public build(): List<String?> { items.toList() }
    }

    let worksArgs(): WorksArgs { new WorksArgs() }

## Reading rows into records

    let worksWorksOf(rows: List<DbRow>): List<Work> throws Bubble {
      let out = new ListBuilder<Work>();
      for (let row of rows) { out.add(Work.fromRow(row)); }
      out.toList()
    }

    let worksSectionsOf(rows: List<DbRow>): List<Section> throws Bubble {
      let out = new ListBuilder<Section>();
      for (let row of rows) { out.add(Section.fromRow(row)); }
      out.toList()
    }

## The parameters of a work

The attributes `Work.changeset` casts: title, intent, body, status,
status_detail, first_impression, source_url, collection, collection_role,
baseline_body and derived_from_id. `user_id`, `folder_id`, `slug` and
`word_count` are not castable. `null` means the attribute was not given;
an empty string is given and is stored as NULL (Ecto's `cast` turns `""` into
`nil`), which for `title` and `body` is then the "can't be blank" error.

`reflowWrapped` asks `worksCreateWork` to reflow the body as PDF page text
first when it looks like it (`isWrapped`). The Elixir upload path never did
that (the importers did it before calling `create_work`), so it is off unless
a caller asks.

    export class WorkParams(public title: String?, public body: String?) {
      public var intent: String? = null;
      public var sourceUrl: String? = null;
      public var collection: String? = null;
      public var collectionRole: String? = null;
      public var status: String? = null;
      public var statusDetail: String? = null;
      public var firstImpression: String? = null;
      public var baselineBody: String? = null;
      public var derivedFromId: Int? = null;
      public var reflowWrapped: Boolean = false;
    }

    export let workParams(title: String?, body: String?): WorkParams {
      new WorkParams(title, body)
    }

## The result of a write

Exactly one of `ok` (the stored work) or a problem. `errors` holds the
changeset errors (`error` is `"invalid"`); otherwise `error` is `"empty"` (no
words), `"too_long"` (over the upload limit; `message` is the sentence to show)
or `"no_sections"` (the segmenter found nothing).

    export class WorksResult(
      public ok: Work?,
      public error: String?,
      public errors: List<FieldError>,
      public message: String?,
    ) {}

    let worksWorkOrBubble(w: Work?): Work throws Bubble {
      if (w != null) { w } else { bubble() }
    }

    let worksSectionOrBubble(s: Section?): Section throws Bubble {
      if (s != null) { s } else { bubble() }
    }

    let worksFailed(error: String, errors: List<FieldError>, message: String?): WorksResult {
      new WorksResult(null, error, errors, message)
    }

## Reads

The works a user owns, newest first.

    export let worksListWorks(db: Db, scope: Scope): List<Work> throws Bubble {
      let user = scope.user;
      if (user != null) {
        worksWorksOf(db.query(
          "SELECT ${workColumns} FROM works WHERE user_id = $1 ORDER BY id DESC",
          worksArgs().n(user.id).build(),
        ))
      } else {
        []
      }
    }

A work the given user owns, or null. Ownership is checked here, once.

    export let worksFindWork(db: Db, scope: Scope, id: Int): Work? throws Bubble {
      let user = scope.user;
      if (user != null) {
        let row = db.one(
          "SELECT ${workColumns} FROM works WHERE user_id = $1 AND id = $2",
          worksArgs().n(user.id).n(id).build(),
        );
        if (row == null) { null } else { Work.fromRow(row) }
      } else {
        null
      }
    }

`Marginalia.Works.get_work!/2`: raises `Ecto.NoResultsError` there, bubbles
here.

    export let worksGetWork(db: Db, scope: Scope, id: Int): Work throws Bubble {
      worksWorkOrBubble(worksFindWork(db, scope, id))
    }

A work by its slug, with no ownership check. This is the sharing model: a
draft is unlisted rather than numbered, and the slug is 128 bits. Anything
that spends money or changes the draft must use `worksFindWork`.

    export let worksGetBySlug(db: Db, slug: String?): Work? throws Bubble {
      if (slug != null) {
        let row = db.one(
          "SELECT ${workColumns} FROM works WHERE slug = $1",
          worksArgs().s(slug).build(),
        );
        if (row == null) { null } else { Work.fromRow(row) }
      } else {
        null
      }
    }

A work by id with no ownership check, for the places that already hold a
checked id (a link between two works, a background job).

    export let worksGetById(db: Db, id: Int): Work? throws Bubble {
      let row = db.one(
        "SELECT ${workColumns} FROM works WHERE id = $1",
        worksArgs().n(id).build(),
      );
      if (row == null) { null } else { Work.fromRow(row) }
    }

Whether this user owns this work. A null user owns nothing.

    export let worksIsOwner(work: Work, user: User?): Boolean {
      if (user == null) { false } else { work.userId == user.id }
    }

The public face of a deploy: the drafts of the one account the deploy belongs
to, newest first, and nobody else's. `Accounts.owner()` is the accounts
context's to answer, so the caller passes the owner's id; `null` is "no owner
configured" and yields nothing.

    export let worksPublicDrafts(db: Db, ownerId: Int?): List<Work> throws Bubble {
      if (ownerId != null) {
        worksWorksOf(db.query(
          "SELECT ${workColumns} FROM works WHERE user_id = $1 ORDER BY inserted_at DESC, id ASC",
          worksArgs().n(ownerId).build(),
        ))
      } else {
        []
      }
    }

A public draft by slug, or null. Scoped to the owner's account: without that
check this would serve any draft anybody had ever uploaded.

    export let worksPublicDraft(db: Db, ownerId: Int?, slug: String?): Work? throws Bubble {
      if (ownerId != null) {
        if (slug != null) {
          let row = db.one(
            "SELECT ${workColumns} FROM works WHERE slug = $1 AND user_id = $2",
            worksArgs().s(slug).n(ownerId).build(),
          );
          return if (row == null) { null } else { Work.fromRow(row) };
        }
      }
      null
    }

The summary drafted from this one, if there is one: the newest work whose
`derived_from_id` is `workId`.

    export let worksCondensationOf(db: Db, workId: Int): Work? throws Bubble {
      let row = db.one(
        "SELECT ${workColumns} FROM works WHERE derived_from_id = $1 ORDER BY id DESC LIMIT 1",
        worksArgs().n(workId).build(),
      );
      if (row == null) { null } else { Work.fromRow(row) }
    }

How many works a user has.

    export let worksCountByUser(db: Db, userId: Int): Int throws Bubble {
      let row = db.one("SELECT count(*) AS n FROM works WHERE user_id = $1", worksArgs().n(userId).build());
      if (row == null) { 0 } else { row.int("n") }
    }

## Validation

`Work.changeset`'s rules with Ecto's messages: title and body required
(whitespace counts as blank), title at most 200 characters, status one of the
four. The `looks empty` rule on `word_count` cannot fire for a body that is
not blank (a non-blank body has a word), so it is not repeated here.

    let worksStatuses(): List<String> { ["pending", "reading", "read", "failed"] }

    let worksIn(xs: List<String>, x: String): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i] == x) { return true; }
        i += 1;
      }
      false
    }

    let worksValidate(title: String?, body: String?, status: String?): List<FieldError> {
      let errors = new ListBuilder<FieldError>();
      if (title != null) {
        if (worksIsBlank(title)) {
          errors.add(new FieldError("title", "can't be blank"));
        } else if (sysGraphemeLength(title) > 200) {
          errors.add(new FieldError("title", "should be at most 200 character(s)"));
        }
      } else {
        errors.add(new FieldError("title", "can't be blank"));
      }
      if (body != null) {
        if (worksIsBlank(body)) { errors.add(new FieldError("body", "can't be blank")); }
      } else {
        errors.add(new FieldError("body", "can't be blank"));
      }
      if (status != null) {
        if (!worksIn(worksStatuses(), status)) {
          errors.add(new FieldError("status", "is invalid"));
        }
      }
      errors.toList()
    }

`cast` on one field: not given keeps the old value, `""` is NULL.

    let worksCast(provided: String?, existing: String?): String? {
      if (provided != null) {
        if (provided.isEmpty) { null } else { provided }
      } else {
        existing
      }
    }

The errors `Marginalia.Works.change_work/2` would show for these attributes
over `work` (or over a new work when `work` is null).

    export let worksChangeWork(work: Work?, params: WorkParams): List<FieldError> {
      let title = worksCast(params.title, if (work != null) { work.title } else { null });
      let body = worksCast(params.body, if (work != null) { work.body } else { null });
      let status = worksCast(params.status, if (work != null) { work.status } else { "pending" });
      worksValidate(title, body, status)
    }

## Slugs

Sixteen random bytes, URL-safe base64 without padding: 22 characters. The
first 22 characters of a 32-byte URL-safe token carry 130 bits, so they are
as unguessable as the Elixir's. Minted once and never regenerated: the link
people have must keep working. The unique index is the last word; checking
first and retrying makes a collision a retry instead of a crash.

    let worksMintSlug(db: Db): String throws Bubble {
      var attempt = 0;
      while (attempt < 8) {
        let slug = sysGraphemeTake(sysRandomToken(), 22);
        let taken = db.one("SELECT 1 AS taken FROM works WHERE slug = $1", worksArgs().s(slug).build());
        if (taken == null) { return slug; }
        attempt += 1;
      }
      bubble()
    }

## Create

Create a work and split it into sections in one transaction. The upload rules
run first (`uploadPrepare`: no words, too many words, the default title), then
the segmenter, which is deterministic and never involves a model. The body and
the baseline are the section bodies joined back up, so `baseline + patches ==
body` from the first moment; `word_count` stays the count of the raw upload
(hazard 2 of the spec).

Segmenting happens before anything is written, so the failure that rolls
everything back in Elixir (`no_sections`) here writes nothing at all.

    class WorksMade { public var id: Int = 0; }

    export let worksCreateWork(db: Db, scope: Scope, params: WorkParams): WorksResult throws Bubble {
      let userId = scope.userId;
      let prepared = uploadPrepare(params.title, params.body, params.intent);
      let accepted = prepared.ok;
      if (accepted != null) {
        worksCreateChecked(db, userId, params, accepted)
      } else if (prepared.problem == "too_long") {
        worksFailed("too_long", [], uploadTooLongMessage(prepared.words))
      } else {
        worksFailed("empty", [new FieldError("body", "can't be blank")], null)
      }
    }

    let worksCreateChecked(db: Db, userId: Int, params: WorkParams, accepted: UploadParams): WorksResult throws Bubble {
      let errors = worksValidate(accepted.title, accepted.body, params.status);
      if (errors.length > 0) { return worksFailed("invalid", errors, null); }
      let castStatus = worksCast(params.status, "pending");
      var raw = accepted.body;
      if (params.reflowWrapped && isWrapped(raw)) { raw = reflowPage(raw); }
      let segments = segment(raw);
      if (segments.length == 0) { return worksFailed("no_sections", [], null); }
      let bodies = new ListBuilder<String>();
      for (let s of segments) { bodies.add(s.body); }
      let joined = sysJoin(bodies.toList(), "\n\n");
      let slug = worksMintSlug(db);
      let words = wordCount(raw);
      let made = new WorksMade();
      dbTransaction(db, fn (): Void throws Bubble {
        let id = db.insert(
          "INSERT INTO works (user_id, title, intent, body, word_count, status, status_detail, first_impression, slug, source_url, collection, collection_role, baseline_body, derived_from_id) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)",
          worksArgs().n(userId).s(accepted.title).s(accepted.intent).s(joined).n(words)
            .s(castStatus).s(worksCast(params.statusDetail, null))
            .s(worksCast(params.firstImpression, null)).s(slug)
            .s(worksCast(params.sourceUrl, null)).s(worksCast(params.collection, null))
            .s(worksCast(params.collectionRole, null)).s(joined).no(params.derivedFromId).build(),
        );
        var ordinal = 1;
        for (let s of segments) {
          db.exec(
            "INSERT INTO sections (work_id, ordinal, title, body, word_count, status) VALUES ($1, $2, $3, $4, $5, 'pending')",
            worksArgs().n(id).n(ordinal).s(s.title).s(s.body).n(wordCount(s.body)).build(),
          );
          ordinal += 1;
        }
        made.id = id;
      });
      new WorksResult(worksWorkOrBubble(worksGetById(db, made.id)), null, [], null)
    }

## Update, status, delete

`Work.changeset |> Repo.update`: only the attributes given change; the word
count follows the body; the slug never changes.

    export let worksUpdateWork(db: Db, work: Work, params: WorkParams): WorksResult throws Bubble {
      let errors = worksChangeWork(work, params);
      if (errors.length > 0) { return worksFailed("invalid", errors, null); }
      let title = worksCast(params.title, work.title);
      let body = worksCast(params.body, work.body);
      let status = worksCast(params.status, work.status);
      if (title != null) {
        if (body != null) {
          if (status != null) {
            return worksUpdateChecked(db, work, params, title, body, status);
          }
        }
      }
      bubble()
    }

    let worksUpdateChecked(
      db: Db, work: Work, params: WorkParams, title: String, body: String, status: String,
    ): WorksResult throws Bubble {
      let words = if (params.body != null) { wordCount(body) } else { work.wordCount };
      db.exec(
        "UPDATE works SET title = $1, intent = $2, body = $3, word_count = $4, status = $5, status_detail = $6, first_impression = $7, source_url = $8, collection = $9, collection_role = $10, baseline_body = $11, derived_from_id = $12, updated_at = $13 WHERE id = $14",
        worksArgs().s(title).s(worksCast(params.intent, work.intent)).s(body).n(words)
          .s(status).s(worksCast(params.statusDetail, work.statusDetail))
          .s(worksCast(params.firstImpression, work.firstImpression))
          .s(worksCast(params.sourceUrl, work.sourceUrl))
          .s(worksCast(params.collection, work.collection))
          .s(worksCast(params.collectionRole, work.collectionRole))
          .s(worksCast(params.baselineBody, work.baselineBody))
          .no(if (params.derivedFromId != null) { params.derivedFromId } else { work.derivedFromId })
          .s(sysUtcNow()).n(work.id).build(),
      );
      new WorksResult(worksWorkOrBubble(worksGetById(db, work.id)), null, [], null)
    }

`status_detail` was `varchar(255)` in Postgres and a longer value was rejected
there, killing the read that wrote it (hazard 8). SQLite would store any
length, but a 255-character column is what the pages and the schema were
designed around, so the detail is cut to its first 255 characters here.

    let worksDetailLimit = 255;

Sets `status` and `status_detail` with no validation. The detail replaces the
old one (usually null).

    export let worksSetStatus(db: Db, work: Work, status: String, detail: String?): Work throws Bubble {
      let kept = if (detail != null) { worksTake(detail, worksDetailLimit) } else { null };
      db.exec(
        "UPDATE works SET status = $1, status_detail = $2, updated_at = $3 WHERE id = $4",
        worksArgs().s(status).s(kept).s(sysUtcNow()).n(work.id).build(),
      );
      worksWorkOrBubble(worksGetById(db, work.id))
    }

Delete cascades to the sections, nodes, edges, conversations, events,
corrections, revisions, attachments, summaries and links; a draft derived
from this one keeps existing with `derived_from_id` null.

    export let worksDeleteWork(db: Db, work: Work): Boolean throws Bubble {
      db.exec("DELETE FROM works WHERE id = $1", worksArgs().n(work.id).build()) > 0
    }

Files a work in a folder (or at the top, with null), owner only. A folder that
is not the user's lands the work at the top rather than in someone else's
tree. Answers the moved work, or null when the work is not theirs.

    export let worksMoveToFolder(db: Db, scope: Scope, workId: Int, folderId: Int?): Work? throws Bubble {
      let user = scope.user;
      let work = worksFindWork(db, scope, workId);
      if (user != null) {
        if (work != null) {
          var target: Int? = null;
          if (folderId != null) {
            let mine = db.one(
              "SELECT id FROM folders WHERE id = $1 AND user_id = $2",
              worksArgs().n(folderId).n(user.id).build(),
            );
            if (mine != null) { target = folderId; }
          }
          db.exec(
            "UPDATE works SET folder_id = $1, updated_at = $2 WHERE id = $3",
            worksArgs().no(target).s(sysUtcNow()).n(workId).build(),
          );
          return worksGetById(db, workId);
        }
      }
      null
    }

## Sections

In ordinal order.

    export let worksListSections(db: Db, workId: Int): List<Section> throws Bubble {
      worksSectionsOf(db.query(
        "SELECT ${sectionColumns} FROM sections WHERE work_id = $1 ORDER BY ordinal ASC",
        worksArgs().n(workId).build(),
      ))
    }

    export let worksGetSection(db: Db, workId: Int, ordinal: Int): Section? throws Bubble {
      let row = db.one(
        "SELECT ${sectionColumns} FROM sections WHERE work_id = $1 AND ordinal = $2",
        worksArgs().n(workId).n(ordinal).build(),
      );
      if (row == null) { null } else { Section.fromRow(row) }
    }

    export let worksSectionById(db: Db, id: Int): Section? throws Bubble {
      let row = db.one(
        "SELECT ${sectionColumns} FROM sections WHERE id = $1",
        worksArgs().n(id).build(),
      );
      if (row == null) { null } else { Section.fromRow(row) }
    }

Update the status only (not validated).

    export let worksSetSectionStatus(db: Db, section: Section, status: String): Section throws Bubble {
      db.exec(
        "UPDATE sections SET status = $1, updated_at = $2 WHERE id = $3",
        worksArgs().s(status).s(sysUtcNow()).n(section.id).build(),
      );
      worksSectionOrBubble(worksSectionById(db, section.id))
    }
