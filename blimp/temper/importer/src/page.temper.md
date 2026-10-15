# A web page, as a draft

`Marginalia.Import.fetch/2`. Paste and file upload cover the case where the
writer has the text; a lot of what people want to relate is published, and
retyping it is not a thing anyone will do. This fetches the page and turns it
into the markdown the rest of the product works on.

What it keeps: headings, paragraphs, lists, blockquotes, links, emphasis and
code. The headings matter more than they look: the segmenter cuts a draft into
sections on `#` to `###`, so losing them would turn a structured essay into one
undifferentiated block. Everything else goes. Navigation, footers, share
buttons and cookie banners are not the article, and a beat anchored to
"Subscribe to our newsletter" is a beat that makes the whole map look stupid.

    let { sysByteLength, sysGraphemeLength } = import("sys/src");

    let importerMaxBytes = 4000000;

The title becomes the draft's one `h1`, and `text` is the markdown with that
heading on the front.

    export class ImporterPage(public title: String, public text: String, public url: String) {}

    export class ImporterPageResult(public page: ImporterPage?, public error: ImporterError?) {}

    let importerPageError(e: ImporterError): ImporterPageResult { new ImporterPageResult(null, e) }

## Inline text

`squash` and `clean` are different jobs. `wrap` has to know whether emphasis
ended with a space, and it cannot if the space has already been trimmed off:
that was how "now. </strong>We intend" once came out as "now.**We intend", with
the two words run together.

