# server: accept, fork, answer, exit

The parent process only accepts and forks, so it stays the size it started
(about 2.5 MB after a thousand requests, notes/blimp-native.md section 4).
The interpreter frees nothing until exit; the child that served a request
takes its garbage with it.

Three details that cost an hour each. The parent closes its copy of the
client socket with `sysCloseFd`, a plain `close(2)`: `sysClose` shuts the
socket down for both processes and the child's response never leaves. The
parent reaps finished children at the top of every turn, or they stay
zombies. The child closes the listener, or a restart cannot bind while a
slow child lives.

    let { Request, Response, httpParse, httpRender, httpStatic, httpHtml, httpText } = import("http/src");
    let {
      sysListen, sysAccept, sysReadRequest, sysWrite, sysClose, sysCloseFd,
      sysFork, sysExit, sysReapChildren, sysGetEnv, sysAppendFile, sysUtcNow,
      sysMonoMs, sysFileSize, sysExec,
    } = import("sys/src");

    let maxRequestBytes = 16 * 1024 * 1024;

## Configuration

    export let portFromEnv(): Int {
      let raw = sysGetEnv("PORT");
      if (raw != null) {
        raw.toInt32() orelse 4000
      } else {
        4000
      }
    }

    let logDir(): String {
      let raw = sysGetEnv("LOG_DIR");
      if (raw != null) { raw } else { "log" }
    }

`STATIC_ROOT`, default `static`. When it is unset and `static/` is not under
the working directory, `blimp/static` is tried, which is where it is when the
server is started from the repository root (the end-to-end script does that).

    let staticRoot(): String {
      let raw = sysGetEnv("STATIC_ROOT");
      if (raw != null) {
        raw
      } else if (sysFileSize("static/robots.txt") >= 0) {
        "static"
      } else {
        "blimp/static"
      }
    }

## The default handler

Stands in until `web` exists, and serves the smoke test's routes after that.

    let page(title: String, inner: String): String {
      "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>${title}</title><link rel=\"stylesheet\" href=\"/assets/css/app.css\"></head><body><main id=\"main\">${inner}</main></body></html>"
    }

    export let serverNotFound(): Response {
      httpHtml(404, page("Not Found", "<h1>Not Found</h1>"))
    }

    export let serverDefaultHandler(req: Request): Response {
      let asset = httpStatic(staticRoot(), req.path);
      if (asset != null) {
        asset
      } else if (req.path == "/") {
        httpHtml(200, page("Marginalia", "<h1>Marginalia</h1>"))
      } else if (req.path == "/healthz") {
        httpText(200, "ok")
      } else if (req.path == "/sitemap.xml") {
        new Response(200, [new Pair("Content-Type", "application/xml; charset=utf-8")], "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\"></urlset>")
      } else if (req.path == "/users/log-in") {
        httpHtml(200, page("Log in", "<h1>Log in</h1><form id=\"login_form_password\" method=\"post\" action=\"/users/log-in\"><input type=\"email\" name=\"user[email]\"><input type=\"password\" name=\"user[password]\"><button type=\"submit\">Log in</button></form>"))
      } else if (req.path == "/works") {
        httpHtml(200, page("Works", "<h1>Your drafts</h1>"))
      } else {
        serverNotFound()
      }
    }

## One request

`serverRespond` is the whole of a request after parsing, separated from the
socket so a test can drive it. A bubble escaping the handler becomes a 500
page and a line in `error.log`; the Temper bubble carries no text, so the
line says `Bubble`. A request the parser refused is a 400, and a body over
the cap is a 413.

    let logError(req: Request, what: String): Void {
      sysExec(["mkdir", "-p", logDir()], "", null);
      let line = "${sysUtcNow()} ${req.method} ${req.path} ${what}\n";
      sysAppendFile("${logDir()}/error.log", line);
    }

    export let serverRespond(handler: fn (Request): Response throws Bubble, req: Request): Response {
      if (req.method == "BAD") {
        httpText(400, "Bad Request")
      } else if (req.truncated) {
        httpText(413, "Payload Too Large")
      } else {
        handler(req) orelse do {
          logError(req, "Bubble");
          httpHtml(500, page("Something went wrong", "<h1>Something went wrong</h1>"))
        }
      }
    }

## The loop

`quitFile`, when not null, is checked after every accept: if the file exists
the parent exits once the child it just forked has the connection. A test
uses it to stop a server it cannot signal. `serve` enables it only when
`MARGINALIA_ALLOW_QUIT=1`.

    let serveChild(client: Int, handler: fn (Request): Response throws Bubble): Void {
      let started = sysMonoMs();
      let raw = sysReadRequest(client, maxRequestBytes);
      if (raw == null) {
        sysClose(client);
        sysExit(0);
      } else {
        let req = httpParse(raw);
        let resp = serverRespond(handler, req);
        sysWrite(client, httpRender(resp));
        sysClose(client);
        let ms = sysMonoMs() - started;
        console.log("${sysUtcNow()} ${req.method} ${req.path} ${resp.status.toString()} ${ms.toString()}");
        sysExit(0);
      }
    }

    export let serveWith(port: Int, handler: fn (Request): Response throws Bubble, quitFile: String?): Void {
      var listener = -1;
      do {
        listener = sysListen(port);
      } orelse do {
        console.log("marginalia: cannot listen on port ${port.toString()}");
        sysExit(1);
      }
      console.log("marginalia on http://localhost:${port.toString()}");
      while (true) {
        sysReapChildren();
        let client = sysAccept(listener);
        let pid = sysFork();
        if (pid == 0) {
          sysCloseFd(listener);
          serveChild(client, handler);
          sysExit(0);
        } else {
          sysCloseFd(client);
          if (quitFile != null) {
            if (sysFileSize(quitFile) >= 0) { sysExit(0); }
          }
        }
      }
    }

    export let serve(port: Int, handler: fn (Request): Response throws Bubble): Void {
      let allow = sysGetEnv("MARGINALIA_ALLOW_QUIT");
      if (allow == "1") {
        serveWith(port, handler, "${logDir()}/quit")
      } else {
        serveWith(port, handler, null)
      }
    }
