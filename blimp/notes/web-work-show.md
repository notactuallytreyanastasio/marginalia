# The work page (`/works/:slug`) — specification

Source of truth: `lib/marginalia_web/live/work_live/show.ex` (4492 lines at main `c9eb474`, which includes the "mutterings" commits; an earlier draft of this note was written against `81161a8`),
`controllers/graph_controller.ex`, `controllers/work_controller.ex`, `controllers/work_html.ex`,
and the routes in `router.ex`. Where a behaviour depends on another module, that module's contract
is stated here under "Dependencies" so the rewrite does not need the Elixir.

CSS: every class name below is from the existing stylesheet (`assets/css/app.css`: `mg-*` classes
plus Tailwind utilities written inline). The CSS is reused byte for byte, so class strings must be
emitted exactly as written, including Tailwind arbitrary-value utilities such as `text-[0.8rem]`
and `border-[var(--mg-rule)]`. Whatever builds the CSS must still scan the new templates for them,
or those utilities will not exist.

Notation: HEEx is quoted verbatim. `{expr}` is an interpolation, `:if=`/`:for=` are conditional and
loop attributes, `phx-click="x"` pushes event `x` to the server, `phx-value-foo="v"` adds `foo: "v"`
to that event's params. An attribute whose value is `false` or `nil` is omitted; `true` renders the
bare attribute. A `class` given as a list drops `false`/`nil` entries. The section numbers match the
brief: 1 route, 2 mount, 3 render, 4 hooks, 5 events, 6 async and messages, 7 graph controller
(plus walkthrough and tour text), 8 no-JS create path, 9 summary.

---

## 1. Route, params, auth, layout

### Routes (router.ex)

```
scope "/", MarginaliaWeb do
  pipe_through [:browser, :ensure_user_or_guest]

  post "/works/new",            WorkController,  :create     # no-JS fallback, section 8
  get  "/works/:id/graph.json", GraphController, :json
  get  "/works/:id/graph.dot",  GraphController, :dot
  get  "/works/:id/trace.json", GraphController, :trace

  live_session :allow_guest, on_mount: [{MarginaliaWeb.UserAuth, :allow_guest}] do
    live "/works",     WorkLive.Index, :index
    live "/works/new", WorkLive.New,   :new          # declared before :id; first match wins
    live "/works/:id", WorkLive.Show,  :show         # this page
    ...
  end
end
```

* `live_action` is always `:show`. There is exactly one variant of the LiveView. Every other
  "variant" is a *view* (a tab) chosen by query string.
* Path param `:id` is the work's **slug** (128 random bits, url-safe base64 without padding, 22
  chars), not the numeric id. `Works.get_by_slug/1`.
* Query params, read in `handle_params`:
  * `view` = `read | spine | threads | graph | changes | trace | prompts`. Anything else or absent is `read`.
  * `chat` = `"1"` opens the chat drawer; anything else or absent closes it.
* The server keeps the URL authoritative with `push_patch(to: path, replace: true)` where
  `path = /works/{slug}?view={view}` plus `&chat=1` when the drawer is open. It always emits
  `view=`, so `/works/abc` becomes `/works/abc?view=read` after the first interaction. History is
  replaced, not pushed.
* Pipeline `:browser`: accepts html, session, live flash, root layout `MarginaliaWeb.Layouts :root`,
  CSRF, secure headers, `fetch_current_scope_for_user`. `ensure_user_or_guest` then guarantees a
  user: with no logged-in user it creates a guest account (`Accounts.create_guest_user/0`), starts a
  session for it and continues. On failure: flash "Something went wrong. Try logging in." and
  redirect to `/users/log-in`.
* LiveView `on_mount :allow_guest`: loads `current_scope` from the session token; with no user it
  redirects to `/users/log-in`. So **every request that reaches the page has a user**, guests included.

### Auth levels (the slug is the permission to read)

| name | meaning | computed as |
|---|---|---|
| reader | anyone holding the slug, guest or not | true whenever the work exists |
| `mine?` | this user owns this draft | `work.user_id == user.id` (`Works.owner?/2`) |
| `owner?` | this user is the account the deploy belongs to | lowercase email equals the configured owner email (`Accounts.owner?/1`) |
| `admin?` | `user.is_admin` (assigned, never rendered) | |

* A non-`mine?` reader sees the draft and its notes read-only, with a badge "reading someone's draft"
  and no mutating controls. Mutating events are also refused server side (section 5 records which are
  guarded and which are not).
* `owner?` additionally gets the Trace and Prompts tabs, the backend selector, and no chat quota.
* Non-existent slug on mount: `put_flash(:error, "No such draft.")` and `push_navigate` to `/works`.

### Layout

* Root layout (`layouts/root.html.heex`): `<html lang="en">`; head = `<.head_meta>`, `csrf-token`
  meta, `<link phx-track-static rel="stylesheet" href="/assets/css/app.css">`,
  `<script defer phx-track-static src="/assets/js/app.js">`, an inline theme script (sets
  `data-theme` on `<html>` from `localStorage["phx:theme"]` or the system preference, follows
  changes); body = inner content.
* `head_meta` for this page: `<title>` = `{work.title}` + suffix ` · Marginalia`; `<meta name="robots"
  content="noindex, nofollow">`; description, Open Graph and Twitter tags from the site defaults (no
  custom image or url; canonical is the site root; `theme-color` `#fbfaf7`).
* The page body is wrapped in `<Layouts.app flash={@flash} current_scope={@current_scope}>`:

```heex
<header class="mg-bar">
  <a href="/" class="mg-brand">Marginalia <span>a reader for drafts</span></a>
  <nav>
    <.link navigate={~p"/cases"}>Cases</.link>
    guest user -> Drafts(/works) | New draft(/works/new) | <span class="text-[var(--mg-dim)] opacity-70">guest</span> | <.link navigate="/users/register" class="mg-btn sm">Keep my drafts</.link>
    real user  -> Drafts(/works) | Linked(/links) | Cuts(/cuts) | Methods(/stacks) | New draft(/works/new) | {user.email}(/users/settings) | <.link href="/users/log-out" method="delete">Log out</.link>
    no user    -> Log in(/users/log-in)
  </nav>
</header>
<main class="px-4 py-8 sm:px-6 lg:px-8"><div class="space-y-4">{page content}</div></main>
<.flash_group flash={@flash} />
```

  `flash_group` is `<div id="flash-group" aria-live="polite">` holding an info flash and an error
  flash (`<div id="flash-info|flash-error" role="alert" class="toast toast-top toast-end z-50"><div
  class="alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap alert-info|alert-error">` icon,
  `<p>{message}</p>`, spacer, close button; clicking it pushes `lv:clear-flash` and hides it) plus two
  hidden connection banners, `#client-error` ("We can't find the internet") and `#server-error`
  ("Something went wrong!"), each followed by "Attempting to reconnect" and a spinning icon,
  revealed on socket disconnect. A rewrite without LiveView needs its own flash: one-shot info and
  error messages, dismissed on click.
* The page content div is `<div class="w-full px-6 py-6">` (full width on purpose).

---

## 2. Mount, handle_params, data loaded

### mount(%{"id" => slug})

1. `work = Works.get_by_slug(slug)`; `nil` -> flash + navigate (above).
2. If connected (the websocket render, not the first HTTP render):
   * `PubSub.subscribe("work:#{work.id}")` (`Analysis.topic/1`; `DecisionGraph` broadcasts on the same topic).
   * `Runs.subscribe({:work, work.id})`, i.e. PubSub topic `"run:{:work, ID}"`: the comparison pass belongs to the draft, not to this socket.
3. `{:ok, convo} = Chat.get_or_create_conversation(work.id)`. This **writes a row** if the draft has no
   whole-draft conversation (`anchor_kind == "work"`), even for a read-only visitor. Latest by id wins.
4. Assign everything in the table below, then `load_map/1`.

The page renders twice (HTTP, then websocket). Only the second is "connected": subscriptions and the
tour-seen write happen there.

### Shapes returned by the context functions

| call | returns |
|---|---|
| `Works.get_by_slug/1` | `Work{id, slug, title, intent, body, baseline_body, word_count, status ("pending"\|"reading"\|"read"\|"failed"), status_detail, first_impression, source_url, user_id, derived_from_id, inserted_at, updated_at}` |
| `Works.list_sections/1` | `[Section{id, work_id, ordinal (1-based), title, body, word_count, status ("pending"\|"reading"\|"read"\|"failed"), summary, summary_fingerprint, summary_body, summarised_at, summary_covers [string], summary_follows [int], summary_sets_up, summary_dropped [string]}]`, ascending ordinal |
| `Works.list_nodes(id, type: t)` | `[Node{id, work_id, section_id, node_type ("beat"\|"spine"\|"thread"\|"question"\|"note"), title, body, quote, ordinal, status ("pending"\|"superseded"\|...), narrative}]`, ordered by `ordinal, id` |
| `Works.counts/1` | `%{beats, spine, notes, questions, threads, total}` (integers) |
| `Works.revisions/1` | `[Revision{id, seq, before, after, origin ("edit"\|"rewrite"), note, section_ordinal, section_id}]`, ascending seq; the page stores them reversed (newest first) |
| `Works.revision_count/1` | integer |
| `Works.list_events/1` | `[GraphEvent{id, narrative, seq, tool, args (JSON string), result (JSON string), ok, node_id}]`, ascending id |
| `Works.event_stats/1` | `%{calls, refused, by_tool: %{tool=>n}, refusals: %{kind=>n}}` |
| `Works.baseline/1` | string: `baseline_body`, else reconstructed by un-applying revisions newest first |
| `Works.condensation_of/1` | the newest Work whose `derived_from_id == work.id`, or nil |
| `Links.for_work/1` | `[Link{id, status ("linking"\|"linked"\|...), a_work_id, b_work_id, a_work, b_work}]`, newest first; `Links.other(link, work_id)` is the Work at the other end |
| `Links.linkable(user_id, work_id)` | the user's other Works with `status == "read"`, newest first |
| `Links.get_for(a, b)` | the Link between two works or nil |
| `Chat.history(conv_id)` | last 60 messages, oldest first, as `[%{"role" => "user"\|"assistant", "content" => text}]` |
| `Chat.conversation_summaries/1` | `[%{id, mode, messages (count), title, at}]`, newest first, max 30, whole-draft convs only; title = explicit title, else the first user message with whitespace squashed and cut to 51 chars + "…" when over 52, else "New thread" |
| `Chat.threads_by_block/1` | `%{block_ref => %{id, messages (count), quote, resolved (bool), mode}}` for conversations that have a block_ref |
| `Chat.remaining/1` | `:unlimited` for the deploy owner, else `max(100 - user_questions_asked_across_all_their_drafts, 0)` |
| `Chat.allowed?/1` | `remaining != 0` |
| `Chat.message_limit/0` | 100 |
| `Chat.Editor.modes/0` | `[%{id, label, blurb, opener, stance}]`: `read` "Read" / "What is actually on the page"; `provoke` "Provoke" / "Questions that open the next draft"; `bounce` "Bounce" / "Pressure-test an idea against the draft". Default `"read"`. Openers: read "I've read the whole draft. Ask me what's there — or what isn't."; provoke "Ask me to push on something, or take one of these. I'll ask rather than answer."; bounce "Tell me the idea. I'll hold it against the draft you actually wrote and tell you where it bends." (`stance` is a long system-prompt fragment shown on the Prompts tab.) |
| `Document.get/1` | `DocumentSummary{summary, throughline, movements [%{"heading","sections" [..],"does"}], guidelines [%{"guideline","because","sections"}], tensions [%{"tension","sections"}], fingerprint, dropped [string]}` or nil |
| `Accounts.provider_for/1` | the deploy owner's chosen backend string (`"openai"`/`"deepseek"`) or nil for everyone else |
| `LLM.choices/0` | `[%{name: :openai\|:deepseek, label, model}]` for providers with an API key configured, sorted by label (labels "DeepSeek Flash", "Sol 5") |
| `LLM.configured?(provider)` | whether the resolved provider has a key |
| `LLM.label(provider)` | the provider's label; nil resolves to the deploy default |
| `LLM.provider_name/0` | the deploy default, atom `:openai` or `:deepseek` |
| `Mutterings.some(n)` | up to `n` random strings from the `mutterings` table (`text`, `source` default "cron"), excluding any this LiveView process showed recently (its process dictionary keeps the last 40; if everything unseen is exhausted the memory is reset); `[]` when the table is empty, which renders the dots alone. Rows are written elsewhere: on boot with an API key the table is filled to 100, then 10 more are added every half hour, each from a cheap model call with a fixed persona prompt (a modern-day Dostoyevsky working alone at a grilled-cheese counter, 240 characters or less; longer replies are dropped). A port needs the table and a way to fill it; the page only reads it. |
| `Analysis.passes/0 ++ DecisionGraph.passes/0 ++ Rewrite.passes/0` | `[%{id, name, model, runs, produces, prompt}]`; the Prompts tab prints them. They come from module attributes of the running code and are not stored. |

### Initial assigns

`page_title: work.title`, `page_robots: "noindex, nofollow"`, then:

| assign | initial | notes |
|---|---|---|
| `work` | the Work | replaced by `reload_work` |
| `conversation` | the whole-draft Conversation | `{id, mode, title, anchor_kind: "work"}` |
| `history` | `Chat.history(convo.id)` | |
| `view` | `:read` | overwritten by handle_params |
| `chat_open` | `false` | overwritten by handle_params |
| `draft` | `""` | assigned, never rendered |
| `loading` | `false` | a chat question is in flight |
| `graph_json` | `nil` | JSON string of `Graph.export` once the Graph tab has been opened |
| `graph_stats` | `nil` | `%{nodes, edges, anchored, by_type}` |
| `events` | `[]` | trace rows |
| `event_stats` | `nil` | |
| `page` | `nil` | `Reading.page` result; `nil` until the read view loads |
| `only` | `nil` | note filter: `nil` (all) \| `"beats"` \| `"connections"` \| `"tensions"` |
| `focus` | `nil` | what the chat is "holding": `%{kind, title, body, quote, sections: [Section]}` |
| `summary_link` | `summary_link(work)` | id of the Link between this draft and its condensation, or nil |
| `comparing` | `comparing(Runs.get({:work, work.id}))` | nil or a status string, see section 6 |
| `quota` | `Chat.remaining(user)` | `:unlimited` or integer |
| `threads_list` | `Chat.conversation_summaries(work.id)` | |
| `cited` | `[]` | passages carried into the next question: `[%{text, section (title), ordinal}]`, max 6 |
| `block_threads` | `Chat.threads_by_block(work.id)` | |
| `open_thread` | `nil` | the pinned Conversation currently open inline |
| `rewrite` | `nil` | `%{reading, original, section, candidates [%{text, move, cost}] (1..4), spans_blocks (bool), covers [block refs]}` |
| `rewriting` | `false` | a rewrite is in flight |
| `mutter` | `[]` | up to 8 "mutterings" (short in-character lines) shown in front of the thinking dots; refilled by `Mutterings.some(8)` each time a model call starts (`suggest_rewrite`, `steer_rewrite`, `thread_send`, `send`, including the demo paths). One list serves every thinking indicator on the page. |
| `revision_count` | `Works.revision_count(work.id)` | |
| `diff_rows` | `[]` | |
| `summarising` | `MapSet.new()` | ordinals of sections being summarised |
| `doc_running` | `false` | |
| `changes_on` | `false` | the read view shows the change rail instead of the notes |
| `applied` | `nil` | `%{before, after}` of the last accepted change |
| `document` | `Document.get(work.id)` | |
| `diff_stat` | `nil` | `%{same, changed, added, removed}` |
| `revisions` | `[]`, then overwritten by load_map | newest first |
| `steer` | `nil` | the writer's note on a rewrite |
| `rewrite_span` | `nil` | selected text being rewritten |
| `rewrite_ref` | `nil` | block ref the rewrite panel is anchored to |
| `editing` | `nil` | block ref being edited |
| `edit_text` | `nil` | text seeded into the editor |
| `tour` | `nil` | `%{title, points}` |
| `walk` | `[]` | walkthrough step list for the client |
| `demo` | `false` | walkthrough running: writes and model calls are faked |
| `links` | `Links.for_work(work.id)` | |
| `linking?` | `false` | link menu open |
| `preview` | `nil` | `%{original, text}`: a candidate shown inline in the prose |
| `thread_history` | `[]` | messages of `open_thread` |
| `thread_loading` | `false` | |
| `stages` | `infer_stages(work)` | `%{sections, spine, weave}`, each `:waiting\|:start\|:done\|:failed` |
| `started_at` | `DateTime.to_unix(work.inserted_at)` if `status == "reading"`, else `nil` | unix seconds. For a page loaded mid-read this is the work's *creation* time, not the read's start; `start_read` sets it to now. |
| `passes` | the three pass lists concatenated | |
| `graph_building` | `false` | not restored on mount; a reload mid-build shows the button again |
| `mode` | `convo.mode` | |
| `modes` | `Editor.modes()` | |
| `provider` | `Accounts.provider_for(user)` | |
| `admin?` | `user.is_admin` | unused in render |
| `owner?` | `Accounts.owner?(user)` | |
| `mine?` | `Works.owner?(work, user)` | |
| `backends` | `LLM.choices()` | |
| `llm_ready` | `LLM.configured?(provider)` | |

`load_map/1` (also run by `reload_work/1`) assigns `revisions` (newest first), `sections`, `beats`,
`spine`, `threads`, `questions` (the node lists by type) and `counts`.
`reload_work/1` re-fetches `Works.get_by_slug(slug)`, assigns `work` and `revision_count`, then `load_map`.

`infer_stages(work)`: `status == "read"` -> all `:done`; `status != "reading"` -> all `:waiting`;
else if `counts.spine > 0` -> `{sections: :done, spine: :done, weave: :start}`; else if every section is
`read` or `failed` -> `{sections: :done, spine: :start, weave: :waiting}`; else
`{sections: :start, spine: :waiting, weave: :waiting}`.

`summary_link(work)`: `Works.condensation_of(work.id)`, then `Links.get_for(work.id, condensation.id)`; the link's id or nil.

### handle_params(params, _uri, socket)

```
assign view: to_view(params["view"]), chat_open: params["chat"] == "1"
|> load_for_view()
|> maybe_tour()
```

`load_for_view`:
* `view in [:trace, :prompts]` and `owner? == false` -> `view = :read`, then load the page (the URL is not rewritten).
* `:read` -> `page = Reading.page(work, only: only)`. Runs on every params change, including a chat toggle.
* `:graph` and `graph_json == nil` -> `graph_json = Jason.encode!(Graph.export(work))`, `graph_stats = Graph.stats(work)`. Not reloaded on later visits; invalidated by `start_read`, refreshed by `{:graph, :done}`.
* `:trace` -> `events = Works.list_events`, `event_stats = Works.event_stats`.
* `:changes` -> `rows = Diff.rows(Works.baseline(work), work.body)`, `diff_stat = Diff.stat(rows)`, `revisions = reverse(Works.revisions)`.
* `:spine`, `:threads`, `:prompts` -> nothing extra (the data came from `load_map`/mount).

`maybe_tour`: `tour = Tour.for_view(view)` (a map keyed by view atom; tours exist for read, graph,
spine, threads, trace, prompts; none for changes). If the user's `seen_tours` string list contains
the view name, or there is no tour for it -> `tour = nil`. Otherwise, if connected:
`Accounts.mark_tour_seen(user, view)` (append the view name to `user.seen_tours`, and replace the
user in `current_scope`) and `tour = <that tour>`; if not connected, `tour = <that tour>` without
marking. Net effect: each tab's tour card shows once per user, on first connected visit; the `?`
button brings it back.

### Dependencies (contracts of modules this page leans on)

**`Reading.page(work, only: only)`** returns `[%{section: Section, blocks: [Block], unplaced: [Note]}]`, one per section in ordinal order.
* `Block = %{text, mark, notes: [Note], ref}`. `ref = "s{section.ordinal}p{paragraph_index_0_based}"`.
* Paragraphs come from `Reading.split(section.body)`: split on lines; a blank line ends a block; a line that starts (after leading whitespace) with 3+ backticks or tildes opens a fenced block that ends at the next line starting with the same fence string, however many blank lines it contains; trailing whitespace trimmed; empty blocks dropped.
* `Note = %{id, key, section_id, kind, quote, title, body, stale}`:
  * beat notes, one per node of type `beat`: `key "beat:{id}"`, `kind "beat"`, `quote`, `title`, `body`, `stale = (status == "superseded")`.
  * connection notes, from edges whose `edge_type` is one of `develops pays_off requires tension realises asks_about` with both end nodes present, shown only when the from-node is a beat with a section: `key "conn:{from_id}:{to_id}:{type}"`, `kind = type`, `quote = from.quote`, `title = label(type) <> " " <> to.title` with labels `develops →`, `pays off →`, `requires ←`, `tension with`, `realises`, `asks about`; `body = edge rationale`; `stale = false`.
  * `only`: `"beats"` keeps beat notes; `"connections"` keeps connection notes; `"tensions"` keeps connection notes of kind `tension`; anything else keeps both, beat notes first.
