# The read view: the margin and the contents rail

The notes beside the draft: how they are piled into slots, how a slot is drawn
as a card or a deck, and the map of the draft down the left.

Layout is the stylesheet's and the `MarginNotes` hook's: the notes are drawn in
a rail that is a sibling of the prose, as slots carrying `data-anchor`, and the
hook measures the highlights and lines them up. The ids and class names here
are the contract with it (`read-rail`, `read-body`, `anchor-<ref>`,
`mg-note-slot`, `collapsed`).

    let { Ctx, cMutter } = import("webcore/src");
    let { h, hv, htext, hraw, attr, markdownToHtml } = import("html/src");
    let { sysStringReplace, sysGraphemeTake } = import("sys/src");
    let { Section, Revision } = import("works/src");
    let {
      ReadingSection, ReadingBlock, ReadingNote, ReadingOutline, ReadingPreview, RewriteCandidate,
      readingRenderBlock, readingOutline, summaryCurrent, summaryDrift,
      rewriteSpanLabel, rewriteSpanExtent,
    } = import("reading/src");
    let { ChatTurn, Conversation, ChatThread } = import("chat/src");
    let { graphIso } = import("analysis/src");
    let { Row } = import("core/src");
    let { JsonSyntaxTree } = import("std/json");

## The margin's piles

`piles/1`. Four or fewer notes: one slot each, because a pile that fits is
easier to read than a pile with controls on it, and most paragraphs carry one or
two notes. Past four they are grouped by kind, the groups in the order of the
first note of each kind, and a kind with several in it becomes one slot you flip
through. The case that forced this is a section whose beats could not be
anchored: those have no paragraph to sit beside, so every one stacks at the top
of the rail. Nothing is dropped; a note behind a pager is still on the page.

    let psKnown(kinds: List<String>, kind: String): Boolean {
      var i = 0;
      while (i < kinds.length) {
        if (kinds[i] == kind) { return true; }
        i += 1;
      }
      false
    }

    let psKindsOf(notes: List<ReadingNote>): List<String> {
      let kinds = new ListBuilder<String>();
      var i = 0;
      while (i < notes.length) {
        if (!psKnown(kinds.toList(), notes[i].kind)) { kinds.add(notes[i].kind); }
        i += 1;
      }
      kinds.toList()
    }

    let psOfKind(notes: List<ReadingNote>, kind: String): List<ReadingNote> {
      let out = new ListBuilder<ReadingNote>();
      var i = 0;
      while (i < notes.length) {
        if (notes[i].kind == kind) { out.add(notes[i]); }
        i += 1;
      }
      out.toList()
    }

    export let showPiles(notes: List<ReadingNote>): List<List<ReadingNote>> {
      let out = new ListBuilder<List<ReadingNote>>();
      if (notes.length <= 4) {
        var i = 0;
        while (i < notes.length) {
          out.add([notes[i]]);
          i += 1;
        }
      } else {
        let kinds = psKindsOf(notes);
        var k = 0;
        while (k < kinds.length) {
          let kind = kinds[k];
          out.add(psOfKind(notes, kind));
          k += 1;
        }
      }
      out.toList()
    }

