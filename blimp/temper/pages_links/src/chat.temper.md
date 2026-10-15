# The chat bubble

`MarginaliaWeb.LinkChat.bubble/1`: the round button over the page and, open,
the panel in which the reader asks about the pair. The conversation is not
kept anywhere the model can see it change: it lives in the session's UI state
under `links:<id>:chat` as JSON and goes away with a fresh visit, as it went
away with the LiveView process.

    let { Ctx, uiGet, uiPut, uiDelete } = import("webcore/src");
    let { h, hv, htext, hraw, attr, classes, markdownToHtml } = import("html/src");
    let { JsonObject, JsonSyntaxTree, JsonArray, JsonString, JsonBoolean, JsonTextProducer, NullInterchangeContext, parseJson } = import("std/json");
    let { LinkEdgeEnds, linksJsonField, linksJsonInt } = import("links/src");
    let { LlmMessage } = import("llm/src");
    let { sysJoin } = import("sys/src");

## The state

`cited` are edge ids, in the order they were pointed at. `history` is the last
`pagesLinksChatKept()` turns: the Elixir kept them all, in the socket, until
the tab went away; the session's UI state is one column rewritten on every
change, so it is cut (and the model sees no more than that either).

    export class LinksChat(
      public open: Boolean,
      public history: List<LlmMessage>,
      public cited: List<Int>,
    ) {}

    export let pagesLinksChatKept(): Int { 20 }

    export let pagesLinksChatKey(linkId: Int): String { "links:${linkId.toString()}:chat" }

    export let pagesLinksNoChat(): LinksChat { new LinksChat(false, [], []) }

    export let pagesLinksChatOf(ctx: Ctx, linkId: Int): LinksChat {
      let raw = uiGet(ctx, pagesLinksChatKey(linkId));
      if (raw != null) { plChatParse(raw) } else { pagesLinksNoChat() }
    }

    let plChatParse(raw: String): LinksChat {
      let tree: JsonSyntaxTree? = parseJson(raw) orelse null;
      if (!(tree is JsonObject)) { return pagesLinksNoChat(); }
      let open = linksJsonField(tree, "open");
      let history = new ListBuilder<LlmMessage>();
      let turns = linksJsonField(tree, "history");
      if (turns is JsonArray) {
        for (let t of turns.elements) {
          let role = linksJsonField(t, "role");
          let content = linksJsonField(t, "content");
          if (role is JsonString) {
            if (content is JsonString) {
              history.add(new LlmMessage(role.content, content.content));
            }
          }
        }
      }
      let cited = new ListBuilder<Int>();
      let ids = linksJsonField(tree, "cited");
      if (ids is JsonArray) {
        for (let x of ids.elements) {
          let id = linksJsonInt(x, false);
          if (id != null) { cited.add(id); }
        }
      }
      new LinksChat(open is JsonBoolean && open.content, history.toList(), cited.toList())
    }

    export let pagesLinksChatText(chat: LinksChat): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      p.objectKey("open");
      p.booleanValue(chat.open);
      p.objectKey("history");
      p.startArray();
      let from = if (chat.history.length > pagesLinksChatKept()) { chat.history.length - pagesLinksChatKept() } else { 0 };
      var i = from;
      while (i < chat.history.length) {
        let m = chat.history[i];
        p.startObject();
        p.objectKey("role");
        p.stringValue(m.role);
        p.objectKey("content");
        p.stringValue(m.content);
        p.endObject();
        i += 1;
      }
      p.endArray();
      p.objectKey("cited");
      p.startArray();
      for (let id of chat.cited) { p.int32Value(id); }
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

    export let pagesLinksChatPut(ctx: Ctx, linkId: Int, chat: LinksChat): Void throws Bubble {
      uiPut(ctx, pagesLinksChatKey(linkId), pagesLinksChatText(chat));
    }

## The component

Defaults of the Elixir attributes: the title, the label of the button, the
placeholder, the hint and the three openers.

    export let pagesLinksChatOpeners(): List<String> {
      [
        "What does the second document already answer?",
        "Which disagreement here is real, and which is vocabulary?",
        "Which connection is doing the most work?",
      ]
    }

    let plChatHint(): String {
      "This one holds both maps and every edge between them. Ask what the second draft already answers, where the disagreement is real, or which connection is doing the most work. It will not write for either of them."
    }

An assistant turn is Markdown (hard breaks, sanitised); a user turn is text.

    let plTurn(m: LlmMessage): List<AnyValue> {
      let mine = m.role == "user";
      h("div", attr("class", "lc-turn ${m.role}"), [
        "\n",
        h("span", attr("class", "who"), htext(if (mine) { "you" } else { "the reader" })),
        "\n",
        h("div", attr("class", "said md"), [
          "\n",
          if (mine) { htext(m.content) } else { hraw(markdownToHtml(m.content)) },
          "\n",
        ]),
        "\n",
      ])
    }

