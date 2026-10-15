# The read view: what opens under a paragraph, and the boxes around the prose

The rewrite panel and the thread, which sit directly under the paragraph they
are about; the box for the whole document above the prose; and a section's
heading with its summary.

    let { Ctx, cMutter } = import("webcore/src");
    let { h, hv, htext, hraw, attr, markdownToHtml } = import("html/src");
    let { Section } = import("works/src");
    let { ChatTurn, Conversation } = import("chat/src");
    let { RewriteCandidate, rewriteSpanLabel, rewriteSpanExtent, summaryCurrent, summaryDrift } = import("reading/src");
    let { DocumentSummary } = import("works/src");
    let { graphIso } = import("analysis/src");
    let { JsonSyntaxTree } = import("std/json");

## Rewrites

`rewrite_panel/1`: candidates for one selected line, side by side with what is
there now. Three labelled options rather than one suggestion: a single rewrite
reads as the answer, and the point is that the writer chooses.

The panel says how much is about to be replaced (a span can now be 2,500
words, and the panel renders under the first paragraph of a multi-paragraph
selection). The steering box is a textarea that grows, with an id so the morph
keeps it, and `phx-update="ignore"` so what is half-typed survives; that
freezes every attribute on the node, which is why it never carries `disabled`.
The button is what goes quiet during a pass.

    let psCandidate(i: Int, c: RewriteCandidate, blockRef: String, spansBlocks: Boolean): List<AnyValue> {
      let cost = c.cost;
      let costSpan: List<AnyValue> = if (cost != null) { h("span", attr("class", "cost"), htext(cost)) } else { [] };
      let edit: List<AnyValue> = if (!spansBlocks) {
        h("span", "${attr("class", "mine")}${attr("phx-click", "edit_block")}${attr("phx-value-ref", blockRef)}${attr("phx-value-seed", c.text)}", htext("or edit it first →"))
      } else { [] };
      h("button", "${attr("class", "mg-rw")}${attr("style", "--i:${i.toString()}")}${attr("data-i", i.toString())}", [
        h("span", attr("class", "head"), [
          h("span", attr("class", "move"), htext(showOr(c.move, ""))),
          costSpan,
        ]),
        h("span", attr("class", "words"), htext(c.text)),
        h("span", "${attr("class", "mine apply")}${attr("phx-click", "apply_rewrite")}${attr("phx-value-i", i.toString())}${attr("data-confirm", "Replace the selected passage with this version? It goes in the Changes tab and the draft's git history, so it can be got back.")}", htext("replace the passage with this →")),
        edit,
      ])
    }

    let psCandidates(r: ShowRewrite, blockRef: String): List<AnyValue> {
      let cands = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < r.candidates.length) {
        cands.add(psCandidate(i, r.candidates[i], blockRef, r.spansBlocks));
        i += 1;
      }
      let reading = r.reading;
      let readingNote: List<AnyValue> = if (reading != null) {
        h("p", attr("class", "mg-hint mt-0 mb-2.5"), htext(reading))
      } else { [] };
      let several: List<AnyValue> = if (r.spansBlocks) {
        h("p", attr("class", "mg-hint mt-0 mb-2.5"), htext("This covers more than one paragraph. Replacing works on the whole passage; editing one first needs a selection inside a single paragraph."))
      } else { [] };
      h("div", attr("class", "mg-rewrite-body"), [
        readingNote,
        several,
        h("div", "${attr("class", "mg-rw-list")}${attr("id", "rw-list")}${attr("phx-hook", "Hover")}", cands.toList()),
        h("p", attr("class", "mg-hint mt-2.5"), [
          htext("The line above is dimmed because these would replace it. Hover one and it shows there instead — "),
          h("ins", attr("class", "mg-swap"), htext("what arrives")),
          htext(" against "),
          h("del", attr("class", "mg-cut"), htext("what goes")),
          htext(". Nothing is applied."),
        ]),
      ])
    }

    export let showRewritePanel(state: ShowState, blockRef: String): List<AnyValue> {
      let working = state.rewriting;
      let span = state.rewriteSpan;
      let extent = rewriteSpanExtent(span);
      let extentLine: List<AnyValue> = if (extent != null) {
        h("p", attr("class", "mg-rw-extent"), htext(extent))
      } else { [] };
      let dots: List<AnyValue> = if (working) {
        h("div", attr("class", "mg-rewrite-body"), cMutter(state.mutter, "reading it", null))
      } else { [] };
      let rewrite = state.rewrite;
      let found: List<AnyValue> = if (rewrite != null) { psCandidates(rewrite, blockRef) } else { [] };
      h("div", "${attr("class", if (working) { "mg-rewrite working" } else { "mg-rewrite" })}${attr("id", "rewrite-panel")}", [
        h("div", attr("class", "mg-rewrite-head"), [
          h("span", attr("class", "mg-label"), htext(rewriteSpanLabel(span))),
          h("button", "${attr("class", "mg-btn sm ghost ml-auto")}${attr("phx-click", "close_rewrite")}", htext("close")),
        ]),
        extentLine,
        h("form", "${attr("id", "rw-steer-form")}${attr("class", "mg-rw-steer")}${attr("phx-submit", "steer_rewrite")}", [
          h("textarea", "${attr("id", "rw-steer")}${attr("name", "steer")}${attr("rows", "1")}${attr("maxlength", "400")}${attr("phx-hook", "Steer")}${attr("phx-update", "ignore")}${attr("placeholder", "ask for something specific — shorter, lead with the finding, drop the hedging")}",
            htext(showOr(state.steer, ""))),
          h("button", "${attr("type", "submit")}${attr("class", "mg-btn sm")}${if (working) { " disabled" } else { "" }}", htext("Again")),
        ]),
        dots,
        found,
      ])
    }

