# What went wrong

    let { sysUtcNow } = import("sys/src");

The Elixir passed atoms and tuples around (`:unauthorized`,
`{:rate_limited, reset}`, `{:many_roots, [1, 2]}`) and `explain/1` turned each
into a sentence. Here an error is one class with a `kind` (the atom's name, or
the tuple's first element) and the payload in the field that fits.

    export class ImporterError(public kind: String) {
      public var text: String? = null;
      public var number: Int = 0;
      public var numbers: List<Int> = [];
      public var texts: List<String> = [];
    }

    export let importerError(kind: String): ImporterError { new ImporterError(kind) }

    export let importerErrorText(kind: String, text: String?): ImporterError {
      let e = new ImporterError(kind);
      e.text = text;
      e
    }

    export let importerErrorNumber(kind: String, number: Int): ImporterError {
      let e = new ImporterError(kind);
      e.number = number;
      e
    }

    export let importerErrorNumbers(kind: String, numbers: List<Int>): ImporterError {
      let e = new ImporterError(kind);
      e.numbers = numbers;
      e
    }

    export let importerErrorTexts(kind: String, texts: List<String>): ImporterError {
      let e = new ImporterError(kind);
      e.texts = texts;
      e
    }

## inspect

`inspect/1` of the same value, because two documents quote it: a failed commit
or file fetch is written into the chapter as `(#{inspect(reason)})`.

    let importerQuoted(s: String): String {
      "\"${importerReplaceAll(importerReplaceAll(s, "\\", "\\\\"), "\"", "\\\"")}\""
    }

    let importerQuotedOrNil(s: String?): String {
      if (s != null) { importerQuoted(s) } else { "nil" }
    }

    let importerNumberList(xs: List<Int>): String {
      "[${importerJoin(xs.map { (n: Int): String => n.toString() }, ", ")}]"
    }

    export let importerInspect(e: ImporterError): String {
      let k = e.kind;
      if (k == "http") {
        "{:http, ${e.number.toString()}}"
      } else if (k == "transport") {
        "{:transport, ${importerQuotedOrNil(e.text)}}"
      } else if (k == "rejected") {
        "{:rejected, ${importerQuotedOrNil(e.text)}}"
      } else if (k == "rate_limited") {
        "{:rate_limited, ${importerQuotedOrNil(e.text)}}"
      } else if (k == "many_roots") {
        "{:many_roots, ${importerNumberList(e.numbers)}}"
      } else if (k == "off_chain") {
        "{:off_chain, ${importerNumberList(e.numbers)}}"
      } else if (k == "no_root") {
        "{:no_root, ${importerQuotedOrNil(e.text)}}"
      } else if (k == "duplicate_branches") {
        "{:duplicate_branches, [${importerJoin(e.texts.map { (t: String): String => importerQuoted(t) }, ", ")}]}"
      } else if (k == "crashed") {
        "{:crashed, ${importerQuotedOrNil(e.text)}}"
      } else if (k == "unexpected") {
        "{:ok, ${importerQuotedOrNil(e.text)}}"
      } else if (k == "other") {
        importerOrEmpty(e.text)
      } else {
        ":${k}"
      }
    }

An error that came back from a fetch, as the document quotes it:
`{:error, reason}`.

    export let importerInspectError(e: ImporterError): String {
      "{:error, ${importerInspect(e)}}"
    }

## explain

What went wrong, in words a person can act on. The messages are verbatim.

    let importerNumbersHashed(xs: List<Int>): String {
      "#${importerJoin(xs.map { (n: Int): String => n.toString() }, ", #")}"
    }

`back_at`: the reset header is a unix timestamp, said as a wall clock and as a
wait, because "resets at 1755 seconds" is not a thing anybody can act on.

    let importerBackAt(reset: String?, now: Int): String {
      let seconds = if (reset != null) { importerParseIntPrefix(reset) } else { null };
      if (seconds != null) {
        let wait = if (seconds > now) { seconds - now } else { 0 };
        let minuteOfDay = (seconds % 86400) / 60;
        let hh = importerPad(minuteOfDay / 60, 2);
        let mm = importerPad(minuteOfDay % 60, 2);
        "It comes back at ${hh}:${mm} UTC, in ${(wait / 60).toString()}m${(wait % 60).toString()}s."
      } else {
        "Give it a few minutes."
      }
    }

`now` is the unix time in seconds, for the rate-limit wait.

    export let importerExplainAt(e: ImporterError, now: Int): String {
      let k = e.kind;
      if (k == "many_roots") {
        "${e.numbers.length.toString()} pull requests are based on the default branch (${importerNumbersHashed(e.numbers)}). That is more than one stack, and this cannot tell which you meant."
      } else if (k == "no_root") {
        "No open pull request is based on ${importerOrEmpty(e.text)}, so there is no start to the chain."
      } else if (k == "off_chain") {
        "${e.numbers.length.toString()} pull request(s) are not on the chain: ${importerNumbersHashed(e.numbers)}. A stack is each one based on the one before it."
      } else if (k == "duplicate_branches") {
        "More than one open pull request comes from the same branch (${importerJoin(e.texts, ", ")}). A stack is one pull request per branch."
      } else if (k == "no_pull_requests") {
        "That repository has no open pull requests."
      } else if (k == "empty_query") {
        "Write a search query first."
      } else if (k == "rejected") {
        let said = e.text;
        if (said == null) {
          "GitHub would not run that search. Check the qualifiers and the dates."
        } else {
          "GitHub would not run that search: ${said}"
        }
      } else if (k == "no_results_field") {
        "GitHub answered the search with something this does not recognise."
      } else if (k == "crashed") {
        "That one crashed on the way in."
      } else if (k == "unauthorized") {
        "GitHub rejected the token."
      } else if (k == "forbidden") {
        "GitHub refused: the token may lack access, or you are rate limited. Without a token that is 60 requests an hour, and 10 searches a minute."
      } else if (k == "rate_limited") {
        "GitHub is rate limiting this. ${importerBackAt(e.text, now)} Without a token the allowance is 60 requests an hour; with one it is 5000, and a hundred pull requests is three hundred requests."
      } else if (k == "not_found") {
        "No such repository, or the token cannot see it."
      } else if (k == "bad_name") {
        "Owner and repository must look like GitHub names."
      } else if (k == "http") {
        "GitHub answered ${e.number.toString()}."
      } else if (k == "transport") {
        "Could not reach GitHub."
      } else {
        "Import failed: ${importerInspect(e)}"
      }
    }

    export let importerExplain(e: ImporterError): String {
      importerExplainAt(e, importerNowSeconds())
    }

    export let importerNowSeconds(): Int {
      let day = importerToday();
      let clock = sysUtcNow();
      let h = importerParseInt(importerSliceFrom(importerTake(clock, 13), 11));
      let m = importerParseInt(importerSliceFrom(importerTake(clock, 16), 14));
      let s = importerParseInt(importerSliceFrom(importerTake(clock, 19), 17));
      day * 86400 + (if (h != null) { h } else { 0 }) * 3600 +
        (if (m != null) { m } else { 0 }) * 60 + (if (s != null) { s } else { 0 })
    }
