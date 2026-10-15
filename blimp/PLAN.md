# Marginalia as a Blimp project: the plan and the contract

This is the one document every implementer reads first. It says what is being
built, how the pieces fit, what each library exports, and the rules Temper on
Blimp forces on the code. The surveys in `notes/` are the detailed specs; this
file tells you which one to open.

Status words used below: DONE, IN PROGRESS, TODO.

## 1. What is being built

Marginalia (a Phoenix LiveView app, ~32k lines of Elixir, Postgres, LLM calls)
rewritten so that the running program is one Blimp file produced by
`temper build -b blimp`, served by the Blimp interpreter, with no Elixir, no
BEAM, no Postgres, no Node. The pages must look the same: the compiled CSS is
reused byte for byte (`static/css/app.css`, 207 KB, produced from the pinned
Tailwind 4.3.0 + daisyUI 5.5.20), the HTML carries the same class names, and the
23 client hooks are ported to a small hand-written `static/js/blimp.js`.

What is Temper: everything that is logic or text: request parsing, routing,
sessions, HTML, Markdown, the domain (works, folders, links, cuts, stacks,
cases, accounts, import), the LLM client, the SQL (Alloy builds it).

What is native Blimp:
- `_connected.blimp` files beside Temper modules, one `def connected_<name>` per
  `@connected` Temper declaration, wrapping interpreter builtins (files, env,
  sockets, fork, hashing, random, HTTPS via `http_start`/`http_result`, time).
  No compiler change is needed for these (notes/toolchain.md §4).
- A handful of new interpreter builtins in Zig, in the temper-blimp repo
  (worktree `/Users/bg/code/temper-blimp-115`, branch `115-marginalia-builtins`):
  `sqlite_*`, `exec`, `pbkdf2_sha256`, `append_file`. See §4.
- `entry.blimp`: the one hand-written line that starts the server.

## 2. Decisions, with the reason each beat the alternatives

1. **HTML over the wire, not LiveView, not no-JS, not Blimp view trees.** Every
   user event is `POST /ev/<name>` with a JSON payload; the server re-renders
   the page's `<main>` and returns it; `blimp.js` morphs it in by element id.
   Server pushes (a read finishing, a run progressing) are polling: a page that
   is waiting carries `data-poll="2"` and the client re-fetches `<main>` every
   two seconds while the attribute is present. No WebSocket, no SSE: nothing in
   Marginalia streams tokens, and a forked child per request makes long
   connections awkward. notes/assets.md §3 is the client design; its hook port
   table (§3.3) is authoritative.
2. **SQLite through new builtins, with Alloy building the SQL.** There is no
   database in Blimp. A Postgres wire client over `tcp_connect` would be weeks;
   JSON files cannot hold the joins the pages do. SQLite is one C library the
   interpreter links. The prior branch `temper/alloy-slice` already has Alloy
   (225 tests, compiles for Blimp unchanged) and a `Statement(text, params)`
   boundary that is exactly `sqlite_query(text, params)`.
3. **Fork a child per request.** The interpreter frees nothing until exit and
   leaks ~2.7 KB per trivial request (notes/toolchain.md §6). A parent that
   only accepts and forks stays small forever; the child handles one request
   and exits; SQLite serialises writers across processes. Background jobs
   (reads, links, stack passes) are a second fork from the request child that
   outlives it, writing status rows that the next request reads. This also
   gives concurrency the single-threaded interpreter otherwise lacks.
4. **HTTPS through `http_start`/`http_result`.** Blimp main already has a TLS
   client with headers and timeouts (notes/toolchain.md §7). `std/net` has no
   TLS and no headers, so it is not used. The LLM client polls `http_result`
   with `sleep_ms` between polls, inside the child, so blocking is fine.
5. **Passwords: PBKDF2-HMAC-SHA256 via a Zig builtin**, not bcrypt. Existing
   bcrypt hashes are not migrated (no data is migrated: this is a new program
   with a new database). 600,000 iterations, 16-byte salt, stored as
   `pbkdf2-sha256$<iters>$<salt hex>$<hash hex>`.
6. **Git stays, through an `exec` builtin.** `Marginalia.Git` runs `git init`,
   `commit`, `log`, `show` in a repo per draft. An `exec(argv, stdin, cwd)`
   builtin is 60 lines of Zig and keeps that behaviour; it also serves tests.
7. **The prior Temper core is reused as is**: diff, words, blocks, sentences,
   reflow, segmenter, text from `/Users/bg/code/marginalia-temper/temper/marginalia-core`,
   and Alloy from `/Users/bg/code/marginalia-temper/temper/alloy`. The nine
   `@connected` Unicode helpers get `_connected.blimp` bodies over Blimp's
   `utf8_*`/`grapheme*` builtins instead of Elixir bodies.
