# Pieces more than one view draws

The side-by-side diff (`diff_table/1`) is drawn by the read view (the applied
change, a stale summary's drift) and by the Changes tab. It lives here so the
views agree on it, and so does the word diff the revision log prints.

    let { Row, Part, diff } = import("core/src");
    let { h, hv, htext, hraw, attr } = import("html/src");

## The word diff

`word_class/2`: the old column shows what was removed and hides what replaced
it; the new column does the reverse. Showing both marks in both columns is how
an inline diff reads, and this is not one.

    export let showWordClass(kind: String, side: String): String {
      if (kind == "same") {
        "w"
      } else if (kind == "del") {
        if (side == "old") { "w del" } else { "w hide" }
      } else {
        if (side == "old") { "w hide" } else { "w ins" }
      }
    }

One column of a word diff: a span per part, in the column's class.

    export let renderWordSpans(before: String, after: String, side: String): List<AnyValue> {
      diff(before, after).map { (p: Part): List<AnyValue> =>
        h("span", attr("class", showWordClass(p.kind, side)), htext(p.text))
      }
    }

## The split view

Two columns, GitHub's split view: what was there on the left with the removed
words struck through in red, what is there now on the right with the added
words in green. The counterpart's marks are hidden in each column. `compact`
adds the class that tightens it under a summary or a paragraph.

    let psSide(cls: String, inner: List<AnyValue>): List<AnyValue> {
      h("div", attr("class", cls), inner)
    }

    let psDiffRow(row: Row): List<AnyValue> {
      let left = showOr(row.left, "");
      let right = showOr(row.right, "");
      let body: List<AnyValue> = if (row.kind == "same") {
        [psSide("side old", htext(left)), "\n", psSide("side new", htext(left))]
      } else if (row.kind == "change") {
        [
          psSide("side old", renderWordSpans(left, right, "old")), "\n",
          psSide("side new", renderWordSpans(left, right, "new")),
        ]
      } else if (row.kind == "del") {
        [psSide("side old gone", htext(left)), "\n", psSide("side new empty", [])]
      } else {
        [psSide("side old empty", []), "\n", psSide("side new fresh", htext(right))]
      };
      h("div", attr("class", "mg-diff-row ${row.kind}"), ["\n", body, "\n"])
    }

    export let renderDiffTable(rows: List<Row>, left: String, right: String, compact: Boolean): List<AnyValue> {
      h("div", attr("class", if (compact) { "mg-diff-cols compact" } else { "mg-diff-cols" }), [
        "\n",
        h("div", attr("class", "mg-diff-colhead"), [h("span", "", htext(left)), h("span", "", htext(right))]),
        "\n",
        rows.map { (r: Row): List<AnyValue> => [psDiffRow(r), "\n"] },
      ])
    }

## Ids

Element ids are what the client morphs by. A list item gets a stable one even
where the HEEx relied on position.

    export let showId(prefix: String, n: Int): String { "${prefix}-${n.toString()}" }
