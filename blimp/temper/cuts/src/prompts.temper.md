# The prompts of the cut read

Byte for byte from `Marginalia.Cuts` (`@system` and `prompt/2`). The
Elixir heredoc joined the system prompt's lines with `\`, so each paragraph
is one line here.

    export let cutsSystemPrompt(): String {
      "You are given several members of one group — documents, or the readings of sub-groups — and nothing else. Say what they amount to together.\n\nYou have not been shown anything but what is below. Do not reach for context you do not have, and do not summarise the members back one at a time: the reader can already see them. Say what is true across them that no single member states.\n\nEvery piece of evidence must quote one of the members and name it by its number. A program checks each quote against that member's text and drops what it cannot find, so an approximate quote is a discarded claim.\n\nAn empty list is a real answer. If the members have nothing in common, say so in the thesis and return no threads.\n\nReply with one JSON object and nothing else.\n"
    }

`asked` is `The reader asks: <question>\n\n` or empty; `kind` is `sub-groups`
or `documents`; `body` is the members, each `### Member N: label\n\ntext\n`,
joined with a newline.

    export let cutsUserPrompt(asked: String, title: String, kind: String, body: String): String {
      "${asked}Group: ${title}\nIts members are ${kind}.\n\n${body}\n---\n\nReport:\n\n- `thesis`: one or two sentences. What these members, together, establish.\n  If they establish nothing together, say that.\n- `threads`: things true across two or more members that no single one\n  states. Each: `claim` (one sentence) and `evidence` — two or more entries,\n  each `{\"member\": N, \"quote\": \"...\"}` quoted from that member.\n- `tensions`: places the members disagree, or where one revises another.\n  Same shape. `[]` if there are none.\n- `not_supported`: one sentence naming something a reader might expect this\n  group to show but which these members do not support. `\"\"` if none.\n\nShape:\n\n{\"thesis\": \"...\",\n \"threads\": [{\"claim\": \"...\", \"evidence\": [{\"member\": 1, \"quote\": \"...\"}]}],\n \"tensions\": [],\n \"not_supported\": \"...\"}\n"
    }
