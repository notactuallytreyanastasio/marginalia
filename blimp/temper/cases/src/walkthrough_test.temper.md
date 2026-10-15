# Tests for the walkthroughs and the tour

`test/marginalia/walkthrough_test.exs` (13 tests), the pure half of
`cases_tour_test.exs` (the steps themselves) and of `tour_test.exs` (a card
for every tab), plus the data they stand for, checked against the Elixir.

The walkthrough drives the real controls, so its fixtures have to be the real
shapes. The bug the Elixir file exists for: the canned rewrite was written with
string keys, `rewrite_panel` reads `c.text`, and the render raised, which in a
LiveView does not show an error, it drops the socket. The tour got to step
eight and the page quietly stopped responding.

    let { JsonSyntaxTree, JsonArray, JsonObject, parseJson } = import("std/json");

    let places(): List<String> { ["left", "right", "bottom", "top", "centre"] }

    let inList(xs: List<String>, x: String): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i] == x) { return true; }
        i += 1;
      }
      false
    }

    let idsOf(steps: List<WalkStep>): List<String> {
      steps.map { (s: WalkStep): String => s.id }
    }

    let distinct(xs: List<String>): Boolean {
      var i = 0;
      while (i < xs.length) {
        var j = i + 1;
        while (j < xs.length) {
          if (xs[i] == xs[j]) { return false; }
          j += 1;
        }
        i += 1;
      }
      true
    }

    let lastOf(steps: List<WalkStep>): WalkStep {
      steps[steps.length - 1]
    }

    let longEnough(s: String): Boolean { s.countBetween(String.begin, s.end) > 40 }

