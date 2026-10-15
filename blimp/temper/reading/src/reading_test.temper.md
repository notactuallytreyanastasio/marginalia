# Tests for the reading page

Ported from `test/marginalia/reading_test.exs` (18 tests): the page view. Notes
sit beside the paragraph that caused them, which is only possible because every
note carries a span verified against the source.

    let { Db, dbOpen } = import("db/src");
    let { Scope } = import("accounts/src");
    let {
      Work, Section, GraphNode, NodeParams, worksListSections, worksInsertNodes, worksLink,
    } = import("works/src");
    let { sysJoin } = import("sys/src");

    let readingBody(): String {
      "# A draft\n\nShe had been standing at the window for an hour before anyone noticed.\n\nThe kettle went cold on the counter, and nobody moved to fill it again.\n\nBy evening the argument had found its real subject, which was not the kettle.\n"
    }

    class ReadingFx(public db: Db, public me: Scope, public work: Work, public section: Section) {}

    let readingFixture(): ReadingFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = rdUser(db, "a@example.com");
      let work = rdWork(db, me, "W", readingBody());
      new ReadingFx(db, me, work, rdFirst(db, work))
    }

    let withNotes(page: List<ReadingSection>): List<ReadingBlock> {
      let out = new ListBuilder<ReadingBlock>();
      for (let s of page) {
        for (let b of s.blocks) {
          if (!b.notes.isEmpty) { out.add(b); }
        }
      }
      out.toList()
    }

How many notes of this kind the page placed in its blocks.

    let placedOf(page: List<ReadingSection>, kind: String): Int {
      var n = 0;
      for (let b of withNotes(page)) {
        for (let note of b.notes) {
          if (note.kind == kind) { n += 1; }
        }
      }
      n
    }

    let pageOf(fx: ReadingFx, only: String?): List<ReadingSection> throws Bubble {
      readingPage(fx.db, fx.work, new ReadingOptions(only, null, null))
    }

## Placing notes

    test("reading: a note lands on the paragraph its quote came from") { test =>
      let fx = readingFixture();
      rdBeat(fx.db, fx.work, fx.section, "The kettle goes cold", "The kettle went cold on the counter");
      let pages = pageOf(fx, null);
      rdInt(test, pages.length, 1);
      let page = pages[0];
      rdInt(test, page.unplaced.length, 0);
      let placed = withNotes(pages);
      rdInt(test, placed.length, 1);
      let block = placed[0];
      rdInt(test, block.notes.length, 1);
      rdText(test, block.notes[0].title, "The kettle goes cold");
      rdHas(test, block.text, "kettle went cold");
      rdText(test, rdOr(block.mark, "<none>"), "The kettle went cold on the counter");
      // every paragraph carries a stable id the rail can point a note at
      rdText(test, block.ref, "s1p2");
    }

    test("reading: a note whose quote is nowhere is kept, not silently dropped") { test =>
      let fx = readingFixture();
      rdBeat(fx.db, fx.work, fx.section, "Invented", "a sentence that is not in this draft at all");
      let page = pageOf(fx, null)[0];
      rdInt(test, withNotes([page]).length, 0);
      rdInt(test, page.unplaced.length, 1);
      rdText(test, page.unplaced[0].title, "Invented");
    }

    test("reading: a note with no quote is unplaced") { test =>
      let fx = readingFixture();
      rdBeat(fx.db, fx.work, fx.section, "Bare", null);
      let page = pageOf(fx, null)[0];
      rdInt(test, page.unplaced.length, 1);
    }

    test("reading: a quote is placed once, in the first paragraph that holds it") { test =>
      let fx = readingFixture();
      rdBeat(fx.db, fx.work, fx.section, "Kettle", "the kettle");
      rdBeat(fx.db, fx.work, fx.section, "Kettle again", "The kettle went cold on the counter");
      let placed = withNotes(pageOf(fx, null));
      // "the kettle" is first found in the paragraph with the kettle going cold, case folded;
      // the mark is the draft's own wording of it, not the quote's
      rdInt(test, placed.length, 1);
      rdInt(test, placed[0].notes.length, 2);
      // one highlight per paragraph: the first quote found in it
      rdText(test, rdOr(placed[0].mark, "<none>"), "The kettle");
    }

    test("reading: refs are s<ordinal>p<index> down the section") { test =>
      let fx = readingFixture();
      let blocks = readingBlocks(fx.section);
      rdInt(test, blocks.length, 4);
      rdText(test, blocks[0].ref, "s1p0");
      rdText(test, blocks[3].ref, "s1p3");
      rdText(test, blocks[0].text, "# A draft");
    }

    test("reading: the entries are every block of the draft in order") { test =>
      let fx = readingFixture();
      rdBeat(fx.db, fx.work, fx.section, "The kettle goes cold", "The kettle went cold on the counter");
      let entries = readingEntries(fx.db, fx.work);
      rdInt(test, entries.length, 4);
      rdText(test, entries[2].ref, "s1p2");
      rdInt(test, entries[2].notes.length, 1);
    }

    test("reading: one section can be asked for by ordinal") { test =>
      let fx = readingFixture();
      rdInt(test, readingPage(fx.db, fx.work, new ReadingOptions(null, 1, null)).length, 1);
      rdInt(test, readingPage(fx.db, fx.work, new ReadingOptions(null, 2, null)).length, 0);
    }

