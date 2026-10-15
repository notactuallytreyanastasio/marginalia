# Rewrite

`Marginalia.Rewrite`: candidate rewrites of one span the writer selected.

This is the one place in the product that writes prose for the manuscript, and
the constraints on it are what keep that from swallowing the rest.

- It only ever runs on a span the writer selected and explicitly asked about.
- It returns **candidates**, plural, each labelled with the move it makes and
  what it costs. A single suggestion reads as the answer; three labelled ones
  read as options, which is what they are.
- It never applies anything on its own. The writer picks, or does neither.
- The span is verified against the draft first, so a rewrite is always a
  drop-in replacement for something actually on the page.

The word diff shown beside a candidate is `core`'s `diff`, run on one paragraph
at a time and never over a whole draft: it costs 17.9 s for 2,000 words in the
interpreter.

    let { Db } = import("db/src");
    let { Work, Section, ReplaceResult, worksReplaceBlock, worksSectionById } = import("works/src");
    let { diff, Part } = import("core/src");
    let { wordCount, markdownParagraphs } = import("html/src");
    let { LlmClient, LlmTool } = import("llm/src");
    let { JsonObject, JsonSyntaxTree, JsonString, JsonArray } = import("std/json");
    let { sysJoin, sysUtf8Downcase } = import("sys/src");

## The limits

The longest span that may be rewritten, measured: a draft of 12 sections of
1,560 to 2,290 words has paragraphs with a median of 248 words and a longest of
539; 2,500 covers a section of it with room over the largest. The provider's
own ceiling was probed (deepseek-flash takes 65,536) and a span of 2,500 words
asks for 17,500 answer tokens, which with the 24,000 of reasoning headroom is
41,500.

    export let rewriteMaxSpanWords(): Int { 2500 }

The longest steer taken from the writer. Past this it is a brief, not a note.

    export let rewriteMaxSteerChars(): Int { 400 }

The answer budget for a span: three candidates plus their two labels each.
The client adds reasoning headroom on top, so this is answer only. A flat 3,000
was ample at 250 words and wrong at 750: the reply comes back `length`, and the
symptom is not three short candidates but none at all. Seven tokens per word of
span is three candidates at about 1.4 tokens a word with room for the JSON.

    export let rewriteAnswerBudget(span: String): Int {
      let n = wordCount(span) * 7;
      if (n > 3000) { n } else { 3000 }
    }

## What the panel calls the span

"Rewrites of one line" whatever was selected was true enough at a 250-word
ceiling and false at 2,500.

    export let rewriteSpanLabel(span: String?): String {
      if (span != null) {
        let n = wordCount(span);
        if (n == 0) {
          "Rewrites"
        } else if (n < 25) {
          "Rewrites of one line"
        } else {
          "Rewrites of ${n.toString()} words"
        }
      } else {
        "Rewrites"
      }
    }

The head and tail of the selection, for showing its extent; null when short
enough that the writer can already see all of it (120 characters once
whitespace is flattened). The head is 64 characters, the tail 48, and the
middle is ` … ` (U+2026 with a space each side).

    export let rewriteSpanExtent(span: String?): String? {
      if (span != null) {
        let flat = readingTrim(readingCollapse(span, false));
        if (flat.isEmpty) { return null; }
        let length = readingLength(flat);
        if (readingGraphemes(flat) <= 120) { return null; }
        let head = readingTake(flat, 64);
        let tail = readingSliceCp(flat, length - 48, 48);
        "${head} … ${tail}"
      } else {
        null
      }
    }

## The steer

The writer's own instruction, as it goes into the prompt: trimmed and cut to
400 characters. It outranks the standing "differ in kind" rule, because three
candidates that ignore what was asked for are three wasted candidates, but they
still have to differ. The one place writer-supplied text enters the prompt, so
the one place it is bounded.

    export let rewriteSteerBlock(steer: String?): String {
      if (steer != null) {
        let trimmed = readingTrim(steer);
        if (trimmed.isEmpty) { "" } else { promptsAskedFor(readingTake(trimmed, rewriteMaxSteerChars())) }
      } else {
        ""
      }
    }

## Putting a candidate back

