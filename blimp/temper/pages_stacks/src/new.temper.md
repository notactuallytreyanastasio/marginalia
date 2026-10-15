# /stacks/new

`StackLive.New`: import one strict pull-request chain as a folder of drafts.

The Elixir page started the import with `start_async` and learned how it went
from a message. Here it is a run of its own (`stack-import:<user id>`), and the
page polls it: `data-poll` while the run is going, and the page that finds it
ended does what the message did, a redirect to the new folder with the flash,
or the error under the form.

What the form holds (`repo`, `folder`, `state`) and the error are the session's
UI state, because a change event re-renders the page and the fields must come
back as they were typed. The token is not: it is read from the event that
carries it, handed to the job, and never stored.

    let { Ctx, webCsrfField, webRedirect, uiGet, uiPut, uiDelete, webMeta, webPage } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, hv, htext, attr } = import("html/src");
    let { Run, runsGet } = import("runs/src");
    let { StackRunView, stacksRunView } = import("stacks/src");
    let { sysStringTrim } = import("sys/src");

## State

    export class PagesStacksNewState(
      public repo: String,
      public folder: String,
      public state: String,
      public error: String?,
      public working: Boolean,
      public saved: Int,
    ) {}

    let pkNewRepoKey(): String { "stacks_new:repo" }
    let pkNewFolderKey(): String { "stacks_new:folder" }
    let pkNewStateKey(): String { "stacks_new:state" }
    let pkNewErrorKey(): String { "stacks_new:error" }
    let pkNewRunKey(): String { "stacks_new:run" }

The state as it stands: the form from the session, `working` and the count
from the run row, which says `running` while the job is going.

    export let loadStacksNew(ctx: Ctx, run: Run?): PagesStacksNewState {
      let view: StackRunView? = stacksRunView(run);
      let saved = if (view != null) { view.done } else { 0 };
      new PagesStacksNewState(
        pkOr(uiGet(ctx, pkNewRepoKey()), ""),
        pkOr(uiGet(ctx, pkNewFolderKey()), ""),
        pkOr(uiGet(ctx, pkNewStateKey()), "open"),
        uiGet(ctx, pkNewErrorKey()),
        view != null,
        saved,
      )
    }

