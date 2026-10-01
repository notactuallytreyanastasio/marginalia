# Tests for the paragraph diff

Ported from `test/marginalia/diff_test.exs`.

    let kinds(before: String, after: String): String {
      rows(before, after).join(" ") { (r): String => r.kind }
    }

    let rowsAre(test: Test, before: String, after: String, want: String): Void {
      expectText(test, kinds(before, after), want);
    }

    test("identical prose is all same") { test =>
      rowsAre(test, "One.\n\nTwo.\n\nThree.", "One.\n\nTwo.\n\nThree.", "same same same");
    }

    test("an edited paragraph is a change, not a delete and an insert") { test =>
      rowsAre(test, "One.\n\nTwo.\n\nThree.", "One.\n\nTwo, amended.\n\nThree.", "same change same");
    }

    test("a paragraph inserted in the middle shifts nothing after it") { test =>
      rowsAre(test, "One.\n\nTwo.", "One.\n\nINSERTED.\n\nTwo.", "same ins same");
    }

    test("a removed paragraph is a delete, and the rest still lines up") { test =>
      rowsAre(test, "One.\n\nGONE.\n\nThree.", "One.\n\nThree.", "same del same");
    }

    test("rewrapping is not an edit") { test =>
      rowsAre(test, "A sentence that\nwraps across lines.", "A sentence that wraps   across lines.", "same");
    }
