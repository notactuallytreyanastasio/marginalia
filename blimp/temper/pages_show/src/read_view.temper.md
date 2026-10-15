# The read view

`read_pane/1`: the draft with its notes in the margin. This is the only view
that shows the writer their own prose, and the notes sit beside the paragraph
that caused them rather than at the top of a section, which is possible only
because every note carries a span verified against the source.

Structure, in order: a header line (the title "The page", the "Show what
changed" toggle, the four filters, a hint); "Nothing read yet." if there is no
page; otherwise the contents rail and `#read-rail`, the grid the `MarginNotes`
hook lays out. Its children are the box for the whole document (the owner's),
`#read-body` with every section's heading and every paragraph, and the rail of
notes (or, with the toggle on, of changes).

    let { Ctx } = import("webcore/src");
    let { h, hv, htext, hraw, attr } = import("html/src");
    let { sysGraphemeTake, sysStringReplace } = import("sys/src");
    let { Row } = import("core/src");
    let { Section, Revision } = import("works/src");
    let { ReadingSection, ReadingBlock, ReadingNote, readingRenderBlock, readingOutline } = import("reading/src");
    let { ChatThread } = import("chat/src");

## One paragraph

A block is a wrapper with a tick (the hairline in the gutter that opens a
thread), then the prose, then whatever opened under it. `has-thread` says a
thread exists, `resolved` that it is settled, `open` that it is the open one,
and `rewriting` that a rewrite is pending or present, no preview is showing,
and this paragraph is one the span covers: every paragraph, not only the one
the panel is anchored to, since a rewrite of three paragraphs that dimmed one
and left the other two looking untouched was a bug.

    let psIn(xs: List<String>, x: String): Boolean {
      for (let y of xs) { if (y == x) { return true; } }
      false
    }

    let psCovered(state: ShowState, ref: String): Boolean {
      let rewrite = state.rewrite;
      if (rewrite != null) {
        if (rewrite.covers.length > 0) { return psIn(rewrite.covers, ref); }
      }
      let anchor = state.rewriteRef;
      anchor != null && anchor == ref
    }

    let psBlockClass(state: ShowState, ref: String, t: ChatThread?): String {
      let thread = state.openThread;
      let open = if (thread != null) { thread.blockRef == ref } else { false };
      let pending = (state.rewriting || state.rewrite != null) && state.preview == null && psCovered(state, ref);
      showCls([
        "mg-block",
        if (t != null) { "has-thread" } else { "" },
        if (t != null) { if (t.resolved) { "resolved" } else { "" } } else { "" },
        if (open) { "open" } else { "" },
        if (pending) { "rewriting" } else { "" },
      ])
    }

The block that now holds what was written. A replacement collapsing three
paragraphs into one means the ref that was anchored no longer names the same
text, so the text is what identifies it.

    let psLanded(applied: ShowApplied, text: String): Boolean {
      if (applied.after == "") { return false; }
      showHas(text, sysGraphemeTake(applied.after, 80))
    }

    let psEditor(state: ShowState, ref: String): List<AnyValue> {
      h("form", "${attr("phx-submit", "save_block")}${attr("id", "edit-${ref}")}${attr("phx-hook", "Editor")}${attr("class", "mg-edit")}", [
        h("textarea", "${attr("name", "text")}${attr("rows", "3")}${attr("spellcheck", "true")}", htext(showOr(state.editText, ""))),
        h("div", attr("class", "foot"), [
          h("span", attr("class", "mg-hint mt-0"), htext("This is the paragraph's markdown. ⌘↵ saves · Esc cancels")),
          h("button", "${attr("type", "button")}${attr("class", "mg-btn sm ghost")}${attr("phx-click", "cancel_edit")}", htext("cancel")),
          h("button", "${attr("type", "submit")}${attr("class", "mg-btn sm")}", htext("Save")),
        ]),
      ])
    }

The paragraph the change landed in shows what it replaced, in place, until it
is dismissed.

    let psApplied(applied: ShowApplied): List<AnyValue> {
      h("div", attr("class", "mg-applied"), [
        h("div", attr("class", "mg-applied-head"), [
          h("span", attr("class", "mg-label"), htext("replaced")),
          h("button", "${attr("class", "mg-btn sm ghost ml-auto")}${attr("phx-click", "dismiss_applied")}", htext("done")),
        ]),
        renderDiffTable([new Row("change", applied.before, applied.after)], "Before", "Now", true),
      ])
    }

    let psProse(state: ShowState, b: ReadingBlock): List<AnyValue> {
      if (state.editing != null && state.editing == b.ref) { return psEditor(state, b.ref); }
      let applied = state.applied;
      if (applied != null) {
        if (psLanded(applied, b.text)) { return psApplied(applied); }
      }
      hraw(readingRenderBlock(b.text, b.mark, b.ref, state.preview))
    }

    let psTick(sec: Section, b: ReadingBlock, t: ChatThread?): List<AnyValue> {
      let label = if (t != null) { "Open the thread on this paragraph" } else { "Talk about this paragraph" };
      let hint = if (t != null) { "${t.messages.toString()} in this thread" } else { "Talk about this paragraph" };
      h("button", "${attr("class", "mg-tick")}${attr("phx-click", "open_thread")}${attr("phx-value-ref", b.ref)}${attr("phx-value-section", sec.id.toString())}${attr("aria-label", label)}${attr("title", hint)}", [])
    }

With the rail given over to the diff, a note has nowhere to sit in the margin,
so it sits under its own paragraph.

    let psInlineNotes(state: ShowState, b: ReadingBlock): List<AnyValue> {
      if (!state.changesOn || b.notes.length == 0) { return []; }
      h("div", attr("class", "mg-note-inline"),
        b.notes.map { (n: ReadingNote): List<AnyValue> =>
          h("button", "${attr("class", "mg-note ${n.kind}")}${attr("phx-click", "discuss")}${attr("phx-value-key", n.key)}", [
            h("span", attr("class", "who"), htext(sysStringReplace(n.kind, "_", " "))),
            h("span", attr("class", "said"), htext(n.title)),
          ])
        })
    }

    let psPanels(state: ShowState, b: ReadingBlock): List<AnyValue> {
      let anchor = state.rewriteRef;
      let panel: List<AnyValue> = if ((state.rewriting || state.rewrite != null) && anchor != null && anchor == b.ref) {
        showRewritePanel(state, b.ref)
      } else { [] };
      let thread = state.openThread;
      let open: List<AnyValue> = if (thread != null) {
        if (thread.blockRef == b.ref) { showInlineThread(state, thread) } else { [] }
      } else { [] };
      [panel, open]
    }

    let psBlock(state: ShowState, sec: Section, b: ReadingBlock): List<AnyValue> {
      let t: ChatThread? = state.blockThreads.get(b.ref) orelse null;
      [
        h("div", "${attr("class", psBlockClass(state, b.ref, t))}${attr("id", "block-${b.ref}")}", [
          psTick(sec, b, t),
          psProse(state, b),
        ]),
        psInlineNotes(state, b),
        psPanels(state, b),
      ]
    }

## The rails

The notes rail: for each section the notes that located nowhere come first, in
slots without `data-anchor` and marked "not located", then each paragraph's
piles in slots that carry its ref.

    let psNotesRail(page: List<ReadingSection>): List<AnyValue> {
      h("div", attr("class", "mg-read-rail"),
        page.map { (sec: ReadingSection): List<AnyValue> =>
          [
            showPiles(sec.unplaced).map { (pile: List<ReadingNote>): List<AnyValue> => showSlot(pile, false, null) },
            sec.blocks.map { (b: ReadingBlock): List<AnyValue> =>
              showPiles(b.notes).map { (pile: List<ReadingNote>): List<AnyValue> => showSlot(pile, true, b.ref) }
            },
          ]
        })
    }

What changed, where the notes usually are. The notes do not disappear: they
move into the prose column beside the paragraph that caused them.

    let psRevisionLabel(rev: Revision): String {
      let note = rev.note;
      let ordinal = rev.sectionOrdinal;
      "${rev.origin}${if (note != null) { " — ${note}" } else { "" }} · section ${if (ordinal != null) { ordinal.toString() } else { "" }}"
    }

    let psChangesRail(state: ShowState): List<AnyValue> {
      let none: List<AnyValue> = if (state.revisions.length == 0) {
        h("p", attr("class", "mg-empty"), htext("Nothing has been changed yet."))
      } else { [] };
      h("div", attr("class", "mg-read-rail changes"), [
        none,
        state.revisions.map { (rev: Revision): List<AnyValue> =>
          h("div", "${attr("class", "mg-chg")}${attr("id", "chg-${rev.id.toString()}")}", [
            h("span", attr("class", "mg-label"), htext(psRevisionLabel(rev))),
            h("div", attr("class", "mg-chg-old"), renderWordSpans(rev.before, rev.after, "old")),
            h("div", attr("class", "mg-chg-new"), renderWordSpans(rev.before, rev.after, "new")),
          ])
        },
      ])
    }

## The header line

    let psFilter(state: ShowState, id: String, label: String): List<AnyValue> {
      let current = showOr(state.only, "all");
      h("button", "${attr("class", if (current == id) { "mg-tab on" } else { "mg-tab" })}${attr("phx-click", "set_only")}${attr("phx-value-only", id)}", htext(label))
    }

    let psHead(state: ShowState): List<AnyValue> {
      let toggle: List<AnyValue> = if (state.revisions.length > 0) {
        h("button", "${attr("class", if (state.changesOn) { "mg-btn sm ghost mg-chg-toggle on" } else { "mg-btn sm ghost mg-chg-toggle" })}${attr("phx-click", "toggle_changes")}",
          htext(if (state.changesOn) { "Back to the notes" } else { "Show what changed" }))
      } else { [] };
      h("div", attr("class", "flex items-baseline gap-4 flex-wrap"), [
        h("h2", attr("class", "mg-label"), htext("The page")),
        toggle,
        h("div", "${attr("class", "mg-tabs")}${attr("id", "read-filters")}", [
          psFilter(state, "all", "Everything"),
          psFilter(state, "beats", "Beats"),
          psFilter(state, "connections", "Connections"),
          psFilter(state, "tensions", "Tensions"),
        ]),
        h("span", attr("class", "mg-hint mt-0 ml-auto"), htext("Notes sit beside the sentence that caused them. The highlight is the span they are anchored to.")),
      ])
    }

## The view

    let psProseColumn(state: ShowState, page: List<ReadingSection>): List<AnyValue> {
      h("div", "${attr("class", "mg-read-body")}${attr("id", "read-body")}${attr("phx-hook", "SummaryVault")}${attr("data-editable", if (state.mine) { "true" } else { "false" })}",
        page.map { (sec: ReadingSection): List<AnyValue> =>
          [
            showSectionHead(state, sec.section),
            sec.blocks.map { (b: ReadingBlock): List<AnyValue> => psBlock(state, sec.section, b) },
          ]
        })
    }

    export let renderReadView(ctx: Ctx, state: ShowState): List<AnyValue> {
      let page = state.page;
      let body: List<AnyValue> = if (page == null) {
        h("p", attr("class", "mg-empty mt-6"), htext("Nothing read yet."))
      } else if (page.length == 0) {
        h("p", attr("class", "mg-empty mt-6"), htext("Nothing read yet."))
      } else {
        [
          showMinimap(readingOutline(page), state.work.wordCount),
          h("div", "${attr("class", if (state.chatOpen) { "mg-read mt-6 collapsed" } else { "mg-read mt-6" })}${attr("id", "read-rail")}${attr("phx-hook", "MarginNotes")}", [
            showDocBox(state),
            psProseColumn(state, page),
            if (state.changesOn) { psChangesRail(state) } else { psNotesRail(page) },
          ]),
        ]
      };
      h("div", "", [psHead(state), body])
    }