* Placement: for each paragraph in order, take the notes not yet placed whose `quote` locates in it via `Anchor.verify(quote, paragraph)` -> `{:ok, source_span}`. `Anchor.verify` contract: the quote must be at least 8 characters after trim; matching is on a normalised copy (whitespace, line wraps, curly punctuation, case) but the returned span is the literal substring of the paragraph; **exact, no fuzzy matching**. `block.mark` is the span of the first note that locates (one highlight per paragraph). A note that locates nowhere goes to the section's `unplaced`.
* `render_block(text, mark, ref, preview)`: renders the markdown to HTML (see `Markdown`) with `mark` wrapped as `<mark id="anchor-{ref}">…</mark>`. The id uses the *block* ref, so a block has at most one mark, with id like `anchor-s2p3`. The mark is shrunk inside leading/trailing `* _ ` ~` characters so emphasis still pairs. When `preview = %{original, text}` and `original` occurs in this paragraph: no mark; `original` is replaced in the source by a word diff against `text`, deletions as `<del class="mg-cut">…</del>` and insertions as `<ins class="mg-swap">…</ins>`; if `original` is not in this paragraph the paragraph renders normally.
* `Reading.outline(page)` returns `[%{id, level, title, words}]`: per section `%{id "sec-{ordinal}", level 0, title, words section.word_count}`, then one entry per block whose text is a markdown heading (`^#{1,6}\s+\S`): `%{id "block-{ref}", level = count of #, title = heading text, words nil}`, skipping headings whose text equals the section title case-insensitively.
* `Reading.focus(work, key)`: for `"beat:ID"`: `%{kind "beat", title, body, quote, sections [its section]}`; for `"conn:F:T:TYPE"`: `%{kind TYPE, title "{from.title}  —{TYPE with _ as space}→  {to.title}", body (edge rationale), quote from.quote, sections [from section, to section], uniq by id}`; otherwise nil.
* `Reading.grounding(work, node_id)` returns `%{beats: [%{id, title, quote, why, section}], sections: [Section]}`; beats are nodes of type `beat` joined to the node by edges of type `realises` or `asks_about` in either direction, unique by id, sorted by `{section.ordinal, id}`.
* `Reading.cite(work, text)` returns `%{text: exact source span, section: section title, ordinal}` or nil, via `Selection.locate` (the selection is verified as a substring of one section's body, possibly across paragraphs, with a minimum length).
* `Reading.plain(text)`: markdown links become their text, backticks/asterisks/underscores/tildes and leading `#`s are removed, whitespace collapsed and trimmed.

**`Markdown.to_html(text, breaks: :hard | :soft)`**: comrak with strikethrough, table, autolink, tasklist, footnotes; `smart: false`; raw HTML disabled (`unsafe: false`); output sanitised by an allowlist (script, `javascript:` hrefs, `on*` attributes gone). `:hard` (the default; chat replies) turns newlines into `<br>`; `:soft` (the draft) does not. Nil or "" -> "". On parse failure, HTML-escaped plain text.

**`Diff`**: `Diff.rows(a, b)`: paragraphs are split on 2+ newlines and trimmed; LCS over paragraphs compared whitespace-squashed; between two "same" rows the run of deletions and insertions is zipped pairwise into `{:change, l, r}`, leftovers become `{:del, l}` or `{:ins, r}`; equal rows are `{:same, p, p}`. `Diff.words(l, r)` is `Rewrite.diff`: tokens `\S+\s*`; compared on the trimmed token; computed with a Myers edit script (`List.myers_difference`), not an LCS table; result `[{:same|:del|:ins, joined_text}]` with adjacent same-op runs merged. Two rules beyond the plain edit script: (1) if both sides have 200 or more tokens and the number of distinct trimmed tokens they share is less than 5% of the smaller side's distinct-token count, the result is one `:del` run of all of the old text followed by one `:ins` run of all of the new (no specks); (2) a shared token is emitted as `:same` carrying the **new** side's trailing whitespace, except when the new token has none (it ends its paragraph), in which case it carries the old side's trailing whitespace. Deletions and insertions carry their own original whitespace. The change was made because the old table-based LCS took about 1.5 s per 2,000-word revision and the Changes page took 13 s. `Diff.stat(rows)` = `%{same, changed, added, removed}`. `Diff.any?(rows)` = some row is not `:same`.

**`Summary`**: `current?(section)` is true when `summary` is non-nil and `sha256_hex(section.body) == summary_fingerprint`. `drift(section)` is `[]` when current or when `summary_body` is nil, else `Diff.rows(section.summary_body, section.body)`.

**`Rewrite`**: `propose(work, span, provider:, steer:)` returns `{:ok, rewrite_map}` (shape above) or `{:error, :not_in_draft | {:span_too_long, words, 2500} | :no_candidates | other}`. `span_label(span)`: 0 words "Rewrites"; under 25 words "Rewrites of one line"; else "Rewrites of N words". `span_extent(span)`: nil if the whitespace-flattened span is 120 chars or fewer, else first 64 chars + " … " + last 48 chars. `place(block, original, seed)`: `{:ok, block with the first occurrence of original replaced by seed}` if the block contains original, else `:not_here`; if any argument is not a string and `seed` is, `{:ok, seed}`.

The walkthrough steps and the tour text are reproduced in section 7.


---

## 3. The rendered HTML, region by region

The page is one `render/1` plus 19 function components in `show.ex` (listed at the end of this
section), and it calls four external components: `Layouts.app` (section 1), `CoreComponents.mutter` (the thinking indicator, 3.20), `MarginaliaWeb.Walk.overlay`
(reproduced below) and `.link` (an `<a>`; `navigate=` is a client-side route change within the live
session, i.e. a normal link for a non-LiveView rewrite; `href=` with `method="delete"` is a link that
submits a DELETE form).

### Page skeleton (what `render/1` emits, in order)

1. **Header row** `div.flex.items-baseline.gap-3.flex-wrap`: `<h1>` title (serif via inline style),
   `span.mg-meta` "`{word_count} words · {n} sections · {beats} beats`", right group containing the
   link control (only `mine?` and `status == "read"`) and a "Read again" button (only `mine?`,
   `status == "read"`, `counts.beats == 0`; pushes `start_read`).
2. **"read alongside" row** `div.mg-linkrow` (only when the draft has links): one `<a class="one">` per link to
   `/links/{link.id}?lead={work.slug}` showing the other draft's title and, unless the link status is
   `linked`, a status chip `span.st.{status}`.
3. **Tab strip**: Read, Graph, Spine, Threads, then Changes (only when `revision_count > 0`), then
   Trace and Prompts (only when `owner?`); a `?` help button; at the right: "Copy link" button (mine) or the
   "reading someone's draft" badge (not mine), a "Talk about it" toggle for the chat drawer, and
   (deploy owner only, and only when more than one backend is configured) the backend `<select>`.
4. **`#page-body`** (`phx-hook=".Selection"`, class `mt-5 relative` + ` mg-shifted` when the drawer is open): the
   hidden selection toolbar `#sel-actions`, then the content column `div.min-w-0`, whose content is chosen by `work.status`:
   * `"pending"` -> `confirm_gate` (the draft has been split into sections and is awaiting "Read it").
   * anything else (`reading`, `read`, `failed`) -> `tour_card` (if `@tour`), the walkthrough overlay (if `@walk != []`),
     `progress` (only while `status == "reading"`), then `map_view` (dispatches on `@view`).
5. **Chat drawer** `div.mg-drawer` (+ ` open`; `aria-hidden` = not open) containing `chat_panel` only while open.

Region to component map: reading pane -> `read_pane`; margin notes -> `deck` inside `read_pane`'s rail;
threads on a paragraph -> `inline_thread`; contents rail -> `minimap`; rewrite candidates ->
`rewrite_panel`; lane tree -> `graph_pane`; summary vault -> `.mg-sum-vault` inside `read_pane`;
editor -> the `#edit-{ref}` form inside `read_pane`; share -> the `#share-link` button in `render`;
clock -> `#read-clock` in `progress`; steer -> `#rw-steer-form` in `rewrite_panel`; chat -> `chat_panel`;
spine / threads / questions -> `map_view` + `grounded_node`; Changes -> `changes_pane` + `diff_table`;
Trace -> `trace_pane`; Prompts -> `prompts_pane`.

### Things the markup depends on that are easy to break in a rewrite

* **Stable ids**: `page-body`, `sel-actions`, `sel-discuss`, `sel-rewrite`, `sel-add`, `share-link`,
  `linkbox`, `read-clock`, `graph-canvas`, `graph-svg`, `graph-detail`, `minimap`,
  `read-rail`, `read-body`, `read-filters`, `sec-{ordinal}`, `block-{ref}`, `anchor-{ref}` (on the `<mark>`),
  `deck-{first note key}`, `mutter-{hash of the lines list}`, `sumvault-{ordinal}`, `thread-{id}`, `thread-body-{id}`, `thread-form-{id}`,
  `edit-{ref}`, `rewrite-panel`, `rw-list`, `rw-steer-form`, `rw-steer`, `chat-scroll`, `chat-form`, `walk`.
  The hooks and the walkthrough select by these and by class names (`.mg-block`, `.mg-tick`, `.mg-note-slot`,
  `.mg-read-body`, `.mg-read-rail`, `.mg-map`, `.mg-map-rail`, `.mg-rw`, `.mg-thread-panel`, `.mg-rewrite`,
  `.mg-applied`, `mark[id]`).
* **`phx-update="ignore"`** appears on `#graph-canvas`, `.mg-sum-vault`, `#rw-steer` and every `.mg-mutter` span: the client owns their
  contents and the server's later renders must not touch them. `#rw-steer` is also frozen in its attributes, which is why it never carries `disabled`.
* **`data-confirm="..."`** on an element with `phx-click` means: show `window.confirm(text)` first; push only if accepted.
  Used by `apply_rewrite` and `delete_chat`.
* **`phx-click-away`** on `#linkbox`: when the menu is open, a click outside it pushes `toggle_linking`.
* **Forms**: `phx-submit` sends the form's named fields as event params; `phx-change` on the backend `<form>` (which has no id now)
  fires on every change of the select and sends `provider` (plus `_target`). Submit-button `disabled` states are server-driven.
* **`phx-value-*`** are string-valued; handlers parse integers themselves (`arg_int`).
* **Every `<button>` without `type` inside a `<form>` is a submit button** unless `type="button"` is stated; the markup states it where it matters.
* **Wide vs collapsed layout** is decided by the `MarginNotes` hook, which reads the CSS grid: if
  `getComputedStyle(#read-rail).gridTemplateColumns` has fewer than 3 tracks the notes fall back to flow layout. The
  stylesheet defines the grid on `.mg-read`; `.mg-read.collapsed` is the drawer-open state.

### Walkthrough overlay (`MarginaliaWeb.Walk.overlay`, attrs `steps` required, `auto` nil, `note` default "Nothing here is saved, and no model is called — the answers are fixed examples.")

```heex
<div id="walk" phx-hook=".Walk" data-steps={Jason.encode!(@steps)} data-auto={@auto}>
  <div class="mg-walk-ring" hidden></div>
  <div class="mg-walk-veil" hidden></div>

  <div class="mg-walk-card" hidden>
    <div class="mg-walk-head">
      <span class="mg-label">Walkthrough</span>
      <span class="n"></span>
      <button class="mg-btn sm ghost ml-auto end">end</button>
    </div>
    <h3></h3>
    <p class="body"></p>
    <div class="mg-walk-foot">
      <button class="mg-btn sm ghost back">Back</button>
      <button class="mg-btn sm next">Next</button>
    </div>
    <p class="mg-walk-safe">{@note}</p>
  </div>
</div>
```

On this page it is rendered as `<MarginaliaWeb.Walk.overlay :if={@walk != []} steps={@walk} />`; `steps` is
`Walkthrough.steps(view, mine?: mine?)` (section 7), so `data-steps` is a JSON array of
`{id, title, body, target (CSS selector or null), place, owner?, act}` where `act` is
`{kind: "push", event, params}` or `{kind: "client", name}` (the page never uses `hop`/`click`).

### Source of every component

Below, every component is quoted from the source. Script blocks for colocated hooks are cut out
and replaced by a one-line comment naming the hook; the hooks are in section 4. Elixir function bodies
that are not templates are kept where they compute what the template shows. `~p"/path"` is a verified
route: it renders as the plain path. `url(~p"...")` renders an absolute URL using the endpoint's host.
Component attr declarations (`attr :name, :type, default:`) come first in each block and are the component's inputs.


#### 3.1 `render/1` — header, tabs, page body, drawer

Notes: the backend `<select>` shows only to the deploy owner when `length(@backends) > 1`; its selected option is the one
whose `name` (stringified) equals `@provider` or, when that is nil, the deploy default `LLM.provider_name()`; the grey text
beside it is that backend's `model`. The "Talk about it" button has the `ghost` modifier when the drawer is closed. The
`Copy link` button's `data-url` is the absolute URL `https://{host}/works/{slug}` (no query string).
The `?` button (`.mg-help`) pushes `show_help`, which re-opens the tour card for the current view (it is a no-op
where the view has no tour). `Links.linkable(user_id, work_id)` is evaluated on every render of the header for owners of a read draft.

```heex
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="w-full px-6 py-6">
        <div class="flex items-baseline gap-3 flex-wrap">
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            {@work.title}
          </h1>
          <span class="mg-meta">
            {@work.word_count} words · {length(@sections)} sections · {@counts.beats} beats
          </span>
          <div class="ml-auto flex gap-2 items-baseline flex-wrap">
            <.links_control
              :if={@mine? and @work.status == "read"}
              work={@work}
              links={@links}
              open={@linking?}
              others={Links.linkable(@current_scope.user.id, @work.id)}
            />

            <%= if @mine? and @work.status == "read" and @counts.beats == 0 do %>
              <button class="mg-btn sm" phx-click="start_read">Read again</button>
            <% end %>
          </div>
        </div>

        <%!-- A draft can be related to several others, and a relationship
              that only appears inside a dropdown is one nobody remembers
              they made. --%>
        <div :if={@links != []} class="mg-linkrow">
          <span class="mg-label">read alongside</span>
          <.link :for={l <- @links} navigate={~p"/links/#{l.id}?lead=#{@work.slug}"} class="one">
            <span class="t">{Links.other(l, @work.id).title}</span>
            <span :if={l.status != "linked"} class={["st", l.status]}>{l.status}</span>
          </.link>
        </div>

        <div class="mt-5 flex items-baseline gap-5 flex-wrap border-b border-[var(--mg-rule)] pb-0">
          <div class="mg-tabs">
            <.tab view={@view} this={:read} label="Read" />
            <.tab view={@view} this={:graph} label="Graph" />
            <.tab view={@view} this={:spine} label="Spine" />
            <.tab view={@view} this={:threads} label="Threads" />
            <%!-- only offered once there is something to show --%>
            <.tab :if={@revision_count > 0} view={@view} this={:changes} label="Changes" />
            <%!-- how the thing works, not what it found: mine to look at --%>
            <.tab :if={@owner?} view={@view} this={:trace} label="Trace" />
            <.tab :if={@owner?} view={@view} this={:prompts} label="Prompts" />
          </div>

          <button
            class="mg-help"
            phx-click="show_help"
            title="What is this tab for?"
            aria-label="What is this tab for?"
          >?</button>

          <div class="ml-auto flex items-baseline gap-3 pb-1">
            <%= if @mine? do %>
              <button
                class="mg-btn sm ghost"
                id="share-link"
                phx-hook=".Share"
                data-url={url(~p"/works/#{@work.slug}")}
              >Copy link</button>
            <% else %>
              <span class="mg-badge">reading someone's draft</span>
            <% end %>
            <button
              class={"mg-btn sm" <> if(@chat_open, do: "", else: " ghost")}
              phx-click="toggle_chat"
            >Talk about it</button>
            <%= if @owner? and length(@backends) > 1 do %>
              <form phx-change="set_provider" class="inline-flex items-baseline gap-1.5">
                <span class="mg-label">backend</span>
                <select
                  name="provider"
                  class="text-[0.72rem] bg-transparent border border-[var(--mg-rule)] rounded-sm px-1.5 py-0.5"
                >
                  <%= for b <- @backends do %>
                    <option
                      value={b.name}
                      selected={
                        to_string(b.name) == (@provider || to_string(Marginalia.LLM.provider_name()))
                      }
                    >
                      {b.label}
                    </option>
                  <% end %>
                </select>
                <span class="mg-meta opacity-60">
                  {Enum.find(
                    @backends,
                    &(to_string(&1.name) == (@provider || to_string(Marginalia.LLM.provider_name())))
                  ).model}
                </span>
              </form>
            <% end %>
          </div>
        </div>

        <div
          class={"mt-5 relative " <> if(@chat_open, do: "mg-shifted", else: "")}
          id="page-body"
          phx-hook=".Selection"
        >
          <div id="sel-actions" hidden>
            <button id="sel-discuss" type="button">Discuss this</button>
            <button id="sel-rewrite" type="button">Suggest a rewrite</button>
            <button id="sel-add" type="button">Add to question</button>
          </div>
          <div class="min-w-0">
            <%= case @work.status do %>
              <% "pending" -> %>
                <.confirm_gate
                  sections={@sections}
                  llm_ready={@llm_ready}
                  provider={@provider}
                  mine?={@mine?}
                />
              <% _ -> %>
                <.tour_card :if={@tour} tour={@tour} walk?={Walkthrough.for_view?(@view)} />
                <MarginaliaWeb.Walk.overlay :if={@walk != []} steps={@walk} />

                <%= if @work.status == "reading" do %>
                  <.progress
                    sections={@sections}
                    counts={@counts}
                    stages={@stages}
                    started_at={@started_at}
                  />
                <% end %>
                <.map_view
                  view={@view}
                  work={@work}
                  diff_rows={@diff_rows}
                  diff_stat={@diff_stat}
                  revisions={@revisions}
                  summarising={@summarising}
                  document={@document}
                  doc_running={@doc_running}
                  changes_on={@changes_on}
                  applied={@applied}
                  summary_link={@summary_link}
                  comparing={@comparing}
                  graph_json={@graph_json}
                  graph_stats={@graph_stats}
                  passes={@passes}
                  modes={@modes}
                  graph_building={@graph_building}
                  events={@events}
                  event_stats={@event_stats}
                  page={@page}
                  only={@only}
                  mine?={@mine?}
                  collapsed={@chat_open}
                  block_threads={@block_threads}
                  open_thread={@open_thread}
                  rewrite={@rewrite}
                  rewriting={@rewriting}
                  rewrite_ref={@rewrite_ref}
                  steer={@steer}
                  rewrite_span={@rewrite_span}
                  preview={@preview}
                  editing={@editing}
                  edit_text={@edit_text}
                  thread_history={@thread_history}
                  thread_loading={@thread_loading}
                  mutter={@mutter}
                  sections={@sections}
                  beats={@beats}
                  spine={@spine}
                  threads={@threads}
                  questions={@questions}
                />
            <% end %>
          </div>
        </div>

        <div class={"mg-drawer " <> if(@chat_open, do: "open", else: "")} aria-hidden={not @chat_open}>
          <%= if @chat_open do %>
            <.chat_panel
              history={@history}
              loading={@loading}
              mutter={@mutter}
              status={@work.status}
              llm_ready={@llm_ready}
              provider={@provider}
              mode={@mode}
              modes={@modes}
              focus={@focus}
              quota={@quota}
              mine?={@mine?}
              threads_list={@threads_list}
              conversation={@conversation}
              cited={@cited}
            />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
```

#### 3.2 `tab/1` (attrs: `view` atom, `this` atom, `label` string)

Pushes `set_view` with `view="read"` etc. The active tab has class `mg-tab on`.

```heex
  attr :view, :atom, required: true
  attr :this, :atom, required: true
  attr :label, :string, required: true

  defp tab(assigns) do
    ~H"""
    <button
      class={"mg-tab" <> if(@view == @this, do: " on", else: "")}
      phx-click="set_view"
      phx-value-view={Atom.to_string(@this)}
    >{@label}</button>
    """
  end
```

#### 3.3 `confirm_gate/1` (attrs: `sections` list, `llm_ready` bool, `provider` string|nil, `mine?` bool default true)

Shown instead of the read while `work.status == "pending"`. The Read button is above the section list on purpose.
`start_read` is the only action. If there is no API key or the viewer does not own the draft, a bordered notice replaces
the button (the same notice, "No {provider label} key is configured on this deploy, so the read can't run.", is shown to a
non-owner visitor too). A second Read button appears under the list when there are more than 8 sections.

```heex
  attr :sections, :list, required: true
  attr :llm_ready, :boolean, required: true
  attr :provider, :string, default: nil
  attr :mine?, :boolean, default: true

  defp confirm_gate(assigns) do
    ~H"""
    <div>
      <h2 class="mg-label">Before it reads</h2>
      <p class="mg-prose mt-2.5 max-w-[62ch] text-[0.95rem]">
        This is how the draft has been divided. A machine guessing your section breaks is a
        machine getting everything after that wrong, so have a look before anything is read.
      </p>

      <%!-- The action goes above the list, not below it.
            It was below, and the one draft a stranger left sitting
            unread for two days was the one with the most sections —
            twenty-five rows, which is about eight hundred pixels, which
            put the only button on the page under the fold. The list is
            there to be checked, not read: whoever wants to check it can
            scroll, and whoever does not should not have to. --%>
      <div :if={@llm_ready and @mine?} class="mt-5 flex items-baseline gap-3 flex-wrap">
        <button class="mg-btn" phx-click="start_read">
          Read it — {length(@sections)} sections
        </button>
        <span class="mg-hint mt-0">
          Takes a few minutes. Everything else on the page stays usable while it runs.
        </span>
      </div>

      <div
        :if={not (@llm_ready and @mine?)}
        class="mt-5 text-[0.85rem] border-l-2 border-[var(--mg-accent)] pl-3 py-1.5"
      >
        No {Marginalia.LLM.label(@provider)} key is configured on this deploy, so the read can't run.
      </div>

      <div class="mg-rows mt-5 max-w-[62ch]">
        <%= for s <- @sections do %>
          <div class="mg-row">
            <span class="n">{s.ordinal}</span>
            <span class="flex-1 min-w-0 truncate text-[0.9rem]">{s.title}</span>
            <span class="mg-meta">{s.word_count}w</span>
          </div>
        <% end %>
      </div>

      <%!-- and again at the end, for anyone who did read to the bottom --%>
      <button
        :if={@llm_ready and @mine? and length(@sections) > 8}
        class="mg-btn mt-5"
        phx-click="start_read"
      >
        Read it — {length(@sections)} sections
      </button>
    </div>
    """
  end
```

#### 3.4 `progress/1` and `stage/1`

Shown above the map while `work.status == "reading"`. `progress` attrs: `sections`, `counts`, `stages` (map, default `%{}`),
`started_at` (integer unix seconds or nil). `stage` attrs: `state` atom, `name`, `detail`. A stage's glyph: `:done` "✓", `:failed` "✕",
`:start` a filled accent `span.mg-dot`, anything else "·". `stage_of(stages, key)` is `Map.get(stages, key, :waiting)`.
`status_class/1` (used for the per-section number badges while the first stage runs): `"read"` -> `ink`, `"failed"` -> `accent`, `"reading"` -> `accent`, otherwise empty.
The grid has three columns (`1.4rem 11rem 1fr`) and each `<.stage>` emits three sibling `<span>`s into it.

```heex
  attr :sections, :list, required: true
  attr :counts, :map, required: true
  attr :stages, :map, default: %{}
  attr :started_at, :integer, default: nil

  # A read is three different jobs that take about a minute each, and the last
  # of them produces nothing visible until it is finished. A row of badges
  # left the writer watching a still page for the final minute with no way to
  # tell working from hung. So: name the three, say which one is running, and
  # show what each has actually found.
  defp progress(assigns) do
    ~H"""
    <div class="border-b border-[var(--mg-rule)] pb-6 mb-7">
      <div class="flex items-baseline gap-3">
        <h2 class="mg-label">Reading your draft</h2>
        <span
          :if={@started_at}
          id="read-clock"
          phx-hook=".Clock"
          data-since={@started_at}
          class="mg-meta"
        >0:00</span>
        <span class="mg-hint mt-0 ml-auto">Everything else on the page stays usable.</span>
      </div>

      <div class="mt-4 grid gap-y-3 max-w-[58ch]" style="grid-template-columns:1.4rem 11rem 1fr">
        <.stage
          state={stage_of(@stages, :sections)}
          name="Sections"
          detail={
            "#{Enum.count(@sections, &(&1.status == "read"))} of #{length(@sections)} read" <>
              if(@counts.beats > 0, do: " · #{@counts.beats} beats", else: "")
          }
        />
        <.stage
          state={stage_of(@stages, :spine)}
          name="The spine"
          detail={
            if @counts.spine > 0 do
              "#{@counts.spine} spine · #{@counts.threads} threads · #{@counts.questions} questions"
            else
              "what the whole draft hangs off"
            end
          }
        />
        <.stage
          state={stage_of(@stages, :weave)}
          name="Connections"
          detail="what develops, pays off, requires, or contradicts what"
        />
      </div>

      <div :if={stage_of(@stages, :sections) == :start} class="mt-5 flex flex-wrap gap-1.5">
        <span :for={s <- @sections} class={"mg-badge " <> status_class(s.status)}>
          {s.ordinal}
        </span>
      </div>

      <%!-- hook script .Clock omitted here; see section 4 --%>
    </div>
    """
  end
```

```heex
  attr :state, :atom, required: true
  attr :name, :string, required: true
  attr :detail, :string, required: true

  defp stage(assigns) do
    ~H"""
    <span class={[
      "text-[0.8rem] leading-6",
      @state == :done && "text-[var(--mg-accent)]",
      @state == :start && "text-[var(--mg-ink)]",
      @state == :waiting && "text-[var(--mg-dim)] opacity-40"
    ]}>
      <%= case @state do %>
        <% :done -> %>
          ✓
        <% :failed -> %>
          ✕
        <% :start -> %>
          <span class="mg-dot inline-block" style="background:var(--mg-accent)"></span>
        <% _ -> %>
          ·
      <% end %>
    </span>
    <span class={[
      "text-[0.8rem] leading-6",
      @state == :waiting && "text-[var(--mg-dim)] opacity-50",
      @state == :start && "font-semibold"
    ]}>{@name}</span>
    <span class={[
      "text-[0.8rem] leading-6 text-[var(--mg-dim)]",
      @state == :waiting && "opacity-50"
    ]}>{@detail}</span>
    """
  end
```

Elixir helpers producing copy and state used by these and the rest:

```elixir
  defp grounding_note(%{beats: []}), do: nil

  defp grounding_note(%{beats: beats}) do
    "It runs through " <>
      Enum.map_join(beats, "; ", fn b ->
        "section #{b.section && b.section.ordinal}: #{b.title}"
      end) <> "."
  end

  defp supersede_note(1), do: "One note was about the line you changed. It is greyed, not gone."

  defp supersede_note(n),
    do: "#{n} notes were about lines you changed. They are greyed, not gone."

  defp block_source(page, ref) do
    case block_and_section(page, ref) do
      %{block: block} -> block
      _ -> ""
    end
  end

  defp block_and_section(page, ref) do
    Enum.find_value(page || [], fn sec ->
      Enum.find_value(sec.blocks, fn b ->
        b.ref == ref && %{block: b.text, section: sec.section}
      end)
    end)
  end

  # the candidate, dropped into the paragraph where the original sat, so the
  # writer edits their own line rather than staring at a replacement
  # `:not_here` rather than a guess. This used to fall through to `seed`,
  # which replaced the WHOLE paragraph with a rewrite of text that was not in
  # it — the panel anchored to a paragraph the span did not cover, and one
  # click silently overwrote it. A rewrite that cannot be placed is a refusal,
  # not a substitution.
  defp seeded(block, assigns, seed) do
    case assigns.rewrite do
      %{original: original} -> Marginalia.Rewrite.place(block, original, seed)
      _ -> {:ok, seed}
    end
  end

  defp rewrite_error(:not_in_draft),
    do: "That selection is not in the draft, character for character."

  defp rewrite_error({:span_too_long, words, max}),
    do:
      "That is #{words} words. Rewrites go up to #{max} — past that, split it and take " <>
        "the part you actually want reworked."

  defp rewrite_error(:no_candidates),
    do: "Nothing came back that was different from what you wrote."

  defp rewrite_error(other), do: "That did not go through: #{inspect(other)}"

  defp stage_of(stages, key), do: Map.get(stages || %{}, key, :waiting)

  defp arg_int(n) when is_integer(n), do: n

  defp arg_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp arg_int(_), do: nil

  # A reload mid-read gets no broadcasts for the stages that already finished,
  # so the state is read back off what is in the database instead of resetting
  # the writer's view to "nothing has happened yet".
  defp infer_stages(work) do
    counts = Works.counts(work.id)
    sections = Works.list_sections(work.id)
    all_read? = sections != [] and Enum.all?(sections, &(&1.status in ["read", "failed"]))

    cond do
      work.status == "read" ->
        %{sections: :done, spine: :done, weave: :done}

      work.status != "reading" ->
        %{sections: :waiting, spine: :waiting, weave: :waiting}

      counts.spine > 0 ->
        %{sections: :done, spine: :done, weave: :start}

      all_read? ->
        %{sections: :done, spine: :start, weave: :waiting}

      true ->
        %{sections: :start, spine: :waiting, weave: :waiting}
    end
  end

  defp status_class("read"), do: "ink"
  defp status_class("failed"), do: "accent"
  defp status_class("reading"), do: "accent"
  defp status_class(_), do: ""
```

#### 3.5 `map_view/1` — the tab dispatcher (spine and threads are inlined here)

Input attrs are the long list below (every assign a tab might need; a missing one is a render error that drops the socket in
LiveView, so the rewrite should treat the list as the full input of this view). The body switches on `@view`:
`:spine`, `:changes`, `:graph`, `:read`, `:trace`, `:prompts`, `:threads`. Nodes are numbered `01`, `02`... in the spine
(`String.pad_leading(to_string(i), 2, "0")`, 1-based).

```heex
  attr :view, :atom, required: true
  attr :work, :map, required: true
  attr :graph_json, :string, default: nil
  attr :graph_stats, :map, default: nil
  attr :passes, :list, default: []
  attr :modes, :list, default: []
  attr :graph_building, :boolean, default: false
  attr :events, :list, default: []
  attr :event_stats, :map, default: nil
  attr :page, :list, default: nil
  attr :only, :string, default: nil
  attr :mine?, :boolean, default: true
  attr :collapsed, :boolean, default: false
  attr :block_threads, :map, default: %{}
  attr :open_thread, :map, default: nil
  attr :thread_history, :list, default: []
  attr :thread_loading, :boolean, default: false
  attr :mutter, :list, default: []
  attr :rewrite, :map, default: nil
  attr :rewriting, :boolean, default: false
  attr :rewrite_ref, :string, default: nil
  attr :steer, :string, default: nil
  attr :rewrite_span, :string, default: nil
  attr :preview, :map, default: nil
  attr :editing, :string, default: nil
  attr :edit_text, :string, default: nil
  attr :sections, :list, required: true
  attr :beats, :list, required: true
  attr :spine, :list, required: true
  attr :threads, :list, required: true
  attr :questions, :list, required: true
  attr :diff_rows, :list, default: []
  attr :diff_stat, :map, default: nil
  attr :revisions, :list, default: []
  attr :summarising, :any, default: nil
  attr :document, :any, default: nil
  attr :doc_running, :boolean, default: false
  attr :changes_on, :boolean, default: false
  attr :applied, :any, default: nil
  # Declared here *and* passed at every call site between the render and the
  # button. An assign used inside a function component and missing from its
  # attrs is a KeyError during render, which LiveView turns into a dropped
  # socket rather than an error — the failure that has cost the most time in
  # this file, and this feature reproduced it twice.
  attr :summary_link, :any, default: nil
  attr :comparing, :any, default: nil

  defp map_view(assigns) do
    ~H"""
    <div>
      <%= case @view do %>
        <% :spine -> %>
          <%= if @work.first_impression do %>
            <h2 class="mg-label">First impression</h2>
            <p class="mg-prose mt-2.5 max-w-[78ch]">{@work.first_impression}</p>
          <% end %>

          <p
            :if={@work.status_detail}
            class="mt-3 text-[0.8rem] border-l-2 border-[var(--mg-accent)] pl-2.5 py-1 text-[var(--mg-dim)]"
          >
            {@work.status_detail}
          </p>

          <h2 class={"mg-label" <> if(@work.first_impression, do: " mt-12", else: "")}>The spine</h2>
          <p class="mg-hint">The chain the whole draft hangs off, in order.</p>
          <%= if @spine == [] do %>
            <p class="mg-empty mt-4">No spine was produced for this draft.</p>
          <% else %>
            <div class="mg-cards mt-5">
              <.grounded_node
                :for={{n, i} <- Enum.with_index(@spine, 1)}
                node={n}
                work={@work}
                mine?={@mine?}
                n={String.pad_leading(to_string(i), 2, "0")}
              />
            </div>
          <% end %>

          <%= if @questions != [] do %>
            <h2 class="mg-label mt-12">Questions this raised</h2>
            <p class="mg-hint">
              Each names something specific in the draft. In the page view they are attached
              to the paragraphs they are about.
            </p>
            <div class="mg-cards mt-4">
              <.grounded_node :for={q <- @questions} node={q} work={@work} mine?={@mine?} />
            </div>
          <% end %>
        <% :changes -> %>
          <.changes_pane
            rows={@diff_rows}
            stat={@diff_stat}
            revisions={@revisions}
            work={@work}
          />
        <% :graph -> %>
          <.graph_pane
            work={@work}
            graph_json={@graph_json}
            stats={@graph_stats}
            building={@graph_building}
            mine?={@mine?}
          />
        <% :read -> %>
          <.read_pane
            page={@page}
            slug={@work.slug}
            changes_on={@changes_on}
            revisions={@revisions}
            applied={@applied}
            summary_link={@summary_link}
            comparing={@comparing}
            summarising={@summarising}
            document={@document}
            doc_running={@doc_running}
            words={@work.word_count}
            only={@only}
            collapsed={@collapsed}
            block_threads={@block_threads}
            open_thread={@open_thread}
            thread_history={@thread_history}
            thread_loading={@thread_loading}
            mutter={@mutter}
            mine?={@mine?}
            modes={@modes}
            rewrite={@rewrite}
            rewriting={@rewriting}
            rewrite_ref={@rewrite_ref}
            steer={@steer}
            rewrite_span={@rewrite_span}
            preview={@preview}
            editing={@editing}
            edit_text={@edit_text}
          />
        <% :trace -> %>
          <.trace_pane work={@work} events={@events} stats={@event_stats} building={@graph_building} />
        <% :prompts -> %>
          <.prompts_pane passes={@passes} modes={@modes} />
        <% :threads -> %>
          <h2 class="mg-label">Threads</h2>
          <p class="mg-hint">Patterns that run across sections rather than happening in one.</p>
          <%= if @threads == [] do %>
            <p class="mg-empty mt-4">No threads were identified.</p>
          <% else %>
            <div class="mg-cards mt-5">
              <.grounded_node :for={t <- @threads} node={t} work={@work} mine?={@mine?} />
            </div>
          <% end %>
      <% end %>
    </div>
    """
  end
```

#### 3.6 `grounded_node/1` (spine nodes, threads, questions)

Attrs: `node`, `work`, `mine?` default true, `n` string|nil. It calls `Reading.grounding(work, node.id)` itself (one query set per node).
The Discuss button is for the draft's owner only and pushes `discuss_node` with the node id.

```heex
  attr :node, :map, required: true
  attr :work, :map, required: true
  attr :mine?, :boolean, default: true
  attr :n, :string, default: nil

  # A spine node, thread or question with what it is grounded in underneath:
  # the beats that realise it and the sections they sit in. Clicking it takes
  # the whole lot into the chat, so the writer never has to re-explain which
  # thread they meant or go and find where it happens.
  defp grounded_node(assigns) do
    assigns =
      assign(assigns, :grounding, Marginalia.Reading.grounding(assigns.work, assigns.node.id))

    ~H"""
    <div class="mg-grounded">
      <div class="flex items-start gap-3">
        <div class="min-w-0 flex-1">
          <div style="font-family:var(--mg-serif)" class="text-[1.04rem] leading-snug">
            <span :if={@n} class="mg-meta mr-1.5">{@n}</span>{@node.title}
          </div>
          <div :if={@node.body} class="text-[0.8rem] text-[var(--mg-dim)] mt-1 leading-relaxed">
            {@node.body}
          </div>
        </div>

        <button
          :if={@mine?}
          class="mg-btn sm ghost shrink-0"
          phx-click="discuss_node"
          phx-value-id={@node.id}
          title="Open the chat holding this and everywhere it happens"
        >Discuss</button>
      </div>

      <%= if @grounding.beats == [] do %>
        <div class="mg-meta mt-2 opacity-60">not yet linked to anywhere in the draft</div>
      <% else %>
        <div class="mg-where">
          <span class="mg-label">where it happens</span>
          <div :for={b <- @grounding.beats} class="hit">
            <span class="n">{b.section && b.section.ordinal}</span>
            <span class="min-w-0">
              <span class="t">{b.title}</span>
              <span :if={b.quote} class="q">"{Marginalia.Reading.plain(b.quote)}"</span>
            </span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
```

#### 3.7 `tour_card/1` (attrs: `tour` map, `walk?` bool)

`walk?` is `Walkthrough.for_view?(view)` (true only for `:read`, the one view with steps). "Got it" pushes `dismiss_tour`; "Show me" pushes `start_walk`.

```heex
  attr :tour, :map, required: true
  attr :walk?, :boolean, default: false

  # One card, shown the first time a tab is opened. Every point here exists
  # because the affordance it names is invisible until someone says it: a
  # hairline in the gutter, a highlight you can hover, a filter that changes
  # what the margin is about.
  defp tour_card(assigns) do
    ~H"""
    <div class="mg-tour">
      <div class="flex items-baseline gap-3">
        <h2 style="font-family:var(--mg-serif)" class="text-[1.15rem] font-semibold">
          {@tour.title}
        </h2>
        <button class="mg-btn sm ghost ml-auto" phx-click="dismiss_tour">Got it</button>
      </div>

      <ul class="mg-tour-points">
        <li :for={point <- @tour.points}>{point}</li>
      </ul>

      <%!-- Offered rather than started. Almost everything here is invisible
            until it fires, so being shown beats being told — but firing nine
            controls at somebody who has just handed over a manuscript,
            without asking, is not a demo, it is a fright. --%>
      <div :if={@walk?} class="mg-tour-foot">
        <button class="mg-btn sm" phx-click="start_walk">Show me</button>
        <span class="mg-hint mt-0">
          Works the controls for you. Nothing is saved and the model is never called.
        </span>
      </div>

      <p class="mg-hint mt-2.5">The <strong>?</strong> beside the tabs brings this back.</p>
    </div>
    """
  end
```

#### 3.8 `graph_pane/1` (Graph tab)

Attrs: `work`, `graph_json` string|nil, `stats` map|nil, `building` bool, `mine?` bool. The `<div id="graph-canvas">` carries the entire
export JSON (section 7 gives its structure) in `data-graph`; the `LaneTree` hook draws the SVG and fills `#graph-detail`.
Neither is rendered until `graph_json` is non-nil, i.e. until the tab has loaded. `graph.json`/`graph.dot` are plain download links.

```heex
  attr :work, :map, required: true
  attr :graph_json, :string, default: nil
  attr :stats, :map, default: nil
  attr :building, :boolean, default: false
  attr :mine?, :boolean, default: true

  defp graph_pane(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline gap-3 flex-wrap">
        <h2 class="mg-label">Knowledge graph</h2>
        <%= if @stats do %>
          <span class="mg-meta">
            {@stats.nodes} nodes · {@stats.edges} edges · {@stats.anchored} anchored
          </span>
        <% end %>
        <div class="ml-auto flex gap-2 items-baseline">
          <%= cond do %>
            <% @building -> %>
              <span class="text-[0.75rem] italic text-[var(--mg-dim)]">building the decision graph…</span>
            <% @mine? -> %>
              <button class="mg-btn sm" phx-click="build_graph">Build decision graph</button>
            <% true -> %>
              <span></span>
          <% end %>
          <a href={~p"/works/#{@work.slug}/graph.json"} class="mg-btn sm ghost">graph.json</a>
          <a href={~p"/works/#{@work.slug}/graph.dot"} class="mg-btn sm ghost">graph.dot</a>
        </div>
      </div>

      <div class="mt-2.5 flex items-baseline gap-4 flex-wrap">
        <div class="mg-legend">
          <span><i style="background:#8a3324"></i>goal</span>
          <span><i style="background:#b45309"></i>option</span>
          <span><i style="background:#1e3a8a"></i>decision</span>
          <span><i style="background:#166534"></i>action</span>
          <span><i style="background:#0891b2"></i>outcome</span>
          <span><i style="background:#6b665e"></i>observation</span>
          <span><i style="background:#7c2d92"></i>revisit</span>
        </div>
        <span class="mg-hint mt-0">solid = leads to · dotted = develops / pays off / requires / tension</span>
      </div>

      <%= if @graph_json do %>
        <div class="mg-card mg-graph mt-3.5" style="height:calc(100vh - 17rem); min-height:26rem">
          <div
            id="graph-canvas"
            phx-hook=".LaneTree"
            phx-update="ignore"
            data-graph={@graph_json}
            class="mg-graph-canvas"
          >
            <svg id="graph-svg"></svg>
          </div>
          <div class="mg-graph-detail" id="graph-detail">
            <p class="mg-empty">Pick a node to see what it says and why it is there.</p>
          </div>
        </div>
      <% end %>

      <%!-- hook script .LaneTree omitted here; see section 4 --%>
    </div>
    """
  end
```

#### 3.9 `changes_pane/1` and `diff_table/1` (Changes tab, and reused elsewhere)

`changes_pane` attrs: `rows`, `stat` (map|nil), `revisions`, `work` (plus unused leftovers `rewrite`, `working`, `block_ref`, `steer`, `span`).
`diff_table` attrs: `rows` required, `left` (default "Before"), `right` (default "After"), `compact` bool (adds class `compact`).
The row kinds and column CSS: a `:same` row prints the same text in both columns; `:change` prints the word diff twice, once per column,
with the counterpart's marks hidden (`word_class(op, side)`: `:same` -> `w`; `:del` -> `w del` on the old side and `w hide` on the new;
`:ins` -> `w hide` on the old and `w ins` on the new); `:del` prints the old text with an empty new cell; `:ins` the reverse.
`row_kind` gives the row's extra class: `same`, `change`, `del`, `ins`.

