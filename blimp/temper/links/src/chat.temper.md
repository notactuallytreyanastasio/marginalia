# Chat: talking about the relationship between two drafts

`Marginalia.Links.Chat`. The draft chat holds one manuscript and answers about
what is on its page. This one holds a pair, and the thing it knows that
nothing else does is the set of edges between them: which passage develops
which, where they argue, where they arrived at the same point separately.

It is handed both maps and every edge, and nothing else. No tools and no
retrieval: the maps are small, they cache, and a pass that could go looking
would spend a minute doing it for a question that is answerable from the
structure it already has.

**It is not kept.** The turns live in the page (the caller holds `history`)
and nowhere else. This is a conversation about a shape, and the shape changes
every time either draft is re-read or the pair is linked again; a resumed
thread would be answering questions about a graph that no longer exists. There
is deliberately no function here that stores a turn.

    let { Db } = import("db/src");
    let { LlmClient, LlmCall, LlmMessage, LlmReply, LlmError, Result, llmErrorText, llmConfigFromEnv, llmProvider } = import("llm/src");
    let { Work, GraphNode, worksListSections, worksNodes } = import("works/src");
    let { sysJoin, sysStringTrim, sysUtf8Upcase } = import("sys/src");

    export let linksChatPrompt(): String { linksChatSystem() }

The metadata `passes/0` gave the prompts page.

    export class LinksPass(
      public id: String,
      public name: String,
      public model: String,
      public runs: String,
      public produces: String,
      public prompt: String,
    ) {}

`LLM.default_model/0`: the configured model, else the provider's.

    export let linksDefaultModel(): String {
      let config = llmConfigFromEnv();
      if (config.model != "") { config.model } else { llmProvider(config.provider).model }
    }

    export let linksChatPasses(): List<LinksPass> {
      [new LinksPass(
        "link_chat",
        "Talking about a pair",
        linksDefaultModel(),
        "per message, on a linked pair",
        "answers about how two drafts relate",
        linksChatSystem(),
      )]
    }

## The card

Both maps and every edge, as one cacheable block. The order is for the
provider's prefix cache: the system prompt never changes, the two maps change
only when a draft is re-read, and the history only grows at the end.

    let linksChatSide(node: GraphNode, aId: Int): String {
      if (node.workId == aId) { "A" } else { "B" }
    }

`- A:[12] title --tension--> B:[30] title` and the reason on the next line.
The rationale has already been through `plain`.

    let linksChatEdgeLine(e: LinkEdgeEnds, aId: Int): String {
      "- ${linksChatSide(e.from, aId)}:[${e.edge.fromId.toString()}] ${e.from.title} --${e.edge.edgeType}--> ${linksChatSide(e.to, aId)}:[${e.edge.toId.toString()}] ${e.to.title}\n    ${linksOrEmpty(e.edge.rationale)}"
    }

    let linksChatNodeLine(n: GraphNode, ordinals: Map<Int, Int>): String {
      let parts = new ListBuilder<String>();
      parts.add("- [${n.id.toString()}]");
      let sectionId = n.sectionId;
      if (sectionId != null) {
        if (ordinals.has(sectionId)) {
          parts.add(" (§${ordinals.getOr(sectionId, 0).toString()})");
        } else {
          parts.add(" (§)");
        }
      }
      parts.add(" ${n.title}");
      let quote = n.quote;
      if (quote != null) {
        if (quote != "") { parts.add("\n    \"${linksOneLine(quote, 160)}\""); }
      }
      sysJoin(parts.toList(), "")
    }

The nodes of a work grouped by type, the types in ascending order (an Elixir
map iterates its keys sorted), each group `"\n## type\n"` and its lines, the
groups joined by a newline.

    let linksChatMap(db: Db, work: Work): String throws Bubble {
      let ordinals = new MapBuilder<Int, Int>();
      for (let s of worksListSections(db, work.id)) { ordinals.set(s.id, s.ordinal); }
      let ordinalMap = ordinals.toMap();
      let nodes = worksNodes(db, work.id);
      let types = new ListBuilder<String>();
      for (let n of nodes) {
        var known = false;
        var i = 0;
        while (i < types.length) {
          if (types[i] == n.nodeType) { known = true; }
          i += 1;
        }
        if (!known) {
          var at = types.length;
          while (at > 0 && n.nodeType < types[at - 1]) { at -= 1; }
          types.add(n.nodeType, at);
        }
      }
      let groups = new ListBuilder<String>();
      for (let kind of types.toList()) {
        let lines = new ListBuilder<String>();
        for (let n of nodes) {
          if (n.nodeType == kind) { lines.add(linksChatNodeLine(n, ordinalMap)); }
        }
        groups.add("\n## ${kind}\n${sysJoin(lines.toList(), "\n")}");
      }
      sysJoin(groups.toList(), "\n")
    }

