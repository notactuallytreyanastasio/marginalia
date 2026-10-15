# The Trace view

`trace_pane/1` (3.16), the deploy owner's: the build of the decision graph as
it happened. Refusals are kept and shown rather than hidden, because "the
server said no and the model corrected itself" is the evidence that the flow
rule and the anchoring guarantee are real and not decorative.

The events are grouped by consecutive equal narrative (`Enum.chunk_by`), each
group a labelled block of `.call` rows, `.call.no` for a refusal. While the
graph is building the frame polls (the run is under `work:<id>:`), which is
what "this fills in live" was.

    let { Ctx } = import("webcore/src");
    let { h, htext, hraw, attr } = import("html/src");
    let { sysGraphemeTake, sysJoin } = import("sys/src");
    let { GraphEvent, EventStats } = import("works/src");
    let { JsonSyntaxTree, JsonString, JsonInt, JsonNumeric, JsonBoolean, JsonNull } = import("std/json");

## Reading a call

`decode/1`: the stored text as a map, or an empty one when it is missing, does
not parse or is not an object. `showField` answers null for anything but an
object, so a tree that is not one reads as empty.

A field as the template's string interpolation prints it: a string as it is, a
number as its digits, a boolean as `true` or `false`, anything else (missing,
null, a list) as the empty string.

    let pvText(tree: JsonSyntaxTree?, key: String): String {
      let v = showField(tree, key);
      if (v is JsonString) {
        v.content
      } else if (v is JsonInt) {
        v.content.toString()
      } else if (v is JsonNumeric) {
        v.asJsonNumericToken()
      } else if (v is JsonBoolean) {
        if (v.content) { "true" } else { "false" }
      } else { "" }
    }

`if a["rationale"]`: present, and neither null nor false. The empty string is
present, so `""` prints as `()`.

    let pvTruthy(tree: JsonSyntaxTree?, key: String): Boolean {
      let v = showField(tree, key);
      if (v == null) {
        false
      } else if (v is JsonNull) {
        false
      } else { pvNotFalse(v) }
    }

    let pvNotFalse(v: JsonSyntaxTree?): Boolean {
      if (v is JsonBoolean) { v.content } else { true }
    }

The one line each call would have been at a shell prompt. An `add_node` is
"type  title" (two spaces), a `link` "from → to  (rationale)", a `set_status`
"id → status", anything else the first 160 characters of the stored arguments.

    let pvSummary(e: GraphEvent): String {
      let a = showParse(e.args);
      if (e.tool == "add_node") {
        "${pvText(a, "type")}  ${pvText(a, "title")}"
      } else if (e.tool == "link") {
        "${pvText(a, "from")} → ${pvText(a, "to")}${if (pvTruthy(a, "rationale")) { "  (${pvText(a, "rationale")})" } else { "" }}"
      } else if (e.tool == "set_status") {
        "${pvText(a, "id")} → ${pvText(a, "status")}"
      } else {
        sysGraphemeTake(showOr(e.args, ""), 160)
      }
    }

The server's answer to a refused call: the `error` field of the result, or the
first 200 characters of it.

    let pvRefusal(e: GraphEvent): String {
      let r = showParse(e.result);
      let err = showField(r, "error");
      if (err != null) {
        pvText(r, "error")
      } else {
        sysGraphemeTake(showOr(e.result, ""), 200)
      }
    }

## Grouping

    export class ShowTraceGroup(public narrative: String?, public events: List<GraphEvent>) {}

    let pvSame(a: String?, b: String?): Boolean {
      if (a != null) {
        if (b != null) { a == b } else { false }
      } else {
        b == null
      }
    }

    let pvChunks(events: List<GraphEvent>): List<ShowTraceGroup> {
      let out = new ListBuilder<ShowTraceGroup>();
      var i = 0;
      while (i < events.length) {
        let head = events[i];
        let run = new ListBuilder<GraphEvent>();
        var j = i;
        while (j < events.length && pvSame(events[j].narrative, head.narrative)) {
          run.add(events[j]);
          j += 1;
        }
        out.add(new ShowTraceGroup(head.narrative, run.toList()));
        i = j;
      }
      out.toList()
    }

