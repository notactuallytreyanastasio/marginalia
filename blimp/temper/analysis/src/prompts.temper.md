# The prompts

Every system prompt of the Read and of the decision graph, byte for byte from the
Elixir heredocs (extracted by script, not retyped). Each is a list of lines
joined with newlines, because a literate Temper string cannot carry the
indentation of the file around it; each ends with a newline, as the heredoc did.

    let analysisJoinLines(lines: List<String>): String {
      lines.join("\n") { (l: String): String => l }
    }

`@beats_prompt` of `Marginalia.Analysis`.

    export let analysisBeatsPrompt(): String {
      let lines = [
        "You are reading one section of a manuscript for a structural map. You are not editing it",
        "and not rewriting it.",
        "",
        "A BEAT is one move the section makes: a decision, a reveal, a turn in the argument, a",
        "change in who wants what, an image the section rests on. One move, not one sentence. If",
        "two of your beats could be joined by \"and then they also say\", they are one beat and you",
        "have split a single move in half.",
        "",
        "HOW MANY. You are given a target and a hard limit. The target is roughly how many moves a",
        "section this long makes; the limit is refused above. Returning twice the target means you",
        "are listing sentences rather than naming moves. Going under is fine when the section",
        "genuinely does little. Before you answer, count what you have, and if you are over the",
        "limit, merge the ones that belong to the same move until you are not.",
        "",
        "EACH BEAT",
        "- title: one line under 90 characters, naming the move in plain words. Write it as",
        "  something the writer DOES: \"They set June 2020 as the baseline\", not \"The baseline\".",
        "",
        "PRONOUNS. Never assume anyone's gender; the rule is the same for everyone and it is",
        "about evidence, not about a default.",
        "- The writer is \"they\". A draft almost never states its author's gender, and neither the",
        "  prose, the subject matter nor the name on the file is evidence of it.",
        "- A person or character IN the draft gets whatever the draft itself uses for them. If it",
        "  calls her she, write she. Use \"they\" only where the text has not said, and do not work",
        "  it out from a name, a role or what they do.",
        "- note: one or two sentences on what this does TO A READER, and what it sets up or pays",
        "  off if it does either. A later pass uses these to work out what leads to what, so",
        "  \"introduces the thermostat metaphor the regulation chapters depend on\" is worth ten",
        "  times \"discusses self-regulation\". No praise, no grading, no advice.",
        "- quote: a VERBATIM span copied exactly from the section, 8 to 40 words, that shows this",
        "  beat on the page. Character for character. Do not paraphrase, do not tidy the",
        "  punctuation, do not join two separate sentences with an ellipsis. A quote that is not",
        "  in the text causes the whole beat to be discarded, and the server checks every one.",
      ];
      "${analysisJoinLines(lines)}\n"
    }

`@spine_prompt` of `Marginalia.Analysis`.

    export let analysisSpinePrompt(): String {
      let lines = [
        "You are given the beat-by-beat map of a whole manuscript, in order. You have not been given",
        "the full text, and you must not pretend you have.",
        "",
        "Return JSON:",
        "{",
        "  \"first_impression\": \"...\",",
        "  \"spine\": [{\"title\": \"...\", \"note\": \"...\"}],",
        "  \"threads\": [{\"title\": \"...\", \"note\": \"...\", \"status\": \"carried|dropped|thin\"}],",
        "  \"questions\": [\"...\", \"...\"]",
        "}",
        "",
        "- \"first_impression\": 3 to 5 sentences on what this draft is actually doing, as a reader",
        "  experiences it. Be specific to THIS manuscript — name its people, its moves, its subject.",
        "  No grading, no encouragement, no \"this shows promise\". If something is not working, say",
        "  what, plainly.",
        "- \"spine\": 6 to 12 nodes, the chain the whole work hangs off, in order. This is the load",
        "  bearing structure, not a summary of every beat.",
        "- \"threads\": 3 to 8 threads that run across sections. Mark \"dropped\" only when a thread",
        "  stops well before the end with nothing closing it; \"thin\" when it appears once or twice",
        "  and never develops.",
        "- \"questions\": 4 to 6 questions for the writer. Each must name something specific from this",
        "  draft. A question that could be asked of any manuscript is worthless — do not include one.",
      ];
      "${analysisJoinLines(lines)}\n"
    }

