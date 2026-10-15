# Rendering the wizard

`ImportLive.render/1`: one chrome (the title, the four numbered steps, the
sentence under them if there is one) and a body for each of the steps. The
class names and the text are the HEEx's.

What is not here: the live file input with its per-file progress, and the
`working` state of the find button. A file cannot ride a JSON event, so the
files form is a plain `multipart/form-data` form that posts to `/import`
(`files.temper.md`), and nothing is listed before it is sent; and the find is
made inside the request that asks for it, so no page ever shows "Looking…".

    let { Ctx, webCsrfField } = import("webcore/src");
    let { h, hv, htext, attr } = import("html/src");
    let { sysStringReplace, sysGraphemeTake } = import("sys/src");
    let { ImporterPull } = import("importer/src");

## What a render is given

`phase`, `done` and `total` are the running import's progress, read from its
`runs` row; `result` is how the last one ended.

    export class PimView(
      public wiz: PimWiz,
      public rows: List<PimRow>,
      public counts: PimCounts,
      public result: PimResult?,
      public phase: String,
      public done: Int,
      public total: Int,
    ) {}

    export let pimViewOf(
      wiz: PimWiz, rows: List<PimRow>, counts: PimCounts,
      result: PimResult?, phase: String, done: Int, total: Int,
    ): PimView {
      new PimView(wiz, rows, counts, result, phase, done, total)
    }

    let pimChecked(on: Boolean): String { if (on) { " checked" } else { "" } }

    let pimSelected(on: Boolean): String { if (on) { " selected" } else { "" } }

    let pimOn(base: String, on: Boolean): String { if (on) { "${base} on" } else { base } }

`count(1, one, _) = "1 " <> one`.

    export let pimCount(n: Int, one: String, many: String): String {
      if (n == 1) { "1 ${one}" } else { "${n.toString()} ${many}" }
    }

## The chrome

    let pimSteps(step: String): List<AnyValue> {
      h("ol", attr("class", "im-steps"), [
        h("li", attr("class", pimOn("im-step", step == "source")), [h("span", "", htext("1")), htext(" Source")]),
        h("li", attr("class", pimOn("im-step", step == "find" || step == "files")), [h("span", "", htext("2")), htext(" Find")]),
        h("li", attr("class", pimOn("im-step", step == "pick")), [h("span", "", htext("3")), htext(" Choose")]),
        h("li", attr("class", pimOn("im-step", step == "running" || step == "done")), [h("span", "", htext("4")), htext(" Import")]),
      ])
    }

    let pimErrorLine(error: String?): List<AnyValue> {
      if (error != null) { h("p", attr("class", "cut-err mt-4"), htext(error)) } else { [] }
    }

## Step source

    let pimSourceStep(): List<AnyValue> {
      [
        h("p", attr("class", "mg-meta mt-4 leading-relaxed"), htext("Both of these land in a folder and stop. Nothing is read, and nothing costs anything, until you press the buttons on the folder afterwards.")),
        h("div", attr("class", "im-pick"), [
          h("button", "${attr("class", "im-card")}${attr("type", "button")}${attr("phx-click", "source")}${attr("phx-value-to", "github")}", [
            h("span", attr("class", "mg-label"), htext("GitHub")),
            h("b", "", htext("Pull requests")),
            h("span", "", htext("A repository, or a search across several. Filter by title, tick the ones you mean. Each becomes a draft of its description and its commit trail.")),
          ]),
          h("button", "${attr("class", "im-card")}${attr("type", "button")}${attr("phx-click", "source")}${attr("phx-value-to", "files")}", [
            h("span", attr("class", "mg-label"), htext("Files")),
            h("b", "", htext("From this computer")),
            h("span", "", htext("Up to 40 markdown or text files, dropped together. Each one becomes a draft, named after the file.")),
          ]),
        ]),
      ]
    }

