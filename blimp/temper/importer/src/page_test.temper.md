# Tests for fetching a page

`test/marginalia/import_test.exs`: what gets refused, and what survives the
trip from HTML to markdown. The page comes from a fake `ImporterHttp` instead of
the `body:` option; the Elixir's `allowed/1` tests that resolved real public
hostnames need no network here, because nothing is resolved.

    let { markdownToHtml } = import("html/src");
    let { sysJoin } = import("sys/src");

    let allowedKind(url: String?): String {
      let r = importerAllowed(url);
      let e = r.error;
      if (e != null) { e.kind } else { "ok" }
    }

## What may be fetched

    test("plain http and https to a public host") { test =>
      expectText(test, allowedKind("https://darioamodei.com/post/we-must-pace-the-frontier"), "ok");
      expectText(test, allowedKind("http://example.com/essay"), "ok");
    }

    test("nothing that is not http") { test =>
      let urls = [
        "file:///etc/passwd", "ftp://example.com/x", "gopher://example.com",
        "javascript:alert(1)", "data:text/html,hi",
      ];
      var i = 0;
      while (i < urls.length) {
        expectText(test, allowedKind(urls[i]), "bad_scheme");
        i += 1;
      }
    }

    test("nothing on this machine or this network") { test =>
      let urls = [
        "http://localhost:4000/admin", "http://127.0.0.1/", "http://0.0.0.0/", "http://10.0.0.5/",
        "http://192.168.1.1/", "http://172.16.4.4/", "http://169.254.169.254/latest/meta-data/",
        "http://[::1]/", "http://something.local/", "http://box.internal/",
      ];
      var i = 0;
      while (i < urls.length) {
        expectText(test, allowedKind(urls[i]), "private_address");
        i += 1;
      }
    }

    test("a hostname that is only another name for loopback is still refused") { test =>
      expectText(test, allowedKind("http://localhost.localdomain/"), "private_address");
      expectText(test, allowedKind("http://LOCALHOST/"), "private_address");
      expectText(test, allowedKind("http://localhost./"), "private_address");
      expectText(test, allowedKind("http://api.localhost/"), "private_address");
      expectText(test, allowedKind("http://printer.lan/"), "private_address");
      expectText(test, allowedKind("http://ip6-localhost/"), "private_address");
    }

    test("rubbish is refused rather than crashing") { test =>
      expectTrue(test, allowedKind("not a url") != "ok", "not a url");
      expectTrue(test, allowedKind("https://") != "ok", "no host");
      expectText(test, allowedKind(null), "bad_url");
      expectText(test, allowedKind("https://"), "no_host");
      expectText(test, allowedKind("http:///path"), "no_host");
      expectText(test, allowedKind(""), "bad_scheme");
      expectText(test, allowedKind("//example.com/x"), "bad_scheme");
    }

    test("every reserved IPv4 range, and the edges of each") { test =>
      expectText(test, allowedKind("http://100.64.0.1/"), "private_address");
      expectText(test, allowedKind("http://100.127.255.255/"), "private_address");
      expectText(test, allowedKind("http://100.63.255.255/"), "ok");
      expectText(test, allowedKind("http://100.128.0.1/"), "ok");
      expectText(test, allowedKind("http://172.15.255.255/"), "ok");
      expectText(test, allowedKind("http://172.16.0.0/"), "private_address");
      expectText(test, allowedKind("http://172.31.255.255/"), "private_address");
      expectText(test, allowedKind("http://172.32.0.1/"), "ok");
      expectText(test, allowedKind("http://192.167.1.1/"), "ok");
      expectText(test, allowedKind("http://169.253.1.1/"), "ok");
      expectText(test, allowedKind("http://0.1.2.3/"), "private_address");
      expectText(test, allowedKind("http://224.0.0.1/"), "private_address");
      expectText(test, allowedKind("http://255.255.255.255/"), "private_address");
      expectText(test, allowedKind("http://223.255.255.255/"), "ok");
      expectText(test, allowedKind("http://8.8.8.8/"), "ok");
      expectText(test, allowedKind("http://93.184.216.34:8080/x"), "ok");
    }

    test("IPv6: loopback, link-local and unique-local, and the ways in the Elixir missed") { test =>
      expectText(test, allowedKind("http://[::1]/"), "private_address");
      expectText(test, allowedKind("http://[fe80::1]/"), "private_address");
      expectText(test, allowedKind("http://[febf::1]/"), "private_address");
      expectText(test, allowedKind("http://[fec0::1]/"), "ok");
      expectText(test, allowedKind("http://[fc00::1]/"), "private_address");
      expectText(test, allowedKind("http://[fd12:3456::1]/"), "private_address");
      expectText(test, allowedKind("http://[2001:db8::1]/"), "ok");
      expectText(test, allowedKind("http://[2606:4700:4700::1111]/"), "ok");
      expectText(test, allowedKind("http://[::]/"), "private_address");
      expectText(test, allowedKind("http://[::ffff:127.0.0.1]/"), "private_address");
      expectText(test, allowedKind("http://[::ffff:7f00:1]/"), "private_address");
      expectText(test, allowedKind("http://[::ffff:8.8.8.8]/"), "ok");
      expectText(test, allowedKind("http://[::127.0.0.1]/"), "private_address");
      expectText(test, allowedKind("http://[64:ff9b::7f00:1]/"), "private_address");
      expectText(test, allowedKind("http://[2002:7f00:1::]/"), "private_address");
      expectText(test, allowedKind("http://[ff02::1]/"), "private_address");
      expectText(test, allowedKind("http://[not:an:address]/"), "private_address");
      expectText(test, allowedKind("http://[1:2:3:4:5:6:7:8:9]/"), "private_address");
    }

    test("an address written as a number is worked out by a resolver, so it is refused") { test =>
      expectText(test, allowedKind("http://2130706433/"), "private_address");
      expectText(test, allowedKind("http://0x7f000001/"), "private_address");
      expectText(test, allowedKind("http://0x7f.0.0.1/"), "private_address");
      expectText(test, allowedKind("http://127.1/"), "private_address");
      expectText(test, allowedKind("http://0177.0.0.1/"), "private_address");
      expectText(test, allowedKind("http://017700000001/"), "private_address");
    }

    test("where the host is: userinfo, port, case and spaces do not move it") { test =>
      expectText(test, allowedKind("http://user@127.0.0.1/"), "private_address");
      expectText(test, allowedKind("http://evil.com@127.0.0.1/"), "private_address");
      expectText(test, allowedKind("http://127.0.0.1@example.com/"), "ok");
      expectText(test, allowedKind("http://127.0.0.1:80@example.com/"), "ok");
      expectText(test, allowedKind("http://example.com:127/"), "ok");
      expectText(test, allowedKind("http://127.0.0.1:8080/"), "private_address");
      expectText(test, allowedKind("  http://127.0.0.1/  "), "private_address");
      expectText(test, allowedKind("HTTP://127.0.0.1/"), "private_address");
      expectText(test, allowedKind("http://example.com#@127.0.0.1/"), "ok");
      expectText(test, allowedKind("http://example.com?x=@127.0.0.1"), "ok");
    }

    test("the address that comes back is the one that will be fetched") { test =>
      let r = importerAllowed("  HTTPS://Example.com/Essay?x=1#top  ");
      expectText(test, orNone(r.uri), "https://Example.com/Essay?x=1#top");
      expectText(test, orNone(r.host), "example.com");
      expectTrue(test, r.error == null, "no error");
      expectTrue(test, importerAllowed("file:///etc/passwd").uri == null, "nothing to fetch");
    }

    test("what the check cannot see is said to be unseen") { test =>
      expectText(test, allowedKind("http://looks-public.example.com/"), "ok");
    }