Put a candidate back into the paragraph it came from: the block with the first
occurrence of `original` replaced by `seed`, or null (`:not_here`) when the
block does not hold it. A rewrite that cannot be placed is a refusal, not a
substitution: the LiveView used to fall through to the candidate, which
replaced the whole paragraph with a rewrite of text that was not in it.

A missing block or original places the seed as it is.

    export let rewritePlace(block: String?, original: String?, seed: String): String? {
      if (block != null) {
        if (original != null) {
          if (readingContains(block, original)) {
            readingReplaceFirst(block, original, seed)
          } else {
            null
          }
        } else {
          seed
        }
      } else {
        seed
      }
    }

## Which paragraphs a span covers

Every paragraph the span touches, by the ref the page gives it. Overlap is
decided on offsets in the section body rather than by asking whether a
paragraph is inside the span: a selection that starts mid-paragraph covers that
paragraph without containing it. Touching at a boundary is not overlapping.
The ref is built the way `readingBlocks` builds it.

    export let rewriteCoveredRefs(section: Section, span: String): List<String> {
      let body = section.body;
      let spanStart = readingIndexOf(body, span);
      let out = new ListBuilder<String>();
      if (spanStart < 0) { return out.toList(); }
      let spanEnd = spanStart + readingLength(span);
      let paragraphs = markdownParagraphs(body);
      var i = 0;
      while (i < paragraphs.length) {
        let start = readingIndexOf(body, paragraphs[i]);
        if (start >= 0) {
          let end = start + readingLength(paragraphs[i]);
          if (start < spanEnd && spanStart < end) {
            out.add(readingRef(section.ordinal, i));
          }
        }
        i += 1;
      }
      out.toList()
    }

The first paragraph of the section that holds the span, or null. Null is the
ordinary case once spans can be section-sized: a selection crossing three
paragraphs sits in none of them, and a candidate cannot be dropped into one.

    export let rewriteParagraphAround(body: String, span: String): String? {
      let paragraphs = markdownParagraphs(body);
      var i = 0;
      while (i < paragraphs.length) {
        if (selectionInBlock(paragraphs[i], span) != null) { return paragraphs[i]; }
        i += 1;
      }
      null
    }

## Cleaning what the model returned

Models like to wrap the replacement in quotes or prefix it with a label, and
either one pasted into the draft is a bug the writer has to fix.

`^(option|candidate|version)\s*\d*\s*[:.\-—]\s*`, case-insensitive: the label
and its separator come off the front.

    let rewriteLabelEnd(s: String): Int {
      let cps = readingCodePoints(s);
      let words = ["option", "candidate", "version"];
      var w = 0;
      while (w < words.length) {
        let word = words[w];
        let n = readingLength(word);
        if (cps.length >= n) {
          let head = readingStringOf(cps, 0, n);
          if (sysUtf8Downcase(head) == word) {
            var i = n;
            while (i < cps.length && readingIsAsciiSpace(cps[i])) { i += 1; }
            while (i < cps.length && cps[i] >= 48 && cps[i] <= 57) { i += 1; }
            while (i < cps.length && readingIsAsciiSpace(cps[i])) { i += 1; }
            if (i < cps.length && (cps[i] == 58 || cps[i] == 46 || cps[i] == 45 || cps[i] == 0x2014)) {
              i += 1;
              while (i < cps.length && readingIsAsciiSpace(cps[i])) { i += 1; }
              return i;
            }
          }
        }
        w += 1;
      }
      0
    }

A text wrapped in straight `"..."` or curly `"..."` quotes loses the outer
pair.

    let rewriteUnwrap(t: String): String {
      let cps = readingCodePoints(t);
      let n = cps.length;
      if (n == 0) { return t; }
      let first = cps[0];
      let last = cps[n - 1];
      let straight = first == 34 && last == 34;
      let curly = first == 0x201C && last == 0x201D;
      if (straight || curly) {
        if (n < 2) { "" } else { readingStringOf(cps, 1, n - 1) }
      } else {
        t
      }
    }

    let rewriteTrimText(t: String): String {
      let first = readingTrim(t);
      let cps = readingCodePoints(first);
      let cut = rewriteLabelEnd(first);
      let unlabelled = readingTrim(readingStringOf(cps, cut, cps.length));
      readingTrim(rewriteUnwrap(unlabelled))
    }

