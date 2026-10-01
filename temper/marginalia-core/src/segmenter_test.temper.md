# Tests for the segmenter

Ported from `test/marginalia/segmenter_test.exs`.

    let titles(sections: List<Section>): String {
      sections.join(" / ") { (s): String => s.title }
    }

    let titlesAre(test: Test, text: String, want: String): Void {
      expectText(test, titles(segment(text)), want);
    }

    test("a blog post with no structure is one section") { test =>
      let para = repeated("word ", 40);
      let sections = segment("Paragraph 1. ${para}\n\nParagraph 2. ${para}\n\nParagraph 4. ${para}");
      assert(sections.length == 1) { "${sections.length} sections" }
      assert(includes(sections[0].body, "Paragraph 4")) { sections[0].body }
    }

    test("markdown headings win when the writer supplied them") { test =>
      titlesAre(
        test,
        "# The Opening\n${repeated("alpha ", 300)}\n\n# The Middle\n${repeated("beta ", 300)}\n\n# The End\n${repeated("gamma ", 300)}\n",
        "The Opening / The Middle / The End",
      );
    }

    test("chapter markers are found when there is no markdown") { test =>
      let sections = segment("Chapter 1\n${repeated("one ", 300)}\n\nChapter 2\n${repeated("two ", 300)}\n");
      assert(sections.length == 2) { titles(sections) }
      assert(includes(sections[0].title, "Chapter 1")) { titles(sections) }
    }

The bug the port found: `—{3,}` without the `u` flag never matched, so a
scene break drawn with em dashes was not a break.

    test("a run of em dashes is a section marker, as hyphens are") { test =>
      let sections = segment("——— One\n${repeated("one ", 300)}\n\n———\n${repeated("two ", 300)}\n");
      assert(sections.length == 2) { titles(sections) }
      expectText(test, sections[0].title, "——— One");
    }

    test("empty input yields nothing") { test =>
      titlesAre(test, "", "");
    }
