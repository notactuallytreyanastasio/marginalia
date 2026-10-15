# The page

`ImportLive.mount/3` and `render/1`: load what the session holds, look at the
import if one is going, and render the step.

    let { Ctx, webRedirect } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { Run } = import("runs/src");
    let { ImporterPull, ImporterHttp } = import("importer/src");

## An import that is going, or has ended

A page that finds its import still running shows the bar, and asks to be
fetched again in two seconds. A page that finds it ended does what
`handle_async(:import)` did, once:

* a run that crashed, or whose row is gone: the sentence under the steps,
  `The import crashed: ...`, on the results step with nothing to show;
* a clean import (a folder, nothing failed to land, nothing could not be
  fetched; skips do not count): the flash `3 drafts imported.` and on to the
  folder's page. A GitHub import with the folder box left empty has no folder
  and so always shows the results;
* anything else: the results step.

What a look at the import came to: a response to send instead of the page, or
the run that is still going.

    class PimLive(public response: Response?, public run: Run?) {}

    let pimCrashed(ctx: Ctx, w: PimWiz, why: String): PimLive throws Bubble {
      w.step = "done";
      w.error = "The import crashed: ${why}";
      pimSaveResult(ctx, "");
      pimSaveWiz(ctx, w);
      new PimLive(null, null)
    }

    let pimConcludeResult(ctx: Ctx, w: PimWiz, r: PimResult, detail: String): PimLive throws Bubble {
      let id = r.folderId;
      if (id != null) {
        if (r.failed.length == 0 && r.missed.length == 0) {
          pimClear(ctx);
          let to = new Pair("info", pimImportedNote(r.created, r.skipped.length));
          return new PimLive(webRedirect(ctx, "/stacks/${id.toString()}", to), null);
        }
      }
      pimSaveResult(ctx, detail);
      w.step = "done";
      w.error = null;
      pimSaveWiz(ctx, w);
      new PimLive(null, null)
    }

    let pimConcludeRun(ctx: Ctx, w: PimWiz, run: Run): PimLive throws Bubble {
      if (run.isRunning()) { return new PimLive(null, run); }
      pimStoreToken(ctx, "");
      let detail = pimOr(run.detail, "");
      let r: PimResult? = if (run.status == "done") { pimResultFrom(detail) } else { null };
      if (r != null) {
        pimConcludeResult(ctx, w, r, detail)
      } else {
        pimCrashed(ctx, w, detail)
      }
    }

    let pimConclude(ctx: Ctx, w: PimWiz): PimLive throws Bubble {
      let run = pimRunOf(ctx, pimRunKey(ctx));
      if (run != null) {
        pimConcludeRun(ctx, w, run)
      } else {
        pimCrashed(ctx, w, "its run is gone.")
      }
    }

`"3/12"`: how far the import has got.

    class PimProgress(public phase: String, public done: Int, public total: Int) {}

    let pimProgressOf(run: Run?): PimProgress {
      if (run != null) {
        let counts = pimOr(run.progress, "0/0").split("/");
        new PimProgress(
          if (pimOr(run.detail, "") == "landing") { "landing" } else { "fetching" },
          pimInt(counts.getOr(0, "0"), 0),
          pimInt(counts.getOr(1, "0"), 0),
        )
      } else {
        new PimProgress("fetching", 0, 0)
      }
    }

## Rendering

The listing is read only on the step that shows it, and the result only on the
one that does.

    let pimViewFor(ctx: Ctx, w: PimWiz, run: Run?): PimView throws Bubble {
      let p = pimProgressOf(run);
      let onPick = w.step == "pick";
      pimViewOf(
        w,
        if (onPick) { pimLoadRows(ctx) } else { [] },
        if (onPick) { pimLoadCounts(ctx) } else { new PimCounts(0, 0, 0) },
        if (w.step == "done") { pimLoadResult(ctx) } else { null },
        p.phase, p.done, p.total,
      )
    }

    export let pimReplyAt(ctx: Ctx, status: Int): Response throws Bubble {
      let w = pimLoadWiz(ctx);
      var run: Run? = null;
      if (w.step == "running") {
        let live = pimConclude(ctx, w);
        let sent = live.response;
        if (sent != null) { return sent; }
        run = live.run;
      }
      let tree = renderImport(ctx, pimViewFor(ctx, w, run));
      pimRender(ctx, tree, null, if (w.step == "running") { 2 } else { null }, status)
    }

    export let pimReply(ctx: Ctx): Response throws Bubble {
      pimReplyAt(ctx, 200)
    }

## GET /import

A page load that is not a poll starts the wizard over, as the mount did, except
on the running step: leaving the page did not stop the import here, and coming
back to it should show where it has got to.

    export let pagesImportPage(ctx: Ctx): Response throws Bubble {
      if (!ctx.isAjax) {
        let w = pimLoadWiz(ctx);
        if (w.step != "running") { pimClear(ctx); }
      }
      pimReply(ctx)
    }

## POST /ev/<event>

    export let pagesImportEventPage(
      ctx: Ctx, event: String, payload: JsonObject, http: ImporterHttp,
      launch: fn (Ctx, String, PimJob): Boolean throws Bubble,
    ): Response throws Bubble {
      pimHandle(ctx, event, payload, http, launch);
      pimReply(ctx)
    }