## A thread pinned to a paragraph

`inline_thread/1`: one conversation, about one paragraph, opened where that
paragraph is. Deliberately not the drawer: the drawer is for the draft, and
this is for the sentence in front of you. Assistant messages are rendered as
markdown with hard breaks; the writer's own are text. Someone holding the link
reads the thread and has no box to type in.

    let psTurn(m: ChatTurn): List<AnyValue> {
      if (m.role == "user") {
        h("div", attr("class", "mg-thread-turn mine"), [
          h("span", attr("class", "who"), htext("you")),
          h("div", attr("class", "said"), htext(m.content)),
        ])
      } else {
        h("div", attr("class", "mg-thread-turn theirs"), [
          h("span", attr("class", "who"), htext("the reader")),
          h("div", attr("class", "said md"), hraw(markdownToHtml(m.content))),
        ])
      }
    }

    export let showInlineThread(state: ShowState, thread: Conversation): List<AnyValue> {
      let id = thread.id.toString();
      let loading = state.threadLoading;
      let history = state.threadHistory;
      let settled: List<AnyValue> = if (thread.resolvedAt != null) {
        h("span", attr("class", "mg-badge"), htext("settled"))
      } else { [] };
      let settle: List<AnyValue> = if (state.mine && history.length > 0) {
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "resolve_thread")}",
          htext(if (thread.resolvedAt != null) { "reopen" } else { "settle" }))
      } else { [] };
      let quote = thread.quote;
      let quoted: List<AnyValue> = if (quote != null) {
        h("blockquote", attr("class", "mg-thread-quote"), htext("\"${quote}\""))
      } else { [] };
      let empty: List<AnyValue> = if (history.length == 0) {
        h("p", attr("class", "text-[0.78rem] text-[var(--mg-dim)] leading-relaxed"),
          htext("Ask about this one. What is it doing, what is it not doing, what would have to change. It will quote the draft back rather than rewrite it."))
      } else { [] };
      let dots: List<AnyValue> = if (loading) { cMutter(state.mutter, "thinking", "py-0.5") } else { [] };
      let foot: List<AnyValue> = if (state.mine) {
        h("div", attr("class", "mg-thread-foot"),
          h("form", "${attr("phx-submit", "thread_send")}${attr("id", "thread-form-${id}")}${attr("phx-hook", "ChatComposer")}", [
            h("textarea", "${attr("name", "message")}${attr("rows", "2")}${attr("autocomplete", "off")}${attr("placeholder", "What about this paragraph?")}${attr("class", "w-full text-[0.8rem] leading-relaxed resize-none min-h-[3.2rem] max-h-56 px-2.5 py-2 bg-[var(--mg-paper)] border border-[var(--mg-rule)] rounded-sm focus:outline-none focus:border-[var(--mg-accent)]")}${if (loading) { " disabled" } else { "" }}", []),
            h("div", attr("class", "flex items-center gap-2 mt-1.5"), [
              h("span", attr("class", "mg-hint mt-0"), htext("Enter to send")),
              h("button", "${attr("type", "submit")}${attr("class", "mg-btn sm ml-auto")}${if (loading) { " disabled" } else { "" }}", htext(if (loading) { "…" } else { "Ask" })),
            ]),
          ]))
      } else { [] };
      h("div", "${attr("class", "mg-thread-panel")}${attr("id", "thread-${id}")}", [
        h("div", attr("class", "mg-thread-head"), [
          h("span", attr("class", "mg-label"), htext(if (thread.anchorKind == "span") { "on this passage" } else { "on this paragraph" })),
          settled,
          h("div", attr("class", "ml-auto flex items-baseline gap-2"), [
            settle,
            h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "close_thread")}", htext("close")),
          ]),
        ]),
        h("div", "${attr("class", "mg-thread-body")}${attr("id", "thread-body-${id}")}${attr("phx-hook", "StickToBottom")}", [
          quoted,
          empty,
          history.map { (m: ChatTurn): List<AnyValue> => psTurn(m) },
          dots,
        ]),
        foot,
      ])
    }