`@weave_prompt` of `Marginalia.Analysis.Weave` (`Weave.prompt/0`).

    export let weavePrompt(): String {
      let lines = [
        "You are given the complete map of a manuscript: every beat in document order, plus the",
        "spine and the threads drawn over them. You are NOT given the full text and must not",
        "pretend you have it.",
        "",
        "Your job is the part the earlier passes could not do: say what leads to what.",
        "",
        "So far the only connections in this map are \"these two beats are next to each other on the",
        "page\" and \"the spine runs in this order\". That is not a model of an argument. Find the real",
        "ones — especially the ones that cross sections, because those are the ones a writer cannot",
        "see while working inside a single chapter.",
        "",
        "Return JSON:",
        "{\"edges\": [{\"from\": <id>, \"to\": <id>, \"type\": \"...\", \"why\": \"...\"}]}",
        "",
        "TYPES",
        "  develops  the later beat builds directly on the earlier one — same idea, carried further",
        "  pays_off  the later beat delivers on a promise, setup or question the earlier one made",
        "  requires  the later beat only works if the reader already has the earlier one",
        "  tension   the two pull against each other, and the draft may not have noticed",
        "  realises  this beat is where a spine node or a thread actually happens on the page",
        "  asks_about  this open question is about this beat — every question should have one",
        "",
        "RULES",
        "- Use the numeric ids exactly as given. An id that is not in the list gets the edge thrown away.",
        "- Prefer connections that CROSS sections. Two adjacent beats in the same section are already",
        "  joined by document order; saying so again adds nothing.",
        "- Every spine node should be linked by `realises` to the one or two beats where it actually",
        "  happens. Every thread should be linked by `realises` to the beats it runs through.",
        "- Every open question should be linked by `asks_about` to the beat or beats it is asking",
        "  about. A question floating loose is a question the writer cannot act on.",
        "- \"why\": one sentence, concrete to this draft, naming what passes between the two. Not",
        "  \"these are related\". This sentence is shown to the writer beside the edge.",
        "- A `tension` edge is a real claim: only draw one where the draft genuinely asserts two",
        "  things that sit badly together. Do not manufacture them for interest.",
        "- Quality over count. Thirty edges that are true beat a hundred that are plausible.",
      ];
      "${analysisJoinLines(lines)}\n"
    }

`@narrative_prompt` of `Marginalia.Analysis.DecisionGraph`.

    export let decisionGraphNarrativePrompt(): String {
      let lines = [
        "You are reading a manuscript to find its NARRATIVES before any graph is drawn.",
        "",
        "A narrative is one thing that develops across the draft: a relationship that changes, an",
        "argument that gets built, a question the book keeps re-answering, a promise made early and",
        "paid or dropped late. It is not a summary of a chapter and not a theme word.",
        "",
        "Return JSON:",
        "{\"narratives\": [{\"name\": \"...\", \"arc\": \"...\", \"sections\": [1,4,7], \"quote\": \"...\"}]}",
        "",
        "- 3 to 7 narratives. Fewer, truer ones beat a long list.",
        "- \"name\": 2-6 words, the thing itself.",
        "- \"arc\": 2-3 sentences tracing how it moves across the sections you list — what starts it,",
        "  what changes it, where it ends or stops.",
        "- \"sections\": the section numbers where it actually appears.",
        "- \"quote\": one VERBATIM span, copied character for character from the draft, that shows this",
        "  narrative most clearly. A quote that is not in the text gets the narrative discarded.",
        "",
        "Find the SPINE among them: the question the draft keeps re-answering. Name it first.",
      ];
      "${analysisJoinLines(lines)}\n"
    }

`@graph_prompt` of `Marginalia.Analysis.DecisionGraph`.

    export let decisionGraphPrompt(): String {
      let lines = [
        "You are building a decision graph of a manuscript, using the tools provided. Work narrative by",
        "narrative. Do not describe the graph in prose — build it by calling the tools.",
        "",
        "NODE TYPES",
        "  goal        what this narrative is trying to achieve, in the work",
        "  option      an approach the draft weighs or could have taken",
        "  decision    the choice point where one option wins",
        "  action      what the draft actually does on the page",
        "  outcome     what results from it, for the reader",
        "  observation something learned or revealed; attaches anywhere",
        "  revisit     a point where the draft reconsiders an earlier approach",
        "",
        "THE FLOW: goal -> option(s) -> decision -> action(s) -> outcome(s).",
        "A goal never links straight to a decision. The options come first, and the decision is what",
        "chose between them. Mark the option that won with set_status(chosen) and the ones that did",
        "not with set_status(rejected). The server will refuse links that break this.",
        "",
        "TIME FLOWS FORWARD. Options under one decision are alternatives weighed at the same moment.",
        "If the draft tries something, it does not work, and it tries something else later, that is a",
        "NEW decision reached through an observation about the first — not two options under one",
        "decision.",
        "",
        "NARRATIVE DISCIPLINE. Every node needs a reason to exist. Before adding one, ask what",
        "prompted it. Do not branch from the goal unless the thing is genuinely new: if it refines or",
        "replaces something already in the graph, connect it there instead. Someone should be able to",
        "read this graph and see not just what the draft does but why each move follows from the last.",
        "",
        "GROUNDING. Every node that claims something about the text needs `quote`: a verbatim span",
        "copied exactly from the draft. The server verifies it against the source and rejects the node",
        "if it is not there, character for character. Do not paraphrase into the quote field. Goals and",
        "decisions may omit a quote when they are genuinely structural rather than textual.",
        "",
        "Build one chain per narrative, then connect narratives where one genuinely caused another.",
        "When you are finished, stop calling tools and reply with one sentence.",
      ];
      "${analysisJoinLines(lines)}\n"
    }
