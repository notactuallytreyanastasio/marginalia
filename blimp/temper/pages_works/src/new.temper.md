# /works/new: upload a draft

`WorkLive.New` and `WorkController.create`, one page. The form posts
`multipart/form-data` to `POST /works/new` and that is the whole upload: the
LiveView read a file over its socket, and a file cannot ride a JSON event, so
here the plain POST that was once the fallback is the only way, and it takes
the file as well as the pasted text. The browser does the work; no script has
to run.

What is left to events is the box that reads a web page (`fetch`), which
fills the fields below it, plus `validate` (echo what was typed) and `save`
(the same save, for a client that sends the fields as an event).

The few things the LiveView kept in assigns are in the session's UI state, one
key each (`works_new:title`, `:intent`, `:body`, `:url`), so that an event's
re-render does not wipe what a fetch filled in. A page load starts them empty.

    let { Ctx, uiGet, uiPut, uiDelete, webCsrfField, webRedirect, cInputSpec, cInput } = import("webcore/src");
    let { Response, UploadedFile } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, hv, htext, attr, wordCount } = import("html/src");
    let { sysStringTrim, sysByteLength, sysUtf8Downcase, sysUtf8Upcase, sysUtf8Valid, sysGraphemeTake } = import("sys/src");
    let { FieldError } = import("core/src");
    let { workParams, worksCreateWork } = import("works/src");
    let { ImporterHttp, ImporterError, importerFetchPage, importerRealHttp, importerInspect } = import("importer/src");

## State

`error` is the sentence in the bordered box above the form, `fileError` the
one under the file input. The rest is what the fields hold.

    export class WorksNewState(
      public error: String?,
      public fileError: String?,
      public url: String,
      public title: String,
      public intent: String,
      public body: String,
    ) {}

    let pwNewTitleKey(): String { "works_new:title" }
    let pwNewIntentKey(): String { "works_new:intent" }
    let pwNewBodyKey(): String { "works_new:body" }
    let pwNewUrlKey(): String { "works_new:url" }

    let pwUi(ctx: Ctx, key: String): String { pwOr(uiGet(ctx, key), "") }

    export let loadWorksNew(ctx: Ctx): WorksNewState {
      new WorksNewState(
        null, null, pwUi(ctx, pwNewUrlKey()), pwUi(ctx, pwNewTitleKey()),
        pwUi(ctx, pwNewIntentKey()), pwUi(ctx, pwNewBodyKey()),
      )
    }

    let pwClearNew(ctx: Ctx): Void {
      uiDelete(ctx, pwNewTitleKey());
      uiDelete(ctx, pwNewIntentKey());
      uiDelete(ctx, pwNewBodyKey());
      uiDelete(ctx, pwNewUrlKey());
    }

    let pwKeepFields(ctx: Ctx, title: String, intent: String, body: String): Void {
      uiPut(ctx, pwNewTitleKey(), title);
      uiPut(ctx, pwNewIntentKey(), intent);
      uiPut(ctx, pwNewBodyKey(), body);
    }

## Render

The red-ruled sentence above the form, if there is one.

    let pwNewError(error: String?): List<AnyValue> {
      if (error != null) {
        h("div", attr("class", "mt-5 border-l-2 border-[var(--mg-accent)] pl-3 py-1.5 text-[0.85rem]"), htext(error))
      } else { [] }
    }

