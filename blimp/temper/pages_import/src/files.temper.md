# Files dropped on the page

`handle_event("import_files", ...)`. The live input sent each file over the
socket as soon as it was chosen, listed it with a progress bar and a "remove",
and the submit consumed what had arrived. A JSON event can not carry a file, so
the form is a plain `multipart/form-data` form that posts to `POST /import`
with every file in it: the bytes are in the request, and the landing is made
inside it. There is no list before the send and no progress bar; what the
list's per-file errors said is said after.

    let { Ctx, webRedirect } = import("webcore/src");
    let { Response, UploadedFile } = import("http/src");
    let { sysStringTrim, sysByteLength, sysUtf8Downcase, sysUtf8Valid } = import("sys/src");
    let {
      ImporterDoc, ImporterSilent, importerRootname, importerInNameOrder, importerFolderNameFor,
      importerLandWith,
    } = import("importer/src");

## The rules

Forty files of eight million bytes, with four extensions.

    let pimMaxFiles(): Int { 40 }

    let pimMaxFileBytes(): Int { 8000000 }

    let pimEndsWith(s: String, suffix: String): Boolean {
      let parts = s.split(suffix);
      parts.length > 1 && parts.getOr(parts.length - 1, "x") == ""
    }

    let pimAccepted(filename: String): Boolean {
      let n = sysUtf8Downcase(filename);
      pimEndsWith(n, ".txt") || pimEndsWith(n, ".md") || pimEndsWith(n, ".markdown") || pimEndsWith(n, ".text")
    }

`upload_error`, and the one it could not say: a file that is not text.

    let pimFileProblem(f: UploadedFile): String? {
      if (!pimAccepted(f.filename)) {
        "not a text or markdown file"
      } else if (sysByteLength(f.content) > pimMaxFileBytes()) {
        "over 8 MB"
      } else if (!sysUtf8Valid(f.content)) {
        "not text"
      } else { null }
    }

## What came in

The files of the `docs` field. A file input with nothing chosen is dropped by
the parser, so these are real. The ones that fail a rule are not landed: they
are named afterwards with the rest of what did not go in.

    class PimDropped(public docs: List<ImporterDoc>, public refused: List<Pair<String, String>>) {}

    let pimDropped(files: List<UploadedFile>): PimDropped {
      let docs = new ListBuilder<ImporterDoc>();
      let refused = new ListBuilder<Pair<String, String>>();
      var i = 0;
      while (i < files.length) {
        let f = files[i];
        if (f.field == "docs") {
          let problem = pimFileProblem(f);
          if (problem != null) {
            refused.add(new Pair(f.filename, problem));
          } else {
            docs.add(new ImporterDoc(importerRootname(f.filename), f.content, null));
          }
        }
        i += 1;
      }
      new PimDropped(docs.toList(), refused.toList())
    }

    let pimRefusal(ctx: Ctx, w: PimWiz, sentence: String): Response throws Bubble {
      w.source = "files";
      w.step = "files";
      w.error = sentence;
      pimSaveWiz(ctx, w);
      pimReplyAt(ctx, 422)
    }

## POST /import

`folder` is the box trimmed, and left empty it is named for what the files
share (`chapter-01` to `chapter-07` give `chapter`): a dropped file is never
loose. The documents are filed in the order their names say, not the order a
browser handed them over. A folder that comes out of it with nothing failing and
nothing refused is the end of the wizard: on to the folder's page with a flash.
Anything else shows the results page, with the refused files beside the ones
that failed to land.

    export let pagesImportFiles(ctx: Ctx): Response throws Bubble {
      let form = ctx.req.form;
      if (form.getOr("_form", "") != "files") {
        return webRedirect(ctx, "/import", null);
      }
      let w = pimLoadWiz(ctx);
      let wantNumber = form.getOr("number", "") == "true";
      w.number = wantNumber;
      w.folder = sysStringTrim(form.getOr("folder", ""));
      if (ctx.req.truncated) {
        return pimRefusal(ctx, w, "That was more than the server takes in one upload.");
      }
      let dropped = pimDropped(ctx.req.files);
      if (dropped.docs.length + dropped.refused.length > pimMaxFiles()) {
        return pimRefusal(ctx, w, "more than ${pimMaxFiles().toString()} files");
      }
      if (dropped.docs.length == 0 && dropped.refused.length == 0) {
        return pimRefusal(ctx, w, "No files yet — drop some in.");
      }
      let ordered = importerInNameOrder(dropped.docs);
      let folder = if (w.folder == "" && ordered.length > 0) { importerFolderNameFor(ordered) } else { w.folder };
      w.folder = folder;
      let landed = importerLandWith(ctx.db, ctx.scope, folder, wantNumber, new ImporterSilent(), ordered);
      let result = pimResultOf(landed, []);
      let failed = new ListBuilder<Pair<String, String>>();
      for (var i = 0; i < result.failed.length; ++i) { failed.add(result.failed.getOr(i, new Pair("", ""))); }
      for (var i = 0; i < dropped.refused.length; ++i) { failed.add(dropped.refused.getOr(i, new Pair("", ""))); }
      let id = result.folderId;
      let shown = new PimResult(id, result.created, result.skipped, failed.toList(), []);
      if (id != null) {
        if (failed.length == 0) {
          pimClear(ctx);
          return webRedirect(ctx, "/stacks/${id.toString()}", new Pair("info", pimImportedNote(result.created, result.skipped.length)));
        }
      }
      pimSaveResult(ctx, pimResultJson(shown));
      w.source = "files";
      w.step = "done";
      w.error = null;
      pimSaveWiz(ctx, w);
      pimReplyAt(ctx, 200)
    }

The flash both ways in take: `3 drafts imported.`, or `3 drafts imported, 1
already there and left alone.`

    export let pimImportedNote(created: Int, skipped: Int): String {
      let head = pimCount(created, "draft", "drafts");
      if (skipped > 0) {
        "${head} imported, ${skipped.toString()} already there and left alone."
      } else {
        "${head} imported."
      }
    }