8. **Tests at three levels.** Temper `test(...)` blocks per library (run with
   `temper test -b blimp`), the 311 pure-function assertions from
   notes/tests.md ported verbatim, and an end-to-end shell suite that starts
   the server on a temp database and drives it with curl, checking status
   codes, redirects, and text on the page (the LiveView tests' assertions,
   notes/tests.md parts 5-9). LLM calls in tests go to a fake endpoint the
   test starts (a tiny Blimp HTTP server that answers canned JSON), selected by
   the `MARGINALIA_LLM_ENDPOINT` env var, exactly as the Elixir config did.

## 3. Repository layout

All of it lives under `blimp/` in the marginalia repository (this worktree,
branch `worktree-blimp-rewrite`), except the interpreter changes, which live in
the temper-blimp repository on branch `115-marginalia-builtins`.

```
blimp/
  PLAN.md                 this file
  README.md               how to build, run, test (written last)
  build.sh                temper build -b blimp -w temper; assembles out/marginalia.blimp
  test.sh                 temper test per library, then test/e2e.sh
  entry.blimp             serve(portFromEnv()) ; temper_run_async()
  temper/                 the Temper work root: one directory per library
    core/                 marginalia-core from the prior branch (library "core")
    alloy/                Alloy (library "orm"), SQLite-adapted
    sys/                  @connected wrappers over Blimp builtins (library "sys")
    http/                 request/response/router/cookies/forms/multipart/static (library "http")
    html/                 escaping, the H builder, Markdown (library "html")
    db/                   sqlite wrapper, schema DDL, migrations, row decoding (library "db")
    llm/                  the one model client (library "llm")
    app/                  domain contexts (library "app")
    web/                  layouts, components, pages, event handlers (library "web")
    server/               the accept/fork loop and dispatch; no tests here (library "server")
    e2e/                  nothing Temper; see test/
  static/
    css/app.css           compiled, committed, byte-identical to the Phoenix build
    js/blimp.js           the client runtime
    js/hooks/*.js         one file per ported hook (concatenated by build.sh into static/js/app.js)
    images/, favicon.ico, robots.txt
  test/
    e2e.sh                starts the server on a temp db, runs test/e2e/*.sh
    e2e/*.sh              one file per page group
    fake_llm.blimp        canned-answer HTTP server for tests
    fixtures/             drafts, canned LLM replies
  notes/                  the surveys (read-only input to this work)
  out/                    build output, gitignored
```

Library names are what `import("...")` uses. A library's `config.temper.md`
is one line: `export let name = "http";`. Sources are literate Temper:
`src/<module>.temper.md`, code indented four spaces under prose.

### Build and run

```
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH="$JAVA_HOME/bin:/Users/bg/code/temper-blimp-115/blimp/chunks/lang/zig-out/bin:$PATH"
TEMPER=/Users/bg/code/temper-blimp-115/temper/cli/build/install/temper/bin/temper
cd blimp && ./build.sh          # -> out/marginalia.blimp
MARGINALIA_DB=out/dev.sqlite3 PORT=4000 blimp out/marginalia.blimp
```

`build.sh` runs `temper build -b blimp -w temper`, takes
`temper/temper.out/blimp/server/main.blimp` (which splices std, temper-core and
every library the server imports into one file), appends `entry.blimp`, and
concatenates `static/js/blimp.js` + `static/js/hooks/*.js` into
`static/js/app.js`. The `blimp` first on PATH must be the one built from
branch 115: the CLI runs tests with whatever `blimp` it finds by name.

## 4. Native layer

### 4.1 New interpreter builtins (Zig, temper-blimp-115)

All return plain Blimp values; errors raise the interpreter's error, which
reaches Temper as a bubble when the connected wrapper is called inside a
`do { } orelse`.

| builtin | signature | notes |
|---|---|---|
| `sqlite_open(path)` | `-> Int` handle | opens or creates; `PRAGMA journal_mode=WAL; busy_timeout=5000; foreign_keys=ON` |
| `sqlite_exec(db, sql)` | `-> Int` changes | DDL and multi-statement scripts; no params |
| `sqlite_query(db, sql, params)` | `-> [[String\|nil]]` | params bound as text (`$1`.. numbered); every cell returned as text, NULL as nil; the first row is the column names |
| `sqlite_changes(db)` | `-> Int` | rows changed by the last statement |
| `sqlite_last_id(db)` | `-> Int` | last inserted rowid |
| `sqlite_close(db)` | `-> nil` | |
| `exec(argv, stdin, cwd)` | `-> [status, stdout, stderr]` | fork/execvp with pipes; `cwd` may be nil |
| `pbkdf2_sha256(password, salt_hex, iterations, dklen)` | `-> String` hex | `std.crypto.pwhash.pbkdf2` |
| `constant_time_eq(a, b)` | `-> Bool` | |
| `append_file(path, data)` | `-> nil` | `write_file` truncates |