## Render

    let pkNewField(label: String, input: List<AnyValue>, extra: List<AnyValue>): List<AnyValue> {
      h("label", attr("class", "mg-field"), [
        "\n",
        h("span", attr("class", "mg-label"), htext(label)), "\n",
        input, "\n",
        extra,
      ])
    }

    let pkNewError(state: PagesStacksNewState): List<AnyValue> {
      let e = state.error;
      if (e != null) { h("p", attr("class", "cut-err"), htext(e)) } else { [] }
    }

    export let renderStacksNew(ctx: Ctx, state: PagesStacksNewState): List<AnyValue> {
      let placeholder = if (state.repo == "") { "defaults to owner/name" } else { state.repo };
      let error = pkNewError(state);
      let saved: List<AnyValue> = if (state.working) {
        h("span", attr("class", "mg-meta"), htext("${state.saved.toString()} document${if (state.saved == 1) { "" } else { "s" }} saved"))
      } else { [] };
      h("div", attr("class", "mx-auto max-w-xl px-6 py-10"), [
        h("div", attr("class", "mg-meta"), h("a", attr("href", "/stacks"), htext("← every method"))),
        h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "mt-2 text-2xl font-semibold tracking-tight")}", htext("Import a stack")),
        h("p", attr("class", "mg-meta mt-2 leading-relaxed"), htext("A stack is pull requests each based on the one before it, so the series reads in order. The order is taken from that chain, not from the numbers — and if the repository is not a stack, this says which pull requests break it rather than importing them in a guessed order.")),
        h("form", "${attr("id", "stack-import")}${attr("method", "post")}${attr("phx-submit", "import")}${attr("phx-change", "form")}${attr("class", "mt-6 space-y-4")}", [
          webCsrfField(ctx),
          pkNewField("Repository",
            hv("input", "${attr("type", "text")}${attr("name", "repo")}${attr("value", state.repo)}${attr("placeholder", "owner/name")}${attr("autocomplete", "off")}${attr("class", "mg-input")}"),
            []),
          pkNewField("GitHub token",
            hv("input", "${attr("type", "password")}${attr("name", "token")}${attr("value", "")}${attr("autocomplete", "off")}${attr("placeholder", "used for this fetch, never stored")}${attr("class", "mg-input")}"),
            h("span", attr("class", "mg-meta"), htext("Needs only read access to the repository. It is used for the request and thrown away."))),
          pkNewField("Folder name",
            hv("input", "${attr("type", "text")}${attr("name", "folder")}${attr("value", state.folder)}${attr("placeholder", placeholder)}${attr("autocomplete", "off")}${attr("class", "mg-input")}"),
            []),
          pkNewField("Which pull requests",
            h("select", "${attr("name", "state")}${attr("class", "mg-select")}", [
              h("option", "${attr("value", "open")}${if (state.state == "open") { " selected" } else { "" }}", htext("Open")),
              h("option", "${attr("value", "all")}${if (state.state == "all") { " selected" } else { "" }}", htext("All, open and closed")),
            ]),
            []),
          error,
          h("div", attr("class", "flex items-center gap-3"), [
            h("button", "${attr("class", "mg-btn")}${attr("type", "submit")}${if (state.working) { " disabled" } else { "" }}", htext(if (state.working) { "Importing…" } else { "Import" })),
            saved,
          ]),
        ]),
        h("p", attr("class", "mg-meta mt-8 leading-relaxed"), [
          htext("If the repository is not a stack, or you only want some of it, "),
          h("a", attr("href", "/import"), htext("import in bulk")),
          htext(" instead: that lists the pull requests first and lets you pick, and asks nothing about the shape they are in."),
        ]),
        h("p", attr("class", "mg-meta mt-4 leading-relaxed"), htext("Importing saves each pull request's description as a draft, in order, in a folder. Nothing is read yet — that is the next three buttons on the folder's page.")),
      ])
    }

## A run that ended since the page last looked

`handle_async(:import, ...)`. The page remembers the run it started as
`<started_at>|running`; a run that has ended while that is what the page holds
is acted on once, and the page then holds `<started_at>|seen`.

* `import|ok:<folder>:<made>:<total>`: flash `Imported {made} documents.` when
  every document was new, else `{made} new, {total - made} already there.`, and
  on to `/stacks/{folder}`.
* `import|error:<text>`: the text under the form.
* anything else on a run that ended (the job bubbled): `The import crashed:
  {detail}`.

Answers the redirect, or null when the page stays.

    let pkNewConcludes(ctx: Ctx, run: Run?): Response? throws Bubble {
      if (run != null) { pkNewConcludesRun(ctx, run) } else { null }
    }

    let pkNewConcludesRun(ctx: Ctx, run: Run): Response? throws Bubble {
      if (run.isRunning()) { return null; }
      let mark = "${pkOr(run.startedAt, "")}|running";
      if (uiGet(ctx, pkNewRunKey()) != mark) { return null; }
      uiPut(ctx, pkNewRunKey(), "${pkOr(run.startedAt, "")}|seen");
      let detail = pkOr(run.detail, "");
      let tail = pkAfterFirst(detail, "|");
      if (run.status == "done" && pkStartsWith(tail, "ok:")) {
        let parts = tail.split(":");
        let id = parts.getOr(1, "");
        let made = do { parts.getOr(2, "0").toInt32() } orelse 0;
        let total = do { parts.getOr(3, "0").toInt32() } orelse 0;
        let note = if (made == total) {
          "Imported ${made.toString()} documents."
        } else {
          "${made.toString()} new, ${(total - made).toString()} already there."
        };
        uiDelete(ctx, pkNewErrorKey());
        webRedirect(ctx, "/stacks/${id}", new Pair("info", note))
      } else if (run.status == "done" && pkStartsWith(tail, "error:")) {
        uiPut(ctx, pkNewErrorKey(), pkAfterFirst(tail, "error:"));
        null
      } else {
        uiPut(ctx, pkNewErrorKey(), "The import crashed: ${detail}");
        null
      }
    }

