# Events of the other views (none yet)

OWNED BY THE VIEWS AGENT: replace this file if a view needs an event of its
own. Every event the LiveView had is already answered somewhere (see the table
in `events.temper.md`): the Graph and Trace tabs' buttons are `build_graph` and
`start_read`, and a node's Discuss button is `discuss_node`, which is the chat
drawer's. Add the names of any new event to `showViewEventNames()` and answer
them in `showViewEvent`.

    let { Ctx } = import("webcore/src");
    let { JsonObject } = import("std/json");

    export let showViewEventNames(): List<String> { [] }

    export let showViewEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      console.log("TODO pages_show views: event ${event} is the views agent's (view_events.temper.md)");
      bubble()
    }
