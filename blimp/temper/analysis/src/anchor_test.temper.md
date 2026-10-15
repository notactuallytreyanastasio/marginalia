# Tests for the anchor

Ported from `anchor_test.exs`, with the spans and the edge cases the notes
state for `Anchor.verify/2` and `filter/2`.

    let { NodeParams } = import("works/src");

    let anchorSource(): String {
      "She had been standing at the window for an hour before anyone noticed, and by then the\nlight had gone completely. \"You can't keep doing this,\" her brother said, from the doorway.\nHe did not come in.\n"
    }

    let anchorPara(): String {
      "She kept them in the freezer, which she never explained to anyone, and by then it hardly mattered."
    }

    let anchorFails(test: Test, quote: String?, source: String?, what: String): Void {
      expectFalse(test, anchorVerify(quote, source).ok, what);
    }

    let curlyQuote(): String {
      "\u{201c}You can\u{2019}t keep doing this,\u{201d} her brother said"
    }

    test("an exact quote verifies, and the span is the quote") { test =>
      let r = anchorVerify("standing at the window for an hour", anchorSource());
      expectTrue(test, r.ok, "verifies");
      expectText(test, r.span, "standing at the window for an hour");
    }

    test("curly quotes and dashes are normalised away") { test =>
      let r = anchorVerify(curlyQuote(), anchorSource());
      expectTrue(test, r.ok, "verifies");
      expectText(test, r.span, "\"You can't keep doing this,\" her brother said");
    }

    test("a fabricated quote is rejected") { test =>
      anchorFails(test, "She turned and left without saying anything at all", anchorSource(), "fabricated");
    }

    test("a too-short quote is rejected rather than trivially matched") { test =>
      anchorFails(test, "the", anchorSource(), "three letters");
      anchorFails(test, "standin", anchorSource(), "seven letters");
      expectTrue(test, anchorVerify("standing", anchorSource()).ok, "eight letters");
    }

    test("the same words in a different order are rejected") { test =>
      anchorFails(test, "the freezer she kept them in which she never explained", anchorPara(), "rearranged");
    }

    test("a deleted negation is rejected") { test =>
      anchorFails(test, "which she explained to anyone, and by then it hardly mattered", anchorPara(), "negation");
    }

    test("a dropped word is rejected") { test =>
      anchorFails(test, "had been standing at window for an hour before anyone noticed", anchorSource(), "dropped");
    }

    test("a substituted word is rejected") { test =>
      anchorFails(test, "standing at the doorway for an hour", anchorSource(), "substituted");
    }

    test("typography and line wrapping are still absorbed, and the span keeps the newlines") { test =>
      let wrapped = "She kept them in the\nfreezer, which she never\nexplained to anyone.";
      let r = anchorVerify("She kept them in the freezer, which she never explained", wrapped);
      expectTrue(test, r.ok, "verifies");
      expectText(test, r.span, "She kept them in the\nfreezer, which she never\nexplained");
      expectTrue(test, anContains(wrapped, r.span), "a substring of the source");
    }

    test("a null quote or source is an error") { test =>
      anchorFails(test, null, anchorSource(), "null quote");
      anchorFails(test, "standing at the window", null, "null source");
      anchorFails(test, null, null, "both null");
    }

    test("matching is case-insensitive and ignores runs of whitespace") { test =>
      let r = anchorVerify("STANDING   AT\nTHE window", anchorSource());
      expectTrue(test, r.ok, "verifies");
      expectText(test, r.span, "standing at the window");
      let s = anchorVerify("The  purpose\nof society", "1. The purpose of society is the thing.");
      expectTrue(test, s.ok, "whitespace runs");
      expectText(test, s.span, "The purpose of society");
    }

    test("a numbered opening and a reordered tail") { test =>
      let body = "1. The purpose of society is the thing.";
      expectTrue(test, anchorVerify("1. The purpose of society", body).ok, "exact");
      anchorFails(test, "society of purpose the", body, "reordered");
    }

    test("the span keeps a line break between sentences") { test =>
      let body = "The tea went cold on the counter.\nNobody moved, and nobody spoke.";
      let r = anchorVerify("went cold on the counter. Nobody moved", body);
      expectTrue(test, r.ok, "verifies");
      expectText(test, r.span, "went cold on the counter.\nNobody moved");
    }

    test("the ellipsis folds to three dots and the em dash to a hyphen") { test =>
      let body = "Wait... then he left - quietly - and did not look back at all.";
      let q = "Wait\u{2026} then he left \u{2014} quietly \u{2014} and did not look back";
      let r = anchorVerify(q, body);
      expectTrue(test, r.ok, "verifies");
      expectText(test, r.span, "Wait... then he left - quietly - and did not look back");
    }

    test("a no-break space and a zero-width space count as whitespace") { test =>
      let body = "the\u{a0}kettle\u{200b}went cold on the counter";
      let r = anchorVerify("the kettle went cold", body);
      expectTrue(test, r.ok, "verifies");
      expectText(test, r.span, "the\u{a0}kettle\u{200b}went cold");
    }

    test("a quote longer than the source cannot match") { test =>
      anchorFails(test, "standing at the window for an hour before anyone noticed, and then some", "standing at the window for an hour", "too long");
    }

    test("a quote that is only whitespace around a short word is rejected") { test =>
      anchorFails(test, "      window      ", anchorSource(), "trimmed to six");
    }

    test("the span of a match at the very end of the source") { test =>
      let r = anchorVerify("He did not come in.", anchorSource());
      expectTrue(test, r.ok, "verifies");
      expectText(test, r.span, "He did not come in.");
    }

    test("combining marks stay with their letter in the span") { test =>
      let body = "Nai\u{308}ve readers, said the clerk, never ask where the ledger went.";
      let r = anchorVerify("readers, said the clerk, never ask", body);
      expectTrue(test, r.ok, "verifies after a combining mark");
      expectText(test, r.span, "readers, said the clerk, never ask");
      let whole = anchorVerify("Nai\u{308}ve readers, said", body);
      expectText(test, whole.span, "Nai\u{308}ve readers, said");
    }

    class AnchorCandidates(public list: List<NodeParams>) {}

    let candidate(title: String, quote: String?): NodeParams {
      let p = new NodeParams(1, "beat", title);
      p.quote = quote;
      p
    }

    test("filter keeps anchored nodes in order and counts the discards") { test =>
      let nodes = [
        candidate("real", "He did not come in."),
        candidate("invented", "She screamed at the top of her lungs and ran."),
        candidate("also real", "by then the light had gone completely"),
      ];
      let r = anchorFilter(nodes, anchorSource());
      expectInt(test, r.dropped, 1);
      expectInt(test, r.kept.length, 2);
      expectText(test, r.kept[0].title, "real");
      expectText(test, r.kept[1].title, "also real");
      expectText(test, orNull(r.kept[1].quote), "by then the\nlight had gone completely");
    }

    test("filter discards a node with no quote at all") { test =>
      let r = anchorFilter([candidate("unsourced", null)], anchorSource());
      expectInt(test, r.dropped, 1);
      expectInt(test, r.kept.length, 0);
    }

    test("filter on a long section is fast enough to use") { test =>
      let body = repeated("word ", 3000);
      let r = anchorFilter([candidate("tail", "word word word word word")], body);
      expectInt(test, r.dropped, 0);
    }