Each name is also added to `blimpBuiltins` in
`temper/be-blimp/.../BlimpNames.kt` (the test `BlimpNamesTest` fails until it
is), and the CLI is rebuilt with `./gradlew :cli:installDist`.

### 4.2 The `sys` library: what Temper can ask the machine

Every function is `@connected`, declared in `temper/sys/src/sys.temper.md`,
implemented in `temper/sys/src/_connected.blimp` as `def connected_<name>(...) -> Any`.
Parameters are received as `Any` (a typed Blimp parameter crashes on nil).
Names are prefixed `sys` to stay out of std's and the builtins' way.

```temper
// files
export let sysReadFile(path: String): String?;        // nil if missing
export let sysWriteFile(path: String, data: String): Void;
export let sysAppendFile(path: String, data: String): Void;
export let sysListDir(path: String): List<String>;
export let sysFileSize(path: String): Int;            // -1 if missing
// environment and process
export let sysGetEnv(name: String): String?;
export let sysArgv(): List<String>;
export let sysExit(code: Int): Void;
export let sysFork(): Int;                            // 0 in the child, pid in the parent
export let sysWaitPid(pid: Int, noHang: Boolean): Int; // 0 if still running under noHang
export let sysExec(argv: List<String>, stdin: String, cwd: String?): List<String>; // [status, out, err]
export let sysSleepMs(ms: Int): Void;
export let sysRss(): Int;                             // bytes
// time
export let sysNowMs(): Int64;
export let sysUtcNow(): String;                       // "YYYY-MM-DD HH:MM:SS"
export let sysUtcFromMs(ms: Int64): String;
// bytes and crypto
export let sysByteLength(s: String): Int;
export let sysSha256(s: String): String;              // hex
export let sysHmacSha256(key: String, msg: String): String;
export let sysPbkdf2(password: String, saltHex: String, iterations: Int, dklen: Int): String;
export let sysRandomHex(bytes: Int): String;
export let sysRandomToken(): String;                  // url-safe, 32 bytes
export let sysBase64(s: String): String;
export let sysBase64Decode(s: String): String?;
export let sysConstantTimeEq(a: String, b: String): Boolean;
export let sysUtf8Valid(s: String): Boolean;
export let sysUtf8Downcase(s: String): String;
export let sysUtf8Upcase(s: String): String;
export let sysGraphemeLength(s: String): Int;
export let sysGraphemeTake(s: String, n: Int): String;
export let sysStringReplace(s: String, from: String, to: String): String; // native, all occurrences
export let sysStringTrim(s: String): String;
export let sysJoin(parts: List<String>, sep: String): String;             // native join; use for big pages
export let sysFlatJoin(parts: List<Any>): String;                         // flattens nested lists, then joins with ""
// sockets (the server loop; std/serve is not used)
export let sysListen(port: Int): Int;                 // fd; bubbles with a message naming the port
export let sysAccept(fd: Int): Int;                   // blocks; client fd
export let sysReadRequest(fd: Int, maxBytes: Int): String?; // reads headers, then Content-Length more; nil on a dead client
export let sysWrite(fd: Int, data: String): Void;
export let sysClose(fd: Int): Void;
// https
export let sysHttpStart(method: String, url: String, headers: List<String>, body: String, timeoutMs: Int): Int;
export let sysHttpResult(handle: Int): List<String>?; // nil = pending; ["ok", status, body] or ["error", reason]
// sqlite
export let sysDbOpen(path: String): Int;
export let sysDbExec(db: Int, sql: String): Int;
export let sysDbQuery(db: Int, sql: String, params: List<String?>): List<List<String?>>;
export let sysDbLastId(db: Int): Int;
export let sysDbChanges(db: Int): Int;
export let sysDbClose(db: Int): Void;
```

`sysReadRequest` is the one piece of logic in Blimp: loop over `tcp_read`
until the header block has arrived, parse `Content-Length`, keep reading until
the body is complete or `maxBytes` is exceeded (then return what there is with
a marker header `X-Blimp-Truncated: 1` prepended so Temper can answer 413).

## 5. Library contracts

Signatures are binding: another agent is coding against them right now. If one
must change, post the change on the deciduous message board (label of the
library) before changing it, and update this file in the same commit.

### 5.1 `core` (DONE on the prior branch; adapt)

As in notes/prior-temper.md §1: `paragraphs`, `rows`, `Row`; `diff` (words),
`Part`; `blocks`; `reflow`, `reflowBlock` (sentences); `isWrapped`,
`reflowPage`, `align` (reflow); `segment`, `Section` (segmenter). Rename the
clashing names on import: `words.diff` is used as `wordDiff`; keep the files'
export names, alias at the import site. The nine `@connected` functions get a
`_connected.blimp` beside `sentences`, `reflow`, `segmenter` over
`utf8_downcase`, `grapheme_length`, `grapheme_take`, and Unicode class tables
written in Blimp for the ranges the tests and the verify oracles exercise
(Latin-1, Latin Extended-A, Greek, Cyrillic at least).

