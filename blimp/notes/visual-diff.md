# Visual diff: Blimp rewrite vs the Phoenix original

Result: at 1280 px wide, light and dark, the two apps render pixel-identically on every compared page except four (`/drafts`, `/drafts/<slug>`, `/links`, `/users/register`), which differ by an ordering tie-break, a missing floating button, and two sub-pixel text shifts. Everything else that differs is behavioural (first-run tour, chat pill count, a crash in Phoenix) or invisible (markup).

All numbers below come from a pixel diff of full-page PNGs (threshold: summed RGB delta > 24), not from eyeballing. Screenshots are in
`/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad/shots/<page>-{phoenix,blimp}.png`, diff overlays in `shots/diff/<page>-diff.png`, side-by-side crops in `shots/crop-*.png`. Normalised DOM text for every page is in `scratchpad/norm/`, the raw post-JS DOM in `scratchpad/dom/`.

## Setup (exact)

Scratchpad = `/private/tmp/claude-501/-Users-bg-code-marginalia/0085fd58-ce55-4cc1-bad7-6e37ce5bdc30/scratchpad` (all scripts named below live there).

Blimp (rewrite, worktree incl. its uncommitted edits to `temper/web` and `temper/webtest`):

```
cd /Users/bg/code/marginalia/.claude/worktrees/blimp-rewrite/blimp && ./build.sh      # 74 s, out/marginalia.blimp 197,999 lines
BLIMP=/Users/bg/code/temper-blimp-115/blimp/chunks/lang/zig-out/bin/blimp
$BLIMP test/fake_llm.blimp 4871 test/fixtures/llm &
MARGINALIA_DB=$S/run/blimp.sqlite3 PORT=4873 \
  MARGINALIA_LLM_ENDPOINT=http://127.0.0.1:4871/chat/completions MARGINALIA_LLM_PROVIDER=deepseek \
  DEEPSEEK_API_KEY=anything MARGINALIA_OWNER_EMAIL=owner@example.com OWNER_EMAIL=owner@example.com \
  MARGINALIA_SECRET='test-secret-32-bytes-long-string!!' $BLIMP out/marginalia.blimp &     # start.sh
```

Phoenix (original). `config/dev.exs` hard-codes `marginalia_dev` and the LLM endpoint can only be set through `config :marginalia, :llm_endpoints` (no env), so the main checkout could not be run unmodified against a throwaway database. I did not touch the main checkout. I copied it (`rsync`, excluding `.git`, `.claude`, `blimp`, `node_modules`, `log`, `var`; `.env` and `erl_crash.dump` deleted from the copy) to `$S/phx` and edited only the copy's `config/dev.exs`:

- `database: "marginalia_visualdiff"` (created with `psql -U postgres -c "create database marginalia_visualdiff"`, migrated with `MIX_ENV=dev mix ecto.migrate`)
- `llm_endpoints` for both providers -> `http://127.0.0.1:4871/chat/completions` (the same fake model), `llm_backoff_ms: 0`
- `debug_errors`, `code_reloader`, `debug_heex_annotations`, `debug_attributes` -> false (dev-only chrome that would pollute the 404 page and the DOM); watchers disabled; then `mix deps.compile phoenix_live_view --force` and `mix compile --force` so the annotations are really gone
- run with `MIX_ENV=dev PORT=4872 DEEPSEEK_API_KEY=anything LLM_PROVIDER=deepseek OWNER_EMAIL=owner@example.com mix phx.server` (`start_phx.sh`); `runtime.exs` overrides the port from `PORT`

The Phoenix code under test is the main checkout's current working tree at copy time; app code and templates are untouched.

Seeding (every request is logged in `$S/seed.log`; scripts `seed1.sh`, `seed2.mjs`, `seed3.mjs`, `seed4.sh`, `login.sh`):

