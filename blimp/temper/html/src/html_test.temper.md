# html tests

Escaping, attributes, the nested-list tree and `classes`. Every check is inside a
helper that takes the `test` (see `testing.temper.md`).

## esc

    let escIs(test: Test, input: String, want: String): Void {
      expectText(test, esc(input), want);
    }

    test("esc: ampersand") { test => escIs(test, "a & b", "a &amp; b"); }
    test("esc: less-than") { test => escIs(test, "1 < 2", "1 &lt; 2"); }
    test("esc: greater-than") { test => escIs(test, "2 > 1", "2 &gt; 1"); }
    test("esc: double quote") { test => escIs(test, "say \"hi\"", "say &quot;hi&quot;"); }
    test("esc: single quote") { test => escIs(test, "it's", "it&#39;s"); }
    test("esc: all five at once") { test => escIs(test, "&<>\"'", "&amp;&lt;&gt;&quot;&#39;"); }
    test("esc: ampersand first, so entities are not escaped twice over") { test =>
      escIs(test, "&lt;", "&amp;lt;");
    }
    test("esc: empty") { test => escIs(test, "", ""); }
    test("esc: plain text is untouched") { test => escIs(test, "plain words, 123.", "plain words, 123."); }
    test("esc: non-ASCII is untouched") { test => escIs(test, "caf\u{e9} \u{2603} \u{1f600}", "caf\u{e9} \u{2603} \u{1f600}"); }
    test("esc: a tag") { test =>
      escIs(test, "<script>alert('x')</script>", "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;");
    }

## attr

    let attrIs(test: Test, name: String, value: String?, want: String): Void {
      expectText(test, attr(name, value), want);
    }

    test("attr: null is nothing") { test => attrIs(test, "class", null, ""); }
    test("attr: a value") { test => attrIs(test, "class", "btn", " class=\"btn\""); }
    test("attr: the value is escaped") { test =>
      attrIs(test, "title", "a \"b\" & <c>", " title=\"a &quot;b&quot; &amp; &lt;c&gt;\"");
    }
    test("attr: an empty string is still an attribute") { test => attrIs(test, "alt", "", " alt=\"\""); }

## The tree

    let treeIs(test: Test, tree: List<AnyValue>, want: String): Void {
      expectText(test, hjoin(tree), want);
    }

    test("tree: htext escapes") { test => treeIs(test, htext("a < b"), "a &lt; b"); }
    test("tree: hraw does not") { test => treeIs(test, hraw("<b>x</b>"), "<b>x</b>"); }
    test("tree: hv is a void element") { test => treeIs(test, hv("br", ""), "<br>"); }
    test("tree: hv with attributes") { test =>
      treeIs(test, hv("img", "${attr("src", "/a.png")}${attr("alt", null)}"), "<img src=\"/a.png\">");
    }
    test("tree: h with no children") { test => treeIs(test, h("p", "", []), "<p></p>"); }
    test("tree: h with attributes and text") { test =>
      treeIs(test, h("a", attr("href", "/x?a=1&b=2"), [htext("go")]), "<a href=\"/x?a=1&amp;b=2\">go</a>");
    }
    test("tree: nested h") { test =>
      treeIs(test, h("ul", "", [h("li", "", [htext("one")]), h("li", "", [htext("two")])]),
        "<ul><li>one</li><li>two</li></ul>");
    }
    test("tree: a list inside the children is flattened") { test =>
      let inner: List<AnyValue> = [hraw("<i>"), htext("x&y"), hraw("</i>")];
      treeIs(test, h("p", "", [inner, [[htext("!")]]]), "<p><i>x&amp;y</i>!</p>");
    }
    test("tree: five levels deep") { test =>
      treeIs(test, h("a", "", [h("b", "", [h("c", "", [h("d", "", [h("e", "", [htext("z")])])])])]),
        "<a><b><c><d><e>z</e></d></c></b></a>");
    }
    test("tree: empty") { test => treeIs(test, [], ""); }
    test("tree: empty lists vanish") { test => treeIs(test, [[], [[]], hraw("x"), []], "x"); }
    test("tree: order is kept") { test => treeIs(test, [hraw("1"), [hraw("2"), [hraw("3")], hraw("4")], hraw("5")], "12345"); }
    test("tree: a text node that holds markup is escaped, not raw") { test =>
      treeIs(test, h("p", "", [htext("<script>")]), "<p>&lt;script&gt;</p>");
    }

## classes

    let classesIs(test: Test, a: String?, b: String?, c: String?, want: String): Void {
      expectText(test, classes([a, b, c]), want);
    }

    test("classes: all present") { test => classesIs(test, "a", "b", "c", "a b c"); }
    test("classes: nulls are dropped") { test => classesIs(test, "a", null, "c", "a c"); }
    test("classes: all null") { test => classesIs(test, null, null, null, ""); }
    test("classes: one") { test => classesIs(test, null, "only", null, "only"); }
    test("classes: empty strings are dropped too") { test => classesIs(test, "a", "", "b", "a b"); }
    test("classes: empty list") { test => expectText(test, classes([]), ""); }

## The 20,000-leaf timing

200 rows of 100 leaves each, joined once. The elapsed time is printed.

    let commas(n: Int): String {
      let sb = new StringBuilder();
      for (var i = 0; i < n; i += 1) { sb.append("x,"); }
      sb.toString()
    }

    let bigTree(test: Test): List<AnyValue> {
      let leaves = commas(100).split(",");
      let rows = commas(200).split(",");
      let kids: List<AnyValue> = [leaves];
      let one = h("li", "", kids);
      let items = rows.map { (w): List<AnyValue> => one };
      [h("ul", "", items)]
    }

    let timing(test: Test): Void {
      let t0 = htmlNowMs();
      let out = hjoin(bigTree(test));
      let t1 = htmlNowMs();
      console.log("hjoin of ${201 * 100} leaves: ${t1 - t0} ms, ${out.countBetween(String.begin, out.end)} chars");
      expectInt(test, out.split("<li>").length, 202);
    }

    test("hjoin of twenty thousand leaves") { test => timing(test); }
