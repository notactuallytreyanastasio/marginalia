# Assets: reusing Marginalia's CSS, replacing its JavaScript

Source tree: `/Users/bg/code/marginalia/.claude/worktrees/blimp-rewrite` (branch
`worktree-blimp-rewrite`). Everything below was run against the original checkout's
`deps/` and `_build/` (read-only); outputs went to
`/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad/assets/`.
Versions: Tailwind 4.3.0, daisyUI 5.5.20, esbuild 0.25.4, phoenix_live_view 1.2.11.

---

## 1. CSS

### 1.1 How it is built

`config/config.exs`:

```elixir
config :esbuild,
  version: "0.25.4",
  marginalia: [
    args: ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.3.0",
  marginalia: [
    args: ~w(--input=assets/css/app.css --output=priv/static/assets/css/app.css),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]
```

It is the standalone Tailwind binary (no Node, no `package.json`). The `NODE_PATH` is how
`@plugin "daisyui/packages/bundle/daisyui"` and `@import "phoenix-colocated/marginalia/colocated.css"`
resolve: daisyUI lives in `deps/daisyui` (a mix dep), and the colocated-hook extraction lives in
`_build/dev/phoenix-colocated/marginalia/`.

The head of `assets/css/app.css` (5250 lines, 164,210 bytes):

```css
@import "tailwindcss" source(none);                       /* no automatic source detection */
@import "phoenix-colocated/marginalia/colocated.css";     /* 0 bytes today: no hook ships CSS */
@source "../css";
@source "../js";
@source "../../lib/marginalia_web";
@source "../../_build/dev/phoenix-colocated/marginalia/*/";   /* the JS pulled out of ColocatedHook blocks */
@plugin "../vendor/heroicons";                            /* build-time plugin: hero-* classes */
@plugin "daisyui/packages/bundle/daisyui" { themes: false; }
@plugin "daisyui/packages/bundle/daisyui-theme" { name: "dark"; ... }
@plugin "daisyui/packages/bundle/daisyui-theme" { name: "light"; default: true; ... }
@custom-variant phx-click-loading (.phx-click-loading&, .phx-click-loading &);
@custom-variant phx-submit-loading (...); @custom-variant phx-change-loading (...);
@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *));
[data-phx-session], [data-phx-teleported-src] { display: contents }
```

Only `@source` lines decide which utilities are emitted. They point at `lib/marginalia_web`
(the HEEx and `~H` strings), `assets/js` and the extracted hook JS. Anything a new server
renders from a different directory is invisible to Tailwind until those paths change.

### 1.2 Producing the compiled CSS

Did it, with the repo's own pinned binary, no mix involved:

```
$ cd /Users/bg/code/marginalia
$ NODE_PATH=$PWD/deps:$PWD/_build/dev _build/tailwind-macos-arm64-4.3.0 \
    --input=assets/css/app.css --output=$SCRATCH/app.css
≈ tailwindcss v4.3.0
/*! 🌼 daisyUI 5.5.20 */
Done in 100ms
$ ... --output=$SCRATCH/app.min.css --minify          # Done in 102ms
$ ls -l
-rw-r--r--  256645  app.css
-rw-r--r--  207738  app.min.css
$ gzip -c app.min.css | wc -c
36094
```

| file | bytes |
|---|---|
| `scratchpad/assets/app.css` (unminified) | 256,645 |
| `scratchpad/assets/app.min.css` (`--minify`) | 207,738 |
| `app.min.css` gzipped | 36,094 |


**Update after the worktree moved to main (c9eb474, 6 commits newer).** `assets/css/app.css` changed from 5250 lines / 164,210 bytes
to 5230 lines / 165,011 bytes (net: +15 lines of rules, so the file shrank elsewhere). Added: `.mg-read-body ::selection` / `::-moz-selection`
(`background:#f7d774; color:var(--mg-ink)`) and `.mg-mutter` (+ `.out`, `@keyframes mg-mutter-in`) for the Rotate hook. Recompiled with the same
Tailwind 4.3.0 binary and daisyUI 5.5.20 (input copied to a staging dir `scratchpad/stage/` with `lib/` from the new worktree and `deps`, `_build` symlinked
to the original checkout, because the plugin paths in `app.css` resolve relative to the CSS file and the worktree has no `deps/`):

```
-rw-r--r--  207339  new.min.css      (was 207738; 36,048 gzipped, was 36,094)
$ cmp old new   -> differ at byte 149873
```

The new minified output is 399 bytes smaller despite the added rules: lib/ changes (rewrite.ex, case_live/read.ex, work_live/show.ex) dropped some utility tokens.
Caveat: `_build/dev/phoenix-colocated` is the original checkout's, not regenerated for c9eb474, so utilities used only inside the new Rotate hook's JS (it uses none) would be missed.
The committed copy is `blimp/static/css/app.css` (207,339 bytes), overwritten from the old 207,738-byte build. Everywhere below that says 207,738 refers to the pre-update build.
The class-token scan re-run on 122 files gives 717 tokens, 628 with a selector, 89 without (was 119 / 717 / 627 / 90, against the old compile).

Breakdown of the minified file by top-level block (script `scratchpad/assets/layers.py`):

```
   99270  unlayered rules (hand-written .mg-* / .cr-* / .fl-* / .lc-* ... from app.css)
   84475  @layer utilities
    8382  @media
    8321  @layer base
    3100  @property
    1462  @layer properties
    1310  @keyframes
    1243  @layer theme
```

So about half the file is hand-written and independent of any scanning: it is emitted verbatim.
Caveat: daisyUI 5 nests its output in `@layer daisyui` blocks inside these, so "utilities" includes
daisyUI component CSS and the number is not a pure Tailwind-utility figure.

The unlayered hand-written CSS has no dependence on Tailwind at all. It uses CSS custom properties
declared on `:root` (`--mg-paper #fbfaf7`, `--mg-ink #1c1a17`, `--mg-accent #8a3324`, `--mg-serif`,
`--mg-sans`, `--mg-mono`, ...).

### 1.3 How many classes does the markup need from the scan?

Method: regex over `class="..."` and string literals inside `class={...}` in
`lib/**/*.ex` and `*.heex` (119 files), then check each token against the selectors in the
compiled CSS (`scratchpad/assets/classes.py`, outputs `tokens_found.txt`, `tokens_missing.txt`,
`utils.txt`):

```
119 files 717 distinct class tokens
tokens with a selector in compiled css: 627  without: 90
found in compiled CSS but not defined anywhere in app.css source: 215   (= Tailwind/daisyUI/heroicons output)
found and defined by hand in app.css: 412
```

The 90 without a selector are not bugs: they are JS-only hooks, state names toggled by hooks, or
words in a regex-captured string (`act`, `arcs`, `dots`, `fresh`, `d1`, `h2`, `gone`, `mg-cands`,
`mg-chips`, `mg-edges`, `mg-fold`, `mg-gut`, `mg-head`, `mg-toggle`, `st-publish`, `st-revision`,
`st-step`, `sec-aside`, `note-cta`, ...). Full list in `tokens_missing.txt`. One more caveat: the
regex does not see classes built in Elixir helper functions or by interpolation (`k-#{kind}`),
which Tailwind would still find as literals. Treat 717 as a floor.

The 215 generated tokens include, concretely: `flex flex-col flex-row flex-wrap flex-1 items-center
items-baseline justify-between gap-1.5 gap-2 gap-3 gap-4 gap-5 gap-6 mt-0.5 mt-1 ... mt-12 mb-1 mb-2.5 mb-7
px-1.5 px-2.5 px-3 px-4 px-6 py-0.5 py-1 py-1.5 py-2 py-2.5 py-4 py-6 py-8 py-10 py-16 p-2 p-3 p-3.5 p-4 p-5
max-w-2xl max-w-3xl max-w-4xl max-w-5xl max-w-prose max-w-sm max-w-xl max-w-[58ch] max-w-[62ch]
max-w-[68ch] max-w-[78ch] max-w-[80ch] max-h-56 max-h-[22rem] min-h-[3.2rem] min-h-[7.5rem] opacity-40
opacity-50 opacity-60 opacity-70 opacity-75 bg-base-100 bg-base-300 bg-[var(--mg-card)]
bg-[var(--mg-margin)] bg-[var(--mg-paper)] border border-b border-l-2 border-t border-dashed
border-base-200 border-base-300 border-[var(--mg-rule)] border-[var(--mg-accent)] rounded-full
rounded-sm hover:opacity-100 hover:underline hover:text-[var(--mg-accent)] group-hover:opacity-70
focus:outline-none focus:border-[var(--mg-accent)] first:mt-0 lg:px-8 sm:px-6 sm:w-96 sm:max-w-96
motion-safe:animate-spin size-3 size-4 size-5 font-bold font-medium font-normal font-semibold italic
leading-6 leading-8 leading-relaxed leading-snug space-y-4 resize-none overflow-x-auto overflow-y-auto
cursor-pointer break-words brightness-200 transition-[left]
[[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0`.
Arbitrary values (`max-w-[58ch]`, `bg-[var(--mg-card)]`) are the ones that break when someone
edits the template without re-running Tailwind.

daisyUI components referenced from markup are few (all in `core_components.ex` and `layouts.ex`):

| class | where | note |
|---|---|---|
| `toast toast-top toast-end` | core_components.ex:66 | flash container |
| `alert alert-error / alert-info` | core_components.ex flash | |
| `checkbox checkbox-sm` | core_components.ex:231 | `<.input type="checkbox">` |
| `table table-zebra` | core_components.ex:364 | `<.table>` |
| `card` (+ `border-base-300 bg-base-300 rounded-full`) | layouts.ex:223 | the theme toggle pill |
| `label`, `divider` | core_components.ex | |

No `btn`, `menu`, `dropdown`, `modal`, `navbar` class appears in `lib/` (buttons are the hand-written
`mg-btn`). Yet the compiled CSS still contains `.btn .btn-active .btn-ghost .btn-link .menu .menu-active
.menu-title .dropdown .dropdown-content .modal ...`: daisyUI 5's plugin emits every component
unconditionally, not on demand. Theme colour utilities (`bg-base-100`, `border-base-300`) resolve to the
`--color-base-*` variables set by the two `daisyui-theme` plugin blocks.

Heroicons: 7 icons are used, compiled as `.hero-arrow-path .hero-computer-desktop-micro
.hero-exclamation-circle .hero-information-circle .hero-moon-micro .hero-sun-micro .hero-x-mark`.
`assets/vendor/heroicons.js` (1,394 bytes) is *not* browser JS: it is a Tailwind plugin run at build
time that reads `deps/heroicons/optimized/` and emits `mask` rules with inlined SVG data URIs. It is
never shipped.

### 1.4 Recommendation: (a) compile once, commit the CSS

Commit `priv/static/assets/css/app.css` (the minified file, now 207,339 bytes) into the new server and treat it
as a vendored artifact. Reasons:

1. "Look identical" is guaranteed only by identical bytes. A re-scan of new templates can only add or drop
   utilities; it cannot make the hand-written 99 KB any more faithful.
2. Rebuilding needs `deps/daisyui` (a mix dep, absent from the worktree), `deps/heroicons`, and the
   `_build/dev/phoenix-colocated` directory that only an Elixir compile produces. `@import
   "phoenix-colocated/marginalia/colocated.css"` fails without it. The new server would need to
   carry or re-fetch all of that for a file that changes rarely.
3. The surface that needs scanning is small and checkable: 215 utility tokens. Where a new template
   needs a utility not in the file, either add it to a small hand-written supplement file
   (loaded after `app.css`) or regenerate.

Keep (b) as an escape hatch, not a pipeline: store the Tailwind input and the exact command
(`tailwind 4.3.0 --input ... --output ... --minify`, with `NODE_PATH` pointing at a vendored
`daisyui` and `heroicons`), change only the `@source` lines to the new template directory, and regenerate
when a template introduces a utility. Add a test that extracts class tokens from the new templates and fails on any
token that is neither in the committed CSS nor in an allow-list (`classes.py` is the prototype of
that check; it takes under a second).

Two things the committed file implies:

- `app.css` is served at `/assets/css/app.css` with `phx-track-static`; in prod `config/prod.exs` uses
  `cache_static_manifest: "priv/static/cache_manifest.json"` (digested URLs). A new server needs its own
  cache-busting (content hash in the filename or `?vsn=`).
- `[data-phx-session], [data-phx-teleported-src] { display: contents }` and the `phx-*-loading`
  variants are LiveView-specific. They are harmless without LiveView. If the client runtime adds a
  `phx-click-loading` class during fetches the variants work; no markup in `lib/` uses them today (0 hits
  for `phx-click-loading:` / `phx-submit-loading:`).

### 1.5 Fonts, theme, static files

**Fonts.** None are loaded. `grep -c '@font-face' assets/css/app.css` is 0; no Google Fonts `<link>`;
no `https://` stylesheet or script anywhere in `lib/` or the CSS. The stacks are:

```css
--mg-serif: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
--mg-sans:  -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
--mg-mono:  ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace;
```

Pixel identity therefore depends on the viewer's OS fonts, not on any file. `MarginaliaWeb.static_paths()`
lists `fonts` but `priv/static/fonts` does not exist.

**Theme mechanism.**
- `root.html.heex` has an inline `<script>` that sets `data-theme` (`light`/`dark`) and
  `data-theme-source` (`system`/`user`) on `<html>`, stores the choice under `localStorage["phx:theme"]`,
  follows `prefers-color-scheme` while the source is `system`, listens for `storage` events (other tabs),
  and for a `phx:set-theme` window event. The event target's `dataset.phxTheme` is the value.
- The toggle (layouts.ex:224-244) is three buttons with `phx-click={JS.dispatch("phx:set-theme")}` and a
  `data-phx-theme` attribute. Without LiveView, replace the `phx-click` with a plain click listener that
  dispatches the same event; the inline script needs no change.
- The two daisyUI themes are defined in `app.css` lines 17-93: `light` (default; primary
  `oklch(70% 0.213 47.604)`) and `dark` (`prefersdark: true`; base-100 `oklch(30.33% 0.016 252.42)`).
- The hand-written `.mg-*` palette is on `:root` and is not redefined for `data-theme=dark`. `data-theme`
  appears 6 times in `app.css`; the two dark overrides for hand-written classes (lines 4615 and 4767) are
  `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) ... }`, i.e. they follow the
  OS setting, not `data-theme="dark"`. Picking "dark" in the toggle while the OS is light changes the
  daisyUI surfaces but not those two blocks. That is current behaviour and should be copied, not fixed,
  if the goal is identical output.

**Static files** (`priv/static`, served by `Plug.Static` for `assets fonts images favicon.ico robots.txt`):

| file | bytes | referenced by |
|---|---|---|
| `images/og.png` | 145,532 | `layouts.ex:54` default `og:image` (2400x1260 per the comment at :39) |
| `images/og-cases.png` | 211,657 | `case_live/{index,show,read}.ex` `page_image` |
| `images/logo.svg` | 3,072 | no reference found in `lib/` |
| `favicon.ico` | 152 | implicit browser request |
| `robots.txt` | 303 | implicit |

Built output the pages reference: `/assets/css/app.css` (207,738 as above) and `/assets/js/app.js`.
The current JS bundle, built the same way with the repo's esbuild (`--minify`):

```
$ ... _build/esbuild-darwin-arm64 js/app.js --bundle --target=es2022 --outdir=$SCRATCH/js --minify ...
  app.js  188.9kb       (193,405 bytes; 58,551 gzipped)
```

That is phoenix + phoenix_live_view + phoenix_html + topbar + 22 hooks (measured before Rotate was added). The replacement runtime
(section 3) should be a small fraction of this, but the 22 hooks themselves are about 2,500 lines of the
unminified source (appendix), so most of the weight is hooks, not LiveView.

---

## 2. JavaScript

### 2.1 The entry files

`assets/js/app.js` (3,137 bytes) does five things:

1. `import "phoenix_html"` (adds `data-method`/`data-confirm` handling for links and buttons).
2. `new LiveSocket("/live", Socket, {longPollFallbackMs: 2500, params: {_csrf_token}, hooks: {...colocatedHooks}})`
   where `colocatedHooks` comes from `phoenix-colocated/marginalia` (generated into `_build/dev/phoenix-colocated/marginalia/index.js`).
3. topbar progress bar on `phx:page-loading-start` / `phx:page-loading-stop` (`topbar.show(300)` / `topbar.hide()`, blue `#29d`).
4. `liveSocket.connect()`; `window.liveSocket = liveSocket`.
5. A dev-only block (`process.env.NODE_ENV === "development"`) wiring phoenix_live_reload: server-log streaming
   and click-to-open-in-editor on `c`/`d` key + click. Dead in prod.

`assets/vendor/topbar.js` (4,391 bytes): topbar 3.0.0, a canvas drawn progress bar at the top of the window
(`topbar.config`, `show`, `hide`). Pure DOM, portable as-is, or drop it: with fetch-based events the
equivalent is a CSS class on `<html>` while a request is in flight.

`assets/vendor/heroicons.js` (1,394 bytes): the Tailwind plugin described in 1.3; build-time only.

### 2.2 Binding inventory (counts in `lib/`, all files)