1. User `owner@example.com` / `correct horse battery`. Blimp: plain `POST /users/register`. Phoenix: registration is a LiveView with no plain-HTTP path, so `mix run -e 'Marginalia.Accounts.register_user(...)'` (the function the LiveView calls). Then `POST /users/log-in` with a CSRF token in both.
2. `POST /works/new` (`work[title]`, `work[intent]`, `work[body]`) with `kettle.md`, `notes-on-a-server.md`, `lighthouse.txt`, and `kettle.md` again as `kettle-two`. Same bytes to both apps.
3. Read started by clicking "Read it" in headless Chrome. The fake model has beats only for the kettle text, so `kettle` and `kettle-two` have 3 beats each; `notes-on-a-server` and `lighthouse` end `read` with `spine unavailable: :no_beats` in both apps.
4. One link: `kettle` + `kettle-two` through the `/links` form (status `linked`, 0 edges, in both). A first link `kettle`+`notes` fails with `:not_read` in both (the raw atom is shown to the user in both).
5. A case: no UI sets `works.collection`, so one SQL `UPDATE` per database (`psql` / `sqlite3`) put all four drafts in "The Kettle Case" with roles opinion/dissent/concurrence/argument.
6. Not creatable without GitHub: folders-with-cuts, stacks, import listing. `/stacks`, `/cuts`, `/import` are compared in their empty/initial states only.
7. A second user `second@example.com` (`tour.sh`) for the first-run-tour test.

