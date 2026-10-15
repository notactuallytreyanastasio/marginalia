# Bulk: which pairs of a folder are worth relating

`Marginalia.Links.Bulk`. Relating two drafts costs a model call over both
their maps. A folder of twelve is sixty-six pairs; the stack of pull requests
is a hundred and eleven documents, which is six thousand one hundred and five.
Linking everything to everything is not expensive, it is impossible.

So this is two stages, and the first one is cheap.

**Triage.** One call. Every document gets one line (its title and the best
short description already on hand) and the model picks the pairs worth the
second stage, each with the reason it expects to find something. A proposal is
not a finding: `why` is a hypothesis, and the pair exists to be tested rather
than believed.

**Relating.** The pairs that survive validation are created and handed to the
linker. The Elixir ran three at a time under `Task.async_stream`; a context
here does not fork, so `linksBulkRelatePair` is the unit of work, and
`linksBulkRelate` runs the pairs one after another. Whoever owns the forking
(the `runs` library) can call the pair function from as many children as it
likes.

What it will not do: the linker needs both documents to have been read (it
works over node maps, and an unread document has none). Unread halves are
reported by name rather than skipped quietly.

    let { Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Work, worksListWorks } = import("works/src");
    let {
      LlmClient, LlmCall, LlmMessage, LlmTool, LlmReply, LlmError, Result, llmErrorText,
    } = import("llm/src");
    let {
      JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonNull, JsonBoolean,
      JsonInt32, JsonInt64, JsonFloat64, parseJson,
    } = import("std/json");
    let { sysStringTrim, sysGraphemeTake, sysJoin } = import("sys/src");

    export let linksBulkMaxPairs(): Int { 24 }

    let linksBulkLineCap(): Int { 220 }

## One tool call

`LLM.call_tool/1`: the tool is sent alongside the messages and the model
answers by calling it. The choice is `auto` unless the effort is `none`
(DeepSeek refuses a forced choice while it is thinking); every caller in this
context uses effort `high`. Only the first tool call is read. A reply that
called nothing is `no_tool_call`; arguments that are not a JSON object are
`invalid_json`; the client's own errors pass through.

    export let linksCallTool(
      llm: LlmClient, tool: LlmTool, messages: List<LlmMessage>, effort: String,
      temperature: Float64, maxTokens: Int,
    ): Result<JsonObject, LlmError> {
      let call = new LlmCall(messages, null, effort, maxTokens, temperature, false, [tool], null, 0);
      let r = llm.chat(call);
      let reply = r.ok;
      if (reply != null) {
        if (reply.toolCalls.length == 0) {
          return new Result<JsonObject, LlmError>(null,
            new LlmError("no_tool_call", "the model answered without calling ${tool.name}"));
        }
        let parsed: JsonSyntaxTree? = parseJson(reply.toolCalls[0].argumentsJson) orelse null;
        if (parsed is JsonObject) {
          new Result<JsonObject, LlmError>(parsed, null)
        } else {
          new Result<JsonObject, LlmError>(null,
            new LlmError("invalid_json", "the tool arguments are not a JSON object"))
        }
      } else {
        new Result<JsonObject, LlmError>(null, r.err)
      }
    }

## What the model is given

One line per document: whatever short description already exists for it. In
preference order, because each is better than the next and all of them are
already paid for: the step read for it as part of a stack, then its own
section summaries, then the first impression from its read, then nothing but
the title. A document with only a title is still offered; the model can tell
it has been given little.

    export class BulkLine(public n: Int, public work: Work, public line: String) {}

    let linksBulkBlank(s: String?): Boolean {
      if (s != null) { sysStringTrim(s) == "" } else { true }
    }

    export let linksBulkDescribe(db: Db, work: Work): String throws Bubble {
      var text: String? = null;
      let step = db.one(
        "SELECT capability FROM stack_steps WHERE work_id = $1 ORDER BY id DESC LIMIT 1",
        [work.id.toString()],
      );
      if (step != null) { text = step.strOrNull("capability"); }
      if (linksBulkBlank(text)) {
        let parts = new ListBuilder<String>();
        for (let row of db.query(
          "SELECT summary FROM sections WHERE work_id = $1 AND summary IS NOT NULL ORDER BY ordinal ASC LIMIT 2",
          [work.id.toString()],
        )) {
          parts.add(row.str("summary"));
        }
        text = sysJoin(parts.toList(), " ");
      }
      if (linksBulkBlank(text)) { text = work.firstImpression; }
      let chosen = text;
      if (chosen != null) {
        if (!linksBulkBlank(chosen)) {
          return sysGraphemeTake(sysStringTrim(linksCollapse(chosen, true)), linksBulkLineCap());
        }
      }
      ""
    }

