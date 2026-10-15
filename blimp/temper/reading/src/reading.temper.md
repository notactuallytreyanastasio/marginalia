# Reading

`Marginalia.Reading`: the draft itself, with the notes in the margin beside
the lines that caused them.

Every other view in the app shows the map. This one shows the page. Because
each beat carries a span verified to be a literal substring of the writer's
own text, the exact paragraph it came from can be found and the note put
beside it. A note whose quote cannot be located in any paragraph is not
dropped; it is attached to the section instead, and says so.

    let { Db } = import("db/src");
    let {
      Work, Section, GraphNode, GraphEdge, FullConnection,
      worksListSections, worksNodes, worksAllConnections, worksListEdges,
    } = import("works/src");
    let { markdownToHtmlSoft, markdownParagraphs } = import("html/src");
    let { diff, Part } = import("core/src");
    let { sysStringReplace, sysJoin, sysUtf8Downcase } = import("sys/src");

## Blocks

Top-level markdown blocks (`Reading.split/1`): what blank lines separate,
except that a fenced code block is one block however many blank lines it
holds. `html` already has this, as `markdownParagraphs`.

    export let readingSplit(body: String): List<String> { markdownParagraphs(body) }

A section's blocks with their refs, `s<ordinal>p<index>` (zero-based, headings
and code included), and nothing placed in them.

    export let readingBlocks(section: Section): List<ReadingBlock> {
      let paragraphs = markdownParagraphs(section.body);
      let out = new ListBuilder<ReadingBlock>();
      var i = 0;
      while (i < paragraphs.length) {
        out.add(new ReadingBlock(paragraphs[i], null, [], readingRef(section.ordinal, i)));
        i += 1;
      }
      out.toList()
    }

    export let readingRef(ordinal: Int, index: Int): String {
      "s${ordinal.toString()}p${index.toString()}"
    }

## Rendering a block

Private-use characters are markdown-inert and not something a draft contains.
They mark the anchored span in the *source* so it survives being rendered and
can be turned into a `<mark>` afterwards. Doing it the other way round means
either literal asterisks on the page or a highlight that no longer matches the
draft character for character.

Each is a function because a `\u{...}` literal handed straight to a
`@connected` call breaks the frontend.

    let readingMarkOpen(): String { "\u{E000}" }
    let readingMarkClose(): String { "\u{E001}" }
    let readingSwapOpen(): String { "\u{E002}" }
    let readingSwapClose(): String { "\u{E003}" }
    let readingDelOpen(): String { "\u{E004}" }
    let readingDelClose(): String { "\u{E005}" }

One block, rendered as markdown with its anchored span marked, or with a
rewrite shown in place (`preview`): the original is found in the block and
replaced by the word diff of original against replacement, deletions inside
`<del class="mg-cut">` and insertions inside `<ins class="mg-swap">`. A
preview whose original is not in the block is ignored.

`ref` is the string put after `anchor-` in the mark's id.

    export let readingRenderBlock(
      text: String, mark: String?, ref: String, preview: ReadingPreview?,
    ): String {
      if (preview != null) {
        let original = preview.original;
        if (readingIndexOf(text, original) >= 0) {
          let parts = text.split(original);
          let before = parts[0];
          let after = sysJoin(parts.slice(1, parts.length), original);
          let diffed = readingDiffed(diff(original, preview.text));
          let html = readingRenderMarkdown("${before}${diffed}${after}", null, ref);
          let a = sysStringReplace(html, readingSwapOpen(), "<ins class=\"mg-swap\">");
          let b = sysStringReplace(a, readingSwapClose(), "</ins>");
          let c = sysStringReplace(b, readingDelOpen(), "<del class=\"mg-cut\">");
          return sysStringReplace(c, readingDelClose(), "</del>");
        }
      }
      readingRenderMarkdown(text, mark, ref)
    }

    let readingDiffed(parts: List<Part>): String {
      let out = new ListBuilder<String>();
      for (let part of parts) {
        if (part.kind == "del") {
          out.add(readingDelOpen());
          out.add(part.text);
          out.add(readingDelClose());
        } else if (part.kind == "ins") {
          out.add(readingSwapOpen());
          out.add(part.text);
          out.add(readingSwapClose());
        } else {
          out.add(part.text);
        }
      }
      sysJoin(out.toList(), "")
    }

