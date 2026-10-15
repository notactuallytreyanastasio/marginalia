# Tests for http

Every check runs inside a helper that takes the `test`, or the compiler
evaluates it while compiling and the generated code is never exercised.

`httpParse` is given the whole raw request. Reading the rest of a body from
the socket is the socket layer's concern, and nothing here tests it.

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()} want ${want.toString()}" }
    }

    let expectBool(test: Test, got: Boolean, want: Boolean): Void {
      assert(got == want) { "got ${got.toString()} want ${want.toString()}" }
    }

    let orNil(s: String?): String {
      if (s == null) { "nil" } else { s }
    }

    let statusOf(r: Response?): Int {
      if (r == null) { -1 } else { r.status }
    }

    let at(m: Map<String, String>, key: String): String {
      m.getOr(key, "<missing>")
    }

    let lines(parts: List<String>): String {
      parts.join("\r\n") { (x: String): String => x }
    }

    let multipartBody(): String {
      lines([
        "--XyZ",
        "Content-Disposition: form-data; name=\"title\"",
        "",
        "Chapter one",
        "--XyZ",
        "Content-Disposition: form-data; name=\"kind\"",
        "",
        "essay",
        "--XyZ",
        "Content-Disposition: form-data; name=\"upload\"; filename=\"draft.md\"",
        "Content-Type: text/markdown",
        "",
        "# Draft\r\n\r\nline two",
        "--XyZ--",
        "",
      ])
    }

    let multipartRequest(body: String): String {
      lines([
        "POST /import HTTP/1.1",
        "Host: localhost",
        "Content-Type: multipart/form-data; boundary=XyZ",
        "",
        body,
      ])
    }

