# One reading: /cuts/:id

`CutLive.Show`. The members that were read as a weave and a row of buttons,
then by status: the read in progress, the failure with a way to retry, or the
thesis, the through-lines and the tensions. Pressing a member keeps only the
claims that rest on it.

A cut still `draft` when the page is fetched is started then: the Elixir
started it on the connected mount only, and a draft opened by its URL stayed
"Reading this folder" with nothing running. Here the first fetch of any kind
starts it, so the URL works and so does the redirect from `/cuts`.

    let { Ctx, webRedirect, webNotFound, webPutFlash, uiGet, uiPut, uiDelete } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject, JsonTextProducer, NullInterchangeContext } = import("std/json");
    let { h, htext, attr } = import("html/src");
    let { Cut, CutMemberRef, CutPick, CutThread, CutTension, CutMember, cutsGet, cutsMembers, cutsIsStale, cutsDelete, cutsSetStatus } = import("cuts/src");
    let { runsGet } = import("runs/src");

## State

`members` is what the weave and the buttons list. `links` are the pairs of
members a through-line or a tension rests on, drawn once the read has landed.
`focus` is the member the claims are filtered to, or null. `stale` is a
finished reading whose folder has changed since.

    export class CutsLink(public a: Int, public b: Int, public kind: String) {}

    export class CutsShowState(
      public cut: Cut,
      public members: List<CutMemberRef>,
      public links: List<CutsLink>,
      public focus: Int?,
      public stale: Boolean,
    ) {}

The focus lives in the session's UI state, one slot per reading.

    let pcFocusKey(cutId: Int): String { "cut:focus:${cutId.toString()}" }

    let pcFocusOf(ctx: Ctx, cutId: Int): Int? {
      let raw = uiGet(ctx, pcFocusKey(cutId));
      if (raw != null) { pcInt(raw) } else { null }
    }

### The members

The members stored by the last finished read; until there is one, the ones the
read would use now. The Elixir computed this in `assign_weave` and then
overwrote it in `render` with the stored list, so a reading that had never
finished showed no weave and no members, though the comment above the weave
says it is drawn "members first, because they are knowable before the answer
is". This is the computed list, kept.

    let pcMembersOf(ctx: Ctx, cut: Cut): List<CutMemberRef> throws Bubble {
      if (cut.members.length > 0) {
        cut.members
      } else {
        cutsMembers(ctx.db, ctx.scope, cut.folderId).map { (m: CutMember): CutMemberRef => m.ref() }
      }
    }

### The links

Only for a finished reading. For each claim, its distinct members; for every
pair `a < b` of those one link, of the kind of the claim's group.

    let pcDistinct(picks: List<CutPick>): List<Int> {
      let out = new ListBuilder<Int>();
      for (let p of picks) {
        var seen = false;
        for (let q of out.toList()) { if (q == p.member) { seen = true; } }
        if (!seen) { out.add(p.member); }
      }
      out.toList()
    }

    let pcPairs(picks: List<CutPick>, kind: String, out: ListBuilder<CutsLink>): Void {
      let nums = pcDistinct(picks);
      for (let a of nums) {
        for (let b of nums) {
          if (a < b) { out.add(new CutsLink(a, b, kind)); }
        }
      }
    }

    let pcLinksOf(cut: Cut): List<CutsLink> {
      let out = new ListBuilder<CutsLink>();
      if (cut.status == "read") {
        for (let t of cut.threads) { pcPairs(t.evidence, "thread", out); }
        for (let t of cut.tensions) { pcPairs(t.evidence, "tension", out); }
      }
      out.toList()
    }

    export let loadCutsShow(ctx: Ctx, cut: Cut): CutsShowState throws Bubble {
      new CutsShowState(
        cut, pcMembersOf(ctx, cut), pcLinksOf(cut), pcFocusOf(ctx, cut.id),
        cutsIsStale(ctx.db, ctx.scope, cut),
      )
    }

## The data the weave hook reads

