# http: responses, cookies, static files

The library has five files. `text.temper.md` holds the string tools Temper
lacks, `url.temper.md` percent coding and query strings, `request.temper.md`
the parser, `router.temper.md` the router, and this file the response side.

## Deviations

From PLAN section 5.4: none in names or signatures. Behaviour the plan left
open:

* `Request.param(name)` looks in `form` first, then `query`.
* `urlDecode` treats `+` as a space (form rules). The request path is decoded
  with `+` left alone.
* `httpStatic` returns a 404 `Response` (not nil) for a static-looking path
  whose file is missing or whose path contains `..`; nil is only for paths that
  are not static. Static files are read with the local `httpReadFile`
  (`_connected.blimp`), a stand-in for `sysReadFile`; TODO switch to `sys`.
* An unknown status code is rendered with the reason phrase `Status`.
* `Content-Length` is the native byte count (`httpByteLength`, over Blimp's
  `length`), not the pure-Temper count from code points that the brief asked
  for. Measured: a 14-byte file with invalid UTF-8 in it (a PNG header, say)
  counts as 22 by code points, so a binary static file would be sent with the
  wrong length. `utf8Length` stays, and a test checks the two agree on valid
  text. TODO: `sysByteLength`.
* `httpWithCookie` writes the value as given. The caller encodes it.

## Responses

    export class Response(
      public status: Int,
      public headers: List<Pair<String, String>>,
      public body: String,
    ) {}

    let respond(status: Int, contentType: String, body: String): Response {
      let headers = new ListBuilder<Pair<String, String>>();
      headers.add(new Pair("Content-Type", contentType));
      new Response(status, headers.toList(), body)
    }

    export let httpHtml(status: Int, body: String): Response {
      respond(status, "text/html; charset=utf-8", body)
    }

    export let httpJson(status: Int, body: String): Response {
      respond(status, "application/json; charset=utf-8", body)
    }

    export let httpText(status: Int, body: String): Response {
      respond(status, "text/plain; charset=utf-8", body)
    }

A 303, so a POST redirects to a GET.

    export let httpRedirect(to: String): Response {
      let headers = new ListBuilder<Pair<String, String>>();
      headers.add(new Pair("Location", to));
      new Response(303, headers.toList(), "")
    }

    export let httpNotFound(): Response {
      httpText(404, "Not Found")
    }

## Cookies

`name=value; Path=/; HttpOnly; SameSite=Lax`, with `; Max-Age=n` when an age
is given. Clearing is an empty value and `Max-Age=0`.

    let withHeader(r: Response, name: String, value: String): Response {
      let headers = new ListBuilder<Pair<String, String>>();
      for (var k = 0; k < r.headers.length; ++k) {
        headers.add(r.headers.getOr(k, new Pair("", "")));
      }
      headers.add(new Pair(name, value));
      new Response(r.status, headers.toList(), r.body)
    }

    export let httpWithCookie(
      r: Response, name: String, value: String, maxAgeSeconds: Int?, httpOnly: Boolean,
    ): Response {
      let flags = new ListBuilder<String>();
      flags.add("${name}=${value}");
      flags.add("Path=/");
      if (httpOnly) { flags.add("HttpOnly"); }
      flags.add("SameSite=Lax");
      if (maxAgeSeconds != null) { flags.add("Max-Age=${maxAgeSeconds.toString()}"); }
      withHeader(r, "Set-Cookie", flags.toList().join("; ") { (x: String): String => x })
    }

    export let httpClearCookie(r: Response, name: String): Response {
      httpWithCookie(r, name, "", 0, true)
    }

## Rendering

