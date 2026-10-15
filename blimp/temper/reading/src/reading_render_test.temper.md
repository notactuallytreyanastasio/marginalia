# Tests for rendering a block

Ported from `test/marginalia/reading_render_test.exs`. A draft is stored one
sentence per line. On the page, a paragraph is a paragraph: its sentences run
on from one another, and only a blank line in the draft makes a break.

The anchor id the Elixir tests passed as an integer (`2`) is the string `"2"`
here; it is only ever printed after `anchor-`.

    test("render: sentences on separate lines render as one paragraph") { test =>
      let html = readingRenderBlock("One sentence.\nAnother sentence.\nA third.", null, "1", null);
      rdLacks(test, html, "<br");
      rdHas(test, html, "<p>One sentence.\nAnother sentence.\nA third.</p>");
    }

    test("render: a blank line in the draft is a paragraph break, and the highlight survives") { test =>
      let blocks = readingSplit("One.\nTwo.\n\nThree.\nFour.");
      rdInt(test, blocks.length, 2);
      rdText(test, blocks[0], "One.\nTwo.");
      rdText(test, blocks[1], "Three.\nFour.");
      let html = readingRenderBlock("Three.\nFour.", "Four.", "2", null);
      rdHas(test, html, "<mark id=\"anchor-2\">Four.</mark>");
      rdLacks(test, html, "<br");
    }

    test("render: emphasis that opens on one sentence line and closes on the next still pairs") { test =>
      let html = readingRenderBlock("This is *very\nimportant* indeed.", null, "3", null);
      rdHas(test, html, "<em>very\nimportant</em>");
    }

    test("render: a fenced block keeps every newline, soft breaks or not") { test =>
      let html = readingRenderBlock("```\na. B.\n\nc. D.\n```", null, "4", null);
      rdHas(test, html, "<code>a. B.\n\nc. D.\n</code>");
    }

    test("render: a rewrite preview whose original spans a sentence break still diffs in place") { test =>
      let text = "One sentence.\nAnother sentence.\nA third.";
      let preview = new ReadingPreview("sentence.\nAnother sentence.", "sentence.\nA second sentence.");
      let html = readingRenderBlock(text, null, "5", preview);
      rdHas(test, html, "<del class=\"mg-cut\">");
      rdHas(test, html, "<ins class=\"mg-swap\">");
      rdLacks(test, html, "<br");
    }

    test("render: a highlight that starts on one line and ends on the next is one mark") { test =>
      let html = readingRenderBlock("One.\nTwo.\nThree.", "Two.\nThree.", "6", null);
      rdHas(test, html, "<mark id=\"anchor-6\">Two.\nThree.</mark>");
    }

The preview sentinels are as private as the mark's.

    test("render: a preview leaves no sentinel behind, and an original that is not there is ignored") { test =>
      let text = "The kettle went cold.";
      let shown = readingRenderBlock(text, null, "7", new ReadingPreview("went cold", "went stone cold"));
      rdLacks(test, shown, "\u{E002}");
      rdLacks(test, shown, "\u{E003}");
      rdLacks(test, shown, "\u{E004}");
      rdLacks(test, shown, "\u{E005}");
      rdHas(test, shown, "<ins class=\"mg-swap\">stone </ins>");
      let ignored = readingRenderBlock(text, null, "7", new ReadingPreview("not in the block", "anything"));
      rdText(test, ignored, readingRenderBlock(text, null, "7", null));
    }
