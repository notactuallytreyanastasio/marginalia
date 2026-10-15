# What the pages share

Small helpers: how a number is printed, how a title is cut, how a payload is
read, and the few things the pages keep in the session's UI state. Every
top-level name in this library is shared with every other library in the
built program, so the private helpers all start with `pgc`.

    let { Ctx, PageMeta, uiGet, uiPut, uiDelete, webPage, webPutFlash } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject, JsonString, JsonNumeric } = import("std/json");
    let { sysUtf8Downcase, sysUtf8Upcase, sysGraphemeTake, sysGraphemeLength, sysJoin } = import("sys/src");
    let { linksParseIntPrefix } = import("links/src");
    let { casesName, casesRank } = import("cases/src");
    let { Work } = import("works/src");

## Numbers and words

`plural(1, w) = w`, otherwise `w` and an `s`.

    export let pagesCasesPlural(n: Int, word: String): String {
      if (n == 1) { word } else { "${word}s" }
    }

`fmt/1` of the index: 1000 and over is thousands to one decimal and a `k`
(`2.0k`, `1.2k`), rounded half up; below that the number.

    export let pagesCasesFmt(n: Int): String {
      if (n >= 1000) {
        let tenths = (n + 50) / 100;
        "${(tenths / 10).toString()}.${(tenths % 10).toString()}k"
      } else {
        n.toString()
      }
    }

Everything after the first `n` characters.

    let pgcDropChars(s: String, n: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < n && s.hasIndex(i)) {
        i = s.next(i);
        k += 1;
      }
      s.slice(i, s.end)
    }

`commas/1` of the case page: digits grouped by thousands.

    export let pagesCasesCommas(n: Int): String {
      let parts = new ListBuilder<String>();
      var rest = n.toString();
      var done = false;
      while (!done) {
        let len = sysGraphemeLength(rest);
        if (len <= 3) {
          parts.add(rest);
          done = true;
        } else {
          parts.add(pgcDropChars(rest, len - 3));
          rest = sysGraphemeTake(rest, len - 3);
        }
      }
      let out = new ListBuilder<String>();
      var i = parts.length - 1;
      while (i >= 0) {
        out.add(parts[i]);
        i -= 1;
      }
      sysJoin(out.toList(), ",")
    }

`String.capitalize`: the first letter up, the rest down.

    export let pagesCasesCapitalize(s: String): String {
      if (s == "") { return s; }
      "${sysUtf8Upcase(sysGraphemeTake(s, 1))}${sysUtf8Downcase(pgcDropChars(s, 1))}"
    }

## Titles and roles

`short`, `role` and `short_title` of the HEEx are one function: the part of a
title after the first ` — `, else the whole title.

    export let pagesCasesShortTitle(title: String): String { casesName(title) }

The document name of a work, `—` for none (`role(nil)`).

    export let pagesCasesRoleName(w: Work?): String {
      if (w != null) { casesName(w.title) } else { "—" }
    }

Two or three letters for the `.who` of a connection: `Op`, `Diss`, `Conc`,
`Arg`, `?`, and `—` for no work at all.

    export let pagesCasesRoleShort(w: Work?): String {
      if (w != null) { pgcRoleLetters(w.collectionRole) } else { "—" }
    }

    let pgcRoleLetters(r: String?): String {
      if (r == "opinion") {
        "Op"
      } else if (r == "dissent") {
        "Diss"
      } else if (r == "concurrence") {
        "Conc"
      } else if (r == "argument") {
        "Arg"
      } else {
        "?"
      }
    }

`rank/1` of the read page: the index of the role in the reading order, 9 for
none, which picks the colour class `s0` to `s9`.

    export let pagesCasesRank9(role: String?): Int {
      let r = casesRank(role);
      if (r < 4) { r } else { 9 }
    }

## Classes and text

The non-empty strings joined with a space: a HEEx class list with its `false`
and `nil` entries dropped.

    export let pagesCasesCls(parts: List<String>): String {
      sysJoin(parts.filter { (p: String): Boolean => p != "" }, " ")
    }

    export let pagesCasesContains(hay: String, needle: String): Boolean {
      if (needle == "") { true } else { hay.split(needle).length > 1 }
    }

## Payloads

A field of an event's payload as text: a string as it is, a number in its
written form, anything else the empty string.

    export let pagesCasesField(payload: JsonObject, key: String): String {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) {
        v.content
      } else if (v is JsonNumeric) {
        v.asJsonNumericToken()
      } else {
        ""
      }
    }

A field that is a whole number, or null.

    export let pagesCasesFieldInt(payload: JsonObject, key: String): Int? {
      let s = pagesCasesField(payload, key);
      if (s == "") { null } else { linksParseIntPrefix(s) }
    }

## UI state

What a LiveView held in assigns and the database does not know. Each value is
its own key, `cases:<slug>:<name>`, so a page can drop one without parsing the
rest. A flag is the string `1`.

    export let pagesCasesKey(slug: String, name: String): String { "cases:${slug}:${name}" }

    export let pagesCasesGetKey(ctx: Ctx, slug: String, name: String): String? {
      uiGet(ctx, pagesCasesKey(slug, name))
    }

    export let pagesCasesPutKey(ctx: Ctx, slug: String, name: String, value: String): Void {
      uiPut(ctx, pagesCasesKey(slug, name), value);
    }

Dropping a key that is not there does not touch the session.

    export let pagesCasesDropKey(ctx: Ctx, slug: String, name: String): Void {
      if (uiGet(ctx, pagesCasesKey(slug, name)) != null) { uiDelete(ctx, pagesCasesKey(slug, name)); }
    }

    export let pagesCasesFlag(ctx: Ctx, slug: String, name: String): Boolean {
      pagesCasesGetKey(ctx, slug, name) == "1"
    }

    export let pagesCasesSetFlag(ctx: Ctx, slug: String, name: String, on: Boolean): Void {
      if (on) { pagesCasesPutKey(ctx, slug, name, "1"); } else { pagesCasesDropKey(ctx, slug, name); }
    }

An optional string: the key's value, the empty string being none.

    export let pagesCasesOptional(ctx: Ctx, slug: String, name: String): String? {
      let v = pagesCasesGetKey(ctx, slug, name);
      if (v == null) { null } else if (v == "") { null } else { v }
    }

    export let pagesCasesSetOptional(ctx: Ctx, slug: String, name: String, value: String?): Void {
      if (value == null) { pagesCasesDropKey(ctx, slug, name); } else { pagesCasesPutKey(ctx, slug, name, value); }
    }

## Answering

A page and an event answer alike: the region on an event, the whole document
on a plain request. A flash rides in the session either way. Event replies go
through `webPage` and not `webEventReply` so that the bare and bleed layouts
get their own region wrapper back.

    export let pagesCasesAnswer(ctx: Ctx, meta: PageMeta, tree: List<AnyValue>, flash: Pair<String, String>?, layout: String): Response throws Bubble {
      let f = flash;
      if (f != null) { webPutFlash(ctx, f.key, f.value); }
      webPage(ctx, meta, tree, null, layout)
    }

An event this page does not have. A crash with the names in the log is
better than an answer that looks like success.

    export let pagesCasesUnhandled(page: String, event: String): Response throws Bubble {
      console.log("pages_cases: ${page} has no event ${event}");
      bubble()
    }
