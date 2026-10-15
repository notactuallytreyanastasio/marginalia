# The Spine view

`map_view/1`, the `:spine` branch, and `grounded_node/1` (3.6), which the
Threads view draws as well. The first impression, the note about what the read
left unfinished, the spine in order and the questions it raised.

Every card is a spine node, thread or question with what it is grounded in
underneath: the beats that realise it and the sections they sit in. The
Discuss button takes the whole lot into the chat, so the writer never has to
re-explain which thread they meant or go and find where it happens. It is the
draft's owner's, and `discuss_node` is the drawer's event (`chat.temper.md`).

    let { Ctx } = import("webcore/src");
    let { h, hraw, htext, attr } = import("html/src");
    let { GraphNode } = import("works/src");
    let { readingGrounding, readingPlain, ReadingGrounding, ReadingGround } = import("reading/src");

## One place the node happens

`<div :for={b <- @grounding.beats} class="hit">`: the section's ordinal, the
beat's title and, when it has one, its quote as it reads on the page. The
quotation marks around the quote are the template's own text, not the
database's, so they are not escaped.

    let pvHit(nodeId: Int, g: ReadingGround): List<AnyValue> {
      let s = g.section;
      let ordinal = if (s != null) { s.ordinal.toString() } else { "" };
      let q = g.quote;
      let quote: List<AnyValue> = if (q != null) {
        h("span", attr("class", "q"), [hraw("\""), htext(readingPlain(q)), hraw("\"")])
      } else { [] };
      h("div", "${attr("class", "hit")}${attr("id", "hit-${nodeId.toString()}-${g.id.toString()}")}", [
        h("span", attr("class", "n"), htext(ordinal)),
        h("span", attr("class", "min-w-0"), [
          h("span", attr("class", "t"), htext(g.title)),
          quote,
        ]),
      ])
    }

    let pvWhere(nodeId: Int, grounding: ReadingGrounding): List<AnyValue> {
      if (grounding.beats.length == 0) {
        h("div", attr("class", "mg-meta mt-2 opacity-60"), htext("not yet linked to anywhere in the draft"))
      } else {
        h("div", attr("class", "mg-where"), [
          h("span", attr("class", "mg-label"), htext("where it happens")),
          grounding.beats.map { (g: ReadingGround): List<AnyValue> => pvHit(nodeId, g) },
        ])
      }
    }

## The card

`n` is the spine's two-digit number, or the empty string for a thread or a
question. The grounding is read here, a query set per card, as the Elixir did.
The card has an id (`grounded-<node id>`) the HEEx did not give it, so the
morph keeps it where it is.

    export let showGroundedNode(
      ctx: Ctx, state: ShowState, node: GraphNode, n: String,
    ): List<AnyValue> throws Bubble {
      let grounding = readingGrounding(ctx.db, state.work, node.id);
      let number: List<AnyValue> = if (n != "") {
        h("span", attr("class", "mg-meta mr-1.5"), htext(n))
      } else { [] };
      let body = node.body;
      let detail: List<AnyValue> = if (body != null) {
        h("div", attr("class", "text-[0.8rem] text-[var(--mg-dim)] mt-1 leading-relaxed"), htext(body))
      } else { [] };
      let discuss: List<AnyValue> = if (state.mine) {
        h("button", "${attr("class", "mg-btn sm ghost shrink-0")}${attr("phx-click", "discuss_node")}${attr("phx-value-id", node.id.toString())}${attr("title", "Open the chat holding this and everywhere it happens")}", htext("Discuss"))
      } else { [] };
      h("div", "${attr("class", "mg-grounded")}${attr("id", "grounded-${node.id.toString()}")}", [
        h("div", attr("class", "flex items-start gap-3"), [
          h("div", attr("class", "min-w-0 flex-1"), [
            h("div", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "text-[1.04rem] leading-snug")}", [number, htext(node.title)]),
            detail,
          ]),
          discuss,
        ]),
        pvWhere(node.id, grounding),
      ])
    }

## The two-digit number

`String.pad_leading(to_string(i), 2, "0")`, one-based.

    let pvNumber(i: Int): String {
      if (i < 10) { "0${i.toString()}" } else { i.toString() }
    }

    let pvCards(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      let cards = new ListBuilder<List<AnyValue>>();
      var i = 0;
      while (i < state.spine.length) {
        cards.add(showGroundedNode(ctx, state, state.spine[i], pvNumber(i + 1)));
        i += 1;
      }
      h("div", attr("class", "mg-cards mt-5"), cards.toList())
    }

## The view

    export let renderSpineView(ctx: Ctx, state: ShowState): List<AnyValue> throws Bubble {
      let work = state.work;
      let impression = work.firstImpression;
      let first: List<AnyValue> = if (impression != null) {
        [
          h("h2", attr("class", "mg-label"), htext("First impression")),
          h("p", attr("class", "mg-prose mt-2.5 max-w-[78ch]"), htext(impression)),
        ]
      } else { [] };
      let detail = work.statusDetail;
      let status: List<AnyValue> = if (detail != null) {
        h("p", attr("class", "mt-3 text-[0.8rem] border-l-2 border-[var(--mg-accent)] pl-2.5 py-1 text-[var(--mg-dim)]"), htext(detail))
      } else { [] };
      let cards: List<AnyValue> = if (state.spine.length == 0) {
        h("p", attr("class", "mg-empty mt-4"), htext("No spine was produced for this draft."))
      } else {
        pvCards(ctx, state)
      };
      let questions: List<AnyValue> = if (state.questions.length > 0) {
        let qs = new ListBuilder<List<AnyValue>>();
        var j = 0;
        while (j < state.questions.length) {
          qs.add(showGroundedNode(ctx, state, state.questions[j], ""));
          j += 1;
        }
        [
          h("h2", attr("class", "mg-label mt-12"), htext("Questions this raised")),
          h("p", attr("class", "mg-hint"), htext("Each names something specific in the draft. In the page view they are attached to the paragraphs they are about.")),
          h("div", attr("class", "mg-cards mt-4"), qs.toList()),
        ]
      } else { [] };
      [
        first,
        status,
        h("h2", attr("class", if (impression != null) { "mg-label mt-12" } else { "mg-label" }), htext("The spine")),
        h("p", attr("class", "mg-hint"), htext("The chain the whole draft hangs off, in order.")),
        cards,
        questions,
      ]
    }