## Parsing

    test("a GET with a query string and cookies") { test =>
      let r = httpParse(lines([
        "GET /works/12?tab=notes&q=two%20words HTTP/1.1",
        "Host: localhost:4000",
        "Cookie: _marginalia_key=abc123; theme=dark",
        "",
        "",
      ]));
      expectText(test, r.method, "GET");
      expectText(test, r.path, "/works/12");
      expectText(test, at(r.query, "tab"), "notes");
      expectText(test, at(r.query, "q"), "two words");
      expectText(test, at(r.cookies, "_marginalia_key"), "abc123");
      expectText(test, at(r.cookies, "theme"), "dark");
      expectText(test, r.body, "");
      expectBool(test, r.truncated, false);
    }

    test("header names are lower-cased and the last of a repeated header wins") { test =>
      let r = httpParse(lines([
        "GET / HTTP/1.1", "X-Thing: one", "x-thing:   two  ", "HOST: here", "", "",
      ]));
      expectText(test, at(r.headers, "x-thing"), "two");
      expectText(test, at(r.headers, "host"), "here");
    }

    test("header and param lookups") { test =>
      let r = httpParse(lines([
        "POST /a?from=query&both=q HTTP/1.1",
        "Content-Type: application/x-www-form-urlencoded",
        "",
        "both=f&only=form",
      ]));
      expectText(test, orNil(r.header("Content-TYPE")), "application/x-www-form-urlencoded");
      expectBool(test, r.header("x-missing") == null, true);
      expectText(test, orNil(r.param("both")), "f");
      expectText(test, orNil(r.param("from")), "query");
      expectText(test, orNil(r.param("only")), "form");
      expectBool(test, r.param("nope") == null, true);
    }

    test("several Cookie headers are merged") { test =>
      let r = httpParse(lines([
        "GET / HTTP/1.1", "Cookie: a=1", "Cookie: b=2; c=3", "", "",
      ]));
      expectText(test, at(r.cookies, "a"), "1");
      expectText(test, at(r.cookies, "b"), "2");
      expectText(test, at(r.cookies, "c"), "3");
    }

    test("a urlencoded POST decodes + as space and %2B as plus") { test =>
      let r = httpParse(lines([
        "POST /ev/save HTTP/1.1",
        "Content-Type: application/x-www-form-urlencoded; charset=UTF-8",
        "Content-Length: 31",
        "",
        "title=a+b%2Bc&note=x%26y%3Dz&e=",
      ]));
      expectText(test, r.method, "POST");
      expectText(test, at(r.form, "title"), "a b+c");
      expectText(test, at(r.form, "note"), "x&y=z");
      expectText(test, at(r.form, "e"), "");
      expectText(test, r.body, "title=a+b%2Bc&note=x%26y%3Dz&e=");
    }

    test("percent-encoded UTF-8 in a form decodes to code points") { test =>
      let r = httpParse(lines([
        "POST / HTTP/1.1", "Content-Type: application/x-www-form-urlencoded", "",
        "w=caf%C3%A9+%E2%80%94+%F0%9F%99%82",
      ]));
      expectText(test, at(r.form, "w"), "café — 🙂");
    }

    test("a multipart body with two fields and one file") { test =>
      let r = httpParse(multipartRequest(multipartBody()));
      expectText(test, r.method, "POST");
      expectText(test, at(r.form, "title"), "Chapter one");
      expectText(test, at(r.form, "kind"), "essay");
      expectInt(test, r.form.keys().length, 2);
      expectInt(test, r.files.length, 1);
      let f = r.files.getOr(0, new UploadedFile("", "", "", ""));
      expectText(test, f.field, "upload");
      expectText(test, f.filename, "draft.md");
      expectText(test, f.contentType, "text/markdown");
      expectText(test, f.content, "# Draft\r\n\r\nline two");
    }

    test("a multipart boundary may be quoted and followed by parameters") { test =>
      let r = httpParse(lines([
        "POST / HTTP/1.1",
        "Content-Type: multipart/form-data; boundary=\"b0\"; charset=utf-8",
        "",
        "--b0",
        "Content-Disposition: form-data; name=\"a\"",
        "",
        "1",
        "--b0--",
        "",
      ]));
      expectText(test, at(r.form, "a"), "1");
    }

    test("an empty file input is skipped, and a file without a type is octet-stream") { test =>
      let r = httpParse(multipartRequest(lines([
        "--XyZ",
        "Content-Disposition: form-data; name=\"empty\"; filename=\"\"",
        "Content-Type: application/octet-stream",
        "",
        "",
        "--XyZ",
        "Content-Disposition: form-data; name=\"f\"; filename=\"a.bin\"",
        "",
        "abc",
        "--XyZ--",
        "",
      ])));
      expectInt(test, r.files.length, 1);
      let f = r.files.getOr(0, new UploadedFile("", "", "", ""));
      expectText(test, f.filename, "a.bin");
      expectText(test, f.contentType, "application/octet-stream");
      expectText(test, f.content, "abc");
    }

    test("a multipart request with no boundary is BAD") { test =>
      let r = httpParse(lines([
        "POST / HTTP/1.1", "Content-Type: multipart/form-data", "", "x",
      ]));
      expectText(test, r.method, "BAD");
    }

    test("a body that contains a blank line is kept whole") { test =>
      let r = httpParse(lines([
        "POST /raw HTTP/1.1", "Content-Type: text/plain", "", "one\r\n\r\ntwo",
      ]));
      expectText(test, r.body, "one\r\n\r\ntwo");
    }

    test("the truncation marker sets truncated and is not a header") { test =>
      let r = httpParse("X-Blimp-Truncated: 1\r\nPOST /x HTTP/1.1\r\nHost: h\r\n\r\npartial");
      expectBool(test, r.truncated, true);
      expectText(test, r.method, "POST");
      expectText(test, r.body, "partial");
      expectBool(test, r.headers.has("x-blimp-truncated"), false);
    }

    test("a request line with no headers") { test =>
      let r = httpParse("GET /robots.txt HTTP/1.1\r\n\r\n");
      expectText(test, r.method, "GET");
      expectText(test, r.path, "/robots.txt");
      expectInt(test, r.headers.keys().length, 0);
      expectText(test, r.body, "");
    }

    test("a request line with no blank line at all") { test =>
      let r = httpParse("GET /a?b=1 HTTP/1.1");
      expectText(test, r.method, "GET");
      expectText(test, at(r.query, "b"), "1");
    }

    test("an empty string is a BAD request") { test =>
      let r = httpParse("");
      expectText(test, r.method, "BAD");
      expectText(test, r.path, "/");
      expectBool(test, r.truncated, false);
    }

    test("malformed requests are BAD and never bubble") { test =>
      expectText(test, httpParse("hello").method, "BAD");
      expectText(test, httpParse("GET /\r\n\r\n").method, "BAD");
      expectText(test, httpParse("get / HTTP/1.1\r\n\r\n").method, "BAD");
      expectText(test, httpParse("GET noslash HTTP/1.1\r\n\r\n").method, "BAD");
      expectText(test, httpParse("GET / FTP/1.1\r\n\r\n").method, "BAD");
      expectText(test, httpParse("GET / HTTP/1.1\r\nno colon here\r\n\r\n").method, "BAD");
      expectText(test, httpParse("\r\n\r\n").method, "BAD");
    }

    test("a BAD request after the truncation marker keeps truncated") { test =>
      let r = httpParse("X-Blimp-Truncated: 1\r\nnonsense");
      expectText(test, r.method, "BAD");
      expectBool(test, r.truncated, true);
    }

    test("the path is percent-decoded and a plus in it stays a plus") { test =>
      let r = httpParse("GET /files/a%20b+c HTTP/1.1\r\n\r\n");
      expectText(test, r.path, "/files/a b+c");
    }