## A page as the fake serves it

    let essay(): String {
      joinedLines([
        "<html><head><title>Site name — An Essay</title>",
        "<meta property='og:title' content='An Essay About Pacing' /></head>",
        "<body>",
        "  <nav><a href='/'>Home</a><a href='/about'>About</a></nav>",
        "  <article>",
        "    <h1>An Essay About Pacing</h1>",
        "    <p>The <strong>first</strong> paragraph, with an <em>aside</em> and",
        "       a <a href='https://example.com/x'>link</a>.</p>",
        "    <h2>Why Pace?</h2>",
        "    <p>A second paragraph that is long enough to count for something at all.</p>",
        "    <ul><li>One thing</li><li>Another thing</li></ul>",
        "    <ol><li>First</li><li>Second</li></ol>",
        "    <blockquote><p>Something someone said.</p></blockquote>",
        "    <pre><code>defmodule A do",
        "    end</code></pre>",
        "    <p>A closing paragraph, also of a reasonable length for a test fixture,",
        "       carrying enough words that the importer treats the page as an article",
        "       rather than as a stub with nothing on it worth reading.</p>",
        "    <p>One more paragraph so the fixture clears the floor the importer puts",
        "       under a page before it will accept it as a draft at all, which exists",
        "       so that a navigation-only page does not arrive as an empty manuscript.</p>",
        "  </article>",
        "  <footer><p>Subscribe to our newsletter for more!</p></footer>",
        "  <script>console.log('tracking')</script>",
        "</body></html>",
      ])
    }

    let joinedLines(lines: List<String>): String { sysJoin(lines, "\n") }

    let essayHttp(): ImporterHttp {
      importerFake([importerRoute("https://example.com/essay", 200, essay())])
    }

    let imported(): ImporterPageResult {
      importerFetchPage(essayHttp(), "https://example.com/essay")
    }

    let importedText(): String {
      let p = imported().page;
      if (p != null) { p.text } else { "ERROR ${errKind(imported().error)}" }
    }

    let fetchKind(http: ImporterHttp, url: String): String {
      let r = importerFetchPage(http, url);
      let e = r.error;
      if (e != null) { "${e.kind}:${e.number.toString()}" } else { "ok" }
    }

    let pageOf(html: String): String {
      let r = importerPageFromHtml("https://example.com/p", html);
      let p = r.page;
      if (p != null) { p.text } else { "ERROR ${errKind(r.error)}" }
    }

    let titleOf(html: String): String {
      let r = importerPageFromHtml("https://example.com/p", html);
      let p = r.page;
      if (p != null) { p.title } else { "ERROR ${errKind(r.error)}" }
    }

    let padding(n: Int): String { repeated("<p>Padding sentence for length.</p>", n) }

    test("the title comes from the page, not the tab") { test =>
      let p = imported().page;
      expectText(test, if (p != null) { p.title } else { "none" }, "An Essay About Pacing");
    }

    test("structure survives, because the segmenter cuts on headings") { test =>
      let md = importedText();
      expectHas(test, md, "# An Essay About Pacing");
      expectHas(test, md, "## Why Pace?");
      expectHas(test, md, "- One thing");
      expectHas(test, md, "1. First");
      expectHas(test, md, "> Something someone said.");
      expectHas(test, md, "```");
    }

    test("the whole draft is one heading, then the prose") { test =>
      let md = importedText();
      expectTrue(test, importerStartsWith(md, "# An Essay About Pacing\n\nThe **first** paragraph"), "starts with the title once");
      expectInt(test, md.split("# An Essay About Pacing").length, 2);
      expectHas(test, md, "```\ndefmodule A do\n    end\n```");
      expectHas(test, md, "- One thing\n- Another thing\n\n1. First\n2. Second\n\n> Something");
      expectTrue(test, importerEndsWith(md, "manuscript.\n"), "a trailing newline");
    }

    test("inline markup survives") { test =>
      let md = importedText();
      expectHas(test, md, "**first**");
      expectHas(test, md, "*aside*");
      expectHas(test, md, "[link](https://example.com/x)");
      expectHas(test, md, "with an *aside* and a [link](https://example.com/x).");
    }

    test("emphasis never wraps its own whitespace") { test =>
      let html = "<article><h1>T</h1>\n<p><strong>Verifiability. </strong>Embedded evaluators can check things.</p>\n${padding(20)}\n</article>";
      let md = pageOf(html);
      expectHas(test, md, "**Verifiability.** Embedded");
      let rendered = markdownToHtml(md);
      let plain = sysJoin(
        rendered.split("<").map { (piece: String): String =>
          let parts = piece.split(">");
          if (parts.length > 1) { sysJoin(parts.slice(1, parts.length), ">") } else { piece }
        },
        "",
      );
      expectLacks(test, plain, "*");
      expectHas(test, rendered, "<strong>Verifiability.</strong>");
    }

    test("the furniture is left behind") { test =>
      let md = importedText();
      expectLacks(test, md, "Subscribe to our newsletter");
      expectLacks(test, md, "console.log");
      expectLacks(test, md, "Home");
    }

    test("a page with no article in it is refused rather than imported empty") { test =>
      let http = importerFake([importerRoute("https://example.com/x", 200, "<html><body><nav>Home</nav></body></html>")]);
      expectText(test, fetchKind(http, "https://example.com/x"), "too_little_text:0");
    }

    test("the source url comes back, so the draft can say where it is from") { test =>
      let p = imported().page;
      expectText(test, if (p != null) { p.url } else { "none" }, "https://example.com/essay");
    }

    test("a refused address never reaches the fetch") { test =>
      let http = essayHttp();
      expectText(test, fetchKind(http, "http://169.254.169.254/latest/meta-data/"), "private_address:0");
      expectInt(test, http.sent().length, 0);
      expectText(test, fetchKind(http, "file:///etc/passwd"), "bad_scheme:0");
      expectInt(test, http.sent().length, 0);
    }

