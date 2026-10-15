# The HTTP seam

Every function in this library that fetches takes an `ImporterHttp`. The
Elixir had the same seam in `config :marginalia, :github_api` (`FakeHub` in
the tests); here it is an interface with a real implementation over the
interpreter's HTTPS client and a fake that answers canned responses.

    let { sysHttpStart, sysHttpAwait, sysSleepMs } = import("sys/src");

## What a GET answers

`failure` is set when nothing came back at all (DNS, TLS, timeout): the
transport error, as text. Otherwise `status` and `body` are the response.
`headers` are `Name: value` strings; the real transport cannot fill them in
(the interpreter hands back a status and a body, nothing else), so code that
reads a header must have a plan for an empty list.

    export class ImporterHttpResult(
      public status: Int,
      public body: String,
      public headers: List<String>,
      public failure: String?,
    ) {}

    export let importerHttpOk(status: Int, body: String, headers: List<String>): ImporterHttpResult {
      new ImporterHttpResult(status, body, headers, null)
    }

    export let importerHttpFailed(reason: String): ImporterHttpResult {
      new ImporterHttpResult(0, "", [], reason)
    }

`headers` on the way out are `Name: value` strings too. `sent` and `sentHeaders`
are what a fake remembers being asked (the real one remembers nothing).

    export interface ImporterHttp {
      public get(url: String, headers: List<String>): ImporterHttpResult;
      public sent(): List<String>;
      public sentHeaders(): List<String>;
    }

## Reading a header

Case-insensitive on the name; the first one wins; null when absent.

    export let importerHeader(headers: List<String>, wanted: String): String? {
      let want = importerLower(wanted);
      var i = 0;
      while (i < headers.length) {
        let parts = importerSplitOnce(headers[i], ":");
        if (parts.length == 2) {
          if (importerLower(importerTrim(parts[0])) == want) {
            return importerTrim(parts[1]);
          }
        }
        i += 1;
      }
      null
    }

## The real one

`retries` extra attempts on a transport failure or a 408, 429, 500, 502, 503
or 504, a second apart (Req's `:safe_transient` retry, with a fixed backoff
because the interpreter shows no `Retry-After`). The interpreter's client
follows redirects on its own account; whether it re-checks them is not
something this library can see.

    export class ImporterRealHttp(public timeoutMs: Int, public retries: Int) extends ImporterHttp {
      public get(url: String, headers: List<String>): ImporterHttpResult {
        var attempt = 0;
        var last = importerHttpFailed("not tried");
        var done = false;
        while (!done) {
          last = importerRealOnce(url, headers, timeoutMs);
          let transient = last.failure != null || importerTransient(last.status);
          if (transient && attempt < retries) {
            attempt += 1;
            sysSleepMs(1000 * attempt);
          } else {
            done = true;
          }
        }
        last
      }
      public sent(): List<String> { [] }
      public sentHeaders(): List<String> { [] }
    }

    let importerTransient(status: Int): Boolean {
      status == 408 || status == 429 || status == 500 || status == 502 || status == 503 || status == 504
    }

    let importerRealOnce(url: String, headers: List<String>, timeoutMs: Int): ImporterHttpResult {
      let answer: List<String> = do {
        sysHttpAwait(sysHttpStart("GET", url, headers, "", timeoutMs))
      } orelse ["error", "the request could not be started"];
      if (answer.length >= 3 && answer[0] == "ok") {
        let status = importerParseInt(answer[1]);
        if (status != null) {
          importerHttpOk(status, answer[2], [])
        } else {
          importerHttpFailed("unreadable status ${answer[1]}")
        }
      } else if (answer.length >= 2) {
        importerHttpFailed(answer[1])
      } else {
        importerHttpFailed("empty answer")
      }
    }

    export let importerRealHttp(retries: Int): ImporterHttp {
      new ImporterRealHttp(20000, retries)
    }

## The fake

`FakeHub`, generalised: a list of canned `(url pattern, status, body)`. A
request is answered by the first route whose pattern its URL contains. A URL
nothing matches is a transport failure that names the URL, so a test that makes
a request it did not arrange fails by name. A negative status is a transport
failure with the body as the reason.

    export class ImporterFakeRoute(public pattern: String, public status: Int, public body: String) {
      public var headers: List<String> = [];
    }

    export let importerRoute(pattern: String, status: Int, body: String): ImporterFakeRoute {
      new ImporterFakeRoute(pattern, status, body)
    }

    export let importerRouteWith(
      pattern: String, status: Int, body: String, headers: List<String>,
    ): ImporterFakeRoute {
      let r = new ImporterFakeRoute(pattern, status, body);
      r.headers = headers;
      r
    }

    export let importerRouteFail(pattern: String, reason: String): ImporterFakeRoute {
      new ImporterFakeRoute(pattern, -1, reason)
    }

    export class ImporterFakeHttp(private routes: List<ImporterFakeRoute>) extends ImporterHttp {
      private urls: ListBuilder<String> = new ListBuilder<String>();
      private heads: ListBuilder<String> = new ListBuilder<String>();
      public get(url: String, headers: List<String>): ImporterHttpResult {
        urls.add(url);
        heads.add(importerJoin(headers, "\n"));
        var i = 0;
        while (i < routes.length) {
          let r = routes[i];
          if (importerContains(url, r.pattern)) {
            if (r.status < 0) { return importerHttpFailed(r.body); }
            return importerHttpOk(r.status, r.body, r.headers);
          }
          i += 1;
        }
        importerHttpFailed("no canned response for ${url}")
      }
      public sent(): List<String> { urls.toList() }
      public sentHeaders(): List<String> { heads.toList() }
    }

    export let importerFake(routes: List<ImporterFakeRoute>): ImporterHttp {
      new ImporterFakeHttp(routes)
    }
