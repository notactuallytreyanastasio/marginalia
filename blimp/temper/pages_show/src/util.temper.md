# Small things the work page shares

Every top-level name in this library is shared by all of its files and, in the
built program, with every other library's. Exported names start with `show`
(or `render`/`load`/`handle` for the frame); the private helpers start with
`ps`.

    let { JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonBoolean, JsonInt, JsonNumeric, JsonNull,
          JsonTextProducer, NullInterchangeContext, parseJson } = import("std/json");
    let { sysStringTrim, sysJoin, sysUtf8Upcase } = import("sys/src");

## Strings

    export let showOr(s: String?, d: String): String {
      if (s != null) { s } else { d }
    }

    export let showHas(s: String, part: String): Boolean {
      if (part == "") { return true; }
      s.split(part).length > 1
    }

    export let showStartsWith(s: String, prefix: String): Boolean {
      if (s == "" || prefix == "") { return false; }
      let parts = s.split(prefix);
      parts.length > 1 && parts.getOr(0, "x") == ""
    }

    export let showJoin(parts: List<String>, sep: String): String {
      sysJoin(parts, sep)
    }

    export let showTrim(s: String): String { sysStringTrim(s) }

A class attribute out of the parts that are not empty, in order: the HEEx
`class={[...]}` list that drops `false` and `nil`.

    export let showCls(parts: List<String>): String {
      sysJoin(parts.filter { (p: String): Boolean => p != "" }, " ")
    }

An integer from text (digits only), or null: `arg_int/1`.

    export let showIntOr(n: Int?, d: Int): Int {
      if (n != null) { n } else { d }
    }

    export let showInt(s: String): Int? {
      let t = sysStringTrim(s);
      if (t == "") { return null; }
      let n: Int? = do { t.toInt32() } orelse null;
      n
    }

## JSON in, JSON out

The ui state is a JSON object in the session, and a run's `detail` carries a
job's answer as JSON. These read a field without a cast.

    export let showField(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

    export let showJStr(t: JsonSyntaxTree?, key: String): String? {
      let v = showField(t, key);
      if (v is JsonString) { v.content } else { null }
    }

    export let showJInt(t: JsonSyntaxTree?, key: String): Int? {
      let v = showField(t, key);
      if (v is JsonInt) {
        v.content
      } else if (v is JsonNumeric) {
        let n: Int? = do { v.asJsonNumericToken().toInt32() } orelse null;
        n
      } else { null }
    }

    export let showJBool(t: JsonSyntaxTree?, key: String): Boolean {
      let v = showField(t, key);
      if (v is JsonBoolean) { v.content } else { false }
    }

    export let showJList(t: JsonSyntaxTree?, key: String): List<JsonSyntaxTree> {
      let v = showField(t, key);
      if (v is JsonArray) { v.elements } else { [] }
    }

    export let showJStrings(t: JsonSyntaxTree?, key: String): List<String> {
      let out = new ListBuilder<String>();
      for (let e of showJList(t, key)) {
        if (e is JsonString) { out.add(e.content); }
      }
      out.toList()
    }

    export let showJInts(t: JsonSyntaxTree?, key: String): List<Int> {
      let out = new ListBuilder<Int>();
      for (let e of showJList(t, key)) {
        if (e is JsonInt) { out.add(e.content); }
      }
      out.toList()
    }

    export let showParse(text: String?): JsonSyntaxTree? {
      if (text != null) {
        let tree: JsonSyntaxTree? = parseJson(text) orelse null;
        tree
      } else { null }
    }

A payload field as text: a string as it is, a number as its digits, anything
else (and a missing key) the empty string.

    export let showPayloadStr(payload: JsonObject, key: String): String {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) {
        v.content
      } else if (v is JsonInt) {
        v.content.toString()
      } else if (v is JsonNumeric) {
        v.asJsonNumericToken()
      } else { "" }
    }

    export let showPayloadInt(payload: JsonObject, key: String): Int? {
      showInt(showPayloadStr(payload, key))
    }