Whitespace to single spaces, trimmed, and cut to 160 characters.

    let rewriteOneLine(t: String): String {
      readingTake(readingTrim(readingCollapse(t, false)), 160)
    }

Two candidates are the same candidate when they use the same words.

    let rewriteSquash(t: String): String { readingLetters(t) }

Normalise the model's raw candidates into what the panel renders: items that
are objects, with their text cleaned, the move and cost on one line each;
candidates without text, those the same as the original, and repeats of an
earlier one are dropped; the first four are kept.

    export let rewriteClean(raw: List<JsonSyntaxTree>, original: String): List<RewriteCandidate> {
      let normalised = rewriteSquash(original);
      let out = new ListBuilder<RewriteCandidate>();
      let seen = new ListBuilder<String>();
      for (let item of raw) {
        if (item is JsonObject && out.length < 4) {
          let rawText = readingStr(item, "text");
          if (rawText != null) {
            let text = rewriteTrimText(rawText);
            if (!text.isEmpty) {
              let key = rewriteSquash(text);
              if (key != normalised && !rewriteHas(seen.toList(), key)) {
                seen.add(key);
                let move = readingStr(item, "move");
                let cost = readingStr(item, "cost");
                out.add(new RewriteCandidate(
                  text,
                  if (move != null) { rewriteOneLine(move) } else { null },
                  if (cost != null) { rewriteOneLine(cost) } else { null },
                ));
              }
            }
          }
        }
      }
      out.toList()
    }

    let rewriteHas(xs: List<String>, x: String): Boolean {
      for (let y of xs) {
        if (y == x) { return true; }
      }
      false
    }

## The word diff

A word-level diff of two spans, as `Part`s of kind `same`, `del` or `ins`, shown
beside a candidate so the writer can see what actually changed. It is `core`'s;
call it on a paragraph, not a draft.

    export let rewriteDiff(a: String, b: String): List<Part> { diff(a, b) }

## The call

The tool, and the pass the admin page lists.

    export let rewriteTool(): LlmTool {
      new LlmTool(rewriteToolName(), rewriteToolDescription(), rewriteToolParameters())
    }

    export class RewritePass(
      public id: String,
      public name: String,
      public runs: String,
      public produces: String,
      public prompt: String,
    ) {}

    export let rewritePasses(): List<RewritePass> {
      [new RewritePass(
        "rewrite",
        "On request — rewrite one selected span",
        "only when the writer selects a span and asks",
        "three labelled candidates, each with the move it makes and what it costs",
        rewritePrompt(),
      )]
    }

How much to tell the model about the scale of the span: nothing up to 60
words, a note about structure to 400, and a stronger one beyond.

    let rewriteScale(n: Int): String {
      if (n > 400) {
        promptsScaleSection(n)
      } else if (n > 60) {
        promptsScaleSeveral(n)
      } else {
        ""
      }
    }

A failed result: no candidates, with the reason.

    let rewriteFailed(
      original: String, section: Section?, error: String, detail: String?, words: Int,
    ): RewriteResult {
      new RewriteResult(
        null, original, section, [], false, [], error, detail, words, rewriteMaxSpanWords(),
      )
    }

Ask for candidates for `found` in `section`: the span as the draft has it.
The one call, with high effort, temperature 0.7 and `rewriteAnswerBudget`
tokens of answer. Nothing is stored. A reply without a `rewrites` list, or
whose candidates all clean away, is `no_candidates`, never the raw reply.

    let rewriteRun(
      llm: LlmClient, work: Work, section: Section, found: String, steer: String?,
    ): RewriteResult {
      let words = wordCount(found);
      let around = rewriteParagraphAround(section.body, found);
      let context = if (around != null) { promptsContext(around) } else { "" };
      let user = promptsRewriteUser(
        work.title, work.intent, rewriteSteerBlock(steer), rewriteScale(words), found, context,
      );
      let reply = readingCallTool(
        llm, rewriteTool(), null, "high", 0.7, rewriteAnswerBudget(found), rewritePrompt(), user,
      );
      let out = reply.ok;
      if (out == null) {
        return rewriteFailed(found, section, orError(reply.error), reply.detail, words);
      }
      let rewrites = readingProp(out, "rewrites");
      if (rewrites is JsonArray) {
        let candidates = rewriteClean(rewrites.elements, found);
        if (candidates.isEmpty) {
          rewriteFailed(found, section, "no_candidates", null, words)
        } else {
          new RewriteResult(
            readingStr(out, "reading"), found, section, candidates,
            around == null, rewriteCoveredRefs(section, found),
            null, null, words, rewriteMaxSpanWords(),
          )
        }
      } else {
        rewriteFailed(found, section, "no_candidates", "the reply has no rewrites", words)
      }
    }

    let orError(e: String?): String { if (e != null) { e } else { "unknown" } }