`[\x{00a0}\x{200b}\t ]+` becomes one space, then `\s*\n\s*` becomes one space.

    let importerCollapse(s: String): String {
      var out = s;
      while (importerContains(out, "  ")) { out = importerReplaceAll(out, "  ", " "); }
      out
    }

    let importerTrimAround(s: String, leading: Boolean, trailing: Boolean): String {
      var b = String.begin;
      var e = s.end;
      if (leading) {
        while (s.hasIndex(b) && importerIsSpace(s[b])) { b = s.next(b); }
      }
      if (trailing) {
        while (e > b && importerIsSpace(s[s.prev(e)])) { e = s.prev(e); }
      }
      s.slice(b, e)
    }

    let importerSquash(text: String): String {
      let flat = importerReplaceAll(
        importerReplaceAll(importerReplaceAll(text, importerChr(160), " "), importerChr(8203), " "),
        "\t", " ",
      );
      let spaced = importerCollapse(flat);
      if (!importerContains(spaced, "\n")) { return spaced; }
      let lines = spaced.split("\n");
      let out = new ListBuilder<String>();
      var i = 0;
      while (i < lines.length) {
        out.add(importerTrimAround(lines[i], i > 0, i < lines.length - 1));
        i += 1;
      }
      importerCollapse(importerJoin(out.toList(), " "))
    }

    let importerClean(text: String): String { importerTrim(importerSquash(text)) }

    let importerBlockTags = ["h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "blockquote", "pre"];

    let importerStripTags = [
      "script", "style", "nav", "header", "footer", "aside", "form", "noscript", "svg",
      "iframe", "button", "figure", "figcaption", "template",
    ];

    let importerInline(node: ImporterNode): String {
      importerClean(importerRenderKids(node))
    }

    let importerRenderKids(node: ImporterNode): String {
      let parts = new ListBuilder<String>();
      var i = 0;
      while (i < node.kids.length) {
        parts.add(importerRender(node.kids[i]));
        i += 1;
      }
      importerJoin(parts.toList(), "")
    }

Emphasis must not wrap its own whitespace: `**text **` is not valid CommonMark
(the closing run is not right-flanking) and renders as four literal asterisks.
The space belongs outside the delimiters.

    let importerWrap(el: ImporterNode, mark: String): String {
      let raw = importerSquash(importerRenderKids(el));
      let text = importerTrim(raw);
      if (text.isEmpty) { return ""; }
      let lead = if (importerStartsWith(raw, " ")) { " " } else { "" };
      let trail = if (importerEndsWith(raw, " ")) { " " } else { "" };
      "${lead}${mark}${text}${mark}${trail}"
    }

    let importerRender(node: ImporterNode): String {
      if (!importerIsElement(node)) { return node.text; }
      let tag = node.tag;
      if (tag == "strong" || tag == "b") { return importerWrap(node, "**"); }
      if (tag == "em" || tag == "i") { return importerWrap(node, "*"); }
      if (tag == "code") { return importerWrap(node, "`"); }
      if (tag == "br") { return " "; }
      if (tag == "sup") { return ""; }
      if (tag == "a") {
        let text = importerInline(node);
        let href = importerOrEmpty(importerAttrOf(node, "href"));
        if (text.isEmpty) { return ""; }
        if (href.isEmpty || importerStartsWith(href, "#")) { return text; }
        return "[${text}](${href})";
      }
      importerInline(node)
    }

## Blocks

The block elements in document order, without descending into one already
taken: otherwise a `p` inside a `blockquote` arrives twice. Text at the level
between blocks is ignored.

    let importerBlocks(node: ImporterNode, out: ListBuilder<ImporterNode>): Void {
      var i = 0;
      while (i < node.kids.length) {
        let kid = node.kids[i];
        if (importerIsElement(kid)) {
          if (importerIsOneOf(kid.tag, importerBlockTags)) {
            out.add(kid);
          } else {
            importerBlocks(kid, out);
          }
        }
        i += 1;
      }
    }

    let importerPresence(s: String): String? { if (s.isEmpty) { null } else { s } }

    let importerListItems(el: ImporterNode): List<String> {
      let items = new ListBuilder<String>();
      let all = importerElements(el);
      var i = 0;
      while (i < all.length) {
        if (all[i].tag == "li") {
          let text = importerInline(all[i]);
          if (!text.isEmpty) { items.add(text); }
        }
        i += 1;
      }
      items.toList()
    }

All the descendant `li`, so nested lists are flattened, numbered by position
for an `ol`.

    let importerMarkdownList(el: ImporterNode): String? {
      let items = importerListItems(el);
      let lines = new ListBuilder<String>();
      var i = 0;
      while (i < items.length) {
        if (el.tag == "ol") {
          lines.add("${(i + 1).toString()}. ${items[i]}");
        } else {
          lines.add("- ${items[i]}");
        }
        i += 1;
      }
      importerPresence(importerJoin(lines.toList(), "\n"))
    }

    let importerBlock(el: ImporterNode): String? {
      let tag = el.tag;
      if (tag == "p") { return importerPresence(importerInline(el)); }
      if (tag == "blockquote") {
        let text = importerInline(el);
        if (text.isEmpty) { return null; }
        return importerJoin(text.split("\n").map { (line: String): String => "> ${line}" }, "\n");
      }
      if (tag == "pre") {
        let code = importerTrim(importerTextOf(el));
        if (code.isEmpty) { return null; }
        return "```\n${code}\n```";
      }
      if (tag == "ul" || tag == "ol") { return importerMarkdownList(el); }
      let level = importerParseInt(importerSliceFrom(tag, 1));
      let n = if (level != null) { level } else { 1 };
      let text = importerInline(el);
      if (text.isEmpty) { null } else { "${importerRepeat("#", n)} ${text}" }
    }

    let importerRepeat(unit: String, n: Int): String {
      var out = "";
      var i = 0;
      while (i < n) {
        out = "${out}${unit}";
        i += 1;
      }
      out
    }

Blocks rendered and joined with a blank line, empties dropped, three or more
newlines collapsed to two, and a trailing newline.

    let importerToMarkdown(node: ImporterNode): String {
      let blocks = new ListBuilder<ImporterNode>();
      importerBlocks(node, blocks);
      let rendered = new ListBuilder<String>();
      var i = 0;
      while (i < blocks.length) {
        let r = importerBlock(blocks[i]);
        if (r != null) { rendered.add(r); }
        i += 1;
      }
      var joined = importerJoin(rendered.toList(), "\n\n");
      while (importerContains(joined, "\n\n\n")) { joined = importerReplaceAll(joined, "\n\n\n", "\n\n"); }
      "${joined}\n"
    }

## The title

The article's own `h1` first: `og:title` and `<title>` carry the site's name and
the author's, and "Dario Amodei — We Must Pace the Frontier" is a worse draft
title than "We Must Pace the Frontier".

    let importerFirstH1(node: ImporterNode, inArticle: Boolean, needArticle: Boolean): ImporterNode? {
      var i = 0;
      while (i < node.kids.length) {
        let kid = node.kids[i];
        if (importerIsElement(kid)) {
          if (kid.tag == "h1" && (inArticle || !needArticle)) { return kid; }
          let found = importerFirstH1(kid, inArticle || kid.tag == "article", needArticle);
          if (found != null) { return found; }
        }
        i += 1;
      }
      null
    }

`Floki.text(sep: " ")` of the first match: its text nodes with a space between.

    let importerH1Text(node: ImporterNode?): String {
      if (node != null) { importerJoin(importerTextParts(node), " ") } else { "" }
    }

    let importerTitle(doc: ImporterNode): String {
      let candidates = new ListBuilder<String>();
      candidates.add(importerClean(importerH1Text(importerFirstH1(doc, false, true))));
      candidates.add(importerClean(importerH1Text(importerFirstH1(doc, false, false))));
      let all = importerElements(doc);
      var i = 0;
      while (i < all.length) {
        let el = all[i];
        if (el.tag == "meta" && importerAttrOf(el, "property") == "og:title") {
          let content = importerAttrOf(el, "content");
          if (content != null) { candidates.add(importerClean(content)); }
        }
        i += 1;
      }
      let titleText = new ListBuilder<String>();
      var j = 0;
      while (j < all.length) {
        if (all[j].tag == "title") { titleText.add(importerTextOf(all[j])); }
        j += 1;
      }
      candidates.add(importerClean(importerJoin(titleText.toList(), "")));
      var k = 0;
      while (k < candidates.length) {
        if (!candidates[k].isEmpty) { return importerTake(candidates[k], 200); }
        k += 1;
      }
      "Untitled"
    }

## The article

The body of the piece: whichever candidate container holds the most prose.
Picking `<article>` outright is wrong often enough: plenty of sites wrap
comments or a "related posts" list in one too. The first of equals wins.

    let importerHasClass(el: ImporterNode, wanted: String): Boolean {
      let c = importerAttrOf(el, "class");
      if (c != null) { importerIsOneOf(wanted, importerClassTokens(c)) } else { false }
    }

    let importerClassTokens(c: String): List<String> {
      importerReplaceAll(importerReplaceAll(importerReplaceAll(c, "\n", " "), "\t", " "), "\r", " ")
        .split(" ").filter { (t: String): Boolean => !t.isEmpty }
    }

    let importerMatches(el: ImporterNode, selector: String): Boolean {
      if (selector == "[role=main]") { return importerAttrOf(el, "role") == "main"; }
      if (selector == ".post") { return importerHasClass(el, "post"); }
      if (selector == ".entry-content") { return importerHasClass(el, "entry-content"); }
      el.tag == selector
    }

    let importerArticle(doc: ImporterNode): ImporterNode {
      importerStrip(doc, importerStripTags);
      let all = importerElements(doc);
      let selectors = ["article", "main", "[role=main]", ".post", ".entry-content", "body"];
      var best = doc;
      var bestLength = -1;
      var s = 0;
      while (s < selectors.length) {
        var i = 0;
        while (i < all.length) {
          if (importerMatches(all[i], selectors[s])) {
            let length = sysGraphemeLength(importerTextOf(all[i]));
            if (length > bestLength) {
              best = all[i];
              bestLength = length;
            }
          }
          i += 1;
        }
        s += 1;
      }
      best
    }

## Dropping the repeated title

The title is re-added as the draft's one heading, so the article's own copy of
it would be a second heading saying the same thing. Letters and digits only,
lower case; one containing the other is enough. A character above U+007F counts
as a letter unless it is in a punctuation, symbol or space block.

    let importerKeepsInSimilar(cp: Int): Boolean {
      if (cp < 128) { return importerIsDigit(cp) || (cp >= 97 && cp <= 122); }
      if (cp < 0xC0) {
        return cp == 0xAA || cp == 0xB5 || cp == 0xBA || cp == 0xB2 || cp == 0xB3 || cp == 0xB9 ||
          (cp >= 0xBC && cp <= 0xBE);
      }
      if (cp == 0xD7 || cp == 0xF7) { return false; }
      if (cp >= 0x2000 && cp <= 0x2BFF) { return false; }
      if (cp >= 0x3000 && cp <= 0x303F) { return false; }
      if (cp >= 0xFE30 && cp <= 0xFE6F) { return false; }
      if (cp >= 0xFF00 && cp <= 0xFF0F) { return false; }
      if (cp >= 0xFF1A && cp <= 0xFF20) { return false; }
      if (cp >= 0x1F000 && cp <= 0x1FAFF) { return false; }
      true
    }

    let importerLettersOnly(s: String): String {
      let lower = importerLower(s);
      let sb = new StringBuilder();
      var i = String.begin;
      while (lower.hasIndex(i)) {
        let c = lower[i];
        if (importerKeepsInSimilar(c)) { sb.append(importerChr(c)); }
        i = lower.next(i);
      }
      sb.toString()
    }

    let importerSimilar(a: String, b: String): Boolean {
      let x = importerLettersOnly(a);
      let y = importerLettersOnly(b);
      !x.isEmpty && (importerContains(y, x) || importerContains(x, y))
    }

    let importerDropLeadingTitle(markdown: String, title: String): String {
      let parts = importerSplitOnce(markdown, "\n\n");
      if (parts.length == 2 && importerStartsWith(parts[0], "# ")) {
        if (importerSimilar(importerSliceFrom(parts[0], 2), title)) { parts[1] } else { markdown }
      } else {
        markdown
      }
    }

## From HTML to a draft

`html` is a page already in hand (the Elixir's `body:` option). A page with
under 400 characters of prose is refused rather than imported empty: it is
usually navigation only.

    export let importerPageFromHtml(url: String, html: String): ImporterPageResult {
      let doc = importerParseHtml(html);
      let title = importerTitle(doc);
      let article = importerArticle(doc);
      let markdown = importerDropLeadingTitle(importerToMarkdown(article), title);
      if (sysGraphemeLength(markdown) < 400) {
        return importerPageError(importerError("too_little_text"));
      }
      let heading = if (title.isEmpty) { "" } else { "# ${title}\n\n" };
      new ImporterPageResult(new ImporterPage(title, "${heading}${markdown}", url), null)
    }

## The fetch

The address is checked before anything is requested, whatever else is true.
`user-agent` and `accept` as the Elixir sent them. A 200 over four million
bytes is `too_big`; any other status is `{:http, status}`; nothing coming back
at all is `unreachable`.

    let importerPageHeaders = [
      "user-agent: Marginalia/1.0 (+https://marginalia.bobbby.online)",
      "accept: text/html,application/xhtml+xml",
    ];

    export let importerFetchPage(http: ImporterHttp, url: String?): ImporterPageResult {
      let ok = importerAllowed(url);
      let why = ok.error;
      let uri = ok.uri;
      if (why != null) { return importerPageError(why); }
      if (uri != null) {
        importerFetchAllowed(http, uri)
      } else {
        importerPageError(importerError("bad_url"))
      }
    }

    let importerFetchAllowed(http: ImporterHttp, uri: String): ImporterPageResult {
      let res = http.get(uri, importerPageHeaders);
      if (res.failure != null) { return importerPageError(importerError("unreachable")); }
      if (res.status != 200) {
        return importerPageError(importerErrorNumber("http", res.status));
      }
      if (sysByteLength(res.body) > importerMaxBytes) {
        return importerPageError(importerError("too_big"));
      }
      importerPageFromHtml(uri, res.body)
    }
