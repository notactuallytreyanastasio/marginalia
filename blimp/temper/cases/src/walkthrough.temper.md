# The tour and the walkthroughs

Static data, ported verbatim: `Marginalia.Tour` (the per-tab explainer cards),
`Marginalia.Walkthrough` (the guided run through the read view, with its
canned rewrite and canned exchange) and `Marginalia.Walkthrough.Cases` (the
three legs of the run through a Supreme Court term).

The Elixir kept these as maps with atom keys. Here a step is a `WalkStep` and
an action a `WalkAct`, so a misspelt field is a compile error rather than a
`nil`. `walkthroughStepsJson` produces the JSON the client reads; an absent
`owner` or `act` is omitted from it, as `Jason` omitted the missing key.

    let { JsonTextProducer, NullInterchangeContext } = import("std/json");

## Shapes

`kind` is `push` (send `event` with `params` to the server), `client` (run the
named client action `clientName`), `hop` (go to the next leg, `to`) or `click`
(press the element matching the selector `target`). Only the fields of that
kind are set; the rest are null or empty.

    export class WalkAct(
      public kind: String,
      public event: String?,
      public params: Map<String, String>,
      public clientName: String?,
      public to: String?,
      public target: String?,
    ) {}

`target` is a CSS selector or null (a step with no spotlight). `place` is one
of `left`, `right`, `bottom`, `top`, `centre`. `owner` marks a step that
narrates a control only the draft's owner has.

    export class WalkStep(
      public id: String,
      public title: String,
      public body: String,
      public target: String?,
      public place: String,
      public owner: Boolean,
      public act: WalkAct?,
    ) {}

    let walkNoParams(): Map<String, String> { new MapBuilder<String, String>().toMap() }

    let walkPush(event: String, only: String): WalkAct {
      let params = new MapBuilder<String, String>();
      params.set("only", only);
      new WalkAct("push", event, params.toMap(), null, null, null)
    }

    let walkClient(clientName: String): WalkAct {
      new WalkAct("client", null, walkNoParams(), clientName, null, null)
    }

    let walkHop(to: String): WalkAct {
      new WalkAct("hop", null, walkNoParams(), null, to, null)
    }

    let walkClick(target: String): WalkAct {
      new WalkAct("click", null, walkNoParams(), null, null, target)
    }

## The read view's steps

Ten steps. `ask`, `rewrite` and `edit` are the owner's.

    let walkReadSteps(): List<WalkStep> {
      [
        new WalkStep("margin", "The notes sit beside the line", "Every note is level with the sentence that caused it, and the highlight under the prose is the exact span it is anchored to — copied out of your draft character for character.", ".mg-read-rail .mg-note-slot", "left", false, null),
        new WalkStep("filters", "The filter changes what the margin is about", "Watch the margin, not the tabs. Tensions leaves only the places the draft argues with itself. Beats is what it does, in order; Connections is what reaches across sections.", "#read-filters", "bottom", false, walkPush("set_only", "tensions")),
        new WalkStep("filters_back", "Everything, again", "Back to both passes at once, which is how it opens. The filter never removes a note from the draft — only from this view.", "#read-filters", "bottom", false, walkPush("set_only", "all")),
        new WalkStep("map", "A map of the draft, drawn to scale", "Each block is sized by its section's word count, so the shape of the thing is visible before you have read a line of it. Click any block to land there.", ".mg-map", "right", false, walkClient("open_map")),
        new WalkStep("thread", "A thread pinned to one paragraph", "Move the pointer to the left edge of any paragraph and a hairline appears in the gutter. Clicking it opens a conversation about that paragraph, already holding it — and it is still there when you come back.", ".mg-read-body .mg-block", "right", false, walkClient("open_thread")),
        new WalkStep("ask", "Ask about that spot", "No re-explaining which bit you meant. The paragraph goes in as the subject of the question.", ".mg-thread-panel", "right", true, walkClient("ask_thread")),
        new WalkStep("select", "Or select a passage", "Click and hold, then drag across any run of text. Three things come up at the end of it: talk about that spot, ask for rewrites of it, or carry it into the chat.", ".mg-read-body .mg-block", "right", false, walkClient("select")),
        new WalkStep("rewrite", "Three rewrites, each with its cost", "The one place it writes, and it only opens from your side. Hover a candidate to see it over your own line as a diff. Nothing is ever applied.", ".mg-rewrite", "right", true, walkClient("rewrite")),
        new WalkStep("edit", "Then answer it in your own words", "Click into any paragraph and it opens for editing, in the markdown you wrote it in. Start from a candidate or ignore them all. Saving is switched off for the tour.", ".mg-read-body .mg-block", "right", true, walkClient("edit")),
        new WalkStep("done", "That is the read view", "The thread, the rewrite and the edit you just saw were never written down, and no model was called for any of it. Your draft is exactly as you left it. The ? in the header runs this again.", null, "centre", false, walkClient("reset")),
      ]
    }


