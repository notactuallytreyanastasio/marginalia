# Tests for the read view

The draft with its notes in the margin: the paragraph and its highlight, the
filters, the piles and decks of notes, the toggle that gives the rail to the
changes, the summaries, the contents rail.

    let { ReadingNote } = import("reading/src");
    let { worksListSections } = import("works/src");
    let { sysSha256 } = import("sys/src");

    let tRoot(w: TWorld, extra: String): String throws Bubble {
      tBodyOf(tGet(w.db, w.owner, "${tPath(w.work, "read")}${extra}", tKeyed()))
    }

## The prose and its notes

    test("read: the draft is shown with the note beside its own paragraph") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "The kettle goes cold");
      let html = tRoot(w, "");
      expectHas(test, html, "The kettle went cold on the counter");
      expectHas(test, html, "The kettle goes cold");
      expectHas(test, html, "id=\"anchor-s1p");
      expectHas(test, html, "The kettle went cold on the counter</mark>");
      expectHas(test, html, "data-anchor=\"s1p");
    }

    test("read: a note's quote is marked in the paragraph it was found in, once") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "First note");
      tBeat(w.db, w.work, "Second note");
      expectInt(test, tCount(tRoot(w, ""), "<mark id=\"anchor-"), 1);
    }

    test("read: every paragraph is a block with a tick, and an id") { test =>
      let w = tWorld();
      let html = tRoot(w, "");
      expectHas(test, html, "id=\"block-s1p0\"");
      expectHas(test, html, "id=\"block-s1p1\"");
      expectHas(test, html, "class=\"mg-tick\" phx-click=\"open_thread\"");
      expectTrue(test, tCount(html, "phx-click=\"open_thread\"") > 3, "one tick per paragraph");
    }

    test("read: the tick says whose section it is by id") { test =>
      let w = tWorld();
      let s = worksListSections(w.db, w.work.id)[0];
      expectHas(test, tRoot(w, ""), "phx-value-section=\"${s.id.toString()}\"");
    }

    test("read: the prose column says whether it can be edited") { test =>
      let w = tWorld();
      expectHas(test, tRoot(w, ""), "data-editable=\"true\"");
      let theirs = tBodyOf(tGet(w.db, w.reader, tPath(w.work, "read"), tKeyed()));
      expectHas(test, theirs, "data-editable=\"false\"");
    }

    test("read: the rail is the hook's, and the prose column carries the vault's") { test =>
      let w = tWorld();
      let html = tRoot(w, "");
      expectHas(test, html, "id=\"read-rail\" phx-hook=\"MarginNotes\"");
      expectHas(test, html, "id=\"read-body\" phx-hook=\"SummaryVault\"");
      expectHas(test, html, "mg-read-rail");
    }

    test("read: the section has a heading with its ordinal and title") { test =>
      let w = tWorld();
      let html = tRoot(w, "");
      expectHas(test, html, "id=\"sec-1\"");
      expectHas(test, html, "Section 1");
      expectHas(test, html, "A draft");
    }

    test("read: a draft with no sections read says so") { test =>
      let w = tWorld();
      w.db.exec("DELETE FROM sections WHERE work_id = $1", [w.work.id.toString()]);
      expectHas(test, tRoot(w, ""), "Nothing read yet.");
    }

## The filters

    test("filters: it opens on everything, with no filter applied") { test =>
      let w = tWorld();
      let html = tRoot(w, "");
      expectHas(test, html, "class=\"mg-tab on\" phx-click=\"set_only\" phx-value-only=\"all\"");
      expectLacks(test, html, "class=\"mg-tab on\" phx-click=\"set_only\" phx-value-only=\"beats\"");
      expectHas(test, html, "Tensions");
      expectHas(test, html, "id=\"read-filters\"");
    }

    test("filters: trimming to tensions hides the beats and keeps the prose") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "The kettle goes cold");
      let r = tEvent(w.db, w.owner, tPath(w.work, "read"), "set_only", "{\"only\":\"tensions\"}", tKeyed());
      expectInt(test, r.resp.status, 200);
      let html = tRoot(w, "");
      expectLacks(test, html, "The kettle goes cold");
      expectHas(test, html, "The kettle went cold on the counter");
      expectHas(test, html, "class=\"mg-tab on\" phx-click=\"set_only\" phx-value-only=\"tensions\"");
    }

    test("filters: all puts everything back") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "The kettle goes cold");
      tEvent(w.db, w.owner, tPath(w.work, "read"), "set_only", "{\"only\":\"connections\"}", tKeyed());
      expectLacks(test, tRoot(w, ""), "The kettle goes cold");
      tEvent(w.db, w.owner, tPath(w.work, "read"), "set_only", "{\"only\":\"all\"}", tKeyed());
      expectHas(test, tRoot(w, ""), "The kettle goes cold");
    }

    test("filters: the filter is the reader's own, not the draft's") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "The kettle goes cold");
      tEvent(w.db, w.owner, tPath(w.work, "read"), "set_only", "{\"only\":\"tensions\"}", tKeyed());
      expectHas(test, tBodyOf(tGet(w.db, w.reader, tPath(w.work, "read"), tKeyed())), "The kettle goes cold");
    }

