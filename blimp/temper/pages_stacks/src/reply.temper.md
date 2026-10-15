# Answering

What the four pages share: one way to answer with a rendered `<main>` whether
the request was a page or an event, the small readers for an event's JSON, and
the one way to refuse an event nobody handles.

Every top-level name in this library is shared by all of its files and, in the
built program, with every other library's: the private helpers start with `pk`.

    let { Ctx, webMeta, webPage, webEventReply, webPutFlash, uiGet, uiPut } = import("webcore/src");
    let { Response } = import("http/src");
    let { JsonObject, JsonString, JsonInt } = import("std/json");
    let { sysStringTrim } = import("sys/src");
    let { StackFlash } = import("stacks/src");

An event answers with the region, the flash and, while a run is going, the
poll interval (it has to be repeated here: the attribute lives inside the
region, and a reply without it stops the polling). A plain request answers
with the whole page. `title` is the page title.

    let pkRender(ctx: Ctx, title: String, tree: List<AnyValue>, flash: Pair<String, String>?, poll: Int?): Response throws Bubble {
      if (ctx.isAjax) {
        webEventReply(ctx, tree, [], flash, poll)
      } else {
        let f = flash;
        if (f != null) { webPutFlash(ctx, f.key, f.value); }
        webPage(ctx, webMeta(title), tree, poll, "app")
      }
    }

A `StackFlash` as the pair the replies take.

    let pkFlashPair(f: StackFlash): Pair<String, String> {
      new Pair(f.level, f.text)
    }

An event the page does not have. A crash with the names in the log is better
than an answer that looks like success.

    let pkUnhandledEvent(page: String, event: String): Response throws Bubble {
      console.log("pages_stacks: ${page} has no event ${event}");
      bubble()
    }

## Reading a payload

A string field; a number is read as its digits; anything else, and a missing
key, is the empty string.

    let pkStr(payload: JsonObject, key: String): String {
      let v = payload.propertyValueOrNull(key);
      if (v is JsonString) {
        v.content
      } else if (v is JsonInt) {
        v.content.toString()
      } else { "" }
    }

    let pkTrim(s: String): String { sysStringTrim(s) }

    let pkOr(s: String?, d: String): String {
      if (s != null) { s } else { d }
    }

    let pkStartsWith(s: String, prefix: String): Boolean {
      if (s == "" || prefix == "") { return false; }
      let parts = s.split(prefix);
      parts.length > 1 && parts.getOr(0, "x") == ""
    }

Everything after the first `sep`, or the empty string. (`split` cuts at every
one.)

    let pkAfterFirst(s: String, sep: String): String {
      let parts = s.split(sep);
      if (parts.length < 2) { return ""; }
      var out = "";
      var i = 1;
      while (i < parts.length) {
        out = if (i == 1) { parts.getOr(i, "") } else { "${out}${sep}${parts.getOr(i, "")}" };
        i += 1;
      }
      out
    }

The text before the first `sep`.

    let pkBeforeFirst(s: String, sep: String): String {
      s.split(sep).getOr(0, "")
    }

## What the page last saw of a run

The LiveView learned that a pass ended from a message and put a flash up on
every page watching. Here a page only learns when it is asked for, so what it
last looked at is kept in the session's UI state, under a key, as the run's
identity and status (`<started_at>|<status>`, or `none`). A flash is due when
a run has ended and what the page last saw was a different state of things; a
page that has never looked before is told nothing, so opening an old folder
does not announce a pass finished last month.

`seen` is what the page held, `finished` whether the run there now has ended;
this answers whether the flash is due.

    let pkFlashDue(seen: String?, current: String, finished: Boolean): Boolean {
      if (!finished) { return false; }
      if (seen == null) { return false; }
      seen != current
    }

    let pkRemember(ctx: Ctx, key: String, current: String): Void {
      let seen = uiGet(ctx, key);
      if (seen == null || seen != current) { uiPut(ctx, key, current); }
    }