## The whole document

The box above the prose, for the owner: summarise the document, open the
summaries as a draft, draft it and compare. Each button is offered only when
there is something for it to do; a draft built from no summaries is an empty
draft.

    let psAnySummary(sections: List<Section>): Boolean {
      for (let s of sections) {
        let text = s.summary;
        if (text != null) {
          if (text != "") { return true; }
        }
      }
      false
    }

    let psRefs(sections: List<String>): String {
      if (sections.length == 0) { "§" } else { "§${showJoin(sections, ", §")}" }
    }

    let psMovement(m: JsonSyntaxTree): List<AnyValue> {
      h("div", attr("class", "mg-doc-move"), [
        h("strong", "", htext(showOr(showJStr(m, "heading"), ""))),
        h("span", attr("class", "mg-meta"), htext(psRefs(showJStrings(m, "sections")))),
        h("p", "", htext(showOr(showJStr(m, "does"), ""))),
      ])
    }

    let psRule(g: JsonSyntaxTree): List<AnyValue> {
      h("div", attr("class", "mg-doc-rule"), [
        h("strong", "", htext(showOr(showJStr(g, "guideline"), ""))),
        h("p", "", htext(showOr(showJStr(g, "because"), ""))),
        h("span", attr("class", "mg-meta"), htext(psRefs(showJStrings(g, "sections")))),
      ])
    }

    let psTension(t: JsonSyntaxTree): List<AnyValue> {
      h("div", attr("class", "mg-doc-rule"), [
        h("p", "", htext(showOr(showJStr(t, "tension"), ""))),
        h("span", attr("class", "mg-meta"), htext(psRefs(showJStrings(t, "sections")))),
      ])
    }

    let psDocBody(doc: DocumentSummary): List<AnyValue> {
      let through = doc.throughline;
      let throughLine: List<AnyValue> = if (through != null) {
        h("p", attr("class", "mg-doc-through"), htext(through))
      } else { [] };
      let moves: List<AnyValue> = if (doc.movements.length > 0) {
        h("div", attr("class", "mg-doc-moves"), [
          h("span", attr("class", "mg-label"), htext("how it moves")),
          doc.movements.map { (m: JsonSyntaxTree): List<AnyValue> => psMovement(m) },
        ])
      } else { [] };
      let rules: List<AnyValue> = if (doc.guidelines.length > 0) {
        h("div", attr("class", "mg-doc-rules"), [
          h("span", attr("class", "mg-label"), htext("what it is working under")),
          doc.guidelines.map { (g: JsonSyntaxTree): List<AnyValue> => psRule(g) },
        ])
      } else { [] };
      let tensions: List<AnyValue> = if (doc.tensions.length > 0) {
        h("div", attr("class", "mg-doc-rules tensions"), [
          h("span", attr("class", "mg-label"), htext("where those pull against each other")),
          doc.tensions.map { (t: JsonSyntaxTree): List<AnyValue> => psTension(t) },
        ])
      } else { [] };
      let dropped: List<AnyValue> = if (doc.dropped.length > 0) {
        h("p", attr("class", "mg-sum-stale"), htext("${doc.dropped.length.toString()} claim(s) dropped: ${showJoin(doc.dropped, "; ")}"))
      } else { [] };
      h("div", attr("class", "mg-doc-body"), [
        h("p", attr("class", "mg-doc-summary"), htext(showOr(doc.summary, ""))),
        throughLine, moves, rules, tensions, dropped,
      ])
    }

    export let showDocBox(state: ShowState): List<AnyValue> {
      if (!state.mine) { return []; }
      let any = psAnySummary(state.sections);
      let draftIt: List<AnyValue> = if (any) {
        h("button", "${attr("class", "mg-btn sm ghost ml-auto")}${attr("phx-click", "summaries_to_draft")}${attr("title", "Make a draft out of the summaries, to edit and read like any other")}", htext("Open as a draft"))
      } else { [] };
      let link = state.summaryLink;
      let side: List<AnyValue> = if (link != null) {
        h("a", "${attr("href", "/links/${link.toString()}?lead=${state.work.slug}")}${attr("class", "mg-btn sm")}", htext("Side by side"))
      } else { [] };
      let comparing = state.comparing;
      let compareLabel = if (comparing != null) {
        "${comparing}…"
      } else if (link != null) { "Relate them again" } else { "Draft it and compare" };
      let compare: List<AnyValue> = if (any) {
        h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "compare_summary")}${if (comparing != null) { " disabled" } else { "" }}", htext(compareLabel))
      } else { [] };
      let docLabel = if (state.docRunning) {
        "Reading it all…"
      } else if (state.document != null) { "Read it again" } else { "Summarise the document" };
      let doc = state.document;
      let body: List<AnyValue> = if (doc != null) { psDocBody(doc) } else { [] };
      h("div", attr("class", "mg-doc"), [
        h("div", attr("class", "mg-doc-head"), [
          h("span", attr("class", "mg-label"), htext("The whole document")),
          draftIt, side, compare,
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "summarise_document")}${if (state.docRunning) { " disabled" } else { "" }}", htext(docLabel)),
        ]),
        body,
      ])
    }

