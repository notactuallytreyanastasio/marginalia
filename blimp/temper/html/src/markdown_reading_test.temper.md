# Markdown: the assertions from the Elixir tests

Ported from `notes/tests.md`: `markdown_test.exs` (2 tests), `reading_render_test.exs`
(6) and the markdown-facing tests of `reading_test.exs`, plus the cases for
`Reading.split/1` (`markdownParagraphs`).

`Reading.render_block` is the app's, not this library's, but what it asks of the
renderer is exactly what these tests pin: private-use sentinels around a mark must
come through the renderer and sit inside the emphasis around them. `renderBlock`
here is that function in miniature: shrink the mark past its edge delimiters, wrap
it in U+E000/U+E001, render with soft breaks, turn the sentinels into `<mark>`.

    let mark0 = cpStr(0xE000);
    let mark1 = cpStr(0xE001);

    let isDelimCp(c: Int): Boolean { c == 42 || c == 95 || c == 96 || c == 126 }

    let leftEdge(mark: String): StringIndex {
      var b = String.begin;
      while (mark.hasIndex(b) && isDelimCp(mark[b])) { b = mark.next(b); }
      b
    }

    let rightEdge(mark: String, left: StringIndex): StringIndex {
      var e = mark.end;
      while (e > left && isDelimCp(mark[mark.prev(e)])) { e = mark.prev(e); }
      e
    }

    let advanceBy(s: String, from: StringIndex, n: Int): StringIndex {
      var i = from;
      var k = 0;
      while (k < n && s.hasIndex(i)) { i = s.next(i); k += 1; }
      i
    }

    let renderBlock(text: String, mark: String?, ref: String): String {
      if (mark != null) { renderMarked(text, mark, ref) } else { markdownToHtmlSoft(text) }
    }

    let renderMarked(text: String, mark: String, ref: String): String {
      let at = findFrom(text, mark, String.begin);
      if (at != null) { renderAt(text, mark, ref, at) } else { markdownToHtmlSoft(text) }
    }

    let renderAt(text: String, mark: String, ref: String, at: StringIndex): String {
      let a = leftEdge(mark);
      let z = rightEdge(mark, a);
      let stop = advanceBy(text, at, mark.countBetween(String.begin, mark.end));
      let wrapped = [text.slice(String.begin, at), mark.slice(String.begin, a), mark0, mark.slice(a, z), mark1,
        mark.slice(z, mark.end), text.slice(stop, text.end)];
      let html = markdownToHtmlSoft(joinStr(wrapped, ""));
      replaceAll(replaceAll(html, mark0, "<mark id=\"anchor-${ref}\">"), mark1, "</mark>")
    }

    let hasPart(test: Test, html: String, part: String): Void {
      expectTrue(test, contains(html, part), "missing ${part} in ${html}");
    }

    let lacksPart(test: Test, html: String, part: String): Void {
      expectTrue(test, !contains(html, part), "unexpected ${part} in ${html}");
    }

## markdown_test.exs

    test("markdown: a reply keeps its line breaks") { test => hasPart(test, markdownToHtml("one\ntwo"), "<br"); }

    test("markdown: a draft joins the sentences of a paragraph and keeps its paragraphs") { test =>
      let html = markdownToHtmlSoft("One.\nTwo.\n\nThree.");
      lacksPart(test, html, "<br");
      hasPart(test, html, "<p>One.\nTwo.</p>");
      hasPart(test, html, "<p>Three.</p>");
    }

## reading_render_test.exs

    test("render: sentences on separate lines render as one paragraph") { test =>
      let html = renderBlock("One sentence.\nAnother sentence.\nA third.", null, "1");
      lacksPart(test, html, "<br");
      hasPart(test, html, "<p>One sentence.\nAnother sentence.\nA third.</p>");
    }

    test("render: a blank line is a paragraph break, and the highlight survives") { test =>
      expectText(test, joinStr(markdownParagraphs("One.\nTwo.\n\nThree.\nFour."), "|"), "One.\nTwo.|Three.\nFour.");
      let html = renderBlock("Three.\nFour.", "Four.", "2");
      hasPart(test, html, "<mark id=\"anchor-2\">Four.</mark>");
      lacksPart(test, html, "<br");
    }

    test("render: emphasis that opens on one sentence line and closes on the next still pairs") { test =>
      hasPart(test, renderBlock("This is *very\nimportant* indeed.", null, "3"), "<em>very\nimportant</em>");
    }

    test("render: a fenced block keeps every newline, soft breaks or not") { test =>
      hasPart(test, renderBlock("```\na. B.\n\nc. D.\n```", null, "4"), "<code>a. B.\n\nc. D.\n</code>");
    }

    test("render: a highlight that starts on one line and ends on the next is one mark") { test =>
      hasPart(test, renderBlock("One.\nTwo.\nThree.", "Two.\nThree.", "6"), "<mark id=\"anchor-6\">Two.\nThree.</mark>");
    }

    test("render: a rewrite preview whose original spans a sentence break still diffs in place") { test =>
      let html = markdownToHtmlSoft("One sentence.\n\u{e004}Another sentence.\u{e005}\u{e002}A second sentence.\u{e003}\nA third.");
      lacksPart(test, html, "<br");
      hasPart(test, html, "\u{e004}Another sentence.\u{e005}\u{e002}A second sentence.\u{e003}");
      let shown = replaceAll(replaceAll(html, cpStr(0xE004), "<del class=\"mg-cut\">"), cpStr(0xE002), "<ins class=\"mg-swap\">");
      hasPart(test, shown, "<del class=\"mg-cut\">Another sentence.");
      hasPart(test, shown, "<ins class=\"mg-swap\">A second sentence.");
    }

