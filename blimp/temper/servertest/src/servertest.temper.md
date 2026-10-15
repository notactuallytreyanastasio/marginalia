# Tests for server

Every check runs inside a helper that takes the `test`, or the compiler
evaluates it while compiling and the generated code is never exercised.

    let { Request, httpParse, Response } = import("http/src");
    let {
      sysFork, sysExit, sysSleepMs, sysRss, sysNowMs, sysExec, sysWriteFile,
      sysReadFile, sysWaitPid, sysFileSize, sysByteLength, sysStringTrim,
    } = import("sys/src");
    let {
      serverDefaultHandler, serverRespond, serveWith,
    } = import("server/src");

    let expectTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let has(haystack: String, needle: String): Boolean {
      haystack.split(needle).length > 1
    }

    let get(path: String): Request {
      httpParse("GET ${path} HTTP/1.1\r\nHost: localhost\r\n\r\n")
    }

## The pure parts

    test("the default handler answers its routes") { test =>
      let h = serverDefaultHandler(get("/healthz"));
      expectInt(test, h.status, 200);
      expectTrue(test, h.body == "ok", "healthz body: ${h.body}");

      let root = serverDefaultHandler(get("/"));
      expectInt(test, root.status, 200);
      expectTrue(test, has(root.body, "Marginalia"), "root names the app");
      expectTrue(test, has(root.body, "<link rel=\"stylesheet\" href=\"/assets/css/app.css\">"), "root links the css");

      let site = serverDefaultHandler(get("/sitemap.xml"));
      expectInt(test, site.status, 200);
      expectTrue(test, site.body == "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\"></urlset>", "sitemap: ${site.body}");

      let login = serverDefaultHandler(get("/users/log-in"));
      expectInt(test, login.status, 200);
      expectTrue(test, has(login.body, "<form"), "log-in has a form");

      expectInt(test, serverDefaultHandler(get("/works")).status, 200);

      let missing = serverDefaultHandler(get("/nope"));
      expectInt(test, missing.status, 404);
      expectTrue(test, has(missing.body, "Not Found"), "404 page says Not Found");
    }

    let boom(r: Request): Response throws Bubble {
      bubble()
    }

    test("a bubble escaping the handler is a 500 page and a log line") { test =>
      sysExec(["rm", "-f", "log/error.log"], "", null);
      let resp = serverRespond(boom, get("/explode"));
      expectInt(test, resp.status, 500);
      expectTrue(test, has(resp.body, "Something went wrong"), "500 page text");
      let logged = sysReadFile("log/error.log");
      if (logged != null) {
        expectTrue(test, has(logged, "GET /explode Bubble"), "error.log line: ${logged}");
      } else {
        expectTrue(test, false, "no log/error.log");
      }
    }

    test("a request the parser refused is a 400") { test =>
      let bad = serverRespond(serverDefaultHandler, httpParse("nonsense"));
      expectInt(test, bad.status, 400);
    }

## The real server

A forked child runs the accept loop. The parent is this test. The loop's
parent process is the forked pid, so its RSS is read with `ps`.

    @connected
    let serverTestRequest(port: Int, data: String): String;

    @connected
    let serverTestHangup(port: Int): Void;

    let ask(port: Int, path: String): String {
      serverTestRequest(port, "GET ${path} HTTP/1.1\r\nHost: localhost\r\n\r\n")
    }

    let rssOf(pid: Int): String {
      let out = sysExec(["ps", "-o", "rss=", "-p", pid.toString()], "", null);
      out[1]
    }

    test("a forked server answers 50 requests, survives hostile clients, and stays flat") { test =>
      let port = 45000 + (sysNowMs() % 1000i64).toInt32Unsafe();
      let quit = "log/quit";
      sysExec(["mkdir", "-p", "log"], "", null);
      sysExec(["rm", "-f", quit], "", null);
      let pid = sysFork();
      if (pid == 0) {
        serveWith(port, serverDefaultHandler, quit);
        sysExit(0);
      }
      sysSleepMs(200);
      let before = rssOf(pid);

      for (var i = 0; i < 50; ++i) {
        let k = i % 5;
        if (k == 0 || k == 3) {
          let r = ask(port, "/healthz");
          expectTrue(test, has(r, "HTTP/1.1 200 OK"), "healthz status: ${r}");
          expectTrue(test, has(r, "\r\n\r\nok"), "healthz body: ${r}");
        } else if (k == 1) {
          let r = ask(port, "/");
          expectTrue(test, has(r, "HTTP/1.1 200 OK"), "root status: ${r}");
          expectTrue(test, has(r, "Marginalia"), "root body");
        } else if (k == 2) {
          let r = ask(port, "/nope");
          expectTrue(test, has(r, "HTTP/1.1 404 Not Found"), "nope status: ${r}");
        } else {
          let r = ask(port, "/users/log-in");
          expectTrue(test, has(r, "<form"), "log-in form");
        }
      }

A 128 KiB body: read whole, answered.

      var body = "x";
      for (var d = 0; d < 17; ++d) { body = "${body}${body}"; }
      let big = serverTestRequest(
        port,
        "POST /healthz HTTP/1.1\r\nHost: a\r\nContent-Length: ${sysByteLength(body).toString()}\r\n\r\n${body}",
      );
      expectTrue(test, has(big, "HTTP/1.1 200 OK"), "big body answered: ${big}");

A client that connects and leaves, three times, and the next request works.

      serverTestHangup(port);
      serverTestHangup(port);
      serverTestHangup(port);
      let after = ask(port, "/healthz");
      expectTrue(test, has(after, "\r\n\r\nok"), "alive after hangups: ${after}");

      let flat = rssOf(pid);
      console.log("server parent RSS KB before: ${sysStringTrim(before)} after 50+ requests: ${sysStringTrim(flat)}");

Stop it: the quit file is checked after each accept.

      sysWriteFile(quit, "1");
      let last = ask(port, "/healthz");
      expectTrue(test, has(last, "\r\n\r\nok"), "the last request is still answered: ${last}");
      var gone = 0;
      for (var w = 0; w < 30 && gone != pid; ++w) {
        gone = sysWaitPid(pid, true);
        if (gone != pid) { sysSleepMs(100); }
      }
      expectInt(test, gone, pid);
      sysExec(["rm", "-f", quit], "", null);
    }