## The drawer

    test("drawer: the rail is not marked collapsed until the drawer is open") { test =>
      let w = tWorld();
      expectLacks(test, tRoot(w, ""), "mg-read mt-6 collapsed");
      expectHas(test, tRoot(w, "&chat=1"), "mg-read mt-6 collapsed");
    }

## The margin

    test("deck: four notes are four plain cards, with nothing to press") { test =>
      let w = tWorld();
      for (var i = 1; i <= 4; ++i) { tLost(w.db, w.work, "beat", "Beat ${i.toString()}"); }
      let html = tRoot(w, "");
      expectHas(test, html, "Beat 1");
      expectHas(test, html, "Beat 4");
      expectLacks(test, html, "mg-note-slot beat deck");
      expectLacks(test, html, "data-step");
    }

    test("deck: seven notes stack by kind and every one is still on the page") { test =>
      let w = tWorld();
      let a = tLost(w.db, w.work, "beat", "Opens on the broken link");
      let b = tLost(w.db, w.work, "beat", "Locates it in file mode");
      let c = tLost(w.db, w.work, "beat", "Gives a verification procedure");
      let d = tLost(w.db, w.work, "beat", "Prescribes the two-part edit");
      let e = tLost(w.db, w.work, "beat", "Template edits are inert");
      let f = tLost(w.db, w.work, "beat", "Splits seven into four and three");
      tLost(w.db, w.work, "beat", "Lists the deliverables");
      tNode(w.db, w.work, "beat", "Only the start of a connection", "nowhere either");
      tEdge(w.db, w.work, b, a, "pays_off");
      tEdge(w.db, w.work, c, a, "pays_off");
      tEdge(w.db, w.work, d, e, "requires");
      tEdge(w.db, w.work, e, f, "develops");
      let html = tRoot(w, "");
      expectHas(test, html, "Opens on the broken link");
      expectHas(test, html, "Lists the deliverables");
      expectHas(test, html, "Splits seven into four and three");
      expectHas(test, html, "mg-note-slot beat deck");
      expectHas(test, html, "data-step=\"1\"");
      expectHas(test, html, "data-step=\"-1\"");
      expectHas(test, html, "1 / 8");
      expectHas(test, html, "1 / 2");
    }

    test("deck: only the first card of a stack starts visible") { test =>
      let w = tWorld();
      for (var i = 1; i <= 5; ++i) { tLost(w.db, w.work, "beat", "Beat ${i.toString()}"); }
      let html = tRoot(w, "");
      let deck = html.split("<div class=\"cards\">").getOr(1, "").split("<div class=\"nav\">").getOr(0, "");
      expectInt(test, tCount(deck, "mg-note beat on"), 1);
      expectInt(test, tCount(deck, "class=\"mg-note beat\""), 4);
      expectHas(test, html, "1 / 5");
    }

    test("deck: a pile of one is a card, not a deck of one") { test =>
      let w = tWorld();
      tLost(w.db, w.work, "beat", "The only note");
      let html = tRoot(w, "");
      expectHas(test, html, "The only note");
      expectLacks(test, html, "class=\"nav\"");
    }

    test("deck: the pile does not lie about how deep it is") { test =>
      let w = tWorld();
      let a = tLost(w.db, w.work, "beat", "Beat 1");
      let b = tLost(w.db, w.work, "beat", "Beat 2");
      let c = tLost(w.db, w.work, "beat", "Beat 3");
      let d = tLost(w.db, w.work, "beat", "Beat 4");
      let e = tLost(w.db, w.work, "beat", "Beat 5");
      tEdge(w.db, w.work, b, a, "pays_off");
      tEdge(w.db, w.work, c, a, "pays_off");
      tEdge(w.db, w.work, d, e, "requires");
      let html = tRoot(w, "");
      expectHas(test, html, "class=\"mg-note-slot beat deck deep\"");
      expectLacks(test, html, "class=\"mg-note-slot pays_off deck deep\"");
      expectHas(test, html, "class=\"mg-note-slot pays_off deck\"");
    }

    test("deck: a note that locates nowhere is marked as such") { test =>
      let w = tWorld();
      tLost(w.db, w.work, "beat", "Adrift");
      let html = tRoot(w, "");
      expectHas(test, html, "beat · not located");
      expectLacks(test, html, "data-anchor=\"s1p0\"");
    }

    test("deck: a card asks the chat to hold the note") { test =>
      let w = tWorld();
      let n = tBeat(w.db, w.work, "The kettle goes cold");
      let html = tRoot(w, "");
      expectHas(test, html, "phx-click=\"discuss\" phx-value-key=\"beat:${n.id.toString()}\"");
      expectHas(test, html, "id=\"deck-beat:${n.id.toString()}\" phx-hook=\"Deck\"");
    }

    test("deck: a superseded note is still on the page") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "Old note about the kettle");
      tEdit(w.db, w.work, "The kettle went cold on the counter", "The kettle sat on the counter");
      expectHas(test, tRoot(w, ""), "Old note about the kettle");
    }