### 5.2 `orm` (Alloy; DONE on the prior branch; adapt for SQLite)

Changes: `SqlDefault` renders nothing (omit the column from INSERT); `ILIKE`
becomes `LIKE`; `lock` renders nothing; `timestamps()` default is
`strftime('%Y-%m-%d %H:%M:%S','now')`; `toUpdateSql` and `limit`/`offset`
keep working. Keep all 225 tests passing; add tests for each change.

### 5.3 `db`

```temper
export class Db(public handle: Int) {
  public query(sql: String, params: List<String?>): List<Row>;   // Row wraps a column-name list and a cell list
  public exec(sql: String, params: List<String?>): Int;           // changes
  public insert(sql: String, params: List<String?>): Int;         // last id
  public one(sql: String, params: List<String?>): Row?;
  public transaction<T>(body: fn (): T): T;                       // BEGIN IMMEDIATE / COMMIT / ROLLBACK on bubble
}
export class Row(public columns: List<String>, public cells: List<String?>) {
  public str(col: String): String;        // bubbles if null
  public strOrNull(col: String): String?;
  public int(col: String): Int;
  public intOrNull(col: String): Int?;
  public bool(col: String): Boolean;      // "1"/"0"
  public float(col: String): Float64;
  public strList(col: String): List<String>;  // JSON array column
  public intList(col: String): List<Int>;
  public json(col: String): JsonSyntaxTree?;  // std/json
}
export let dbOpen(path: String): Db;      // opens, runs migrations
export let dbMigrate(db: Db): Int;        // applies schema/*.sql not yet in schema_migrations; returns count
export let dbStatement(fragment: SqlFragment): Pair<String, List<String?>>; // Alloy -> (text, params)
```

The schema is `temper/db/src/schema.temper.md`: one `CREATE TABLE` per table in
notes/domain-works.md §1 and notes/domain-accounts-links-stacks.md §1, with the
same columns, defaults, uniqueness and indexes, types mapped `citext -> TEXT
COLLATE NOCASE`, `utc_datetime -> TEXT`, `boolean -> INTEGER`, `{:array,_}` and
`:map -> TEXT` holding JSON, `binary -> TEXT` holding hex. Every table keeps
`inserted_at`, `updated_at` TEXT defaults. Ids are INTEGER PRIMARY KEY. Foreign
keys with the same `ON DELETE` as the migrations.

### 5.4 `http`

```temper
export class Request(
  public method: String, public path: String, public query: Map<String, String>,
  public headers: Map<String, String>,     // lower-cased names
  public cookies: Map<String, String>,
  public body: String, public form: Map<String, String>,   // urlencoded or multipart fields
  public files: List<UploadedFile>, public truncated: Boolean,
) { public header(name: String): String?; public param(name: String): String?; }
export class UploadedFile(public field: String, public filename: String, public contentType: String, public content: String) {}
export let httpParse(raw: String): Request;              // never bubbles; a bad request parses to method "BAD"
export class Response(public status: Int, public headers: List<Pair<String, String>>, public body: String) {}
export let httpHtml(status: Int, body: String): Response;
export let httpJson(status: Int, body: String): Response;
export let httpText(status: Int, body: String): Response;
export let httpRedirect(to: String): Response;           // 303
export let httpNotFound(): Response;
export let httpWithCookie(r: Response, name: String, value: String, maxAgeSeconds: Int?, httpOnly: Boolean): Response;
export let httpClearCookie(r: Response, name: String): Response;
export let httpRender(r: Response): String;              // status line, headers, Content-Length in bytes, Connection: close, body
export let httpStatic(root: String, path: String): Response?; // nil when not a static path; sets Content-Type by extension, Cache-Control
export let urlDecode(s: String): String;  export let urlEncode(s: String): String;
export let queryParse(s: String): Map<String, String>;
// router
export class Route(public method: String, public pattern: String, public name: String) {} // pattern "/works/:id/graph.json"
export class Match(public route: Route, public params: Map<String, String>) {}
export let routeMatch(routes: List<Route>, method: String, path: String): Match?;  // first match wins, as Phoenix
```

### 5.5 `html`

