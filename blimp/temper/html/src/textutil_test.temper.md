# textutil tests

## Helpers

    let runOf(unit: String, n: Int): String {
      let sb = new StringBuilder();
      for (var i = 0; i < n; i += 1) { sb.append(unit); }
      sb.toString()
    }

## slug

`Cases.slug("Trump v. Slaughter")` is `trump-v-slaughter` (the case tests); the
rest follow `mint_slug`.

    let slugIs(test: Test, input: String, want: String): Void {
      expectText(test, slug(input), want);
    }

    let plainIs(test: Test, input: String, want: String): Void {
      expectText(test, slugPlain(input), want);
    }

    test("slug: a case name") { test => slugIs(test, "Trump v. Slaughter", "trump-v-slaughter"); }
    test("slug: another case name") { test => slugIs(test, "Other v. Matter", "other-v-matter"); }
    test("slug: runs of symbols are one dash") { test => slugIs(test, "a  --  b!!c", "a-b-c"); }
    test("slug: leading and trailing symbols go") { test => slugIs(test, "  ...Hello, World!  ", "hello-world"); }
    test("slug: digits stay") { test => slugIs(test, "Chapter 12", "chapter-12"); }
    test("slug: non-ASCII letters are symbols") { test => slugIs(test, "Caf\u{e9} au lait", "caf-au-lait"); }
    test("slug: nothing left is stack") { test => slugIs(test, "!!!", "stack"); }
    test("slug: empty is stack") { test => slugIs(test, "", "stack"); }
    test("slug: capped at 60") { test =>
      slugIs(test, "abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij",
        "abcdefghij-abcdefghij-abcdefghij-abcdefghij-abcdefghij-abcde");
    }
    test("slug: a dash left by the cut is kept") { test =>
      slugIs(test, "${runOf("a", 59)} b", "${runOf("a", 59)}-");
    }
    test("slug: a cut inside a word") { test =>
      slugIs(test, runOf("a", 80), runOf("a", 60));
    }
    test("slugPlain: no cap") { test =>
      plainIs(test, "abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij abcdefghij",
        "abcdefghij-abcdefghij-abcdefghij-abcdefghij-abcdefghij-abcdefghij-abcdefghij");
    }
    test("slugPlain: no fallback") { test => plainIs(test, "!!!", ""); }
    test("slugPlain: same as slug otherwise") { test => plainIs(test, "Trump v. Slaughter", "trump-v-slaughter"); }

## wordCount

`length(String.split(text, ~r/\s+/, trim: true))`: runs of non-ASCII-space.

    let wordsAre(test: Test, input: String, want: Int): Void {
      expectInt(test, wordCount(input), want);
    }

    test("wordCount: empty") { test => wordsAre(test, "", 0); }
    test("wordCount: only whitespace") { test => wordsAre(test, " \n\t \r\n ", 0); }
    test("wordCount: one word") { test => wordsAre(test, "word", 1); }
    test("wordCount: a sentence") { test => wordsAre(test, "The kettle went cold.", 4); }
    test("wordCount: runs of whitespace") { test => wordsAre(test, "  a   b\n\nc\t\td  ", 4); }
    test("wordCount: a bare # counts as a word") { test => wordsAre(test, "# One\n\nword word", 4); }
    test("wordCount: punctuation is part of the word") { test => wordsAre(test, "well - well, then.", 4); }
    test("wordCount: vertical tab and form feed are space") { test => wordsAre(test, "a\u{b}b\u{c}c", 3); }
    test("wordCount: non-breaking space is not space") { test => wordsAre(test, "a\u{a0}b c", 2); }
    test("wordCount: 1301 words, the section in the beat ceiling test") { test =>
      wordsAre(test, "# One\n\n${runOf("word ", 1300)}", 1302);
    }

## truncateWords

No Elixir test pins this; the rule is stated in `textutil.temper.md`.

    let truncIs(test: Test, input: String, n: Int, want: String): Void {
      expectText(test, truncateWords(input, n), want);
    }

    test("truncateWords: shorter than n is unchanged") { test => truncIs(test, "one two", 5, "one two"); }
    test("truncateWords: exactly n is unchanged") { test => truncIs(test, "one two three", 3, "one two three"); }
    test("truncateWords: cut with an ellipsis") { test => truncIs(test, "one two three four", 2, "one two\u{2026}"); }
    test("truncateWords: keeps the spacing it had") { test => truncIs(test, "one  two\nthree four", 3, "one  two\nthree\u{2026}"); }
    test("truncateWords: leading space is kept") { test => truncIs(test, " one two three", 2, " one two\u{2026}"); }
    test("truncateWords: zero words") { test => truncIs(test, "one two", 0, "\u{2026}"); }
    test("truncateWords: empty") { test => truncIs(test, "", 3, ""); }
    test("truncateWords: one word then more") { test => truncIs(test, "a b", 1, "a\u{2026}"); }

## nl2br

    let brIs(test: Test, input: String, want: String): Void {
      expectText(test, nl2br(input), want);
    }

    test("nl2br: none") { test => brIs(test, "one line", "one line"); }
    test("nl2br: one") { test => brIs(test, "a\nb", "a<br>\nb"); }
    test("nl2br: several") { test => brIs(test, "a\n\nb\n", "a<br>\n<br>\nb<br>\n"); }
    test("nl2br: CRLF") { test => brIs(test, "a\r\nb", "a<br>\nb"); }
    test("nl2br: empty") { test => brIs(test, "", ""); }