## The fetch itself

    test("the page is asked for politely, and by the address as typed") { test =>
      let http = essayHttp();
      importerFetchPage(http, "  https://example.com/essay  ");
      expectText(test, http.sent()[0], "https://example.com/essay");
      expectHas(test, http.sentHeaders()[0], "user-agent: Marginalia/1.0 (+https://marginalia.bobbby.online)");
      expectHas(test, http.sentHeaders()[0], "accept: text/html,application/xhtml+xml");
    }

    test("any status but 200 is an http error that says which") { test =>
      expectText(test, fetchKind(importerFake([importerRoute("example.com", 404, "gone")]), "https://example.com/x"), "http:404");
      expectText(test, fetchKind(importerFake([importerRoute("example.com", 500, "oops")]), "https://example.com/x"), "http:500");
      expectText(test, fetchKind(importerFake([importerRoute("example.com", 301, "")]), "https://example.com/x"), "http:301");
    }

    test("nothing coming back at all is unreachable") { test =>
      expectText(test, fetchKind(importerFake([importerRouteFail("example.com", "timeout")]), "https://example.com/x"), "unreachable:0");
      expectText(test, fetchKind(importerFake([]), "https://example.com/x"), "unreachable:0");
    }

    test("a page over four million bytes is too big, and one under is not") { test =>
      let big = repeated("a", 4000001);
      expectText(test, fetchKind(importerFake([importerRoute("example.com", 200, big)]), "https://example.com/x"), "too_big:0");
      expectText(
        test,
        fetchKind(importerFake([importerRoute("example.com", 200, repeated("a", 4000000))]), "https://example.com/x"),
        "too_little_text:0",
      );
    }

    test("the address that comes back is the one fetched, scheme lower-cased") { test =>
      let http = importerFake([importerRoute("Example.com", 200, essay())]);
      let r = importerFetchPage(http, "HTTPS://Example.com/essay");
      let p = r.page;
      expectText(test, if (p != null) { p.url } else { "none" }, "https://Example.com/essay");
    }

