# Tests for the link chat

Ported from `link_chat_test.exs` in `notes/tests.md` (5 tests): the card, the
prompt, the labels. Two of those five do not carry over: "the module offers no
way to store a turn" asserts that `append/3`, `history/1` and `conversation/1`
are not exported, which here is true by there being no such function to name,
and "a conversation row still has to belong to a draft" tests
`Conversation.changeset`, which is the works context's. The ask itself, which
the Elixir tests never reached, is tested through a fake model.

The conversation about a pair: what it is handed.

    class LinksChatFx(public f: LinksFx, public link: Link) {}

First and Second, each with a beat quoting "A sentence long enough", linked,
with a summary and one tension edge between the beats.

    let chatFixture(): LinksChatFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "writer@example.com");
      let a = makeLinkedPoint(db, me, "First");
      let b = makeLinkedPoint(db, me, "Second");
      let c = makeLinkedPoint(db, me, "Third");
      let made = linksLinkOrBubble(linksGetOrCreate(db, a.work.id, b.work.id).ok);
      let link = linksLinkOrBubble(linksSetStatus(db, made, "linked", linksAttrsSummary("B answers A.")).ok);
      linksStoreEdges(db, link, oneEdge(a.node.id, b.node.id, "tension", "They pull apart on pace."), linkerTypes());
      new LinksChatFx(new LinksFx(db, me, a.work, b.work, c.work, a.node, b.node, c.node, link), link)
    }

    let makeLinkedPoint(db: Db, me: Scope, title: String): LinksMade throws Bubble {
      let w = readWork(db, makeWork(db, me, title, "# ${title}\n\nA sentence long enough to make a section of it.\n\n${repeated("word ", 200)}"));
      new LinksMade(w, addNode(db, w, firstSection(db, w), "beat", "a beat in ${title}", "A sentence long enough"))
    }

    let cardOf(c: LinksChatFx): String throws Bubble { linksChatCard(c.f.db, c.link) }

## What it is handed

    test("the card has both maps, every edge, and the reason each was drawn") { test =>
      let c = chatFixture();
      let card = cardOf(c);
      expectHas(test, card, "First");
      expectHas(test, card, "Second");
      expectHas(test, card, "B answers A.");
      expectHas(test, card, "--tension-->");
      expectHas(test, card, "They pull apart on pace.");
      expectHas(test, card, "A sentence long enough");
    }

    test("the sides are labelled, so it can tell which document is which") { test =>
      let c = chatFixture();
      let card = cardOf(c);
      expectHas(test, card, "A:");
      expectHas(test, card, "B:");
      expectHas(test, card, "# MAP OF A");
      expectHas(test, card, "# MAP OF B");
    }

    test("the prompt forbids the things the product does not do") { test =>
      let p = linksChatPrompt();
      expectHas(test, p, "do not write prose");
      expectHas(test, p, "do not rank them");
      expectHas(test, p, "An edge you were not given does not exist");
    }

    test("the card, in full") { test =>
      let c = chatFixture();
      let a = c.f.aNode.id.toString();
      let b = c.f.bNode.id.toString();
      let want = "# THE PAIR\n\nA: First — ${c.f.a.wordCount.toString()} words\nB: Second — ${c.f.b.wordCount.toString()} words\n\nHow they relate, as already established:\nB answers A.\n\n# THE EDGES BETWEEN THEM (1)\n\n- A:[${a}] a beat in First --tension--> B:[${b}] a beat in Second\n    They pull apart on pace.\n\n# MAP OF A: First\n\n## beat\n- [${a}] (§1) a beat in First\n    \"A sentence long enough\"\n\n# MAP OF B: Second\n\n## beat\n- [${b}] (§1) a beat in Second\n    \"A sentence long enough\"\n";
      expectText(test, cardOf(c), want);
    }

    test("the card of a link with no summary and no edges has the blank lines the template leaves") { test =>
      let f = linksFixture();
      let card = linksChatCard(f.db, f.link);
      expectHas(test, card, "words\n\n\n# THE EDGES BETWEEN THEM (0)\n\n\n\n# MAP OF A: First");
    }

    test("the map groups nodes by type in ascending order of the type") { test =>
      let c = chatFixture();
      addNode(c.f.db, c.f.a, null, "thread", "a thread", null);
      addNode(c.f.db, c.f.a, null, "question", "an open question", "line one\n  line   two");
      addNode(c.f.db, c.f.a, null, "spine", "the spine", null);
      let card = cardOf(c);
      expectBefore(test, card, "## beat", "## question");
      expectBefore(test, card, "## question", "## spine");
      expectBefore(test, card, "## spine", "## thread");
      expectHas(test, card, "- [");
      expectHas(test, card, "an open question\n    \"line one line two\"\n");
    }

    test("a quote on a card is cut at 160 characters") { test =>
      let c = chatFixture();
      addNode(c.f.db, c.f.a, null, "note", "long", repeated("x", 400));
      expectHas(test, cardOf(c), "\"${repeated("x", 160)}\"\n");
      expectLacks(test, cardOf(c), repeated("x", 161));
    }

    test("the passes list says what the chat is") { test =>
      let passes = linksChatPasses();
      expectInt(test, passes.length, 1);
      expectText(test, passes[0].id, "link_chat");
      expectText(test, passes[0].name, "Talking about a pair");
      expectText(test, passes[0].runs, "per message, on a linked pair");
      expectText(test, passes[0].produces, "answers about how two drafts relate");
      expectText(test, passes[0].prompt, linksChatPrompt());
      expectText(test, passes[0].model, "deepseek-flash");
    }

