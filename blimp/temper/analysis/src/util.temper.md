# Small helpers

Private to the analysis library and prefixed `an` so they cannot collide with
another library's names (the namespace is one flat table). Temper's `String`
has no trim, contains or regex, and the Elixir used `String.trim/1`,
`String.slice/3` and `~r/\s+/`.

    let { sysUtf8Downcase, sysStringReplace, sysJoin, sysGraphemeLength, sysGraphemeTake } = import("sys/src");
    let {
      JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonInt32, JsonBoolean, JsonNull,
      JsonNumeric, JsonTextProducer, parseJson,
    } = import("std/json");
    let { LlmError } = import("llm/src");

## Text

What `String.trim/1` strips: Unicode whitespace.

    let anIsTrimSpace(cp: Int): Boolean {
      cp == 32 || (cp >= 9 && cp <= 13) || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    let anTrim(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && anIsTrimSpace(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && anIsTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

    let anIsBlank(s: String): Boolean { anTrim(s).isEmpty }

    let anContains(hay: String, needle: String): Boolean {
      if (needle.isEmpty) { return true; }
      hay.split(needle).length > 1
    }

    let anCodePoints(s: String): Int { s.countBetween(String.begin, s.end) }

The code points `[from, to)` of `s`.

    let anSliceCp(s: String, from: Int, to: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < from && s.hasIndex(i)) { i = s.next(i); k += 1; }
      let a = i;
      while (k < to && s.hasIndex(i)) { i = s.next(i); k += 1; }
      s.slice(a, i)
    }

`~r/\s+/` replaced by one space, then trimmed: ASCII whitespace runs.

    let anVt(): String { "\u{b}" }
    let anFf(): String { "\u{c}" }

    let anCollapse(s: String): String {
      let a = sysStringReplace(s, "\n", " ");
      let b = sysStringReplace(a, "\t", " ");
      let c = sysStringReplace(b, "\r", " ");
      let d = sysStringReplace(c, anVt(), " ");
      let e = sysStringReplace(d, anFf(), " ");
      anTrim(sysJoin(e.split(" ").filter { (w: String): Boolean => !w.isEmpty }, " "))
    }

`to_line/1`: collapse, trim, first 300 graphemes; not a string is null.

    let anToLine(s: String?): String? {
      if (s == null) { null } else { sysGraphemeTake(anCollapse(s), 300) }
    }

    let anDash(): String { "\u{2014}" }

    let anOrEmpty(s: String?): String { if (s == null) { "" } else { s } }

The `INTENT` interpolation of the prompts: `<label><intent>\n` or nothing.

    let anIntent(label: String, intent: String?): String {
      if (intent != null) {
        if (intent != "") { return "${label}${intent}\n"; }
      }
      ""
    }

    let anIn(xs: List<String>, x: String): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i] == x) { return true; }
        i += 1;
      }
      false
    }