## The piles, as a function

    let tNote(kind: String, title: String): ReadingNote {
      new ReadingNote("${kind}:${title}", null, kind, null, title, "b", false)
    }

    let tKinds(piles: List<List<ReadingNote>>): String {
      piles.map { (p: List<ReadingNote>): String =>
        p.map { (n: ReadingNote): String => n.kind }.join(",") { (x: String): String => x }
      }.join("|") { (x: String): String => x }
    }

    test("piles: four or fewer get a slot each, with no pager on them") { test =>
      let notes = [tNote("beat", "a"), tNote("beat", "b"), tNote("tension", "c"), tNote("beat", "d")];
      expectText(test, tKinds(showPiles(notes)), "beat|beat|tension|beat");
    }

    test("piles: an empty section has no slots") { test =>
      expectInt(test, showPiles([]).length, 0);
    }

    test("piles: past four, like notes stack together") { test =>
      let notes = [
        tNote("beat", "1"), tNote("pays_off", "2"), tNote("pays_off", "3"), tNote("requires", "4"),
        tNote("develops", "5"), tNote("beat", "6"), tNote("beat", "7"),
      ];
      expectText(test, tKinds(showPiles(notes)), "beat,beat,beat|pays_off,pays_off|requires|develops");
    }

    test("piles: the groups keep the order the notes arrived in") { test =>
      let notes = [
        tNote("develops", "1"), tNote("beat", "2"), tNote("develops", "3"), tNote("beat", "4"), tNote("tension", "5"),
      ];
      expectText(test, tKinds(showPiles(notes)), "develops,develops|beat,beat|tension");
    }

    test("piles: nothing is lost, whichever side of the threshold it falls on") { test =>
      let kinds = ["tension", "pays_off", "beat"];
      for (var n = 1; n <= 12; ++n) {
        let notes = new ListBuilder<ReadingNote>();
        for (var i = 1; i <= n; ++i) { notes.add(tNote(kinds[i % 3], i.toString())); }
        var total = 0;
        for (let pile of showPiles(notes.toList())) { total += pile.length; }
        expectInt(test, total, n);
      }
    }

    test("piles: five notes all of different kinds stay five slots") { test =>
      let notes = ["beat", "tension", "pays_off", "requires", "develops"].map { (k: String): ReadingNote => tNote(k, k) };
      expectInt(test, showPiles(notes).length, 5);
    }

    test("piles: the order within a stack is the order they were written") { test =>
      let notes = [
        tNote("beat", "first"), tNote("tension", "x"), tNote("beat", "second"), tNote("tension", "y"), tNote("beat", "third"),
      ];
      let beats = showPiles(notes)[0];
      expectText(test, beats.map { (n: ReadingNote): String => n.title }.join(",") { (x: String): String => x }, "first,second,third");
    }

