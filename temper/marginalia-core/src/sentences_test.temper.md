# Tests for one sentence per line

Ported from `test/marginalia/sentences_test.exs`.

    let reflowsTo(test: Test, text: String, want: String): Void {
      expectText(test, reflow(text), want);
    }

    test("a hard-wrapped paragraph comes back one sentence per line") { test =>
      reflowsTo(
        test,
        "At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step\nreset for lock delay. The idea came from agent-8, which had not committed the\ncode. Agent-8 had logged a decision.",
        "At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step reset for lock delay.\nThe idea came from agent-8, which had not committed the code.\nAgent-8 had logged a decision.",
      );
    }

    test("paragraphs stay separated by a blank line") { test =>
      reflowsTo(test, "One. Two.\n\nThree. Four.", "One.\nTwo.\n\nThree.\nFour.");
    }

    test("reflowing twice changes nothing") { test =>
      let once = reflow("She stood at the window\nfor an hour. The kettle went cold. It was late.");
      reflowsTo(test, once, once);
    }

    test("abbreviations and initials do not end a sentence") { test =>
      reflowsTo(
        test,
        "Ask Dr. Jones, e.g. tomorrow. J. K. Rowling agreed. It cost No. 4 dearly. Done.",
        "Ask Dr. Jones, e.g. tomorrow.\nJ. K. Rowling agreed.\nIt cost No. 4 dearly.\nDone.",
      );
    }

    test("decimals, question marks, exclamations and closing quotes") { test =>
      reflowsTo(
        test,
        "It scored 3.16 on the board! Was that enough? \"No,\" she said. \"Not nearly.\" Fine.",
        "It scored 3.16 on the board!\nWas that enough?\n\"No,\" she said.\n\"Not nearly.\"\nFine.",
      );
    }

    test("fenced code is untouched, blank lines and all") { test =>
      let code = "```\nfoo. Bar baz.\n\nqux. Quux.\n```";
      reflowsTo(test, "Intro one. Intro two.\n\n${code}", "Intro one.\nIntro two.\n\n${code}");
    }
