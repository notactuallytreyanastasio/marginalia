# Events of the other views (none)

The six views have no event of their own. Every control the LiveView drew on
them is answered elsewhere (see the table in `events.temper.md`): the tabs and
the help button are navigation, the Graph tab's Build button is `build_graph`
and the Trace tab's retry is `start_read` (`events_read.temper.md`), and a
node's Discuss button is `discuss_node`, the chat drawer's (`chat.temper.md`).
The Changes, Prompts and Trace tabs only show things; Spine and Threads only
carry the Discuss button.

A view that grows an event adds its name to `showViewEventNames()` and answers
it in `showViewEvent`. Until then an event addressed here is a crash with its
name in the log, which is better than an answer that looks like success.

    let { Ctx } = import("webcore/src");
    let { JsonObject } = import("std/json");

    export let showViewEventNames(): List<String> { [] }

    export let showViewEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      console.log("pages_show views: no view has an event, but ${event} was sent here (view_events.temper.md)");
      bubble()
    }