The box that reads a page off the web. It is a form of its own, above the main
one, because forms do not nest.

    let pwFetchForm(url: String): List<AnyValue> {
      h("form", "${attr("id", "fetch-form")}${attr("phx-submit", "fetch")}${attr("class", "mt-6")}", [
        h("label", "${attr("class", "mg-label block mb-1.5")}${attr("for", "import-url")}", htext("Read it off the web")),
        h("div", attr("class", "flex gap-2 items-start"), [
          hv("input", "${attr("type", "url")}${attr("id", "import-url")}${attr("name", "url")}${attr("value", url)}${attr("placeholder", "https://…")}${attr("class", "flex-1 min-w-0 px-2.5 py-1.5 border border-[var(--mg-rule)] rounded-sm bg-[var(--mg-paper)] text-[0.9rem]")}"),
          h("button", "${attr("type", "submit")}${attr("class", "mg-btn sm shrink-0")}${attr("phx-disable-with", "Reading…")}", htext("Fetch")),
        ]),
        h("p", attr("class", "mg-hint mt-1.5"), htext("The article is pulled out and turned into markdown — headings, lists and links kept, navigation and footers dropped. It fills in the fields below for you to check before uploading.")),
      ])
    }

    let pwTitleField(title: String): List<AnyValue> {
      let spec = cInputSpec("work[title]");
      spec.id = "work_title";
      spec.label = "Title";
      spec.value = title;
      spec.rest = attr("placeholder", "Working title is fine");
      cInput(spec)
    }

    let pwIntentField(intent: String): List<AnyValue> {
      let spec = cInputSpec("work[intent]");
      spec.kind = "textarea";
      spec.id = "work_intent";
      spec.label = "In a sentence or two, what is this supposed to do to a reader?";
      spec.value = intent;
      spec.rest = "${attr("rows", "2")}${attr("placeholder", "Optional — but it's what stops the notes being generic.")}";
      h("div", "", cInput(spec))
    }

    let pwBodyField(body: String): List<AnyValue> {
      let spec = cInputSpec("work[body]");
      spec.kind = "textarea";
      spec.id = "work_body";
      spec.label = "Paste the draft";
      spec.value = body;
      spec.rest = "${attr("rows", "12")}${attr("placeholder", "Paste the whole thing. Chapter headings or markdown headings help it divide the draft correctly.")}";
      cInput(spec)
    }

The file input, in its dashed box, and what is wrong with the file, if
anything.

    let pwFileField(fileError: String?): List<AnyValue> {
      let problem: List<AnyValue> = if (fileError != null) {
        h("p", attr("class", "text-[var(--mg-accent)] text-[0.75rem] mt-1"), htext(fileError))
      } else { [] };
      h("div", "", [
        h("label", "${attr("class", "mg-label block mb-1.5")}${attr("for", "manuscript")}", htext("Attach a file")),
        h("div", attr("class", "border border-dashed border-[var(--mg-rule)] rounded-sm p-5 text-[0.85rem] bg-[var(--mg-card)]"), [
          hv("input", "${attr("type", "file")}${attr("id", "manuscript")}${attr("name", "manuscript")}${attr("accept", ".txt,.md,.markdown,.text")}"),
          problem,
        ]),
      ])
    }

    let pwOrRule(): List<AnyValue> {
      h("div", attr("class", "flex items-center gap-3 text-[var(--mg-dim)]"), [
        hv("hr", attr("class", "flex-1 border-0 border-t border-[var(--mg-rule)]")),
        h("span", attr("class", "mg-label"), htext("or")),
        hv("hr", attr("class", "flex-1 border-0 border-t border-[var(--mg-rule)]")),
      ])
    }

`action` and `enctype` are what make this a form the browser can send by
itself, with the file: the token is a hidden field, as the router checks every
`POST`.

    export let renderWorksNew(ctx: Ctx, s: WorksNewState): List<AnyValue> {
      h("div", attr("class", "mx-auto max-w-2xl px-6 py-10"), [
        h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-2xl font-semibold tracking-tight")}", htext("Upload a draft")),
        h("p", attr("class", "mg-prose mt-2 text-[0.95rem] text-[var(--mg-dim)]"), [
          "Paste it or attach a ",
          h("code", "", htext(".txt")),
          "/",
          h("code", "", htext(".md")),
          " file. Nothing is read until you confirm how it's divided on the next screen.",
        ]),
        pwNewError(s.error),
        pwFetchForm(s.url),
        h("form", "${attr("id", "upload-form")}${attr("action", "/works/new")}${attr("method", "post")}${attr("enctype", "multipart/form-data")}${attr("class", "mt-6 space-y-5")}", [
          webCsrfField(ctx),
          pwTitleField(s.title),
          pwIntentField(s.intent),
          pwFileField(s.fileError),
          pwOrRule(),
          pwBodyField(s.body),
          h("button", "${attr("type", "submit")}${attr("class", "mg-btn")}", htext("Continue")),
        ]),
      ])
    }

