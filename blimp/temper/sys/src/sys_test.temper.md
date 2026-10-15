# Tests for sys

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Calls to `@connected` functions are never
evaluated early, but the comparisons around them can be.

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let expectTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let orEmpty(s: String?): String {
      if (s != null) { s } else { "" }
    }

    let orNull(s: String?): String {
      if (s != null) { s } else { "NULL" }
    }

    let accented(): String { "h\u{e9}llo" }

## Bytes and text

    test("byte length counts UTF-8 bytes, not code points") { test =>
      expectInt(test, sysByteLength("h\u{e9}llo"), 6);
      expectInt(test, sysByteLength(""), 0);
    }

    test("sha256 and hmac are lower-case hex") { test =>
      expectText(test, sysSha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
      expectText(test, sysHmacSha256("key", "The quick brown fox jumps over the lazy dog"), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8");
    }

    test("random hex and tokens have the right shape") { test =>
      expectInt(test, sysRandomHex(8).countBetween(String.begin, sysRandomHex(8).end), 16);
      expectInt(test, sysRandomToken().countBetween(String.begin, sysRandomToken().end), 43);
      expectTrue(test, sysRandomToken() != sysRandomToken(), "two tokens differ");
    }

    test("base64 round trips and rejects junk") { test =>
      expectText(test, sysBase64("hi"), "aGk=");
      expectText(test, orEmpty(sysBase64Decode("aGk=")), "hi");
      expectTrue(test, sysBase64Decode("not base64!") == null, "junk decodes to null");
    }

    test("unicode case mapping and graphemes") { test =>
      expectText(test, sysUtf8Downcase("\u{c0}B"), "\u{e0}b");
      expectText(test, sysUtf8Upcase("stra\u{df}e"), "STRASSE");
      expectInt(test, sysGraphemeLength("e\u{301}a"), 2);
      expectText(test, sysGraphemeTake("e\u{301}abc", 2), "e\u{301}a");
    }

    test("replace, trim and join are native") { test =>
      expectText(test, sysStringReplace("aaa", "aa", "b"), "ba");
      expectText(test, sysStringTrim("  x y \t\n"), "x y");
      expectText(test, sysJoin(["a", "b", "c"], ", "), "a, b, c");
      expectText(test, sysJoin([], ", "), "");
    }

    test("flat join flattens any depth") { test =>
      let tree: List<AnyValue> = ["<p>", ["a", ["b", "c"]], "</p>"];
      expectText(test, sysFlatJoin(tree), "<p>abc</p>");
      expectText(test, sysFlatJoin([]), "");
    }

## Environment, time, files

    test("env is null when unset") { test =>
      expectTrue(test, sysGetEnv("PATH") != null, "PATH is set");
      expectTrue(test, sysGetEnv("MARGINALIA_NO_SUCH_VARIABLE") == null, "unset is null");
    }

    test("the clock is UTC text") { test =>
      expectInt(test, sysUtcNow().countBetween(String.begin, sysUtcNow().end), 19);
      expectText(test, sysUtcFromMs(0i64), "1970-01-01 00:00:00");
      expectText(test, sysUtcFromMs(1700000000000i64), "2023-11-14 22:13:20");
      expectTrue(test, sysNowMs() > 1700000000000i64, "now is after 2023");
    }

    test("files round trip") { test =>
      let fname = "marginalia-sys-test-${sysRandomHex(4)}.txt";
      let path = "/tmp/${fname}";
      expectTrue(test, sysWriteFile(path, accented()), "write succeeds");
      expectText(test, orEmpty(sysReadFile(path)), accented());
      expectInt(test, sysFileSize(path), 6);
      expectTrue(test, sysReadFile("/tmp/${fname}.missing") == null, "missing is null");
      expectInt(test, sysFileSize("/tmp/${fname}.missing"), -1);
      let listing = sysListDir("/tmp").join(",") { (s: String): String => s };
      expectTrue(test, listing.split(fname).length == 2, "listing names the file");
      expectInt(test, sysListDir("/tmp/${fname}.nodir").length, 0);
    }

    test("exec captures status and output") { test =>
      let r = sysExec(["/bin/echo", "hello"], "", null);
      expectText(test, r[0], "0");
      expectText(test, r[1], "hello\n");
      let bad = sysExec(["/bin/sh", "-c", "echo oops >&2; exit 3"], "", null);
      expectText(test, bad[0], "3");
      expectText(test, bad[2], "oops\n");
      let cat = sysExec(["/bin/cat"], "from stdin", null);
      expectText(test, cat[1], "from stdin");
    }

    test("append file appends") { test =>
      let path = "/tmp/marginalia-sys-append-${sysRandomHex(4)}.log";
      sysAppendFile(path, "one\n");
      sysAppendFile(path, "two\n");
      expectText(test, orEmpty(sysReadFile(path)), "one\ntwo\n");
    }

## Process

    test("a forked child's work is visible to the parent after waitpid") { test =>
      let path = "/tmp/marginalia-sys-fork-${sysRandomHex(4)}.txt";
      let pid = sysFork();
      if (pid == 0) {
        sysWriteFile(path, "from the child");
        sysExit(0);
      }
      var done = sysWaitPid(pid, false);
      expectInt(test, done, pid);
      expectText(test, orEmpty(sysReadFile(path)), "from the child");
      expectInt(test, sysReapChildren().length, 0);
    }

## Sockets

Loopback: connect first so the bytes are queued, then accept and read. One
process, no threads, and it still exercises the header and body phases.

    @connected
    let sysTestConnect(port: Int): Int;

    @connected
    let sysTestSend(fd: Int, data: String): Void;

    test("a request with a body is read whole") { test =>
      let port = 42000 + (sysNowMs() % 1000i64).toInt32Unsafe();
      let server = sysListen(port);
      let client = sysTestConnect(port);
      sysTestSend(client, "POST /x HTTP/1.1\r\nHost: a\r\nContent-Length: 11\r\n\r\n");
      sysTestSend(client, "hello world");
      let conn = sysAccept(server);
      let raw = orEmpty(sysReadRequest(conn, 1000000));
      expectText(test, raw, "POST /x HTTP/1.1\r\nHost: a\r\nContent-Length: 11\r\n\r\nhello world");
      expectTrue(test, sysWrite(conn, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"), "write ok");
      sysClose(conn);
      sysClose(client);
      sysClose(server);
    }

    test("a body past the cap is marked truncated") { test =>
      let port = 43000 + (sysNowMs() % 1000i64).toInt32Unsafe();
      let server = sysListen(port);
      let client = sysTestConnect(port);
      sysTestSend(client, "POST /x HTTP/1.1\r\nContent-Length: 20\r\n\r\n12345678901234567890");
      let conn = sysAccept(server);
      let raw = orEmpty(sysReadRequest(conn, 10));
      expectTrue(test, raw.split("\r\nX-Blimp-Truncated: 1\r\n").length == 2, "marker inserted after the request line: ${raw}");
      expectText(test, raw.split("\r\n")[0], "POST /x HTTP/1.1");
      sysClose(conn);
      sysClose(client);
      sysClose(server);
    }

    test("listening twice on one port bubbles with the port in the message") { test =>
      let port = 44000 + (sysNowMs() % 1000i64).toInt32Unsafe();
      let server = sysListen(port);
      var message = "";
      do {
        sysListen(port);
      } orelse do {
        message = "bubbled";
      }
      expectText(test, message, "bubbled");
      sysClose(server);
    }

## HTTPS

No network in tests: a connection refused is an error result, not a hang.

    test("an unreachable host is an error result") { test =>
      let handle = sysHttpStart("GET", "http://127.0.0.1:1/", [], "", 2000);
      let r = sysHttpAwait(handle);
      expectText(test, r[0], "error");
    }

## SQLite

    test("a database answers text cells with a header row") { test =>
      let db = sysDbOpen(":memory:");
      sysDbExec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, n INTEGER, f REAL, b BLOB)");
      let ins = sysDbQuery(db, "INSERT INTO t (name, n, f) VALUES ($1, $2, $3)", ["O'Brien \u{e9}", "42", "1.5"]);
      expectText(test, orEmpty(ins[0][0]), "changes");
      expectText(test, orEmpty(ins[1][0]), "1");
      expectInt(test, sysDbLastId(db), 1);
      let nullBuilder = new ListBuilder<String?>();
      nullBuilder.add(null);
      let nullParams = nullBuilder.toList();
      sysDbQuery(db, "INSERT INTO t (name) VALUES ($1)", nullParams);
      let rows = sysDbQuery(db, "SELECT id, name, n, f FROM t ORDER BY id", []);
      expectInt(test, rows.length, 3);
      expectText(test, rows[0].join(",") { (c: String?): String => orNull(c) }, "id,name,n,f");
      expectText(test, rows[1].join(",") { (c: String?): String => orNull(c) }, "1,O'Brien \u{e9},42,1.5");
      expectText(test, rows[2].join(",") { (c: String?): String => orNull(c) }, "2,NULL,NULL,NULL");
      expectInt(test, sysDbExec(db, "UPDATE t SET n = 7"), 2);
      expectInt(test, sysDbChanges(db), 2);
      sysDbClose(db);
    }

    test("pbkdf2 matches a known vector") { test =>
      expectText(test, sysPbkdf2("password", "73616c74", 1, 32), "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b");
      expectTrue(test, sysConstantTimeEq("abc", "abc"), "equal");
      expectTrue(test, !sysConstantTimeEq("abc", "abd"), "different");
      expectTrue(test, !sysConstantTimeEq("abc", "ab"), "different lengths");
    }