The highlight is pulled inside any emphasis markers at its edges. A beat is
anchored to a literal substring of the draft, and the draft is markdown, so a
quote of a bolded sentence carries its `**` along with it. Wrapping that whole
thing in the mark sentinel puts the sentinel between the delimiter and the
rest of the paragraph, and the parser then fails to pair the run: the reader
gets a highlighted sentence with four literal asterisks in it. Trimming the
delimiters out of the span fixes it at the only layer that can. A mark made
only of delimiters yields an empty `<mark>` pair.

    let readingIsDelimiter(cp: Int): Boolean {
      cp == 42 || cp == 95 || cp == 96 || cp == 126
    }

    let readingRenderMarkdown(text: String, mark: String?, ref: String): String {
      var source = text;
      if (mark != null) {
        if (readingIndexOf(text, mark) >= 0) {
          let parts = text.split(mark);
          let before = parts[0];
          let after = sysJoin(parts.slice(1, parts.length), mark);
          let cps = readingCodePoints(mark);
          var left = 0;
          while (left < cps.length && readingIsDelimiter(cps[left])) { left += 1; }
          var right = cps.length;
          while (right > left && readingIsDelimiter(cps[right - 1])) { right -= 1; }
          let lead = readingStringOf(cps, 0, left);
          let core = readingStringOf(cps, left, right);
          let trail = readingStringOf(cps, right, cps.length);
          source = "${before}${lead}${readingMarkOpen()}${core}${readingMarkClose()}${trail}${after}";
        }
      }
      // A draft, not a reply: a newline inside a paragraph is a sentence end,
      // not a line break the writer wants on the page.
      let html = markdownToHtmlSoft(source);
      let opened = sysStringReplace(html, readingMarkOpen(), "<mark id=\"anchor-${ref}\">");
      sysStringReplace(opened, readingMarkClose(), "</mark>")
    }

## The page

A note and the section it belongs to are all the page needs of a node, so
that is what is collected: every beat, and every connection that starts at a
beat with a section, shown on that beat because that is where the writer is
standing when they need to know it goes somewhere.

    let readingLabel(edgeType: String): String {
      if (edgeType == "develops") {
        "develops →"
      } else if (edgeType == "pays_off") {
        "pays off →"
      } else if (edgeType == "requires") {
        "requires ←"
      } else if (edgeType == "tension") {
        "tension with"
      } else if (edgeType == "realises") {
        "realises"
      } else if (edgeType == "asks_about") {
        "asks about"
      } else {
        edgeType
      }
    }

    let readingNodeIn(nodes: List<GraphNode>, id: Int): GraphNode? {
      var i = 0;
      while (i < nodes.length) {
        if (nodes[i].id == id) { return nodes[i]; }
        i += 1;
      }
      null
    }

    let readingCollect(db: Db, work: Work, only: String?): List<ReadingNote> throws Bubble {
      let nodes = worksNodes(db, work.id);
      let beatNotes = new ListBuilder<ReadingNote>();
      for (let n of nodes) {
        if (n.nodeType == "beat") {
          beatNotes.add(new ReadingNote(
            "beat:${n.id.toString()}", n.sectionId, "beat", n.quote, n.title, n.body,
            n.status == "superseded",
          ));
        }
      }
      let connNotes = new ListBuilder<ReadingNote>();
      for (let c of worksAllConnections(db, work.id)) {
        let from = readingNodeIn(nodes, c.from.id);
        if (from != null) {
          let sectionId = from.sectionId;
          if (from.nodeType == "beat" && sectionId != null) {
            connNotes.add(new ReadingNote(
              "conn:${c.from.id.toString()}:${c.to.id.toString()}:${c.edgeType}",
              sectionId, c.edgeType, from.quote,
              "${readingLabel(c.edgeType)} ${c.to.title}", c.why, false,
            ));
          }
        }
      }
      if (only == "beats") {
        beatNotes.toList()
      } else if (only == "connections") {
        connNotes.toList()
      } else if (only == "tensions") {
        let tensions = new ListBuilder<ReadingNote>();
        for (let n of connNotes.toList()) {
          if (n.kind == "tension") { tensions.add(n); }
        }
        tensions.toList()
      } else {
        let all = new ListBuilder<ReadingNote>();
        all.addAll(beatNotes.toList());
        all.addAll(connNotes.toList());
        all.toList()
      }
    }