```temper
export let esc(s: String): String;                       // & < > " '
export let attr(name: String, value: String?): String;   // ' name="escaped"' or ""
// H: a tree of strings joined natively once at the end; never append char by char
export class H(public parts: List<Any>) {}               // Any = String | H | List<...>
export let h(tag: String, attrs: String, children: List<Any>): H;   // "<tag attrs>...</tag>"
export let hv(tag: String, attrs: String): H;             // void element
export let raw(s: String): H;  export let text(s: String): H;        // text escapes
export let hjoin(x: H): String;                           // sysFlatJoin underneath
export let classes(xs: List<String?>): String;            // joins non-null with spaces
// markdown (the subset MDEx renders for Marginalia: notes/domain-works.md §3)
export let markdownToHtml(md: String): String;            // paragraphs, headings, emphasis, strong, code spans, fenced code, blockquotes, lists, links (sanitised: no raw HTML, no javascript: urls), hard breaks
export let markdownParagraphs(md: String): List<String>;  // what Reading.split gives (delegates to core.blocks)
export let slug(s: String): String;                       // Marginalia's slug rules (notes/domain-accounts-links-stacks.md "mint_slug")
export let wordCount(s: String): Int;
export let truncateWords(s: String, n: Int): String;
export let nl2br(s: String): String;
```

### 5.6 `llm`

```temper
export class LlmMessage(public role: String, public content: String) {}
export class LlmTool(public name: String, public description: String, public parametersJson: String) {}
export class LlmCall(
  public messages: List<LlmMessage>, public model: String?, public effort: String?,
  public maxTokens: Int?, public temperature: Float64?, public json: Boolean,
  public tools: List<LlmTool>, public toolChoice: String?, public timeoutMs: Int,
) {}
export class LlmReply(public content: String?, public toolCalls: List<LlmToolCall>, public finishReason: String, public raw: String) {}
export class LlmToolCall(public id: String, public name: String, public argumentsJson: String) {}
export class LlmError(public kind: String, public detail: String) {}  // kinds: no_key, rate_limited, length, invalid_json, http, timeout, transport
export interface LlmClient { chat(call: LlmCall): Result<LlmReply, LlmError>; json(call: LlmCall): Result<JsonObject, LlmError>; }
export let llmFromEnv(): LlmClient;     // MARGINALIA_LLM_PROVIDER (deepseek|openai), *_API_KEY, MARGINALIA_LLM_ENDPOINT override, backoff
export class Result<T, E>(public ok: T?, public err: E?) {}
```

Behaviour is notes/domain-accounts-links-stacks.md "llm.ex": provider table,
request body (`reasoning_effort`, `max_tokens` vs `max_completion_tokens`, the
24,000 headroom), 3 attempts with backoff on 429/5xx/transport, `length` is a
failure, `invalid_json` is not retried.

### 5.7 `app` (the domain)

One module per Elixir context, same function names in camelCase, same
semantics, specified in notes/domain-works.md §4-§6 and
notes/domain-accounts-links-stacks.md §2-§7. Every function takes the `Db` (and
a `Scope` where the Elixir took one) as its first argument. Records are plain
classes mirroring the Ecto schemas (`Work`, `Section`, `Node`, `Edge`,
`Conversation`, `Message`, `GraphEvent`, `Correction`, `Revision`,
`Attachment`, `User`, `UserToken`, `Folder`, `Link`, `LinkEdge`, `Cut`,
`StackStep`, `StackStory`, `Mutter`) with a `fromRow(Row)` each.

Background work: `Runs` becomes a table `runs(key, status, progress, detail,
started_at, finished_at, pid)`; `runsStart(db, key, body)` forks a detached
child (fork twice; the middle process exits; the request child reaps it) that
runs `body` and updates the row; pages read the row. `pubsub` becomes a
`versions(topic, n)` table bumped by writers; `GET /watch?topics=a,b` returns the
sum, and `blimp.js` re-fetches `<main>` when it changes. Recovery at boot marks
`reading`/`linking` rows failed and `runs` rows whose pid is gone crashed.

LLM prompts are copied verbatim from the notes, as constants in
`temper/app/src/prompts/*.temper.md`, one file per prompt, with the
interpolation points as functions.

### 5.8 `web`

```temper
export class Ctx(public db: Db, public req: Request, public scope: Scope?, public flash: Map<String, String>, public params: Map<String, String>, public now: String) {}
export let webRoutes(): List<Route>;
export let webDispatch(ctx: Ctx): Response;          // routes, auth plugs, page render or event handler
export let webEvent(ctx: Ctx, name: String, payload: JsonObject): Response;  // POST /ev/<name>: returns {"regions":{"#main": html}, "events":[...], "redirect": ...}
```

A page is a module exporting `render<Page>(ctx, state): H` plus
`handle<Page>(ctx, event, payload): state`; state is loaded from the database
on every request (there is no socket to keep it in), with the few pieces of
ephemeral UI state (open panel, chosen view, chat history on public pages)
kept in the URL query or in a `ui_state` table keyed by session. notes/web-*.md
give the markup; copy class names and copy text exactly; `:if` becomes an
`if`, `:for` becomes `map`.

Auth: notes/web-public.md §2 and notes/web-cuts-links-users.md endpoint
section. Session cookie `_marginalia_key` holds a session id (random token);
sessions table maps it to `user_token`, flash and `live_socket_id`-like data.
Guest minting, 14-day tokens, remember-me, the four auth levels, every redirect
and flash text as specified.