`Jason.encode!` of the members and the links, in the shapes `Weave.js`
destructures: `{n, kind, id, label, "read?"}` and `{a, b, kind}`.

    let pcMembersJson(members: List<CutMemberRef>): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startArray();
      for (let m of members) {
        p.startObject();
        p.objectKey("n");
        p.int32Value(m.n);
        p.objectKey("kind");
        p.stringValue(m.kind);
        p.objectKey("id");
        p.int32Value(m.id);
        p.objectKey("label");
        p.stringValue(m.label);
        p.objectKey("read?");
        p.booleanValue(m.read);
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

    let pcLinksJson(links: List<CutsLink>): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startArray();
      for (let l of links) {
        p.startObject();
        p.objectKey("a");
        p.int32Value(l.a);
        p.objectKey("b");
        p.int32Value(l.b);
        p.objectKey("kind");
        p.stringValue(l.kind);
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

## Render

The weave: `phx-update="ignore"`, so the client keeps the drawing and takes
only new `data-*` values from each render.

    let pcWeave(state: CutsShowState): List<AnyValue> throws Bubble {
      if (state.members.length > 0) {
        let cut = state.cut;
        h("div", "${attr("id", "weave-${cut.id.toString()}")}${attr("class", "cut-weave")}${attr("phx-hook", "Weave")}${attr("phx-update", "ignore")}${attr("data-status", cut.status)}${attr("data-members", pcMembersJson(state.members))}${attr("data-links", pcLinksJson(state.links))}", [
          h("svg", attr("aria-hidden", "true"), []),
        ])
      } else { [] }
    }

    let pcUnreadFolder(m: CutMemberRef): Boolean { m.kind == "folder" && !m.read }

    let pcMemberButton(m: CutMemberRef, focus: Int?): List<AnyValue> {
      let f = focus;
      let on = if (f != null) { f == m.n } else { false };
      h("button", "${attr("id", "cut-member-${m.n.toString()}")}${attr("type", "button")}${attr("phx-click", "focus")}${attr("phx-value-n", m.n.toString())}${attr("class", if (on) { "cut-member on" } else { "cut-member" })}", [
        h("span", attr("class", "i"), htext(m.n.toString())),
        h("span", attr("class", "l"), htext(m.label)),
        if (pcUnreadFolder(m)) { h("span", attr("class", "u"), htext("not read")) } else { [] },
      ])
    }

    let pcMembers(state: CutsShowState): List<AnyValue> {
      if (state.members.length > 0) {
        var holes = false;
        for (let m of state.members) { if (pcUnreadFolder(m)) { holes = true; } }
        [
          h("div", attr("class", "cut-members"), state.members.map { (m: CutMemberRef): List<AnyValue> => pcMemberButton(m, state.focus) }),
          if (holes) {
            h("p", attr("class", "cut-hole"), htext("Some of these have not been read yet, so this stands on their titles rather than on what they say. Read them first and this will be worth more."))
          } else { [] },
        ]
      } else { [] }
    }

A thread and a tension have one shape; the page draws them with one function.

    class CutsClaim(public claim: String, public evidence: List<CutPick>) {}

    let pcThreadClaims(xs: List<CutThread>): List<CutsClaim> {
      xs.map { (t: CutThread): CutsClaim => new CutsClaim(t.claim, t.evidence) }
    }

    let pcTensionClaims(xs: List<CutTension>): List<CutsClaim> {
      xs.map { (t: CutTension): CutsClaim => new CutsClaim(t.claim, t.evidence) }
    }

`shown/2`: with a focus, the claims with at least one citation of that member.

    let pcRests(item: CutsClaim, focus: Int?): Boolean {
      let f = focus;
      if (f != null) {
        var rests = false;
        for (let ev of item.evidence) { if (ev.member == f) { rests = true; } }
        rests
      } else { true }
    }

The cite line is the member's label, or `member N` when it has none.

    let pcCite(ev: CutPick): String {
      if (ev.label != "") { ev.label } else { "member ${ev.member.toString()}" }
    }

    let pcQuote(ev: CutPick): List<AnyValue> {
      h("blockquote", "", ["\n", htext(ev.quote), "\n", h("cite", "", htext(pcCite(ev))), "\n"])
    }

The id of a claim is its place in the whole list, not in the filtered one, so
it stays the same element when the focus changes what is shown.

    let pcGroup(title: String, kind: String, items: List<CutsClaim>, focus: Int?): List<AnyValue> {
      let shown = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < items.length) {
        let item = items.getOr(i, new CutsClaim("", []));
        if (pcRests(item, focus)) {
          shown.add(h("div", "${attr("id", "cut-claim-${kind}-${i.toString()}")}${attr("class", "cut-claim")}", [
            h("p", attr("class", "c"), htext(item.claim)),
            item.evidence.map { (ev: CutPick): List<AnyValue> => pcQuote(ev) },
          ]));
        }
        i += 1;
      }
      if (shown.length > 0) {
        h("div", "", [h("h2", attr("class", "cut-h"), htext(title)), shown.toList()])
      } else { [] }
    }

    let pcOrEmpty(s: String?): String { if (s != null) { s } else { "" } }

    let pcRead(state: CutsShowState): List<AnyValue> {
      let cut = state.cut;
      [
        if (state.stale) {
          h("p", attr("class", "cut-stale"), [
            "This folder has changed since it was read. ",
            h("button", "${attr("class", "mg-btn sm ghost ml-2")}${attr("phx-click", "again")}", htext("read again")),
          ])
        } else { [] },
        h("h2", attr("class", "cut-h"), htext("Thesis")),
        h("p", attr("class", "cut-thesis"), htext(pcOrEmpty(cut.thesis))),
        pcGroup("Through-lines", "thread", pcThreadClaims(cut.threads), state.focus),
        pcGroup("Tensions", "tension", pcTensionClaims(cut.tensions), state.focus),
        if (pcOrEmpty(cut.notSupported) != "") {
          h("div", "", [
            h("h2", attr("class", "cut-h"), htext("What this does not show")),
            h("p", attr("class", "cut-body"), htext(pcOrEmpty(cut.notSupported))),
          ])
        } else { [] },
      ]
    }

The branch on the status, under the members.

    let pcStatusBody(state: CutsShowState): List<AnyValue> {
      let cut = state.cut;
      if (cut.status == "reading") {
        h("p", attr("class", "cut-working"), htext("Reading this folder. One call, and it is the slow kind."))
      } else if (cut.status == "failed") {
        h("p", attr("class", "cut-err mt-6"), [
          htext(pcOrEmpty(cut.statusDetail)), " ",
          h("button", "${attr("class", "mg-btn sm ghost ml-2")}${attr("phx-click", "again")}", htext("try again")),
        ])
      } else if (cut.status == "read") {
        pcRead(state)
      } else {
        h("p", attr("class", "cut-working"), htext("Queued."))
      }
    }

    let pcDroppedNote(cut: Cut): List<AnyValue> {
      let n = cut.dropped.length;
      if (n > 0) {
        h("span", attr("class", "mg-meta"), htext("${n.toString()} claim${if (n == 1) { "" } else { "s" }} dropped for quotes that could not be found"))
      } else { [] }
    }

    export let renderCutsShow(ctx: Ctx, state: CutsShowState): List<AnyValue> throws Bubble {
      let cut = state.cut;
      let question = pcOrEmpty(cut.question);
      [
        h("div", attr("class", "mx-auto max-w-3xl px-6 py-10"), [
          h("div", attr("class", "mg-meta"), h("a", attr("href", "/cuts"), htext("← every reading"))),
          h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "mt-2 text-2xl font-semibold tracking-tight")}", htext(cut.title)),
          if (question != "") { h("p", attr("class", "cut-ask"), htext(question)) } else { [] },
          pcWeave(state),
          pcMembers(state),
          pcStatusBody(state),
          h("div", attr("class", "mt-10 flex flex-wrap items-center gap-2 border-t border-[var(--mg-rule)] pt-4"), [
            if (cut.status == "read") {
              h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "again")}", htext("read again"))
            } else { [] },
            pcDroppedNote(cut),
            h("button", "${attr("class", "mg-btn sm ghost ml-auto")}${attr("phx-click", "delete")}${attr("data-confirm", "Delete this reading?")}", htext("delete")),
          ]),
        ]),
      ]
    }