Putting each note beside its paragraph. For each paragraph in order, the notes
not yet placed whose quote is in it are placed there, and the first span found
among them is the paragraph's one highlight, so the marks never overlap and
the prose stays readable. The quotes are normalised once each and a paragraph
once, however many notes there are.

    let readingPlace(section: Section, notes: List<ReadingNote>): ReadingSection {
      let paragraphs = markdownParagraphs(section.body);
      let needles = new ListBuilder<String>();
      let placed = new ListBuilder<Boolean>();
      for (let n of notes) {
        needles.add(readingAnchorQuote(n.quote));
        placed.add(false);
      }
      let blocks = new ListBuilder<ReadingBlock>();
      var p = 0;
      while (p < paragraphs.length) {
        let para = paragraphs[p];
        let mine = new ListBuilder<ReadingNote>();
        var mark: String? = null;
        var norm: ReadingNorm? = null;
        var i = 0;
        while (i < notes.length) {
          if (!placed[i] && !needles[i].isEmpty) {
            if (norm == null) { norm = readingNormalize(para); }
            let have = norm;
            if (have != null) {
              let span = readingAnchorSpan(para, have, needles[i]);
              if (span != null) {
                if (!span.isEmpty) {
                  mine.add(notes[i]);
                  placed[i] = true;
                  if (mark == null) { mark = span; }
                }
              }
            }
          }
          i += 1;
        }
        blocks.add(new ReadingBlock(para, mark, mine.toList(), readingRef(section.ordinal, p)));
        p += 1;
      }
      let unplaced = new ListBuilder<ReadingNote>();
      var k = 0;
      while (k < notes.length) {
        if (!placed[k]) { unplaced.add(notes[k]); }
        k += 1;
      }
      new ReadingSection(section, blocks.toList(), unplaced.toList())
    }

The whole draft as sections of paragraphs, each paragraph carrying the notes
anchored inside it (`Reading.page/2`). `opts.only` trims what is shown,
`opts.section` keeps one section by ordinal, and `opts.notes` supplies the
margin from somewhere other than this work's own graph.

    export let readingPage(db: Db, work: Work, opts: ReadingOptions): List<ReadingSection> throws Bubble {
      let sections = worksListSections(db, work.id);
      let supplied = opts.notes;
      let notes = if (supplied != null) { supplied } else { readingCollect(db, work, opts.only) };
      let wanted = opts.section;
      let out = new ListBuilder<ReadingSection>();
      for (let s of sections) {
        let keep = if (wanted != null) { s.ordinal == wanted } else { true };
        if (keep) {
          let mine = new ListBuilder<ReadingNote>();
          for (let n of notes) {
            let sid = n.sectionId;
            if (sid != null && sid == s.id) { mine.add(n); }
          }
          out.add(readingPlace(s, mine.toList()));
        }
      }
      out.toList()
    }

What the read view lists: every block of the draft in order, each with its ref
`s<ordinal>p<index>`, its highlight and its notes.

    export let readingEntries(db: Db, work: Work): List<ReadingBlock> throws Bubble {
      let out = new ListBuilder<ReadingBlock>();
      for (let s of readingPage(db, work, readingNoOptions())) {
        out.addAll(s.blocks);
      }
      out.toList()
    }

## Focus

