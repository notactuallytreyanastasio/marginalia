# The query language

`Marginalia.Import.Query`: a GitHub-shaped query, run over pull requests
already fetched. It decides what is *kept*; GitHub's own search box decides
what is *fetched*. Nothing here touches the network.

> is:pr state:closed created:>@today-30d
> repo:phoenixframework/phoenix base:main -Bump
> merged:2025-04-01..2025-08-05 draft:false

A bare word is a substring of the title, a leading `-` negates a term, terms
are joined with AND. An unknown qualifier is an error and not a no-op: a typo
that silently means nothing lets somebody import a hundred and forty-seven pull
requests believing they filtered to nine.

Dates are day numbers (see `text.temper.md`). The clock is a parameter: every
function that reads `@today` has an `...At` twin taking today as a day number,
and the plain name passes `importerToday()`.

## The row

One light row per pull request, the same shape whether it came from a listing
or from a search. `state` is `open`, `closed` or `merged`; the three dates are
ISO 8601 strings or null.

    export class ImporterPull(
      public repo: String,
      public number: Int,
      public title: String,
      public url: String?,
      public state: String?,
      public draft: Boolean,
      public base: String?,
      public head: String?,
      public updatedAt: String?,
      public createdAt: String?,
      public mergedAt: String?,
    ) {}

## Terms

A comparison is `eq`, `gt`, `lt`, `gte`, `lte` (with `a`) or `between` (with
`a` and `b`), over numbers or day numbers.

    export class ImporterCmp(public kind: String, public a: Int, public b: Int) {}

A term. `kind` is `text` (`word`), `state` (`want`), `draft` (`wantDraft`),
`field` (`field` is `repo`, `base` or `head`; `want` is lower-cased), `number`
(`cmp`) or `date` (`field` is `created_at`, `updated_at` or `merged_at`;
`cmp`). `negated` is the leading `-`.

    export class ImporterTerm(public kind: String) {
      public var negated: Boolean = false;
      public var word: String = "";
      public var want: String = "";
      public var field: String = "";
      public var wantDraft: Boolean = false;
      public var cmp: ImporterCmp = new ImporterCmp("eq", 0, 0);
    }

`terms` is empty and `error` set when the query is wrong; an empty query is
no terms and no error.

    export class ImporterQuery(public terms: List<ImporterTerm>, public error: String?) {}

    export class ImporterFiltered(public kept: List<ImporterPull>, public error: String?) {}

    class ImporterTermResult(public term: ImporterTerm?, public error: String?) {}

    class ImporterCmpResult(public cmp: ImporterCmp?, public bad: String) {}

## Dates

`@today` and its offsets (`+` or `-`, a number, and `d`, `w`, `m` or `y`), or
`YYYY-MM-DD`; anything else is null. `@today` is lower case here, and the
offset is the whole of what follows it.

    export let importerDateAt(raw: String, today: Int): Int? {
      let text = importerTrim(raw);
      if (text == "@today") { return today; }
      if (importerStartsWith(text, "@today")) {
        let offset = importerAfterFirst(text, "@today");
        if (offset != null) { return importerOffsetDate(offset, today); }
        return null;
      }
      importerParseIso(text)
    }

    export let importerDate(raw: String): Int? { importerDateAt(raw, importerToday()) }

`^([+-])(\d+)([dwmy])$`.

    let importerOffsetDate(offset: String, today: Int): Int? {
      let cps = importerCps(offset);
      if (cps.length < 3) { return null; }
      if (cps[0] != 43 && cps[0] != 45) { return null; }
      let unit = cps[cps.length - 1];
      if (unit != 100 && unit != 119 && unit != 109 && unit != 121) { return null; }
      var n = 0;
      var i = 1;
      var digits = 0;
      while (i < cps.length - 1) {
        if (!importerIsDigit(cps[i])) { return null; }
        if (digits >= 6) { return null; }
        n = n * 10 + (cps[i] - 48);
        digits += 1;
        i += 1;
      }
      if (digits == 0) { return null; }
      let signed = if (cps[0] == 45) { 0 - n } else { n };
      if (unit == 100) {
        today + signed
      } else if (unit == 119) {
        today + signed * 7
      } else if (unit == 109) {
        importerShiftMonths(today, signed)
      } else {
        importerShiftMonths(today, signed * 12)
      }
    }