## Percent coding

    test("urlDecode") { test =>
      expectText(test, urlDecode("a+b%20c%2B"), "a b c+");
      expectText(test, urlDecode("plain"), "plain");
      expectText(test, urlDecode(""), "");
      expectText(test, urlDecode("%e2%82%ac"), "€");
    }

    test("urlDecode keeps a percent that is not followed by two hex digits") { test =>
      expectText(test, urlDecode("100%"), "100%");
      expectText(test, urlDecode("50%zz"), "50%zz");
      expectText(test, urlDecode("%4"), "%4");
      expectText(test, urlDecode("%41%"), "A%");
    }

    test("urlDecode turns bytes that are not UTF-8 into U+FFFD, one per byte") { test =>
      expectText(test, urlDecode("a%FFb"), "a\u{fffd}b");
      expectText(test, urlDecode("%C3"), "\u{fffd}");
      expectText(test, urlDecode("%C0%80"), "\u{fffd}\u{fffd}");
    }

    test("urlEncode keeps unreserved characters and encodes the rest") { test =>
      expectText(test, urlEncode("AZaz09-._~"), "AZaz09-._~");
      expectText(test, urlEncode("a b"), "a%20b");
      expectText(test, urlEncode("a+b&c=d/e?"), "a%2Bb%26c%3Dd%2Fe%3F");
      expectText(test, urlEncode(""), "");
    }

    test("urlEncode writes UTF-8 bytes in upper-case hex") { test =>
      expectText(test, urlEncode("é"), "%C3%A9");
      expectText(test, urlEncode("€"), "%E2%82%AC");
      expectText(test, urlEncode("🙂"), "%F0%9F%99%82");
    }

    test("urlEncode and urlDecode round trip") { test =>
      let s = "naïve — «text» & 🙂 100% +1";
      expectText(test, urlDecode(urlEncode(s)), s);
    }

    test("queryParse: flags, empty keys, and the last duplicate wins") { test =>
      let q = queryParse("a=1&flag&=skipped&a=2&b=x%3Dy&&c=");
      expectText(test, at(q, "a"), "2");
      expectText(test, at(q, "flag"), "");
      expectText(test, at(q, "b"), "x=y");
      expectText(test, at(q, "c"), "");
      expectInt(test, q.keys().length, 4);
      expectInt(test, queryParse("").keys().length, 0);
    }

