# The frame

`render/1`: the header with its controls, the strip of links to the drafts it
is read alongside, the tab strip with the help button and the drawer's toggle,
the body (the confirm gate while the draft is unread; otherwise the tour card,
the walkthrough, the progress of a read and the chosen view), and the drawer.
The views draw the inside of the body; this draws everything around them and
chooses which.

    let { Ctx, webAbsolute, cMutter } = import("webcore/src");
    let { h, hv, htext, hraw, attr, classes } = import("html/src");
    let { Work, Section } = import("works/src");
    let { LinkWorks, linksOther } = import("links/src");
    let { llmProvider } = import("llm/src");
    let { walkthroughForView, walkthroughStepsJson, WalkStep, TourCard } = import("cases/src");

## When the page waits

`data-poll` goes on the page while a read is going or any run of this work is
(`handle_info` refreshed the page on every message; the poll is what stands in
for them).

    export let showPoll(state: ShowState): Int? {
      if (state.work.status == "reading" || state.running.length > 0 || state.rewritePending
          || state.loading || state.threadLoading) {
        2
      } else { null }
    }

## The header

    let psTab(state: ShowState, id: String, label: String): List<AnyValue> {
      h("button", "${attr("class", if (state.view == id) { "mg-tab on" } else { "mg-tab" })}${attr("phx-click", "set_view")}${attr("phx-value-view", id)}", htext(label))
    }

`links_control/1`: linking this draft to another, and the ones already related
to it. Only drafts that have been read are offered: the pass relates two
graphs, and an unread draft has no graph to relate.

    let psLinkRow(lw: LinkWorks, work: Work): List<AnyValue> {
      let other = linksOther(lw, work.id);
      h("a", "${attr("href", "/links/${lw.link.id.toString()}?lead=${work.slug}")}${attr("class", "row")}", [
        h("span", attr("class", "t"), htext(other.title)),
        h("span", attr("class", "st ${lw.link.status}"), htext(lw.link.status)),
      ])
    }

    let psLinkMenu(state: ShowState): List<AnyValue> {
      if (!state.linking) { return []; }
      let already: List<AnyValue> = if (state.links.length > 0) {
        [
          h("span", attr("class", "mg-label"), htext("already linked")),
          state.links.map { (lw: LinkWorks): List<AnyValue> => psLinkRow(lw, state.work) },
        ]
      } else { [] };
      let others: List<AnyValue> = if (state.linkable.length == 0) {
        h("p", attr("class", "none"), htext("Nothing to link to yet. A second draft has to have been read before the two can be related — linking works on the maps, not the text."))
      } else {
        state.linkable.map { (o: Work): List<AnyValue> =>
          h("button", "${attr("class", "row")}${attr("phx-click", "link_to")}${attr("phx-value-id", o.id.toString())}", [
            h("span", attr("class", "t"), htext(o.title)),
            h("span", attr("class", "n"), htext("${o.wordCount.toString()}w")),
          ])
        }
      };
      h("div", attr("class", "mg-linkmenu"), [already, h("span", attr("class", "mg-label"), htext("link to")), others])
    }

    let psLinksControl(state: ShowState): List<AnyValue> {
      let n = state.links.length;
      let away = if (state.linking) { attr("phx-click-away", "toggle_linking") } else { "" };
      h("div", "${attr("class", "mg-linkbox")}${attr("id", "linkbox")}${away}", [
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "toggle_linking")}",
          htext("Link${if (n > 0) { " · ${n.toString()}" } else { "" }}")),
        psLinkMenu(state),
      ])
    }

    let psHeader(state: ShowState): List<AnyValue> {
      let work = state.work;
      let linkControl: List<AnyValue> = if (state.mine && work.status == "read") { psLinksControl(state) } else { [] };
      let again: List<AnyValue> = if (state.mine && work.status == "read" && state.counts.beats == 0) {
        h("button", "${attr("class", "mg-btn sm")}${attr("phx-click", "start_read")}", htext("Read again"))
      } else { [] };
      h("div", attr("class", "flex items-baseline gap-3 flex-wrap"), [
        h("h1", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-2xl font-semibold tracking-tight")}", htext(work.title)),
        h("span", attr("class", "mg-meta"),
          htext("${work.wordCount.toString()} words · ${state.sections.length.toString()} sections · ${state.counts.beats.toString()} beats")),
        h("div", attr("class", "ml-auto flex gap-2 items-baseline flex-wrap"), [linkControl, again]),
      ])
    }

