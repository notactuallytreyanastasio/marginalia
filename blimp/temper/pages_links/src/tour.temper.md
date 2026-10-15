# The one-time card and the walkthrough

Two ways of explaining the follow view. The card is shown once, on a first
visit, over the page (`Tour.for_view(:follow)`); the walkthrough
(`MarginaliaWeb.Walk.overlay/1`) is a spotlight that presses the page's own
controls, started by `?walk=1`.

    let { h, hv, htext, attr } = import("html/src");
    let { JsonTextProducer, NullInterchangeContext } = import("std/json");

## The card

Over the page rather than beside it: the things it describes are the page, and
a card in a corner is read after you have already failed to work out what the
dimmed half is for.

    export let pagesLinksTourTitle(): String { "Two documents, read as one" }

    export let pagesLinksTourPoints(): List<String> {
      [
        "The left is what you are reading. The right is the reference, and it is dimmed on purpose — it lights up only where it has something to say about the passage you are on.",
        "Scroll the left. The right is scrolled for you, and snaps to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again.",
        "The line drawn between them runs through the reason in the middle — left passage, why, right passage, which is the actual shape of the claim. Click the line to carry both passages into the chat.",
        "The filters leave one kind of relation in view: where the two documents disagree, where one answers the other, where one depends on the other.",
        "Stretches where the two have nothing to say to each other are folded away, with their size on the label. Nothing is deleted — open one and read it.",
        "Referencing… swaps which document sits in the margin, and swap sides reads the other one as the lead. The pair is symmetric and the two directions are genuinely different.",
      ]
    }

    export let renderLinkTour(): List<AnyValue> {
      h("div", "${attr("class", "fl-tour-veil")}${attr("phx-click", "dismiss_tour")}", [
        "\n",
        h("div", "${attr("class", "fl-tour")}${attr("phx-click-away", "dismiss_tour")}", [
          "\n",
          h("div", attr("class", "fl-tour-head"), [
            "\n",
            h("h2", "", htext(pagesLinksTourTitle())),
            "\n",
            h("button", "${attr("class", "mg-btn sm ghost")}${attr("phx-click", "dismiss_tour")}", htext("Got it")),
            "\n",
          ]),
          "\n",
          h("ul", "", [
            "\n",
            pagesLinksTourPoints().map { (point: String): List<AnyValue> =>
              [h("li", "", htext(point)), "\n"]
            },
          ]),
          "\n",
          h("p", attr("class", "mg-hint"), ["The ", h("strong", "", htext("?")), " in the bar brings this back."]),
          "\n",
        ]),
        "\n",
      ])
    }

## The walkthrough

`Walkthrough.Cases.steps(:follow)`: eight steps. Each has an `id`, a `title`, a
`body`, the CSS selector of the thing it lights, which side of it the card
prefers, and optionally an `act`: push an event (`set_only`), or hop to
another page (`case_read`).

    export class LinksWalkStep(
      public id: String,
      public title: String,
      public body: String,
      public target: String,
      public place: String,
      public actKind: String,
      public actEvent: String,
      public actValue: String,
    ) {}

    let plStep(id: String, title: String, body: String, target: String, place: String): LinksWalkStep {
      new LinksWalkStep(id, title, body, target, place, "", "", "")
    }

    export let pagesLinksWalkSteps(): List<LinksWalkStep> {
      [
        plStep("sides", "Left is read. Right is the reference",
          "One document down the left at your own pace. The other is dimmed on purpose — it lights up only where it has something to say about the passage you are on.",
          ".fl-colhead", "bottom"),
        plStep("follow", "The right side follows you",
          "Scroll the left and the right is scrolled for you, snapping to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again.",
          "#fl-lead", "right"),
        plStep("wire", "The line runs through the reason",
          "Left passage, why, right passage — the actual shape of the claim. The middle is the reason for drawing it, and it belongs to neither document.",
          ".fl-mid", "left"),
        new LinksWalkStep("filter", "One kind of relation at a time",
          "Tension leaves only where the two genuinely pull apart. Answers leaves where one replies to the other. The filter changes what the page is about, not how much of it there is.",
          ".fl-legend", "bottom", "push", "set_only", "tension"),
        new LinksWalkStep("filter_back", "Everything, again",
          "Back to the whole relationship, which is how it opens.",
          ".fl-legend", "bottom", "push", "set_only", "all"),
        plStep("gaps", "The quiet stretches are folded",
          "Where the two have nothing to say to each other, the prose is folded away with its size on the label. Nothing is deleted — open one and read it.",
          ".fl-gap", "right"),
        plStep("chat", "You can argue with it",
          "Click the line between two passages and both go into the question. The chat starts fresh on this page and holds whatever you cite into it.",
          ".lc", "left"),
        new LinksWalkStep("onward", "Two documents is the pair. Now the whole case",
          "The same opinion, with every other document in the case beside it at once.",
          ".fl-colhead", "bottom", "hop", "", "case_read"),
      ]
    }

    export let pagesLinksWalkNote(): String {
      "Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would."
    }

