# The machine, as Temper sees it

Temper on Blimp cannot read a file, ask the time, open a socket or hash a
string on its own. The interpreter has builtins for all of those; this module
declares them so Temper code can call them, and `_connected.blimp` beside it
gives each declaration its one-line body.

Two rules shape every signature. Blimp hands values back as lists, strings,
integers, booleans and `nil`, never as Temper maps (a Temper `Map` is an actor
the builtins cannot build), so anything structured comes back as a list of
strings and the caller takes it apart. And a Blimp parameter with a declared
type crashes on `nil`, so the bodies take `Any` and check.

Names carry the `sys` prefix because every exported Temper name shares one
flat namespace with std and with the builtins, and a collision is silent.

## Files

`sysReadFile` is `null` for a file that is missing or unreadable, as the
builtin is. A directory listing is sorted by bytes and leaves out `.` and `..`.

    @connected
    export let sysReadFile(path: String): String?;

    @connected
    export let sysWriteFile(path: String, data: String): Boolean;

    @connected
    export let sysAppendFile(path: String, data: String): Void;

    @connected
    export let sysListDir(path: String): List<String>;

`-1` for a file that is not there.

    @connected
    export let sysFileSize(path: String): Int;

## Environment and process

    @connected
    export let sysGetEnv(name: String): String?;

    @connected
    export let sysArgv(): List<String>;

    @connected
    export let sysExit(code: Int): Void;

`sysFork` answers `0` in the child and the child's pid in the parent, like
`fork(2)`. A child must end in `sysExit`; one that returns runs the rest of
the program. `sysWaitPid` with `noHang` answers `0` while the child runs,
the pid once it has exited, and `-1` when there is no such child; the exit
status is not available.

    @connected
    export let sysFork(): Int;

    @connected
    export let sysWaitPid(pid: Int, noHang: Boolean): Int;

Reap every finished child: the pids, in no order.

    @connected
    export let sysReapChildren(): List<Int>;

`sysExec` runs a program and waits for it. The answer is three strings:
the exit status as decimal text (`-N` when a signal ended it), everything it
wrote to stdout, everything it wrote to stderr. `cwd` may be null. There is
no timeout.

    @connected
    export let sysExec(argv: List<String>, stdin: String, cwd: String?): List<String> throws Bubble;

    @connected
    export let sysSleepMs(ms: Int): Void;

Resident set size, in bytes.

    @connected
    export let sysRss(): Int;

## Time

Milliseconds since the epoch, and the UTC clock as `YYYY-MM-DD HH:MM:SS`,
which is how every timestamp is stored.

    @connected
    export let sysNowMs(): Int64;

A monotonic millisecond clock for measuring durations; its zero is arbitrary.

    @connected
    export let sysMonoMs(): Int64;

    @connected
    export let sysUtcNow(): String;

    @connected
    export let sysUtcFromMs(ms: Int64): String;

## Bytes, text and hashes

`sysByteLength` is the UTF-8 length. Temper counts code points and has no
way to ask for bytes, and `Content-Length` is bytes.

    @connected
    export let sysByteLength(s: String): Int;

Hex digests, lower case.

    @connected
    export let sysSha256(s: String): String;

    @connected
    export let sysHmacSha256(key: String, msg: String): String;

PBKDF2-HMAC-SHA256; the salt is hex in, the key is hex out.

    @connected
    export let sysPbkdf2(password: String, saltHex: String, iterations: Int, dklen: Int): String;

Random bytes from the OS, as hex; and a 43-character url-safe token.

    @connected
    export let sysRandomHex(bytes: Int): String;

    @connected
    export let sysRandomToken(): String;

    @connected
    export let sysBase64(s: String): String;

`null` for text that is not strict base64.

    @connected
    export let sysBase64Decode(s: String): String?;

    @connected
    export let sysConstantTimeEq(a: String, b: String): Boolean;

    @connected
    export let sysUtf8Valid(s: String): Boolean;

Whole-string case mapping, Unicode-aware, and grapheme counts.

    @connected
    export let sysUtf8Downcase(s: String): String;

    @connected
    export let sysUtf8Upcase(s: String): String;

    @connected
    export let sysGraphemeLength(s: String): Int;

    @connected
    export let sysGraphemeTake(s: String, n: Int): String;

The string operations Temper's `String` lacks, done natively: every
occurrence replaced, left to right without overlap; ASCII whitespace trimmed
from both ends; a list joined once.

    @connected
    export let sysStringReplace(s: String, from: String, to: String): String;

    @connected
    export let sysStringTrim(s: String): String;

    @connected
    export let sysJoin(parts: List<String>, sep: String): String;

A nested list of strings, however deep, joined into one string in one native
pass. This is what a rendered page goes through.

    @connected
    export let sysFlatJoin(parts: List<AnyValue>): String;

## Sockets

The server loop, not `std/serve`: `std/serve` reads one 64 KB segment and
cannot be told which fd it holds, and a forked child needs the fd. These are
the raw calls.

`sysListen` bubbles with a message naming the port when it cannot bind.
`sysAccept` blocks. `sysReadRequest` reads until the header block has
arrived and then until `Content-Length` more bytes have, or `maxBytes` is
exceeded; past the cap it stops reading and inserts `X-Blimp-Truncated: 1`
as the first header line so the parser can answer 413. It is `null` when the
client went away before sending a complete request line. `sysCloseFd` is a
plain `close(2)` for the parent's copy of a socket a child owns;
`sysClose` is the full shutdown-and-close for the side that answered.

    @connected
    export let sysListen(port: Int): Int throws Bubble;

    @connected
    export let sysAccept(fd: Int): Int;

    @connected
    export let sysReadRequest(fd: Int, maxBytes: Int): String?;

    @connected
    export let sysWrite(fd: Int, data: String): Boolean;

    @connected
    export let sysClose(fd: Int): Void;

    @connected
    export let sysCloseFd(fd: Int): Void;

## HTTPS

The interpreter's client runs on a thread. `sysHttpStart` answers a handle;
`sysHttpResult` is `null` while the request is in flight, then
`["ok", status, body]` or `["error", reason]`. Headers are `Name: value`
strings. Bodies are capped at 8 MiB by the interpreter.

    @connected
    export let sysHttpStart(method: String, url: String, headers: List<String>, body: String, timeoutMs: Int): Int throws Bubble;

    @connected
    export let sysHttpResult(handle: Int): List<String>?;

Wait for one, polling every 50 ms.

    export let sysHttpAwait(handle: Int): List<String> {
      var result: List<String>? = sysHttpResult(handle);
      while (result == null) {
        sysSleepMs(50);
        result = sysHttpResult(handle);
      }
      let done = result;
      let none: List<String> = [];
      if (done != null) { done } else { none }
    }

## SQLite

A handle per open database. `sysDbQuery` binds every parameter as text
(`null` binds NULL) and answers every cell as text, NULL as `null`; the first
row is the column names. A statement with no result columns answers
`[["changes"], ["N"]]`.

    @connected
    export let sysDbOpen(path: String): Int throws Bubble;

    @connected
    export let sysDbExec(db: Int, sql: String): Int throws Bubble;

    @connected
    export let sysDbQuery(db: Int, sql: String, params: List<String?>): List<List<String?>> throws Bubble;

    @connected
    export let sysDbLastId(db: Int): Int;

    @connected
    export let sysDbChanges(db: Int): Int;

    @connected
    export let sysDbClose(db: Int): Void;