## The rules for an upload

Eight million bytes, and four extensions.

    let pwMaxFileBytes(): Int { 8000000 }

    let pwTooBig(): String { "That file is too big (8MB limit)." }
    let pwWrongType(): String { "Only .txt and .md for now." }

    let pwEndsWith(s: String, suffix: String): Boolean {
      let parts = s.split(suffix);
      parts.length > 1 && parts.getOr(parts.length - 1, "x") == ""
    }

    let pwAccepted(filename: String): Boolean {
      let n = sysUtf8Downcase(filename);
      pwEndsWith(n, ".txt") || pwEndsWith(n, ".md") || pwEndsWith(n, ".markdown") || pwEndsWith(n, ".text")
    }

`Path.rootname`: the name without its last extension; a name that is only an
extension stays as it is.

    let pwRootname(filename: String): String {
      let parts = filename.split(".");
      if (parts.length < 2) { return filename; }
      let stem = parts.slice(0, parts.length - 1).join(".") { (p: String): String => p };
      if (stem == "") { filename } else { stem }
    }

What is wrong with an attached file, or null. The file picker's `accept` is a
hint only; the extension is checked here.

    let pwFileProblem(f: UploadedFile): String? {
      if (!pwAccepted(f.filename)) {
        pwWrongType()
      } else if (sysByteLength(f.content) > pwMaxFileBytes()) {
        pwTooBig()
      } else if (!sysUtf8Valid(f.content)) {
        "That file is not text."
      } else { null }
    }

The file the form carried, if the visitor chose one. A browser that sends the
file input with nothing chosen sends it with an empty name: that is no file.

    let pwAttached(files: List<UploadedFile>): UploadedFile? {
      var found: UploadedFile? = null;
      for (var i = 0; i < files.length; ++i) {
        let f = files.getOr(i, new UploadedFile("", "", "", ""));
        if (f.field == "manuscript" && f.filename != "" && found == null) { found = f; }
      }
      found
    }

`first_error` of a refused changeset: `"title should be at most 200
character(s)"` becomes `Title should be at most 200 character(s).`.

    let pwFirstError(errors: List<FieldError>): String {
      if (errors.length == 0) { return "That draft could not be saved."; }
      let e = errors.getOr(0, new FieldError("", ""));
      let raw = "${e.field} ${e.message}";
      let first = sysGraphemeTake(raw, 1);
      let rest = raw.slice(raw.next(String.begin), raw.end);
      "${sysUtf8Upcase(first)}${rest}."
    }

## Saving

What a save came to: the slug of the new draft, or a sentence for the box
above the form, or a sentence for the file input.

    export class WorksNewOutcome(
      public slug: String?,
      public error: String?,
      public fileError: String?,
    ) {}

    let pwRefused(error: String?, fileError: String?): WorksNewOutcome {
      new WorksNewOutcome(null, error, fileError)
    }

