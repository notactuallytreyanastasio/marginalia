# Mutterings: the words in front of the three dots

`Marginalia.Mutterings`, `Mutterings.Mutter` and `Mutterings.Clock`. While a
model is reading, a page shows a line in front of the dots. The lines are
written by a model too, with one prompt, and kept in `mutterings`: a hundred
the first time, ten more every half hour.

    let { Db, DbRow } = import("db/src");
    let { sysFork, sysExit, sysSleepMs, sysUtcNow, sysDbOpen, sysStringTrim, sysGraphemeLength } = import("sys/src");
    let { LlmClient, LlmCall, LlmMessage, LlmError, Result, llmConfigFromEnv, llmProvider, llmErrorText } = import("llm/src");

## The record

    export class Mutter(
      public id: Int,
      public text: String,
      public source: String,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): Mutter throws Bubble {
        new Mutter(row.int("id"), row.str("text"), row.str("source"), row.str("inserted_at"), row.str("updated_at"))
      }
    }

    export let mutteringsColumns(): String { "id, text, source, inserted_at, updated_at" }

## Constants

The system prompt is Bobby's, verbatim, spelling and all ("teh").

    export let mutteringsPrompt(): String {
      "You are Fyordor Dostoyevsky. You live in the modern day. You work a job at a grilled cheese sandwich factory in Menlo Park, CA. Give some words you might utter while working alone at teh sandwich counter. Keep it 240 characters or less."
    }

What the table is filled to, how many a top-up adds, the longest line kept,
and how many shown lines a page remembers (`mutteringsRemember`).

    export let mutteringsSeedSize(): Int { 100 }
    export let mutteringsBatchSize(): Int { 10 }
    export let mutteringsMaxChars(): Int { 240 }
    export let mutteringsRemember(): Int { 40 }

## Picking

`Mutterings.some/1`. The Elixir kept the last 40 lines shown in the
LiveView process dictionary. A request here is a fresh process, so the page
keeps them in its ui state and passes them in as `recent` (ids), and takes
the lines it gets back (ids, in `Mutter.id`) to build the next `recent`
with `mutteringsRemembered`.

Up to `n` random lines whose ids are not in `recent`; `[]` when the table is
empty. A page that has seen most of the table forgets: when the pick comes back
empty and `recent` is not, it picks again with nothing excluded. The ids are
integers, so they are written into the SQL as numbers.

    let mutteringsPick(db: Db, n: Int, except: List<Int>): List<Mutter> throws Bubble {
      let ids = new ListBuilder<String>();
      for (let id of except) { ids.add(id.toString()); }
      let notIn = if (ids.length == 0) {
        ""
      } else {
        " WHERE id NOT IN (${ids.toList().join(",") { (s: String): String => s }})"
      };
      let out = new ListBuilder<Mutter>();
      let rows = db.query(
        "SELECT ${mutteringsColumns()} FROM mutterings${notIn} ORDER BY random() LIMIT ${n.toString()}",
        [],
      );
      for (let row of rows) { out.add(Mutter.fromRow(row)); }
      out.toList()
    }

    export let mutteringsSome(db: Db, n: Int, recent: List<Int>): List<Mutter> throws Bubble {
      if (n <= 0) { return []; }
      let first = mutteringsPick(db, n, recent);
      if (first.length == 0 && recent.length > 0) {
        mutteringsPick(db, n, [])
      } else {
        first
      }
    }

The next `recent`: the ids of `picked` followed by the old ones, the first 40
(`Enum.take(lines ++ seen, 40)`). In Elixir, when the pick fell back to
"forget everything", the memory was cleared before the new lines went in;
here the old ids stay behind the new ones until they fall off the end of the
40, which only differs for a table of fewer than 40 lines.

    export let mutteringsRemembered(picked: List<Mutter>, recent: List<Int>): List<Int> {
      let out = new ListBuilder<Int>();
      var i = 0;
      while (i < picked.length && out.length < mutteringsRemember()) {
        out.add(picked[i].id);
        i += 1;
      }
      var j = 0;
      while (j < recent.length && out.length < mutteringsRemember()) {
        out.add(recent[j]);
        j += 1;
      }
      out.toList()
    }

