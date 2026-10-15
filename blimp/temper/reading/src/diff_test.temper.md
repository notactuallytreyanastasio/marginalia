# Tests for the paragraph diff

Ported from `test/marginalia/diff_test.exs`: aligning two versions of a draft.
The alignment is the whole job. Zipping the two lists and comparing by
position marks everything after an inserted paragraph as changed, which is a
diff nobody can read. The implementation is `core`'s `rows` and `diff`; these
are the assertions the Elixir made of it, here because the reading contexts
are what call it.

`nil` is not a value of `String` here, so the one assertion that passed `nil`
twice (`Diff.rows(nil, nil) == []`) has no counterpart.

    let { rows, diff, Row, Part } = import("core/src");
    let { sysMonoMs, sysJoin } = import("sys/src");

    let dp(items: List<String>): String { sysJoin(items, "\n\n") }

    let kindsOf(rs: List<Row>): String {
      rdJoin(rs.map { (r: Row): String => r.kind })
    }

    let countKind(rs: List<Row>, kind: String): Int {
      var n = 0;
      for (let r of rs) {
        if (r.kind == kind) { n += 1; }
      }
      n
    }

    let partKinds(parts: List<Part>): String {
      rdJoin(parts.map { (p: Part): String => p.kind })
    }

    test("diff: identical prose is all same") { test =>
      let text = dp(["One.", "Two.", "Three."]);
      let rs = rows(text, text);
      rdInt(test, countKind(rs, "same"), 3);
      rdInt(test, rs.length, 3);
    }

    test("diff: an edited paragraph is a change, not a delete and an insert") { test =>
      let rs = rows(dp(["One.", "Two.", "Three."]), dp(["One.", "Two, amended.", "Three."]));
      rdText(test, kindsOf(rs), "same|change|same");
      rdText(test, rdOr(rs[0].left, "?"), "One.");
      rdText(test, rdOr(rs[0].right, "?"), "One.");
      rdText(test, rdOr(rs[1].left, "?"), "Two.");
      rdText(test, rdOr(rs[1].right, "?"), "Two, amended.");
      rdInt(test, countKind(rs, "change"), 1);
    }

    test("diff: a paragraph inserted in the middle shifts nothing after it") { test =>
      let rs = rows(dp(["One.", "Two."]), dp(["One.", "INSERTED.", "Two."]));
      rdText(test, kindsOf(rs), "same|ins|same");
      rdText(test, rdOr(rs[1].right, "?"), "INSERTED.");
      rdInt(test, countKind(rs, "same"), 2);
      rdInt(test, countKind(rs, "change"), 0);
      rdInt(test, countKind(rs, "ins"), 1);
      rdInt(test, countKind(rs, "del"), 0);
    }

    test("diff: a removed paragraph is a delete, and the rest still lines up") { test =>
      let rs = rows(dp(["One.", "GONE.", "Three."]), dp(["One.", "Three."]));
      rdText(test, kindsOf(rs), "same|del|same");
      rdText(test, rdOr(rs[1].left, "?"), "GONE.");
      rdInt(test, countKind(rs, "del"), 1);
    }

    test("diff: rewrapping is not an edit") { test =>
      let rs = rows("A sentence that\nwraps across lines.", "A sentence that wraps   across lines.");
      rdText(test, kindsOf(rs), "same");
    }

    test("diff: a changed pair carries a word-level diff inside it") { test =>
      let rs = rows("The kettle went cold.", "The kettle went stone cold.");
      rdText(test, kindsOf(rs), "change");
      let parts = diff(rdOr(rs[0].left, ""), rdOr(rs[0].right, ""));
      var ins = false;
      var same = false;
      for (let p of parts) {
        if (p.kind == "ins") { ins = true; }
        if (p.kind == "same") { same = true; }
      }
      rdTrue(test, ins, "an insertion");
      rdTrue(test, same, "a shared stretch");
    }

    test("diff: several edits in a row pair up rather than stacking") { test =>
      let rs = rows(dp(["A.", "B.", "C."]), dp(["A1.", "B1.", "C1."]));
      rdInt(test, rs.length, 3);
      rdInt(test, countKind(rs, "change"), 3);
    }

    test("diff: more new paragraphs than old leaves the extra as inserts") { test =>
      let rs = rows(dp(["A."]), dp(["A1.", "B.", "C."]));
      rdInt(test, countKind(rs, "change"), 1);
      rdInt(test, countKind(rs, "ins"), 2);
    }

    test("diff: empty sides do not crash") { test =>
      rdInt(test, rows("", "").length, 0);
      let added = rows("", dp(["A.", "B."]));
      rdInt(test, added.length, 2);
      rdInt(test, countKind(added, "ins"), 2);
      let removed = rows(dp(["A.", "B."]), "");
      rdInt(test, removed.length, 2);
      rdInt(test, countKind(removed, "del"), 2);
    }

A guard against making the alignment accidentally cubic, not a benchmark: the
bound is loose on purpose and the real assertion is the count.

    test("diff: a real-sized draft aligns in reasonable time") { test =>
      let paragraph = rdRepeat("word ", 60);
      let old = new ListBuilder<String>();
      let next = new ListBuilder<String>();
      for (var i = 1; i <= 120; ++i) {
        old.add("Paragraph ${i.toString()}. ${paragraph}");
        next.add(if (i == 75) { "Paragraph 75 REWRITTEN." } else { "Paragraph ${i.toString()}. ${paragraph}" });
      }
      let started = sysMonoMs();
      let rs = rows(dp(old.toList()), dp(next.toList()));
      let took = (sysMonoMs() - started).toInt32() orelse 0;
      rdInt(test, countKind(rs, "change"), 1);
      rdTrue(test, took < 20000, "120 paragraphs took ${took.toString()}ms");
    }