`link.summary` here is the raw stored summary, not the `plain` one: the model
reads it as the pass wrote it.

    export let linksChatCard(db: Db, link: Link): String throws Bubble {
      let lw = linksWorks(db, link);
      let a = lw.aWork;
      let b = lw.bWork;
      let edges = linksEdges(db, link);
      let edgeLines = new ListBuilder<String>();
      for (let e of edges) { edgeLines.add(linksChatEdgeLine(e, a.id)); }
      let summary = link.summary;
      let established = if (summary != null) {
        "How they relate, as already established:\n${summary}\n"
      } else {
        ""
      };
      sysJoin([
        "# THE PAIR",
        "",
        "A: ${a.title} — ${a.wordCount.toString()} words",
        "B: ${b.title} — ${b.wordCount.toString()} words",
        "",
        established,
        "# THE EDGES BETWEEN THEM (${edges.length.toString()})",
        "",
        sysJoin(edgeLines.toList(), "\n"),
        "",
        "# MAP OF A: ${a.title}",
        linksChatMap(db, a),
        "",
        "# MAP OF B: ${b.title}",
        linksChatMap(db, b),
        "",
      ], "\n")
    }

## The cited card

The passages behind specific edges, both sides, in full. Clicking the line
between two paragraphs puts them here. The map already names every edge; this
hands over the prose on both ends, which is what a question about "this bit"
needs. Null when nothing is cited or none of the ids is an edge of this link.

    let linksChatUpper(s: String): String {
      sysUtf8Upcase(sysJoin(s.split("_"), " "))
    }

    export let linksChatCited(db: Db, link: Link, edgeIds: List<Int>): LlmMessage? throws Bubble {
      if (edgeIds.length == 0) { return null; }
      let lw = linksWorks(db, link);
      let a = lw.aWork;
      let blocks = new ListBuilder<String>();
      for (let e of linksEdges(db, link)) {
        var cited = false;
        var i = 0;
        while (i < edgeIds.length) {
          if (edgeIds[i] == e.edge.id) { cited = true; }
          i += 1;
        }
        if (cited) {
          blocks.add(sysJoin([
            "## ${linksChatUpper(e.edge.edgeType)}",
            "Why it was drawn: ${linksOrEmpty(e.edge.rationale)}",
            "",
            "### ${linksChatSide(e.from, a.id)} — ${e.from.title}",
            linksPassage(db, e.from),
            "",
            "### ${linksChatSide(e.to, a.id)} — ${e.to.title}",
            linksPassage(db, e.to),
            "",
          ], "\n"));
        }
      }
      if (blocks.length == 0) { return null; }
      new LlmMessage(
        "system",
        "The reader is pointing at these connections and wants to talk about them. Both passages are given in full — quote from them freely.\n\n${sysJoin(blocks.toList(), "\n\n")}",
      )
    }

## Asking

`ok` is the answer, or `error` says why there is none: `empty_reply` when the
model answered with no text, otherwise the client's error text.

    export class LinksChatResult(public ok: String?, public error: String?) {}

The messages of a turn: the system prompt, the card, the history, the
question, and the cited passages last. Ordered for the cache: the cited
passages change every time someone points at a different line, and anything
after them would have its cache thrown away with them.

    export let linksChatMessages(
      db: Db, link: Link, history: List<LlmMessage>, question: String, cited: List<Int>,
    ): List<LlmMessage> throws Bubble {
      let out = new ListBuilder<LlmMessage>();
      out.add(new LlmMessage("system", linksChatSystem()));
      out.add(new LlmMessage("system", linksChatCard(db, link)));
      for (let m of history) { out.add(m); }
      if (sysStringTrim(question) != "") { out.add(new LlmMessage("user", question)); }
      let card = linksChatCited(db, link, cited);
      if (card != null) { out.add(card); }
      out.toList()
    }

`ask/3`. `history` is the turns so far, oldest first; `question` is the new
one, appended as the last user turn (leave it empty when `history` already
ends with it). The model answers at effort `low`, temperature 0.5, 4000
tokens.

    export let linksChatAskCited(
      db: Db, llm: LlmClient, link: Link, history: List<LlmMessage>, question: String, cited: List<Int>,
    ): LinksChatResult throws Bubble {
      let messages = linksChatMessages(db, link, history, question, cited);
      let call = new LlmCall(messages, null, "low", 4000, 0.5, false, [], null, 0);
      let r = llm.chat(call);
      let reply = r.ok;
      if (reply != null) {
        let text = reply.content;
        if (text != null) {
          if (text != "") { return new LinksChatResult(text, null); }
        }
        new LinksChatResult(null, "empty_reply")
      } else {
        let e = r.err;
        new LinksChatResult(null, if (e != null) { llmErrorText(e) } else { "no_reply" })
      }
    }

    export let linksChatAsk(
      db: Db, llm: LlmClient, link: Link, history: List<LlmMessage>, question: String,
    ): LinksChatResult throws Bubble {
      linksChatAskCited(db, llm, link, history, question, [])
    }