## A section's heading and its summary

What the section says, for finding your place in twelve of them, per section
and on request: a draft here can be a hundred and eleven documents. The server
keeps one summary per section, and the text that was there is gone when it is
run again; the vault below keeps the last few in this browser (the
`SummaryVault` hook) so a re-run is undoable by the person who ran it. The
vault div is `phx-update="ignore"`: the hook owns what is in it.

    let psSummaryText(sec: Section, slug: String): List<AnyValue> {
      let text = sec.summary;
      if (text != null) { psSummaryOf(sec, slug, text) } else { [] }
    }

    let psSummaryOf(sec: Section, slug: String, text: String): List<AnyValue> {
      let current = summaryCurrent(sec);
      let at = sec.summarisedAt;
      let covers: List<AnyValue> = if (sec.summaryCovers.length > 0) {
        h("div", attr("class", "mg-sum-covers"),
          sec.summaryCovers.map { (t: String): List<AnyValue> => h("span", "", htext(t)) })
      } else { [] };
      let setsUp = sec.summarySetsUp;
      let needs: List<AnyValue> = if (sec.summaryFollows.length > 0) {
        h("span", "", htext("needs ${showJoin(sec.summaryFollows.map { (n: Int): String => "§${n.toString()}" }, ", ")}"))
      } else { [] };
      let sets: List<AnyValue> = if (setsUp != null) {
        h("span", "", htext("sets up: ${setsUp}"))
      } else { [] };
      let links: List<AnyValue> = if (sec.summaryFollows.length > 0 || setsUp != null) {
        h("div", attr("class", "mg-sum-links"), [needs, sets])
      } else { [] };
      let stale: List<AnyValue> = if (!current) {
        h("span", attr("class", "mg-sum-stale"), htext("the section has been edited since this was written"))
      } else { [] };
      let drift = summaryDrift(sec);
      let moved: List<AnyValue> = if (drift.length > 0) {
        renderDiffTable(drift, "When it was summarised", "Now", true)
      } else { [] };
      let dropped: List<AnyValue> = if (sec.summaryDropped.length > 0) {
        h("span", attr("class", "mg-sum-stale"), htext("${sec.summaryDropped.length.toString()} term(s) dropped: not in the section"))
      } else { [] };
      h("div", "${attr("class", if (current) { "mg-sum-text" } else { "mg-sum-text stale" })}${attr("data-sum-key", "${slug}:${sec.ordinal.toString()}")}${attr("data-sum-at", if (at != null) { graphIso(at) } else { null })}${attr("data-sum-text", text)}", [
        htext(text), covers, links, stale, moved, dropped,
      ])
    }

    let psSummaryVault(sec: Section): List<AnyValue> {
      if (sec.summary == null) { return []; }
      h("div", "${attr("id", "sumvault-${sec.ordinal.toString()}")}${attr("class", "mg-sum-vault")}${attr("phx-update", "ignore")}", [])
    }

    let psSummariseLabel(state: ShowState, sec: Section): String {
      if (psSummarising(state, sec.ordinal)) {
        "Summarising…"
      } else if (sec.summary != null) { "Summarise again" } else { "Summarise this section" }
    }

    let psSummarising(state: ShowState, ordinal: Int): Boolean {
      for (let n of state.summarising) {
        if (n == ordinal) { return true; }
      }
      false
    }

    export let showSectionHead(state: ShowState, sec: Section): List<AnyValue> {
      let box: List<AnyValue> = if (state.mine) {
        h("div", attr("class", "mg-sum"), [
          psSummaryText(sec, state.work.slug),
          psSummaryVault(sec),
          h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "summarise")}${attr("phx-value-ordinal", sec.ordinal.toString())}${if (psSummarising(state, sec.ordinal)) { " disabled" } else { "" }}", htext(psSummariseLabel(state, sec))),
        ])
      } else { [] };
      h("div", "${attr("class", "mg-read-head")}${attr("id", "sec-${sec.ordinal.toString()}")}", [
        h("div", attr("class", "mg-label"), htext("Section ${sec.ordinal.toString()}")),
        h("h2", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-[1.45rem] font-semibold mt-1")}", htext(sec.title)),
        box,
      ])
    }