```heex
  attr :rewrite, :map, default: nil
  attr :working, :boolean, default: false
  attr :mutter, :list, default: []
  attr :block_ref, :string, default: nil
  attr :steer, :string, default: nil
  attr :span, :string, default: nil

  attr :rows, :list, required: true
  attr :stat, :map, default: nil
  attr :revisions, :list, default: []
  attr :work, :map, required: true

  @doc false
  # The draft as it arrived beside the draft as it is. Two columns rather
  # than one marked-up copy, because a writer comparing versions is asking
  # "what did I have before", and an inline diff answers a different question.
  def changes_pane(assigns) do
    ~H"""
    <div class="mg-diff">
      <div class="mg-diff-head">
        <span class="mg-label">Changes since it arrived</span>
        <span :if={@stat} class="mg-meta ml-auto">
          {@stat.changed} edited · {@stat.added} added · {@stat.removed} removed
        </span>
      </div>

      <p :if={not Marginalia.Diff.any?(@rows)} class="mg-empty">
        Nothing has changed yet. Edits and applied rewrites show up here.
      </p>

      <.diff_table :if={Marginalia.Diff.any?(@rows)} rows={@rows} left="As it arrived" right="Now" />

      <div :if={@revisions != []} class="mg-diff-log">
        <div class="mg-label">Every change, newest first</div>
        <ol class="mg-rows">
          <li :for={rev <- @revisions}>
            <span class="n">{rev.seq}</span>
            <span class="mg-meta">
              {rev.origin}{if rev.note, do: " — #{rev.note}"} · section {rev.section_ordinal}
            </span>
            <div class="mg-diff-patch">
              <span
                :for={{op, t} <- Marginalia.Diff.words(rev.before, rev.after)}
                class={word_class(op, :new)}
              >{t}</span>
            </div>
          </li>
        </ol>
      </div>
    </div>
    """
  end

  attr :rows, :list, required: true
  attr :left, :string, default: "Before"
  attr :right, :string, default: "After"
  attr :compact, :boolean, default: false

  @doc false
  # Two columns, GitHub's split view: what was there on the left with the
  # removed words struck through in red, what is there now on the right with
  # the added words in green. The counterpart's marks are hidden in each
  # column — showing both in both is how a unified diff reads, and this is
  # not one.
  def diff_table(assigns) do
    ~H"""
    <div class={"mg-diff-cols" <> if(@compact, do: " compact", else: "")}>
      <div class="mg-diff-colhead"><span>{@left}</span><span>{@right}</span></div>

      <div :for={row <- @rows} class={"mg-diff-row " <> row_kind(row)}>
        <%= case row do %>
          <% {:same, l, _} -> %>
            <div class="side old">{l}</div>
            <div class="side new">{l}</div>
          <% {:change, l, r} -> %>
            <div class="side old">
              <span :for={{op, t} <- Marginalia.Diff.words(l, r)} class={word_class(op, :old)}>{t}</span>
            </div>
            <div class="side new">
              <span :for={{op, t} <- Marginalia.Diff.words(l, r)} class={word_class(op, :new)}>{t}</span>
            </div>
          <% {:del, l} -> %>
            <div class="side old gone">{l}</div>
            <div class="side new empty"></div>
          <% {:ins, r} -> %>
            <div class="side old empty"></div>
            <div class="side new fresh">{r}</div>
        <% end %>
      </div>
    </div>
    """
  end
```

Their helpers:

```elixir
  # The block that now holds what was written. A replacement collapsing three
  # paragraphs into one means the ref that was anchored no longer names the
  # same text, so the text is what identifies it.
  defp landed?(nil, _block), do: false

  defp landed?(%{after: written}, %{text: text}) when is_binary(written) and written != "" do
    String.contains?(text, String.slice(written, 0, 80))
  end

  defp landed?(_applied, _block), do: false

  # While the candidates are still coming back there is no located span yet,
  # so the anchor block is all there is to go on. Once they arrive, `covers`
  # names every paragraph the span touches.
  defp rewriting?(%{covers: covers}, _anchor, ref) when is_list(covers) and covers != [],
    do: ref in covers

  defp rewriting?(_rewrite, anchor, ref), do: anchor == ref

  defp row_kind({:same, _, _}), do: "same"
  defp row_kind({:change, _, _}), do: "change"
  defp row_kind({:del, _}), do: "del"
  defp row_kind({:ins, _}), do: "ins"

  # The old column shows what was removed and hides what replaced it; the new
  # column does the reverse. Showing both marks in both columns is how an
  # inline diff reads, and this is not one.
  defp word_class(:same, _), do: "w"
  defp word_class(:del, :old), do: "w del"
  defp word_class(:del, :new), do: "w hide"
  defp word_class(:ins, :old), do: "w hide"
  defp word_class(:ins, :new), do: "w ins"
```

#### 3.10 `rewrite_panel/1` (rewrite candidates, rendered inside the read pane under the anchor block)

Attrs: `rewrite` map|nil, `working` bool, `mutter` list (default `[]`), `block_ref`, `steer`, `span`. While `working`, the body shows `<.mutter lines={@mutter} label="reading it" />` (3.20). Rendered by `read_pane` as
`<.rewrite_panel :if={(@rewriting or @rewrite) && @rewrite_ref == b.ref} rewrite={@rewrite} working={@rewriting} block_ref={b.ref} steer={@steer} span={@rewrite_span} />`
immediately after the block (and its inline notes), so it sits directly under the paragraph where the selection ended.
Each candidate is a `<button class="mg-rw">` containing two nested clickable spans (a click on the `replace` span pushes
`apply_rewrite`, guarded by `data-confirm`; a click on the `or edit it first` span pushes `edit_block`). The `.Hover`
hook sits on the list `#rw-list`.