The `data-steps` JSON: `{id, title, body, target, place}` and, where there is
one, `act`: `{"kind": "push", "event": "set_only", "params": {"only": ...}}` or
`{"kind": "hop", "to": "case_read"}`.

    export let pagesLinksWalkJson(steps: List<LinksWalkStep>): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startArray();
      var i = 0;
      while (i < steps.length) {
        let s = steps[i];
        i += 1;
        p.startObject();
        p.objectKey("id");
        p.stringValue(s.id);
        p.objectKey("title");
        p.stringValue(s.title);
        p.objectKey("body");
        p.stringValue(s.body);
        p.objectKey("target");
        p.stringValue(s.target);
        p.objectKey("place");
        p.stringValue(s.place);
        if (s.actKind == "push") {
          p.objectKey("act");
          p.startObject();
          p.objectKey("kind");
          p.stringValue("push");
          p.objectKey("event");
          p.stringValue(s.actEvent);
          p.objectKey("params");
          p.startObject();
          p.objectKey("only");
          p.stringValue(s.actValue);
          p.endObject();
          p.endObject();
        } else if (s.actKind == "hop") {
          p.objectKey("act");
          p.startObject();
          p.objectKey("kind");
          p.stringValue("hop");
          p.objectKey("to");
          p.stringValue(s.actValue);
          p.endObject();
        }
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

`data-auto` is absent on this page, so the hook starts at step 0 on mount and
End or Escape pushes `end_walk`.

    export let renderLinkWalk(): List<AnyValue> throws Bubble {
      h("div", "${attr("id", "walk")}${attr("phx-hook", "Walk")}${attr("data-steps", pagesLinksWalkJson(pagesLinksWalkSteps()))}", [
        "\n",
        h("div", "${attr("class", "mg-walk-ring")} hidden", []),
        "\n",
        h("div", "${attr("class", "mg-walk-veil")} hidden", []),
        "\n",
        h("div", "${attr("class", "mg-walk-card")} hidden", [
          "\n",
          h("div", attr("class", "mg-walk-head"), [
            "\n",
            h("span", attr("class", "mg-label"), htext("Walkthrough")),
            "\n",
            h("span", attr("class", "n"), []),
            "\n",
            h("button", attr("class", "mg-btn sm ghost ml-auto end"), htext("end")),
            "\n",
          ]),
          "\n",
          h("h3", "", []),
          "\n",
          h("p", attr("class", "body"), []),
          "\n",
          h("div", attr("class", "mg-walk-foot"), [
            "\n",
            h("button", attr("class", "mg-btn sm ghost back"), htext("Back")),
            "\n",
            h("button", attr("class", "mg-btn sm next"), htext("Next")),
            "\n",
          ]),
          "\n",
          h("p", attr("class", "mg-walk-safe"), htext(pagesLinksWalkNote())),
          "\n",
        ]),
        "\n",
      ])
    }
