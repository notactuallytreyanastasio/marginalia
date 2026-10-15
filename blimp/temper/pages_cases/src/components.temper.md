# The walk overlay and the chat bubble

`MarginaliaWeb.Walk.overlay/1` and `MarginaliaWeb.LinkChat.bubble/1`, the two
components the case pages share with the pairwise reading. The hooks they name
(`Walk`, `LinkChat`, `LinkChatComposer`, `StickDown`) are in `static/js/hooks`;
the markup here is what they find.

    let { h, hv, hraw, htext, attr } = import("html/src");
    let { markdownToHtml } = import("html/src");
    let { sysStringReplace } = import("sys/src");
    let { LinkEdgeEnds } = import("links/src");
    let { LlmMessage } = import("llm/src");
    let { WalkStep, walkthroughStepsJson } = import("cases/src");

## The walk

`data-steps` is the JSON of the steps, `data-auto` the name the browser keeps
the seen flag under (`mg.tour.<auto>`) and is absent on a page where the server
decides whether the walk runs. The ring, the veil and the card start `hidden`;
the hook moves them.

    export let pagesCasesWalkNote(): String {
      "Nothing here is saved, and no model is called — the answers are fixed examples."
    }

    export let pagesCasesWalkOverlay(steps: List<WalkStep>, auto: String?, note: String): List<AnyValue> {
      h("div", "${attr("id", "walk")}${attr("phx-hook", "Walk")}${attr("data-steps", walkthroughStepsJson(steps))}${attr("data-auto", auto)}", [
        "\n  ",
        h("div", "${attr("class", "mg-walk-ring")} hidden", []),
        "\n  ",
        h("div", "${attr("class", "mg-walk-veil")} hidden", []),
        "\n\n  ",
        h("div", "${attr("class", "mg-walk-card")} hidden", [
          "\n    ",
          h("div", attr("class", "mg-walk-head"), [
            "\n      ",
            h("span", attr("class", "mg-label"), hraw("Walkthrough")),
            "\n      ",
            h("span", attr("class", "n"), []),
            "\n      ",
            h("button", attr("class", "mg-btn sm ghost ml-auto end"), hraw("end")),
            "\n    ",
          ]),
          "\n    ",
          h("h3", "", []),
          "\n    ",
          h("p", attr("class", "body"), []),
          "\n    ",
          h("div", attr("class", "mg-walk-foot"), [
            "\n      ",
            h("button", attr("class", "mg-btn sm ghost back"), hraw("Back")),
            "\n      ",
            h("button", attr("class", "mg-btn sm next"), hraw("Next")),
            "\n    ",
          ]),
          "\n    ",
          h("p", attr("class", "mg-walk-safe"), htext(note)),
          "\n  ",
        ]),
        "\n",
      ])
    }

## The chat

What the bubble is told: whether the panel is open, the turns so far, the
connections the reader is pointing at, and the copy that is particular to the
page it sits on. The reply to a question arrives whole, so there is no thinking
state and no wait indicator.

    export class PagesCasesChat(
      public open: Boolean,
      public history: List<LlmMessage>,
      public cited: List<LinkEdgeEnds>,
      public title: String,
      public label: String,
      public hint: String,
      public placeholder: String,
      public openers: List<String>,
    ) {}

The copy of the case page's chat.

    export let pagesCasesChatCopy(open: Boolean, history: List<LlmMessage>, cited: List<LinkEdgeEnds>): PagesCasesChat {
      new PagesCasesChat(
        open, history, cited,
        "About this case",
        "Talk about how these documents sit together",
        "This one holds every document in the case and every connection between the one you are reading and the rest. Ask what the dissent already answered, what the lectern settled, or which of the disagreements is real. It writes for none of them.",
        "How do these sit together?",
        [
          "What did the dissent already answer?",
          "What did the advocates concede that the opinion then relied on?",
          "Where do these documents actually collide?",
        ],
      )
    }

    let pgcChatTurn(m: LlmMessage): List<AnyValue> {
      let isUser = m.role == "user";
      h("div", attr("class", "lc-turn ${m.role}"), [
        "\n          ",
        h("span", attr("class", "who"), htext(if (isUser) { "you" } else { "the reader" })),
        "\n          ",
        h("div", attr("class", "said md"), if (isUser) { htext(m.content) } else { hraw(markdownToHtml(m.content)) }),
        "\n        ",
      ])
    }

    let pgcChatOpener(q: String): List<AnyValue> {
      h("button", "${attr("type", "button")}${attr("phx-click", "chat_send")}${attr("phx-value-message", q)}", [
        "\n          ", htext(q), "\n        ",
      ])
    }

    let pgcChatChip(e: LinkEdgeEnds): List<AnyValue> {
      h("div", attr("class", "chip ${e.edge.edgeType}"), [
        h("span", attr("class", "rel"), htext(sysStringReplace(e.edge.edgeType, "_", " "))),
        h("span", attr("class", "t"), htext("${e.from.title} ↔ ${e.to.title}")),
        h("button", "${attr("phx-click", "uncite")}${attr("phx-value-edge", e.edge.id.toString())}${attr("aria-label", "Remove")}", hraw("×")),
      ])
    }