```heex
  # Candidates for one selected line, side by side with what is there now.
  # Three labelled options rather than one suggestion: a single rewrite reads
  # as the answer, and the point is that the writer chooses.
  defp rewrite_panel(assigns) do
    ~H"""
    <div class={"mg-rewrite" <> if(@working, do: " working", else: "")} id="rewrite-panel">
      <%!-- It said "one line" regardless. A span can now be 2,500 words, the
            panel renders under the FIRST block of a multi-paragraph selection,
            and a writer looking at it had nothing on screen telling them how
            much was about to be replaced. --%>
      <div class="mg-rewrite-head">
        <span class="mg-label">{Marginalia.Rewrite.span_label(@span)}</span>
        <button class="mg-btn sm ghost ml-auto" phx-click="close_rewrite">close</button>
      </div>

      <p :if={Marginalia.Rewrite.span_extent(@span)} class="mg-rw-extent">
        {Marginalia.Rewrite.span_extent(@span)}
      </p>

      <%!-- Optional, and after the fact: the first three come back off one
            click, and this is for when none of them is what was wanted. --%>
      <%!-- A textarea that grows, not a one-line input. What people write
            here is a sentence or three — "lead with the finding, keep the
            scale point, do not add claims that are not already there" — and
            a single line shows the tail of that and hides the rest, so you
            cannot read back what you asked for before asking for it.

            The id is not decoration. Without one, LiveView matches this
            node by position when it patches, and the panel above it changes
            shape every time an answer lands.

            `phx-update="ignore"` keeps what is half-typed through those
            patches, and it freezes every attribute on the node, not only
            the value — which is why `disabled` is not on the textarea. It
            was, for about ten minutes, and the box rendered disabled on
            first paint and stayed that way for good. Nothing needs it:
            typing while a rewrite runs is harmless and `steer_rewrite`
            already ignores a submit that arrives mid-pass. --%>
      <form id="rw-steer-form" class="mg-rw-steer" phx-submit="steer_rewrite">
        <textarea
          id="rw-steer"
          name="steer"
          rows="1"
          maxlength="400"
          phx-hook=".Steer"
          phx-update="ignore"
          placeholder="ask for something specific — shorter, lead with the finding, drop the hedging"
        >{@steer}</textarea>
        <button type="submit" class="mg-btn sm" disabled={@working}>Again</button>
      </form>

      <%!-- an empty box that fills in, rather than a spinner standing where
            the answer will be: the shape of the thing arrives first --%>
      <div :if={@working} class="mg-rewrite-body">
        <.mutter lines={@mutter} label="reading it" />
      </div>

      <div :if={@rewrite} class="mg-rewrite-body">
        <p :if={@rewrite.reading} class="mg-hint mt-0 mb-2.5">{@rewrite.reading}</p>

        <%!-- A span crossing paragraphs has no one paragraph to be dropped
              into, and the editor writes one paragraph at a time. Saying so
              is better than an action that silently overwrites the wrong one. --%>
        <p :if={@rewrite.spans_blocks} class="mg-hint mt-0 mb-2.5">
          This covers more than one paragraph. Replacing works on the whole passage;
          editing one first needs a selection inside a single paragraph.
        </p>

        <%!-- LiveView has no phx-mouseover: hovering is not one of its
              bindings, so the preview never fired and the legend in the hint
              below was the only ins/del on the page. A hook does it. --%>
        <div class="mg-rw-list" id="rw-list" phx-hook=".Hover">
          <button
            :for={{c, i} <- Enum.with_index(@rewrite.candidates)}
            class="mg-rw"
            style={"--i:#{i}"}
            data-i={i}
          >
            <span class="head">
              <span class="move">{c.move}</span>
              <span :if={c.cost} class="cost">{c.cost}</span>
            </span>
            <span class="words">{c.text}</span>
            <span
              class="mine apply"
              phx-click="apply_rewrite"
              phx-value-i={i}
              data-confirm="Replace the selected passage with this version? It goes in the Changes tab and the draft's git history, so it can be got back."
            >replace the passage with this →</span>

            <span
              :if={not @rewrite.spans_blocks}
              class="mine"
              phx-click="edit_block"
              phx-value-ref={@block_ref}
              phx-value-seed={c.text}
            >or edit it first →</span>
          </button>
        </div>

        <%!-- hook script .Hover omitted here; see section 4 --%>

        <p class="mg-hint mt-2.5">
          The line above is dimmed because these would replace it. Hover one and it shows there
          instead — <ins class="mg-swap">what arrives</ins>
          against <del class="mg-cut">what goes</del>. Nothing is applied.
        </p>
      </div>
    </div>
    """
  end
```

#### 3.11 `inline_thread/1` (one pinned conversation, under its paragraph)

Attrs: `thread` (Conversation: `id`, `anchor_kind` "block"|"span", `quote`, `resolved_at`, `block_ref`, `mode`), `history`, `loading`, `mine?`, `modes` (unused), `mutter` list (default `[]`). While `loading`, the body ends with `<.mutter :if={@loading} lines={@mutter} class="py-0.5" />` (3.20).
Assistant messages are rendered through `Markdown.to_html` (hard breaks) and inserted raw; user messages as escaped text.

```heex
  attr :thread, :map, required: true
  attr :history, :list, default: []
  attr :loading, :boolean, default: false
  attr :mutter, :list, default: []
  attr :mine?, :boolean, default: true
  attr :modes, :list, default: []

  # One conversation, about one paragraph, opened where that paragraph is.
  # Deliberately not the drawer: the drawer is for the draft, and this is for
  # the sentence in front of you. Keeping them apart is what lets a thread
  # still be here next week when you come back to the same paragraph.
  defp inline_thread(assigns) do
    ~H"""
    <div class="mg-thread-panel" id={"thread-#{@thread.id}"}>
      <div class="mg-thread-head">
        <span class="mg-label">
          {if @thread.anchor_kind == "span", do: "on this passage", else: "on this paragraph"}
        </span>
        <span :if={@thread.resolved_at} class="mg-badge">settled</span>

        <div class="ml-auto flex items-baseline gap-2">
          <button
            :if={@mine? and @history != []}
            class="mg-btn sm ghost"
            phx-click="resolve_thread"
          >{if @thread.resolved_at, do: "reopen", else: "settle"}</button>
          <button class="mg-btn sm ghost" phx-click="close_thread">close</button>
        </div>
      </div>

      <div class="mg-thread-body" id={"thread-body-#{@thread.id}"} phx-hook=".StickToBottom">
        <blockquote :if={@thread.quote} class="mg-thread-quote">"{@thread.quote}"</blockquote>

        <p :if={@history == []} class="text-[0.78rem] text-[var(--mg-dim)] leading-relaxed">
          Ask about this one. What is it doing, what is it not doing, what would have to
          change. It will quote the draft back rather than rewrite it.
        </p>

        <%= for m <- @history do %>
          <%= if m["role"] == "user" do %>
            <div class="mg-thread-turn mine">
              <span class="who">you</span>
              <div class="said">{m["content"]}</div>
            </div>
          <% else %>
            <div class="mg-thread-turn theirs">
              <span class="who">the reader</span>
              <div class="said md">{Marginalia.Markdown.to_html(m["content"])}</div>
            </div>
          <% end %>
        <% end %>

        <.mutter :if={@loading} lines={@mutter} class="py-0.5" />
      </div>

      <div :if={@mine?} class="mg-thread-foot">
        <form phx-submit="thread_send" id={"thread-form-#{@thread.id}"} phx-hook=".Composer">
          <textarea
            name="message"
            rows="2"
            autocomplete="off"
            placeholder="What about this paragraph?"
            class="w-full text-[0.8rem] leading-relaxed resize-none min-h-[3.2rem] max-h-56 px-2.5 py-2 bg-[var(--mg-paper)] border border-[var(--mg-rule)] rounded-sm focus:outline-none focus:border-[var(--mg-accent)]"
            disabled={@loading}
          ></textarea>
          <div class="flex items-center gap-2 mt-1.5">
            <span class="mg-hint mt-0">Enter to send</span>
            <button type="submit" class="mg-btn sm ml-auto" disabled={@loading}>
              {if @loading, do: "…", else: "Ask"}
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
```

#### 3.12 `links_control/1` (header, owner of a read draft)

Attrs: `work`, `links`, `open`, `others`. "link to" rows push `link_to` with the other work's numeric id.

```heex
  attr :work, :map, required: true
  attr :links, :list, default: []
  attr :open, :boolean, default: false
  attr :others, :list, default: []

  # Linking this draft to another, and the ones already related to it.
  #
  # Only drafts that have been read are offered: the pass relates two
  # graphs, and an unread draft has no graph to relate.
  defp links_control(assigns) do
    ~H"""
    <div class="mg-linkbox" id="linkbox" phx-click-away={@open && JS.push("toggle_linking")}>
      <button class="mg-btn sm ghost" phx-click="toggle_linking">
        Link{if @links != [], do: " · #{length(@links)}"}
      </button>

      <div :if={@open} class="mg-linkmenu">
        <%= if @links != [] do %>
          <span class="mg-label">already linked</span>
          <.link :for={l <- @links} navigate={~p"/links/#{l.id}?lead=#{@work.slug}"} class="row">
            <span class="t">{Links.other(l, @work.id).title}</span>
            <span class={"st " <> l.status}>{l.status}</span>
          </.link>
        <% end %>

        <span class="mg-label">link to</span>
        <%= if @others == [] do %>
          <p class="none">
            Nothing to link to yet. A second draft has to have been read before the two
            can be related — linking works on the maps, not the text.
          </p>
        <% else %>
          <button :for={o <- @others} class="row" phx-click="link_to" phx-value-id={o.id}>
            <span class="t">{o.title}</span>
            <span class="n">{o.word_count}w</span>
          </button>
        <% end %>
      </div>
    </div>
    """
  end
```

#### 3.13 `minimap/1` (the contents rail down the left of the read view)

Attrs: `entries` (from `Reading.outline`), `words`. Pre-render computation (verbatim below): `total` = sum of entry words (min 1); each entry's
`grow` = `max(words or 0, max(div(total, 40), 1))`; the headline word count is the work's own `word_count` when given. Rendered only when there is more than one entry.
The `<i class="t l{level}" style="flex-grow:{grow}">` ticks in the collapsed rail and the `<li style="flex-grow:{grow}">` rows
in the panel are what make it a to-scale map.

```heex
  attr :entries, :list, default: []
  attr :words, :integer, default: nil

  # A map of the draft, parked in the corner. The point of a map is that
  # distance on it means distance in the thing it describes, so every row is
  # sized by its word count: a 1,600-word section gets five times the block a
  # 320-word one does. Collapsed that is a silhouette you can read the shape
  # of the draft off; open it is the same shape, labelled, and you can jump
  # from it. Reading a long draft a paragraph at a time makes it very easy to
  # lose the whole, and scrolling for a section you half remember is the tax
  # on that.
  defp minimap(assigns) do
    entries = assigns.entries
    total = entries |> Enum.map(&(&1.words || 0)) |> Enum.sum() |> max(1)

    # a sub-heading carries no word count of its own, and a very short
    # section would collapse to an unclickable hairline, so every row is
    # floored at roughly a fortieth of the draft
    floor = max(div(total, 40), 1)
    entries = Enum.map(entries, &Map.put(&1, :grow, max(&1.words || 0, floor)))

    # proportions come from the section sums, but the headline number is the
    # work's own: two different word counts on one screen reads as a bug
    assigns = assign(assigns, entries: entries, total: assigns.words || total)

    ~H"""
    <nav :if={length(@entries) > 1} class="mg-map" id="minimap" phx-hook=".Minimap">
      <button class="mg-map-rail" aria-label="Contents" aria-expanded="false">
        <i :for={e <- @entries} class={"t l#{e.level}"} style={"flex-grow:#{e.grow}"}></i>
      </button>

      <div class="mg-map-panel">
        <div class="mg-map-head">
          <span>contents</span>
          <span class="n">{@total} words</span>
        </div>

        <ol class="mg-map-body">
          <li :for={e <- @entries} style={"flex-grow:#{e.grow}"} data-full={e.title}>
            <a href={"##{e.id}"} class={"l#{e.level}"} data-target={e.id}>
              <span class="t">{e.title}</span>
              <span :if={e.words} class="w">{e.words}w</span>
            </a>
          </li>
        </ol>
      </div>

      <%!-- hook script .Minimap omitted here; see section 4 --%>
    </nav>
    """
  end
```

#### 3.14 `read_pane/1` — the page itself

Attrs are listed at the top of the block. Structure, in order: header line (title "The page", optional "Show what changed" / "Back to the notes" toggle,
the four filter tabs `#read-filters`, a hint); if there is no page: "Nothing read yet."; else the minimap and then `#read-rail` (class `mg-read mt-6`, + ` collapsed` while the
drawer is open) containing, as grid children: (1) the whole-document box `.mg-doc` (owner only), (2) `#read-body.mg-read-body` with every section header
(and, for the owner, its summary controls) and every block, (3) either the change rail `.mg-read-rail.changes` or the notes rail `.mg-read-rail`.
`data-editable` on `#read-body` is `"true"`/`"false"` = `mine?`.

A block's wrapper has class list `mg-block`, `has-thread` (a thread exists), `resolved` (that thread is settled), `open` (that thread is the open one),
`rewriting` (while a rewrite is pending or present, no preview is showing, and this block is one the span covers: `rewriting?(rewrite, rewrite_ref, ref)` is
`ref in rewrite.covers` when the rewrite has a non-empty `covers`, else `rewrite_ref == ref`).
The `mg-tick` button is the hairline in the gutter that opens a thread; its `title` is "{n} in this thread" when a thread exists, else "Talk about this paragraph".

The note rail groups notes through `piles/1` (below) and prints each pile with `deck/1`; located notes go in slots carrying `data-anchor={block.ref}`;
unplaced notes of a section come first, in slots without `data-anchor`, labelled "· not located".

```heex
  attr :page, :list, default: nil
  attr :words, :integer, default: nil
  attr :only, :string, default: nil
  attr :collapsed, :boolean, default: false
  attr :block_threads, :map, default: %{}
  attr :open_thread, :map, default: nil
  attr :thread_history, :list, default: []
  attr :thread_loading, :boolean, default: false
  attr :mutter, :list, default: []
  attr :mine?, :boolean, default: true
  attr :modes, :list, default: []
  attr :rewrite, :map, default: nil
  attr :rewriting, :boolean, default: false
  attr :rewrite_ref, :string, default: nil
  attr :steer, :string, default: nil
  attr :rewrite_span, :string, default: nil
  attr :preview, :map, default: nil
  attr :editing, :string, default: nil
  attr :edit_text, :string, default: nil
  attr :summarising, :any, default: nil
  attr :document, :any, default: nil
  attr :doc_running, :boolean, default: false
  attr :slug, :string, default: nil
  attr :changes_on, :boolean, default: false
  attr :revisions, :list, default: []
  attr :applied, :any, default: nil
  attr :summary_link, :any, default: nil
  attr :comparing, :any, default: nil

  # The draft with its notes in the margin. This is the only view that shows
  # the writer their own prose, and the notes sit beside the paragraph that
  # caused them rather than at the top of a section — which is possible only
  # because every note carries a span verified against the source.
  defp read_pane(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline gap-4 flex-wrap">
        <h2 class="mg-label">The page</h2>
        <button
          :if={@revisions != []}
          class={"mg-btn sm ghost mg-chg-toggle" <> if(@changes_on, do: " on", else: "")}
          phx-click="toggle_changes"
        >{if @changes_on, do: "Back to the notes", else: "Show what changed"}</button>

        <div class="mg-tabs" id="read-filters">
          <button
            :for={
              {id, label} <- [
                {"all", "Everything"},
                {"beats", "Beats"},
                {"connections", "Connections"},
                {"tensions", "Tensions"}
              ]
            }
            class={"mg-tab" <> if((@only || "all") == id, do: " on", else: "")}
            phx-click="set_only"
            phx-value-only={id}
          >{label}</button>
        </div>
        <span class="mg-hint mt-0 ml-auto">
          Notes sit beside the sentence that caused them. The highlight is the span they are anchored to.
        </span>
      </div>

      <%= if @page in [nil, []] do %>
        <p class="mg-empty mt-6">Nothing read yet.</p>
      <% else %>
        <.minimap entries={Marginalia.Reading.outline(@page)} words={@words} />

        <div
          class={"mg-read mt-6" <> if(@collapsed, do: " collapsed", else: "")}
          id="read-rail"
          phx-hook=".MarginNotes"
        >
          <div :if={@mine?} class="mg-doc">
            <div class="mg-doc-head">
              <span class="mg-label">The whole document</span>

              <%!-- Only once there is something to make one out of. A draft
                    built from no summaries is an empty draft. --%>
              <button
                :if={Enum.any?(@page || [], &(&1.section.summary not in [nil, ""]))}
                class="mg-btn sm ghost ml-auto"
                phx-click="summaries_to_draft"
                title="Make a draft out of the summaries, to edit and read like any other"
              >Open as a draft</button>

              <%!-- The summary as a draft of its own, read, and related back
                    to this one — so the two can be held against each other
                    instead of the short version being a claim about a
                    document you are no longer looking at. --%>
              <.link
                :if={@summary_link}
                navigate={~p"/links/#{@summary_link}?lead=#{@slug}"}
                class="mg-btn sm"
              >
                Side by side
              </.link>

              <button
                :if={@mine? and Enum.any?(@page || [], &(&1.section.summary not in [nil, ""]))}
                class="mg-btn sm ghost"
                phx-click="compare_summary"
                disabled={@comparing != nil}
              >
                {cond do
                  @comparing -> "#{@comparing}…"
                  @summary_link -> "Relate them again"
                  true -> "Draft it and compare"
                end}
              </button>

              <button
                class="mg-btn sm ghost"
                phx-click="summarise_document"
                disabled={@doc_running}
              >
                {cond do
                  @doc_running -> "Reading it all…"
                  @document -> "Read it again"
                  true -> "Summarise the document"
                end}
              </button>
            </div>

            <div :if={@document} class="mg-doc-body">
              <p class="mg-doc-summary">{@document.summary}</p>
              <p :if={@document.throughline} class="mg-doc-through">{@document.throughline}</p>

              <div :if={@document.movements != []} class="mg-doc-moves">
                <span class="mg-label">how it moves</span>
                <div :for={m <- @document.movements} class="mg-doc-move">
                  <strong>{m["heading"]}</strong>
                  <span class="mg-meta">
                    §{Enum.join(m["sections"] || [], ", §")}
                  </span>
                  <p>{m["does"]}</p>
                </div>
              </div>

              <div :if={@document.guidelines != []} class="mg-doc-rules">
                <span class="mg-label">what it is working under</span>
                <div :for={g <- @document.guidelines} class="mg-doc-rule">
                  <strong>{g["guideline"]}</strong>
                  <p>{g["because"]}</p>
                  <span class="mg-meta">§{Enum.join(g["sections"] || [], ", §")}</span>
                </div>
              </div>

              <div :if={@document.tensions != []} class="mg-doc-rules tensions">
                <span class="mg-label">where those pull against each other</span>
                <div :for={t <- @document.tensions} class="mg-doc-rule">
                  <p>{t["tension"]}</p>
                  <span class="mg-meta">§{Enum.join(t["sections"] || [], ", §")}</span>
                </div>
              </div>

              <p :if={@document.dropped != []} class="mg-sum-stale">
                {length(@document.dropped)} claim(s) dropped: {Enum.join(@document.dropped, "; ")}
              </p>
            </div>
          </div>

          <div
            class="mg-read-body"
            id="read-body"
            phx-hook=".SummaryVault"
            data-editable={to_string(@mine?)}
          >
            <%= for sec <- @page do %>
              <div class="mg-read-head" id={"sec-#{sec.section.ordinal}"}>
                <div class="mg-label">Section {sec.section.ordinal}</div>
                <h2 style="font-family:var(--mg-serif)" class="text-[1.45rem] font-semibold mt-1">
                  {sec.section.title}
                </h2>

                <%!-- What the section says, for finding your place in twelve
                      of them. Per section and on request: a draft here can be
                      a hundred and eleven documents. --%>
                <div :if={@mine?} class="mg-sum">
                  <%!-- The server keeps one summary per section: re-running
                        overwrites it, and the text that was there is gone. The
                        vault below keeps the last few in this browser so a
                        re-run is undoable by the person who ran it. --%>
                  <div
                    :if={sec.section.summary}
                    class={"mg-sum-text" <> if(Marginalia.Summary.current?(sec.section), do: "", else: " stale")}
                    data-sum-key={"#{@slug}:#{sec.section.ordinal}"}
                    data-sum-at={
                      sec.section.summarised_at && DateTime.to_iso8601(sec.section.summarised_at)
                    }
                    data-sum-text={sec.section.summary}
                  >
                    {sec.section.summary}

                    <div :if={sec.section.summary_covers != []} class="mg-sum-covers">
                      <span :for={t <- sec.section.summary_covers}>{t}</span>
                    </div>

                    <div
                      :if={sec.section.summary_follows != [] or sec.section.summary_sets_up}
                      class="mg-sum-links"
                    >
                      <span :if={sec.section.summary_follows != []}>
                        needs {Enum.map_join(sec.section.summary_follows, ", ", &"§#{&1}")}
                      </span>
                      <span :if={sec.section.summary_sets_up}>
                        sets up: {sec.section.summary_sets_up}
                      </span>
                    </div>

                    <span :if={not Marginalia.Summary.current?(sec.section)} class="mg-sum-stale">
                      the section has been edited since this was written
                    </span>

                    <%!-- Not only that it went stale but what moved under it,
                          which is what decides whether it is worth running
                          again. --%>
                    <.diff_table
                      :if={Marginalia.Summary.drift(sec.section) != []}
                      rows={Marginalia.Summary.drift(sec.section)}
                      left="When it was summarised"
                      right="Now"
                      compact
                    />

                    <span :if={sec.section.summary_dropped != []} class="mg-sum-stale">
                      {length(sec.section.summary_dropped)} term(s) dropped: not in the section
                    </span>
                  </div>

                  <%!-- phx-update="ignore": the hook owns what is in here, and
                        a LiveView patch would wipe it on the next broadcast. --%>
                  <div
                    :if={sec.section.summary}
                    id={"sumvault-#{sec.section.ordinal}"}
                    class="mg-sum-vault"
                    phx-update="ignore"
                  >
                  </div>

                  <button
                    class="mg-btn sm ghost"
                    phx-click="summarise"
                    phx-value-ordinal={sec.section.ordinal}
                    disabled={MapSet.member?(@summarising, sec.section.ordinal)}
                  >
                    <%= cond do %>
                      <% MapSet.member?(@summarising, sec.section.ordinal) -> %>
                        Summarising…
                      <% sec.section.summary -> %>
                        Summarise again
                      <% true -> %>
                        Summarise this section
                    <% end %>
                  </button>
                </div>
              </div>

              <%= for b <- sec.blocks do %>
                <% t = @block_threads[b.ref] %>
                <div
                  class={
                    [
                      "mg-block",
                      t && "has-thread",
                      t && t.resolved && "resolved",
                      @open_thread && @open_thread.block_ref == b.ref && "open",
                      # every paragraph the span covers, not only the one the
                      # panel is anchored to: a rewrite of three paragraphs
                      # dimmed one and left the other two looking untouched
                      (@rewriting or @rewrite) && is_nil(@preview) &&
                        rewriting?(@rewrite, @rewrite_ref, b.ref) && "rewriting"
                    ]
                  }
                  id={"block-#{b.ref}"}
                >
                  <button
                    class="mg-tick"
                    phx-click="open_thread"
                    phx-value-ref={b.ref}
                    phx-value-section={sec.section.id}
                    aria-label={
                      if t, do: "Open the thread on this paragraph", else: "Talk about this paragraph"
                    }
                    title={
                      if t,
                        do: "#{t.messages} in this thread",
                        else: "Talk about this paragraph"
                    }
                  ></button>
                  <%= if @editing == b.ref do %>
                    <form
                      phx-submit="save_block"
                      id={"edit-#{b.ref}"}
                      phx-hook=".Editor"
                      class="mg-edit"
                    >
                      <textarea name="text" rows="3" spellcheck="true">{@edit_text}</textarea>
                      <div class="foot">
                        <span class="mg-hint mt-0">
                          This is the paragraph's markdown. ⌘↵ saves · Esc cancels
                        </span>
                        <button type="button" class="mg-btn sm ghost" phx-click="cancel_edit">cancel</button>
                        <button type="submit" class="mg-btn sm">Save</button>
                      </div>
                    </form>
                  <% else %>
                    <%!-- The paragraph the change landed in shows what it
                          replaced, in place, until it is dismissed. Matched on
                          the text rather than on the ref because replacing
                          three paragraphs with one renumbers every ref after
                          it. --%>
                    <%= if landed?(@applied, b) do %>
                      <div class="mg-applied">
                        <div class="mg-applied-head">
                          <span class="mg-label">replaced</span>
                          <button class="mg-btn sm ghost ml-auto" phx-click="dismiss_applied">
                            done
                          </button>
                        </div>

                        <.diff_table
                          rows={[{:change, @applied.before, @applied.after}]}
                          left="Before"
                          right="Now"
                          compact
                        />
                      </div>
                    <% else %>
                      {Marginalia.Reading.render_block(b.text, b.mark, b.ref, @preview)}
                    <% end %>
                  <% end %>
                </div>

                <%!-- With the rail given over to the diff, a note has nowhere
                      to sit in the margin, so it sits under its own paragraph. --%>
                <div :if={@changes_on and b.notes != []} class="mg-note-inline">
                  <button
                    :for={n <- b.notes}
                    class={"mg-note " <> n.kind}
                    phx-click="discuss"
                    phx-value-key={n.key}
                  >
                    <span class="who">{String.replace(n.kind, "_", " ")}</span>
                    <span class="said">{n.title}</span>
                  </button>
                </div>

                <.rewrite_panel
                  :if={(@rewriting or @rewrite) && @rewrite_ref == b.ref}
                  rewrite={@rewrite}
                  working={@rewriting}
                  mutter={@mutter}
                  block_ref={b.ref}
                  steer={@steer}
                  span={@rewrite_span}
                />

                <.inline_thread
                  :if={@open_thread && @open_thread.block_ref == b.ref}
                  thread={@open_thread}
                  history={@thread_history}
                  loading={@thread_loading}
                  mutter={@mutter}
                  mine?={@mine?}
                  modes={@modes}
                />
              <% end %>
            <% end %>
          </div>

          <%!-- What changed, where the notes usually are. The notes do not
                disappear: they move into the prose column beside the paragraph
                that caused them, so the rail is free for the before and after. --%>
          <div :if={@changes_on} class="mg-read-rail changes">
            <p :if={@revisions == []} class="mg-empty">
              Nothing has been changed yet.
            </p>

            <div :for={rev <- @revisions} class="mg-chg">
              <span class="mg-label">
                {rev.origin}{if rev.note, do: " — #{rev.note}"} · section {rev.section_ordinal}
              </span>
              <div class="mg-chg-old">
                <span
                  :for={{op, t} <- Marginalia.Diff.words(rev.before, rev.after)}
                  class={word_class(op, :old)}
                >{t}</span>
              </div>
              <div class="mg-chg-new">
                <span
                  :for={{op, t} <- Marginalia.Diff.words(rev.before, rev.after)}
                  class={word_class(op, :new)}
                >{t}</span>
              </div>
            </div>
          </div>

          <div :if={not @changes_on} class="mg-read-rail">
            <%= for sec <- @page do %>
              <%!-- A section whose beats could not be anchored puts every one
                    of them at the top of the rail. Seven of those is thirteen
                    hundred pixels of margin for one section, so past four they
                    are stacked by kind — see piles/1. --%>
              <div
                :for={pile <- piles(sec.unplaced)}
                class={[
                  "mg-note-slot",
                  hd(pile).kind,
                  length(pile) > 1 && "deck",
                  length(pile) > 2 && "deep"
                ]}
              >
                <.deck pile={pile} located={false} />
              </div>

              <%= for b <- sec.blocks, pile <- piles(b.notes) do %>
                <div
                  class={[
                    "mg-note-slot",
                    hd(pile).kind,
                    length(pile) > 1 && "deck",
                    length(pile) > 2 && "deep"
                  ]}
                  data-anchor={b.ref}
                >
                  <.deck pile={pile} located={true} />
                </div>
              <% end %>
            <% end %>
          </div>

          <%!-- hook script .Steer omitted here; see section 4 --%>

          <%!-- hook script .Deck omitted here; see section 4 --%>

          <%!-- hook script .Editor omitted here; see section 4 --%>

          <%!-- hook script .Selection omitted here; see section 4 --%>

          <%!-- hook script .Share omitted here; see section 4 --%>

          <%!-- hook script .SummaryVault omitted here; see section 4 --%>

          <%!-- hook script .MarginNotes omitted here; see section 4 --%>
        </div>
      <% end %>
    </div>
    """
  end
```

