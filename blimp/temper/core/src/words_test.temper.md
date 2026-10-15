# Tests for the word diff

Ported from `test/marginalia/rewrite_test.exs`, "the word diff".

    let render(parts: List<Part>): String {
      parts.join("|") { (part): String => "${part.kind}:${part.text}" }
    }

    let side(parts: List<Part>, skip: String): String {
      parts.filter { (part): Boolean => part.kind != skip }.join("") { (part): String => part.text }
    }

Every word, and the whitespace after it, comes back on its own side.

    let reconstructs(test: Test, a: String, b: String): Void {
      let parts = diff(a, b);
      expectText(test, side(parts, "ins"), a);
      expectText(test, side(parts, "del"), b);
    }

    let diffIs(test: Test, a: String, b: String, want: String): Void {
      expectText(test, render(diff(a, b)), want);
    }

    test("both sides reconstruct exactly") { test =>
      reconstructs(
        test,
        "The kettle went cold on the counter, and nobody moved to fill it again.",
        "The kettle went cold, and nobody moved.",
      );
    }

    test("each side's whitespace, newlines included, comes back with its words") { test =>
      reconstructs(test, "One sentence.\nAnother  sentence.\nA third.", "One sentence.\nA different sentence.\nA third.");
    }

    test("identical spans are all one piece") { test =>
      diffIs(test, "a b c", "a b c", "same:a b c");
    }

    test("an empty original is all insertion") { test =>
      diffIs(test, "", "new text", "ins:new text");
    }

    test("it finds the shared middle rather than replacing everything") { test =>
      diffIs(test, "the cat sat on the mat", "the dog sat on the mat", "same:the |del:cat |ins:dog |same:sat on the mat");
    }

    test("a word is the same word whatever whitespace followed it") { test =>
      diffIs(test, "a b\nc", "a b c", "same:a b c");
    }
