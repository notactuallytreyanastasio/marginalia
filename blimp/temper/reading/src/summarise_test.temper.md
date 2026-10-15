# Tests for the section summary

Ported from `test/marginalia/summary_test.exs` (19 tests): a summary of a
section, and knowing when it has stopped being true. A summary of prose that
has since been rewritten is worse than none: it is a confident description of
text that is not there.

The Elixir file never reached a model (`run/1` was exercised only on its
`:empty` refusal). The tests at the end do, with canned answers.

    let { Db, dbOpen } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Work, Section, worksListSections, worksReplaceBlock } = import("works/src");
    let { diff, Row, Part } = import("core/src");
    let { LlmClient, llmFake, llmFakeScript, LlmFakeResponse, llmLastRequest } = import("llm/src");
    let { JsonSyntaxTree } = import("std/json");
    let { versionsOf, versionsWorkTopic } = import("runs/src");
    let { sysJoin } = import("sys/src");

    class SummaryFx(public db: Db, public me: Scope, public work: Work, public section: Section) {}

    let summaryBodyText(): String {
      "# One\n\nALPHA the first paragraph. ${rdRepeat("word ", 300)}\n\n# Two\n\nBRAVO. ${rdRepeat("word ", 300)}"
    }

    let summaryFixture(): SummaryFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = rdUser(db, "a@example.com");
      let work = rdWork(db, me, "Draft", summaryBodyText());
      new SummaryFx(db, me, work, rdFirst(db, work))
    }

Edit the first paragraph of a section: ALPHA becomes AMENDED.

    let amend(fx: SummaryFx, section: Section): Section throws Bubble {
      let block = rdBlockWith(section, "ALPHA");
      worksReplaceBlock(fx.db, section, block, readingReplaceFirst(block, "ALPHA", "AMENDED"), null, null);
      rdSection(fx.db, section.id)
    }

## Currency

    test("summary: a section with no summary is not current") { test =>
      let fx = summaryFixture();
      rdFalse(test, summaryCurrent(fx.section), "nothing to be current");
    }

    test("summary: a stored summary is current against the text it was made from") { test =>
      let fx = summaryFixture();
      let s = rdSummarise(fx.db, fx.section, "It sets up alpha.", summaryFingerprint(fx.section), null);
      rdTrue(test, summaryCurrent(s), "current");
    }