## Responses

    test("a rendered response") { test =>
      let out = httpRender(httpText(200, "hello"));
      expectText(test, out, lines([
        "HTTP/1.1 200 OK",
        "Content-Type: text/plain; charset=utf-8",
        "Content-Length: 5",
        "Connection: close",
        "",
        "hello",
      ]));
    }

    test("Content-Length counts bytes, not characters") { test =>
      let out = httpRender(httpHtml(200, "é€🙂"));
      assert(out.split("Content-Length: 9\r\n").length == 2) { out };
      expectInt(test, utf8Length("aé€🙂"), 10);
      expectInt(test, utf8Length(""), 0);
    }

    test("the native byte count agrees with the code point count on valid text") { test =>
      let samples = ["", "plain", "é", "€", "🙂", "naïve — «text» 🙂 \r\n"];
      for (var k = 0; k < samples.length; ++k) {
        let sample = samples.getOr(k, "");
        expectInt(test, httpByteLength(sample), utf8Length(sample));
      }
    }

    test("status lines and reason phrases") { test =>
      expectText(test, httpRender(httpNotFound()).split("\r\n").getOr(0, ""), "HTTP/1.1 404 Not Found");
      expectText(test, httpRender(httpHtml(500, "")).split("\r\n").getOr(0, ""), "HTTP/1.1 500 Internal Server Error");
      expectText(test, httpRender(httpJson(413, "{}")).split("\r\n").getOr(0, ""), "HTTP/1.1 413 Payload Too Large");
    }

    test("a redirect is a 303 with a Location and an empty body") { test =>
      let out = httpRender(httpRedirect("/works/3"));
      expectText(test, out, lines([
        "HTTP/1.1 303 See Other",
        "Location: /works/3",
        "Content-Length: 0",
        "Connection: close",
        "",
        "",
      ]));
    }

    test("httpJson sets the JSON content type") { test =>
      let r = httpJson(201, "{\"ok\":true}");
      expectInt(test, r.status, 201);
      expectText(test, r.headers.getOr(0, new Pair("", "")).value, "application/json; charset=utf-8");
    }

    test("a session cookie") { test =>
      let out = httpRender(httpWithCookie(httpText(200, "x"), "_marginalia_key", "tok", null, true));
      assert(out.split("Set-Cookie: _marginalia_key=tok; Path=/; HttpOnly; SameSite=Lax\r\n").length == 2) { out };
    }

    test("a cookie with Max-Age and without HttpOnly") { test =>
      let out = httpRender(httpWithCookie(httpText(200, "x"), "remember", "yes", 1209600, false));
      assert(out.split("Set-Cookie: remember=yes; Path=/; SameSite=Lax; Max-Age=1209600\r\n").length == 2) { out };
    }

    test("clearing a cookie sends an empty value and Max-Age=0") { test =>
      let out = httpRender(httpClearCookie(httpRedirect("/"), "_marginalia_key"));
      assert(out.split("Set-Cookie: _marginalia_key=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0\r\n").length == 2) { out };
    }

    test("two cookies are two Set-Cookie headers") { test =>
      let r = httpWithCookie(httpWithCookie(httpText(200, ""), "a", "1", null, true), "b", "2", 5, true);
      expectText(test, httpRender(r).split("Set-Cookie: ").length.toString(), "3");
    }

    test("a caller's Content-Length or Connection header is replaced, not duplicated") { test =>
      let headers = new ListBuilder<Pair<String, String>>();
      headers.add(new Pair("content-length", "999"));
      headers.add(new Pair("Connection", "keep-alive"));
      headers.add(new Pair("X-Mine", "1"));
      let out = httpRender(new Response(200, headers.toList(), "abc"));
      expectText(test, out, lines([
        "HTTP/1.1 200 OK", "X-Mine: 1", "Content-Length: 3", "Connection: close", "", "abc",
      ]));
    }

## Static files

    test("paths that are not static answer nil") { test =>
      expectBool(test, httpStatic("/etc", "/") == null, true);
      expectBool(test, httpStatic("/etc", "/works/1") == null, true);
      expectBool(test, httpStatic("/etc", "/assetsx/a.css") == null, true);
      expectBool(test, httpStatic("/etc", "/robots.txt.bak") == null, true);
    }

    test("static paths with a missing file answer 404, not nil") { test =>
      let r = httpStatic("/nonexistent-root", "/assets/css/app.css");
      expectInt(test, statusOf(r), 404);
      expectInt(test, statusOf(httpStatic("/nonexistent-root", "/favicon.ico")), 404);
    }

    test("dot-dot and other unsafe paths are rejected with 404") { test =>
      expectInt(test, statusOf(httpStatic("/etc", "/assets/../etc/passwd")), 404);
      expectInt(test, statusOf(httpStatic("/etc", "/images/a/../../passwd")), 404);
      expectInt(test, statusOf(httpStatic("/etc", "/assets/")), 404);
      expectInt(test, statusOf(httpStatic("/etc", "/assets//hosts")), 404);
      expectInt(test, statusOf(httpStatic("/etc", "/assets/a\\b")), 404);
    }

    test("/assets/x maps to <root>/x and gets a year of caching") { test =>
      let found = httpStatic("/etc", "/assets/hosts");
      let r = if (found == null) { httpText(0, "") } else { found };
      expectInt(test, r.status, 200);
      assert(r.body != "") { "hosts file was empty" };
      let out = httpRender(r);
      assert(out.split("Cache-Control: public, max-age=31536000\r\n").length == 2) { out };
      assert(out.split("Content-Type: application/octet-stream\r\n").length == 2) { out };
    }

    test("/images/x maps to <root>/images/x") { test =>
      expectInt(test, statusOf(httpStatic("/nonexistent-root", "/images/logo.png")), 404);
      expectText(test, staticFileFor("/r", "/images/logo.png"), "/r/images/logo.png");
      expectText(test, staticFileFor("/r", "/assets/css/app.css"), "/r/css/app.css");
      expectText(test, staticFileFor("/r", "/assets/js/app.js"), "/r/js/app.js");
      expectText(test, staticFileFor("/r", "/favicon.ico"), "/r/favicon.ico");
      expectText(test, staticFileFor("/r", "/robots.txt"), "/r/robots.txt");
    }

    test("content types by extension") { test =>
      expectText(test, contentTypeOf("css/app.css"), "text/css; charset=utf-8");
      expectText(test, contentTypeOf("js/app.js"), "text/javascript; charset=utf-8");
      expectText(test, contentTypeOf("a.png"), "image/png");
      expectText(test, contentTypeOf("a.SVG"), "image/svg+xml");
      expectText(test, contentTypeOf("favicon.ico"), "image/x-icon");
      expectText(test, contentTypeOf("robots.txt"), "text/plain; charset=utf-8");
      expectText(test, contentTypeOf("a.html"), "text/html; charset=utf-8");
      expectText(test, contentTypeOf("a.json"), "application/json; charset=utf-8");
      expectText(test, contentTypeOf("f.woff2"), "font/woff2");
      expectText(test, contentTypeOf("noext"), "application/octet-stream");
    }