What the reader pointed at: both passages go to the model in full, so
removing a chip removes it from the question.

    let plChip(e: LinkEdgeEnds): List<AnyValue> {
      h("div", attr("class", "chip ${e.edge.edgeType}"), [
        "\n",
        h("span", attr("class", "rel"), htext(sysJoin(e.edge.edgeType.split("_"), " "))),
        "\n",
        h("span", attr("class", "t"), htext("${e.from.title} ↔ ${e.to.title}")),
        "\n",
        h("button", "${attr("phx-click", "uncite")}${attr("phx-value-edge", e.edge.id.toString())}${attr("aria-label", "Remove")}", htext("×")),
        "\n",
      ])
    }

    let plPanel(chat: LinksChat, thinking: Boolean, cited: List<LinkEdgeEnds>): List<AnyValue> {
      let title = "About this pair";
      h("div", "${attr("class", "lc-panel")}${attr("role", "dialog")}${attr("aria-label", title)}", [
        "\n",
        h("div", attr("class", "lc-head"), [
          "\n",
          h("span", attr("class", "mg-label"), htext(title)),
          "\n",
          h("button", "${attr("class", "lc-x")}${attr("phx-click", "toggle_chat")}${attr("aria-label", "Close")}", htext("×")),
          "\n",
        ]),
        "\n",
        h("div", "${attr("class", "lc-body")}${attr("id", "lc-body")}${attr("phx-hook", "StickDown")}", [
          "\n",
          if (chat.history.length == 0) {
            h("p", attr("class", "lc-hint"), htext("\n${plChatHint()}\n"))
          } else { [] },
          "\n",
          if (chat.history.length == 0) {
            h("div", attr("class", "lc-openers"), [
              "\n",
              pagesLinksChatOpeners().map { (q: String): List<AnyValue> =>
                [
                  h("button", "${attr("type", "button")}${attr("phx-click", "chat_send")}${attr("phx-value-message", q)}", htext("\n${q}\n")),
                  "\n",
                ]
              },
            ])
          } else { [] },
          "\n",
          chat.history.map { (m: LlmMessage): List<AnyValue> => plTurn(m) },
          "\n",
          if (thinking) {
            h("div", "${attr("class", "mg-dots")}${attr("aria-label", "reading")}", [
              "\n",
              h("span", attr("class", "mg-dot"), []),
              "\n",
              h("span", "${attr("class", "mg-dot")}${attr("style", "animation-delay:.18s")}", []),
              "\n",
              h("span", "${attr("class", "mg-dot")}${attr("style", "animation-delay:.36s")}", []),
              "\n",
            ])
          } else { [] },
          "\n",
        ]),
        "\n",
        if (cited.length > 0) {
          h("div", attr("class", "lc-cited"), [
            "\n",
            h("span", attr("class", "mg-label"), htext("pointing at")),
            "\n",
            cited.map { (e: LinkEdgeEnds): List<AnyValue> => plChip(e) },
          ])
        } else { [] },
        "\n",
        h("form", "${attr("class", "lc-foot")}${attr("phx-submit", "chat_send")}${attr("id", "lc-form")}${attr("phx-hook", "LinkChatComposer")}", [
          "\n",
          h("textarea", "${attr("name", "message")}${attr("rows", "2")}${attr("placeholder", "How do these two sit together?")}${if (thinking) { " disabled" } else { "" }}", []),
          "\n",
          h("div", attr("class", "row"), [
            "\n",
            h("span", attr("class", "mg-hint mt-0"), htext("Enter to send")),
            "\n",
            h("button", "${attr("type", "submit")}${attr("class", "mg-btn sm")}${if (thinking) { " disabled" } else { "" }}", htext("Ask")),
            "\n",
          ]),
          "\n",
        ]),
        "\n",
      ])
    }

`count` is the number of turns, shown on the button while the panel is shut.

    export let renderLinkChatBubble(chat: LinksChat, thinking: Boolean, cited: List<LinkEdgeEnds>): List<AnyValue> {
      let label = "Talk about how these two relate";
      let count = chat.history.length;
      h("div", "${attr("class", "lc")}${attr("id", "linkchat")}${attr("phx-hook", "LinkChat")}", [
        "\n",
        h("button", "${attr("class", classes(["lc-bubble", if (chat.open) { "on" } else { null }]))}${attr("phx-click", "toggle_chat")}${attr("aria-label", label)}${attr("title", label)}", [
          "\n",
          h("span", "${attr("class", "mark")}${attr("aria-hidden", "true")}", htext("↔")),
          "\n",
          if (count > 0 && !chat.open) {
            h("span", attr("class", "n"), htext(count.toString()))
          } else { [] },
          "\n",
        ]),
        "\n",
        if (chat.open) { plPanel(chat, thinking, cited) } else { [] },
        "\n",
      ])
    }
