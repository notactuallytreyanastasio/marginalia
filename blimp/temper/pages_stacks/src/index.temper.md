# /stacks

`StackLive.Index`: the folders that can be read forwards, as the method they
embody. No events, no background work.

    let { Ctx, webMeta, webPage } = import("webcore/src");
    let { Response } = import("http/src");
    let { Folder, FolderNode, foldersTree } = import("folders/src");
    let { StackStats, stacksStats } = import("stacks/src");
    let { h, htext, attr } = import("html/src");

## State

One row per folder that holds at least one document directly (a document in a
subfolder counts for the subfolder), the folders in tree order: a parent
before its children, siblings in the order the tree gives them. `depth` is how
far down the tree.

    export class PagesStacksIndexRow(
      public folder: Folder,
      public depth: Int,
      public stats: StackStats,
    ) {}

    let pkFlatten(node: FolderNode, depth: Int, out: ListBuilder<Pair<Folder, Int>>): Void {
      for (let child of node.folders) {
        let f = child.folder;
        if (f != null) {
          out.add(new Pair(f, depth));
          pkFlatten(child, depth + 1, out);
        }
      }
    }

    export let loadStacksIndex(ctx: Ctx): List<PagesStacksIndexRow> throws Bubble {
      let flat = new ListBuilder<Pair<Folder, Int>>();
      pkFlatten(foldersTree(ctx.db, ctx.scope), 0, flat);
      let rows = new ListBuilder<PagesStacksIndexRow>();
      for (let entry of flat.toList()) {
        let stats = stacksStats(ctx.db, ctx.scope, entry.key.id);
        if (stats.documents > 0) { rows.add(new PagesStacksIndexRow(entry.key, entry.value, stats)); }
      }
      rows.toList()
    }

## Render

`padding-left:{depth * 1.4}rem`: the Elixir float, which for depth 3 printed
`4.199999999999999`; here it is the same number to one decimal.

    let pkIndent(depth: Int): String {
      let tenths = depth * 14;
      "${(tenths / 10).toString()}.${(tenths % 10).toString()}"
    }

"No pluralisation logic": `1 documents`, `1 readable folders`.

    let pkIndexRow(r: PagesStacksIndexRow): List<AnyValue> {
      let stats = r.stats;
      let read: List<AnyValue> = if (stats.read > 0) {
        [h("span", "", htext("· ${stats.read.toString()} read")), "\n"]
      } else { [] };
      let pitfalls: List<AnyValue> = if (stats.pitfalls > 0) {
        [h("span", "", htext("· ${stats.pitfalls.toString()} pitfalls")), "\n"]
      } else { [] };
      let stale: List<AnyValue> = if (stats.stale > 0) {
        [h("span", attr("class", "cut-err"), htext("· ${stats.stale.toString()} stale")), "\n"]
      } else { [] };
      let badge: List<AnyValue> = if (stats.read == stats.documents) {
        h("span", attr("class", "mg-badge ink"), htext("read"))
      } else { [] };
      h("div", "${attr("id", "stack-row-${r.folder.id.toString()}")}${attr("class", "cut-row")}${attr("style", "padding-left:${pkIndent(r.depth)}rem")}", [
        h("div", attr("class", "min-w-0 flex-1"), [
          h("a", "${attr("href", "/stacks/${r.folder.id.toString()}")}${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-[1.05rem] hover:text-[var(--mg-accent)]")}", htext(r.folder.name)),
          h("div", attr("class", "mg-meta mt-0.5"), [
            htext("${stats.documents.toString()} documents"), "\n",
            read, pitfalls, stale,
          ]),
        ]),
        badge,
      ])
    }

    export let renderStacksIndex(ctx: Ctx, rows: List<PagesStacksIndexRow>): List<AnyValue> {
      let empty: List<AnyValue> = if (rows.length == 0) {
        h("p", attr("class", "mg-empty mt-8"), htext("Nothing here yet. Put some drafts in a folder and it becomes readable."))
      } else { [] };
      h("div", attr("class", "mx-auto max-w-3xl px-6 py-10"), [
        h("div", attr("class", "flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4"), [
          h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-2xl font-semibold tracking-tight")}", htext("Methods")),
          h("span", attr("class", "mg-meta"), htext("${rows.length.toString()} readable folders")),
          h("a", "${attr("href", "/import")}${attr("class", "mg-btn sm ghost ml-auto")}", htext("Import many")),
          h("a", "${attr("href", "/stacks/new")}${attr("class", "mg-btn sm")}", htext("Import a stack")),
        ]),
        h("p", attr("class", "mg-meta mt-4 leading-relaxed"), [
          htext("A folder of documents that build one thing, read "),
          h("em", "", htext("forwards")),
          htext(": each document told only what the ones before it established. What comes back is what somebody building the same thing would have to do, in order."),
        ]),
        empty,
        h("div", attr("class", "mg-rows mt-2"), rows.map { (r: PagesStacksIndexRow): List<AnyValue> => pkIndexRow(r) }),
      ])
    }

## GET /stacks

    export let pagesStacksIndexPage(ctx: Ctx): Response throws Bubble {
      pkRender(ctx, "Methods", renderStacksIndex(ctx, loadStacksIndex(ctx)), null, null)
    }
