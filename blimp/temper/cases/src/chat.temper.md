# Talking about a case

`Marginalia.Cases.Chat`: the public case chat. `Links.Chat` holds two
documents and the edges between them, the right shape for the pairwise
reading and the wrong one here: on the whole-case view the reader is looking
at one document with every other document in the margin at once, and the
question is almost always about three of them (what the Court said, what the
dissent said back, what the advocate had already conceded at the lectern).

So this holds the document being read, every other document related to it,
and every edge from the lead out to each of them, including the ones that
leave the case entirely, because "the same Court said the opposite three weeks
ago" is the best thing on the page when it is there.

## Documents are named

The pairwise chat labels its two documents A and B. That is right for a prompt
about a pair and reads badly coming back out ("A:[4030] ↔ B:[7497]"), and with
four or five documents in play A and B are not enough. Everything here is
named the way the page names it, "Dissent (Sotomayor)" or "Argument: Amit
Agarwal", so the answer comes back in the reader's vocabulary and the node ids
never leave the building.

No tools, no storage: the history lives with the page that asks.

    let { Db } = import("db/src");
    let { Work, GraphNode, worksListSections, worksNodes } = import("works/src");
    let { LinkEdge, LinkEdgeEnds, linkEdgeColumns } = import("links/src");
    let {
      LlmClient, LlmCall, LlmMessage, LlmReply, LlmError, Result, llmErrorText,
    } = import("llm/src");
    let { isUnicodeSpace } = import("core/src");
    let { sysUtf8Upcase, sysGraphemeTake, sysJoin, sysStringReplace } = import("sys/src");

## The text of the context

`name(work)` is `casesName`. `fromCase` says where a connection comes from when
it is not this case.

    let casesFromCase(s: CaseSource): String {
      let e = s.elsewhere;
      if (e == null) { "" } else { " (from ${e}, a different case)" }
    }

`whose(node)`: the document a node belongs to, by name rather than by letter.

    let casesWhose(node: GraphNode, lead: Work, s: CaseSource): String {
      let who = if (node.workId == lead.id) {
        casesName(lead.title)
      } else if (node.workId == s.work.id) {
        casesName(s.work.title)
      } else {
        "another document"
      };
      "${who} — ${node.title}"
    }

A quote on one line: runs of whitespace (Unicode `\s`) become one space, then
the first 160 characters.

    let casesOneLine(q: String): String {
      let parts = new ListBuilder<String>();
      var inSpace = false;
      var i = String.begin;
      while (q.hasIndex(i)) {
        let c = q[i];
        if (isUnicodeSpace(c)) {
          if (!inSpace) { parts.add(" "); }
          inSpace = true;
        } else {
          parts.add(String.fromCodePoint(c) orelse "");
          inSpace = false;
        }
        i = q.next(i);
      }
      sysGraphemeTake(sysJoin(parts.toList(), ""), 160)
    }

    let casesUpperType(edgeType: String): String {
      sysUtf8Upcase(sysStringReplace(edgeType, "_", " "))
    }

`map(work)`: its nodes grouped by type, types in key order, each group
`"\n## <type>\n"` and its lines. A line is `- <title>`, then ` (§<ordinal>)`
when the node has a section, then the quote on its own line.

    let casesMap(db: Db, work: Work): String throws Bubble {
      let ordinals = new MapBuilder<Int, Int>();
      for (let s of worksListSections(db, work.id)) { ordinals.set(s.id, s.ordinal); }
      let groups = new MapBuilder<String, ListBuilder<String>>();
      let types = new ListBuilder<String>();
      for (let n of worksNodes(db, work.id)) {
        if (!groups.has(n.nodeType)) {
          groups.set(n.nodeType, new ListBuilder<String>());
          types.add(n.nodeType);
        }
        let sectionId = n.sectionId;
        let where = if (sectionId != null) {
          let o = ordinals.getOr(sectionId, -1);
          if (o >= 0) { " (§${o.toString()})" } else { " (§)" }
        } else {
          ""
        };
        let q = n.quote;
        let quoted = if (q != null) {
          if (q.isEmpty) { "" } else { "\n    \"${casesOneLine(q)}\"" }
        } else {
          ""
        };
        groups.get(n.nodeType).add("- ${n.title}${where}${quoted}");
      }
      let ordered = types.toList().sorted { (a: String, b: String): Int => casesCompareText(a, b) };
      let blocks = new ListBuilder<String>();
      for (let t of ordered) {
        blocks.add("\n## ${t}\n${sysJoin(groups.get(t).toList(), "\n")}");
      }
      sysJoin(blocks.toList(), "\n")
    }

