# The Changes view

`changes_pane/1` (3.9): the draft as it arrived beside the draft as it is. Two
columns rather than one marked-up copy, because a writer comparing versions is
asking "what did I have before", and an inline diff answers a different
question. The split view is `renderDiffTable` (`components.temper.md`), which
the read view draws too; the log under it prints each revision's word diff in
the new column's marks.

The Elixir tab is reachable on an untouched draft by its address, and says so
rather than erroring: "Nothing has changed yet."

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");
    let { Revision } = import("works/src");

## The log

`{rev.origin}{if rev.note, do: " — #{rev.note}"} · section {rev.section_ordinal}`.
A revision with no section ordinal prints the empty string after "section ".

    let pvRevisionLabel(rev: Revision): String {
      let note = rev.note;
      let ordinal = rev.sectionOrdinal;
      "${rev.origin}${if (note != null) { " — ${note}" } else { "" }} · section ${if (ordinal != null) { ordinal.toString() } else { "" }}"
    }

    let pvLog(state: ShowState): List<AnyValue> {
      if (state.revisions.length == 0) { return []; }
      h("div", attr("class", "mg-diff-log"), [
        h("div", attr("class", "mg-label"), htext("Every change, newest first")),
        h("ol", attr("class", "mg-rows"),
          state.revisions.map { (rev: Revision): List<AnyValue> =>
            h("li", attr("id", "rev-${rev.id.toString()}"), [
              h("span", attr("class", "n"), htext(rev.seq.toString())),
              h("span", attr("class", "mg-meta"), htext(pvRevisionLabel(rev))),
              h("div", attr("class", "mg-diff-patch"), renderWordSpans(rev.before, rev.after, "new")),
            ])
          }),
      ])
    }

## The view

    export let renderChangesView(ctx: Ctx, state: ShowState): List<AnyValue> {
      let stat = state.diffStat;
      let counts: List<AnyValue> = if (stat != null) {
        h("span", attr("class", "mg-meta ml-auto"),
          htext("${stat.changed.toString()} edited · ${stat.added.toString()} added · ${stat.removed.toString()} removed"))
      } else { [] };
      let any = showAnyChange(state.diffRows);
      let table: List<AnyValue> = if (any) {
        renderDiffTable(state.diffRows, "As it arrived", "Now", false)
      } else {
        h("p", attr("class", "mg-empty"), htext("Nothing has changed yet. Edits and applied rewrites show up here."))
      };
      h("div", attr("class", "mg-diff"), [
        h("div", attr("class", "mg-diff-head"), [
          h("span", attr("class", "mg-label"), htext("Changes since it arrived")),
          counts,
        ]),
        table,
        pvLog(state),
      ])
    }
