# The prompts

Byte for byte from `Marginalia.Summary`, `Marginalia.Rewrite` and
`Marginalia.Document`: the system prompts and the three tool schemas are the
module attributes themselves, evaluated by Elixir and written out (the `\`
continuations of the heredocs joined, the schemas as JSON text with keys in
the order Jason writes them). The user messages are the Elixir templates with
their interpolations as parameters.

## Section summary (`Summary.ask`)

The system prompt, byte for byte from `@prompt` (the `\` continuations joined).

    export let summaryPrompt(): String {
      "You summarise one section of a draft for its own writer, who knows the material and wants to find their place in it.\n\nYou are given the whole draft's section list so you can see where this one sits, and the summary of the section before it when one exists. Use them. A section that continues an argument should say so rather than starting it again, and what a reader needs from earlier belongs in follows_from, not repeated in the summary.\n\nSay what is in the section, in the order it appears. This is not a review: do not say whether it works, what is missing, or what to do about it.\n\nReport by calling report_section.\n"
    }

The tool `report_section`; `parameters` is JSON text.

    export let summaryToolName(): String {
      "report_section"
    }

    export let summaryToolDescription(): String {
      "Report what this section of the draft contains and where it sits among the others."
    }

    export let summaryToolParameters(): String {
      "{\"properties\":{\"covers\":{\"description\":\"The specific things this section deals with, two or three words each, as they are named IN THE SECTION. A program checks every one of these against the text and drops what it cannot find, so a term you inferred rather than read is a discarded entry.\",\"items\":{\"type\":\"string\"},\"maxItems\":6,\"type\":\"array\"},\"follows_from\":{\"description\":\"Ordinals of earlier sections this one leans on — whose material a reader would need before this makes sense. Only from the list you were given, only earlier ones, and empty if it stands on its own.\",\"items\":{\"type\":\"integer\"},\"type\":\"array\"},\"sets_up\":{\"description\":\"One sentence: what this section leaves in place for the ones after it. Empty string if it closes something rather than opening anything.\",\"type\":\"string\"},\"summary\":{\"description\":\"Three or four sentences saying what is in this section, in the order it appears. Concrete nouns taken from the text itself — \\\"the out-grammar, kcodegen, and the first emitted module\\\", never \\\"technical foundations\\\". Describe the prose; do not judge it, do not say what is missing, and do not write \\\"the author argues\\\". Do not re-explain anything the listed earlier sections have already established — name it and move on.\",\"type\":\"string\"}},\"required\":[\"summary\",\"covers\",\"follows_from\",\"sets_up\"],\"type\":\"object\"}"
    }

## Rewrite candidates (`Rewrite.ask`)

The system prompt, byte for byte.

    export let rewritePrompt(): String {
      "The writer has selected one span of their own draft and asked for rewrites of it. This is\nthe one thing you do write. Do it well and do it narrowly.\n\nReturn 3 candidates through the tool. Each is a DROP-IN REPLACEMENT for the selected span:\npaste it in place of the original and the paragraph still reads. Not a paragraph, not a\nplan, not advice — the words.\n\nWHAT MAKES THESE USEFUL\n- They must differ from each other in KIND, not in wording. Three versions of the same move\n  is one candidate and two impostors. Cut something / reorder so the object lands first /\n  make the implicit claim explicit / drop the hedge / hand the line to a concrete image.\n- Keep the writer's voice. Match their register, their contractions, their sentence music.\n  If they write short declaratives, do not hand back a subordinate clause with a semicolon.\n- Keep what the span asserts. You may sharpen a claim, and you may not invent one or\n  quietly drop one.\n- Stay close in length unless the move IS the length. A candidate three times longer is a\n  different paragraph, not a rewrite.\n\nFOR EACH ONE\n- \"text\": the replacement, and nothing else. No quotes around it, no \"Option 2:\", no\n  trailing commentary.\n- \"move\": what this version does differently, in under ten words. \"Cuts the gloss.\"\n  \"Puts the number first.\" \"Drops the hedge.\" This is what the writer reads first.\n- \"cost\": what it gives up, in under fifteen words. Every rewrite gives something up; a\n  candidate with no cost has not been thought about. Say it plainly.\n\nAlso return \"reading\": one sentence on what the original span is currently doing, so the\nwriter can see what you thought you were changing before they read what you changed.\n"
    }

The tool `propose_rewrites`.

    export let rewriteToolName(): String {
      "propose_rewrites"
    }

    export let rewriteToolDescription(): String {
      "Offer the writer a few labelled rewrites of the span they selected."
    }

    export let rewriteToolParameters(): String {
      "{\"properties\":{\"reading\":{\"description\":\"One sentence on what the original span is doing now.\",\"type\":\"string\"},\"rewrites\":{\"description\":\"Three candidates, each a different KIND of move.\",\"items\":{\"properties\":{\"cost\":{\"description\":\"What it gives up. Under fifteen words. Every rewrite gives something up.\",\"type\":\"string\"},\"move\":{\"description\":\"What this version does differently. Under ten words.\",\"type\":\"string\"},\"text\":{\"description\":\"The replacement span itself. No label, no quotes, no commentary.\",\"type\":\"string\"}},\"required\":[\"text\",\"move\",\"cost\"],\"type\":\"object\"},\"type\":\"array\"}},\"required\":[\"reading\",\"rewrites\"],\"type\":\"object\"}"
    }

## Document composition (`Document.compose`)

The system prompt, byte for byte.

    export let documentComposePrompt(): String {
      "You are given the section-by-section summaries of one document and must say what the document as a whole does.\n\nWork from the summaries, in order. The value here is the shape that no single section contains: where it turns, what it assumes before it turns, what a reader has at the end that they did not have at the start.\n\nDo not re-list the sections. A movement spanning sections three to seven is one line, not five. This is not a review: do not say whether it works or what is missing.\n\nReport by calling report_composition.\n"
    }

The tool `report_composition`.

    export let documentComposeToolName(): String {
      "report_composition"
    }

    export let documentComposeToolDescription(): String {
      "Report what the whole document does, built from the summaries of its sections."
    }

    export let documentComposeToolParameters(): String {
      "{\"properties\":{\"movements\":{\"description\":\"The document divided into the few stretches it actually falls into. Not one per section: a movement usually spans several, and two movements is a legitimate answer for a short document.\",\"items\":{\"properties\":{\"does\":{\"description\":\"One sentence: what the reader has after this stretch.\",\"type\":\"string\"},\"heading\":{\"description\":\"A claim about what this stretch does, not a label for it. \\\"Nothing runs until the emitter is generated\\\", not \\\"Setup\\\".\",\"type\":\"string\"},\"sections\":{\"description\":\"The section ordinals in this movement, from the list you were given. A program checks these and drops any that do not exist.\",\"items\":{\"type\":\"integer\"},\"type\":\"array\"}},\"required\":[\"heading\",\"sections\",\"does\"],\"type\":\"object\"},\"maxItems\":8,\"type\":\"array\"},\"summary\":{\"description\":\"Four to six sentences: what this document does, in the order it does it. Written for somebody deciding whether to read it and where to start. Concrete nouns from the section summaries, not categories. Do not evaluate it, do not say what is missing.\",\"type\":\"string\"},\"throughline\":{\"description\":\"One sentence naming the single thread that runs through every part. If the parts do not share one, say what they share instead — do not invent a unity the document does not have.\",\"type\":\"string\"}},\"required\":[\"summary\",\"throughline\",\"movements\"],\"type\":\"object\"}"
    }

## Document guidelines (`Document.guidelines`)

The system prompt, byte for byte.

    export let documentGuidePrompt(): String {
      "You are given the shape of a document — its title, what it is meant to do, its section titles, and the thread running through it — and must name the rules it is working under.\n\nA guideline here is something the document does consistently and would be noticed for breaking. It is descriptive, not prescriptive: you are reading the practice off the document, not recommending one. A rule you cannot point at two sections for is not a rule this document has.\n\nReport by calling report_guidelines.\n"
    }

The tool `report_guidelines`.

    export let documentGuideToolName(): String {
      "report_guidelines"
    }

    export let documentGuideToolDescription(): String {
      "Report the rules this document is working under, read down from the whole."
    }

    export let documentGuideToolParameters(): String {
      "{\"properties\":{\"guidelines\":{\"description\":\"The governing rules this document has committed to — the things it does consistently that a reader would notice if it stopped. Not advice, not what it should do: what it IS doing, as a rule.\",\"items\":{\"properties\":{\"because\":{\"description\":\"One sentence: what this rule buys the reader, or what it prevents.\",\"type\":\"string\"},\"guideline\":{\"description\":\"The rule, in one imperative sentence, as this document practises it. \\\"Name the failing case before the fix for it\\\", not \\\"clarity\\\".\",\"type\":\"string\"},\"sections\":{\"description\":\"Two or three section ordinals where this is visibly in force. Checked; ordinals that do not exist are dropped.\",\"items\":{\"type\":\"integer\"},\"type\":\"array\"}},\"required\":[\"guideline\",\"because\",\"sections\"],\"type\":\"object\"},\"maxItems\":7,\"type\":\"array\"},\"tensions\":{\"description\":\"Places two of the rules above pull against each other. Empty if they do not — a document with no tensions is a real answer and inventing one is worse than reporting none.\",\"items\":{\"properties\":{\"sections\":{\"description\":\"Where it shows. Checked.\",\"items\":{\"type\":\"integer\"},\"type\":\"array\"},\"tension\":{\"description\":\"One sentence naming the pull, and between which rules.\",\"type\":\"string\"}},\"required\":[\"tension\",\"sections\"],\"type\":\"object\"},\"maxItems\":4,\"type\":\"array\"}},\"required\":[\"guidelines\",\"tensions\"],\"type\":\"object\"}"
    }

## The user messages

`intent` is `What it is meant to do to a reader: <intent>\n` when the draft
has one (the Elixir tests `work.intent && work.intent != ""`) and nothing
otherwise; the line it sits on is kept either way, so a draft without one has
an empty line there.

    export let promptsIntent(intent: String?): String {
      if (intent != null) {
        if (intent.isEmpty) { "" } else { "What it is meant to do to a reader: ${intent}\n" }
      } else {
        ""
      }
    }

The section summary: the draft, the sections in order (`spine`), the summary of
the section before (`previous`, empty or starting and ending with a newline),
then the section itself, capped at 12,000 characters by the caller.

    export let promptsSummaryUser(
      title: String, intent: String?, spine: String, previous: String,
      ordinal: Int, sectionTitle: String, body: String,
    ): String {
      "Draft: ${title}\n${promptsIntent(intent)}\nThe sections of this draft, in order:\n${spine}\n${previous}\nTHE SECTION TO SUMMARISE — ${ordinal.toString()}. ${sectionTitle}:\n\n${body}\n"
    }

The rewrite request: `steer` is the output of `rewriteSteerBlock`, `scale` the
note about a long span, `context` the paragraph the span sits in or nothing.

    export let promptsRewriteUser(
      title: String, intent: String?, steer: String, scale: String, span: String, context: String,
    ): String {
      "Manuscript: ${title}\n${promptsIntent(intent)}${steer}\nTHE SELECTED SPAN, to be replaced:${scale}\n\n${span}\n\n${context}\n"
    }

What the writer asked for, in their words.

    export let promptsAskedFor(steer: String): String {
      "\nWHAT THE WRITER ASKED FOR, in their words:\n${steer}\n\nEvery candidate must do this. They still differ from each other, but now\nin HOW they do it, not in whether they do it.\n"
    }

The note about a span of more than 60 words, and more than 400.

    export let promptsScaleSeveral(n: Int): String {
      "\nThis span is ${n.toString()} words — several sentences. Your candidates should differ STRUCTURALLY: cut one of the sentences, reorder so the strongest lands first, merge two into one. Rewording every sentence a little is one candidate, not three."
    }

    export let promptsScaleSection(n: Int): String {
      "\nThis span is ${n.toString()} words — a section, not a sentence. Do not reword it line by line: at this length three lightly-reworded versions are indistinguishable and useless. Each candidate should make ONE structural decision and follow it all the way through — cut it to its argument, reorder so the finding leads, or split the pile of claims into a sequence. Say which in `move`."
    }

    export let promptsContext(paragraph: String): String {
      "The paragraph it sits in, for context — do not rewrite this, only the span above:\n${paragraph}"
    }

The composition request: `count` summarised sections, `spine` each as
`N. Title\nsummary` with `\n(sets up: ...)`, joined by a blank line.

    export let promptsComposeUser(title: String, intent: String?, count: Int, spine: String): String {
      "Document: ${title}\n${promptsIntent(intent)}\n${count.toString()} sections, summarised, in order:\n\n${spine}\n"
    }

The guidelines request: every section's title, then what each summarised
section does. The composition's throughline is deliberately not in it.

    export let promptsGuideUser(title: String, intent: String?, titles: String, what: String): String {
      "Document: ${title}\n${promptsIntent(intent)}\nIts sections:\n${titles}\n\nWhat each section does:\n${what}\n"
    }
