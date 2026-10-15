# March, read for what Blimp can take

March's value to Blimp is in how it handles failure at run time and in how its team keeps docs and error messages honest. It is not in the type system or the memory manager, which is where the site spends its words. A supervisor with a restart budget, a call that has a deadline, a bubble that carries its reason, a sandbox cut from declared grants, a read-only observe socket: each of those fits a single-threaded tree-walking interpreter and fits Blimp's vocabulary. Perceus, FBIP, refinement types and the 19x benchmark do not transfer, and the benchmark and the "typed" actor claim do not survive reading the source (section 6).

Method. Read-only. I cloned `march-language/march` and seven sibling repos into `/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad/march/` (main repo at commit `df461af7`, 2026-10-15) and read source, docs, specs, workflows, issues and PRs. Nothing was built or run, so every behaviour below comes from source and from March's own recorded output, not from a run of mine. Line numbers are in that checkout; where a spec cites a line that has moved I say so. Blimp references are to `/Users/bg/code/blimp-for-blog`.

## 1. What March is

March is a statically typed functional language with ML data types and Elixir-like syntax (`mod`, `fn ... do ... end`, `match`, `|>`), compiled to native code through LLVM, with actors, supervision and capabilities as the headline features. The compiler is OCaml 5.5.1 (about 141,500 lines in `lib/*/*.ml`, 6,486 in `bin/main.ml`). The runtime is C (44,128 lines in `runtime/`; `march_scheduler.c` is an M:N work-stealing green-thread scheduler of 5,231 lines). The standard library is 56,160 lines of March in 135 files. There is also a tree-walking interpreter in OCaml (`lib/eval/`, 14,490 lines), which `bench/interp/README.md:3-5` calls "100-400x slower" than compiled code. Blimp's Zig source is 36,131 lines, for scale.

Version and activity. Latest release `v0.5.0`, published 2026-10-13, labelled "Early Access" on the site. Before it: `0.4.0` on 2026-09-10, `0.3.0` on 2026-08-23, `0.2.0` on 2026-07-23, `0.1.1` on 2026-07-21 (`CHANGELOG.md:10-14`), so four minor releases in twelve weeks. A nightly prerelease is cut whenever `main` is green and has moved (`nightly-20261014` is the newest). The repository was created 2026-03-18; GitHub's commits API reports 6,526 commits (my clone is shallow and holds 2,349); 16 stars, 0 forks, 5 open issues, 2 open PRs. Of the commits I have: Matthew Gilliam 1,639, Chase Gilliam 490, `github-actions[bot]` 196, `Claude` 24. Branch names such as `claude/march-actors-docs`, `merge-train/groups-opqrt` and `codex/todo-sweep-coverage-oracle` show that most recent volume is agent-driven. The latest merged PRs (#985 to #994, 2026-10-13 and 14) are the 0.5.0 release, a remote shell and observe tier, executable stdlib doc examples (#993), `Diagnostics.observe_crashes` (#992), a REPL segfault (#994) and a Perceus leak (#991). The tracker is nearly empty (7 issues ever); design discussion lives in `specs/` and in 92 files under `specs/todos/`. There is no `LICENSE` file, though `README.md:527` and `march.opam:9` say MIT.

The organisation has ten repositories. Only the compiler repository is active.

| Repo | What | Last push | State |
|---|---|---|---|
| `march` | compiler, runtime, stdlib, `forge` build tool, LSP, docs | 2026-10-15 | active, many commits a day |
| `march_doc` | static HTML docs generator for `lib/` with a fuzzy search index | 2026-10-14 | small, 5 test files |
| `conduit` | job queue and durable workflows on Postgres | 2026-10-02 | its CI hit compiler bug #708 |
| `depot` | ORM, query builder, own Postgres wire client | 2026-09-29 | its pool hit compiler bug #705 |
| `march-lean` | Lean 4 re-implementation of the capability, linearity and inference checks, used as a differential oracle | 2026-09-21 | 11,202 lines of Lean, 113 theorems, no `sorry` outside plan documents |
| `bastion` | web framework (plugs, islands, channels) | 2026-08-21 | README says the compiler lives at `/Users/80197052/code/march` |
| `scroll` | notebooks as markdown (`.scrollmd`), served over WebSocket | 2026-08-21 | README: `forge test` "fails to link" because of three upstream bugs |
| `sigil` | static site generator | 2026-08-21 | predates 0.4.0 |
| `setup-march`, `march-language.github.io` | CI action, site | | |

## 2. Feature inventory

"Blimp today" is read from `chunks/lang/src` and `docs/`. Where a gap is large the row says so.