## Step find

    let pimMode(w: PimWiz, value: String, title: String, text: String): List<AnyValue> {
      h("label", attr("class", pimOn("im-mode", w.mode == value)), [
        hv("input", "${attr("type", "radio")}${attr("name", "mode")}${attr("value", value)}${pimChecked(w.mode == value)}"),
        h("b", "", htext(title)),
        h("span", "", htext(text)),
      ])
    }

    let pimRepoFields(w: PimWiz): List<AnyValue> {
      [
        h("label", attr("class", "mg-field"), [
          h("span", attr("class", "mg-label"), htext("Repository")),
          hv("input", "${attr("type", "text")}${attr("name", "repo")}${attr("value", w.repo)}${attr("placeholder", "owner/name")}${attr("autocomplete", "off")}${attr("class", "mg-input")}"),
        ]),
        h("label", attr("class", "mg-field"), [
          h("span", attr("class", "mg-label"), htext("Which pull requests")),
          h("select", "${attr("name", "state")}${attr("class", "mg-select")}", [
            h("option", "${attr("value", "all")}${pimSelected(w.state == "all")}", htext("All, open and closed")),
            h("option", "${attr("value", "open")}${pimSelected(w.state == "open")}", htext("Open only")),
            h("option", "${attr("value", "closed")}${pimSelected(w.state == "closed")}", htext("Closed only")),
          ]),
        ]),
      ]
    }

    let pimSearchFields(w: PimWiz): List<AnyValue> {
      h("label", attr("class", "mg-field"), [
        h("span", attr("class", "mg-label"), htext("Search")),
        hv("input", "${attr("type", "text")}${attr("name", "query")}${attr("value", w.query)}${attr("placeholder", "repo:owner/name label:design merged:>2025-01-01")}${attr("autocomplete", "off")}${attr("class", "mg-input")}"),
        h("span", attr("class", "mg-meta"), [
          htext("Passed to GitHub as written, with two exceptions: "),
          h("code", "", htext("is:pr")),
          htext(" is added for you, and "),
          h("code", "", htext("@today-30d")),
          htext(" is turned into the date it means, because GitHub has no relative dates and answers them with a 422. Search is capped at 1000 results and rate limited to 30 a minute, both by GitHub."),
        ]),
      ])
    }

The token's input is never given a value.

    let pimFindStep(ctx: Ctx, w: PimWiz): List<AnyValue> {
      h("form", "${attr("id", "im-find")}${attr("method", "post")}${attr("action", "/import")}${attr("phx-submit", "find")}${attr("phx-change", "form")}${attr("class", "mt-6 space-y-4")}", [
        webCsrfField(ctx),
        h("div", attr("class", "im-modes"), [
          pimMode(w, "repo", "One repository", "Every pull request in it, then filter."),
          pimMode(w, "search", "A search", "GitHub's own query language, across repositories."),
        ]),
        if (w.mode == "repo") { pimRepoFields(w) } else { pimSearchFields(w) },
        h("label", attr("class", "mg-field"), [
          h("span", attr("class", "mg-label"), [htext("GitHub token "), h("em", "", htext("optional"))]),
          hv("input", "${attr("type", "password")}${attr("name", "token")}${attr("value", "")}${attr("autocomplete", "off")}${attr("placeholder", "leave blank for a public repository")}${attr("class", "mg-input")}"),
          h("span", attr("class", "mg-meta"), htext("A public repository needs none, at 60 requests an hour and 10 searches a minute. A token raises that to 5000 an hour and reaches private repositories; read access is enough. It is held for as long as this page is open and written down nowhere.")),
        ]),
        h("div", attr("class", "flex items-center gap-3"), [
          h("button", "${attr("class", "mg-btn")}${attr("type", "submit")}", htext("Find them")),
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("type", "button")}${attr("phx-click", "back")}", htext("back")),
        ]),
      ])
    }

## Step pick

    let pimPatternHelp(w: PimWiz): List<AnyValue> {
      let e = w.patternError;
      if (e != null) {
        h("p", attr("class", "cut-err mt-2"), htext(e))
      } else if (w.how == "regex") {
        h("p", attr("class", "mg-meta mt-2"), htext("Case insensitive, matched against the title. Filters the list and selects what it matches — the boxes below still have the last word."))
      } else {
        h("p", attr("class", "mg-meta mt-2"), [
          htext("Runs over the rows already fetched, so it costs nothing and does not have to be right first time. "),
          h("code", "", htext("state:")), htext(" "),
          h("code", "", htext("is:")), htext(" "),
          h("code", "", htext("draft:")), htext(" "),
          h("code", "", htext("repo:")), htext(" "),
          h("code", "", htext("base:")), htext(" "),
          h("code", "", htext("head:")), htext(" "),
          h("code", "", htext("number:")), htext(", the dates "),
          h("code", "", htext("created:")), htext(" "),
          h("code", "", htext("updated:")), htext(" "),
          h("code", "", htext("merged:")), htext(", and a bare word matches the title. Dates take "),
          h("code", "", htext("@today-30d")), htext(" as well as "),
          h("code", "", htext("2025-08-05")), htext(", and "),
          h("code", "", htext("-")), htext(" in front of anything takes it away."),
        ])
      }
    }