`Mutterings.one/0`: one random line, or null.

    export let mutteringsOne(db: Db): Mutter? throws Bubble {
      let got = mutteringsPick(db, 1, []);
      if (got.length == 0) { null } else { got[0] }
    }

    export let mutteringsCount(db: Db): Int throws Bubble {
      let row = db.one("SELECT count(*) AS n FROM mutterings", []);
      if (row == null) { 0 } else { row.int("n") }
    }

## Parsing a reply

The reply is asked for as bare lines and rarely arrives that way. Each line
is cleaned exactly as the Elixir `clean/1`:

1. trim (Unicode whitespace);
2. strip one leading bullet (`-`, `*`, or the bullet character) or number
   (`12.` or `12)`), and the whitespace after it;
3. trim;
4. strip a leading run of the quote characters `" " " ' '` (straight double,
   curly double, low double, straight single, curly single) and a trailing
   run of `" " ' '` (straight double, closing curly double, straight single,
   closing curly single);
5. trim.

Then a line is dropped if it is empty, ends with a colon (the model
introducing the list), or is longer than 240 characters, and duplicates are
dropped keeping the first. The regex's `\d` is read as ASCII digits only.
Length is graphemes, as `String.length` is.

    let isOpenQuote(cp: Int): Boolean {
      cp == 0x22 || cp == 0x201C || cp == 0x201E || cp == 0x27 || cp == 0x2018
    }

    let isCloseQuote(cp: Int): Boolean {
      cp == 0x22 || cp == 0x201D || cp == 0x27 || cp == 0x2019
    }

    let isDigit(cp: Int): Boolean { cp >= 0x30 && cp <= 0x39 }

The text after one leading bullet or number, or the text itself.

    let stripMarker(s: String): String {
      if (!s.hasIndex(String.begin)) { return s; }
      let c = s[String.begin];
      if (c == 0x2D || c == 0x2A || c == 0x2022) {
        return s.slice(s.next(String.begin), s.end);
      }
      var i = String.begin;
      while (s.hasIndex(i) && isDigit(s[i])) { i = s.next(i); }
      if (i != String.begin && s.hasIndex(i) && (s[i] == 0x2E || s[i] == 0x29)) {
        return s.slice(s.next(i), s.end);
      }
      s
    }

    let stripQuotes(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && isOpenQuote(s[b])) { b = s.next(b); }
      var e = s.end;
      while (e > b && isCloseQuote(s[s.prev(e)])) { e = s.prev(e); }
      s.slice(b, e)
    }

    export let mutteringsClean(line: String): String {
      let a = sysStringTrim(line);
      let b = sysStringTrim(stripMarker(a));
      sysStringTrim(stripQuotes(b))
    }

    let endsWithColon(s: String): Boolean {
      s.hasIndex(String.begin) && s[s.prev(s.end)] == 0x3A
    }

    let listHas(xs: List<String>, s: String): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i] == s) { return true; }
        i += 1;
      }
      false
    }

`Mutterings.parse/1`. A null reply is no lines.

    export let mutteringsParse(text: String?): List<String> {
      if (text == null) { [] } else { mutteringsParseText(text) }
    }

    let mutteringsParseText(text: String): List<String> {
      let out = new ListBuilder<String>();
      let raws = text.split("\n");
      var k = 0;
      while (k < raws.length) {
        let line = mutteringsClean(raws[k]);
        k += 1;
        if (line != "" && !endsWithColon(line) && sysGraphemeLength(line) <= mutteringsMaxChars()) {
          if (!listHas(out.toList(), line)) { out.add(line); }
        }
      }
      out.toList()
    }

## Asking and storing

The user message of call 9, verbatim from the notes.

    export let mutteringsAsk(n: Int): String {
      "Give ${n.toString()} of them. One per line. No numbering, no quotation marks, no introduction and no commentary: nothing but the words themselves."
    }

