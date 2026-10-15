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

The cases below are not ASCII. Their expected text was produced by running
the Elixir this library replaced (`Old.Sentences.reflow/1`) on the same input,
so a stub that classes only ASCII fails them.

    test("sentences: accented capitals start sentences") { test =>
      reflowsTo(test, "Élodie came home late. Ça va mal, she said. Ångström laughed. Ünder the stairs it hid. Ōtsu was far.", "Élodie came home late.\nÇa va mal, she said.\nÅngström laughed.\nÜnder the stairs it hid.\nŌtsu was far.");
    }

    test("sentences: Greek sentences split on a Greek capital") { test =>
      reflowsTo(test, "Ο Σωκράτης μίλησε στην αγορά. Ήταν αργά το απόγευμα. Όλοι έφυγαν. Ωστόσο έμεινε. Ο ΟΔΥΣΣΕΑΣ ήρθε.", "Ο Σωκράτης μίλησε στην αγορά.\nΉταν αργά το απόγευμα.\nΌλοι έφυγαν.\nΩστόσο έμεινε.\nΟ ΟΔΥΣΣΕΑΣ ήρθε.");
    }

    test("sentences: Cyrillic sentences split on a Cyrillic capital") { test =>
      reflowsTo(test, "Он пришёл домой. Была ночь. Все спали. Утром пошёл дождь! Это правда? Да.", "Он пришёл домой.\nБыла ночь.\nВсе спали.\nУтром пошёл дождь!\nЭто правда?\nДа.");
    }

    test("sentences: an em dash does not end a sentence, the full stop after it does") { test =>
      reflowsTo(test, "She said — and meant it. Éclat followed — loudly. Done.", "She said — and meant it.\nÉclat followed — loudly.\nDone.");
    }

    test("sentences: a non-breaking space after a full stop is a space") { test =>
      reflowsTo(test, "First one.\u{a0}Élan second. Third\u{a0}one here. Ünder it.\u{2003}Ωmega last.", "First one.\nÉlan second.\nThird\u{a0}one here.\nÜnder it.\nΩmega last.");
    }

    test("sentences: a lower-case accented word after a full stop does not split") { test =>
      reflowsTo(test, "He left. élan stayed behind. ölçü too. Ünder.", "He left. élan stayed behind. ölçü too.\nÜnder.");
    }

    test("sentences: Arabic-Indic digits are digits, as the decimal rule needs") { test =>
      reflowsTo(test, "Chapter ٣.٥ is long. ٣ apples fell. Done.", "Chapter ٣.٥ is long.\n٣ apples fell.\nDone.");
    }
