# Events: the read, the graph, the backend, linking

`start_read`, `build_graph`, `set_provider`, `link_to`. The first two start a
job that outlives the request (`launch.temper.md`); the page learns how it is
going from the `runs` row.

    let { Ctx } = import("webcore/src");
    let { JsonObject } = import("std/json");
    let { Work, worksResetRead, worksSetStatus, worksFindWork } = import("works/src");
    let { accountsSetLlmProvider, accountsProviderFor } = import("accounts/src");
    let { runsRunning } = import("runs/src");
    let { Db } = import("db/src");
    let { Link, linksGetOrCreate, linksSetStatus, linksAttrsError } = import("links/src");

    export let showReadEvents(): List<String> {
      ["start_read", "build_graph", "set_provider", "link_to"]
    }

## Reading the draft

`start_read` (Read it, Read again; the owner's, guarded). A draft already read
is thrown away first (every node, edge and trace row, every section back to
pending); a read that failed part-way is not, as in the Elixir, so a retry
after a crash stacks a second set of nodes. The work is marked `reading` before
the job is forked, so the page that answers this very request shows the
progress and not the button. A read already going is left alone.

There is no quota or key check here, as there was none: the button is not
offered without a key.

    let psStartRead(ctx: Ctx, state: ShowState, launcher: ShowLauncher): ShowOutcome throws Bubble {
      let key = showReadKey(state.work.id);
      if (runsRunning(ctx.db, key)) { return showDone(); }
      if (state.work.status == "read") { worksResetRead(ctx.db, state.work.id); }
      let marked = worksSetStatus(ctx.db, state.work, "reading", null);
      state.work = marked;
      let provider = state.provider;
      let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
        showJobRead(own, launcher.llm(provider), marked, key)
      };
      if (started) { showMarkLaunched(ctx, marked, key); }
      showDone()
    }

## The decision graph

`build_graph`: the pass that builds goal, option, decision, action and outcome
nodes over the read, with the model's tool calls recorded in the trace. The
page shows "building" while its run is going.

    let psBuildGraph(ctx: Ctx, state: ShowState, launcher: ShowLauncher): ShowOutcome throws Bubble {
      let key = showGraphKey(state.work.id);
      if (runsRunning(ctx.db, key)) { return showDone(); }
      let work = state.work;
      let provider = state.provider;
      let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
        showJobGraph(own, launcher.llm(provider), work, key)
      };
      if (started) {
        showMarkLaunched(ctx, work, key);
        state.graphBuilding = true;
        state.events = [];
        state.eventStats = null;
      }
      showDone()
    }

## The backend

`set_provider`: the deploy's owner chooses which model their work runs
against. For anyone else it is a silent no-op that leaves the account alone.
An unknown name changes nothing.

    let psSetProvider(ctx: Ctx, state: ShowState, payload: JsonObject): ShowOutcome throws Bubble {
      let user = state.user;
      if (user != null) {
        let r = accountsSetLlmProvider(ctx.db, user, showPayloadStr(payload, "provider"));
        let updated = r.ok;
        if (updated != null) {
          let now = accountsProviderFor(updated);
          state.provider = now;
          state.llmReady = showKeyConfigured(now);
          showInfo("Backend: ${showOr(now, "deploy default")}")
        } else {
          showDone()
        }
      } else {
        showDone()
      }
    }

## Linking

`link_to`: relate this draft to another of the writer's own, read draft. The
pass that reads the pair is started if the link is not already being read, and
the page goes to the pair. Any failure is `That draft can't be linked.`

    let psCannotLink(): ShowOutcome { showError("That draft can't be linked.") }

    let psLinkRead(ctx: Ctx, state: ShowState, link: Link, launcher: ShowLauncher): ShowOutcome throws Bubble {
      if (link.status != "linking") {
        let key = showLinkKey(link.id);
        if (!runsRunning(ctx.db, key)) {
          linksSetStatus(ctx.db, link, "linking", linksAttrsError(null));
          let provider = state.provider;
          let linkId = link.id;
          let started = launcher.start(ctx, key) { (own: Db): Void throws Bubble =>
            showJobLink(own, launcher.llm(provider), linkId)
          };
        }
      }
      state.linking = false;
      showGoing("/links/${link.id.toString()}?lead=${state.work.slug}")
    }

    let psLinkWith(ctx: Ctx, state: ShowState, other: Work, launcher: ShowLauncher): ShowOutcome throws Bubble {
      let link = linksGetOrCreate(ctx.db, state.work.id, other.id).ok;
      if (link != null) { psLinkRead(ctx, state, link, launcher) } else { psCannotLink() }
    }

    let psLinkTo(ctx: Ctx, state: ShowState, payload: JsonObject, launcher: ShowLauncher): ShowOutcome throws Bubble {
      let id = showPayloadInt(payload, "id");
      if (id != null) {
        let other = worksFindWork(ctx.db, ctx.scope, id);
        if (other != null) { psLinkWith(ctx, state, other, launcher) } else { psCannotLink() }
      } else {
        psCannotLink()
      }
    }

    export let showReadEvent(
      ctx: Ctx, state: ShowState, event: String, payload: JsonObject, launcher: ShowLauncher,
    ): ShowOutcome throws Bubble {
      if (event == "start_read") {
        psStartRead(ctx, state, launcher)
      } else if (event == "build_graph") {
        psBuildGraph(ctx, state, launcher)
      } else if (event == "set_provider") {
        psSetProvider(ctx, state, payload)
      } else if (!state.mine) {
        showError(showDeniedPlain())
      } else {
        psLinkTo(ctx, state, payload, launcher)
      }
    }