## `Walkthrough.steps/2`

The ordered steps for a view, or `[]` where there is no walkthrough.
`mine` false drops the steps that only exist for the person who owns the
draft: a reader of a draft sent to them cannot type in a thread, ask for
rewrites or edit a paragraph.

    export let walkthroughSteps(view: String, mine: Boolean): List<WalkStep> {
      if (view == "read") {
        if (mine) {
          walkReadSteps()
        } else {
          walkReadSteps().filter { (s: WalkStep): Boolean => !s.owner }
        }
      } else {
        []
      }
    }

Whether a view has one (for a reader who does not own the draft).

    export let walkthroughForView(view: String): Boolean {
      walkthroughSteps(view, false).length > 0
    }

Views with a walkthrough, as the strings stored against an account.

    export let walkthroughViews(): List<String> { ["read"] }

## Fixtures

What the tour shows instead of calling the model. Deliberately about a sample
sentence rather than the writer's own.

    export class WalkCandidate(public text: String, public move: String, public cost: String) {}

`spansBlocks` false and `covers` empty are not in the Elixir fixture. The
rewrite panel reads `rewrite.spans_blocks`, and a missing key raised there,
which in a LiveView drops the socket (the walkthrough's rewrite step crashed
the page as the source stands). The fixture carries them so the panel renders
it through the same path as a real answer.

    export class WalkRewrite(
      public sample: Boolean,
      public reading: String,
      public original: String,
      public section: String?,
      public candidates: List<WalkCandidate>,
      public spansBlocks: Boolean,
      public covers: List<String>,
    ) {}

    export let walkthroughRewrite(): WalkRewrite {
      new WalkRewrite(
        true,
        "The line is doing two jobs: announcing that something changed, and holding back what it was.",
        "It was, in a sense, the beginning of something that would eventually change everything about the way she saw her father.",
        null,
        [
          new WalkCandidate(
            "It changed how she saw her father.",
            "Cuts the gloss",
            "Loses the narrator's distance from the moment",
          ),
          new WalkCandidate(
            "She would not see her father the same way again, and this was where it started.",
            "Puts the change last",
            "Slower into the paragraph that follows",
          ),
          new WalkCandidate(
            "She watched him back the car out, and something in it went.",
            "Hands it to the image",
            "Only works if the car is already in the scene",
          ),
        ],
        false,
        [],
      )
    }

The question the tour types into the thread, and the answer it gets. The
answer ends with a newline, as the heredoc did.

    export class WalkExchange(public question: String, public answer: String) {}

    export let walkthroughExchange(): WalkExchange {
      let lines = [
        "Two things, and the second one is quieter.",
        "",
        "It is placing the scene — where everyone is standing, and how long they have been",
        "standing there. And it is establishing that nobody in the room will say the thing",
        "out loud, which the rest of the section then depends on.",
        "",
        "The risk is that the second job is carried entirely by one clause. If a reader",
        "skims it, the next three pages read as people being oddly polite.",
        "",
        "*(A fixed example. The tour never calls the model, so this is not a reading of",
        "your paragraph.)*",
      ];
      let text = lines.join("\n") { (l: String): String => l };
      new WalkExchange("What is this paragraph actually doing?", "${text}\n")
    }

