# /stacks/:id/story

`StackLive.Story`: the longform telling, read as one thing. Every part carries
the steps it tells, so a reader who wants the detail behind a paragraph can
leave for it; this page is the argument and the step pages are the evidence.
The page is static: no run, no polling.

Markdown goes through `markdownToHtml`, which keeps a newline as a line break
(MDEx's `hardbreaks`) and writes no raw HTML.

    let { Ctx, webRedirect } = import("webcore/src");
    let { Response, Match } = import("http/src");
    let { JsonObject } = import("std/json");
    let { Folder, foldersGetFolderOrNull, foldersParseId } = import("folders/src");
    let {
      StackStory, StackStep, StoryMovement, stacksGetStory, stacksListSteps, stacksStoryCurrent, stacksToDraft,
    } = import("stacks/src");
    let { h, htext, hraw, attr, markdownToHtml } = import("html/src");
    let { sysJoin } = import("sys/src");

## State

`steps` is the folder's steps in ordinal order, to look a capability up by
number for the link titles.

    export class PagesStacksStoryState(
      public folder: Folder,
      public story: StackStory,
      public steps: List<StackStep>,
      public stale: Boolean,
    ) {}

    export let loadStacksStory(ctx: Ctx, folder: Folder, story: StackStory): PagesStacksStoryState throws Bubble {
      new PagesStacksStoryState(
        folder, story, stacksListSteps(ctx.db, folder.id),
        !stacksStoryCurrent(ctx.db, story, folder.id),
      )
    }

## Render

`cap`: the capability of step `n`, or `step n` when there is none.

    let pkCap(steps: List<StackStep>, n: Int): String {
      var found = "step ${n.toString()}";
      for (let s of steps) {
        if (s.ordinal == n) { found = pkOr(s.capability, found); }
      }
      found
    }

    let pkPlural(n: Int): String { if (n == 1) { "" } else { "s" } }

    let pkMarkdown(md: String?): List<AnyValue> {
      hraw(markdownToHtml(pkOr(md, "")))
    }

    let pkMovementSteps(folderId: Int, steps: List<StackStep>, m: StoryMovement): List<AnyValue> {
      if (m.steps.length == 0) { return []; }
      h("nav", attr("class", "st-move-steps"), [
        h("span", attr("class", "mg-label"), htext("from")), "\n",
        m.steps.map { (n: Int): List<AnyValue> =>
          [h("a", "${attr("href", "/stacks/${folderId.toString()}/${n.toString()}")}${attr("title", pkCap(steps, n))}", htext(n.toString())), "\n"]
        },
      ])
    }

    let pkMovement(folderId: Int, steps: List<StackStep>, i: Int, m: StoryMovement): List<AnyValue> {
      let turn: List<AnyValue> = if (m.turn != "") {
        h("aside", attr("class", "st-turn md st-md"), hraw(markdownToHtml(m.turn)))
      } else { [] };
      h("section", "${attr("id", "move-${i.toString()}")}${attr("class", "st-move")}", [
        h("h2", "", [h("span", attr("class", "n"), htext(i.toString())), htext(m.heading)]),
        h("div", attr("class", "md st-md"), hraw(markdownToHtml(m.prose))),
        turn,
        pkMovementSteps(folderId, steps, m),
      ])
    }

    export let renderStacksStory(ctx: Ctx, state: PagesStacksStoryState): List<AnyValue> {
      let story = state.story;
      let stale: List<AnyValue> = if (state.stale) {
        h("p", attr("class", "cut-stale"), htext("The steps have been re-read since this was composed."))
      } else { [] };
      let n = story.uncovered.length;
      let left: List<AnyValue> = if (n > 0) {
        h("p", attr("class", "cut-stale"), htext("${n.toString()} step${pkPlural(n)} found no place in this telling: ${sysJoin(story.uncovered.map { (x: Int): String => x.toString() }, ", ")}. The composition is incomplete, not the stack."))
      } else { [] };
      let d = story.dropped.length;
      let drops: List<AnyValue> = if (d > 0) {
        h("p", attr("class", "mg-meta st-drops"), htext("${d.toString()} problem${pkPlural(d)} with the composition: ${sysJoin(story.dropped, "; ")}"))
      } else { [] };
      let moves = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < story.movements.length) {
        moves.add(pkMovement(state.folder.id, state.steps, i + 1, story.movements[i]));
        i += 1;
      }
      h("article", attr("class", "st-story"), [
        h("div", attr("class", "mg-meta"), h("a", attr("href", "/stacks/${state.folder.id.toString()}"), htext("← ${state.folder.name}"))),
        h("h1", "", htext(pkOr(story.title, ""))),
        h("p", attr("class", "mg-meta"), [
          h("button", "${attr("phx-click", "to-draft")}${attr("class", "mg-btn sm")}", htext("Open as a draft")), "\n",
          h("span", attr("class", "ml-2"), htext("a copy, read and annotated like any other manuscript")),
        ]),
        stale, left,
        h("div", attr("class", "lede md st-md"), pkMarkdown(story.opening)),
        moves.toList(),
        h("div", attr("class", "st-closing md st-md"), pkMarkdown(story.closing)),
        drops,
      ])
    }

## The folder and the telling of the route

Either absent is the same answer: `No telling for that folder yet.` and back to
the list.

    let pkStoryReply(ctx: Ctx, folder: Folder, story: StackStory, flash: Pair<String, String>?): Response throws Bubble {
      let state = loadStacksStory(ctx, folder, story);
      pkRender(ctx, pkOr(story.title, folder.name), renderStacksStory(ctx, state), flash, null)
    }

    let pkNoTelling(ctx: Ctx): Response throws Bubble {
      webRedirect(ctx, "/stacks", new Pair("error", "No telling for that folder yet."))
    }

    export let pagesStacksStoryPage(ctx: Ctx, idText: String): Response throws Bubble {
      let id = foldersParseId(idText);
      let folder = if (id != null) { foldersGetFolderOrNull(ctx.db, ctx.scope, id) } else { null };
      if (folder != null) {
        let story = stacksGetStory(ctx.db, folder.id);
        if (story != null) { pkStoryReply(ctx, folder, story, null) } else { pkNoTelling(ctx) }
      } else {
        pkNoTelling(ctx)
      }
    }

## Event `to-draft`

`Stacks.to_draft`: a copy of the telling as an ordinary draft, which is not
filed into the stack's own folder. On success the reader is taken to it; on a
refusal the reason, as Elixir's `inspect` of the atom printed it.

    export let pagesStacksStoryEvent(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble {
      if (event != "to-draft") { return pkUnhandledEvent("/stacks/:id/story", event); }
      let id = foldersParseId(match.params.getOr("id", ""));
      let folder = if (id != null) { foldersGetFolderOrNull(ctx.db, ctx.scope, id) } else { null };
      if (folder != null) {
        let story = stacksGetStory(ctx.db, folder.id);
        if (story != null) { pkToDraft(ctx, folder, story) } else { pkNoTelling(ctx) }
      } else {
        pkNoTelling(ctx)
      }
    }

    let pkToDraft(ctx: Ctx, folder: Folder, story: StackStory): Response throws Bubble {
      let draft = stacksToDraft(ctx.db, ctx.scope, folder.id);
      let work = draft.work;
      if (work != null) {
        webRedirect(ctx, "/works/${work.slug}", new Pair("info", "Opened as a draft. Read it the way you would anything else."))
      } else {
        pkStoryReply(ctx, folder, story, new Pair("error", "Could not open it as a draft: :${pkOr(draft.error, "unknown")}"))
      }
    }