`save`. With a file, the file's text is the draft (the pasted text is
ignored) and its name, less the extension, stands in for a blank title.
Without, the pasted text is. `Upload.prepare` and `Works.create_work` do the
rest: they count the words, name the untitled draft and split it in sections.

    let pwSave(ctx: Ctx, title: String, intent: String, body: String, file: UploadedFile?): WorksNewOutcome throws Bubble {
      var useTitle = title;
      var useBody = body;
      if (file != null) {
        let problem = pwFileProblem(file);
        if (problem != null) { return pwRefused(null, problem); }
        if (sysStringTrim(title) == "") { useTitle = pwRootname(file.filename); }
        useBody = file.content;
      }
      let params = workParams(useTitle, useBody);
      params.intent = intent;
      let r = worksCreateWork(ctx.db, ctx.scope, params);
      let made = r.ok;
      if (made != null) {
        new WorksNewOutcome(made.slug, null, null)
      } else if (r.error == "empty") {
        pwRefused("There's no text there yet — paste a draft or attach a file.", null)
      } else if (r.error == "too_long") {
        pwRefused(pwOr(r.message, "That draft is too long."), null)
      } else if (r.error == "no_sections") {
        pwRefused("Couldn't find any text to split into sections.", null)
      } else {
        pwRefused(pwFirstError(r.errors), null)
      }
    }

## POST /works/new

The form as the browser sends it. A draft saved goes to `/works/<slug>`. One
refused comes back as this page, status 422, with what was typed in its boxes
and the reason above the form. A file is not echoed: the browser will not
let a page fill a file input, so the visitor chooses it again.

A body the server cut short (over its limit) has lost its tail, and with it
the fields after the cut: it is the one failure that can be only the file.

    export let pagesWorksCreate(ctx: Ctx): Response throws Bubble {
      let form = ctx.req.form;
      let title = form.getOr("work[title]", "");
      let intent = form.getOr("work[intent]", "");
      let body = form.getOr("work[body]", "");
      if (ctx.req.truncated) {
        let s = new WorksNewState(null, pwTooBig(), "", title, intent, body);
        return pwRender(ctx, "Upload a draft", renderWorksNew(ctx, s), null, 422);
      }
      let out = pwSave(ctx, title, intent, body, pwAttached(ctx.req.files));
      let slug = out.slug;
      if (slug != null) {
        pwClearNew(ctx);
        webRedirect(ctx, "/works/${slug}", null)
      } else {
        let s = new WorksNewState(out.error, out.fileError, "", title, intent, body);
        pwRender(ctx, "Upload a draft", renderWorksNew(ctx, s), null, 422)
      }
    }

## GET /works/new

    export let pagesWorksNewPage(ctx: Ctx): Response throws Bubble {
      if (!ctx.isAjax) { pwClearNew(ctx); }
      pwRender(ctx, "Upload a draft", renderWorksNew(ctx, loadWorksNew(ctx)), null, 200)
    }

## Events

The fields of `work`, from the flat keys the client runtime posts
(`work[title]`) or the nested object a hand-written client may send; the
nested one wins.

    let pwWorkField(payload: JsonObject, field: String): String {
      let flat = pwStr(payload, "work[${field}]");
      let nested = payload.propertyValueOrNull("work");
      if (nested is JsonObject) {
        let v = pwStr(nested, field);
        if (v != "") { v } else { flat }
      } else { flat }
    }

`why/1`: what a failed fetch says.

    let pwWhy(e: ImporterError): String {
      let k = e.kind;
      if (k == "bad_scheme") {
        "That needs to be an http or https address."
      } else if (k == "bad_url") {
        "That does not look like a web address."
      } else if (k == "no_host") {
        "That address has no site in it."
      } else if (k == "private_address") {
        "That address points at a private network, so it will not be fetched."
      } else if (k == "too_little_text") {
        "There was not enough prose on that page to read. A paywall, or a page that builds itself with JavaScript."
      } else if (k == "too_big") {
        "That page is too large."
      } else if (k == "unparseable") {
        "That page could not be read as HTML."
      } else if (k == "http" && e.number == 404) {
        "That page was not found."
      } else if (k == "http") {
        "That site answered with a ${e.number.toString()}."
      } else if (k == "unreachable") {
        "That site could not be reached."
      } else {
        "That did not work: ${importerInspect(e)}"
      }
    }