| March feature | Where it lives | Blimp today | Gap |
|---|---|---|---|
| Supervisor strategies `one_for_one`, `one_for_all`, `rest_for_one` | `docs/supervision.md:311`; interpreter `lib/eval/eval_runtime.ml:1022-1140` | Per-handler `bubbles(SelfBubble\|CascadeBubble\|FatalBubble)`; `registry.zig:155-170` | No `rest_for_one`; policy sits on the handler, not on the supervisor |
| Restart budget `max_restarts N within S`, escalation | `docs/supervision.md:379`; `eval_runtime.ml:1034-1043` | None. `Registry.restartActor` resets state to defaults every time | A crash loop never stops. Also `evalBubble` (`eval.zig:809-840`) restarts only when the actor name contains a `.`: a top-level actor never restarts |
| Restart backoff with jitter | `docs/supervision.md:395`; `runtime/march_runtime.c:6534-6672` (compiled only) | None | Absent. March's interpreter does not do it either (`supervision.md:437`) |
| Restart types `permanent`, `transient`, `temporary` | `docs/supervision.md:268` | None | Absent |
| Monitors: `Down(ref, pid, reason)` with `Normal`, `Killed`, `Crash(msg)`; no links | `docs/actors.md:714-770` | `orelse` catches a bubble and drops the reason: `evalOrElse` (`eval.zig:2376-2393`) never reads `bubble_reason`, which `evalBubble` stores at `:813` | The reason is computed and thrown away; nobody can watch an actor |
| `Actor.call(pid, msg, timeout_ms)` with a correlation id on every reply | `docs/actors.md:403-476`; `runtime/march_runtime.c:8674` (`march_actor_call_unwrap`), `:8842` (`march_actor_call`) | `<-` is a synchronous call with no deadline. `tcp_poll` takes a timeout; nothing else does | No deadlines in the evaluator |
| Bounded mailboxes; `drop_new`, `drop_old`, `block_sender`; `mailbox 1000 drop_old` declaration | `docs/actors.md:922-969` | `mailbox.zig` is unbounded; `enqueue` ends in `catch {}`, so an allocation failure drops the message with no signal; `dequeue` shifts the whole array (`copyForwards`), O(n) per message | Irrelevant today because `<--` drains at once (`eval.zig:1127`) |
| `Scheduler.live_procs`, `Actor.top_by_mailbox`, `over_mailbox` | `docs/actors.md:971-1010` | `:stats` on the `--serve` control socket: ticks, errors, compactions, heap, actor count (`main.zig:1622`) | No per-actor numbers |
| Observe socket: one line in, one JSON line out; verbs `ACTORS`, `ACTOR`, `TREE`, `NAMES`, `SCHED`, `MEM`, `CRASHES`, `TOP`, `SNAPSHOT`, `WATCH`; three tiers | `docs/observe.md:800-1160` | `--serve` has a control socket (mode 0600, `main.zig:1551`) that evaluates Blimp source; `blimp --attach` (`main.zig:1648`) is a prompt on it | Blimp's channel is more powerful (it runs code) and has no read-only tier, no structured verbs, no JSON |
| `forge diagnose` findings: `mailbox.growth`, `crash.loop`, `rc.climb`, `epoch.stuck`; the reply says which checks did not run | `docs/observe.md:511-650` | None | Absent |
| Crash observers: `Diagnostics.observe_crashes`, `with_context`, a `CrashReport` with kind, message, backtrace, pid, context | `stdlib/diagnostics.march`; commit `34bd0f73` | `uncaughtBubble` prints one error; `bubble_line`/`bubble_col` record the raise site | No structured report, no observer, no context |
| Capabilities as types: `needs IO.FileWrite`, `Cap(IO)` parameters, a ceiling and a grant from `main` | `docs/capabilities.md`; `lib/caps/*.ml` (`cap_lattice.ml` holds a 20-entry hierarchy) | About 200 builtins (204 `reg.register` calls in `builtins.zig`), all ambient: any actor can `fork`, `exec`, `tcp_connect`, `write_file` | The largest gap, and the one that matters most because holes are filled by a model |
| Capability enforcement by the OS: Seatbelt `sandbox_init` on macOS, seccomp-bpf on Linux, fail closed | `runtime/march_runtime.c:3709-3830`; `docs/capability-enforcement.md` | None | Absent |
| Hot reload with `<actor>_migrate_state`, applied at a mailbox marker | `docs/hot-code-reload.md:426-500` (compiled `.so` patches only) | `--serve` compacts its heap; it does not reload code | Absent |
| Error codes (169), `march --explain <slug>`, a byte-exact corpus of rendered diagnostics, machine fixes, `--check-json` | `lib/errors/code.ml`, `lib/errors/explain.ml`, `test/run_errors.ml`, `test/errors/*.expected` | `errors.zig` (701 lines) has named constructors and a good format (`-- BAD ARGUMENT ---`, source line, caret); 56 tests in `errors_test.zig` | No slugs, no `--explain`, no byte-exact corpus, no fixes |
| Doc examples run in CI against the native and browser REPLs | `scripts/check-stdlib-doctests.py`; `.github/workflows/ci.yml:675-694`; commits `2ca6cbcd`, `e6371a35` | `docs/builtins.md` has `=>` examples; I found no runner for them in `Makefile`, `chunks/lang/Makefile` or `chunks/lang/scripts/` | Examples are not executed |
| Interpreter-versus-compiled golden corpus and cross-mode checksum runner | `specs/lang/golden/g01..g50`; `bench/interp/README.md`; `bench/run_interp_bench.sh` | Three evaluators (Zig; the Blimp-written one in `chunks/lang/lib/eval.blimp`; codegen) plus WASM; `lib/bootstrap_test.blimp` | No runner that diffs them over one corpus that I could find |
| Determinism oracle with a self-test that must go red | `scripts/determinism-oracle.sh`; `specs/progress/2026-10-06-determinism-oracle.md` | The self-hosting fixpoint is the analogue | Unknown whether it is checked |
| Time-travel debugger: ring buffer of frames, each with an actor snapshot; DAP server | `lib/debug/*.ml`; `lib/eval/eval.ml:575-660, 2520-2545`; `lib/dap/` | `--trace` writes TSV for spawn, send, cast, state (`chunks/lang/README.md`) | No replay |
| Durable workflow `ctx.checkpoint("charge", fn () -> ...)`, memoised in Postgres | `conduit/lib/conduit/workflow_context.march:36` | `sqlite_*` builtins exist | Idea only |
| Notebooks as plain markdown | `scroll/README.md` | Tutorial runs in the page | Comparable |
| Perceus RC and FBIP | `docs/memory-model.md` | No refcounting; `gc.zig` compacts on demand under `--serve`; per-actor arenas planned in `docs/lang_design/actor-runtime.md` | Do not copy (section 4) |
| Mutable builtins must be linear or copy-on-write; `Vault` named tables behind `IO.Mut` | `docs/memory-model.md:456-486`; `docs/capabilities.md:603` | `buf_*`, `sbuf_*`, `hmap_*` are `Int` handles; any actor holding the number can mutate; one `buf_new()` stops `--serve` compaction (`docs/lang_design/handles.md`) | Open; see 5.5 |
| Refinement types (z3), linear types, session types, choreographies, clustering, topology | `docs/refinement-types.md` and others | None | Section 4 |

### What I found about Blimp while reading

These are in Blimp's files, not March's, and they bear on the steals below.

`become` is not atomic. `evalBecomeStmt` (`eval.zig:1265-1287`) evaluates one field and writes it into `ctx.entry.state_fields` before it evaluates the next. A handler that does `become total: total + 1, last: parse(x)` and bubbles inside `parse` leaves `total` changed. March's handlers return the next state, so an aborted handler changes nothing. Every item below that unwinds a handler (a budget escalation, a deadline, a watcher) makes this visible.

`evalBubble` restarts the actor at raise time (`eval.zig:818-837`), before any `orelse` has decided whether the failure matters, and only when the actor type name has a dot.

`orelse` treats `nil` and a hole as failure as well as a bubble (`eval.zig:2389`). That is a Blimp choice with no March counterpart.

## 3. What to steal, ranked

Proposed Blimp syntax below is mine. Nothing in it exists yet.

### 3.0 Prerequisite: a handler commits its state when it returns

March design. The state is the handler's return value. `docs/actors.md:144`: "Inside a handler, `state` refers to the current state record. Each handler must return the new state (same type as `state`)."

Blimp. Keep `become` as the statement, but stage its writes and commit them when the handler returns normally.

```
on :checkout(cart) do
  become total: total + cart.price, last: parse(cart.note)   # parse bubbles
  reply :ok
end
# today: total is already bumped when parse bubbles. After: neither field changes.
```

Interpreter. `evalBecomeStmt` pushes `(key, value)` pairs onto a pending list on `actor_ctx`; the handler epilogue (where `reply` and normal exit are handled, around `eval.zig:1196-1230` and `:2226`) applies the list; any `error.Bubble` or timeout drops it. About 40 lines in `eval.zig`. Reads of state inside the same handler keep seeing the old values, which is already the documented behaviour (`eval.zig:1284`: "become is a snapshot transition").

Risk. A handler that calls `self <- :nudge(...)` and expects the nested call to see the new state. Today it does, because the write is immediate. Staged commit changes that. Decide it on purpose and write the test first (`chunks/lang/test/regression_spawn_in_send_arg.blimp` is the model).

Why the obvious version is wrong. Evaluating every field and then writing them all (a fix local to `evalBecomeStmt`) is the minimal change and is not enough: a later statement in the same handler can still bubble after the `become`.

