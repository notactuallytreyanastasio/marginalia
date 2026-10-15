# /works: the drafts, as a tree

`WorkLive.Index`. Every draft the visitor has, filed in folders they make by
typing a name or by dragging. The drag is the `Tree` hook of `blimp.js`; what
it sends is one event, `move`, and everything else is a button or a form.

There is no socket to keep the page's few private facts in, so the two that
are not in the database live in the session's UI state: which folders the
visitor has collapsed (`works:collapsed`, ids joined by commas) and which one
is being renamed (`works:renaming`). A page load starts both afresh, as the
LiveView's mount did; an event keeps them.

    let { Ctx, uiGet, uiPut, uiDelete, webMeta, webPage } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, hv, htext, attr } = import("html/src");
    let { sysStringTrim, sysJoin } = import("sys/src");
    let {
      Folder, FolderNode, FolderWork, FoldersResult, foldersTree, foldersCreateFolder, foldersRenameFolder,
      foldersMoveFolder, foldersMoveWork, foldersDeleteFolder, foldersBackfill, foldersUnfiledCount,
      foldersParseId, foldersFirstError,
    } = import("folders/src");
    let { worksFindWork, worksDeleteWork } = import("works/src");
    let { StackStepRef, stacksStepsByWork } = import("stacks/src");

## State

`tree` is the whole tree (its root has no folder), `steps` says which drafts
became a step of a method, `unfiled` is how many drafts name a case and sit in
no folder, `collapsed` the folder ids the visitor closed, `renaming` the one
being renamed.

    export class WorksIndexState(
      public tree: FolderNode,
      public steps: Map<Int, StackStepRef>,
      public unfiled: Int,
      public collapsed: List<Int>,
      public renaming: Int?,
    ) {}

    let pwCollapsedKey(): String { "works:collapsed" }
    let pwRenamingKey(): String { "works:renaming" }

The collapsed ids, from their stored text.

    let pwCollapsedIds(raw: String?): List<Int> {
      let out = new ListBuilder<Int>();
      if (raw != null) {
        let parts = raw.split(",");
        for (var i = 0; i < parts.length; ++i) {
          let id = foldersParseId(parts.getOr(i, ""));
          if (id != null) { out.add(id); }
        }
      }
      out.toList()
    }

    let pwIdIn(ids: List<Int>, id: Int): Boolean {
      var found = false;
      for (var i = 0; i < ids.length; ++i) {
        if (ids.getOr(i, -1) == id) { found = true; }
      }
      found
    }

    let pwIdsText(ids: List<Int>): String {
      sysJoin(ids.map { (i: Int): String => i.toString() }, ",")
    }

Every query the mount did.

    export let loadWorksIndex(ctx: Ctx): WorksIndexState throws Bubble {
      new WorksIndexState(
        foldersTree(ctx.db, ctx.scope),
        stacksStepsByWork(ctx.db, ctx.scope),
        foldersUnfiledCount(ctx.db, ctx.scope),
        pwCollapsedIds(uiGet(ctx, pwCollapsedKey())),
        foldersParseId(uiGet(ctx, pwRenamingKey())),
      )
    }

## Render

Indentation is `depth * 1.25 + 0.4` rem for a row and `depth * 1.25 + 0.95`
for the rail of its children; the sums are done in hundredths so that the
text is what Elixir printed for the float (`0.4`, `1.65`, `2.9`).

    let pwRem(hundredths: Int): String {
      let whole = hundredths / 100;
      let frac = hundredths % 100;
      if (frac == 0) {
        whole.toString()
      } else if (frac % 10 == 0) {
        "${whole.toString()}.${(frac / 10).toString()}"
      } else if (frac < 10) {
        "${whole.toString()}.0${frac.toString()}"
      } else {
        "${whole.toString()}.${frac.toString()}"
      }
    }

    let pwRowPad(depth: Int): String { pwRem(depth * 125 + 40) }
    let pwRail(depth: Int): String { pwRem(depth * 125 + 95) }