## steps

    let wellFormed(test: Test): Void {
      let steps = walkthroughSteps("read", true);
      expectTrue(test, steps.length >= 8, "the read view has at least eight steps");
      for (let s of steps) {
        expectTrue(test, s.id != "", "an id");
        expectTrue(test, s.title != "", "a title for ${s.id}");
        expectTrue(test, s.body != "", "a body for ${s.id}");
        let target = s.target;
        expectTrue(test, target == null || target != "", "a target is a selector or nothing for ${s.id}");
        expectTrue(test, inList(places(), s.place), "place ${s.place} for ${s.id}");
      }
    }

    test("the read view has one and every step is well formed") { test => wellFormed(test); }

    let distinctIds(test: Test): Void {
      expectTrue(test, distinct(idsOf(walkthroughSteps("read", true))), "the hook indexes by position and reports by id");
    }

    test("every id is distinct, the hook indexes by position and reports by id") { test => distinctIds(test); }

    let knownActs(test: Test): Void {
      let known = ["open_map", "open_thread", "ask_thread", "select", "rewrite", "edit", "reset"];
      for (let s of walkthroughSteps("read", true)) {
        let act = s.act;
        if (act != null) {
          if (act.kind == "push") {
            let ev = act.event;
            expectTrue(test, ev != null && ev != "", "a push has an event for ${s.id}");
          } else if (act.kind == "client") {
            let n = act.clientName;
            expectTrue(test, n != null && inList(known, orNone(n)), "unknown client action ${orNone(n)}");
          } else {
            expectTrue(test, false, "the read view only pushes and runs client actions, got ${act.kind}");
          }
        }
      }
    }

    test("every action is one the client knows how to perform") { test => knownActs(test); }

    let endsByReset(test: Test): Void {
      let last = lastOf(walkthroughSteps("read", true));
      let act = last.act;
      expectTrue(test, act != null, "the last step has an action");
      if (act != null) {
        expectText(test, act.kind, "client");
        expectText(test, orNone(act.clientName), "reset");
        expectTrue(test, act.event == null && act.to == null && act.target == null, "and nothing else");
        expectInt(test, act.params.length, 0);
      }
    }

    test("it ends by putting the page back") { test => endsByReset(test); }

    let jsonTrip(test: Test): Void throws Bubble {
      let steps = walkthroughSteps("read", true);
      let parsed = parseJson(walkthroughStepsJson(steps));
      expectTrue(test, parsed is JsonArray, "an array");
      if (parsed is JsonArray) {
        expectInt(test, parsed.elements.length, steps.length);
        var allObjects = true;
        for (let e of parsed.elements) {
          if (!(e is JsonObject)) { allObjects = false; }
        }
        expectTrue(test, allObjects, "every step is an object");
      }
    }

    test("the steps survive the trip to the browser as JSON") { test =>
      do { jsonTrip(test); } orelse expectTrue(test, false, "bubbled");
    }

    let jsonShape(test: Test): Void {
      let json = walkthroughStepsJson(walkthroughSteps("read", true));
      expectHas(test, json, "\"id\":\"margin\"");
      expectHas(test, json, "\"target\":\".mg-read-rail .mg-note-slot\"");
      expectHas(test, json, "\"act\":{\"kind\":\"push\",\"event\":\"set_only\",\"params\":{\"only\":\"tensions\"}}");
      expectHas(test, json, "\"owner\":true");
      expectHas(test, json, "\"target\":null,\"place\":\"centre\"");
      expectHas(test, json, "\"act\":{\"kind\":\"client\",\"name\":\"reset\"}");
    }

    test("the JSON carries owner only where it is true, and a null target as null") { test => jsonShape(test); }

    let notMine(test: Test): Void {
      let theirs = idsOf(walkthroughSteps("read", false));
      expectFalse(test, inList(theirs, "ask"), "no ask for a reader");
      expectFalse(test, inList(theirs, "edit"), "no edit for a reader");
      expectFalse(test, inList(theirs, "rewrite"), "no rewrite for a reader");
      expectTrue(test, inList(theirs, "thread"), "the thread is still there");
      expectTrue(test, inList(theirs, "filters"), "the filters are still there");
      expectText(test, theirs[theirs.length - 1], "done");
    }

    test("a reader who does not own the draft is not shown controls they lack") { test => notMine(test); }

    let mineAll(test: Test): Void {
      let mine = idsOf(walkthroughSteps("read", true));
      expectTrue(test, inList(mine, "ask") && inList(mine, "edit") && inList(mine, "rewrite"), "the owner has all three");
      expectTrue(test, mine.length > walkthroughSteps("read", false).length, "and more of them");
      expectText(test, joined(mine), "margin,filters,filters_back,map,thread,ask,select,rewrite,edit,done");
      expectInt(test, walkthroughSteps("read", false).length, 7);
    }

    test("the owner gets all of them") { test => mineAll(test); }

    let noOther(test: Test): Void {
      expectInt(test, walkthroughSteps("graph", true).length, 0);
      expectInt(test, walkthroughSteps("spine", true).length, 0);
      expectFalse(test, walkthroughForView("graph"), "graph has none");
      expectTrue(test, walkthroughForView("read"), "read has one");
      expectText(test, joined(walkthroughViews()), "read");
    }

    test("views without one get an empty list rather than an error") { test => noOther(test); }

    let verbatim(test: Test): Void {
      let steps = walkthroughSteps("read", true);
      let margin = steps[0];
      expectText(test, margin.title, "The notes sit beside the line");
      expectText(test, orNone(margin.target), ".mg-read-rail .mg-note-slot");
      expectText(test, margin.place, "left");
      expectFalse(test, margin.owner, "margin is for everyone");
      let ask = steps[5];
      expectTrue(test, ask.owner, "ask is the owner's");
      let done = steps[9];
      expectTrue(test, done.target == null, "done spotlights nothing");
      expectText(test, done.place, "centre");
      expectHas(test, done.body, "The ? in the header runs this again.");
      let filters = steps[1];
      let act = filters.act;
      if (act != null) {
        expectText(test, act.params.getOr("only", ""), "tensions");
      } else {
        expectTrue(test, false, "filters pushes");
      }
    }

    test("the copy is the Elixir's") { test => verbatim(test); }