### 3.1 Restart budget, escalation to a wider bubble, restart types

March design. `docs/supervision.md:379-391`:

```march
supervise do
  strategy one_for_one
  max_restarts 3 within 60  -- 3 restarts in 60 seconds → supervisor crashes
  FlakeyWorker w
end
```

The restart-types table (`:268-285`): `permanent` restarts on crash and on `kill()`, `transient` restarts on crash only, `temporary` never; "A death that does not restart also spends **none** of the supervisor's `max_restarts` budget". The interpreter implements the window in about fifteen lines (`lib/eval/eval_runtime.ml:1034-1043`: filter the restart log to the window, sum, compare, `crash_actor sup_pid "max_restarts exceeded"`). The compiled runtime adds backoff: the first crash restarts at once, then `delay = base << min(streak-1, 7)` capped and jittered, `crash_streak` reset after a clean window (`runtime/march_runtime.c:6600-6672`); defaults are 25 ms base, 5000 ms cap, 25% jitter.

In Blimp the namespace is the tree, so the policy goes on the parent name and escalation is a wider bubble, not a crashed supervisor.

```
actor Shop do
  restarts 5 within 30              # seconds; past this a SelfBubble is promoted
  backoff 25, cap: 5000, jitter: 25 # milliseconds, percent
end

actor Shop.Checkout do
  on :charge(p: Payment) bubbles(SelfBubble) do
    ...
    _ -> bubble reason: :card_declined
  end
end

actor Shop.Receipts restart: :transient do   # kill() retires it, a crash revives it
  ...
end
```

Semantics. The sixth `SelfBubble` from `Shop.Checkout` inside 30 s is delivered as a `CascadeBubble` at `Shop`; a sixth cascade inside the window is delivered as a `FatalBubble` at `Shop`'s own parent; at the root the process reports and exits non-zero. The bubble gets wider as the failure repeats, which is what the word already means.

Interpreter. `registry.zig`: a small ring of restart timestamps per supervisor name and a `restartAllowed(name, now)` function; `evalBubble` calls it and changes the strategy before the `restartChildren`/`restartActor` branch. Policy fields parse on the actor header (`parser.zig`, about 40 lines) and travel on the registry template. Backoff is a `not_before_ms` on the entry; a send to an actor still cooling raises a `DownBubble` with reason `:restarting` instead of running the handler. About 120 lines across `registry.zig` and `eval.zig`, 40 in `parser.zig`, plus tests. `--trace` gets a `restart` line with the streak and delay, as `MARCH_SUP_TRACE=1` does (`march: supervisor backoff child=<idx> streak=<n> delay_ms=<ms>`).

Risks. A policy on a namespace that has no actor declared (`Shop` may exist only as a prefix; `restartChildren` takes a name string) needs a home: allow a bodyless `actor Shop do restarts 5 within 30 end`.

Why the obvious version is wrong. (1) "Crash the supervisor" has no referent in Blimp, because the supervisor may not exist as an instance; promoting the bubble does. (2) Backoff by sleeping stalls the only thread. March's interpreter skips backoff for that reason, and March spends most of `march_runtime.c:6534-6600` on races between a delayed batch restart and a sibling's crash; a single-threaded interpreter has none of those races, so the cooling-flag version is both simpler and correct. (3) Charge the budget where the bubble leaves the handler, not where `bubble` is evaluated, or an `orelse` inside the same handler spends budget for a failure the handler already absorbed. That needs 3.0.

### 3.2 Deadlines as bubbles

March design. `docs/actors.md:436-458`:

> `Actor.call(pid, sentinel, timeout_ms)` ... returns `Ok(result)`, or `Err(reason)` if no reply arrives before `timeout_ms` (a value `<= 0` means wait indefinitely). ... Every reply is wrapped in an envelope carrying the correlation id issued for that specific call, and the receive loop discards an envelope whose id does not match, so a late reply from a timed-out first call can never be misdelivered as the answer to a second, unrelated call.

That is real in the compiled runtime (`march_runtime.c:8674-8842`). In the interpreter it is not; see 6.3. Compiled code checks a process-wide preemption flag at function entry, "one load, one predictable branch, no call" (`bench/RESULTS.md:58-66`), and a timer sets the flag.

Blimp.

```
quote = Pricing <- :quote(cart) within 200 orelse :stale

situation Pricing <- :quote(cart) within 200 do
  :timeout -> cached_quote(cart)     # the bubble's reason, matched like any value
  q        -> q
end
```

`within N` raises a bubble with reason `:timeout` in the caller when the callee has not replied in N ms. The callee's handler is unwound (so, with 3.0, its pending state is discarded) and there is no late reply to correlate, because nothing was left running.

Interpreter. `evalNode` already counts reductions and calls out every 4,000 (`eval.zig:431-436`). Add a `deadline_ms` stack on `Evaluator`; at that hook read `now_ms` (builtin at `builtins.zig:86`) once per 4,000 nodes and `return error.Bubble` with `bubble_reason = :timeout` when past the innermost deadline. Blocking builtins do not pass through `evalNode` while they block, so `tcp_read`, `tcp_accept`, `sleep_ms`, `exec` and `waitpid` take `min(own_timeout, remaining_deadline)` and bubble when the deadline, not the call, ran out. About 70 lines in `eval.zig`, 30 in `builtins.zig`, 20 in `parser.zig`.

Risks. A builtin that cannot be interrupted (a long `sqlite_query`, a DNS lookup) overruns by its own duration; say so per builtin in `docs/builtins.md`. A `fork`ed child inherits no deadline.

Why the obvious version is wrong. March's interpreter does the obvious thing: run the callee, then compare timestamps. `lib/eval/eval_builtins.ml:4430-4457`: "a handler that burned ten seconds before replying used to be reported as answering in time even against a 1ms timeout ... actor_reply timestamps each reply; compare it here". The ten-second handler still runs for ten seconds. A deadline that does not stop the work is a late error, and in an interpreter that serves requests it blocks every other connection for the duration.

### 3.3 Bubbles that carry their reason; watchers; crash reports

March design. `docs/actors.md:714-748`: `monitor(watcher, target)` delivers `Down(ref, target_pid, reason)` with reasons `Normal`, `Killed`, `Crash(message)`, and "Monitor `Down` messages are control-plane delivery: they bypass the target watcher's mailbox limit, so a full bounded mailbox cannot lose the death notification". There are no links: "Failure propagates *downward* through supervision trees, never sideways between actor peers" (`:751-770`). `stdlib/diagnostics.march` (commit `34bd0f73`):

```march
let h = Diagnostics.observe_crashes(fn r -> send(reporter, Report(r)))
```

gives a `CrashReport = { kind, message, location, backtrace, process : { pid, supervised }, context }`. `with_context` attaches request metadata that survives the unwind. Observers "run inline, on the failing actor's or task's own thread, in registration order", before the supervisor decides anything, and "a panic inside one is swallowed".

Blimp. Three small things on one mechanism, since an observer is just an actor.

