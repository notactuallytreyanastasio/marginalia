# Brief for a page library (Phase 3)

You are porting a group of Marginalia's LiveView pages to Temper on Blimp.
Read, in this order: `blimp/PLAN.md` (all; §6 and §6a are the rules that
bite), this file, `blimp/notes/assets.md` §3 (what the client does with the
HTML you emit), the `webcore` library's `src/*.temper.md` (layouts,
components, Ctx, session, flash, auth, response helpers: the API you call),
then the sections of `blimp/notes/web-*.md` named in your assignment, and
the matching parts of `blimp/notes/tests.md` (parts 5-9) which the e2e suite
asserts. The HEEx under `lib/marginalia_web/` is the truth when the notes are
silent; read it.

## The model

There is no socket. Every page is a function of a request: load state from
the database, render `<main>`. Every event is `POST /ev/<name>` with a JSON
payload and the page's path; the handler mutates (database, or the small
per-session UI state), then the page is re-rendered and its `<main>` goes
back as `{"regions": {"#main": html}, ...}`; `blimp.js` morphs it in by
element id. A page that is waiting for background work carries
`data-poll="2"` on `<main>` and the client re-fetches it every two seconds.

So a page library exports three things per page group:

```temper
export let pages<Group>Routes(): List<Route>;            // Route(method, pattern, name), in Phoenix router order
export let pages<Group>Get(ctx: Ctx, match: Match): Response throws Bubble;   // GET: full page or JSON region
export let pages<Group>Event(ctx: Ctx, match: Match, event: String, payload: JsonObject): Response throws Bubble; // POST /ev/<event> for a path this group owns
```