A draft's row. The badge is `ink` only for a draft that has been read, and its
class keeps the trailing space the template left.

    let pwWorkRow(w: FolderWork, s: WorksIndexState, depth: Int): List<AnyValue> {
      let id = w.id.toString();
      let step: List<AnyValue> = if (s.steps.has(w.id)) {
        let ref = s.steps.getOr(w.id, new StackStepRef(0, 0, 0));
        h("a", "${attr("href", "/stacks/${ref.folderId.toString()}/${ref.ordinal.toString()}")}${attr("class", "mg-btn sm ghost")}${attr("title", "The step of the method this document became")}", htext("step ${ref.ordinal.toString()}"))
      } else { [] };
      h("div", "${attr("id", "work-${id}")}${attr("class", "mg-wrow")}${attr("draggable", "true")}${attr("data-drag-kind", "work")}${attr("data-drag-id", id)}${attr("style", "padding-left:${pwRowPad(depth)}rem")}", [
        h("span", "${attr("class", "mg-grip")}${attr("aria-hidden", "true")}", htext("⠿")),
        h("div", attr("class", "min-w-0 flex-1"), [
          h("a", "${attr("href", "/works/${w.slug}")}${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-[1.1rem] hover:text-[var(--mg-accent)]")}", htext(w.title)),
          h("div", attr("class", "mg-meta mt-0.5"), htext("${w.wordCount.toString()} words")),
        ]),
        h("span", attr("class", if (w.status == "read") { "mg-badge ink" } else { "mg-badge " }), htext(w.status)),
        step,
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "delete")}${attr("phx-value-id", id)}${attr("data-confirm", "Delete this draft, its map and its conversations?")}", htext("delete")),
      ])
    }

The row of a folder being renamed: the field, focused when it first appears,
and Escape on the window cancels.

    let pwRenameForm(f: Folder): List<AnyValue> {
      let id = f.id.toString();
      h("form", "${attr("id", "rename-${id}")}${attr("phx-submit", "rename")}${attr("class", "flex flex-1 items-center gap-2")}", [
        hv("input", "${attr("type", "hidden")}${attr("name", "folder_id")}${attr("value", id)}"),
        hv("input", "${attr("type", "text")}${attr("name", "name")}${attr("value", f.name)}${attr("autocomplete", "off")}${attr("class", "mg-input sm flex-1")}${attr("phx-mounted", "[[\"focus\",{}]]")}${attr("phx-window-keydown", "rename_cancel")}${attr("phx-key", "Escape")}"),
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("type", "submit")}", htext("save")),
      ])
    }

The name, the count and the two tools, when no rename is under way.

    let pwFolderLabel(f: Folder, count: Int): List<AnyValue> {
      let id = f.id.toString();
      [
        h("button", "${attr("type", "button")}${attr("class", "mg-fname")}${attr("phx-click", "toggle")}${attr("phx-value-id", id)}", htext(f.name)),
        h("span", attr("class", "mg-meta"), htext(count.toString())),
        h("span", attr("class", "mg-frow-tools"), [
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "rename_start")}${attr("phx-value-id", id)}", htext("rename")),
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "delete_folder")}${attr("phx-value-id", id)}${attr("data-confirm", "Delete this folder? The drafts in it move up a level, they are not deleted.")}", htext("delete")),
        ]),
      ]
    }