## The edges, with their reasons in words

An edge of a source, with its rationale resolved, and the source it came from.

    export class CaseSourceEdge(public source: CaseSource, public ends: LinkEdgeEnds) {}

`edges(reading)`: every edge the reader could point at, across all the sources,
source by source, each source's edges in the order they were drawn.

    export let casesChatEdges(db: Db, reading: CaseReading): List<CaseSourceEdge> throws Bubble {
      let lead = reading.lead;
      let ids = reading.sources.map { (s: CaseSource): Int => s.link.id };
      let grouped = new MapBuilder<Int, ListBuilder<LinkEdgeEnds>>();
      for (let e of casesLoadEdges(db, ids)) {
        if (!grouped.has(e.edge.linkId)) { grouped.set(e.edge.linkId, new ListBuilder<LinkEdgeEnds>()); }
        grouped.get(e.edge.linkId).add(e);
      }
      let out = new ListBuilder<CaseSourceEdge>();
      for (let s of reading.sources) {
        if (grouped.has(s.link.id)) {
          let a = if (s.link.aWorkId == lead.id) { lead } else { s.work };
          let b = if (s.link.aWorkId == lead.id) { s.work } else { lead };
          for (let e of grouped.get(s.link.id).toList()) {
            out.add(new CaseSourceEdge(s, casesPlainEdge(e, a, b)));
          }
        }
      }
      out.toList()
    }

    let casesAgainstLine(s: CaseSource, lead: Work): String {
      let a = if (s.link.aWorkId == lead.id) { lead } else { s.work };
      let b = if (s.link.aWorkId == lead.id) { s.work } else { lead };
      let summary = casesLinkSummary(s.link, a, b);
      let tail = if (s.link.summary != null && summary != null) { "\n    ${summary}" } else { "" };
      "- ${casesName(s.work.title)} — ${s.work.wordCount.toString()} words${casesFromCase(s)}${tail}"
    }

    let casesEdgeLine(se: CaseSourceEdge, lead: Work): String {
      let e = se.ends;
      let why = e.edge.rationale;
      let reason = if (why != null) { why } else { "" };
      "- ${casesWhose(e.from, lead, se.source)} --${e.edge.edgeType}--> ${casesWhose(e.to, lead, se.source)}\n    ${reason}"
    }

## `card(reading)`

The case, its documents and every connection from the one being read. The
layout is exact: the model was tuned against it.

    export let casesChatCard(db: Db, reading: CaseReading): String throws Bubble {
      let lead = reading.lead;
      let edges = casesChatEdges(db, reading);
      let against = reading.sources.map { (s: CaseSource): String => casesAgainstLine(s, lead) };
      let lines = edges.map { (se: CaseSourceEdge): String => casesEdgeLine(se, lead) };
      let maps = new ListBuilder<String>();
      for (let s of reading.sources) {
        maps.add("\n# MAP OF ${sysUtf8Upcase(casesName(s.work.title))}${casesFromCase(s)}\n${casesMap(db, s.work)}");
      }
      let top = new ListBuilder<String>();
      top.add("# THE DOCUMENT BEING READ");
      top.add("");
      top.add("${casesName(lead.title)} — ${lead.wordCount.toString()} words");
      top.add("");
      top.add("# READ AGAINST (${reading.sources.length.toString()})");
      top.add("");
      top.add(sysJoin(against, "\n"));
      top.add("");
      top.add("# THE CONNECTIONS (${edges.length.toString()})");
      top.add("");
      top.add(sysJoin(lines, "\n"));
      top.add("");
      top.add("# MAP OF ${sysUtf8Upcase(casesName(lead.title))}");
      top.add(casesMap(db, lead));
      top.add(sysJoin(maps.toList(), "\n"));
      top.add("");
      sysJoin(top.toList(), "\n")
    }

## `cited_card(reading, edge_ids)`