## reading_test.exs: the draft's own markdown

    let code = "Create a new file:\n\n```elixir\ndefmodule Producer do\n  use GenStage\n\n  def handle_demand(demand, state) do\n    {:noreply, [], state}\n  end\nend\n```\n\nThe consumer is in control. It's **impossible** to overwhelm it.\n\n1. First principle\n2. Second principle";

    let blockWith(test: Test, start: String): String {
      let blocks = markdownParagraphs(code);
      for (var k = 0; k < blocks.length; ++k) {
        if (startsAt(blocks[k], String.begin, start) != null) { return blocks[k]; }
      }
      expectTrue(test, false, "no block starts with ${start}");
      ""
    }

    test("reading: a fenced code block survives the blank lines inside it") { test =>
      let fence = blockWith(test, "```");
      hasPart(test, fence, "handle_demand");
      hasPart(test, fence, "end\n```");
    }

    test("reading: a fence renders as code, not as prose") { test =>
      let html = renderBlock(blockWith(test, "```"), null, "x");
      hasPart(test, html, "<pre><code");
      lacksPart(test, html, "`");
    }

    test("reading: a list renders as a list") { test =>
      expectText(test, blockWith(test, "1."), "1. First principle\n2. Second principle");
      hasPart(test, renderBlock(blockWith(test, "1."), null, "y"), "<ol>");
    }

    test("reading: a highlight survives rendering, even across inline markup") { test =>
      let html = renderBlock(blockWith(test, "The consumer"), "It's **impossible** to overwhelm it", "z");
      hasPart(test, html, "<mark id=\"anchor-z\">");
      hasPart(test, html, "<strong>impossible</strong>");
      hasPart(test, html, "</mark>");
    }

    test("reading: a block with no highlight gets no mark") { test =>
      lacksPart(test, renderBlock(blockWith(test, "The consumer"), null, "z"), "<mark");
    }

    test("reading: the sentinels never reach the page") { test =>
      let html = renderBlock(blockWith(test, "The consumer"), "The consumer is in control", "z");
      lacksPart(test, html, mark0);
      lacksPart(test, html, mark1);
    }

## reading_test.exs: a highlight that lands on markdown syntax

    test("reading: emphasis around the quote still renders, and the mark sits inside it") { test =>
      let text = "Prudence. **We must slow the pace. Progress will still seem fast.** Two things.";
      let quote = "**We must slow the pace. Progress will still seem fast.**";
      let html = renderBlock(text, quote, "r1");
      lacksPart(test, html, "**");
      hasPart(test, html, "<strong>");
      hasPart(test, html, "<mark id=\"anchor-r1\">We must slow the pace.");
    }

    let edgeCase(test: Test, open: String, close: String, tag: String): Void {
      let html = renderBlock("Before ${open}the marked words${close} after.", "${open}the marked words${close}", "r2");
      hasPart(test, html, "<${tag}>");
      hasPart(test, html, "<mark");
      lacksPart(test, html, "${open}the marked");
    }

    test("reading: italics at the edges are trimmed out of the mark") { test => edgeCase(test, "*", "*", "em"); }
    test("reading: code fences at the edges are trimmed out of the mark") { test => edgeCase(test, "`", "`", "code"); }

    test("reading: a quote that is only delimiters marks nothing rather than crashing") { test =>
      let html = renderBlock("Some prose with ** in it somewhere.", "**", "r3");
      expectTrue(test, !html.isEmpty, "a binary comes back");
      lacksPart(test, html, mark0);
    }

    test("reading: an ordinary quote is untouched") { test =>
      hasPart(test, renderBlock("She had been standing at the window for an hour.", "standing at the window", "r4"),
        "<mark id=\"anchor-r4\">standing at the window</mark>");
    }