`URI.parse(url).host || url`: the part between `//` and the next `/`, `?`,
`#` or `:`, less any user info.

    let pwHost(url: String): String {
      let afterScheme = url.split("://");
      if (afterScheme.length < 2) { return url; }
      var rest = afterScheme.getOr(1, "");
      rest = rest.split("/").getOr(0, "");
      rest = rest.split("?").getOr(0, "");
      rest = rest.split("#").getOr(0, "");
      let at = rest.split("@");
      rest = at.getOr(at.length - 1, "");
      rest = rest.split(":").getOr(0, "");
      if (rest == "") { url } else { rest }
    }

`fetch`: ask for the page, then fill the title and the body with what came
back and leave the visitor to check them. The intent is cleared, as the
LiveView's rebuilt form cleared it (a known quirk, kept). The address the
visitor typed stays in its box.

    export let pagesWorksFetch(ctx: Ctx, http: ImporterHttp, payload: JsonObject): Response throws Bubble {
      let url = sysStringTrim(pwStr(payload, "url"));
      if (url == "") {
        return pwRender(ctx, "Upload a draft", renderWorksNew(ctx, loadWorksNew(ctx)), null, 200);
      }
      uiPut(ctx, pwNewUrlKey(), url);
      let res = importerFetchPage(http, url);
      let page = res.page;
      let err = res.error;
      if (page != null) {
        uiPut(ctx, pwNewTitleKey(), page.title);
        uiPut(ctx, pwNewBodyKey(), page.text);
        uiDelete(ctx, pwNewIntentKey());
        let words = wordCount(page.text);
        pwRender(
          ctx, "Upload a draft", renderWorksNew(ctx, loadWorksNew(ctx)),
          new Pair("info", "Read ${words.toString()} words from ${pwHost(page.url)}. Check it over before uploading."), 200,
        )
      } else if (err != null) {
        let s = loadWorksNew(ctx);
        let shown = new WorksNewState(pwWhy(err), null, url, s.title, s.intent, s.body);
        pwRender(ctx, "Upload a draft", renderWorksNew(ctx, shown), null, 200)
      } else {
        console.log("pages_works: fetch of ${url} gave neither a page nor an error");
        bubble()
      }
    }

`validate`: echo what was typed so a re-render does not lose it. No errors are
shown, because nothing has been submitted.

    let pwValidate(ctx: Ctx, payload: JsonObject): Response throws Bubble {
      pwKeepFields(ctx, pwWorkField(payload, "title"), pwWorkField(payload, "intent"), pwWorkField(payload, "body"));
      pwRender(ctx, "Upload a draft", renderWorksNew(ctx, loadWorksNew(ctx)), null, 200)
    }

`save`, as an event: the same rules as the POST, without a file. A draft saved
navigates; one refused re-renders with the reason.

    let pwSaveEvent(ctx: Ctx, payload: JsonObject): Response throws Bubble {
      let title = pwWorkField(payload, "title");
      let intent = pwWorkField(payload, "intent");
      let body = pwWorkField(payload, "body");
      let out = pwSave(ctx, title, intent, body, null);
      let slug = out.slug;
      if (slug != null) {
        pwClearNew(ctx);
        webRedirect(ctx, "/works/${slug}", null)
      } else {
        pwKeepFields(ctx, title, intent, body);
        let s = loadWorksNew(ctx);
        let shown = new WorksNewState(out.error, out.fileError, s.url, s.title, s.intent, s.body);
        pwRender(ctx, "Upload a draft", renderWorksNew(ctx, shown), null, 200)
      }
    }

    export let pagesWorksNewEventWith(ctx: Ctx, http: ImporterHttp, event: String, payload: JsonObject): Response throws Bubble {
      if (event == "fetch") {
        pagesWorksFetch(ctx, http, payload)
      } else if (event == "validate") {
        pwValidate(ctx, payload)
      } else if (event == "save") {
        pwSaveEvent(ctx, payload)
      } else {
        pwUnhandledEvent("/works/new", event)
      }
    }

    export let pagesWorksNewEvent(ctx: Ctx, event: String, payload: JsonObject): Response throws Bubble {
      pagesWorksNewEventWith(ctx, importerRealHttp(1), event, payload)
    }
