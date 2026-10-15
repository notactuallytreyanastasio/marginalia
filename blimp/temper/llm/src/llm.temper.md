# The model client

A port of `Marginalia.LLM` (`lib/marginalia/llm.ex`), which is the truth for
every number and every rule below. Two ideas carry over unchanged:

* `finish_reason: "length"` is a failure (kind `length`), never a success, and
  it is never retried: asking again for the same thing truncates again.
* `invalid_json` is a different failure from `rate_limited`, so a malformed
  reply is not retried three times as if it were congestion.

The two imports: std/json for the wire format, sys for the machine.

    let { JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonTextProducer,
          NullInterchangeContext, parseJson } = import("std/json");
    let { sysGetEnv, sysHttpStart, sysHttpAwait, sysNowMs, sysSleepMs } = import("sys/src");

## Values

    export class LlmMessage(public role: String, public content: String) {
      public var toolCallsJson: String? = null;
      public var toolCallId: String? = null;
    }

`parametersJson` is the JSON Schema object, as text; it is parsed and embedded,
never concatenated.

    export class LlmTool(
      public name: String,
      public description: String,
      public parametersJson: String,
    ) {}

`model` null means the provider's model. `effort` is `low`, `high` or `none`;
anything else (or null) leaves the provider default `low`. `maxTokens` is how
much *answer* the caller wants: the reasoning headroom is added on the wire.
`toolChoice` is `auto`, `none`, `required`, or a JSON object as text (the forced
form `{"type":"function","function":{"name":"x"}}`); null means `auto` when
tools are given. `timeoutMs` of 0 or less means the configured default.

    export class LlmCall(
      public messages: List<LlmMessage>,
      public model: String?,
      public effort: String?,
      public maxTokens: Int?,
      public temperature: Float64?,
      public json: Boolean,
      public tools: List<LlmTool>,
      public toolChoice: String?,
      public timeoutMs: Int,
    ) {}

    export class LlmToolCall(
      public id: String,
      public name: String,
      public argumentsJson: String,
    ) {}

`raw` is the whole response body, so `usage` and `reasoning_content` are there
for whoever wants them.

    export class LlmReply(
      public content: String?,
      public toolCalls: List<LlmToolCall>,
      public finishReason: String,
      public raw: String,
    ) {}

Kinds: `no_key`, `rate_limited` (HTTP 429), `length`, `invalid_json`, `http`
(any other non-2xx status, and a 200 without usable choices); 500, 502, 503 and 504 are `rate_limited` too, once the attempts are spent, `timeout`,
`transport`.

    export class LlmError(public kind: String, public detail: String) {}

Temper has no sum type for results, so this is two nullable fields. Exactly one
is set.

    export class Result<T, E>(public ok: T?, public err: E?) {}

    export let llmErrorText(e: LlmError): String { "${e.kind}: ${e.detail}" }

    export let llmSimpleCall(content: String): LlmCall {
      new LlmCall([new LlmMessage("user", content)], null, null, null, null,
        false, [], null, 0)
    }

## Providers

The table of `@providers`. Unknown names fall back to deepseek, as `resolve/1`.

    export class LlmProvider(
      public name: String,
      public label: String,
      public endpoint: String,
      public model: String,
      public fastModel: String,
      public tokensField: String,
      public effort: String,
      public headroom: Int,
    ) {}

    export let llmProvider(name: String): LlmProvider {
      if (name == "openai") {
        new LlmProvider("openai", "Sol 5", "https://api.openai.com/v1/chat/completions",
          "gpt-5.6-sol", "gpt-5.4-nano", "max_completion_tokens", "low", 24000)
      } else {
        new LlmProvider("deepseek", "DeepSeek Flash", "https://api.deepseek.com/chat/completions",
          "deepseek-flash", "deepseek-flash", "max_tokens", "low", 24000)
      }
    }

What goes on the wire for a caller asking for `asked` tokens of answer.

    export let llmTokenBudget(provider: String, asked: Int?): Int? {
      if (asked == null) { null } else { asked + llmProvider(provider).headroom }
    }

