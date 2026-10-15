# Selection

`Marginalia.Selection`: where a passage the reader selected on the page lives
in the draft.

A selection is made against *rendered* text; the draft is markdown. Those two
strings differ, and every rule that encoded one way they differ (strip
backticks, blank out link targets, blank out list markers) fixed one
construct and left the rest broken. The transformation is not guessed at. The
page is rendered here too, so both strings are in hand, and the page's text is
very nearly a subsequence of the source's. Walking the two together gives a
map from every rendered character back to the character in the draft it came
from, with no knowledge of markdown in it anywhere.

What comes back is a literal substring of the draft.

Positions are code points, not graphemes (see `text.temper.md`), and the
search for the selection inside the rendered text is the native `split`, so
the only per-character loops are the dense copy of each side and the alignment
walk, which stops as soon as it has passed the end of the selection.

    let { Db } = import("db/src");
    let { Section, Work, worksListSections } = import("works/src");
    let { markdownToHtml, markdownParagraphs } = import("html/src");
    let { isUnicodeSpace } = import("core/src");
    let { sysStringReplace } = import("sys/src");

`@min_chars`: a selection shorter than this, once its spaces are squashed, is a
stray click.

    let selectionMinChars(): Int { 12 }

The alignment looks ahead at most this far for the next character, so one
character the renderer invented cannot throw it to the end of a long block.

    let selectionLookahead(): Int { 400 }

## The rendered text

The text of one markdown block as the page shows it: rendered with the same
renderer the page uses (hard breaks, as the Elixir's default), every tag
replaced by one space, and the five entities the renderer writes undone, in
the order the Elixir undid them.

The Elixir first deleted `<script>` and `<style>` elements. The sanitiser never
lets one through (a `<script>` in a draft is rendered as its text), so that
step could not fire and is not ported.

    export let selectionRenderedText(source: String): String {
      let html = markdownToHtml(source);
      selectionUnescape(selectionStripTags(html))
    }

`<[^>]+>` becomes a space.

    let selectionStripTags(html: String): String {
      let out = new StringBuilder();
      var runStart = String.begin;
      var i = String.begin;
      while (html.hasIndex(i)) {
        var advanced = false;
        if (html[i] == 60) {
          let afterOpen = html.next(i);
          var j = afterOpen;
          while (html.hasIndex(j) && html[j] != 62) { j = html.next(j); }
          if (html.hasIndex(j) && j != afterOpen) {
            out.appendBetween(html, runStart, i);
            out.append(" ");
            i = html.next(j);
            runStart = i;
            advanced = true;
          }
        }
        if (!advanced) { i = html.next(i); }
      }
      out.appendBetween(html, runStart, html.end);
      out.toString()
    }

    let selectionUnescape(text: String): String {
      let a = sysStringReplace(text, "&lt;", "<");
      let b = sysStringReplace(a, "&gt;", ">");
      let c = sysStringReplace(b, "&quot;", "\"");
      let d = sysStringReplace(c, "&#39;", "'");
      sysStringReplace(d, "&amp;", "&")
    }

`squash/1`: whitespace runs to one space, trimmed.

    export let selectionSquash(text: String): String { readingSquash(text) }

## Dense text

A string with every space removed, and where each remaining character came
from. Whitespace is dropped before anything else is attempted: the renderer
invents it (a `</li>` becomes a line break that is nowhere in the source), so
trying to line it up sends the alignment to the wrong end of the block on the
first character. What the reader selected and what the draft says agree on
the letters; they do not agree on the spaces.

`cps` are the kept characters, `at[k]` the position of `cps[k]` in the
original, `text` the kept characters as a string.

    export class SelectionDense(
      public text: String,
      public cps: List<Int>,
      public at: List<Int>,
    ) {}

    export let selectionDense(text: String): SelectionDense {
      let kept = new ListBuilder<Int>();
      let at = new ListBuilder<Int>();
      var position = 0;
      var i = String.begin;
      while (text.hasIndex(i)) {
        let cp = text[i];
        if (!isUnicodeSpace(cp)) {
          kept.add(cp);
          at.add(position);
        }
        position += 1;
        i = text.next(i);
      }
      let cps = kept.toList();
      new SelectionDense(readingStringOf(cps, 0, cps.length), cps, at.toList())
    }

## Aligning the page back to the draft

The rendered text is a subsequence of the source once the spaces are gone:
the renderer removes syntax, it does not reorder. So walk the two together
and take, for each rendered character, the next source character that
matches. Where none matches within the lookahead the renderer invented a
character: it maps to where the cursor is, and the cursor stays.

`last` is the last rendered position wanted; the walk stops after it. The
answer for position `k` is the same whether or not the walk went on.

    export let selectionAlignment(
      source: List<Int>, plain: List<Int>, last: Int,
    ): List<Int> {
      let n = source.length;
      let map = new ListBuilder<Int>();
      var i = 0;
      var k = 0;
      let stop = if (last < plain.length - 1) { last } else { plain.length - 1 };
      while (k <= stop) {
        let g = plain[k];
        var found = -1;
        if (n > 0) {
          let reach = if (i + selectionLookahead() < n - 1) { i + selectionLookahead() } else { n - 1 };
          var j = i;
          while (found < 0 && j <= reach) {
            if (source[j] == g) { found = j; }
            j += 1;
          }
        }
        if (found >= 0) {
          map.add(found);
          i = found + 1;
        } else {
          let top = if (n - 1 > 0) { n - 1 } else { 0 };
          map.add(if (i < top) { i } else { top });
        }
        k += 1;
      }
      map.toList()
    }

## Finding a selection in one block

The source substring of `block` that the rendered `needle` selects, or null.
The needle is matched case-sensitively against the rendered text with the
spaces taken out of both.

    export let selectionInBlock(block: String, needle: String): String? {
      let needleDense = selectionDense(needle);
      let len = needleDense.cps.length;
      if (len == 0) { return null; }
      let source = selectionDense(block);
      let plain = selectionDense(selectionRenderedText(block));
      let pos = readingIndexOf(plain.text, needleDense.text);
      if (pos < 0) { return null; }
      let map = selectionAlignment(source.cps, plain.cps, pos + len - 1);
      if (pos + len - 1 >= map.length) { return null; }
      let from = map[pos];
      let to = map[pos + len - 1];
      if (from >= source.at.length || to >= source.at.length) { return null; }
      let a = source.at[from];
      let b = source.at[to];
      if (b < a) { return null; }
      readingStringOf(readingCodePoints(block), a, b + 1)
    }

## Locating

`locate/2` over a list of sections, in ordinal order: the first block of the
first section that holds the selection wins; a section is tried whole when no
single block holds it (the reader dragged across a paragraph break, out of a
paragraph and into a list, or over a heading). `null` is `:error`.

    export let selectionLocateIn(sections: List<Section>, text: String): SelectionHit? {
      if (readingGraphemes(selectionSquash(text)) < selectionMinChars()) { return null; }
      var s = 0;
      while (s < sections.length) {
        let section = sections[s];
        let blocks = markdownParagraphs(section.body);
        var b = 0;
        while (b < blocks.length) {
          let span = selectionInBlock(blocks[b], text);
          if (span != null) { return new SelectionHit(section, blocks[b], span); }
          b += 1;
        }
        let whole = selectionInBlock(section.body, text);
        if (whole != null) { return new SelectionHit(section, section.body, whole); }
        s += 1;
      }
      null
    }

    export let selectionLocate(db: Db, work: Work, text: String): SelectionHit? throws Bubble {
      selectionLocateIn(worksListSections(db, work.id), text)
    }
