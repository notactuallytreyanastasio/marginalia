# Temper -> Blimp toolchain survey

Surveyed 2026-10-14 against `/Users/bg/code/temper-blimp-114` (branch
`114-the-builtins-blimp-grew`, HEAD `91b1022`). Nothing in that tree was
modified. Every experiment lives in
`/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad/toolchain/`
(call it `$S` below). Commands and outputs below were run, not read.

The pull request bodies are not in `-114`; `.prs/` is gitignored and only exists
in `/Users/bg/code/temper-blimp/.prs/` (chapters 01-113; there is no 112 file).
"PR NNN" below means that file.

## 0. Environment facts that cost time

* The Temper CLI needs a JDK. This shell has no `JAVA_HOME` and `/usr/bin/java`
  is a stub, so the bare `temper` wrapper prints "Unable to locate a Java
  Runtime". **JDK 21 worked**:
  `JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
  (`java -version` -> `openjdk version "21.0.12.1"`). `openjdk` and
  `openjdk@27` are also installed; I did not try them. `/usr/libexec/java_home`
  does not find any of them.
* `$S/env.sh` sets JDK 21 and puts the NEW blimp first on `PATH`, then execs its
  arguments: `$S/env.sh $S/temper test -b blimp`. `$S/blimp` and `$S/temper` are
  symlinks to the two binaries named in the brief.
* `temper test -b blimp` and `temper run -b blimp` find the interpreter by
  looking for `blimp` on `PATH` (`BlimpCommand.cliNames = listOf("blimp")`,
  `be-blimp/.../BlimpSpecifics.kt:77`). On this machine
  `/opt/homebrew/bin/blimp -> /Users/bg/code/temper-blimp/blimp/chunks/lang/zig-out/bin/blimp`,
  i.e. the branch-110 build, which lacks `join`/`index_of`/`replace`. PR 113 says
  the same thing: with the old interpreter "every test raised (0 of 11)". Always
  run the CLI with the new blimp first on `PATH` (that is what `env.sh` does).
* CLI rebuild: I did NOT rebuild. The binary at
  `temper/cli/build/install/temper/bin/temper` (dated Oct 3) works. Rebuild
  command, per `temper/cli/build.gradle` (uses the `application` plugin, line
  23) and the coordinator: `cd temper && ./gradlew :cli:installDist` with JDK 21
  on `PATH`; wrapper is Gradle 9.0.0. Untested here. Do not run it in
  `/Users/bg/code/temper-blimp-115`.
* Tooling gotcha unrelated to Temper: this session's shell wrapper refuses some
  compound commands (heredocs containing certain words, `time` with a variable
  command). I wrote scripts to files instead. Not a toolchain property.

## 1. Build and run a library end to end

### Layout

A library is a directory (the "work root") holding `src/`; every
`config.temper.md` under the work root declares one library. Source is literate
markdown: **a four-space-indented block is code**, prose is everything else.
Consequence (hit three times in the branch, PRs 88, 92, 103): never indent a
shell transcript or error message by four spaces in a `.temper.md`; it gets
compiled. Blockquote it.

```
hello/
  src/config.temper.md      # "    export let name = "hello";"
  src/hello.temper.md       # code
  src/hello_test.temper.md  # test("...") { ... } blocks
  src/_connected.blimp      # optional: hand-written Blimp, see section 4
```

`$S/hello/src/config.temper.md`:

```
# hello

    export let name = "hello";
```

`$S/hello/src/hello.temper.md` (excerpt): a `class Greeter(public who: String)`,
`firstEven(xs: List<Int>)` with a `for` and early `return`, and

```temper
    let { listen } = import("std/serve");
    export let main(): Void throws Bubble {
      console.log(new Greeter("world").greet());
      let l = listen(8123);
      let c = l.accept();
      console.log("request: ${c.request.split("\r\n").getOr(0, "")}");
      c.respond("HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nhi\n");
    }
```

Multi-library work roots work (snake-nojs: `src/` is the game, `web/` imports
it with `import("snake")`; `web/snake-nojs/build.sh:20-22`).

### Build

```
$ cd $S/hello
$ $S/env.sh $S/temper build -b blimp          # 3.2 s wall (JVM, 4 cores)
$ find temper.out temper.keep -type f
temper.out/-logs/0000.log
temper.out/blimp/hello/main.blimp           8700 lines
temper.out/blimp/hello/main.blimp.map
temper.out/blimp/std/main.blimp             8604 lines (std on its own)
temper.out/blimp/std/main.blimp.map
temper.keep/blimp/hello/name-selection.json
```

(`temper.out/blimp/temper-core/` also exists after `temper test`.) The whole
library is ONE file. Blimp has no modules, so `BlimpBackend.translate`
(`BlimpBackend.kt:~70-200`) splices, in order: temper-core (`core.blimp`, 4322
lines, whole thing whenever any helper is used), any `_connected.blimp`, every
dependency library's declarations (std, other app libraries), this library's
declarations, top-level statements, one `temper_run_tests([...], "test-results.xml")`
call (only if this library has tests), and `temper_run_async()` (only if
`sleep`/`readLine` was used).

Gradle is not involved at app build time; only the JVM.

### Run

`blimp file.blimp` evaluates the file. Nothing calls `main`; the file defines it.

```
$ $S/blimp temper.out/blimp/hello/main.blimp ; echo exit=$?
ok   greeterGreets__28
ok   firstEven__31
exit=0                                   # 0.008 s total
$ cat test-results.xml
<testsuites><testsuite name="blimp" tests="2" failures="0" ...>
<testcase name="greeterGreets__28" .../>
```

Entry point = append a call and run the concatenation:

```
$ cat temper.out/blimp/hello/main.blimp - > app.blimp <<< 'main()'
$ $S/blimp app.blimp &     # prints: ok.. ok.. hello, world
$ curl -s -i 'http://localhost:8123/foo?x=1'
HTTP/1.1 200 OK
Content-Length: 3
Connection: close

