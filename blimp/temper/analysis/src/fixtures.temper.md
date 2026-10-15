# Fixtures for the Read and the decision graph

A three-section draft whose quotes are the ones `HARD.beats.json` in
`test/fixtures/llm` carries, and canned model replies in the shapes the notes
give: a tool call for the beats, a JSON object for the spine and for the weave.

    let { Db, dbOpen } = import("db/src");
    let { Scope } = import("accounts/src");
    let { LlmClient, llmFakeScript, LlmFakeResponse, llmRequests } = import("llm/src");
    let { versionsOf, versionsWorkTopic } = import("runs/src");
    let { JsonTextProducer } = import("std/json");
    let { Work, Section, GraphNode, worksListNodes } = import("works/src");
    let { sysJoin } = import("sys/src");

    class AnFx(public db: Db, public scope: Scope, public work: Work, public sections: List<Section>) {}

    let readFiller(): String { repeated("word ", 260) }

    let readBody(): String {
      "# The window\n\nShe had been standing at the window for an hour before anyone noticed. The kettle went cold on the counter, and nobody moved to fill it again.\n\n${readFiller()}\n\n# The thermostat\n\nHer father had installed the thermostat himself the winter before, and he never trusted it. It kept a single promise, to hold the hallway at nineteen degrees, and it kept that promise with total loyalty and no understanding.\n\n${readFiller()}\n\n# The telephone\n\nWhen the telephone finally rang, it was her brother who crossed the room, because he was the only one who had stopped pretending not to wait. Nobody had noticed that either, and she crossed the kitchen and filled it, because it was the one thing in the room that she knew how to do.\n\n${readFiller()}\n"
    }

    let fxWith(title: String, body: String): AnFx throws Bubble {
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let work = makeWork(db, me, title, body);
      new AnFx(db, me, work, sectionsOf(db, work))
    }

    let fxRead(): AnFx throws Bubble { fxWith("The Long Wait", readBody()) }

    let fxGraph(): AnFx throws Bubble {
      let body = "Chapter 1\n\nShe had been standing at the window for an hour before anyone noticed. ${repeated("word ", 300)}";
      fxWith("W", body)
    }