The page polls while the read runs and not otherwise.

    let pcPoll(cut: Cut): Int? { if (cut.status == "reading") { 2 } else { null } }

## A read that died

A job that crashed leaves the cut `reading` and its run `crashed`. The
Elixir saw that as the task exiting: the cut became `failed` with the reason
and the flash was `The read crashed.` Here the page notices on its next fetch.

    let pcReconcile(ctx: Ctx, cut: Cut): Cut throws Bubble {
      if (cut.status == "reading") {
        let run = runsGet(ctx.db, "cut:${cut.id.toString()}");
        if (run != null) {
          if (run.status == "crashed") {
            webPutFlash(ctx, "error", "The read crashed.");
            let detail = run.detail;
            return cutsSetStatus(ctx.db, cut, "failed", if (detail != null) { detail } else { "crashed" });
          }
        }
      }
      cut
    }

A cut the user does not have: the flash and the list.

    let pcGone(ctx: Ctx): Response throws Bubble {
      webRedirect(ctx, "/cuts", new Pair("error", "No such reading."))
    }

    let pcReply(ctx: Ctx, cut: Cut, flash: Pair<String, String>?): Response throws Bubble {
      pcRender(ctx, cut.title, renderCutsShow(ctx, loadCutsShow(ctx, cut)), pcPoll(cut), flash)
    }