The documents of a folder, oldest first, numbered from 1, with the line each
will be described by.

    export let linksBulkSheet(db: Db, scope: Scope, folderId: Int): List<BulkLine> throws Bubble {
      let mine = worksListWorks(db, scope);
      let out = new ListBuilder<BulkLine>();
      var i = mine.length - 1;
      var n = 1;
      while (i >= 0) {
        let w = mine[i];
        if (w.folderId == folderId) {
          out.add(new BulkLine(n, w, linksBulkDescribe(db, w)));
          n += 1;
        }
        i -= 1;
      }
      out.toList()
    }

## Triage

A pair worth the second stage. `linkId` and `error` are filled in by relating.

    export class BulkPair(public a: Work, public b: Work, public why: String, public expect: String) {
      public var linkId: Int? = null;
      public var error: String? = null;
    }

    export class BulkTriage(public pairs: List<BulkPair>, public dropped: List<String>, public skipped: String) {}

`ok` is the validated triage; otherwise `error` is the client's error text.

    export class BulkProposed(public ok: BulkTriage?, public error: String?) {}

    export let linksBulkTool(): LlmTool {
      new LlmTool(
        "propose_links",
        "Choose which pairs of these documents are worth reading against each other.",
        linksBulkToolParameters(),
      )
    }

One call, whatever the folder's size. The spine does not grow with document
length, so the cost of deciding is the same for a folder of twelve as for a
hundred and eleven.

    export let linksBulkListing(sheet: List<BulkLine>): String {
      let lines = new ListBuilder<String>();
      for (let s of sheet) {
        if (s.line == "") {
          lines.add("${s.n.toString()}. ${s.work.title}");
        } else {
          lines.add("${s.n.toString()}. ${s.work.title} — ${s.line}");
        }
      }
      sysJoin(lines.toList(), "\n")
    }

    export let linksBulkPropose(db: Db, llm: LlmClient, sheet: List<BulkLine>): BulkProposed throws Bubble {
      let messages = [
        new LlmMessage("system", linksBulkPrompt()),
        new LlmMessage("user", "${sheet.length.toString()} documents:\n\n${linksBulkListing(sheet)}"),
      ];
      let r = linksCallTool(llm, linksBulkTool(), messages, "high", 0.3, 3000);
      let raw = r.ok;
      if (raw != null) {
        new BulkProposed(linksBulkValidate(raw, sheet), null)
      } else {
        let e = r.err;
        new BulkProposed(null, if (e != null) { llmErrorText(e) } else { "no_reply" })
      }
    }

## Validation

Elixir's `inspect/1` of a decoded JSON value, enough for the dropped-pair
messages: strings quoted, `nil`, maps with sorted keys.

    let linksBulkInspectString(s: String): String {
      let escaped = sysJoin(sysJoin(s.split("\\"), "\\\\").split("\""), "\\\"");
      let lines = sysJoin(escaped.split("\n"), "\\n");
      "\"${lines}\""
    }

    export let linksBulkInspect(t: JsonSyntaxTree): String {
      if (t is JsonString) {
        linksBulkInspectString(t.content)
      } else if (t is JsonInt32) {
        t.content.toString()
      } else if (t is JsonInt64) {
        t.content.toString()
      } else if (t is JsonFloat64) {
        t.content.toString()
      } else if (t is JsonBoolean) {
        if (t.content) { "true" } else { "false" }
      } else if (t is JsonNull) {
        "nil"
      } else if (t is JsonArray) {
        let parts = new ListBuilder<String>();
        for (let e of t.elements) { parts.add(linksBulkInspect(e)); }
        "[${sysJoin(parts.toList(), ", ")}]"
      } else {
        "%{}"
      }
    }