```
phx-click=            102        phx-value-*            41
phx-submit=            22        phx-hook=              24 (22 elements + 2 mentions in comments)
phx-change=            15        phx-update=             8 (6 "ignore" in show.ex, 1 in cut_live, 1 stream in core_components)
phx-window-keydown=     1        phx-click-away=         3
phx-debounce=           3        phx-mounted=            4 (all JS.focus() or show/remove_attribute)
phx-disable-with=       3        phx-trigger-action=     2 (login.ex, settings.ex)
phx-connected=          2        phx-disconnected=       2 (the client/server error banners in layouts.ex)
phx-keydown=            0        phx-update="stream"     0 literal (core_components passes a computed value
                                                           only when @rows is a LiveStream; no caller streams)
handle_event/3 clauses: 136      push_event (server to client): 2, both "chat:clear" (show.ex:854, :998)
```

Per file, `phx-click`: work_live/show.ex 36, import_live 11, stack_live/show 8, case_live/read 8,
work_live/index 6, link_live/read 6, case_live/show 6, cut_live/show 5, link_chat 4, core_components 4,
layouts 3, link_live/index 2, case_live/index 2, work_live/new 1.
`phx-submit`: import_live 6, work_live/show 4, work_live/new 2, work_live/index 2, user_live/settings 2,
link_live/index 2, registration 1, login 1, stack_live/new 1, walk 1, link_chat 1.
`phx-change`: import_live 6, settings 2, link_live/index 2, show 1, new 1, registration 1, stack_live/new 1,
linked_live/index 1, case_live/show 1.
`phx-debounce`: import_live.ex:622 (300), link_live/index.ex:345 (150), case_live/show.ex:192 (150).
`phx-window-keydown`: work_live/index.ex:363 (`rename_cancel`).

Every `JS.` command in `lib/` (Phoenix.LiveView.JS), exhaustively:

| file:line | command | purpose |
|---|---|---|
| core_components.ex:43 | `phx-mounted={show("#welcome-back") \|> JS.remove_attribute("hidden")}` | |
| core_components.ex:64 | `JS.push("lv:clear-flash", value: %{key: @kind}) \|> hide("#id")` | dismiss a flash |
| core_components.ex:452, :463 | `JS.show` / `JS.hide` with transitions (helpers `show/2`, `hide/2`) | |
| layouts.ex:189-206 | `JS.remove_attribute("hidden", to: ".phx-client-error #client-error")`, `JS.set_attribute({"hidden",""})` on `phx-connected`/`phx-disconnected` | connection banners |
| layouts.ex:228, :236, :244 | `JS.dispatch("phx:set-theme")` | theme toggle |
| work_live/show.ex:2721 | `phx-click-away={@open && JS.push("toggle_linking")}` | |
| work_live/index.ex:362, registration.ex:36, login.ex:42 | `phx-mounted={JS.focus()}` | autofocus |
| case_live/index.ex:103 | `Phoenix.LiveView.JS.dispatch("mg:walk", to: "#walk")` | starts the tour hook |

No `JS.navigate`, `JS.toggle`, `JS.transition`, `JS.exec`. Navigation is `<.link navigate=...>` /
`patch=...` (live navigation); those become ordinary `<a href>` in the new server.

Other LiveView features in use that are not hooks: `allow_upload` + `live_file_input` + `consume_uploaded_entries`
in `import_live.ex:77,304,763` and `work_live/new.ex:25,63,216`; `phx-trigger-action` for password login/settings
(LiveView validates over the socket, then triggers a native POST); PubSub subscriptions that push renders
(show.ex:26-28 `Analysis.topic`, `Runs.subscribe`; stack_live/show.ex:27; link_live/read.ex:31);
`Process.send_after` for demo mode (show.ex:466,519,823); `Freshness` on_mount that reloads a tab whose asset
URLs changed (`static_changed?`), because a stale bundle meeting new markup throws `unknown hook`.

### 2.3 Hook inventory: 23 colocated hooks