A draft can be related to several others, and a relationship that only appears
inside a dropdown is one nobody remembers they made.

    let psLinkStrip(state: ShowState): List<AnyValue> {
      if (state.links.length == 0) { return []; }
      let work = state.work;
      h("div", attr("class", "mg-linkrow"), [
        h("span", attr("class", "mg-label"), htext("read alongside")),
        state.links.map { (lw: LinkWorks): List<AnyValue> =>
          let other = linksOther(lw, work.id);
          let chip: List<AnyValue> = if (lw.link.status != "linked") {
            h("span", attr("class", "st ${lw.link.status}"), htext(lw.link.status))
          } else { [] };
          h("a", "${attr("href", "/links/${lw.link.id.toString()}?lead=${work.slug}")}${attr("class", "one")}", [
            h("span", attr("class", "t"), htext(other.title)),
            chip,
          ])
        },
      ])
    }

### The backend

The deploy's owner chooses which model the work runs against, when more than
one has a key. A change of the select posts `set_provider`.

    let psBackend(state: ShowState): List<AnyValue> {
      if (!(state.owner && state.backends.length > 1)) { return []; }
      let current = showProviderName(state.provider);
      let shown = llmProvider(current).model;
      h("form", "${attr("phx-change", "set_provider")}${attr("class", "inline-flex items-baseline gap-1.5")}", [
        h("span", attr("class", "mg-label"), htext("backend")),
        h("select", "${attr("name", "provider")}${attr("class", "text-[0.72rem] bg-transparent border border-[var(--mg-rule)] rounded-sm px-1.5 py-0.5")}",
          state.backends.map { (b: ShowBackend): List<AnyValue> =>
            h("option", "${attr("value", b.name)}${if (b.name == current) { " selected" } else { "" }}", htext(b.label))
          }),
        h("span", attr("class", "mg-meta opacity-60"), htext(shown)),
      ])
    }

    let psTabStrip(ctx: Ctx, state: ShowState): List<AnyValue> {
      let work = state.work;
      let changes: List<AnyValue> = if (state.revisionCount > 0) { psTab(state, "changes", "Changes") } else { [] };
      let trace: List<AnyValue> = if (state.owner) {
        [psTab(state, "trace", "Trace"), psTab(state, "prompts", "Prompts")]
      } else { [] };
      let share: List<AnyValue> = if (state.mine) {
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("id", "share-link")}${attr("phx-hook", "Share")}${attr("data-url", webAbsolute("/works/${work.slug}"))}", htext("Copy link"))
      } else {
        h("span", attr("class", "mg-badge"), htext("reading someone's draft"))
      };
      h("div", attr("class", "mt-5 flex items-baseline gap-5 flex-wrap border-b border-[var(--mg-rule)] pb-0"), [
        h("div", attr("class", "mg-tabs"), [
          psTab(state, "read", "Read"),
          psTab(state, "graph", "Graph"),
          psTab(state, "spine", "Spine"),
          psTab(state, "threads", "Threads"),
          changes, trace,
        ]),
        h("button", "${attr("class", "mg-help")}${attr("phx-click", "show_help")}${attr("title", "What is this tab for?")}${attr("aria-label", "What is this tab for?")}", htext("?")),
        h("div", attr("class", "ml-auto flex items-baseline gap-3 pb-1"), [
          share,
          h("button", "${attr("class", if (state.chatOpen) { "mg-btn sm" } else { "mg-btn sm ghost" })}${attr("phx-click", "toggle_chat")}", htext("Talk about it")),
          psBackend(state),
        ]),
      ])
    }