A summary of prose that has been rewritten describes text that is not there; the
stale summary is kept and marked, not silently deleted.

    test("summary: editing the section makes its summary stale") { test =>
      let fx = summaryFixture();
      let s = rdSummarise(fx.db, fx.section, "It sets up alpha.", summaryFingerprint(fx.section), null);
      rdTrue(test, summaryCurrent(s), "current before");
      let after = amend(fx, s);
      rdFalse(test, summaryCurrent(after), "stale after");
      rdText(test, rdOr(after.summary, "<none>"), "It sets up alpha.");
    }

    test("summary: an empty section is refused before any call is made") { test =>
      let fx = summaryFixture();
      let llm = llmFake([]);
      let r = summaryAsk(fx.db, llm, fx.work, rdWithBody(fx.section, "   "));
      rdText(test, rdOr(r.error, "ok"), "empty");
      rdCalls(test, llm, 0);
    }

    test("summary: the fingerprint changes with the text and not with anything else") { test =>
      let fx = summaryFixture();
      let a = summaryFingerprint(fx.section);
      rdText(test, summaryFingerprint(rdWithTitle(fx.section, "A different title")), a);
      rdFalse(test, summaryFingerprint(rdWithBody(fx.section, "${fx.section.body} more")) == a, "the body moved");
    }

    test("summary: a fingerprint is the lower-case hex SHA-256 of the body") { test =>
      let fx = summaryFixture();
      let f = summaryFingerprint(rdWithBody(fx.section, "abc"));
      rdText(test, f, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    }

## The prompt knows where the section sits

    test("summary: the spine lists every section and marks this one") { test =>
      let fx = summaryFixture();
      let siblings = worksListSections(fx.db, fx.work.id);
      let spine = summarySpine(siblings, fx.section);
      rdHas(test, spine, "1. One");
      rdHas(test, spine, "2. Two");
      rdHas(test, spine, "<- THIS ONE");
      rdInt(test, spine.split("\n").length, siblings.length);
      rdText(test, spine, "1. One  <- THIS ONE\n2. Two");
    }

    test("summary: the section before is handed over in the words already used for it") { test =>
      let fx = summaryFixture();
      rdSummarise(fx.db, fx.section, "It establishes alpha.", null, null);
      let siblings = worksListSections(fx.db, fx.work.id);
      let block = summaryPreviousBlock(siblings, siblings[1]);
      rdHas(test, block, "It establishes alpha.");
      rdHas(test, block, "1. One");
      rdText(test, block, "\nThe section before this one (1. One) was summarised as:\nIt establishes alpha.\n");
    }

    test("summary: the first section has no previous block rather than an empty one") { test =>
      let fx = summaryFixture();
      let siblings = worksListSections(fx.db, fx.work.id);
      rdText(test, summaryPreviousBlock(siblings, siblings[0]), "");
    }

    test("summary: an unsummarised predecessor contributes nothing") { test =>
      let fx = summaryFixture();
      let siblings = worksListSections(fx.db, fx.work.id);
      rdText(test, summaryPreviousBlock(siblings, siblings[1]), "");
    }

## validate

    let validateBody(): String {
      "The out-grammar declares the syntax, and kcodegen expands it into Blimp.kt."
    }

    let validated(json: String, ordinal: Int): SummaryChecked throws Bubble {
      summaryValidate(rdJson(json), validateBody(), ordinal)
    }

    test("summary: a term that is really in the section is kept") { test =>
      let v = validated("{\"summary\":\"It sets up the emitter.\",\"covers\":[\"out-grammar\",\"kcodegen\"]}", 3);
      rdText(test, rdJoin(v.covers), "out-grammar|kcodegen");
      rdInt(test, v.dropped.length, 0);
      rdText(test, v.summary, "It sets up the emitter.");
    }

    test("summary: a term the section never mentions is dropped and said so") { test =>
      let v = validated("{\"summary\":\"s\",\"covers\":[\"out-grammar\",\"monad transformers\"]}", 3);
      rdText(test, rdJoin(v.covers), "out-grammar");
      rdInt(test, v.dropped.length, 1);
      rdHas(test, v.dropped[0], "monad transformers");
      rdHas(test, v.dropped[0], "not in the section");
      rdText(test, v.dropped[0], "covers: \"monad transformers\" is not in the section");
    }

Matching ignores case, because prose capitalises at a sentence start, and the
model's casing is kept.

    test("summary: matching ignores case") { test =>
      let v = validated("{\"summary\":\"s\",\"covers\":[\"Out-Grammar\"]}", 3);
      rdText(test, rdJoin(v.covers), "Out-Grammar");
      rdInt(test, v.dropped.length, 0);
    }

5 and 3 are not earlier than 3.

    test("summary: follows_from only points backwards") { test =>
      let v = validated("{\"summary\":\"s\",\"covers\":[],\"follows_from\":[1,2,5,3]}", 3);
      rdText(test, rdJoin(v.follows.map { (n: Int): String => n.toString() }), "1|2");
      rdInt(test, v.dropped.length, 2);
      rdText(test, v.dropped[0], "follows_from 5: not an earlier section");
      rdText(test, v.dropped[1], "follows_from 3: not an earlier section");
    }

    test("summary: follows_from accepts a numeral in a string and refuses what is not a number") { test =>
      let v = validated("{\"summary\":\"s\",\"follows_from\":[\" 2 \",\"1st\",\"x\",2.5,null]}", 3);
      rdText(test, rdJoin(v.follows.map { (n: Int): String => n.toString() }), "2|1");
      rdInt(test, v.dropped.length, 3);
      rdText(test, v.dropped[0], "follows_from \"x\": not a number");
      rdText(test, v.dropped[1], "follows_from 2.5: not a number");
      rdText(test, v.dropped[2], "follows_from nil: not a number");
    }

    test("summary: an empty sets_up is nil rather than a blank line on the page") { test =>
      let v = validated("{\"summary\":\"s\",\"covers\":[],\"sets_up\":\"  \"}", 2);
      rdTrue(test, v.setsUp == null, "null");
      let w = validated("{\"summary\":\"s\",\"sets_up\":\" It opens a door. \"}", 2);
      rdText(test, rdOr(w.setsUp, "<none>"), "It opens a door.");
    }

    test("summary: duplicates are collapsed and the list is bounded") { test =>
      let tens = new ListBuilder<String>();
      for (var i = 0; i < 10; ++i) { tens.add("\"out-grammar\""); }
      let json = "{\"summary\":\"s\",\"covers\":[\"kcodegen\",\"kcodegen\",${sysJoin(tens.toList(), ",")}]}";
      let v = validated(json, 2);
      rdText(test, rdJoin(v.covers), "kcodegen|out-grammar");
      let many = "{\"summary\":\"s\",\"covers\":[\"the\",\"out\",\"grammar\",\"syntax\",\"and\",\"expands\",\"into\",\"declares\"]}";
      rdInt(test, validated(many, 2).covers.length, 6);
    }

    test("summary: anything but a string is an empty summary") { test =>
      let v = validated("{\"summary\":5,\"covers\":\"not a list\"}", 2);
      rdText(test, v.summary, "");
      rdInt(test, v.covers.length, 0);
    }

## What moved under a stale summary

    class DriftFx(public fx: SummaryFx, public section: Section) {}

    let driftFixture(): DriftFx throws Bubble {
      let fx = summaryFixture();
      let s = rdSummarise(
        fx.db, fx.section, "It sets up alpha.", summaryFingerprint(fx.section), fx.section.body,
      );
      new DriftFx(fx, s)
    }

    test("summary: a current summary has no drift to show") { test =>
      let d = driftFixture();
      rdInt(test, summaryDrift(d.section).length, 0);
    }

    test("summary: an edited section shows the paragraph that changed") { test =>
      let d = driftFixture();
      let after = amend(d.fx, d.section);
      let drift = summaryDrift(after);
      var found: Row? = null;
      for (let r of drift) {
        if (r.kind == "change") { found = r; }
      }
      let changed = found;
      rdTrue(test, changed != null, "a change row");
      if (changed != null) {
        rdHas(test, rdOr(changed.left, ""), "ALPHA");
        rdHas(test, rdOr(changed.right, ""), "AMENDED");
      }
    }

    test("summary: the word diff marks what went and what arrived") { test =>
      let d = driftFixture();
      let after = amend(d.fx, d.section);
      var found: Row? = null;
      for (let r of summaryDrift(after)) {
        if (r.kind == "change") { found = r; }
      }
      let changed = found;
      rdTrue(test, changed != null, "a change row");
      if (changed != null) {
        let parts = diff(rdOr(changed.left, ""), rdOr(changed.right, ""));
        var went = false;
        var arrived = false;
        for (let p of parts) {
          if (p.kind == "del" && readingContains(p.text, "ALPHA")) { went = true; }
          if (p.kind == "ins" && readingContains(p.text, "AMENDED")) { arrived = true; }
        }
        rdTrue(test, went, "ALPHA went");
        rdTrue(test, arrived, "AMENDED arrived");
      }
    }

Inventing a baseline would draw a diff that never happened.

    test("summary: a summary written before the source was kept draws no diff") { test =>
      let fx = summaryFixture();
      let s = rdSummarise(fx.db, fx.section, "It sets up alpha.", "stale", null);
      rdFalse(test, summaryCurrent(s), "stale");
      rdInt(test, summaryDrift(s).length, 0);
    }

## Asking, with the model's answer canned

    let sectionReply(): String throws Bubble {
      rdToolReply("report_section", "{\"summary\":\"It opens with ALPHA and a long run of words.\",\"covers\":[\"ALPHA\",\"monad transformers\"],\"follows_from\":[],\"sets_up\":\"The second section.\"}")
    }

    test("summary: ask stores the summary and everything it was made from") { test =>
      let fx = summaryFixture();
      let llm = llmFake([sectionReply()]);
      let r = summaryAsk(fx.db, llm, fx.work, fx.section);
      rdText(test, rdOr(r.error, "ok"), "ok");
      let s = r.ok;
      rdTrue(test, s != null, "stored");
      if (s != null) {
        rdText(test, rdOr(s.summary, "<none>"), "It opens with ALPHA and a long run of words.");
        rdText(test, rdJoin(s.summaryCovers), "ALPHA");
        rdText(test, rdJoin(s.summaryDropped), "covers: \"monad transformers\" is not in the section");
        rdText(test, rdOr(s.summarySetsUp, "<none>"), "The second section.");
        rdInt(test, s.summaryFollows.length, 0);
        rdText(test, rdOr(s.summaryBody, "<none>"), fx.section.body);
        rdText(test, rdOr(s.summaryFingerprint, "<none>"), summaryFingerprint(fx.section));
        rdTrue(test, s.summarisedAt != null, "a time");
        rdTrue(test, summaryCurrent(s), "current");
      }
      rdInt(test, versionsOf(fx.db, versionsWorkTopic(fx.work.id)), 1);
    }

    test("summary: the request carries the spine, the section and the limits") { test =>
      let fx = summaryFixture();
      let llm = llmFake([sectionReply()]);
      summaryAsk(fx.db, llm, fx.work, fx.section);
      rdSent(test, llm, "Draft: Draft\\n\\nThe sections of this draft, in order:\\n1. One  <- THIS ONE\\n2. Two\\n\\nTHE SECTION TO SUMMARISE — 1. One:\\n\\nALPHA the first paragraph.");
      rdSent(test, llm, "report_section");
      rdSent(test, llm, "\"temperature\":0.2");
      rdSent(test, llm, "\"reasoning_effort\":\"low\"");
      rdSent(test, llm, "\"max_tokens\":25200");
      rdSent(test, llm, "You summarise one section of a draft for its own writer");
    }

    test("summary: the second section's request carries the first's summary") { test =>
      let fx = summaryFixture();
      rdSummarise(fx.db, fx.section, "It establishes alpha.", null, null);
      let second = worksListSections(fx.db, fx.work.id)[1];
      let llm = llmFake([sectionReply()]);
      summaryAsk(fx.db, llm, fx.work, second);
      rdSent(test, llm, "The section before this one (1. One) was summarised as:\\nIt establishes alpha.");
    }

    test("summary: a reply with an empty summary stores nothing") { test =>
      let fx = summaryFixture();
      let llm = llmFake([rdToolReply("report_section", "{\"summary\":\"  \",\"covers\":[],\"follows_from\":[],\"sets_up\":\"\"}")]);
      let r = summaryAsk(fx.db, llm, fx.work, fx.section);
      rdText(test, rdOr(r.error, "ok"), "no_summary");
      rdTrue(test, rdSection(fx.db, fx.section.id).summary == null, "nothing stored");
      rdInt(test, versionsOf(fx.db, versionsWorkTopic(fx.work.id)), 0);
    }

    test("summary: a failed call is reported and stores nothing") { test =>
      let fx = summaryFixture();
      let llm = llmFakeScript([new LlmFakeResponse(400, "{\"error\":\"bad\"}")]);
      let r = summaryAsk(fx.db, llm, fx.work, fx.section);
      rdText(test, rdOr(r.error, "ok"), "http");
      rdTrue(test, r.ok == null, "nothing");
      let cut = llmFake(["{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"x\"},\"finish_reason\":\"length\"}]}"]);
      rdText(test, rdOr(summaryAsk(fx.db, cut, fx.work, fx.section).error, "ok"), "length");
    }

    test("summary: only the first twelve thousand characters go to the model") { test =>
      let fx = summaryFixture();
      let long = rdWithBody(fx.section, "${rdRepeat("a", 12000)}ZZZ");
      let llm = llmFake([sectionReply()]);
      summaryAsk(fx.db, llm, fx.work, long);
      rdSentNot(test, llm, "ZZZ");
      rdSent(test, llm, rdRepeat("a", 100));
    }

The fingerprint check: ask only when the summary has stopped describing the text.

    test("summary: ensure asks only when the summary is stale") { test =>
      let fx = summaryFixture();
      let llm = llmFake([sectionReply(), sectionReply()]);
      let first = summaryEnsure(fx.db, llm, fx.work, fx.section);
      rdCalls(test, llm, 1);
      let s = first.ok;
      if (s != null) {
        let again = summaryEnsure(fx.db, llm, fx.work, s);
        rdCalls(test, llm, 1);
        rdTrue(test, again.ok != null, "returned as it was");
        let edited = amend(fx, s);
        summaryEnsure(fx.db, llm, fx.work, edited);
        rdCalls(test, llm, 2);
      } else {
        rdTrue(test, false, "the first ask stored");
      }
    }

    test("summary: run reads the work itself, and section finds one by ordinal") { test =>
      let fx = summaryFixture();
      let llm = llmFake([sectionReply()]);
      let r = summaryRun(fx.db, llm, fx.section);
      rdTrue(test, r.ok != null, "stored");
      let two = summarySection(fx.db, fx.work.id, 2);
      rdTrue(test, two != null, "section 2");
      if (two != null) { rdText(test, two.title, "Two"); }
      rdTrue(test, summarySection(fx.db, fx.work.id, 9) == null, "no section 9");
    }
