# The editor assistant

`Marginalia.Chat.Editor`: the editorial chat, the product's whole point. A
function-calling loop over the stored analysis, pointed at one job: it reads
with the writer and does not write for them. That constraint lives in the
prompt (`prompts.temper.md`, verbatim) and is the single thing the product is
sold on.

Every tool closes over one `Work`, so no tool takes a work id and a
hallucinated id cannot reach another writer's manuscript.

    let { Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { FieldError } = import("core/src");
    let { sysJoin, sysStringReplace, sysStringTrim, sysUtf8Downcase } = import("sys/src");
    let {
      LlmClient, LlmCall, LlmMessage, LlmTool, LlmToolCall, LlmReply, LlmError,
      llmErrorText,
    } = import("llm/src");
    let {
      JsonSyntaxTree, JsonObject, JsonString, JsonNumeric, JsonTextProducer,
      NullInterchangeContext, parseJson,
    } = import("std/json");
    let {
      Work, Section, GraphNode, FullConnection, Correction, CorrectionParams,
      worksListSections, worksCounts, worksSearch, worksFindInSource,
      worksGetSection, worksListNodes, worksAllConnections,
      worksRecordCorrection, worksListCorrections, worksGetById, SourceHit,
    } = import("works/src");

## Modes

Three stances over the same tools and the same refusal to write. They are not
personalities: the register never changes. The texts are in
`prompts.temper.md`.

    export let editorModes(): List<ChatMode> { chatModes() }

    export let editorModeNames(): List<String> {
      editorModes().map { (m: ChatMode): String => m.id }
    }

    export let editorDefaultMode(): String { "read" }

An unknown or missing id is the first mode, `read`.

    export let editorMode(id: String?): ChatMode {
      let all = editorModes();
      if (id != null) {
        var i = 0;
        while (i < all.length) {
          if (all[i].id == id) { return all[i]; }
          i += 1;
        }
      }
      all[0]
    }

What the assistant says before the writer has said anything.

    export let editorOpener(modeId: String?): String { editorMode(modeId).opener }

## The prompt and the tool surface

    export let editorSystemPrompt(): String { chatSystemPromptText() }

`access` is `owner` (all eleven tools) or `public` (a visitor reading a shared
draft). Two tools are unsafe in public: `record_correction` writes to the
draft's record and `recall_sessions` reads the owner's private conversations.
They are not offered to the model and, if it calls them anyway, refused.

    export let editorUnsafeTools(): List<String> { ["record_correction", "recall_sessions"] }

    let editorOffered(name: String, access: String): Boolean {
      if (access != "public") { return true; }
      var i = 0;
      let unsafe = editorUnsafeTools();
      while (i < unsafe.length) {
        if (unsafe[i] == name) { return false; }
        i += 1;
      }
      true
    }

    export let editorTools(access: String): List<LlmTool> {
      let all = chatToolDefinitions();
      let out = new ListBuilder<LlmTool>();
      var i = 0;
      while (i < all.length) {
        if (editorOffered(all[i].name, access)) { out.add(all[i]); }
        i += 1;
      }
      out.toList()
    }

    export let editorToolNames(access: String): List<String> {
      editorTools(access).map { (t: LlmTool): String => t.name }
    }

## The cards

What the page hands the model besides the history. `ChatFocus` is what
`Reading.focus` returns: the note the writer clicked and the sections it
touches. `ChatCited` is one passage the writer carried into the question.

    export class ChatFocusSection(public ordinal: Int, public title: String, public body: String) {}

    export class ChatFocus(
      public kind: String,
      public title: String,
      public body: String?,
      public quote: String?,
      public sections: List<ChatFocusSection>,
    ) {}

    export class ChatCited(public text: String, public section: String, public ordinal: Int) {}

A short card about this manuscript, so the model never has to ask what it is
looking at and never guesses the title or shape.

    export let editorManuscriptCard(db: Db, work: Work): String throws Bubble {
      let sections = worksListSections(db, work.id);
      let counts = worksCounts(db, work.id);
      let intent = work.intent;
      let intentLine = if (intent != null && intent != "") {
        "What the writer says it should do to a reader: ${intent}"
      } else {
        "The writer did not state an intent."
      };
      let impression = work.firstImpression;
      let impressionPart = if (impression != null) {
        "\nThe first impression from the read:\n${impression}"
      } else {
        ""
      };
      "THIS MANUSCRIPT\n\nTitle: ${work.title}\nLength: ${work.wordCount.toString()} words in ${sections.length.toString()} sections\nRead so far: ${counts.beats.toString()} beats, ${counts.spine.toString()} spine nodes, ${counts.threads.toString()} threads, ${counts.questions.toString()} open questions\n${intentLine}\n${impressionPart}\n"
    }

When the writer clicks a note, the note and the sections it touches are put in
front of the model in full.

    export let editorFocusCard(focus: ChatFocus): String {
      let parts = new ListBuilder<String>();
      for (let s of focus.sections) {
        parts.add("### Section ${s.ordinal.toString()}: ${s.title}\n${s.body}");
      }
      let sections = sysJoin(parts.toList(), "\n\n");
      let kind = sysStringReplace(focus.kind, "_", " ");
      let body = focus.body;
      let bodyPart = if (body != null) { "\n${body}\n" } else { "" };
      let quote = focus.quote;
      let quotePart = if (quote != null) { "Anchored to their line: \"${quote}\"\n" } else { "" };
      let plural = if (focus.sections.length > 1) { "s" } else { "" };
      "THE WRITER CLICKED A NOTE. This is what they are pointing at, and they expect you to\nalready have it. Do not go and search for it, and do not ask them which part they mean.\n\nNote (${kind}): ${focus.title}\n${bodyPart}\n${quotePart}\nThe section${plural} it touches, in full:\n\n${sections}\n\nOpen on this. One or two sentences on what you see, then the question that moves it.\n"
    }

Passages the writer picked out of the page and carried into the question.

    export let editorCitedCard(cited: List<ChatCited>): String {
      let parts = new ListBuilder<String>();
      for (let c of cited) {
        parts.add("From section ${c.ordinal.toString()} (${c.section}):\n\"${c.text}\"");
      }
      let passages = sysJoin(parts.toList(), "\n\n");
      "THE WRITER SELECTED THESE PASSAGES and attached them to the question below. They are\nverbatim from the draft — you may quote them back exactly without going to look them up.\nThis is what they are asking about. Answer about these, not about the draft in general.\n\n${passages}\n"
    }

Said once, to a visitor's conversation only, after the stance.

    export let editorPublicNote(): String {
      "THIS READER IS A VISITOR.\n\nThe draft is shared publicly and the person asking is not the writer. record_correction and recall_sessions are not available here: there is no earlier session to search and nothing of theirs to record, so do not promise either. Everything else above holds, including that you never write the book.\n"
    }

## The messages of one turn

Ordered by how often each part changes, because the provider caches on an
exact prefix: the system prompt never changes, the manuscript card changes per
draft, the stance per mode, the history only ever grows at the end. The focus
and the selected passages change every message, so they go last.

    export let editorMessages(
      db: Db, work: Work, history: List<ChatTurn>, stanceMode: String?,
      focus: ChatFocus?, cited: List<ChatCited>, access: String,
    ): List<LlmMessage> throws Bubble {
      let out = new ListBuilder<LlmMessage>();
      out.add(new LlmMessage("system", editorSystemPrompt()));
      out.add(new LlmMessage("system", editorManuscriptCard(db, work)));
      out.add(new LlmMessage("system", editorMode(stanceMode).stance));
      if (access == "public") { out.add(new LlmMessage("system", editorPublicNote())); }
      for (let t of history) { out.add(new LlmMessage(t.role, t.content)); }
      if (focus != null) { out.add(new LlmMessage("system", editorFocusCard(focus))); }
      if (cited.length > 0) { out.add(new LlmMessage("system", editorCitedCard(cited))); }
      out.toList()
    }

## JSON in, JSON out

Tool results are JSON text, built with the encoder so the writer's words are
escaped by it and by nothing of ours. Keys are emitted in alphabetical order,
as Jason does for an Elixir map.

    let ejNew(): JsonTextProducer { new JsonTextProducer(NullInterchangeContext.instance) }

    let ejDone(p: JsonTextProducer): String { p.toJsonString() orelse panic() }

    let ejOne(key: String, text: String): String {
      let p = ejNew();
      p.startObject();
      p.objectKey(key);
      p.stringValue(text);
      p.endObject();
      ejDone(p)
    }

    let ejOptional(p: JsonTextProducer, key: String, v: String?): Void {
      p.objectKey(key);
      if (v != null) { p.stringValue(v); } else { p.nullValue(); }
    }

    let ejOptionalInt(p: JsonTextProducer, key: String, v: Int?): Void {
      p.objectKey(key);
      if (v != null) { p.int32Value(v); } else { p.nullValue(); }
    }

A node as the model sees it: `{id, note, quote, title, type}`.

    let ejNode(p: JsonTextProducer, n: GraphNode): Void {
      p.startObject();
      p.objectKey("id");
      p.int32Value(n.id);
      ejOptional(p, "note", n.body);
      ejOptional(p, "quote", n.quote);
      p.objectKey("title");
      p.stringValue(n.title);
      p.objectKey("type");
      p.stringValue(n.nodeType);
      p.endObject();
    }

A list of nodes, or the note that there are none.

    let ejNodes(nodes: List<GraphNode>, none: String): String {
      if (nodes.length == 0) { return ejOne("result", none); }
      let p = ejNew();
      p.startArray();
      for (let n of nodes) { ejNode(p, n); }
      p.endArray();
      ejDone(p)
    }

The arguments the model sent. Text that does not decode to an object is the
empty object.

    let ejArgs(argumentsJson: String?): JsonSyntaxTree? {
      if (argumentsJson != null) {
        let tree: JsonSyntaxTree? = parseJson(argumentsJson) orelse null;
        if (tree is JsonObject) { tree } else { null }
      } else {
        null
      }
    }

    let ejProp(args: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (args is JsonObject) { args.propertyValueOrNull(key) } else { null }
    }

    let ejString(args: JsonSyntaxTree?, key: String): String? {
      let v = ejProp(args, key);
      if (v is JsonString) { v.content } else { null }
    }

`arg_int`: an integer as is; a string is its leading integer or -1; anything
else is -1.

    let editorLeadingInt(s: String): Int {
      var i = String.begin;
      var sign = 1;
      if (s.hasIndex(i)) {
        let first = s[i];
        if (first == 45) {
          sign = -1;
          i = s.next(i);
        } else if (first == 43) {
          i = s.next(i);
        }
      }
      var n = 0;
      var digits = 0;
      var going = true;
      while (going && s.hasIndex(i)) {
        let c = s[i];
        if (c >= 48 && c <= 57 && digits < 9) {
          n = n * 10 + (c - 48);
          digits += 1;
          i = s.next(i);
        } else {
          going = false;
        }
      }
      if (digits == 0) { -1 } else { sign * n }
    }

    let ejInt(args: JsonSyntaxTree?, key: String): Int {
      let v = ejProp(args, key);
      if (v is JsonString) {
        editorLeadingInt(v.content)
      } else if (v is JsonNumeric) {
        do { v.asInt32() } orelse -1
      } else {
        -1
      }
    }

## The tools

Each answers JSON text. None throws on bad input: a missing section is an
`error` field, an empty result is a `result` note saying so.

    let toolSearchManuscript(db: Db, work: Work, args: JsonSyntaxTree?): String throws Bubble {
      let found = worksSearch(db, work.id, ejString(args, "query"), 12);
      let kind = ejString(args, "type");
      let kept = new ListBuilder<GraphNode>();
      for (let n of found) {
        if (kind == null || kind == "" || n.nodeType == kind) { kept.add(n); }
      }
      ejNodes(kept.toList(), "nothing matching that in the read")
    }

A phrase that is missing is an error to the model. (The Elixir called
`String.downcase(nil)` and raised, which killed the whole turn.)

    let toolFindExact(db: Db, work: Work, args: JsonSyntaxTree?): String throws Bubble {
      let phrase = ejString(args, "phrase");
      if (phrase != null) {
        let hits = worksFindInSource(db, work.id, phrase, 5);
        if (hits.length == 0) {
          ejOne("result", "that phrase does not appear in the draft")
        } else {
          let p = ejNew();
          p.startArray();
          for (let h of hits) {
            p.startObject();
            p.objectKey("ordinal");
            p.int32Value(h.ordinal);
            p.objectKey("section");
            p.stringValue(h.section);
            p.objectKey("window");
            p.stringValue(h.window);
            p.endObject();
          }
          p.endArray();
          ejDone(p)
        }
      } else {
        ejOne("error", "find_exact needs a phrase")
      }
    }

    let toolReadPassage(db: Db, work: Work, args: JsonSyntaxTree?): String throws Bubble {
      let s = worksGetSection(db, work.id, ejInt(args, "ordinal"));
      if (s != null) {
        let p = ejNew();
        p.startObject();
        p.objectKey("ordinal");
        p.int32Value(s.ordinal);
        p.objectKey("text");
        p.stringValue(s.body);
        p.objectKey("title");
        p.stringValue(s.title);
        p.objectKey("words");
        p.int32Value(s.wordCount);
        p.endObject();
        ejDone(p)
      } else {
        ejOne("error", "no section with that number")
      }
    }

    let toolListSections(db: Db, work: Work): String throws Bubble {
      let perSection = new MapBuilder<Int, Int>();
      for (let b of worksListNodes(db, work.id, "beat", null, null)) {
        let at = b.sectionId;
        if (at != null) {
          perSection.set(at, perSection.getOr(at, 0) + 1);
        }
      }
      let counts = perSection.toMap();
      let p = ejNew();
      p.startArray();
      for (let s of worksListSections(db, work.id)) {
        p.startObject();
        p.objectKey("beats");
        p.int32Value(counts.getOr(s.id, 0));
        p.objectKey("ordinal");
        p.int32Value(s.ordinal);
        p.objectKey("title");
        p.stringValue(s.title);
        p.objectKey("words");
        p.int32Value(s.wordCount);
        p.endObject();
      }
      p.endArray();
      ejDone(p)
    }

    let toolSectionBeats(db: Db, work: Work, args: JsonSyntaxTree?): String throws Bubble {
      let s = worksGetSection(db, work.id, ejInt(args, "ordinal"));
      if (s != null) {
        ejNodes(
          worksListNodes(db, work.id, "beat", s.id, null),
          "that section has no beats — it may have failed to read",
        )
      } else {
        ejOne("error", "no section with that number")
      }
    }

    let toolManuscriptSpine(db: Db, work: Work): String throws Bubble {
      ejNodes(
        worksListNodes(db, work.id, "spine", null, null),
        "the spine pass has not produced anything for this draft",
      )
    }

    let toolOpenThreads(db: Db, work: Work): String throws Bubble {
      ejNodes(
        worksListNodes(db, work.id, "thread", null, null),
        "no threads were identified",
      )
    }

The same word-scoring `search` uses, over the connection text, so
"connections about the prologue" behaves the way the writer expects.

    class EditorScored(public connection: FullConnection, public score: Int, public order: Int) {}

    let editorMatching(conns: List<FullConnection>, about: String): List<FullConnection> {
      let terms = chatTerms(about);
      if (terms.length == 0) { return conns; }
      let scored = new ListBuilder<EditorScored>();
      var k = 0;
      while (k < conns.length) {
        let c = conns[k];
        let why = c.why;
        let said = if (why != null) { why } else { "" };
        let text = sysUtf8Downcase("${c.from.title} ${c.to.title} ${said}");
        var score = 0;
        for (let t of terms) { if (text.split(t).length > 1) { score += 1; } }
        if (score > 0) { scored.add(new EditorScored(c, score, k)); }
        k += 1;
      }
      let ranked = scored.toList().sorted { (a: EditorScored, b: EditorScored): Int =>
        if (a.score != b.score) { b.score - a.score } else { a.order - b.order }
      };
      ranked.map { (s: EditorScored): FullConnection => s.connection }
    }

The type filter applies to any value the model sent, an empty string
included, which then keeps nothing: `if kind` is truthy for `""`.

    let toolConnections(db: Db, work: Work, args: JsonSyntaxTree?): String throws Bubble {
      let all = worksAllConnections(db, work.id);
      let kindTree = ejProp(args, "type");
      let kind = ejString(args, "type");
      let byKind = new ListBuilder<FullConnection>();
      for (let c of all) {
        if (kindTree == null) {
          byKind.add(c);
        } else if (kind != null && c.edgeType == kind) {
          byKind.add(c);
        }
      }
      let about = ejString(args, "about");
      var narrowed: List<FullConnection> = byKind.toList();
      if (about != null) {
        if (about != "") { narrowed = editorMatching(byKind.toList(), about); }
      }
      if (narrowed.length == 0) {
        return ejOne("result", "no cross-section connections were drawn for this draft yet");
      }
      let p = ejNew();
      p.startArray();
      var i = 0;
      while (i < narrowed.length && i < 60) {
        let c = narrowed[i];
        p.startObject();
        p.objectKey("from");
        p.stringValue(c.from.title);
        p.objectKey("to");
        p.stringValue(c.to.title);
        p.objectKey("type");
        p.stringValue(c.edgeType);
        ejOptional(p, "why", c.why);
        p.endObject();
        i += 1;
      }
      p.endArray();
      ejDone(p)
    }

`inspect` of the errors map Ecto's `traverse_errors` gave, for the message the
model reads: `%{kind: ["is invalid"]}`, fields alphabetical.

    let editorInspectErrors(errors: List<FieldError>): String {
      let fields = new ListBuilder<String>();
      for (let e of errors) {
        var seen = false;
        for (let f of fields.toList()) { if (f == e.field) { seen = true; } }
        if (!seen) { fields.add(e.field); }
      }
      let sortedFields = fields.toList().sorted { (a: String, b: String): Int =>
        if (a < b) { -1 } else if (a > b) { 1 } else { 0 }
      };
      let parts = new ListBuilder<String>();
      for (let f of sortedFields) {
        let messages = new ListBuilder<String>();
        for (let e of errors) {
          if (e.field == f) { messages.add("\"${e.message}\""); }
        }
        parts.add("${f}: [${sysJoin(messages.toList(), ", ")}]");
      }
      "%{${sysJoin(parts.toList(), ", ")}}"
    }

A section the model did not name is stored as -1, as the Elixir did.

    let toolRecordCorrection(db: Db, work: Work, args: JsonSyntaxTree?): String throws Bubble {
      let kind = ejString(args, "kind");
      let about = ejString(args, "about");
      let p = new CorrectionParams(
        work.id,
        if (kind != null) { kind } else { "" },
        if (about != null) { about } else { "" },
      );
      p.ruling = ejString(args, "ruling");
      p.sectionOrdinal = ejInt(args, "section");
      let r = worksRecordCorrection(db, p);
      let c = r.correction;
      if (c != null) {
        let out = ejNew();
        out.startObject();
        out.objectKey("about");
        out.stringValue(c.about);
        out.objectKey("note");
        out.stringValue("this will be in front of you next time");
        out.objectKey("recorded");
        out.stringValue(c.kind);
        out.endObject();
        ejDone(out)
      } else {
        ejOne("error", "not recorded: ${editorInspectErrors(r.errors)}")
      }
    }

Corrections newest first, then what was said before. With no query
`earlier_talk` is empty.

    let toolRecallSessions(db: Db, work: Work, args: JsonSyntaxTree?): String throws Bubble {
      let p = ejNew();
      p.startObject();
      p.objectKey("corrections");
      p.startArray();
      for (let c of worksListCorrections(db, work.id)) {
        p.startObject();
        p.objectKey("about");
        p.stringValue(c.about);
        p.objectKey("kind");
        p.stringValue(c.kind);
        ejOptionalInt(p, "section", c.sectionOrdinal);
        ejOptional(p, "they_said", c.ruling);
        p.endObject();
      }
      p.endArray();
      p.objectKey("earlier_talk");
      p.startArray();
      for (let h of chatSearch(db, work.id, ejString(args, "query"))) {
        p.startObject();
        p.objectKey("at");
        p.stringValue(h.at);
        p.objectKey("said");
        p.stringValue(h.said);
        p.objectKey("who");
        p.stringValue(h.who);
        p.endObject();
      }
      p.endArray();
      p.endObject();
      ejDone(p)
    }

    let toolStatedIntent(db: Db, work: Work): String throws Bubble {
      let p = ejNew();
      p.startObject();
      ejOptional(p, "first_impression", work.firstImpression);
      p.objectKey("questions");
      p.startArray();
      for (let q of worksListNodes(db, work.id, "question", null, null)) {
        p.stringValue(q.title);
      }
      p.endArray();
      ejOptional(p, "stated_intent", work.intent);
      p.objectKey("title");
      p.stringValue(work.title);
      p.endObject();
      ejDone(p)
    }

## Running a tool call

`run_call`'s content: the JSON of what the tool answered. An unknown tool is
`{"error":"unknown tool"}`; a tool that is not offered at this `access` is
refused by name.

    export let editorRunTool(
      db: Db, work: Work, name: String, argumentsJson: String?, access: String,
    ): String throws Bubble {
      if (!editorOffered(name, access)) {
        return ejOne("error", "${name} is not available on a public draft");
      }
      let args = ejArgs(argumentsJson);
      if (name == "search_manuscript") { toolSearchManuscript(db, work, args) } else if (name == "find_exact") { toolFindExact(db, work, args) } else if (name == "read_passage") { toolReadPassage(db, work, args) } else if (name == "list_sections") { toolListSections(db, work) } else if (name == "section_beats") { toolSectionBeats(db, work, args) } else if (name == "manuscript_spine") { toolManuscriptSpine(db, work) } else if (name == "open_threads") { toolOpenThreads(db, work) } else if (name == "connections") { toolConnections(db, work, args) } else if (name == "record_correction") { toolRecordCorrection(db, work, args) } else if (name == "recall_sessions") { toolRecallSessions(db, work, args) } else if (name == "stated_intent") { toolStatedIntent(db, work) } else { ejOne("error", "unknown tool") }
    }

The tool-role message that goes back to the model.

    export let editorRunCall(db: Db, work: Work, call: LlmToolCall, access: String): LlmMessage throws Bubble {
      let m = new LlmMessage("tool", editorRunTool(db, work, call.name, call.argumentsJson, access));
      m.toolCallId = call.id;
      m
    }

## The loop

What one tool call did, for the page to show and the tests to read.

    export class ChatToolEffect(
      public tool: String,
      public argumentsJson: String,
      public resultJson: String,
      public ok: Boolean,
    ) {}

`text` is the reply; `error` is the sentence for the writer when there is no
reply; `quotaExhausted` is set (and nothing is asked) when the account has no
questions left. Exactly one of `text`, `error`, `quotaExhausted` says how it
ended, except for a blank question, which is all three unset.

    export class ChatAskResult(
      public text: String?,
      public error: String?,
      public quotaExhausted: Boolean,
      public effects: List<ChatToolEffect>,
    ) {}

    export let editorMaxRounds(): Int { 8 }

    let editorDescribe(e: LlmError): String {
      if (e.kind == "no_key") {
        "no OpenAI key is configured on this deploy"
      } else if (e.kind == "length") {
        "the reply was cut off — try a narrower question"
      } else if (e.kind == "rate_limited") {
        "OpenAI is rate limiting us; give it a moment"
      } else {
        llmErrorText(e)
      }
    }

The assistant's tool calls as the wire carries them back: the same objects the
provider sent, keys in alphabetical order.

    let editorToolCallsJson(calls: List<LlmToolCall>): String {
      let p = ejNew();
      p.startArray();
      for (let c of calls) {
        p.startObject();
        p.objectKey("function");
        p.startObject();
        p.objectKey("arguments");
        p.stringValue(c.argumentsJson);
        p.objectKey("name");
        p.stringValue(c.name);
        p.endObject();
        p.objectKey("id");
        p.stringValue(c.id);
        p.objectKey("type");
        p.stringValue("function");
        p.endObject();
      }
      p.endArray();
      ejDone(p)
    }

    let editorIsError(json: String): Boolean {
      let parts = json.split("{\"error\":");
      parts.length > 1 && parts[0] == ""
    }

    let editorFailed(text: String, effects: List<ChatToolEffect>): ChatAskResult {
      new ChatAskResult(null, text, false, effects)
    }

Ask, with the tool loop. At most eight rounds of tool calls; the ninth would
be a model still reaching for tools and is an error. The call carries no model
and no effort (the provider's own), temperature 0.7, 2,000 tokens, tool choice
`auto`. Stores nothing: the caller persists the turns.

    export let editorAsk(
      db: Db, llm: LlmClient, work: Work, history: List<ChatTurn>, stanceMode: String?,
      focus: ChatFocus?, cited: List<ChatCited>, access: String,
    ): ChatAskResult throws Bubble {
      let messages = new ListBuilder<LlmMessage>();
      for (let m of editorMessages(db, work, history, stanceMode, focus, cited, access)) {
        messages.add(m);
      }
      let tools = editorTools(access);
      let effects = new ListBuilder<ChatToolEffect>();
      var outcome: ChatAskResult? = null;
      var round = 0;
      while (outcome == null && round < editorMaxRounds()) {
        let call = new LlmCall(messages.toList(), null, null, 2000, 0.7, false, tools, null, 0);
        let r = llm.chat(call);
        let reply = r.ok;
        if (reply != null) {
          if (reply.toolCalls.length == 0) {
            let content = reply.content;
            outcome = new ChatAskResult(
              if (content != null) { content } else { "(no response)" },
              null, false, effects.toList(),
            );
          } else {
            let said = reply.content;
            let turn = new LlmMessage("assistant", if (said != null) { said } else { "" });
            turn.toolCallsJson = editorToolCallsJson(reply.toolCalls);
            messages.add(turn);
            for (let c of reply.toolCalls) {
              let result = editorRunCall(db, work, c, access);
              messages.add(result);
              effects.add(new ChatToolEffect(
                c.name, c.argumentsJson, result.content, !editorIsError(result.content),
              ));
            }
            round += 1;
          }
        } else {
          let e = r.err;
          outcome = editorFailed(
            if (e != null) { editorDescribe(e) } else { "no reply" },
            effects.toList(),
          );
        }
      }
      let done = outcome;
      if (done != null) {
        done
      } else {
        editorFailed("gave up after too many tool calls", effects.toList())
      }
    }

The public draft chat: a visitor's question, a history the page holds, the
restricted tools. No quota, nothing stored.

    export let editorPublicAsk(
      db: Db, llm: LlmClient, work: Work, history: List<ChatTurn>, stanceMode: String?,
      focus: ChatFocus?, cited: List<ChatCited>,
    ): ChatAskResult throws Bubble {
      editorAsk(db, llm, work, history, stanceMode, focus, cited, "public")
    }

## One question, start to finish

The unit of work the page runs for `send` and `thread_send`, inline or in a
run: check the quota, store the question, ask with the last twenty turns,
store the reply. A failed ask stores no reply (the page shows the error and
the question stays). `mode` null means the conversation's own. Whether the
visitor may write at all is the page's check (owner only), not this one's.

    export let chatEditorAskWith(
      db: Db, llm: LlmClient, scope: Scope, conversation: Conversation, text: String,
      mode: String?, focus: ChatFocus?, cited: List<ChatCited>,
    ): ChatAskResult throws Bubble {
      let question = sysStringTrim(text);
      if (question == "") { return new ChatAskResult(null, null, false, []); }
      let user = scope.user;
      let allowed = if (user != null) { chatAllowed(db, user) } else { false };
      if (!allowed) { return new ChatAskResult(null, null, true, []); }
      let work = worksGetById(db, conversation.workId);
      if (work != null) {
        chatAppend(db, conversation.id, "user", question);
        let window = chatContextWindow(chatHistory(db, conversation.id));
        let stance = if (mode != null) { mode } else { conversation.mode };
        let result = editorAsk(db, llm, work, window, stance, focus, cited, "owner");
        let reply = result.text;
        if (reply != null) { chatAppend(db, conversation.id, "assistant", reply); }
        result
      } else {
        bubble()
      }
    }

    export let chatEditorAsk(
      db: Db, llm: LlmClient, scope: Scope, conversation: Conversation, text: String, mode: String?,
    ): ChatAskResult throws Bubble {
      chatEditorAskWith(db, llm, scope, conversation, text, mode, null, [])
    }