The result of a generate, seed or tick: how many were added, or why not.
Exactly one of the two is meaningful; `error` is null on success.

    export class MutteringsResult(public added: Int, public error: String?) {}

The model call: the cheapest the provider has. On DeepSeek that is
`deepseek-chat` (the same model with thinking off; the bare model id turns
reasoning on); otherwise the provider's fast model. Effort `none`,
temperature 1.2, `40 * n + 100` tokens, 60 seconds. Which provider is read
from the environment, as the client does; a fake client ignores the model.
A reply without text is the error `no_content`.

    let mutteringsReply(llm: LlmClient, n: Int): Result<String, String> {
      let config = llmConfigFromEnv();
      let model = if (config.provider == "deepseek") { "deepseek-chat" } else { llmProvider(config.provider).fastModel };
      let call = new LlmCall(
        [new LlmMessage("system", mutteringsPrompt()), new LlmMessage("user", mutteringsAsk(n))],
        model, "none", 40 * n + 100, 1.2, false, [], null, 60000,
      );
      let got = llm.chat(call);
      let err = got.err;
      if (err != null) { return new Result<String, String>(null, llmErrorText(err)); }
      let reply = got.ok;
      if (reply != null) {
        let content = reply.content;
        if (content != null) { return new Result<String, String>(content, null); }
      }
      new Result<String, String>(null, "no_content")
    }

`Mutterings.generate/2`: ask for `n` lines, parse, keep the first `n`, insert
them with the `source`. A line the table already has is not an error and not
a row. No usable line is the error `nothing_usable`; a call error comes back
as `kind: detail`. Takes `text` as a parameter instead of asking so tests can
feed a reply; `mutteringsGenerate` is the one that asks.

    export let mutteringsStore(db: Db, text: String?, n: Int, source: String): MutteringsResult throws Bubble {
      let lines = mutteringsParse(text);
      if (lines.length == 0) { return new MutteringsResult(0, "nothing_usable"); }
      var added = 0;
      var i = 0;
      let now = sysUtcNow();
      while (i < lines.length && i < n) {
        added += db.exec(
          "INSERT OR IGNORE INTO mutterings (text, source, inserted_at, updated_at) VALUES ($1, $2, $3, $3)",
          [lines[i], source, now],
        );
        i += 1;
      }
      new MutteringsResult(added, null)
    }

    export let mutteringsGenerate(db: Db, llm: LlmClient, n: Int, source: String): MutteringsResult throws Bubble {
      let got = mutteringsReply(llm, n);
      let err = got.err;
      if (err != null) { return new MutteringsResult(0, err); }
      mutteringsStore(db, got.ok, n, source)
    }

## Seeding and topping up

`Mutterings.seed/1`: fill the table to 100, if it is short. The model gives
fewer lines than it is asked for (57 of a hundred the first time) and some are
already there, so this asks again, up to four rounds, each for what is still
missing, and stops when the table is full or a call fails. An error in the
first round, with nothing added yet, is the result's error; an error later
returns what was added so far.

    export let mutteringsSeedResult(db: Db, llm: LlmClient): MutteringsResult throws Bubble {
      var added = 0;
      var tries = 4;
      while (tries > 0) {
        let missing = mutteringsSeedSize() - mutteringsCount(db);
        if (missing <= 0) { return new MutteringsResult(added, null); }
        let r = mutteringsGenerate(db, llm, missing, "seed");
        let err = r.error;
        if (err != null) {
          if (added == 0) { return r; }
          return new MutteringsResult(added, null);
        }
        added += r.added;
        tries -= 1;
      }
      new MutteringsResult(added, null)
    }

The count only: how many lines the seed added, 0 on failure (the reason is
in `mutteringsSeedResult`).

    export let mutteringsSeed(db: Db, llm: LlmClient): Int throws Bubble {
      mutteringsSeedResult(db, llm).added
    }

`Mutterings.topup/1`: add a batch of ten with source `cron`.

    export let mutteringsTopup(db: Db, llm: LlmClient): MutteringsResult throws Bubble {
      mutteringsGenerate(db, llm, mutteringsBatchSize(), "cron")
    }