### 5.9 `server`

```temper
export let serve(port: Int): Void;   // listen; loop: accept, fork; child: read, dispatch, write, close, exit; parent: reap with waitpid(noHang) each loop
```

Plus `entry.blimp`:

```
serve(temper_port_from_env())
temper_run_async()
```

(`portFromEnv` is a Temper export; the spelling of the first line follows the
name the build emits.)

## 6. House rules for Temper on Blimp (each one cost somebody an hour)

1. End every assignment statement with `;`. An assignment as the last statement
   of a block without one crashes the compiler with no location.
2. No string `+`. Use interpolation, `ListBuilder<String>` + `join`, or `H`.
3. (Lifted on 2026-10-15 by temper-blimp 7634e93.) `ListBuilder.add`,
   `StringBuilder.append` and `MapBuilder.set/get` are amortised O(1) now,
   backed by native buffers: 20,000 adds 87 ms / 17 MB, 20,000 map sets
   41 ms. Still O(n) per call: `splice`, `addAt`, `sort`, `reverse`, and a
   read of a builder's items right after a write. Pages still go through the
   nested-list tree and one native join; that is simply the cheapest shape.
4. (Lifted, same commit.) `Map` lookups are hashed for String, Int, Float,
   Atom and Boolean keys and lists of those. A key that is a closure or a
   Blimp map is a TypeError. `removeLast` on an empty builder bubbles.
5. Lambda parameters must be typed: `{ (x: Int): Int => x + 1 }`.
6. `orelse` catches bubbles, not null. Test `== null`.
7. Ids are `Int`. Timestamps are `String` "YYYY-MM-DD HH:MM:SS" UTC. Money,
   none. Floats only where the Elixir had floats.
8. Exported names share ONE flat namespace across all libraries and std, and a
   collision is silent (the last definition wins). Prefix exports with the
   library's noun (`http*`, `html*`, `db*`, `sys*`, `llm*`, `web*`), name
   domain functions `<context><Verb>` (`worksGet`, `accountsRegister`), and
   never export `sleep`, `listen`, `length`, `filter`, `map`, `text`, `form`,
   `link`, `row`, `list`, `key`, `input`, `select`, `option`, `code`.
   Classes are unique nouns.
9. `@connected` works only for top-level functions. Receive parameters as
   `Any` in Blimp. Return lists and strings, never Blimp maps.
10. No `String.length`: use `countBetween` (code points) or `sysByteLength`.
    No `String.replace`: `sysStringReplace` or regex. No `trim`:
    `sysStringTrim` or `core`'s `trim`.
11. Tests: every assertion inside a helper that takes `test`, or the compiler
    constant-folds it. Tests live in each library and run with
    `temper test -b blimp -w temper --library <name>`. The `server` library
    has no tests, so the shipped file has no test runner and no `exit(1)`.
12. Content-Length is bytes: `sysByteLength`, never `countBetween`.
13. A `TODO()` with the offending value is the right way to leave something
    unhandled. Never a plausible fallback.
14. Each library's README section in `blimp/README.md` says what does not work,
    by name.

Found while writing Phase 1 (each one cost an agent an hour):

15. There is no `??` and no postfix `!`. Write `if (x != null) { x } else { d }`
    in a helper.
16. `else` goes on the same line as the closing `}`. A newline before it
    crashes the translator.
17. `new Map<K,V>()` and `new List<T>()` do not exist: `new MapBuilder<K,V>()`
    then `.toMap()`, `new ListBuilder<T>()` then `.toList()`. A list literal
    containing `null` cannot be typed `List<String?>`; build it with a
    ListBuilder.
18. Null narrowing works for a `let` or a parameter inside
    `if (x != null) { ... }`, and nowhere else: not after an early return, not
    for a `var`. Copy a `var` to a `let` first.
19. A `\u{..}` escape inside a string literal that is the argument of a
    `@connected` call breaks the frontend ("Explicit return type required" on
    the enclosing `let`). Put the literal in a function and call it.
20. Do not name a local `name`: it collides with the library config's export.
21. A block lambda followed by a method call on the same expression
    (`xs.join(",") { ... }.split(x)`) does not parse; bind the lambda call to a
    `let` first.
22. `temper test` in a work root needs `--library <name>`; the server library
    has none so the shipped file never calls exit(1) on load.
23. In `_connected.blimp`, a Temper `List` argument may arrive as a
    ListBuilder actor: call `temper_items(x)` before treating it as a Blimp
    list. Blimp tuples (`{:ok, s, b}`) must be turned into lists before they
    cross back. `http_start` wants its headers as a Blimp map.
25. `import("sys")` imports nothing: import a library by its source directory,
    `let { sysGetEnv } = import("sys/src");` (as core does with `"orm/src"`).