```
receipt = Checkout <- :charge(payment) orelse why do     # bind the reason
  Audit <-- :failed(payment.id, why)
  :error
end

actor Ledger.Audit do
  state seen: Int :: 0
  on :down(who, kind, reason, ctx) do          # kind: :normal | :killed | :crash
    become seen: seen + 1
    ...
  end
end

Audit <- :watch(Shop.Checkout)                 # Audit now receives :down for it

with_context request_id: id do                 # copied into any report raised inside
  Checkout <- :charge(payment)
end
```

Interpreter. `evalOrElse` (`eval.zig:2376`) binds a name in a new env frame from `self.bubble_reason`, which is already stored (`:813`). `Registry` gets a `watchers` list per entry; `evalBubble` and normal handler exit post `:down` through the existing mailbox path (`traceSend` already exists) before restarting. Context is a small map on `Evaluator`, pushed and popped by `with_context`, copied into the report at raise time because the bubble has unwound past it by the time the observer runs. About 60 lines for `orelse why`, 80 for watchers and reports. The report carries `bubble_line`/`bubble_col` (already tracked) and, for free in an interpreter, the actor call stack.

Risks. A watcher whose `:down` handler bubbles: skip it and log, as March does. A watcher that is the dying actor's own caller: deliver after the caller resumes, not inside the failing frame. Report payloads can carry user data; keep the reason text out of anything the observe tier exports (3.5), as March does (`docs/observe.md:964`: "The panic message is never shown here or anywhere in the observe tier: panic strings can carry payloads").

Why the obvious version is wrong. Binding the reason in `orelse` is obvious and enough for a caller. Putting a stack trace in every bubble value is the wrong default: it costs a copy on a path Blimp uses for ordinary control flow. Capture the trace only when a watcher or `--trace` is attached. And do not add links: the namespace tree already propagates failure downward, and a link is a way to fail sideways, which March argues against in the open (`actors.md:751`).

### 3.4 Grants: per-actor capabilities checked at the builtin, with the OS underneath

March design. Capabilities are types, erased after checking, with the declared set turned into confinement at start-up. `docs/capability-enforcement.md`:

> Compiling with `--cap-sandbox` embeds a **deny-default** profile, derived from *this program's own* declared capabilities, that the binary installs on itself at startup before any user code runs ... Installation **fails closed**: if the sandbox cannot be installed, the program will not run rather than continue unconfined.

The failure path is `runtime/march_runtime.c:3809-3816`: `sandbox_init(profile, 0, &err) != 0` prints `refusing to run uncontained` and `exit(70)`. Linux installs an unprivileged seccomp-bpf filter after `PR_SET_NO_NEW_PRIVS`, denying one syscall class per withheld capability (`socket` without `IO.Network`, `execve` without `IO.Process`). Path scopes, `needs IO.FileWrite("/var/lib/myapp")`, are normalised lexically at build time and resolved with `realpath` on the machine that runs the program, because Seatbelt matches after symlink resolution and `/tmp` is `/private/tmp` (`march_runtime.c:3719-3790`). The document is candid that this is self-imposed ("a malicious author simply omits it") and that `forge cap run --allow-only X ./binary`, where the person running it picks the policy, is the strong form.

Blimp has no static effect types and cannot trace a call graph through `a <- msg`, so the check is at the builtin call and fails at run time. Blimp also has the property that makes this matter: holes are filled by a model, so code arrives at run time from a source nobody reviewed, inside a process that can `fork`, `exec` and open sockets.

```
actor Report.Writer needs files_write("/var/reports"), net_connect("api.internal:443") do
  on :save(name: String, body: String) do
    write_file("/var/reports/" ++ name, body)       # allowed
    tcp_connect("evil.example", 80)                  # DeniedBubble: net_connect not granted to Report.Writer
  end
end

situation load(report) do
  :cached -> read_cache(report)
  _ # Hole: fetch it from the report API       # the fill runs with Report.Loader's grants, nothing wider
end
```

and, for the operator who chooses the policy:

```
blimp --serve site.blimp --allow-only files_write:/var/reports,net_listen:8080
```

Interpreter. `builtins.zig` registers builtins one at a time; add a `group` tag per entry (the groups are already the sections of `docs/builtins.md`: Files, Sockets, Process, Buffers). `evalCallExpr` (`eval.zig:1061`) checks `actor_ctx.grants`, a bitset, before dispatch and raises a `DeniedBubble` naming the group and the actor. Grants parse on the actor header. A new `sandbox.zig` of about 150 lines wraps `sandbox_init` and seccomp, called from `main.zig` before the first user node when `--allow-only` is present, with March's fail-closed exit. The per-actor check is the real boundary; the OS layer is a backstop that also covers builtins you forgot to tag. Roughly 100 lines of tagging (mechanical), 60 in `eval.zig`, 40 in `parser.zig`, 150 in `sandbox.zig`.

Risks. March's own table of what the OS layer cannot do applies as written (`capability-enforcement.md`, "Two platform asymmetries"): on macOS `socket()` creation is not gated, only `bind`, `listen` and `connect`; `IO.FileRead` is advisory because dyld reads libraries before user code exists; and under `forge cap run` a program without `IO.Process` can still exec because `sandbox-exec` must exec the target. `sandbox_init` is deprecated by Apple and thinly documented, though March relies on it. Some Blimp servers fork per connection (`docs/lang_design/concurrency.md`), so denying `fork` breaks them; grant it to the server actor. The sandbox is process-wide while grants are per actor, so the OS layer equals the union of every actor's grants and gives no isolation between actors in one process. Only the dynamic check does.

Why the obvious version is wrong. Deriving the OS policy from the program's own `needs` lines, which is what `--cap-sandbox` does, makes the program attest to itself, and a hole fill that adds a `needs` line widens its own cage. The policy has to come from outside the source (`--allow-only`), and a fill must run with the grants of the actor whose hole it is, not with whatever the generated text declares. March reached the same conclusion and says so; its docs still lead with the weaker mode.

A related non-steal. March spends a chapter on mocking capabilities (`with_cap`, `cap_impl`, `docs/capabilities.md:1132-1240`) and admits that "An actor whose handlers reach **more than one** capability" cannot be mocked. In an actor-only language the test double is `spawn Fake.Clock` under the name the code looks up. Do not import the mechanism.

### 3.5 Structured verbs on the control socket

March design. `docs/observe.md:800-815`: "Connect, send **one line**, read **one line** of JSON, and the server closes the connection."

```json
{"proto":"march.observe/1","node":"web-1","at_ms":1791167992809,"took_us":2,"truncated":false,"data":"pong"}
```

Verbs: `ACTORS [mbox|status|epoch|pid] [n]`, `ACTOR <pid>` (alive or dead, with supervisor strategy, `restarts_held`, `restart_ages_ms`), `TREE`, `NAMES`, `CRASHES [n]`, `TOP <attr> <n> [window_ms]`, `SNAPSHOT`, `WATCH`. Three tiers: observe (counts, states, names), debug (state, panic text, traces; signed requests plus a policy file), shell (run code; same key plus its own policy). Replies are capped at 16 MB with `truncated: true`; at most eight connections, then `busy`. `forge diagnose` reads a snapshot and reports findings, each with what fires it, what it usually means and the next command. The envelope's `coverage` lists `ran`, `unavailable` and `partial` checks "so an empty `findings` list is never read as 'healthy' for things nobody looked at" (`observe.md:634-650`).

