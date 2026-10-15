# Prompts and tool schemas

Copied byte for byte from `Marginalia.Stacks` (`@prompt`, `@deep_prompt`,
`@compose_prompt`, `@tool`, `@deep_tool`, `@outline_tool`, `@part_tool`). Each
system prompt ends with the newline the Elixir heredoc ends with.

Every call is a forced tool call, not prose asked to look like JSON. The
schemas are written with the JSON producer, with object keys in the order
Jason wrote Elixir's small maps (alphabetical), because that is the order the
model was shown them in.

    let { JsonTextProducer } = import("std/json");
    let { LlmTool } = import("llm/src");

## System prompts

    export let stacksReadPrompt(): String {
      "You read one document out of an ordered series that together build one thing, and report what it contributes to *building that thing* — not what happened to the project that produced it.\n\nThe reader you are writing for intends to build the same thing themselves, in this order, and has seen none of the other documents.\n\nQuotes must be copied character for character. A program checks each one against the document and drops what it cannot find, so an approximate quote is a discarded field. Never write an excerpt yourself.\n\nReport by calling report_step.\n"
    }

    export let stacksDeepPrompt(): String {
      "You are reading one step of a series a second time, and this time you have the whole series in front of you — including everything that comes after it.\n\nThe first reading could not see forwards. It was told only what came before each step, which is the reading a learner follows, and it means nothing it said could account for what a later step changes. Your job is the part it could not do.\n\nDo not restate the first reading. Say what only the whole chain reveals: how the thing actually works underneath, what must be got right here because something later leans on it, and whether a later step walks this back.\n\nQuotes must be copied character for character. A program checks each one and drops what it cannot find.\n\nReport by calling deepen_step.\n"
    }

    export let stacksComposePrompt(): String {
      "You are writing the long-form telling of how a thing gets built, from notes already checked line by line against the documents they came from. Your job is composition, not extraction: everything you need is in front of you, and anything not in front of you is something you do not know.\n\nWrite for someone about to build the same thing. They want the shape of the work and the order of it, and above all the places where the obvious move is wrong.\n\nLead with the load-bearing or surprising fact, never with \"this guide will\". Explain why the obvious version is wrong wherever the notes say so — that is usually the most valuable sentence available to you. Say plainly what is still undone. No marketing language, no bullet padding, no emoji.\n"
    }

## Schema pieces

A property of a given type with its description: `{"description", "type"}`.

    let stacksSchemaProp(p: JsonTextProducer, key: String, kind: String, description: String): Void {
      p.objectKey(key);
      p.startObject();
      p.objectKey("description");
      p.stringValue(description);
      p.objectKey("type");
      p.stringValue(kind);
      p.endObject();
    }

An array of integers with its description: `{"description", "items": {"type":
"integer"}, "type": "array"}`.

    let stacksSchemaIntArray(p: JsonTextProducer, key: String, description: String): Void {
      p.objectKey(key);
      p.startObject();
      p.objectKey("description");
      p.stringValue(description);
      p.objectKey("items");
      p.startObject();
      p.objectKey("type");
      p.stringValue("integer");
      p.endObject();
      p.objectKey("type");
      p.stringValue("array");
      p.endObject();
    }

    let stacksSchemaRequired(p: JsonTextProducer, names: List<String>): Void {
      p.objectKey("required");
      p.startArray();
      var i = 0;
      while (i < names.length) { p.stringValue(names[i]); i += 1; }
      p.endArray();
    }

## report_step

    export let stacksReportStepSchema(): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("properties");
      p.startObject();
      stacksSchemaProp(p, "capability", "string", "One line, present tense, naming what the thing can do after this document that it could not before. A property of the thing being built (\"a class becomes an actor\"), never an event (\"added actor support\").");
      p.objectKey("excerpts");
      p.startObject();
      p.objectKey("description");
      p.stringValue("Passages worth showing a learner. Quote a line that is already in the document; the passage around it is fetched for you. Never write one.");
      p.objectKey("items");
      p.startObject();
      p.objectKey("properties");
      p.startObject();
      p.objectKey("caption");
      p.startObject();
      p.objectKey("type");
      p.stringValue("string");
      p.endObject();
      p.objectKey("quote");
      p.startObject();
      p.objectKey("type");
      p.stringValue("string");
      p.endObject();
      p.endObject();
      stacksSchemaRequired(p, ["quote", "caption"]);
      p.objectKey("type");
      p.stringValue("object");
      p.endObject();
      p.objectKey("maxItems");
      p.int32Value(2);
      p.objectKey("type");
      p.stringValue("array");
      p.endObject();
      stacksSchemaProp(p, "lesson", "string", "Two or three sentences telling someone building this themselves what to do at this point. Imperative. No project history, no \"we\".");
      stacksSchemaProp(p, "pitfall", "string", "The obvious approach that is wrong here and why, in one or two sentences. Empty string if the document does not say.");
      stacksSchemaProp(p, "pitfall_quote", "string", "The exact sentence from the document establishing the pitfall, copied character for character. Empty string if there is no pitfall.");
      stacksSchemaIntArray(p, "requires", "Numbers of earlier documents this one could not have been done without. Empty if it stands alone.");
      p.endObject();
      stacksSchemaRequired(p, ["capability", "requires", "lesson", "pitfall", "pitfall_quote", "excerpts"]);
      p.objectKey("type");
      p.stringValue("object");
      p.endObject();
      p.toJsonString()
    }

    export let stacksReportStepTool(): LlmTool throws Bubble {
      new LlmTool(
        "report_step",
        "Report what this document contributes to building the thing the series builds.",
        stacksReportStepSchema(),
      )
    }