Everything the chat needs in order to talk about one note: the note, and the
section it sits in, or for a connection both sections, in full. `null` for a
key that does not parse or names a node that is gone.

    export let readingFocus(db: Db, work: Work, key: String): ReadingFocus? throws Bubble {
      let parts = key.split(":");
      if (parts.length == 2 && parts[0] == "beat") {
        let id = readingParseInt(parts[1]);
        if (id != null) {
          let node = readingNodeIn(worksNodes(db, work.id), id);
          if (node != null) {
            let ids = new ListBuilder<Int?>();
            ids.add(node.sectionId);
            return new ReadingFocus(
              "beat", node.title, node.body, node.quote,
              readingSectionsOf(worksListSections(db, work.id), ids.toList()),
            );
          }
        }
        return null;
      }
      if (parts.length == 4 && parts[0] == "conn") {
        let fromId = readingParseInt(parts[1]);
        let toId = readingParseInt(parts[2]);
        if (fromId != null) {
          if (toId != null) {
            let kind = parts[3];
            let nodes = worksNodes(db, work.id);
            let a = readingNodeIn(nodes, fromId);
            let b = readingNodeIn(nodes, toId);
            if (a != null) {
              if (b != null) {
                var why: String? = null;
                for (let c of worksAllConnections(db, work.id)) {
                  if (why == null && c.from.id == fromId && c.to.id == toId && c.edgeType == kind) {
                    why = c.why;
                  }
                }
                let ids = new ListBuilder<Int?>();
                ids.add(a.sectionId);
                ids.add(b.sectionId);
                let arrow = sysStringReplace(kind, "_", " ");
                return new ReadingFocus(
                  kind,
                  "${a.title}  —${arrow}→  ${b.title}",
                  why, a.quote,
                  readingSectionsOf(worksListSections(db, work.id), ids.toList()),
                );
              }
            }
          }
        }
        return null;
      }
      null
    }

The sections with these ids, in the order the ids are supplied, once each.

    let readingSectionsOf(sections: List<Section>, ids: List<Int?>): List<Section> {
      let out = new ListBuilder<Section>();
      for (let id of ids) {
        if (id != null) {
          let hit = readingSectionOf(sections, id);
          if (hit != null) {
            var seen = false;
            for (let o of out.toList()) {
              if (o.id == hit.id) { seen = true; }
            }
            if (!seen) { out.add(hit); }
          }
        }
      }
      out.toList()
    }

`Integer.parse/1` as the whole-key parse the Elixir did: an optional sign and
digits, whatever follows ignored; null when there are no digits.

    let readingParseInt(s: String): Int? {
      var i = String.begin;
      var negative = false;
      if (s.hasIndex(i) && (s[i] == 43 || s[i] == 45)) {
        negative = s[i] == 45;
        i = s.next(i);
      }
      let start = i;
      while (s.hasIndex(i) && s[i] >= 48 && s[i] <= 57) { i = s.next(i); }
      if (i == start) { return null; }
      let digits = s.slice(start, i);
      let n = digits.toInt32() orelse -1;
      if (n < 0) { return null; }
      if (negative) { 0 - n } else { n }
    }

## Rows

Group blocks into rail rows. One grid row per paragraph looks right until a
short paragraph carries three notes: the row grows to the height of the notes
and tears a hole in the prose. So a row is a run of un-annotated blocks plus
the one annotated block that ends it; trailing un-annotated blocks are a last
row with no notes.

    export let readingRows(blocks: List<ReadingBlock>): List<ReadingRow> {
      let rows = new ListBuilder<ReadingRow>();
      var run = new ListBuilder<ReadingBlock>();
      var i = 0;
      while (i < blocks.length) {
        let b = blocks[i];
        run.add(b);
        if (!b.notes.isEmpty) {
          rows.add(new ReadingRow(run.toList(), b.notes));
          run = new ListBuilder<ReadingBlock>();
        }
        i += 1;
      }
      if (run.length > 0) { rows.add(new ReadingRow(run.toList(), [])); }
      rows.toList()
    }

## Citing

