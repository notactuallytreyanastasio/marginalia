# Parsing a request

`httpParse` is given the whole raw request, as `sysReadRequest` returns it:
the head, a blank line, and the body. Reading more from the socket until
`Content-Length` bytes have arrived is the socket layer's job, not this one's.
A body that arrives in pieces is not handled here, and a request cut short is
parsed as far as it goes.

    export class UploadedFile(
      public field: String,
      public filename: String,
      public contentType: String,
      public content: String,
    ) {}

    export class Request(
      public method: String,
      public path: String,
      public query: Map<String, String>,
      public headers: Map<String, String>,
      public cookies: Map<String, String>,
      public body: String,
      public form: Map<String, String>,
      public files: List<UploadedFile>,
      public truncated: Boolean,
    ) {

The header with this name (any case), or null.

      public header(name: String): String? {
        let key = lowerAscii(name);
        if (headers.has(key)) { headers.getOr(key, "") } else { null }
      }

A form field if there is one, else a query parameter, else null.

      public param(name: String): String? {
        if (form.has(name)) { form.getOr(name, "") } else if (query.has(name)) { query.getOr(name, "") } else { null }
      }
    }

A request that cannot be parsed. The server answers it with a 400.

    let emptyMap(): Map<String, String> {
      new MapBuilder<String, String>().toMap()
    }

    let badRequest(truncated: Boolean): Request {
      new Request(
        "BAD", "/", emptyMap(), emptyMap(), emptyMap(), "", emptyMap(),
        new ListBuilder<UploadedFile>().toList(), truncated,
      )
    }

    let isMethodToken(m: String): Boolean {
      if (m == "") { return false; }
      var i = String.begin;
      while (m.hasIndex(i)) {
        let cp = m[i];
        if (cp < 65 || cp > 90) { return false; }
        i = m.next(i);
      }
      true
    }

## Cookies

`a=1; b=2`. Values are kept as sent; the first of a repeated name is
overwritten by the last. A pair with no `=` or an empty name is dropped.

    let cookiesParse(header: String): Map<String, String> {
      let out = new MapBuilder<String, String>();
      let pairs = header.split(";");
      for (var k = 0; k < pairs.length; ++k) {
        let kv = splitOnce(trimWs(pairs.getOr(k, "")), "=");
        let name = trimWs(kv.head);
        if (kv.found && name != "") { out.set(name, trimWs(kv.tail)); }
      }
      out.toMap()
    }

## Multipart

A part's `Content-Disposition` carries `name="..."` and maybe
`filename="..."`. The search is for `; name="` so that `filename="` is not
mistaken for it.

    let dispositionParam(disposition: String, key: String): String? {
      let pieces = disposition.split("; ${key}=\"");
      if (pieces.length < 2) { return null; }
      pieces.getOr(1, "").split("\"").getOr(0, "")
    }

