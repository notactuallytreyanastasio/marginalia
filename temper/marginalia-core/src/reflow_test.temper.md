# Tests for PDF page text

Ported from `test/marginalia/reflow_test.exs`. The page is the opening of
the Landor opinion as `pdftotext` handed it over, page furniture and all.

    let landor = [
      "JUSTICE GORSUCH delivered the opinion of the Court.",
      "This case concerns whether the Religious Land Use and",
      "Institutionalized Persons Act of 2000 permits plaintiffs to",
      "sue nonconsenting state employees in their private capaci-",
      "ties for damages.",
      "I",
      "Today, Congress offers financial support to all 50 States",
      "and many other entities. Much of that support comes with",
      "strings attached. So, for example, Congress has conditioned",
      "receipt of federal highway funds on a State's agreement to",
      "maintain laws setting a minimum drinking age of 21. See",
      "South Dakota v. Dole, 483 U. S. 203 (1987). Likewise, Con-",
      "gress has conditioned federal Medicaid funds on a State's",
      "willingness to administer its healthcare programs con-",
      "sistent with various rules.",
      "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND",
      "PUBLIC SAFETY",
      "In each of these contexts and many others, the penalty for",
      "noncompliance is straightforward: Congress may termi-",
      "nate funds if a recipient fails to abide by the conditions",
      "associated with its grants.",
    ].join("\n") { (line): String => line };

    let paragraphsOf(page: String): List<String> {
      reflowPage(page).split("\n\n")
    }

    let wrappedIs(test: Test, text: String, want: Boolean): Void {
      assert(isWrapped(text) == want) { "isWrapped: wanted ${want}" }
    }

    test("hard-wrapped text with no blank lines is page text") { test =>
      wrappedIs(test, landor, true);
    }

    test("text that already has paragraphs is left alone") { test =>
      let para = repeated("word ", 30);
      let prose = "Paragraph 1. ${para}\n\nParagraph 2. ${para}\n\nParagraph 3. ${para}\n\nParagraph 4. ${para}";
      wrappedIs(test, prose, false);
      expectText(test, reflowPage(prose), prose);
    }

    test("the typesetter's hyphens are closed up, and the running head is dropped") { test =>
      let out = reflowPage(landor);
      assert(includes(out, "private capacities for damages")) { out }
      assert(includes(out, "Congress has conditioned federal Medicaid")) { out }
      assert(!includes(out, "LANDOR v. LOUISIANA")) { out }
    }

    test("the division numeral stands alone") { test =>
      let paragraphs = paragraphsOf(landor);
      var found = false;
      for (var i = 0; i < paragraphs.length; i += 1) {
        if (paragraphs[i] == "I") { found = true; }
      }
      assert(found) { paragraphs.join("\n--\n") { (p): String => p } }
    }