## Replies

    class FxBeat(public title: String, public note: String, public quote: String) {}

    let beatsArgs(beats: List<FxBeat>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("beats");
      p.startArray();
      var k_b = 0;
      while (k_b < beats.length) {
        let b = beats[k_b];
        p.startObject();
        p.objectKey("note");
        p.stringValue(b.note);
        p.objectKey("quote");
        p.stringValue(b.quote);
        p.objectKey("title");
        p.stringValue(b.title);
        p.endObject();
        k_b += 1;
      }
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

    let beatsReply(beats: List<FxBeat>): String throws Bubble {
      fakeCalls([new FakeCall("record_beats", beatsArgs(beats))])
    }

    let q1(): String { "She had been standing at the window for an hour before anyone noticed." }
    let q2(): String { "The kettle went cold on the counter, and nobody moved to fill it again." }
    let q3(): String { "Her father had installed the thermostat himself the winter before, and he never trusted it." }
    let q4(): String { "It kept a single promise, to hold the hallway at nineteen degrees, and it kept that promise with total loyalty and no understanding." }
    let q5(): String { "When the telephone finally rang, it was her brother who crossed the room, because he was the only one who had stopped pretending not to wait." }
    let q6(): String { "Nobody had noticed that either, and she crossed the kitchen and filled it, because it was the one thing in the room that she knew how to do." }

    let sectionOneReply(): String throws Bubble {
      beatsReply([
        new FxBeat("They set the scene at the window", "Opens on stillness.", q1()),
        new FxBeat("They let the kettle go cold", "A small domestic failure.", q2()),
      ])
    }

    let sectionTwoReply(): String throws Bubble {
      beatsReply([
        new FxBeat("They introduce the father and his distrust of the thermostat", "Introduces the thermostat.", q3()),
        new FxBeat("They say what the thermostat can and cannot know", "The central metaphor.", q4()),
      ])
    }

    let sectionThreeReply(): String throws Bubble {
      beatsReply([
        new FxBeat("They have the brother answer the telephone", "Breaks the waiting.", q5()),
        new FxBeat("They close on the kettle being filled", "Pays off the cold kettle.", q6()),
      ])
    }

    class FxTitled(public title: String, public note: String, public status: String?) {}

    let spineContent(
      impression: String, spine: List<FxTitled>, threads: List<FxTitled>, questions: List<String>,
    ): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("first_impression");
      p.stringValue(impression);
      p.objectKey("questions");
      p.startArray();
      var kq = 0; while (kq < questions.length) { p.stringValue(questions[kq]); kq += 1; }
      p.endArray();
      p.objectKey("spine");
      p.startArray();
      var k_s = 0;
      while (k_s < spine.length) {
        let s = spine[k_s];
        p.startObject();
        p.objectKey("note");
        p.stringValue(s.note);
        p.objectKey("title");
        p.stringValue(s.title);
        p.endObject();
        k_s += 1;
      }
      p.endArray();
      p.objectKey("threads");
      p.startArray();
      var k_t = 0;
      while (k_t < threads.length) {
        let t = threads[k_t];
        p.startObject();
        p.objectKey("note");
        p.stringValue(t.note);
        p.objectKey("status");
        let st = t.status;
        if (st != null) { p.stringValue(st); } else { p.nullValue(); }
        p.objectKey("title");
        p.stringValue(t.title);
        p.endObject();
        k_t += 1;
      }
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

    let spineReply(): String throws Bubble {
      fakeContent(spineContent(
        "A household waits for news it dreads.",
        [
          new FxTitled("The household waits at the window", "Establishes the stillness.", null),
          new FxTitled("The kettle goes cold", "The first small failure.", null),
          new FxTitled("The telephone rings", "The brother ends the waiting.", null),
        ],
        [
          new FxTitled("The kettle", "Cold in section one, filled in section three.", "carried"),
          new FxTitled("The thermostat", "Appears in section two only.", "thin"),
          new FxTitled("The telephone", "Set early, answered at the end.", null),
        ],
        ["What does the thermostat passage do for a reader?", "Why is her name never given?"],
      ))
    }

    class FxEdge(public from: Int, public to: Int, public kind: String, public why: String) {}

    let weaveContent(edges: List<FxEdge>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("edges");
      p.startArray();
      var k_e = 0;
      while (k_e < edges.length) {
        let e = edges[k_e];
        p.startObject();
        p.objectKey("from");
        p.int32Value(e.from);
        p.objectKey("type");
        p.stringValue(e.kind);
        p.objectKey("to");
        p.int32Value(e.to);
        p.objectKey("why");
        p.stringValue(e.why);
        p.endObject();
        k_e += 1;
      }
      p.endArray();
      p.endObject();
      p.toJsonString()
    }

    let weaveReply(): String throws Bubble {
      fakeContent(weaveContent([
        new FxEdge(2, 6, "pays_off", "The kettle that goes cold is the kettle that is filled."),
        new FxEdge(3, 4, "develops", "The thermostat is introduced, then explained."),
        new FxEdge(1, 5, "pays_off", "The waiting ends when the brother answers."),
      ]))
    }

    let ok(body: String): LlmFakeResponse { new LlmFakeResponse(200, body) }

    let fullScript(): LlmClient throws Bubble {
      llmFakeScript([
        ok(sectionOneReply()), ok(sectionTwoReply()), ok(sectionThreeReply()),
        ok(spineReply()), ok(weaveReply()),
      ])
    }

    let nodesOfType(db: Db, work: Work, kind: String): List<GraphNode> throws Bubble {
      worksListNodes(db, work.id, kind, null, null)
    }

    let bumps(db: Db, work: Work): Int throws Bubble {
      versionsOf(db, versionsWorkTopic(work.id))
    }

    let requestsText(llm: LlmClient): String {
      sysJoin(llmRequests(llm), "\n")
    }