## The draft's own markdown

    let codeBody(): String {
      "Create a new file:\n\n```elixir\ndefmodule Producer do\n  use GenStage\n\n  def handle_demand(demand, state) do\n    {:noreply, [], state}\n  end\nend\n```\n\nThe consumer is in control. It's **impossible** to overwhelm it.\n\n1. First principle\n2. Second principle\n"
    }

    let blockStarting(blocks: List<String>, prefix: String): String {
      var i = 0;
      while (i < blocks.length) {
        if (readingStartsWith(blocks[i], prefix)) { return blocks[i]; }
        i += 1;
      }
      ""
    }

    let blockHolding(blocks: List<String>, part: String): String {
      var i = 0;
      while (i < blocks.length) {
        if (readingContains(blocks[i], part)) { return blocks[i]; }
        i += 1;
      }
      ""
    }

A fence contains blank lines, and splitting on those tore it in half: the draft
came out as reflowed serif with stray backticks in it.

    test("reading: a fenced code block survives the blank lines inside it") { test =>
      let fence = blockStarting(readingSplit(codeBody()), "```");
      rdTrue(test, !fence.isEmpty, "the fence should be one block");
      rdHas(test, fence, "handle_demand");
      rdHas(test, fence, "end\n```");
    }

    test("reading: a fence renders as code, not as prose") { test =>
      let fence = blockStarting(readingSplit(codeBody()), "```");
      let html = readingRenderBlock(fence, null, "x", null);
      rdHas(test, html, "<pre><code");
      rdLacks(test, html, "`");
    }

    test("reading: a list renders as a list") { test =>
      let list = blockStarting(readingSplit(codeBody()), "1.");
      rdHas(test, readingRenderBlock(list, null, "y", null), "<ol>");
    }

    test("reading: a highlight survives rendering, even across inline markup") { test =>
      let para = blockHolding(readingSplit(codeBody()), "impossible");
      let html = readingRenderBlock(para, "It's **impossible** to overwhelm it", "z", null);
      rdHas(test, html, "<mark id=\"anchor-z\">");
      // the bold inside the span is still bold, and the mark wraps it
      rdHas(test, html, "<strong>impossible</strong>");
      rdHas(test, html, "</mark>");
    }

    test("reading: a block with no highlight gets no mark") { test =>
      let para = blockHolding(readingSplit(codeBody()), "impossible");
      rdLacks(test, readingRenderBlock(para, null, "z", null), "<mark");
    }

    test("reading: the sentinels never reach the page") { test =>
      let para = blockHolding(readingSplit(codeBody()), "impossible");
      let html = readingRenderBlock(para, "The consumer is in control", "z", null);
      rdLacks(test, html, "\u{E000}");
      rdLacks(test, html, "\u{E001}");
    }

## Trimming

    class ReadingTrimFx(public fx: ReadingFx, public a: GraphNode, public b: GraphNode) {}

    let trimFixture(): ReadingTrimFx throws Bubble {
      let fx = readingFixture();
      let pa = new NodeParams(fx.work.id, "beat", "The window");
      pa.quote = "standing at the window for an hour";
      let pb = new NodeParams(fx.work.id, "beat", "The kettle");
      pb.quote = "The kettle went cold on the counter";
      let nodes = worksInsertNodes(fx.db, fx.work.id, fx.section.id, [pa, pb]);
      worksLink(fx.db, fx.work.id, nodes[0].id, nodes[1].id, "tension", 0, "the two do not sit together");
      new ReadingTrimFx(fx, nodes[0], nodes[1])
    }

    test("reading: everything shows beats and connections") { test =>
      let t = trimFixture();
      let page = pageOf(t.fx, null);
      rdInt(test, placedOf(page, "beat"), 2);
      rdInt(test, placedOf(page, "tension"), 1);
    }

    test("reading: beats alone") { test =>
      let t = trimFixture();
      let page = pageOf(t.fx, "beats");
      rdInt(test, placedOf(page, "beat"), 2);
      rdInt(test, placedOf(page, "tension"), 0);
    }

    test("reading: tensions alone") { test =>
      let t = trimFixture();
      let page = pageOf(t.fx, "tensions");
      rdInt(test, placedOf(page, "beat"), 0);
      rdInt(test, placedOf(page, "tension"), 1);
    }

    test("reading: connections alone, shown on the beat they start from, titled by the label") { test =>
      let t = trimFixture();
      let placed = withNotes(pageOf(t.fx, "connections"));
      rdInt(test, placed.length, 1);
      rdText(test, placed[0].notes[0].title, "tension with The kettle");
      rdText(test, placed[0].notes[0].key, "conn:${t.a.id.toString()}:${t.b.id.toString()}:tension");
      rdText(test, rdOr(placed[0].notes[0].body, "?"), "the two do not sit together");
    }