## Reading the page

    test("the title falls back from the article's h1 to any h1, og:title, then the tab") { test =>
      let filler = padding(20);
      expectText(
        test,
        titleOf("<title>Tab</title><meta property='og:title' content='Og'><h1>Any</h1><article><h1>Mine</h1>${filler}</article>"),
        "Mine",
      );
      expectText(
        test,
        titleOf("<title>Tab</title><meta property='og:title' content='Og'><h1>Any</h1><article>${filler}</article>"),
        "Any",
      );
      expectText(
        test,
        titleOf("<title>Tab</title><meta property='og:title' content='Og'><article>${filler}</article>"),
        "Og",
      );
      expectText(test, titleOf("<title>Tab</title><article>${filler}</article>"), "Tab");
      expectText(test, titleOf("<article>${filler}</article>"), "Untitled");
      expectText(test, titleOf("<h1>   </h1><article>${filler}</article>"), "Untitled");
    }

    test("a title is squashed to one line and cut to 200 characters") { test =>
      expectText(test, titleOf("<h1>  Many\n   spaces\there </h1>${padding(20)}"), "Many spaces here");
      expectText(test, titleOf("<h1>Hello <em>World</em>!</h1>${padding(20)}"), "Hello World !");
      let long = titleOf("<h1>${repeated("x", 300)}</h1>${padding(20)}");
      expectInt(test, importerCpCount(long), 200);
    }

    test("a title's entities stay as written in the tab, and are decoded in attributes") { test =>
      expectText(test, titleOf("<title>A &amp; B</title>${padding(20)}"), "A &amp; B");
      expectText(test, titleOf("<meta property='og:title' content='A &amp; B'>${padding(20)}"), "A & B");
    }

    test("the article's own heading is dropped when it repeats the title, and only then") { test =>
      let same = pageOf("<h1>The Title</h1><p>Opening.</p>${padding(20)}");
      expectTrue(test, importerStartsWith(same, "# The Title\n\nOpening."), "one heading");
      expectInt(test, same.split("# The Title").length, 2);
      let different = pageOf("<title>Tab Name</title><article><h2>Intro</h2><h1>Real</h1>${padding(20)}</article>");
      expectInt(test, different.split("# Real").length, 3);
      let contained = pageOf("<title>Essay</title><article><h1>Essay: a long subtitle</h1>${padding(20)}</article>");
      expectText(test, importerTake(contained, 20), "# Essay: a long subt");
    }

    test("the container with the most prose is the article") { test =>
      let page = joinedLines([
        "<h1>T</h1>",
        "<article><p>Comments: short</p></article>",
        "<main><p>The real piece.</p>${padding(20)}</main>",
        "<p>Outside everything, unseen.</p>",
      ]);
      let md = pageOf(page);
      expectHas(test, md, "The real piece.");
      expectLacks(test, md, "Comments: short");
      expectLacks(test, md, "Outside everything");
    }

    test("role=main, .post and .entry-content are containers too") { test =>
      expectHas(test, pageOf("<h1>T</h1><div role='main'><p>Role text.</p>${padding(20)}</div><p>Out</p>"), "Role text.");
      expectLacks(test, pageOf("<h1>T</h1><div role='main'><p>Role text.</p>${padding(20)}</div><p>Out</p>"), "Out\n");
      expectHas(test, pageOf("<h1>T</h1><div class='x post y'><p>Post text.</p>${padding(20)}</div><p>Out</p>"), "Post text.");
      expectHas(test, pageOf("<h1>T</h1><div class='entry-content'><p>Entry text.</p>${padding(20)}</div>"), "Entry text.");
    }

    test("with no container at all the whole document is read") { test =>
      expectHas(test, pageOf("<h1>T</h1><p>Bare.</p>${padding(20)}"), "Bare.");
    }

    test("inside the article, furniture is stripped wherever it is") { test =>
      let md = pageOf("<article><h1>T</h1><p>Keep.</p><aside>Side note</aside><div><form>Search</form><button>Click</button></div><figure><figcaption>Caption</figcaption></figure><svg><text>vector</text></svg>${padding(20)}</article>");
      expectHas(test, md, "Keep.");
      expectLacks(test, md, "Side note");
      expectLacks(test, md, "Search");
      expectLacks(test, md, "Click");
      expectLacks(test, md, "Caption");
      expectLacks(test, md, "vector");
    }

    test("headings of every level keep their level") { test =>
      let md = pageOf("<article><h1>T</h1><h2>Two</h2><h3>Three</h3><h4>Four</h4><h5>Five</h5><h6>Six</h6>${padding(20)}</article>");
      expectHas(test, md, "## Two\n\n### Three\n\n#### Four\n\n##### Five\n\n###### Six");
    }

    test("lists are flattened, numbered by position, and empty items dropped") { test =>
      let md = pageOf("<article><h1>T</h1><ol><li>a</li><li> </li><li>b<ul><li>nested</li></ul></li></ol>${padding(20)}</article>");
      expectHas(test, md, "1. a\n2. bnested\n3. nested");
    }

    test("a link to nowhere is just its text, and so is one with no text") { test =>
      let md = pageOf("<article><h1>T</h1><p>See <a href='#top'>the top</a>, <a>nothing</a>, <a href=''>blank</a>, <a href='/rel'>rel</a>, <a href='http://e.com'></a>.</p>${padding(20)}</article>");
      expectHas(test, md, "See the top, nothing, blank, [rel](/rel), .");
    }

    test("footnote markers vanish and line breaks are spaces") { test =>
      let md = pageOf("<article><h1>T</h1><p>Claim<sup>1</sup> made.<br>Next line<br/>end</p>${padding(20)}</article>");
      expectHas(test, md, "Claim made. Next line end");
    }

    test("whitespace, non-breaking spaces and tabs collapse to one space") { test =>
      let md = pageOf("<article><h1>T</h1><p>a&nbsp;&nbsp;b\t\tc\n\n   d</p>${padding(20)}</article>");
      expectHas(test, md, "a b c d");
    }

    test("entities are decoded in text") { test =>
      let md = pageOf("<article><h1>T</h1><p>Fish &amp; chips &lt;tasty&gt; &quot;q&quot; &mdash; &#8212; &#x41;</p>${padding(20)}</article>");
      expectHas(test, md, "Fish & chips <tasty> \"q\" — — A");
    }

    test("code spans, and a code block with no language") { test =>
      let md = pageOf("<article><h1>T</h1><p>Use <code>map</code> here.</p><pre>\n  x = 1\n  y = 2\n</pre>${padding(20)}</article>");
      expectHas(test, md, "Use `map` here.");
      expectHas(test, md, "```\nx = 1\n  y = 2\n```");
    }

    test("emphasis keeps a single space outside its marks, and an empty one vanishes") { test =>
      let md = pageOf("<article><h1>T</h1><p>a <b> bold </b> b<i></i>c <em>x</em><strong>y</strong></p>${padding(20)}</article>");
      expectHas(test, md, "a **bold** bc *x***y**");
    }

    test("an element the importer does not know is read through, trimmed") { test =>
      let md = pageOf("<article><h1>T</h1><p>one <span> two </span>three <u>four</u></p>${padding(20)}</article>");
      expectHas(test, md, "one twothree four");
    }

    test("blocks inside divs and sections are found, and a block inside a block once") { test =>
      let md = pageOf("<article><h1>T</h1><div><section><p>Deep.</p></section></div><blockquote><p>Quoted.</p></blockquote>${padding(20)}</article>");
      expectHas(test, md, "Deep.");
      expectInt(test, md.split("Quoted.").length, 2);
    }

    test("text between blocks is ignored") { test =>
      let md = pageOf("<article><h1>T</h1>Loose words <p>Kept.</p>more loose${padding(20)}</article>");
      expectHas(test, md, "Kept.");
      expectLacks(test, md, "Loose words");
      expectLacks(test, md, "more loose");
    }

    test("a script inside the article never counts toward its length or its text") { test =>
      let md = pageOf("<article><h1>T</h1><script>var long = '${repeated("x", 2000)}';</script><p>Kept.</p></article>");
      expectText(test, md, "ERROR too_little_text");
    }