`endpoint` empty means the provider's own. `model` empty means the provider's.

    export class LlmConfig(
      public provider: String,
      public apiKey: String,
      public endpoint: String,
      public backoffMs: Int,
      public timeoutMs: Int,
      public model: String,
    ) {}

    let orElse(s: String?, fallback: String): String {
      if (s == null) { fallback } else { s }
    }

    let envInt(name: String, fallback: Int): Int {
      let v = sysGetEnv(name);
      if (v == null) { fallback } else { v.toInt32() orelse fallback }
    }

    export let llmConfigFromEnv(): LlmConfig {
      let wanted = orElse(sysGetEnv("MARGINALIA_LLM_PROVIDER"), "deepseek");
      let provider = if (wanted == "openai") { "openai" } else { "deepseek" };
      let keyVar = if (provider == "openai") { "OPENAI_API_KEY" } else { "DEEPSEEK_API_KEY" };
      new LlmConfig(
        provider,
        orElse(sysGetEnv(keyVar), ""),
        orElse(sysGetEnv("MARGINALIA_LLM_ENDPOINT"), ""),
        envInt("MARGINALIA_LLM_BACKOFF_MS", 250),
        envInt("MARGINALIA_LLM_TIMEOUT_MS", 300000),
        orElse(sysGetEnv("LLM_MODEL"), ""),
      )
    }

## The request body

Built with `JsonTextProducer`, so user text is escaped by the encoder and
never by us. Keys are emitted in alphabetical order, which is what Jason does
for an Elixir map, so a body here is byte-identical to the one Elixir sent.

    let writeMessage(p: JsonTextProducer, m: LlmMessage): Void {
      p.startObject();
      p.objectKey("content");
      let calls = m.toolCallsJson;
      if (calls != null && m.content == "") {
        p.nullValue();
      } else {
        p.stringValue(m.content);
      }
      p.objectKey("role");
      p.stringValue(m.role);
      let callId = m.toolCallId;
      if (callId != null) {
        p.objectKey("tool_call_id");
        p.stringValue(callId);
      }
      if (calls != null) {
        let parsed: JsonSyntaxTree? = parseJson(calls) orelse null;
        if (parsed != null) {
          p.objectKey("tool_calls");
          parsed.produce(p);
        }
      }
      p.endObject();
    }

    let isEffort(e: String): Boolean { e == "low" || e == "high" || e == "none" }

    let startsWithBrace(s: String): Boolean {
      s.hasIndex(String.begin) && s[String.begin] == 123
    }

    let failBody(kind: String, detail: String): Result<String, LlmError> {
      new Result<String, LlmError>(null, new LlmError(kind, detail))
    }

    export let llmRequestBody(config: LlmConfig, call: LlmCall): Result<String, LlmError> {
      let prov = llmProvider(config.provider);
      let schemas = new ListBuilder<JsonSyntaxTree>();
      for (let t of call.tools) {
        let parsed: JsonSyntaxTree? = parseJson(t.parametersJson) orelse null;
        if (parsed != null) {
          schemas.add(parsed);
        } else {
          return failBody("invalid_json", "parameters of tool ${t.name} are not JSON");
        }
      }
      var forced: JsonSyntaxTree? = null;
      let wantedChoice = call.toolChoice;
      var choiceWord: String? = null;
      if (wantedChoice != null) {
        if (startsWithBrace(wantedChoice)) {
          forced = parseJson(wantedChoice) orelse null;
          if (forced == null) {
            return failBody("invalid_json", "toolChoice is not JSON");
          }
        } else {
          choiceWord = wantedChoice;
        }
      } else if (!call.tools.isEmpty) {
        choiceWord = "auto";
      }
      let asked = llmTokenBudget(config.provider, call.maxTokens);
      let effort = call.effort;
      let callModel = call.model;
      var model: String = prov.model;
      if (callModel != null) {
        model = callModel;
      } else if (config.model != "") {
        model = config.model;
      }
      var effortWord: String = prov.effort;
      if (effort != null) {
        if (isEffort(effort)) { effortWord = effort; }
      }

      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startObject();
      if (asked != null) {
        p.objectKey(prov.tokensField);
        p.int32Value(asked);
      }
      p.objectKey("messages");
      p.startArray();
      for (let m of call.messages) { writeMessage(p, m); }
      p.endArray();
      p.objectKey("model");
      p.stringValue(model);
      p.objectKey("reasoning_effort");
      p.stringValue(effortWord);
      if (call.json) {
        p.objectKey("response_format");
        p.startObject();
        p.objectKey("type");
        p.stringValue("json_object");
        p.endObject();
      }
      let temp = call.temperature;
      if (temp != null) {
        p.objectKey("temperature");
        p.float64Value(temp);
      }
      let forcedChoice = forced;
      let word = choiceWord;
      if (forcedChoice != null) {
        p.objectKey("tool_choice");
        forcedChoice.produce(p);
      } else if (word != null) {
        p.objectKey("tool_choice");
        p.stringValue(word);
      }
      if (!call.tools.isEmpty) {
        p.objectKey("tools");
        p.startArray();
        var i = 0;
        for (let t of call.tools) {
          p.startObject();
          p.objectKey("function");
          p.startObject();
          p.objectKey("description");
          p.stringValue(t.description);
          p.objectKey("name");
          p.stringValue(t.name);
          p.objectKey("parameters");
          schemas[i].produce(p);
          p.endObject();
          p.objectKey("type");
          p.stringValue("function");
          p.endObject();
          i += 1;
        }
        p.endArray();
      }
      p.endObject();
      new Result<String, LlmError>(p.toJsonString() orelse panic(), null)
    }