## fixtures

    let cannedRewrite(test: Test): Void {
      let r = walkthroughRewrite();
      expectTrue(test, r.original != "", "an original");
      expectTrue(test, r.reading != "", "a reading");
      expectTrue(test, r.section == null, "no section, as the key is there and nil");
      expectInt(test, r.candidates.length, 3);
    }

    test("the canned rewrite has the shape Rewrite.propose returns") { test => cannedRewrite(test); }

    let rewriteFlags(test: Test): Void {
      let r = walkthroughRewrite();
      expectTrue(test, r.sample, "it says it is a sample");
      expectFalse(test, r.spansBlocks, "spans_blocks is false: the panel reads it");
      expectInt(test, r.covers.length, 0);
    }

    test("the rewrite carries spans_blocks and covers, which the panel reads") { test => rewriteFlags(test); }

    let candidateFields(test: Test): Void {
      for (let c of walkthroughRewrite().candidates) {
        expectTrue(test, c.text != "", "text");
        expectTrue(test, c.move != "", "move");
        expectTrue(test, c.cost != "", "cost");
      }
    }

    test("candidates carry the fields the panel reads") { test => candidateFields(test); }

    let noOriginal(test: Test): Void {
      let r = walkthroughRewrite();
      for (let c of r.candidates) {
        expectFalse(test, c.text == r.original, "no candidate is the original, which the real cleaner also rejects");
      }
      expectText(test, r.candidates[0].move, "Cuts the gloss");
      expectText(test, r.candidates[2].cost, "Only works if the car is already in the scene");
    }

    test("no candidate is the original") { test => noOriginal(test); }

    let canned(test: Test): Void {
      let x = walkthroughExchange();
      expectTrue(test, x.question != "", "a question");
      expectText(test, x.question, "What is this paragraph actually doing?");
      expectHas(test, x.answer, "never calls the model");
      expectHas(test, x.answer, "Two things, and the second one is quieter.\n\nIt is placing the scene");
      expectTrue(test, x.answer.split("\n").length == 12, "eleven lines and the heredoc's final newline");
      let both = walkthroughFixtures();
      expectText(test, both.exchange.question, x.question);
      expectInt(test, both.rewrite.candidates.length, 3);
    }

    test("the canned answer says it is canned") { test => canned(test); }