Found with `grep -rn ColocatedHook lib/marginalia_web`. Re-run against commit c9eb474 after the worktree moved from 306e058: line numbers in this table are current; line numbers elsewhere in the notes (flash, banners, push_event sites, `file:line` citations in 2.2) are from 306e058 and have drifted by up to ~25 lines in show.ex, link_chat.ex, read.ex and core_components.ex. The script tag line is the hook's definition;
the "mounted on" line is the `phx-hook=` element. Full verbatim source of each is in the Appendix at
the end of this file (extracted by script from the line ranges below, so it cannot drift from the
original). Two names occur twice in different modules (`.Composer` in link_chat.ex and show.ex); colocated
hooks are namespaced by module, so they are separate hooks (show.ex's one listens for `chat:clear`).

Legend: **push** = `this.pushEvent(name, payload)`; **handle** = `this.handleEvent(name, fn)`;
LV-coupling = reliance on LiveView internals.

| # | hook | defined at (lines) | mounted on | what it does |
|---|---|---|---|---|
| 1 | LinkChat | components/link_chat.ex:113-141 | `div#linkchat` (:47) | Outside-click/Escape closes the chat panel. |
| 2 | Composer | components/link_chat.ex:143-187 | `form#lc-form` (:99) | Enter submits, Shift-Enter newline, textarea autogrow (max 160px). |
| 3 | StickDown | components/link_chat.ex:189-252 | `div#lc-body` (:64) | Scroll policy when an answer lands: long reply snaps to its top and is held. |
| 4 | Walk | components/walk.ex:78-357 | `div#walk` (:59) | Guided tour: spotlight ring + card, auto-clicks real controls. |
| 5 | Clock | live/work_live/show.ex:1712-1725 | `span#read-clock` (:1672) | Counts up from `data-since` once a second. |
| 6 | LaneTree | live/work_live/show.ex:2080-2293 | `div#graph-canvas` (:2067) | Draws the decision graph as an SVG lane tree from `data-graph` JSON; side detail panel. |
| 7 | Hover | live/work_live/show.ex:2613-2639 | `div#rw-list` (:2584) | Hovering a rewrite candidate previews it in the paragraph. |
| 8 | Minimap | live/work_live/show.ex:2817-2891 | `nav#minimap` (:2796) | Open/close contents rail; IntersectionObserver highlights current heading. |
| 9 | Steer | live/work_live/show.ex:3329-3371 | `textarea#rw-steer` (:2557) | Autogrow textarea, Enter submits form. |
| 10 | Deck | live/work_live/show.ex:3373-3443 | `div#deck-<key>` (:4100) | Flips between notes of one kind by moving an `on` class. |
| 11 | Editor | live/work_live/show.ex:3445-3477 | block editor wrapper (:3191) | Autogrow + focus, Escape cancels, Cmd/Ctrl-Enter submits. |
| 12 | Selection | live/work_live/show.ex:3479-3663 | reading column (:1481) | Floating action bar on text selection; click-vs-drag detection to open the editor. |
| 13 | Share | live/work_live/show.ex:3665-3685 | share button (:1439) | Copies `data-url` to the clipboard. |
| 14 | SummaryVault | live/work_live/show.ex:3687-3764 | `div#read-body` (:3062) | Keeps the last 6 summaries per section in localStorage, renders the older ones. |
| 15 | MarginNotes | live/work_live/show.ex:3766-4054 | reading grid (:2968) | Positions margin notes beside their highlights; narrow mode peek/pin popovers. |
| 16 | StickToBottom | live/work_live/show.ex:4445-4463 | `#thread-body-<id>` (:2681) and chat (:4313) | Follow a chat only while the reader is at the bottom. |
| 17 | Composer (show) | live/work_live/show.ex:4465-4488 | `form#chat-form` (:2707), also `#thread-form-<id>` (:2689) | As #2 plus `handleEvent("chat:clear")`. |
| 18 | Wiring | components/link_waiting.ex:101-164 | wiring svg wrapper (:56) | Random candidate arcs between two columns while a job runs. |
| 19 | Reveal | live/landing_live.ex:71-128 | `div#landing` (:440) | Scroll-reveal and timed step playback on the landing page. |
| 20 | Tree | live/work_live/index.ex:229-315 | `div#tree` (:212) | HTML5 drag-and-drop to move works/folders. |
| 21 | Weave | live/cut_live/show.ex:206-304 | `div#weave-<id>` (:134) | Arc diagram of members and links; trial arcs while status is "reading". |
| 22 | Follow | live/link_live/read.ex:466-993 | `div#follow` (:272) | Two-column synchronized reader with SVG wire; phone bottom sheet. |
| 23 | Rotate | components/core_components.ex:537-558 | `span#<id>` (components/core_components.ex:527), `phx-update="ignore"` | Rotates "mutterings" lines in front of the thinking dots: fade out, swap text, fade in, every 3 s. |

Details per hook (DOM touched / browser APIs / server traffic / LiveView coupling):

**1. LinkChat.** DOM: `.lc-panel`, `.lc-foot textarea` inside `#linkchat`. APIs: `document` listeners for `mousedown`, `keydown`.
push `close_chat {}` (outside click, Escape). handle: none. Coupling: `updated()` is used to focus the textarea when the panel
first appears (`this.was`); needs a post-patch callback.

**2. Composer (link_chat).** DOM: `textarea` in the form. APIs: keydown/input, `scrollHeight`, synthetic `new Event("submit", {bubbles, cancelable})`
(this is how it triggers LiveView's form binding; any delegated submit handler also works). push none. handle none.
Coupling: `updated()` resets height only.

**3. StickDown.** DOM: `#lc-body` scroll position, `.lc-turn.assistant:last-child`. APIs: scroll events, `getBoundingClientRect`, `scrollTop`.
push none. Coupling: `updated()` is the trigger that detects a new assistant turn: needs the morph to call it after a patch, and
to keep the same element (it stores `this.seen`, `this.holding` as DOM refs).

**4. Walk.** DOM: `.mg-walk-ring/veil/card`, `h3`, `.body`, `.n`, `.back/.next/.end`; reaches out to `.mg-read-body`, `.mg-block`, `.mg-map-rail`,
`.mg-map`, `.mg-tick`, `#sel-rewrite`, `form[phx-submit="thread_send"]`, and any selector in `data-steps` JSON. APIs: `localStorage` (`mg.tour.<auto>`),
`setInterval` 250 ms, `setTimeout` 550/260 ms, `document.createRange` + `getSelection` (it fakes a text selection), synthetic `MouseEvent("mouseup")`,
`MouseEvent("mousedown")`, `scrollIntoView`, resize/scroll listeners. Listens for DOM event `mg:walk` (dispatched by `JS.dispatch` in case_live/index.ex:103).
push: `end_walk {}`, `walk_hop {to}`, `edit_block {ref}`, `walk_reset {}`, and `step.act.event` with `step.act.params` for arbitrary events named in the server-supplied JSON.
handle: none. Coupling: `updated()` re-measures; hard-coded `form[phx-submit="thread_send"]` is a LiveView attribute name baked into the hook; it
drives the page by clicking real controls so every other hook's selectors must stay stable.

**5. Clock.** DOM: its own `textContent`. APIs: `setInterval(1000)`, `Date.now()`. push/handle none. Coupling none.

**6. LaneTree.** DOM: `svg#graph-svg` (innerHTML rewritten), `#graph-detail` (innerHTML rewritten). APIs: JSON.parse of `data-graph`, SVG string building,
mouseenter/mouseleave/click per row. push/handle none (the panel is client-rendered from the JSON). Coupling: the element is `phx-update="ignore"` and
`updated()` re-draws. Verified in `deps/phoenix_live_view/assets/js/phoenix_live_view/dom.ts:602` and `view.ts:655-659`: for an ignored element LiveView
still merges `data-*` attributes and still calls `updated()` when `dataset` changed. So `data-graph` does refresh. The new morph must reproduce that exact rule
(ignore = skip children and non-data attributes, merge `data-*`, call `updated()` if dataset differs) or the graph goes stale.

**7. Hover.** DOM: `.mg-rw` rows inside `#rw-list`. APIs: mouseover/mouseleave (delegated), `setTimeout` 80 ms. push: `preview_rewrite {i}` (the row's `data-i`),
`clear_preview {}`. Coupling none, but this is the one hook whose feel changes with transport: it sends a round trip per hovered row. Over WebSocket this was
tens of ms; over HTTP POST it needs a queue (below) and may want the previews inlined in the page.

**8. Minimap.** DOM: `a[data-target]`, `.mg-map-rail`, `.mg-map-rail .t`; toggles `open`, `on`; sets `aria-expanded`. APIs: `IntersectionObserver`
(rootMargin `-10% 0px -80% 0px`), `scrollIntoView({behavior:"smooth"})`, `document` click/keydown. push/handle none. Coupling: caches `this.links/rows/ticks/rail` in
`mounted()` and never in `updated()`, so it relies on LiveView keeping the same nodes (it does, by id).

**9. Steer.** DOM: itself (a textarea), its `form`. APIs: input/keydown, synthetic submit. push none. Coupling: `phx-update="ignore"` on the textarea so half-typed text
survives patches; `updated()` re-measures. Needs the ignore rule.

**10. Deck.** DOM: `.cards > .mg-note`, `[data-step]` buttons, `.nav .n`; toggles `on`, `aria-hidden`, `tabIndex`. APIs: click (`stopPropagation`, `preventDefault`), keydown.
push none. Coupling: index kept in `this.at`; `updated()` re-applies it, because a patch replaces the cards.

**11. Editor.** DOM: `textarea` in its element. APIs: input, keydown (Escape, Cmd/Ctrl-Enter), `setSelectionRange`, `focus`. push: `cancel_edit {}`. Submit via synthetic event.
Coupling: none; it has no `updated()`, so correctness relies on the textarea node surviving unrelated patches (focused-input preservation).

**12. Selection.** DOM: `#sel-actions`, `#sel-add`, `#sel-discuss`, `#sel-rewrite`, `.mg-read-body`, `.mg-block`, `.mg-tick`, `mark[id]`; reads attribute
`phx-value-section` off `.mg-tick`; block ids are `block-<ref>`. APIs: `Selection`/`Range` (`getRangeAt`, `compareBoundaryPoints`, `getBoundingClientRect`),
`document` mousedown/mouseup/keyup, window scroll, `requestAnimationFrame`. push: `add_context {text}`, `suggest_rewrite {text, ref}`,
`open_thread {ref, section, quote}`, `edit_block {ref}`. handle none. Coupling: the `phx-value-section` read is a LiveView attribute convention baked in (rename or keep inert);
a server patch that replaces text nodes under a live selection collapses it, which is true of LiveView today.

**13. Share.** DOM: itself. APIs: `navigator.clipboard.writeText`, `window.prompt` fallback, `setTimeout` 1400. push/handle none. Coupling none.

**14. SummaryVault.** DOM: `[data-sum-key]`, `#sumvault-<ordinal>` (itself `phx-update="ignore"`; the hook writes `details/summary/p` into it). APIs: `localStorage`
(`mg:sum:<key>`, 6 entries kept, all access wrapped in try/catch). push/handle none. Coupling: `mounted()` and `updated()` both call `sweep()`; depends on the ignore box keeping what
the hook wrote. Without `updated()` firing after each patch the vault stops saving new summaries.

**15. MarginNotes.** DOM: `.mg-read-rail`, `.mg-note-slot[data-anchor]`, `mark[id^=anchor-]`, `.mg-applied`, `.mg-read-body`, `.mg-map`; sets inline `top/left/width/zIndex/--caret`, classes
`peek pinned lit shoved flipped tailed measured`. APIs: `ResizeObserver`, `getComputedStyle(...).gridTemplateColumns`, `getBoundingClientRect`, `CSS.escape`, `requestAnimationFrame`,
window scroll (capture) and resize, document click. push/handle none. Coupling: highest of all. `watch()` binds mouseenter/click listeners directly on each slot and each `mark` once at mount
and never rebinds; correct only because LiveView/morphdom keeps existing nodes by id. A morph that rebuilds or recreates nodes silently kills hover and pin for them (no error). Re-layout runs
from `updated()`. Recommend porting with delegated listeners (one `mouseover`/`click` on the root) and no per-node binding.

**16. StickToBottom.** DOM: itself (scroll container). APIs: scroll, `scrollTo({behavior})`, `requestAnimationFrame`. push none. Coupling: `updated()` autoscroll.

**17. Composer (show).** As #2, plus `this.handleEvent("chat:clear", () => { ta.value = ""; grow(); ta.focus(); })`. This is the only `handleEvent` in the codebase
and `push_event("chat:clear", %{})` (show.ex:854, 998) the only server push event. Coupling: textarea is client-owned between patches.

**18. Wiring.** DOM: `.lw-svg .arcs`, `.dots`, `.lw-now .l/.r`, `circle[data-side][data-i]`; creates SVG `path` elements. APIs: `setInterval(900)`, `matchMedia("(prefers-reduced-motion)")`,
`getTotalLength`, `setTimeout`. data: `data-a`, `data-b` JSON. push/handle none. Coupling: no `updated()`; if a morph recreates `.arcs` the interval keeps appending into a detached node.

**19. Reveal.** DOM: `[data-reveal]`, `[data-demo]`, `[data-step]`; adds `reveal-ready` to the root, `in` and `on` to children. APIs: `IntersectionObserver`
(rootMargin `0 0 -12% 0`, threshold 0.15), `matchMedia`, `setTimeout`. push/handle none. Coupling none; the landing page is static content and needs no morph.

**20. Tree.** DOM: `[data-drag-id]`, `[data-drag-kind]`, `[data-drop-id]`; toggles `is-dragging`, `is-over`. APIs: HTML5 drag and drop (`dragstart/dragover/drop/dragend`, `dataTransfer`),
all delegated on the container. push: `move {kind, id, into}`. handle none. Coupling none (written delegated on purpose).

**21. Weave.** DOM: `svg` inside; `data-members`, `data-links`, `data-status` JSON/attrs. APIs: `getTotalLength`, CSS animations by `style.animation`, `requestAnimationFrame`/`setTimeout`,
`matchMedia`. push/handle none. Coupling: `phx-update="ignore"` + `updated()` redraw, same data-attribute rule as LaneTree (`data-status` flips `reading` to settled).

**22. Follow.** DOM: `#fl-lead`, `#fl-other`, `.fl-strip`, `.fl-sheet`, `.fl-stack`, `.fl-wire` (SVG with `.w1 .w2 .h1 .h2 .d1 .d2`), `.fl-split`, `.fl-idle`, `.fl-count b`, `.fl-mid`,
`.fl-block.linked`, `[data-peer-ref]`, `[data-edge]`, `.fl-jump`, `.fl-card .ask`; creates card nodes with `createElement`. APIs: scroll (passive) with `requestAnimationFrame`
throttle, `wheel` (non-passive, `preventDefault`), `matchMedia("(max-width: 1100px)")`, `getBoundingClientRect`, `scrollTo({behavior:"smooth"})`, `performance.now()`, `CSS.escape`, `getSelection`,
document keydown. push: `cite_edge {edge}` (three paths). handle none. Coupling: written defensively for LiveView patches (`cache()` re-queries nodes in `updated()`, listeners are delegated on
`this.el`, a comment records the bug when they were not). That is the style to port the others toward.

**23. Rotate** (added after commit 306e058, by the mutterings commits). DOM: itself, a `span.mg-mutter` inside `.mg-dots`; reads `data-lines` (JSON array), sets `textContent`, toggles
class `out` (CSS: `.mg-mutter.out { opacity: 0 }`, `transition: opacity .32s`). APIs: `setInterval(3000)`, `setTimeout(320)`. push/handle none. Coupling: `phx-update="ignore"`; no `updated()`,
so a changed `data-lines` is never picked up after mount (same as today under LiveView, where `updated()` would fire but is not defined). `destroyed()` clears both timers; the 320 ms swap timer is the
only handle that survives if the interval is cleared mid-fade, and `destroyed()` handles it. Ports trivially (needs only the ignore rule and the `destroyed()` call when the dots are removed).

Summary: **23 hooks; 1 `handleEvent` name (`chat:clear`); 7 hooks push events** (LinkChat, Walk, Hover, Editor, Selection, Tree, Follow), using 13 distinct
event names: `close_chat end_walk walk_hop edit_block walk_reset preview_rewrite clear_preview cancel_edit add_context suggest_rewrite open_thread move cite_edge`
(plus whatever event names the server puts in Walk's `data-steps` JSON). The other 16 push nothing.
No hook uses `pushEventTo`, `this.upload`, `liveSocket`, `JS` commands, `this.js()`, or `phx-target`.

Mechanisms from LiveView that the hooks lean on, all of them:

1. `this.el` and the lifecycle `mounted / updated / destroyed`.
2. `updated()` being called when LiveView changed the element or its subtree (12 hooks define it: LinkChat, Composer-lc, StickDown, Walk, LaneTree, Steer, Deck, SummaryVault, MarginNotes, StickToBottom, Weave, Follow).
3. DOM node identity preserved across patches for elements with an `id`.
4. `phx-update="ignore"` (Steer, LaneTree, Weave; also the SummaryVault box).
5. `pushEvent` and `handleEvent` (listed above).
6. The dispatched-event convention for submit (`new Event("submit", {bubbles:true, cancelable:true})`): LiveView listens for `submit` on `form[phx-submit]`; a delegated
   `submit` listener in a new runtime is hit identically.
7. Two attribute-name conventions leaked into hook code: `phx-value-section` (Selection) and `form[phx-submit="thread_send"]` (Walk).

---

## 3. Replacement client runtime

Goal: one vanilla JS file, no CDN, no framework, that gives the new server (any server that returns HTML)
the three things LiveView supplied: event delivery, patching, server push. Estimated size: 250-350 lines plus the hooks.

### 3.1 Protocol

- **Event delivery.** Delegated listeners on `document`.
  - `click` on `[data-ev]` sends event `data-ev` with payload from `data-v-*` attributes (`data-v-ref="3"` becomes `{ref:"3"}`).
    This is `phx-click` + `phx-value-*` renamed. (Alternative with zero template edits: the runtime also accepts the literal names
    `phx-click`, `phx-submit`, `phx-change`, `phx-value-*`, `phx-hook`, `phx-update`, `phx-debounce`, `phx-click-away`, `phx-window-keydown`. 102+22+15+41+24+8+3+3+1 = 219
    attribute uses move unchanged. Recommended for the port; rename later.)
  - `submit` on `form[data-ev]` sends `Object.fromEntries(new FormData(form))`, disables the submit button (`phx-disable-with`), adds `.phx-submit-loading`.
  - `input` on `form[data-ev-change]` sends the form debounced by `data-debounce` (15 uses of `phx-change`; 3 debounces: 150/300 ms).
  - Transport: `POST /ev/<name>` with header `X-CSRF-Token` (the `<meta name="csrf-token">` already exists), body JSON `{payload, path}`.
- **Response.** JSON: `{regions: {"#main": "<html>"}, events: [{name:"chat:clear", payload:{}}], redirect: "/x", title: "..."}`.
  The server re-renders the whole view it was asked about and returns `<main>` (simplest, and what LiveView's diff effectively does). Regions are an optimization.
- **Ordering.** One in-flight promise chain per page (`queue = queue.then(...)`), the equivalent of the single WebSocket's ordering. Without it, a fast
  `preview_rewrite` then `clear_preview` can arrive reordered.
- **Server push.** `EventSource` on `/stream?path=...` (server-sent events). Messages: `{"refresh": true}` (client GETs the current URL with `X-Blimp-Region: main` and morphs the
  result; this is `live_refresh/1` on the `{:status,_}`, `{:section,..}`, `{:run,:progress,..}`, `{:graph,..}` PubSub messages) and `{"events":[...]}` (for `handleEvent` targets).
  On reconnect, refresh once (LiveView re-mounts on reconnect). Polling fallback: `<main data-poll="2">` makes the runtime `setInterval`-GET every 2 s. WebSocket is not needed:
  there is no token-by-token streaming in this codebase (replies land whole via `handle_info`), nothing is client-to-server over the socket except events, and SSE passes through
  proxies without extra config. Use WebSocket only if you later stream partial replies in both directions.
- **Navigation.** `<a href>` full page loads, or intercept same-origin link clicks, `fetch`, and morph `<body>`'s `<main>`; `history.pushState`. The first is correct and cheapest.
  (`Freshness` goes away: a full page load always brings a matching bundle.)
- **Loading UI.** `html.classList.add("blimp-busy")` while any request is in flight; reuse `topbar` or a CSS bar. Replace the `#client-error`/`#server-error` banners with
  a fetch failure handler that un-hides them.
- **Not hooks, still needed:** `JS.dispatch("phx:set-theme")` becomes a click listener on `[data-phx-theme]`; `phx-mounted JS.focus()` becomes `autofocus`;
  `phx-click-away` becomes one `document` click listener checking `closest`; `JS.show/hide` with transitions becomes `hidden` toggles plus the existing CSS;
  `phx-trigger-action` becomes a normal form POST (the server validates and either re-renders the page with errors or redirects); uploads become `<form enctype="multipart/form-data">`
  with a progress bar from `XMLHttpRequest` (two upload forms: import_live, work_live/new). The upload one is the only non-trivial LiveView feature to replace.

### 3.2 Is a hand-written morph feasible? Yes, about 80 lines

idiomorph/morphdom from a CDN is excluded; vendoring morphdom (about 3 KB gz) is allowed but not needed. What the existing hooks require from a patch is narrow:

1. Elements with an `id` are matched by id and keep identity (including moved).
2. Same-position elements with the same tag and no id are patched in place; otherwise replaced.
3. Attributes are synced both ways (class is overwritten by the server, exactly as LiveView does today, so hooks already re-add their classes in `updated()`).
4. The focused input/textarea/select keeps its value and selection; other form controls take the server value.
5. `data-morph="ignore"` (alias for `phx-update="ignore"`): skip children and non-`data-*` attributes, merge `data-*`, report as updated if `dataset` changed.
6. After the patch call `updated()` on hooks whose element was changed, `destroyed()` on hooks whose element was removed, `mounted()` on new ones.
7. Skip work with `isEqualNode` (so `updated()` fires only on change, as in LiveView).

Sketch (not tested; the algorithm, not the final file):

```js
// blimp.js
(() => {
  const hooks = {};                    // name -> definition object
  const live = new WeakMap();          // element -> hook instance
  const csrf = document.querySelector("meta[name=csrf-token]")?.content;
  let queue = Promise.resolve();

  // ---------- events ----------
  function send(name, payload = {}, from) {
    from?.classList.add("phx-click-loading");
    document.documentElement.classList.add("blimp-busy");
    queue = queue.then(async () => {
      try {
        const res = await fetch(`/ev/${name}`, {
          method: "POST", credentials: "same-origin",
          headers: {"content-type": "application/json", "x-csrf-token": csrf},
          body: JSON.stringify({payload, path: location.pathname + location.search}),
        });
        if (!res.ok) throw new Error(res.status);
        apply(await res.json());
      } catch (e) { showBanner("#server-error"); }
      finally {
        from?.classList.remove("phx-click-loading");
        document.documentElement.classList.remove("blimp-busy");
      }
    });
    return queue;
  }

  const values = (el) => Object.fromEntries(
    [...el.attributes].filter(a => a.name.startsWith("data-v-"))
      .map(a => [a.name.slice(7), a.value]));

  document.addEventListener("click", (e) => {
    const el = e.target.closest("[data-ev]");
    if (!el || el.matches("form")) return;               // forms go through "submit"
    if (el.type === "submit" && el.form?.dataset.ev) return;
    send(el.dataset.ev, values(el), el);
  });
  document.addEventListener("submit", (e) => {
    const f = e.target.closest("form[data-ev]"); if (!f) return;
    e.preventDefault();
    send(f.dataset.ev, Object.fromEntries(new FormData(f)), f);
  });

  // ---------- apply a response ----------
  function apply({regions = {}, events = [], redirect, title}) {
    if (redirect) return void (location.href = redirect);
    if (title) document.title = title;
    for (const [sel, html] of Object.entries(regions)) {
      const el = document.querySelector(sel);
      const to = el.cloneNode(false); to.innerHTML = html;
      morphChildren(el, to);
    }
    for (const ev of events) for (const h of handlers.get(ev.name) || []) h(ev.payload);
  }

  // ---------- morph ----------
  const touched = new Set(), removed = new Set(), added = new Set();
  function morphChildren(from, to) {
    const keyed = new Map();
    for (const n of from.children) if (n.id) keyed.set(n.id, n);
    let cur = from.firstChild;
    for (const want of [...to.childNodes]) {
      let have = want.id && keyed.get(want.id);
      if (!have && cur && !cur.id && cur.nodeName === want.nodeName) have = cur;
      if (have) {
        if (have === cur) cur = cur.nextSibling; else from.insertBefore(have, cur);
        morphNode(have, want);
      } else { from.insertBefore(want, cur); if (want.nodeType === 1) added.add(want); }
    }
    while (cur) { const next = cur.nextSibling; if (cur.nodeType === 1) removed.add(cur); cur.remove(); cur = next; }
  }
  function morphNode(a, b) {
    if (a.nodeType !== 1) { if (a.nodeValue !== b.nodeValue) a.nodeValue = b.nodeValue; return; }
    if (a.isEqualNode(b)) return;
    const ignore = a.dataset.morph === "ignore" || a.getAttribute("phx-update") === "ignore";
    for (const {name, value} of b.attributes)
      if ((!ignore || name.startsWith("data-")) && a.getAttribute(name) !== value) a.setAttribute(name, value);
    if (!ignore) for (const {name} of [...a.attributes]) if (!b.hasAttribute(name)) a.removeAttribute(name);
    if (ignore) { if (JSON.stringify({...a.dataset}) !== JSON.stringify({...b.dataset})) touched.add(a); return; }
    if (/^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName) && a !== document.activeElement) a.value = b.value; // simplified
    if (a.tagName !== "TEXTAREA") morphChildren(a, b);
    touched.add(a);
  }
  // after each apply(): for el of touched -> live.get(el)?.updated?.(); for removed -> destroyed(); for added -> mountHooks(el)

  // ---------- hooks: pushEvent / handleEvent shim ----------
  const handlers = new Map();
  function mount(el) {
    const name = el.dataset.hook || el.getAttribute("phx-hook")?.replace(/^\./, "");
    const def = hooks[name];
    if (!def) throw new Error(`unknown hook ${name}`);        // fail loudly, as LiveView does
    const h = Object.create(def);
    h.el = el;
    h.pushEvent = (n, p = {}) => send(n, p, el);
    h.handleEvent = (n, fn) => { (handlers.get(n) || handlers.set(n, []).get(n)).push(fn); };
    live.set(el, h); h.mounted?.();
  }
  window.Blimp = {hook: (name, def) => (hooks[name] = def)};
  // each ported hook file: Blimp.hook("Deck", { mounted() {...}, updated() {...}, ... })
})();
```

Because the 22 hooks are written as `export default { mounted(), updated(), destroyed(), ... }` objects, porting is: strip `export default`, wrap in
`Blimp.hook("Name", {...})`, and namespace the two `Composer`s (`LinkChatComposer`, `ChatComposer`).

Known gaps in this sketch that the real file needs: `<option>`/checkbox/radio sync, `<select>` value, `contenteditable`, scroll preservation for nodes that are replaced,
removal of listeners for `handleEvent` in `destroyed`, and `data-v-*` values coerced to the types the server expects (LiveView sends strings too, so strings are fine).

### 3.3 Which hooks port how

**Trivial (no server DOM contract beyond `this.el`, no `updated()` dependence): 12**
Clock, Share, Reveal, Tree (pushEvent only, delegated), Hover (pushEvent only; see latency note), Editor (pushEvent only), LinkChat (pushEvent only; its `updated()` focus
nicety needs a post-patch call), Composer (link_chat), Composer (show; `handleEvent("chat:clear")` maps to the `events` array), Steer (needs the ignore rule), Rotate (ignore rule, timers only), Wiring
(timer-only; move the interval handle so it re-looks-up `.arcs` each tick to survive a morph).

**Port with the morph preserving DOM nodes and calling `updated()`: 9**
StickDown, StickToBottom (scroll container must be the same node; `updated()` decides scrolling), Deck (cards replaced by patch, `updated()` reapplies `at`), Minimap (caches
nodes at mount; needs identity stability or `updated()` re-cache), SummaryVault (`updated()` sweep; contains an ignore subtree), LaneTree and Weave (ignore + data-attribute change + `updated()`),
Walk (re-measure in `updated()`; its `go()` drives real controls so selectors must stay), Follow (already re-queries in `updated()` and uses delegation; the best-behaved).

**Need rework, not just a shim: 2**
- **MarginNotes**: per-node listeners bound once in `watch()`. With LiveView this works because nodes keep identity; with any morph that replaces nodes (or a new note added by a
  server push) the new `.mg-note-slot` and `mark[id]` have no listeners and nothing logs. Convert to delegated `mouseover/mouseout/click` on `this.el`
  and re-run `layout()` from `updated()` (it already does). About 20 lines of change.
- **Selection**: no problem in logic, but it reads `phx-value-section` and drives the `mouseup` / `keyup` / `mousedown` sequence on `document`. Two things need care: (1) a morph that
  rewrites paragraph text nodes while the user holds a selection will collapse it, so the runtime must not apply a push-triggered refresh while `getSelection()` is non-collapsed
  inside `.mg-read-body` (defer until it is); LiveView had the same hazard and it is only partly mitigated there. (2) the `edit_block` click-versus-drag logic assumes immediate
  server feedback; with an HTTP round trip the editor appears one RTT later and the user may have started another gesture. The queue and `blimp-busy` class cover most of it.

**Cannot be ported faithfully:** nothing in the 22 hooks is impossible. What does not carry over exactly is behaviour that came from the socket rather than from the hooks:

1. **Latency-sensitive hover** (`Hover` pushing `preview_rewrite` per row). Same code, different feel. Fix by sending all candidates' replacement text in the page and previewing client-side, which
   is a behaviour-preserving change, but it is a change.
2. **Ordering and presence guarantees** of one socket (ordered events, automatic reconnect with re-mount, `phx-connected` banners, `phx-click-away` with `@open &&` computed per render). Reproduced
   by the queue, SSE reconnect + refresh, and a document click listener, not by identical code.
3. **LiveView uploads** (progress, validation while choosing a file). Replaced by a form post; not hook code but it is the one place the UI would visibly differ.
4. **`phx-update` semantics when LiveView patches an element that has focus** (it keeps the focused input's value and selection and skips patching it in some cases); the sketch handles the
   `activeElement` case only. Anything stricter (preserving caret in a non-focused textarea) would need extra code.
5. Whatever the Elixir side relies on in `static_changed?` / `Freshness`: gone, and no longer needed.

### 3.4 Order of work

1. Commit the compiled CSS and `og*.png`, `favicon.ico`, `robots.txt`; serve them statically.
2. Write `blimp.js` with delegated events, `apply`, morph, SSE, hook shim; accept the `phx-*` attribute names at first.
3. Move the 23 hooks over mechanically (strip `export default`, wrap, rename the two Composers). Run each page against a fixture HTML of the original and diff the DOM after a scripted
   gesture (hooks mutate the DOM; the DOM after `mounted()` is a testable artifact).
4. Fix MarginNotes delegation; add the Selection deferral.
5. Replace uploads and the login `phx-trigger-action` with plain form posts.

---

# Appendix: the 23 hooks, verbatim

Extracted by script from `lib/marginalia_web/**` at c9eb474 at the line ranges in the table in 2.3 (common
indentation removed, nothing else changed).

## 1. LinkChat

`lib/marginalia_web/components/link_chat.ex:113-141`

```js
// Click anywhere outside the panel and it puts itself away. The
// conversation is server-side, so this loses nothing — reopening
// comes back to the same place.
export default {
  mounted() {
    this.away = (e) => {
      if (!this.el.querySelector(".lc-panel")) return;
      if (this.el.contains(e.target)) return;
      this.pushEvent("close_chat", {});
    };
    this.esc = (e) => e.key === "Escape" && this.pushEvent("close_chat", {});
    document.addEventListener("mousedown", this.away);
    document.addEventListener("keydown", this.esc);
  },

  updated() {
    // focus the box when the panel has just appeared
    const box = this.el.querySelector(".lc-foot textarea");
    if (box && !this.was) box.focus();
    this.was = !!this.el.querySelector(".lc-panel");
  },

  destroyed() {
    document.removeEventListener("mousedown", this.away);
    document.removeEventListener("keydown", this.esc);
  },
};
```

## 2. Composer (link_chat)

`lib/marginalia_web/components/link_chat.ex:143-187`

```js
// Enter sends; shift-Enter is a newline. The form said "Enter to
// send" and named this hook, and the hook was never written — so
// LiveView threw `unknown hook` on the client, the binding for
// the form never attached, and the panel opened, took typing and
// sent nothing. Server-side tests cannot see that: they do not
// run the hooks.
export default {
  mounted() {
    this.box = this.el.querySelector("textarea");
    if (!this.box) return;

    this.onKey = (e) => {
      if (e.key !== "Enter" || e.shiftKey || e.isComposing) return;
      e.preventDefault();
      if (this.box.value.trim() === "") return;
      this.el.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}));
    };

    // two rows is right for a question and wrong for a paragraph
    this.grow = () => {
      this.box.style.height = "auto";
      this.box.style.height = Math.min(this.box.scrollHeight, 160) + "px";
    };

    this.box.addEventListener("keydown", this.onKey);
    this.box.addEventListener("input", this.grow);
    this.box.focus();
  },

  updated() {
    // the textarea is cleared by the server on send; put the
    // cursor back where someone would carry on typing
    if (this.box && !this.box.disabled && document.activeElement !== this.box) {
      this.box.style.height = "auto";
    }
  },

  destroyed() {
    if (!this.box) return;
    this.box.removeEventListener("keydown", this.onKey);
    this.box.removeEventListener("input", this.grow);
  },
};
```

## 3. StickDown

`lib/marginalia_web/components/link_chat.ex:189-252`

```js
// Where to put the scroll when an answer lands.
//
// Sticking to the bottom is right for short replies and wrong for
// long ones: it drops the reader at the last line of something they
// have not read a word of, and they have to scroll *up* to find the
// beginning. So a reply taller than the panel is snapped to its own
// top instead, and held there — no auto-scrolling while they read.
//
// The hold is released the moment they reach the end of it. From
// then on the panel sticks to the bottom again, which is what you
// want once you are caught up.
export default {
  mounted() {
    this.bottom();
    this.el.addEventListener("scroll", () => this.check(), {passive: true});
  },

  updated() {
    const last = this.el.querySelector(".lc-turn.assistant:last-child");

    if (last && last !== this.seen) {
      this.seen = last;
      const room = this.el.clientHeight - 24;

      if (last.offsetHeight > room) {
        // start them at the first line of it
        this.holding = last;
        this.el.scrollTop = this.topOf(last) - 8;
        return;
      }

      this.holding = null;
      return this.bottom();
    }

    // a turn being added while they are caught up
    if (!this.holding && this.near()) this.bottom();
  },

  // the reader has read to the end of the held reply, so let go
  check() {
    if (!this.holding) return;
    const end = this.topOf(this.holding) + this.holding.offsetHeight;
    if (this.el.scrollTop + this.el.clientHeight >= end - 8) this.holding = null;
  },

  topOf(el) {
    return (
      el.getBoundingClientRect().top -
      this.el.getBoundingClientRect().top +
      this.el.scrollTop
    );
  },

  near() {
    return this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 120;
  },

  bottom() {
    this.el.scrollTop = this.el.scrollHeight;
  },
};
```

## 4. Walk

`lib/marginalia_web/components/walk.ex:78-357`

```js
// Spotlight one control, press it, wait for the page to answer, move
// on. The spotlight is a transparent box over the control with a
// very large shadow spread, so the lit thing keeps its own colours
// and everything else goes under a tint.
export default {
  mounted() {
    this.steps = JSON.parse(this.el.dataset.steps || "[]");
    this.i = -1;

    this.ring = this.el.querySelector(".mg-walk-ring");
    this.veil = this.el.querySelector(".mg-walk-veil");
    this.card = this.el.querySelector(".mg-walk-card");

    this.auto = this.el.dataset.auto || null;
    this.card.querySelector(".end").addEventListener("click", () => this.stop());
    this.card.querySelector(".next").addEventListener("click", () => this.go(this.i + 1));
    this.card.querySelector(".back").addEventListener("click", () => this.go(this.i - 1));

    // in auto mode the page always renders the overlay and the
    // button only asks it to run, so there is no round trip and
    // no account to remember it on
    this.onAsk = () => this.begin(true);
    this.el.addEventListener("mg:walk", this.onAsk);

    this.onKey = (e) => {
      if (e.key === "Escape") this.stop();
      if (e.key === "ArrowRight") this.go(this.i + 1);
      if (e.key === "ArrowLeft") this.go(this.i - 1);
    };
    document.addEventListener("keydown", this.onKey);

    // the target moves: panels open below it, the margin reflows,
    // the page scrolls. Re-measure rather than paint once.
    this.track = () => this.place();
    window.addEventListener("scroll", this.track, {passive: true});
    window.addEventListener("resize", this.track);
    this.timer = setInterval(this.track, 250);

    this.begin(false);
  },

  // `forced` is the button; otherwise it is a first visit
  begin(forced) {
    if (!this.auto) return this.go(0);

    const key = `mg.tour.${this.auto}`;
    let seen = false;
    try { seen = localStorage.getItem(key) === "1"; } catch (_) {}

    if (seen && !forced) return;

    try { localStorage.setItem(key, "1"); } catch (_) {}
    this.go(0);
  },

  // in auto mode the overlay stays in the DOM, so ending it is
  // the hook's job rather than the server's
  stop() {
    if (!this.auto) return this.pushEvent("end_walk", {});
    this.i = -1;
    this.card.hidden = true;
    this.ring.hidden = true;
    this.veil.hidden = true;
  },

  updated() {
    // a step's action re-renders the page; the element it lit may
    // have been replaced, so look it up again
    this.place();
  },

  destroyed() {
    document.removeEventListener("keydown", this.onKey);
    this.el.removeEventListener("mg:walk", this.onAsk);
    window.removeEventListener("scroll", this.track);
    window.removeEventListener("resize", this.track);
    clearInterval(this.timer);
  },

  go(i) {
    if (i < 0) return;
    if (i >= this.steps.length) return this.stop();

    this.i = i;
    const step = this.steps[i];

    this.card.querySelector("h3").textContent = step.title;
    this.card.querySelector(".body").textContent = step.body;
    this.card.querySelector(".n").textContent = `${i + 1} / ${this.steps.length}`;
    this.card.querySelector(".back").disabled = i === 0;
    this.card.querySelector(".next").textContent =
      i === this.steps.length - 1 ? "Done" : "Next";

    this.card.hidden = false;
    this.place();

    // let the spotlight land before the control is pressed, or the
    // reader never sees which one it was
    clearTimeout(this.actTimer);
    this.actTimer = setTimeout(() => this.act(step), 550);
  },

  act(step) {
    if (!step.act || this.i !== this.steps.indexOf(step)) return;

    if (step.act.kind === "push") {
      this.pushEvent(step.act.event, step.act.params || {});
    } else if (step.act.kind === "click") {
      // a control with no server event of its own: a details
      // summary, a link, the rail. Clicking it is what a reader
      // does, so the tour does the same thing.
      document.querySelector(step.act.target)?.click();
    } else if (step.act.kind === "hop") {
      // the cases are read across three views, and a tour that
      // stopped at a page boundary would be a tour of one page
      this.pushEvent("walk_hop", {to: step.act.to});
    } else {
      this.client(step.act.name);
    }
    setTimeout(() => this.place(), 260);
  },

  // Everything here goes through the real control: the tour clicks
  // what you would click. The only thing it does that you cannot is
  // make a text selection, which has no button.
  client(name) {
    const body = document.querySelector(".mg-read-body");
    const block = body && body.querySelector(".mg-block");

    if (name === "open_map") {
      const rail = document.querySelector(".mg-map-rail");
      if (rail && !document.querySelector(".mg-map").classList.contains("open")) rail.click();
      return;
    }

    if (name === "open_thread") {
      const tick = block && block.querySelector(".mg-tick");
      if (tick) tick.click();
      return;
    }

    if (name === "ask_thread") {
      const form = document.querySelector('form[phx-submit="thread_send"]');
      const box = form && form.querySelector("textarea, input[name=message]");
      if (!box) return;
      box.value = "What is this paragraph actually doing?";
      box.dispatchEvent(new Event("input", {bubbles: true}));
      form.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}));
      return;
    }

    if (name === "select") {
      const p = block && block.querySelector("p");
      if (!p) return;
      const range = document.createRange();
      range.selectNodeContents(p);
      const sel = window.getSelection();
      sel.removeAllRanges();
      sel.addRange(range);
      // the selection toolbar listens on the document, as a real
      // drag would end
      document.dispatchEvent(new MouseEvent("mouseup", {bubbles: true}));
      return;
    }

    if (name === "rewrite") {
      const btn = document.querySelector("#sel-rewrite");
      // it binds mousedown, because a click clears the selection first
      if (btn) btn.dispatchEvent(new MouseEvent("mousedown", {bubbles: true, cancelable: true}));
      return;
    }

    if (name === "edit") {
      if (block) this.pushEvent("edit_block", {ref: block.id.replace(/^block-/, "")});
      return;
    }

    if (name === "reset") {
      window.getSelection()?.removeAllRanges();
      document.querySelector(".mg-map")?.classList.remove("open");
      // the server holds the thread, the rewrite and the open editor
      this.pushEvent("walk_reset", {});
    }
  },

  target() {
    const step = this.steps[this.i];
    return step && step.target ? document.querySelector(step.target) : null;
  },

  place() {
    if (this.card.hidden) return;
    const el = this.target();

    if (!el) {
      // a step with nothing to point at — or a target that has not
      // rendered yet. Centre the card and drop the spotlight rather
      // than lighting the top-left corner of the page.
      this.ring.hidden = true;
      this.veil.hidden = false;
      this.card.className = "mg-walk-card centre";
      this.card.style.top = "";
      this.card.style.left = "";
      return;
    }

    const r = el.getBoundingClientRect();
    const pad = 6;
    const box = {
      top: r.top - pad, left: r.left - pad,
      width: r.width + pad * 2, height: r.height + pad * 2,
    };

    if (r.top < 90 || r.bottom > window.innerHeight - 60) {
      // the reading views scroll a column, not the window, and
      // scrollIntoView on a child of an overflow box moves that
      // box — which is exactly what is wanted here
      el.scrollIntoView({behavior: "smooth", block: "center"});
    }

    this.ring.hidden = false;
    this.veil.hidden = true;
    Object.assign(this.ring.style, {
      top: `${box.top}px`, left: `${box.left}px`,
      width: `${box.width}px`, height: `${box.height}px`,
    });

    this.card.className = "mg-walk-card";
    const cw = 22 * 16, gap = 16, m = 12;
    const ch = this.card.offsetHeight || 220;
    const W = window.innerWidth, H = window.innerHeight;

    // Candidates in the order the step asked for, then the rest.
    // A card that covers the thing it is pointing at defeats the
    // spotlight, so the clamped position is only taken when no
    // side fits — and even then it is the side with most room.
    const spots = {
      bottom: {left: box.left, top: box.top + box.height + gap},
      top: {left: box.left, top: box.top - ch - gap},
      right: {left: box.left + box.width + gap, top: box.top},
      left: {left: box.left - cw - gap, top: box.top},
    };

    const order = [this.steps[this.i].place || "right", "right", "left", "bottom", "top"];
    const fits = (p) =>
      p && p.left >= m && p.top >= m && p.left + cw <= W - m && p.top + ch <= H - m;

    let pick = order.map((k) => spots[k]).find(fits);

    if (!pick) {
      // no side fits whole; take the roomiest and clamp it, then
      // push it clear of the ring if it still overlaps
      const room = {
        bottom: H - (box.top + box.height), top: box.top,
        right: W - (box.left + box.width), left: box.left,
      };
      const best = Object.keys(room).sort((a, b) => room[b] - room[a])[0];
      pick = spots[best];
    }

    let left = Math.max(m, Math.min(pick.left, W - cw - m));
    let top = Math.max(m, Math.min(pick.top, H - ch - m));

    const over =
      left < box.left + box.width && left + cw > box.left &&
      top < box.top + box.height && top + ch > box.top;

    if (over) {
      // slide it to whichever side of the ring has the room
      left = box.left > W - (box.left + box.width)
        ? Math.max(m, box.left - cw - gap)
        : Math.min(W - cw - m, box.left + box.width + gap);
    }

    this.card.style.left = `${left}px`;
    this.card.style.top = `${top}px`;
  },
};
```

## 5. Clock

`lib/marginalia_web/live/work_live/show.ex:1712-1725`

```js
// Counts up from when the read started. Server-side ticking would mean
// a message a second per viewer to render a number nobody acts on.
export default {
  mounted() { this.tick(); this.t = setInterval(() => this.tick(), 1000); },
  destroyed() { clearInterval(this.t); },
  tick() {
    const since = Number(this.el.dataset.since);
    if (!since) return;
    const s = Math.max(0, Math.floor(Date.now() / 1000) - since);
    this.el.textContent = Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
  },
};
```

## 6. LaneTree

`lib/marginalia_web/live/work_live/show.ex:2080-2293`

```js
// A git-log style lane tree: one row per node, a dot in a narrow lane
// column, the title beside it. The trunk (each node's first child) runs
// straight down; every other child branches into a fresh lane where it
// diverges. No d3 — a force layout of a few hundred nodes is an
// unreadable hairball, and this is lines and circles.
//
// Clicking a row fills the panel beside it. That panel is the point:
// a shape with no way to read the node under the dot tells you the
// graph exists but nothing about what it claims.
const COLOR = {
  goal: "#8a3324", option: "#b45309", decision: "#1e3a8a",
  action: "#166534", outcome: "#0891b2", observation: "#6b665e",
  revisit: "#7c2d92", spine: "#8a3324", beat: "#166534",
  thread: "#0891b2", question: "#7c2d92", note: "#9a948a",
};
const esc = (t) => String(t == null ? "" : t)
  .replace(/[&<>"]/g, (c) => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

export default {
  mounted() { this.draw(); },
  updated() { this.draw(); },

  draw() {
    const data = JSON.parse(this.el.dataset.graph || "{}");
    const nodes = data.nodes || [];
    const edges = data.edges || [];
    const svg = this.el.querySelector("svg");
    if (!nodes.length) { svg.innerHTML = ""; return; }

    const byId = new Map(nodes.map((n) => [n.id, n]));
    this.byId = byId;
    this.edges = edges;

    // first edge into a node is its parent; the rest are cross-links
    const parentOf = new Map(), secondary = [];
    [...edges].sort((a, b) => a.id - b.id).forEach((e) => {
      if (!parentOf.has(e.to_node_id)) parentOf.set(e.to_node_id, e.from_node_id);
      else secondary.push(e);
    });

    const kids = new Map();
    nodes.forEach((n) => {
      const p = parentOf.get(n.id);
      if (p !== undefined) { if (!kids.has(p)) kids.set(p, []); kids.get(p).push(n.id); }
    });

    // A node's lane is how deep a branch it sits on, not the order it
    // was allocated in. The first child continues its parent's lane —
    // that is the trunk — and every other child opens one lane to the
    // right of it. Allocating a fresh lane per branch instead made the
    // tree walk off the right-hand side as a staircase; recycling
    // lanes flattened every branch back onto the trunk. Depth is the
    // thing a reader is actually looking for, and it is bounded by how
    // nested the argument is rather than by how long the draft is.
    const row = new Map(), lane = new Map();
    let r = 0;

    const walk = (startId, l) => {
      let id = startId;
      while (id != null) {
        if (row.has(id)) return;          // a cycle would spin here
        row.set(id, r++); lane.set(id, l);
        const cs = (kids.get(id) || []).filter((k) => !row.has(k));
        if (!cs.length) { id = null; }
        else { for (let i = 1; i < cs.length; i++) walk(cs[i], l + 1); id = cs[0]; }
      }
    };
    const roots = nodes.filter((n) => !parentOf.has(n.id));
    roots.forEach((n) => walk(n.id, 0));
    nodes.forEach((n) => { if (!row.has(n.id)) walk(n.id, 0); });

    const rowH = 21, laneW = 12, x0 = 12, gap = 16;
    const maxLane = Math.max(0, ...lane.values());
    const cap = Math.min(maxLane, 12);
    // clamped, so a deep lane can never be drawn past the gutter and
    // land on top of the label — which is exactly what it was doing
    const xOf = (l) => x0 + Math.min(l, cap) * laneW;
    const yOf = (id) => row.get(id) * rowH + 16;
    const labelX = x0 + cap * laneW + gap;
    const width = labelX + 640;
    const height = r * rowH + 28;
    const parts = [];

    secondary.forEach((e) => {
      if (!row.has(e.from_node_id) || !row.has(e.to_node_id)) return;
      const ax = xOf(lane.get(e.from_node_id)) - 5, ay = yOf(e.from_node_id);
      const bx = xOf(lane.get(e.to_node_id)) - 5, by = yOf(e.to_node_id);
      const mx = Math.min(ax, bx) - 10;
      parts.push(`<path d="M${ax},${ay} C${mx},${ay} ${mx},${by} ${bx},${by}" fill="none" stroke="#8a3324" stroke-opacity=".3" stroke-dasharray="1,3"/>`);
    });

    kids.forEach((cs, pid) => {
      if (!row.has(pid)) return;
      cs.forEach((cid) => {
        if (!row.has(cid)) return;
        const ax = xOf(lane.get(pid)), ay = yOf(pid);
        const bx = xOf(lane.get(cid)), by = yOf(cid);
        const stroke = COLOR[byId.get(cid)?.marginalia_type] || "#9a948a";
        const d = ax === bx
          ? `M${ax},${ay} L${bx},${by}`
          : `M${ax},${ay} C${ax},${(ay + by) / 2} ${bx},${(ay + by) / 2} ${bx},${by}`;
        parts.push(`<path d="${d}" fill="none" stroke="${stroke}" stroke-opacity=".45" stroke-width="1.5"/>`);
      });
    });

    nodes.forEach((n) => {
      if (!row.has(n.id)) return;
      const x = xOf(lane.get(n.id)), y = yOf(n.id);
      const c = COLOR[n.marginalia_type] || "#9a948a";
      const anchored = (() => { try { return JSON.parse(n.metadata_json).anchored; } catch { return false; } })();
      const label = n.title.length > 82 ? n.title.slice(0, 81) + "…" : n.title;
      parts.push(
        `<g class="gnode" data-id="${n.id}" style="cursor:pointer">` +
        `<rect x="0" y="${y - 10}" width="${width}" height="${rowH}" fill="transparent"/>` +
        `<circle cx="${x}" cy="${y}" r="3.6" fill="${anchored ? c : "none"}" stroke="${c}" stroke-width="1.5"/>` +
        `<text x="${labelX}" y="${y + 4}" font-size="12.5" fill="#1c1a17" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Helvetica,Arial,sans-serif">${esc(label)}</text>` +
        `</g>`
      );
    });

    svg.setAttribute("width", width);
    svg.setAttribute("height", height);
    svg.innerHTML =
      `<style>.gnode:hover rect{fill:#f4f1ea}.gnode.sel rect{fill:#fdf2c9}</style>` + parts.join("");

    // Hovering previews, clicking keeps. Reading a graph means moving
    // down it; making someone click every row to find out what it
    // says turns reading into filing.
    svg.querySelectorAll(".gnode").forEach((g) => {
      const nodeId = Number(g.dataset.id);

      g.addEventListener("mouseenter", () => this.detail(nodeId, true));
      g.addEventListener("mouseleave", () => this.restore());

      g.addEventListener("click", () => {
        svg.querySelectorAll(".gnode.sel").forEach((o) => o.classList.remove("sel"));
        g.classList.add("sel");
        this.kept = nodeId;
        this.detail(nodeId, false);
      });
    });
  },

  // back to whatever was clicked, or to the empty state
  restore() {
    if (this.kept != null) return this.detail(this.kept, false);
    const panel = document.getElementById("graph-detail");
    if (panel && this.blank != null) panel.innerHTML = this.blank;
  },

  detail(id, previewing) {
    const panel = document.getElementById("graph-detail");
    if (!panel) return;
    if (this.blank == null) this.blank = panel.innerHTML;
    const n = this.byId.get(id);
    if (!n) return;
    let meta = {};
    try { meta = JSON.parse(n.metadata_json); } catch {}
    const c = COLOR[n.marginalia_type] || "#9a948a";

    const rel = (list, dir) => list.map((e) => {
      const other = this.byId.get(dir === "out" ? e.to_node_id : e.from_node_id);
      if (!other) return "";
      return `<div class="gd-edge">` +
        `<span class="gd-arrow">${dir === "out" ? "→" : "←"}</span>` +
        `<span><b>${esc(other.title)}</b>` +
        `<span class="gd-type">${esc(other.marginalia_type)}</span>` +
        (e.rationale ? `<em>${esc(e.rationale)}</em>` : "") +
        `</span></div>`;
    }).join("");

    const out = this.edges.filter((e) => e.from_node_id === id);
    const into = this.edges.filter((e) => e.to_node_id === id);

    panel.innerHTML =
      `<style>
         .gd h3{font-family:var(--mg-serif);font-size:1.02rem;line-height:1.3;margin:.35rem 0 .5rem}
         .gd .row{display:flex;gap:.35rem;flex-wrap:wrap;align-items:center}
         .gd .t{font-size:.6rem;letter-spacing:.09em;text-transform:uppercase;font-weight:600;
                border:1px solid ${c};color:${c};border-radius:2px;padding:.08rem .35rem}
         .gd .k{font-size:.6rem;letter-spacing:.12em;text-transform:uppercase;color:var(--mg-dim);
                font-weight:600;margin:1rem 0 .3rem}
         .gd p{font-size:.8rem;line-height:1.6;margin:0}
         .gd blockquote{font-family:var(--mg-serif);font-size:.88rem;color:var(--mg-dim);
                border-left:2px solid var(--mg-accent);padding-left:.6rem;margin:0}
         .gd-edge{display:flex;gap:.4rem;font-size:.76rem;line-height:1.45;margin:.45rem 0}
         .gd-arrow{color:var(--mg-dim)}
         .gd-edge b{font-weight:600}
         .gd-edge .gd-type{font-size:.58rem;letter-spacing:.08em;text-transform:uppercase;
                color:var(--mg-dim);margin-left:.35rem}
         .gd-edge em{display:block;color:var(--mg-dim);font-style:italic;margin-top:.1rem}
         .gd .peeking{font-size:.58rem;letter-spacing:.11em;text-transform:uppercase;
                color:var(--mg-dim);opacity:.75;margin-bottom:.55rem}
         .gd.previewing{opacity:.88}
       </style>
       <div class="gd${previewing ? " previewing" : ""}">
         ${previewing ? `<div class="peeking">previewing · click to keep</div>` : ""}
         <div class="row">
           <span class="t">${esc(n.marginalia_type)}</span>
           ${n.status && n.status !== "pending" ? `<span class="mg-badge">${esc(n.status)}</span>` : ""}
           ${meta.anchored ? `<span class="mg-badge">anchored</span>` : `<span class="mg-badge">unanchored</span>`}
         </div>
         <h3>${esc(n.title)}</h3>
         ${n.narrative ? `<div class="k">narrative</div><p>${esc(n.narrative)}</p>` : ""}
         ${n.section ? `<div class="k">section</div><p>${esc(n.section_ordinal)}. ${esc(n.section)}</p>` : ""}
         ${n.body ? `<div class="k">commentary</div><p>${esc(n.body)}</p>` : ""}
         ${n.quote ? `<div class="k">in your own words</div><blockquote>${esc(n.quote)}</blockquote>` : ""}
         ${into.length ? `<div class="k">follows from</div>${rel(into, "in")}` : ""}
         ${out.length ? `<div class="k">leads to</div>${rel(out, "out")}` : ""}
       </div>`;
  },
};
```

## 7. Hover

`lib/marginalia_web/live/work_live/show.ex:2613-2639`

```js
// Hover to see a candidate in the line it would replace; the
// pointer leaving puts the line back. Debounced on the way out so
// moving between two candidates does not flicker the paragraph.
export default {
  mounted() {
    this.el.addEventListener("mouseover", (e) => {
      const row = e.target.closest(".mg-rw");
      if (!row) return;
      clearTimeout(this.out);
      if (row.dataset.i !== this.showing) {
        this.showing = row.dataset.i;
        this.pushEvent("preview_rewrite", {i: row.dataset.i});
      }
    });

    this.el.addEventListener("mouseleave", () => {
      clearTimeout(this.out);
      this.out = setTimeout(() => {
        this.showing = null;
        this.pushEvent("clear_preview", {});
      }, 80);
    });
  },
  destroyed() { clearTimeout(this.out); },
};
```

## 8. Minimap

`lib/marginalia_web/live/work_live/show.ex:2817-2891`

```js
// Open on click, and follow the reader down the page so the block
// beside where they are is lit. Kept client-side: which heading is
// on screen changes every few hundred milliseconds and is nobody's
// business but the browser's.
export default {
  mounted() {
    this.links = [...this.el.querySelectorAll("a[data-target]")];
    this.rows = this.links.map((a) => a.parentElement);
    this.ticks = [...this.el.querySelectorAll(".mg-map-rail .t")];
    this.rail = this.el.querySelector(".mg-map-rail");

    this.rail.addEventListener("click", () => {
      const open = this.el.classList.toggle("open");
      this.rail.setAttribute("aria-expanded", open ? "true" : "false");
    });

    this.links.forEach((a, i) => {
      a.addEventListener("click", (e) => {
        e.preventDefault();
        const el = document.getElementById(a.dataset.target);
        if (el) el.scrollIntoView({behavior: "smooth", block: "start"});
        this.close();
        this.mark(i);
      });
    });

    // a click anywhere else closes it
    this.away = (e) => { if (!this.el.contains(e.target)) this.close(); };
    this.esc = (e) => { if (e.key === "Escape") this.close(); };
    document.addEventListener("click", this.away);
    document.addEventListener("keydown", this.esc);

    this.follow();
  },

  destroyed() {
    document.removeEventListener("click", this.away);
    document.removeEventListener("keydown", this.esc);
    this.io?.disconnect();
  },

  close() {
    this.el.classList.remove("open");
    this.rail.setAttribute("aria-expanded", "false");
  },

  mark(i) {
    this.ticks.forEach((t, j) => t.classList.toggle("on", j === i));
    this.rows.forEach((r, j) => r.classList.toggle("on", j === i));
  },

  follow() {
    const targets = this.links
      .map((a) => document.getElementById(a.dataset.target))
      .filter(Boolean);
    if (!targets.length) return;

    this.io = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const i = targets.indexOf(entry.target);
          if (i >= 0) this.mark(i);
        }
      },
      // a band across the top: whatever has most recently passed it
      // is what the reader is in
      {rootMargin: "-10% 0px -80% 0px"}
    );

    targets.forEach((t) => this.io.observe(t));
  },
};
```

## 9. Steer

`lib/marginalia_web/live/work_live/show.ex:3329-3371`

```js
// The steering box grows with what is typed in it, up to a point.
//
// It was a one-line input, which is fine for "shorter" and wrong
// for the three-clause instruction people actually write: past
// the width of the box you are typing into a slot that shows you
// the last few words and hides the rest.
export default {
  mounted() {
    this.grow = () => {
      this.el.style.height = "auto";
      // capped, because this sits between the passage and the
      // candidates and should not push either off the screen
      this.el.style.height = Math.min(this.el.scrollHeight, 160) + "px";
    };

    this.onKey = (e) => {
      // Enter sends it; Shift+Enter is a newline, which is the
      // convention every chat box has taught everybody
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        this.el.form?.dispatchEvent(
          new Event("submit", {bubbles: true, cancelable: true})
        );
      }
    };

    this.el.addEventListener("input", this.grow);
    this.el.addEventListener("keydown", this.onKey);
    this.grow();
  },

  // phx-update="ignore" keeps what is half-typed through a patch,
  // so the height has to be re-measured here rather than on the
  // server's say-so
  updated() { this.grow(); },

  destroyed() {
    this.el.removeEventListener("input", this.grow);
    this.el.removeEventListener("keydown", this.onKey);
  },
};
```

## 10. Deck

`lib/marginalia_web/live/work_live/show.ex:3373-3443`

```js
// One slot holding several notes of the same kind, one visible.
//
// Every card is in the DOM; this only moves the `on` class. No
// round trip to read the next note, and nothing to re-fetch when
// you flip back. The cards share a single grid cell, so the slot
// is as tall as the tallest of them and flipping never changes
// the height — which matters here more than it looks, because
// the rail is measured and a slot that grew would push every
// note below it off its own line.
export default {
  mounted() {
    this.at = 0;
    this.onClick = (e) => {
      const step = e.target.closest("[data-step]");
      if (!step) return;
      // it is inside the slot, and the slot's other job is to
      // open the chat on the note it is showing
      e.preventDefault();
      e.stopPropagation();
      this.go(this.at + Number(step.dataset.step));
    };
    this.el.addEventListener("click", this.onClick);

    // arrows, once the pager has been reached by keyboard
    this.onKey = (e) => {
      if (e.key === "ArrowLeft") this.go(this.at - 1);
      if (e.key === "ArrowRight") this.go(this.at + 1);
    };
    this.el.addEventListener("keydown", this.onKey);

    this.show();
  },

  // A patch can replace the cards — a note added, a note
  // superseded — so the index is re-applied rather than assumed,
  // and clamped in case the pile got shorter.
  updated() { this.show(); },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    this.el.removeEventListener("keydown", this.onKey);
  },

  cards() { return [...this.el.querySelectorAll(".cards > .mg-note")]; },

  go(i) {
    const n = this.cards().length;
    if (!n) return;
    this.at = ((i % n) + n) % n;
    this.show();
  },

  show() {
    const cards = this.cards();
    if (!cards.length) return;
    this.at = Math.min(this.at, cards.length - 1);

    cards.forEach((c, i) => {
      const on = i === this.at;
      c.classList.toggle("on", on);
      // a hidden card is not a tab stop and is not read out
      c.setAttribute("aria-hidden", on ? "false" : "true");
      c.tabIndex = on ? 0 : -1;
    });

    const n = this.el.querySelector(".nav .n");
    if (n) n.textContent = `${this.at + 1} / ${cards.length}`;
  },
};
```

## 11. Editor

`lib/marginalia_web/live/work_live/show.ex:3445-3477`

```js
// The paragraph's markdown, in place. Not a rich text editor: the
// page is rendered from this source and every note is anchored into
// it, so round-tripping HTML back to markdown would quietly move
// every anchor in the section.
export default {
  mounted() {
    const ta = this.el.querySelector("textarea");
    if (!ta) return;

    const grow = () => {
      ta.style.height = "auto";
      ta.style.height = ta.scrollHeight + "px";
    };
    grow();
    ta.addEventListener("input", grow);

    ta.focus();
    ta.setSelectionRange(ta.value.length, ta.value.length);

    ta.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        this.pushEvent("cancel_edit", {});
      }
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        this.el.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}));
      }
    });
  },
};
```

## 12. Selection

`lib/marginalia_web/live/work_live/show.ex:3479-3663`

```js
// Select a passage and both things you can do with it appear at the
// end of it: talk about that spot in its own thread, or carry it into
// the question you are already writing. Two different intentions, and
// guessing which one someone meant gets it wrong half the time.
//
// The text is verified against the manuscript server-side before
// either path keeps it: a browser selection picks up whatever the
// markup puts in its way.
export default {
  mounted() {
    this.bar = this.el.querySelector("#sel-actions");
    if (!this.bar) return;

    const act = (fn) => (e) => {
      // mousedown, not click: clicking clears the selection first
      e.preventDefault();
      const text = String(window.getSelection() || "").trim();
      const block = this.blockOf(window.getSelection());
      const endBlock = this.endBlockOf(window.getSelection());
      if (text.length >= 12) fn(text, block, endBlock);
      window.getSelection()?.removeAllRanges();
      this.hide();
    };

    this.bar.querySelector("#sel-add").addEventListener("mousedown", act((text) => {
      this.pushEvent("add_context", {text});
    }));

    this.bar.querySelector("#sel-rewrite").addEventListener("mousedown", act((text, block, endBlock) => {
      // The END of the selection, not the start. The panel renders
      // inside the block it names, so anchoring it to the first
      // paragraph of a four-paragraph drag put it above three
      // paragraphs of the thing it was rewriting and nowhere near
      // the cursor. The bar sits at the bottom of the range, so the
      // last block is where the mouse actually is.
      const at = endBlock || block;
      this.pushEvent("suggest_rewrite", {text, ref: at && at.ref});
    }));

    this.bar.querySelector("#sel-discuss").addEventListener("mousedown", act((text, block) => {
      if (!block) return;
      this.pushEvent("open_thread", {
        ref: block.ref,
        section: block.section,
        quote: text,
      });
    }));

    // Where the press landed, so a release can tell a click from a
    // drag. This is the whole reason the paragraph has no invisible
    // hit target over it any more: a <button> covering the prose
    // swallows the drag, and the owner — the only person who saw
    // that overlay — could not select a word of their own draft.
    this.onDown = (e) => { this.down = {x: e.clientX, y: e.clientY}; };
    this.onUp = (e) => {
      requestAnimationFrame(() => this.place());
      this.maybeEdit(e);
    };
    document.addEventListener("mousedown", this.onDown);
    document.addEventListener("mouseup", this.onUp);
    document.addEventListener("keyup", this.onUp);
    this.onScroll = () => this.hide();
    window.addEventListener("scroll", this.onScroll, {passive: true});
  },

  destroyed() {
    document.removeEventListener("mousedown", this.onDown);
    document.removeEventListener("mouseup", this.onUp);
    document.removeEventListener("keyup", this.onUp);
    window.removeEventListener("scroll", this.onScroll);
  },

  // A click inside your own prose opens the paragraph for editing; a
  // drag selects it. The two are told apart by whether anything got
  // selected and whether the pointer travelled, which is how every
  // text surface has always decided this.
  maybeEdit(e) {
    const body = this.el.querySelector(".mg-read-body");
    if (!body || body.dataset.editable !== "true") return;
    if (!e || typeof e.clientX !== "number" || !this.down) return;

    const sel = window.getSelection();
    if (sel && !sel.isCollapsed && String(sel).trim().length) return;
    if (Math.hypot(e.clientX - this.down.x, e.clientY - this.down.y) > 4) return;

    const block = e.target?.closest?.(".mg-block");
    if (!block || !body.contains(block)) return;

    // anything with its own job keeps it: the thread tick, a link in
    // the prose, an open thread or rewrite panel nested in the block
    if (e.target.closest("a, button, input, textarea, form, .mg-thread-panel, .mg-rewrite")) return;

    // A highlight is the note's own affordance — hover peeks,
    // click pins — so a click on one belongs to the margin, not
    // to the editor. With the drawer open that is the whole way
    // a passage gets fed to the conversation, and opening an
    // editor on top of it made adding a second one impossible.
    if (e.target.closest("mark[id]")) return;

    // and with the drawer open the draft is the reference, not
    // the thing being edited
    if (body.closest(".mg-read")?.classList.contains("collapsed")) return;

    this.pushEvent("edit_block", {ref: block.id.replace(/^block-/, "")});
  },

  // which paragraph the selection started in, so a thread can pin to it
  blockOf(sel) {
    if (!sel || !sel.rangeCount) return null;
    let node = sel.getRangeAt(0).startContainer;
    if (node.nodeType === Node.TEXT_NODE) node = node.parentElement;
    const el = node?.closest?.(".mg-block");
    if (!el) return null;
    const tick = el.querySelector(".mg-tick");
    return {ref: el.id.replace(/^block-/, ""), section: tick?.getAttribute("phx-value-section")};
  },

  // The last paragraph the selection actually covers, so the panel
  // opens where the drag finished rather than where it began.
  //
  // NOT endContainer. A drag that stops at the end of a paragraph
  // reports the NEXT node at offset 0 — the range ends *before* it,
  // covering none of it — so three highlighted paragraphs anchored
  // the panel under a fourth that was not selected at all. The
  // boundary comparisons below exclude a block the range merely
  // touches.
  endBlockOf(sel) {
    if (!sel || !sel.rangeCount) return null;
    const range = sel.getRangeAt(0);

    const covered = [...this.el.querySelectorAll(".mg-block")].filter((b) => {
      const br = document.createRange();
      br.selectNodeContents(b);
      // range ends at or before the block starts, or starts at or
      // after it ends: no text of this block is in the selection
      if (range.compareBoundaryPoints(Range.END_TO_START, br) >= 0) return false;
      if (range.compareBoundaryPoints(Range.START_TO_END, br) <= 0) return false;
      return true;
    });

    const el = covered[covered.length - 1];
    if (!el) return null;
    const tick = el.querySelector(".mg-tick");
    return {ref: el.id.replace(/^block-/, ""), section: tick?.getAttribute("phx-value-section")};
  },

  hide() { if (this.bar) this.bar.hidden = true; },

  place() {
    const sel = window.getSelection();
    const text = String(sel || "").trim();
    if (!sel || sel.isCollapsed || text.length < 12) return this.hide();

    const range = sel.getRangeAt(0);
    // only for the draft itself, not for the chat transcript
    if (!this.el.contains(range.commonAncestorContainer)) return this.hide();

    // The WHOLE range has to be in the prose, not just where it
    // started: dragging out of a paragraph and into a margin note
    // used to pass this check and then fail server-side, because the
    // note's words are not in the draft.
    //
    // Both ends, not the common ancestor. A selection inside one
    // paragraph has a text node for an ancestor and passed; a
    // selection across several has the container above them, which
    // is .mg-read-body itself or higher, and `contains` went false —
    // so the rewrite button vanished exactly when the span got
    // interesting. Testing the endpoints says what was meant.
    const body = this.el.querySelector(".mg-read-body");
    const inBody =
      body &&
      body.contains(range.startContainer) &&
      body.contains(range.endContainer);
    this.bar.querySelector("#sel-discuss").hidden = !inBody;
    this.bar.querySelector("#sel-rewrite").hidden = !inBody;

    const r = range.getBoundingClientRect();
    const host = this.el.getBoundingClientRect();
    this.bar.hidden = false;
    this.bar.style.top = `${r.bottom - host.top + 8}px`;
    this.bar.style.left = `${Math.max(0, r.left - host.left)}px`;
  },
};
```

## 13. Share

`lib/marginalia_web/live/work_live/show.ex:3665-3685`

```js
// The link is the permission, so handing it over has to be one click.
export default {
  mounted() {
    this.el.addEventListener("click", async () => {
      const was = this.el.textContent;
      try {
        await navigator.clipboard.writeText(this.el.dataset.url);
        this.el.textContent = "Copied";
      } catch {
        // clipboard blocked (insecure origin, denied permission):
        // select it instead so they can copy it by hand
        window.prompt("Copy this link", this.el.dataset.url);
        this.el.textContent = was;
        return;
      }
      setTimeout(() => (this.el.textContent = was), 1400);
    });
  },
};
```

## 14. SummaryVault

`lib/marginalia_web/live/work_live/show.ex:3687-3764`

```js
// The server stores one summary per section. Running it again overwrites
// that row, and the text that was there is gone — so this keeps the last
// few in the browser that produced them, and offers them back.
//
// It is a safety net, not a backup: localStorage is per-browser and
// per-device, it can be cleared by the person or the browser, and every
// read and write here is wrapped because in a private window the
// accessor itself throws. Nothing on the page depends on it working.
const KEY = (k) => `mg:sum:${k}`;
const KEEP = 6;