Both fixtures together, for a page that wants them in one call.

    export class WalkFixtures(public rewrite: WalkRewrite, public exchange: WalkExchange) {}

    export let walkthroughFixtures(): WalkFixtures {
      new WalkFixtures(walkthroughRewrite(), walkthroughExchange())
    }

## The term's three legs

    let walkCasesIndex(): List<WalkStep> {
      [
        new WalkStep("hook", "One real disagreement, first", "Every case leads with the sharpest thing found between its documents, in the terms the pass used. Not a summary of the case — a place where two of its documents pull against each other.", ".cs-case:first-of-type .cs-hook", "bottom", false, null),
        new WalkStep("held", "The holding is the Court's own sentence", "Quoted out of the opinion, not paraphrased, and not taken from the Reporter's syllabus — which is no part of the opinion and says so on its own first page. Three of these sixteen never state their holding in one sentence, and those show none at all.", ".cs-case:first-of-type .cs-held", "bottom", false, null),
        new WalkStep("ways", "A case is read one document against another", "Not 'open the case'. The opinion against the dissent, the opinion against the advocate it is answering — each with how much the two actually have to say to each other, which is the honest signal of which to open.", ".cs-case:first-of-type .cs-ways", "top", false, null),
        new WalkStep("kin", "And the term argues with itself", "Cases are related across the term too, chosen by the vocabulary the opinions actually share rather than by anyone's idea of a theme. It is the only thing here that could not have come from reading one case carefully.", ".cs-case:first-of-type .cs-kin", "top", false, null),
        new WalkStep("sources", "Everything links back to the PDF", "The whole claim of this site is that none of it is invented. The only way to make that checkable is to keep the Court's own file one click away, so every document does.", ".cs-case:first-of-type .cs-parts", "top", false, null),
        new WalkStep("into", "Now the reading itself", "This is where the site actually happens. Opening the strongest pairing in the first case.", ".cs-case:first-of-type .cs-ways li:first-child", "top", false, walkHop("first_pair")),
      ]
    }

    let walkCasesFollow(): List<WalkStep> {
      [
        new WalkStep("sides", "Left is read. Right is the reference", "One document down the left at your own pace. The other is dimmed on purpose — it lights up only where it has something to say about the passage you are on.", ".fl-colhead", "bottom", false, null),
        new WalkStep("follow", "The right side follows you", "Scroll the left and the right is scrolled for you, snapping to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again.", "#fl-lead", "right", false, null),
        new WalkStep("wire", "The line runs through the reason", "Left passage, why, right passage — the actual shape of the claim. The middle is the reason for drawing it, and it belongs to neither document.", ".fl-mid", "left", false, null),
        new WalkStep("filter", "One kind of relation at a time", "Tension leaves only where the two genuinely pull apart. Answers leaves where one replies to the other. The filter changes what the page is about, not how much of it there is.", ".fl-legend", "bottom", false, walkPush("set_only", "tension")),
        new WalkStep("filter_back", "Everything, again", "Back to the whole relationship, which is how it opens.", ".fl-legend", "bottom", false, walkPush("set_only", "all")),
        new WalkStep("gaps", "The quiet stretches are folded", "Where the two have nothing to say to each other, the prose is folded away with its size on the label. Nothing is deleted — open one and read it.", ".fl-gap", "right", false, null),
        new WalkStep("chat", "You can argue with it", "Click the line between two passages and both go into the question. The chat starts fresh on this page and holds whatever you cite into it.", ".lc", "left", false, null),
        new WalkStep("onward", "Two documents is the pair. Now the whole case", "The same opinion, with every other document in the case beside it at once.", ".fl-colhead", "bottom", false, walkHop("case_read")),
      ]
    }

    let walkCasesRead(): List<WalkStep> {
      [
        new WalkStep("margin", "The whole case in one margin", "The dissent and every advocate, against the same paragraph, each saying which one it is. Reading the pairs separately is exactly what this hides — and the paragraphs where all of them speak at once are the ones worth having.", ".cr-grid .cr-notes:not(.bare)", "left", false, null),
        new WalkStep("row", "A paragraph and its notes are one row", "One hairline runs from the left edge of the paragraph, across the gutter, into its notes. They are level because the layout says so — there is no scrolling machinery here to drift.", ".cr-text.linked", "right", false, null),
        new WalkStep("who", "Filter by who is speaking", "Each chip is one of the other documents, with how often it has something to say. A dashed chip is another case in the term rather than another document in this one.", ".cr-srcs", "bottom", false, null),
        new WalkStep("lead", "Read it from anyone's side", "Any document in the case can be the one you read. The dissent with the majority in its margin is a different experience from the reverse, and both of them are the case.", ".cr-pick", "bottom", false, walkClick(".cr-pick > summary")),
        new WalkStep("done", "That is the whole of it", "Sixteen cases, eighty-two documents, each read on its own and then related. Every connection is anchored to a sentence in both documents, and anything that could not be found in both was discarded before it was stored.", null, "centre", false, null),
      ]
    }