## Before it reads

`confirm_gate/1`: shown while the draft is `pending`. The Read button is above
the section list on purpose, and again below it when the list is long. With no
key, or for someone who does not own the draft, a notice stands in its place.

    let psReadButton(count: Int): List<AnyValue> {
      h("button", "${attr("class", "mg-btn")}${attr("phx-click", "start_read")}", htext("Read it — ${count.toString()} sections"))
    }

    let psGate(state: ShowState): List<AnyValue> {
      let n = state.sections.length;
      let ready = state.llmReady && state.mine;
      let top: List<AnyValue> = if (ready) {
        h("div", attr("class", "mt-5 flex items-baseline gap-3 flex-wrap"), [
          psReadButton(n),
          h("span", attr("class", "mg-hint mt-0"), htext("Takes a few minutes. Everything else on the page stays usable while it runs.")),
        ])
      } else {
        h("div", attr("class", "mt-5 text-[0.85rem] border-l-2 border-[var(--mg-accent)] pl-3 py-1.5"),
          htext("No ${llmProvider(showProviderName(state.provider)).label} key is configured on this deploy, so the read can't run."))
      };
      let bottom: List<AnyValue> = if (ready && n > 8) {
        h("button", "${attr("class", "mg-btn mt-5")}${attr("phx-click", "start_read")}", htext("Read it — ${n.toString()} sections"))
      } else { [] };
      h("div", "", [
        h("h2", attr("class", "mg-label"), htext("Before it reads")),
        h("p", attr("class", "mg-prose mt-2.5 max-w-[62ch] text-[0.95rem]"),
          htext("This is how the draft has been divided. A machine guessing your section breaks is a machine getting everything after that wrong, so have a look before anything is read.")),
        top,
        h("div", attr("class", "mg-rows mt-5 max-w-[62ch]"),
          state.sections.map { (s: Section): List<AnyValue> =>
            h("div", attr("class", "mg-row"), [
              h("span", attr("class", "n"), htext(s.ordinal.toString())),
              h("span", attr("class", "flex-1 min-w-0 truncate text-[0.9rem]"), htext(s.title)),
              h("span", attr("class", "mg-meta"), htext("${s.wordCount.toString()}w")),
            ])
          }),
        bottom,
      ])
    }

## While it reads