Browser: headless `/Applications/Google Chrome.app` driven over the DevTools protocol by a 60-line Node script (`cdp.mjs`, Node's global WebSocket, no Puppeteer) so that cookies, the LiveView socket and `blimp.js` really run; 1280 px viewport, device scale 1, full-page capture, 2.5-3 s settle after load. Cookies for the logged-in pass come from the curl jar. Chrome's `prefers-color-scheme` was emulated for the dark pass. Commands: `node shots.mjs phoenix`, `node shots.mjs blimp`, `node diff.mjs`, `node crop.mjs <page> <y0> <y1>`, `node inter.mjs <app>`, `node dark.mjs <app>`; markup diff: `node norm.mjs dom/<p>-phoenix.html norm/<p>-phoenix.txt` then `diff`.

## Pages

Pixel diff = number of differing pixels out of the full page. "Same" means 0 differing pixels.

| Page (URL) | Result |
|---|---|
| `/` guest | same (12875 px tall) |
| `/` logged in | same (the first capture showed a note dimmed in Phoenix only; it was a transition caught mid-flight, two re-captures are 0 px) |
| `/cases` | same |
| `/cases/the-kettle-case` | same |
| `/cases/the-kettle-case/read` | same |
| `/works` guest | same |
| `/works` owner | same |
| `/works/new` guest and owner | same |
| `/works/<slug>?view=read` | same (once the first-run tour is out of the way; see D3) |
| `?view=graph`, `spine`, `threads`, `changes`, `trace`, `prompts` | same (7629 px tall for prompts) |
| `?view=read&chat=1` | same |
| `/works/<slug>` of a draft with 0 beats | same |
| `/drafts` | differs: order of two same-second drafts swapped (D1), 1,932 px |
| `/drafts/<slug>` | differs: floating "talk about this draft" button missing, notes are `div` not `button` (D2), 3,185 px |
| `/stacks`, `/stacks/new` | same (empty states) |
| `/cuts` guest and owner | same (empty states) |
| `/links` | differs: 149 px, sub-pixel shift of the "1 web of three or more" label (D8); and dropdown order (D1) |
| `/links/2`, `/links/2/read` | same (the page opens with its tour card in both) |
| `/linked`, `/reading` | same |
| `/import` guest and owner | same |
| `/users/log-in` | same |
| `/users/register` | differs: 556 px, sub-pixel shift of the subtitle line (D7) |
| `/users/settings` | same (needs a login < ~20 min old in both) |
| 404 (`/no-such-page-here`) | same, 0 px, same status 404 |
| Dark (`prefers-color-scheme: dark`): login, works guest, 404, works, work read, work graph, cases, link, settings | all same; neither app changes colours under the media query |
| Chat drawer opened, answered; `?` help; GRAPH tab; clicking a note | same once the model has answered, except D5 |

## Differences, most visible first

**D1. Draft order when two drafts have the same `inserted_at` second.** `/drafts` lists kettle-two, lighthouse, **kettle, notes-on-a-server** in Phoenix and kettle-two, lighthouse, **notes-on-a-server, kettle** in Blimp. The two were uploaded in the same second; the sort is `inserted_at desc` with no tie-break in Phoenix (`works.ex:59`), so Phoenix falls back to Postgres's row order (id ascending) and Blimp's SQLite returns id descending. The `/links` "Choose a draft" dropdowns reorder the same way (Blimp has `notes` before `kettle`, Phoenix `kettle` before `notes`). Visible whenever drafts are created in one second (bulk import, scripted uploads); `list_works` itself (`/works`) is `desc: w.id` and matches. A deterministic tie-break in either app would remove it.

**D2. `/drafts/<slug>` (the public draft page) is missing the chat bubble and the clickable notes.** Phoenix renders a fixed round "↔" button at bottom right (`div#linkchat > button.lc-bubble`, aria-label "Talk about this draft") for a signed-in reader; Blimp renders none (1204-1267 x, 1594-1657 y, 3,185 px). In Phoenix each note on this page is `<button class="mg-note ..." title="Talk about this">`; in Blimp it is `<div class="mg-note ...">`, so there is no tooltip, no pointer cursor via button defaults, and no click-to-discuss. The notes on `/works/<slug>?view=read` are buttons in both apps.

**D3. First-run tour appears in Blimp after reading, never in Phoenix.** Phoenix marks a tab's tour as seen when the tab is first opened, even when the page is the pre-read "Before it reads" screen that has no tour card (`work_live/show.ex` `maybe_tour`, marks on connected mount). Blimp marks it only when the card is rendered. Test with a fresh user (`tourtest.mjs`): upload, open `?view=read` twice (unread), start the read, open again: Phoenix no tour; Blimp shows "The page, with its notes in the margin" (screenshot `shots/work-read-blimp-with-tour.png`, 2270 px tall against 1903, 42% of pixels differ). So a user who opens the draft before reading sees the tour in Blimp and not in Phoenix. Once seen, both are identical. Same logic applies to the other tabs' tours (`seen` list in Blimp `users.tours_seen`: read, graph, spine, threads, trace, prompts, follow).

**D4. Phoenix crashes where Blimp does not (cases index).** With some drafts in a collection and a link between a collection draft and a non-collection draft, Phoenix `/cases` returns 500: `BadBooleanError ... got: nil` at `lib/marginalia/cases.ex:122` (`a && b && a.collection != b.collection` inside `and`). Blimp returned 200 in the same state (checked by temporarily clearing one collection). Screenshot of the Phoenix failure: `shots/cases-phoenix-crash-mixed-collection.png` (captured with debug errors on). This is an original-app bug, not a Blimp regression.

**D5. Chat pill count and response latency.** After one question and one answer the conversation pill reads "What is this draft doing? **1**" in Phoenix and "... **2**" in Blimp (`shots/i-chat-answer-*.png`, 26 px). Also 1.5 s after sending, Phoenix has already shown the answer while Blimp shows the three-dot indicator and a greyed "Thinking..." button (Blimp polls every 2 s); by 7.5 s the pages match.

**D6. Query-parameter order in the address bar.** Phoenix: `?chat=1&view=read`; Blimp: `?view=read&chat=1`. Same page.

**D7. `/users/register` subtitle line shifts by under a pixel** ("Already registered? Log in to your account now.", x 486-795, y 186-199, 556 px). Phoenix wraps the link text in newlines/indentation (`<a>\n Log in\n </a>`), Blimp has none. No layout change a person would notice.

**D8. `/links` "1 web of three or more" label** differs in 149 px (x 218-319, y 378-385), the same kind of text-position shift; not investigated further.

Invisible markup differences (every page; found by diffing normalised DOM):

- Wrapper: Phoenix `div#phx-...[data-phx-main]` LiveView container; Blimp `main#main` plus an extra empty `div`. `main` has `id=main` only in Blimp.
- "Log out" is `<a href="/users/log-out">` (Phoenix, method delete by JS) vs `<form method=post><input _method=delete><button>` (Blimp). Pixel-identical.
- Blimp adds ids for morphing: `work-N` on `.mg-wrow`, `grounded-N`, `legend-*`, `pass-*`, `mode-*`, `fetch-form`, `upload-form`, `stack-import`, `manuscript`.
- Form field ids: Phoenix `user_email`, `user_password`; Blimp `registration_form_email`, `login_form_password_password`, `password_form_password`, etc. (labels use matching `for`). Blimp inputs carry an empty `value` attribute.
- Registration form: Phoenix has no `action`; Blimp has `action=/users/register`. `/users/settings` email form: Phoenix `method=put`; Blimp none.
- `<button class="im-card">` on `/import`: Blimp adds `type=button`.
- `<link rel=canonical>` and `og:url`/`og:image` use `http://localhost:4000` in Blimp (default of its public-origin env, `webcore/layouts.temper.md:53`) and the endpoint URL in Phoenix. Not a difference when the env is set; I did not set it.
- Redirects are 303 in Blimp, 302 in Phoenix; `robots.txt` and `favicon.ico` content-types differ slightly (`text/plain; charset=utf-8`, `image/x-icon`). `/dev/dashboard` is 404 in Blimp (dev-only route in Phoenix).
- Head tags (`description`, Open Graph, Twitter, theme-color) are the same apart from the origin.

Hooks that needed JS: all ran on both (graph, link page, chat drawer, tabs, help, note click, theme). Compiled CSS, fonts, icons, spacing and light/dark were identical in every pair.

## What I could not compare, and why

- Stacks, cuts, import listing, folders with cuts: need a GitHub repository and network; only the empty states and the forms were compared.
- Link graph with edges and the link page's scroll-follow, folded gaps, filters: the fake model returns no link edges (0 edges in both apps), so the populated link reader was not exercised. Same for populated `/cases/<slug>/read/<lead>` pages.
- Tension/connection-rich read pages, multi-section drafts, rewrites ("Suggest a rewrite"), summaries: the fake model has fixtures for only a few prompts, so real model output was not compared; the notes shown come from the fixtures.
- Text selection toolbar: a synthetic selection in headless Chrome did not raise the toolbar in either app (both report the buttons at 0x0), so it is not compared.
- Drag-and-drop ordering of drafts, hover/focus states, keyboard shortcuts, scroll-linked animation timing, mobile widths, long-running read progress screens, the live-update path (LiveView push vs 2 s polling) beyond D5.
- Owner-only backend switch, password/email change submissions, guest-to-account conversion, flash toasts after actions. A "Welcome back!" toast was present in the Phoenix DOM of `/drafts/<slug>` right after login and absent in Blimp's; I could not reproduce it with curl (neither app showed it) and did not isolate it.
- Phoenix ran from a copy with dev-only debug flags off and a different database name; Blimp ran against SQLite. Timestamps, ids and slugs differ by construction and were masked in the DOM diff.
- Only one browser (Chrome headless, macOS font rendering), one width (1280).

Servers (4871, 4872, 4873) were stopped and `marginalia_visualdiff` dropped at the end.

## Read after the fact (coordinator, 2026-10-15)

D2 is not a Blimp omission. The committed `DraftLive.Show` (the worktree's
`lib/marginalia_web/live/draft_live/show.ex`, 89 lines) renders each note as
a `div` and has no chat bubble, which is what Blimp does. The Phoenix that was
screenshotted ran from a copy of the main checkout, whose working tree holds
uncommitted changes to `draft_live/show.ex` (240 lines: a public chat through
`Chat.Editor` with `public: true`, the LinkChat bubble, discuss buttons, links
to a published folder's neighbours), `chat/editor.ex`, `link_chat.ex`,
`reading_live/index.ex`, `reading_live/story.ex`, three tests and
`assets/css/app.css`. The rewrite follows committed main; those changes are
work in progress and were not ported.

D5: Phoenix's conversation list is loaded at mount and not refreshed when the
async answer lands, so its pill shows the count before the answer; Blimp
re-reads on every request and shows 2. Blimp's is the stored count.

D1 is fixed in the rewrite: the owner's listing orders `inserted_at DESC, id
ASC`, the order Postgres happens to give Phoenix.

D3 is by design (see the pages_show commit): the tour is marked seen when its
card is shown, not when a tab is first opened on an unread draft.