`Rewrite.propose/3`: rewrites of a selected span. The length first (it is about
what they selected and costs nothing), then the span is located in the draft:
a selection that is not in the manuscript gets no rewrites, because a rewrite
of something the writer did not write is a rewrite of nothing. `steer` is the
writer's own instruction, or null.

    export let rewritePropose(
      db: Db, llm: LlmClient, work: Work, span: String, steer: String?,
    ): RewriteResult throws Bubble {
      let words = wordCount(span);
      if (words > rewriteMaxSpanWords()) {
        return rewriteFailed(span, null, "span_too_long", null, words);
      }
      let hit = selectionLocate(db, work, span);
      if (hit != null) {
        rewriteRun(llm, work, hit.section, hit.span, steer)
      } else {
        rewriteFailed(span, null, "not_in_draft", null, words)
      }
    }

The block of a section with this ref (`s<ordinal>p<index>`), or null.

    export let rewriteBlockText(section: Section, blockRef: String): String? {
      var found: String? = null;
      for (let b of readingBlocks(section)) {
        if (b.ref == blockRef) { found = b.text; }
      }
      found
    }

Rewrites of one whole block of the page, named by its ref. The block is already
a literal piece of the section, so it is not located again. A ref the section
does not have is `no_such_block`.

    export let rewriteAsk(
      db: Db, llm: LlmClient, work: Work, section: Section, blockRef: String,
    ): RewriteResult throws Bubble {
      rewriteSteer(db, llm, work, section, blockRef, null)
    }

The same, with the writer's own instruction in the prompt.

    export let rewriteSteer(
      db: Db, llm: LlmClient, work: Work, section: Section, blockRef: String, steer: String?,
    ): RewriteResult throws Bubble {
      let block = rewriteBlockText(section, blockRef);
      if (block != null) {
        let words = wordCount(block);
        if (words > rewriteMaxSpanWords()) {
          rewriteFailed(block, section, "span_too_long", null, words)
        } else {
          rewriteRun(llm, work, section, block, steer)
        }
      } else {
        rewriteFailed("", section, "no_such_block", blockRef, 0)
      }
    }

## Applying

Put a candidate in the place of `original` in the section, through the draft's
own edit so it is reflowed, recorded as a revision with origin `rewrite` and the
candidate's move as the note, and the notes about the old line superseded. The
section is read fresh, so a candidate asked for before another edit is applied
to the draft as it is now: `moved` if the old text has since gone.

    export let rewriteApplySpan(
      db: Db, section: Section, original: String, candidate: RewriteCandidate,
    ): RewriteApplied throws Bubble {
      let fresh = worksSectionById(db, section.id);
      let current = if (fresh != null) { fresh } else { section };
      let r = worksReplaceBlock(db, current, original, candidate.text, "rewrite", candidate.move);
      new RewriteApplied(r.section, r.superseded, r.error)
    }

Apply a candidate over the whole block `blockRef` names. A ref the section no
longer has is `no_such_block`.

    export let rewriteApply(
      db: Db, work: Work, section: Section, blockRef: String, candidate: RewriteCandidate,
    ): RewriteApplied throws Bubble {
      let fresh = worksSectionById(db, section.id);
      let current = if (fresh != null) { fresh } else { section };
      let block = rewriteBlockText(current, blockRef);
      if (block != null) {
        rewriteApplySpan(db, current, block, candidate)
      } else {
        new RewriteApplied(current, 0, "no_such_block")
      }
    }