## The tree it builds

Re-serialised, for comparison with what Floki 0.38 returned for the same input.

    let serialize(node: ImporterNode): String {
      if (!importerIsElement(node)) { return node.text; }
      let attrs = sysJoin(node.attrs.map { (a: ImporterAttr): String => " ${a.name}=\"${a.value}\"" }, "");
      if (node.kids.length == 0) { return "<${node.tag}${attrs}/>"; }
      let inner = new ListBuilder<String>();
      var i = 0;
      while (i < node.kids.length) {
        inner.add(serialize(node.kids[i]));
        i += 1;
      }
      "<${node.tag}${attrs}>${sysJoin(inner.toList(), "")}</${node.tag}>"
    }

    let tree(html: String): String {
      let root = importerParseHtml(html);
      let parts = new ListBuilder<String>();
      var i = 0;
      while (i < root.kids.length) {
        parts.add(serialize(root.kids[i]));
        i += 1;
      }
      sysJoin(parts.toList(), "")
    }

    test("whitespace between tags is dropped, comments and doctypes are not nodes") { test =>
      expectText(test, tree("<p>a</p> <p>b</p>"), "<p>a</p><p>b</p>");
      expectText(test, tree("<p>a <b> </b> c</p>"), "<p>a <b/> c</p>");
      expectText(test, tree("<p><b>a</b> <i>b</i> c</p>"), "<p><b>a</b><i>b</i> c</p>");
      expectText(test, tree("<div>x<br>y</div><!-- c <b> -->z"), "<div>x<br/>y</div>z");
      expectText(test, tree("<!DOCTYPE html><html><head><title>T</title></head><body></body></html>"), "<html><head><title>T</title></head><body/></html>");
      expectText(test, tree("<p>a<!-- x -->b</p>"), "<p>ab</p>");
      expectText(test, tree("<?xml version='1.0'?><p>x</p>"), "<p>x</p>");
    }

    test("names are lower-cased, attributes read every way they are written") { test =>
      expectText(test, tree("<P CLASS=x>Hi</P>"), "<p class=\"x\">Hi</p>");
      expectText(test, tree("<p a=\"x &amp; y\" b='z' c=d e>t</p>"), "<p a=\"x & y\" b=\"z\" c=\"d\" e=\"e\">t</p>");
      expectText(test, tree("<div id=a class=\"b\" >x</div >"), "<div id=\"a\" class=\"b\">x</div>");
      expectText(test, tree("<p title=\"a>b\">t</p>"), "<p title=\"a>b\">t</p>");
      expectText(test, tree("<ARTICLE><H1>T</H1></ARTICLE>"), "<article><h1>T</h1></article>");
    }

    test("void elements and self-closing tags have no children") { test =>
      expectText(test, tree("<br/>x<br />y"), "<br/>x<br/>y");
      expectText(test, tree("<a href=x>t</a><img src=y>after"), "<a href=\"x\">t</a><img src=\"y\"/>after");
      expectText(test, tree("<a href=\"x\"/>t"), "<a href=\"x\"/>t");
      expectText(test, tree("<hr><input type=text><link rel=x><meta charset=x>z"), "<hr/><input type=\"text\"/><link rel=\"x\"/><meta charset=\"x\"/>z");
    }

    test("a stray end tag is ignored and an end tag closes up to its element") { test =>
      expectText(test, tree("<p>a</b>b</p>"), "<p>ab</p>");
      expectText(test, tree("<div><span>a</div>b"), "<div><span>a</span></div>b");
      expectText(test, tree("<div><span>a</div>b</span>c"), "<div><span>a</span></div>bc");
      expectText(test, tree("<p>x</p></div></div><p>y</p>"), "<p>x</p><p>y</p>");
    }

    test("li, dt, dd and option close an open one; p and td do not") { test =>
      expectText(test, tree("<ul><li>a<li>b</ul>"), "<ul><li>a</li><li>b</li></ul>");
      expectText(test, tree("<ul><li>a<ul><li>n</li></ul><li>b</ul>"), "<ul><li>a<ul><li>n</li></ul></li><li>b</li></ul>");
      expectText(test, tree("<dl><dt>a<dd>b<dt>c</dl>"), "<dl><dt>a</dt><dd>b</dd><dt>c</dt></dl>");
      expectText(test, tree("<select><option>a<option>b</select>"), "<select><option>a</option><option>b</option></select>");
      expectText(test, tree("<p>one<p>two"), "<p>one<p>two</p></p>");
      expectText(test, tree("<tr><td>a<td>b</tr>"), "<tr><td>a<td>b</td></td></tr>");
    }

    test("script, style, title and textarea hold raw text up to their end tag") { test =>
      expectText(test, tree("<p>a<script>if (a<b) {}</script>b</p>"), "<p>a<script>if (a<b) {}</script>b</p>");
      expectText(test, tree("<SCRIPT>var a = '</p>';</SCRIPT><p>k</p>"), "<script>var a = '</p>';</script><p>k</p>");
      expectText(test, tree("<style>p>a{}</style><p>x</p>"), "<style>p>a{}</style><p>x</p>");
      expectText(test, tree("<title>A &amp; B</title><textarea>x &amp; y</textarea>"), "<title>A &amp; B</title><textarea>x &amp; y</textarea>");
      expectText(test, tree("<script>x</script> tail"), "<script>x</script> tail");
    }

    test("a < that does not start a tag is text") { test =>
      expectText(test, tree("<p>a < b and c > d</p>"), "<p>a < b and c > d</p>");
      expectText(test, tree("<p>a <3 b</p>"), "<p>a <3 b</p>");
      expectText(test, tree("just text <b>x</b>"), "just text <b>x</b>");
    }

    test("entities: the common names, numbers, and the ones left alone") { test =>
      expectText(test, tree("<p>&copy; &hellip; &lsquo;q&rsquo; &#x41; &amp;amp; &lt;b&gt; &AMP; &quot;</p>"), "<p>© … ‘q’ A &amp; <b> & \"</p>");
      expectText(test, tree("<p>&foo; &amp &#; &#x; AT&T</p>"), "<p>&foo; &amp &#; &#x; AT&T</p>");
      expectText(test, tree("<p>caf&eacute; &Eacute; &ndash; &trade; &times; &rarr;</p>"), "<p>café É – ™ × →</p>");
      expectText(test, tree("<p>x&nbsp;</p>"), "<p>x\u{a0}</p>");
    }

    test("an unterminated tag or comment is text, not a crash") { test =>
      expectText(test, tree("<p>a</p><div"), "<p>a</p><div");
      expectText(test, tree("<p>a</p><!-- never ends"), "<p>a</p>");
    }