`Map.take(p, ["a", "b"])` inspected: only the keys present, `a` first.

    let linksBulkTaken(p: JsonObject): String {
      let parts = new ListBuilder<String>();
      let a = p.propertyValueOrNull("a");
      let b = p.propertyValueOrNull("b");
      if (a != null) { parts.add("\"a\" => ${linksBulkInspect(a)}"); }
      if (b != null) { parts.add("\"b\" => ${linksBulkInspect(b)}"); }
      "%{${sysJoin(parts.toList(), ", ")}}"
    }

    let linksBulkEntry(sheet: List<BulkLine>, n: Int): Work? {
      var i = 0;
      while (i < sheet.length) {
        if (sheet[i].n == n) { return sheet[i].work; }
        i += 1;
      }
      null
    }

    let linksBulkMissing(sheet: List<BulkLine>, a: Int, b: Int): String {
      let parts = new ListBuilder<String>();
      if (linksBulkEntry(sheet, a) == null) { parts.add(a.toString()); }
      if (linksBulkEntry(sheet, b) == null) { parts.add(b.toString()); }
      "[${sysJoin(parts.toList(), ", ")}]"
    }

    let linksBulkKey(a: Int, b: Int): String {
      if (a < b) { "${a.toString()}:${b.toString()}" } else { "${b.toString()}:${a.toString()}" }
    }

Keep the pairs that name two real, different documents, once each. Public
because it is pure and because a proposal citing document 140 of a folder of
twelve reads exactly like one that is real. Every dropped pair is named, with
the reason.

    export let linksBulkValidate(raw: JsonObject, sheet: List<BulkLine>): BulkTriage {
      let kept = new ListBuilder<BulkPair>();
      let dropped = new ListBuilder<String>();
      let seen = new MapBuilder<String, Boolean>();
      let list = raw.propertyValueOrNull("pairs");
      if (list is JsonArray) {
        for (let item of list.elements) {
          if (item is JsonObject) {
            linksBulkOne(item, sheet, kept, dropped, seen);
          }
        }
      }
      let first = new ListBuilder<BulkPair>();
      var i = 0;
      while (i < kept.length && i < linksBulkMaxPairs()) {
        first.add(kept[i]);
        i += 1;
      }
      new BulkTriage(first.toList(), dropped.toList(), linksJsonTrimmed(raw.propertyValueOrNull("skipped")))
    }

    let linksBulkOne(
      p: JsonObject, sheet: List<BulkLine>, kept: ListBuilder<BulkPair>,
      dropped: ListBuilder<String>, seen: MapBuilder<String, Boolean>,
    ): Void {
      let a = linksJsonInt(p.propertyValueOrNull("a"), true);
      let b = linksJsonInt(p.propertyValueOrNull("b"), true);
      if (a != null) {
        if (b != null) {
          linksBulkOneIds(p, a, b, sheet, kept, dropped, seen);
          return;
        }
      }
      dropped.add("a pair without two numbers: ${linksBulkTaken(p)}");
    }

    let linksBulkOneIds(
      p: JsonObject, a: Int, b: Int, sheet: List<BulkLine>, kept: ListBuilder<BulkPair>,
      dropped: ListBuilder<String>, seen: MapBuilder<String, Boolean>,
    ): Void {
      let workA = linksBulkEntry(sheet, a);
      let workB = linksBulkEntry(sheet, b);
      if (a == b) {
        dropped.add("${a.toString()} paired with itself");
        return;
      }
      if (workA != null) {
        if (workB != null) {
          if (seen.has(linksBulkKey(a, b))) {
            dropped.add("${a.toString()}–${b.toString()} proposed twice");
          } else {
            seen.set(linksBulkKey(a, b), true);
            kept.add(new BulkPair(
              workA,
              workB,
              linksJsonTrimmed(p.propertyValueOrNull("why")),
              linksJsonTrimmed(p.propertyValueOrNull("expect")),
            ));
          }
          return;
        }
      }
      dropped.add("${linksBulkMissing(sheet, a, b)} is not in this folder");
    }

## Relating