## The clock

One tick, the work of `Clock`'s `:tick`: seed when the table is short of 100,
otherwise add ten. The Elixir clock held a `seeded` flag in its process;
this one is stateless and reads the table instead, so a seed that fell short
is tried again next tick rather than followed by a top-up. Never throws: any
failure, a bubble included, is a logged line and the next tick. Answers how
many lines were added.

    export let mutteringsTick(db: Db, llm: LlmClient): Int {
      var added = 0;
      let ok = do {
        if (mutteringsCount(db) < mutteringsSeedSize()) {
          let r = mutteringsSeedResult(db, llm);
          let err = r.error;
          if (err != null) {
            console.log("marginalia mutterings: ${err}");
          } else {
            added = r.added;
            console.log("marginalia mutterings: seeded ${added.toString()}");
          }
        } else {
          let r = mutteringsTopup(db, llm);
          let err = r.error;
          if (err != null) {
            console.log("marginalia mutterings: ${err}");
          } else {
            added = r.added;
            console.log("marginalia mutterings: added ${added.toString()}");
          }
        }
        true
      } orelse false;
      if (!ok) { console.log("marginalia mutterings: tick failed"); }
      added
    }

The loop, with its timings as parameters so a test can run one tick: sleep
`firstMs`, then tick, sleep `everyMs`, tick, and so on. `ticks` is how many
ticks to run; 0 means for ever. Opens its own `Db` from `dbPath` (a clock is
a process of its own and must not share the server's connection), and
reopens nothing after that. A database that cannot be opened is one logged
line and the loop ends.

    export let mutteringsClockLoop(dbPath: String, makeLlm: fn (): LlmClient, firstMs: Int, everyMs: Int, ticks: Int): Void {
      let db = runsOpenOwn(dbPath);
      if (db != null) {
        mutteringsClockWith(db, makeLlm, firstMs, everyMs, ticks);
      } else {
        console.log("marginalia mutterings: cannot open ${dbPath}");
      }
    }

    let mutteringsClockWith(db: Db, makeLlm: fn (): LlmClient, firstMs: Int, everyMs: Int, ticks: Int): Void {
      var done = 0;
      sysSleepMs(firstMs);
      while (ticks == 0 || done < ticks) {
        mutteringsTick(db, makeLlm());
        done += 1;
        if (ticks == 0 || done < ticks) { sysSleepMs(everyMs); }
      }
    }

`Mutterings.Clock` as a process: first tick 5 seconds after start, then every
30 minutes (1,800,000 ms), for ever. It never returns; call it only in a
process that exists for it, which is what `mutteringsClockStart` does.
`makeLlm` is `llmFromEnv`, so the key is read in the clock's process, and a
key that appears after boot is seen at the next tick.

    export let mutteringsClockMain(dbPath: String, makeLlm: fn (): LlmClient): Void {
      mutteringsClockLoop(dbPath, makeLlm, 5000, 1800000, 0);
    }

How the server starts it, once, at boot, after `recoveryRun` and before the
accept loop:

`let clockPid = mutteringsClockStart(dbPath, db, llmFromEnv);`

`db` is the server's own `Db`. It is closed before the fork and reopened from
`dbPath` in the parent afterwards (`db.handle` is reassigned), so the clock
child starts with no inherited connection (see `runs.temper.md` for why a
child must never close one).

This forks. The parent gets the child's pid back and goes on to accept
connections; it reaps the child with its other children (`sysReapChildren`),
which only matters if the clock dies. The child runs `mutteringsClockMain`
and exits if it ever returns. The child inherits the listening socket and
never uses it. Nothing restarts a clock that dies; the next server boot
starts a new one.

    export let mutteringsClockStart(dbPath: String, db: Db, makeLlm: fn (): LlmClient): Int throws Bubble {
      db.close();
      let pid = sysFork();
      if (pid == 0) {
        mutteringsClockMain(dbPath, makeLlm);
        sysExit(0);
      }
      db.handle = sysDbOpen(dbPath);
      pid
    }