### Writing

    export let showKeyStr(p: JsonTextProducer, key: String, value: String?): Void {
      p.objectKey(key);
      if (value != null) { p.stringValue(value); } else { p.nullValue(); }
    }

    export let showKeyInt(p: JsonTextProducer, key: String, value: Int?): Void {
      p.objectKey(key);
      if (value != null) { p.int32Value(value); } else { p.nullValue(); }
    }

    export let showKeyBool(p: JsonTextProducer, key: String, value: Boolean): Void {
      p.objectKey(key);
      p.booleanValue(value);
    }

    export let showKeyStrings(p: JsonTextProducer, key: String, xs: List<String>): Void {
      p.objectKey(key);
      p.startArray();
      for (let x of xs) { p.stringValue(x); }
      p.endArray();
    }

    export let showKeyInts(p: JsonTextProducer, key: String, xs: List<Int>): Void {
      p.objectKey(key);
      p.startArray();
      for (let x of xs) { p.int32Value(x); }
      p.endArray();
    }

    export let showProducer(): JsonTextProducer {
      new JsonTextProducer(NullInterchangeContext.instance)
    }

## Time

`"YYYY-MM-DD HH:MM:SS"` (UTC) as unix seconds, or null when it does not parse.
`started_at` of the progress clock is this: the clock counts up from it in the
browser.

    let psDaysFromCivil(year: Int, month: Int, day: Int): Int {
      let y = if (month <= 2) { year - 1 } else { year };
      let era = if (y >= 0) { y / 400 } else { (y - 399) / 400 };
      let yoe = y - era * 400;
      let mp = if (month > 2) { month - 3 } else { month + 9 };
      let doy = (153 * mp + 2) / 5 + day - 1;
      let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
      era * 146097 + doe - 719468
    }

    let psIntOr(s: String, d: Int): Int {
      let n = showInt(s);
      if (n != null) { n } else { d }
    }

    export let showEpoch(stamp: String): Int? {
      let halves = stamp.split(" ");
      if (halves.length < 2) { return null; }
      let date = halves.getOr(0, "").split("-");
      let time = halves.getOr(1, "").split(":");
      if (date.length < 3 || time.length < 3) { return null; }
      let y = psIntOr(date.getOr(0, ""), -1);
      let mo = psIntOr(date.getOr(1, ""), -1);
      let d = psIntOr(date.getOr(2, ""), -1);
      let hh = psIntOr(time.getOr(0, ""), -1);
      let mm = psIntOr(time.getOr(1, ""), -1);
      let ss = psIntOr(time.getOr(2, ""), -1);
      if (y < 0 || mo < 1 || d < 1 || hh < 0 || mm < 0 || ss < 0) { return null; }
      psDaysFromCivil(y, mo, d) * 86400 + hh * 3600 + mm * 60 + ss
    }

## Run keys

Everything the page starts in the background is a row of `runs` under
`work:<id>:<what>`. A page that finds one running polls; one that finds a
finished run it had last seen running says so, once.

    export let showKeyPrefix(workId: Int): String { "work:${workId.toString()}:" }

    export let showRunKey(workId: Int, what: String): String { "${showKeyPrefix(workId)}${what}" }

    export let showReadKey(workId: Int): String { showRunKey(workId, "read") }

    export let showGraphKey(workId: Int): String { showRunKey(workId, "graph") }

    export let showRewriteKey(workId: Int): String { showRunKey(workId, "rewrite") }

    export let showDocumentKey(workId: Int): String { showRunKey(workId, "document") }

    export let showCompareKey(workId: Int): String { showRunKey(workId, "compare") }

    export let showSummariseKey(workId: Int, ordinal: Int): String {
      showRunKey(workId, "summarise:${ordinal.toString()}")
    }

The page's own address: the view is always in it, and the drawer when it is
open. `push_patch(to: path, replace: true)`.

    export let showPath(slug: String, view: String, chat: Boolean): String {
      "/works/${slug}?view=${view}${if (chat) { "&chat=1" } else { "" }}"
    }