const read = (k) => {
  try {
    return JSON.parse(localStorage.getItem(KEY(k)) || "[]");
  } catch (_) {
    return [];
  }
};

const write = (k, list) => {
  try {
    localStorage.setItem(KEY(k), JSON.stringify(list.slice(0, KEEP)));
  } catch (_) {
    // quota, or storage disabled. The page is unaffected.
  }
};

export default {
  mounted() { this.sweep(); },
  updated() { this.sweep(); },

  sweep() {
    this.el.querySelectorAll("[data-sum-key]").forEach((el) => {
      const key = el.dataset.sumKey;
      const text = el.dataset.sumText || "";
      if (!key || !text) return;

      const list = read(key);

      // Only when it actually changed. A re-render of the same summary
      // must not fill the vault with copies of one thing.
      if (!list.length || list[0].s !== text) {
        list.unshift({ s: text, at: el.dataset.sumAt || new Date().toISOString() });
        write(key, list);
      }

      this.render(key, list);
    });
  },

  render(key, list) {
    const ordinal = key.split(":").pop();
    const box = document.getElementById(`sumvault-${ordinal}`);
    if (!box) return;

    const older = list.slice(1);
    if (!older.length) { box.innerHTML = ""; return; }

    const d = document.createElement("details");
    const sum = document.createElement("summary");
    sum.textContent = `${older.length} earlier ${older.length === 1 ? "version" : "versions"} of this summary, kept in this browser`;
    d.appendChild(sum);

    older.forEach((v) => {
      const p = document.createElement("p");
      const when = document.createElement("span");
      when.className = "when";
      when.textContent = (v.at || "").slice(0, 16).replace("T", " ");
      p.appendChild(when);
      p.appendChild(document.createTextNode(v.s));
      d.appendChild(p);
    });

    box.replaceChildren(d);
  },
};
```

## 15. MarginNotes

`lib/marginalia_web/live/work_live/show.ex:3766-4054`

```js
// Two layouts, one set of notes.
//
// Wide: each note sits level with its own highlight, measured and
// stacked so nothing overlaps. Grid rows cannot do this — they either
// tear holes in the prose or drop the alignment.
//
// Narrow, which is what the chat drawer leaves: there is no margin,
// and a rail squeezed into what remains is worse than none. So the
// notes fold back into the text. The highlight becomes the whole
// affordance — hover peeks, click pins. Pinning matters because
// reading a note and then going to write about it should not require
// holding the mouse still.
export default {
  mounted() {
    this.pinned = new Set();
    this.showing = new Map();
    this.layout();
    this.watch();
  },
  updated() { this.layout(); },
  destroyed() {
    this.ro?.disconnect();
    document.removeEventListener("click", this.onAway);
    window.removeEventListener("scroll", this.onScroll, true);
    window.removeEventListener("resize", this.onScroll);
  },

  collapsed() { return this.el.classList.contains("collapsed"); },

  slotsFor(ref) {
    return [...this.el.querySelectorAll(`.mg-note-slot[data-anchor="${CSS.escape(ref)}"]`)];
  },

  watch() {
    this.ro = new ResizeObserver(() => this.layout());
    this.ro.observe(this.el);

    this.el.querySelectorAll(".mg-note-slot").forEach((slot) => {
      const id = slot.dataset.anchor;
      const mark = id && this.el.querySelector(`#anchor-${CSS.escape(id)}`);
      if (!mark) return;
      slot.addEventListener("mouseenter", () => mark.classList.add("lit"));
      slot.addEventListener("mouseleave", () => mark.classList.remove("lit"));
    });

    this.el.querySelectorAll(".mg-read-body mark[id]").forEach((mark) => {
      const ref = mark.id.replace(/^anchor-/, "");
      mark.addEventListener("mouseenter", () => this.collapsed() && this.peek(ref, mark));
      mark.addEventListener("mouseleave", () => this.collapsed() && this.unpeek(ref));
      mark.addEventListener("click", (e) => {
        if (!this.collapsed()) return;
        e.stopPropagation();
        if (this.pinned.has(ref)) { this.pinned.delete(ref); this.unpeek(ref); }
        else { this.pinned.add(ref); this.peek(ref, mark); }
        mark.classList.toggle("pinned", this.pinned.has(ref));
      });
    });

    // a click anywhere else lets go of everything pinned
    this.onAway = (e) => {
      if (!this.collapsed()) return;
      if (e.target.closest(".mg-note-slot") || e.target.closest("mark[id]")) return;
      [...this.pinned].forEach((ref) => { this.pinned.delete(ref); this.unpeek(ref); });
      this.el.querySelectorAll("mark.pinned").forEach((m) => m.classList.remove("pinned"));
    };
    document.addEventListener("click", this.onAway);

    // follow the text: capture phase, so a scroll inside the drawer
    // or any other scrolling ancestor counts too
    let queued = false;
    this.onScroll = () => {
      if (queued || !this.showing.size) return;
      queued = true;
      requestAnimationFrame(() => { queued = false; this.reposition(); });
    };
    window.addEventListener("scroll", this.onScroll, true);
    window.addEventListener("resize", this.onScroll);
  },

  peek(ref, mark) {
    this.showing.set(ref, mark);
    this.slotsFor(ref).forEach((slot) => slot.classList.add("peek"));
    this.reposition();
  },

  unpeek(ref) {
    if (this.pinned.has(ref)) return;
    this.showing.delete(ref);
    this.slotsFor(ref).forEach((slot) => {
      slot.classList.remove("peek");
      slot.style.left = "";
      slot.style.top = "";
      slot.style.removeProperty("--caret");
    });
  },

  // Fixed positioning takes viewport coordinates, and the page scrolls
  // under them — so the note has to be put back against its highlight
  // on every scroll, or it is left behind the moment you move. This
  // runs on scroll and resize, rAF-throttled.
  // The notes on one highlight are laid out as a stack, not as
  // independent boxes. Clamping each one to the viewport separately
  // collapsed them onto the same `top` whenever the group did not
  // fit, so two notes landed on top of each other — the group is
  // measured and clamped once, then each note is placed from there.
  reposition() {
    const GAP = 8;

    this.showing.forEach((mark, ref) => {
      const r = mark.getBoundingClientRect();
      const slots = this.slotsFor(ref);
      if (!slots.length) return;

      // the highlight has scrolled away: take the note with it,
      // unless it is pinned
      const gone = r.bottom < 8 || r.top > window.innerHeight - 8;
      if (gone && !this.pinned.has(ref)) return this.unpeek(ref);

      const heights = slots.map((s) => s.offsetHeight);
      const total = heights.reduce((a, h) => a + h, 0) + GAP * (slots.length - 1);

      // below the line by default, above it when there is no room,
      // and clamped as one block so the stack never folds together
      const below = r.bottom + 10;
      const above = below + total > window.innerHeight - 12;
      let top = above ? r.top - total - 10 : below;
      top = Math.max(8, Math.min(top, window.innerHeight - total - 8));

      const width = slots[0].offsetWidth;
      const left = Math.max(12, Math.min(r.left, window.innerWidth - 12 - width));
      // the caret points back at the start of the span it is about
      const caret = Math.max(14, Math.min(r.left - left + 10, width - 20));

      slots.forEach((slot, i) => {
        slot.style.left = `${left}px`;
        slot.style.top = `${top}px`;
        slot.style.setProperty("--caret", `${caret}px`);
        slot.style.zIndex = `${55 + i}`;
        slot.classList.toggle("flipped", above);
        // only the note nearest the line gets the pointer
        slot.classList.toggle("tailed", above ? i === slots.length - 1 : i === 0);
        top += heights[i] + GAP;
      });
    });
  },

  layout() {
    const rail = this.el.querySelector(".mg-read-rail");
    if (!rail) return;

    // collapsed: the notes live in the highlights, nothing to place
    if (this.collapsed()) {
      rail.classList.remove("measured");
      rail.style.height = "";
      this.unshove();
      this.el.querySelectorAll(".mg-note-slot").forEach((s) => {
        if (!s.classList.contains("peek")) s.style.top = "";
      });
      return;
    }

    // back to the margin: drop anything left floating
    this.el.querySelectorAll(".mg-note-slot.peek").forEach((s) => {
      s.classList.remove("peek");
      s.style.left = "";
    });
    this.el.querySelectorAll("mark.pinned").forEach((m) => m.classList.remove("pinned"));
    this.pinned.clear();
    this.showing.clear();

    // one column is too narrow for a margin: fall back to flow
    if (getComputedStyle(this.el).gridTemplateColumns.split(" ").length < 3) {
      rail.classList.remove("measured");
      rail.style.height = "";
      this.unshove();
      this.el.querySelectorAll(".mg-note-slot").forEach((s) => (s.style.top = ""));
      return;
    }

    rail.classList.add("measured");
    const railTop = rail.getBoundingClientRect().top;
    let y = 0;

    this.el.querySelectorAll(".mg-note-slot").forEach((slot) => {
      const id = slot.dataset.anchor;
      const mark = id && this.el.querySelector(`#anchor-${CSS.escape(id)}`);
      const wanted = mark ? mark.getBoundingClientRect().top - railTop : y;
      const top = Math.max(wanted, y);
      slot.style.top = `${top}px`;
      y = top + slot.offsetHeight + 10;
    });

    rail.style.height = `${y}px`;
    this.shove(rail, railTop);
  },

  // An applied diff is as wide as all three columns and sits on
  // top of the rail, so the notes level with it are buried — and
  // the ones it buries are exactly the notes about the paragraph
  // that just changed. They move out past the prose, on the other
  // side, and come back when the diff is dismissed.
  //
  // There is less room out there than the note needs. The page is
  // 66ch of prose, a 3rem gutter and a 34ch rail, centred: at
  // 1512px that leaves 232px of margin against a 327px rail, and
  // on the 1000px-wide window this was reported from, 115px. So
  // the note goes as far left as the window allows and floats
  // over the left edge of the diff for the rest. Covering the
  // first few characters of a diff that is 100ch wide costs less
  // than burying the note about the paragraph that just changed,
  // which is what happens today.
  shove(rail, railTop) {
    const diff = this.el.querySelector(".mg-applied");
    if (!diff) return this.unshove();

    const slots = [...this.el.querySelectorAll(".mg-note-slot")];
    const body = this.el.querySelector(".mg-read-body");
    if (!slots.length || !body) return this.unshove();

    const d = diff.getBoundingClientRect();
    const b = body.getBoundingClientRect();
    const r = rail.getBoundingClientRect();

    const EDGE = 14;
    const TAIL = 18;
    // how close a note may come to the diff without being moved
    const CLEAR = 20;

    // Clear of the contents rail, which is fixed furniture down
    // the left of the window and would otherwise be drawn over
    // the first few words of every shoved note.
    const map = document.querySelector(".mg-map");
    const edge = Math.max(EDGE, map ? map.getBoundingClientRect().right + 10 : EDGE);

    const width = slots[0].offsetWidth;

    // in the rail's own coordinates, since that is what `left`
    // on an absolutely positioned slot is measured from
    const to = Math.max(edge, b.left - TAIL - width) - r.left;

    const band = {top: d.top - railTop, bottom: d.bottom - railTop};
    let floor = -Infinity;

    slots.forEach((slot) => {
      let top = parseFloat(slot.style.top) || 0;
      const high = slot.offsetHeight;

      // A third of the note, not a pixel of it. A card whose last
      // line grazes the top of the diff is still readable, and
      // sending it across the page for that is a worse jolt than
      // the overlap.
      const over = Math.min(top + high, band.bottom) - Math.max(top, band.top);
      const hits = over > high / 3;

      slot.classList.toggle("shoved", hits);
      // pinned in pixels rather than left to `right: auto`, or the
      // bubble collapses to its content width as it crosses
      slot.style.width = hits ? `${width}px` : "";
      slot.style.left = hits ? `${to}px` : "";

      // The near miss, which is the common one and the one that
      // looks like a bug: a card comes to rest with its last line
      // four pixels under the diff's top edge. Not worth sending
      // across the page, so it is moved clear the short way —
      // away from the diff, never into the card above it.
      if (!hits && top + high > band.top - CLEAR && top < band.bottom + CLEAR) {
        const above = top + high / 2 < (band.top + band.bottom) / 2;
        const want = above ? band.top - CLEAR - high : band.bottom + CLEAR;

        if (!above || want >= floor + 10) {
          top = want;
          slot.style.top = `${top}px`;
        }
      }

      floor = top + high;
    });
  },

  unshove() {
    this.el.querySelectorAll(".mg-note-slot.shoved").forEach((s) => {
      s.classList.remove("shoved");
      s.style.left = "";
      s.style.width = "";
    });
  },
};
```

## 16. StickToBottom

`lib/marginalia_web/live/work_live/show.ex:4445-4463`

```js
// Follow the conversation only while the reader is already at the
// bottom. Yanking someone back down mid-scroll while they are reading
// an earlier answer is the single most irritating thing a chat can do.
export default {
  mounted() {
    this.pinned = true;
    this.el.addEventListener("scroll", () => {
      const gap = this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight;
      this.pinned = gap < 80;
    });
    this.toBottom("auto");
  },
  updated() { if (this.pinned) this.toBottom("smooth"); },
  toBottom(behavior) {
    requestAnimationFrame(() => this.el.scrollTo({top: this.el.scrollHeight, behavior}));
  },
};
```

## 17. Composer (show)

`lib/marginalia_web/live/work_live/show.ex:4465-4488`

```js
// Enter sends, Shift+Enter writes a newline, and the box grows with
// the question instead of hiding it one line at a time.
export default {
  mounted() {
    const ta = this.el.querySelector("textarea");
    if (!ta) return;
    const MIN = 120, MAX = 352;
    const grow = () => {
      ta.style.height = "auto";
      ta.style.height = Math.max(MIN, Math.min(ta.scrollHeight, MAX)) + "px";
    };
    ta.addEventListener("input", grow);
    ta.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
        e.preventDefault();
        if (ta.value.trim()) this.el.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}));
      }
    });
    this.handleEvent("chat:clear", () => { ta.value = ""; grow(); ta.focus(); });
    ta.focus();
  },
};
```

## 18. Wiring

`lib/marginalia_web/components/link_waiting.ex:101-164`

```js
// Two columns of real nodes, and arcs tried between them. Nothing
// here is a result — see the note under it — it is the shape of the
// work, drawn while the work happens.
export default {
  mounted() {
    this.a = JSON.parse(this.el.dataset.a || "[]");
    this.b = JSON.parse(this.el.dataset.b || "[]");
    this.svg = this.el.querySelector(".lw-svg");
    this.arcs = this.svg.querySelector(".arcs");
    this.dots = this.svg.querySelector(".dots");
    this.now = {l: this.el.querySelector(".lw-now .l"), r: this.el.querySelector(".lw-now .r")};

    if (!this.a.length || !this.b.length) return;
    // the dots are already on the page; motion is all this adds
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    this.tick = setInterval(() => this.tryPair(), 900);
    this.tryPair();
  },

  destroyed() { clearInterval(this.tick); },

  // mirrors y/2 in the component — the dots are placed server-side
  // and the arcs have to arrive at the same coordinates
  y(i, n) { return 30 + (i * (300 / Math.max(n - 1, 1))); },

  tryPair() {
    const ns = "http://www.w3.org/2000/svg";
    const i = Math.floor(Math.random() * this.a.length);
    const j = Math.floor(Math.random() * this.b.length);
    const y1 = this.y(i, this.a.length);
    const y2 = this.y(j, this.b.length);

    const path = document.createElementNS(ns, "path");
    path.setAttribute("d", `M 90 ${y1} C 300 ${y1}, 380 ${y2}, 590 ${y2}`);
    path.setAttribute("class", "arc");
    this.arcs.appendChild(path);

    // draw it on, hold, fade it out — then take it away entirely, so
    // nothing accumulates that could be mistaken for a result
    const len = path.getTotalLength();
    path.style.strokeDasharray = len;
    path.style.strokeDashoffset = len;
    path.getBoundingClientRect();
    path.style.transition = "stroke-dashoffset .7s ease-out, opacity .5s ease-in .9s";
    path.style.strokeDashoffset = 0;
    path.style.opacity = 0;
    setTimeout(() => path.remove(), 1800);

    this.lightUp("a", i);
    this.lightUp("b", j);
    this.now.l.textContent = this.a[i];
    this.now.r.textContent = this.b[j];
  },

  lightUp(side, i) {
    const dot = this.dots.querySelector(`circle[data-side="${side}"][data-i="${i}"]`);
    if (!dot) return;
    dot.classList.add("lit");
    setTimeout(() => dot.classList.remove("lit"), 1200);
  },
};
```

## 19. Reveal

`lib/marginalia_web/live/landing_live.ex:71-128`

```js
// Notes arrive as you reach the paragraph they annotate, and the worked
// examples play their turns in sequence once they're on screen. Both are
// one-shot: re-animating on every scroll past would be nauseating.
export default {
  mounted() {
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const targets = this.el.querySelectorAll("[data-reveal], [data-demo]");

    if (reduce || !("IntersectionObserver" in window)) return;

    // Only now does anything hide. Without JS, or before this runs, the
    // page is fully readable — a landing page that needs JS to show its
    // own copy is a landing page that sometimes shows nothing.
    this.el.classList.add("reveal-ready");

    this.io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("in");
          if (entry.target.hasAttribute("data-demo")) this.play(entry.target);
          this.io.unobserve(entry.target);
        });
      },
      // fire a little before the top edge so the note is already there
      // by the time the eye arrives
      { rootMargin: "0px 0px -12% 0px", threshold: 0.15 }
    );

    targets.forEach((el) => this.io.observe(el));
  },

  // A demo is markup that already says what it means; the steps only
  // control WHEN each part of it appears, so the whole thing is legible
  // with the script dead or with motion turned down — the final frame is
  // the default state and `reveal-ready` is what hides it.
  play(demo) {
    const gap = parseInt(demo.dataset.interval || "650", 10);
    const steps = [...demo.querySelectorAll("[data-step]")].sort(
      (a, b) => Number(a.dataset.step) - Number(b.dataset.step)
    );

    this.timers = this.timers || [];

    steps.forEach((step, i) => {
      this.timers.push(
        setTimeout(() => step.classList.add("on"), gap * (i + 1))
      );
    });
  },

  destroyed() {
    if (this.io) this.io.disconnect();
    (this.timers || []).forEach(clearTimeout);
  },
};
```

## 20. Tree

`lib/marginalia_web/live/work_live/index.ex:229-315`

```js
// Native HTML5 drag and drop, delegated from the tree container so it
// survives every re-render LiveView does underneath it. No library:
// this is dragstart, dragover, drop, and the work is in deciding what
// is under the cursor.
//
// The one real rule is that a folder cannot be dropped into its own
// subtree. Because a folder's children are rendered *inside* its
// element, that rule is just `dragged.contains(target)` — the illegal
// targets are exactly the ones the dragged element encloses. The
// server checks it again by walking parent_id, since this is a fact
// about the tree rather than about the mouse.
export default {
  mounted() {
    this.drag = null;

    this.on("dragstart", (e) => {
      const row = e.target.closest("[data-drag-id]");
      if (!row || !this.el.contains(row)) return;
      this.drag = {
        el: row,
        kind: row.dataset.dragKind,
        id: row.dataset.dragId,
      };
      row.classList.add("is-dragging");
      e.dataTransfer.effectAllowed = "move";
      // Firefox will not start a drag at all unless the payload is set.
      e.dataTransfer.setData("text/plain", row.dataset.dragId);
    });

    this.on("dragend", () => this.clear());

    // dragover is the only place the highlight is decided. A
    // dragleave handler is the obvious way to turn it off and the
    // wrong one: leave fires every time the cursor crosses into a
    // child of the row it is already over, so the row you are aiming
    // at strobes while you hold still.
    this.on("dragover", (e) => {
      const target = this.target(e);
      if (!target) return this.unlight();
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      if (target !== this.lit) {
        this.unlight();
        this.lit = target;
        target.classList.add("is-over");
      }
    });

    this.on("drop", (e) => {
      const target = this.target(e);
      if (!target) return this.clear();
      e.preventDefault();
      const into = target.dataset.dropId;
      const drag = this.drag;
      this.clear();
      // Dropping something back where it already was is not a move.
      if (drag.kind === "folder" && into === drag.id) return;
      this.pushEvent("move", {kind: drag.kind, id: drag.id, into: into});
    });
  },

  destroyed() { this.clear(); },

  on(name, fn) { this.el.addEventListener(name, fn); },

  // The drop zone under the cursor, or null if this drop is illegal.
  target(e) {
    if (!this.drag) return null;
    const zone = e.target.closest("[data-drop-id]");
    if (!zone || !this.el.contains(zone)) return null;
    if (this.drag.el.contains(zone)) return null;
    return zone;
  },

  unlight() {
    if (this.lit) this.lit.classList.remove("is-over");
    this.lit = null;
  },

  clear() {
    this.unlight();
    if (this.drag) this.drag.el.classList.remove("is-dragging");
    this.drag = null;
  },
}
```

## 21. Weave

`lib/marginalia_web/live/cut_live/show.ex:206-304`

```js
// A member per row, and arcs between the pairs a claim rests on.
//
// While the read runs, the arcs shown are *candidates*: every pair of
// members, tried one at a time. That is not decoration — it is the
// question being asked, which is whether anything holds across two or
// more of these. When the answer lands the candidates stop and the
// pairs that actually held are drawn in, so the waiting state and the
// result are the same picture at two moments.
const ROW = 26, PAD = 12, GUT = 22;