The regex placeholder is the emitted one: Elixir dropped the backslashes of the
source string's unknown escapes.

    let pimPatternForm(w: PimWiz): List<AnyValue> {
      let placeholder = if (w.how == "regex") {
        "a regular expression — ^d+. or fix|revert"
      } else {
        "is:pr state:closed created:>@today-30d"
      };
      h("form", "${attr("id", "im-pattern")}${attr("phx-submit", "pattern")}${attr("phx-change", "pattern")}${attr("class", "mt-6")}", [
        h("span", attr("class", "mg-label"), htext("Narrow this list")),
        h("div", attr("class", "im-filter"), [
          h("select", "${attr("name", "how")}${attr("class", "mg-select sm")}", [
            h("option", "${attr("value", "query")}${pimSelected(w.how != "regex")}", htext("Query")),
            h("option", "${attr("value", "regex")}${pimSelected(w.how == "regex")}", htext("Title regex")),
          ]),
          hv("input", "${attr("type", "text")}${attr("name", "pattern")}${attr("value", w.pattern)}${attr("autocomplete", "off")}${attr("class", "mg-input")}${attr("phx-debounce", "300")}${attr("placeholder", placeholder)}"),
        ]),
        pimPatternHelp(w),
      ])
    }

    let pimOrderForm(w: PimWiz): List<AnyValue> {
      h("form", "${attr("id", "im-order")}${attr("phx-submit", "order")}${attr("phx-change", "order")}${attr("class", "im-order")}", [
        h("span", attr("class", "mg-label"), htext("Order")),
        h("select", "${attr("name", "order")}${attr("class", "mg-select sm")}", [
          h("option", "${attr("value", "oldest")}${pimSelected(w.order != "newest")}", htext("Oldest first, by when it landed")),
          h("option", "${attr("value", "newest")}${pimSelected(w.order == "newest")}", htext("Newest first")),
        ]),
        h("span", attr("class", "mg-meta"), htext("This is the order they are created in, and the order the folder is read forwards in. For a release, oldest first.")),
      ])
    }

    let pimBar(v: PimView): List<AnyValue> {
      let outOf = if (v.rows.length != v.counts.total) { " of ${v.counts.total.toString()}" } else { "" };
      h("div", attr("class", "im-bar"), [
        h("span", "", [
          htext("${pimCount(v.rows.length, "pull request", "pull requests")} shown${outOf} · "),
          h("b", "", htext("${v.counts.chosen.toString()} selected")),
        ]),
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("type", "button")}${attr("phx-click", "all")}", htext("select all shown")),
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("type", "button")}${attr("phx-click", "none")}", htext("clear shown")),
      ])
    }

