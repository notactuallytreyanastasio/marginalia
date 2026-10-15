# Talking to the model, reading what comes back

`LLM.call_tool/1` and the small amount of JSON handling the three validators
share. The client is passed in (`LlmClient`), never made here, so a test hands
over `llmFake([...])`.

    let { JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonNumeric, JsonBoolean,
          JsonNull, JsonTextProducer, parseJson } = import("std/json");
    let { LlmClient, LlmCall, LlmMessage, LlmTool, LlmError, llmProvider, llmConfigFromEnv } = import("llm/src");
    let { sysJoin } = import("sys/src");

## Calling a tool

One tool, offered to the model, and the first call it makes decoded as a JSON
object. `effort` is `"low"`, `"high"` or `"none"`; the tool choice is forced to
the tool only when `effort` is `"none"` (DeepSeek refuses a forced choice while
it reasons) and `auto` otherwise.

A reply that finished for length is the `length` error and is not retried by
the client. A reply that made no call is `no_tool_call`; arguments that are not
a JSON object are `invalid_json`.

    let readingCallTool(
      llm: LlmClient, tool: LlmTool, model: String?, effort: String, temperature: Float64,
      maxTokens: Int, system: String, user: String,
    ): ReadingToolReply {
      let choice: String? = if (effort == "none") {
        "{\"type\":\"function\",\"function\":{\"name\":\"${tool.name}\"}}"
      } else {
        null
      };
      let call = new LlmCall(
        [new LlmMessage("system", system), new LlmMessage("user", user)],
        model, effort, maxTokens, temperature, false, [tool], choice, 0,
      );
      let result = llm.chat(call);
      let reply = result.ok;
      if (reply != null) {
        if (reply.toolCalls.length == 0) {
          new ReadingToolReply(null, "no_tool_call", "the reply made no tool call")
        } else {
          let args = reply.toolCalls[0].argumentsJson;
          let parsed: JsonSyntaxTree? = parseJson(args) orelse null;
          let obj = readingObject(parsed);
          if (obj != null) {
            new ReadingToolReply(obj, null, null)
          } else {
            new ReadingToolReply(null, "invalid_json", "the arguments are not a JSON object")
          }
        }
      } else {
        let err = result.err;
        if (err != null) {
          new ReadingToolReply(null, err.kind, err.detail)
        } else {
          new ReadingToolReply(null, "transport", "the client answered nothing")
        }
      }
    }

The fast model of the configured provider, for the section summaries. The
default model is `null` in a call, which the client fills in.

    let readingFastModel(): String {
      llmProvider(llmConfigFromEnv().provider).fastModel
    }

## Reading JSON

    let readingObject(t: JsonSyntaxTree?): JsonObject? {
      if (t is JsonObject) { t } else { null }
    }

    let readingProp(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

A string property, or null when it is absent or not a string.

    let readingStr(t: JsonSyntaxTree?, key: String): String? {
      let v = readingProp(t, key);
      if (v is JsonString) { v.content } else { null }
    }

The elements of an array property; no array is an empty list.

    let readingElements(t: JsonSyntaxTree?, key: String): List<JsonSyntaxTree> {
      let v = readingProp(t, key);
      if (v is JsonArray) { v.elements } else { [] }
    }

`String.trim/1` of a string, `""` for anything else (`trimmed/1` in the
Elixir).

    let readingTrimmed(t: JsonSyntaxTree?): String {
      if (t is JsonString) { readingTrim(t.content) } else { "" }
    }

An integer, as the JSON parser reads one: a number whose text has no point and
no exponent. Floats are not integers, as in Elixir (`2.0` is not `2`).

    let readingJsonInt(t: JsonSyntaxTree?): Int? {
      if (t is JsonNumeric) {
        let token = t.asJsonNumericToken();
        if (readingContains(token, ".") || readingContains(token, "e") || readingContains(token, "E")) {
          null
        } else {
          do { t.asInt32() } orelse null
        }
      } else {
        null
      }
    }

`inspect/1` of a decoded JSON value, for the reasons the validators write.

    let readingInspect(t: JsonSyntaxTree): String {
      if (t is JsonString) {
        readingInspectString(t.content)
      } else if (t is JsonNumeric) {
        t.asJsonNumericToken()
      } else if (t is JsonBoolean) {
        if (t.content) { "true" } else { "false" }
      } else if (t is JsonNull) {
        "nil"
      } else if (t is JsonArray) {
        let parts = t.elements.map { (e: JsonSyntaxTree): String => readingInspect(e) };
        "[${sysJoin(parts, ", ")}]"
      } else {
        let p = new JsonTextProducer();
        t.produce(p);
        do { p.toJsonString() } orelse "?"
      }
    }

    let readingInspectList(items: List<JsonSyntaxTree>): String {
      let parts = items.map { (e: JsonSyntaxTree): String => readingInspect(e) };
      "[${sysJoin(parts, ", ")}]"
    }

The text of an array of objects, for the `jsonb[]` columns.

    let readingItemsText(items: List<JsonObject>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      var i = 0;
      while (i < items.length) {
        items[i].produce(p);
        i += 1;
      }
      p.endArray();
      p.toJsonString()
    }