A folder and, inside its own element, everything in it: that is what makes
"not into its own subtree" a question of `contains` for the hook.

    let pwFolderBlock(child: FolderNode, s: WorksIndexState, depth: Int): List<AnyValue> {
      let f = child.folder;
      if (f != null) { pwFolderBlockOf(f, child, s, depth) } else { [] }
    }

    let pwFolderBlockOf(f: Folder, child: FolderNode, s: WorksIndexState, depth: Int): List<AnyValue> {
      let id = f.id.toString();
      let open = !pwIdIn(s.collapsed, f.id);
      let renaming = s.renaming;
      let editing = renaming != null && renaming == f.id;
      let kids: List<AnyValue> = if (open) {
        let empty: List<AnyValue> = if (child.folders.length == 0 && child.works.length == 0) {
          h("p", attr("class", "mg-fempty"), htext("empty — drag a draft here"))
        } else { [] };
        h("div", "${attr("class", "mg-fkids")}${attr("style", "--rail:${pwRail(depth)}rem")}", [
          empty,
          pwLevel(child, s, depth + 1),
        ])
      } else { [] };
      h("div", "${attr("id", "folder-${id}")}${attr("class", "mg-fold")}${attr("draggable", "true")}${attr("data-drag-kind", "folder")}${attr("data-drag-id", id)}", [
        h("div", "${attr("class", "mg-frow")}${attr("data-drop-kind", "folder")}${attr("data-drop-id", id)}${attr("style", "padding-left:${pwRowPad(depth)}rem")}", [
          h("button", "${attr("type", "button")}${attr("class", "mg-twist")}${attr("phx-click", "toggle")}${attr("phx-value-id", id)}${attr("aria-label", if (open) { "Collapse" } else { "Expand" })}", htext(if (open) { "▾" } else { "▸" })),
          if (editing) { pwRenameForm(f) } else { pwFolderLabel(f, child.count) },
        ]),
        kids,
      ])
    }

`level/1`: the child folders, then the drafts that sit directly in the node.

    let pwLevel(node: FolderNode, s: WorksIndexState, depth: Int): List<AnyValue> {
      [
        node.folders.map { (child: FolderNode): List<AnyValue> => pwFolderBlock(child, s, depth) },
        node.works.map { (w: FolderWork): List<AnyValue> => pwWorkRow(w, s, depth) },
      ]
    }

The heading row: the count of every draft, filed or not, the form for a new
folder (its field is always empty, so the server never keeps typed text), and
the two ways in. The field is submitted by `phx-submit`, so no token rides.

    let pwHeading(count: Int): List<AnyValue> {
      h("div", attr("class", "flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4"), [
        h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-2xl font-semibold tracking-tight")}", htext("Your drafts")),
        h("span", attr("class", "mg-meta"), htext(count.toString())),
        h("form", "${attr("id", "new-folder")}${attr("phx-submit", "new_folder")}${attr("class", "ml-auto flex items-center gap-2")}", [
          hv("input", "${attr("type", "text")}${attr("name", "name")}${attr("value", "")}${attr("autocomplete", "off")}${attr("placeholder", "New folder")}${attr("class", "mg-input sm mg-newfolder")}"),
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("type", "submit")}", htext("add folder")),
        ]),
        h("a", "${attr("href", "/import")}${attr("class", "mg-btn sm ghost")}", htext("Import many")),
        h("a", "${attr("href", "/works/new")}${attr("class", "mg-btn")}", htext("Upload a draft")),
      ])
    }

The offer to file drafts by the case they say they belong to: only while
there is something to file.

    let pwTidy(unfiled: Int): List<AnyValue> {
      if (unfiled > 0) {
        h("p", attr("class", "mg-tidy"), [
          "${unfiled.toString()} of these already say which case they belong to. ",
          h("button", "${attr("phx-click", "backfill")}${attr("class", "mg-btn sm ghost")}", htext("file them by case")),
        ])
      } else { [] }
    }