## Parsing

Whitespace, except inside double quotes: a title fragment with a space in it is
the ordinary reason to reach for quoting. This is `"[^"]*"|\S+` scanned over
the text, with the empty quotes `""` dropped.

    let importerTokens(text: String): List<String> {
      let cps = importerCps(text);
      let out = new ListBuilder<String>();
      var i = 0;
      while (i < cps.length) {
        if (importerIsSpace(cps[i])) {
          i += 1;
        } else {
          var j = i + 1;
          var quoted = false;
          if (cps[i] == 34) {
            var k = i + 1;
            while (k < cps.length && cps[k] != 34) { k += 1; }
            if (k < cps.length) {
              j = k + 1;
              quoted = true;
            }
          }
          if (!quoted) {
            while (j < cps.length && !importerIsSpace(cps[j])) { j += 1; }
          }
          let token = importerSlice(cps, i, j);
          if (token != "\"\"") { out.add(token); }
          i = j;
        }
      }
      out.toList()
    }

    let importerUnquote(v: String): String {
      importerTrim(importerTrimQuotes(v))
    }

    let importerTermOk(t: ImporterTerm?): ImporterTermResult { new ImporterTermResult(t, null) }

    let importerTermError(message: String): ImporterTermResult { new ImporterTermResult(null, message) }

    let importerIsOneOf(v: String, options: List<String>): Boolean {
      var i = 0;
      while (i < options.length) {
        if (options[i] == v) { return true; }
        i += 1;
      }
      false
    }

    let importerStateWord(v: String): Boolean {
      v == "open" || v == "closed" || v == "merged"
    }

    let importerStateTerm(v: String): ImporterTermResult {
      let t = new ImporterTerm("state");
      t.want = v;
      importerTermOk(t)
    }

    let importerDraftTerm(v: Boolean): ImporterTermResult {
      let t = new ImporterTerm("draft");
      t.wantDraft = v;
      importerTermOk(t)
    }

    let importerFieldTerm(field: String, v: String): ImporterTermResult {
      let t = new ImporterTerm("field");
      t.field = field;
      t.want = importerLower(v);
      importerTermOk(t)
    }

    let importerTextTerm(word: String): ImporterTermResult {
      let t = new ImporterTerm("text");
      t.word = word;
      importerTermOk(t)
    }

    let importerKnown = "is, state, draft, repo, base, head, number, created, updated, merged";

One piece of a comparison, cast to a number or a day number.

    let importerCast(raw: String, dates: Boolean, today: Int): Int? {
      if (dates) { importerDateAt(raw, today) } else { importerParseInt(importerTrim(raw)) }
    }

    let importerOne(raw: String, kind: String, dates: Boolean, today: Int): ImporterCmpResult {
      let v = importerCast(raw, dates, today);
      if (v != null) {
        new ImporterCmpResult(new ImporterCmp(kind, v, 0), "")
      } else {
        new ImporterCmpResult(null, raw)
      }
    }

`>=x`, `<=x`, `>x`, `<x` (in that order), else `a..b` (`*` for an open end),
else exact.

    let importerCompare(value: String, dates: Boolean, today: Int): ImporterCmpResult {
      if (importerStartsWith(value, ">=")) {
        return importerOne(importerSliceFrom(value, 2), "gte", dates, today);
      }
      if (importerStartsWith(value, "<=")) {
        return importerOne(importerSliceFrom(value, 2), "lte", dates, today);
      }
      if (importerStartsWith(value, ">")) {
        return importerOne(importerSliceFrom(value, 1), "gt", dates, today);
      }
      if (importerStartsWith(value, "<")) {
        return importerOne(importerSliceFrom(value, 1), "lt", dates, today);
      }
      let parts = importerSplitOnce(value, "..");
      if (parts.length == 1) { return importerOne(value, "eq", dates, today); }
      let from = parts[0];
      let to = parts[1];
      if (to == "*") { return importerOne(from, "gte", dates, today); }
      if (from == "*") { return importerOne(to, "lte", dates, today); }
      let a = importerCast(from, dates, today);
      let b = importerCast(to, dates, today);
      if (a != null) {
        if (b != null) {
          new ImporterCmpResult(new ImporterCmp("between", a, b), "")
        } else {
          new ImporterCmpResult(null, to)
        }
      } else {
        new ImporterCmpResult(null, from)
      }
    }

