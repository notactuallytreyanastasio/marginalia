# The Prompts view

`prompts_pane/1` (3.17), the deploy owner's: the exact prompts that ran against
the draft, read out of the running code rather than retyped, so this page
cannot drift from what actually happened. For each pass its name, model, the
cadence and what it produces, and the full prompt in a `<pre>`; then each
chat stance, appended last to the one system prompt every conversation
carries.

    let { Ctx } = import("webcore/src");
    let { h, htext, attr } = import("html/src");
    let { AnalysisPass } = import("analysis/src");
    let { ChatMode } = import("chat/src");

    let pvPre(text: String): List<AnyValue> {
      h("pre", attr("class", "mt-2.5 text-[0.74rem] leading-relaxed whitespace-pre-wrap bg-[var(--mg-margin)] border border-[var(--mg-rule)] rounded-sm p-3.5 overflow-x-auto max-w-[80ch]"), htext(text))
    }

    let pvPass(p: AnalysisPass): List<AnyValue> {
      h("div", "${attr("class", "mt-6")}${attr("id", "pass-${p.id}")}", [
        h("div", attr("class", "flex items-baseline gap-2 flex-wrap"), [
          h("h3", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "font-semibold text-[1.05rem]")}", htext(p.name)),
          h("span", attr("class", "mg-meta"), htext(p.model)),
        ]),
        h("div", attr("class", "mg-hint mt-0.5"), htext("${p.runs} · produces ${p.produces}")),
        pvPre(p.prompt),
      ])
    }

    let pvMode(m: ChatMode): List<AnyValue> {
      h("div", "${attr("class", "mt-5")}${attr("id", "mode-${m.id}")}", [
        h("h3", "${attr("style", "font-family:var(--mg-serif)")}${attr("class", "font-semibold text-[1.05rem]")}", [
          htext("${m.label} "),
          h("span", attr("class", "font-normal text-[var(--mg-dim)]"), htext("— ${m.blurb}")),
        ]),
        pvPre(m.stance),
      ])
    }

    export let renderPromptsView(ctx: Ctx, state: ShowState): List<AnyValue> {
      h("div", "", [
        h("h2", attr("class", "mg-label"), htext("How the graph was built")),
        h("p", attr("class", "mt-2 text-xs opacity-60 max-w-prose"),
          htext("The exact prompts that ran against your draft, read out of the running code rather than retyped here — so this page cannot drift from what actually happened.")),
        state.passes.map { (p: AnalysisPass): List<AnyValue> => pvPass(p) },
        h("h2", attr("class", "mg-label mt-12"), htext("How the chat is steered")),
        h("p", attr("class", "mt-2 text-xs opacity-60 max-w-prose"),
          htext("Every conversation carries the same system prompt; the stance below is appended last, depending on which mode you are in.")),
        state.modes.map { (m: ChatMode): List<AnyValue> => pvMode(m) },
      ])
    }