The tree itself, or the empty page. `#tree` is the element the hook is mounted
on; `.mg-tree-root` is the drop zone for "out of every folder".

    let pwTreeBody(s: WorksIndexState): List<AnyValue> {
      if (s.tree.count == 0 && s.tree.folders.length == 0) {
        h("p", attr("class", "mg-empty mt-8"), htext("Nothing here yet. Bring the draft in the drawer."))
      } else {
        h("div", "${attr("id", "tree")}${attr("phx-hook", "Tree")}${attr("class", "mg-tree mt-2")}",
          h("div", "${attr("class", "mg-tree-root")}${attr("data-drop-kind", "folder")}${attr("data-drop-id", "root")}", [
            pwLevel(s.tree, s, 0),
            if (s.tree.folders.length > 0) {
              h("p", attr("class", "mg-tree-hint"), htext("drag a draft onto a folder to file it · drop it out here to unfile it"))
            } else { [] },
          ]),
        )
      }
    }

    export let renderWorksIndex(ctx: Ctx, s: WorksIndexState): List<AnyValue> {
      h("div", attr("class", "mx-auto max-w-4xl px-6 py-10"), [
        pwHeading(s.tree.count),
        pwTidy(s.unfiled),
        pwTreeBody(s),
      ])
    }

## Events

Each returns the flash it wants shown, if any; the page is reloaded and
rendered after it either way (no optimistic UI).

    let pwInfo(text: String): Pair<String, String>? { new Pair("info", text) }
    let pwError(text: String): Pair<String, String>? { new Pair("error", text) }
    let pwNoFlash(): Pair<String, String>? { null }

`new_folder`: a blank name makes nothing; a refused one says why.

    let pwNewFolder(ctx: Ctx, raw: String): Pair<String, String>? throws Bubble {
      let name = sysStringTrim(raw);
      if (name == "") { return null; }
      let r = foldersCreateFolder(ctx.db, ctx.scope, name, null);
      if (r.ok) { null } else { pwError(foldersFirstError(r)) }
    }

`backfill`: "Filed 2 drafts by case." (`draft` for one); nothing to file says
nothing.

    let pwBackfill(ctx: Ctx): Pair<String, String>? throws Bubble {
      var n = -1;
      let ok = do { n = foldersBackfill(ctx.db, ctx.scope); true } orelse false;
      if (!ok || n < 0) {
        pwError("Could not file those.")
      } else if (n == 0) {
        null
      } else {
        pwInfo("Filed ${n.toString()} ${if (n == 1) { "draft" } else { "drafts" }} by case.")
      }
    }

`toggle`: flip a folder in the collapsed set. The database is not touched.

    let pwToggle(ctx: Ctx, rawId: String): Pair<String, String>? {
      let id = foldersParseId(rawId);
      if (id != null) {
        let now = pwCollapsedIds(uiGet(ctx, pwCollapsedKey()));
        if (pwIdIn(now, id)) {
          uiPut(ctx, pwCollapsedKey(), pwIdsText(now.filter { (i: Int): Boolean => i != id }));
        } else {
          let grown = new ListBuilder<Int>();
          for (var i = 0; i < now.length; ++i) { grown.add(now.getOr(i, -1)); }
          grown.add(id);
          uiPut(ctx, pwCollapsedKey(), pwIdsText(grown.toList()));
        }
      }
      null
    }

`rename`: saved, the field goes away; refused, the field stays and the flash
says why; a folder that is not there ends the rename.

    let pwRename(ctx: Ctx, rawId: String, name: String): Pair<String, String>? throws Bubble {
      let id = foldersParseId(rawId);
      if (id != null) { pwRenameOf(ctx, id, name) } else { null }
    }

    let pwRenameOf(ctx: Ctx, id: Int, name: String): Pair<String, String>? throws Bubble {
      let r = foldersRenameFolder(ctx.db, ctx.scope, id, name);
      if (r.ok) {
        uiDelete(ctx, pwRenamingKey());
        null
      } else if (r.error == "not_found") {
        uiDelete(ctx, pwRenamingKey());
        null
      } else if (r.error == "invalid") {
        pwError(foldersFirstError(r))
      } else { null }
    }

`delete_folder`: its drafts and folders move up a level. Any refusal is
silent, as it was.

    let pwDeleteFolder(ctx: Ctx, rawId: String): Pair<String, String>? throws Bubble {
      let id = foldersParseId(rawId);
      if (id != null) {
        let r = foldersDeleteFolder(ctx.db, ctx.scope, id);
        if (r.ok) { pwInfo("Folder gone. What was in it moved up a level.") } else { null }
      } else { null }
    }

