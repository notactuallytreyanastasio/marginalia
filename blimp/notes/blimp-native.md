# Blimp native interpreter: build, builtins, process model, memory

Surveyed: `/Users/bg/code/temper-blimp-114/blimp/chunks/lang` (read-only). All
experiments ran on a scratchpad copy,
`/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad/native/`
(zig 0.16.0, macOS 26.2, aarch64, ReleaseSafe binary). Line numbers below are
for the original files unless a diff is named. Probe programs are in `t/` of
that directory.

Two corrections to the brief: the pull request bodies are not in
`temper-blimp-114/.prs`; they are in `/Users/bg/code/temper-blimp/.prs/10[3-7]-*.md`
(103 sleep/read_line/now_ms, 104 event loop on `tcp_poll([0], ms)`, 105
closures borrow captures, 106 ReleaseSafe by default, 107 `tcp_poll` treats
HUP/ERR/NVAL as ready). And `docs/web_framework.md` is a one-line pointer to
`docs/web/`, so the web framework docs are HTML (`docs/web/{index,reference,rooms}.html`).
`docs/lang_design/{concurrency,sessions,websockets}.md` are design documents
and are partly stale (sessions.md says there is no `random_bytes`; there is).

## Summary of the findings that matter

1. **The interpreter never frees.** Every value lives until exit. A plain
   accept loop answering a 3.3 KB page costs about **21 KB of RSS per request**
   (measured, linear: 2.4 MB at start, 23.3 MB after 1000). The default ceiling
   is 2 GiB (`BLIMP_HEAP_LIMIT=<bytes>`, `0` lifts it), so a plain loop dies
   with "Out of heap" after roughly 100k such requests.
2. **`blimp --serve FILE --tick EXPR` already solves that.** The loop is in Zig
   (`main.zig:1434`), the program does one bounded piece of work per tick, and
   the heap is compacted between ticks. Same 3000-request test: RSS sawtooths
   between 4 and 13 MB and does not grow. Use this for a long-lived server.
3. A handler error under `--serve` is logged and the server carries on (tested:
   `to_int("x")` in `:accept`, next request answered). In a plain run the same
   error prints and exits 1.