The text after the first `n` code points.

    let importerSliceFrom(s: String, n: Int): String {
      var i = String.begin;
      var k = 0;
      while (k < n && s.hasIndex(i)) {
        i = s.next(i);
        k += 1;
      }
      s.slice(i, s.end)
    }

    let importerNumberTerm(v: String, today: Int): ImporterTermResult {
      let r = importerCompare(v, false, today);
      let cmp = r.cmp;
      if (cmp != null) {
        let t = new ImporterTerm("number");
        t.cmp = cmp;
        importerTermOk(t)
      } else {
        importerTermError("`number:${v}` — a number, or >100, <100, 10..20.")
      }
    }

    let importerDateTerm(key: String, v: String, today: Int): ImporterTermResult {
      let r = importerCompare(v, true, today);
      let cmp = r.cmp;
      if (cmp != null) {
        let t = new ImporterTerm("date");
        t.field = "${key}_at";
        t.cmp = cmp;
        importerTermOk(t)
      } else {
        importerTermError(
          "`${key}:${v}` — ${r.bad} is not a date. Write 2025-08-05, or @today, or @today-30d, and compare with > < >= <= or a .. range.",
        )
      }
    }

    let importerQualifier(key: String, v: String, today: Int): ImporterTermResult {
      if (key == "is") {
        if (v == "pr") { return importerTermOk(null); }
        if (v == "issue") { return importerTermError("`is:issue` — there are only pull requests here."); }
        if (v == "draft") { return importerDraftTerm(true); }
        if (importerStateWord(v)) { return importerStateTerm(v); }
        return importerTermError("`is:${v}` — I know is:pr, is:draft, is:open, is:closed and is:merged.");
      }
      if (key == "state") {
        if (importerStateWord(v)) { return importerStateTerm(v); }
        return importerTermError("`state:${v}` — a pull request here is open, closed or merged.");
      }
      if (key == "draft") {
        if (v == "true" || v == "yes") { return importerDraftTerm(true); }
        if (v == "false" || v == "no") { return importerDraftTerm(false); }
        return importerTermError("`draft:${v}` — true or false.");
      }
      if (key == "repo" || key == "base" || key == "head") { return importerFieldTerm(key, v); }
      if (key == "number") { return importerNumberTerm(v, today); }
      if (key == "created" || key == "updated" || key == "merged") {
        return importerDateTerm(key, v, today);
      }
      importerTermError(
        "`${key}:${v}` — I do not know the qualifier `${key}`. I know ${importerKnown}, and a bare word matches the title.",
      )
    }

One token. A leading `-` negates the rest (a negated no-op stays a no-op). The
split is on the first `:`: none, or one at position 0, is a bare word.

    let importerTerm(token: String, today: Int): ImporterTermResult {
      if (importerStartsWith(token, "-")) {
        let inner = importerTerm(importerSliceFrom(token, 1), today);
        let t = inner.term;
        if (t != null) {
          t.negated = !t.negated;
          return importerTermOk(t);
        }
        return inner;
      }
      let parts = importerSplitOnce(token, ":");
      if (parts.length == 1) { return importerTextTerm(importerUnquote(token)); }
      if (parts[0].isEmpty) { return importerTextTerm(importerUnquote(token)); }
      importerQualifier(importerLower(parts[0]), importerUnquote(parts[1]), today)
    }

    export let importerQueryParseAt(text: String, today: Int): ImporterQuery {
      let terms = new ListBuilder<ImporterTerm>();
      let tokens = importerTokens(text);
      var i = 0;
      while (i < tokens.length) {
        let r = importerTerm(tokens[i], today);
        let why = r.error;
        if (why != null) { return new ImporterQuery([], why); }
        let t = r.term;
        if (t != null) { terms.add(t); }
        i += 1;
      }
      new ImporterQuery(terms.toList(), null)
    }

    export let importerQueryParse(text: String): ImporterQuery {
      importerQueryParseAt(text, importerToday())
    }