## What changed, beside the prose

    test("changes: the toggle is not offered on a draft nobody has changed") { test =>
      let w = tWorld();
      expectLacks(test, tRoot(w, ""), "Show what changed");
    }

    test("changes: it appears once something has changed") { test =>
      let w = tWorld();
      tEdit(w.db, w.work, "kettle", "AMENDED");
      expectHas(test, tRoot(w, ""), "Show what changed");
    }

    test("changes: turning it on puts the before and after in the rail") { test =>
      let w = tWorld();
      tEdit(w.db, w.work, "kettle", "AMENDED");
      tEvent(w.db, w.owner, tPath(w.work, "read"), "toggle_changes", "{}", tKeyed());
      let html = tRoot(w, "");
      expectHas(test, html, "mg-read-rail changes");
      expectHas(test, html, "kettle");
      expectHas(test, html, "AMENDED");
      expectHas(test, html, "cuts the gloss");
      expectHas(test, html, "Back to the notes");
    }

    test("changes: the notes rail is replaced, not shown twice") { test =>
      let w = tWorld();
      tEdit(w.db, w.work, "kettle", "AMENDED");
      tEvent(w.db, w.owner, tPath(w.work, "read"), "toggle_changes", "{}", tKeyed());
      expectInt(test, tCount(tRoot(w, ""), "class=\"mg-read-rail"), 1);
    }

    test("changes: it toggles back") { test =>
      let w = tWorld();
      tEdit(w.db, w.work, "kettle", "AMENDED");
      tEvent(w.db, w.owner, tPath(w.work, "read"), "toggle_changes", "{}", tKeyed());
      tEvent(w.db, w.owner, tPath(w.work, "read"), "toggle_changes", "{}", tKeyed());
      let html = tRoot(w, "");
      expectLacks(test, html, "mg-read-rail changes");
      expectHas(test, html, "Show what changed");
    }

    test("changes: with the rail given over, a note sits under its own paragraph") { test =>
      let w = tWorld();
      tBeat(w.db, w.work, "The kettle goes cold");
      tEdit(w.db, w.work, "nobody moved", "nobody stirred");
      tEvent(w.db, w.owner, tPath(w.work, "read"), "toggle_changes", "{}", tKeyed());
      expectHas(test, tRoot(w, ""), "mg-note-inline");
    }