The status line, the headers as given (any `Content-Length` or `Connection` of
the caller's is dropped), then `Content-Length` in bytes, `Connection: close`,
a blank line and the body.

    let reasonOf(status: Int): String {
      if (status == 200) { "OK" } else if (status == 201) { "Created" } else if (status == 202) { "Accepted" } else if (status == 204) { "No Content" } else if (status == 301) { "Moved Permanently" } else if (status == 302) { "Found" } else if (status == 303) { "See Other" } else if (status == 304) { "Not Modified" } else if (status == 307) { "Temporary Redirect" } else if (status == 400) { "Bad Request" } else if (status == 401) { "Unauthorized" } else if (status == 403) { "Forbidden" } else if (status == 404) { "Not Found" } else if (status == 405) { "Method Not Allowed" } else if (status == 409) { "Conflict" } else if (status == 413) { "Payload Too Large" } else if (status == 422) { "Unprocessable Entity" } else if (status == 429) { "Too Many Requests" } else if (status == 500) { "Internal Server Error" } else if (status == 502) { "Bad Gateway" } else if (status == 503) { "Service Unavailable" } else { "Status" }
    }

    @connected
    let httpByteLength(s: String): Int;

    export let httpRender(r: Response): String {
      let lines = new ListBuilder<String>();
      lines.add("HTTP/1.1 ${r.status.toString()} ${reasonOf(r.status)}");
      for (var k = 0; k < r.headers.length; ++k) {
        let h = r.headers.getOr(k, new Pair("", ""));
        let lower = lowerAscii(h.key);
        if (lower != "content-length" && lower != "connection" && lower != "") {
          lines.add("${h.key}: ${h.value}");
        }
      }
      lines.add("Content-Length: ${httpByteLength(r.body).toString()}");
      lines.add("Connection: close");
      lines.add("");
      lines.add(r.body);
      lines.toList().join("\r\n") { (x: String): String => x }
    }

## Static files

The native part is one function. TODO: replace with `sysReadFile` from the
`sys` library and delete `_connected.blimp`.

    @connected
    export let httpReadFile(path: String): String?;

    let contentTypeOf(name: String): String {
      let dots = name.split(".");
      let ext = if (dots.length < 2) { "" } else { lowerAscii(dots.getOr(dots.length - 1, "")) };
      if (ext == "css") { "text/css; charset=utf-8" } else if (ext == "js") { "text/javascript; charset=utf-8" } else if (ext == "png") { "image/png" } else if (ext == "svg") { "image/svg+xml" } else if (ext == "ico") { "image/x-icon" } else if (ext == "txt") { "text/plain; charset=utf-8" } else if (ext == "html") { "text/html; charset=utf-8" } else if (ext == "json") { "application/json; charset=utf-8" } else if (ext == "woff2") { "font/woff2" } else { "application/octet-stream" }
    }

A relative path is safe if it is not empty and no segment is empty, `.` or
`..`, and it has no backslash.

    let safeRelative(rel: String): Boolean {
      if (rel == "") { return false; }
      if (rel.split("\\").length > 1) { return false; }
      let segments = rel.split("/");
      for (var k = 0; k < segments.length; ++k) {
        let seg = segments.getOr(k, "");
        if (seg == "" || seg == "." || seg == "..") { return false; }
      }
      true
    }

`/assets/css/app.css` is `<root>/css/app.css`, `/images/x.png` is
`<root>/images/x.png`, `/favicon.ico` and `/robots.txt` are `<root>/` those.
`root` has no trailing slash. Only `/assets/` files get the year-long
`Cache-Control`; the others get a day.

    let isStaticPath(path: String): Boolean {
      startsWith(path, "/assets/") || startsWith(path, "/images/") ||
        path == "/favicon.ico" || path == "/robots.txt"
    }

The part of the path below its prefix, which must be safe.

    let staticRel(path: String): String {
      if (startsWith(path, "/assets/")) { splitOnce(path, "/assets/").tail } else if (startsWith(path, "/images/")) { splitOnce(path, "/images/").tail } else if (path == "/favicon.ico") { "favicon.ico" } else if (path == "/robots.txt") { "robots.txt" } else { "" }
    }

The file on disk, or "" when the path is not static or is unsafe.

    let staticFileFor(root: String, path: String): String {
      let rel = staticRel(path);
      if (!isStaticPath(path) || !safeRelative(rel)) {
        ""
      } else if (startsWith(path, "/images/")) {
        "${root}/images/${rel}"
      } else {
        "${root}/${rel}"
      }
    }

    export let httpStatic(root: String, path: String): Response? {
      if (!isStaticPath(path)) { return null; }
      let file = staticFileFor(root, path);
      if (file == "") { return httpNotFound(); }
      let content = httpReadFile(file);
      if (content != null) {
        let headers = new ListBuilder<Pair<String, String>>();
        headers.add(new Pair("Content-Type", contentTypeOf(staticRel(path))));
        headers.add(new Pair(
          "Cache-Control",
          if (startsWith(path, "/assets/")) { "public, max-age=31536000" } else { "public, max-age=86400" },
        ));
        new Response(200, headers.toList(), content)
      } else {
        httpNotFound()
      }
    }