## deepen_step

    export let stacksDeepenStepSchema(): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("properties");
      p.startObject();
      stacksSchemaProp(p, "mechanism", "string", "How this actually works, three or four sentences, below the level of what to do. Name the moving parts and how they fit. Concrete, from the document.");
      stacksSchemaProp(p, "revised_by", "integer", "The number of a LATER step that corrects, replaces or materially changes what this one established. 0 if none does.");
      stacksSchemaProp(p, "revision", "string", "What that later step changes about this one, in one or two sentences. Empty string if nothing revises it.");
      stacksSchemaProp(p, "revision_quote", "string", "The exact sentence from the LATER step's own summary establishing the revision, copied character for character. Empty string if there is no revision.");
      stacksSchemaProp(p, "watch_for", "string", "What to get right at this step because a later step leans on it, naming which. Empty string if nothing later depends on the details here.");
      p.endObject();
      stacksSchemaRequired(p, ["mechanism", "watch_for", "revised_by", "revision", "revision_quote"]);
      p.objectKey("type");
      p.stringValue("object");
      p.endObject();
      p.toJsonString()
    }

    export let stacksDeepenStepTool(): LlmTool throws Bubble {
      new LlmTool(
        "deepen_step",
        "Report what can only be said about this step with the whole series in hand.",
        stacksDeepenStepSchema(),
      )
    }

## outline_story

    export let stacksOutlineStorySchema(): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("properties");
      p.startObject();
      stacksSchemaProp(p, "closing", "string", "One or two paragraphs. What the reader has at the end, and what is honestly still undone.");
      stacksSchemaProp(p, "opening", "string", "Two or three paragraphs. What is being built, what makes it hard, and what the reader will have at the end. Lead with the load-bearing or surprising fact, never with \"this guide covers\".");
      p.objectKey("parts");
      p.startObject();
      p.objectKey("description");
      p.stringValue("The telling in parts, in the order the work is done. Every step must appear in exactly one part. Aim for parts of five to fifteen steps.");
      p.objectKey("items");
      p.startObject();
      p.objectKey("properties");
      p.startObject();
      stacksSchemaProp(p, "heading", "string", "A claim, not a label.");
      p.objectKey("steps");
      p.startObject();
      p.objectKey("items");
      p.startObject();
      p.objectKey("type");
      p.stringValue("integer");
      p.endObject();
      p.objectKey("type");
      p.stringValue("array");
      p.endObject();
      p.endObject();
      stacksSchemaRequired(p, ["heading", "steps"]);
      p.objectKey("type");
      p.stringValue("object");
      p.endObject();
      p.objectKey("type");
      p.stringValue("array");
      p.endObject();
      stacksSchemaProp(p, "title", "string", "A title for the whole telling. A claim, not a label.");
      p.endObject();
      stacksSchemaRequired(p, ["title", "opening", "closing", "parts"]);
      p.objectKey("type");
      p.stringValue("object");
      p.endObject();
      p.toJsonString()
    }

    export let stacksOutlineStoryTool(): LlmTool throws Bubble {
      new LlmTool(
        "outline_story",
        "Divide the series into the parts the telling will be written in.",
        stacksOutlineStorySchema(),
      )
    }

## write_part

    export let stacksWritePartSchema(): String throws Bubble {
      let p = new JsonTextProducer();
      p.startObject();
      p.objectKey("properties");
      p.startObject();
      stacksSchemaProp(p, "prose", "string", "Three to six paragraphs telling this stretch as continuous prose. Say what gets built and in what order, and name the pitfalls where they bite. Do not enumerate the steps one by one — the reader already has that list.");
      stacksSchemaProp(p, "turn", "string", "The thing in this stretch a reader would not have guessed — a pitfall, or a place a later step walks an earlier one back. One or two sentences. Empty string if this stretch has none.");
      p.endObject();
      stacksSchemaRequired(p, ["prose", "turn"]);
      p.objectKey("type");
      p.stringValue("object");
      p.endObject();
      p.toJsonString()
    }

    export let stacksWritePartTool(): LlmTool throws Bubble {
      new LlmTool(
        "write_part",
        "Write one part of the telling.",
        stacksWritePartSchema(),
      )
    }