## Reading.split (markdownParagraphs)

    let splitIs(test: Test, input: String, want: String): Void {
      expectText(test, joinStr(markdownParagraphs(input), "|"), want);
    }

    test("split: blank lines separate blocks") { test => splitIs(test, "One.\nTwo.\n\nThree.\nFour.", "One.\nTwo.|Three.\nFour."); }
    test("split: empty") { test => expectInt(test, markdownParagraphs("").length, 0); }
    test("split: only blank lines") { test => expectInt(test, markdownParagraphs("\n\n  \n").length, 0); }
    test("split: several blank lines are one break") { test => splitIs(test, "a\n\n\n\nb", "a|b"); }
    test("split: a fence with blank lines is one block") { test =>
      splitIs(test, "intro\n\n```\na\n\nb\n```\n\noutro", "intro|```\na\n\nb\n```|outro");
    }
    test("split: a fence interrupts a block") { test => splitIs(test, "text\n```\ncode\n```\nmore", "text|```\ncode\n```|more"); }
    test("split: an unclosed fence swallows the rest") { test => splitIs(test, "a\n\n```\nb\n\nc", "a|```\nb\n\nc"); }
    test("split: a closer may be longer than the opener") { test => splitIs(test, "```\nx\n\n`````\n\ny", "```\nx\n\n`````|y"); }
    test("split: tilde fences") { test => splitIs(test, "~~~\nx\n\ny\n~~~\n\nz", "~~~\nx\n\ny\n~~~|z"); }
    test("split: trailing whitespace is trimmed, leading indentation kept") { test =>
      splitIs(test, "  indented  \n\nplain   ", "  indented|plain");
    }
    test("split: a whitespace-only line separates") { test => splitIs(test, "a\n   \nb", "a|b"); }

## Rendering in the other direction

    test("render: soft and hard differ only in the break") { test =>
      expectText(test, markdownToHtml("a\nb"), "<p>a<br>\nb</p>");
      expectText(test, markdownToHtmlSoft("a\nb"), "<p>a\nb</p>");
    }

    test("render: empty input is empty output") { test =>
      expectText(test, markdownToHtml(""), "");
      expectText(test, markdownToHtmlSoft(""), "");
    }

    test("render: only blank lines is empty output") { test => expectText(test, markdownToHtml("\n\n \n"), ""); }

    test("render: raw HTML is never emitted") { test =>
      let html = markdownToHtml("<script>alert(1)</script> <img src=x onerror=y> <div>d</div>\n\n<div>\nblock\n</div>\n\ntext");
      lacksPart(test, html, "<script");
      lacksPart(test, html, "<img");
      lacksPart(test, html, "<div");
      lacksPart(test, html, "onerror");
      hasPart(test, html, "text");
    }

    test("render: javascript: and data: links lose their target") { test =>
      let html = markdownToHtml("[a](javascript:alert(1)) [b](data:text/html;base64,AA) [c](http://ok.example)");
      lacksPart(test, html, "javascript");
      lacksPart(test, html, "data:");
      hasPart(test, html, "href=\"http://ok.example\"");
    }

    test("render: every link carries rel") { test =>
      let html = markdownToHtml("[a](/x) http://y.example <z@example.com>");
      expectInt(test, html.split("rel=\"noopener noreferrer\"").length, 4);
    }

    test("render: text is escaped") { test =>
      expectText(test, markdownToHtml("1 < 2 & 3 > 2 \"q\" 'a'"), "<p>1 &lt; 2 &amp; 3 &gt; 2 \"q\" 'a'</p>");
    }

    test("render: the private-use sentinels pass through") { test =>
      expectText(test, markdownToHtmlSoft("a \u{e000}b\u{e001} c"), "<p>a \u{e000}b\u{e001} c</p>");
    }

    test("render: windows line endings") { test => expectText(test, markdownToHtmlSoft("a\r\nb\r\n\r\nc"), "<p>a\nb</p>\n<p>c</p>"); }

## Speed

A 60 KB document, rendered once; the time is printed. The renderer is quadratic
only in the number of top-level blocks and of tokens in one paragraph.

    let bigDoc(test: Test): String {
      let sb = new StringBuilder();
      for (var i = 0; i < 40; i += 1) {
        sb.append("## Section\n\nA paragraph with *emphasis*, **strong**, `code`, a [link](http://x.example/a_b), and some more words to fill it out a little.\nA second line of the same paragraph, with a quote \"here\" and an ampersand & a bracket [x].\n\n- item one\n- item two with **bold**\n  - nested\n\n> quoted text\n> more\n\n```\ncode block\n```\n\n");
      }
      sb.toString()
    }

    test("speed: a large document") { test =>
      let doc = bigDoc(test);
      let t0 = htmlNowMs();
      let html = markdownToHtmlSoft(doc);
      let t1 = htmlNowMs();
      console.log("markdown of ${doc.countBetween(String.begin, doc.end)} chars: ${t1 - t0} ms");
      expectInt(test, html.split("<h2>Section</h2>").length, 41);
    }