4. `fork` per request also keeps the parent flat (+0.14 KB/request), but
   **`tcp_close` in the parent after `fork` breaks the child** (it
   `shutdown(SHUT_WR)`s the shared socket and its lingering drain eats the
   child's request bytes). The parent must not close, so it leaks one fd per
   request: 308 open fds after 300 requests; with `ulimit -n 64` the server
   died at request 60. `waitpid` returns only the pid, not the exit status.
5. SQLite is feasible. `sqlite3.h` and `libsqlite3.tbd` are in the Xcode SDK and
   `linkSystemLibrary("sqlite3")` links `/usr/lib/libsqlite3.dylib`. I
   implemented `exec` and `sqlite_query`; they pass 4 new Zig tests and a Blimp
   test file. Patch: `blimp/notes/blimp-native-ext.patch` (396 lines).
6. **`sha256` and `random_bytes` already exist.** `sha256(s)` returns 64 hex
   chars. `random_bytes(n)` returns *raw* bytes, not hex; use
   `hex_encode(random_bytes(n))`, or `random_token(n)` for base64url.
7. Build: `zig build interp` works here, 22-25 s, ReleaseSafe. `zig build`
   (default step) installs `blimp` and then fails building `blimp-compile`
   (wants `llvm@20`; only 21 and 22 are installed). The Makefile workaround for
   "macOS 26" is not needed on this machine (zig 0.16.0, macOS 26.2).
8. **A builtin error cannot be caught with `orelse`**; `orelse` catches only
   `bubble` and nil. `try do ... catch e do ... end` catches everything, but `e`
   is only `:type_error` or `:error`; the message goes to stderr/`last_error`
   and is lost.
9. SIGPIPE does not kill the process, even in a plain run: Zig 0.16's
   `std.Io.Threaded.init` installs a no-op SIGPIPE handler (`Threaded.zig:1661`).
   Five hostile clients (close at once, half a request, RST, vanish mid-response)
   against a plain loop: server alive after each, writes return `:error`.
10. A blocking accept loop serves one client at a time: a client that sends half
    a request and stalls held a second client for 3 s (`tcp_read` has no
    timeout). Use `tcp_set_nonblocking` + `tcp_poll`, or `--serve`.
11. `tcp_read` returns at most 64 KiB (`builtins.zig:4795`). A body larger than
    that needs a loop; it works (3 MB body in 301 reads) but accumulating with
    `concat` is quadratic (see section 5).
12. `exec` is new; nothing in the language runs a subprocess (only `fork`, with
    no `exec`).
13. Lambdas need typed parameters (`fn(i: Int) do ... end`) or the checker
    rejects the file. The checker also rejects some wrong calls statically
    (`length(5)`), so runtime error probes need `to_int("abc")`-style code.
14. `Int` arithmetic wraps silently: `9223372036854775807 + 1` prints
    `-9223372036854775808`. `sum([1, 2.5])` is `1` (floats skipped). `1 == 1.0`
    is `false`. Strings do not support `<`.
15. Strings are byte strings. `length`, `slice`, `char_at`, `upcase`,
    `downcase`, `index_of` are bytes/ASCII; the `utf8_*` and `grapheme*`
    builtins are the code point / cluster versions.

## 1. Building and testing

```
$ zig version
0.16.0
$ cd <copy of chunks/lang> && time zig build interp
zig build interp   21.60s user 0.86s system 99% cpu 22.677 total      # first build
zig build interp   21.91s user 1.32s system 91% cpu 25.525 total      # after editing src
$ ls -la zig-out/bin   ->  blimp, 2.1 MB (ReleaseSafe; 7.2 MB for the Debug make build below)
```

`build.zig` defaults `optimize` to `ReleaseSafe` (lines 4-29; PR 106: Debug was
10x slower). `link_libc = true` on the exe. Steps: `interp` (just the
interpreter, no LLVM), `test`, `wasm`, `run`, default (adds `blimp-compile`).

The default step:

```
$ zig build
...  error: process exited with error code 1   (compile exe blimp-compile)
failed command: zig build-exe -lLLVM ... -isystem /opt/homebrew/opt/llvm@20/include ...
$ ls zig-out/bin   ->  blimp          # still installed
$ ls /opt/homebrew/opt | grep llvm    ->  llvm  llvm@21  llvm@22
```

So `zig build` exits 1 but leaves a good `blimp`. Use `zig build interp`.

The Makefile (`Makefile`) says "use make instead of zig build on macOS 26+
(zig build runner fails to link on macOS 26 / Zig 0.15)". On this machine
(macOS 26.2, zig 0.16.0) `zig build` works. The Makefile still works too, but
it is an unoptimised Debug build:

```
$ make blimp
zig build-exe src/main.zig --name blimp -target aarch64-macos-none -lSystem     # 4.4 s, 7.2 MB, Debug
```

Its `test` target (`zig build-lib ... src/lib.zig`) only compiles; it runs
nothing. Do not use it as the test command.

**Tests.** Two layers:

- Zig `test` blocks live inline at the bottom of `src/builtins.zig` (about line
  5000-6300: tcp_write_some, ws_accept_key, sum overflow, pow, write_file/read_file
  round trip, p256...) and in `memory_test.zig`, `websocket.zig`,
  `unicode_builtins.zig`, `eval.zig` etc. `lib.zig:27` pulls them in with
  `refAllDecls`. `build.zig` runs two test binaries (lib and main) in both
  Debug and ReleaseSafe:

  ```
  $ zig build test --summary all
  Build Summary: 5/5 steps succeeded; 762/762 tests passed
  +- run test 402 pass (402 total) 6s
  +- run test 360 pass (360 total) 5s     # 25.9 s wall including compile
  ```

  A builtin that touches files needs an `Io`; the unit tests install one
  (`builtins.zig:~5990`: `var threaded: std.Io.Threaded = .init(...); ioenv.install(threaded.io())`).
- Blimp-level tests: `test "name" do ... end` **inside an actor**, run with
  `blimp file.blimp --test`, or `blimp test <dir>` which finds `*_test.blimp`
  (`test/counter_test.blimp`, `test/shadow_builtin_test.blimp`). A bare top-level
  `test` is a parse error. Example I used, `t/ext_test.blimp`:

  ```
  $ ./zig-out/bin/blimp t/ext_test.blimp --test
  ...  3 tests passed   Finished in 5ms
  ```

## 2. Builtins

Registered in `BuiltinRegistry.init`, `builtins.zig:77-249` (167 `register`
lines; `get` is a linear scan, line 64). Four more are handled inside the
evaluator because they call closures or need evaluator state (`eval.zig:1600-1612`):
`map(list, fn)`, `filter(list, fn)`, `reduce(list, init, fn)`, `each(list, fn)`,
`show(cond, node)` (lazy), `blimp_eval`, `runtime_snapshot`, `blimp_test`,
`schedule`. There is also `for x in list do ... end` as an expression.

A user `def` with a builtin's name wins over the builtin
(`test/shadow_builtin_test.blimp`), so a new builtin name cannot break an
existing program, but the Temper backend refuses Temper names that equal a
builtin (be-blimp commit 2a8dcd8, "63 builtins"); check there before naming one.

"Raises" below means `error.TypeError` unless said otherwise.

**Strings** (bytes unless noted)

| builtin | notes |
|---|---|
| `length(String\|List\|Map) -> Int` | bytes for a String |
| `concat(a, b, ...)` (2 or more) | each arg String, Int, or Atom; an Atom is written **with a leading `:`**; anything else raises |
| `split(s, sep) -> [String]` | bytes; `"a,b,,c"` gives 4 parts; empty sep splits every byte |
| `join([String], sep) -> String` | one allocation; non-String element raises |
| `contains(s, sub) -> Bool`, `index_of(s, sub) -> Int` | byte offset, `-1` if absent |
| `replace(s, find, with)` | empty `find` raises; no match returns the same value |
| `to_string(v)` | String, Int, Float, Atom, Bool, nil; List/Map/tuple raise |
| `to_int(v)` | String (base 10, raises on junk), Float (truncates), Bool; Int passes |
| `to_atom(s)` | |
| `char_at(s, i) -> String\|nil` | one **byte**; a multi-byte character comes out as a broken string |
| `char_code(s[, i]) -> Int\|nil` | byte value (`char_code("é", 1)` is 195) |
| `from_char_code(n)` | one byte, `n` clamped to 0..255 |
| `slice(s, start, LENGTH)` | third argument is a length, not an end; clamps; shares memory with `s` (no copy) |
| `upcase(s)`, `downcase(s)` | ASCII only (`upcase("héllo")` is `"HéLLO"`) |
| `utf8_valid(s)`, `utf8_scrub(s)`, `utf8_length(s)`, `utf8_slice(s, start, count)`, `utf8_upcase(s)`, `utf8_downcase(s)` | code points; all but valid/scrub raise on invalid UTF-8 |
| `graphemes(s)`, `grapheme_length(s)`, `grapheme_slice(s, start, count)`, `grapheme_take(s, n)` | extended grapheme clusters |
| `hex_encode(s)`, `hex_decode(h)` | lowercase; decode takes either case |
| `base64_encode/decode`, `base64url_encode/decode` | strict decoders |
| `sha256(s) -> String` | **64 hex chars** (`sha256("abc")` is `ba7816bf...15ad`) |
| `hmac_sha256(key, msg) -> String` | hex |
| `xor_bytes(a, b)` | equal lengths or raises |
| `json_encode(v) -> String` | raises on NaN, invalid UTF-8, closures |
| `json_decode(s) -> {:ok, v} \| {:error, msg}` | the one builtin that returns an error tuple instead of raising |
| `actor_name(ref) -> String` | |

**Lists**

`append(list, v)`, `reverse`, `head` (nil when empty), `tail`, `range(a, b)`
(inclusive), `sort(list)` (all numbers or all strings, pdqsort, **no comparator**),
`sort_by_keys(items, keys)` (stable; keys computed with `map`), `flat`, `zip`,
`uniq`, `sum` (Ints only: other elements are skipped, and the sum wraps), `set_at(list, i, v)`
(raises when `i` is out of range), `elem(tuple, i)`, `size`, `empty?`,
`min(a, b)`, `max(a, b)` (Ints only), `length`.

**Maps** (string keys, atom keys are converted to strings)

`lookup(map, key)` (**nil** when missing; `m.key` also gives nil), `put(map, key, v)`,
`keys`, `values`, `merge(a, b)`.

**Numbers**

`rem(a, b)`, `abs`, `floor`, `ceil`, `round` (Float to Int), `pow(a, b)`,
`atan2(y, x)`, the float table at `builtins.zig:1690`: `sqrt exp expm1 log log1p
log2 log10 sin cos tan asin acos atan sinh cosh tanh` (each takes Int or Float,
returns Float), `not`, `nil?`, `random(min, max)` (xorshift, fixed default seed,
not secure), `seed(n)`, `type_of(v)`.

**IO and environment**

`print(v)` (formatted, returns v), `puts(v)` (raw string + newline), both
**unbuffered** writes to fd 1; `read_line() -> String|nil` (reads fd 0 one byte
at a time, strips CR, nil at EOF), `getenv(name) -> String|nil`, `argv() -> [String]`,
`now()` (epoch seconds), `now_ms()` (monotonic ms), `utc_offset()`,
`format_time(epoch, pattern)` (UTC only; `%Y %m %d %j %H %I %p %M %S %B %b %A %a %Z %%`, `%-d`),
`sleep_ms(n)`, `process_stats() -> %{cpu_ms, rss_bytes, heap_bytes, cores}`,
`random_bytes(n)` (**raw** OS CSPRNG bytes), `random_token(n)` (base64url, no padding).
Also P-256/AES for Web Push: `p256_keypair`, `p256_public_key`, `p256_ecdh`,
`ecdsa_p256_sign`, `ecdsa_p256_verify`, `aes128gcm_encrypt`, `aes128gcm_decrypt`.

**Files** (all raise `NotSupported` on WASM)

`read_file(path) -> String|nil` (nil on any failure; over 64 MiB raises),
`write_file(path, s) -> Bool`, `write_bytes(path, [Int]) -> :ok` (raises on failure),
`list_dir(path) -> [String]|nil` (sorted), `file_exists?(path)`, `file_size(path) -> Int|nil`.
There is no append, delete, rename, mkdir or stat beyond size. Paths are relative
to the process cwd.

**TCP**

| builtin | notes |
|---|---|
| `tcp_listen(port) -> Int` | IPv4, binds **0.0.0.0**, backlog 128, SO_REUSEADDR (`:3752`). Port in use: prints `tcp_listen(N): the port is already in use`, raises `NotSupported`. Not CLOEXEC |
| `tcp_connect(host, port) -> Int\|nil` | `getaddrinfo`, blocking connect (`:4724`) |
| `tcp_accept(fd) -> Int\|nil` | blocking; nil if the listener is non-blocking and nothing pending (`:4773`); other errors raise |
| `tcp_read(fd) -> String\|nil` | one `read()` of up to **64 KiB** (`:4792`). `""` is EOF or connection reset. nil only if non-blocking and nothing there. Other errors (EBADF) raise `NotSupported` |
| `tcp_write(fd, s) -> :ok\|:error` | writes all of it, retrying partial writes; waits via `poll` on a full non-blocking socket; gives up after 10 s without progress (`:4827`) |
| `tcp_write_some(fd, s) -> Int\|:error` | one non-blocking `send`; returns bytes taken (`:4894`) |
| `tcp_poll(fds, ms) -> [Int]` | readable, or HUP/ERR/NVAL; `ms` -1 blocks (`:5618`). Works on fd 0 |
| `tcp_poll_write(fds, ms) -> [Int]` | writable |
| `tcp_set_nonblocking(fd) -> :ok` | |
| `tcp_close(fd) -> nil` | **lingering close**: `shutdown(SHUT_WR)`, drain input, keep the fd open up to 30 s, swept on later `tcp_poll`/`tcp_accept`/`tcp_close` (`:5127-5183`). Table of 256 |
| `http_start(method, url, headers, body[, opts]) -> Int`, `http_result(h) -> nil\|{:ok, status, body}\|{:error, reason}` | outbound HTTP(S) on a worker thread; 32 slots |

**WebSocket**

Server side, blocking and text frames only: `ws_accept_key(key)`, `ws_read_frame(fd) -> String|nil`
(`:5216`, replies to ping), `ws_write_frame(fd, s) -> :ok|:error`, `view_diff` (`builtinViewDiffNative`, not examined).
Client side (own thread): `ws_open(url, headers)`, `ws_recv(h)`, `ws_send(h, text)`,
`ws_close(h)`, `ws_stats(h)`.

**Process**

`fork() -> Int` (0 in the child, pid in the parent, -1 on error), `waitpid(pid, nohang) -> Int`
(pid, 0 if nohang and still running, -1 on error; the **exit status is discarded**),
`exit(code)` (clamped 0..255). No `exec`, `kill`, `getpid`, `pipe`.

**View** (build `view_node` values for the browser runtime)

`stack row grid text heading bold italic code code_block blockquote divider list link
image video canvas draw el button timer fetch location_query stored store socket show
key input textarea select option form mount_root`, and `to_html(node) -> String`.

**Test**

`assert(x)`, `assert_eq(a, b)`, `assert_ne(a, b)`, `refute(x)`, `gen_integer(lo, hi)`,
`gen_string`, `gen_boolean`, `gen_list`, `gen_one_of`.

## 3. Adding a builtin

### How an existing one is wired

`BuiltinFn` is `*const fn (std.mem.Allocator, []const *const Value) EvalError!*const Value`
(`builtins.zig:23`). `EvalError` (`:12`) is `UndefinedVariable, TypeError,
UnsupportedOperation, DivisionByZero, NotSupported, OutOfMemory, Bubble, RecursionTooDeep`.

The evaluator calls it at `eval.zig:1636`:

```zig
return func(self.allocator, args) catch |err| {
    if (builtins_mod.takeFailure()) |why| {
        if (self.last_error == null) self.last_error = errors.builtinFailure(why, self.source);
    }
    return err;
};
```

`self.allocator` is the evaluator heap: **nothing you allocate with it is ever
freed** (until `--serve` compacts). Use a scratch allocator for temporaries
(`json_decode` does: `builtinJsonDecode`, `:1299`).

**`read_file`** (`:2110`), line by line:

```zig
fn builtinReadFile(allocator, args) EvalError!*const Value {
    if (args.len != 1 or args[0].* != .string) return error.TypeError;   // arity and type check; Values are tagged unions, test with .* != .tag
    if (is_wasm) return error.NotSupported;                              // native-only
    const path = args[0].string;                                         // payload of .string is []const u8
    const content = std.Io.Dir.cwd().readFileAlloc(ioenv.io, path, allocator, .limited(read_file_limit)) catch |err| {
        if (err == error.StreamTooLong) return error.NotSupported;       // raising: the program stops
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return make(allocator, .nil);                                    // soft failure: nil
    };
    const result = allocator.create(Value) catch return error.OutOfMemory;
    result.* = Value{ .string = content };                               // the bytes are now owned by the heap
    return result;
}
```

**`tcp_connect`** (`:4724`): same arity check; copies the host into a stack buffer
to NUL-terminate it for `getaddrinfo`; every failure is `make(allocator, .nil)`;
success is `make(allocator, .{ .integer = fd })`.

**Value constructors.** `make(allocator, v)` (`:272`) returns a shared static
value for Ints in [-1024, 4096], both Bools and nil (`value.zig` `interned`),
otherwise allocates. Direct forms:

| want | write |
|---|---|
| String | `make(a, .{ .string = bytes })` (bytes must outlive the call: `a.dupe`) |
| Int / Float | `.{ .integer = n }` / `.{ .float = f }` |
| Atom | `.{ .atom = "ok" }` (a static literal is fine) |
| nil / Bool | `.nil` / `.{ .boolean = b }` |
| List | `const items = try a.alloc(*const Value, n); ... .{ .list = items }` |
| Tuple | same with `.tuple` (shows as `{:ok, v}`) |
| Map | `const e = try a.alloc(Value.MapEntry, n); e[i] = .{ .key = "status", .val = ptr }; .{ .map = e }`. Order is the array order; keys are strings |

**Raising.** Return an `EvalError`. At top level in a plain run:
`Runtime error`/`-- RUNTIME ERROR -- TypeError while evaluating this.` and exit 1.
To say *why*, call `failArg("name: reason {d}", .{x})` (`:47`, now `pub` in my
patch) which stores a 256-byte message and returns `TypeError`; the evaluator
turns it into `-- BAD ARGUMENT -- sqlite_query: no such table: nope` with the
source line.

**What Blimp code can catch.** Verified (`t/errs.blimp`, `t/sql.blimp`):

```
try do tcp_read(999) catch e do {:caught, e} end        # {:caught, :error}        (NotSupported)
try do to_int("abc") catch e do {:c, e} end             # {:c, :type_error}
try do (to_int("abc") orelse :fallback) catch e do ... end   # orelse did NOT catch: :type_error reaches catch
sqlite_query(db, "select * from nope", []) orelse :fallback  # not caught: program dies with BAD ARGUMENT
```

`orelse` (`eval.zig:2376`) catches only `error.Bubble` and a nil/hole left side.
`try/catch` (`eval.zig:965`) catches any error, and `e` is only `:type_error`,
`:undefined`, `:division_by_zero`, `:bubble` or `:error`: **the message from
`failArg` is lost to the program.** So: for failures a server should handle, return
nil or an error tuple (`json_decode` shape), and raise only for programmer
errors. `bubble` as a plain statement did not parse inside a top-level `def`
(probably actor-only; not investigated).

**Registering.** Three edits, all in `builtins.zig`:

1. `reg.register("name", &builtinNameImpl);` in `BuiltinRegistry.init` (`:77-249`).
2. `const builtinNameImpl = if (is_wasm) native_stub.stub else builtinNameNative;`
   near `:3357-3379` (WASM then gets a stub that raises `NotSupported`; without
   it the WASM build must resolve the libc symbols).
3. Optionally add the name to the suggestion list in `errors.zig:467-486`
   (`unknownFunction`). The static checker (`checker.zig`) knows the types of only a
   few builtins (`length` etc.); for the rest it infers "any", so a new builtin
   needs no checker entry (verified: `r = exec(...); r.status` type-checks).

The unit test goes next to the others in `builtins.zig` or, as I did, in a new
file pulled in from `lib.zig`'s `test {}` block.

### What I built (verified)

`sha256` and `random_bytes` exist, so only two builtins were missing.
Patch: `/Users/bg/code/marginalia/.claude/worktrees/blimp-rewrite/blimp/notes/blimp-native-ext.patch`
(applies to `chunks/lang`; new file `src/native_ext.zig` 328 lines, plus the
registration, `pub fn failArg`, a `lib.zig` test import, and three
`linkSystemLibrary("sqlite3", .{})` lines in `build.zig`). Result of
`zig build test`: 766/766 (762 before; 4 new). `zig build wasm` still builds.

Changes outside `native_ext.zig`:

```diff
-fn failArg(comptime fmt: []const u8, args: anytype) EvalError {
+pub fn failArg(comptime fmt: []const u8, args: anytype) EvalError {
...
         reg.register("argv", &builtinArgv_impl);
+        reg.register("exec", &builtinExec_impl);
+        reg.register("sqlite_query", &builtinSqliteQuery_impl);
...
 const builtinArgv_impl = if (is_wasm) native_stub.stub else builtinArgvNative;
+const builtinExec_impl = if (is_wasm) native_stub.stub else @import("native_ext.zig").exec;
+const builtinSqliteQuery_impl = if (is_wasm) native_stub.stub else @import("native_ext.zig").sqliteQuery;
--- lib.zig
+    _ = @import("native_ext.zig");
--- build.zig
+    exe.root_module.linkSystemLibrary("sqlite3", .{});      // before b.installArtifact(exe)
+    lib_mod.linkSystemLibrary("sqlite3", .{});               // before lib_tests
+    main_tests.root_module.linkSystemLibrary("sqlite3", .{});
```

**`exec(argv: [String], stdin: String) -> %{status, out, err}`.** Three `pipe()`s,
`fork()`, in the child `dup2` onto 0/1/2, close fds 3..1023, `execvp`, `_exit(127)`.
The parent writes stdin and drains stdout and stderr with one `poll` loop (so a
child that fills its stdout before reading stdin cannot deadlock), then `waitpid`.
`status` is the exit code, `-signal` if a signal ended it, `127` if `execvp` failed.
Output (`t/ext.blimp`):

```
exec(["echo","hello world"], "")                    %{status: 0, out: "hello world\n", err: ""}
exec(["cat"], "from stdin")                         %{status: 0, out: "from stdin", err: ""}
exec(["sh","-c","echo out; echo err 1>&2; exit 3"]) %{status: 3, out: "out\n", err: "err\n"}
exec(["sh","-c","kill -9 $$"], "")                  %{status: -9, out: "", err: ""}
exec(["no-such-program-xyz"], "")                   %{status: 127, out: "", err: ""}
exec(["wc","-c"], <109 KB of stdin>)                out: "  108893\n"
exec(["sh","-c","head -c 300000 /dev/zero"], "")    out length 300000
```

Gaps, by name: no timeout (blocks the whole interpreter, and under `--serve`
every other request, until the child exits); no environment or cwd control; no
`stdin` streaming. The fd-closing loop is there because `tcp_listen`/`tcp_accept`
do not set `FD_CLOEXEC`: before it, `ls /dev/fd` in the child showed the listener
(fds `0 1 2 3 4 5`), after it `0 1 2 3 4`. It is safe because the fork happens in
a process with other threads (`http_start` workers), and the child calls only
`dup2`, `close`, `execvp` and `_exit`; everything it needs is allocated before the
fork.

**`sqlite_query(path, sql, params) -> [[Any]]`.** Opens the file (creating it)
per call, `busy_timeout` 5 s, prepares **one** statement, binds `params` in order,
steps to the end, closes. Cells: INTEGER to Int, FLOAT to Float, TEXT and BLOB to
String, NULL to nil. Params: Int, Float, String, Bool (0/1), nil. A statement
with no result columns returns `[]`. Output (`t/sql.blimp`):

```
create table ...                                    []
insert into t(name, score) values (?, ?)  ["alice", 1.5]    []
select id, name, score from t order by id           [[1, "alice", 1.5], [2, "bob", nil]]
select count(*) from t where name = ?    ["alice"]  [[1]]
select x'00ff41', 'héllo', 9223372036854775807      [["\0\xffA", "héllo", 9223372036854775807]]
bad table                                           try/catch -> {:caught, :type_error}
                                                    uncaught -> -- BAD ARGUMENT -- sqlite_query: no such table: nope
```

Refused with a message (raise): wrong placeholder count, a second statement
("one statement per call"), an unbindable param (list, map, atom). Choices to
revisit: errors raise rather than returning `{:error, msg}`, which means a
server cannot see the message (see "What Blimp code can catch"; an error tuple like
`json_decode` is probably the better contract); the database is opened and closed
on every call (cheap for a file, but `:memory:` cannot persist between calls);
no transactions across calls (each call is its own connection, and a
multi-statement string is refused, so `begin ... commit` cannot be expressed; a
held handle, `sqlite_open`/`sqlite_close`, or an `sqlite_script(path, sql)` that
runs many statements would be the next step).

**How Zig links a C library here.** `module.linkSystemLibrary("sqlite3", .{})`;
the declarations are hand-written `extern "c" fn sqlite3_...` (no `@cImport`, so
no header is needed to build). The result:

```
$ otool -L zig-out/bin/blimp
	/usr/lib/libsqlite3.dylib (compatibility version 9.0.0, current version 382.0.0)
	/usr/lib/libSystem.B.dylib
$ ls /usr/lib/libsqlite3.dylib            -> No such file (it lives in the dyld shared cache, normal on macOS 11+)
$ xcrun --show-sdk-path                   -> /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
$ ls $SDK/usr/include/sqlite3.h           -> present
$ ls $SDK/usr/lib | grep sqlite           -> libsqlite3.0.tbd  libsqlite3.tbd
$ brew --prefix sqlite                    -> /opt/homebrew/opt/sqlite   (also installed; not needed)
```

SQLite from the OS: `select sqlite_version()` answers `[["3.51.0"]]`. On Linux the
same line needs `libsqlite3-dev`; a static build would use
`addCSourceFile` on the amalgamation instead. The Dockerfile for production is
not part of this survey.

**`sha256` / `random_bytes` in the requested shapes.** Already there:

```
sha256("abc")                      -> "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
hex_encode(random_bytes(8))        -> "9235bd46768d86d8"
length(random_bytes(16))           -> 16        # raw bytes
random_token(32)                   -> 43-char base64url
```

## 4. Process model

**Threads.** `main` spawns one thread with a **512 MiB stack** and runs
everything on it (`main.zig:21,32`); a Blimp call costs about 16 KB of native stack
and the call-depth ceiling is 10,000 (`eval.zig:93`). Tail calls are optimised:
a 100,000-iteration tail-recursive `def` and a never-ending
`def serve_loop ... serve_loop(fd, n + 1)` both ran fine.

**fork.** It is a real `fork(2)` (`builtins.zig:5548`): the child gets a
copy-on-write copy of the whole interpreter, heap included. The child is the
evaluator thread only; the main thread (blocked in `join`) and any `http_start`
worker threads do not exist in the child. Verified (`t/fork1.blimp`):

```
child sees 3 items; exit(7)
parent: waitpid returned 35539 (child pid was 35539)      # the pid, not the status 7
nohang while running: 0
nohang after exit equals pid: true
waitpid with no children: -1
```

- `fork` returns in both processes and **both continue after the `case`**; a child
  that does not call `exit` runs the rest of the program (I saw the program's
  tail printed twice). Always `exit(0)` in the child.
- `exit(n)` calls `std.process.exit`. stdout/stderr are unbuffered
  (`outWrite`, `builtins.zig:1486`), so there is nothing to flush.
- State changes in the child (actors, the session map) are lost; the
  concurrency doc says the same.
- **Sockets.** The child inherits every open fd. `tcp_close` in the parent is
  wrong after a fork: it does `shutdown(fd, SHUT_WR)` (socket-wide, not per fd)
  and then drains/lingers the fd, reading the request bytes the child has not
  read yet. Measured with `t/fork_srv.blimp`, the pattern from `concurrency.md`
  (`_ -> tcp_close(client_fd)` in the parent):

  ```
  curl: FAILED
  child: read 0 bytes, write -> error
  ```

  Without that line it works (`curl: hello`, child `read 78 bytes, write -> ok`).
  The cost is one leaked fd per request in the parent: **308 fds open after 300
  requests**; at `ulimit -n 64` the server stopped answering after 60. There is
  no builtin for a plain `close(2)`; adding one (say `fd_close(fd)`, no shutdown,
  no lingering) is the fix. Zombies: not a problem if the loop calls `waitpid(-1, true)` until it
  returns <= 0 (0 zombies, 0 children after 300 requests).
- Parent RSS with fork per request, 1000 requests: 2432 KB, 2496, 2512, 2560,
  2576 KB (+0.14 KB/request). Throughput was the same as non-fork (6 s for 1000
  requests including curl start-up).

**Accept and read.**

- `tcp_accept` blocks (`std.c.accept`) until a client arrives unless the
  listener was made non-blocking, in which case nil. A sleeping accept is not
  interruptible from Blimp.
- `tcp_read` is one `read()` into a 64 KiB stack buffer, copied to the heap. On a
  blocking socket it blocks until at least one byte, EOF (`""`) or reset (`""`).
  No timeout: a client that sends half a request and stalls holds the whole
  server (measured: a second client waited 3 s behind a stalled one on the plain
  loop).
- Bodies larger than 64 KiB: loop until `Content-Length` is satisfied. Verified
  with `t/srv_body.blimp` (parse `Content-Length` with `index_of`/`slice`, then
  `read_more` until `length(acc) >= header_end + 4 + content_length`):

  ```
  request 1: 149 bytes in 1 reads
  request 2: 300052 bytes in 31 reads
  request 3: 3000053 bytes in 301 reads
  ```

  (The reads are 10 KB because that is how the test client sent it. One read
  returns whatever has arrived, up to 64 KiB.) Building `acc` by `concat` costs
  about half of (reads x final size): for 301 reads of a 3 MB body that is on the
  order of 450 MB of retained garbage in a plain run. Keep chunks in a list and
  `join` once, or run under `--serve`.
- `tcp_write` handles partial writes itself (loop until all bytes are taken,
  waiting on `poll` for room), and returns `:error` for a peer that is gone or
  stalls for 10 s. It blocks the caller meanwhile; under `--serve` that is every
  request. `tcp_write_some` + `tcp_poll_write` is the non-blocking alternative.
  A 14 MB response to a normal client completed (`client got 14400063 bytes`).
- `sleep_ms(n)` is `nanosleep` restarted on signals, blocks the interpreter.
  `read_line()` blocks on fd 0, one byte per `read`. `tcp_poll([0], ms)` makes
  stdin pollable (PR 104).
- fd limits: the interpreter imposes none on sockets. `tcp_poll` allocates its
  `pollfd` array per call (no fixed size); the lingering-close table is 256
  entries (oldest is closed when full); `http_start` has 32 slots. The OS limit
  applies: `ulimit -n` in this shell is 1,048,576, but `launchctl limit maxfiles`
  soft is 256 for processes not started from a raised shell.
- `tcp_listen` binds `0.0.0.0` and IPv4 only.

## 5. Memory

**The evaluator allocates from an arena-backed heap and frees nothing**
(`gc.zig:1-22`, `heap_limit.zig:1-12`, `value.zig:3-13`). `heap_limit.zig` wraps the
arena's backing allocator: default `2 GiB` (`:29`), `BLIMP_HEAP_LIMIT=<bytes>`
changes it, `0` removes it (`:36`). Past it, allocations fail, `main.zig`
prints "Out of heap: this run reached its N MB ceiling" and exits 1. The count
is arena chunks, so it jumps in steps; a 50 MB limit stopped a request loop at
roughly 1700 requests though RSS was 33 MB.

Measurements (ReleaseSafe, `/usr/bin/time -l`, `process_stats()`):

```
100,000 iterations of: s = concat("request number ", to_string(n), "... padding ...", to_string(n*7)); tail call
    heap_bytes 45.3 MB   max RSS 37.6 MB     0.06 s       (~450 B per iteration)
1,000,000 iterations (same loop)
    heap_bytes 384 MB    max RSS 354 MB      0.58 s       (linear: ~384 B per iteration)
10,000 empty tail calls                       360 KB       (~36 B per call)
acc = concat(acc, "xxxxxxxxxx"), 10,000 times (final length 100 KB)
    heap_bytes 582 MB    max RSS 504 MB      <- quadratic: every step copies the whole string
same, 30,000 times (final 300 KB)             needs ~4.5 GB: hits the 2 GiB ceiling and stops
    with BLIMP_HEAP_LIMIT=0:  heap_bytes 6.65 GB, max RSS 1.9 GB (macOS compressed the rest)
5,000 appends to a list                       113 MB       (O(n) copy each: ~n^2/2 x 8 B)
2,000 puts into a map                         57 MB        (O(n) copy each)
5,000 concats up to 50 KB                     215 MB
join() of 5,000 pieces (50 KB)                ~0 (below the 1 MB arena granularity of this counter; one allocation)
```

**The accept loop with 1,000 HTTP requests.** Handler builds a ~3.3 KB HTML table
of 49 rows with `map`/`join` (`t/srv_plain.blimp`, tail-recursive
`serve_loop`, blocking `tcp_accept`, `curl -s` per request):

```
rss before (KB):   2448
after 250 requests rss (KB):   7760
after 500 requests rss (KB):  12960
after 750 requests rss (KB):  18144
after 1000 requests rss (KB): 23328            # 20.9 KB per request, linear
elapsed: 7s
```

At 21 KB a request, the 2 GiB ceiling is reached after about 100,000 requests;
a handler that renders more (the blog measured 0.86 MB a request, `main.zig:1373`)
reaches it in about 2,400. So a plain loop cannot be a long-lived server.

**Options that bound it:**

1. **`blimp --serve FILE --tick EXPR [--control PATH]`** (`main.zig:1434`).
   Boots the file once, then evaluates `EXPR` (for example `server <- :tick`) at
   top level in a Zig loop. Between ticks it resets the environment, drains the
   control socket, and when the heap has grown by `max(live_after_last_compact,
   16 MB)` it runs `gc.compactWith(..., .drop_unreachable)` (copy live data to
   the other half, drop the old half; actors nothing can name are dropped).
   It also sets SIGPIPE to ignore and survives a failing tick (logged). Same test
   as above with 3,000 requests (`t/srv_tick.blimp`, `tcp_poll([fd], 50)` in
   `:tick`, `tcp_accept` on a non-blocking listener):

   ```
   after  250 requests rss (KB):   7920
   after  500 requests rss (KB):  13200
   after  750 requests rss (KB):   7136     <- compaction
   after 1000 requests rss (KB):  12416
   ...
   after 3000 requests rss (KB):   9520      booted live heap 21512 bytes
   ```

   Constraints: the tick must do a bounded amount of work and must wait with a
   timeout (a tick that returns at once is a busy loop); a handler runs inside the
   tick, so one slow `tcp_write`, `exec` or `sqlite_query` stalls everything;
   state must live in actors or top-level bindings (anything on the Zig stack
   during a tick is gone at compaction, which the design relies on);
   `--control` creates a 0600 unix socket (default `blimp.sock` in the cwd) taking
   Blimp source to evaluate; `blimp --attach` is its client. A failing tick:

   ```
   good: <html>...request 1...      boom: (empty reply)      good again: ...request 2...
   server output: -- RUNTIME ERROR -- TypeError while evaluating this.  36| true -> to_int("x")
   ```

   The request whose handler failed is never answered or closed (fd leaked until
   exit). I did not test heap-ceiling behaviour inside `--serve`.
2. **Fork per request**: parent flat, children die. Needs the fd-leak caveat above.
3. A plain loop with a small `BLIMP_HEAP_LIMIT` under a supervisor that restarts
   it. Works but drops in-flight work and all in-memory state.

## 6. Strings

- Representation: `[]const u8` in `Value.string`. Any bytes, including NUL. No
  length limit other than memory (`read_file` 64 MiB; the source file 64 MiB).
- `concat` allocates a new string and copies every argument (O(total)). Repeated
  `concat(acc, x)` is O(n^2) in time and, because nothing is freed, in memory
  (above). `concat` takes any number of arguments, so a fixed template is one
  copy. `join(list, sep)` sizes once and copies once.
- `slice(s, start, len)` returns a view into the original (no copy, pins the
  original in memory); `split` parts are also views into the input. `replace`
  with no match returns the same value.
- `char_at`/`char_code`/`from_char_code`/`upcase`/`downcase`/`index_of`/`length`
  are bytes and ASCII; use `utf8_*` or `graphemes` for text. Observed with
  `"héllo"`: `length` 6, `utf8_length` 5, `char_at(s, 1)` a lone `0xC3` byte,
  `char_code(s, 1)` 195, `slice(s, 1, 2)` `é`, `utf8_slice(s, 1, 2)` `él`,
  `upcase` `HéLLO`, `utf8_upcase` `HÉLLO`.
- `to_string`: `1.5` -> `"1.5"`, `3.0` -> `"3"`, `1.0/3.0` -> `"0.3333333333333333"`,
  `1e21` -> `"1000000000000000000000"`, Bool -> `"true"`, nil -> `"nil"`, Atom ->
  its name without `:`. A List or Map raises (`to_string(%{a: 1})` gives
  `:type_error` in a catch). `puts`/`print` of a collection formats it:
  `%{a: 1, b: [1, 2]}`. `concat` of an Atom writes `:name`.
- `7 / 2` is `3`, `7 / 2.0` is `3.5`, `-7 / 2` is `-3`, `rem(-7, 2)` is `-1`.
- Escaping in HTML: nothing is escaped unless you go through `to_html`/`el`
  (section 9).

## 7. Maps and lists

- Map: a slice of `{key: []const u8, val}` in **insertion order**. `put` of an
  existing key replaces in place (position kept); a new key goes last
  (`put(%{z:1, a:2}, "m", 3)` then `put(.., "z", 9)` has keys `["z","a","m"]`).
  `put` and `merge` copy the whole entry array: O(n) per call, 2,000 puts built a
  57 MB heap. `lookup` is a linear scan comparing bytes (200,000 lookups in a
  2,000-key map took 541 ms with the loop overhead). Missing key: nil, for
  `lookup(m, k)` and `m.k` alike. Keys are strings only; `lookup(m, :a)` and
  `lookup(m, "a")` are the same. Atoms, ints etc. cannot be keys.
- List: a slice of pointers, immutable. `append` copies (O(n)); 5,000 appends
  cost 113 MB. `head`/`tail`: `tail` is a view (no copy). `set_at` copies.
  `reverse`, `sort`, `uniq` etc. return new lists. `range(1, n)` allocates n
  values (Ints above 4096 are heap-boxed, 24 bytes each plus the pointer).
- Sorting: `sort(list)` for all-number or all-string lists (strings by bytes),
  not stable, no custom comparator; `sort_by_keys(items, keys)` is stable and is
  how to sort by a field: `sort_by_keys(rows, map(rows, fn(r: Map) do r.name end))`.
  Mixed types or NaN raise.
- Equality: `[1, 2] == [1, 2]` true; `1 == 1.0` false.

## 8. Errors in a server

All verified with `t/robust.sh` + `t/client.py` against `t/srv_robust.blimp`
(plain blocking loop; handler reads once, then writes the 7.2 MB body three
times) and `t/errs.blimp`.

- **tcp_read of a closed peer**: returns `""` (EOF) or, after RST,
  `""` as well (ECONNRESET is mapped to `""`, `:4792-4810`). A client that connected
  and left gives `req 1 read 0 bytes`.
- **tcp_write to a closed peer**: returns `:error`; never raises, never kills the
  process. Writes in a sequence to a vanished client: `ok error error`,
  `error error error`.
- **SIGPIPE**: no kill. `--serve` ignores it explicitly (`main.zig:1462`), and in a
  plain run Zig's `std.Io.Threaded.init` already installs a no-op handler
  (`/opt/homebrew/Cellar/zig/0.16.0_1/lib/zig/std/Io/Threaded.zig:1661`).
- **Disconnect mid-request/response**: five hostile clients in a row (connect and
  close; half a request line then close; full request then RST; request, wait,
  RST while the response is being written; a normal 14 MB download). Result:
  `server alive` after every one, and the last client received all 14,400,063
  bytes. The server survives today. What it does not survive is its own bugs.
- **fd misuse**: `tcp_read(999)` raises `NotSupported` (caught as `:error`). After
  `tcp_close(c)`, the fd is still open in the lingering table for up to 30 s:
  `tcp_read(c)` returns **nil** (it was made non-blocking), `tcp_write(c, "x")`
  returns `:error`. Reading or writing a closed-then-reused fd number would hit
  whatever socket now has it.
- **tcp_listen on a busy port** prints the reason and raises `NotSupported`
  (`{:caught_listen, :error}`). `tcp_accept(-1)` raises.
- **Unhandled error at top level (plain run)**: prints the error with source
  line, exit status 1 (`t/errs.blimp`). Inside an actor handler I did not test
  anything beyond the `--serve` case below; actors have `bubbles(...)` strategies
  (`examples/supervision.blimp`).
- **Unhandled error under `--serve`**: logged, tick abandoned, loop continues.
- **Heap exhaustion**: plain run exits 1 with the "Out of heap" text.
- **Recursion** deeper than 10,000 non-tail calls: a `RECURSION TOO DEEP` error,
  not a segfault (per `errors.zig`'s `recursionTooDeep`; I did not trigger it).

## 9. `to_html` and the view builtins

Mostly nothing reusable, with one exception.

- `stack`, `row`, `grid`, `text`, `button`, `heading`, ... build `view_node`
  values for the Blimp browser runtime (`web/blimp-view.js`, event messages,
  `view_diff`). `to_html(stack(text("hello"), button("Go", :go)))` gives
  `<div><span>hello</span><button data-sends="go" onclick="blimpSend(this)">Go</button></div>`:
  it assumes a page that defines a `blimpSend` JS function and posts `msg=`; the
  markup is not what a hand-written app wants.
- `el(tag, attrs, children...)` + `to_html` **is** a safe HTML builder:
  attribute values and text are escaped, booleans and nil attrs behave like HTML,
  children are variadic and lists flatten.

  ```
  to_html(el("ul", %{id: "x"}, el("li", %{}, "a<b"), el("li", %{class: "k"}, "c")))
    -> <ul id="x"><li>a&lt;b</li><li class="k">c</li></ul>
  to_html(el("input", %{type: "text", disabled: true, value: "v\"q"}))
    -> <input type="text" disabled value="v&quot;q">
  to_html(el("a", %{href: "/x?a=1&b=2", click: :go}, "link"))
    -> <a href="/x?a=1&amp;b=2">link</a>             # host instruction `click` dropped
  to_html(el("p", %{}, 42, " items"))
    -> <p>42 items</p>                                # numbers are accepted as children
  to_html(el("div", %{inner_html: "<b>raw</b>"}))
    -> <div><b>raw</b></div>                          # inner_html is written unescaped
  to_html(el("form", %{submit: :save, action: "/save"}, el("input", %{name: "q"})))
    -> <form action="/save"><input name="q"></form>
  ```

  Limits: the tag must be in `el_tags` (`builtins.zig:2478`), which has no
  `html head body meta link style script`, so a page shell is a string; `el("script", ...)`
  raises; `on*` attributes and `javascript:` URLs raise; the instruction keys
  (`click with input change submit swipe drag select ...`, `:2493`) are silently
  omitted, so `form`'s `submit:` is not turned into an `action` (give `action:` yourself);
  `inner_html:` is the unescaped escape hatch. No escape function
  is exposed on its own: there is no `html_escape(s)` builtin, so a string
  renderer built on `concat` has to write its own `replace` chain (`&` first).

## Appendix: commands to reproduce

```
cd <scratchpad>/native
zig build interp                       # 22 s
zig build test --summary all           # 766 tests
./zig-out/bin/blimp t/ext.blimp        # exec, sha256, random_bytes
./zig-out/bin/blimp t/sql.blimp        # sqlite_query
./zig-out/bin/blimp t/ext_test.blimp --test
zsh t/srv_run.sh t/srv_plain.blimp 18080 1000                                   # plain loop, RSS growth
zsh t/srv_run2.sh 18081 3000 --serve t/srv_tick.blimp --tick "server <- :tick" --control t/x.sock
zsh t/robust.sh 18082 t/srv_robust.blimp                                        # hostile clients
zsh t/fork_run.sh ; zsh t/fdleak.sh ; zsh t/body_run.sh ; zsh t/boom.sh
```

Baseline (unmodified) tree for comparison: `<scratchpad>/orig` (`make blimp` and
`zig build` experiments). The original `chunks/lang` was not touched.