`deck/1`. One slot: a pile of one is a card; a pile of several is a card with
the rest behind it and a pager under it. Every card is rendered either way and
the `Deck` hook only changes which one is visible, so there is no round trip to
read the next note and the slot does not change height when you flip.

    let psKindWords(kind: String): String { sysStringReplace(kind, "_", " ") }

    let psCard(n: ReadingNote, i: Int, located: Boolean): List<AnyValue> {
      let body = n.body;
      let why: List<AnyValue> = if (body != null) { h("span", attr("class", "why"), htext(body)) } else { [] };
      h("button", "${attr("class", showCls(["mg-note", n.kind, if (i == 0) { "on" } else { "" }]))}${attr("phx-click", "discuss")}${attr("phx-value-key", n.key)}${attr("title", "Talk about this")}", [
        h("span", attr("class", "who"), htext("${psKindWords(n.kind)}${if (located) { "" } else { " · not located" }}")),
        h("span", attr("class", "said"), htext(n.title)),
        why,
      ])
    }

    let psDeck(pile: List<ReadingNote>, located: Boolean): List<AnyValue> {
      let first = pile.getOr(0, new ReadingNote("", null, "", null, "", null, false));
      let cards = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < pile.length) {
        cards.add(psCard(pile[i], i, located));
        i += 1;
      }
      let nav: List<AnyValue> = if (pile.length > 1) {
        h("div", attr("class", "nav"), [
          h("button", "${attr("type", "button")}${attr("data-step", "-1")}${attr("aria-label", "Previous")}", htext("‹")),
          h("span", attr("class", "n"), htext("1 / ${pile.length.toString()}")),
          h("button", "${attr("type", "button")}${attr("data-step", "1")}${attr("aria-label", "Next")}", htext("›")),
        ])
      } else { [] };
      h("div", "${attr("class", "mg-deck")}${attr("id", "deck-${first.key}")}${attr("phx-hook", "Deck")}", [
        h("div", attr("class", "cards"), cards.toList()),
        "\n",
        nav,
      ])
    }

    export let showSlot(pile: List<ReadingNote>, located: Boolean, anchor: String?): List<AnyValue> {
      let first = pile.getOr(0, new ReadingNote("", null, "", null, "", null, false));
      let cls = showCls([
        "mg-note-slot", first.kind,
        if (pile.length > 1) { "deck" } else { "" },
        if (pile.length > 2) { "deep" } else { "" },
      ]);
      h("div", "${attr("class", cls)}${attr("data-anchor", anchor)}", psDeck(pile, located))
    }

## The contents rail

`minimap/1`. A map of the draft, drawn to scale: every row is sized by its word
count, so a 1,600-word section gets five times the block a 320-word one does.
A sub-heading carries no count of its own and a very short section would
collapse to an unclickable hairline, so every row is floored at about a
fortieth of the draft. Proportions come from the section sums, but the headline
number is the work's own: two different word counts on one screen reads as a bug.

    let psGrow(e: ReadingOutline, floor: Int): Int {
      let words = e.words;
      let own = if (words != null) { words } else { 0 };
      if (own > floor) { own } else { floor }
    }

    let psMapRow(e: ReadingOutline, floor: Int): List<AnyValue> {
      let w = e.words;
      let count: List<AnyValue> = if (w != null) { h("span", attr("class", "w"), htext("${w.toString()}w")) } else { [] };
      h("li", "${attr("style", "flex-grow:${psGrow(e, floor).toString()}")}${attr("data-full", e.title)}",
        h("a", "${attr("href", "#${e.id}")}${attr("class", "l${e.level.toString()}")}${attr("data-target", e.id)}", [
          h("span", attr("class", "t"), htext(e.title)),
          count,
        ]))
    }

    export let showMinimap(entries: List<ReadingOutline>, words: Int): List<AnyValue> {
      if (entries.length <= 1) { return []; }
      var total = 0;
      for (let e of entries) {
        let w = e.words;
        if (w != null) { total += w; }
      }
      let sum = if (total > 1) { total } else { 1 };
      let floor = if (sum / 40 > 1) { sum / 40 } else { 1 };
      h("nav", "${attr("class", "mg-map")}${attr("id", "minimap")}${attr("phx-hook", "Minimap")}", [
        h("button", "${attr("class", "mg-map-rail")}${attr("aria-label", "Contents")}${attr("aria-expanded", "false")}",
          entries.map { (e: ReadingOutline): List<AnyValue> =>
            h("i", "${attr("class", "t l${e.level.toString()}")}${attr("style", "flex-grow:${psGrow(e, floor).toString()}")}", [])
          }),
        h("div", attr("class", "mg-map-panel"), [
          h("div", attr("class", "mg-map-head"), [
            h("span", "", htext("contents")),
            h("span", attr("class", "n"), htext("${words.toString()} words")),
          ]),
          h("ol", attr("class", "mg-map-body"),
            entries.map { (e: ReadingOutline): List<AnyValue> => psMapRow(e, floor) }),
        ]),
      ])
    }