Turn a passage the writer selected into a citation, or null: the draft's own
characters, found with the selection matcher, and not whatever a browser
selection dragged across markup picked up.

    export let readingCite(db: Db, work: Work, text: String): ReadingCite? throws Bubble {
      let hit = selectionLocate(db, work, text);
      if (hit != null) {
        new ReadingCite(hit.span, hit.section.title, hit.section.ordinal)
      } else {
        null
      }
    }

## Grounding

What a spine node, thread or question is grounded in: the `realises` and
`asks_about` edges touching it, walked back to the beats at the other end and
the sections and quotes underneath.

    export class ReadingGround(
      public id: Int,
      public title: String,
      public quote: String?,
      public why: String?,
      public section: Section?,
    ) {}

    export class ReadingGrounding(
      public beats: List<ReadingGround>,
      public sections: List<Section>,
    ) {}

Beats sort by their section's ordinal, then id. A beat with no section sorts
after every one that has one: the Elixir sorted `{nil, id}` against
`{ordinal, id}` as terms, and an atom is greater than a number (the survey said
nil first; running it says nil last).

    export let readingGrounding(db: Db, work: Work, nodeId: Int): ReadingGrounding throws Bubble {
      let nodes = worksNodes(db, work.id);
      let sections = worksListSections(db, work.id);
      let found = new ListBuilder<ReadingGround>();
      for (let e of worksListEdges(db, work.id)) {
        if (e.edgeType == "realises" || e.edgeType == "asks_about") {
          var otherId = -1;
          if (e.fromId == nodeId) {
            otherId = e.toId;
          } else if (e.toId == nodeId) {
            otherId = e.fromId;
          }
          if (otherId >= 0) {
            let other = readingNodeIn(nodes, otherId);
            if (other != null) {
              if (other.nodeType == "beat") {
                var seen = false;
                for (let g of found.toList()) {
                  if (g.id == other.id) { seen = true; }
                }
                if (!seen) {
                  found.add(new ReadingGround(
                    other.id, other.title, other.quote, e.rationale,
                    readingSectionOf(sections, other.sectionId),
                  ));
                }
              }
            }
          }
        }
      }
      let beats = found.toList().sorted { (a: ReadingGround, b: ReadingGround): Int =>
        let sa = a.section;
        let sb = b.section;
        let oa = if (sa != null) { sa.ordinal } else { 1000000000 };
        let ob = if (sb != null) { sb.ordinal } else { 1000000000 };
        if (oa != ob) { oa - ob } else { a.id - b.id }
      };
      let distinct = new ListBuilder<Section>();
      for (let g of beats) {
        let s = g.section;
        if (s != null) {
          var seen = false;
          for (let o of distinct.toList()) {
            if (o.id == s.id) { seen = true; }
          }
          if (!seen) { distinct.add(s); }
        }
      }
      new ReadingGrounding(beats, distinct.toList())
    }

    let readingSectionOf(sections: List<Section>, id: Int?): Section? {
      if (id != null) {
        var found: Section? = null;
        for (let s of sections) {
          if (s.id == id) { found = s; }
        }
        found
      } else {
        null
      }
    }

## Plain text

A quote as it reads on the page rather than as it sits in the source. Quotes
are copied out of the markdown, so a link comes back as `[words](url)` and a
call as `` `gen_stage` ``: fine for matching, wrong for showing someone their
own sentence back.

Links lose their target, the characters backtick, `*`, `_` and `~` go, a run
of `#` at the start of a line goes with the space after it, whitespace
collapses, and the ends are trimmed.

    export let readingPlain(text: String?): String {
      if (text != null) {
        let unlinked = readingUnlink(text);
        let bare = readingStripMarks(unlinked);
        let flat = readingStripHashes(bare);
        readingTrim(readingCollapse(flat, false))
      } else {
        ""
      }
    }