Blimp. The `--serve` control socket exists (`main.zig:1399-1646`: NUL-framed source in, NUL-framed text out, plus `:stats`), and `blimp --attach` is already the shell tier with mode 0600 as its only guard. The tier below it is missing.

```
$ printf ':actors mailbox 10\0' | nc -U blimp.sock
{"proto":"blimp.observe/1","at_ms":1791167992809,"data":{"total":412,"actors":[{"name":"Shop.Cart#31","mailbox":0,"restarts":2,"idle_ms":5120}, ...]}}
$ printf ':tree\0' | nc -U blimp.sock
$ printf ':crashes 20\0' | nc -U blimp.sock          # kinds and names, never reasons
$ blimp --diagnose blimp.sock                         # restart storms, mailbox growth, heap climb
```

Interpreter. A verb branch ahead of the parse in `controlEval` (`main.zig:1622`) for `:actors`, `:actor`, `:tree`, `:names`, `:crashes`, `:top`, `:heap`; JSON through the writer already in `wasm_json.zig`. `crash.loop` needs the restart log from 3.1. About 250 lines in a new `observe.zig` plus `main.zig`, and about 100 for a `--diagnose` client. March's `rc.climb` becomes `heap.climb` (heap bytes after compaction rising across windows), with the same honesty: March documents "Never fires under the interpreter (no gauge)", and Blimp's version should say "unavailable while a buffer exists" because `inUse()` stops compaction.

Risks. The verbs run on the serve thread between requests (the `service` loop polls with timeout 0), so they must not keep `*const Value` across a compaction (`gc.zig` moves everything). Return copies of names and numbers. An attached `eval` of an infinite loop blocks the server; with 3.2 the control eval gets a default deadline.

Why the obvious version is wrong. Adding `:actors` beside source evaluation leaves one tier, so anyone who can read the socket can run `exec`. Keep read-only verbs on their own path and make `--attach` opt-in (`--serve --shell`), as March separates observe from `forge shell` and signs the latter (`observe.md:69-95`). Do not copy March's signing and replay-nonce scheme yet; it exists for a socket reachable beyond one host.

### 3.6 Reload with `migrate` under `--serve`

March design. `docs/hot-code-reload.md:426-470`: a state-shape change needs a function named `<actor>_migrate_state(old) : new`, run per actor "at a marker in its own mailbox"; "messages already queued when the deploy lands finish on the old code against the old state". It "must be IO-free", checked by the compiler.

```march
fn counter_migrate_state(old : { count: Int }) : { count: Int, history: List(Int) } do ...
```

Blimp. Holes get re-filled while a site is up. Re-reading the source in the serve loop (an mtime poll next to the control socket) and swapping handler tables while keeping `state_fields` is a few dozen lines, because nothing is freed.

```
actor Cart do
  state items: List :: []
  state coupons: List :: []                 # new in this version
  migrate(old) do                            # runs with every grant denied (3.4)
    become coupons: []
  end
end
```

Interpreter. `Registry.replaceTemplate` (new, about 80 lines): update handlers and defaults, append default values for new fields, drop removed ones, run `migrate` per instance at the next message boundary (trivial, since sends are synchronous). About 60 lines in `main.zig` for the watcher, 30 in `parser.zig` for `migrate`.

Risks. Closures stored in state keep their old AST. That is safe (arena) but stale; document it, as March does with "epochs" (each unit of work keeps the code version it started under). Do this after 3.0: a reload that interrupts a half-applied `become` is the worst case.

Why the obvious version is wrong. "It's an interpreter, reload is trivial" holds for memory and fails for the contract. March's native swap was found by a spike (`specs/progress/2026-10-13-hcr-phase0-spike.md`, PR #962) to corrupt memory three ways: a parameter flipped from borrowed to owned gave a heap-use-after-free and SIGSEGV; a changed closure shape leaked 49,962 objects over 20,000 requests; a reclaimed patch image crashed callers holding its closures. None of those exist in an arena interpreter. What does exist is the semantic hole: a `migrate` that does IO, or a check for IO-freedom that misses IO nested in a tuple. That is March issue #82 ("the check misses an IO call when it appears inside a tuple (or record/list) constructor"), found by `march-lean`. Enforce IO-freedom at run time with the 3.4 mechanism, not with a syntactic scan.

### 3.7 Declared mailbox bounds (later)

March design. `docs/actors.md:933-946`:

```march
actor Worker do
  state { n : Int }
  init  { n: 0 }
  mailbox 1000 drop_old        -- after init, before any supervise block
```

and `block_sender` "is compiled-only ... the interpreter refuses it at the call rather than silently running unbounded" (`:957-962`).

Blimp. Worth stealing only once a send can leave a message waiting. Today `<--` enqueues and then runs `runScheduler(1)` (`eval.zig:1127`), so the mailbox holds at most the message in flight. When it matters:

```
actor Ingest.Worker do
  mailbox 1000 drop_old
```

with a `dropped` count in `:stats`, and `block_sender` refused at load time with a message that names `drop_new` and `drop_old`, as March does. Fix `mailbox.zig` now regardless: `enqueue` must not end in `catch {}` (it contradicts "fail loudly"), and `dequeue` should be a ring rather than a `copyForwards`.

Why the obvious version is wrong. A drop policy on a request that expects a reply makes a dropped request indistinguishable from a lost reply; March says so (`actors.md:963-969`) and tells callers to use `block_sender` for anything that answers `Actor.call`. In Blimp, with `within` (3.2), both surface as `:timeout`. Do not add a second reason; document it.

## 4. Attractive, and not worth it for a tree-walking interpreter