## focus

    test("reading: a beat carries its own section in full") { test =>
      let fx = readingFixture();
      let n = rdBeat(fx.db, fx.work, fx.section, "The kettle", "The kettle went cold on the counter");
      let focus = readingFocus(fx.db, fx.work, "beat:${n.id.toString()}");
      rdTrue(test, focus != null, "found");
      if (focus != null) {
        rdText(test, focus.kind, "beat");
        rdText(test, focus.title, "The kettle");
        rdInt(test, focus.sections.length, 1);
        rdInt(test, focus.sections[0].id, fx.section.id);
      }
    }

    test("reading: a connection carries both ends' sections") { test =>
      let fx = readingFixture();
      let two = "# One\n\n${rdRepeat("early ", 300)}\n\n# Two\n\n${rdRepeat("later ", 300)}";
      let work2 = rdWork(fx.db, fx.me, "Two", two);
      let sections = worksListSections(fx.db, work2.id);
      rdInt(test, sections.length, 2);
      let a = rdBeat(fx.db, work2, sections[0], "A", null);
      let b = rdBeat(fx.db, work2, sections[1], "B", null);
      worksLink(fx.db, work2.id, a.id, b.id, "pays_off", 0, "A promises what B delivers");
      let key = "conn:${a.id.toString()}:${b.id.toString()}:pays_off";
      let focus = readingFocus(fx.db, work2, key);
      rdTrue(test, focus != null, "found");
      if (focus != null) {
        rdText(test, focus.kind, "pays_off");
        rdText(test, rdOr(focus.body, "?"), "A promises what B delivers");
        rdInt(test, focus.sections.length, 2);
        rdText(test, rdJoin(focus.sections.map { (s: Section): String => s.ordinal.toString() }), "1|2");
        rdTrue(test, fx.section.id != sections[0].id, "the second work's sections are distinct");
        rdText(test, focus.title, "A  —pays off→  B");
      }
    }

    test("reading: a nonsense key is nil rather than a crash") { test =>
      let fx = readingFixture();
      rdTrue(test, readingFocus(fx.db, fx.work, "beat:999999") == null, "no such node");
      rdTrue(test, readingFocus(fx.db, fx.work, "garbage") == null, "no such kind of key");
      rdTrue(test, readingFocus(fx.db, fx.work, "conn:1:2") == null, "too few parts");
    }

## A highlight that lands on markdown syntax

A beat is anchored to a literal substring of the draft, and the draft is
markdown, so a quote of a bolded sentence carries its `**` along. Wrapping that
in the mark sentinel used to break the delimiter pair and print four asterisks
at the reader.

    test("reading: emphasis around the quote still renders, and the mark sits inside it") { test =>
      let text = "Prudence. **We must slow the pace. Progress will still seem fast.** Two things.";
      let quote = "**We must slow the pace. Progress will still seem fast.**";
      let html = readingRenderBlock(text, quote, "r1", null);
      rdLacks(test, html, "**");
      rdHas(test, html, "<strong>");
      rdHas(test, html, "<mark id=\"anchor-r1\">We must slow the pace.");
    }

    test("reading: italics at the edges are trimmed out of the mark too") { test =>
      let html = readingRenderBlock("Before *the marked words* after.", "*the marked words*", "r2", null);
      rdHas(test, html, "<em>");
      rdHas(test, html, "<mark");
      rdLacks(test, html, "*the marked");
    }

    test("reading: code fences at the edges are trimmed out of the mark too") { test =>
      let html = readingRenderBlock("Before `the marked words` after.", "`the marked words`", "r2", null);
      rdHas(test, html, "<code>");
      rdHas(test, html, "<mark");
      rdLacks(test, html, "`the marked");
    }

    test("reading: a quote that is only delimiters marks nothing rather than crashing") { test =>
      let html = readingRenderBlock("Some prose with ** in it somewhere.", "**", "r3", null);
      rdTrue(test, !html.isEmpty, "a string came back");
    }

    test("reading: an ordinary quote is untouched") { test =>
      let html = readingRenderBlock(
        "She had been standing at the window for an hour.", "standing at the window", "r4", null,
      );
      rdHas(test, html, "<mark id=\"anchor-r4\">standing at the window</mark>");
    }