`progress/1` and `stage/1`. A read is three different jobs that take about a
minute each, and the last of them produces nothing visible until it is
finished: name the three, say which one is running, show what each has found.

    let psStageGlyph(st: String): List<AnyValue> {
      if (st == "done") {
        htext("✓")
      } else if (st == "failed") {
        htext("✕")
      } else if (st == "start") {
        h("span", "${attr("class", "mg-dot inline-block")}${attr("style", "background:var(--mg-accent)")}", [])
      } else { htext("·") }
    }

    let psStage(st: String, name: String, detail: String): List<AnyValue> {
      let waiting = st == "waiting";
      [
        h("span", attr("class", showCls([
          "text-[0.8rem] leading-6",
          if (st == "done") { "text-[var(--mg-accent)]" } else { "" },
          if (st == "start") { "text-[var(--mg-ink)]" } else { "" },
          if (waiting) { "text-[var(--mg-dim)] opacity-40" } else { "" },
        ])), psStageGlyph(st)),
        h("span", attr("class", showCls([
          "text-[0.8rem] leading-6",
          if (waiting) { "text-[var(--mg-dim)] opacity-50" } else { "" },
          if (st == "start") { "font-semibold" } else { "" },
        ])), htext(name)),
        h("span", attr("class", showCls([
          "text-[0.8rem] leading-6 text-[var(--mg-dim)]",
          if (waiting) { "opacity-50" } else { "" },
        ])), htext(detail)),
      ]
    }

    let psSectionBadgeClass(status: String): String {
      if (status == "read") { "ink" } else if (status == "failed") { "accent" } else if (status == "reading") { "accent" } else { "" }
    }

    let psClock(state: ShowState): List<AnyValue> {
      let at = state.startedAt;
      if (at != null) {
        h("span", "${attr("id", "read-clock")}${attr("phx-hook", "Clock")}${attr("data-since", at.toString())}${attr("class", "mg-meta")}", htext("0:00"))
      } else { [] }
    }

    let psProgress(state: ShowState): List<AnyValue> {
      let counts = state.counts;
      let read = state.sections.filter { (s: Section): Boolean => s.status == "read" }.length;
      let clock = psClock(state);
      let sectionsDetail = "${read.toString()} of ${state.sections.length.toString()} read${if (counts.beats > 0) { " · ${counts.beats.toString()} beats" } else { "" }}";
      let spineDetail = if (counts.spine > 0) {
        "${counts.spine.toString()} spine · ${counts.threads.toString()} threads · ${counts.questions.toString()} questions"
      } else { "what the whole draft hangs off" };
      let badges: List<AnyValue> = if (state.stages.sections == "start") {
        h("div", attr("class", "mt-5 flex flex-wrap gap-1.5"),
          state.sections.map { (s: Section): List<AnyValue> =>
            h("span", attr("class", "mg-badge ${psSectionBadgeClass(s.status)}"), htext(s.ordinal.toString()))
          })
      } else { [] };
      h("div", attr("class", "border-b border-[var(--mg-rule)] pb-6 mb-7"), [
        h("div", attr("class", "flex items-baseline gap-3"), [
          h("h2", attr("class", "mg-label"), htext("Reading your draft")),
          clock,
          h("span", attr("class", "mg-hint mt-0 ml-auto"), htext("Everything else on the page stays usable.")),
        ]),
        h("div", "${attr("class", "mt-4 grid gap-y-3 max-w-[58ch]")}${attr("style", "grid-template-columns:1.4rem 11rem 1fr")}", [
          psStage(state.stages.sections, "Sections", sectionsDetail),
          psStage(state.stages.spine, "The spine", spineDetail),
          psStage(state.stages.weave, "Connections", "what develops, pays off, requires, or contradicts what"),
        ]),
        badges,
      ])
    }

## The tour card and the walkthrough

One card, shown the first time a tab is opened. Every point exists because the
affordance it names is invisible until someone says it.

    let psTourCard(state: ShowState, tour: TourCard): List<AnyValue> {
      let offer: List<AnyValue> = if (walkthroughForView(state.view)) {
        h("div", attr("class", "mg-tour-foot"), [
          h("button", "${attr("class", "mg-btn sm")}${attr("phx-click", "start_walk")}", htext("Show me")),
          h("span", attr("class", "mg-hint mt-0"), htext("Works the controls for you. Nothing is saved and the model is never called.")),
        ])
      } else { [] };
      h("div", attr("class", "mg-tour"), [
        h("div", attr("class", "flex items-baseline gap-3"), [
          h("h2", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-[1.15rem] font-semibold")}", htext(tour.title)),
          h("button", "${attr("class", "mg-btn sm ghost ml-auto")}${attr("phx-click", "dismiss_tour")}", htext("Got it")),
        ]),
        h("ul", attr("class", "mg-tour-points"),
          tour.points.map { (point: String): List<AnyValue> => h("li", "", htext(point)) }),
        offer,
        h("p", attr("class", "mg-hint mt-2.5"), [htext("The "), h("strong", "", htext("?")), htext(" beside the tabs brings this back.")]),
      ])
    }