## Reading a reply

    let jfield(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

    let jstr(t: JsonSyntaxTree?): String? {
      if (t is JsonString) { t.content } else { null }
    }

    let jfirst(t: JsonSyntaxTree?): JsonSyntaxTree? {
      if (t is JsonArray) {
        if (t.elements.length > 0) { t.elements[0] } else { null }
      } else {
        null
      }
    }

    let clip(s: String, n: Int): String {
      var i = String.begin;
      var count = 0;
      while (s.hasIndex(i) && count < n) {
        i = s.next(i);
        count += 1;
      }
      s.slice(String.begin, i)
    }

    let has(s: String, needle: String): Boolean { s.split(needle).length > 1 }

    let failReply(kind: String, detail: String): Result<LlmReply, LlmError> {
      new Result<LlmReply, LlmError>(null, new LlmError(kind, detail))
    }

    let readToolCalls(message: JsonSyntaxTree?): List<LlmToolCall> {
      let out = new ListBuilder<LlmToolCall>();
      let calls = jfield(message, "tool_calls");
      if (calls is JsonArray) {
        for (let c of calls.elements) {
          let fn = jfield(c, "function");
          out.add(new LlmToolCall(
            orElse(jstr(jfield(c, "id")), ""),
            orElse(jstr(jfield(fn, "name")), ""),
            orElse(jstr(jfield(fn, "arguments")), "{}"),
          ));
        }
      }
      out.toList()
    }

A 200 whose body has `choices[0]`: the `length` rule first, then the message.

    export let llmParseReply(body: String): Result<LlmReply, LlmError> {
      let root: JsonSyntaxTree? = parseJson(body) orelse null;
      let choice = jfirst(jfield(root, "choices"));
      if (choice == null) {
        return failReply("http", "status 200 without choices: ${clip(body, 300)}");
      }
      let finish = orElse(jstr(jfield(choice, "finish_reason")), "");
      if (finish == "length") {
        return failReply("length", "the answer was cut off (finish_reason length)");
      }
      let message = jfield(choice, "message");
      if (!(message is JsonObject)) {
        return failReply("http", "unexpected choice: ${clip(body, 200)}");
      }
      new Result<LlmReply, LlmError>(
        new LlmReply(jstr(jfield(message, "content")), readToolCalls(message), finish, body),
        null,
      )
    }

## Transport

A transport answers like `sysHttpAwait`: `["ok", status, body]` or
`["error", reason]`. The real one is the interpreter's HTTPS client; the fake
answers canned responses and remembers what it was asked.

    export interface LlmTransport {
      public send(url: String, headers: List<String>, body: String, timeoutMs: Int): List<String>;
      public sent(): List<String>;
    }

    export class LlmSysTransport extends LlmTransport {
      public send(url: String, headers: List<String>, body: String, timeoutMs: Int): List<String> {
        let failed: List<String> = ["error", "transport: could not start the request"];
        do { sysHttpAwait(sysHttpStart("POST", url, headers, body, timeoutMs)) } orelse failed
      }
      public sent(): List<String> { [] }
    }

    export class LlmFakeResponse(public status: Int, public body: String) {}

Answers in order; once they run out, a transport error, so a test that makes
one call too many fails by name.

    export class LlmFakeTransport(private responses: List<LlmFakeResponse>) extends LlmTransport {
      private var next: Int = 0;
      private bodies: ListBuilder<String> = new ListBuilder<String>();
      public send(url: String, headers: List<String>, body: String, timeoutMs: Int): List<String> {
        bodies.add(body);
        let i = next;
        next += 1;
        if (i < responses.length) {
          ["ok", responses[i].status.toString(), responses[i].body]
        } else {
          ["error", "fake transport has no response number ${(i + 1).toString()}"]
        }
      }
      public sent(): List<String> { bodies.toList() }
    }

## The client

    export interface LlmClient {
      public chat(call: LlmCall): Result<LlmReply, LlmError>;
      public json(call: LlmCall): Result<JsonObject, LlmError>;
      public requests(): List<String>;
      public lastRequest(): String?;
    }

    class LlmStep(public result: Result<LlmReply, LlmError>, public retry: Boolean) {}

    let stepFail(kind: String, detail: String, retry: Boolean): LlmStep {
      new LlmStep(failReply(kind, detail), retry)
    }

One attempt's outcome. 429 and 5xx and transport failures retry; everything
else is final.

    let llmStep(resp: List<String>): LlmStep {
      if (resp.length >= 3 && resp[0] == "ok") {
        let status = resp[1].toInt32() orelse 0;
        let body = resp[2];
        if (status == 200) {
          new LlmStep(llmParseReply(body), false)
        } else if (status == 429) {
          stepFail("rate_limited", "status 429: ${clip(body, 300)}", true)
        } else if (status == 500 || status == 502 || status == 503 || status == 504) {
          stepFail("rate_limited", "status ${status.toString()}: ${clip(body, 300)}", true)
        } else {
          stepFail("http", "status ${status.toString()}: ${clip(body, 300)}", false)
        }
      } else {
        let reason = if (resp.length >= 2) { resp[1] } else { "no response" };
        if (has(reason, "timeout") || has(reason, "Timeout") || has(reason, "timed out")) {
          stepFail("timeout", reason, true)
        } else {
          stepFail("transport", reason, true)
        }
      }
    }

    let LLM_MAX_ATTEMPTS = 3;

2^attempt times the base: 500 ms then 1000 ms at the default 250, plus up to
400 ms of jitter so concurrent reads do not return together. Nothing at all
when the base is 0.

    let llmBackoff(baseMs: Int, attempt: Int): Void {
      var factor = 1;
      var i = 0;
      while (i < attempt) {
        factor = factor * 2;
        i += 1;
      }
      let wait = factor * baseMs;
      if (wait > 0) {
        let jitter = do { (sysNowMs() % 400.toInt64()).toInt32() + 1 } orelse 1;
        sysSleepMs(wait + jitter);
      }
    }

    let llmObjectOf(content: String?): JsonObject? {
      let parsed: JsonSyntaxTree? = if (content == null) { null } else { parseJson(content) orelse null };
      if (parsed is JsonObject) { parsed } else { null }
    }

    export class LlmHttpClient(
      private config: LlmConfig,
      private transport: LlmTransport,
    ) extends LlmClient {
      public requests(): List<String> { transport.sent() }

      public lastRequest(): String? {
        let sentBodies = transport.sent();
        if (sentBodies.length == 0) { return null; }
        return sentBodies[sentBodies.length - 1];
      }

      public chat(call: LlmCall): Result<LlmReply, LlmError> {
        if (config.apiKey == "") {
          return failReply("no_key", "no API key configured for ${config.provider}");
        }
        let built = llmRequestBody(config, call);
        let bodyText = built.ok;
        if (bodyText != null) {
          return send(call, bodyText);
        }
        new Result<LlmReply, LlmError>(null, built.err)
      }

      private send(call: LlmCall, bodyText: String): Result<LlmReply, LlmError> {
        let prov = llmProvider(config.provider);
        let url = if (config.endpoint != "") { config.endpoint } else { prov.endpoint };
        let timeout = if (call.timeoutMs > 0) { call.timeoutMs } else { config.timeoutMs };
        let headers = ["authorization: Bearer ${config.apiKey}", "content-type: application/json"];
        var attempt = 1;
        var last = failReply("transport", "no attempt was made");
        while (attempt <= LLM_MAX_ATTEMPTS) {
          let step = llmStep(transport.send(url, headers, bodyText, timeout));
          last = step.result;
          if (!step.retry) { return last; }
          if (attempt < LLM_MAX_ATTEMPTS) { llmBackoff(config.backoffMs, attempt); }
          attempt += 1;
        }
        last
      }

      public json(call: LlmCall): Result<JsonObject, LlmError> {
        let asJson = new LlmCall(call.messages, call.model, call.effort, call.maxTokens,
          call.temperature, true, call.tools, call.toolChoice, call.timeoutMs);
        let r = chat(asJson);
        let reply = r.ok;
        if (reply != null) {
          let content = reply.content;
          let obj = llmObjectOf(content);
          if (obj != null) {
            new Result<JsonObject, LlmError>(obj, null)
          } else {
            new Result<JsonObject, LlmError>(null,
              new LlmError("invalid_json", "the reply is not a JSON object: ${clip(orElse(content, ""), 200)}"))
          }
        } else {
          new Result<JsonObject, LlmError>(null, r.err)
        }
      }
    }

    export let llmWithConfig(config: LlmConfig): LlmClient {
      new LlmHttpClient(config, new LlmSysTransport())
    }

    export let llmFromEnv(): LlmClient { llmWithConfig(llmConfigFromEnv()) }

## Fakes

`llmFake` answers canned raw response bodies, status 200, in order, with a
fixed key and no backoff. `llmFakeScript` takes statuses too, and
`llmFakeWithConfig` lets a test pick the provider or drop the key.

    export let llmFakeConfig(): LlmConfig {
      new LlmConfig("deepseek", "test-key", "https://fake.invalid/chat/completions", 0, 1000, "")
    }

    export let llmFakeWithConfig(config: LlmConfig, responses: List<LlmFakeResponse>): LlmClient {
      new LlmHttpClient(config, new LlmFakeTransport(responses))
    }

    export let llmFakeScript(responses: List<LlmFakeResponse>): LlmClient {
      llmFakeWithConfig(llmFakeConfig(), responses)
    }

    export let llmFake(replies: List<String>): LlmClient {
      let rs = new ListBuilder<LlmFakeResponse>();
      var i = 0;
      while (i < replies.length) {
        rs.add(new LlmFakeResponse(200, replies[i]));
        i += 1;
      }
      llmFakeScript(rs.toList())
    }

Every request body the client sent, oldest first (empty for a real client), and
the last one.

    export let llmRequests(client: LlmClient): List<String> { client.requests() }

    export let llmLastRequest(client: LlmClient): String? { client.lastRequest() }
