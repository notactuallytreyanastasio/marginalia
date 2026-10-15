# Readings: /cuts

`CutLive.Index`. Every folder, depth first, with the reading it has (if any)
and a button that opens one and goes to it. The page does not refresh itself:
a folder being read shows `reading` in its line and the next visit shows the
rest.

    let { Ctx } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject } = import("std/json");
    let { h, htext, attr } = import("html/src");
    let { webRedirect } = import("webcore/src");
    let { Folder, FolderNode, foldersTree } = import("folders/src");
    let { Cut, cutsList, cutsOpenFolderReading } = import("cuts/src");

## State

One line of the page: a folder, how deep it sits, what it holds and the
reading it has. `works` is its own drafts, `subfolders` its child folders,
`count` every draft below it.

    export class CutsIndexRow(
      public folder: Folder,
      public depth: Int,
      public works: Int,
      public subfolders: Int,
      public count: Int,
      public cut: Cut?,
    ) {}

`count` is every reading the user has, whatever its status, and is what the
header prints before "of N folders read".

    export class CutsIndexState(public rows: List<CutsIndexRow>, public count: Int) {}

    let pcCutFor(cuts: List<Cut>, folderId: Int): Cut? {
      var found: Cut? = null;
      for (let c of cuts) {
        if (c.folderId == folderId) { found = c; }
      }
      found
    }

Each folder, then its descendants. The root node has no folder of its own; its
drafts are the unfiled ones and are not a line.

    let pcFlatten(node: FolderNode, cuts: List<Cut>, depth: Int, out: ListBuilder<CutsIndexRow>): Void {
      for (let kid of node.folders) {
        let folder = kid.folder;
        if (folder != null) {
          out.add(new CutsIndexRow(
            folder, depth, kid.works.length, kid.folders.length, kid.count,
            pcCutFor(cuts, folder.id),
          ));
          pcFlatten(kid, cuts, depth + 1, out);
        }
      }
    }

    export let loadCutsIndex(ctx: Ctx): CutsIndexState throws Bubble {
      let cuts = cutsList(ctx.db, ctx.scope);
      let out = new ListBuilder<CutsIndexRow>();
      pcFlatten(foldersTree(ctx.db, ctx.scope), cuts, 0, out);
      new CutsIndexState(out.toList(), cuts.length)
    }

## Render

`padding-left:{depth * 1.4}rem`. The Elixir printed a float (`0.0`, `1.4`,
`2.8`, `4.199999999999999`); this prints the same number to one decimal, which
is what the browser makes of it.

    let pcIndent(depth: Int): String {
      let tenths = depth * 14;
      let whole = (tenths / 10).toString();
      let frac = (tenths % 10).toString();
      "padding-left:${whole}.${frac}rem"
    }

    let pcRowSummary(row: CutsIndexRow): String {
      if (row.subfolders > 0) {
        "${row.subfolders.toString()} folders · ${row.count.toString()} drafts below"
      } else {
        "${row.works.toString()} drafts"
      }
    }

The part of a line after the draft count: the number of through-lines of a
finished reading, or the status of one that is neither finished nor queued.

    let pcRowTail(row: CutsIndexRow): List<AnyValue> {
      let cut = row.cut;
      if (cut != null) {
        if (cut.status == "read") {
          [" ", h("span", "", htext("· ${cut.threads.length.toString()} through-lines"))]
        } else if (cut.status != "draft") {
          [" ", h("span", "", htext("· ${cut.status}"))]
        } else { [] }
      } else { [] }
    }

The name is a link only when a reading exists to go to.

    let pcRowName(row: CutsIndexRow): List<AnyValue> {
      let cut = row.cut;
      if (cut != null) {
        [
          h("span", attr("class", "mg-badge ink mr-2"), htext("read")),
          "\n",
          h("a", "${attr("href", "/cuts/${cut.id.toString()}")}${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-[1.05rem] hover:text-[var(--mg-accent)]")}", htext(row.folder.name)),
        ]
      } else {
        h("span", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-[1.05rem] text-[var(--mg-dim)]")}", htext(row.folder.name))
      }
    }

    let pcIndexRow(row: CutsIndexRow): List<AnyValue> {
      let id = row.folder.id.toString();
      h("div", "${attr("id", "cut-row-${id}")}${attr("class", "cut-row")}${attr("style", pcIndent(row.depth))}", [
        h("div", attr("class", "min-w-0 flex-1"), [
          pcRowName(row),
          h("div", attr("class", "mg-meta mt-0.5"), [
            "\n", htext(pcRowSummary(row)), pcRowTail(row), "\n",
          ]),
        ]),
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "read")}${attr("phx-value-folder", id)}",
          htext(if (row.cut != null) { "read again" } else { "read" })),
      ])
    }

    export let renderCutsIndex(ctx: Ctx, state: CutsIndexState): List<AnyValue> {
      let rows = state.rows;
      [
        h("div", attr("class", "mx-auto max-w-3xl px-6 py-10"), [
          h("div", attr("class", "flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4"), [
            h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-2xl font-semibold tracking-tight")}", htext("Readings")),
            h("span", attr("class", "mg-meta"), htext("${state.count.toString()} of ${rows.length.toString()} folders read")),
            h("a", "${attr("href", "/works")}${attr("class", "mg-btn sm ghost ml-auto")}", htext("Folders")),
          ]),
          if (rows.length == 0) {
            h("p", attr("class", "mg-empty mt-8"), htext("A reading is what a folder says that none of its drafts says alone. Make a folder on the drafts page and there will be something here to read."))
          } else {
            h("p", attr("class", "mg-meta mt-4 leading-relaxed"), htext("Read from the inside out. A folder of folders is read over what its children already found, so reading a case first makes the reading above it worth more."))
          },
          h("div", attr("class", "mg-rows mt-2"), rows.map { (r: CutsIndexRow): List<AnyValue> => pcIndexRow(r) }),
        ]),
      ]
    }

## GET /cuts

    export let pagesCutsIndexPage(ctx: Ctx): Response throws Bubble {
      pcRender(ctx, "Readings", renderCutsIndex(ctx, loadCutsIndex(ctx)), null, null)
    }

## Events

`read` with `folder`: open (or reopen) the folder's one reading, queued, and go
to it; the page there starts the read. A folder that is not the user's is the
flash `That folder is not yours.` and the list stays. A folder that is not a
number is a bug in the caller and stops with a line in the log.

    let pcOpenReading(ctx: Ctx, id: Int): Response throws Bubble {
      let result = cutsOpenFolderReading(ctx.db, ctx.scope, id, null);
      let opened = result.ok;
      if (opened != null) {
        webRedirect(ctx, "/cuts/${opened.id.toString()}", null)
      } else {
        pcRender(ctx, "Readings", renderCutsIndex(ctx, loadCutsIndex(ctx)), null, new Pair("error", "That folder is not yours."))
      }
    }

    export let pagesCutsIndexEvent(ctx: Ctx, event: String, payload: JsonObject): Response throws Bubble {
      if (event == "read") {
        let folderId = pcPayloadInt(payload, "folder");
        if (folderId != null) {
          pcOpenReading(ctx, folderId)
        } else {
          console.log("pages_cuts: /cuts read without a numeric folder");
          bubble()
        }
      } else {
        console.log("pages_cuts: /cuts has no event ${event}");
        bubble()
      }
    }