| Feature | Why not |
|---|---|
| Perceus reference counting and FBIP in-place reuse | It is a compile-time liveness analysis. An interpreter holding values in an environment cannot know a use is the last, so RC would add a count to every `Value` and a decrement to every scope exit for no reuse. March's own interpreter does none (`docs/memory-model.md:596`: "the interpreter does no explicit refcounting at all"). The cost in compiled March is visible in its tracker: #705 (open: a tail field projection is not retained before its parent record is dropped, so an actor handler's new state is read after free, compiled only), #119 (a self-recursive tail call double-frees; closed), `DEBUG-REPORT-rc-underflow.md`, `DEBUG-REPORT-scheduler-race.md`, `88b57558 fix(perceus): a ~H hole borrows its value instead of leaking it`, and the hot-swap spike with three corruption modes. Blimp's `docs/lang_design/parser.md` (D8) and `actor-runtime.md` plan "Perceus RC local per actor". I would replace that plan with per-actor arenas freed on actor death or restart plus `gc.compactWith`, which needs no analysis; `restartActor` is a natural arena reset. |
| Cycle handling | March has none: "reference counting cannot reclaim a reference cycle ... it would leak: silently and permanently" (`memory-model.md:556`). An arena with compaction does not have the problem. |
| Refinement types with z3, linear types, typestate, proof caps | Static machinery tied to a type checker Blimp does not have. `cap no_panic` needs refinements on divisors to prove no division by zero. Blimp's `case` exhaustiveness plus a runtime `DeniedBubble` covers the same ground less strongly at no cost. |
| Session types and choreographies | Compile-time protocol projection for conversations and multi-node roles (`docs/choreography.md`, 1,394 lines). Real, and out of scope for an interpreter whose sends are synchronous calls. |
| Clustering (SWIM), topology files, signed hot deploys, cluster certificates | An operations product. A single-process Blimp does not need it. |
| M:N work-stealing green threads, `Task.async`, `Task.scope`, `pmap`, `Flow` | Blimp is actor-only and single-threaded by design (`docs/lang_design/concurrency.md` rejects Option D). `Task` is a second concurrency abstraction; `Flow` is a pipeline library on top. |
| Sentinel-routed `Actor.call` | The call handler "must be declared FIRST" because the zero-arg sentinel's constructor index selects the handler, and the sentinel needs a name distinct from the handler (`actors.md:437-441`). Blimp's `<-` replies directly. |
| `stash` and `become` as a documented pattern | `actors.md:329-380` builds selective receive from a `mode` field and a stash list. Blimp has `become` and guards (`on :left when over or paused`) already. |
| Whole-program ORC JIT (`--jit`) | Experimental: "does not support actor programs yet; running interpreted", and `json_stream` SIGBUSes (`bench/interp/README.md:21-33`). |
| Defunctionalisation, escape analysis, TRMC, SIMD vectorisation, cross-compiling through `zig cc` | Compiler passes. Blimp's LLVM backend is a separate project. |
| A Lean mechanisation as proof | March's Lean code is not a proof of Perceus; see 6.8. |

## 5. Tooling and process

### 5.1 Executable documentation, with loud skips

March design. `scripts/check-stdlib-doctests.py`, called from `.github/workflows/ci.yml:675-694`, takes the `march>` transcripts in stdlib doc comments:

```
        march> List.singleton(42)
        [42]
```

and feeds every expression of an opted-in module (`-- doc: try` in its header) to one REPL session in file order, so a `let` line sets up later ones. Its rules are the useful part, from its own header: "LOUD SKIPS (Wave-2 doctrine — never an invisible skip)": a doctest is skipped, with its reason printed, when the module is not opted in, the expected line is a panic, the expected value spans lines, or no value came back; and it "Exits nonzero on any mismatch (or if zero doctests were actually run — a silent-empty guard)". Whole programs go in a ` ```march try ` fence and must exit 0 and match a following ` ```output ` fence. The same examples feed "Try it" buttons that open a browser REPL, and `scripts/browser-repl-doc-sweep.js` runs them there. Commit `e6371a35`: "Native doctests 402 run + 1 program; browser sweep 523 examples (510 clean, 13 expected)".

What it found. Converting the examples "corrected dozens of wrong docs" (`e6371a35`). For `String` alone: "The check found 4 wrong docs and 7 non-March example forms (split on '' splits BYTES, not 'returns whole string'; NFD example was NFC; to_int / to_float error text; split_first's tuple; hex/1e10 literals)" (`2ca6cbcd`). The docs were wrong for months before the check existed.

Blimp. `docs/builtins.md` already writes examples as an expression followed by `=> value`, and raising ones as `-- BAD ARGUMENT: ...`. Write `scripts/check-builtin-docs.sh`: extract fenced blocks, run each expression through `blimp` and through the WASM build (`wasm_api.zig`), compare values with Blimp's own `==`, print each skip with its reason, exit 1 when zero examples ran. Put a "Try it" button on the playground page that already runs the WASM module. About 150 lines of script and no Zig.

Why the obvious version is wrong. Comparing printed text is not enough. March's REPL printed `None` as `null`, `Some(1)` as a raw tagged integer and an opaque type as `#<tag>`, so the checker compares only primitive values as text and checks everything else with `(expr) == (expected)` evaluated in the same session. That REPL also segfaulted on `Err(:invalid)` until #994 (2026-10-14). Do the comparison in the language. Keep nondeterministic builtins (`now_ms`, `exec`, `random`) out by an explicit skip with a reason, not by omission.

Limits to copy knowingly. The check covers stdlib doc comments and `try` fences only. The prose chapters (`docs/actors.md`) instead point at real test files ("The full example is `test/native/actor_stash_become.march`, run on both backends") and `scripts/check-docs.sh` checks for dead source pointers and stale counts. Pointers still rot: `specs/lang/core-march-types.md:2394-2440` cites `typecheck.ml:4177` for the `ESend` arm, which sits at `:3081` today. Cite function names, not lines.

### 5.2 Error codes, `--explain`, and a byte-exact corpus of rendered diagnostics

March design. Every diagnostic carries a snake_case slug from `lib/errors/code.ml` (169 of them), "unique, never reused for a different condition, and never renamed once shipped". `march --explain <slug>` prints `specs/lang/errors/<slug>.md` (14 pages so far; "pages accrue"). `scripts/check-docs.sh` Check G (`:402-470`) fails the build if a slug is spelled as a string literal outside the registry. `test/run_errors.ml` compares, byte for byte, the exit code, the rendered diagnostic, each machine fix as a before/after diff, and the result of applying the fix and checking again, for every `test/errors/<slug>_<n>.march`. Real expected output, `test/errors/then_keyword_1.expected`:

```
-- ERROR -------------------- errors/then_keyword_1.march

I don't recognize `then` here — March uses do/end blocks instead. [then_keyword]

4 |     if n > 0 then 1 else 0 end
                 ^^^^

    if cond do
        expr1
    else
        expr2
    end
    run `march --explain then_keyword`

fix [then_keyword]:
@@ lines 4-4 @@
-    if n > 0 then 1 else 0 end
+    if n > 0 do 1 else 0 end

after fix: exit 0
```

Look at which codes have pages: `elif_keyword`, `then_keyword`, `semicolon_separator`, `module_keyword`, `parse_error`. Those are the mistakes someone from another language, or a model, makes. The repository's `.claude/skills/march-lang/SKILL.md` opens with a "WRONG vs RIGHT — Most Common Bugs" section for the same reason.

Blimp. Holes are filled by a model, so parse errors in generated code are the commonest error Blimp will show. Give each a slug, a one-line fix and a `--explain` page. Emit `--check-json` (one line per diagnostic with `code`, `line`, `col` and `fix: [{line, old, new}]`) so the hole-fill loop can apply a mechanical fix without another model call. Start from data: Blimp's own failed fills say which five to seven foreign constructs (`return`, `self.x =`, `+=`, `try`, `def`, `class`) to catch first. I did not look at that data. `errors.zig` is one constructor per error, so a slug is a field on `BlimpError`. The golden corpus is a `test/errors/` directory of `.blimp` and `.expected` files, a runner of about 100 lines, and an `UPDATE_ERRORS=1` switch to regenerate so a message change shows as a diff in review.

