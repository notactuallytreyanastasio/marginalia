# Markdown tests

Every expected string below is the output of the real MDEx 0.13.5 (the options
`Marginalia.Markdown` passes, ammonia sanitiser included), captured by running it
on the input. `mdIs` renders with hard breaks (`markdownToHtml`), `mdSoft` with
soft ones (`markdownToHtmlSoft`).

    let mdIs(test: Test, input: String, want: String): Void {
      expectText(test, markdownToHtml(input), want);
    }

    let mdSoft(test: Test, input: String, want: String): Void {
      expectText(test, markdownToHtmlSoft(input), want);
    }

## Captured from MDEx

    test("md 000 H1") { test => mdSoft(test, "# H1", "<h1>H1</h1>"); }

    test("md 001 H6") { test => mdSoft(test, "###### H6", "<h6>H6</h6>"); }

    test("md 002 seven") { test => mdSoft(test, "####### seven", "<p>####### seven</p>"); }

    test("md 003 nospace") { test => mdSoft(test, "#nospace", "<p>#nospace</p>"); }

    test("md 004 trailing") { test => mdSoft(test, "## trailing ##", "<h2>trailing</h2>"); }

    test("md 005 blank") { test => mdSoft(test, "#", "<h1></h1>"); }

    test("md 006 Setext") { test => mdSoft(test, "Setext\n===", "<h1>Setext</h1>"); }

    test("md 007 Paraline two") { test => mdSoft(test, "Para\nline two\n---", "<h2>Para\nline two</h2>"); }

    test("md 008 a  b") { test => mdSoft(test, "a  \nb", "<p>a<br>\nb</p>"); }

    test("md 009 ab") { test => mdSoft(test, "a\\\nb", "<p>a<br>\nb</p>"); }

    test("md 010 H a  b") { test => mdIs(test, "a  \nb", "<p>a<br>\nb</p>"); }

    test("md 011 em em strong strong both a b") { test => mdSoft(test, "*em* _em_ **strong** __strong__ ***both*** *a **b** c*", "<p><em>em</em> <em>em</em> <strong>strong</strong> <strong>strong</strong> <em><strong>both</strong></em> <em>a <strong>b</strong> c</em></p>"); }

    test("md 012 snakecaseword and 234") { test => mdSoft(test, "snake_case_word and 2*3*4", "<p>snake_case_word and 2<em>3</em>4</p>"); }

    test("md 013 code  ab   a") { test => mdSoft(test, "`code` `` a`b `` ` a `", "<p><code>code</code> <code>a`b</code> <code>a</code></p>"); }

    test("md 014 unclosed") { test => mdSoft(test, "`unclosed", "<p>`unclosed</p>"); }

    test("md 015 code") { test => mdSoft(test, "```\ncode\n```", "<pre><code>code\n</code></pre>"); }

    test("md 016 pyx  1") { test => mdSoft(test, "~~~py\nx = 1\n~~~", "<pre><code class=\"language-py\">x = 1\n</code></pre>"); }

    test("md 017 inner") { test => mdSoft(test, "````\n```\ninner\n```\n````", "<pre><code>```\ninner\n```\n</code></pre>"); }

    test("md 018 unclosed") { test => mdSoft(test, "```\nunclosed", "<pre><code>unclosed</code></pre>"); }

    test("md 019 para    indented code    mor") { test => mdSoft(test, "para\n\n    indented code\n    more\n\nafter", "<p>para</p>\n<pre><code>indented code\nmore\n</code></pre>\n<p>after</p>"); }

    test("md 020 a b c") { test => mdSoft(test, "> a\n> b\n\n> c", "<blockquote>\n<p>a\nb</p>\n</blockquote>\n<blockquote>\n<p>c</p>\n</blockquote>"); }

    test("md 021 alazy") { test => mdSoft(test, "> a\nlazy", "<blockquote>\n<p>a\nlazy</p>\n</blockquote>"); }

    test("md 022 nested back") { test => mdSoft(test, "> > nested\n> back", "<blockquote>\n<blockquote>\n<p>nested\nback</p>\n</blockquote>\n</blockquote>"); }

    test("md 023 item  two") { test => mdSoft(test, "> - item\n> - two", "<blockquote>\n<ul>\n<li>item</li>\n<li>two</li>\n</ul>\n</blockquote>"); }

    test("md 024 a b c") { test => mdSoft(test, "- a\n- b\n- c", "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n</ul>"); }

    test("md 025 a b") { test => mdSoft(test, "* a\n* b", "<ul>\n<li>a</li>\n<li>b</li>\n</ul>"); }

    test("md 026 a b") { test => mdSoft(test, "+ a\n+ b", "<ul>\n<li>a</li>\n<li>b</li>\n</ul>"); }

    test("md 027 1 a2 b3 c") { test => mdSoft(test, "1. a\n2. b\n3. c", "<ol>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n</ol>"); }

    test("md 028 3 a4 b") { test => mdSoft(test, "3. a\n4. b", "<ol start=\"3\">\n<li>a</li>\n<li>b</li>\n</ol>"); }

    test("md 029 1 a2 b") { test => mdSoft(test, "1) a\n2) b", "<ol>\n<li>a</li>\n<li>b</li>\n</ol>"); }

    test("md 030 a   b     c d") { test => mdSoft(test, "- a\n  - b\n    - c\n- d", "<ul>\n<li>a\n<ul>\n<li>b\n<ul>\n<li>c</li>\n</ul>\n</li>\n</ul>\n</li>\n<li>d</li>\n</ul>"); }

    test("md 031 1 a    b    c2 d") { test => mdSoft(test, "1. a\n   - b\n   - c\n2. d", "<ol>\n<li>a\n<ul>\n<li>b</li>\n<li>c</li>\n</ul>\n</li>\n<li>d</li>\n</ol>"); }

    test("md 032 a b") { test => mdSoft(test, "- a\n\n- b", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>"); }

    test("md 033 a  more b") { test => mdSoft(test, "- a\n\n  more\n- b", "<ul>\n<li>\n<p>a</p>\n<p>more</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>"); }

    test("md 034 a b") { test => mdSoft(test, "- a\n* b", "<ul>\n<li>a</li>\n</ul>\n<ul>\n<li>b</li>\n</ul>"); }

    test("md 035 para list directly after") { test => mdSoft(test, "para\n- list directly after", "<p>para</p>\n<ul>\n<li>list directly after</li>\n</ul>"); }

    test("md 036 blank") { test => mdSoft(test, "---", "<hr>"); }

    test("md 037 blank") { test => mdSoft(test, "***", "<hr>"); }

    test("md 038 blank") { test => mdSoft(test, "___", "<hr>"); }

    test("md 039 blank") { test => mdSoft(test, "- - -", "<hr>"); }

    test("md 040 ab") { test => mdSoft(test, "a\n\n---\n\nb", "<p>a</p>\n<hr>\n<p>b</p>"); }

    test("md 041 linkhttpxcom thttpxcom title") { test => mdSoft(test, "[link](http://x.com) [t](http://x.com \"title\") [e]()", "<p><a href=\"http://x.com\" rel=\"noopener noreferrer\">link</a> <a href=\"http://x.com\" title=\"title\" rel=\"noopener noreferrer\">t</a> <a href=\"\" rel=\"noopener noreferrer\">e</a></p>"); }

    test("md 042 jsjavascriptalert1 ddatatext") { test => mdSoft(test, "[js](javascript:alert(1)) [d](data:text/html,x) [ok](mailto:a@b.c) [rel](/a/b?c=d&e=f)", "<p><a href=\"\" rel=\"noopener noreferrer\">js</a> <a href=\"\" rel=\"noopener noreferrer\">d</a> <a href=\"mailto:a@b.c\" rel=\"noopener noreferrer\">ok</a> <a href=\"/a/b?c=d&amp;e=f\" rel=\"noopener noreferrer\">rel</a></p>"); }

    test("md 043 alt textipng ttl xjavascript") { test => mdSoft(test, "![alt text](/i.png \"ttl\") ![x](javascript:foo)", "<p><img src=\"/i.png\" alt=\"alt text\" title=\"ttl\"> <img src=\"\" alt=\"x\"></p>"); }

    test("md 044 a b chttpxcom") { test => mdSoft(test, "[a [b] c](http://x.com)", "<p><a href=\"http://x.com\" rel=\"noopener noreferrer\">a [b] c</a></p>"); }

    test("md 045 httpxcom abco notalink") { test => mdSoft(test, "<http://x.com> <a@b.co> <notalink", "<p><a href=\"http://x.com\" rel=\"noopener noreferrer\">http://x.com</a> <a href=\"mailto:a@b.co\" rel=\"noopener noreferrer\">a@b.co</a> &lt;notalink</p>"); }

    test("md 046 visit httpxcomab and wwwexam") { test => mdSoft(test, "visit http://x.com/a_b. and www.example.com, or (http://y.org/p) ok. mail a@b.co.", "<p>visit <a href=\"http://x.com/a_b\" rel=\"noopener noreferrer\">http://x.com/a_b</a>. and <a href=\"http://www.example.com\" rel=\"noopener noreferrer\">www.example.com</a>, or (<a href=\"http://y.org/p\" rel=\"noopener noreferrer\">http://y.org/p</a>) ok. mail <a href=\"mailto:a@b.co\" rel=\"noopener noreferrer\">a@b.co</a>.</p>"); }

    test("md 047 httpxcomab1c2") { test => mdSoft(test, "http://x.com/a?b=1&c=2", "<p><a href=\"http://x.com/a?b=1&amp;c=2\" rel=\"noopener noreferrer\">http://x.com/a?b=1&amp;c=2</a></p>"); }

    test("md 048 bboldb span classxsspan  c") { test => mdSoft(test, "<b>bold</b> <span class=\"x\">s</span> <!-- c --> <br> text", "<p>bold s   text</p>"); }

    test("md 049 divblock htmldivafter") { test => mdSoft(test, "<div>\nblock html\n</div>\n\nafter", "<p>after</p>"); }

    test("md 050 scriptalert1script") { test => mdSoft(test, "<script>alert(1)</script>", ""); }

    test("md 051 a  b  c  d amp e copy f 65 x") { test => mdSoft(test, "a < b > c & d &amp; e &copy; f &#65; &#x42; &bogus; \"q\" 'a'", "<p>a &lt; b &gt; c &amp; d &amp; e © f A B &amp;bogus; \"q\" 'a'</p>"); }

    test("md 052 not em  a") { test => mdSoft(test, "\\* not em \\# \\a \\\\ \\`", "<p>* not em # \\a \\ `</p>"); }

    test("md 053 gone single triple") { test => mdSoft(test, "~~gone~~ ~single~ ~~~triple~~~", "<p><del>gone</del> <del>single</del> ~~~triple~~~</p>"); }

    test("md 054 a x b X c  d") { test => mdSoft(test, "- [ ] a\n- [x] b\n- [X] c\n- [] d", "<ul>\n<li> a</li>\n<li> b</li>\n<li> c</li>\n<li>[] d</li>\n</ul>"); }

    test("md 055 a  b  1  2") { test => mdSoft(test, "| a | b |\n|---|---|\n| 1 | 2 |", "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>"); }

    test("md 056 a  b  c  1  2  3  x") { test => mdSoft(test, "| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n| x |", "<table>\n<thead>\n<tr>\n<th align=\"left\">a</th>\n<th align=\"center\">b</th>\n<th align=\"right\">c</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"left\">1</td>\n<td align=\"center\">2</td>\n<td align=\"right\">3</td>\n</tr>\n<tr>\n<td align=\"left\">x</td>\n<td align=\"center\"></td>\n<td align=\"right\"></td>\n</tr>\n</tbody>\n</table>"); }

    test("md 057 a  b1  2after") { test => mdSoft(test, "a | b\n--|--\n1 | 2\n\nafter", "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>\n<p>after</p>"); }

    test("md 058 text11 note") { test => mdSoft(test, "text[^1]\n\n[^1]: note", "<p>text<sup><a href=\"#fn-1\" rel=\"noopener noreferrer\">1</a></sup></p>\n\n<ol>\n<li>\n<p>note <a href=\"#fnref-1\" rel=\"noopener noreferrer\">↩</a></p>\n</li>\n</ol>"); }

    test("md 059 refr and rr httpxcom T") { test => mdSoft(test, "[ref][r] and [r]\n\n[r]: http://x.com \"T\"", "<p><a href=\"http://x.com\" title=\"T\" rel=\"noopener noreferrer\">ref</a> and <a href=\"http://x.com\" title=\"T\" rel=\"noopener noreferrer\">r</a></p>"); }

    test("md 060 line oneline twoline three") { test => mdSoft(test, "line one\nline two\n\n\n\nline three", "<p>line one\nline two</p>\n<p>line three</p>"); }

    test("md 061 leading spaces para") { test => mdSoft(test, "  leading spaces para", "<p>leading spaces para</p>"); }

    test("md 062 text") { test => mdSoft(test, "* * *\ntext", "<hr>\n<p>text</p>"); }

    test("md 063 1 a   b2 c") { test => mdSoft(test, "1. a\n\n   b\n2. c", "<ol>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ol>"); }

    test("md 064 a btext1 x") { test => mdSoft(test, "- a\n- b\n\ntext\n\n1. x", "<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n<p>text</p>\n<ol>\n<li>x</li>\n</ol>"); }

    test("md 065 Head em c lu") { test => mdSoft(test, "# Head *em* `c` [l](/u)", "<h1>Head <em>em</em> <code>c</code> <a href=\"/u\" rel=\"noopener noreferrer\">l</a></h1>"); }

    test("md 066 a b") { test => mdSoft(test, "***a** b*", "<p><em><strong>a</strong> b</em></p>"); }

    test("md 067 a b c") { test => mdSoft(test, "**a *b* c**", "<p><strong>a <em>b</em> c</strong></p>"); }

    test("md 068 a b") { test => mdSoft(test, "*a **b***", "<p><em>a <strong>b</strong></em></p>"); }

    test("md 069 boldtext and aboldb and ab a") { test => mdSoft(test, "**bold**text and a**bold**b and _a_b and a_b_ c", "<p><strong>bold</strong>text and a<strong>bold</strong>b and <em>a_b and a_b</em> c</p>"); }

    test("md 070 not em  and  not strong  he") { test => mdSoft(test, "* not em * and ** not strong ** here", "<ul>\n<li>not em * and ** not strong ** here</li>\n</ul>"); }

    test("md 071 mark and quotes   a") { test => mdSoft(test, "\u{e000}mark\u{e001} and \"quotes\" -- ... 'a'", "<p>\u{e000}mark\u{e001} and \"quotes\" -- ... 'a'</p>"); }

    test("md 072 Tabseparated and trailing sp") { test => mdSoft(test, "Tab\tseparated and trailing space \n", "<p>Tab\tseparated and trailing space</p>"); }

    test("md 073 ab") { test => mdSoft(test, "a\n\n\nb\n", "<p>a</p>\n<p>b</p>"); }

    test("md 074 blank") { test => mdSoft(test, "``", "<p>``</p>"); }

    test("md 075 itemcode") { test => mdSoft(test, "- item\n```\ncode\n```", "<ul>\n<li>item</li>\n</ul>\n<pre><code>code\n</code></pre>"); }

    test("md 076 code") { test => mdSoft(test, "- ```\n  code\n  ```", "<ul>\n<li>\n<pre><code>code\n</code></pre>\n</li>\n</ul>"); }

    test("md 077 1 one1 one again1 and again") { test => mdSoft(test, "1. one\n1. one again\n1. and again", "<ol>\n<li>one</li>\n<li>one again</li>\n<li>and again</li>\n</ol>"); }

    test("md 078 0 zero1 one") { test => mdSoft(test, "0. zero\n1. one", "<ol start=\"0\">\n<li>zero</li>\n<li>one</li>\n</ol>"); }

    test("md 079 not list") { test => mdSoft(test, "-not list\n-", "<h2>-not list</h2>"); }

    test("md 080 b") { test => mdSoft(test, "- \n- b", "<ul>\n<li></li>\n<li>b</li>\n</ul>"); }

    test("md 081 head text") { test => mdSoft(test, "> # head\n> text", "<blockquote>\n<h1>head</h1>\n<p>text</p>\n</blockquote>"); }

    test("md 082 codenot lazy") { test => mdSoft(test, "    code\nnot lazy", "<pre><code>code\n</code></pre>\n<p>not lazy</p>"); }

    test("md 083 a bc d") { test => mdSoft(test, "a *b\nc* d", "<p>a <em>b\nc</em> d</p>"); }

    test("md 084 x") { test => mdSoft(test, "+++\nx", "<p>+++\nx</p>"); }

    test("md 085 Hellonbspworld mdash hellip") { test => mdSoft(test, "Hello&nbsp;world &mdash; &hellip;", "<p>Hello&nbsp;world — …</p>"); }

    test("md 086 ab c de f") { test => mdSoft(test, "[a](<b c>) [d](e f)", "<p><a href=\"b%20c\" rel=\"noopener noreferrer\">a</a> [d](e f)</p>"); }

    test("md 087 xabc yab") { test => mdSoft(test, "[x](/a(b)c) [y](/a\\)b)", "<p><a href=\"/a(b)c\" rel=\"noopener noreferrer\">x</a> <a href=\"/a)b\" rel=\"noopener noreferrer\">y</a></p>"); }

    test("md 088 auto httpsabcdef and httpsqr") { test => mdSoft(test, "auto https://a.b/c?d=e#f, and <https://q.r>.\n", "<p>auto <a href=\"https://a.b/c?d=e#f\" rel=\"noopener noreferrer\">https://a.b/c?d=e#f</a>, and <a href=\"https://q.r\" rel=\"noopener noreferrer\">https://q.r</a>.</p>"); }

    test("md 089 xfoobar yJAVASCRIPTalert zvb") { test => mdSoft(test, "[x](foo:bar) [y](JAVASCRIPT:alert) [z](vbscript:x) [w](ftp://a.b) [v](tel:123) ![i](data:image/png;base64,AAA)", "<p><a rel=\"noopener noreferrer\">x</a> <a href=\"\" rel=\"noopener noreferrer\">y</a> <a href=\"\" rel=\"noopener noreferrer\">z</a> <a href=\"ftp://a.b\" rel=\"noopener noreferrer\">w</a> <a href=\"tel:123\" rel=\"noopener noreferrer\">v</a> <img alt=\"i\"></p>"); }

    test("md 090 a1 b2 c11 one2 two") { test => mdSoft(test, "a[^1] b[^2] c[^1]\n\n[^1]: one\n[^2]: two", "<p>a<sup><a href=\"#fn-1\" rel=\"noopener noreferrer\">1</a></sup> b<sup><a href=\"#fn-2\" rel=\"noopener noreferrer\">2</a></sup> c<sup><a href=\"#fn-1\" rel=\"noopener noreferrer\">1</a></sup></p>\n\n<ol>\n<li>\n<p>one <a href=\"#fnref-1\" rel=\"noopener noreferrer\">↩</a> <a href=\"#fnref-1-2\" rel=\"noopener noreferrer\">↩<sup>2</sup></a></p>\n</li>\n<li>\n<p>two <a href=\"#fnref-2\" rel=\"noopener noreferrer\">↩</a></p>\n</li>\n</ol>"); }

    test("md 091 ax no def") { test => mdSoft(test, "a[^x] no def", "<p>a[^x] no def</p>"); }

    test("md 092 Rows   todo  more") { test => mdSoft(test, "Rows\n\n- [ ] todo\n\n  more", "<p>Rows</p>\n<ul>\n<li> \n<p>todo</p>\n<p>more</p>\n</li>\n</ul>"); }

    test("md 093 Line with spaninlinespan htm") { test => mdSoft(test, "Line with <span>inline</span> html and a <https://auto.link> too", "<p>Line with inline html and a <a href=\"https://auto.link\" rel=\"noopener noreferrer\">https://auto.link</a> too</p>"); }

    test("md 094 paradivhtml interruptdivmore") { test => mdSoft(test, "para\n<div>html interrupt</div>\nmore", "<p>para</p>"); }

    test("md 095 pxptext right after") { test => mdSoft(test, "<p>x</p>\ntext right after", ""); }

    test("md 096 customtagtext") { test => mdSoft(test, "<custom-tag>\ntext", ""); }

    test("md 097 comment after") { test => mdSoft(test, "<!-- comment -->\n\nafter", "<p>after</p>"); }

    test("md 098 quotepara quote2") { test => mdSoft(test, "> quote\n\npara\n> quote2", "<blockquote>\n<p>quote</p>\n</blockquote>\n<p>para</p>\n<blockquote>\n<p>quote2</p>\n</blockquote>"); }

    test("md 099 a  b c") { test => mdSoft(test, "- a\n  b\n- c", "<ul>\n<li>a\nb</li>\n<li>c</li>\n</ul>"); }

    test("md 100 a b") { test => mdSoft(test, "- a\n\n\n- b", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>"); }

    test("md 101 10 ten11 eleven") { test => mdSoft(test, "10. ten\n11. eleven", "<ol start=\"10\">\n<li>ten</li>\n<li>eleven</li>\n</ol>"); }

    test("md 102 1 a1 b") { test => mdSoft(test, "1. a\n1) b", "<ol>\n<li>a</li>\n</ol>\n<ol>\n<li>b</li>\n</ol>"); }

    test("md 103 a      code in item") { test => mdSoft(test, "- a\n\n      code in item", "<ul>\n<li>\n<p>a</p>\n<pre><code>code in item\n</code></pre>\n</li>\n</ul>"); }

    test("md 104 TitleText") { test => mdSoft(test, "Title\n=====\n\nText", "<h1>Title</h1>\n<p>Text</p>"); }

    test("md 105 indented heading") { test => mdSoft(test, "  # indented heading", "<h1>indented heading</h1>"); }

    test("md 106 not heading") { test => mdSoft(test, "    # not heading", "<pre><code># not heading\n</code></pre>"); }

    test("md 107 Tab heading") { test => mdSoft(test, "#\tTab heading", "<h1>Tab heading</h1>"); }

    test("md 108 blank") { test => mdSoft(test, "# \n#", "<h1></h1>\n<h1></h1>"); }

    test("md 109 a  b and    and") { test => mdSoft(test, "`a  b` and `` ` `` and ` `` `", "<p><code>a  b</code> and <code>`</code> and <code>``</code></p>"); }

    test("md 110 linebreak") { test => mdSoft(test, "`line\nbreak`", "<p><code>line break</code></p>"); }

    test("md 111 abc ab") { test => mdSoft(test, "*a*b*c* __a__b", "<p><em>a</em>b<em>c</em> __a__b</p>"); }

    test("md 112 a  b   c") { test => mdSoft(test, "_a_ _ b _ __ c __", "<p><em>a</em> _ b _ __ c __</p>"); }

    test("md 113 bold em") { test => mdSoft(test, "***bold em***", "<p><em><strong>bold em</strong></em></p>"); }

    test("md 114 ab ab") { test => mdSoft(test, "**a**__b__ *a*_b_", "<p><strong>a</strong><strong>b</strong> <em>a</em><em>b</em></p>"); }

    test("md 115 foobarbaz foobarbaz") { test => mdSoft(test, "foo*bar*baz foo_bar_baz", "<p>foo<em>bar</em>baz foo_bar_baz</p>"); }

    test("md 116 foobarbaz") { test => mdSoft(test, "*foo**bar**baz*", "<p><em>foo<strong>bar</strong>baz</em></p>"); }

    test("md 117 foobarbaz") { test => mdSoft(test, "**foo*bar*baz**", "<p><strong>foo<em>bar</em>baz</strong></p>"); }

    test("md 118 ab c") { test => mdSoft(test, "a\\\\*b* c", "<p>a\\<em>b</em> c</p>"); }

    test("md 119 au tq bu t cu p") { test => mdSoft(test, "[a](/u \"t\"q\") [b](/u 't') [c](/u (p))", "<p>[a](/u \"t\"q\") <a href=\"/u\" title=\"t\" rel=\"noopener noreferrer\">b</a> <a href=\"/u\" title=\"p\" rel=\"noopener noreferrer\">c</a></p>"); }

    test("md 120 imgipnglink") { test => mdSoft(test, "[![img](/i.png)](/link)", "<p><a href=\"/link\" rel=\"noopener noreferrer\"><img src=\"/i.png\" alt=\"img\"></a></p>"); }

    test("md 121 em cu") { test => mdSoft(test, "[*em* `c`](/u)", "<p><a href=\"/u\" rel=\"noopener noreferrer\"><em>em</em> <code>c</code></a></p>"); }

    test("md 122 em altipng") { test => mdSoft(test, "![*em* alt](/i.png)", "<p><img src=\"/i.png\" alt=\"em alt\"></p>"); }

    test("md 123 a ua and A and ba and a") { test => mdSoft(test, "[a]: /u\n\n[a] and [A] and [b][a] and [a][]", "<p><a href=\"/u\" rel=\"noopener noreferrer\">a</a> and <a href=\"/u\" rel=\"noopener noreferrer\">A</a> and <a href=\"/u\" rel=\"noopener noreferrer\">b</a> and <a href=\"/u\" rel=\"noopener noreferrer\">a</a></p>"); }

    test("md 124 ref httpxcom Titleref") { test => mdSoft(test, "[ref]: <http://x.com> 'Title'\n[ref]", "<p><a href=\"http://x.com\" title=\"Title\" rel=\"noopener noreferrer\">ref</a></p>"); }

    test("md 125 x not a link and  and") { test => mdSoft(test, "[x] not a link and [] and [ ]", "<p>[x] not a link and [] and [ ]</p>"); }

    test("md 126 blank") { test => mdSoft(test, "] [ ( ) ](", "<p>] [ ( ) ](</p>"); }

    test("md 127 smart quotes  dashes") { test => mdSoft(test, "\"smart\" 'quotes' -- dashes ...", "<p>\"smart\" 'quotes' -- dashes ...</p>"); }

    test("md 128 a   b    c") { test => mdSoft(test, "a   b    c", "<p>a   b    c</p>"); }

    test("md 129 trail") { test => mdSoft(test, "trail  \n", "<p>trail</p>"); }

    test("md 130 a   b      c") { test => mdSoft(test, "a\n   b\n      c", "<p>a\nb\nc</p>"); }

    test("md 131 a b") { test => mdSoft(test, "- a\n -b", "<ul>\n<li>a\n-b</li>\n</ul>"); }

    test("md 132 HelloBye") { test => mdSoft(test, "Hello\n\n\n```\n\n\n```\n\nBye", "<p>Hello</p>\n<pre><code>\n\n</code></pre>\n<p>Bye</p>"); }

    test("md 133 js titlexx") { test => mdSoft(test, "```js title=\"x\"\nx\n```", "<pre><code class=\"language-js\">x\n</code></pre>"); }

    test("md 134 jsx") { test => mdSoft(test, "``` js\nx\n```", "<pre><code class=\"language-js\">x\n</code></pre>"); }

    test("md 135 abx") { test => mdSoft(test, "```a`b\nx", "<p>```a`b\nx</p>"); }

    test("md 136 blank") { test => mdSoft(test, "~~~\n```\n~~~", "<pre><code>```\n</code></pre>"); }

    test("md 137 code    more") { test => mdSoft(test, "  ```\n  code\n    more\n  ```", "<pre><code>code\n  more\n</code></pre>"); }

    test("md 138 blank") { test => mdSoft(test, "```\n  \n```", "<pre><code>  \n</code></pre>"); }

    test("md 139 blank") { test => mdSoft(test, "```\n```", "<pre><code></code></pre>"); }

    test("md 140 a    c   b") { test => mdSoft(test, "- a\n  ```\n  c\n  ```\n- b", "<ul>\n<li>a\n<pre><code>c\n</code></pre>\n</li>\n<li>b</li>\n</ul>"); }

    test("md 141 c") { test => mdSoft(test, "> ```\n> c\n> ```", "<blockquote>\n<pre><code>c\n</code></pre>\n</blockquote>"); }

    test("md 142 1 a2 b    c3 d") { test => mdSoft(test, "1. a\n2. b\n\n   - c\n3. d", "<ol>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n<ul>\n<li>c</li>\n</ul>\n</li>\n<li>\n<p>d</p>\n</li>\n</ol>"); }

    test("md 143 a     b") { test => mdSoft(test, "- a\n    - b", "<ul>\n<li>a\n<ul>\n<li>b</li>\n</ul>\n</li>\n</ul>"); }

    test("md 144 a  b   c") { test => mdSoft(test, "- a\n - b\n  - c", "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n</ul>"); }

    test("md 145 wwwabcd and httpabx and see") { test => mdSoft(test, "www.a.b/c_d_ and http://a.b/(x) and (see http://a.b/c). end http://a.b/c?x=1;", "<p><a href=\"http://www.a.b/c_d\" rel=\"noopener noreferrer\">www.a.b/c_d</a>_ and <a href=\"http://a.b/(x)\" rel=\"noopener noreferrer\">http://a.b/(x)</a> and (see <a href=\"http://a.b/c\" rel=\"noopener noreferrer\">http://a.b/c</a>). end <a href=\"http://a.b/c?x=1\" rel=\"noopener noreferrer\">http://a.b/c?x=1</a>;</p>"); }

    test("md 146 contact meexamplecom or xyzz") { test => mdSoft(test, "contact me@example.com or <x@y.zz>, ok", "<p>contact <a href=\"mailto:me@example.com\" rel=\"noopener noreferrer\">me@example.com</a> or <a href=\"mailto:x@y.zz\" rel=\"noopener noreferrer\">x@y.zz</a>, ok</p>"); }

    test("md 147 xy and user and abc") { test => mdSoft(test, "x@y and @user and a.b@c", "<p>x@y and @user and a.b@c</p>"); }

    test("md 148 snowman  caf lttaggt ampamp") { test => mdSoft(test, "snowman ☃ café &lt;tag&gt; &amp;amp;", "<p>snowman ☃ café &lt;tag&gt; &amp;amp;</p>"); }

    test("md 149 a  b 3 c  d") { test => mdSoft(test, "a & b <3 c < d", "<p>a &amp; b &lt;3 c &lt; d</p>"); }

    test("md 150 a  xy") { test => mdSoft(test, "| a |\n|---|\n| `x|y` |", "<table>\n<thead>\n<tr>\n<th>a</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>`x</td>\n</tr>\n</tbody>\n</table>"); }

    test("md 151 a  b  e  lu  1  2  3") { test => mdSoft(test, "| a | b |\n|---|---|\n| *e* | [l](/u) |\n| 1 | 2 | 3 |", "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td><em>e</em></td>\n<td><a href=\"/u\" rel=\"noopener noreferrer\">l</a></td>\n</tr>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>"); }

    test("md 152 a  b      1  2 text after") { test => mdSoft(test, "| a | b |\n| - | - |\n| 1 | 2 |\ntext after\n", "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n<tr>\n<td>text after</td>\n<td></td>\n</tr>\n</tbody>\n</table>"); }

    test("md 153 a  b") { test => mdSoft(test, "| a | b |\n|---|---|", "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n</table>"); }

    test("md 154 abxy") { test => mdSoft(test, "|a|b|\n|-|-|\n|\\|x|y|", "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>|x</td>\n<td>y</td>\n</tr>\n</tbody>\n</table>"); }

    test("md 155 a b  c  1  2") { test => mdSoft(test, "a\n| b | c |\n|---|---|\n| 1 | 2 |", "<p>a</p>\n<table>\n<thead>\n<tr>\n<th>b</th>\n<th>c</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>"); }

    test("md 156 xn note with emyn") { test => mdSoft(test, "x\n\n[^n]: note with *em*\n\ny[^n]", "<p>x</p>\n<p>y<sup><a href=\"#fn-n\" rel=\"noopener noreferrer\">1</a></sup></p>\n\n<ol>\n<li>\n<p>note with <em>em</em> <a href=\"#fnref-n\" rel=\"noopener noreferrer\">↩</a></p>\n</li>\n</ol>"); }

    test("md 157 Texta andaa First para    Se") { test => mdSoft(test, "Text[^a] and[^a].\n\n[^a]: First para.\n\n    Second para.", "<p>Text<sup><a href=\"#fn-a\" rel=\"noopener noreferrer\">1</a></sup> and<sup><a href=\"#fn-a\" rel=\"noopener noreferrer\">1</a></sup>.</p>\n\n<ol>\n<li>\n<p>First para.</p>\n<p>Second para. <a href=\"#fnref-a\" rel=\"noopener noreferrer\">↩</a> <a href=\"#fnref-a-2\" rel=\"noopener noreferrer\">↩<sup>2</sup></a></p>\n</li>\n</ol>"); }

    test("md 158 a b c") { test => mdSoft(test, "- a\n- b\n\n\n- c", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>"); }

    test("md 159 q") { test => mdSoft(test, "- > q", "<ul>\n<li>\n<blockquote>\n<p>q</p>\n</blockquote>\n</li>\n</ul>"); }

    test("md 160 a  b") { test => mdSoft(test, "> - a\n>\n> - b", "<blockquote>\n<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n</blockquote>"); }

    test("md 161 12 b") { test => mdSoft(test, "1.\n2. b", "<ol>\n<li></li>\n<li>b</li>\n</ol>"); }

    test("md 162 2 a") { test => mdSoft(test, "2) a", "<ol start=\"2\">\n<li>a</li>\n</ol>"); }

    test("md 163 123456789 big1234567890 too") { test => mdSoft(test, "123456789. big\n1234567890. too big", "<ol start=\"123456789\">\n<li>big\n1234567890. too big</li>\n</ol>"); }

    test("md 164 tab item") { test => mdSoft(test, "-\ttab item", "<ul>\n<li>tab item</li>\n</ul>"); }

    test("md 165 ab") { test => mdSoft(test, "- a\n\n\tb\n", "<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ul>"); }

    test("md 166 One sentenceAnother sentence") { test => mdSoft(test, "One sentence.\nAnother sentence.\nA third.", "<p>One sentence.\nAnother sentence.\nA third.</p>"); }

    test("md 167 ThreeFour") { test => mdSoft(test, "Three.\n\u{e000}Four.\u{e001}", "<p>Three.\n\u{e000}Four.\u{e001}</p>"); }

    test("md 168 ThreeFour") { test => mdSoft(test, "Three.\nFour.", "<p>Three.\nFour.</p>"); }

    test("md 169 This is veryimportant indeed") { test => mdSoft(test, "This is *very\nimportant* indeed.", "<p>This is <em>very\nimportant</em> indeed.</p>"); }

    test("md 170 a Bc D") { test => mdSoft(test, "```\na. B.\n\nc. D.\n```", "<pre><code>a. B.\n\nc. D.\n</code></pre>"); }

    test("md 171 OneTwoThree") { test => mdSoft(test, "One.\n\u{e000}Two.\nThree.\u{e001}", "<p>One.\n\u{e000}Two.\nThree.\u{e001}</p>"); }

    test("md 172 Create a new fileelixirdefmo") { test => mdSoft(test, "Create a new file:\n\n```elixir\ndefmodule Producer do\n  use GenStage\n\n  def handle_demand(demand, state) do\n    {:noreply, [], state}\n  end\nend\n```\n\nThe consumer is in control. It's **impossible** to overwhelm it.\n\n1. First principle\n2. Second principle", "<p>Create a new file:</p>\n<pre><code class=\"language-elixir\">defmodule Producer do\n  use GenStage\n\n  def handle_demand(demand, state) do\n    {:noreply, [], state}\n  end\nend\n</code></pre>\n<p>The consumer is in control. It's <strong>impossible</strong> to overwhelm it.</p>\n<ol>\n<li>First principle</li>\n<li>Second principle</li>\n</ol>"); }

    test("md 173 Its impossible to overwhelm") { test => mdSoft(test, "\u{e000}It's **impossible** to overwhelm it\u{e001}.", "<p>\u{e000}It's <strong>impossible</strong> to overwhelm it\u{e001}.</p>"); }

    test("md 174 Prudence We must slow the pa") { test => mdSoft(test, "Prudence. \u{e000}**We must slow the pace. Progress will still seem fast.**\u{e001} Two things.", "<p>Prudence. \u{e000}**We must slow the pace. Progress will still seem fast.**\u{e001} Two things.</p>"); }

    test("md 175 Prudence We must slow the pa") { test => mdSoft(test, "Prudence. **\u{e000}We must slow the pace. Progress will still seem fast.\u{e001}** Two things.", "<p>Prudence. <strong>\u{e000}We must slow the pace. Progress will still seem fast.\u{e001}</strong> Two things.</p>"); }

    test("md 176 Before the marked words afte") { test => mdSoft(test, "Before *\u{e000}the marked words\u{e001}* after.", "<p>Before <em>\u{e000}the marked words\u{e001}</em> after.</p>"); }

    test("md 177 Before the marked words afte") { test => mdSoft(test, "Before `\u{e000}the marked words\u{e001}` after.", "<p>Before <code>\u{e000}the marked words\u{e001}</code> after.</p>"); }

    test("md 178 Some prose with  in it somew") { test => mdSoft(test, "Some prose with \u{e000}\u{e001}** in it somewhere.", "<p>Some prose with \u{e000}\u{e001}** in it somewhere.</p>"); }

    test("md 179 She had been standing at the") { test => mdSoft(test, "She had been standing at the window for an hour.", "<p>She had been standing at the window for an hour.</p>"); }

    test("md 180 The oldnew textand more") { test => mdSoft(test, "The \u{e004}old\u{e005}\u{e002}new\u{e003} text\nand more.", "<p>The \u{e004}old\u{e005}\u{e002}new\u{e003} text\nand more.</p>"); }

    test("md 181 Heres a list1 First thing2 S") { test => mdSoft(test, "Here's a list:\n\n1. **First**: thing\n2. *Second*: other\n\n- nested\n  - deeper\n\nDone.", "<p>Here's a list:</p>\n<ol>\n<li><strong>First</strong>: thing</li>\n<li><em>Second</em>: other</li>\n</ol>\n<ul>\n<li>nested\n<ul>\n<li>deeper</li>\n</ul>\n</li>\n</ul>\n<p>Done.</p>"); }

    test("md 182 TitleText right after") { test => mdSoft(test, "## Title\nText right after", "<h2>Title</h2>\n<p>Text right after</p>"); }

    test("md 183 H Line oneLine two quote line") { test => mdIs(test, "Line one\nLine two\n\n> quote line\n> another\n\n---\n\nend", "<p>Line one<br>\nLine two</p>\n<blockquote>\n<p>quote line<br>\nanother</p>\n</blockquote>\n<hr>\n<p>end</p>"); }

    test("md 184 call myfunctionname and othe") { test => mdSoft(test, "call my_function_name and other_var_x then *emph* and __init__ and _private", "<p>call my_function_name and other_var_x then <em>emph</em> and <strong>init</strong> and _private</p>"); }

    test("md 185 abc") { test => mdSoft(test, "a\r\nb\r\n\r\nc", "<p>a\nb</p>\n<p>c</p>"); }

    test("md 186 no space quotesecond") { test => mdSoft(test, ">no space quote\n>\n>second", "<blockquote>\n<p>no space quote</p>\n<p>second</p>\n</blockquote>"); }

    test("md 187 1 a2 b") { test => mdSoft(test, "1. a\n\n2. b", "<ol>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ol>"); }

    test("md 188 a b   c") { test => mdSoft(test, "- a\n- b\n\n  - c", "<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n<ul>\n<li>c</li>\n</ul>\n</li>\n</ul>"); }

    test("md 189 quotes  dash  ellipsis  bold") { test => mdSoft(test, "“quotes” — dash … ellipsis ✓ **bold** émigré *éa*", "<p>“quotes” — dash … ellipsis ✓ <strong>bold</strong> émigré <em>éa</em></p>"); }

    test("md 190 Title") { test => mdSoft(test, "Title  \n===", "<h1>Title</h1>"); }

    test("md 191 amp and  and b") { test => mdSoft(test, "`&amp;` and `\\*` and `<b>`", "<p><code>&amp;amp;</code> and <code>\\*</code> and <code>&lt;b&gt;</code></p>"); }

    test("md 192 Note text quoted parenthetic") { test => mdSoft(test, "**Note:** text, *\"quoted\"*, (*parenthetical*), **bold**, then _underscored_. a*b*c", "<p><strong>Note:</strong> text, <em>\"quoted\"</em>, (<em>parenthetical</em>), <strong>bold</strong>, then <em>underscored</em>. a<em>b</em>c</p>"); }

    test("md 193 space and space  and  a  b") { test => mdSoft(test, "** space** and **space ** and * a * b", "<p>** space** and **space ** and * a * b</p>"); }

    test("md 194 img srcx onerroralert1 after") { test => mdSoft(test, "<img src=x onerror=alert(1)> after", "<p> after</p>"); }

    test("md 195 a hrefjavascriptalert1xa and") { test => mdSoft(test, "<a href=\"javascript:alert(1)\">x</a> and <style>p{}</style>", "<p>x and p{}</p>"); }

    test("md 196 text iframe srcxiframe br en") { test => mdSoft(test, "text <iframe src=x></iframe> <br/> end", "<p>text   end</p>"); }

    test("md 197 DOCTYPE htmltext") { test => mdSoft(test, "<!DOCTYPE html>\n\ntext", "<p>text</p>"); }

    test("md 198 ascriptxscriptb") { test => mdSoft(test, "a<script>x</script>b", "<p>axb</p>"); }

    test("md 199 php echo 1 after") { test => mdSoft(test, "<?php echo 1 ?>\n\nafter", "<p>after</p>"); }

    test("md 200 x  javascriptalert1   yJavaS") { test => mdSoft(test, "[x](  javascript:alert(1)  ) [y](JavaScript:alert(1)) [z](&#106;avascript:alert(1))", "<p><a href=\"\" rel=\"noopener noreferrer\">x</a> <a href=\"\" rel=\"noopener noreferrer\">y</a> <a href=\"\" rel=\"noopener noreferrer\">z</a></p>"); }

    test("md 201 text") { test => mdSoft(test, "\n\n text \n\n", "<p>text</p>"); }

    test("md 202 blank") { test => mdSoft(test, "   \n", ""); }

    test("md 203 blank") { test => mdSoft(test, "\n", ""); }

    test("md 204 ab") { test => mdSoft(test, "a\\\\\nb", "<p>a\\\nb</p>"); }

    test("md 205 a b a  a") { test => mdSoft(test, "# a #b\n\n# a \\#\n\n## a ##   \n\n### ###", "<h1>a #b</h1>\n<h1>a #</h1>\n<h2>a</h2>\n<h3></h3>"); }

    test("md 206 1 a3 b2 c") { test => mdSoft(test, "1. a\n3. b\n2. c", "<ol>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n</ol>"); }

    test("md 207 ab c") { test => mdSoft(test, "- a\nb\n- c", "<ul>\n<li>a\nb</li>\n<li>c</li>\n</ul>"); }

    test("md 208 a  b   c") { test => mdSoft(test, "- ```\n  a\n\n  b\n  ```\n- c", "<ul>\n<li>\n<pre><code>a\n\nb\n</code></pre>\n</li>\n<li>c</li>\n</ul>"); }

    test("md 209 jsx") { test => mdSoft(test, "````\n```js\nx\n```\n````", "<pre><code>```js\nx\n```\n</code></pre>"); }

    test("md 210 item      indented code in") { test => mdSoft(test, "- item\n\n      indented code in item", "<ul>\n<li>\n<p>item</p>\n<pre><code>indented code in item\n</code></pre>\n</li>\n</ul>"); }

    test("md 211 Foo a Abar bUse foo and bar") { test => mdSoft(test, "[Foo]: /a \"A\"\n[bar]: /b\n\nUse [foo] and [bar] and [Foo][] and [x][bar] and [baz]", "<p>Use <a href=\"/a\" title=\"A\" rel=\"noopener noreferrer\">foo</a> and <a href=\"/b\" rel=\"noopener noreferrer\">bar</a> and <a href=\"/a\" title=\"A\" rel=\"noopener noreferrer\">Foo</a> and <a href=\"/b\" rel=\"noopener noreferrer\">x</a> and [baz]</p>"); }

    test("md 212 httpsexamplecomabc and httpl") { test => mdSoft(test, "https://example.com/a_(b)_c and http://localhost:3000/x and ftp://x.y/z and e.g. http://x.com/y-z.", "<p><a href=\"https://example.com/a_(b)_c\" rel=\"noopener noreferrer\">https://example.com/a_(b)_c</a> and <a href=\"http://localhost:3000/x\" rel=\"noopener noreferrer\">http://localhost:3000/x</a> and <a href=\"ftp://x.y/z\" rel=\"noopener noreferrer\">ftp://x.y/z</a> and e.g. <a href=\"http://x.com/y-z\" rel=\"noopener noreferrer\">http://x.com/y-z</a>.</p>"); }

    test("md 213 bold and em text and tri and") { test => mdSoft(test, "**bold *and em* text** and ***tri*** and ~~del *em*~~", "<p><strong>bold <em>and em</em> text</strong> and <em><strong>tri</strong></em> and <del>del <em>em</em></del></p>"); }

    test("md 214 a b c  d") { test => mdSoft(test, "`a` `b` ``c ` d``", "<p><code>a</code> <code>b</code> <code>c ` d</code></p>"); }

    test("md 215 Hello world   Next") { test => mdSoft(test, "Hello *world*\n   \nNext", "<p>Hello <em>world</em></p>\n<p>Next</p>"); }

    test("md 216 one two three") { test => mdSoft(test, "* one\n* two\n\n\n* three\n\n---", "<ul>\n<li>\n<p>one</p>\n</li>\n<li>\n<p>two</p>\n</li>\n<li>\n<p>three</p>\n</li>\n</ul>\n<hr>"); }

    test("md 217 one x two       nested") { test => mdSoft(test, "- [ ] one\n- [x] two\n    - [ ] nested", "<ul>\n<li> one</li>\n<li> two\n<ul>\n<li> nested</li>\n</ul>\n</li>\n</ul>"); }

    test("md 218 Term definition no") { test => mdSoft(test, "Term\n: definition? no", "<p>Term\n: definition? no</p>"); }

    test("md 219 A line with trailing backsla") { test => mdSoft(test, "A line with trailing backslash\\", "<p>A line with trailing backslash\\</p>"); }

    test("md 220 h1  h2  ab  c") { test => mdSoft(test, "| h1 | h2 |\n|----|----|\n| `a\\|b` | c |", "<table>\n<thead>\n<tr>\n<th>h1</th>\n<th>h2</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td><code>a|b</code></td>\n<td>c</td>\n</tr>\n</tbody>\n</table>"); }

    test("md 221 a b c") { test => mdSoft(test, "> a\n>\n> b\n\n> c", "<blockquote>\n<p>a</p>\n<p>b</p>\n</blockquote>\n<blockquote>\n<p>c</p>\n</blockquote>"); }

    test("md 222 quote  list   more  code") { test => mdSoft(test, "> quote\n> - list\n>   more\n>\n> ```\n> code\n> ```", "<blockquote>\n<p>quote</p>\n<ul>\n<li>list\nmore</li>\n</ul>\n<pre><code>code\n</code></pre>\n</blockquote>"); }

    test("md 223 Footnotenote1 and againnote1") { test => mdSoft(test, "Footnote[^note_1] and again[^note_1] and [^missing].\n\n[^note_1]: The note.", "<p>Footnote<sup><a href=\"#fn-note_1\" rel=\"noopener noreferrer\">1</a></sup> and again<sup><a href=\"#fn-note_1\" rel=\"noopener noreferrer\">1</a></sup> and [^missing].</p>\n\n<ol>\n<li>\n<p>The note. <a href=\"#fnref-note_1\" rel=\"noopener noreferrer\">↩</a> <a href=\"#fnref-note_1-2\" rel=\"noopener noreferrer\">↩<sup>2</sup></a></p>\n</li>\n</ol>"); }

    test("md 224 abpng cpng xy") { test => mdSoft(test, "![a](b.png) ![](c.png) ![x][y]", "<p><img src=\"b.png\" alt=\"a\"> <img src=\"c.png\" alt=\"\"> ![x][y]</p>"); }

    test("md 225 link with code and boldhttpx") { test => mdSoft(test, "[link with `code` and **bold**](http://x.com/a(b)?q=1&r=2#h)", "<p><a href=\"http://x.com/a(b)?q=1&amp;r=2#h\" rel=\"noopener noreferrer\">link with <code>code</code> and <strong>bold</strong></a></p>"); }

    test("md 226 ahttpxcoma b t bhttpxcom cpq") { test => mdSoft(test, "[a](<http://x.com/a b> \"t\") [b](http://x.com/ü) [c](/p?q=a b)", "<p><a href=\"http://x.com/a%20b\" title=\"t\" rel=\"noopener noreferrer\">a</a> <a href=\"http://x.com/%C3%BC\" rel=\"noopener noreferrer\">b</a> [c](/p?q=a b)</p>"); }

    test("md 227 line1line2  line3line4") { test => mdSoft(test, "line1\nline2  \nline3\\\nline4", "<p>line1\nline2<br>\nline3<br>\nline4</p>"); }

    test("md 228 Heading with trailing space") { test => mdSoft(test, "# Heading with trailing spaces   \n\ntext", "<h1>Heading with trailing spaces</h1>\n<p>text</p>"); }

    test("md 229 4 5 6") { test => mdSoft(test, "#### 4\n##### 5\n###### 6", "<h4>4</h4>\n<h5>5</h5>\n<h6>6</h6>"); }

    test("md 230 Escaped b and amp and xy and") { test => mdSoft(test, "Escaped \\<b> and \\&amp; and \\[x](y) and \\_u\\_ and 1\\. no list", "<p>Escaped &lt;b&gt; and &amp;amp; and [x](y) and _u_ and 1. no list</p>"); }

    test("md 231 1986 A great year") { test => mdSoft(test, "1986\\. A great year", "<p>1986. A great year</p>"); }

    test("md 232 plus list dash list") { test => mdSoft(test, "+ plus\n+ list\n\n- dash\n- list", "<ul>\n<li>plus</li>\n<li>list</li>\n</ul>\n<ul>\n<li>dash</li>\n<li>list</li>\n</ul>"); }

    test("md 233 Some text    not code lazy") { test => mdSoft(test, "Some text\n    not code (lazy)", "<p>Some text\nnot code (lazy)</p>"); }

    test("md 234 a   q  text") { test => mdSoft(test, "- a\n\n  > q\n\n  text", "<ul>\n<li>\n<p>a</p>\n<blockquote>\n<p>q</p>\n</blockquote>\n<p>text</p>\n</li>\n</ul>"); }

    test("md 235 blank") { test => mdSoft(test, "***\n---\n___", "<hr>\n<hr>\n<hr>"); }

    test("md 236 a  b  c and 2  3  4 and abc") { test => mdSoft(test, "a * b * c and 2 * 3 * 4 and a_b_c and a __b__ c", "<p>a * b * c and 2 * 3 * 4 and a_b_c and a <strong>b</strong> c</p>"); }

    test("md 237 italictext and textitalic an") { test => mdSoft(test, "*italic*text and text*italic* and *a*\n*b*", "<p><em>italic</em>text and text<em>italic</em> and <em>a</em>\n<em>b</em></p>"); }

    test("md 238 Bold itemBold2  item") { test => mdSoft(test, "**Bold**: item\n**Bold2** - item", "<p><strong>Bold</strong>: item\n<strong>Bold2</strong> - item</p>"); }

    test("md 239 Visit httpsxcomabcde now") { test => mdSoft(test, "Visit <https://x.com/a?b=c&d=e> now", "<p>Visit <a href=\"https://x.com/a?b=c&amp;d=e\" rel=\"noopener noreferrer\">https://x.com/a?b=c&amp;d=e</a> now</p>"); }

    test("md 240 Visit httpsxcomabcde now htt") { test => mdSoft(test, "Visit https://x.com/a?b=c&d=e now (https://y.com).", "<p>Visit <a href=\"https://x.com/a?b=c&amp;d=e\" rel=\"noopener noreferrer\">https://x.com/a?b=c&amp;d=e</a> now (<a href=\"https://y.com\" rel=\"noopener noreferrer\">https://y.com</a>).</p>"); }

    test("md 241 Is httpxcomabc ok yes wwwxco") { test => mdSoft(test, "Is http://x.com/a_b_c/ ok? yes! www.x.com/a*b* and mail@x.co.", "<p>Is <a href=\"http://x.com/a_b_c/\" rel=\"noopener noreferrer\">http://x.com/a_b_c/</a> ok? yes! <a href=\"http://www.x.com/a*b\" rel=\"noopener noreferrer\">www.x.com/a*b</a>* and <a href=\"mailto:mail@x.co\" rel=\"noopener noreferrer\">mail@x.co</a>.</p>"); }

    test("md 242 httpinnercomhttpoutercom") { test => mdSoft(test, "[http://inner.com](http://outer.com)", "<p><a href=\"http://outer.com\" rel=\"noopener noreferrer\">http://inner.com</a></p>"); }

    test("md 243 bboldbtext and i and 3 and a") { test => mdSoft(test, "<b>bold</b>text and </i> and <3 and <a b>\n", "<p>boldtext and  and &lt;3 and </p>"); }

    test("md 244 1 First   second line of fir") { test => mdSoft(test, "1. First\n   second line of first\n2. Second\n\n   Para in second\n\n   - nested a\n   - nested b\n3. Third", "<ol>\n<li>\n<p>First\nsecond line of first</p>\n</li>\n<li>\n<p>Second</p>\n<p>Para in second</p>\n<ul>\n<li>nested a</li>\n<li>nested b</li>\n</ul>\n</li>\n<li>\n<p>Third</p>\n</li>\n</ol>"); }

    test("md 245 a   b    c   d e") { test => mdSoft(test, "- a\n  - b\n\n    c\n  - d\n- e", "<ul>\n<li>a\n<ul>\n<li>\n<p>b</p>\n<p>c</p>\n</li>\n<li>\n<p>d</p>\n</li>\n</ul>\n</li>\n<li>e</li>\n</ul>"); }

    test("md 246 1 one 2 two text") { test => mdSoft(test, "> 1. one\n> 2. two\n>\n> text", "<blockquote>\n<ol>\n<li>one</li>\n<li>two</li>\n</ol>\n<p>text</p>\n</blockquote>"); }

    test("md 247 a    code   b") { test => mdSoft(test, "- a\n\n  ```\n  code\n  ```\n\n- b", "<ul>\n<li>\n<p>a</p>\n<pre><code>code\n</code></pre>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>"); }

    test("md 248 text a btext lazyafter") { test => mdSoft(test, "text\n\n- a\n- b\ntext lazy\n\nafter", "<p>text</p>\n<ul>\n<li>a</li>\n<li>b\ntext lazy</li>\n</ul>\n<p>after</p>"); }

    test("md 249 a b   continued c") { test => mdSoft(test, "- a\n- b\n   continued\n- c", "<ul>\n<li>a</li>\n<li>b\ncontinued</li>\n<li>c</li>\n</ul>"); }

    test("md 250 a    code b") { test => mdSoft(test, "* a\n\n    code?\n* b", "<ul>\n<li>\n<p>a</p>\n<p>code?</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>"); }

    test("md 251 1 a      x   2 b") { test => mdSoft(test, "1. a\n   ```\n   x\n   ```\n2. b", "<ol>\n<li>a\n<pre><code>x\n</code></pre>\n</li>\n<li>b</li>\n</ol>"); }

    test("md 252 head in item text") { test => mdSoft(test, "- # head in item\n- text", "<ul>\n<li>\n<h1>head in item</h1>\n</li>\n<li>text</li>\n</ul>"); }

    test("md 253 quote with trailing hard") { test => mdSoft(test, "> quote with trailing\\\n> hard", "<blockquote>\n<p>quote with trailing<br>\nhard</p>\n</blockquote>"); }

    test("md 254 Intro a b") { test => mdSoft(test, "Intro:\n- a\n- b", "<p>Intro:</p>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>"); }

    test("md 255 Intro1 a2 b") { test => mdSoft(test, "Intro:\n1. a\n2. b", "<p>Intro:</p>\n<ol>\n<li>a</li>\n<li>b</li>\n</ol>"); }

    test("md 256 Intro2 a3 b") { test => mdSoft(test, "Intro:\n2. a\n3. b", "<p>Intro:\n2. a\n3. b</p>"); }

    test("md 257 one  two  three four") { test => mdSoft(test, "- one\n  two\n\n  three\n- four", "<ul>\n<li>\n<p>one\ntwo</p>\n<p>three</p>\n</li>\n<li>\n<p>four</p>\n</li>\n</ul>"); }

    test("md 258 spaced marker    more") { test => mdSoft(test, "-   spaced marker\n-    more", "<ul>\n<li>spaced marker</li>\n<li>more</li>\n</ul>"); }

    test("md 259 code in item marker") { test => mdSoft(test, "-     code in item marker", "<ul>\n<li>\n<pre><code>code in item marker\n</code></pre>\n</li>\n</ul>"); }

    test("md 260 a  b") { test => mdSoft(test, "- a\n\n\n  b", "<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n</ul>"); }

    test("md 261 a b") { test => mdSoft(test, "> a\n\n\n> b", "<blockquote>\n<p>a</p>\n</blockquote>\n<blockquote>\n<p>b</p>\n</blockquote>"); }

    test("md 262 a  b") { test => mdSoft(test, "> a\n> ---\n> b", "<blockquote>\n<h2>a</h2>\n<p>b</p>\n</blockquote>"); }

    test("md 263 nested immediately   secon") { test => mdSoft(test, "- - nested immediately\n  - second", "<ul>\n<li>\n<ul>\n<li>nested immediately</li>\n<li>second</li>\n</ul>\n</li>\n</ul>"); }

    test("md 264 1 2 nested ordered") { test => mdSoft(test, "1. 2. nested ordered", "<ol>\n<li>\n<ol start=\"2\">\n<li>nested ordered</li>\n</ol>\n</li>\n</ol>"); }

    test("md 265 text on next line") { test => mdSoft(test, "- \n  text on next line", "<ul>\n<li>text on next line</li>\n</ul>"); }

    test("md 266 texttext") { test => mdSoft(test, "text\n***\ntext", "<p>text</p>\n<hr>\n<p>text</p>"); }

    test("md 267 a b") { test => mdSoft(test, "- a\n***\n- b", "<ul>\n<li>a</li>\n</ul>\n<hr>\n<ul>\n<li>b</li>\n</ul>"); }

    test("md 268 codetextmore") { test => mdSoft(test, "~~~\ncode\n~~~\ntext\n```\nmore\n```", "<pre><code>code\n</code></pre>\n<p>text</p>\n<pre><code>more\n</code></pre>"); }

    test("md 269 code trailing") { test => mdSoft(test, "```\ncode\n``` trailing", "<pre><code>code\n``` trailing</code></pre>"); }

    test("md 270 code") { test => mdSoft(test, "``` \ncode\n```", "<pre><code>code\n</code></pre>"); }

    test("md 271 indented fence") { test => mdSoft(test, "   ```\n   indented fence\n ```", "<pre><code>indented fence\n</code></pre>"); }

    test("md 272 rubyputs 1plain") { test => mdSoft(test, "```ruby\nputs 1\n```\n\n```\nplain\n```", "<pre><code class=\"language-ruby\">puts 1\n</code></pre>\n<pre><code>plain\n</code></pre>"); }

    test("md 273 ab12 list after table") { test => mdSoft(test, "|a|b|\n|-|-|\n|1|2|\n\n- list after table", "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>\n<ul>\n<li>list after table</li>\n</ul>"); }

    test("md 274 a  b  1  2  quote after") { test => mdSoft(test, "| a | b |\n|---|---|\n| 1 | 2 |\n> quote after", "<table>\n<thead>\n<tr>\n<th>a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>1</td>\n<td>2</td>\n</tr>\n</tbody>\n</table>\n<blockquote>\n<p>quote after</p>\n</blockquote>"); }

    test("md 275 Head  Head2cell  cellpara") { test => mdSoft(test, "Head | Head2\n---|---\ncell | cell\n\npara", "<table>\n<thead>\n<tr>\n<th>Head</th>\n<th>Head2</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td>cell</td>\n<td>cell</td>\n</tr>\n</tbody>\n</table>\n<p>para</p>"); }

    test("md 276 Name  Value  b  c  lu  iipn") { test => mdSoft(test, "| Name | Value |\n|:-----|------:|\n| **b** | `c` |\n| [l](/u) | ![i](/i.png) |", "<table>\n<thead>\n<tr>\n<th align=\"left\">Name</th>\n<th align=\"right\">Value</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"left\"><strong>b</strong></td>\n<td align=\"right\"><code>c</code></td>\n</tr>\n<tr>\n<td align=\"left\"><a href=\"/u\" rel=\"noopener noreferrer\">l</a></td>\n<td align=\"right\"><img src=\"/i.png\" alt=\"i\"></td>\n</tr>\n</tbody>\n</table>"); }

    test("md 277 onetwo  threefour") { test => mdSoft(test, "one\ntwo  \nthree\n\nfour", "<p>one\ntwo<br>\nthree</p>\n<p>four</p>"); }

    test("md 278 H onetwo a  b c") { test => mdIs(test, "one\ntwo\n\n- a\n  b\n- c", "<p>one<br>\ntwo</p>\n<ul>\n<li>a<br>\nb</li>\n<li>c</li>\n</ul>"); }

    test("md 279 H quote morecodelines") { test => mdIs(test, "> quote\n> more\n\n```\ncode\nlines\n```", "<blockquote>\n<p>quote<br>\nmore</p>\n</blockquote>\n<pre><code>code\nlines\n</code></pre>"); }

    test("md 280 Text with trailing colon") { test => mdSoft(test, "Text with trailing colon:\n\n    code block\n    second line\n\nAfter", "<p>Text with trailing colon:</p>\n<pre><code>code block\nsecond line\n</code></pre>\n<p>After</p>"); }

    test("md 281 First paragraph   Indented c") { test => mdSoft(test, "First paragraph.\n   Indented continuation.\n\n  Second paragraph indented.", "<p>First paragraph.\nIndented continuation.</p>\n<p>Second paragraph indented.</p>"); }

    test("md 282 Setext oneSetext twoNot sete") { test => mdSoft(test, "Setext one\n=\n\nSetext two\n--\n\nNot setext\n- -", "<h1>Setext one</h1>\n<h2>Setext two</h2>\n<p>Not setext</p>\n<ul>\n<li>\n<ul>\n<li></li>\n</ul>\n</li>\n</ul>"); }

    test("md 283 Paramore") { test => mdSoft(test, "Para\n====\nmore", "<h1>Para</h1>\n<p>more</p>"); }

    test("md 284 foobar") { test => mdSoft(test, "foo\n---\nbar\n---", "<h2>foo</h2>\n<h2>bar</h2>"); }

    test("md 285 foo bar") { test => mdSoft(test, "* foo\n---\n* bar", "<ul>\n<li>foo</li>\n</ul>\n<hr>\n<ul>\n<li>bar</li>\n</ul>"); }

    test("md 286 not heading and  not quote") { test => mdSoft(test, "\\# not heading and \\> not quote and \\- not list", "<p># not heading and &gt; not quote and - not list</p>"); }

    test("md 287 four backslashes a  end") { test => mdSoft(test, "\\\\\\\\ four backslashes \\a \\ end", "<p>\\\\ four backslashes \\a \\ end</p>"); }

    test("md 288 aampb ltigt x2603 9731 0 xD8") { test => mdSoft(test, "a&amp;b &lt;i&gt; &#x2603; &#9731; &#0; &#xD800; &nosuch; &amp", "<p>a&amp;b &lt;i&gt; ☃ ☃ � � &amp;nosuch; &amp;amp</p>"); }

    test("md 289 a u  bu  t  c   d") { test => mdSoft(test, "[a]( /u ) [b](/u  \"t\" ) [c](  ) [d](<>)", "<p><a href=\"/u\" rel=\"noopener noreferrer\">a</a> <a href=\"/u\" title=\"t\" rel=\"noopener noreferrer\">b</a> <a href=\"\" rel=\"noopener noreferrer\">c</a> <a href=\"\" rel=\"noopener noreferrer\">d</a></p>"); }

    test("md 290 au text bv and ipxq") { test => mdSoft(test, "[a](/u) text [b](/v) and ![i](/p)[x](/q)", "<p><a href=\"/u\" rel=\"noopener noreferrer\">a</a> text <a href=\"/v\" rel=\"noopener noreferrer\">b</a> and <img src=\"/p\" alt=\"i\"><a href=\"/q\" rel=\"noopener noreferrer\">x</a></p>"); }

    test("md 291 au bv cw") { test => mdSoft(test, "*[a](/u)* **[b](/v)** [*c*](/w)", "<p><em><a href=\"/u\" rel=\"noopener noreferrer\">a</a></em> <strong><a href=\"/v\" rel=\"noopener noreferrer\">b</a></strong> <a href=\"/w\" rel=\"noopener noreferrer\"><em>c</em></a></p>"); }

    test("md 292 a bu cvtitle") { test => mdSoft(test, "[a\n b](/u) [c](/v\n\"title\")", "<p><a href=\"/u\" rel=\"noopener noreferrer\">a\nb</a> <a href=\"/v\" title=\"title\" rel=\"noopener noreferrer\">c</a></p>"); }

    test("md 293 ab c db bc cd d") { test => mdSoft(test, "[a][b] [c][] [d]\n\n[b]: /b\n[c]: /c\n[d]: /d", "<p><a href=\"/b\" rel=\"noopener noreferrer\">a</a> <a href=\"/c\" rel=\"noopener noreferrer\">c</a> <a href=\"/d\" rel=\"noopener noreferrer\">d</a></p>"); }

    test("md 294 abb bb override") { test => mdSoft(test, "[a][b]\n\n[b]: /b\n[b]: /override", "<p><a href=\"/b\" rel=\"noopener noreferrer\">a</a></p>"); }

    test("md 295 Use b hereb    spaced    Tit") { test => mdSoft(test, "Use [b] here.\n\n[b]:    /spaced    \"Title Words\"\n", "<p>Use <a href=\"/spaced\" title=\"Title Words\" rel=\"noopener noreferrer\">b</a> here.</p>"); }

    test("md 296 textx notdefafterparagraphx") { test => mdSoft(test, "text\n[x]: /not-def-after-paragraph\n\n[x]", "<p>text\n[x]: /not-def-after-paragraph</p>\n<p>[x]</p>"); }

    test("md 297 ab cd e") { test => mdSoft(test, "a_b_ _c_d _e_", "<p>a_b_ _c_d <em>e</em></p>"); }

    test("md 298 a a b c  x") { test => mdSoft(test, "*a* *a *b* c* ** x **", "<p><em>a</em> <em>a <em>b</em> c</em> ** x **</p>"); }

    test("md 299 one two three four five") { test => mdSoft(test, "*one **two *three* four** five*", "<p><em>one <strong>two <em>three</em> four</strong> five</em></p>"); }

    test("md 300 a b c") { test => mdSoft(test, "__a _b_ c__", "<p><strong>a <em>b</em> c</strong></p>"); }

    test("md 301 ab c d e") { test => mdSoft(test, "~~a~~~b~~ ~~~c~~~ ~d~ ~~e", "<p><del>a~~~b</del> ~~~c~~~ <del>d</del> ~~e</p>"); }

    test("md 302 unclosed bold and unclosed e") { test => mdSoft(test, "**unclosed bold and *unclosed em", "<p>**unclosed bold and *unclosed em</p>"); }

    test("md 303 code with stars and under an") { test => mdSoft(test, "`code with *stars* and _under_` and **`bold code`**", "<p><code>code with *stars* and _under_</code> and <strong><code>bold code</code></strong></p>"); }

    test("md 305 Line ending with two spaces") { test => mdSoft(test, "Line ending with two spaces  \n", "<p>Line ending with two spaces</p>"); }

    test("md 306 a tab line") { test => mdSoft(test, "  \n\ta tab line", "<pre><code>a tab line\n</code></pre>"); }

    test("md 307 tabbed code    spaced code") { test => mdSoft(test, "\ttabbed code\n    spaced code", "<pre><code>tabbed code\nspaced code\n</code></pre>"); }

    test("md 308 a tabbed nested") { test => mdSoft(test, "- a\n\t- tabbed nested", "<ul>\n<li>a\n<ul>\n<li>tabbed nested</li>\n</ul>\n</li>\n</ul>"); }

    test("md 309 abc") { test => mdSoft(test, "a\tb\t\tc", "<p>a\tb\t\tc</p>"); }

    test("md 310 emoji  bold   httpxcom") { test => mdSoft(test, "emoji 😀 **bold 😀** `😀` [😀](http://x.com/😀)", "<p>emoji 😀 <strong>bold 😀</strong> <code>😀</code> <a href=\"http://x.com/%F0%9F%98%80\" rel=\"noopener noreferrer\">😀</a></p>"); }

    test("md 311 nonascii") { test => mdSoft(test, "non-ascii é ñ 日本語 **日本語** _日本語_ 日本語*強調*日本語", "<p>non-ascii é ñ 日本語 <strong>日本語</strong> <em>日本語</em> 日本語<em>強調</em>日本語</p>"); }

    test("md 312 a    b") { test => mdSoft(test, "  *a*  \n  *b*", "<p><em>a</em><br>\n<em>b</em></p>"); }

    test("md 313 divmd insidediv") { test => mdSoft(test, "<div>\n\n*md inside*\n\n</div>", "<p><em>md inside</em></p>"); }

    test("md 314 divnot mddivmd") { test => mdSoft(test, "<div>*not md*</div>\n*md*", ""); }

    test("md 315 prerawstill rawpremd") { test => mdSoft(test, "<pre>\nraw\n\n*still raw*\n</pre>\n\n*md*", "<p><em>md</em></p>"); }

    test("md 316 amultiline md") { test => mdSoft(test, "<!-- a\nmulti\nline -->\n*md*", "<p><em>md</em></p>"); }

    test("md 317 text  inlinecomment  more") { test => mdSoft(test, "text <!-- inline\ncomment --> more", "<p>text  more</p>"); }

    test("md 318 spanaspanspanbspan c") { test => mdSoft(test, "<span>a</span>\n\n<span>b</span> c", "<p>a</p>\n<p>b c</p>"); }

    test("md 319 tabletrtdxtdtrtableafter") { test => mdSoft(test, "<table>\n<tr><td>x</td></tr>\n</table>\nafter", ""); }

    test("md 320 beforedetailssummarySsummary") { test => mdSoft(test, "before\n\n<details>\n<summary>S</summary>\n\nBody *md*\n\n</details>\n\nafter\n", "<p>before</p>\n\n<p>Body <em>md</em></p>\n\n<p>after</p>"); }