26. In literate files an indented code block straight after a bullet list is
    prose, not code; put a plain paragraph between.
27. The frontend constant-folds pure calls on compile-time-built objects, so a
    test that inspects state after a call (`llmLastRequest(c)` after
    `c.chat(...)`) must go through a helper that takes `test`.
28. A `for (let x of xs)` over a parameter with an early `return` inside hit
    "Never reached by macro expander"; a `while` with an index works.
29. A literal `#{` inside a Temper string becomes Blimp's own interpolation
    in the emitted code and raises at run time; build it as
    `sysJoin(["#", "\u{7b}"], "")`.
30. `x != null && x is T` does not narrow; `x is T` alone does. Narrowing
    does not survive `&&`.
31. A function-typed return (`: fn (A): Void`) cannot be declared; pass the
    function in instead. A lambda argument is `fn (a: T): R { ... }`.
32. The sqlite builtin binds `$N` by number since temper-blimp f6fa178;
    before that it bound by order of first appearance.
33. The interpreter compiles SQLite 3.54.0 from a vendored amalgamation
    since temper-blimp c50aaf7. Before that, macOS's libsqlite3 segfaulted
    in forked children (any sqlite call after a fork once the process had
    run an exec, 4 to 6 runs in 10); OS_ACTIVITY_MODE=disable is no longer
    needed anywhere.
24. `now_ms()` in Blimp is monotonic, not epoch. `sysNowMs` is `now() * 1000`;
    `sysMonoMs` is the monotonic one, for timing only.

## 6a. Amendments to the contract (binding)

- `html`: the tree type `H` is a plain nested Temper list (`List<AnyValue>`)
  with String leaves, not a class, because the native flatten+join can only
  see lists. `text`/`raw` are `htext`/`hraw`.
- `sys` grew `sysMonoMs`, `sysReapChildren`, `sysCloseFd`; `sysWriteFile`
  returns `Boolean`; `sysHttpAwait(handle)` polls to completion.
- `http`: `httpStatic` returns a 404 Response (not null) for a static-looking
  path whose file is missing or unsafe; null only for non-static paths.
  `Request.param` looks in form first, then query.
- Library names: the text core is `core`, Alloy is `orm` (import
  `"orm/src"` as core does).
- `db`: the row class is `DbRow`, not `Row` (core already exports `Row`, and
  two classes of one name in the flat namespace broke the build with
  `__new expects 3 arguments`). `Db` has `query/exec/insert/one/script/
  begin/commit/rollback/inTransaction/close` and a public `lastError`;
  `dbTransaction(db, body: fn (): Void throws Bubble)` replaces the generic
  method. `DbRow.json` bubbles on bad JSON; a NULL list column reads as `[]`.
  Every `sys` function that can fail is `throws Bubble`; without that
  annotation on a callee the compiler deletes the `orelse` around it.
- Class names are global. Before declaring a class, run
  `grep -rn "class <Name>\b" blimp/temper` and pick another name if it
  exists. Record classes are reserved per context: accounts: `User`,
  `UserToken`, `Scope`; works: `Work`, `Section`, `GraphNode`, `GraphEdge`,
  `Conversation`, `Message`, `GraphEvent`, `Correction`, `Revision`,
  `Attachment`, `DocumentSummary`; folders: `Folder`; links: `Link`,
  `LinkEdge`; cuts: `Cut`; stacks: `StackStep`, `StackStory`; runs: `Run`,
  `Mutter`. (`Node`, `Edge`, `Row`, `Param`, `Statement`, `Part`, `Section`
  are taken or ambiguous: `Section` belongs to works; core's segmenter
  `Section` must be aliased at import.)
- `llm`: error kinds are `no_key`, `rate_limited` (429 and 5xx after three
  attempts), `length`, `invalid_json`, `http`, `timeout`, `transport`.
  Fakes: `llmFake(replies)`, `llmFakeScript(List<LlmFakeResponse>)`,
  `llmRequests(client)`.
- `blimp.js` keeps the Phoenix attribute names (`phx-click`, `phx-value-*`,
  `phx-submit`, `phx-change`, `phx-debounce`, `phx-click-away`,
  `phx-window-keydown`, `phx-key`, `phx-hook`, `phx-update="ignore"`,
  `phx-disable-with`, `phx-mounted`, `data-phx-theme`). Events are
  `POST /ev/<name>` with JSON `{"payload", "path"}` and headers
  `x-requested-with: blimp`, `x-csrf-token`. Replies are JSON
  `{"regions": {"#main": html}, "events": [...], "redirect", "title",
  "flash": {"info", "error"}}`. A page with `[data-poll="N"]` is re-fetched
  (GET, `accept: application/json`) every N seconds and gets the same JSON.
  Hook names: the two Composers are `ChatComposer` (work show) and
  `LinkChatComposer`.