Why the obvious version is wrong. Pinning fragments (`expect "undefined variable"`) passes when a caret moves, a label vanishes or a fix changes. The runner's header says it: "Nothing else in the tree pins a whole message". Also, the "A program that triggers it" sample in each explain page is not run by any check I could find (`grep 'triggers it'` over `scripts/` and `test/*.ml` returns nothing), so those samples can rot. Make Blimp's pages executable from day one by putting each sample in `test/errors/`.

### 5.3 Differential oracles that must be able to fail

March does three separate things.

1. One corpus, two backends. `specs/lang/golden/g01..g50` run interpreted and compiled and must match. Every program in `bench/interp/*.march` prints one `checksum=<int>` and the runner "diffs it across modes and fails on mismatch"; a crashed mode is a `FAILED` row, not an abort (`bench/interp/README.md:10-20`). The two disagreed on `Int` overflow until `CHANGELOG.md:2503`: "`int_max_value() + int_max_value()` ... printed `9223372036854775806` compiled and `-2` interpreted".
2. An independent second implementation. `march-lean` re-implements the capability, linearity and inference checks in Lean 4 from `march --emit-core-ast` JSON, and `.github/workflows/march-lean-dispatch.yml` triggers it on every push to the type corpus. It found a bug in March: issue #82. It is a checker used as an oracle, not a proof; see 6.8.
3. An oracle with a self-test. `scripts/determinism-oracle.sh` compiles every program in the corpus four ways (cold and warm cache, two home directories, two working directories) and demands byte-identical IR. `--self-test` perturbs the stdlib and "requires the oracle to report `FAIL`"; "A green self-test exits 1: the oracle would be vacuous". A run that emits fewer than 10 or 100 programs "exits 2 as vacuous".

Blimp has the raw material for all three: the Zig evaluator, `chunks/lang/lib/eval.blimp`, the LLVM codegen and the WASM module. Write one corpus directory of programs that print a `checksum` line, a runner for the four, and a self-test that flips one builtin in one of them and expects red. The self-hosting fixpoint (generation N compiles generation N+1 to identical output) is the determinism oracle and deserves the same vacuity guards.

### 5.4 Record per message, not per expression

March design. The time-travel debugger (`docs/tooling.md:1247`) drops into `dbg>` with `:back N`, `:forward N`, `:goto`, `:diff`, `:actors`, `:actor ID`. `lib/eval/eval.ml:2520-2545` pushes a frame into a ring on every evaluated expression and calls `snapshot_actors ()` each time, which copies the whole actor table (`:637-649`): O(actors) per expression. It also keeps `ame_state_before` and `ame_state_after` per delivered message (`:597-603`), which is the useful part.

Blimp. Immutable values make state snapshots free, so record per handler: message, `state_before`, `state_after` or the bubble, and the `--trace` line numbers. `blimp --record run.jsonl`, then `blimp --replay run.jsonl --actor Shop.Cart#31` prints that actor's history with a diff between consecutive states. About 120 lines; it reuses `traceState` and `traceSend`.

Why the obvious version is wrong. Snapshot-per-expression is the cost, and snapshots of `*const Value` are wrong for exactly the thing that makes Blimp fast: `buf_*`, `sbuf_*` and `hmap_*` live outside the heap (`docs/lang_design/handles.md`), so a replayed "state" would show the buffer's present contents. Record `buf_len` and a hash with each snapshot and say loudly that handles are not time-travelled, or fix handles first (5.5).

### 5.5 Handles that cannot be aliased

March design. `docs/memory-model.md:456-486`: "A builtin type whose operations write memory another March reference could observe must be either **`always_linear`** ... or **copy-on-write gated on sole ownership** ... A type that is neither must be listed in `non_sendable_types`", and a unit test fails the build if that list gains a name before a general `Send` check exists. `Vault` named tables are the exception and sit behind `needs IO.Mut`.