## the term's three legs

    let legsHaveSteps(test: Test): Void {
      for (let leg of ["cases", "follow", "case_read"]) {
        let steps = casesWalkSteps(leg);
        expectTrue(test, steps.length >= 5, "${leg} is too short to be a tour");
        for (let s of steps) {
          expectTrue(test, s.title != "", "a title");
          expectTrue(test, longEnough(s.body), "${leg}/${s.id} says nothing");
          expectTrue(test, inList(places(), s.place), "place for ${leg}/${s.id}");
        }
        expectTrue(test, distinct(idsOf(steps)), "ids of ${leg} are distinct");
      }
      expectInt(test, casesWalkSteps("cases").length, 6);
      expectInt(test, casesWalkSteps("follow").length, 8);
      expectInt(test, casesWalkSteps("case_read").length, 5);
    }

    test("every leg has steps, and every step says something") { test => legsHaveSteps(test); }

    let noLeg(test: Test): Void {
      expectInt(test, casesWalkSteps("graph").length, 0);
      expectFalse(test, casesWalkForView("graph"), "graph has no leg");
      expectTrue(test, casesWalkForView("follow"), "follow has");
    }

    test("a view with no leg gets none") { test => noLeg(test); }

    let handOver(test: Test): Void {
      let a = lastOf(casesWalkSteps("cases")).act;
      let b = lastOf(casesWalkSteps("follow")).act;
      expectTrue(test, a != null, "the first leg hands over");
      expectTrue(test, b != null, "the second leg hands over");
      if (a != null) {
        expectText(test, a.kind, "hop");
        expectText(test, orNone(a.to), "first_pair");
      }
      if (b != null) {
        expectText(test, b.kind, "hop");
        expectText(test, orNone(b.to), "case_read");
      }
      expectTrue(test, lastOf(casesWalkSteps("case_read")).act == null, "the last leg has no action");
    }

    test("each leg but the last hands over to the next") { test => handOver(test); }

    let actsOfLegs(test: Test): Void {
      for (let leg of ["cases", "follow", "case_read"]) {
        for (let s of casesWalkSteps(leg)) {
          let act = s.act;
          if (act != null) {
            if (act.kind == "push") {
              expectText(test, orNone(act.event), "set_only");
              expectTrue(test, act.params.has("only"), "a filter push names the filter");
            } else if (act.kind == "hop") {
              expectTrue(test, act.to != null, "a hop says where to");
            } else if (act.kind == "click") {
              expectText(test, orNone(act.target), ".cr-pick > summary");
            } else {
              expectTrue(test, false, "unexpected action ${act.kind} in ${leg}/${s.id}");
            }
          }
        }
      }
    }

    test("the actions of the legs are push, hop and click") { test => actsOfLegs(test); }

    let legCopy(test: Test): Void {
      let index = casesWalkSteps("cases");
      expectText(test, index[0].title, "One real disagreement, first");
      expectText(test, orNone(index[0].target), ".cs-case:first-of-type .cs-hook");
      expectHas(test, index[1].body, "Three of these sixteen never state their holding in one sentence");
      expectText(test, orNone(index[5].target), ".cs-case:first-of-type .cs-ways li:first-child");
      let follow = casesWalkSteps("follow");
      expectText(test, follow[0].title, "Left is read. Right is the reference");
      expectText(test, orNone(follow[3].target), ".fl-legend");
      let read = casesWalkSteps("case_read");
      expectText(test, read[0].title, "The whole case in one margin");
      expectTrue(test, read[4].target == null, "the last step spotlights nothing");
      expectText(test, read[4].place, "centre");
    }

    test("the copy of the term's legs is the Elixir's") { test => legCopy(test); }

## the tour: one card for each tab

    let everyTab(test: Test): Void {
      for (let v of ["read", "graph", "spine", "threads", "trace", "prompts"]) {
        let card = tourFor(v);
        expectTrue(test, card != null, "${v} has no tour");
        if (card != null) {
          expectTrue(test, card.title != "", "${v} has a title");
          expectTrue(test, card.points.length >= 3, "${v} needs more than a sentence");
        }
      }
    }

    test("every tab that exists has something to say") { test => everyTab(test); }

    let tourCopy(test: Test): Void {
      let read = tourFor("read");
      let graph = tourFor("graph");
      let spine = tourFor("spine");
      if (read != null) {
        expectText(test, read.title, "The page, with its notes in the margin");
        expectHas(test, joined(read.points), "thin line appears");
        expectInt(test, read.points.length, 4);
      } else {
        expectTrue(test, false, "read");
      }
      if (graph != null) { expectText(test, graph.title, "What leads to what"); }
      if (spine != null) { expectText(test, spine.title, "The whole draft at once"); }
    }

    test("the tour cards say what the Elixir said") { test => tourCopy(test); }

    let tourViewList(test: Test): Void {
      expectText(test, joined(tourViews()), "follow,graph,prompts,read,spine,threads,trace");
      expectTrue(test, tourFor("nothing") == null, "an unknown view has no card");
      let follow = tourFor("follow");
      if (follow != null) {
        expectInt(test, follow.points.length, 6);
        expectText(test, follow.title, "Two documents, read as one");
      } else {
        expectTrue(test, false, "follow");
      }
    }

    test("the views with a card, sorted, are what gets stored as seen") { test => tourViewList(test); }