## The view

    let pvCall(e: GraphEvent): List<AnyValue> {
      let why: List<AnyValue> = if (!e.ok) {
        h("span", attr("class", "why"), htext("↳ ${pvRefusal(e)}"))
      } else { [] };
      h("div", "${attr("class", if (e.ok) { "call" } else { "call no" })}${attr("id", "event-${e.id.toString()}")}", [
        h("span", attr("class", "seq"), htext(e.seq.toString())),
        h("span", attr("class", "tool"), htext(e.tool)),
        h("span", attr("class", "min-w-0 break-words"), [htext(pvSummary(e)), hraw(" "), why]),
      ])
    }

    let pvGroup(g: ShowTraceGroup): List<AnyValue> {
      let first = g.events[0];
      h("div", "${attr("class", "mt-5 first:mt-0")}${attr("id", "trace-group-${first.id.toString()}")}", [
        h("div", attr("class", "mg-label mb-1"), htext(showOr(g.narrative, ""))),
        g.events.map { (e: GraphEvent): List<AnyValue> => pvCall(e) },
      ])
    }

    let pvRefusedBadges(stats: EventStats?): List<AnyValue> {
      if (stats != null) {
        if (stats.refused > 0) {
          let refusals = stats.refusals;
          let kinds = refusals.keys().toList().sorted { (a: String, b: String): Int =>
            if (a == b) { 0 } else if (a < b) { -1 } else { 1 }
          };
          return h("div", attr("class", "mt-3 flex gap-2 flex-wrap"),
            kinds.map { (kind: String): List<AnyValue> =>
              h("span", "${attr("class", "mg-badge accent")}${attr("id", "refusal-${sysJoin(kind.split(" "), "-")}")}",
                htext("${kind} × ${refusals.getOr(kind, 0).toString()}"))
            });
        }
      }
      []
    }

    let pvCounts(stats: EventStats?): List<AnyValue> {
      if (stats != null) {
        if (stats.calls > 0) {
          return h("span", attr("class", "mg-meta"), htext("${stats.calls.toString()} tool calls · ${stats.refused.toString()} refused"));
        }
      }
      []
    }

    export let renderTraceView(ctx: Ctx, state: ShowState): List<AnyValue> {
      let slug = state.work.slug;
      let building: List<AnyValue> = if (state.graphBuilding) {
        h("span", attr("class", "text-[0.75rem] italic text-[var(--mg-dim)]"), htext("building…"))
      } else { [] };
      let body: List<AnyValue> = if (state.events.length == 0) {
        h("p", attr("class", "mg-empty mt-6"), htext("Nothing recorded yet. Build the decision graph from the Graph tab and this fills in live."))
      } else {
        h("div", attr("class", "mg-trace mt-4"),
          pvChunks(state.events).map { (g: ShowTraceGroup): List<AnyValue> => pvGroup(g) })
      };
      h("div", "", [
        h("div", attr("class", "flex items-baseline gap-3 flex-wrap"), [
          h("h2", attr("class", "mg-label"), htext("Build trace")),
          pvCounts(state.eventStats),
          h("div", attr("class", "ml-auto flex gap-2 items-baseline"), [
            building,
            h("a", "${attr("href", "/works/${slug}/trace.json")}${attr("class", "mg-btn sm ghost")}", htext("trace.json")),
          ]),
        ]),
        h("p", attr("class", "mg-hint mt-2 max-w-[68ch]"), [
          htext("Every call the model made to "),
          h("code", "", htext("add_node")),
          htext(", "),
          h("code", "", htext("link")),
          htext(" and "),
          h("code", "", htext("set_status")),
          htext(" — the deciduous CLI, handed over as functions — and what the server answered. Red lines are refusals: a quote that was not in your draft, or a link that broke "),
          h("code", "", htext("goal → option → decision → action → outcome")),
          htext("."),
        ]),
        pvRefusedBadges(state.eventStats),
        body,
      ])
    }
