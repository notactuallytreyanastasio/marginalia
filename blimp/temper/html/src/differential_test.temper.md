# Markdown, differential cases

Every expected string below is the output of the real MDEx 0.13.5 (the options
`Marginalia.Markdown` passes, ammonia sanitiser included), captured by running it
on the input. `mdIs` renders with hard breaks (`markdownToHtml`), `mdSoft` with
soft ones (`markdownToHtmlSoft`).

## Random documents

These are documents assembled at random from a pool of Markdown fragments
(headings, lists, quotes, fences, tables, HTML, links, footnotes, tabs), run
through MDEx for the expected output. Of 875 generated, 16 disagree with this
library; they are not here. What they have in common is listed under Deviations in
`markdown.temper.md`'s notes: duplicate footnote definitions, footnotes that
reference themselves, a tab after a list marker, and a link definition that
splits a list. The 214 below agree byte for byte.

    test("diff 000 r  Hamp") { test => mdSoft(test, "[r]\n=== # H\n&amp;", "<p>[r]\n=== # H\n&amp;</p>"); }

    test("diff 001 ampmore words here 1  2  z") { test => mdSoft(test, ">  &amp;\nmore words here\n| 1 | 2 |\n===\n* z\n1) o\n[r]: /r", "<blockquote>\n<p>&amp;\nmore words here\n| 1 | 2 |\n===</p>\n</blockquote>\n<ul>\n<li>z</li>\n</ul>\n<ol>\n<li>o\n[r]: /r</li>\n</ol>"); }

    test("diff 002 H more words here xycom") { test => mdIs(test, "more words here x@y.com", "<p>more words here <a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a></p>"); }

    test("diff 003 t 1 o     deepamp a  b") { test => mdSoft(test, "- [ ] t \n1) o     deep\n===\n&amp;\n| a | b |     deep\n===\n```js", "<ul>\n<li> t</li>\n</ul>\n<ol>\n<li>o     deep\n===\n&amp;\n| a | b |     deep\n===</li>\n</ol>\n<pre><code class=\"language-js\"></code></pre>"); }

    test("diff 004 line two1 x1 o H c  wline on") { test => mdSoft(test, "line two\n1. x\n1) o\n# H\n<!-- c -->\n+ w\n\nline one\n~~~ \t- tab", "<p>line two</p>\n<ol>\n<li>x</li>\n</ol>\n<ol>\n<li>o</li>\n</ol>\n<h1>H</h1>\n\n<ul>\n<li>w</li>\n</ul>\n<p>line one</p>\n<pre><code class=\"language--\"></code></pre>"); }

    test("diff 005 bold10 ten z10 tenblu") { test => mdSoft(test, "\n**bold**\n10. ten\n\n|---|---|\n* z\n10. ten\n<b>\n[l](/u)", "<p><strong>bold</strong>\n10. ten</p>\n<p>|---|---|</p>\n<ul>\n<li>z</li>\n</ul>\n<ol start=\"10\">\n<li>ten</li>\n</ol>"); }

    test("diff 006 more words here    code btex") { test => mdSoft(test, "|---|---|\nmore words here\n~~~\n    code\n\n- b\ntext", "<p>|---|---|\nmore words here</p>\n<pre><code>    code\n\n- b\ntext</code></pre>"); }

    test("diff 007 deep a  b rline one siit") { test => mdSoft(test, "    deep\n| a | b |\n[r]\nline one ~~s~~\n![i](/i)\ntext\n[^1]\n\t- tab\n\\*", "<pre><code>deep\n</code></pre>\n<p>| a | b |\n[r]\nline one <del>s</del>\n<img src=\"/i\" alt=\"i\">\ntext\n[^1]\n- tab\n*</p>"); }

    test("diff 008 H nem2 y a  b text    code") { test => mdIs(test, "  - n\n*em*\n|---|---|\n2. y\n\n| a | b |\ntext\n    code\n***", "<ul>\n<li>n<br>\n<em>em</em><br>\n|---|---|</li>\n</ul>\n<ol start=\"2\">\n<li>y</li>\n</ol>\n<p>| a | b |<br>\ntext<br>\ncode</p>\n<hr>"); }

    test("diff 009 H indented r r1 xabc1") { test => mdIs(test, "  indented [r]: /r\n1. x\na_b_c\n[^1]", "<p>indented [r]: /r</p>\n<ol>\n<li>x<br>\na_b_c<br>\n[^1]</li>\n</ol>"); }

    test("diff 010 H codeb") { test => mdIs(test, "`code`\n<b> ===", "<p><code>code</code><br>\n ===</p>"); }

    test("diff 011 H H1 xu   qqhttpxcomabar  w") { test => mdIs(test, "# H\n1. x\n_u_ > > qq\nhttp://x.com/a\nbar\\ + w", "<h1>H</h1>\n<ol>\n<li>x<br>\n<em>u</em> &gt; &gt; qq<br>\n<a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a><br>\nbar\\ + w</li>\n</ol>"); }

    test("diff 012 ampmore words here2 y   qq c") { test => mdSoft(test, "&amp;\nmore words here\n***\n2. y > > qq\n<!-- c -->\n  - n", "<p>&amp;\nmore words here</p>\n<hr>\n<ol start=\"2\">\n<li>y &gt; &gt; qq</li>\n</ol>\n\n<ul>\n<li>n</li>\n</ul>"); }

    test("diff 013 H deep  a") { test => mdIs(test, "    deep - a", "<pre><code>deep - a\n</code></pre>"); }

    test("diff 014 b   tbi   indented") { test => mdSoft(test, "<b>\n- [ ] t\n***bi***   indented", ""); }

    test("diff 015 b foo  more words hererbarem") { test => mdSoft(test, "<b> foo  \nmore words here\n[r]\nbar\\\n*em*\n## H2 ##\n\t- tab _u_\n[^1] line one\n~~~", "<p> foo<br>\nmore words here\n[r]\nbar<br>\n<em>em</em></p>\n<h2>H2</h2>\n<pre><code>- tab _u_\n</code></pre>\n<p>[^1] line one</p>\n<pre><code></code></pre>"); }

    test("diff 016 H2   tab1 234   nr234") { test => mdSoft(test, "## H2 ## \t- tab\n[^1] 2*3*4\n  - n\n[r]\n2*3*4", "<h2>H2 ## \t- tab</h2>\n<p>[^1] 2<em>3</em>4</p>\n<ul>\n<li>n\n[r]\n2<em>3</em>4</li>\n</ul>"); }

    test("diff 017 bold a  b  r   tr r lubarmor") { test => mdSoft(test, "**bold**\n| a | b | [r]\n- [ ] t\n[r]: /r [l](/u)\nbar\\\n\\*\n---\n\nmore words here [^1]", "<p><strong>bold</strong>\n| a | b | [r]</p>\n<ul>\n<li> t\n[r]: /r <a href=\"/u\" rel=\"noopener noreferrer\">l</a>\nbar<br>\n*</li>\n</ul>\n<hr>\n<p>more words here [^1]</p>"); }

    test("diff 018 bi") { test => mdSoft(test, "***\n```\n***bi***", "<hr>\n<pre><code>***bi***</code></pre>"); }

    test("diff 019 ampxycom 1 obold  b b   n ii") { test => mdSoft(test, "&amp;\nx@y.com 1) o\n**bold** - b\n- b\n  - n ***\n![i](/i)\n> > qq\n*** > q\n[^1]: note", "<p>&amp;\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a> 1) o\n<strong>bold</strong> - b</p>\n<ul>\n<li>b\n<ul>\n<li>n ***\n<img src=\"/i\" alt=\"i\"></li>\n</ul>\n</li>\n</ul>\n<blockquote>\n<blockquote>\n<p>qq\n*** &gt; q</p>\n</blockquote>\n</blockquote>"); }

    test("diff 020 H2   bold 1 note   H2  r r") { test => mdSoft(test, "## H2 ##\n-  **bold**\n [^1]: note\n>  ## H2 ##\n*** [r]: /r\n> \n_u_\n    deep", "<h2>H2</h2>\n<ul>\n<li><strong>bold</strong></li>\n</ul>\n<blockquote>\n<h2>H2</h2>\n</blockquote>\n<p>*** [r]: /r</p>\n<blockquote>\n</blockquote>\n<p><em>u</em>\ndeep</p>"); }

    test("diff 021 c  xycomline two  c  bold23") { test => mdSoft(test, "<!-- c --> x@y.com\nline two <!-- c -->\n``` **bold**\n2*3*4     code\nbar\\ \n# H", "<p>line two </p>\n<pre><code class=\"language-**bold**\">2*3*4     code\nbar\\ \n# H</code></pre>"); }

    test("diff 022 qr r H   t 10 ten") { test => mdSoft(test, "> q\n[r]: /r\n# H\n- [ ] t 10. ten", "<blockquote>\n<p>q\n[r]: /r</p>\n</blockquote>\n<h1>H</h1>\n<ul>\n<li> t 10. ten</li>\n</ul>"); }

    test("diff 023 H line oneabcline ones div foo") { test => mdIs(test, "line one\na_b_c\nline one\n~~s~~ <div>\n--- foo  \n--- text\n> ", "<p>line one<br>\na_b_c<br>\nline one<br>\n<del>s</del> <br>\n--- foo<br>\n--- text</p>\n<blockquote>\n</blockquote>"); }

    test("diff 024 b line onediv    n  c") { test => mdSoft(test, "<b>\n line one\n---\n</div>   - n\n> \n<!-- c -->", ""); }

    test("diff 025 H qq    n codecodeb rfoo") { test => mdIs(test, "> > qq   - n\n~~~ |---|---|\n`code`\n`code`\n<b> [r]\nfoo  ", "<blockquote>\n<blockquote>\n<p>qq   - n</p>\n</blockquote>\n</blockquote>\n<pre><code class=\"language-|---|---|\">`code`\n`code`\n&lt;b&gt; [r]\nfoo  </code></pre>"); }

    test("diff 026 boldr r luxycom") { test => mdSoft(test, "**bold**\n---\n[r]: /r\n~~~ [l](/u)\nx@y.com", "<h2><strong>bold</strong></h2>\n<pre><code class=\"language-[l](/u)\">x@y.com</code></pre>"); }

    test("diff 027 H q abc q") { test => mdIs(test, "> q a_b_c\n> q", "<blockquote>\n<p>q a_b_c<br>\nq</p>\n</blockquote>"); }

    test("diff 028 1 o   indentedtext") { test => mdSoft(test, "1) o   indented\ntext > ", "<ol>\n<li>o   indented\ntext &gt;</li>\n</ol>"); }

    test("diff 029 1 notelu 1 x  a a w") { test => mdSoft(test, "[^1]: note\n[l](/u)\n> \n\\*\n1. x - a\n- a\n---\n+ w", "<blockquote>\n</blockquote>\n<p>*</p>\n<ol>\n<li>x - a</li>\n</ol>\n<ul>\n<li>a</li>\n</ul>\n<hr>\n<ul>\n<li>w</li>\n</ul>"); }

    test("diff 030 H2  a1 o 234abc") { test => mdSoft(test, "## H2 ##\n- a\n1) o ---\n2*3*4\na_b_c", "<h2>H2</h2>\n<ul>\n<li>a</li>\n</ul>\n<ol>\n<li>o ---\n2<em>3</em>4\na_b_c</li>\n</ol>"); }

    test("diff 031 1 x xycom b 1 notebar  u") { test => mdSoft(test, "1. x x@y.com\n- b [^1]: note\nbar\\ - \n_u_", "<ol>\n<li>x <a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a></li>\n</ol>\n<ul>\n<li>b [^1]: note\nbar\\ -\n<em>u</em></li>\n</ul>"); }

    test("diff 032 s b1text ampmore words herel") { test => mdSoft(test, "~~s~~ <b>\n[^1]\ntext\n*** &amp;\nmore words here\nline two\n[r] * z", "<p><del>s</del> \n[^1]\ntext\n*** &amp;\nmore words here\nline two\n[r] * z</p>"); }

    test("diff 033 H r r   qqbi r code") { test => mdIs(test, "[r]: /r > > qq\n***bi*** [r]\n `code`", "<p>[r]: /r &gt; &gt; qq<br>\n<em><strong>bi</strong></em> [r]<br>\n<code>code</code></p>"); }

    test("diff 034 1 x") { test => mdSoft(test, "1. x", "<ol>\n<li>x</li>\n</ol>"); }

    test("diff 035 line two1 o amp    deepline") { test => mdSoft(test, "line two\n1) o ---\n&amp;\n    deep\n***\nline one\nfoo   foo  \n    deep _u_", "<p>line two</p>\n<ol>\n<li>o ---\n&amp;\ndeep</li>\n</ol>\n<hr>\n<p>line one\nfoo   foo<br>\ndeep <em>u</em></p>"); }

    test("diff 036 H b  1 b10 ten") { test => mdIs(test, "- b\n> \n~~~ ~~~\n[^1]\n- b\n10. ten", "<ul>\n<li>b</li>\n</ul>\n<blockquote>\n</blockquote>\n<pre><code class=\"language-~~~\">[^1]\n- b\n10. ten</code></pre>"); }

    test("diff 037 H c") { test => mdIs(test, "<!-- c -->\n\\*", "<p>*</p>"); }

    test("diff 038 r1 oem a  b") { test => mdSoft(test, " [r]\n1) o\n*em*\n\n| a | b |", "<p>[r]</p>\n<ol>\n<li>o\n<em>em</em></li>\n</ol>\n<p>| a | b |</p>"); }

    test("diff 039 1 ohttpxcomaabc lucode H2") { test => mdSoft(test, "1) o\nhttp://x.com/a\na_b_c [l](/u)\n```\n`code`\n## H2 ##\n    code\nbar\\\n`code`", "<ol>\n<li>o\n<a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a>\na_b_c <a href=\"/u\" rel=\"noopener noreferrer\">l</a></li>\n</ol>\n<pre><code>`code`\n## H2 ##\n    code\nbar\\\n`code`</code></pre>"); }

    test("diff 040 H abc b line oneamp Hxycom H") { test => mdIs(test, "a_b_c\n ---\n<b> line one\n&amp;\n# H\nx@y.com\n# H", "<h2>a_b_c</h2>\n<p> line one<br>\n&amp;</p>\n<h1>H</h1>\n<p><a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a></p>\n<h1>H</h1>"); }

    test("diff 041 10 ten2 yr r   indentedii") { test => mdSoft(test, "10. ten\n2. y\n[r]: /r   indented\n![i](/i) > > qq\n  - n - a\nx@y.com ~~~\n[r]: /r", "<ol start=\"10\">\n<li>ten</li>\n<li>y\n[r]: /r   indented\n<img src=\"/i\" alt=\"i\"> &gt; &gt; qq</li>\n</ol>\n<ul>\n<li>n - a\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a> ~~~\n[r]: /r</li>\n</ul>"); }

    test("diff 043 tfoo      t") { test => mdSoft(test, "- [ ] t\nfoo   \\*\n|---|---|\n~~~\n- [ ] t", "<ul>\n<li> t\nfoo   *\n|---|---|</li>\n</ul>\n<pre><code>- [ ] t</code></pre>"); }

    test("diff 044 H") { test => mdSoft(test, "# H", "<h1>H</h1>"); }

    test("diff 045 xycom rfoo   1  2  text") { test => mdSoft(test, "x@y.com\n> \n[r]\nfoo  \n| 1 | 2 | text", "<p><a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a></p>\n<blockquote>\n</blockquote>\n<p>[r]\nfoo<br>\n| 1 | 2 | text</p>"); }

    test("diff 046 2 ydivhttpxcoma10 tenbhttpxc") { test => mdSoft(test, "2. y\n</div>\nhttp://x.com/a\n10. ten\n~~~\n<b>\nhttp://x.com/a http://x.com/a\ntext\n[r]: /r", "<ol start=\"2\">\n<li>y</li>\n</ol>"); }

    test("diff 047 amp q") { test => mdSoft(test, "&amp;\n> q", "<p>&amp;</p>\n<blockquote>\n<p>q</p>\n</blockquote>"); }

    test("diff 048 H blank") { test => mdIs(test, "", ""); }

    test("diff 049 1 x   ii line one  qqxycom") { test => mdSoft(test, ">  1. x\n-  - \n![i](/i) line one\n> > qq\n\nx@y.com\n</div>", "<blockquote>\n<ol>\n<li>x</li>\n</ol>\n</blockquote>\n<ul>\n<li>\n<ul>\n<li></li>\n</ul>\n</li>\n</ul>\n<p><img src=\"/i\" alt=\"i\"> line one</p>\n<blockquote>\n<blockquote>\n<p>qq</p>\n</blockquote>\n</blockquote>\n<p><a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a></p>"); }

    test("diff 050 H lu ubar b b") { test => mdIs(test, "\\* \\*\n[l](/u)\n _u_\nbar\\\n- b\n- b\n\n```", "<p>* *<br>\n<a href=\"/u\" rel=\"noopener noreferrer\">l</a><br>\n<em>u</em><br>\nbar\\</p>\n<ul>\n<li>b</li>\n<li>b</li>\n</ul>\n<pre><code></code></pre>"); }

    test("diff 051 q  zbibar") { test => mdSoft(test, "> q\n``` * z\n***bi***\nbar\\", "<blockquote>\n<p>q</p>\n</blockquote>\n<pre><code class=\"language-*\">***bi***\nbar\\</code></pre>"); }

    test("diff 052 b 10 ten") { test => mdSoft(test, "- b 10. ten", "<ul>\n<li>b 10. ten</li>\n</ul>"); }

    test("diff 053 10 ten s    qq  qq w barmore") { test => mdSoft(test, "```\n10. ten ~~s~~\n > \n> > qq\n***\n> > qq\n+ w bar\\\nmore words here\n[^1]: note", "<pre><code>10. ten ~~s~~\n &gt; \n&gt; &gt; qq\n***\n&gt; &gt; qq\n+ w bar\\\nmore words here\n[^1]: note</code></pre>"); }

    test("diff 054 line two  u  indented1 noteb") { test => mdSoft(test, "line two\n>  _u_\n  indented\n[^1]: note\n<b>\nline two\n![i](/i)", "<p>line two</p>\n<blockquote>\n<p><em>u</em>\nindented</p>\n</blockquote>"); }

    test("diff 055 H2  c") { test => mdSoft(test, "## H2 ##\n<!-- c -->\n|---|---|", "<h2>H2</h2>\n\n<p>|---|---|</p>"); }

    test("diff 056 w    t     deep") { test => mdSoft(test, "+ w - [ ] t\n~~~     deep", "<ul>\n<li>w - [ ] t</li>\n</ul>\n<pre><code class=\"language-deep\"></code></pre>"); }

    test("diff 057 H line two 1 xbold iimore word") { test => mdIs(test, "line two 1. x\n**bold** ![i](/i)\nmore words here\n  - n\n&amp;\n2*3*4\n\t- tab\n***", "<p>line two 1. x<br>\n<strong>bold</strong> <img src=\"/i\" alt=\"i\"><br>\nmore words here</p>\n<ul>\n<li>n<br>\n&amp;<br>\n2<em>3</em>4\n<ul>\n<li>tab</li>\n</ul>\n</li>\n</ul>\n<hr>"); }

    test("diff 058 H lu     deepamp     deep") { test => mdIs(test, "[l](/u)     deep\n&amp;\n===     deep", "<p><a href=\"/u\" rel=\"noopener noreferrer\">l</a>     deep<br>\n&amp;<br>\n===     deep</p>"); }

    test("diff 059 H div 1  2   w  qqr r    ncode") { test => mdIs(test, "</div>\n| 1 | 2 | + w\n> > qq\n[r]: /r   - n\n`code` a_b_c", ""); }

    test("diff 060 H 1line one  b tabfoo   line o") { test => mdIs(test, "---\n[^1]\nline one - b\n\t- tab\nfoo   line one\nmore words here - a\n\t- tab\n*em*", "<hr>\n<p>[^1]<br>\nline one - b<br>\n- tab<br>\nfoo   line one<br>\nmore words here - a<br>\n- tab<br>\n<em>em</em></p>"); }

    test("diff 061 H div") { test => mdIs(test, "</div>\n~~~", ""); }

    test("diff 062 H httpxcoma") { test => mdIs(test, "http://x.com/a", "<p><a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a></p>"); }

    test("diff 063 code2 y   indented H2    t") { test => mdSoft(test, "-  `code`\n2. y   indented\n## H2 ##\n- [ ] t\n2. y", "<ul>\n<li><code>code</code></li>\n</ul>\n<ol start=\"2\">\n<li>y   indented</li>\n</ol>\n<h2>H2</h2>\n<ul>\n<li> t</li>\n</ul>\n<ol start=\"2\">\n<li>y</li>\n</ol>"); }

    test("diff 064 qq q r rline two1 xii") { test => mdSoft(test, "> > qq\n> q [r]: /r\nline two\n1. x\n![i](/i)", "<blockquote>\n<blockquote>\n<p>qq\nq [r]: /r\nline two</p>\n</blockquote>\n</blockquote>\n<ol>\n<li>x\n<img src=\"/i\" alt=\"i\"></li>\n</ol>"); }

    test("diff 065 c") { test => mdSoft(test, "<!-- c -->", ""); }

    test("diff 066 wu10 ten") { test => mdSoft(test, "+ w\n\n_u_\n10. ten", "<ul>\n<li>w</li>\n</ul>\n<p><em>u</em>\n10. ten</p>"); }

    test("diff 067 qq lu a    n") { test => mdSoft(test, "> > qq [l](/u)\n- a   - n", "<blockquote>\n<blockquote>\n<p>qq <a href=\"/u\" rel=\"noopener noreferrer\">l</a></p>\n</blockquote>\n</blockquote>\n<ul>\n<li>a   - n</li>\n</ul>"); }

    test("diff 068 em") { test => mdSoft(test, "*em*", "<p><em>em</em></p>"); }

    test("diff 069 divlubold boldb c  wb httpxc") { test => mdSoft(test, "<div>\n[l](/u)\n**bold** **bold**\n<b>\n<!-- c -->\n+ w\n<b> http://x.com/a\n``` a_b_c\n--- **bold**", ""); }

    test("diff 070 H 1 o 10 ten") { test => mdIs(test, "1) o 10. ten", "<ol>\n<li>o 10. ten</li>\n</ol>"); }

    test("diff 071 H abc    t bi q   nr r") { test => mdIs(test, "a_b_c - [ ] t\n~~~ ***bi***\n> q\n  - n\n***\n\n[r]: /r", "<p>a_b_c - [ ] t</p>\n<pre><code class=\"language-***bi***\">&gt; q\n  - n\n***\n\n[r]: /r</code></pre>"); }

    test("diff 072 httpxcoma1 or rxycom bijs2 y") { test => mdSoft(test, "http://x.com/a\n1) o\n[r]: /r\nx@y.com ***bi***\n```js\n2. y\nhttp://x.com/a\n", "<p><a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a></p>\n<ol>\n<li>o\n[r]: /r\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a> <em><strong>bi</strong></em></li>\n</ol>\n<pre><code class=\"language-js\">2. y\nhttp://x.com/a\n</code></pre>"); }

    test("diff 073 blank") { test => mdSoft(test, "~~~", "<pre><code></code></pre>"); }

    test("diff 074 a  b 10 tentext a1 o") { test => mdSoft(test, " | a | b |\n```\n10. ten\ntext\n- a\n1) o", "<p>| a | b |</p>\n<pre><code>10. ten\ntext\n- a\n1) o</code></pre>"); }

    test("diff 075 bdiv") { test => mdSoft(test, "<b>\n<div>", ""); }

    test("diff 076 234codeabc emhttpxcoma1  r10") { test => mdSoft(test, "2*3*4\n`code`\na_b_c *em*\nhttp://x.com/a\n[^1]\n>  [r]\n10. ten", "<p>2<em>3</em>4\n<code>code</code>\na_b_c <em>em</em>\n<a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a>\n[^1]</p>\n<blockquote>\n<p>[r]</p>\n</blockquote>\n<ol start=\"10\">\n<li>ten</li>\n</ol>"); }

    test("diff 077 iixycommore words here    t") { test => mdSoft(test, "\n![i](/i)\nx@y.com\nmore words here - [ ] t\n    deep\nline one - ", "<p><img src=\"/i\" alt=\"i\">\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a>\nmore words here - [ ] t\ndeep\nline one -</p>"); }

    test("diff 078 abc xycom") { test => mdSoft(test, "a_b_c x@y.com", "<p>a_b_c <a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a></p>"); }

    test("diff 079 H n   indentedr") { test => mdIs(test, "  - n   indented\n[r]", "<ul>\n<li>n   indented<br>\n[r]</li>\n</ul>"); }

    test("diff 080 foo") { test => mdSoft(test, "> \nfoo  ", "<blockquote>\n</blockquote>\n<p>foo</p>"); }

    test("diff 081 more words here c  w    deep") { test => mdSoft(test, "more words here\n<!-- c -->\n+ w\n    deep\n![i](/i)\n<!-- c -->\n", "<p>more words here</p>\n\n<ul>\n<li>w\ndeep\n<img src=\"/i\" alt=\"i\"></li>\n</ul>"); }

    test("diff 082 abcu  qqtext") { test => mdSoft(test, "a_b_c\n_u_\n> > qq\ntext", "<p>a_b_c\n<em>u</em></p>\n<blockquote>\n<blockquote>\n<p>qq\ntext</p>\n</blockquote>\n</blockquote>"); }

    test("diff 083 tabr r a  b div  ztext234") { test => mdSoft(test, "\t- tab\n\n\\*\n[r]: /r\n| a | b |\n</div> ~~~\n* z\ntext\n2*3*4", "<pre><code>- tab\n</code></pre>\n<p>*\n[r]: /r\n| a | b |</p>"); }

    test("diff 084 rjsxycomline two") { test => mdSoft(test, "- \n[r]\n```js\nx@y.com\nline two\n", "<ul>\n<li></li>\n</ul>\n<p>[r]</p>\n<pre><code class=\"language-js\">x@y.com\nline two\n</code></pre>"); }

    test("diff 085 br r   b textr  bar c more") { test => mdSoft(test, "~~~ <b>\n[r]: /r - \n- b text\n\n[r] \n bar\\\n<!-- c -->\nmore words here", "<pre><code class=\"language-&lt;b&gt;\">[r]: /r - \n- b text\n\n[r] \n bar\\\n&lt;!-- c --&gt;\nmore words here</code></pre>"); }

    test("diff 086 1  2") { test => mdSoft(test, "| 1 | 2 | ```", "<p>| 1 | 2 | ```</p>"); }

    test("diff 087 indenteddiv 1  2  H amore") { test => mdSoft(test, "  indented\n<div>\n| 1 | 2 |\n# H\n- a\nmore words here", "<p>indented</p>"); }

    test("diff 088 H 1  js js z") { test => mdIs(test, "[^1] > \n```js\n \\*\n```js\n* z ***\n- ", "<p>[^1] &gt;</p>\n<pre><code class=\"language-js\"> \\*\n```js\n* z ***\n- </code></pre>"); }

    test("diff 089 code    n a more words herel") { test => mdSoft(test, "\n`code`   - n\n- a more words here\n[l](/u) <div>\n- \n\n1. x\n`code`", "<p><code>code</code>   - n</p>\n<ul>\n<li>a more words here\n<a href=\"/u\" rel=\"noopener noreferrer\">l</a> </li>\n<li></li>\n</ul>\n<ol>\n<li>x\n<code>code</code></li>\n</ol>"); }

    test("diff 090 s") { test => mdSoft(test, "~~s~~ ", "<p><del>s</del></p>"); }

    test("diff 091 10 ten") { test => mdSoft(test, "10. ten\n", "<ol start=\"10\">\n<li>ten</li>\n</ol>"); }

    test("diff 092 t divabc1    n   t1 note") { test => mdSoft(test, "- [ ] t <div>\na_b_c\n[^1]   - n\n- [ ] t\n[^1]: note", "<ul>\n<li> t \na_b_c\n<sup><a href=\"#fn-1\" rel=\"noopener noreferrer\">1</a></sup>   - n</li>\n<li> t</li>\n</ul>\n\n<ol>\n<li>\n<p>note <a href=\"#fnref-1\" rel=\"noopener noreferrer\">↩</a></p>\n</li>\n</ol>"); }

    test("diff 093 H t c iilu     code c") { test => mdIs(test, "- [ ] t\n<!-- c -->\n![i](/i)\n[l](/u)     code\n<!-- c -->", "<ul>\n<li> t</li>\n</ul>\n\n<p><img src=\"/i\" alt=\"i\"><br>\n<a href=\"/u\" rel=\"noopener noreferrer\">l</a>     code</p>"); }

    test("diff 094 line twojs  indentedxycom") { test => mdSoft(test, "\nline two\n```js\n  indented\nx@y.com", "<p>line two</p>\n<pre><code class=\"language-js\">  indented\nx@y.com</code></pre>"); }

    test("diff 095 1 notetext1 oline two w xyco") { test => mdSoft(test, "[^1]: note\ntext\n1) o\nline two\n+ w x@y.com\n  indented", "<ol>\n<li>o\nline two</li>\n</ol>\n<ul>\n<li>w <a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a>\nindented</li>\n</ul>"); }

    test("diff 096 deep") { test => mdSoft(test, "    deep\n```", "<pre><code>deep\n</code></pre>\n<pre><code></code></pre>"); }

    test("diff 097 qq s  indentedem") { test => mdSoft(test, "> > qq ~~s~~\n  indented\n*em*", "<blockquote>\n<blockquote>\n<p>qq <del>s</del>\nindented\n<em>em</em></p>\n</blockquote>\n</blockquote>"); }

    test("diff 098 div zamp") { test => mdSoft(test, " <div>\n* z\n&amp; |---|---|", ""); }

    test("diff 099 1 xr rxycom") { test => mdSoft(test, "*** ===\n1. x\n[r]: /r\nx@y.com \\*", "<p>*** ===</p>\n<ol>\n<li>x\n[r]: /r\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a> *</li>\n</ol>"); }

    test("diff 100 H foo   c      codeamp") { test => mdIs(test, "foo  \n<!-- c -->     code\n&amp;", "<p>foo</p>\n\n<p>&amp;</p>"); }

    test("diff 101 z code  indented z 1 x") { test => mdSoft(test, "* z `code`\n  indented\n* z 1. x", "<ul>\n<li>z <code>code</code>\nindented</li>\n<li>z 1. x</li>\n</ul>"); }

    test("diff 102 r rbar") { test => mdSoft(test, "[r] [r]\nbar\\\n\n-  ~~~", "<p>[r] [r]\nbar\\</p>\n<ul>\n<li>\n<pre><code></code></pre>\n</li>\n</ul>"); }

    test("diff 103 code1 noteii") { test => mdSoft(test, "`code`\n```\n[^1]: note\n![i](/i)", "<p><code>code</code></p>\n<pre><code>[^1]: note\n![i](/i)</code></pre>"); }

    test("diff 104 H H") { test => mdIs(test, "***\n# H - ", "<hr>\n<h1>H -</h1>"); }

    test("diff 105 a  b  1 o") { test => mdSoft(test, "| a | b | 1) o", "<p>| a | b | 1) o</p>"); }

    test("diff 106 H httpxcomaemcode   indented") { test => mdIs(test, "--- http://x.com/a\n*em*\n`code` \n|---|---|\n  indented", "<p>--- <a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a><br>\n<em>em</em><br>\n<code>code</code><br>\n|---|---|<br>\nindented</p>"); }

    test("diff 107 H tab Habc1 oii") { test => mdIs(test, "``` \t- tab\n---\n# H\na_b_c\n1) o\n![i](/i)", "<pre><code class=\"language--\">---\n# H\na_b_c\n1) o\n![i](/i)</code></pre>"); }

    test("diff 108 t1 o") { test => mdSoft(test, "- [ ] t\n1) o", "<ul>\n<li> t</li>\n</ul>\n<ol>\n<li>o</li>\n</ol>"); }

    test("diff 109 line two c  s ii  q   n  qqh") { test => mdSoft(test, "line two\n<!-- c --> ~~~\n~~s~~ ![i](/i)\n\\* > q\n  - n\n```\n> > qq\nhttp://x.com/a ## H2 ##\n", "<p>line two</p>\n\n<p><del>s</del> <img src=\"/i\" alt=\"i\">\n* &gt; q</p>\n<ul>\n<li>n</li>\n</ul>\n<pre><code>&gt; &gt; qq\nhttp://x.com/a ## H2 ##\n</code></pre>"); }

    test("diff 110 foo") { test => mdSoft(test, "foo  \n|---|---|", "<p>foo<br>\n|---|---|</p>"); }

    test("diff 111 t    code   t uline one") { test => mdSoft(test, "- [ ] t\n    code\n- [ ] t _u_\nline one\n- [ ] t\n  - n\na_b_c\n***\n```js [^1]", "<ul>\n<li> t\ncode</li>\n<li> t <em>u</em>\nline one</li>\n<li> t\n<ul>\n<li>n\na_b_c</li>\n</ul>\n</li>\n</ul>\n<hr>\n<pre><code class=\"language-js\"></code></pre>"); }

    test("diff 112 H ii a bar   tiixycomline one") { test => mdIs(test, " ![i](/i)\n- a bar\\\n- [ ] t\n![i](/i)\nx@y.com\nline one\n## H2 ##\n~~s~~", "<p><img src=\"/i\" alt=\"i\"></p>\n<ul>\n<li>a bar\\</li>\n<li> t<br>\n<img src=\"/i\" alt=\"i\"><br>\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a><br>\nline one</li>\n</ul>\n<h2>H2</h2>\n<p><del>s</del></p>"); }

    test("diff 113 blank") { test => mdSoft(test, "- ", "<ul>\n<li></li>\n</ul>"); }

    test("diff 114 line twoem  bold z bold") { test => mdSoft(test, "line two\n\n*em* - \n**bold**\n* z **bold**", "<p>line two</p>\n<p><em>em</em> -\n<strong>bold</strong></p>\n<ul>\n<li>z <strong>bold</strong></li>\n</ul>"); }

    test("diff 115 httpxcoma a  b") { test => mdSoft(test, "http://x.com/a\n| a | b |\n> ", "<p><a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a>\n| a | b |</p>\n<blockquote>\n</blockquote>"); }

    test("diff 116 abc z abc    code s a  b  Hl") { test => mdSoft(test, "a_b_c\n* z a_b_c\n    code ~~s~~\n| a | b |\n# H\nline one", "<p>a_b_c</p>\n<ul>\n<li>z a_b_c\ncode <del>s</del>\n| a | b |</li>\n</ul>\n<h1>H</h1>\n<p>line one</p>"); }

    test("diff 117 qq c emjs") { test => mdSoft(test, "> > qq\n<!-- c -->\n*em*\n\n```js\n***", "<blockquote>\n<blockquote>\n<p>qq</p>\n</blockquote>\n</blockquote>\n\n<p><em>em</em></p>\n<pre><code class=\"language-js\">***</code></pre>"); }

    test("diff 118 a    t H1 x  indented Hmore") { test => mdSoft(test, "- a - [ ] t\n# H\n1. x\n  indented\n***\n# H\nmore words here\n  - n\n***bi***", "<ul>\n<li>a - [ ] t</li>\n</ul>\n<h1>H</h1>\n<ol>\n<li>x\nindented</li>\n</ol>\n<hr>\n<h1>H</h1>\n<p>more words here</p>\n<ul>\n<li>n\n<em><strong>bi</strong></em></li>\n</ul>"); }

    test("diff 119 lu bar    tdiv") { test => mdSoft(test, "[l](/u) ***\nbar\\ - [ ] t\n</div>\n|---|---|", "<p><a href=\"/u\" rel=\"noopener noreferrer\">l</a> ***\nbar\\ - [ ] t</p>"); }

    test("diff 120 H xycom ampline two  H2  a") { test => mdIs(test, "\nx@y.com &amp;\nline two ## H2 ##\n- a ", "<p><a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a> &amp;<br>\nline two ## H2 ##</p>\n<ul>\n<li>a</li>\n</ul>"); }

    test("diff 121 foo   1 x") { test => mdSoft(test, "foo   1. x", "<p>foo   1. x</p>"); }

    test("diff 122 H bar234  a a234   qqmore word") { test => mdIs(test, "bar\\\n2*3*4 - a\n- a\n2*3*4 > > qq\nmore words here\na_b_c\n10. ten", "<p>bar<br>\n2<em>3</em>4 - a</p>\n<ul>\n<li>a<br>\n2<em>3</em>4 &gt; &gt; qq<br>\nmore words here<br>\na_b_c</li>\n</ul>\n<ol start=\"10\">\n<li>ten</li>\n</ol>"); }

    test("diff 123 H text qline one 1 xuline two") { test => mdIs(test, "text\n> q\nline one 1. x\n***\n_u_\nline two\n- b [r]: /r", "<p>text</p>\n<blockquote>\n<p>q<br>\nline one 1. x</p>\n</blockquote>\n<hr>\n<p><em>u</em><br>\nline two</p>\n<ul>\n<li>b [r]: /r</li>\n</ul>"); }

    test("diff 124 boldline two2 y z") { test => mdSoft(test, " **bold**\nline two\n2. y\n* z", "<p><strong>bold</strong>\nline two\n2. y</p>\n<ul>\n<li>z</li>\n</ul>"); }

    test("diff 125 H qdiv foo") { test => mdIs(test, "> q\n</div> foo  ", "<blockquote>\n<p>q</p>\n</blockquote>"); }

    test("diff 126 H s 234div httpxcoma") { test => mdIs(test, "~~s~~ 2*3*4\n<div> http://x.com/a", "<p><del>s</del> 2<em>3</em>4</p>"); }

    test("diff 127 more words here") { test => mdSoft(test, "more words here", "<p>more words here</p>"); }

    test("diff 128 1 oii s w b") { test => mdSoft(test, "1) o\n![i](/i) ~~s~~\n+ w\n- \n<b>", "<ol>\n<li>o\n<img src=\"/i\" alt=\"i\"> <del>s</del></li>\n</ol>\n<ul>\n<li>w</li>\n</ul>\n<ul>\n<li></li>\n</ul>"); }

    test("diff 129 b z2 y a 1 1 o    code   qq") { test => mdSoft(test, "- b\n* z\n2. y\n```\n- a ```\n[^1] 1) o\n    code |---|---|\n***\n> > qq | a | b |", "<ul>\n<li>b</li>\n</ul>\n<ul>\n<li>z</li>\n</ul>\n<ol start=\"2\">\n<li>y</li>\n</ol>\n<pre><code>- a ```\n[^1] 1) o\n    code |---|---|\n***\n&gt; &gt; qq | a | b |</code></pre>"); }

    test("diff 130 H text  H2   qq uabc    code") { test => mdIs(test, "text ## H2 ##\n> > qq _u_\na_b_c\n    code \n+ w\n[r] </div>\n\n`code`", "<p>text ## H2 ##</p>\n<blockquote>\n<blockquote>\n<p>qq <em>u</em><br>\na_b_c<br>\ncode</p>\n</blockquote>\n</blockquote>\n<ul>\n<li>w<br>\n[r] </li>\n</ul>\n<p><code>code</code></p>"); }

    test("diff 132 r r   tu") { test => mdSoft(test, "[r]: /r\n- [ ] t\n_u_", "<ul>\n<li> t\n<em>u</em></li>\n</ul>"); }

    test("diff 133 js 1 obi") { test => mdSoft(test, "```js 1) o\n\n***bi*** ~~~", "<pre><code class=\"language-js\">\n***bi*** ~~~</code></pre>"); }

    test("diff 134 ampcode divmore words here a") { test => mdSoft(test, "&amp;\n`code`\n~~~ </div>\nmore words here a_b_c\n    code\n    code", "<p>&amp;\n<code>code</code></p>\n<pre><code class=\"language-&lt;/div&gt;\">more words here a_b_c\n    code\n    code</code></pre>"); }

    test("diff 136 line twolu   indented") { test => mdSoft(test, "line two\n[l](/u) \n  indented", "<p>line two\n<a href=\"/u\" rel=\"noopener noreferrer\">l</a>\nindented</p>"); }

    test("diff 137 line one w  1  2 bar H2 r r") { test => mdSoft(test, "\\*\nline one\n+ w | 1 | 2 |\nbar\\\n## H2 ##\n[r]: /r text\n+ w 2. y\n===\nbar\\", "<p>*\nline one</p>\n<ul>\n<li>w | 1 | 2 |\nbar\\</li>\n</ul>\n<h2>H2</h2>\n<p>[r]: /r text</p>\n<ul>\n<li>w 2. y\n===\nbar\\</li>\n</ul>"); }

    test("diff 138 boldbars1") { test => mdSoft(test, "**bold**\nbar\\\n~~s~~\n[^1]\n```", "<p><strong>bold</strong>\nbar<br>\n<del>s</del>\n[^1]</p>\n<pre><code></code></pre>"); }

    test("diff 139 amp bibi smore words herebol") { test => mdSoft(test, "&amp; ***bi***\n***bi*** ~~s~~\nmore words here\n**bold**\n", "<p>&amp; <em><strong>bi</strong></em>\n<em><strong>bi</strong></em> <del>s</del>\nmore words here\n<strong>bold</strong></p>"); }

    test("diff 140 line one u   t1b 1 xii1") { test => mdSoft(test, "line one _u_\n- [ ] t\n[^1]\n<b> 1. x\n![i](/i)\n[^1]", "<p>line one <em>u</em></p>\n<ul>\n<li> t\n[^1]\n 1. x\n<img src=\"/i\" alt=\"i\">\n[^1]</li>\n</ul>"); }

    test("diff 141 H deep tabu") { test => mdIs(test, "    deep\n\t- tab\n===\n_u_", "<pre><code>deep\n- tab\n</code></pre>\n<p>===<br>\n<em>u</em></p>"); }

    test("diff 142 bi") { test => mdSoft(test, "***bi***", "<p><em><strong>bi</strong></em></p>"); }

    test("diff 143 div ubicode") { test => mdSoft(test, "<div> \\*\n_u_\n***bi***\n`code`\n> ", ""); }

    test("diff 144 a  b divemline onemore wor") { test => mdSoft(test, " | a | b |\n<div>\n*em*\nline one\nmore words here", "<p>| a | b |</p>"); }

    test("diff 146 boldtext") { test => mdSoft(test, "**bold**\ntext ***", "<p><strong>bold</strong>\ntext ***</p>"); }

    test("diff 147 H indentedu  indented xycomb") { test => mdIs(test, "===\n  indented\n_u_\n  indented x@y.com\n<b>\nline one", "<p>===<br>\nindented<br>\n<em>u</em><br>\nindented <a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a><br>\n<br>\nline one</p>"); }

    test("diff 148 line one   n r r a") { test => mdSoft(test, "line one\n  - n [r]: /r\n- a", "<p>line one</p>\n<ul>\n<li>n [r]: /r</li>\n<li>a</li>\n</ul>"); }

    test("diff 149 ii w   indented q  qqrcode") { test => mdSoft(test, "\n***\n![i](/i)\n+ w   indented\n> q\n> > qq\n\n[r]\n`code` - b", "<hr>\n<p><img src=\"/i\" alt=\"i\"></p>\n<ul>\n<li>w   indented</li>\n</ul>\n<blockquote>\n<p>q</p>\n<blockquote>\n<p>qq</p>\n</blockquote>\n</blockquote>\n<p>[r]\n<code>code</code> - b</p>"); }

    test("diff 150 jss  qq luem") { test => mdSoft(test, " ```js\n~~s~~\n> > qq [l](/u)\n```\n*em*", "<pre><code class=\"language-js\">~~s~~\n&gt; &gt; qq [l](/u)\n</code></pre>\n<p><em>em</em></p>"); }

    test("diff 151 234sline two httpxcoma H2  2") { test => mdSoft(test, "2*3*4\n~~s~~\nline two http://x.com/a\n## H2 ## 2*3*4", "<p>2<em>3</em>4\n<del>s</del>\nline two <a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a></p>\n<h2>H2 ## 2<em>3</em>4</h2>"); }

    test("diff 153 tab wbar") { test => mdSoft(test, "\t- tab\n+ w\nbar\\", "<pre><code>- tab\n</code></pre>\n<ul>\n<li>w\nbar\\</li>\n</ul>"); }

    test("diff 154 c   Hr r r r") { test => mdSoft(test, "<!-- c --> # H\n[r]: /r [r]: /r\n\\* ```", "<p>[r]: /r [r]: /r\n* ```</p>"); }

    test("diff 155 blank") { test => mdSoft(test, "|---|---|", "<p>|---|---|</p>"); }

    test("diff 156 H deep  indented ampbold") { test => mdIs(test, "    deep\n  indented &amp;\n**bold** <!-- c -->\n~~s~~     deep\n===\nhttp://x.com/a", "<pre><code>deep\n</code></pre>\n<h1>indented &amp;<br>\n<strong>bold</strong> <br>\n<del>s</del>     deep</h1>\n<p><a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a></p>"); }

    test("diff 157 2 y js qfoo   ii1 x     code") { test => mdSoft(test, "2. y ```js\n> q\n|---|---|\nfoo   ![i](/i)\n1. x     code\n~~~\n[r]: /r\n<div>\n&amp; [l](/u)", "<ol start=\"2\">\n<li>y ```js</li>\n</ol>\n<blockquote>\n<p>q\n|---|---|\nfoo   <img src=\"/i\" alt=\"i\"></p>\n</blockquote>\n<ol>\n<li>x     code</li>\n</ol>\n<pre><code>[r]: /r\n&lt;div&gt;\n&amp;amp; [l](/u)</code></pre>"); }

    test("diff 158 234foo   zampbibar") { test => mdSoft(test, "2*3*4\n***\nfoo  \n* z\n&amp;\n***bi***\nbar\\", "<p>2<em>3</em>4</p>\n<hr>\n<p>foo</p>\n<ul>\n<li>z\n&amp;\n<em><strong>bi</strong></em>\nbar\\</li>\n</ul>"); }

    test("diff 159 H iir div    tabcxycom") { test => mdIs(test, "![i](/i)\n[r]\n- \n<div> ```\n- [ ] t\n~~~\na_b_c\nx@y.com ~~~", "<h2><img src=\"/i\" alt=\"i\"><br>\n[r]</h2>"); }

    test("diff 160 blank") { test => mdSoft(test, "> ", "<blockquote>\n</blockquote>"); }

    test("diff 161 z  indented 1 note") { test => mdSoft(test, "\\*\n* z\n***\n  indented [^1]: note", "<p>*</p>\n<ul>\n<li>z</li>\n</ul>\n<hr>\n<p>indented [^1]: note</p>"); }

    test("diff 162 a  b line one") { test => mdSoft(test, "| a | b |\nline one ===", "<p>| a | b |\nline one ===</p>"); }

    test("diff 164 r r234   n 234foo") { test => mdSoft(test, "[r]: /r\n2*3*4\n  - n\n*** 2*3*4\nfoo   - ", "<p>2<em>3</em>4</p>\n<ul>\n<li>n\n*** 2<em>3</em>4\nfoo   -</li>\n</ul>"); }

    test("diff 165 iimore words here zfoo  js") { test => mdSoft(test, "![i](/i)\nmore words here\n* z\n===\n\\*\nfoo  \n```js", "<p><img src=\"/i\" alt=\"i\">\nmore words here</p>\n<ul>\n<li>z\n===\n*\nfoo</li>\n</ul>\n<pre><code class=\"language-js\"></code></pre>"); }

    test("diff 166 abcuii  q  indented  w    co") { test => mdSoft(test, "a_b_c\n_u_\n\n![i](/i) > q\n  indented + w\n\n    code ~~~\n10. ten", "<p>a_b_c\n<em>u</em></p>\n<p><img src=\"/i\" alt=\"i\"> &gt; q\nindented + w</p>\n<pre><code>code ~~~\n</code></pre>\n<ol start=\"10\">\n<li>ten</li>\n</ol>"); }

    test("diff 167 b   t 1 noteamp") { test => mdSoft(test, "<b>\n- [ ] t |---|---|\n\n[^1]: note\n&amp;", ""); }

    test("diff 168 abcbicode H") { test => mdSoft(test, "a_b_c\n```\n***bi***\n`code`\n# H", "<p>a_b_c</p>\n<pre><code>***bi***\n`code`\n# H</code></pre>"); }

    test("diff 169 H deep ii b line twoem") { test => mdIs(test, "\n    deep ![i](/i)\n\\*\n- b line two\n*em*", "<pre><code>deep ![i](/i)\n</code></pre>\n<p>*</p>\n<ul>\n<li>b line two<br>\n<em>em</em></li>\n</ul>"); }

    test("diff 170 t 1 o") { test => mdSoft(test, "- [ ] t 1) o", "<ul>\n<li> t 1) o</li>\n</ul>"); }

    test("diff 171 u bold") { test => mdSoft(test, "_u_ **bold**", "<p><em>u</em> <strong>bold</strong></p>"); }

    test("diff 172 texts 2 y shttpxcoma     d") { test => mdSoft(test, ">  text\n~~s~~ 2. y\n``` ~~s~~\nhttp://x.com/a     deep\n1. x \t- tab\n*em* ~~s~~", "<blockquote>\n<p>text\n<del>s</del> 2. y</p>\n</blockquote>\n<pre><code class=\"language-~~s~~\">http://x.com/a     deep\n1. x \t- tab\n*em* ~~s~~</code></pre>"); }

    test("diff 173 H blank") { test => mdIs(test, "***", "<hr>"); }

    test("diff 174 deep1 x") { test => mdSoft(test, "\\*\n===     deep\n1. x", "<p>*\n===     deep</p>\n<ol>\n<li>x</li>\n</ol>"); }

    test("diff 176 bi    deep js") { test => mdSoft(test, "***bi***\n    deep ```js", "<p><em><strong>bi</strong></em>\ndeep ```js</p>"); }

    test("diff 177 r r 2 y") { test => mdSoft(test, "[r]: /r 2. y", "<p>[r]: /r 2. y</p>"); }

    test("diff 178 H em10 tencode") { test => mdSoft(test, "# H *em*\n10. ten\n`code`", "<h1>H <em>em</em></h1>\n<ol start=\"10\">\n<li>ten\n<code>code</code></li>\n</ol>"); }

    test("diff 179 jshttpxcoma q1 o 2 y") { test => mdSoft(test, "```js\nhttp://x.com/a\n> q\n1) o 2. y", "<pre><code class=\"language-js\">http://x.com/a\n&gt; q\n1) o 2. y</code></pre>"); }

    test("diff 180 divline two    code   tbi") { test => mdSoft(test, "</div>\nline two\n    code\n- [ ] t\n\n***bi***", "<p><em><strong>bi</strong></em></p>"); }

    test("diff 181 ii q abc") { test => mdSoft(test, "![i](/i)\n> q a_b_c\n", "<p><img src=\"/i\" alt=\"i\"></p>\n<blockquote>\n<p>q a_b_c</p>\n</blockquote>"); }

    test("diff 182 a  b div  b") { test => mdSoft(test, "===\n\n| a | b |\n<div>\n|---|---| - b\n~~~", "<p>===</p>\n<p>| a | b |</p>"); }

    test("diff 183 H b  indented  bcode") { test => mdIs(test, "- b\n  indented - b\n`code`", "<ul>\n<li>b<br>\nindented - b<br>\n<code>code</code></li>\n</ul>"); }

    test("diff 184 H foo    asb1") { test => mdIs(test, "foo  \n```\n~~~ - a\n~~s~~\n<b>\n[^1] ---", "<p>foo</p>\n<pre><code>~~~ - a\n~~s~~\n&lt;b&gt;\n[^1] ---</code></pre>"); }

    test("diff 185 divbold2 y") { test => mdSoft(test, "<div>\n**bold**\n2. y", ""); }

    test("diff 186 H a  b  abc1 x") { test => mdIs(test, "\\*\n| a | b |\n> \na_b_c\n***\n1. x", "<p>*<br>\n| a | b |</p>\n<blockquote>\n</blockquote>\n<p>a_b_c</p>\n<hr>\n<ol>\n<li>x</li>\n</ol>"); }

    test("diff 187 H tababc  qbi q") { test => mdIs(test, "\t- tab\na_b_c > q\n***bi***\n---\n> q", "<pre><code>- tab\n</code></pre>\n<h2>a_b_c &gt; q<br>\n<em><strong>bi</strong></em></h2>\n<blockquote>\n<p>q</p>\n</blockquote>"); }

    test("diff 188 z2 y  H2     deep tab  b") { test => mdSoft(test, "* z\n2. y ## H2 ##\n    deep\n\t- tab - b\n    deep [r]", "<ul>\n<li>z</li>\n</ul>\n<ol start=\"2\">\n<li>y ## H2 ##\ndeep\n<ul>\n<li>tab - b\ndeep [r]</li>\n</ul>\n</li>\n</ol>"); }

    test("diff 189 iixycom1 noter r1 x a  b  ab") { test => mdSoft(test, "![i](/i)\nx@y.com\n[^1]: note\n[r]: /r\n1. x\n| a | b | a_b_c\n_u_     deep\n=== - \n  - n &amp;", "<p><img src=\"/i\" alt=\"i\">\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a></p>\n<ol>\n<li>x\n| a | b | a_b_c\n<em>u</em>     deep\n=== -</li>\n</ol>\n<ul>\n<li>n &amp;</li>\n</ul>"); }

    test("diff 191 codefoo    bbi") { test => mdSoft(test, "`code`\nfoo   ***\n- b\n***bi***", "<p><code>code</code>\nfoo   ***</p>\n<ul>\n<li>b\n<em><strong>bi</strong></em></li>\n</ul>"); }

    test("diff 192 n") { test => mdSoft(test, "  - n", "<ul>\n<li>n</li>\n</ul>"); }

    test("diff 193 c") { test => mdSoft(test, "<!-- c --> |---|---|", ""); }

    test("diff 194 H2 10 tenbarii") { test => mdSoft(test, "## H2 ##\n\\*\n10. ten\nbar\\\n![i](/i)\n> ", "<h2>H2</h2>\n<p>*\n10. ten\nbar<br>\n<img src=\"/i\" alt=\"i\"></p>\n<blockquote>\n</blockquote>"); }

    test("diff 195 H 1 ubar 1 xline one 234  qqam") { test => mdIs(test, "[^1] _u_\nbar\\\n--- 1. x\nline one\n--- 2*3*4\n> > qq\n&amp;", "<p>[^1] <em>u</em><br>\nbar<br>\n--- 1. x<br>\nline one<br>\n--- 2<em>3</em>4</p>\n<blockquote>\n<blockquote>\n<p>qq<br>\n&amp;</p>\n</blockquote>\n</blockquote>"); }

    test("diff 196 indented  H    code  a  b") { test => mdSoft(test, "  indented # H\n\n    code | a | b |", "<p>indented # H</p>\n<pre><code>code | a | b |\n</code></pre>"); }

    test("diff 197 r   qq   t  a a  b   a  b ht") { test => mdSoft(test, "[r] > > qq\n- [ ] t - a\n| a | b | | a | b |\nhttp://x.com/a\n* z\n\n- a\n* z 1) o", "<p>[r] &gt; &gt; qq</p>\n<ul>\n<li> t - a\n| a | b | | a | b |\n<a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a></li>\n</ul>\n<ul>\n<li>z</li>\n</ul>\n<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>z 1) o</li>\n</ul>"); }

    test("diff 198 10 ten httpxcoma") { test => mdSoft(test, "10. ten http://x.com/a\n\\*", "<ol start=\"10\">\n<li>ten <a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a>\n*</li>\n</ol>"); }

    test("diff 199 line one bamp 1  2 sb r r") { test => mdSoft(test, "line one\n- b\n&amp;\n| 1 | 2 |\n~~s~~\n<b> [r]: /r", "<p>line one</p>\n<ul>\n<li>b\n&amp;\n| 1 | 2 |\n<del>s</del>\n [r]: /r</li>\n</ul>"); }

    test("diff 200 234 qbar1 1 note b line two") { test => mdSoft(test, "2*3*4\n> q\nbar\\\n[^1] ===\n[^1]: note\n- b line two", "<p>2<em>3</em>4</p>\n<blockquote>\n<p>q\nbar<br>\n<sup><a href=\"#fn-1\" rel=\"noopener noreferrer\">1</a></sup> ===</p>\n</blockquote>\n<ul>\n<li>b line two</li>\n</ul>\n\n<ol>\n<li>\n<p>note <a href=\"#fnref-1\" rel=\"noopener noreferrer\">↩</a></p>\n</li>\n</ol>"); }

    test("diff 201 rabc ampdiv     deep tabem b") { test => mdSoft(test, "[r]\na_b_c &amp;\n<div>     deep\n\t- tab\n*em*\n- b", "<p>[r]\na_b_c &amp;</p>"); }

    test("diff 202 H H2  abcline onehttpxcomas") { test => mdSoft(test, "# H\n## H2 ##\n*** a_b_c\nline one\nhttp://x.com/a\n~~s~~\n</div>\n~~s~~", "<h1>H</h1>\n<h2>H2</h2>\n<p>*** a_b_c\nline one\n<a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a>\n<del>s</del></p>"); }

    test("diff 203 t a234 H w10 ten  tabbx") { test => mdSoft(test, "~~~\n>  - [ ] t\n- a\n2*3*4\n# H\n+ w\n10. ten \t- tab\n<b>\nx@y.com", "<pre><code>&gt;  - [ ] t\n- a\n2*3*4\n# H\n+ w\n10. ten \t- tab\n&lt;b&gt;\nx@y.com</code></pre>"); }

    test("diff 204 H code") { test => mdIs(test, "`code`", "<p><code>code</code></p>"); }

    test("diff 205 H2 1 xhttpxcomaboldr r 1  2") { test => mdSoft(test, "## H2 ##\n1. x\nhttp://x.com/a\n**bold**\n[r]: /r\n| 1 | 2 | | a | b |\n- ", "<h2>H2</h2>\n<ol>\n<li>x\n<a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a>\n<strong>bold</strong>\n[r]: /r\n| 1 | 2 | | a | b |</li>\n</ol>\n<ul>\n<li></li>\n</ul>"); }

    test("diff 206 1 xmore words hereabcline tw") { test => mdSoft(test, "1. x\nmore words here\na_b_c\nline two\n<b>", "<ol>\n<li>x\nmore words here\na_b_c\nline two</li>\n</ol>"); }

    test("diff 207 1  2  div") { test => mdSoft(test, "| 1 | 2 | </div>\n```", "<p>| 1 | 2 | </p>\n<pre><code></code></pre>"); }

    test("diff 209 z emdiv") { test => mdSoft(test, "* z *em*\n</div> |---|---|", "<ul>\n<li>z <em>em</em></li>\n</ul>"); }

    test("diff 210 H amp w10 tenfoo") { test => mdIs(test, " &amp;\n+ w\n10. ten\nfoo  \n---", "<p>&amp;</p>\n<ul>\n<li>w</li>\n</ul>\n<ol start=\"10\">\n<li>ten<br>\nfoo</li>\n</ol>\n<hr>"); }

    test("diff 211 amp  adiv  H") { test => mdSoft(test, "&amp; - a\n</div> # H", "<p>&amp; - a</p>"); }

    test("diff 212 234   t  indentedr rr r") { test => mdSoft(test, "2*3*4\n- [ ] t\n  indented\n[r]: /r\n[r]: /r\n---", "<p>2<em>3</em>4</p>\n<ul>\n<li> t\nindented\n[r]: /r\n[r]: /r</li>\n</ul>\n<hr>"); }

    test("diff 213 line one  qxycom iiline two") { test => mdSoft(test, "line one > q\nx@y.com ![i](/i)\nline two - \n---\n=== \nmore words here\n|---|---|\n\t- tab\n <!-- c -->", "<h2>line one &gt; q\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a> <img src=\"/i\" alt=\"i\">\nline two -</h2>\n<p>===\nmore words here\n|---|---|\n- tab</p>"); }

    test("diff 214 line one  z   1  2 foo   a") { test => mdSoft(test, "line one \n* z\n-  | 1 | 2 |\nfoo  \n| a | b |", "<p>line one</p>\n<ul>\n<li>z</li>\n</ul>\n<ul>\n<li>| 1 | 2 |\nfoo<br>\n| a | b |</li>\n</ul>"); }

    test("diff 215 deep     code wlu") { test => mdSoft(test, "    deep     code\n---\n+ w\n[l](/u)", "<pre><code>deep     code\n</code></pre>\n<hr>\n<ul>\n<li>w\n<a href=\"/u\" rel=\"noopener noreferrer\">l</a></li>\n</ul>"); }

    test("diff 216 abc a") { test => mdSoft(test, "a_b_c\n- a > ", "<p>a_b_c</p>\n<ul>\n<li>a &gt;</li>\n</ul>"); }

    test("diff 217 1  2 xycom") { test => mdSoft(test, "===\n| 1 | 2 |\nx@y.com", "<p>===\n| 1 | 2 |\n<a href=\"mailto:x@y.com\" rel=\"noopener noreferrer\">x@y.com</a></p>"); }

    test("diff 218 H n  bxycom  a Hhttpxcoma") { test => mdIs(test, "```\n  - n - b\nx@y.com - a\n# H\nhttp://x.com/a ## H2 ##\n[^1]\n> \n- [ ] t\n## H2 ## - ", "<pre><code>  - n - b\nx@y.com - a\n# H\nhttp://x.com/a ## H2 ##\n[^1]\n&gt; \n- [ ] t\n## H2 ## - </code></pre>"); }

    test("diff 219 H zamp foo  code divr") { test => mdIs(test, "* z\n&amp; foo  \n`code` <div>\n[r]", "<ul>\n<li>z<br>\n&amp; foo<br>\n<code>code</code> <br>\n[r]</li>\n</ul>"); }

    test("diff 220 a  b  1  2") { test => mdSoft(test, "```\n| a | b |\n| 1 | 2 |", "<pre><code>| a | b |\n| 1 | 2 |</code></pre>"); }

    test("diff 221 H 1 o  zline one1 obold httpxc") { test => mdIs(test, "1) o * z\nline one\n1) o\n**bold** http://x.com/a", "<ol>\n<li>o * z<br>\nline one</li>\n<li>o<br>\n<strong>bold</strong> <a href=\"http://x.com/a\" rel=\"noopener noreferrer\">http://x.com/a</a></li>\n</ol>"); }

    test("diff 222 2341") { test => mdSoft(test, "2*3*4\n[^1] ", "<p>2<em>3</em>4\n[^1]</p>"); }