`Walkthrough.Cases.steps/1`: the steps for a leg (`cases`, `follow`,
`case_read`), or `[]` for a view with no leg of the tour.

    export let casesWalkSteps(leg: String): List<WalkStep> {
      if (leg == "cases") {
        walkCasesIndex()
      } else if (leg == "follow") {
        walkCasesFollow()
      } else if (leg == "case_read") {
        walkCasesRead()
      } else {
        []
      }
    }

    export let casesWalkForView(leg: String): Boolean {
      casesWalkSteps(leg).length > 0
    }

## The JSON the client reads

    let walkWriteAct(p: JsonTextProducer, a: WalkAct): Void {
      p.startObject();
      p.objectKey("kind");
      p.stringValue(a.kind);
      let event = a.event;
      if (event != null) {
        p.objectKey("event");
        p.stringValue(event);
      }
      if (a.kind == "push") {
        p.objectKey("params");
        p.startObject();
        let only = a.params.getOr("only", "");
        p.objectKey("only");
        p.stringValue(only);
        p.endObject();
      }
      let clientName = a.clientName;
      if (clientName != null) {
        p.objectKey("name");
        p.stringValue(clientName);
      }
      let to = a.to;
      if (to != null) {
        p.objectKey("to");
        p.stringValue(to);
      }
      let target = a.target;
      if (target != null) {
        p.objectKey("target");
        p.stringValue(target);
      }
      p.endObject();
    }

    export let walkthroughStepsJson(steps: List<WalkStep>): String {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startArray();
      var i = 0;
      while (i < steps.length) {
        let s = steps[i];
        p.startObject();
        p.objectKey("id");
        p.stringValue(s.id);
        p.objectKey("title");
        p.stringValue(s.title);
        p.objectKey("body");
        p.stringValue(s.body);
        p.objectKey("target");
        let target = s.target;
        if (target != null) { p.stringValue(target); } else { p.nullValue(); }
        p.objectKey("place");
        p.stringValue(s.place);
        if (s.owner) {
          p.objectKey("owner");
          p.booleanValue(true);
        }
        let act = s.act;
        if (act != null) {
          p.objectKey("act");
          walkWriteAct(p, act);
        }
        p.endObject();
        i += 1;
      }
      p.endArray();
      p.toJsonString() orelse panic()
    }

## The tour: one card per tab