## Rows, plain text, outline, citing

    test("reading: rows close on the annotated block and the tail is a row of its own") { test =>
      let note = new ReadingNote("beat:1", null, "beat", null, "t", null, false);
      let blocks = [
        new ReadingBlock("a", null, [], "s1p0"),
        new ReadingBlock("b", null, [note], "s1p1"),
        new ReadingBlock("c", null, [], "s1p2"),
        new ReadingBlock("d", null, [], "s1p3"),
      ];
      let rs = readingRows(blocks);
      rdInt(test, rs.length, 2);
      rdInt(test, rs[0].blocks.length, 2);
      rdInt(test, rs[0].notes.length, 1);
      rdInt(test, rs[1].blocks.length, 2);
      rdInt(test, rs[1].notes.length, 0);
      rdInt(test, readingRows([]).length, 0);
    }

    test("reading: plain gives a quote as it reads on the page") { test =>
      rdText(test, readingPlain("## A [link](https://x.test) with `code` and *stress*_ed_"), "A link with code and stressed");
      rdText(test, readingPlain("  one\n\n  two   three  "), "one two three");
      rdText(test, readingPlain(null), "");
    }

    test("reading: heading, level and text") { test =>
      rdTrue(test, readingIsHeading("## Step 4"), "two hashes and a word");
      rdTrue(test, !readingIsHeading("#hash"), "no space after");
      rdTrue(test, !readingIsHeading("####### seven"), "seven is not a heading");
      rdTrue(test, !readingIsHeading("# "), "nothing after the space");
      rdInt(test, readingHeadingLevel("### three"), 3);
      rdInt(test, readingHeadingLevel("not a heading"), 1);
      rdText(test, readingHeadingText("## Step 4:  Creating "), "Step 4:  Creating");
    }

    test("reading: the outline is section titles plus inner headings, without saying a title twice") { test =>
      let fx = readingFixture();
      let outline = readingOutline(pageOf(fx, null));
      // the section is called "Section 1" and its one heading "A draft": both are listed
      rdInt(test, outline.length, 2);
      rdText(test, outline[0].id, "sec-1");
      rdInt(test, outline[0].level, 0);
      rdText(test, outline[0].title, "Section 1");
      rdText(test, outline[1].id, "block-s1p0");
      rdInt(test, outline[1].level, 1);
      rdText(test, outline[1].title, "A draft");
      let blocks = [
        new ReadingBlock("# A draft", null, [], "s1p0"),
        new ReadingBlock("## Inner heading", null, [], "s1p1"),
        new ReadingBlock("Not a heading.", null, [], "s1p2"),
      ];
      // a heading that says what its section's title already says is not said twice
      let named = rdWithTitle(fx.section, "a DRAFT");
      let hand = readingOutline([new ReadingSection(named, blocks, [])]);
      rdInt(test, hand.length, 2);
      rdText(test, hand[1].id, "block-s1p1");
      rdInt(test, hand[1].level, 2);
      rdText(test, hand[1].title, "Inner heading");
    }

    test("reading: cite verifies a selection against the draft") { test =>
      let fx = readingFixture();
      let cite = readingCite(fx.db, fx.work, "The kettle went cold on the counter");
      rdTrue(test, cite != null, "found");
      if (cite != null) {
        rdText(test, cite.text, "The kettle went cold on the counter");
        rdInt(test, cite.ordinal, 1);
        rdText(test, cite.section, "Section 1");
      }
      rdTrue(test, readingCite(fx.db, fx.work, "a sentence nobody wrote") == null, "refused");
    }

    test("reading: grounding walks realises and asks_about edges back to beats") { test =>
      let fx = readingFixture();
      let early = rdBeat(fx.db, fx.work, fx.section, "Early", "standing at the window");
      let late = rdBeat(fx.db, fx.work, fx.section, "Late", "not the kettle");
      let spineParams = new NodeParams(fx.work.id, "spine", "What it is about");
      let spine = worksInsertNodes(fx.db, fx.work.id, null, [spineParams])[0];
      worksLink(fx.db, fx.work.id, spine.id, late.id, "realises", 0, "it lands here");
      worksLink(fx.db, fx.work.id, early.id, spine.id, "asks_about", 0, "it opens here");
      worksLink(fx.db, fx.work.id, spine.id, early.id, "develops", 0, "not counted");
      let g = readingGrounding(fx.db, fx.work, spine.id);
      rdInt(test, g.beats.length, 2);
      rdInt(test, g.sections.length, 1);
      rdTrue(test, g.beats[0].id < g.beats[1].id, "same section, so by id");
      rdText(test, rdOr(g.beats[0].why, "?"), "it opens here");
    }