## The page

    let pkNewReply(ctx: Ctx, flash: Pair<String, String>?): Response throws Bubble {
      let run = pagesStacksRunOf(ctx, pagesStacksImportKey(ctx.scope.userId));
      let done = pkNewConcludes(ctx, run);
      if (done != null) { return done; }
      let state = loadStacksNew(ctx, run);
      let tree = renderStacksNew(ctx, state);
      pkRender(ctx, "Import a stack", tree, flash, if (state.working) { 2 } else { null })
    }

    export let pagesStacksNewPage(ctx: Ctx): Response throws Bubble {
      pkNewReply(ctx, null)
    }

## Events

`form` (`phx-change`): the fields as typed, the error cleared. The token is
not kept.

    let pkNewForm(ctx: Ctx, payload: JsonObject): Void {
      uiPut(ctx, pkNewRepoKey(), pkStr(payload, "repo"));
      uiPut(ctx, pkNewFolderKey(), pkStr(payload, "folder"));
      let state = pkStr(payload, "state");
      uiPut(ctx, pkNewStateKey(), if (state == "") { "open" } else { state });
      uiDelete(ctx, pkNewErrorKey());
    }

`import` (submit): each field trimmed, the repository split on its first `/`.
Two non-empty parts start the job; anything else is
`Write the repository as owner/name.` with the repository kept. A second import
while the first is going is refused (the Elixir ran both): `An import is
already running.`

    let pkNewStart(
      ctx: Ctx, repoRaw: String, tokenRaw: String, folderRaw: String, stateRaw: String,
      importing: fn (Ctx, String, String, String, String, String): Boolean throws Bubble,
    ): Void throws Bubble {
      let repo = pkTrim(repoRaw);
      let token = pkTrim(tokenRaw);
      let folder = pkTrim(folderRaw);
      let state = if (stateRaw == "") { "open" } else { stateRaw };
      let owner = pkBeforeFirst(repo, "/");
      let name = pkAfterFirst(repo, "/");
      if (owner != "" && name != "") {
        uiPut(ctx, pkNewRepoKey(), repo);
        uiPut(ctx, pkNewFolderKey(), folder);
        uiPut(ctx, pkNewStateKey(), state);
        uiDelete(ctx, pkNewErrorKey());
        let started = importing(ctx, owner, name, token, folder, state);
        if (started) {
          let run = pagesStacksRunOf(ctx, pagesStacksImportKey(ctx.scope.userId));
          if (run != null) { uiPut(ctx, pkNewRunKey(), "${pkOr(run.startedAt, "")}|running"); }
        } else {
          uiPut(ctx, pkNewErrorKey(), "An import is already running.");
        }
      } else {
        uiPut(ctx, pkNewRepoKey(), repo);
        uiPut(ctx, pkNewErrorKey(), "Write the repository as owner/name.");
      }
    }

    export let pagesStacksNewEvent(
      ctx: Ctx, event: String, payload: JsonObject,
      importing: fn (Ctx, String, String, String, String, String): Boolean throws Bubble,
    ): Response throws Bubble {
      if (event == "form") {
        pkNewForm(ctx, payload);
        pkNewReply(ctx, null)
      } else if (event == "import") {
        pkNewStart(ctx, pkStr(payload, "repo"), pkStr(payload, "token"), pkStr(payload, "folder"), pkStr(payload, "state"), importing);
        pkNewReply(ctx, null)
      } else {
        pkUnhandledEvent("/stacks/new", event)
      }
    }

## POST /stacks/new

The form without the client runtime: the same fields, posted. A browser that
cannot run the script would otherwise submit the form as a `GET` and put the
token in the address bar. The answer is the page again (a redirect, so a
reload does not post twice).

    export let pagesStacksNewPost(
      ctx: Ctx,
      importing: fn (Ctx, String, String, String, String, String): Boolean throws Bubble,
    ): Response throws Bubble {
      let form = ctx.req.form;
      pkNewStart(
        ctx, form.getOr("repo", ""), form.getOr("token", ""), form.getOr("folder", ""),
        form.getOr("state", ""), importing,
      );
      webRedirect(ctx, "/stacks/new", null)
    }