export default {
  mounted() { this.draw(); },
  updated() { this.draw(); },
  destroyed() { this.stop(); },

  stop() {
    cancelAnimationFrame(this.frame);
    clearTimeout(this.timer);
    this.frame = this.timer = null;
  },

  draw() {
    this.stop();
    const members = JSON.parse(this.el.dataset.members || "[]");
    const links = JSON.parse(this.el.dataset.links || "[]");
    const reading = this.el.dataset.status === "reading";
    const svg = this.el.querySelector("svg");
    if (members.length < 2) { svg.innerHTML = ""; this.el.hidden = true; return; }

    const h = PAD * 2 + members.length * ROW;
    const w = 280;
    svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
    svg.setAttribute("height", h);
    const y = (n) => PAD + (n - 1) * ROW + ROW / 2;

    const rows = members.map((m) => `
      <line class="cw-rule" x1="${GUT}" y1="${y(m.n)}" x2="${w - 8}" y2="${y(m.n)}"></line>
      <circle class="cw-dot" cx="${GUT}" cy="${y(m.n)}" r="3.2"></circle>
      <text class="cw-lbl" x="${GUT - 10}" y="${y(m.n) + 3.5}">${m.n}</text>`).join("");

    // The `d` alone, so both kinds of arc keep their class name as a
    // literal in the markup they build. A class that only exists as a
    // function argument is one nothing can check for.
    const curve = (a, b) => {
      const y1 = y(a), y2 = y(b);
      const bulge = Math.min(46, 14 + Math.abs(y1 - y2) * 0.42);
      return `M ${GUT} ${y1} C ${GUT + bulge} ${y1}, ${GUT + bulge} ${y2}, ${GUT} ${y2}`;
    };

    svg.innerHTML = rows + links.map((l) =>
      `<path class="cw-arc k-${l.kind}" fill="none" d="${curve(l.a, l.b)}"></path>`
    ).join("");

    // draw the settled arcs in, once
    svg.querySelectorAll(".cw-arc").forEach((p, i) => {
      const len = p.getTotalLength();
      p.style.strokeDasharray = len;
      p.style.strokeDashoffset = len;
      p.style.animation = `cw-draw .7s ease ${0.1 + i * 0.09}s forwards`;
    });

    if (reading) this.tryPairs(svg, members, curve);
  },

  // Every pair, in order, on a loop. The order is fixed rather than
  // random so two people watching the same folder see the same thing.
  tryPairs(svg, members, curve) {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const pairs = [];
    for (let i = 0; i < members.length; i++)
      for (let j = i + 1; j < members.length; j++)
        pairs.push([members[i].n, members[j].n]);

    let k = 0;
    const step = () => {
      svg.querySelectorAll(".cw-try").forEach((n) => n.remove());
      const [a, b] = pairs[k % pairs.length];
      svg.insertAdjacentHTML(
        "beforeend",
        `<path class="cw-try" fill="none" d="${curve(a, b)}"></path>`
      );
      const p = svg.querySelector(".cw-try");
      const len = p.getTotalLength();
      p.style.setProperty("--len", len);
      p.style.strokeDasharray = len;
      p.style.strokeDashoffset = len;
      p.style.animation = "cw-try 1.15s ease-in-out forwards";
      [a, b].forEach((n) => {
        const dot = svg.querySelectorAll(".cw-dot")[n - 1];
        if (dot) { dot.classList.remove("lit"); void dot.offsetWidth; dot.classList.add("lit"); }
      });
      k++;
      this.timer = setTimeout(step, 1250);
    };
    step();
  },
}
```

## 22. Follow

`lib/marginalia_web/live/link_live/read.ex:466-993`

```js
// The left column is read; the right one is driven.
//
// A focus line a third of the way down the left column decides what
// you are "on". Whichever linked paragraph last crossed it is the
// current one, and the right column is scrolled to put its
// counterpart at the same height. Reading is the input; nothing has
// to be clicked.
export default {
  // Every element this hook touches, looked up in one place.
  //
  // These used to be cached once in mounted() and never again.
  // A server re-render — dismissing the one-time card is enough —
  // can replace those nodes, and the hook then holds detached
  // ones: it adds the open class to a `.fl-mid` that is no longer
  // in the document, so a tap highlights the paragraph and the
  // reference never appears. Nothing throws, nothing logs, and
  // the feature is simply dead until reload.
  cache() {
    this.lead = this.el.querySelector("#fl-lead");
    this.other = this.el.querySelector("#fl-other");
    this.strip = this.el.querySelector(".fl-strip");
    this.sheet = this.el.querySelector(".fl-sheet");
    this.stack = this.el.querySelector(".fl-stack");
    this.svg = this.el.querySelector(".fl-wire");
    this.split = this.el.querySelector(".fl-split");
    this.idle = this.el.querySelector(".fl-idle");
    this.count = this.el.querySelector(".fl-count b");
    this.mid = this.el.querySelector(".fl-mid");
  },

  mounted() {
    this.cache();

    // clicking the line carries both passages into the chat;
    // delegated for the same reason as the sheet's controls
    this.onWireClick = (e) => {
      if (e.target.closest(".fl-wire .hit") && this.edge) {
        this.pushEvent("cite_edge", {edge: this.edge});
      }
    };
    this.el.addEventListener("click", this.onWireClick);

    // The chip's menu, in both columns. Delegated for the reason
    // everything else here is: a server patch replaces these nodes
    // and a listener bound to one of them stops working silently.
    this.onJump = (e) => {
      const item = e.target.closest(".fl-jump");
      if (item && !item.disabled) this.jump(item);
    };
    this.el.addEventListener("click", this.onJump);

    // Hovering an entry lights its far paragraph without committing
    // to it, so the menu answers "which three" before you pick one.
    this.onPeek = (e) => {
      const item = e.target.closest(".fl-jump");
      this.peek(item && !item.disabled ? item : null);
    };
    this.el.addEventListener("mouseover", this.onPeek);
    this.el.addEventListener("mouseout", this.onPeek);

    this.seen = new Set();
    this.current = null;

    this.onScroll = () => {
      if (this.queued) return;
      this.queued = true;
      requestAnimationFrame(() => { this.queued = false; this.follow(); });
    };

    this.lead.addEventListener("scroll", this.onScroll, {passive: true});
    // the right column moves under the wire too, by its own scroll
    // or by being driven, so it has to redraw as well
    this.other.addEventListener("scroll", () => this.wire(), {passive: true});

    // The two columns scroll; nothing else on the page does. That
    // leaves the strip between them — 17rem in the dead centre of
    // the screen, exactly where a cursor rests — and the bar at the
    // top as places where the wheel does nothing at all, which
    // reads as "this page will not scroll". Anywhere that is not a
    // column drives the one being read.
    this.onWheel = (e) => {
      if (e.target.closest(".fl-col")) return;
      this.lead.scrollTop += e.deltaY;
      e.preventDefault();
    };
    this.el.addEventListener("wheel", this.onWheel, {passive: false});
    // reading the right-hand document by hand should not be fought
    this.other.addEventListener("wheel", () => this.release(), {passive: true});
    window.addEventListener("resize", this.onScroll);

    // A tap on a highlighted passage picks it, rather than making
    // someone scroll it past the focus line. On a phone, where
    // the other column is not on screen at all, that is the only
    // way to point at something.
    this.onTap = (e) => {
      // the chip's menu picks one edge out of several; letting the
      // tap handler run too would immediately re-select the first
      if (e.target.closest(".fl-jump")) return;
      const block = e.target.closest(".fl-block.linked");
      if (!block) return;
      if (window.getSelection()?.toString()) return;
      this.current = block;
      this.free = false;
      this.mark(block);

      if (this.phone()) {
        if (this.fillStack(block)) {
          this.sheet.hidden = false;
          this.strip.hidden = true;
          this.stack.scrollTop = 0;
          this.openSheet();
        }
      } else {
        this.align(block);
      }
    };
    this.lead.addEventListener("click", this.onTap);

    this.onSheetKey = (e) => {
      if (e.key === "Escape" && this.mid?.classList.contains("open")) this.closeSheet();
    };
    document.addEventListener("keydown", this.onSheetKey);

    // Delegated, not bound to the nodes themselves: a patch can
    // replace them, and a listener on a node that is no longer in
    // the document is a control that silently stops working.
    this.onSheetClick = (e) => {
      // asking about it takes you into the chat, so the reference
      // gets out of the way rather than sitting on top of it
      // The stack's cards are created here, not rendered by the
      // server, so LiveView never bound their clicks — the hook
      // sends the event itself.
      const ask = e.target.closest(".fl-card .ask");
      if (ask) {
        if (ask.dataset.edge) this.pushEvent("cite_edge", {edge: ask.dataset.edge});
        return this.closeSheet();
      }

      // The strip's ask is the same gesture as clicking the drawn
      // line, so it sends the same event. It used to be a server
      // `phx-click` whose edge id the hook wrote on with
      // setAttribute — a server-owned attribute patched from JS,
      // paired with a handler clause that silently did nothing when
      // the attribute was missing. One path, pushed from here, is
      // both shorter and impossible to half-wire.
      const stripAsk = e.target.closest(".fl-strip .ask");
      if (stripAsk) {
        if (this.edge) this.pushEvent("cite_edge", {edge: this.edge});
        return;
      }

      if (e.target.closest(".shut")) {
        return this.closeSheet();
      }
      // the dimmed part, outside the sheet itself
      if (e.target.classList && e.target.classList.contains("fl-mid")) {
        return this.closeSheet();
      }
    };
    this.el.addEventListener("click", this.onSheetClick);

    this.follow();
  },

  updated() {
    // the patch may have swapped the nodes underneath us
    const wasOpen = this.mid?.classList.contains("open");
    this.cache();
    if (wasOpen) this.mid?.classList.add("open");

    this.seen.clear();
    this.current = null;
    this.follow();
  },

  destroyed() {
    document.documentElement.classList.remove("fl-sheet-open");
    document.removeEventListener("keydown", this.onSheetKey);
    this.lead.removeEventListener("click", this.onTap);
    this.el.removeEventListener("click", this.onSheetClick);
    this.el.removeEventListener("click", this.onWireClick);
    this.el.removeEventListener("click", this.onJump);
    this.el.removeEventListener("mouseover", this.onPeek);
    this.el.removeEventListener("mouseout", this.onPeek);
    this.lead.removeEventListener("scroll", this.onScroll);
    this.el.removeEventListener("wheel", this.onWheel);
    cancelAnimationFrame(this.frame);
    window.removeEventListener("resize", this.onScroll);
  },

  release() { this.free = true; },

  // A phone has no room for a second column and no room for a
  // permanent strip either: the screenshot that killed the last
  // design had six hundred pixels of chrome, a sliver of reading
  // and a sheet competing with it for the rest. So the reference
  // is a place you go and come back from.
  phone() { return window.matchMedia("(max-width: 1100px)").matches; },

  // The sheet scrolls, and it kept its position between passages,
  // so it opened halfway down the previous one. Defined here with
  // the other methods rather than as a closure in mounted(),
  // where deleting the code above it took this with it and left
  // mark() calling a function that no longer existed — which
  // threw after the highlight and before the sheet, so a tap lit
  // the paragraph and did nothing else.
  rewind() { if (this.strip) this.strip.scrollTop = 0; },

  // One card per connection on the tapped paragraph, in the order
  // the page has them. Built here rather than rendered by the
  // server because the server does not know which paragraph a
  // thumb landed on, and shipping every paragraph's stack up
  // front would be the whole document twice.
  fillStack(block) {
    const notes = [...block.querySelectorAll("[data-peer-ref]")];
    if (!notes.length) return false;

    this.sheet.querySelector(".n").textContent =
      notes.length === 1 ? "1 connection" : `${notes.length} connections`;

    this.stack.replaceChildren(
      ...notes.map((note) => {
        const card = document.createElement("article");
        card.className = `fl-card k-${note.dataset.kind}`;

        const peer = this.other.querySelector(
          `#blk-other-${CSS.escape(note.dataset.peerRef || "")}`
        );
        const prose = peer
          ? [...peer.querySelectorAll("p")].map((el) => el.textContent.trim()).join(" ")
          : "";

        const head = document.createElement("header");
        const rel = document.createElement("span");
        rel.className = "rel";
        rel.textContent = (note.dataset.kind || "").replace(/_/g, " ");
        const src = document.createElement("span");
        src.className = "src";
        src.textContent = note.dataset.src || "";
        head.append(rel, src);

        const why = document.createElement("p");
        why.className = "why";
        why.textContent = note.dataset.why || "";

        const ask = document.createElement("button");
        ask.type = "button";
        ask.className = "ask";
        ask.dataset.edge = note.dataset.edge || "";
        ask.textContent = "ask about this";

        card.append(head, why);

        if (prose) {
          const far = document.createElement("blockquote");
          far.className = "far";
          far.textContent = prose;
          card.append(far);
        }

        card.append(ask);
        return card;
      })
    );

    return true;
  },

  openSheet() {
    this.mid.classList.add("open");
    document.documentElement.classList.add("fl-sheet-open");
  },

  closeSheet() {
    this.mid.classList.remove("open");
    document.documentElement.classList.remove("fl-sheet-open");
  },

  // The linked paragraph you are currently on: the last one to have
  // crossed the focus line while still being on screen. The "still
  // on screen" half matters — without it a paragraph scrolled past
  // ten screens ago stays selected through every unlinked stretch,
  // and the right-hand column sits on something you cannot see.
  currentBlock() {
    const box = this.lead.getBoundingClientRect();
    const line = box.top + this.lead.clientHeight * 0.33;
    let passed = null;
    let upcoming = null;

    for (const b of this.lead.querySelectorAll(".fl-block.linked")) {
      const r = b.getBoundingClientRect();
      if (r.bottom < box.top || r.top > box.bottom) continue;
      if (r.top <= line) passed = b;
      else if (!upcoming) upcoming = b;
    }

    // nothing has crossed the line yet but something is coming: show
    // it rather than nothing, so the right column is never blank
    // while a link is plainly visible
    return passed || upcoming;
  },

  follow() {
    // nothing to follow with: the reference is not on screen and
    // the reader opens it deliberately
    if (this.phone()) return;

    // A jump from the right column scrolls the left one, and that
    // scroll fires this. Without the hold, follow() re-picks
    // whatever paragraph the smooth scroll is currently passing
    // and the pair you asked for is gone before it arrives.
    if (performance.now() < (this.hold || 0)) return;

    const block = this.currentBlock();
    if (!block) return this.blank();

    if (block !== this.current) {
      this.current = block;
      this.free = false;
      this.mark(block);
    }

    if (!this.free) this.align(block);
  },

  // One entry of the chip's menu. The button carries only the edge
  // id; the note itself is the hidden span already on the paragraph,
  // which is where every other path here reads a relation from.
  jump(item) {
    const edge = item.dataset.edge;
    const block = item.closest(".fl-block");
    const mine = block.querySelector(`[data-peer-ref][data-edge="${CSS.escape(edge)}"]`);
    if (!mine) return;

    this.peek(null);

    // Clicked in the left column: this paragraph is the near end,
    // and the right column comes to meet it.
    if (this.lead.contains(block)) {
      this.current = block;
      this.free = false;
      this.mark(block, mine);

      if (this.phone()) {
        if (this.fillStack(block)) {
          this.sheet.hidden = false;
          this.strip.hidden = true;
          this.stack.scrollTop = 0;
          this.openSheet();
        }
      } else {
        this.align(block, mine);
      }
      return;
    }

    // Clicked in the right column, where the far end is a paragraph
    // of the document being read. Go there rather than to it: the
    // left column is the one with the reading position in it.
    const ref = mine.dataset.peerRef;
    const target = ref && this.lead.querySelector(`#blk-lead-${CSS.escape(ref)}`);
    if (!target) return;

    const note =
      target.querySelector(`[data-peer-ref][data-edge="${CSS.escape(edge)}"]`) ||
      target.querySelector("[data-peer-ref]");

    const to =
      target.getBoundingClientRect().top -
      this.lead.getBoundingClientRect().top +
      this.lead.scrollTop -
      this.lead.clientHeight * 0.28;

    this.hold = performance.now() + 1200;
    this.lead.scrollTo({top: Math.max(0, to), behavior: "smooth"});

    this.current = target;
    this.free = false;
    this.mark(target, note);
    this.chase();
  },

  // The far paragraph of the entry under the cursor, lit but not
  // chosen. A class of its own: `on` is the committed pair, and
  // borrowing it would leave two pairs highlighted at once.
  peek(item) {
    this.el.querySelectorAll(".fl-block.peek").forEach((b) => b.classList.remove("peek"));
    if (!item) return;

    const here = item.closest(".fl-block");
    const far = this.lead.contains(here) ? this.other : this.lead;
    const side = far === this.other ? "other" : "lead";
    const ref = item.dataset.peerRef;
    if (!ref) return;

    far.querySelector(`#blk-${side}-${CSS.escape(ref)}`)?.classList.add("peek");
  },

  // `pick` is the specific edge to show. It defaults to the first
  // one on the paragraph, which is what scrolling past it means,
  // but a hub paragraph has several and the chip's menu names one.
  mark(block, pick) {
    const note = pick || block.querySelector("[data-peer-ref]");
    if (!note) return;

    this.lead.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.other.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    block.classList.add("on", "seen");

    const peer = this.other.querySelector(`#blk-other-${note.dataset.peerRef}`);
    peer?.classList.add("on");

    this.strip.hidden = false;
    this.idle.hidden = true;
    this.strip.dataset.kind = note.dataset.kind;
    this.strip.querySelector(".rel").textContent = note.dataset.kind.replace(/_/g, " ");
    this.strip.querySelector(".why").textContent = note.dataset.why;

    this.seen.add(note.dataset.edge);
    this.count.textContent = this.seen.size;
    this.strip.querySelector(".nth").textContent = note.dataset.src;

    // The passage on the other side, for the half of the screen a
    // phone does not have. The paragraphs only: the block also
    // holds the relation tag
    // and the hidden spans carrying this data, and on a phone the
    // column is display:none, where innerText falls back to
    // textContent and would sweep both of them in
    const far = this.strip.querySelector(".far");
    const prose = peer
      ? [...peer.querySelectorAll("p")].map((el) => el.textContent.trim()).join(" ")
      : "";
    far.textContent = prose;
    far.hidden = !prose;
    this.svg.dataset.kind = note.dataset.kind;
    // what the strip's ask button will cite, read at click time
    this.edge = note.dataset.edge;
    this.rewind();
    this.chase();
  },

  // the right column is scrolled smoothly, so the wire has to follow
  // it rather than be drawn once against where it used to be
  chase() {
    cancelAnimationFrame(this.frame);
    const until = performance.now() + 900;
    const step = () => {
      this.wire();
      if (performance.now() < until) this.frame = requestAnimationFrame(step);
    };
    step();
  },

  wire() {
    const l = this.lead.querySelector(".fl-block.on");
    const r = this.other.querySelector(".fl-block.on");
    if (!l || !r || this.strip.hidden) return this.svg.setAttribute("hidden", "");

    const box = this.split.getBoundingClientRect();
    const lb = l.getBoundingClientRect();
    const rb = r.getBoundingClientRect();
    const card = this.strip.getBoundingClientRect();
    const lc = this.lead.getBoundingClientRect();
    const rc = this.other.getBoundingClientRect();

    // a passage scrolled out of its own column is not connected to
    // anything the reader can see
    const on = (b, c) => b.bottom > c.top + 4 && b.top < c.bottom - 4;
    if (!on(lb, lc) || !on(rb, rc)) return this.svg.setAttribute("hidden", "");

    // below the sticky column head, so the line never runs under it
    const clamp = (y, c) => Math.max(c.top + 44, Math.min(y, c.bottom - 8));
    const y1 = clamp(lb.top + lb.height / 2, lc) - box.top;
    const y4 = clamp(rb.top + rb.height / 2, rc) - box.top;
    const ym = card.top + card.height / 2 - box.top;

    const x1 = lb.right - box.left;
    const x2 = card.left - box.left - 6;
    const x3 = card.right - box.left + 6;
    const x4 = rb.left - box.left;

    this.svg.removeAttribute("hidden");
    this.svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
    const d1 = `M ${x1} ${y1} C ${(x1 + x2) / 2} ${y1}, ${(x1 + x2) / 2} ${ym}, ${x2} ${ym}`;
    const d2 = `M ${x3} ${ym} C ${(x3 + x4) / 2} ${ym}, ${(x3 + x4) / 2} ${y4}, ${x4} ${y4}`;
    this.svg.querySelector(".w1").setAttribute("d", d1);
    this.svg.querySelector(".w2").setAttribute("d", d2);
    this.svg.querySelector(".h1").setAttribute("d", d1);
    this.svg.querySelector(".h2").setAttribute("d", d2);
    this.svg.querySelector(".d1").setAttribute("cx", x1);
    this.svg.querySelector(".d1").setAttribute("cy", y1);
    this.svg.querySelector(".d2").setAttribute("cx", x4);
    this.svg.querySelector(".d2").setAttribute("cy", y4);
  },

  // put the cited passage at the same height as the one being read
  align(block, pick) {
    const note = pick || block.querySelector("[data-peer-ref]");
    const peer = note && this.other.querySelector(`#blk-other-${CSS.escape(note.dataset.peerRef || "")}`);
    if (!peer) return;

    // offsetTop is measured from the offsetParent, which is not the
    // scroll container — the two only agree by accident. Work in
    // viewport coordinates and add the scroll back on.
    const want = block.getBoundingClientRect().top - this.lead.getBoundingClientRect().top;
    const peerTop =
      peer.getBoundingClientRect().top -
      this.other.getBoundingClientRect().top +
      this.other.scrollTop;

    const to = Math.max(0, Math.min(peerTop - want, this.other.scrollHeight - this.other.clientHeight));

    if (Math.abs(this.other.scrollTop - to) > 2) {
      this.other.scrollTo({top: to, behavior: "smooth"});
    }
  },

  blank() {
    this.svg.setAttribute("hidden", "");
    this.strip.hidden = true;
    this.idle.hidden = false;
    this.lead.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.other.querySelectorAll(".fl-block.on").forEach((b) => b.classList.remove("on"));
    this.current = null;
  },
};
```

## 23. Rotate

`lib/marginalia_web/components/core_components.ex:537-558`

```js
// Three seconds a line, then out, swap, in. One line never rotates.
export default {
  mounted() {
    this.lines = JSON.parse(this.el.dataset.lines || "[]");
    this.i = 0;
    if (this.lines.length < 2) return;
    this.timer = setInterval(() => {
      this.el.classList.add("out");
      this.swap = setTimeout(() => {
        this.i = (this.i + 1) % this.lines.length;
        this.el.textContent = this.lines[this.i];
        this.el.classList.remove("out");
      }, 320);
    }, 3000);
  },
  destroyed() {
    clearInterval(this.timer);
    clearTimeout(this.swap);
  },
};
```