#### 3.15 `piles/1` and `deck/1` (margin note cards)

`piles(notes)`: up to 4 notes -> one pile per note; more than 4 -> group by `kind`, groups ordered by the position of the first note of that kind, each group one pile.
A pile of 1 is a card; a pile of several is a deck with a pager. Every card is rendered; the `Deck` hook shows one. The slot class list
(`mg-note-slot`, the kind, `deck` when pile > 1, `deep` when pile > 2) is set by `read_pane`. `String.replace(kind, "_", " ")` makes "pays_off" read "pays off".

```heex
  @doc """
  Notes for one place in the margin, grouped into the slots the rail holds.

  Four or fewer, one slot each. A pile that fits is easier to read than a
  pile with controls on it, and most paragraphs carry one or two notes.

  Past four they are grouped by kind, and a kind with several in it becomes
  one slot you flip through. The case that forced this is a section whose
  beats could not be anchored: those have no paragraph to sit beside, so
  every one of them stacks at the top of the rail, and seven of them is
  thirteen hundred pixels of margin against three paragraphs of prose.

  Grouping by kind rather than just paging the lot is the point. Three beats
  about one section are the same kind of remark and read as a set; a beat, a
  tension and a pays-off are three different things and hiding two of them
  behind a control would be worse than the height.

  The groups keep the order the notes arrived in, by first appearance, so
  the rail does not reshuffle itself when a note is added.
  """
  def piles(notes) when length(notes) <= 4, do: Enum.map(notes, &[&1])

  def piles(notes) do
    notes
    |> Enum.group_by(& &1.kind)
    |> Enum.sort_by(fn {kind, _} -> Enum.find_index(notes, &(&1.kind == kind)) end)
    |> Enum.map(fn {_kind, group} -> group end)
  end

  attr :pile, :list, required: true
  attr :located, :boolean, default: true

  # One slot. A pile of one is a card; a pile of several is a card with the
  # rest behind it and a pager under it. Every card is rendered either way —
  # the hook only changes which one is visible, so there is no round trip to
  # the server to read the next note, and the height does not change when
  # you flip because the cards share one grid cell.
  defp deck(assigns) do
    ~H"""
    <div class="mg-deck" id={"deck-" <> hd(@pile).key} phx-hook=".Deck">
      <div class="cards">
        <button
          :for={{n, i} <- Enum.with_index(@pile)}
          class={["mg-note", n.kind, i == 0 && "on"]}
          phx-click="discuss"
          phx-value-key={n.key}
          title="Talk about this"
        >
          <span class="who">
            {String.replace(n.kind, "_", " ")}{if !@located, do: " · not located"}
          </span>
          <span class="said">{n.title}</span>
          <span :if={n.body} class="why">{n.body}</span>
        </button>
      </div>

      <div :if={length(@pile) > 1} class="nav">
        <button type="button" data-step="-1" aria-label="Previous">‹</button>
        <span class="n">1 / {length(@pile)}</span>
        <button type="button" data-step="1" aria-label="Next">›</button>
      </div>
    </div>
    """
  end
```

#### 3.16 `trace_pane/1` (owner only)

Attrs: `work`, `events`, `stats`, `building`. Events are grouped by consecutive equal `narrative` (`Enum.chunk_by`); each group is a labelled block of `.call` rows
(`.call.no` for refusals). `summarise_args` renders an `add_node` call as "{type}  {title}" (two spaces), a `link` call as "{from} → {to}  ({rationale})", a
`set_status` call as "{id} → {status}", any other call as the first 160 characters of the args JSON; `refusal_text` is the `"error"` field of the result JSON or the first 200 characters of the result.

```heex
  attr :work, :map, required: true
  attr :events, :list, required: true
  attr :stats, :map, default: nil
  attr :building, :boolean, default: false

  # The build, as it happened. Refusals are kept and shown rather than hidden,
  # because "the server said no and the model corrected itself" is the evidence
  # that the flow rule and the anchoring guarantee are real and not decorative.
  defp trace_pane(assigns) do
    ~H"""
    <div>
      <div class="flex items-baseline gap-3 flex-wrap">
        <h2 class="mg-label">Build trace</h2>
        <%= if @stats && @stats.calls > 0 do %>
          <span class="mg-meta">{@stats.calls} tool calls · {@stats.refused} refused</span>
        <% end %>
        <div class="ml-auto flex gap-2 items-baseline">
          <%= if @building do %>
            <span class="text-[0.75rem] italic text-[var(--mg-dim)]">building…</span>
          <% end %>
          <a href={~p"/works/#{@work.slug}/trace.json"} class="mg-btn sm ghost">trace.json</a>
        </div>
      </div>

      <p class="mg-hint mt-2 max-w-[68ch]">
        Every call the model made to <code>add_node</code>, <code>link</code>
        and <code>set_status</code>
        — the deciduous CLI, handed over as functions — and what the
        server answered. Red lines are refusals: a quote that was not in your draft, or a link
        that broke <code>goal → option → decision → action → outcome</code>.
      </p>

      <%= if @stats && @stats.refused > 0 do %>
        <div class="mt-3 flex gap-2 flex-wrap">
          <%= for {kind, n} <- @stats.refusals do %>
            <span class="mg-badge accent">{kind} × {n}</span>
          <% end %>
        </div>
      <% end %>

      <%= if @events == [] do %>
        <p class="mg-empty mt-6">
          Nothing recorded yet. Build the decision graph from the Graph tab and this fills in live.
        </p>
      <% else %>
        <div class="mg-trace mt-4">
          <%= for {narrative, group} <- Enum.chunk_by(@events, & &1.narrative) |> Enum.map(&{List.first(&1).narrative, &1}) do %>
            <div class="mt-5 first:mt-0">
              <div class="mg-label mb-1">{narrative}</div>
              <%= for e <- group do %>
                <div class={"call" <> if(e.ok, do: "", else: " no")}>
                  <span class="seq">{e.seq}</span>
                  <span class="tool">{e.tool}</span>
                  <span class="min-w-0 break-words">
                    {summarise_args(e)}
                    <%= if not e.ok do %>
                      <span class="why">↳ {refusal_text(e)}</span>
                    <% end %>
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # The trace is only useful if it is skimmable, so each call renders as the one
  # line it would have been at a shell prompt.
  defp summarise_args(%{tool: "add_node", args: args}) do
    a = decode(args)
    "#{a["type"]}  #{a["title"]}"
  end

  defp summarise_args(%{tool: "link", args: args}) do
    a = decode(args)
    "#{a["from"]} → #{a["to"]}#{if a["rationale"], do: "  (#{a["rationale"]})", else: ""}"
  end

  defp summarise_args(%{tool: "set_status", args: args}) do
    a = decode(args)
    "#{a["id"]} → #{a["status"]}"
  end

  defp summarise_args(%{args: args}), do: String.slice(args || "", 0, 160)

  defp refusal_text(%{result: result}) do
    case decode(result) do
      %{"error" => e} -> e
      _ -> String.slice(result || "", 0, 200)
    end
  end

  defp decode(nil), do: %{}

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, m} when is_map(m) -> m
      _ -> %{}
    end
  end
```

#### 3.17 `prompts_pane/1` (owner only)

Attrs: `passes`, `modes`. Prints, for each pass, name, model, "{runs} · produces {produces}" and the full prompt text in a `<pre>`; then each chat mode's `label — blurb` and `stance` text.

```heex
  attr :passes, :list, required: true
  attr :modes, :list, required: true

  defp prompts_pane(assigns) do
    ~H"""
    <div>
      <h2 class="mg-label">How the graph was built</h2>
      <p class="mt-2 text-xs opacity-60 max-w-prose">
        The exact prompts that ran against your draft, read out of the running code rather than
        retyped here — so this page cannot drift from what actually happened.
      </p>

      <%= for p <- @passes do %>
        <div class="mt-6">
          <div class="flex items-baseline gap-2 flex-wrap">
            <h3 style="font-family:var(--mg-serif)" class="font-semibold text-[1.05rem]">{p.name}</h3>
            <span class="mg-meta">{p.model}</span>
          </div>
          <div class="mg-hint mt-0.5">{p.runs} · produces {p.produces}</div>
          <pre class="mt-2.5 text-[0.74rem] leading-relaxed whitespace-pre-wrap bg-[var(--mg-margin)] border border-[var(--mg-rule)] rounded-sm p-3.5 overflow-x-auto max-w-[80ch]">{p.prompt}</pre>
        </div>
      <% end %>

      <h2 class="mg-label mt-12">How the chat is steered</h2>
      <p class="mt-2 text-xs opacity-60 max-w-prose">
        Every conversation carries the same system prompt; the stance below is appended last,
        depending on which mode you are in.
      </p>
      <%= for m <- @modes do %>
        <div class="mt-5">
          <h3 style="font-family:var(--mg-serif)" class="font-semibold text-[1.05rem]">
            {m.label} <span class="font-normal text-[var(--mg-dim)]">— {m.blurb}</span>
          </h3>
          <pre class="mt-2.5 text-[0.74rem] leading-relaxed whitespace-pre-wrap bg-[var(--mg-margin)] border border-[var(--mg-rule)] rounded-sm p-3.5 overflow-x-auto max-w-[80ch]">{m.stance}</pre>
        </div>
      <% end %>
    </div>
    """
  end
```

#### 3.18 `chat_panel/1` (the drawer)

Attrs: `history`, `loading`, `status`, `llm_ready`, `mode`, `modes`, `provider`, `focus`, `quota` (default `:unlimited`), `mine?`, `threads_list`, `conversation`, `cited`, `mutter` (list, default `[]`).
While `loading`, the transcript ends with `<.mutter :if={@loading} lines={@mutter} class="py-1" />` (3.20), where the old markup was three bare dots. Only rendered while `chat_open`. Composer visibility: shown only when `mine? and llm_ready and status != "pending" and quota != 0` (quota `:unlimited` counts as non-zero);
when `quota == 0` an "Out of questions" box is shown instead; when not `mine?` a "Read only" box is shown. The `quota left` hint shows only for integer quotas of 20 or fewer.

```heex
  attr :history, :list, required: true
  attr :loading, :boolean, required: true
  attr :mutter, :list, default: []
  attr :status, :string, required: true
  attr :llm_ready, :boolean, required: true
  attr :mode, :string, required: true
  attr :modes, :list, required: true
  attr :provider, :string, default: nil
  attr :focus, :map, default: nil
  attr :quota, :any, default: :unlimited
  attr :mine?, :boolean, default: true
  attr :threads_list, :list, default: []
  attr :conversation, :map, default: nil
  attr :cited, :list, default: []

  defp chat_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full min-h-0">
      <div class="px-4 pt-3 pb-2.5 shrink-0 bg-[var(--mg-paper)]">
        <div class="flex items-baseline gap-2">
          <span class="mg-label">Talk about it</span>
          <span class="mg-meta opacity-70">{Marginalia.LLM.label(@provider)}</span>
          <button class="mg-btn sm ghost ml-auto" phx-click="toggle_chat" title="Close">Close</button>
        </div>

        <%= if @llm_ready and @status != "pending" do %>
          <div class="mg-tabs mt-2.5">
            <%= for m <- @modes do %>
              <button
                class={"mg-tab" <> if(m.id == @mode, do: " on", else: "")}
                phx-click="set_mode"
                phx-value-mode={m.id}
                title={m.blurb}
              >{m.label}</button>
            <% end %>
          </div>
          <div class="text-[0.72rem] text-[var(--mg-dim)] mt-1.5">
            {Enum.find(@modes, &(&1.id == @mode)).blurb}
          </div>
        <% end %>
      </div>

      <div :if={@mine?} class="mg-threads shrink-0">
        <button class="mg-thread" phx-click="new_chat" title="Start a new thread">+ New</button>
        <button
          :for={t <- @threads_list}
          class={"mg-thread" <> if(@conversation && t.id == @conversation.id, do: " on", else: "")}
          phx-click="switch_chat"
          phx-value-id={t.id}
        >
          <span class="name">{t.title}</span>
          <span class="n">{t.messages}</span>
        </button>
        <button
          :if={@conversation && length(@threads_list) > 1}
          class="mg-thread"
          phx-click="delete_chat"
          phx-value-id={@conversation.id}
          data-confirm="Delete this thread and everything said in it?"
          title="Delete the thread you are in"
        >×</button>
      </div>

      <div
        id="chat-scroll"
        phx-hook=".StickToBottom"
        class="flex-1 overflow-y-auto min-h-0 px-4 py-4 flex flex-col gap-4"
      >
        <%= cond do %>
          <% not @llm_ready -> %>
            <p class="text-sm opacity-60">
              No {Marginalia.LLM.label(@provider)} key configured on this deploy.
            </p>
          <% @status == "pending" -> %>
            <p class="text-sm opacity-60">Confirm the sections and run the read first.</p>
          <% not @mine? and @history == [] -> %>
            <p class="mg-empty">Nothing has been said about this draft yet.</p>
          <% @history == [] -> %>
            <p class="mg-prose text-[0.95rem] text-[var(--mg-dim)]">
              {Marginalia.Chat.Editor.opener(@mode)}
            </p>
          <% true -> %>
            <%= for m <- @history do %>
              <%= if m["role"] == "user" do %>
                <div class="mg-turn-you">{m["content"]}</div>
              <% else %>
                <div class="md">{Marginalia.Markdown.to_html(m["content"])}</div>
              <% end %>
            <% end %>
        <% end %>

        <.mutter :if={@loading} lines={@mutter} class="py-1" />
      </div>

      <%= if not @mine? do %>
        <div class="border-t border-[var(--mg-rule)] p-4 shrink-0 bg-[var(--mg-margin)]">
          <div class="mg-label">Read only</div>
          <p class="text-[0.8rem] mt-1.5 leading-relaxed text-[var(--mg-dim)]">
            You have the link to someone else's draft. You can read everything here — the
            page, the map, what has already been said — but the asking is theirs.
          </p>
        </div>
      <% end %>

      <%= if @mine? and @llm_ready and @status != "pending" and @quota == 0 do %>
        <div class="border-t border-[var(--mg-rule)] p-4 shrink-0 bg-[var(--mg-margin)]">
          <div class="mg-label">Out of questions</div>
          <p class="text-[0.8rem] mt-1.5 leading-relaxed text-[var(--mg-dim)]">
            This deploy gives every account {Marginalia.Chat.message_limit()} questions. The
            read, the graph and everything already said stay where they are.
          </p>
        </div>
      <% end %>

      <%= if @mine? and @llm_ready and @status != "pending" and @quota != 0 do %>
        <div class="border-t border-[var(--mg-rule)] p-3 shrink-0 bg-[var(--mg-paper)]">
          <div :if={@focus} class="mg-holding">
            <div class="flex items-start gap-2">
              <div class="min-w-0 flex-1">
                <div class="mg-label">holding · {String.replace(@focus.kind, "_", " ")}</div>
                <div class="text-[0.8rem] mt-1 leading-snug font-medium">{@focus.title}</div>
              </div>
              <button type="button" class="mg-btn sm ghost shrink-0" phx-click="clear_focus">drop</button>
            </div>

            <%!-- one card per section, so two sections plainly look like two --%>
            <div class="mt-2 flex gap-2 flex-wrap">
              <div :for={sec <- @focus.sections} class="mg-held">
                <span class="n">{sec.ordinal}</span>
                <span class="min-w-0">
                  <span class="t">{sec.title}</span>
                  <span class="mg-meta">{sec.word_count} words, in full</span>
                </span>
              </div>
            </div>
          </div>

          <div :if={@cited != []} class="flex flex-col gap-1.5 mb-2.5">
            <div class="mg-label">
              Carrying {length(@cited)} passage{if length(@cited) > 1, do: "s"}
            </div>
            <div :for={{c, i} <- Enum.with_index(@cited)} class="mg-chip">
              <span class="min-w-0">
                <span class="cited">"{c.text}"</span>
                <span class="mg-meta">section {c.ordinal}</span>
              </span>
              <button type="button" class="x" phx-click="drop_context" phx-value-i={i} title="Drop">×</button>
            </div>
          </div>

          <form phx-submit="send" id="chat-form" phx-hook=".Composer" class="flex flex-col gap-2">
            <textarea
              name="message"
              rows="5"
              autocomplete="off"
              placeholder="Ask it something. Paste a paragraph you're stuck on, or a question you can't answer yourself."
              class="w-full text-[0.84rem] leading-relaxed resize-none min-h-[7.5rem] max-h-[22rem] px-3 py-2.5 bg-[var(--mg-card)] border border-[var(--mg-rule)] rounded-sm focus:outline-none focus:border-[var(--mg-accent)]"
              disabled={@loading}
            ></textarea>
            <div class="flex items-center gap-3">
              <span class="mg-hint mt-0">
                Enter to send · Shift+Enter for a new line<%= if is_integer(@quota) and @quota <= 20 do %>
                  · <span class="text-[var(--mg-accent)]">{@quota} left</span>
                <% end %>
              </span>
              <button
                type="submit"
                class="mg-btn ml-auto"
                disabled={@loading}
              >{if @loading, do: "Thinking…", else: "Ask"}</button>
            </div>
          </form>
        </div>
      <% end %>

      <%!-- hook script .StickToBottom omitted here; see section 4 --%>

      <%!-- hook script .Composer omitted here; see section 4 --%>
    </div>
    """
  end
```

#### 3.20 `mutter/1` — the thinking indicator (new; `MarginaliaWeb.CoreComponents`, shared with other pages)