`MarginaliaWeb.Walk.overlay`: the ring, the veil and the card the `Walk` hook
drives, with the steps as JSON.

    let psWalkOverlay(steps: List<WalkStep>): List<AnyValue> {
      h("div", "${attr("id", "walk")}${attr("phx-hook", "Walk")}${attr("data-steps", walkthroughStepsJson(steps))}", [
        h("div", "${attr("class", "mg-walk-ring")} hidden", []),
        h("div", "${attr("class", "mg-walk-veil")} hidden", []),
        h("div", "${attr("class", "mg-walk-card")} hidden", [
          h("div", attr("class", "mg-walk-head"), [
            h("span", attr("class", "mg-label"), htext("Walkthrough")),
            h("span", attr("class", "n"), []),
            h("button", attr("class", "mg-btn sm ghost ml-auto end"), htext("end")),
          ]),
          h("h3", "", []),
          h("p", attr("class", "body"), []),
          h("div", attr("class", "mg-walk-foot"), [
            h("button", attr("class", "mg-btn sm ghost back"), htext("Back")),
            h("button", attr("class", "mg-btn sm next"), htext("Next")),
          ]),
          h("p", attr("class", "mg-walk-safe"), htext("Nothing here is saved, and no model is called — the answers are fixed examples.")),
        ]),
      ])
    }

## The views

`map_view/1`: one function per view, each in a file of its own. The read view
is `read_view.temper.md`; the others are replaced by whoever builds them.

    export let renderShowView(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      let v = state.view;
      let inner: List<AnyValue> = if (v == "spine") {
        renderSpineView(ctx, state)
      } else if (v == "changes") {
        renderChangesView(ctx, state)
      } else if (v == "graph") {
        renderGraphView(ctx, state)
      } else if (v == "trace") {
        renderTraceView(ctx, state)
      } else if (v == "prompts") {
        renderPromptsView(ctx, state)
      } else if (v == "threads") {
        renderThreadsView(ctx, state)
      } else {
        renderReadView(ctx, state)
      };
      h("div", "", inner)
    }

    let psBody(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      if (state.work.status == "pending") { return psGate(state); }
      let tour = state.tour;
      let tourCard: List<AnyValue> = if (tour != null) { psTourCard(state, tour) } else { [] };
      let walk: List<AnyValue> = if (state.walk.length > 0) { psWalkOverlay(state.walk) } else { [] };
      let progress: List<AnyValue> = if (state.work.status == "reading") { psProgress(state) } else { [] };
      [tourCard, walk, progress, renderShowView(ctx, state)]
    }

The selection toolbar the `Selection` hook shows at the end of a selection:
three buttons, hidden until there is one.

    let psSelectionBar(): List<AnyValue> {
      h("div", "${attr("id", "sel-actions")} hidden", [
        h("button", "${attr("id", "sel-discuss")}${attr("type", "button")}", htext("Discuss this")),
        h("button", "${attr("id", "sel-rewrite")}${attr("type", "button")}", htext("Suggest a rewrite")),
        h("button", "${attr("id", "sel-add")}${attr("type", "button")}", htext("Add to question")),
      ])
    }

## The page

    export let renderShow(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      h("div", attr("class", "w-full px-6 py-6"), [
        psHeader(state),
        psLinkStrip(state),
        psTabStrip(ctx, state),
        h("div", "${attr("class", if (state.chatOpen) { "mt-5 relative mg-shifted" } else { "mt-5 relative " })}${attr("id", "page-body")}${attr("phx-hook", "Selection")}", [
          psSelectionBar(),
          h("div", attr("class", "min-w-0"), psBody(ctx, state)),
        ]),
        h("div", "${attr("class", if (state.chatOpen) { "mg-drawer open" } else { "mg-drawer " })}${if (state.chatOpen) { "" } else { " aria-hidden" }}",
          if (state.chatOpen) { renderChatPanel(ctx, state) } else { [] }),
      ])
    }