The row's id is its repository and number, with the slash made a dash: stable
across a re-filter, so the morph keeps the checkbox the visitor is on.

    export let pimRowId(c: ImporterPull): String {
      "im-row-${sysStringReplace(c.repo, "/", "-")}-${c.number.toString()}"
    }

    let pimRow(c: ImporterPull, on: Boolean): List<AnyValue> {
      let merged = c.mergedAt;
      let day: List<AnyValue> = if (merged != null) {
        h("span", attr("class", "d"), htext(sysGraphemeTake(merged, 10)))
      } else { [] };
      let state = if (c.state != null) { pimOr(c.state, "open") } else { "open" };
      let draft: List<AnyValue> = if (c.draft) {
        h("span", attr("class", "s draft"), htext("draft"))
      } else { [] };
      h("li", "${attr("id", pimRowId(c))}${attr("class", pimOn("im-row", on))}", [
        h("label", "", [
          hv("input", "${attr("type", "checkbox")}${pimChecked(on)}${attr("phx-click", "toggle")}${attr("phx-value-key", pimKey(c))}"),
          h("span", attr("class", "n"), htext("#${c.number.toString()}")),
          h("span", attr("class", "t"), htext(c.title)),
          day,
          h("span", attr("class", "s ${state}"), htext(state)),
          draft,
          h("span", attr("class", "r"), htext(c.repo)),
        ]),
      ])
    }

    let pimList(v: PimView): List<AnyValue> {
      let rows = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < v.rows.length) {
        rows.add(pimRow(v.rows[i].pull, v.rows[i].chosen));
        i += 1;
      }
      h("ul", attr("class", "im-list"), rows.toList())
    }

    let pimHint(was: String?, tryThis: String?): List<AnyValue> {
      if (was != null) {
        if (tryThis != null) {
          h("p", attr("class", "mg-meta mt-1"), [
            h("code", "", htext(was)),
            htext(" is that one day. For everything since it, write "),
            h("code", "", htext(tryThis)),
            htext("."),
          ])
        } else { [] }
      } else { [] }
    }

    let pimNothing(v: PimView): List<AnyValue> {
      if (v.rows.length > 0) { return []; }
      let w = v.wiz;
      h("div", attr("class", "mt-3"), [
        h("p", attr("class", "mg-meta"), htext("Nothing matches ${if (w.how == "regex") { "that pattern" } else { "that query" }}.")),
        pimHint(w.hintWas, w.hintTry),
      ])
    }

    let pimCheck(name: String, on: Boolean, lead: String, text: String): List<AnyValue> {
      h("label", attr("class", "im-check"), [
        hv("input", "${attr("type", "hidden")}${attr("name", name)}${attr("value", "false")}"),
        hv("input", "${attr("type", "checkbox")}${attr("name", name)}${attr("value", "true")}${pimChecked(on)}"),
        h("span", "", [h("b", "", htext(lead)), htext(text)]),
      ])
    }

    let pimSettingsForm(v: PimView): List<AnyValue> {
      let w = v.wiz;
      h("form", "${attr("id", "im-settings")}${attr("phx-submit", "import")}${attr("phx-change", "settings")}${attr("class", "mt-6 space-y-4")}", [
        h("label", attr("class", "mg-field"), [
          h("span", attr("class", "mg-label"), htext("Folder")),
          hv("input", "${attr("type", "text")}${attr("name", "folder")}${attr("value", w.folder)}${attr("placeholder", "left empty, named for what the files have in common")}${attr("autocomplete", "off")}${attr("class", "mg-input")}"),
        ]),
        pimCheck("commits", w.commits, "Include the commit trail.", " The description argues; the commits are what was done. One more request each."),
        pimCheck("files", w.files, "Include the files changed.", " Paths and line counts, not diffs — what the change is about, in one glance. One more request each."),
        pimCheck("number", w.number, "Number the titles.", " Only if these are a series meant to be read in order — that is where the stack reader looks for the order."),
        h("div", attr("class", "flex items-center gap-3"), [
          h("button", "${attr("class", "mg-btn")}${attr("type", "submit")}${if (v.counts.chosen == 0) { " disabled" } else { "" }}", htext("Import ${v.counts.chosen.toString()}")),
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("type", "button")}${attr("phx-click", "back")}", htext("back")),
        ]),
      ])
    }

    let pimPickStep(v: PimView): List<AnyValue> {
      [
        pimPatternForm(v.wiz),
        pimOrderForm(v.wiz),
        pimBar(v),
        pimList(v),
        pimNothing(v),
        pimSettingsForm(v),
      ]
    }

## Step files

The folder and number boxes show what was last posted. The file input takes
many, and the extensions are a hint: the server checks them.

    let pimFilesStep(ctx: Ctx, w: PimWiz): List<AnyValue> {
      h("form", "${attr("id", "im-files")}${attr("method", "post")}${attr("action", "/import")}${attr("enctype", "multipart/form-data")}${attr("class", "mt-6 space-y-4")}", [
        webCsrfField(ctx),
        hv("input", "${attr("type", "hidden")}${attr("name", "_form")}${attr("value", "files")}"),
        h("div", attr("class", "im-drop"), [
          h("p", attr("class", "mg-meta"), htext("Drop up to 40 markdown or text files here, or choose them. Each one becomes a draft named after the file.")),
          hv("input", "${attr("type", "file")}${attr("name", "docs")}${attr("id", "im-docs")}${attr("multiple", "")}${attr("accept", ".txt,.md,.markdown,.text")}"),
        ]),
        h("label", attr("class", "mg-field"), [
          h("span", attr("class", "mg-label"), htext("Folder")),
          hv("input", "${attr("type", "text")}${attr("name", "folder")}${attr("value", w.folder)}${attr("placeholder", "left empty, named for what the files have in common")}${attr("autocomplete", "off")}${attr("class", "mg-input")}"),
        ]),
        pimCheck("number", w.number, "Number the titles.", " Only if these are a series meant to be read in order."),
        h("div", attr("class", "flex items-center gap-3"), [
          h("button", "${attr("class", "mg-btn")}${attr("type", "submit")}", htext("Import")),
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("type", "button")}${attr("phx-click", "back")}", htext("back")),
        ]),
      ])
    }

## Step running

