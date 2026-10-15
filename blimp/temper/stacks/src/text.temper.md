# Small text helpers

Temper's `String` has no trim, contains or inspect, and the Elixir this
replaces used `String.trim/1`, `String.contains?/2`, `inspect/1` and
`Cuts.locate/2`. These are the ones the stacks context needs, written to
match. Only `stacksLocate`, `stacksScrub` and `stacksInspect` are exported;
the rest is library-private.

    let { sysStringReplace, sysJoin, sysGraphemeTake } = import("sys/src");
    let {
      JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonNull, JsonBoolean,
      JsonNumeric, JsonTextProducer,
    } = import("std/json");

## Whitespace

What `String.trim/1` strips: Unicode whitespace.

    let stacksIsTrimSpace(cp: Int): Boolean {
      cp == 32 || (cp >= 9 && cp <= 13) || cp == 0x85 || cp == 0xA0 || cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) || cp == 0x2028 || cp == 0x2029 ||
        cp == 0x202F || cp == 0x205F || cp == 0x3000
    }

    let stacksTrim(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && stacksIsTrimSpace(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && stacksIsTrimSpace(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

    let stacksContains(hay: String, needle: String): Boolean {
      if (needle.isEmpty) { return true; }
      hay.split(needle).length > 1
    }

    let stacksCodePoints(s: String): Int {
      s.countBetween(String.begin, s.end)
    }

The first `n` characters (graphemes), as `String.slice(s, 0, n)`.

    let stacksTake(s: String, n: Int): String {
      sysGraphemeTake(s, n)
    }

    let stacksVt(): String { "\u{b}" }
    let stacksFf(): String { "\u{c}" }

Every ASCII whitespace run (PCRE `\s`, which includes the vertical tab and
the form feed) becomes one space and the ends are trimmed.

    let stacksCollapse(s: String): String {
      let a = sysStringReplace(s, "\n", " ");
      let b = sysStringReplace(a, "\t", " ");
      let c = sysStringReplace(b, "\r", " ");
      let d = sysStringReplace(c, stacksVt(), " ");
      let e = sysStringReplace(d, stacksFf(), " ");
      sysJoin(e.split(" ").filter { (w: String): Boolean => !w.isEmpty }, " ")
    }

## locate

`Cuts.locate(needle, haystack)`: where a quote sits in a text, answered with
the text's own wording. The needle unchanged when it is there byte for byte;
else the needle with whitespace runs folded is searched in the haystack with
the same folding (space, newline, tab and return only on this side), and the
haystack's own slice, line breaks and all, is returned. A blank needle, or
words missing or out of order, is `null`.

The Elixir walks bytes and keeps a byte offset per output byte; this walks
code points and keeps a `StringIndex` per output code point. Same answers on
valid UTF-8.

    export let stacksLocate(needle: String, hay: String): String? {
      if (stacksTrim(needle).isEmpty) { return null; }
      if (stacksContains(hay, needle)) { return needle; }
      let flatNeedle = stacksCollapse(needle);
      if (flatNeedle.isEmpty) { return null; }
      let flat = new ListBuilder<String>();
      let starts = new ListBuilder<StringIndex>();
      let ends = new ListBuilder<StringIndex>();
      var i = String.begin;
      var prevSpace = false;
      while (hay.hasIndex(i)) {
        let cp = hay[i];
        let after = hay.next(i);
        if (cp == 32 || cp == 10 || cp == 9 || cp == 13) {
          if (flat.length != 0 && !prevSpace) {
            flat.add(" ");
            starts.add(i);
            ends.add(after);
          }
          prevSpace = true;
        } else {
          flat.add(hay.slice(i, after));
          starts.add(i);
          ends.add(after);
          prevSpace = false;
        }
        i = after;
      }
      let flatText = sysJoin(flat.toList(), "");
      let parts = flatText.split(flatNeedle);
      if (parts.length < 2) { return null; }
      let at = stacksCodePoints(parts[0]);
      let len = stacksCodePoints(flatNeedle);
      let startList = starts.toList();
      let endList = ends.toList();
      hay.slice(startList[at], endList[at + len - 1])
    }

## scrub

DeepSeek's own markup delimiters, leaking out of the model into the answer:
`<` immediately followed by U+FF5C (a fullwidth vertical bar). The good text
before the marker is kept, trimmed; the rest is cut; the cut is reported.

    let stacksLeakMarker(): String { "<\u{FF5C}" }

    export class StackScrubbed(public text: String, public leak: String?) {}

    export let stacksScrub(text: String, where: String): StackScrubbed {
      let parts = text.split(stacksLeakMarker());
      if (parts.length < 2) {
        new StackScrubbed(text, null)
      } else {
        new StackScrubbed(
          stacksTrim(parts[0]),
          "${where}: the model leaked its own tool-call markup; the text was cut there",
        )
      }
    }

## inspect

`inspect/1` of a string as the messages quote one: double quotes, with the
backslash, the quote, the newline, tab and return, and `#{` escaped.

A `#` and a `{` side by side inside a string literal is Blimp's own string
interpolation in the emitted code, so the pair is built at run time.

    let stacksHashBrace(): String { sysJoin(["#", "\u{7b}"], "") }

    let stacksInspectString(s: String): String {
      let a = sysStringReplace(s, "\\", "\\\\");
      let b = sysStringReplace(a, "\"", "\\\"");
      let c = sysStringReplace(b, "\n", "\\n");
      let d = sysStringReplace(c, "\t", "\\t");
      let e = sysStringReplace(d, "\r", "\\r");
      let f = sysJoin(e.split(stacksHashBrace()), sysJoin(["\\", stacksHashBrace()], ""));
      "\"${f}\""
    }

    export let stacksInspect(s: String): String { stacksInspectString(s) }

The same for a JSON value as `inspect/1` would show the decoded term.

    let stacksIsFloatToken(token: String): Boolean {
      stacksContains(token, ".") || stacksContains(token, "e") || stacksContains(token, "E")
    }

    let stacksInspectJson(t: JsonSyntaxTree?): String throws Bubble {
      if (t != null) {
        if (t is JsonString) {
          stacksInspectString(t.content)
        } else if (t is JsonNull) {
          "nil"
        } else if (t is JsonBoolean) {
          if (t.content) { "true" } else { "false" }
        } else if (t is JsonNumeric) {
          t.asJsonNumericToken()
        } else if (t is JsonArray) {
          let out = new ListBuilder<String>();
          for (let x of t.elements) { out.add(stacksInspectJson(x)); }
          "[${sysJoin(out.toList(), ", ")}]"
        } else if (t is JsonObject) {
          let out = new ListBuilder<String>();
          for (let kv of t.properties.toList()) {
            let first = if (kv.value.length > 0) { kv.value[0] } else { null };
            out.add("${stacksInspectString(kv.key)} => ${stacksInspectJson(first)}");
          }
          "%{${sysJoin(out.toList(), ", ")}}"
        } else {
          "nil"
        }
      } else {
        "nil"
      }
    }

## Reading a JSON value the way the validators do

`trimmed/1`: a string trimmed, anything else the empty string.

    let stacksTrimmed(t: JsonSyntaxTree?): String {
      if (t is JsonString) { stacksTrim(t.content) } else { "" }
    }

`as_int/1`: an integer as it is; a string by `Integer.parse/1` (an optional
sign, then digits, and whatever follows is ignored); anything else, floats
included, nothing. At most nine digits are read.

    let stacksParseIntPrefix(s: String): Int? {
      var i = String.begin;
      var negative = false;
      if (s.hasIndex(i) && (s[i] == 43 || s[i] == 45)) {
        negative = s[i] == 45;
        i = s.next(i);
      }
      var value = 0;
      var digits = 0;
      while (s.hasIndex(i) && s[i] >= 48 && s[i] <= 57 && digits < 9) {
        value = value * 10 + (s[i] - 48);
        digits += 1;
        i = s.next(i);
      }
      if (digits == 0) { null } else if (negative) { 0 - value } else { value }
    }

    let stacksAsInt(t: JsonSyntaxTree?): Int? {
      if (t != null) {
        if (t is JsonString) {
          stacksParseIntPrefix(t.content)
        } else if (t is JsonNumeric) {
          if (stacksIsFloatToken(t.asJsonNumericToken())) { null } else { do { t.asInt32() } orelse null }
        } else {
          null
        }
      } else {
        null
      }
    }

An object's property, or `null` for anything that is not an object.

    let stacksProp(t: JsonSyntaxTree?, key: String): JsonSyntaxTree? {
      if (t is JsonObject) { t.propertyValueOrNull(key) } else { null }
    }

    let stacksIsObject(t: JsonSyntaxTree?): Boolean {
      t is JsonObject
    }

`raw["x"] || []` for an array: the elements, or none.

    let stacksElements(t: JsonSyntaxTree?): List<JsonSyntaxTree> {
      if (t is JsonArray) { t.elements } else { [] }
    }

## JSON text for the array columns

    let stacksJsonStrings(xs: List<String>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      var i = 0;
      while (i < xs.length) { p.stringValue(xs[i]); i += 1; }
      p.endArray();
      p.toJsonString()
    }

    let stacksJsonInts(xs: List<Int>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      var i = 0;
      while (i < xs.length) { p.int32Value(xs[i]); i += 1; }
      p.endArray();
      p.toJsonString()
    }

## Small list helpers

    let stacksSortedInts(xs: List<Int>): List<Int> {
      xs.sorted { (a: Int, b: Int): Int => a - b }
    }

`Enum.uniq |> Enum.sort`.

    let stacksSortedUniqInts(xs: List<Int>): List<Int> {
      let sorted = stacksSortedInts(xs);
      let out = new ListBuilder<Int>();
      var i = 0;
      while (i < sorted.length) {
        if (i == 0 || sorted[i] != sorted[i - 1]) { out.add(sorted[i]); }
        i += 1;
      }
      out.toList()
    }

    let stacksJoinInts(xs: List<Int>, sep: String): String {
      sysJoin(xs.map { (x: Int): String => x.toString() }, sep)
    }

    let stacksContainsInt(xs: List<Int>, x: Int): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i] == x) { return true; }
        i += 1;
      }
      false
    }

    let stacksPlaceholders(count: Int, from: Int): String {
      let marks = new ListBuilder<String>();
      var i = 0;
      while (i < count) {
        marks.add("\$${(from + i).toString()}");
        i += 1;
      }
      sysJoin(marks.toList(), ",")
    }

    let stacksOrEmpty(s: String?): String {
      if (s != null) { s } else { "" }
    }