`move`, the one event the hook sends: `kind` is `work` or `folder`, `into` a
folder id or `root`. A folder into itself or its own subtree is refused out
loud; a draft into a folder that is not the visitor's lands at the root.

    let pwMove(ctx: Ctx, kind: String, rawId: String, rawInto: String): Pair<String, String>? throws Bubble {
      let id = foldersParseId(rawId);
      if (id != null) { pwMoveOf(ctx, kind, id, foldersParseId(rawInto)) } else { null }
    }

    let pwMoveOf(ctx: Ctx, kind: String, id: Int, into: Int?): Pair<String, String>? throws Bubble {
      if (kind == "work") {
        foldersMoveWork(ctx.db, ctx.scope, id, into);
        null
      } else if (kind == "folder") {
        let r = foldersMoveFolder(ctx.db, ctx.scope, id, into);
        if (r.ok) {
          null
        } else if (r.error == "cycle") {
          pwError("A folder cannot go inside itself.")
        } else if (r.error == "invalid") {
          pwError(foldersFirstError(r))
        } else { null }
      } else {
        console.log("pages_works: move of a ${kind}");
        bubble()
      }
    }

`delete`: a draft that is not theirs is no draft; theirs goes with its map and
its conversations (the foreign keys cascade).

    let pwDeleteWork(ctx: Ctx, rawId: String): Pair<String, String>? throws Bubble {
      let id = foldersParseId(rawId);
      if (id != null) {
        let w = worksFindWork(ctx.db, ctx.scope, id);
        if (w != null) {
          worksDeleteWork(ctx.db, w);
          pwInfo("Deleted.")
        } else { null }
      } else { null }
    }

    export let handleWorksIndex(ctx: Ctx, event: String, payload: JsonObject): Pair<String, String>? throws Bubble {
      if (event == "new_folder") {
        pwNewFolder(ctx, pwStr(payload, "name"))
      } else if (event == "backfill") {
        pwBackfill(ctx)
      } else if (event == "toggle") {
        pwToggle(ctx, pwStr(payload, "id"))
      } else if (event == "rename_start") {
        let id = foldersParseId(pwStr(payload, "id"));
        if (id != null) { uiPut(ctx, pwRenamingKey(), id.toString()); }
        null
      } else if (event == "rename_cancel") {
        uiDelete(ctx, pwRenamingKey());
        null
      } else if (event == "rename") {
        pwRename(ctx, pwStr(payload, "folder_id"), pwStr(payload, "name"))
      } else if (event == "delete_folder") {
        pwDeleteFolder(ctx, pwStr(payload, "id"))
      } else if (event == "move") {
        pwMove(ctx, pwStr(payload, "kind"), pwStr(payload, "id"), pwStr(payload, "into"))
      } else if (event == "delete") {
        pwDeleteWork(ctx, pwStr(payload, "id"))
      } else {
        console.log("pages_works: /works has no event ${event}");
        bubble()
      }
    }

## Answering

A page load starts the view state afresh (nothing collapsed, no rename); a
poll or an event keeps it.

    export let pagesWorksIndexPage(ctx: Ctx): Response throws Bubble {
      if (!ctx.isAjax) {
        if (uiGet(ctx, pwCollapsedKey()) != null) { uiDelete(ctx, pwCollapsedKey()); }
        if (uiGet(ctx, pwRenamingKey()) != null) { uiDelete(ctx, pwRenamingKey()); }
      }
      pwRender(ctx, "Your drafts", renderWorksIndex(ctx, loadWorksIndex(ctx)), null, 200)
    }

    export let pagesWorksIndexEvent(ctx: Ctx, event: String, payload: JsonObject): Response throws Bubble {
      let flash = handleWorksIndex(ctx, event, payload);
      pwRender(ctx, "Your drafts", renderWorksIndex(ctx, loadWorksIndex(ctx)), flash, 200)
    }