`\[([^\]]*)\]\([^)]*\)` becomes the text in the brackets.

    let readingUnlink(text: String): String {
      let cps = readingCodePoints(text);
      let n = cps.length;
      let out = new StringBuilder();
      var i = 0;
      while (i < n) {
        var consumed = 0;
        if (cps[i] == 91) {
          var j = i + 1;
          while (j < n && cps[j] != 93) { j += 1; }
          if (j < n && j + 1 < n && cps[j + 1] == 40) {
            var k = j + 2;
            while (k < n && cps[k] != 41) { k += 1; }
            if (k < n) {
              out.append(readingStringOf(cps, i + 1, j));
              consumed = k + 1 - i;
            }
          }
        }
        if (consumed > 0) {
          i += consumed;
        } else {
          out.appendCodePoint(cps[i]) orelse panic();
          i += 1;
        }
      }
      out.toString()
    }

    let readingStripMarks(text: String): String {
      let out = new StringBuilder();
      var runStart = String.begin;
      var i = String.begin;
      while (text.hasIndex(i)) {
        let cp = text[i];
        if (cp == 96 || cp == 42 || cp == 95 || cp == 126) {
          out.appendBetween(text, runStart, i);
          runStart = text.next(i);
        }
        i = text.next(i);
      }
      out.appendBetween(text, runStart, text.end);
      out.toString()
    }

`^#+\s*` in multiline mode: at the start of the text or of a line, a run of
`#` and then any whitespace (newlines included, as `\s*` has it).

    let readingStripHashes(text: String): String {
      let cps = readingCodePoints(text);
      let n = cps.length;
      let out = new StringBuilder();
      var i = 0;
      while (i < n) {
        let lineStart = i == 0 || cps[i - 1] == 10;
        if (lineStart && cps[i] == 35) {
          var j = i;
          while (j < n && cps[j] == 35) { j += 1; }
          while (j < n && readingIsAsciiSpace(cps[j])) { j += 1; }
          i = j;
        } else {
          out.appendCodePoint(cps[i]) orelse panic();
          i += 1;
        }
      }
      out.toString()
    }

## Headings and the outline

`^\#{1,6}\s+\S`: one to six `#`, whitespace, and then something that is not
whitespace.

    let readingHashes(text: String): Int {
      var n = 0;
      var i = String.begin;
      while (text.hasIndex(i) && text[i] == 35) {
        n += 1;
        i = text.next(i);
      }
      n
    }

    export let readingIsHeading(text: String): Boolean {
      let n = readingHashes(text);
      if (n < 1 || n > 6) { return false; }
      var i = String.begin;
      var k = 0;
      while (k < n) { i = text.next(i); k += 1; }
      var spaces = 0;
      while (text.hasIndex(i) && readingIsAsciiSpace(text[i])) {
        spaces += 1;
        i = text.next(i);
      }
      spaces > 0 && text.hasIndex(i)
    }

The number of leading `#`, or 1 when it is not a heading's.

    export let readingHeadingLevel(text: String): Int {
      let n = readingHashes(text);
      if (n < 1 || n > 6) { return 1; }
      var i = String.begin;
      var k = 0;
      while (k < n) { i = text.next(i); k += 1; }
      if (text.hasIndex(i) && readingIsAsciiSpace(text[i])) { n } else { 1 }
    }

    export let readingHeadingText(text: String): String {
      var i = String.begin;
      while (text.hasIndex(i) && text[i] == 35) { i = text.next(i); }
      while (text.hasIndex(i) && readingIsAsciiSpace(text[i])) { i = text.next(i); }
      readingTrim(text.slice(i, text.end))
    }

The draft's headings, in order, for jumping around it: section titles plus any
markdown headings inside them, except a heading that says what its section's
title already says.

    export let readingOutline(page: List<ReadingSection>): List<ReadingOutline> {
      let out = new ListBuilder<ReadingOutline>();
      for (let sec of page) {
        out.add(new ReadingOutline(
          "sec-${sec.section.ordinal.toString()}", 0, sec.section.title, sec.section.wordCount,
        ));
        let title = sysUtf8Downcase(sec.section.title);
        for (let b of sec.blocks) {
          if (readingIsHeading(b.text)) {
            let heading = readingHeadingText(b.text);
            if (sysUtf8Downcase(heading) != title) {
              out.add(new ReadingOutline("block-${b.ref}", readingHeadingLevel(b.text), heading, null));
            }
          }
        }
      }
      out.toList()
    }
