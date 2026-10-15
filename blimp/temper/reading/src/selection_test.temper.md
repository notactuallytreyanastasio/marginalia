# Tests for selection

Ported from `test/marginalia/selection_test.exs`. A selection is made against
rendered text; the draft is markdown. Three earlier attempts encoded the ways
those differ (strip backticks, blank out link targets, blank out list markers)
and each fixed one construct while leaving every other one broken. This aligns
the page back to the source instead, so there is no markdown knowledge to be
incomplete. Every case below is a construct nobody had to write a rule for.

    let { sysJoin } = import("sys/src");
    let { Db, dbOpen } = import("db/src");
    let { Work } = import("works/src");

## Constructs nobody wrote a rule for

Select the middle of a block the way a person drags across it: the rendered
words with the first and the last dropped.

    let selectMiddle(source: String): String {
      let words = selectionSquash(selectionRenderedText(source)).split(" ").filter { (w: String): Boolean => !w.isEmpty };
      let count = if (words.length - 2 > 2) { words.length - 2 } else { 2 };
      let stop = if (1 + count < words.length) { 1 + count } else { words.length };
      sysJoin(words.slice(1, stop), " ")
    }

The span must be a literal substring of the draft and must cover what was
selected: each of the first three selected words is in it.

    let roundtrip(test: Test, source: String): Void {
      let sel = selectMiddle(source);
      let span = selectionInBlock(source, sel);
      rdTrue(test, span != null, "nothing matched for ${sel}");
      if (span != null) {
        rdTrue(test, readingContains(source, span), "the span must be a literal substring of the draft");
        let words = sel.split(" ");
        var i = 0;
        while (i < words.length && i < 3) {
          rdTrue(test, readingContains(span, words[i]), "span ${span} is missing ${words[i]}");
          i += 1;
        }
      }
    }

    test("selection: links") { test =>
      roundtrip(test, "Ten years ago, [I wrote a runner](https://x.test/p) after Jose said so.");
    }

    test("selection: code spans") { test =>
      roundtrip(test, "We will use `gen_stage`, which happens *elsewhere* entirely.");
    }

    test("selection: numbered lists") { test =>
      roundtrip(test, "1. The purpose of society is to make people better off\n2. In general it is hard");
    }

    test("selection: bullets") { test =>
      roundtrip(test, "- a bullet item here\n- another bullet entirely");
    }

    test("selection: blockquotes") { test =>
      roundtrip(test, "> a quoted line here for us to read");
    }

    test("selection: tables") { test =>
      roundtrip(test, "| who | named |\n|---|---|\n| Dario | yes |");
    }

    test("selection: headings") { test =>
      roundtrip(test, "## Step 4: Creating the Producer");
    }

    test("selection: entities") { test =>
      roundtrip(test, "Tom &amp; Jerry went to the shop today");
    }

    test("selection: nested emphasis") { test =>
      roundtrip(test, "This is **bold with _nested_ emphasis** inside it");
    }

    test("selection: images") { test =>
      roundtrip(test, "Look at ![a diagram](/img/x.png) closely now please");
    }

    test("selection: fenced code") { test =>
      roundtrip(test, "```elixir\ndef handle(demand, state) do\n  {:noreply, [], state}\nend\n```");
    }

## locate

    class SelectionFx(public db: Db, public work: Work) {}

    let selectionFixture(): SelectionFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = rdUser(db, "a@example.com");
      let body = "# A draft\n\nShe stood at the [window](https://x.test) for an hour.\n\n1. The purpose of society is to make those living in it better off\n2. In general, it is better to make the less well off better off\n\n${rdRepeat("word ", 300)}";
      new SelectionFx(db, rdWork(db, me, "W", body))
    }

    test("selection: locate finds a selection and returns the source span") { test =>
      let fx = selectionFixture();
      let hit = selectionLocate(fx.db, fx.work, "She stood at the window for an hour");
      rdTrue(test, hit != null, "found");
      if (hit != null) {
        rdTrue(test, readingContains(fx.work.body, hit.span), "a literal substring of the draft");
        rdHas(test, hit.span, "[window](https://x.test)");
        rdInt(test, hit.section.ordinal, 1);
        rdHas(test, hit.block, "She stood at the");
      }
    }

    test("selection: a selection dragged across a paragraph break still lands") { test =>
      let fx = selectionFixture();
      let hit = selectionLocate(
        fx.db, fx.work, "for an hour. The purpose of society is to make those living in it better off",
      );
      rdTrue(test, hit != null, "found");
      if (hit != null) {
        rdTrue(test, readingContains(fx.work.body, hit.span), "a literal substring of the draft");
        // no one block holds it, so the section is the block
        rdText(test, hit.block, hit.section.body);
      }
    }

    test("selection: something not in the draft is refused") { test =>
      let fx = selectionFixture();
      rdTrue(test, selectionLocate(fx.db, fx.work, "a sentence that appears nowhere at all") == null, "refused");
    }

    test("selection: a stray click is refused") { test =>
      let fx = selectionFixture();
      rdTrue(test, selectionLocate(fx.db, fx.work, "the") == null, "refused");
    }

The matcher the beats rely on is the strict one: it matches literally, folding
only whitespace and typography, and it still refuses a reordering, which is the
guarantee the beats rest on.

    test("selection: the strict matcher the beats rely on is untouched") { test =>
      let src = "1. The purpose of society is to make people better off";
      rdText(test, rdOr(readingAnchorVerify("1. The purpose of society", src), "<none>"), "1. The purpose of society");
      rdTrue(test, readingAnchorVerify("The  purpose\nof society", src) != null, "whitespace folds");
      rdTrue(test, readingAnchorVerify("society of purpose the", src) == null, "a reordering is refused");
    }

## The pieces

    test("selection: squash folds every kind of space and trims") { test =>
      rdText(test, selectionSquash("  a \t b\n\nc\u{a0}d  "), "a b c d");
    }

    test("selection: rendered text is the page's text, entities undone") { test =>
      rdText(test, selectionSquash(selectionRenderedText("Tom &amp; **Jerry** <b>x</b>")), "Tom & Jerry x");
    }

    test("selection: dense text drops spaces and remembers where each character was") { test =>
      let d = selectionDense("a b\nc");
      rdText(test, d.text, "abc");
      rdText(test, rdJoin(d.at.map { (n: Int): String => n.toString() }), "0|2|4");
    }

    test("selection: a selection of one character is under the minimum") { test =>
      let fx = selectionFixture();
      rdTrue(test, selectionLocate(fx.db, fx.work, "She stood") == null, "nine characters is a stray click");
    }