The pairs that cannot be related, said in full. Public because it is the part
worth testing and the part most likely to be quietly dropped: "I related your
folder" with no word about the nine documents that were not eligible is worse
than doing nothing.

    let linksBulkRead(w: Work): Boolean { w.status == "read" }

    let linksBulkReadable(pair: BulkPair): Boolean { linksBulkRead(pair.a) && linksBulkRead(pair.b) }

    export let linksBulkIneligible(pairs: List<BulkPair>): List<String> {
      let out = new ListBuilder<String>();
      for (let pair of pairs) {
        if (!linksBulkReadable(pair)) {
          let unread = new ListBuilder<String>();
          if (!linksBulkRead(pair.a)) { unread.add(pair.a.title); }
          if (!linksBulkRead(pair.b)) { unread.add(pair.b.title); }
          out.add("${pair.a.title} ↔ ${pair.b.title}: ${sysJoin(unread.toList(), " and ")} has not been read");
        }
      }
      out.toList()
    }

One pair: find or create its link, then read it. The result of the pass is
ignored (a failed pass leaves the link `failed` with its error, which is what
the page shows); the pair gets the link's id, or the reason there is no link.
This is the body the Elixir ran in each `Task.async_stream` task.

    export let linksBulkRelatePair(db: Db, llm: LlmClient, pair: BulkPair): Void throws Bubble {
      let made = linksGetOrCreate(db, pair.a.id, pair.b.id);
      let link = made.ok;
      if (link != null) {
        linkerRun(db, llm, link);
        pair.linkId = link.id;
      } else {
        pair.error = made.error;
      }
    }

What happened to every pair handed to `linksBulkRelate`: the eligible ones
(with their link ids), and the sentences naming the ones that were not.

    export class BulkRelated(public started: List<BulkPair>, public notRead: List<String>) {}

`relate/2`, one pair after another. A pair is eligible only when BOTH sides
have been read.

    export let linksBulkRelate(db: Db, llm: LlmClient, pairs: List<BulkPair>): BulkRelated throws Bubble {
      let started = new ListBuilder<BulkPair>();
      let skipped = new ListBuilder<BulkPair>();
      for (let pair of pairs) {
        if (linksBulkReadable(pair)) { started.add(pair); } else { skipped.add(pair); }
      }
      for (let pair of started.toList()) { linksBulkRelatePair(db, llm, pair); }
      new BulkRelated(started.toList(), linksBulkIneligible(skipped.toList()))
    }

## Run

Triage a folder and relate the pairs that come back. `error` is `no_folder`
(not the user's), `empty_folder` (nothing in it, said before any model call),
or the client's error text. `proposeOnly` stops after the cheap stage, which is
the sensible thing to do the first time on a folder of a hundred.

    export class BulkRun(
      public error: String?,
      public triage: BulkTriage?,
      public started: List<BulkPair>,
      public notRead: List<String>,
    ) {}

    let linksBulkRunFailed(error: String): BulkRun { new BulkRun(error, null, [], []) }

    export let linksBulkRun(db: Db, llm: LlmClient, scope: Scope, folderId: Int, proposeOnly: Boolean): BulkRun throws Bubble {
      let userId = linksUserId(scope);
      if (userId != null) {
        linksBulkRunOwned(db, llm, scope, userId, folderId, proposeOnly)
      } else {
        linksBulkRunFailed("no_folder")
      }
    }

    let linksBulkRunOwned(
      db: Db, llm: LlmClient, scope: Scope, userId: Int, folderId: Int, proposeOnly: Boolean,
    ): BulkRun throws Bubble {
      let mine = db.one(
        "SELECT id FROM folders WHERE id = $1 AND user_id = $2",
        [folderId.toString(), userId.toString()],
      );
      if (mine == null) { return linksBulkRunFailed("no_folder"); }
      let sheet = linksBulkSheet(db, scope, folderId);
      if (sheet.length == 0) { return linksBulkRunFailed("empty_folder"); }
      let proposed = linksBulkPropose(db, llm, sheet);
      let triage = proposed.ok;
      if (triage != null) {
        if (proposeOnly) {
          new BulkRun(null, triage, [], [])
        } else {
          let related = linksBulkRelate(db, llm, triage.pairs);
          new BulkRun(null, triage, related.started, related.notRead)
        }
      } else {
        let why = proposed.error;
        linksBulkRunFailed(if (why != null) { why } else { "no_reply" })
      }
    }