## Router

The caller lists `/stacks/new` before `/stacks/:id`; the first match wins.

    let routes(): List<Route> {
      [
        new Route("GET", "/", "home"),
        new Route("GET", "/stacks/new", "stackNew"),
        new Route("GET", "/stacks/:id", "stackShow"),
        new Route("POST", "/stacks/:id", "stackUpdate"),
        new Route("GET", "/works/:id/graph.json", "graph"),
        new Route("GET", "/works/:work/notes/:note", "note"),
      ]
    }

    let routeName(test: Test, method: String, path: String, want: String): Void {
      let m = routeMatch(routes(), method, path);
      expectText(test, if (m == null) { "nil" } else { m.route.name }, want);
    }

    test("a literal route and a route with a parameter") { test =>
      routeName(test, "GET", "/", "home");
      routeName(test, "GET", "/stacks/7", "stackShow");
      let m = routeMatch(routes(), "GET", "/stacks/7");
      expectText(test, if (m == null) { "nil" } else { at(m.params, "id") }, "7");
    }

    test("the first match wins, so /stacks/new before /stacks/:id") { test =>
      routeName(test, "GET", "/stacks/new", "stackNew");
      let swapped = [
        new Route("GET", "/stacks/:id", "stackShow"),
        new Route("GET", "/stacks/new", "stackNew"),
      ];
      let m = routeMatch(swapped, "GET", "/stacks/new");
      expectText(test, if (m == null) { "nil" } else { m.route.name }, "stackShow");
    }

    test("method is part of the match") { test =>
      routeName(test, "POST", "/stacks/7", "stackUpdate");
      routeName(test, "DELETE", "/stacks/7", "nil");
      routeName(test, "POST", "/", "nil");
    }

    test("parameters in the middle of a pattern, two of them") { test =>
      let m = routeMatch(routes(), "GET", "/works/4/notes/9");
      expectText(test, if (m == null) { "nil" } else { m.route.name }, "note");
      expectText(test, if (m == null) { "nil" } else { at(m.params, "work") }, "4");
      expectText(test, if (m == null) { "nil" } else { at(m.params, "note") }, "9");
      let g = routeMatch(routes(), "GET", "/works/4/graph.json");
      expectText(test, if (g == null) { "nil" } else { at(g.params, "id") }, "4");
    }

    test("a trailing slash is not significant, and the root is the root") { test =>
      routeName(test, "GET", "/stacks/7/", "stackShow");
      routeName(test, "GET", "/stacks/new/", "stackNew");
      routeName(test, "GET", "", "home");
    }

    test("no match: wrong length, wrong literal, empty parameter") { test =>
      routeName(test, "GET", "/stacks", "nil");
      routeName(test, "GET", "/stacks/7/extra", "nil");
      routeName(test, "GET", "/works/4/graph.csv", "nil");
      routeName(test, "GET", "/stacks//", "nil");
      expectBool(test, routeMatch(new ListBuilder<Route>().toList(), "GET", "/") == null, true);
    }
