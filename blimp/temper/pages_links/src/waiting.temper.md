# The waiting view

`MarginaliaWeb.LinkWaiting.waiting/1`. What the pair page shows instead of the
two documents while the pass runs (`pending`, `linking`) or after it failed:
both maps as two columns of real nodes, with arcs tried between them by the
`Wiring` hook. The arcs say on the page that they are attempts and not
findings. The page polls while it is up, so it fills in on its own.

    let { h, hv, htext, hraw, attr } = import("html/src");
    let { JsonTextProducer, NullInterchangeContext } = import("std/json");

## The dots

At most 24 a side, evenly sampled: dot `i` of `n` titles is title
`trunc(i * n / 24)`.

    export let pagesLinksDots(titles: List<String>): List<String> {
      let n = titles.length;
      if (n <= 24) { return titles; }
      let out = new ListBuilder<String>();
      var i = 0;
      while (i < 24) {
        out.add(titles[(i * n) / 24]);
        i += 1;
      }
      out.toList()
    }

`y(i, n) = 30 + i * (300 / max(n - 1, 1))`, which the hook mirrors to land its
arcs on the same coordinates.

    export let pagesLinksDotY(i: Int, n: Int): String {
      let steps = if (n - 1 > 1) { n - 1 } else { 1 };
      let gap = (300.0 / steps.toFloat64()) orelse 0.0;
      pagesLinksOneDecimal(30.0 + i.toFloat64() * gap)
    }

    let plTitlesJson(titles: List<String>): String throws Bubble {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startArray();
      for (let t of titles) { p.stringValue(t); }
      p.endArray();
      p.toJsonString()
    }

One column of dots. The animation delay is `i * 45` ms.

    let plDotColumn(side: String, cx: String, dots: List<String>): List<AnyValue> {
      var i = 0;
      let out = new ListBuilder<List<AnyValue>>();
      while (i < dots.length) {
        out.add(h("circle", "${attr("cx", cx)}${attr("cy", pagesLinksDotY(i, dots.length))}${attr("r", "3.5")}${attr("data-side", side)}${attr("data-i", i.toString())}${attr("style", "animation-delay:${(i * 45).toString()}ms")}", []));
        i += 1;
      }
      out.toList()
    }

## The component

`aTitle` and `bTitle` are the lead and the other draft; `aNodes` and `bNodes`
the titles of their beats.

    export let renderLinkWaiting(
      aTitle: String, bTitle: String, aNodes: List<String>, bNodes: List<String>,
      status: String, error: String?,
    ): List<AnyValue> throws Bubble {
      if (status == "failed") {
        return h("div", attr("class", "lw"), [
          "\n",
          h("h2", "", htext("That did not go through")),
          "\n",
          h("p", attr("class", "why"), htext(if (error != null) { error } else { "" })),
          "\n",
          h("button", "${attr("class", "mg-btn sm")}${attr("phx-click", "relink")}", htext("Try again")),
          "\n",
        ]);
      }
      let pairs = aNodes.length * bNodes.length;
      let aDots = pagesLinksDots(aNodes);
      let bDots = pagesLinksDots(bNodes);
      h("div", attr("class", "lw"), [
        "\n",
        h("div", attr("class", "lw-head"), [
          "\n",
          h("span", attr("class", "mg-label"), htext("relating")),
          "\n",
          h("h2", "", [
            htext("${aTitle} "),
            h("span", attr("class", "x"), htext("↔")),
            htext(" ${bTitle}"),
          ]),
          "\n",
          h("p", attr("class", "why"), htext(
            "\nReading both maps against each other — ${aNodes.length.toString()} nodes on one side, ${bNodes.length.toString()} on the other, ${pairs.toString()} possible pairs. A minute or two.\nThis page fills in on its own.\n",
          )),
          "\n",
        ]),
        "\n",
        h("div", "${attr("class", "lw-stage")}${attr("id", "wiring")}${attr("phx-hook", "Wiring")}${attr("data-a", plTitlesJson(aDots))}${attr("data-b", plTitlesJson(bDots))}", [
          "\n",
          h("svg", "${attr("class", "lw-svg")}${attr("viewBox", "0 0 680 360")}${attr("preserveAspectRatio", "xMidYMid meet")}", [
            h("g", attr("class", "arcs"), []),
            h("g", attr("class", "dots"), [
              plDotColumn("a", "90", aDots),
              plDotColumn("b", "590", bDots),
            ]),
          ]),
          "\n",
          h("p", attr("class", "lw-now"), [
            h("span", attr("class", "l"), []),
            "\n",
            h("span", "${attr("class", "arrow")}${attr("aria-hidden", "true")}", htext("⇢")),
            "\n",
            h("span", attr("class", "r"), []),
          ]),
          "\n",
          h("p", attr("class", "lw-fine"), htext(
            "\nThe nodes are yours. The lines are the pass trying pairs — none of them are\nfindings yet, and they all fade. What it actually decides arrives at the end.\n",
          )),
          "\n",
        ]),
        "\n",
      ])
    }