The panel: the hint and the openers while the conversation is empty, then the
turns, then what the reader is pointing at, then the form.

    let pgcChatPanel(c: PagesCasesChat): List<AnyValue> {
      let empty = c.history.length == 0;
      h("div", "${attr("class", "lc-panel")}${attr("role", "dialog")}${attr("aria-label", c.title)}", [
        "\n    ",
        h("div", attr("class", "lc-head"), [
          h("span", attr("class", "mg-label"), htext(c.title)),
          h("button", "${attr("class", "lc-x")}${attr("phx-click", "toggle_chat")}${attr("aria-label", "Close")}", hraw("×")),
        ]),
        "\n\n    ",
        h("div", "${attr("class", "lc-body")}${attr("id", "lc-body")}${attr("phx-hook", "StickDown")}", [
          "\n      ",
          if (empty) { h("p", attr("class", "lc-hint"), htext(c.hint)) } else { [] },
          "\n      ",
          if (empty && c.openers.length > 0) {
            h("div", attr("class", "lc-openers"), c.openers.map { (q: String): List<AnyValue> => pgcChatOpener(q) })
          } else { [] },
          "\n      ",
          c.history.map { (m: LlmMessage): List<AnyValue> => pgcChatTurn(m) },
          "\n    ",
        ]),
        "\n\n    ",
        if (c.cited.length > 0) {
          h("div", attr("class", "lc-cited"), [
            h("span", attr("class", "mg-label"), hraw("pointing at")),
            c.cited.map { (e: LinkEdgeEnds): List<AnyValue> => pgcChatChip(e) },
          ])
        } else { [] },
        "\n\n    ",
        h("form", "${attr("class", "lc-foot")}${attr("phx-submit", "chat_send")}${attr("id", "lc-form")}${attr("phx-hook", "LinkChatComposer")}", [
          "\n      ",
          h("textarea", "${attr("name", "message")}${attr("rows", "2")}${attr("placeholder", c.placeholder)}", []),
          "\n      ",
          h("div", attr("class", "row"), [
            h("span", attr("class", "mg-hint mt-0"), hraw("Enter to send")),
            h("button", "${attr("type", "submit")}${attr("class", "mg-btn sm")}", hraw("Ask")),
          ]),
          "\n    ",
        ]),
        "\n  ",
      ])
    }

`div#linkchat` holds the bubble and, open, the panel. The bubble's number is
how many turns there are, shown only while the panel is shut.

    export let pagesCasesChatBubble(c: PagesCasesChat): List<AnyValue> {
      let count = c.history.length;
      h("div", "${attr("class", "lc")}${attr("id", "linkchat")}${attr("phx-hook", "LinkChat")}", [
        "\n  ",
        h("button", "${attr("class", if (c.open) { "lc-bubble on" } else { "lc-bubble" })}${attr("phx-click", "toggle_chat")}${attr("aria-label", c.label)}${attr("title", c.label)}", [
          "\n    ",
          h("span", "${attr("class", "mark")}${attr("aria-hidden", "true")}", hraw("↔")),
          "\n    ",
          if (count > 0 && !c.open) { h("span", attr("class", "n"), htext(count.toString())) } else { [] },
          "\n  ",
        ]),
        "\n\n  ",
        if (c.open) { pgcChatPanel(c) } else { [] },
        "\n",
      ])
    }