- `html`: Markdown cost was ~30 µs per inline character; after the
  interpreter's lookup work (fork e5fac4a, e7a29d2: actors indexed by id,
  builtins by name, call-site cache) a 2,000-character paragraph with
  emphasis and links renders in 33 ms (was 257 ms), plain prose in under
  1 µs per character, fifty such paragraphs in 1.8 s. Pages that render
  many sections should still cache rendered HTML per section keyed by a
  body fingerprint (Phase 4); until then render only what the page shows.
  `markdownToHtmlSoft` keeps newlines (Reading.render_block).
- Seen once, not reproduced (2026-10-15): in one full e2e run the server
  stopped accepting right after a second read job finished (every request
  from "read again: with the same beats" on got connection refused); the
  same file alone and the next full run passed 1806/0. The parent had no
  line in its log. If it recurs, keep the temp dir (E2E_KEEP=1) and look at
  whether the parent died or only its listening socket.
- Memory: since fork commits 731552e, 7eb02e1 and 3510871 (2026-10-15) the
  interpreter compacts between top-level statements, follows the pointers
  buffers hold, drops unreachable actors in a plain run, and be-blimp emits
  one statement per test, so `temper test` needs no `BLIMP_HEAP_LIMIT`:
  pages_show's 293 tests peak at 980 MB in 119 s. The server still forks a
  child per request; the parent's heap does not grow with requests.
- `core` timings in the interpreter (2026-10-15, after the lookup work):
  `segment` of 12,000 words 2.5 s (was 3.5), paragraph `rows` of 2,000 words
  0.22 s, word `diff` of 2,000 words with 20 changes 0.29 s (was 17.9 s on
  a worse case). Word diff runs per changed paragraph only, never over a
  whole draft; the Changes view skips `rows` when baseline and body are
  equal (3.7 s on an unchanged 17,000-word draft before).
- Show page on a read 12,000-word draft, measured with curl against the
  forked server: plain prose read view 0.32 s (120 KB), emphasis-and-link
  heavy prose 1.4 s; graph/spine/threads 0.05-0.06 s. With the render cache
  (`render_cache`, schema v3, keyed by the SHA-256 of a block's Markdown
  source; `reading` loads a page's keys in one query and writes the misses)
  the heavy read view is 0.12 s, trace/prompts 0.10 s, the Changes tab
  0.05 s.

## 7. Phases and who does what

Phase 0 (TODO): native builtins in temper-blimp-115, rebuilt interpreter and
CLI, `BlimpNames.kt` updated, Zig tests. One agent.

Phase 1 (TODO, parallel, after Phase 0 builds): `sys`, `core` adaptation,
`orm` adaptation, `db` + schema, `http`, `html` (escape/H) and `html` Markdown
(two agents), `llm`, `server` + `entry.blimp` + `build.sh`, `blimp.js` + hook
port, `test/e2e.sh` harness + `fake_llm.blimp`. Each ends with its tests green
and a smoke run noted in the report.

Phase 2 (TODO, parallel, after Phase 1): `app` contexts, one agent each:
accounts; works + document + revisions + attachments + git; folders + stacks;
links + link chat; cuts; cases + kinship + case chat; import + github + query;
analysis (read pipeline) + weave + linker; decision graph; chat/editor; reading
+ summary + rewrite; mutterings + runs + recovery. Each ports its unit tests
from notes/tests.md.

Phase 3 (TODO, parallel, after Phase 2 interfaces exist): `web` pages, one
agent per page group: layouts + components; landing; cases (3 pages); drafts +
linked + reading; works index + new; work show (split: reading pane + margin
notes; threads/chat; graph/spine/changes/trace/prompts views; deck/lanes/
summary vault/editor); import; stacks; cuts; links; users + session controller;
graph controller + sitemap + errors.

Phase 4 (TODO): integration: full build, e2e suite, screenshot comparison
against the Phoenix app (headless Chrome, same fixture draft), performance
pass (page build time, child RSS), fix list.

Phase 5 (TODO): the narrative: stacked PRs, one chapter each, per the house
style in the repository's CLAUDE.md.

## 8. Where to read

| topic | file |
|---|---|
| toolchain, language surface, limits, connected recipe | notes/toolchain.md |
| interpreter builtins, adding one, fork, memory | notes/blimp-native.md |
| prior Temper code and Alloy | notes/prior-temper.md |
| CSS, hooks, client design | notes/assets.md |
| public pages, layouts, components, auth | notes/web-public.md |
| work show page | notes/web-work-show.md |
| works index/new, import, stacks | notes/web-works-stacks.md |
| cuts, links, users, endpoint | notes/web-cuts-links-users.md |
| works/analysis/chat domain, prompts, pipeline | notes/domain-works.md |
| accounts/folders/links/cuts/stacks/cases/import/llm domain | notes/domain-accounts-links-stacks.md |
| acceptance tests | notes/tests.md |