The reading as the database has it now.

    let pcFresh(ctx: Ctx, cut: Cut): Cut throws Bubble {
      let again = cutsGet(ctx.db, ctx.scope, cut.id);
      if (again != null) { again } else { cut }
    }

    let pcStart(ctx: Ctx, cut: Cut, launch: fn (Ctx, Cut): Void throws Bubble): Cut throws Bubble {
      launch(ctx, cut);
      pcFresh(ctx, cut)
    }

## GET /cuts/:id

A path that is not a number is a 404 (the Elixir's cast error was a 400). The
focus is forgotten on a fresh visit, as a new LiveView had none, and kept
across the poll.

    let pcShowFound(ctx: Ctx, found: Cut, launch: fn (Ctx, Cut): Void throws Bubble): Response throws Bubble {
      if (!ctx.isAjax) { uiDelete(ctx, pcFocusKey(found.id)); }
      var cut: Cut = pcReconcile(ctx, found);
      if (cut.status == "draft") { cut = pcStart(ctx, cut, launch); }
      pcReply(ctx, cut, null)
    }

    let pcShowId(ctx: Ctx, id: Int, launch: fn (Ctx, Cut): Void throws Bubble): Response throws Bubble {
      let found = cutsGet(ctx.db, ctx.scope, id);
      if (found != null) { pcShowFound(ctx, found, launch) } else { pcGone(ctx) }
    }

    export let pagesCutsShowPage(ctx: Ctx, rawId: String, launch: fn (Ctx, Cut): Void throws Bubble): Response throws Bubble {
      let id = pcInt(rawId);
      if (id != null) { pcShowId(ctx, id, launch) } else { webNotFound(ctx) }
    }

## Events

`again` starts a read; `focus` with `n` toggles the filter; `delete` removes
the reading and goes to the list. The page they came from is the cut's, found
again for the user: another user's id is `No such reading.` as on a GET.

    let pcFocus(ctx: Ctx, cut: Cut, payload: JsonObject): Response throws Bubble {
      let n = pcPayloadInt(payload, "n");
      if (n != null) {
        let current = pcFocusOf(ctx, cut.id);
        if (current != null && current == n) {
          uiDelete(ctx, pcFocusKey(cut.id));
        } else {
          uiPut(ctx, pcFocusKey(cut.id), n.toString());
        }
        pcReply(ctx, cut, null)
      } else {
        console.log("pages_cuts: /cuts/${cut.id.toString()} focus without a numeric n");
        bubble()
      }
    }

    let pcDelete(ctx: Ctx, cut: Cut): Response throws Bubble {
      cutsDelete(ctx.db, cut);
      uiDelete(ctx, pcFocusKey(cut.id));
      webRedirect(ctx, "/cuts", new Pair("info", "Reading deleted."))
    }

    let pcShowEventOf(ctx: Ctx, cut: Cut, event: String, payload: JsonObject, launch: fn (Ctx, Cut): Void throws Bubble): Response throws Bubble {
      if (event == "again") {
        pcReply(ctx, pcStart(ctx, cut, launch), null)
      } else if (event == "focus") {
        pcFocus(ctx, cut, payload)
      } else if (event == "delete") {
        pcDelete(ctx, cut)
      } else {
        console.log("pages_cuts: /cuts/:id has no event ${event}");
        bubble()
      }
    }

    let pcShowEventId(ctx: Ctx, id: Int, event: String, payload: JsonObject, launch: fn (Ctx, Cut): Void throws Bubble): Response throws Bubble {
      let found = cutsGet(ctx.db, ctx.scope, id);
      if (found != null) { pcShowEventOf(ctx, found, event, payload, launch) } else { pcGone(ctx) }
    }

    export let pagesCutsShowEvent(
      ctx: Ctx, rawId: String, event: String, payload: JsonObject,
      launch: fn (Ctx, Cut): Void throws Bubble,
    ): Response throws Bubble {
      let id = pcInt(rawId);
      if (id != null) { pcShowEventId(ctx, id, event, payload, launch) } else { webNotFound(ctx) }
    }