hi
# server printed:  request: GET /foo?x=1 HTTP/1.1     (then exited; main returned)
```

`temper run -b blimp --library hello` exists but just runs `blimp main.blimp`
(`BlimpSpecifics.kt:117-129`, `runMain`): tests only, no entry point. There is no
Temper-level notion of "main" in this backend.

### Test

```
$ $S/env.sh $S/temper test -b blimp           # 2.8 s
Tests passed: 2 of 2
```

Mechanism (`BlimpSpecifics.kt:105-115`): `temper test` runs `blimp main.blimp` in
`temper.out/blimp/<lib>/` with `Aux.JunitXml -> test-results.xml` and stderr to
`stderr.txt`, then reads the XML. A failing assertion, with the exact message:

```
Test failed (blimp): connected - expected `-work/src//`.shout("hi") == (HI!) not (hi!)
Tests passed: 2 of 3
Test failed                                     (exit 1)
```

Test names in the XML are mangled (`greeterGreets__28`); the CLI maps them back
(PR 69, 88). Note the file-level `-work/src//` prefix in messages is a known
cosmetic.

**A compile error in a test body is not a build failure here.** The test is
emitted anyway and "raises" at run time ("Cannot translate Invalid ... test
raised"); the process exit is still non-zero.

## 2. What running a generated file does

* **It runs the library's tests on load and writes `test-results.xml` into the
  current directory**, if the library has any `test(...)` blocks. The call is the
  second to last statement of the file (`temper_run_tests(...)`,
  `main.blimp:8700` for hello). `temper_report_tests` ends in `exit(1)` if any
  test failed (PR 69), so **a failing test aborts the server before it listens.**
  A library with no tests emits no runner. A dependency library's tests are
  never emitted (`BlimpTranslator(..., emitTests = own)`, `BlimpBackend.kt:~107`;
  PR 69). Therefore: keep tests out of the library that is shipped, e.g. put the
  server in `app` and the tests in a sibling library that depends on it.
  highlight/README.md:53-54 says the same ("bin/blimp-hl drops that line").
* Top-level Temper statements (`let x = ...`, `var counter = 0`, class
  instances) run in file order at load, before the test runner call.
* `temper_run_async()` is the last statement, emitted only if `sleep`/`readLine`
  was reachable (`BlimpBackend.kt:~170`). If your entry call is appended AFTER
  the generated file (as in snake-nojs `server.blimp`), anything that
  `main()` queued with `sleep` is not drained unless you also call
  `temper_run_async()` yourself. Verified:

  ```
  $ printf 'main()\ntemper_run_async()\n' > d.blimp ; cat main.blimp d.blimp > app.blimp
  main returned / fast 0 / fast 1 / slow 0 / fast 2 / slow 1      (0.52 s)
  ```

  Without the second line only `main returned` prints.

### Names of exported functions in the generated Blimp

`BlimpNames.kt:110-130`:

* An **exported** Temper name (`ExportedName`) is emitted as its bare display
  name: `export let serve` -> `def serve`, `export class Greeter` -> `actor Greeter`,
  `export let main` -> `def main`, `export let firstEven` -> `def firstEven`
  (`main.blimp:8567`). So hand-written Blimp calls `serve(8099)`, `main()`.
* Everything else (module-private functions, locals, tests, statics) is
  `name__N` where N is a uid that changes between builds (`greeterGreets__28`,
  later `__33`). Never reference these by hand. Test functions get the suffix
  even when an exported function of the same name exists (`firstEven` vs
  `firstEven__31`).
* Names that collide with a Blimp keyword or any builtin (list in
  `BlimpNames.kt:34-87`, 190+ names including `length`, `sort`, `map`, `filter`,
  `log`, `exit`, `form`, `link`, `row`, `text`, `put`, `keys`) get a trailing `_`
  (`length` -> `length_`). Commit 2a8dcd8. `BlimpNamesTest` fails when
  `builtins.zig` grows a name not in the set.
* Compiler-support names are `temper_*` (e.g. `temper_run_async`,
  `temper_listen`) and `blimp_*` (generated loop/continuation names).
* **Exports from different modules and different libraries share one flat
  namespace and the second definition silently wins** (PR 66: "Nothing stops two
  libraries defining the same name, and the collision is silent"). Exported
  names from std (`sleep`, `listen`, `readLine`, `parseJson`...) are in the same
  space as yours. Do not export `sleep`, `listen`, `parseJson`, etc.
* Methods are message atoms: `obj <- :greet()`. A class method named like a
  Blimp special could collide; two handlers with the same sanitised name abort
  translation with `TODO("two handlers answering :x in actor Y")`
  (`BlimpTranslator.kt:~1811`).

## 3. Which std modules are implemented

Keys are in `BlimpSupportCode.kt:304-570` (`blimpConnectedReferences`); bodies in
`core.blimp`. Std sources: `temper/frontend/src/commonMain/resources/std/*/`.

| module | status | detail |
|---|---|---|
| `console.log` | works | `ConsoleLog` -> `puts`. Only `log`. **No stderr, no `console.error`.** |
| `std/io` | `sleep(ms): Promise<Int>`, `readLine(): Promise<String?>` work | `core.blimp:2244,2250`; scheduled by `TemperScheduler` (`:2205`) and `temper_run_async` (`:2261`). **No file read/write, no env, no argv, no exit code, no process spawn.** |
| `std/net` | HTTP **only**, no TLS | `NetRequest(url).post(content, mime).send(): Promise<NetResponse>`; `NetResponse.status/contentType/bodyContent`. `temper_net_send` (`core.blimp:1609`) uses `tcp_connect` + HTTP/1.1 `Connection: close`, decodes chunked (PR 97). **`https://` -> broken promise** ("net: no support for the scheme https"; PR 83). **No request headers at all** (no `Authorization`), no redirects, no timeout. Also an upstream bug in `net.temper.md`: `post` assigns `this.bodyMimeType = bodyMimeType` (itself), so the Content-Type is never sent. Synchronous: the promise is already settled. |
| `std/serve` | works, minimal | `listen(port): Listener`, `Listener.accept(): Connection` (blocks), `Connection.request: String`, `Connection.respond(raw: String)` (writes and closes). See limits in section 6. |
| `std/regex` | works | regex engine written in Blimp (PR 70); node-builder DSL (`oneOrMore(Digit).compiled()`), `found/find/replace/split`. Verified: `found("ab12")` true and `replace("a12b345"){"#"} == "a#b#"`. functional test `RegexMatch`, `RegexZeroAdvance`. |
| `std/temporal` | `Date` only | `Date(y,m,d)`, `fromIsoString`, `toString`, `dayOfWeek`, `yearsBetween`, `Date.today()` (UTC from `now()/86400`, `core.blimp:3591`). **No time of day, no Instant, no formatting.** For clocks use `now()` (s) / `now_ms()` via `_connected.blimp`. |
| `std/json` | **works, but it is Temper, not connected** (my belief that it is not implemented was wrong) | `parseJson(text): JsonSyntaxTree throws Bubble`, `JsonObject/JsonArray/JsonString/JsonInt/...`, `JsonTextProducer.toJsonString()`, `JsonAdapter<T>`. It compiles from `json.temper.md` like user code (that is why `JSON_STATE_OPEN_OBJECT__379` appears in every `main.blimp`). Verified: `parseJson("{\"a\": [1, 2, {\"b\": \"c\"}], \"d\": null}")` then `produce(new JsonTextProducer())` gives `{"a":[1,2,{"b":"c"}],"d":null}` ($S/sec/s6). functional test `TypesJsonSyntaxTree`. Speed is the interpreter's (Temper-level char scan); Blimp also has native `json_decode/json_encode` builtins that std/json does not use. |
| `std/testing` | works | `Test.assert`, `assertHard`; the translated `test(...)` blocks call `test___0 <- :assert(cond, fn)`. functional test `TestingAsserts`. |

Not in std at all: files, env vars, time zones, crypto, hashing, base64, random,
sqlite/pg, processes, sockets as such. Blimp the interpreter has builtins for
many of them (section 7 of Gaps); none are visible to Temper without a
`@connected` declaration.

## 4. How std/serve was added (recipe), and the userland alternative

### Compiler recipe (what commit 7562d9a touched)

`git show 7562d9a --stat`:

```
temper/be-blimp/.../BlimpSupportCode.kt     |  6 ++
temper/be-blimp/.../temper-core/core.blimp  | 75 ++++
temper/frontend/.../std/config.temper.md    |  1 +
temper/frontend/.../std/serve/serve.temper.md | 40 ++++
(+ web/snake-nojs files)
```

Earlier, `std/io` (97c6a51) did the same plus new interpreter builtins:
`io.temper.md`, `std/config.temper.md`, `BlimpSupportCode.kt` (4), `core.blimp`
(23), `blimp/chunks/lang/src/builtins.zig` (117).

Steps, for a new module `std/foo`:

1. Create `temper/frontend/src/commonMain/resources/std/foo/foo.temper.md`.
   Declare with `@connected`: functions `@connected export let f(x: T): R { panic() }`;
   interfaces `@connected export interface I { @connected get p(): String;
   @connected m(a: A): Void; }`; or classes. Prose may not contain 4-space
   indented non-code (see section 1).
2. Add `import("./foo");` to `std/config.temper.md` (the `## Imports` list).
3. Register each member in `blimpConnectedReferences`
   (`BlimpSupportCode.kt:304`), key = the exact connected key string:
   * top-level fn:  `"std/foo.f()"`
   * interface method: `"std/foo.type I.m()"`; getter: `"std/foo.type I.get p()"`
   * class ctor: `"std/foo.type C.constructor()"`; field read: `"std/foo.type C.field"`
   Use `BlimpConnectedCall(key, "temper_foo_f", needsCore, byArity=..., padTo=...)`
   to expand to a call (receiver is argument 0), or `BlimpConnectedSend(key, "msg")`
   to expand to `recv <- :msg(args)`. Optional parameters arrive at several
   arities; Blimp `def`s have fixed arity, so use `padTo`/`byArity`.
   Mark `TEMPER_RUN_ASYNC` in the helper set if the function parks a promise
   (`sleep` does: line 527).
4. Implement the `temper_foo_*` defs and actors in
   `temper-core/core.blimp`. An interface becomes an actor with `on :msg`
   handlers; the Listener/Connection pair (`core.blimp:4131-4180`) is the
   template: `temper_listen(port)` spawns a `TemperListener` actor holding the
   fd as state. Only builtins the interpreter registers can be used; a missing
   one means editing `blimp/chunks/lang/src/builtins.zig`
   (`reg.register("name", &fn)`, around lines 85-245) and rebuilding blimp
   (`zig build`; ReleaseSafe by default since PR 106).
5. If you add a builtin to the interpreter, add its name to `blimpBuiltins`
   (`BlimpNames.kt:34-87`) or `BlimpNamesTest` fails and a Temper export of the
   same name would shadow it.
6. Rebuild the CLI so the std resource and the Kotlin ship in the binary:
   `cd temper && ./gradlew :cli:installDist` (JDK 21). Not run by me.
7. Test: add a case to `be-blimp/src/commonTest/...`; the shared functional
   tests are listed in `FunctionalTestStatus.kt` (all 65 now pass on blimp,
   `onlyPasses(blimp(), ...)` there).

Other backends: a `@connected` std declaration with no implementation in another
backend is only an error when something uses it; `std/serve` was added with
Blimp alone.

### Can a user library supply the Blimp for a `@connected` declaration? YES, without touching the compiler

`BlimpBackend.kt:93-110`: "A library can hand the backend its own Blimp, the way
it hands be-lua a `_connected.lua`: a `_connected.blimp` beside the module source
is spliced in". `BlimpTranslator.kt:877-897` (`connectedBody`): for a
`@connected` **top-level function** in a non-std module, the body becomes
`connected_<name>(params...)`. Added in commit 811a727. The functional test
`functions/connected/connected.temper.md` + `_connected.blimp` passes on blimp.

I verified it end to end (`$S/sec/cn`, `$S/sec/fk`, `$S/hello`):

```temper
    @connected
    export let sha256Hex(s: String): String;
    @connected
    export let getEnv(name: String): String?;
    @connected
    export let forkProcess(): Int;
```
```blimp
# src/_connected.blimp
def connected_sha256Hex(s: Any) -> Any do sha256(s) end
def connected_getEnv(name: Any) -> Any do getenv(name) end
def connected_forkProcess() -> Any do fork() end
def connected_waitFor(pid: Any) -> Any do waitpid(pid, false) end
def connected_exitNow(code: Any) -> Any do exit(code) end
def connected_pieces(s: Any) -> Any do split(s, " ") end     # returns List<String>
```
```
$ $S/t.sh cn      ->  Tests passed: 1 of 1    (sha256, getenv nil/non-nil, hmac_sha256, now_ms, split->List)
$ $S/t.sh fk      ->  Tests passed: 1 of 1    (fork; child writes a file and exit(0); parent waitpid == pid; reads file)
```

Rules and limits found:

* Name = `connected_` + the Temper name exactly. File must be called
  `_connected.blimp` and sit in the same directory as the `.temper.md` module
  (it is looked up with `sourceFile.resolveFile`, one per module directory).
* Only **top-level functions** (exported or not; the functional test has both).
  `@connected` interfaces/classes in user libraries are not wired: the
  `blimpConnectedReferences` map is closed and keyed by std. For an object-like
  API, return an `Int` handle (fd, row id, pid) or a `Map`/`List`, and wrap it
  in a Temper class in the app. (Not tested: user-declared `@connected class`.)
* `sha256` and `hmac_sha256` already return lowercase hex; wrapping them in
  `hex_encode` double-encodes (this bit me).
* Value mapping: Temper `Int`/`Int64` = Blimp Int, `String` = Blimp string
  (bytes), `Boolean`, `null` = `nil`, `List<T>` = Blimp list, `Map`/`MapBuilder`
  = `TemperMap` actor (not a Blimp map), `ListBuilder`/`StringBuilder` = actors
  (`:items`, `:toString`). Receive as `Any`; declared parameter types in the
  `def` cause a crash on `nil` (PR 76), so write `Any` and handle nil yourself.
* The declared Temper body is `panic()`/absent; the interpreter never runs it.
* Anything the connected Blimp defines must be prefixed to avoid shadowing
  builtins (the commit message of 811a727 describes a spin at 100% CPU from a
  wrapper that shadowed `length`).
* Because it is spliced next to temper-core, the connected code can call
  `temper_*` helpers too.

## 5. Language surface

### What the translator refuses (all `TODO(...)`, so they abort the build with a located message; none is a silent fallback)

`BlimpTranslator.kt`:

| line | `TODO` text | construct |
|---|---|---|
| 420 | `break to a label that is not an enclosing block` | labelled `break` to a non-block target |
| 428 | `labelled continue` | `continue label` |
| 430 | `continue outside a loop` | |
| 454 | `statement: $statement` | any TmpL statement kind not handled (catch-all) |
| 489 | `function value: $callable` | a callable used as a value that is not a plain function reference (e.g. a method reference as a value) |
| 519 | `expression: $expression` | catch-all for other TmpL expressions |
| 812 | `actual: $actual` | non-expression actual argument |
| 953 | `early exit inside: $split` | a `return` nested inside a statement kind other than `if`, labelled block, `while`, `try` |
| 1587 | `${decl.kind} declaration` | any type declaration kind other than class/interface (e.g. enum-like declarations if TmpL grows them) |
| 1811 | `two handlers answering :x in actor Y` | two methods whose atoms collide, or `__set_value` beside `var value` |
| 2092 | `property subject: $subject` | assignment target that is not a plain reference/this/expression |
| 2108 | `call subject: $subject` | |
| 2142 | `type subject: $subject` | |
| 2734 | `value of type $tag: $expression` | a *constant* of tag TClass, TClosureRecord, TFunction, TList, TListBuilder, TMap, TMapBuilder, TProblem, TStageRange, TSymbol, i.e. a compile-time-evaluated list/map/function constant that survives to the backend |

`untranslatable()` (`:800`) is the one non-fatal case: a `TmpL.Garbage*` node
(frontend already reported an error) becomes a runtime `temper_bubble`, which is
why a broken test compiles and then "raises".

### What works, with a citation or my own run

I wrote probes in `$S/sec/*`; each passed on `-b blimp` unless noted. Shared
functional tests that pass on blimp (`FunctionalTestStatus.kt:38-103`, 65 of 65;
the README's "18 of 65" is stale, PR 103 says 65) are cited by name.

* **Classes, interface dispatch, generics, sealed interfaces, `is`**: `$S/sec/s0`
  (`class Square extends Shape`, `Box<T>`, `sealed interface Expr` +
  `when (e) { is Num -> ..; is Add -> .. }`, `s is Square`): 1 of 1. Functional:
  `ClassesAngleCall`, `ClassesInheritedGetter`, `InterfacesPureVirtual`,
  `SemanticsMutuallyReferencingTypes`, `CastsAsExpr`, `CastsSpecific`. Class =
  actor; method call = synchronous send (README; PR 04-05, 12). Subclasses are
  flattened (no `super`). `instanceof` = `temper_is_a` question (`core.blimp:3949`
  `temper_cast`).
* **Closures** passed to lambdas capturing locals, including mutation of a
  captured `var` (`twice { (): Void => n = n + 1; }`), and `list.map { (x: Int): Int => x + k }`:
  `$S/sec/c1,c2,c9`. Functional: `FunctionsAsValues`, `FunctionsLocals`. A
  capture-free lambda is a `def`, otherwise a Blimp `fn` closure (commit 4274bbc).
  **Closures cannot be *returned* using `fn (): Int { ... }`** in my attempts
  (`makeCounter(): fn (): Int`): "Never reached by macro expander (S)" from the
  frontend. That is a Temper syntax problem on js too, not a Blimp one; I did not
  find the right spelling. Functional tests use `fn (a: T, b: T): Boolean { .. }`
  only as default-argument values.
* **while / for / break / continue / early return**: `$S/sec/c3` (`while` with
  `return i` inside), `c4` (C-style `for` with `continue`/`break`), `c6/c10`
  (`for (let x of list)`). `while` lowers to a tail-recursive `def`
  (`blimp_loop_N`) returning `[:done|:escape|:break, vars...]`; early return to a
  continuation `def` (see `main.blimp:8530-8575`). Functional: `ControlFlowLoops`,
  `ControlFlowIfReturn`, `ControlFlowLoopReenterable`. PR 05-06, 20.
* **try/catch (bubble)**: `$S/sec/s2`: `bubble()`, `x orelse -9`,
  `do { f() } orelse 42`. 1 of 1. Functional `ControlFlowBubble`,
  `SemanticsBroken`. Bubble = Blimp `bubble`/`try`/`catch` (BubbleBranchStrategy.Exceptions);
  `bubble` takes any value (commit 43b9b70); uncaught: "A bubble reached the top
  of the program: ..." (PR 42). **`orelse` handles only bubbles, not null**:
  `(maybe orelse "d")` stays `null` on blimp, js and py alike ($S/sec/p4). Use
  `if (x == null)`.
* **String interpolation**: `"hi ${who}!"` ($S/sec/p3). **`+` is Int addition
  only; there is no string concatenation operator** (PR 109). Build with
  interpolation, `ListBuilder<String>` + `.join`, or `StringBuilder`.
* **ListBuilder, StringBuilder, Map, MapBuilder, Pair, Deque, DenseBitVector**:
  `$S/sec/p4` (add/removeLast/toList/length; `MapBuilder` set/has/keys/get with
  `orelse`; `new Pair("k",5).key`), `$S/sec/p3` (`StringBuilder` append,
  appendCodePoint). Each is an actor (`core.blimp`, Maps at ~4180-4320). Functional:
  `TypesListOperations`, `TypesMap`, `TypesStringBuild`, `TypesDeque`,
  `TypesDenseBitVector`. **Map is a linear list of entries** (`temper_entry_index_loop`):
  O(n) get/has/set, and `set` appends by copying the list. Keep maps small or
  keep a hash in `_connected.blimp`.
* **Option/null**: `String?`, `x == null`, `x!`-free flows work ($S/sec/p4).
* **Int vs Int64 vs Float**: `$S/sec/p5`. Temper `Int` is 32-bit and wraps
  (`temper_int32(a + b)` after each op; `ident(2147483647) + 1 == ident(-2147483647) - 1`
  passes), `Int64` literals `2147483647i64 + 1i64 == 2147483648i64` pass, integer
  `/` truncates, `%`, `Float` arithmetic, `2.0.sqrt()`, `"42".toInt32()`
  (note: no `toInt()`), `1234567.0.toString() == "1234567.0"`. Functional:
  `TypesIntBasics`, `TypesIntLimits`, `TypesIntShifty`, `TypesFloatBasics`,
  `TypesFloatOps`. Bit ops are arithmetic helpers (`temper_bit_and`), slow.
  Int64 division fixed in 3566671.
* **Strings** ($S/sec/p3): `split(",")`, `list.join(sep) { s => s }`, code-point
  iteration with `String.begin`, `s.hasIndex(i)`, `s.next(i)`, `s[i]` -> code
  point (`s[s.next(String.begin)] == 0xe9` on "héllo wörld"), `s.indexOf(" ", String.begin)`
  -> `StringIndexOption` (`is StringIndex`, `as StringIndex`),
  `s.slice(begin, end)`, `"abc" < "abd"`, `String.fromCodePoint`. Indices are byte
  offsets internally (StringIndex is an Int). Functional: `TypesStringRead`,
  `TypesStringIndices`, `TypesStringIsEmpty`, `NamesNonascii`. **Temper has no
  `String.length`, no `String.replace`, no `String.trim/upper/contains/startsWith`**
  (compile errors "No member length/replace in String"). `replace` = regex or
  split+join; `.countBetween(String.begin, s.end)` counts code points. **There is
  no way to ask for UTF-8 byte length from Temper**: snake-nojs `httpOk` writes
  `Content-Length` using code points (`webapp.temper.md:146`), which is wrong for
  non-ASCII. Use `Connection: close` without `Content-Length`, or a connected
  `length`.
* **List**: `map`, `filter`, `reduceFrom`, `sorted` with comparator
  (`xs.sorted { (a: Int, b: Int): Int => a - b }`, stable), `slice`, indexing
  ($S/sec/p4). Functional: `TypesListSorting`, `TypesListReduce`,
  `TypesListOperations`, `TypesListEmpty`. **Lambda parameters must be typed**
  (`{ (x: Int): Int => ... }`); untyped `n => n.toString()` fails type inference
  ("No member toString in AnyValue").
* **Module-level `var` and shared mutable class state**: `$S/sec/gv`:
  `var counter = 0; let bump() { counter = counter + 1; ... }` and
  `let store = new Store()` with a `MapBuilder` field both work and persist
  across calls.
* **Imports across files/libraries**: `ImportsFunctions/Types/Values`; std
  via `import("std/serve")`.

Frontend bugs I hit (Temper, same on js; not Blimp):

1. **Assignment as the last statement of a block with no trailing `;` crashes the
   compiler** with `java.lang.ClassCastException: SourceName cannot be cast to
   Temporary at CleanupTemporaries.assignNonTemporariesFirst(CleanupTemporaries.kt:367)`
   and no source location. Triggers: `for (let x of xs) { total += x }` and
   `twice { (): Void => n = n + 1 }`. Fix: write `total = total + x;` with the
   semicolon ($S/sec/c5 crashes, c6/c9/c10 pass).
2. **A pure function applied to a large constant in a top-level/`main` body is
   evaluated by the compiler** and aborts with a bare `lang.temper.value.Abort`
   stack trace (`Interpreter.visitEdge`) rather than a message:
   `console.log("spin ${spin(1000000)}")` where `spin` loops. Pass the count from
   outside or make it non-constant.

## 6. Known limits (measured on this machine with the blimp at `-114`)

Memory: **the interpreter frees nothing while a program runs.** `gc.zig`'s first
paragraph; `heap_limit.zig`: default ceiling `2 * 1024 * 1024 * 1024` bytes,
`BLIMP_HEAP_LIMIT=<bytes>` or `0` to lift it; at the ceiling:
`Out of heap: this run reached its 2048 MB ceiling.` PR 27: every intermediate Int
outside the interned range (-1024..4096) costs `@sizeOf(Value)` = 32 bytes, never
reclaimed; fib(40) takes 45 s.

My numbers (`$S/srv/bench.blimp`, `bench2.blimp`, from a Temper library
`$S/srv/src/srv.temper.md`; RSS from `process_stats()`):

```
spin 1e5 iterations (acc = (acc + i*3) % 1000003; i += 1)   216 ms   57 MB RSS
spin 2e5 iterations                                          431 ms  161 MB     ~2.1 us/iteration, ~0.5 KB retained/iteration
depth 3000 (non-tail recursion)                               103 ms  190 MB
listBuild 2000 / 4000 / 5000 / 20000 (ListBuilder.add)        4 / 11 / 16 / 207 ms   53 / 115 / 287 / 1817 MB
StringBuilder 2000 / 4000 / 5000 x10 B                        16 / 35 / 48 ms        137 / 219 / 1916 MB
StringBuilder 20000 x 10 B                                    -> "Out of heap ... 2048 MB ceiling" (killed)
scan 100 KB by code point (s.next loop)                       182 ms   (~550 K code points/s)
split / replace builtins on 100 KB                            <= 1 ms  (native; not Temper-level loops)
```

* **ListBuilder.add and StringBuilder.append copy the whole contents each time**
  (quadratic) and the old copies are never freed. highlight/README.md:
  `ListBuilder 5,000 / 10,000 / 20,000 adds = 118 / 419 MB / 1.6 GB`;
  `StringBuilder same counts, 10 bytes each = 143 / 519 MB / 2.0 GB`; lexing 2000
  lines of Blimp = 1377 MB. In practice: **never build a list or string of more
  than ~2,000 items one `add` at a time.** Build with `split`/`join`/`map` (native
  or O(n)), or collect through `list.map`.
* **A long-running server leaks per request.** `$S/srv` serve loop answering a
  trivial body: RSS 6.4 MB at start; 7.8 / 9.1 / 10.4 / 11.8 MB after 500 / 1000
  / 1500 / 2000 requests = **~2.7 KB per request** for a handler that splits one
  line and builds one string. At the 2 GB ceiling that is ~750 K trivial requests;
  a handler that loops or parses (0.5 KB per loop iteration, 32 B per Int) runs out
  in thousands of requests. There is no compaction in the plain `blimp file`
  mode. (`gc.compact` exists for the REPL, the browser and `blimp --serve`'s tick,
  `gc.zig` header; `Actors.drop_unreachable` is used only by `--serve`.) A
  production server must be restarted periodically, or fork a worker per request
  (fork is reachable, section 7), or a supervisor must restart it when
  `process_stats().rss_bytes` crosses a threshold.
* **Recursion depth 10,000 non-tail calls**: `RECURSION TOO DEEP: A call nested
  10000 deep` (PR 29; reproduced with `depth(100000)`). Tail calls are free;
  `while` is a tail-recursive def so loops are unbounded in depth but not in
  memory. Non-call nesting (e.g. 100,000 nested `1+(...)`) can still SIGBUS (PR 29).
* **Throughput**: ~2 us per simple loop iteration; ~10 us per actor send (PR
  105); Building a page with a class per cell is the typical cost
  (snake render 32 ms in ReleaseSafe, PR 106). Debug-vs-ReleaseSafe was 10x:
  make sure `blimp` is a ReleaseSafe build (the default since PR 106). Startup:
  hello (8.7 K lines) loads in 8 ms; server idle RSS 6 MB.
* **Max string/list size**: no hard limit found; the limit is the 2 GB heap and
  the quadratic builders. `tcp_read` reads at most 64 KB (`builtins.zig:4792`);
  `http_start` bodies capped at 8 MiB, 32 requests in flight (`:3794-3830`).
* **Long-running specifics**: `temper_listen` bubbles with "cannot listen on port
  N -- something else is probably already on it" for every failure reason.
  `accept` blocks the whole process. `write_stall_ms = 10_000`: `tcp_write` gives
  up on a reader that takes nothing for 10 s. The snake servers needed a
  `POLLHUP` fix (PR 107) and a "sleep off early returns" fix; a `sleep` loop is
  asleep, not spinning (0% CPU).

## 7. Concurrency

* **One thread, one program.** Actors run to completion one message at a time;
  Temper method calls are synchronous sends.
* **async/await and promises work** (`ControlFlowAsync`, PR 75, 76, 104).
  `PromiseBuilder` / `promise` / `await` are actors (`temper_new_promise`).
  `sleep` and `readLine` return an UNSETTLED promise and the generator parks;
  `temper_run_async` (the only event loop, `core.blimp:2261`) waits for the
  earliest timer or a readable stdin via `tcp_poll([0], ms)` and resumes.
* **Two async blocks do interleave.** Verified ($S/sec/as): fast loop `sleep(100)`
  x3 and slow loop `sleep(250)` x2:
  `main returned, fast 0, fast 1, slow 0, fast 2, slow 1` in 0.52 s, in the
  right time order. `await sleep(..)` needs `orelse` inside the async lambda
  ("Cannot bubble from a function without Bubble in its return type"). Syntax:
  `async { (): GeneratorResult<Empty> extends GeneratorFn => ... }`
  (from `control-flow/async`).
* **Nothing else is async.** `std/serve.accept()` blocks in `tcp_accept`
  (blocking), `request` blocks in one `tcp_read` (a client that connects and
  sends nothing stops the whole server), `std/net` is synchronous. So a
  `while(true) { accept ... }` loop starves every async block and every timer.
  Nothing in std can poll. The builtins exist (`tcp_set_nonblocking`, `tcp_poll`,
  `tcp_poll_write`, `tcp_write_some`, used by the event loop), but need a
  connected wrapper (e.g. `acceptWithin(listener, ms)`) to be usable.
* **Fork is reachable from Temper through `_connected.blimp`** (no compiler
  change). Verified: `$S/sec/fk` forks, the child writes a file and
  `exit(0)`s, the parent `waitpid`s the pid and reads the file: pass. Caveats:
  `fork()` copies the interpreter heap (copy-on-write), the child shares the
  listening socket and its fds; `waitpid(pid, true)` is non-blocking; there is no
  `exec`, no pipes, no `kill`, no signals. A child that does `tcp_accept` on the
  inherited listener gives a pre-fork worker model.
* **Outbound HTTPS without blocking** is a Blimp builtin pair `http_start` /
  `http_result` (`builtins.zig:3794-3830`): thread-backed, TLS (vendored Zig
  client with its own TLS 1.2/1.3 + ECDSA), custom headers, methods, body,
  `timeout_ms` (default 15 s), `max_redirects` (default 5), body cap 8 MiB, 32 in
  flight. `http_result(handle)` -> `nil` (pending) | `{:ok, status, body}` |
  `{:error, reason}`. Not wired to Temper.

## 8. PR chapters worth reading (by topic)

* 03-04 translator shape; 05-06 loops/early return; 12 cells/inheritance; 16-17 imports and maps
* 27 allocation per call (360 bytes); 29 recursion limit; 30 release benchmarks
* 66 library pasted in (name collisions); 69 tests; 88 `temper test` path
* 70 regex engine; 75-76 promises; 80-83 http client and why https refuses; 97 chunked
* 103-107 snake: sleep/readLine, scheduler, per-call copy of captures (105), ReleaseSafe (106), poll (107)
* 109-110 web server in Temper; `std/serve`; 111 one test report per library
* 113 highlighter: the memory curve

## Gaps to fill for a web app

Order: what blocks a Marginalia-sized server first. "App Temper" = write it in
Temper in the application library; "connected" = `_connected.blimp` in the app
library over existing Blimp builtins (no compiler change, section 4); "std" = new
module in the compiler; "Zig" = new builtin in `blimp/chunks/lang/src/builtins.zig`.

1. **Request parsing beyond the first line (headers, query, form body, cookies).**
   `Connection.request` is one `tcp_read` (<= 64 KB) of raw text; no loop for a
   POST whose body arrives in a second segment, no timeout. App Temper for
   parsing (split on `\r\n\r\n`, `\r\n`, `:`; percent-decoding; urlencoded forms;
   `Cookie:`/`Set-Cookie`). Reading the rest of the body by `Content-Length`
   needs **connected**: `readMore(conn)`; but the fd is private to
   `TemperConnection`, so first add `on :readMore` to a connected-side variant of
   listen. Recommended: write the whole accept/read/respond layer in
   `_connected.blimp` (`tcp_listen/accept/read/write/close/poll` are all builtins)
   and expose `acceptRequest(listenFd, timeoutMs): List<String>` /
   `respond(fd, raw)`, bypassing `std/serve`. This also fixes the blocking-accept
   starvation.
2. **Routing, forms, sessions, static files, templating.** App Temper
   (routing is string comparison; sessions are a `MapBuilder<String, ...>` in a
   module-level object, verified; mind O(n) maps, so cap session count or keep a
   hash in connected Blimp). Static files: needs `read_file` (builtin exists,
   binary-safe? uses String; `write_bytes` exists): **connected**
   `readFile(path): String?`, `fileExists`, `listDir`. Set `Content-Type` and
   compute length with a connected `byteLength(s)` (Temper cannot).
3. **Response size / escaping.** Build HTML with `ListBuilder<String>` of <= a
   few thousand pieces then `join` (native). A single page of 5-20 K appends will
   cost 100s of MB (section 6). App Temper, with discipline; or **connected**
   `concat_all(list)` -> `join(list, "")`.
4. **Memory growth in a long-running process (the biggest risk).** No fix in
   Temper. Options: (a) supervisor restarts on RSS threshold
   (`process_stats` via connected, or external `ps`); (b) pre-fork worker per
   request or per N requests via connected `fork/waitpid/exit`; (c) **Zig**: make
   the plain-run mode call `gc.compact` between requests (the machinery exists:
   `Actors.drop_unreachable`, used by `blimp --serve`) at a safe point exposed as
   a builtin `gc()` that the accept loop calls. (c) is the real fix; (a)+(b) work
   today.
5. **Database.** None exists. Existing Blimp builtins: `read_file`, `write_file`,
   `write_bytes`, `list_dir`, `file_size`, `store/stored` (browser only), `json_encode/json_decode`.
   Options: (a) JSON/line-file persistence in app Temper + connected file I/O
   (fine for small data; whole-file rewrite is O(n); atomic rename missing, so
   write to a temp name and keep a backup); (b) **Zig** builtin binding sqlite
   (`sqlite_open/exec/query` returning lists of lists) with a connected wrapper;
   (c) a Postgres client written in Blimp over `tcp_connect` (there is a
   `~/code/blimp-pg` checkout; not examined). Recommend (b) if SQL is needed; it
   also removes the quadratic-memory concern for data sets.
6. **HTTPS client to an LLM API.** `std/net` cannot (http only, no headers).
   **Connected** wrapper over `http_start`/`http_result`:
   `httpStart(method, url, headers: List<String>, body, timeoutMs): Int` returning
   a handle, and `httpPoll(handle): List<String>?` (nil pending, else
   `[status, body]` or `["error", reason]`); poll from a Temper `async` block with
   `await sleep(50)` between polls. Handles TLS, 8 MiB body cap. Streaming
   (SSE) responses are not supported (whole body at once). Needs a trust store;
   the builtin loads the CA bundle on first https use (`builtins.zig:~4513`);
   verify on the deploy host.
7. **Password hashing.** Builtins: `sha256`, `hmac_sha256`, `random_bytes`,
   `random_token`, `base64*`, `hex*`, `xor_bytes`, `aes128gcm_*`, `p256_*`,
   `ecdsa_p256_*`. No bcrypt/argon2/pbkdf2/scrypt. Option 1 (connected, today):
   PBKDF2-HMAC-SHA256 in Temper/Blimp over `hmac_sha256` with >= 100 K
   iterations; at ~2 us/op plus the native HMAC this is seconds and ~0.5 KB per
   iteration of leaked memory (a login would leak ~50 MB), so iterate in a
   forked child. Option 2 (**Zig**, recommended): add `pbkdf2_sha256(pw, salt,
   iters, len)` or `argon2id` using Zig std (std.crypto.pwhash has both).
   Constant-time compare: add `constant_time_eq` in Zig or XOR-accumulate via
   `xor_bytes`.
8. **JSON.** Works now via `std/json` (Temper); fine for API-sized bodies
   (tens of KB), slow and memory-hungry for large ones. For big payloads, wrap
   the native `json_decode`/`json_encode` through connected and convert the
   Blimp map/list into Temper values in app code. Recommended only if profiling
   demands it.
9. **Markdown rendering.** App Temper. Use `split`/`join`/regex (works) and
   avoid per-character builders; a line-oriented renderer over `split("\n")` with
   a per-line inline pass built from `replace`-by-regex is within the memory
   budget for documents up to tens of KB. Anything per-character over a 100 KB
   document costs 180 ms per pass (`scan` number above) and leaks. If it must be
   fast, **Zig** `markdown_to_html` builtin (or a connected Blimp one using
   `index_of/slice/replace` natives).
10. **Multipart uploads.** Needs the full body: >64 KB bodies and binary content.
    `tcp_read` returns a Blimp string (bytes ok); the request must be read in a
    loop until `Content-Length` bytes arrive, with a limit. **Connected** (item 1)
    plus app-Temper boundary splitting using native `split`. Write the file with
    `write_bytes` (connected). Cap size low; the 2 GB non-freeing heap makes every
    uploaded megabyte permanent for the process lifetime (fork per upload helps).
11. **Cookies and sessions.** Parsing/formatting in app Temper; ids from
    `random_token` (connected), signing via `hmac_sha256` (connected), compare in
    constant time (item 7). `Set-Cookie` needs the raw `respond` string, which
    `std/serve` already allows.
12. **Background jobs.** Single-threaded; `async` blocks only advance in
    `temper_run_async`, which is never reached while the accept loop runs.
    Options: (a) **connected** `acceptWithin(ms)` (item 1) so the server loop is
    itself an async block that does `await sleep(...)` between polls, letting job
    blocks interleave (cooperative; a long job blocks requests); (b) `fork()` a
    job runner (connected `fork/waitpid/exit` verified); communicate through
    files; (c) an external cron/process invoking the same binary with an argv
    switch (`argv()`/`getenv` via connected). For LLM calls, item 6's
    non-blocking client is the right shape: start, return to the loop, poll.
13. **Process runner / shell-outs.** Absent: no `exec`, `spawn`, `system`,
    pipes, `kill`. **Zig** builtins required: `spawn(argv, env, stdin) -> pid`,
    `pipe`-based capture (`proc_read(pid)`, `proc_wait(pid)`), then connected
    wrappers. `fork` alone cannot exec.
14. **Logging / stderr / exit codes / config.** `console.log` -> stdout only.
    **Connected**: `getenv`, `argv`, `exit`, `write_file` append (no append mode
    exists: `write_file` truncates; keep a log by rewriting or add **Zig**
    `append_file`).
15. **Test pipeline.** `temper test -b blimp` works (section 1) but tests run
    inside the same `main.blimp` at load. Keep tests in a separate library that
    depends on the app library so shipped `main.blimp` has no test runner and no
    `exit(1)` at startup. For HTTP-level tests, drive `route(request): response`
    as a pure Temper function (as snake-nojs does with `handle(path)`) so no
    sockets are needed.
16. **Operational gotchas to bake into the build script.** Put the NEW blimp
    first on `PATH`; JDK 21; pin the semicolon rule for assignments; ASCII-only
    guard on `Content-Length` or use `Connection: close`; do not export names
    that collide with std or builtins (`sleep`, `listen`, `length`, `filter`);
    stamp the build with the `blimp` commit (`blimp` has no `--version`; `blimp
    --help` just errors "FileNotFound").