Attrs: `lines` list of strings (default `[]`), `label` string (default `"thinking"`, becomes `aria-label`), `class` (extra classes on the wrapper, default nil). The element id is `"mutter-" <> to_string(:erlang.phash2(lines))`: it changes whenever the list changes, which is what makes a fresh `<span>` (and so a fresh rotation) for each new wait.
Rendered on this page in three places, always fed the single `@mutter` assign:
* `chat_panel` (the drawer transcript), while `@loading` — default label `"thinking"`, `class="py-1"`;
* `inline_thread` (a paragraph's thread), while `@loading` (= `thread_loading`) — default label, `class="py-0.5"`;
* `rewrite_panel`, while `@working` (= `rewriting`) — `label="reading it"`, no class.
It is also used by the linked-pair chat component (`LinkChat`, `label="reading"`), which is not part of this page.
The wrapper is `.mg-dots` (CSS: `display:flex; gap:.3rem; align-items:center; padding:.7rem 0`), replacing the old bare `flex gap-1 items-center py-1` row of dots; the old `aria-label`s ("thinking", "reading it") are preserved through `label`.
With `lines == []` (fresh install, table unseeded) only the three dots render. With one line it is shown and never rotates; with two or more the `.Rotate` hook cycles them. The span carries `phx-update="ignore"` so a server patch cannot put the first line back mid-rotation; because its id depends on the list, a new `@mutter` list produces a new element.
Stylesheet additions that go with it (already in `app.css`): `.mg-mutter` (serif italic 0.84rem, colour `var(--mg-dim)`, `margin-right:.35rem`, fade-in animation `mg-mutter-in .32s`, `transition: opacity .32s`), `.mg-mutter.out {opacity:0}`; and `.mg-read-body ::selection` / `::-moz-selection` set to background `#f7d774` and colour `var(--mg-ink)` so selected prose stays legible.

```heex
  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  The wait, with a few words in front of it.

  Three pulsing dots said only that a model was busy. The words come from
  `Marginalia.Mutterings`, a table of lines a cheap model wrote in
  character. A handful are picked when the wait begins and the page
  cycles through them itself, three seconds each with a fade between,
  so nothing crosses the socket while the model works. `lines` empty, as
  it is on a fresh install before the table has been seeded, leaves the
  dots standing alone.

  The span is `phx-update="ignore"` because the hook owns its text: a
  patch from the server would put the first line back mid-rotation.
  """
  attr :lines, :list, default: []
  attr :label, :string, default: "thinking"
  attr :class, :any, default: nil

  def mutter(assigns) do
    assigns = assign(assigns, :id, "mutter-#{:erlang.phash2(assigns.lines)}")

    ~H"""
    <div class={["mg-dots", @class]} aria-label={@label}>
      <span
        :if={@lines != []}
        id={@id}
        class="mg-mutter"
        phx-hook=".Rotate"
        phx-update="ignore"
        data-lines={Jason.encode!(@lines)}
      >
        {hd(@lines)}
      </span>
      <span class="mg-dot"></span>
      <span class="mg-dot" style="animation-delay:.18s"></span>
      <span class="mg-dot" style="animation-delay:.36s"></span>
    </div>
    <%!-- hook script .Rotate omitted here; see section 4 --%>
    """
  end
```

The hook's JavaScript is in 4.15.

#### 3.19 Where each of the 19 function components is used

`tab` (render, x7), `confirm_gate` (render), `progress` + `stage` (render), `map_view` (render), `graph_pane`, `grounded_node` (spine, questions, threads),
`tour_card` (render), `changes_pane` + `diff_table` (changes tab; `diff_table` also inside `read_pane` for the applied-change box and for stale-summary drift),
`rewrite_panel`, `inline_thread`, `links_control` (render), `minimap`, `read_pane`, `deck`, `trace_pane`, `prompts_pane`, `chat_panel`.
Plus `mutter` from `CoreComponents` (3.20), making 20 components rendered by this page. That is: tab, confirm_gate, progress, stage, map_view, graph_pane, tour_card, grounded_node, changes_pane, diff_table, rewrite_panel, inline_thread, links_control, minimap, read_pane, deck, trace_pane, prompts_pane, chat_panel.
(`piles/1` and `changes_pane`/`diff_table` are public `def`s; the rest are `defp`.)


---

## 4. Hooks (client JavaScript)

There are 15 `phx-hook` bindings on this page: 13 colocated hooks defined in `show.ex`, one (`.Rotate`) defined in
`components/core_components.ex`, and one (`.Walk`) defined in `components/walk.ex`. Each is a `<script :type={Phoenix.LiveView.ColocatedHook} name=".Name">` whose body is an
`export default { mounted(), updated(), destroyed(), ... }` object. They are compiled into the bundle
(`import {hooks as colocatedHooks} from "phoenix-colocated/marginalia"`, passed to `LiveSocket` as `hooks`), keyed by
module-qualified name (`MarginaliaWeb.WorkLive.Show.Clock`; `.Rotate` is `MarginaliaWeb.CoreComponents.Rotate`, `.Walk` is `MarginaliaWeb.Walk.Walk`). The scripts do not
appear in the served HTML.

Lifecycle meaning, for a non-LiveView implementation: `mounted` = the element appeared in the DOM;
`updated` = the server re-rendered and the element survived (attributes/children may have changed);
`destroyed` = the element was removed. `this.el` is the element, `this.pushEvent(name, payload)` sends a server
event (section 5) to the page process, `this.handleEvent(name, fn)` subscribes to server-pushed events (the only
one on this page is `chat:clear`, payload `{}`, pushed by the server on `send` and `thread_send`).

Index (element -> hook -> server traffic):

| hook | element | pushes to server | handles from server |
|---|---|---|---|
| `.Clock` | `#read-clock` | none | none |
| `.LaneTree` | `#graph-canvas` | none | none |
| `.Hover` | `#rw-list` | `preview_rewrite {i}` (string), `clear_preview {}` | none |
| `.Minimap` | `nav#minimap` | none | none |
| `.Steer` | `textarea#rw-steer` | none (dispatches `submit` on its form, which fires `steer_rewrite`) | none |
| `.Deck` | `.mg-deck#deck-*` | none | none |
| `.Editor` | `form#edit-{ref}` | `cancel_edit {}` (dispatches `submit`, which fires `save_block`) | none |
| `.Selection` | `#page-body` | `add_context {text}`, `suggest_rewrite {text, ref}`, `open_thread {ref, section, quote}`, `edit_block {ref}` | none |
| `.Share` | `#share-link` | none | none |
| `.SummaryVault` | `#read-body` | none | none |
| `.MarginNotes` | `#read-rail` | none | none |
| `.StickToBottom` | `#chat-scroll`, `#thread-body-{id}` | none | none |
| `.Composer` | `#chat-form`, `#thread-form-{id}` | none (dispatches `submit`) | `chat:clear {}` |
| `.Rotate` | `span.mg-mutter#mutter-*` | none | none |
| `.Walk` | `#walk` | `end_walk {}`, plus the step's own event (`set_only {only}`, `edit_block {ref}`, `walk_reset {}`) | none |

### 4.1 `.Clock` (`#read-clock`, inside `progress`)

Counts up from `data-since` (unix seconds). Writes `m:ss` into the element's text each second. No server round trip by design.
Its initial text is "0:00".

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

### 4.2 `.LaneTree` (`#graph-canvas`)

Draws the Graph tab as a git-log style lane tree into `<svg id="graph-svg">` from the JSON in `data-graph` (section 7 gives the JSON).
Algorithm: the first edge (by edge id) into each node is its parent edge; later edges into the same node are "secondary" and drawn as dotted
curves. Children are grouped by parent; the walk gives the first child the parent's lane and each further child a lane one to the right,
depth-first, assigning one row per node. Lane x is clamped at 12 lanes. Rows are 21px high, lanes 12px apart. Hovering a row previews its
detail in `#graph-detail`; clicking keeps it (and adds class `sel`). `phx-update="ignore"` means the server never patches the canvas;
`updated()` redraws if `data-graph` was replaced anyway. Colours per node type are in `COLOR`; a filled dot means anchored
(`metadata_json.anchored`), a hollow one structural. Labels are the title cut to 82 chars.

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

### 4.3 `.Hover` (`#rw-list`, inside `rewrite_panel`)

Hover a candidate and it is previewed in the paragraph; leaving the list clears it after 80 ms. The server replies by setting
`preview = %{original, text: candidate_text}`, which re-renders the anchored paragraph with the word diff (`ins.mg-swap`, `del.mg-cut`).
`data-i` on each `.mg-rw` is the candidate index; the payload `i` is that attribute's string.

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

### 4.4 `.Minimap` (`nav#minimap`)

Toggles class `open` on the nav when the rail button is clicked (and `aria-expanded`); clicking a row smooth-scrolls to the section/heading
element whose id is the link's `data-target` (`sec-N` or `block-REF`), closes the panel and lights that row and tick (class `on`).
A click elsewhere or Escape closes it. An `IntersectionObserver` with `rootMargin: "-10% 0px -80% 0px"` marks the heading most recently in the top band as `on`.

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

### 4.5 `.Steer` (`textarea#rw-steer`)

Auto-growing textarea (max 160px). Enter (no Shift) dispatches a bubbling `submit` event on the form, which `phx-submit="steer_rewrite"` turns into
`steer_rewrite {steer}`. Shift+Enter inserts a newline.

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

### 4.6 `.Deck` (`.mg-deck`)

Pure client pager over the cards `.cards > .mg-note`: the element with class `on` is shown, others get `aria-hidden="true"` and `tabindex=-1`;
`[data-step]` buttons (value -1 / +1) step with wraparound, ArrowLeft/ArrowRight too; updates the "n / total" label. Clicks on the pager stop propagation so they do not trigger the card's `discuss` click.

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

### 4.7 `.Editor` (`form#edit-{ref}`)

On mount: grows the textarea to its content, focuses it with the cursor at the end. Escape pushes `cancel_edit {}`. Cmd/Ctrl+Enter dispatches `submit` on the form
(`phx-submit="save_block"` sends `{text}`).

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

### 4.8 `.Selection` (`#page-body`)

The selection toolbar and the click-to-edit gesture. Registers document-level `mousedown`, `mouseup`, `keyup` listeners and a window `scroll` listener.
After a mouse-up/keyup it positions `#sel-actions` below the end of the selection if the selection is 12+ characters and inside `#page-body`; the Discuss and Rewrite
buttons are hidden unless both ends of the selection are inside `.mg-read-body` (so selecting chat text only offers "Add to question").
The buttons listen on `mousedown` (a click would clear the selection first). Payloads:
* `#sel-add` -> `add_context {text}`.
* `#sel-rewrite` -> `suggest_rewrite {text, ref}` where `ref` is the ref of the **last** paragraph the selection covers (falls back to the first).
* `#sel-discuss` -> `open_thread {ref, section, quote: text}` where `ref` is the first paragraph's ref and `section` is the string value of the `phx-value-section` attribute of that paragraph's `.mg-tick` (the section id).
* A plain click (pointer moved 4px or less, nothing selected) inside a paragraph of an editable body (`data-editable="true"`), not on `a, button, input, textarea, form, .mg-thread-panel, .mg-rewrite`, not on a `mark[id]`, and not while `.mg-read` is `collapsed` (drawer open) -> `edit_block {ref}` with the block id minus its `block-` prefix.

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

### 4.9 `.Share` (`#share-link`)

Click copies `data-url` to the clipboard and changes the button text to "Copied" for 1.4 s; if the clipboard is blocked it shows `window.prompt("Copy this link", url)` instead.

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

### 4.10 `.SummaryVault` (`#read-body`)

Browser-local undo for section summaries. For every `[data-sum-key]` (`"{slug}:{ordinal}"`) element in the body it keeps the last 6 distinct summary texts in
`localStorage["mg:sum:{slug}:{ordinal}"]` as `[{s: text, at: iso}]` newest first, and renders the older ones into `#sumvault-{ordinal}` as a `<details>`
("N earlier version(s) of this summary, kept in this browser"). Runs on mount and after every server render. Every storage access is try/caught.

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

### 4.11 `.MarginNotes` (`#read-rail`)

The layout engine for the margin. Wide: each `.mg-note-slot` is absolutely positioned in `.mg-read-rail` level with its `#anchor-{ref}` mark, stacked so nothing overlaps,
and the rail's height set to the stack; slots hovered light their mark (class `lit`). Drawer open (`.mg-read.collapsed`) or fewer than 3 grid tracks: notes fold into the highlights:
hovering a `mark[id]` peeks its slot (fixed position near the mark, class `peek`), clicking pins it (class `pinned`), clicking elsewhere unpins. A shown peek follows scroll and resize.
If a `.mg-applied` diff is on screen, slots that would be buried under it (more than a third overlapping) are "shoved" to the left of the prose (class `shoved`) and near misses nudged clear.
Runs `layout()` on mount, on every `updated`, and on `ResizeObserver` of the rail.

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

### 4.12 `.StickToBottom` (`#chat-scroll`, `#thread-body-{id}`)

Scrolls to the bottom on mount and after each update, but only while the reader is within 80px of the bottom.

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

### 4.13 `.Composer` (`#chat-form`, `#thread-form-{id}`)

Enter sends (dispatches `submit`; Shift+Enter is a newline; ignored while IME composing or when the box is blank). The textarea grows between 120 and 352px.
`chat:clear` empties and refocuses the textarea. Quirk: the server pushes `chat:clear` to the whole page, and every mounted Composer handles it, so sending a thread
message also clears the chat drawer's composer if it is open, and vice versa. It also focuses the box on mount.

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

### 4.14 `.Walk` (`#walk`, from `MarginaliaWeb.Walk`)

The guided tour overlay. Renders a spotlight ring, a veil and a card from the `data-steps` JSON; Back/Next/end buttons, arrow keys and Escape. After 550 ms on each step it performs the step's
`act`: `push` -> `pushEvent(act.event, act.params)`; `client` -> a named DOM gesture (`open_map` clicks the minimap rail, `open_thread` clicks the first block's `.mg-tick`, `ask_thread` types into the open thread form and submits it,
`select` selects the first paragraph and fires a `mouseup`, `rewrite` fires `mousedown` on `#sel-rewrite`, `edit` pushes `edit_block {ref}`, `reset` clears selection, closes the map and pushes `walk_reset {}`). `end` pushes `end_walk {}`.
(`hop` pushes `walk_hop {to}` — there is no handler for it in this LiveView and no step uses it.)

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


### 4.15 `.Rotate` (`span.mg-mutter`, inside `mutter/1`; new)

Reads the JSON array in `data-lines`. With two or more lines, every 3 seconds it adds class `out` (opacity to 0 over .32 s); 320 ms later it sets the text to the next line (wrapping to the first) and removes `out`, which fades back up through the opacity transition. With fewer than two lines it does nothing. The first line is server-rendered text. It clears its interval and timeout on `destroyed`. Pure client: the server never hears about it. The element is `phx-update="ignore"`, so the text the hook sets survives patches; a different line list yields a different element id, hence a new element and a new hook instance. The script sits in `core_components.ex` and is shared by every page that uses `mutter/1`.

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

---

## 5. Events (`handle_event/3`)

42 distinct events. Transport: each is a message `{event, params}` from the browser (a `phx-click` element sends its `phx-value-*`
attributes as string params; a form sends its named fields; hooks send the payload shown in section 4). Handlers return the
new state, optionally a navigation, a flash, or a `push_event`. After every handler the page re-renders from state.

Conventions used below: "flash error X" = one-shot error message X; "patch" = `push_patch(to: path(socket), replace: true)`
(re-enters `handle_params`, which reloads data for the view as in section 2); "navigate" = `push_navigate` (full page change within the live session);
"not mine" = the viewer is not the draft's owner. `arg_int(x)` = integer parse of a string (nil on failure; integers pass through).
`quota 0` = `assign(quota: 0)`, which swaps the composer for the "Out of questions" box; the action does nothing else.
The standard denial text is **"This draft is someone else's."** unless a different one is given.

**Guard clause** (matches before the handlers for these five names, but is written after the others in the file, so it only covers them):
for `build_graph`, `start_read`, `send`, `set_mode`, `set_provider` when `mine? == false` -> flash error
"This draft is someone else's. You can read it, not change it." and nothing else.

**Server-side ownership checks are uneven.** Events that check `mine?`: suggest_rewrite, steer_rewrite, compare_summary, summaries_to_draft, summarise_document,
summarise, apply_rewrite, edit_block, save_block (inside the helper), thread_send, link_to, plus the five in the guard clause. Events with **no** server check, whose
controls are merely hidden from non-owners: discuss_node, open_thread (creates a conversation row for the visitor's click), resolve_thread, new_chat, switch_chat, delete_chat,
add_context, start_walk, set_only, toggle_*, show_help, dismiss_*, clear_*, preview/clear_preview, close_*, cancel_edit. A rewrite should either reproduce this or tighten it deliberately; do not tighten it by accident (for example `open_thread` by a visitor currently works).

### Navigation and view state

1. **`set_view {view}`** (tab buttons, `phx-value-view`): `view = to_view(v)`; patch. Data loads in `handle_params`.
2. **`toggle_chat`** (Talk about it, drawer Close): flip `chat_open`; patch (URL gets/loses `chat=1`).
3. **`set_only {only}`** (read filters; also sent by the walkthrough): `only = nil` if `""` or `"all"`, else the string (`beats|connections|tensions`); `page = Reading.page(work, only:)`. Not in the URL.
4. **`show_help`**: `tour = Tour.for_view(view)` (nil for a view with no tour). Does not touch `seen_tours`.
5. **`dismiss_tour`**: `tour = nil`.
6. **`toggle_changes`**: flip `changes_on`.
7. **`toggle_linking`**: flip `linking?`. Also pushed by `phx-click-away` on `#linkbox` when open.

### Chat focus and context

8. **`discuss {key}`** (a note card): `focus = Reading.focus(work, key)`; nil -> no change. Else `focus`, `chat_open = true`; patch.
9. **`discuss_node {id}`** (spine/thread/question Discuss button): `node = Works.get_node(work.id, arg_int(id))`, nil -> no change. `g = Reading.grounding(work, node.id)`.
   `focus = %{kind: node.node_type, title: node.title, body: <node.body and grounding_note(g) joined by " ", blanks dropped>, quote: node.quote || first beat's quote, sections: g.sections}`;
   `grounding_note` = nil with no beats, else "It runs through section N: title; section M: title." (joined with "; "). `chat_open = true`; patch.
10. **`clear_focus`** ("drop" in the holding card): `focus = nil`.
11. **`add_context {text}`** (selection toolbar "Add to question"): `cite = Reading.cite(work, text)`; nil -> no change. Else `cited = take(uniq_by_text(cited ++ [cite]), 6)`, `chat_open = true`. Does not patch, so the URL does not gain `chat=1` and the next patch will recompute `chat_open` from the URL.
12. **`drop_context {i}`**: remove `cited[i]`.
13. **`new_chat`**: `Chat.create_conversation(work.id, mode)` (new whole-draft conversation in the current mode) then `switch_to`.
14. **`switch_chat {id}`**: `Chat.get_conversation(work.id, arg_int(id))`; nil -> no change; else `switch_to`.
15. **`delete_chat {id}`** (× button; `data-confirm="Delete this thread and everything said in it?"`): fetch the conversation, `Chat.delete_conversation` (messages go with it), then `Chat.get_or_create_conversation(work.id)` (latest remaining, or a new one) and `switch_to` it. Failure -> no change.
    `switch_to(convo)` assigns `conversation`, `history = Chat.history(convo.id)`, `mode = convo.mode`, `focus = nil`, `cited = []`, `loading = false`, `chat_open = true`, `threads_list` refreshed. No patch.
16. **`set_mode {mode}`** (mode tabs): `Chat.set_mode(conversation, mode)` (an invalid mode id makes the changeset fail and the process crashes on the `{:ok, _}` match); assign `conversation`, `mode`, `chat_open = true`. Guarded for non-owners.
17. **`send {message}`** (`#chat-form` submit; guarded for non-owners): `text = trim(message)`. Blank or `loading` -> nothing. `not Chat.allowed?(user)` -> quota 0. Otherwise:
    `history = history ++ [user message]`; `Chat.append(conversation.id, "user", text)`; `window = Chat.context_window(history)` (last 20); assign `history`, `draft = ""`, `loading = true`, `mutter = Mutterings.some(8)`, `chat_open = true`,
    `quota = Chat.remaining(user)`, `cited = []`, `threads_list` refreshed; **push_event `"chat:clear"` `{}`**; `start_async(:ask, fn -> Editor.ask(work, window, provider:, mode:, focus:, cited:) end)` (the `focus` stays held afterwards; `cited` is consumed).

### The read (analysis) and graph

18. **`start_read`** (Read it / Read again; guarded): if `work.status == "read"` -> `Works.reset_read(work.id)` (delete every node, edge and graph event of the work, set every section `pending`). `Analysis.start(work, provider)` (detached task, section 6).
    Assign `work = %{work | status: "reading"}` (local copy), `graph_json = nil`, `stages = %{sections: :start, spine: :waiting, weave: :waiting}`, `started_at = now (unix seconds)`; `load_map`. No quota or key check server side (the button is hidden when `not llm_ready`).
19. **`build_graph`** (Build decision graph; guarded): `DecisionGraph.start(work, provider:)` (detached task); `graph_building = true`, `events = []`, `event_stats = nil`.
20. **`set_provider {provider}`** (`#provider-form` change; guarded as above): `Accounts.set_llm_provider(user, provider)`: for the deploy owner stores the choice on the user (error `:unknown_provider` for a name not in `LLM.available`); for anyone else a silent no-op that returns the unchanged user.
    `{:ok, user}` -> `provider = Accounts.provider_for(user)`, `llm_ready = LLM.configured?(provider)`, flash info "Backend: {provider or 'deploy default'}". `{:error, _}` -> no change.

### Threads pinned to a paragraph

21. **`open_thread {ref, section, quote?}`** (tick button sends `ref`, `section`=section id; the selection toolbar adds `quote`): `section_id = arg_int(section)`.
    Demo mode: `open_thread = %Conversation{id: 0, block_ref: ref, section_id:, anchor_kind: "span" if quote else "block", quote:, mode: "read"}` (never saved), `thread_history = []`, `thread_loading = false`.
    Otherwise `Chat.thread_for_block(work.id, section_id, ref, quote: quote)`: there is one thread per `(work, block_ref)`; created on first use (`anchor_kind` "span" if a quote was given else "block", mode "read"); if it exists and a different non-nil quote is given the thread's quote is replaced and `anchor_kind` set to "span".
    On `{:ok, thread}`: `open_thread = thread`, `thread_history = Chat.history(thread.id)`, `thread_loading = false`, `block_threads` refreshed. Error -> no change.
22. **`close_thread`**: `open_thread = nil`, `thread_history = []`, `thread_loading = false`.
23. **`resolve_thread`** ("settle"/"reopen"): only when `open_thread` is set: `Chat.resolve_thread(thread, is_nil(thread.resolved_at))` sets `resolved_at` to now or back to nil; `open_thread = updated`, `block_threads` refreshed. Otherwise no change.
24. **`thread_send {message}`** (`#thread-form-{id}` submit): `text = trim(message)`. No change if blank, `thread_loading`, no `open_thread`, or not mine. Demo: `Process.send_after(self(), :demo_reply, 1100)`, `thread_history += user message`, `thread_loading = true`, `mutter = Mutterings.some(8)`.
    Not allowed -> quota 0. Otherwise: `history = thread_history ++ [user message]`; `Chat.append(thread.id, "user", text)`; `focus = thread_focus(work, thread)`; `window = Chat.context_window(history)`; assign `thread_history`, `thread_loading = true`, `mutter = Mutterings.some(8)`, `quota` refreshed, `block_threads` refreshed;
    **push_event `"chat:clear"`**; `start_async(:thread_ask, Editor.ask(work, window, provider:, mode: thread.mode, focus:))`.
    `thread_focus` is `%{kind: "passage" if thread.quote else "paragraph", title: "A thread pinned to one place in the draft", body: "The writer opened this thread on a single {passage|paragraph}. Stay on it. Quote it back, say what it is doing and not doing, and propose what would have to change — in their terms, without writing the replacement.", quote: thread.quote, sections: [the thread's section, loaded by id]}`.

### Rewrites and edits of the prose

25. **`suggest_rewrite {text, ref}`** (toolbar; `ref` = block ref of the end of the selection). Checks in order: not mine -> flash error "This draft is someone else's."; demo -> `Process.send_after(self(), :demo_rewrite, 1200)` and set the in-flight state below; `not Chat.allowed?` -> quota 0; already `rewriting` -> no change; otherwise set the state and run the model.
    In-flight state: `rewriting = true`, `mutter = Mutterings.some(8)`, `rewrite = nil`, `preview = nil`, `steer = nil`, `rewrite_span = text`, `rewrite_ref = ref`. Model run: `start_async(:rewrite, fn -> Rewrite.propose(work, text, provider:) end)`.
26. **`steer_rewrite {steer}`** (`#rw-steer-form` submit, "Again"): `steer = trim(steer || "")`. Not mine -> flash error "This draft is someone else's."; `rewriting` or no `rewrite_span` or blank steer -> no change; demo -> `send_after(:demo_rewrite, 1200)`, `rewriting = true, mutter = Mutterings.some(8), rewrite = nil, preview = nil`;
    not allowed -> quota 0; else `rewriting = true`, `mutter = Mutterings.some(8)`, `rewrite = nil`, `preview = nil`, `steer = steer`; `start_async(:rewrite, Rewrite.propose(work, rewrite_span, provider:, steer:))`.
27. **`preview_rewrite {i}`** (Hover hook): if `rewrite` is set and candidate `i` exists -> `preview = %{original: rewrite.original, text: candidate.text}`; else no change.
28. **`clear_preview`**: `preview = nil`.
29. **`close_rewrite`**: `rewrite = nil`, `preview = nil`, `rewriting = false`, `rewrite_ref = nil`. It does not cancel the model task; a later result still sets `rewrite` (the panel stays hidden because `rewrite_ref` is nil, but paragraphs named in `rewrite.covers` will show the dimmed `rewriting` class until something clears it).
30. **`apply_rewrite {i}`** (the "replace the passage with this →" span; `data-confirm="Replace the selected passage with this version? It goes in the Changes tab and the draft's git history, so it can be got back."`): proceeds only if mine, not demo, `rewrite` is set and candidate `i` exists; otherwise silently nothing.
    `section = Works.get_section(work.id, rewrite.section.ordinal) || rewrite.section` (fresh copy). `Works.replace_block(section, rewrite.original, chosen.text, origin: "rewrite", note: chosen.move)`:
    * `{:ok, %{superseded: n}}`: `rewrite = nil, preview = nil, rewrite_ref = nil, rewrite_span = nil, steer = nil, applied = %{before: original, after: chosen.text}`; `reload_work`; `load_page`; `commit_draft(origin "rewrite")` (below); flash info "Replaced. " + (`n > 0` ? `supersede_note(n)` : "It is in the Changes tab if you want it back.").
    * `{:error, :moved}`: `rewrite = nil, preview = nil`, `load_page`, flash error "That passage changed underneath the rewrite. Nothing was replaced."
    * other error: flash error "Could not replace it: {inspect(reason)}".
    `supersede_note(1)` = "One note was about the line you changed. It is greyed, not gone."; `supersede_note(n)` = "{n} notes were about lines you changed. They are greyed, not gone."
    **`Works.replace_block(section, old, new, origin:, note:)` contract**: `new` is trailing-trimmed and reflowed to one sentence per line; blank -> `{:error, :empty}`; equal to `old` -> `{:ok, %{section, superseded: 0}}` with no write; `old` not a substring of `section.body` -> `{:error, :moved}`; else in one transaction: replace the first occurrence in `section.body`, update `section.body` and `word_count`, mark every node of the section whose quote no longer verifies against the new body `status = "superseded"` (counted as `superseded`), insert a Revision `{seq, before: old, after: new, origin, note, section_ordinal}`, and rebuild `work.body` as the sections joined by blank lines (updating `word_count`, `updated_at`).
31. **`edit_block {ref, seed?}`** (a paragraph click via the Selection hook, or "or edit it first →" which sends `ref=@block_ref` and `seed=candidate text`): not mine -> no change. `block = text of the block with that ref in @page` (or `""`).
    With a non-empty `seed`: if a `rewrite` is set, `Rewrite.place(block, rewrite.original, seed)`; `:not_here` -> flash error "That rewrite covers more than this paragraph, so it cannot be dropped into it. Copy the version you want, or select inside one paragraph and rewrite again." and no state change; if no rewrite is set the box is seeded with `seed` verbatim.
    Without a seed: seeded with `block`. On success: `editing = ref`, `edit_text = text`, `rewrite = nil`, `preview = nil` (`rewriting` and `rewrite_ref` are left alone).
32. **`cancel_edit`**: `editing = nil`, `edit_text = nil`.
33. **`save_block {text}`** (`#edit-{ref}` submit): demo -> `editing = nil, edit_text = nil`, flash info "Nothing was saved — the walkthrough does not touch your draft." Otherwise `save_block_for_real`: requires mine, `editing` set, and the block+section found in `@page` for that ref (the section struct is the one loaded with the page, not re-fetched);
    `Works.replace_block(section, block, text, origin: origin(a), note: rewrite_note(a))`. `origin(a)` is `"rewrite"` if `a.rewrite` is a map, else `"edit"`; `rewrite_note` is the previewed candidate's `move` when both `rewrite.candidates` and `preview.move` exist. Because `edit_block` clears `rewrite` and `preview` before the box opens, both are effectively always `"edit"` and nil in practice; the rewrite-origin branches are dead code, so a saved seeded candidate is recorded as an edit.
    * success `{:ok, %{superseded: n}}`: `editing = nil, edit_text = nil, applied = %{before: block, after: text}`; `reload_work`; `load_page`; `commit_draft(origin)`; flash info `supersede_note(n)` if `n > 0` (no flash otherwise).
    * `{:error, :empty}`: flash error "An empty paragraph is a deletion. Select it and cut it instead."
    * `{:error, :moved}`: `editing = nil, edit_text = nil`, `load_page`, flash error "That paragraph changed underneath the edit. Nothing was saved."
    * anything else (including not mine, or no `editing`): `editing = nil, edit_text = nil`.
34. **`dismiss_applied`**: `applied = nil`. (The applied box appears under a block when `landed?(applied, block)`: `String.contains?(block.text, first 80 chars of applied.after)`. Because the stored text was reflowed to one sentence per line while `applied.after` is what was submitted, the box can fail to appear when they differ in whitespace.)

`commit_draft(socket, assigns, origin)`: if `Marginalia.Git.enabled?()` (a configured repo root), start a fire-and-forget task under `Marginalia.TaskSupervisor`:
`Git.commit(work, "{origin}: {work.title}", author: "{email} <{email}>")`. Always returns `:ok`. It captures the `work` from the socket assigns at the time (after `reload_work`).

### Summaries and relating drafts

35. **`summarise {ordinal}`** (per-section button): not mine -> flash error; demo -> flash info "The walkthrough does not call the model."; not allowed -> quota 0; else `n = String.to_integer(ordinal)`, `Works.get_section(work.id, n)`; nil -> no change; else `summarising += n`; `start_async({:summary, n}, Summary.run(section, provider:))`.
36. **`summarise_document`**: not mine -> flash error; demo -> the same flash info as above; not allowed -> quota 0; already `doc_running` -> no change; else `doc_running = true`; `start_async(:document, Document.run(work, provider:))`.
37. **`compare_summary`** ("Draft it and compare" / "Relate them again"): not mine -> flash error. Else `Runs.start({:work, work.id}, :compare, fun)` where `fun` calls `Document.compare(user_id, work, provider:, on_stage: fn stage -> Runs.progress(key, stage: stage) end)` and returns `{:compared, link.id}` or `{:error, reason}`.
    `{:ok, _}` -> `comparing = "Drafting the summary"`. `{:error, {:already_running, kind}}` -> flash error "A {kind} pass is already running on this draft." `Document.compare` creates (or reuses) the condensation draft (`Document.to_draft`), reads it with `Analysis.run` if it has no nodes (stage string "reading the summary"), `Links.get_or_create`, announces stage "relating", then runs `Linker.run`.
38. **`summaries_to_draft`** ("Open as a draft"): not mine -> flash error "This draft is someone else's."; `Document.to_draft(user_id, work)`:
    `{:ok, draft}` -> flash info "Opened the summaries as a draft of their own." and navigate to `/works/{draft.slug}`; `{:error, :nothing_summarised}` -> flash error "Summarise at least one section first."; other error -> flash error "Could not make a draft: {inspect(reason)}".
    (`to_draft` creates a new Work titled "{title} — in summary" derived from this one, body = overview + a `## N. Title` block per summarised section + the guidelines.)
39. **`link_to {id}`** (link menu rows): requires mine; `other = Works.get_work(user.id, arg_int(id))` (must be the same user's own draft); `Links.get_or_create(work.id, other.id)` (error `:same_work` for the same draft). If `link.status != "linking"` -> `Analysis.Linker.start(link, provider)` (detached task). Assign `linking? = false`; navigate to `/links/{link.id}?lead={work.slug}`. Any failure -> flash error "That draft can't be linked."

### Walkthrough

40. **`start_walk`** ("Show me"): `walk = Walkthrough.steps(view, mine?: mine?)`, `demo = true`, `tour = nil`; then `mark_walk_seen`: if connected, and the view is in `Walkthrough.views()` (`["read"]`), and the user has not seen `"walk:read"` -> `Accounts.mark_tour_seen(user, "walk:read")`.
41. **`walk_reset`** (last step): clear `open_thread`, `thread_history = []`, `thread_loading = false`, `rewrite = nil`, `rewriting = false`, `rewrite_ref = nil`, `preview = nil`, `editing = nil`, `edit_text = nil`, `only = nil`; `load_page`.
42. **`end_walk`** ("end"): `walk = []`, `demo = false`, and the same clears as above except `only`, with no `load_page`.

While `demo == true`: `open_thread` uses an unsaved struct, `thread_send` and `suggest_rewrite`/`steer_rewrite` answer from fixtures via `Process.send_after`, `summarise`/`summarise_document` flash instead of calling the model, `save_block` discards, `apply_rewrite` does nothing. The permission checks run first even in demo.

### Push events from server to client

Only `push_event("chat:clear", %{})`, from `send` and `thread_send`.

---

## 6. Background work, async results, PubSub, timers

There is **no token streaming**: every model reply arrives whole. While `loading`, `thread_loading` or `rewriting` is true the UI shows the `mutter` component: a rotating in-character line (from `@mutter`, 3 s each with a fade, handled entirely client side by `.Rotate`) in front of three pulsing dots (`span.mg-dot` with `animation-delay` 0, .18s, .36s). `@mutter` is a single assign, so starting a second kind of wait replaces the lines used by the first; there is no per-indicator list. Nothing about it crosses the socket while the model works.

### `start_async` tasks (linked to the socket; if the socket closes the task and its result are lost, though the user's message has already been persisted)

| name | started by | function | on result |
|---|---|---|---|
| `:ask` | `send` | `Editor.ask(work, window, provider:, mode:, focus:, cited:)` -> `{:ok, reply_markdown}` \| `{:error, reason}` | `{:ok,{:ok,reply}}`: `Chat.append(conversation.id, "assistant", reply)`; `history += %{"role"=>"assistant","content"=>reply}`; `loading = false`. `{:ok,{:error,reason}}`: `history += assistant message "I hit an error: {reason}"` (not persisted), `loading = false`. `{:exit, reason}`: assistant message "Something crashed: {inspect(reason)}", `loading = false`. |
| `:thread_ask` | `thread_send` | `Editor.ask(work, window, provider:, mode: thread.mode, focus: thread_focus)` | ok: if `open_thread` is set, `Chat.append(open_thread.id, "assistant", reply)` (the **currently open** thread, whichever it is); `thread_history += assistant message`; `thread_loading = false`; `block_threads` refreshed. error or exit: `thread_loading = false`, flash error "That did not go through: {inspect(reason)}". |
| `:rewrite` | `suggest_rewrite`, `steer_rewrite` | `Rewrite.propose(work, span, provider:, [steer:])` | `{:ok,{:ok,result}}`: `rewrite = result`, `rewriting = false`. `{:ok,{:error,reason}}`: log a warning with the first 300 chars of the span, `rewriting = false`, flash error `rewrite_error(reason)`: `:not_in_draft` "That selection is not in the draft, character for character."; `{:span_too_long, words, max}` "That is {words} words. Rewrites go up to {max} — past that, split it and take the part you actually want reworked."; `:no_candidates` "Nothing came back that was different from what you wrote."; other "That did not go through: {inspect(other)}". `{:exit, reason}`: `rewriting = false`, flash error "That did not go through: {inspect(reason)}". |
| `:document` | `summarise_document` | `Document.run(work, provider:)` -> `{:ok, doc}` \| `{:error, reason}` | `doc_running = false`; ok: `reload_work`, `load_page`, `document = Document.get(work.id)`, `commit_draft("summarised")`, flash info "The whole document has been read."; error: flash error "Could not summarise the document: {inspect(reason)}"; exit: flash error "The document pass crashed: {inspect(reason)}". |
| `{:summary, n}` | `summarise` | `Summary.run(section, provider:)` | `summarising -= n`; ok: `load_page`; error: flash error "Could not summarise section {n}: {inspect(reason)}"; exit: flash error "The summary crashed: {inspect(reason)}". |

Each is guarded against double-start by its own flag (`loading`, `thread_loading`, `rewriting`, `doc_running`, membership in `summarising` only through the disabled button).

### Detached tasks (survive the socket)

* `Analysis.start(work, provider)` = `Task.Supervisor.start_child(Marginalia.TaskSupervisor, ...)` running the three-pass read. Progress is announced on PubSub topic `"work:{work.id}"`: `{:status, "reading"}`, `{:stage, :sections, :start}`; per section `{:section, section_id, "reading"}`, then `{:section, section_id, "read" | "failed"}` and `{:nodes, section_id, count}` (sections read concurrently); `{:stage, :sections, :done}`, `{:stage, :spine, :start}`, `{:synthesis, :done}`, `{:stage, :spine, :done}`, `{:stage, :weave, :start}`, then `{:stage, :weave, :done | :failed}`, `{:weave, n}`, finally `{:status, "read"}`. The task updates the database; the page only re-reads.
* `DecisionGraph.start(work, provider:)`: broadcasts on the same topic `{:graph, :building}`, `{:graph, :event}` (after every recorded tool call), `{:graph, :narrative_done}`, and `{:graph, :done}` or `{:graph, :failed}`.
* `Analysis.Linker.start(link, provider)`: broadcasts on `"link:{id}"` (read by the link page, not this one).
* `commit_draft`: a fire-and-forget git commit task.
* `Runs.start({:work, id}, :compare, fun)`: a task under the supervisor tracked in an ETS table by key, one run per key. A GenServer (`Marginalia.Runs`) holds `%{kind, done, total, stage, pid, started_at}`, broadcasts `{:run, :started, run}` on start, `{:run, :progress, run}` when the task calls `Runs.progress(key, stage: "...")`, and `{:run, :done, kind, result}` or `{:run, :crashed, kind, reason}` when it ends (the entry is deleted first). A page that mounts reads `Runs.get/1` straight from ETS.

### `handle_info` (everything the page receives)

| message | effect |
|---|---|
| `{:run, :started, run}`, `{:run, :progress, run}` | `comparing = comparing(run)`: for `%{kind: :compare, stage: s}` with `s` a string -> `String.capitalize(s)` ("Reading the summary", "Relating"; capitalize lower-cases the rest); `%{kind: :compare}` without a stage -> "Drafting the summary"; any other run -> nil |
| `{:run, :done, :compare, {:compared, link_id}}` | `comparing = nil`, `summary_link = link_id`, flash info "Drafted, read and related. They are side by side now." |
| `{:run, :done, :compare, {:error, reason}}` | `comparing = nil`, flash error "Could not compare them: {inspect(reason)}" |
| `{:run, :crashed, :compare, _}` | `comparing = nil`, flash error "The comparison crashed. Anything it finished is saved." |
| any other `{:run, ...}` (3- or 4-tuple) | ignored |
| `{:stage, which, state}` | `stages[which] = state`; then `live_refresh` |
| `{:status, _}`, `{:section, _, _}`, `{:nodes, _, _}`, `{:synthesis, :done}` | `live_refresh` |
| `{:graph, :done}` | `graph_building = false`; `reload_work`; `load_graph` (rebuilds `graph_json`/`graph_stats`); `load_trace` |
| `{:graph, :event}` | `load_trace` only if `view == :trace` |
| `{:graph, :failed}` | `graph_building = false` |
| other `{:graph, _}` | ignored |
| `:demo_reply` (only when `demo`) | `thread_loading = false`; `thread_history += assistant message` = the fixture answer from `Walkthrough.exchange()` |
| `:demo_rewrite` (only when `demo`) | `rewriting = false`; `rewrite = Walkthrough.rewrite()` |
| anything else (`{:weave, n}`, ...) | ignored |

`live_refresh` = `reload_work` (re-fetch the work, `revision_count`, and `load_map`: sections, node lists, counts, revisions) and, only when `view == :read`, `load_page`. So while a read runs, the counts, the progress detail, the section badges and — on the read tab — the margin notes update with each message. `work.status` changes through the re-fetch, which is how the page moves from the progress strip to the finished read (and why the status message needs no payload).

### Timers

Server: `Process.send_after(self(), :demo_rewrite, 1200)` and `Process.send_after(self(), :demo_reply, 1100)` in walkthrough mode only. There is **no polling**; all liveness comes from PubSub.
Client: `.Clock` 1 s interval, `.Walk` 250 ms re-measure interval and a 550 ms delay before each step action, `.Share` 1.4 s label reset, `.Hover` 80 ms debounce on mouse leave.


---

## 7. Graph controller endpoints, and the text the page embeds

Routes (pipeline `[:browser, :ensure_user_or_guest]`, so a guest user exists but is not otherwise checked):

| method + path | action | auth |
|---|---|---|
| `GET /works/:id/graph.json` | `GraphController.json` | slug only: `Works.get_by_slug(id)`; nil -> `404`, body `not found` (text/plain) |
| `GET /works/:id/graph.dot` | `GraphController.dot` | slug only, same 404 |
| `GET /works/:id/trace.json` | `GraphController.trace` | slug **and** `work.user_id == current user id` (the draft's owner, not the deploy owner); otherwise `404 not found`. The trace "does not travel with the link". |

`:id` here is the slug. The Trace tab link `trace.json` is only shown to the deploy owner; the endpoint itself admits the draft's owner.

Download filename: `slug(title)` = lowercase title, runs of characters outside `[a-z0-9]` replaced by `-`, leading/trailing `-` trimmed, cut to the first 50 characters (after trimming, so the result can end in `-`), `"draft"` if empty. Then
`content-disposition: attachment; filename="{slug}-graph.json"` / `"{slug}-graph.dot"` / `"{slug}-trace.json"`.

### `graph.json` — `Graph.to_json(work)` = `Jason.encode!(export(work), pretty: true)`, `Content-Type: application/json; charset=utf-8`, status 200

```
{
  "work": {
    "id": 12, "title": "...", "intent": "..."|null, "words": 18342, "sections": 9,
    "status": "read", "first_impression": "..."|null,
    "exported_at": "2026-10-14T09:30:00.123456Z"          // DateTime.utc_now() |> to_iso8601, microsecond precision
  },
  "nodes": [
    {
      "id": 301,
      "node_type": "goal",                  // deciduous name: spine->goal, beat->action, thread->observation, question->decision; any other type unchanged
      "marginalia_type": "spine",           // the native type: spine|beat|thread|question|note, or the deciduous types for nodes made by the decision-graph pass (goal|option|decision|action|outcome|observation|revisit)
      "title": "...",
      "description": "..."|null,            // body, plus (when quote is non-blank) "\n\nSources:\n\n- \"<quote with newlines turned to spaces>\"" — i.e. [body, "Sources:", "- \"quote\""] minus blanks, joined by "\n\n"; with no quote it is just body
      "body": "..."|null, "quote": "..."|null, "narrative": "..."|null,
      "section": "Section title"|null, "section_ordinal": 3|null,
      "status": "pending",                  // node.status, "pending" if null
      "created_at": "2026-10-14T09:12:04Z",
      "metadata_json": "{\"branch\":\"section-3\",\"section\":\"Section title\",\"narrative\":null,\"ordinal\":0,\"status\":\"pending\",\"anchored\":true}"
         // a JSON *string*. branch = "section-{ordinal}" if the node has a section, else "spine" for type spine, else "{node_type}s"
         // (e.g. "threads"); anchored = quote is non-nil and non-empty. Key order as listed.
    }
  ],
  "edges": [
    { "id": 77, "from_node_id": 301, "to_node_id": 302, "edge_type": "leads_to",   // leads_to, or follows, develops, pays_off, requires, tension, realises, asks_about, ...
      "weight": 1.0, "rationale": "..."|null, "created_at": "..." }
  ],
  "themes": [],
  "node_themes": []
}
```

The same `Graph.export(work)` map, JSON-encoded compactly (not pretty), is what the page puts in `data-graph` on `#graph-canvas`; the `LaneTree` hook reads `nodes[].id/title/marginalia_type/metadata_json/section/section_ordinal/body/quote/narrative/status` and `edges[].id/from_node_id/to_node_id/rationale`.
Nodes are ordered by `ordinal, id`; edges by the data layer's `list_edges` order (the lane tree itself re-sorts edges by `id`).
`Graph.stats(work)` for the header = `%{nodes: count, edges: count, anchored: count where metadata anchored == true, by_type: %{marginalia_type => count}}`.

### `graph.dot` — `Graph.to_dot(work)`, `Content-Type: text/vnd.graphviz; charset=utf-8`

```
digraph marginalia {
  rankdir=TB;
  node [shape=box, style=rounded];
  n301 [label="<title>", color="#8a3324"];
  n302 [label="<title>", color="#166534"];
  n301 -> n302 [style=solid, label="follows"];
  n301 -> n305 [style=dashed, label="develops"];
}
```

Lines are joined with `\n`, no trailing newline. Node line: `  n{id} [label="{escaped title}", color="{colour}"];` where the title has `\` -> `\\`, `"` -> `\"`, newlines -> space, then is cut to 90 characters (cut after escaping).
Colour by `marginalia_type`: goal `#8a3324`, option `#b45309`, decision `#1e3a8a`, action `#166534`, outcome `#0891b2`, observation `#6b665e`, revisit `#7c2d92`, spine `#8a3324`, beat `#166534`, thread `#0891b2`, question `#7c2d92`, anything else `#9a948a`.
Edge line: `  n{from} -> n{to} [style={solid|dashed}, label="{edge_type}"];` with `solid` only when `edge_type == "follows"`, else `dashed`; an edge whose endpoint is not in the node list is omitted. (The decision-graph pass writes `follows` edges for its chain; the read's own spine chain uses `leads_to`, which therefore prints dashed — faithfully reproduce.) Nodes first, then edges, in export order.

### `trace.json` — `Content-Type: application/json; charset=utf-8`, pretty-printed

```
{
  "work": { "id": 12, "title": "..." },
  "stats": { "calls": 41, "refused": 3, "by_tool": {"add_node": 30, "link": 9, "set_status": 2},
             "refusals": { "<refusal kind>": 2, ... } },
  "events": [
    { "seq": 1, "narrative": "..."|null, "tool": "add_node",
      "args": <parsed JSON of the stored args string, or the raw string if it does not parse, or null>,
      "result": <same treatment>, "ok": true, "at": "2026-10-14T09:12:04Z" }   // at = event inserted_at
  ]
}
```

`stats.refusals` is `Enum.frequencies_by(refused events, refusal_kind)`: the refusal kind is derived from the stored result (an error string classification inside `Works`); treat it as an opaque grouping key.

### Graph source (verbatim, for exactness)

```elixir
  @type_map %{
    "spine" => "goal",
    "beat" => "action",
    "thread" => "observation",
    "question" => "decision"
  }

  @doc "The whole graph for one work, ready to encode as JSON."
  def export(work) do
    sections = Works.list_sections(work.id)
    section_by_id = Map.new(sections, &{&1.id, &1})
    nodes = Works.list_nodes(work.id)
    edges = Works.list_edges(work.id)

    %{
      work: %{
        id: work.id,
        title: work.title,
        intent: work.intent,
        words: work.word_count,
        sections: length(sections),
        status: work.status,
        first_impression: work.first_impression,
        exported_at: DateTime.utc_now() |> DateTime.to_iso8601()
      },
      nodes: Enum.map(nodes, &node_json(&1, section_by_id)),
      edges: Enum.map(edges, &edge_json/1),
      # no theme layer yet — emitted empty so the explorers, which expect the
      # keys, render rather than crash
      themes: [],
      node_themes: []
    }
  end

  def to_json(work), do: work |> export() |> Jason.encode!(pretty: true)

  defp node_json(n, section_by_id) do
    section = n.section_id && Map.get(section_by_id, n.section_id)

    branch =
      cond do
        section -> "section-#{section.ordinal}"
        n.node_type == "spine" -> "spine"
        true -> n.node_type <> "s"
      end

    %{
      id: n.id,
      node_type: Map.get(@type_map, n.node_type, n.node_type),
      # the native type is kept too, so a round trip back into Marginalia
      # doesn't have to guess
      marginalia_type: n.node_type,
      title: n.title,
      description: description(n),
      # the viewer wants these apart, not glued into one string
      body: n.body,
      quote: n.quote,
      narrative: n.narrative,
      section: section && section.title,
      section_ordinal: section && section.ordinal,
      status: n.status || "pending",
      created_at: n.inserted_at,
      metadata_json:
        Jason.encode!(%{
          branch: branch,
          section: section && section.title,
          narrative: n.narrative,
          ordinal: n.ordinal,
          status: n.status,
          anchored: n.quote not in [nil, ""]
        })
    }
  end

  # The explorers render a trailing "Sources:" block as a quieter footnote,
  # which is exactly what the anchoring quote is.
  defp description(%{body: body, quote: q}) when is_binary(q) and q != "" do
    [body, "Sources:", "- \"#{String.replace(q, "\n", " ")}\""]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp description(%{body: body}), do: body

  defp edge_json(e) do
    %{
      id: e.id,
      from_node_id: e.from_id,
      to_node_id: e.to_id,
      edge_type: e.edge_type,
      weight: 1.0,
      # the model's own reason for drawing this edge — the commentary that
      # makes the graph readable instead of merely shaped
      rationale: e.rationale,
      created_at: e.inserted_at
    }
  end

  @doc """
  Graphviz DOT, for anyone who would rather look at it in a tool than a tab.
  """
  def to_dot(work) do
    %{nodes: nodes, edges: edges} = export(work)
    by_id = Map.new(nodes, &{&1.id, &1})

    lines =
      ["digraph marginalia {", "  rankdir=TB;", "  node [shape=box, style=rounded];"] ++
        Enum.map(nodes, fn n ->
          ~s(  n#{n.id} [label="#{escape(n.title)}", color="#{colour(n.marginalia_type)}"];)
        end) ++
        Enum.map(edges, fn e ->
          style = if e.edge_type == "follows", do: "solid", else: "dashed"

          if Map.has_key?(by_id, e.from_node_id) and Map.has_key?(by_id, e.to_node_id) do
            ~s(  n#{e.from_node_id} -> n#{e.to_node_id} [style=#{style}, label="#{e.edge_type}"];)
          end
        end) ++ ["}"]

    lines |> Enum.reject(&is_nil/1) |> Enum.join("\n")
  end

  defp colour("goal"), do: "#8a3324"
  defp colour("option"), do: "#b45309"
  defp colour("decision"), do: "#1e3a8a"
  defp colour("action"), do: "#166534"
  defp colour("outcome"), do: "#0891b2"
  defp colour("observation"), do: "#6b665e"
  defp colour("revisit"), do: "#7c2d92"
  defp colour("spine"), do: "#8a3324"
  defp colour("beat"), do: "#166534"
  defp colour("thread"), do: "#0891b2"
  defp colour("question"), do: "#7c2d92"
  defp colour(_), do: "#9a948a"

  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", " ")
    |> String.slice(0, 90)
  end

  @doc "Counts for the graph view header."
  def stats(work) do
    %{nodes: nodes, edges: edges} = export(work)

    %{
      nodes: length(nodes),
      edges: length(edges),
      anchored: Enum.count(nodes, &(Jason.decode!(&1.metadata_json)["anchored"] == true)),
      by_type: Enum.frequencies_by(nodes, & &1.marginalia_type)
    }
  end
end
```

### Tour text (`Tour.for_view/1`; the `follow` entry belongs to the linked-drafts page and is not used here)

```elixir
  @tours %{
    read: %{
      title: "The page, with its notes in the margin",
      points: [
        "Every note sits beside the sentence that caused it. The highlight is the span it is anchored to, copied from your draft character for character.",
        "Everything is on by default. Beats are what the draft does, in order; Connections and Tensions are what crosses sections. Each filter leaves only that kind in the margin.",
        "Click and hold, then drag across any passage to select it. Three things come up: talk about that spot, ask for rewrites of it, or carry it into the chat.",
        "Move the pointer to the left edge of a paragraph and a thin line appears in the margin. Click it to start a thread pinned to that paragraph, which will still be there when you come back."
      ]
    },
    follow: %{
      title: "Two documents, read as one",
      points: [
        "The left is what you are reading. The right is the reference, and it is dimmed on purpose — it lights up only where it has something to say about the passage you are on.",
        "Scroll the left. The right is scrolled for you, and snaps to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again.",
        "The line drawn between them runs through the reason in the middle — left passage, why, right passage, which is the actual shape of the claim. Click the line to carry both passages into the chat.",
        "The filters leave one kind of relation in view: where the two documents disagree, where one answers the other, where one depends on the other.",
        "Stretches where the two have nothing to say to each other are folded away, with their size on the label. Nothing is deleted — open one and read it.",
        "Referencing… swaps which document sits in the margin, and swap sides reads the other one as the lead. The pair is symmetric and the two directions are genuinely different."
      ]
    },
    graph: %{
      title: "What leads to what",
      points: [
        "Every row is one move the draft makes. Hover a row and the panel on the right fills in with what it says — move down the list and read the whole draft without clicking anything.",
        "Click a row to keep it there. The panel then holds its type, the section it came from, your own sentence underneath it, and every node it follows from or leads to. Hovering something else only previews; the one you clicked comes back when you move away.",
        "A filled dot is anchored to a line in your draft. A hollow one is structural — the model's word for a move, with no single sentence behind it.",
        "Solid lines are the chain running down the page. Dotted ones cross sections: develops, pays off, requires, tension.",
        "Build decision graph runs the deciduous method over the whole draft — narratives first, then a goal / option / decision / action chain for each. It takes a few minutes and the Trace tab shows it happening."
      ]
    },
    spine: %{
      title: "The whole draft at once",
      points: [
        "The first impression is what a reader takes away, written before any of the detail.",
        "The spine is the chain everything hangs off. Each node shows where it actually happens, with your own words under it.",
        "Discuss opens the chat already holding that node and every section it touches, so you never re-explain which one you meant.",
        "The questions at the bottom each name something specific. They are attached to their paragraphs on the page."
      ]
    },
    threads: %{
      title: "What runs across sections",
      points: [
        "A thread is a pattern that spans the draft rather than happening in one place — carried, thin, or dropped.",
        "A dropped thread is usually the most useful thing on this page: something set up and never paid off.",
        "Each shows the beats it runs through. Discuss carries the whole lot into the chat."
      ]
    },
    trace: %{
      title: "What the model actually did",
      points: [
        "Every tool call made while building the graph, and what the server answered.",
        "The refusals are the point: a quote that was not in your draft, or a link that broke the flow rule. They are kept rather than hidden.",
        "It fills in live while a build runs."
      ]
    },
    prompts: %{
      title: "Every prompt, read out of the running code",
      points: [
        "Not retyped here — read from the modules that ran, so this page cannot drift from what actually happened.",
        "Each pass says which model it used and what it produces.",
        "The chat's three stances are at the bottom."
      ]
    }
  }
```

Tour card: `{title, points[]}`; `Accounts.seen_tour?` compares `to_string(view)` with the user's `seen_tours` list. `Tour.views/0` lists every key as strings.

### Walkthrough (read view only): steps and fixtures

`Walkthrough.steps(:read, mine?: true)` returns the list below in order; for a non-owner (`mine?: false`) steps with `owner: true` (ask, rewrite, edit) are dropped. Other views return `[]`.
`target` is a CSS selector the overlay spotlights; `act` is performed 550 ms after the step appears. Each step is serialised to JSON as written (atom keys become strings; `owner` appears only on owner steps).

```elixir
  @read [
    %{
      id: "margin",
      title: "The notes sit beside the line",
      body:
        "Every note is level with the sentence that caused it, and the highlight under the prose is the exact span it is anchored to — copied out of your draft character for character.",
      target: ".mg-read-rail .mg-note-slot",
      place: "left"
    },
    %{
      id: "filters",
      title: "The filter changes what the margin is about",
      body:
        "Watch the margin, not the tabs. Tensions leaves only the places the draft argues with itself. Beats is what it does, in order; Connections is what reaches across sections.",
      target: "#read-filters",
      place: "bottom",
      act: %{kind: "push", event: "set_only", params: %{"only" => "tensions"}}
    },
    %{
      id: "filters_back",
      title: "Everything, again",
      body:
        "Back to both passes at once, which is how it opens. The filter never removes a note from the draft — only from this view.",
      target: "#read-filters",
      place: "bottom",
      act: %{kind: "push", event: "set_only", params: %{"only" => "all"}}
    },
    %{
      id: "map",
      title: "A map of the draft, drawn to scale",
      body:
        "Each block is sized by its section's word count, so the shape of the thing is visible before you have read a line of it. Click any block to land there.",
      target: ".mg-map",
      place: "right",
      act: %{kind: "client", name: "open_map"}
    },
    %{
      id: "thread",
      title: "A thread pinned to one paragraph",
      body:
        "Move the pointer to the left edge of any paragraph and a hairline appears in the gutter. Clicking it opens a conversation about that paragraph, already holding it — and it is still there when you come back.",
      target: ".mg-read-body .mg-block",
      place: "right",
      act: %{kind: "client", name: "open_thread"}
    },
    %{
      id: "ask",
      owner: true,
      title: "Ask about that spot",
      body:
        "No re-explaining which bit you meant. The paragraph goes in as the subject of the question.",
      target: ".mg-thread-panel",
      place: "right",
      act: %{kind: "client", name: "ask_thread"}
    },
    %{
      id: "select",
      title: "Or select a passage",
      body:
        "Click and hold, then drag across any run of text. Three things come up at the end of it: talk about that spot, ask for rewrites of it, or carry it into the chat.",
      target: ".mg-read-body .mg-block",
      place: "right",
      act: %{kind: "client", name: "select"}
    },
    %{
      id: "rewrite",
      owner: true,
      title: "Three rewrites, each with its cost",
      body:
        "The one place it writes, and it only opens from your side. Hover a candidate to see it over your own line as a diff. Nothing is ever applied.",
      target: ".mg-rewrite",
      place: "right",
      act: %{kind: "client", name: "rewrite"}
    },
    %{
      id: "edit",
      owner: true,
      title: "Then answer it in your own words",
      body:
        "Click into any paragraph and it opens for editing, in the markdown you wrote it in. Start from a candidate or ignore them all. Saving is switched off for the tour.",
      target: ".mg-read-body .mg-block",
      place: "right",
      act: %{kind: "client", name: "edit"}
    },
    %{
      id: "done",
      title: "That is the read view",
      body:
        "The thread, the rewrite and the edit you just saw were never written down, and no model was called for any of it. Your draft is exactly as you left it. The ? in the header runs this again.",
      target: nil,
      place: "centre",
      act: %{kind: "client", name: "reset"}
    }
  ]
```

Fixtures returned instead of calling the model:

```elixir
  @doc """
  What the tour shows instead of calling the model.

  Deliberately about a sample sentence rather than the writer's own. A
  fixture dressed up as a reading of the paragraph in front of them would
  teach them to distrust every real note on the page, which is the whole
  asset.
  """
  def rewrite do
    %{
      sample: true,
      reading:
        "The line is doing two jobs: announcing that something changed, and holding back what it was.",
      original:
        "It was, in a sense, the beginning of something that would eventually change everything about the way she saw her father.",
      section: nil,
      # the same atom keys `Marginalia.Rewrite.clean/2` produces, so the panel
      # renders a fixture through exactly the code path a real answer takes
      candidates: [
        %{
          text: "It changed how she saw her father.",
          move: "Cuts the gloss",
          cost: "Loses the narrator's distance from the moment"
        },
        %{
          text: "She would not see her father the same way again, and this was where it started.",
          move: "Puts the change last",
          cost: "Slower into the paragraph that follows"
        },
        %{
          text: "She watched him back the car out, and something in it went.",
          move: "Hands it to the image",
          cost: "Only works if the car is already in the scene"
        }
      ]
    }
  end

  @doc "The question the tour types into the thread, and the answer it gets."
  def exchange do
    {"What is this paragraph actually doing?",
     """
     Two things, and the second one is quieter.

     It is placing the scene — where everyone is standing, and how long they have been
     standing there. And it is establishing that nobody in the room will say the thing
     out loud, which the rest of the section then depends on.

     The risk is that the second job is carried entirely by one clause. If a reader
     skims it, the next three pages read as people being oddly polite.

     *(A fixed example. The tour never calls the model, so this is not a reading of
     your paragraph.)*
     """}
  end
end
```

`Walkthrough.rewrite()` is assigned to `rewrite` unchanged. **Probable latent bug in the source (found by reading; not executed, and `test/marginalia/walkthrough_test.exs` checks only the candidates' keys, never renders the panel with the fixture):** the fixture map has keys `sample, reading, original, section, candidates` only,
but `rewrite_panel` reads `@rewrite.spans_blocks` (two places). `map.key` on a missing key raises `KeyError`, and a raise during a LiveView render drops the socket, so the walkthrough's "rewrite" step
(and any `:demo_rewrite` result) should crash the page as the source stands (`grep spans_blocks` finds it set only in `Rewrite.propose`). The moduledoc claims a test keeps the fixture and `Rewrite.clean` in step, but that test only compares candidate keys.
A port should give the fixture `spans_blocks: false` and `covers: []`; do not copy the crash. `rewriting?/3` already tolerates a missing `covers` (it falls through to comparing `rewrite_ref`).

---

## 8. `WorkController.create` — the no-JavaScript upload path

`POST /works/new` (pipeline `[:browser, :ensure_user_or_guest]`; CSRF-protected, so the form carries `_csrf_token`). Exists because `/works/new` is a LiveView whose form is `method="post"`; when the socket is dead the browser submits it here.
The LiveView route for the same path is `GET /works/new` (`WorkLive.New`, out of scope).

Params: `work[title]`, `work[intent]`, `work[body]` (strings; any may be missing). No file field exists on this path.

1. `Upload.prepare(title, body, intent)`:
   * `word_count(body)` = number of whitespace-separated tokens (`split(~r/\s+/, trim: true)`); 0 -> `{:error, :empty}`; more than **120,000** -> `{:error, {:too_long, n}}`.
   * else `{:ok, %{"title" => trimmed title or "Untitled draft", "body" => body (unmodified), "intent" => trimmed intent or nil}}`.
2. `{:error, :empty}` -> re-render the form (below) with status **422** and the error
   "There's no text there yet — paste the draft into the box below. Attaching a file needs JavaScript, which is not running on this page."
3. `{:error, {:too_long, n}}` -> 422 and `"That's {n with thousands commas} words, and the limit is 120,000 for now. Split it and upload the first part."`
4. `{:ok, attrs}` -> `Works.create_work(current_user.id, attrs)` in one transaction:
   * Work changeset: casts `title, intent, body, status, ...`; `slug` = 16 random bytes, url-safe base64, no padding (generated once); `word_count` recomputed from body; requires `title` and `body`; `title` max length 200 (error text "should be at most 200 character(s)"); `word_count` must be > 0 (message "looks empty"); status default `"pending"`.
   * Sections: `Segmenter.split(body)` -> `[%{title, body}]` (deterministic, no model; drafts are normalised to one sentence per line on arrival), inserted with `ordinal` 1.., `word_count`, `status "pending"`. No sections -> `{:error, :no_sections}`.
   * Then `baseline_body` and `body` are both set to the sections' bodies joined with blank lines.
   * Success -> **302 redirect to `/works/{slug}`** (`redirect(conn, to: ...)`). The page then shows the confirm gate (`status == "pending"`).
   * `{:error, :no_sections}` -> 422 with "Couldn't find any text to split into sections."
   * `{:error, %Ecto.Changeset{}}` -> 422 with the first error: `traverse_errors` (placeholders `%{count}` etc. interpolated), flattened as `"{field} {message}"` for each field in map order, first one taken, then `String.capitalize` (which also lower-cases everything after the first letter) and a trailing "." — e.g. "Title can't be blank." (nil -> "That draft could not be saved.").
5. "Re-render rather than redirect": `again(conn, work_params, message)` = status 422, render `WorkHTML.new` with `work` (the submitted params map, so the box keeps the text) and `error`.

### `WorkHTML.new` (plain form, wrapped in `Layouts.app`)

```heex
  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl px-6 py-10">
        <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
          Upload a draft
        </h1>

        <div class="mt-5 border-l-2 border-[var(--mg-accent)] pl-3 py-1.5 text-[0.85rem]">
          {@error}
        </div>

        <p class="mg-prose mt-4 text-[0.95rem] text-[var(--mg-dim)]">
          This page is running without its live connection, so it is the plain
          version: paste and press Continue. Reload to get the full one back,
          but copy your text somewhere first — a reload will empty this box.
        </p>

        <form action={~p"/works/new"} method="post" class="mt-6 space-y-5">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

          <.input
            id="work_title"
            name="work[title]"
            value={@work["title"]}
            label="Title"
            placeholder="Working title is fine"
          />

          <.input
            id="work_intent"
            name="work[intent]"
            value={@work["intent"]}
            type="textarea"
            rows="2"
            label="In a sentence or two, what is this supposed to do to a reader?"
            placeholder="Optional — but it's what stops the notes being generic."
          />

          <.input
            id="work_body"
            name="work[body]"
            value={@work["body"]}
            type="textarea"
            rows="12"
            label="Paste the draft"
            placeholder="Paste the whole thing. Chapter headings or markdown headings help it divide the draft correctly."
          />

          <button type="submit" class="mg-btn">Continue</button>
        </form>
      </div>
    </Layouts.app>
    """
  end
```

`<.input>` for `type` text (default) renders `<div class="mg-field"><label for={id}><span class="mg-label block mb-1.5">{label}</span><input type="text" name id value class="mg-input" placeholder .../></label></div>`;
for `type="textarea"` the same shell with `<textarea id name rows class="mg-textarea" placeholder>{value}</textarea>`. Values are HTML-escaped. `{@error}` is shown inside the bordered `div` above the form. Flash comes from the connection.


---

## 9. Counts, and what is hard without LiveView

| thing | count |
|---|---|
| distinct `handle_event` names | 42 (plus one guard clause covering 5 of them for non-owners) |
| `handle_async` names | 5 (`:document`, `{:summary, n}`, `:rewrite`, `:thread_ask`, `:ask`) |
| `handle_info` message shapes | 11 handled + 1 catch-all (`{:run,...}` x5, `{:stage,...}`, `{:status|:section|:nodes|:synthesis}`, `{:graph,...}` x4, `:demo_reply`, `:demo_rewrite`) |
| PubSub subscriptions | 2 (`work:{id}`, `run:{:work, id}`), only when connected |
| `phx-hook` bindings | 15 (13 colocated in `show.ex`: Clock, LaneTree, Hover, Minimap, Steer, Deck, Editor, Selection, Share, SummaryVault, MarginNotes, StickToBottom, Composer; plus Rotate from `core_components.ex` and Walk from `walk.ex`) |
| function components | 19 in `show.ex` plus `mutter` in `core_components.ex` = 20 rendered by the page (`tab`, `confirm_gate`, `progress`, `stage`, `map_view`, `graph_pane`, `tour_card`, `grounded_node`, `changes_pane`, `diff_table`, `rewrite_panel`, `inline_thread`, `links_control`, `minimap`, `read_pane`, `deck`, `trace_pane`, `prompts_pane`, `chat_panel`) |
| server-pushed client events | 1 (`chat:clear`) |
| HTTP endpoints besides the page | 4 (`graph.json`, `graph.dot`, `trace.json`, `POST /works/new`) |

### The behaviours a port has to rebuild by hand

1. **Live patching with client state preserved.** The page re-renders after almost every event and every broadcast, and the DOM is patched, not replaced: the hooks' per-element state (the margin layout, the pinned peeks, the deck index, the minimap observer, the summary vault, typed text in `#rw-steer` and the textareas, scroll position of the chat) survives because the elements survive. A rewrite that swaps HTML wholesale loses focus, selection and half-typed text (the composer re-focuses itself on mount; the edit box and the steer box would be wiped). Needs a morphing diff keyed by element id (hence the many stable ids) plus `phx-update="ignore"` semantics for three regions.
2. **Server push without polling.** The read's progress strip, the margin filling in note by note, the trace filling in, the "Drafting the summary… / Relating…" button text and the settle of a model reply all arrive over one socket from PubSub and from detached tasks that outlive the page (and a `Runs` registry that a freshly loaded page consults). Needs an event channel per page with two topic subscriptions, a task runner independent of the connection, and a "what is running right now" lookup on load.
3. **The margin layout engine.** `MarginNotes` measures highlight positions, stacks notes without overlap, switches between a wide margin and a fold-into-the-text mode when the drawer opens, floats notes around an applied diff and follows scroll — and must re-run after every patch. The server decides nothing here, but the markup contract (ids `anchor-{ref}`, `data-anchor`, `.mg-note-slot`, the `collapsed` class) and the render-then-layout ordering are strict.
4. **Selection to anchor round trip.** A browser selection (with markup debris) is posted, verified server-side as a literal substring of the draft (`Selection.locate`, `Anchor.verify` normalisation), and mapped back to the paragraph refs it covers (`covers`) so the right paragraphs dim. Any change to how paragraphs are split or numbered (`s{ordinal}p{index}`) breaks every stored thread, note placement and revision.
5. **Flash and navigation inside a stateful page.** `push_patch(replace: true)` keeps the page process and state while updating the URL; `push_navigate` swaps to another page; flashes survive neither well. A port needs both semantics.
6. **Idempotent in-flight flags** (`loading`, `rewriting`, `thread_loading`, `doc_running`, `summarising`) that disable buttons and swallow duplicate submits, held in server state per page instance.

### Source quirks recorded above (reproduce or fix on purpose)

* `started_at` for a page loaded mid-read is the work's creation time, so the clock overshoots.
* `open_thread`, `resolve_thread`, `new_chat`, `switch_chat`, `delete_chat`, `discuss_node`, `add_context` have no server-side ownership check.
* `add_context` opens the drawer in state only; the URL gains no `chat=1`.
* `:thread_ask` and `:ask` results are appended to whichever thread/conversation is current when the answer lands, not the one that was asked.
* `chat:clear` is delivered to every mounted `.Composer`.
* `close_rewrite` does not cancel the task; a late result repopulates `rewrite`.
* `save_block` passes the section struct loaded with the page rather than re-fetching it (unlike `apply_rewrite`), so a concurrent edit from another tab can be overwritten.
* `origin`/`rewrite_note` in `save_block` are dead branches (always `"edit"`, nil).
* The walkthrough's rewrite fixture lacks `spans_blocks`/`covers` and should raise during render, by reading (section 7).
* `graph.dot` draws `leads_to` edges (the read's spine chain) dashed, because only `follows` is solid.
* `set_mode` with an unknown mode id crashes the page process; the select/tabs only offer valid ids.
* `phx-value-section` on the tick is the section's numeric id; `phx-value-ordinal` on the summarise button is the section ordinal; they are different numbers.