`percent({_, 0}) = 0`, else `round(done / total * 100)`.

    export let pimPercent(done: Int, total: Int): Int {
      if (total <= 0) { 0 } else { do { (done * 100 + total / 2) / total } orelse 0 }
    }

    let pimRunningStep(v: PimView): List<AnyValue> {
      h("div", attr("class", "mt-8"), [
        h("p", attr("class", "mg-label"), htext(if (v.phase == "landing") { "Filing them" } else { "Reading them off GitHub" })),
        h("div", attr("class", "im-progress"), h("span", attr("style", "width:${pimPercent(v.done, v.total).toString()}%"), [])),
        h("p", attr("class", "mg-meta mt-2"), htext("${v.done.toString()} of ${v.total.toString()}")),
        h("p", attr("class", "mg-meta mt-6 leading-relaxed"), htext("Leave this page open. The pull requests are read off GitHub one at a time, then filed one at a time, which is the half that writes to the database.")),
      ])
    }

## Step done

    let pimWas(n: Int): String { if (n == 1) { "was" } else { "were" } }

    let pimResultBody(r: PimResult, missed: List<PimMissed>): List<AnyValue> {
      let skipped: List<AnyValue> = if (r.skipped.length > 0) {
        h("p", attr("class", "mg-meta mt-2"), htext("${pimCount(r.skipped.length, "was", "were")} already in the folder under the same title and ${pimWas(r.skipped.length)} left alone."))
      } else { [] };
      let failed: List<AnyValue> = if (r.failed.length > 0) {
        h("div", attr("class", "mt-4"), [
          h("p", attr("class", "mg-label"), htext("Not imported")),
          h("ul", attr("class", "im-bad"), r.failed.map { (f: Pair<String, String>): List<AnyValue> =>
            h("li", "", htext("${f.key} — ${f.value}"))
          }),
        ])
      } else { [] };
      let notFetched: List<AnyValue> = if (missed.length > 0) {
        h("div", attr("class", "mt-4"), [
          h("p", attr("class", "mg-label"), htext("Could not be fetched")),
          h("ul", attr("class", "im-bad"), missed.map { (m: PimMissed): List<AnyValue> =>
            h("li", "", htext("#${m.number.toString()} ${m.title} — ${m.reason}"))
          }),
        ])
      } else { [] };
      let id = r.folderId;
      let openLink: List<AnyValue> = if (id != null) {
        h("a", "${attr("href", "/stacks/${id.toString()}")}${attr("class", "mg-btn")}", htext("Open the folder"))
      } else {
        h("a", "${attr("href", "/works")}${attr("class", "mg-btn")}", htext("Every draft"))
      };
      h("div", attr("class", "mt-8"), [
        h("p", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-xl font-semibold")}", htext("${pimCount(r.created, "draft", "drafts")} imported.")),
        skipped,
        failed,
        notFetched,
        h("div", attr("class", "mt-6 flex items-center gap-3"), [
          openLink,
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("type", "button")}${attr("phx-click", "restart")}", htext("import some more")),
        ]),
      ])
    }

A result with no result is an import that crashed: the sentence under the steps
says so, and the only way on is to start again.

    let pimDoneStep(v: PimView): List<AnyValue> {
      let r = v.result;
      if (r != null) {
        pimResultBody(r, r.missed)
      } else {
        h("div", attr("class", "mt-8"),
          h("button", "${attr("class", "mg-btn")}${attr("type", "button")}${attr("phx-click", "restart")}", htext("start again")))
      }
    }

## The page

    let pimBody(ctx: Ctx, v: PimView): List<AnyValue> throws Bubble {
      let w = v.wiz;
      if (w.step == "source") {
        pimSourceStep()
      } else if (w.step == "find") {
        pimFindStep(ctx, w)
      } else if (w.step == "files") {
        pimFilesStep(ctx, w)
      } else if (w.step == "pick") {
        pimPickStep(v)
      } else if (w.step == "running") {
        pimRunningStep(v)
      } else if (w.step == "done") {
        pimDoneStep(v)
      } else {
        console.log("pages_import: no step called ${w.step}");
        bubble()
      }
    }

    export let renderImport(ctx: Ctx, v: PimView): List<AnyValue> throws Bubble {
      let w = v.wiz;
      h("div", attr("class", "mx-auto max-w-3xl px-6 py-10"), [
        h("div", attr("class", "mg-meta"), h("a", attr("href", "/works"), htext("← every draft"))),
        h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "mt-2 text-2xl font-semibold tracking-tight")}", htext("Import documents")),
        pimSteps(w.step),
        pimErrorLine(w.error),
        pimBody(ctx, v),
      ])
    }
