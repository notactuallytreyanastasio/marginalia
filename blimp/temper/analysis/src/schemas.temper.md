# Tool schemas

The JSON Schema of each tool the model is handed, as the Elixir maps spelled
them, written out as JSON text (an `LlmTool` carries its parameters as text and
the client embeds them parsed).

`@beats_tool` parameters (`record_beats`).

    export let analysisBeatsToolParameters(): String {
      "{\"type\":\"object\",\"properties\":{\"beats\":{\"type\":\"array\",\"description\":\"In document order. Merge beats that belong to the same move.\",\"items\":{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\",\"description\":\"The move, as something the writer does. Under 90 characters.\"},\"note\":{\"type\":\"string\",\"description\":\"What it does to a reader, and what it sets up or pays off.\"},\"quote\":{\"type\":\"string\",\"description\":\"8 to 40 words, verbatim from the section. Verified server-side.\"}},\"required\":[\"title\",\"note\",\"quote\"]}}},\"required\":[\"beats\"]}"
    }

`add_node` parameters.

    export let decisionGraphAddNodeParameters(): String {
      "{\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"enum\":[\"goal\",\"decision\",\"option\",\"observation\",\"action\",\"outcome\",\"revisit\"]},\"title\":{\"type\":\"string\",\"description\":\"One clear line, under 100 characters.\"},\"description\":{\"type\":\"string\",\"description\":\"Why this exists and what prompted it. 1-3 sentences.\"},\"quote\":{\"type\":\"string\",\"description\":\"A verbatim span from the draft, copied exactly. Verified server-side; the node is rejected if it is not found.\"},\"section\":{\"type\":\"integer\",\"description\":\"Section number this belongs to, if any.\"},\"narrative\":{\"type\":\"string\",\"description\":\"Which narrative this node belongs to.\"}},\"required\":[\"type\",\"title\",\"narrative\"]}"
    }

`link` parameters.

    export let decisionGraphLinkParameters(): String {
      "{\"type\":\"object\",\"properties\":{\"from\":{\"type\":\"integer\"},\"to\":{\"type\":\"integer\"},\"rationale\":{\"type\":\"string\",\"description\":\"Why this led to that.\"}},\"required\":[\"from\",\"to\"]}"
    }

`set_status` parameters.

    export let decisionGraphSetStatusParameters(): String {
      "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\"},\"status\":{\"type\":\"string\",\"enum\":[\"chosen\",\"rejected\",\"superseded\"]}},\"required\":[\"id\",\"status\"]}"
    }