The passages behind the connections the reader is pointing at, in full. Null
(no message) for no ids, or when none of the ids is an edge of this reading.

    export let casesChatCited(db: Db, reading: CaseReading, edgeIds: List<Int>): LlmMessage? throws Bubble {
      if (edgeIds.length == 0) { return null; }
      let wanted = new MapBuilder<Int, Boolean>();
      for (let id of edgeIds) { wanted.set(id, true); }
      let lead = reading.lead;
      let blocks = new ListBuilder<String>();
      for (let se of casesChatEdges(db, reading)) {
        let e = se.ends;
        if (wanted.has(e.edge.id)) {
          let why = e.edge.rationale;
          let reason = if (why != null) { why } else { "" };
          blocks.add(sysJoin([
            "## ${casesUpperType(e.edge.edgeType)}${casesFromCase(se.source)}",
            "Why it was drawn: ${reason}",
            "",
            "### ${casesWhose(e.from, lead, se.source)}",
            casesPassage(db, e.from),
            "",
            "### ${casesWhose(e.to, lead, se.source)}",
            casesPassage(db, e.to),
            "",
          ], "\n"));
        }
      }
      if (blocks.length == 0) { return null; }
      new LlmMessage("system", "${casesChatCitedPreamble()}${sysJoin(blocks.toList(), "\n\n")}")
    }

## `ask`

Ordered for the cache: the prompt never changes, the card changes only when
something is re-read or re-linked, history grows at the end, and the cited
passages go last because they change every time the reader points somewhere
new.

    export let casesChatMessages(
      db: Db, reading: CaseReading, history: List<LlmMessage>, cited: List<Int>,
    ): List<LlmMessage> throws Bubble {
      let out = new ListBuilder<LlmMessage>();
      out.add(new LlmMessage("system", casesChatSystem()));
      out.add(new LlmMessage("system", casesChatCard(db, reading)));
      for (let m of history) { out.add(m); }
      let extra = casesChatCited(db, reading, cited);
      if (extra != null) { out.add(extra); }
      out.toList()
    }

`ask(reading, history, cited: ids)`: `history` is the turns so far, oldest
first, the reader's latest question last. One model call with the
default model, low effort, temperature 0.5 and room for 4,000 tokens of
answer. The answer is the text iff it is a non-empty string; anything else is
`empty_reply`; a failed call passes its error through.

    export let casesChatAsk(
      db: Db, llm: LlmClient, reading: CaseReading, history: List<LlmMessage>, cited: List<Int>,
    ): CaseChatResult throws Bubble {
      let call = new LlmCall(
        casesChatMessages(db, reading, history, cited), null, "low", 4000, 0.5, false, [], null, 0,
      );
      let r = llm.chat(call);
      let reply = r.ok;
      if (reply == null) {
        let err = r.err;
        if (err != null) {
          new CaseChatResult(null, llmErrorText(err))
        } else {
          new CaseChatResult(null, "empty_reply")
        }
      } else {
        let text = reply.content;
        if (text != null) {
          if (text.isEmpty) { new CaseChatResult(null, "empty_reply") } else { new CaseChatResult(text, null) }
        } else {
          new CaseChatResult(null, "empty_reply")
        }
      }
    }

The same for a page that has the case and the question rather than a reading:
read `leadId` against the rest, add the question to the history, ask. An error
of `no_lead` when `leadId` is not in the case.

    export let casesChatAskLead(
      db: Db, llm: LlmClient, c: CaseStudy, leadId: Int, history: List<LlmMessage>,
      question: String, cited: List<Int>,
    ): CaseChatResult throws Bubble {
      let reading = casesReading(db, c, leadId);
      if (reading != null) {
        let turns = new ListBuilder<LlmMessage>();
        for (let m of history) { turns.add(m); }
        turns.add(new LlmMessage("user", question));
        casesChatAsk(db, llm, reading, turns.toList(), cited)
      } else {
        new CaseChatResult(null, "no_lead")
      }
    }

`for_case(c, lead_id)`: so the prompts page can list this alongside the others.

    export let casesChatForCase(db: Db, c: CaseStudy, leadId: Int): CaseReading? throws Bubble {
      casesReading(db, c, leadId)
    }