## Summaries

    let tSummarise(w: TWorld, text: String): Void throws Bubble {
      let s = tSection(w.db, w.work);
      w.db.exec(
        "UPDATE sections SET summary = $1, summary_fingerprint = $2, summary_body = $3, summarised_at = '2020-01-01 00:00:00' WHERE id = $4",
        [text, sysSha256(s.body), s.body, s.id.toString()],
      );
    }

    test("summary: a summary carries a key, its text and its time") { test =>
      let w = tWorld();
      tSummarise(w, "It establishes the doorway.");
      let html = tRoot(w, "");
      expectHas(test, html, "data-sum-key=\"${w.work.slug}:1\"");
      expectHas(test, html, "It establishes the doorway.");
      expectHas(test, html, "data-sum-at=\"2020-01-01T00:00:00Z\"");
    }

    test("summary: the container the hook writes into is left alone by the morph") { test =>
      let w = tWorld();
      tSummarise(w, "A summary.");
      let html = tRoot(w, "");
      expectHas(test, html, "id=\"sumvault-1\" class=\"mg-sum-vault\" phx-update=\"ignore\"");
    }

    test("summary: a section with no summary offers no vault") { test =>
      let w = tWorld();
      let html = tRoot(w, "");
      expectLacks(test, html, "data-sum-key=");
      expectLacks(test, html, "id=\"sumvault-");
      expectHas(test, html, "Summarise this section");
    }

    test("summary: the hook is attached to something") { test =>
      let w = tWorld();
      tSummarise(w, "A summary.");
      expectHas(test, tRoot(w, ""), "phx-hook=\"SummaryVault\"");
    }

    test("summary: the key survives a re-summarise, so both versions land in one vault") { test =>
      let w = tWorld();
      tSummarise(w, "The first summary.");
      let first = tRoot(w, "");
      tSummarise(w, "A completely different second summary.");
      let second = tRoot(w, "");
      let key = "data-sum-key=\"${w.work.slug}:1\"";
      expectTrue(test, hasText(first, key) && hasText(second, key), "one key for both");
      expectHas(test, second, "A completely different second summary.");
      expectLacks(test, second, "The first summary.");
    }

    test("summary: a stale summary shows the split diff under it, red out and green in") { test =>
      let w = tWorld();
      tSummarise(w, "It sets up the kettle.");
      tEdit(w.db, w.work, "kettle", "AMENDED");
      let html = tRoot(w, "");
      expectHas(test, html, "the section has been edited since this was written");
      expectHas(test, html, "When it was summarised");
      expectHas(test, html, "mg-diff-cols compact");
      expectHas(test, html, "class=\"w del\"");
      expectHas(test, html, "class=\"w ins\"");
      expectHas(test, html, "class=\"mg-sum-text stale\"");
    }

    test("summary: a current summary shows no diff at all") { test =>
      let w = tWorld();
      tSummarise(w, "It sets up alpha.");
      let html = tRoot(w, "");
      expectHas(test, html, "It sets up alpha.");
      expectLacks(test, html, "When it was summarised");
      expectLacks(test, html, "class=\"mg-sum-text stale\"");
    }

    test("summary: the summary controls are the owner's") { test =>
      let w = tWorld();
      tSummarise(w, "It sets up alpha.");
      let theirs = tBodyOf(tGet(w.db, w.reader, tPath(w.work, "read"), tKeyed()));
      expectLacks(test, theirs, "It sets up alpha.");
      expectLacks(test, theirs, "Summarise this section");
      expectLacks(test, theirs, "The whole document");
    }

    test("summary: the buttons say what they will do") { test =>
      let w = tWorld();
      let before = tRoot(w, "");
      expectHas(test, before, "Summarise the document");
      expectLacks(test, before, "Open as a draft");
      expectLacks(test, before, "Draft it and compare");
      tSummarise(w, "It sets up alpha.");
      let after = tRoot(w, "");
      expectHas(test, after, "Summarise again");
      expectHas(test, after, "Open as a draft");
      expectHas(test, after, "Draft it and compare");
    }

    test("summary: the whole document, once read, is laid out") { test =>
      let w = tWorld();
      w.db.exec(
        "INSERT INTO document_summaries (work_id, summary, throughline, movements, guidelines, tensions, dropped) VALUES ($1, 'It is about a kettle.', 'The thread is the kettle.', '[{\"heading\":\"The window\",\"sections\":[\"1\"],\"does\":\"Sets the scene.\"}]', '[{\"guideline\":\"Show, do not tell\",\"because\":\"The draft prefers things.\",\"sections\":[\"1\"]}]', '[{\"tension\":\"Stillness against dread.\",\"sections\":[\"1\"]}]', '[]')",
        [w.work.id.toString()],
      );
      let html = tRoot(w, "");
      expectHas(test, html, "It is about a kettle.");
      expectHas(test, html, "The thread is the kettle.");
      expectHas(test, html, "how it moves");
      expectHas(test, html, "§1");
      expectHas(test, html, "what it is working under");
      expectHas(test, html, "Show, do not tell");
      expectHas(test, html, "where those pull against each other");
      expectHas(test, html, "Read it again");
    }

## The contents rail

    test("map: a draft with headings gets a contents rail to scale") { test =>
      let w = tWorld();
      let long = tRead(w.db, w.owner.scope, "Parts", "# One\n\n${tWords(300)}\n\n# Two\n\n${tWords(300)}");
      let html = tBodyOf(tGet(w.db, w.owner, tPath(long, "read"), tKeyed()));
      expectHas(test, html, "id=\"minimap\" phx-hook=\"Minimap\"");
      expectHas(test, html, "data-target=\"sec-1\"");
      expectHas(test, html, "data-target=\"sec-2\"");
      expectHas(test, html, "flex-grow:");
      expectHas(test, html, "contents");
    }

    test("map: one section with no headings has no map") { test =>
      let w = tWorld();
      let plain = tRead(w.db, w.owner.scope, "Plain", "Just a paragraph.\n\nAnd another one.");
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPath(plain, "read"), tKeyed())), "id=\"minimap\"");
    }
