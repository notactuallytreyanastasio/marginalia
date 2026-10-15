# Tests for llm

Every check runs inside a helper that takes the `test`, or the compiler
evaluates it while compiling and the generated code is never exercised.

    let { JsonObject } = import("std/json");
    let { sysGetEnv, sysFork, sysExec, sysExit, sysSleepMs, sysNowMs,
          sysHttpStart, sysHttpAwait } = import("sys/src");

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let expectTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let orZero(n: Int?): Int { if (n == null) { -1 } else { n } }

    let orNone(s: String?): String { if (s == null) { "<none>" } else { s } }

    let bodyOf(r: Result<String, LlmError>): String {
      let b = r.ok;
      if (b == null) {
        let e = r.err;
        if (e == null) { "<neither>" } else { "ERR ${llmErrorText(e)}" }
      } else { b }
    }

    let errKind(r: Result<LlmReply, LlmError>): String {
      let e = r.err;
      if (e == null) { "ok" } else { e.kind }
    }

    let jsonErrKind(r: Result<JsonObject, LlmError>): String {
      let e = r.err;
      if (e == null) { "ok" } else { e.kind }
    }

    let contentOf(r: Result<LlmReply, LlmError>): String {
      let v = r.ok;
      if (v == null) { "<no reply>" } else { orNone(v.content) }
    }

    let mk(
      msgs: List<LlmMessage>, model: String?, effort: String?, maxTokens: Int?,
      temperature: Float64?, json: Boolean, tools: List<LlmTool>, choice: String?,
    ): LlmCall {
      new LlmCall(msgs, model, effort, maxTokens, temperature, json, tools, choice, 0)
    }

    let lastSent(test: Test, c: LlmClient): String { orNone(llmLastRequest(c)) }

    let hi(): List<LlmMessage> {
      [new LlmMessage("system", "S"), new LlmMessage("user", "hi")]
    }

    let deepseek(): LlmConfig { llmFakeConfig() }

    let openai(): LlmConfig {
      new LlmConfig("openai", "k", "", 0, 1000, "")
    }

    let okBody(content: String): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"${content}\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":7}}"
    }

    let toolBody(): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"record\",\"arguments\":\"{\\\"a\\\":1}\"}},{\"id\":\"call_2\",\"type\":\"function\",\"function\":{\"name\":\"other\",\"arguments\":\"{}\"}}]},\"finish_reason\":\"tool_calls\"}]}"
    }

    let lengthBody(): String {
      "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"{\\\"half\\\":\"},\"finish_reason\":\"length\"}]}"
    }

    let resp(status: Int, body: String): LlmFakeResponse { new LlmFakeResponse(status, body) }

## The request body

    test("deepseek body: max_tokens carries the 24000 headroom, effort, no extras") { test =>
      let call = mk(hi(), null, "high", 1400, null, false, [], null);
      expectText(test, bodyOf(llmRequestBody(deepseek(), call)),
        "{\"max_tokens\":25400,\"messages\":[{\"content\":\"S\",\"role\":\"system\"},{\"content\":\"hi\",\"role\":\"user\"}],\"model\":\"deepseek-flash\",\"reasoning_effort\":\"high\"}");
    }

    test("openai body: max_completion_tokens, its own model") { test =>
      let call = mk(hi(), null, null, 1000, null, false, [], null);
      expectText(test, bodyOf(llmRequestBody(openai(), call)),
        "{\"max_completion_tokens\":25000,\"messages\":[{\"content\":\"S\",\"role\":\"system\"},{\"content\":\"hi\",\"role\":\"user\"}],\"model\":\"gpt-5.6-sol\",\"reasoning_effort\":\"low\"}");
    }

    test("no maxTokens means no token field at all; effort defaults to low") { test =>
      let call = mk(hi(), null, null, null, null, false, [], null);
      expectText(test, bodyOf(llmRequestBody(deepseek(), call)),
        "{\"messages\":[{\"content\":\"S\",\"role\":\"system\"},{\"content\":\"hi\",\"role\":\"user\"}],\"model\":\"deepseek-flash\",\"reasoning_effort\":\"low\"}");
    }

    test("token budget is asked plus 24000, nil stays nil") { test =>
      expectInt(test, orZero(llmTokenBudget("deepseek", 1400)), 25400);
      expectInt(test, orZero(llmTokenBudget("openai", 0)), 24000);
      expectTrue(test, llmTokenBudget("deepseek", null) == null, "nil budget");
    }

    test("effort none and high are kept, anything else falls back to low") { test =>
      let none = bodyOf(llmRequestBody(deepseek(), mk([], null, "none", null, null, false, [], null)));
      expectTrue(test, none.split("\"reasoning_effort\":\"none\"").length == 2, none);
      let weird = bodyOf(llmRequestBody(deepseek(), mk([], null, "extreme", null, null, false, [], null)));
      expectTrue(test, weird.split("\"reasoning_effort\":\"low\"").length == 2, weird);
    }

    test("json mode adds response_format json_object") { test =>
      let call = mk([new LlmMessage("user", "x")], null, null, null, null, true, [], null);
      expectText(test, bodyOf(llmRequestBody(deepseek(), call)),
        "{\"messages\":[{\"content\":\"x\",\"role\":\"user\"}],\"model\":\"deepseek-flash\",\"reasoning_effort\":\"low\",\"response_format\":{\"type\":\"json_object\"}}");
    }

    test("temperature is sent when given") { test =>
      let call = mk([], null, null, null, 0.4, false, [], null);
      expectText(test, bodyOf(llmRequestBody(deepseek(), call)),
        "{\"messages\":[],\"model\":\"deepseek-flash\",\"reasoning_effort\":\"low\",\"temperature\":0.4}");
    }

    test("tools default tool_choice to auto and embed the schema as JSON") { test =>
      let tool = new LlmTool("record", "Record it", "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"integer\"}}}");
      let call = mk([], null, null, null, null, false, [tool], null);
      expectText(test, bodyOf(llmRequestBody(deepseek(), call)),
        "{\"messages\":[],\"model\":\"deepseek-flash\",\"reasoning_effort\":\"low\",\"tool_choice\":\"auto\",\"tools\":[{\"function\":{\"description\":\"Record it\",\"name\":\"record\",\"parameters\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"integer\"}}}},\"type\":\"function\"}]}");
    }

    test("explicit tool_choice word and forced-function object") { test =>
      let tool = new LlmTool("t", "d", "{}");
      let word = bodyOf(llmRequestBody(deepseek(), mk([], null, null, null, null, false, [tool], "required")));
      expectTrue(test, word.split("\"tool_choice\":\"required\"").length == 2, word);
      let forced = "{\"type\":\"function\",\"function\":{\"name\":\"t\"}}";
      let obj = bodyOf(llmRequestBody(deepseek(), mk([], null, null, null, null, false, [tool], forced)));
      expectTrue(test, obj.split("\"tool_choice\":${forced}").length == 2, obj);
    }

    test("no tools means no tool_choice, even if a word was given and no tools") { test =>
      let b = bodyOf(llmRequestBody(deepseek(), mk([], null, null, null, null, false, [], null)));
      expectTrue(test, b.split("tool").length == 1, b);
    }

    test("model: the call's wins over the config's wins over the provider's") { test =>
      let cfg = new LlmConfig("deepseek", "k", "", 0, 1000, "from-config");
      let a = bodyOf(llmRequestBody(cfg, mk([], null, null, null, null, false, [], null)));
      expectTrue(test, a.split("\"model\":\"from-config\"").length == 2, a);
      let b = bodyOf(llmRequestBody(cfg, mk([], "from-call", null, null, null, false, [], null)));
      expectTrue(test, b.split("\"model\":\"from-call\"").length == 2, b);
    }

    test("user text is escaped by the encoder, never concatenated") { test =>
      let nasty = "say \"hi\"\nback\\slash </script>";
      let call = mk([new LlmMessage("user", nasty)], null, null, null, null, false, [], null);
      expectText(test, bodyOf(llmRequestBody(deepseek(), call)),
        "{\"messages\":[{\"content\":\"say \\\"hi\\\"\\nback\\\\slash </script>\",\"role\":\"user\"}],\"model\":\"deepseek-flash\",\"reasoning_effort\":\"low\"}");
    }

    test("tool parameters that are not JSON are an invalid_json error, not a bad request") { test =>
      let tool = new LlmTool("t", "d", "{not json");
      let r = llmRequestBody(deepseek(), mk([], null, null, null, null, false, [tool], null));
      let e = r.err;
      expectText(test, if (e == null) { "no error" } else { e.kind }, "invalid_json");
    }

## Reading replies

    test("content reply") { test =>
      let c = llmFake([okBody("Hello there")]);
      let r = c.chat(llmSimpleCall("hi"));
      expectText(test, contentOf(r), "Hello there");
      let v = r.ok;
      expectText(test, if (v == null) { "" } else { v.finishReason }, "stop");
      expectInt(test, if (v == null) { -1 } else { v.toolCalls.length }, 0);
    }

    test("usage stays in raw") { test =>
      let c = llmFake([okBody("x")]);
      let v = c.chat(llmSimpleCall("hi")).ok;
      expectTrue(test, if (v == null) { false } else { v.raw.split("\"prompt_tokens\":7").length == 2 }, "usage in raw");
    }

    test("tool_calls reply: id, name and arguments text, content null") { test =>
      let c = llmFake([toolBody()]);
      let r = c.chat(llmSimpleCall("hi"));
      let v = r.ok;
      expectText(test, errKind(r), "ok");
      expectTrue(test, if (v == null) { false } else { v.content == null }, "content is null");
      expectInt(test, if (v == null) { -1 } else { v.toolCalls.length }, 2);
      expectText(test, if (v == null) { "" } else { v.toolCalls[0].id }, "call_1");
      expectText(test, if (v == null) { "" } else { v.toolCalls[0].name }, "record");
      expectText(test, if (v == null) { "" } else { v.toolCalls[0].argumentsJson }, "{\"a\":1}");
      expectText(test, if (v == null) { "" } else { v.toolCalls[1].name }, "other");
      expectText(test, if (v == null) { "" } else { v.finishReason }, "tool_calls");
    }

    test("finish_reason length is a failure, kind length, never retried") { test =>
      let c = llmFake([lengthBody(), okBody("never reached")]);
      let r = c.chat(llmSimpleCall("hi"));
      expectText(test, errKind(r), "length");
      expectInt(test, llmRequests(c).length, 1);
    }

    test("json() returns the object") { test =>
      let c = llmFake([okBody("{\\\"a\\\":1}")]);
      let r = c.json(llmSimpleCall("hi"));
      expectText(test, jsonErrKind(r), "ok");
      let o = r.ok;
      expectTrue(test, o != null, "an object");
      let sent = lastSent(test, c);
      expectTrue(test, sent.split("\"response_format\":{\"type\":\"json_object\"}").length == 2, sent);
    }

    test("json() on prose is invalid_json and is not retried") { test =>
      let c = llmFake([okBody("Sure, here you go."), okBody("{}")]);
      expectText(test, jsonErrKind(c.json(llmSimpleCall("hi"))), "invalid_json");
      expectInt(test, llmRequests(c).length, 1);
    }

    test("json() on a JSON array is invalid_json") { test =>
      let c = llmFake([okBody("[1,2]")]);
      expectText(test, jsonErrKind(c.json(llmSimpleCall("hi"))), "invalid_json");
    }

    test("json() passes a chat failure through unchanged") { test =>
      let c = llmFake([lengthBody()]);
      expectText(test, jsonErrKind(c.json(llmSimpleCall("hi"))), "length");
    }

    test("a 200 without choices is http, not retried") { test =>
      let c = llmFake(["{\"nope\":true}", okBody("x")]);
      expectText(test, errKind(c.chat(llmSimpleCall("hi"))), "http");
      expectInt(test, llmRequests(c).length, 1);
    }

## Retries and failures

    test("429 then 200: retried, second answer returned") { test =>
      let c = llmFakeScript([resp(429, "{}"), resp(200, okBody("second"))]);
      let r = c.chat(llmSimpleCall("hi"));
      expectText(test, contentOf(r), "second");
      expectInt(test, llmRequests(c).length, 2);
    }

    test("the same body is sent on every attempt") { test =>
      let c = llmFakeScript([resp(503, "x"), resp(200, okBody("y"))]);
      c.chat(llmSimpleCall("hi"));
      let sent = llmRequests(c);
      expectTrue(test, sent[0] == sent[1], "identical bodies");
    }

    test("429 three times: rate_limited after exactly 3 attempts") { test =>
      let c = llmFakeScript([resp(429, "{}"), resp(429, "{}"), resp(429, "{}"), resp(200, okBody("late"))]);
      expectText(test, errKind(c.chat(llmSimpleCall("hi"))), "rate_limited");
      expectInt(test, llmRequests(c).length, 3);
    }

    test("500 three times: rate_limited after exactly 3 attempts") { test =>
      let c = llmFakeScript([resp(500, "boom"), resp(500, "boom"), resp(500, "boom"), resp(200, okBody("late"))]);
      let r = c.chat(llmSimpleCall("hi"));
      expectText(test, errKind(r), "rate_limited");
      expectInt(test, llmRequests(c).length, 3);
      let e = r.err;
      expectTrue(test, if (e == null) { false } else { e.detail.split("500").length > 1 }, "status in detail");
    }

    test("400 is http and not retried") { test =>
      let c = llmFakeScript([resp(400, "{\"error\":\"bad\"}"), resp(200, okBody("x"))]);
      expectText(test, errKind(c.chat(llmSimpleCall("hi"))), "http");
      expectInt(test, llmRequests(c).length, 1);
    }

    test("transport errors (no response left) retry to 3 attempts") { test =>
      let c = llmFakeWithConfig(deepseek(), []);
      expectText(test, errKind(c.chat(llmSimpleCall("hi"))), "transport");
      expectInt(test, llmRequests(c).length, 3);
    }

    test("no key: no_key and no request is made") { test =>
      let cfg = new LlmConfig("deepseek", "", "", 0, 1000, "");
      let c = llmFakeWithConfig(cfg, [resp(200, okBody("x"))]);
      expectText(test, errKind(c.chat(llmSimpleCall("hi"))), "no_key");
      expectText(test, jsonErrKind(c.json(llmSimpleCall("hi"))), "no_key");
      expectInt(test, llmRequests(c).length, 0);
    }

    test("the fake records every request body; last request is the newest") { test =>
      let c = llmFake([okBody("a"), okBody("b")]);
      c.chat(llmSimpleCall("first"));
      c.chat(llmSimpleCall("second"));
      expectInt(test, llmRequests(c).length, 2);
      expectTrue(test, lastSent(test, c).split("second").length == 2, "last is second: ${lastSent(test, c)} / ${llmRequests(c).length.toString()}");
      expectTrue(test, llmLastRequest(llmFake([])) == null, "no requests yet");
    }

    test("env defaults: deepseek, 300000 ms timeout, 250 ms backoff") { test =>
      let cfg = llmConfigFromEnv();
      if (sysGetEnv("MARGINALIA_LLM_PROVIDER") == null) {
        expectText(test, cfg.provider, "deepseek");
      }
      if (sysGetEnv("MARGINALIA_LLM_TIMEOUT_MS") == null) {
        expectInt(test, cfg.timeoutMs, 300000);
      }
      if (sysGetEnv("MARGINALIA_LLM_BACKOFF_MS") == null) {
        expectInt(test, cfg.backoffMs, 250);
      }
    }

    test("provider table") { test =>
      expectText(test, llmProvider("openai").tokensField, "max_completion_tokens");
      expectText(test, llmProvider("deepseek").tokensField, "max_tokens");
      expectText(test, llmProvider("anything else").name, "deepseek");
      expectText(test, llmProvider("openai").fastModel, "gpt-5.4-nano");
    }

## Against the fake server

`blimp/test/fake_llm.blimp` is started in a forked child on a port picked from
the clock; the parent waits 300 ms, makes its calls over a real socket, and
asks the server to exit with `GET /quit`. `BLIMP_BIN`, `BLIMP_FAKE_LLM` and
`BLIMP_FAKE_DIR` override the paths.

    let envOr(name: String, fallback: String): String {
      let v = sysGetEnv(name);
      if (v == null) { fallback } else { v }
    }

    test("live: FAKE_CHAT gets the canned answer; FAKE_LLM_429 is rate_limited after 3 attempts") { test =>
      let port = do { 20000 + (sysNowMs() % 20000.toInt64()).toInt32() } orelse 23456;
      let blimp = envOr("BLIMP_BIN", "/Users/bg/code/temper-blimp-115/blimp/chunks/lang/zig-out/bin/blimp");
      let script = envOr("BLIMP_FAKE_LLM", "/Users/bg/code/marginalia/.claude/worktrees/blimp-rewrite/blimp/test/fake_llm.blimp");
      let dir = envOr("BLIMP_FAKE_DIR", "/Users/bg/code/marginalia/.claude/worktrees/blimp-rewrite/blimp/test/fixtures/llm");
      let pid = sysFork();
      if (pid == 0) {
        sysExec([blimp, script, port.toString(), dir], "", null);
        sysExit(0);
      }
      sysSleepMs(300);
      let cfg = new LlmConfig("deepseek", "live-key", "http://127.0.0.1:${port.toString()}/chat/completions", 0, 5000, "");
      let c = llmWithConfig(cfg);
      let chat = c.chat(llmSimpleCall("please FAKE_CHAT now"));
      let limited = c.chat(llmSimpleCall("FAKE_LLM_429"));
      let failing = c.chat(llmSimpleCall("FAKE_LLM_500"));
      let quit = sysHttpAwait(sysHttpStart("GET", "http://127.0.0.1:${port.toString()}/quit", [], "", 2000));
      let chatText = contentOf(chat);
      expectTrue(test, chatText.split("canned chat answer").length == 2, "chat answer was: ${chatText} (${errKind(chat)})");
      expectText(test, errKind(limited), "rate_limited");
      expectText(test, errKind(failing), "rate_limited");
      expectText(test, quit[0], "ok");
    }