## Matching

The day a stored ISO timestamp falls on: its first ten characters. A missing or
unparseable date is `null`, which fails every comparison: an unmerged pull
request has no `merged_at`, and `merged:>x` should not match it. `null` is not
"before everything", it is "not a date".

    export let importerPullDay(iso: String?): Int? {
      if (iso != null) { importerParseIso(importerTake(iso, 10)) } else { null }
    }

    let importerCompares(cmp: ImporterCmp, x: Int): Boolean {
      if (cmp.kind == "eq") { x == cmp.a } else if (cmp.kind == "gt") { x > cmp.a } else if (cmp.kind == "lt") { x < cmp.a } else if (cmp.kind == "gte") { x >= cmp.a } else if (cmp.kind == "lte") { x <= cmp.a } else { x >= cmp.a && x <= cmp.b }
    }

    let importerPullField(pull: ImporterPull, field: String): String? {
      if (field == "repo") { pull.repo } else if (field == "base") { pull.base } else if (field == "head") { pull.head } else if (field == "created_at") { pull.createdAt } else if (field == "updated_at") { pull.updatedAt } else { pull.mergedAt }
    }

    let importerOrEmpty(s: String?): String { if (s != null) { s } else { "" } }

    let importerHit(t: ImporterTerm, pull: ImporterPull): Boolean {
      var hit = false;
      if (t.kind == "text") {
        hit = importerContains(importerLower(pull.title), importerLower(t.word));
      } else if (t.kind == "state") {
        let state = pull.state;
        hit = (if (state != null) { state } else { "open" }) == t.want;
      } else if (t.kind == "draft") {
        hit = pull.draft == t.wantDraft;
      } else if (t.kind == "field") {
        hit = importerLower(importerOrEmpty(importerPullField(pull, t.field))) == t.want;
      } else if (t.kind == "number") {
        hit = importerCompares(t.cmp, pull.number);
      } else {
        let day = importerPullDay(importerPullField(pull, t.field));
        if (day != null) { hit = importerCompares(t.cmp, day); }
      }
      if (t.negated) { !hit } else { hit }
    }

Whether one pull request satisfies every term of a parsed query.

    export let importerQueryMatch(query: ImporterQuery, pull: ImporterPull): Boolean {
      var i = 0;
      while (i < query.terms.length) {
        if (!importerHit(query.terms[i], pull)) { return false; }
        i += 1;
      }
      true
    }

Keep the pull requests matching `text`; the error is something the reader can
fix. An empty query keeps everything.

    export let importerQueryFilterAt(pulls: List<ImporterPull>, text: String, today: Int): ImporterFiltered {
      let q = importerQueryParseAt(text, today);
      let why = q.error;
      if (why != null) { return new ImporterFiltered([], why); }
      if (q.terms.length == 0) { return new ImporterFiltered(pulls, null); }
      let kept = new ListBuilder<ImporterPull>();
      var i = 0;
      while (i < pulls.length) {
        if (importerQueryMatch(q, pulls[i])) { kept.add(pulls[i]); }
        i += 1;
      }
      new ImporterFiltered(kept.toList(), null)
    }

    export let importerQueryFilter(pulls: List<ImporterPull>, text: String): ImporterFiltered {
      importerQueryFilterAt(pulls, text, importerToday())
    }

## Why nothing matched

`created:@today-90d` is that day, the one ninety days ago, and what anybody
typing it meant was everything since. A bare date is an exact day here because
that is what it is on GitHub; but a rule that is right and surprising should
say so when the list has just gone empty. `was` and `try` are the two halves a
page sets in `<code>`.

    export class ImporterHint(public was: String, public tryThis: String) {}