## The cited card

    test("nothing cited is no card") { test =>
      let c = chatFixture();
      expectTrue(test, linksChatCited(c.f.db, c.link, []) == null, "empty");
      expectTrue(test, linksChatCited(c.f.db, c.link, [999999]) == null, "not an edge of this link");
    }

    test("a cited edge hands over both passages in full") { test =>
      let c = chatFixture();
      let edges = linksEdges(c.f.db, c.link);
      let card = linksChatCited(c.f.db, c.link, [edges[0].edge.id]);
      expectTrue(test, card != null, "a card");
      if (card != null) {
        expectText(test, card.role, "system");
        let want = "The reader is pointing at these connections and wants to talk about them. Both passages are given in full — quote from them freely.\n\n## TENSION\nWhy it was drawn: They pull apart on pace.\n\n### A — a beat in First\nA sentence long enough to make a section of it.\n\n### B — a beat in Second\nA sentence long enough to make a section of it.\n";
        expectText(test, card.content, want);
      }
    }

    test("the type is shown in capitals with the underscore as a space") { test =>
      let c = chatFixture();
      linksClearEdges(c.f.db, c.link);
      linksStoreEdges(c.f.db, c.link, oneEdge(c.f.aNode.id, c.f.bNode.id, "pays_off", "It lands."), linkerTypes());
      let edges = linksEdges(c.f.db, c.link);
      let card = linksChatCited(c.f.db, c.link, [edges[0].edge.id]);
      if (card != null) { expectHas(test, card.content, "## PAYS OFF\n"); }
    }

## Asking

    test("the answer is the text of the reply") { test =>
      let c = chatFixture();
      let fake = llmFake([replyText("They part on pace.")]);
      let r = linksChatAsk(c.f.db, fake, c.link, [], "How do they differ?");
      expectText(test, orNone(r.ok), "They part on pace.");
      expectTrue(test, r.error == null, "no error");
    }

    test("the messages run system prompt, card, history, question, then the cited passages") { test =>
      let c = chatFixture();
      let fake = llmFake([replyText("Fine.")]);
      let history = [new LlmMessage("user", "FIRSTQUESTION"), new LlmMessage("assistant", "FIRSTANSWER")];
      let edges = linksEdges(c.f.db, c.link);
      linksChatAskCited(c.f.db, fake, c.link, history, "SECONDQUESTION", [edges[0].edge.id]);
      let body = lastRequest(test, fake);
      expectBefore(test, body, "You are reading two manuscripts", "# THE PAIR");
      expectBefore(test, body, "# THE PAIR", "FIRSTQUESTION");
      expectBefore(test, body, "FIRSTQUESTION", "FIRSTANSWER");
      expectBefore(test, body, "FIRSTANSWER", "SECONDQUESTION");
      expectBefore(test, body, "SECONDQUESTION", "The reader is pointing at these connections");
    }

    test("the call is effort low, temperature 0.5, 4000 tokens, and carries no tools") { test =>
      let c = chatFixture();
      let fake = llmFake([replyText("Fine.")]);
      linksChatAsk(c.f.db, fake, c.link, [], "Q?");
      let body = lastRequest(test, fake);
      expectHas(test, body, "\"reasoning_effort\":\"low\"");
      expectHas(test, body, "\"temperature\":0.5");
      expectHas(test, body, "\"max_tokens\":28000");
      expectLacks(test, body, "\"tools\"");
    }

    test("an empty question adds no turn: the history already ends with it") { test =>
      let c = chatFixture();
      let fake = llmFake([replyText("Fine.")]);
      linksChatAsk(c.f.db, fake, c.link, [new LlmMessage("user", "ALREADYTHERE")], "  ");
      let body = lastRequest(test, fake);
      expectInt(test, body.split("ALREADYTHERE").length, 2);
    }

    test("a reply with no text is empty_reply, and a client error passes through") { test =>
      let c = chatFixture();
      let empty = linksChatAsk(c.f.db, llmFake([replyNothing()]), c.link, [], "Q?");
      expectTrue(test, empty.ok == null, "no answer");
      expectText(test, orNone(empty.error), "empty_reply");
      let blank = linksChatAsk(c.f.db, llmFake([replyText("")]), c.link, [], "Q?");
      expectText(test, orNone(blank.error), "empty_reply");
      let broken = linksChatAsk(c.f.db, llmFakeScript([new LlmFakeResponse(401, "no")]), c.link, [], "Q?");
      expectHas(test, orNone(broken.error), "http");
    }

    test("nothing is stored by asking") { test =>
      let c = chatFixture();
      let before = countOf(c.f.db, "SELECT count(*) AS n FROM messages");
      linksChatAsk(c.f.db, llmFake([replyText("Fine.")]), c.link, [], "Q?");
      expectInt(test, countOf(c.f.db, "SELECT count(*) AS n FROM messages"), before);
      expectInt(test, countOf(c.f.db, "SELECT count(*) AS n FROM conversations"), 0);
    }