`Marginalia.Tour`. A card is a title and its points. `tourFor` is the card
for a view, or null; `tourViews` is every view that has one, sorted, which is
what gets stored as seen.

    export class TourCard(public view: String, public title: String, public points: List<String>) {}

    let tourCards(): List<TourCard> {
      [
        new TourCard("read", "The page, with its notes in the margin", [
          "Every note sits beside the sentence that caused it. The highlight is the span it is anchored to, copied from your draft character for character.", 
          "Everything is on by default. Beats are what the draft does, in order; Connections and Tensions are what crosses sections. Each filter leaves only that kind in the margin.", 
          "Click and hold, then drag across any passage to select it. Three things come up: talk about that spot, ask for rewrites of it, or carry it into the chat.", 
          "Move the pointer to the left edge of a paragraph and a thin line appears in the margin. Click it to start a thread pinned to that paragraph, which will still be there when you come back."
        ]),
        new TourCard("follow", "Two documents, read as one", [
          "The left is what you are reading. The right is the reference, and it is dimmed on purpose — it lights up only where it has something to say about the passage you are on.", 
          "Scroll the left. The right is scrolled for you, and snaps to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again.", 
          "The line drawn between them runs through the reason in the middle — left passage, why, right passage, which is the actual shape of the claim. Click the line to carry both passages into the chat.", 
          "The filters leave one kind of relation in view: where the two documents disagree, where one answers the other, where one depends on the other.", 
          "Stretches where the two have nothing to say to each other are folded away, with their size on the label. Nothing is deleted — open one and read it.", 
          "Referencing… swaps which document sits in the margin, and swap sides reads the other one as the lead. The pair is symmetric and the two directions are genuinely different."
        ]),
        new TourCard("graph", "What leads to what", [
          "Every row is one move the draft makes. Hover a row and the panel on the right fills in with what it says — move down the list and read the whole draft without clicking anything.", 
          "Click a row to keep it there. The panel then holds its type, the section it came from, your own sentence underneath it, and every node it follows from or leads to. Hovering something else only previews; the one you clicked comes back when you move away.", 
          "A filled dot is anchored to a line in your draft. A hollow one is structural — the model's word for a move, with no single sentence behind it.", 
          "Solid lines are the chain running down the page. Dotted ones cross sections: develops, pays off, requires, tension.", 
          "Build decision graph runs the deciduous method over the whole draft — narratives first, then a goal / option / decision / action chain for each. It takes a few minutes and the Trace tab shows it happening."
        ]),
        new TourCard("spine", "The whole draft at once", [
          "The first impression is what a reader takes away, written before any of the detail.", 
          "The spine is the chain everything hangs off. Each node shows where it actually happens, with your own words under it.", 
          "Discuss opens the chat already holding that node and every section it touches, so you never re-explain which one you meant.", 
          "The questions at the bottom each name something specific. They are attached to their paragraphs on the page."
        ]),
        new TourCard("threads", "What runs across sections", [
          "A thread is a pattern that spans the draft rather than happening in one place — carried, thin, or dropped.", 
          "A dropped thread is usually the most useful thing on this page: something set up and never paid off.", 
          "Each shows the beats it runs through. Discuss carries the whole lot into the chat."
        ]),
        new TourCard("trace", "What the model actually did", [
          "Every tool call made while building the graph, and what the server answered.", 
          "The refusals are the point: a quote that was not in your draft, or a link that broke the flow rule. They are kept rather than hidden.", 
          "It fills in live while a build runs."
        ]),
        new TourCard("prompts", "Every prompt, read out of the running code", [
          "Not retyped here — read from the modules that ran, so this page cannot drift from what actually happened.", 
          "Each pass says which model it used and what it produces.", 
          "The chat's three stances are at the bottom."
        ]),
      ]
    }

    export let tourFor(view: String): TourCard? {
      let cards = tourCards();
      var i = 0;
      while (i < cards.length) {
        if (cards[i].view == view) { return cards[i]; }
        i += 1;
      }
      null
    }

    export let tourViews(): List<String> {
      tourCards()
        .map { (c: TourCard): String => c.view }
        .sorted { (a: String, b: String): Int => casesCompareText(a, b) }
    }