The body is split on CRLF + `--boundary`, so the first boundary (which has no
CRLF before it) is found by putting one in front. What comes before the first
boundary is a preamble and is ignored; a part starting `--` is the closing
boundary and ends the body; every other part is CRLF, headers, a blank line,
the content. Content is exactly the bytes between the blank line and the next
CRLF + `--boundary`. A file part with an empty filename (a file input left
empty) is skipped.

    class Multipart(public fields: Map<String, String>, public files: List<UploadedFile>) {}

    let multipartParse(body: String, boundary: String): Multipart {
      let fields = new MapBuilder<String, String>();
      let files = new ListBuilder<UploadedFile>();
      let parts = "\r\n${body}".split("\r\n--${boundary}");
      for (var k = 1; k < parts.length; ++k) {
        let part = parts.getOr(k, "");
        if (startsWith(part, "--")) { break; }
        if (!startsWith(part, "\r\n")) { continue; }
        let halves = splitOnce(part.slice(part.next(part.next(String.begin)), part.end), "\r\n\r\n");
        if (!halves.found) { continue; }
        var disposition = "";
        var partType = "application/octet-stream";
        let lines = halves.head.split("\r\n");
        for (var j = 0; j < lines.length; ++j) {
          let line = splitOnce(lines.getOr(j, ""), ":");
          let name = lowerAscii(trimWs(line.head));
          if (name == "content-disposition") { disposition = trimWs(line.tail); } else if (name == "content-type") { partType = trimWs(line.tail); }
        }
        let field = dispositionParam("; ${disposition}", "name");
        let filename = dispositionParam("; ${disposition}", "filename");
        if (field != null) {
          if (filename == null) {
            fields.set(field, halves.tail);
          } else if (filename != "") {
            files.add(new UploadedFile(field, filename, partType, halves.tail));
          }
        }
      }
      new Multipart(fields.toMap(), files.toList())
    }

    let boundaryOf(contentType: String): String? {
      let pieces = contentType.split("boundary=");
      if (pieces.length < 2) { return null; }
      let raw = trimWs(pieces.getOr(1, "").split(";").getOr(0, ""));
      let unquoted = raw.split("\"").join("") { (x: String): String => x };
      if (unquoted == "") { null } else { unquoted }
    }

## The parse

Splits at the first blank line. Anything not shaped like a request is a
bubble, caught in `httpParse` and turned into method `BAD`.

    let parseRequest(rawIn: String, truncated: Boolean): Request throws Bubble {
      let raw = rawIn;
      let halves = splitOnce(raw, "\r\n\r\n");
      let lines = halves.head.split("\r\n");
      let first = lines.getOr(0, "").split(" ");
      if (first.length != 3) { bubble(); }
      let method = first.getOr(0, "");
      let target = first.getOr(1, "");
      if (!isMethodToken(method) || !startsWith(target, "/") || !startsWith(first.getOr(2, ""), "HTTP/")) {
        bubble();
      }
      let beforeFragment = splitOnce(target, "#").head;
      let pq = splitOnce(beforeFragment, "?");
      let path = decodeWith(pq.head, false);
      let query = queryParse(pq.tail);

      let headers = new MapBuilder<String, String>();
      for (var k = 1; k < lines.length; ++k) {
        let line = lines.getOr(k, "");
        if (line != "") {
          let kv = splitOnce(line, ":");
          let name = lowerAscii(trimWs(kv.head));
          if (!kv.found || name == "") { bubble(); }
          let value = trimWs(kv.tail);
          if (name == "cookie" && headers.has("cookie")) {
            headers.set(name, "${headers.getOr("cookie", "")}; ${value}");
          } else {
            headers.set(name, value);
          }
        }
      }
      let headerMap = headers.toMap();
      let cookies = cookiesParse(headerMap.getOr("cookie", ""));
      let body = halves.tail;
      let contentType = headerMap.getOr("content-type", "");
      let lowerType = lowerAscii(contentType);
      var form = emptyMap();
      var files = new ListBuilder<UploadedFile>().toList();
      if (startsWith(lowerType, "application/x-www-form-urlencoded")) {
        form = queryParse(body);
      } else if (startsWith(lowerType, "multipart/form-data")) {
        let boundary = boundaryOf(contentType);
        if (boundary == null) {
          bubble();
        } else {
          let parsed = multipartParse(body, boundary);
          form = parsed.fields;
          files = parsed.files;
        }
      }
      new Request(method, path, query, headerMap, cookies, body, form, files, truncated)
    }

The socket layer prepends `X-Blimp-Truncated: 1` when the body went over the
cap. It is stripped here, so it never appears in `headers`, and sets
`truncated`.

    export let httpParse(raw: String): Request {
      let marker = "X-Blimp-Truncated: 1\r\n";
      if (startsWith(raw, marker)) {
        let rest = splitOnce(raw, marker).tail;
        parseRequest(rest, true) orelse badRequest(true)
      } else {
        parseRequest(raw, false) orelse badRequest(false)
      }
    }