`\b(created|updated|merged):([^\s<>=]\S*)`, the first match.

    let importerHintAt(cps: List<Int>, i: Int, word: String): Int {
      let w = importerCps(word);
      if (i + w.length >= cps.length) { return -1; }
      var k = 0;
      while (k < w.length) {
        if (cps[i + k] != w[k]) { return -1; }
        k += 1;
      }
      if (cps[i + w.length] != 58) { return -1; }
      let start = i + w.length + 1;
      if (start >= cps.length) { return -1; }
      let c = cps[start];
      if (importerIsSpace(c) || c == 60 || c == 62 || c == 61) { return -1; }
      start
    }

    export let importerQueryHint(text: String): ImporterHint? {
      let cps = importerCps(text);
      var i = 0;
      while (i < cps.length) {
        let boundary = i == 0 || !importerIsWordChar(cps[i - 1]);
        if (boundary) {
          let words = ["created", "updated", "merged"];
          var w = 0;
          while (w < words.length) {
            let start = importerHintAt(cps, i, words[w]);
            if (start >= 0) {
              var end = start + 1;
              while (end < cps.length && !importerIsSpace(cps[end])) { end += 1; }
              let value = importerSlice(cps, start, end);
              if (importerContains(value, "..")) { return null; }
              return new ImporterHint("${words[w]}:${value}", "${words[w]}:>${value}");
            }
            w += 1;
          }
        }
        i += 1;
      }
      null
    }

## Expanding `@today` for GitHub

The two boxes take different languages (GitHub's goes over the wire, this
module's never leaves the machine) but `@today-30d` reads like it belongs in
both. GitHub answers it with a 422 about ISO 8601, which is correct and
useless. It is our syntax, so translating it is our job. Anything that is not
a `@today` expression is left exactly as it was.

The lookahead `(?![\w-])` is the difference between translating and mangling:
without it `@today-3fortnights` matches the bare `@today`.

    let importerLowerAscii(cp: Int): Int {
      if (cp >= 65 && cp <= 90) { cp + 32 } else { cp }
    }

    let importerAtToday(cps: List<Int>, i: Int): Boolean {
      let w = importerCps("@today");
      if (i + w.length > cps.length) { return false; }
      var k = 0;
      while (k < w.length) {
        if (importerLowerAscii(cps[i + k]) != w[k]) { return false; }
        k += 1;
      }
      true
    }

    let importerLookaheadOk(cps: List<Int>, end: Int): Boolean {
      if (end >= cps.length) { return true; }
      !(importerIsWordChar(cps[end]) || cps[end] == 45)
    }

The end of the `@today` expression starting at `i`, or -1: the offset group
first (`[+-]\d+[dwmy]`), and without it if the lookahead refuses the longer
match.

    let importerExpressionEnd(cps: List<Int>, i: Int): Int {
      let bare = i + 6;
      if (bare < cps.length && (cps[bare] == 43 || cps[bare] == 45)) {
        var j = bare + 1;
        while (j < cps.length && importerIsDigit(cps[j])) { j += 1; }
        if (j > bare + 1 && j < cps.length) {
          let unit = importerLowerAscii(cps[j]);
          if (unit == 100 || unit == 119 || unit == 109 || unit == 121) {
            if (importerLookaheadOk(cps, j + 1)) { return j + 1; }
          }
        }
      }
      if (importerLookaheadOk(cps, bare)) { bare } else { -1 }
    }

    export let importerExpandAt(text: String, today: Int): String {
      let cps = importerCps(text);
      let sb = new StringBuilder();
      var i = 0;
      while (i < cps.length) {
        var done = false;
        if (cps[i] == 64 && importerAtToday(cps, i)) {
          let end = importerExpressionEnd(cps, i);
          if (end >= 0) {
            let token = importerSlice(cps, i, end);
            let day = importerDateAt(importerLower(token), today);
            if (day != null) {
              sb.append(importerIsoDate(day));
            } else {
              sb.append(token);
            }
            i = end;
            done = true;
          }
        }
        if (!done) {
          sb.append(importerChr(cps[i]));
          i += 1;
        }
      }
      sb.toString()
    }

    export let importerExpand(text: String): String {
      importerExpandAt(text, importerToday())
    }