Blimp. `buf_new()` returns an `Int`. Any actor that learns the number can mutate the buffer; the number can be sent in a message, guessed or saved. This quietly breaks the "no shared memory" decision (D8) and is why compaction stops once any buffer exists. Make the handle an opaque value kind (`Value.handle`) that `gc.compactWith` traces and rewrites (the four-step fix is already written in `handles.md` under "The fix this needs"), owned by the creating actor, so that `<-` with a handle argument either moves it (the sender's variable becomes unusable) or raises. The check is runtime, with an `owner` field on the handle. About 80 lines in `handles.zig` and `value.zig`, 40 in `gc.zig`.

### 5.6 REPL and playground

March's REPL (`docs/repl.md`) is `forge interactive`: value and type after every line, `v` for the last result, `tap>` lines from `|> IO.inspect` mid-pipeline, `:type`, `:inspect`, `:doc`, `:env`, `:load`, `:reload`, `:reset`. The cheap parts for Blimp are `v` (a binding for the last result, a few lines in the REPL loop), `:reload` of the last loaded file, and a `clear` that keeps definitions beside `reset`, which forgets them (`CHANGELOG.md`, [Unreleased]: both are on every REPL on the site).

March's browser REPL is the OCaml interpreter compiled to JavaScript (`js/march_browser.ml`, built by `scripts/build-browser-repl.sh`, regenerated by a workflow after each merge and smoke-tested on PRs), not the LLVM path, and its `Int` is 32-bit while native `Int` is 63-bit. March's answer was to report the overflow in the browser instead of wrapping (`CHANGELOG.md`, [Unreleased]: "`65536 * 65536` was `0`"). Blimp's WASM module runs the same Zig evaluator, so it does not have this problem; keep it that way and put the `int_overflow_test.blimp` cases in the doc check.

### 5.7 Durable steps for model-filled holes

`conduit` memoises named steps: `ctx.checkpoint("charge", fn () -> ...)` stores the result in Postgres, and a crashed workflow resumes after the last checkpoint (`lib/conduit/workflow_context.march:36`; storage interface `checkpoint_get`, `checkpoint_set`, `checkpoint_load_all` at `lib/conduit.march:706-708`). A hole fill is the same shape of expensive, non-repeatable step. Blimp has `sqlite_*`: a `checkpoint(name) do ... end` keyed by actor and name would let a restarted actor skip fills it already paid for. Idea only. I read the interface and not the replay logic, and conduit's own CI is red on #708.

## 6. Claims that did not survive reading the source

6.1 The benchmark. The landing page (`docs/_layouts/landing.html:576-585`) says tree-transform is "7.5x faster than OCaml. 19x faster than Rust" and tabulates March 513 ms, Elixir 2580, OCaml 3825, Rust 9977. The repository holds three sets of numbers for the one benchmark.

| Source | March | OCaml | Rust | Elixir |
|---|---|---|---|---|
| `docs/_layouts/landing.html:581-585` | 513 | 3825 | 9977 | 2580 |
| `bench/RESULTS.md:90-104` (2026-07-24, M3 Max, `RUNS=10`) | 579.1 | 3669.5 | 4902.3 | 2369.0 |
| `README.md`, FBIP section | 1300 | 3650 | 9500 | not given (C 8800) |

`9977` appears in no recorded result; it is in `landing.html`, an unrelated `test/whole_program/zoo.mjs` and generated JSON. `513.3 ms` is the 2026-03-24 baseline, which `RESULTS.md:113` itself calls older. The Rust program (`bench/rust/tree_transform.rs`) is commented "Rust ownership means each inc_leaves call rebuilds the tree (consuming the old one)": it allocates a fresh `Box` tree on every pass. A Rust version that mutates in place through `&mut` is not benchmarked, nor is a C version that reuses nodes, so "faster than Rust" means faster than allocating. The same `RESULTS.md` summary table has March behind on three of four rows: fib(40) 394.7 ms against Rust 286.5; binary-trees(15) 164.7 ms against OCaml 24.1 (6.8x slower); list-ops(1M) 64.3 ms against Rust 5.4 (12x slower). FBIP reuse was disabled program-wide for a while and tree-transform ran at 3842.5 ms, "slower than OCaml, on the workload that is supposed to be March's flagship win" (`RESULTS.md:106-112`); the file attributes it to a missed sink past a join-point cleanup, and it was noticed by a person reading the table.

6.2 "Compiled and interpreted run the same programs." The tracker says otherwise today. #705 prints, for a handler that ends in `result.new_state`, compiled `b-0 b-0 b-0 b-0` and interpreted `b-0 b-1 b-2 b-3`. #708 (open): an `impl` method that uses a capability-threaded builtin gets a hidden leading parameter that some interface call sites do not pass, so "every argument shifts by one register" and the callee segfaults. #707 (open): release tarballs omit `runtime/third_party/blake3`, so native compiles fail with `blake3.h not found`. #705 and #708 were found by March's own libraries, depot and conduit.

6.3 "The timeout is real on both backends" (`docs/actors.md:456`). In the interpreter the callee runs to completion first; `lib/eval/eval_builtins.ml:4430-4457` then compares the reply's timestamp with the deadline and returns `Err "call timed out"`. A ten-second handler under a 1 ms deadline takes ten seconds. The chapter's history list (`actors.md:1184-1258`) calls `Actor.call` "backend-identical", which holds for results and not for elapsed time.

6.4 "Typed" actors. The landing page's Concurrency card is titled "Actor model, typed and isolated". `send` does not relate the message to the target. `lib/typecheck/typecheck.ml:3081-3082`: `| Ast.ESend (cap, msg, _sp) -> ignore (infer_expr env cap);` throws the target's type away; the payload is checked and nothing ties it to an actor. `specs/lang/core-march-types.md:2439-2470` states the consequence: sending `Log("stray")` to a `Counter` "`--check`s clean (exit 0)"; interpreted it is silently dropped; compiled it "is **misrouted, not dropped**: a memory-unsafe outcome", because dispatch is an `ECase` with no default arm over a variant indexed in handler-declaration order (`lower_actor.ml:256`). Filed as `specs/todos/2026-10-12-send-message-not-checked-against-pid-actor.md`, priority P3. The "message protocol is checked on both sides" line (`landing.html:511`) is true of session channels and choreographies, not of `send`. Blimp's `noMatchingHandler` (`errors.zig:544`) raises a located error for the same mistake, which is better than both of March's behaviours.

6.5 "Accidental shared mutable state is a compile error" (`landing.html:553`). `Vault` provides "process-global shared mutable hash maps" (`docs/capabilities.md:603`), `RingBuf` is a mutable linear buffer, and native arrays are copy-on-write. They are tracked by `IO.Mut` and by a rule, not absent, and the word "accidental" is doing work. The design is sound and is Blimp's `hmap_*` situation, with a type-level gate Blimp lacks.

6.6 "Integer overflow reporting." `Int` is 63-bit and wraps silently on both backends: "Nothing traps on overflow: `int_max_value() + 1 == int_min_value()`" (`docs/types.md:46-48`). Overflow is reported only by the browser REPL, whose `Int` is 32-bit (`CHANGELOG.md`, [Unreleased]).

6.7 Supervision features that exist only compiled. Backoff is described as automatic ("March's supervisors apply exponential backoff with jitter to repeat crashes automatically", `docs/overload-resilience.md`) and is implemented only in the C runtime: "the interpreter restarts without delay" (`supervision.md:437`). `block_sender` mailboxes are compiled-only and the interpreter refuses them. The `app`/`Supervisor.spec` DSL is interpreter-only, and compiled programs use `supervise` (`actors.md:1135, 1218`). Scheduler counters other than live actors read `0` under the interpreter.

6.8 Lean. The `march-lean` repository description is "Lean 4 mechanization of March's type system and Perceus/FBIP metatheory". The Lean sources contain no Perceus or FBIP (`grep -rl 'Perceus\|FBIP'` finds only three plan documents). They contain a capability lattice, a linearity pass, tail-call enforcement, an inference oracle and a comparer against `march --emit-core-ast` (`MarchLeanCheck.lean`; `MarchLean/CapCheck.lean` is 4,881 lines). It is a differential oracle, and a good one. Meanwhile `docs/memory-model.md:556-583` says "no part of March is mechanically verified today (a Lean 4 metatheory effort is planned, not started)", which is stale in the other direction. The same page's argument that cycles cannot form "is a *design argument*, not a mechanized proof" with "no runtime detector that would tell you if it were wrong".

6.9 Hot reload "without dropping connections." The phase-0 spike (`specs/progress/2026-10-13-hcr-phase0-spike.md`, PR #962, 2026-10-13) tested the shipped `.so` patch model under ASan and found: borrowed-to-owned parameter change, SIGSEGV and heap-use-after-free; closure-shape change, 49,962 leaked objects; reclaimed patch image, SIGSEGV with `pc == fault address`. Findings 1 and 3 were fixed the same day; finding 2 was open. The verdict was "NO-GO on Model B as specified (ORC JIT in the server), GO on fixing native swap". `docs/hot-code-reload.md` opens without this.

6.10 Doc examples "checked in CI." True from 2026-10-14 for the stdlib doc comments of opted-in modules (249 "Try it" examples on 33 pages), which until then were unchecked ("dozens of wrong docs"). Not true of the prose chapters. Only 14 of 169 error codes have an explain page.

6.11 The siblings. `bastion/README.md` says it depends on the compiler "at `/Users/80197052/code/march`". `scroll/README.md` says `forge test` "currently fails to link the compiled test binary due to three upstream march toolchain bugs" and tells the reader to use `march test`. Four of the nine other repositories (`bastion`, `scroll`, `sigil`, `setup-march`) have not been pushed since before 0.4.0. The repository has no `LICENSE` file.

## What I did not do

I did not run March, so I have not seen a supervisor back off or a sandbox refuse a `socket()`; that is from the C source and the docs. I read the observe, supervision, actors, capabilities, memory-model and hot-reload chapters closely, and the others by headings (session types, choreography, clustering, topology, flow, parallel collections, SIMD, refinement types). I did not read `lib/typecheck`, `lib/tir` or the LLVM emitter beyond the lines cited, nor `forge`'s source. The live pages I fetched (`/`, `/docs/getting-started/`) matched the repo's `docs/` source, which I treated as authoritative. A web search found no discussion of March outside its own repositories, a Bluesky account and the repository's PRs. I have not looked at Blimp's own failed hole fills, on which 5.2 depends.