and the `web` router library assembles them. Inside, one module per page:
`load<Page>(ctx, params): <Page>State` (every query the mount did),
`render<Page>(ctx, state): List<AnyValue>` (the `<main>` subtree, as the
html library's nested-list tree), `handle<Page>(ctx, state, event, payload):
EventOutcome` (what handle_event did: a state change, a redirect, a flash, a
client event). `webcore` turns a rendered tree plus the layout into the
right Response for the request (`webPage(ctx, title, meta, tree)` answers
HTML on a plain GET and the JSON region on a poll or event; `webEventReply`,
`webRedirect(ctx, to, flash)` do the rest).

## webcore as implemented (read its src for signatures)

`webPage(ctx, meta: PageMeta, main, poll: Int?, layout: "app" | "bleed" |
"bare" | "root")`, `webEventReply(ctx, main, events, flash, poll)`,
`webRedirect(ctx, to, flash)`, `webNotFound/webForbidden/webServerError`,
`uiGet/uiPut/uiDelete/uiGetJson/uiPutJson`, `webMeta(title)`,
`webPutFlash`, `cButton`, `cInputSpec(name)`+`cInput`, `cTextInput`,
`cHeader`, `cTable`, `cList`, `cIcon` (the `.hero-*` span the CSS already
styles), `cMutter`, `cThemeToggle`, `cFlashGroup`. Every Response webcore
returns is finished (session saved, cookies set): return it as is. Plugs:
`webMountCurrentScope(ctx)` (call on every route), `webEnsureUserOrGuest`,
`webRequireRealAccount`, `webRedirectIfAuthenticated`, `webLogIn(ctx, user,
remember)`, `webLogOut(ctx)`; CSRF: the router calls `webCheckCsrf(ctx)`
before any POST or `/ev/`; forms include `webCsrfField(ctx)`. `data-poll`
goes through the `poll` argument, never written by hand. Log out is a form
posting `_method=delete` to `/users/log-out`.

## Markup rules

- Class names are copied from the HEEx exactly; the compiled CSS is fixed.
  Text is copied exactly, including punctuation and the `·` separators.
  `:if` becomes `if`, `:for` becomes `map`, `{@x}` becomes `htext(x)`.
- Keep the Phoenix attribute names: `phx-click`, `phx-value-*`, `phx-submit`,
  `phx-change`, `phx-debounce`, `phx-click-away`, `phx-window-keydown`,
  `phx-key`, `phx-hook`, `phx-update="ignore"`, `phx-disable-with`,
  `phx-mounted`, `data-phx-theme`. `blimp.js` reads them. Element ids are
  what the morph keys on: every element that had an `id` in the HEEx keeps it,
  and every list item in a `:for` gets a stable id (`"note-${id}"`) even if
  the HEEx relied on `phx-update="stream"` for that.
- Hook names: `phx-hook="Name"` with the names in PLAN §6a (the two Composers
  are `ChatComposer` and `LinkChatComposer`).
- Links are ordinary `<a href>`; `<.link navigate>`/`patch` become plain
  links. `phx-trigger-action` forms become plain `method="post"` forms to
  the controller routes. Uploads become `<form method="post"
  enctype="multipart/form-data">` to the page's own POST route; progress UI
  is dropped and said so in the report.
- `JS.show/hide/toggle` become `phx-click` events that flip a UI-state flag
  and re-render, unless the notes say the CSS handles it with `hidden`.
- Escape everything that came from the database or the user with `htext`;
  `hraw` only for HTML the html library produced (`markdownToHtml`) or the
  heroicon SVGs from `webcore`.
- Build the tree with list literals and `map`; never a builder loop over
  more than ~2,000 items. A section body goes through `markdownToHtml` once.

## State that was in assigns

Anything the LiveView kept in assigns that is not derivable from the
database on every request (open thread id, chosen view when not in the URL,
a filter string, the public chat's history, "seen tour" for a visitor,
selected rows, wizard step on /import) lives in the session's UI state:
`uiGet(ctx, "<page>:<key>"): String?`, `uiPut(ctx, key, value)`,
`uiPutJson`, `uiGetJson`, or in the URL query where the Elixir already used
`?view=`. Keep it small; it is one JSON column per session. A chat whose
history the Elixir held in the socket is capped at the last N messages the
notes say.

## Auth and scope

`webcore` runs the plugs: `ctx.scope` is `noScope()` for a visitor,
a guest `Scope` where the route group minted guests (`ensure_user_or_guest`),
a real user where `require_real_account` applied; redirects and flash texts
are verbatim from notes/web-public.md §2 and notes/web-cuts-links-users.md.
Your routes declare which group they are in by the `name` prefix
(`public.`, `guest.`, `real.`, `anyone.`) and `web` applies the plug.

## Background work and liveness

Pages that the Elixir refreshed on PubSub (`{:status, _}`, `{:run, ...}`,
`{:link, ...}`) render `data-poll="2"` on `<main>` while the relevant row
says work is in progress (`work.status == "reading"`, an active `Run` for
the key, `link.status == "linking"`), and nothing else: the next poll
re-renders from the database. Start work through the `runs` library
(`runsStart(dbPath, db, key, body)`); never fork in a page.

## Tests

Two kinds. Temper tests in your library for the pure parts: `render<Page>`
against a hand-built state asserting on substrings and on the presence of
the ids and classes the hooks need; `handle<Page>` on an in-memory `Db`
with fixtures through the domain libraries, asserting the state change and
the outcome. And the e2e files: enable the ones for your pages in
`blimp/test/e2e/IMPLEMENTED` (and write the missing ones named in that file's
comments from tests.md), run `blimp/test/e2e.sh` with `BLIMP` set to the 115
interpreter against `./build.sh`'s output, and paste the TAP output in your
report. If the full build is broken by a sibling library mid-edit, retry a
few minutes later; do not edit their files.

Build and test in isolation: `tb.sh pages_<group> webcore <every library you import>` (see PLAN §3 for the script). Edit only
in your library's directory and in the e2e files named for your pages. Do
not commit.

## Report

Every route and event implemented, the pass lines (Temper and e2e), every
HEEx construct you could not reproduce and what you did instead, every
place behaviour differs from LiveView (by name), and what does not work.