## JSON in

    let anParse(text: String?): JsonSyntaxTree? {
      if (text == null) { null } else { parseJson(text) orelse null }
    }

    let anField(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

    let anStr(t: JsonSyntaxTree?): String? {
      if (t is JsonString) { t.content } else { null }
    }

    let anInt(t: JsonSyntaxTree?): Int? {
      if (t is JsonInt32) { t.content } else { null }
    }

    let anElements(t: JsonSyntaxTree?): List<JsonSyntaxTree>? {
      if (t is JsonArray) { t.elements } else { null }
    }

`Integer.parse/1` of a string: an optional sign and at least one digit, the
rest ignored; null when there are none.

    let anParseInt(s: String): Int? {
      var i = String.begin;
      var negative = false;
      if (s.hasIndex(i)) {
        if (s[i] == 45) {
          negative = true;
          i = s.next(i);
        } else if (s[i] == 43) {
          i = s.next(i);
        }
      }
      var n = 0;
      var digits = 0;
      while (s.hasIndex(i)) {
        let c = s[i];
        if (c < 48 || c > 57) { break; }
        n = n * 10 + (c - 48);
        digits += 1;
        i = s.next(i);
      }
      if (digits == 0) { null } else if (negative) { 0 - n } else { n }
    }

## JSON out, sorted

Jason writes a map's keys in term order, which for these small maps is
alphabetical; the trace stores such text and the web layer reads it back, so
the same order is kept.

    let anKeys(o: JsonObject): List<String> {
      o.properties.keys().toList().sorted { (a: String, b: String): Int =>
        if (a == b) { 0 } else if (a < b) { -1 } else { 1 }
      }
    }

    let anProduce(t: JsonSyntaxTree, p: JsonTextProducer): Void {
      if (t is JsonObject) {
        p.startObject();
        for (let k of anKeys(t)) {
          let vs = t.properties.getOr(k, []);
          if (vs.length > 0) {
            p.objectKey(k);
            anProduce(vs[vs.length - 1], p);
          }
        }
        p.endObject();
      } else if (t is JsonArray) {
        p.startArray();
        for (let e of t.elements) { anProduce(e, p); }
        p.endArray();
      } else {
        t.produce(p);
      }
    }

Compact, sorted. Used for the tool-call key and the stored `args`.

    let anCanon(t: JsonSyntaxTree): String throws Bubble {
      let p = new JsonTextProducer();
      anProduce(t, p);
      p.toJsonString()
    }

A string as JSON text.

    let anQuote(s: String): String throws Bubble {
      let p = new JsonTextProducer();
      p.stringValue(s);
      p.toJsonString()
    }

## Pretty printing

`Jason.encode!(pretty: true)`: two-space indent, `"key": value`, empty
containers as `[]` and `{}`.

    class AnPretty {
      private sb: StringBuilder = new StringBuilder();
      private counts: ListBuilder<Int> = new ListBuilder<Int>();
      private var afterKey: Boolean = false;

      private pIndent(): Void {
        sb.append("\n");
        var i = 0;
        while (i < counts.length) {
          sb.append("  ");
          i += 1;
        }
      }

      private pPrefix(): Void {
        if (afterKey) {
          afterKey = false;
          return;
        }
        if (counts.length > 0) {
          let top = counts.length - 1;
          if (counts[top] > 0) { sb.append(","); }
          counts[top] = counts[top] + 1;
          this.pIndent();
        }
      }

      public pBeginObject(): Void {
        this.pPrefix();
        sb.append("{");
        counts.add(0);
      }

      public pBeginArray(): Void {
        this.pPrefix();
        sb.append("[");
        counts.add(0);
      }

      private pClose(mark: String): Void {
        let top = counts.length - 1;
        let n = counts[top];
        counts.removeLast();
        if (n > 0) { this.pIndent(); }
        sb.append(mark);
      }

      public pEndObject(): Void { this.pClose("}"); }
      public pEndArray(): Void { this.pClose("]"); }

      public pKey(k: String): Void throws Bubble {
        this.pPrefix();
        sb.append(anQuote(k));
        sb.append(": ");
        afterKey = true;
      }

      public pStr(v: String): Void throws Bubble {
        this.pPrefix();
        sb.append(anQuote(v));
      }

      public pStrOrNull(v: String?): Void throws Bubble {
        if (v == null) { this.pRaw("null"); } else { this.pStr(v); }
      }

      public pInt(v: Int): Void {
        this.pPrefix();
        sb.append(v.toString());
      }

      public pIntOrNull(v: Int?): Void {
        if (v == null) { this.pRaw("null"); } else { this.pInt(v); }
      }

      public pBool(v: Boolean): Void {
        this.pRaw(if (v) { "true" } else { "false" });
      }

      public pRaw(token: String): Void {
        this.pPrefix();
        sb.append(token);
      }

      public pTree(t: JsonSyntaxTree): Void throws Bubble {
        if (t is JsonObject) {
          this.pBeginObject();
          for (let k of anKeys(t)) {
            let vs = t.properties.getOr(k, []);
            if (vs.length > 0) {
              this.pKey(k);
              this.pTree(vs[vs.length - 1]);
            }
          }
          this.pEndObject();
        } else if (t is JsonArray) {
          this.pBeginArray();
          for (let e of t.elements) { this.pTree(e); }
          this.pEndArray();
        } else if (t is JsonString) {
          this.pStr(t.content);
        } else if (t is JsonNumeric) {
          this.pRaw(t.asJsonNumericToken());
        } else if (t is JsonBoolean) {
          this.pBool(t.content);
        } else {
          this.pRaw("null");
        }
      }

      public toString(): String { sb.toString() }
    }

## Errors as the Elixir printed them

`inspect(reason)` for the reasons the callers wrote into `status_detail` and
into the log.

    let anQuoteOr(s: String): String {
      do { anQuote(s) } orelse s
    }

    let anInspect(e: LlmError): String {
      if (e.kind == "length") {
        ":truncated"
      } else if (e.kind == "no_key") {
        ":no_api_key"
      } else if (e.kind == "rate_limited") {
        ":rate_limited"
      } else if (e.kind == "invalid_json") {
        ":invalid_json"
      } else {
        "{:${e.kind}, ${anQuoteOr(e.detail)}}"
      }
    }
