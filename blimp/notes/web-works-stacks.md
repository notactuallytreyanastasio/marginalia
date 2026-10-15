# Web spec: works index/new, bulk import, stacks

Source: `lib/marginalia_web/live/{work_live/index,work_live/new,import_live,stack_live/*}.ex`, `router.ex`,
plus `controllers/work_controller.ex`, `controllers/work_html.ex` (the no-socket fallback of /works/new).
Context functions are named as in Elixir (`Folders.tree/1`) with their return shapes. CSS class names are
verbatim; the stylesheet is reused byte for byte.

Conventions used below:
- `{x}` in markup is an HTML-escaped interpolation.
- "LV event" = a `phx-click`/`phx-submit`/`phx-change` message the browser sends over the socket.
- All pages render inside `Layouts.app` (section 0). Every page is a LiveView, rendered once over HTTP
  (disconnected mount) and again on websocket connect (connected mount). `mount` runs twice.
- `navigate` links render as `<a href="..." data-phx-link="redirect" data-phx-link-state="push">`; shown below as plain `<a href>`.

---------------------------------------------------------------------------------------------------

## 0. Shared: routes, auth, layout, flash, page meta

### Routes (router.ex)

All pages in this document sit in one scope:

```
scope "/"  pipe_through [:browser, :ensure_user_or_guest]
  post "/works/new", WorkController, :create            # no-JS fallback for the upload form
  live_session :allow_guest, on_mount: [{MarginaliaWeb.UserAuth, :allow_guest}]
    live "/works",                WorkLive.Index,   :index
    live "/works/new",            WorkLive.New,     :new
    live "/import",               ImportLive,       :index
    live "/works/:id",            WorkLive.Show,    :show      # out of scope; after /works/new
    live "/stacks",               StackLive.Index,  :index
    live "/stacks/new",           StackLive.New,    :new       # must precede /stacks/:id
    live "/stacks/:id",           StackLive.Show,   :show
    live "/stacks/:id/story",     StackLive.Story,  :story     # must precede /stacks/:id/:ordinal
    live "/stacks/:id/:ordinal",  StackLive.Show,   :step
```

First-match routing: `/stacks/new` would otherwise resolve as folder id "new"; `/stacks/:id/story` would
otherwise resolve as ordinal "story" (and `String.to_integer("story")` raises -> 500).

### Auth: "guest-or-user"

- Pipeline `:browser`: accepts html, fetch_session, fetch_live_flash, root layout `Layouts.root`, CSRF protection,
  secure headers, `fetch_current_scope_for_user`.
- Plug `:ensure_user_or_guest` (HTTP request only): if `conn.assigns.current_scope.user` is absent, call
  `Accounts.create_guest_user()`, log them in as that guest (session created, scope = `Scope.for_user(guest)`).
  On failure: flash error "Something went wrong. Try logging in." and redirect `/users/log-in`.
  So the first visit to any of these URLs without a session silently mints a guest `users` row.
- `on_mount :allow_guest` (LV): mounts `current_scope` from session; if there is a user, continue; else redirect `/users/log-in`.
  A "user" is a real user OR a guest (`user.is_guest` boolean).
- So `current_scope.user.id` is always non-nil on every page here, and every query is scoped to that `user_id`
  (`works.user_id`, `folders.user_id`). No admin role.
- Exception: `Folders.publish/2` also requires the user to be `Accounts.owner()` (the user whose email equals the
  `:owner_email` app env, case-insensitive).

### Layouts

Root layout (`layouts/root.html.heex`): `<html lang="en">`; head: charset, viewport, `csrf-token` meta, `head_meta`
(title, description, optional robots, OG/Twitter tags), `<link phx-track-static rel=stylesheet href=/assets/css/app.css>`,
`<script defer phx-track-static src=/assets/js/app.js>`, an inline theme script (sets `data-theme` on `<html>` from
`localStorage["phx:theme"]` or `prefers-color-scheme`; listens to `storage` and `phx:set-theme`). Body is only `{@inner_content}`.

Page meta: each LV assigns `page_title`. `<.live_title default="Someone who has actually read the whole thing" suffix=" · Marginalia">`
so `<title>` = `"<page_title> · Marginalia"`; `og:title`/`twitter:title` = page_title (or the tagline).
Only ImportLive also sets `page_robots: "noindex, nofollow"` -> `<meta name="robots" content="noindex, nofollow">`.
Default description: "Upload a draft. It reads end to end, maps what's on the page, and argues with you in the margin — a thread on any paragraph, anchored to your own sentences."
No page here sets description, image or url (defaults: `/images/og.png`; canonical = site root; og image 2400x1260).

`Layouts.app` (every page here calls `<Layouts.app flash={@flash} current_scope={@current_scope}>`, `bleed=false`):

```html
<header class="mg-bar">
  <a href="/" class="mg-brand">Marginalia <span>a reader for drafts</span></a>
  <nav>
    <a href="/cases">Cases</a>
    <!-- if user.is_guest -->
      <a href="/works">Drafts</a> <a href="/works/new">New draft</a>
      <span class="text-[var(--mg-dim)] opacity-70">guest</span>
      <a href="/users/register" class="mg-btn sm">Keep my drafts</a>
    <!-- elsif user (real) -->
      <a href="/works">Drafts</a> <a href="/links">Linked</a> <a href="/cuts">Cuts</a> <a href="/stacks">Methods</a>
      <a href="/works/new">New draft</a> <a href="/users/settings">{user.email}</a>
      <a href="/users/log-out" data-method="delete">Log out</a>
    <!-- else --> <a href="/users/log-in">Log in</a>
  </nav>
</header>
<main class="px-4 py-8 sm:px-6 lg:px-8">      <!-- bleed=false -->
  <div class="space-y-4">  {page content}  </div>
</main>
<div id="flash-group" aria-live="polite"> flash(:info) flash(:error) + client-error / server-error flashes </div>
```
A guest does not see the Methods link, but can open /stacks directly.

Flash component: when `Phoenix.Flash.get(flash, kind)` is non-nil:

```html
<div id="flash-info|flash-error" phx-click="push lv:clear-flash {key: kind} + hide #id" role="alert" class="toast toast-top toast-end z-50">
  <div class="alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap alert-info|alert-error">
    <svg hero-information-circle|hero-exclamation-circle class="size-5 shrink-0"/>
    <div><p>{msg}</p></div><div class="flex-1"></div>
    <button type="button" class="group self-start cursor-pointer" aria-label="close"><svg hero-x-mark class="size-5 opacity-40 group-hover:opacity-70"/></button>
  </div>
</div>
```
`put_flash` followed by `push_navigate` survives the live navigation and shows on the next page.

### `<.input>` component (core_components; used by WorkLive.New and the no-JS form)

Default `type="text"`. For text/url/etc.:
```html
<div class="mg-field"><label for="{id}"><span class="mg-label block mb-1.5">{label}</span>   <!-- span only if label -->
  <input type name id value class="mg-input [border-[var(--mg-accent)] when errors]" {rest}/></label>
  <p class="mt-1.5 flex gap-2 items-center text-sm text-error"><svg hero-exclamation-circle size-5/>{msg}</p>  <!-- one per error -->
</div>
```
Textarea: same wrapper with `<textarea id name class="mg-textarea ...">{value}</textarea>`. Ids/names come from the
form field (`work_title`/`work[title]`, `work_intent`, `work_body`). Errors are shown only if the field "was used"
(form has been submitted/changed with an action); errors from `validate` never show, errors from a failed insert do.

### Markdown (StackLive.Story)

`Markdown.to_html(text)` = MDEx (comrak): extensions strikethrough, table, autolink, tasklist, footnotes;
`parse.smart=false`; `render.hardbreaks=true` (each newline -> `<br>`), `unsafe=false`; output sanitised with the
ammonia default allowlist. nil/"" -> empty. On parse failure -> HTML-escaped plain text. Inserted raw.

---------------------------------------------------------------------------------------------------

## 1. /works -- WorkLive.Index (live_action :index)

### Mount
`mount(_params, _session, socket)`; no handle_params.
Assigns: `page_title: "Your drafts"`, `collapsed: MapSet.new()` (folder ids the user has collapsed; empty = all open),
`renaming: nil` (folder id being renamed). Then `load/1`:

- `tree = Folders.tree(user_id)` -> `%{folders: [node], works: [work]}`; node = `%{folder: %Folder{id,name,parent_id,published_at,slug}, count: int, folders: [node], works: [work]}`.
  Folders per level sorted by `lower(name)`, then id. Works come from `Works.list_works(user_id)` (all the user's works, `order_by desc id`, newest first), grouped by `folder_id`; top-level `works` = those with `folder_id = nil`.
  `node.count` = works directly in it + sum of child counts (recursive). Work fields used: `id, slug, title, word_count, status ("pending"|"reading"|"read"|"failed")`.
- `count = length(tree.works) + sum(tree.folders[].count)` (every work).
- `steps = Stacks.steps_by_work(user_id)` -> `%{work_id => {folder_id, ordinal}}` (one join over all the user's `stack_steps`).
- `unfiled = Folders.unfiled_collection_count(user_id)` -> number of works with non-nil `collection` and nil `folder_id`.

### Render (`max-w-4xl`)
```html
<div class="mx-auto max-w-4xl px-6 py-10">
  <div class="flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4">
    <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">Your drafts</h1>
    <span class="mg-meta">{@count}</span>
    <form id="new-folder" phx-submit="new_folder" class="ml-auto flex items-center gap-2">
      <input type="text" name="name" value="" autocomplete="off" placeholder="New folder" class="mg-input sm mg-newfolder"/>
      <button class="mg-btn sm ghost" type="submit">add folder</button>
    </form>
    <a href="/import" class="mg-btn sm ghost">Import many</a>
    <a href="/works/new" class="mg-btn">Upload a draft</a>
  </div>

  <!-- only if unfiled > 0 -->
  <p class="mg-tidy">{unfiled} of these already say which case they belong to.
     <button phx-click="backfill" class="mg-btn sm ghost">file them by case</button></p>

  <!-- if count == 0 and tree.folders == [] -->
  <p class="mg-empty mt-8">Nothing here yet. Bring the draft in the drawer.</p>
  <!-- else -->
  <div id="tree" phx-hook=".Tree" class="mg-tree mt-2">
    <div class="mg-tree-root" data-drop-kind="folder" data-drop-id="root">
      <.level node={@tree} collapsed renaming steps depth={0}/>
      <p :if={@tree.folders != []} class="mg-tree-hint">drag a draft onto a folder to file it · drop it out here to unfile it</p>
    </div>
  </div>
</div>
```
The "new folder" input has `value=""` in the template so the server never retains typed text.

### Function component `level/1` (private, recursive)
attrs: `node` (map, required), `collapsed` (MapSet), `renaming` (id|nil), `steps` (map), `depth` (int). Helper `open?(collapsed, id) = id NOT in collapsed`.
Emits, in order, every child folder block and then every work row of `node.works`.

Folder block (per `child <- node.folders`):
```html
<div class="mg-fold" draggable="true" data-drag-kind="folder" data-drag-id="{child.folder.id}">
  <div class="mg-frow" data-drop-kind="folder" data-drop-id="{child.folder.id}" style="padding-left:{depth*1.25+0.4}rem">
    <button type="button" class="mg-twist" phx-click="toggle" phx-value-id="{id}"
            aria-label="{open ? 'Collapse' : 'Expand'}">{open ? '▾' : '▸'}</button>

    <!-- if renaming == child.folder.id -->
    <form id="rename-{id}" phx-submit="rename" class="flex flex-1 items-center gap-2">
      <input type="hidden" name="folder_id" value="{id}"/>
      <input type="text" name="name" value="{child.folder.name}" autocomplete="off" class="mg-input sm flex-1"
             phx-mounted={JS.focus()} phx-window-keydown="rename_cancel" phx-key="Escape"/>
      <button class="mg-btn sm ghost" type="submit">save</button>
    </form>
    <!-- else -->
    <button type="button" class="mg-fname" phx-click="toggle" phx-value-id="{id}">{child.folder.name}</button>
    <span class="mg-meta">{child.count}</span>
    <span class="mg-frow-tools">
      <button class="mg-btn sm ghost" phx-click="rename_start" phx-value-id="{id}">rename</button>
      <button class="mg-btn sm ghost" phx-click="delete_folder" phx-value-id="{id}"
              data-confirm="Delete this folder? The drafts in it move up a level, they are not deleted.">delete</button>
    </span>
  </div>

  <!-- if open?(collapsed, id) -->
  <div class="mg-fkids" style="--rail:{depth*1.25+0.95}rem">
    <p :if={child.folders == [] and child.works == []} class="mg-fempty">empty — drag a draft here</p>
    <.level node={child} collapsed renaming steps depth={depth+1}/>
  </div>
</div>
```
Children render INSIDE the parent's `.mg-fold`, which is why "no drop into own subtree" is `dragged.contains(target)`.

Work row (per `w <- node.works`):
```html
<div class="mg-wrow" draggable="true" data-drag-kind="work" data-drag-id="{w.id}" style="padding-left:{depth*1.25+0.4}rem">
  <span class="mg-grip" aria-hidden="true">⠿</span>
  <div class="min-w-0 flex-1">
    <a href="/works/{w.slug}" style="font-family:var(--mg-serif)" class="text-[1.1rem] hover:text-[var(--mg-accent)]">{w.title}</a>
    <div class="mg-meta mt-0.5">{w.word_count} words</div>
  </div>
  <span class="mg-badge ink">{w.status}</span>     <!-- class is "mg-badge ink" iff status == "read"; otherwise "mg-badge " -->
  <!-- if steps[w.id] = {fid, ord} -->
  <a href="/stacks/{fid}/{ord}" class="mg-btn sm ghost" title="The step of the method this document became">step {ord}</a>
  <button class="mg-btn sm ghost" phx-click="delete" phx-value-id="{w.id}"
          data-confirm="Delete this draft, its map and its conversations?">delete</button>
</div>
```

### Colocated hook `.Tree` (on `#tree`; the bundler namespaces the name to the module, `MarginaliaWeb.WorkLive.Index.Tree`)
Full source:
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
Contract:
- Outbound only: `pushEvent("move", {kind: "work"|"folder", id: "<id string>", into: "<folder id string>"|"root"})`. No `handleEvent`; the server never `push_event`s to this hook.
- Drag sources = `[data-drag-id]` (`.mg-fold`, `.mg-wrow`). Drop zones = `[data-drop-id]` (each `.mg-frow` with the folder id, and `.mg-tree-root` with `"root"`). The zone is `closest("[data-drop-id]")` of the event target, so a drop over a work row, a `.mg-fkids` area, or the "empty — drag a draft here" text resolves to the nearest enclosing zone, which is `.mg-tree-root` (= unfile to root); only dropping on a folder's own `.mg-frow` (twist, name, count, tools) files into that folder.
- Classes toggled: `is-dragging` on the dragged element, `is-over` on the highlighted zone.
- Client filter: not into the dragged element's own subtree; a folder dropped on itself is ignored. Server filter: `:cycle`. A work dropped on the folder it is already in still pushes `move` (no-op update).
- Because the hook only attaches listeners to `this.el` (stable `#tree`), LiveView DOM patches inside do not disturb it. Note the `#tree` element is destroyed (`destroyed()` -> `clear()`) and re-created if the page flips between "empty" and non-empty.

### Events (`user_id = current_scope.user.id`)
| event | params | effect |
|---|---|---|
| `new_folder` | `%{"name"}` | `String.trim`; empty -> no change. Else `Folders.create_folder(user_id, %{name: name})` (top level; parent nil). `{:ok,_}` -> `load/1`. `{:error, cs}` -> flash error `first_error(cs)`. |
| `backfill` | any | `Folders.backfill_from_collections(user_id)` (default parent folder name "Cases"). `{:ok, 0}` -> nothing. `{:ok, n}` -> flash info `"Filed {n} draft(s) by case."` (`draft` if n==1 else `drafts`) then `load`. `{:error,_}` -> flash error "Could not file those.". Side effects: get-or-create root folder "Cases" and under it one folder per distinct `collection` string; every work with non-nil `collection` and nil `folder_id` is moved into its collection's folder. Idempotent; never moves a work already in a folder; works with no collection stay at root. |
| `toggle` | `%{"id"}` | flips membership of `String.to_integer(id)` in `collapsed`. No DB. |
| `rename_start` | `%{"id"}` | `renaming = int(id)` |
| `rename_cancel` | any | `renaming = nil` (fired by window keydown Escape while the rename input exists) |
| `rename` | `%{"folder_id","name"}` | `Folders.rename_folder(user_id, folder_id, name)`. `{:ok,_}` -> `renaming=nil`, `load`. `{:error, %Changeset{}}` -> flash error first_error (stays in rename mode). `{:error, :not_found}` -> `renaming=nil`. |
| `delete_folder` | `%{"id"}` | `Folders.delete_folder(user_id, id)`: transaction; works in it get `folder_id = folder.parent_id`; child folders get `parent_id = folder.parent_id`; folder deleted. `{:ok,_}` -> flash info "Folder gone. What was in it moved up a level." + `load`. error -> silent no-op. Browser shows `data-confirm` first. |
| `move` | `%{"kind","id","into"}` | `into` in `["root","",nil]` -> nil. `"work"` -> `Folders.move_work(user_id, id, into)` (work must be owned; `into` must be an owned folder else it silently becomes nil = root). `"folder"` -> `Folders.move_folder(user_id, id, into)` (folder must be owned; refuses `into == self` or a descendant: `{:error, :cycle}`; sibling-name clash -> changeset error). `{:ok,_}` -> `load`. `:cycle` -> flash error "A folder cannot go inside itself.". Changeset error -> flash error first_error. Other errors (`:not_found`, `:unknown`) -> silent. |
| `delete` | `%{"id"}` | `Works.get_work(user_id, id)`; nil -> no-op. Else `Works.delete_work(work)` (DB cascade removes sections/nodes/etc.), flash info "Deleted.", `load`. |

`first_error(changeset)` = `traverse_errors` (messages left uninterpolated) -> flat list of `"{field} {msg}"` -> first, else "That did not work.".
Folder validation: name trimmed, required, max 80 chars, unique among siblings (two unique indexes: per-parent and root-level) with message "there is already a folder with that name here" (so the flash reads "name there is already a folder with that name here").

No handle_info / handle_async / timers / PubSub. Every mutation re-queries via `load` (no optimistic UI).

---------------------------------------------------------------------------------------------------

## 2. /works/new -- WorkLive.New (live_action :new) and POST /works/new

### Mount
Assigns: `page_title: "Upload a draft"`, `error: nil`, `preview: nil` (unused), `fetching: false`, `url: ""`,
`form: to_form(Works.change_work())` (empty `Work` changeset; param namespace `work`).
`allow_upload(:manuscript, accept: ~w(.txt .md .markdown .text), max_entries: 1, max_file_size: 8_000_000)`.
Not `auto_upload`: the entry is registered on change; the bytes are transferred when the main form is submitted;
`consume_uploaded_entries` runs inside `save`.

### Render (`max-w-2xl`)
```html
<div class="mx-auto max-w-2xl px-6 py-10">
  <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">Upload a draft</h1>
  <p class="mg-prose mt-2 text-[0.95rem] text-[var(--mg-dim)]">Paste it or attach a <code>.txt</code>/<code>.md</code> file. Nothing is read until you
     confirm how it's divided on the next screen.</p>

  <!-- if @error -->
  <div class="mt-5 border-l-2 border-[var(--mg-accent)] pl-3 py-1.5 text-[0.85rem]">{@error}</div>

  <form phx-submit="fetch" class="mt-6">      <!-- its own form, ABOVE the main one: forms cannot nest -->
    <label class="mg-label block mb-1.5" for="import-url">Read it off the web</label>
    <div class="flex gap-2 items-start">
      <input type="url" id="import-url" name="url" value="{@url}" placeholder="https://…" disabled={@fetching}
             class="flex-1 min-w-0 px-2.5 py-1.5 border border-[var(--mg-rule)] rounded-sm bg-[var(--mg-paper)] text-[0.9rem]"/>
      <button type="submit" class="mg-btn sm shrink-0" disabled={@fetching}>{fetching ? "Reading…" : "Fetch"}</button>
    </div>
    <p class="mg-hint mt-1.5">The article is pulled out and turned into markdown — headings, lists and links
       kept, navigation and footers dropped. It fills in the fields below for you to
       check before uploading.</p>
  </form>

  <form action="/works/new" method="post" phx-change="validate" phx-submit="save" class="mt-6 space-y-5">
    <!-- hidden _csrf_token (emitted because action is set) -->
    <.input field=title  label="Title" placeholder="Working title is fine"/>                    <!-- id work_title, name work[title] -->
    <div><.input field=intent type="textarea" rows="2"
           label="In a sentence or two, what is this supposed to do to a reader?"
           placeholder="Optional — but it's what stops the notes being generic."/></div>       <!-- work_intent -->
    <div>
      <label class="mg-label block mb-1.5">Attach a file</label>
      <div phx-drop-target="{uploads.manuscript.ref}" class="border border-dashed border-[var(--mg-rule)] rounded-sm p-5 text-[0.85rem] bg-[var(--mg-card)]">
        <input type="file" name="manuscript" accept=".txt,.md,.markdown,.text" ... />            <!-- live_file_input -->
        <!-- per entry -->
        <div class="mt-2 flex items-center gap-2">
          <span>{entry.client_name}</span>
          <button type="button" class="opacity-60 hover:opacity-100" phx-click="cancel-upload" phx-value-ref="{entry.ref}">remove</button>
        </div>
        <!-- per upload_errors(entry) -->
        <p class="text-[var(--mg-accent)] text-[0.75rem] mt-1">{msg}</p>
      </div>
    </div>
    <div class="flex items-center gap-3 text-[var(--mg-dim)]">
      <hr class="flex-1 border-0 border-t border-[var(--mg-rule)]"/><span class="mg-label">or</span><hr class="flex-1 border-0 border-t border-[var(--mg-rule)]"/>
    </div>
    <.input field=body type="textarea" rows="12" label="Paste the draft"
       placeholder="Paste the whole thing. Chapter headings or markdown headings help it divide the draft correctly."/>   <!-- work_body -->
    <button type="submit" class="mg-btn">Continue</button>
  </form>
</div>
```
No progress bar is rendered for the entry. Upload error copy: `:too_large` "That file is too big (8MB limit).", `:not_accepted` "Only .txt and .md for now.", `:too_many_files` "One file at a time.", else `to_string(err)`. Only per-entry errors are rendered.
The `action` on the main form is load-bearing: it makes `<.form>` emit the CSRF hidden field that the no-JS POST needs.

### Events
| event | params | behaviour |
|---|---|---|
| `validate` | `%{"work"=>params}` | `form = to_form(Works.change_work(%Work{}, params))` (re-echo typed values; no errors displayed since no action). Also fired for file-input changes (registers entries). |
| `fetch` | `%{"url"}` | trim; "" -> no-op; if `fetching` already -> no-op. Else assign `fetching: true, error: nil, url: url` and `start_async(:fetch, fn -> Import.fetch(url) end)`. |
| `cancel-upload` | `%{"ref"}` | `cancel_upload(:manuscript, ref)` |
| `save` | `%{"work"=>params}` | see below |

`save` flow:
1. `uploaded = consume_uploaded_entries(:manuscript, fn %{path}, entry -> {:ok, {entry.client_name, File.read!(path)}} end)`.
2. If a file was attached: `title = blank(params["title"]) || Path.rootname(client_name)`, `body = file contents` (the pasted body is ignored). Else `title = blank(params["title"])`, `body = params["body"] || ""`.
3. `Upload.prepare(title, body, blank(params["intent"]))`: word count = `length(String.split(body, ~r/\s+/, trim: true))`; 0 -> `{:error, :empty}`; > 120_000 -> `{:error, {:too_long, n}}`; else `{:ok, %{"title" => title || "Untitled draft", "body" => body, "intent" => intent|nil}}`. `blank/1` = trimmed string or nil.
4. `{:ok, attrs}` -> `Works.create_work(user_id, attrs)`: in one transaction inserts `works` (`slug` = url-safe base64 of 16 random bytes without padding, generated once; `word_count` computed; title required <=200 chars; body required; `status` default "pending"), then splits the body with `Works.Segmenter.split/1` into `sections` rows (ordinal from 1, title, body, word_count, status "pending"), then sets `baseline_body = body = bodies of all sections joined by "\n\n"`.
   - `{:ok, work}` -> `push_navigate(to: "/works/{work.slug}")`.
   - `{:error, %Changeset{}}` -> `form: to_form(cs)`, `error: nil` (field errors now show).
   - `{:error, :no_sections}` -> `error: "Couldn't find any text to split into sections."`
5. `{:error, :empty}` -> `error: "There's no text there yet — paste a draft or attach a file."`
6. `{:error, {:too_long, n}}` -> `error: "That's {n with thousands commas} words, and the limit is 120,000 for now. Split it and upload the first part."`

### handle_async(:fetch)
The task runs `Import.fetch(url)` (2.1) off the LV process.
- `{:ok, {:ok, %{title, markdown, url}}}` -> `fetching: false`; `form = to_form(change_work(%Work{}, %{"title"=>title,"body"=>markdown,"source_url"=>url}))`; flash info `"Read {N} words from {host}. Check it over before uploading."` (N = whitespace-split count of markdown; host = `URI.parse(url).host || url`).
  Known quirks to decide on: `source_url` is in the changeset but not a form field and `save` builds attrs only from title/body/intent, so the source URL is never persisted from this page; and the rebuilt form clears `intent`.
- `{:ok, {:error, reason}}` -> `fetching: false`, `error: why(reason)`.
- `{:exit, _}` -> `fetching: false`, `error: why(:unreachable)`.

`why/1` copy: `:bad_scheme` "That needs to be an http or https address."; `:bad_url` "That does not look like a web address."; `:no_host` "That address has no site in it."; `:private_address` "That address points at a private network, so it will not be fetched."; `:too_little_text` "There was not enough prose on that page to read. A paywall, or a page that builds itself with JavaScript."; `:too_big` "That page is too large."; `:unparseable` "That page could not be read as HTML."; `{:http,404}` "That page was not found."; `{:http,s}` "That site answered with a {s}."; `:unreachable` "That site could not be reached."; other "That did not work: {inspect}".

### 2.1 `Import.fetch(url)`
- `allowed(url)`: parse the trimmed URL; scheme not http/https -> `:bad_scheme`; empty host -> `:no_host`; non-binary -> `:bad_url`. SSRF guard (`:private_address`): host lowercased with trailing dot removed is refused if in `localhost, 0.0.0.0, broadcasthost`, or ends with `.localhost .local .internal`; if an IP literal -> reserved check; otherwise resolve IPv4 A records and refuse if ANY is reserved or if it does not resolve. Reserved IPv4: 127/8, 10/8, 192.168/16, 169.254/16, 172.16/12, 0/8, 100.64/10, >=224/8. IPv6 literal: ::1, fc00::/7, fe80::/10 reserved (other v6 allowed).
- GET: receive timeout 20s, max 3 redirects (targets not re-checked), max 1 retry, `user-agent: Marginalia/1.0 (+https://marginalia.bobbby.online)`, `accept: text/html,application/xhtml+xml`. 200 with binary body <= 4_000_000 bytes else `:too_big`; other status `{:http, s}`; transport error `:unreachable`.
- Parse HTML; failure `:unparseable`.
- Title: first non-empty of `article h1`, `h1`, `meta[property=og:title]@content`, `<title>` (whitespace-normalised), else "Untitled"; cut to 200 chars.
- Article node: strip `script style nav header footer aside form noscript svg iframe button figure figcaption template`; candidates `article, main, [role=main], .post, .entry-content, body`; choose the one with the longest text.
- To markdown: walk children; block elements `h1-h6 p ul ol blockquote pre` are taken (not descended into), others are descended. h* -> `#`*level + " " + inline text (skipped if empty); p -> inline text; blockquote -> every line prefixed `> `; pre -> "```\n" + raw text + "\n```"; ul/ol -> one line per `li` found anywhere inside (`- ` or `1. `, `2. `...). Inline: strong/b `**`, em/i `*`, code backtick, br -> space, `a` -> `[text](href)` unless href empty or starts with `#` (then bare text), `sup` dropped; whitespace inside emphasis moved outside the delimiters; nbsp/zero-width/tabs -> space; newlines -> space. Blocks joined by blank lines, 3+ newlines collapsed to 2, trailing "\n".
- If the first block is `# X` and X is similar to the title (alnum-lowercased substring either way) it is dropped. If the remaining markdown is < 400 characters -> `:too_little_text`. Else `{:ok, %{title, markdown: "# {title}\n\n" <> markdown (heading omitted if title is ""), url: final URL string}}`.

### 2.2 POST /works/new -- WorkController.create (no-socket fallback)
Same pipeline incl. `ensure_user_or_guest`. Params `%{"work" => %{"title","intent","body"}}` (no file).
`Upload.prepare(title, body, intent)`:
- ok -> `Works.create_work(user_id, attrs)`: `{:ok, saved}` -> 302 `/works/{slug}`; `{:error,:no_sections}` -> re-render with "Couldn't find any text to split into sections."; `{:error, changeset}` -> re-render with `first_error`: first `"{field} {message with %{key} interpolated}"`, first letter capitalised, plus "." (default "That draft could not be saved.").
- `{:error, :empty}` -> re-render, 422: "There's no text there yet — paste the draft into the box below. Attaching a file needs JavaScript, which is not running on this page."
- `{:error,{:too_long,n}}` -> re-render, 422 with `Upload.too_long_message(n)`.
Re-render = status 422, `WorkHTML.new` in `Layouts.app` (no live flash):
```html
<div class="mx-auto max-w-2xl px-6 py-10">
  <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">Upload a draft</h1>
  <div class="mt-5 border-l-2 border-[var(--mg-accent)] pl-3 py-1.5 text-[0.85rem]">{error}</div>
  <p class="mg-prose mt-4 text-[0.95rem] text-[var(--mg-dim)]">This page is running without its live connection, so it is the plain
     version: paste and press Continue. Reload to get the full one back,
     but copy your text somewhere first — a reload will empty this box.</p>
  <form action="/works/new" method="post" class="mt-6 space-y-5">
    <input type="hidden" name="_csrf_token" value="..."/>
    <.input id="work_title" name="work[title]" value=work["title"] label="Title" placeholder="Working title is fine"/>
    <.input id="work_intent" name="work[intent]" value=work["intent"] type="textarea" rows="2" label="In a sentence or two, what is this supposed to do to a reader?" placeholder="Optional — but it's what stops the notes being generic."/>
    <.input id="work_body" name="work[body]" value=work["body"] type="textarea" rows="12" label="Paste the draft" placeholder="Paste the whole thing. Chapter headings or markdown headings help it divide the draft correctly."/>
    <button type="submit" class="mg-btn">Continue</button>
  </form>
</div>
```
No file input, URL box or filename fallback on this path.

---------------------------------------------------------------------------------------------------

## 3. /import -- ImportLive (live_action :index)

Four-step wizard in one LiveView: Source -> Find -> Choose -> Import. Nothing is created before the Import step.
Page meta: `page_title: "Import documents"`, `page_robots: "noindex, nofollow"`.

### Constants
`@max_files = 40` (uploaded files), `@max_pick = 200` (pull requests per run).
`api/0` = `Application.get_env(:marginalia, :github_api, Marginalia.Import.GitHub)`; a swappable module exposing `list/4`, `search/3`, `documents/3`. Production = `Import.GitHub`.

### Assigns at mount
| assign | initial | meaning |
|---|---|---|
| `step` | `:source` | `:source :find :files :pick :running :done` |
| `source` | nil | `:github` \| `:files` \| nil |
| `repo` | "" | find form: owner/name |
| `token` | "" | GitHub token; set at `find`, kept in assigns only, never rendered back |
| `mode` | "repo" | "repo" \| "search" |
| `state` | "all" | "all" \| "open" \| "closed" |
| `query` | "" | GitHub search text |
| `pattern` | "" | narrowing text on the pick step |
| `pattern_error` | nil | message for a bad pattern |
| `hint` | nil | `%{was:, try:}` from `Query.hint/1` when the filtered list is empty |
| `how` | "query" | "query" \| "regex" (language of `pattern`) |
| `order` | "oldest" | "oldest" \| "newest" |
| `candidates` | [] | all fetched candidates (sorted by `order`) |
| `shown` | [] | candidates passing the pattern |
| `chosen` | empty MapSet | keys currently ticked |
| `commits` | true | include commit trail |
| `files` | true | include changed files |
| `number` | false | prefix titles "N. " |
| `folder` | "" | destination folder name |
| `working` | false | find in progress |
| `phase` | nil | `:finding` \| `:fetching` \| `:landing` \| nil |
| `progress` | `{0,0}` | `{done,total}` |
| `missed` | [] | `[{candidate, reason}]` fetch failures |
| `result` | nil | the `Bulk.land/3` map |
| `error` | nil | message under the step list |

Candidate map (`GitHub.candidate/2`): `%{repo: "owner/name"|nil, number, title ("" if nil), url (html_url), state: "open"|"closed"|"merged" ("merged" when merged_at present), draft: bool, base, head, updated_at, created_at, merged_at}` (ISO8601 strings; merged_at from `merged_at` or `pull_request.merged_at`).
`key(c) = "#{c.repo}##{c.number}"` (public `ImportLive.key/1`).

Upload: `allow_upload(:docs, accept: ~w(.txt .md .markdown .text), max_entries: 40, max_file_size: 8_000_000, auto_upload: true)`; files begin transferring as soon as chosen/dropped.

### Chrome shown on every step
```html
<div class="mx-auto max-w-3xl px-6 py-10">
  <div class="mg-meta"><a href="/works">← every draft</a></div>
  <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">Import documents</h1>
  <ol class="im-steps">
    <li class="im-step on?"><span>1</span> Source</li>     <!-- "on" iff step == :source -->
    <li class="im-step on?"><span>2</span> Find</li>       <!-- iff step in [:find, :files] -->
    <li class="im-step on?"><span>3</span> Choose</li>     <!-- iff step == :pick -->
    <li class="im-step on?"><span>4</span> Import</li>     <!-- iff step in [:running, :done] -->
  </ol>
  <p :if={@error} class="cut-err mt-4">{@error}</p>
  ... step body ...
</div>
```
(`class={["im-step", cond && "on"]}` renders `class="im-step on"` or `class="im-step"`.)

### Step :source
```html
<p class="mg-meta mt-4 leading-relaxed">Both of these land in a folder and stop. Nothing is read, and nothing costs
  anything, until you press the buttons on the folder afterwards.</p>
<div class="im-pick">
  <button class="im-card" phx-click="source" phx-value-to="github">
    <span class="mg-label">GitHub</span><b>Pull requests</b>
    <span>A repository, or a search across several. Filter by title, tick the ones you
      mean. Each becomes a draft of its description and its commit trail.</span></button>
  <button class="im-card" phx-click="source" phx-value-to="files">
    <span class="mg-label">Files</span><b>From this computer</b>
    <span>Up to 40 markdown or text files, dropped together. Each one becomes
      a draft, named after the file.</span></button>
</div>
```

### Step :find
```html
<form id="im-find" phx-submit="find" phx-change="form" class="mt-6 space-y-4">
  <div class="im-modes">
    <label class="im-mode on?"><input type="radio" name="mode" value="repo" checked={mode=="repo"}/><b>One repository</b><span>Every pull request in it, then filter.</span></label>
    <label class="im-mode on?"><input type="radio" name="mode" value="search" checked={mode=="search"}/><b>A search</b><span>GitHub's own query language, across repositories.</span></label>
  </div>
  <!-- mode == "repo" -->
  <label class="mg-field"><span class="mg-label">Repository</span>
    <input type="text" name="repo" value="{repo}" placeholder="owner/name" autocomplete="off" class="mg-input"/></label>
  <label class="mg-field"><span class="mg-label">Which pull requests</span>
    <select name="state" class="mg-select">
      <option value="all" selected?>All, open and closed</option>
      <option value="open" selected?>Open only</option>
      <option value="closed" selected?>Closed only</option></select></label>
  <!-- mode == "search" -->
  <label class="mg-field"><span class="mg-label">Search</span>
    <input type="text" name="query" value="{query}" placeholder="repo:owner/name label:design merged:>2025-01-01" autocomplete="off" class="mg-input"/>
    <span class="mg-meta">Passed to GitHub as written, with two exceptions: <code>is:pr</code>
      is added for you, and <code>@today-30d</code>
      is turned into the date it means, because GitHub has no relative dates and
      answers them with a 422. Search is capped at 1000 results and rate limited
      to 30 a minute, both by GitHub.</span></label>
  <!-- always -->
  <label class="mg-field"><span class="mg-label">GitHub token <em>optional</em></span>
    <input type="password" name="token" value="" autocomplete="off" placeholder="leave blank for a public repository" class="mg-input"/>
    <span class="mg-meta">A public repository needs none, at 60 requests an hour and 10 searches a
      minute. A token raises that to 5000 an hour and reaches private
      repositories; read access is enough. It is held for as long as this page is
      open and written down nowhere.</span></label>
  <div class="flex items-center gap-3">
    <button class="mg-btn" type="submit" disabled={@working}>{working ? "Looking…" : "Find them"}</button>
    <button class="mg-btn sm ghost" type="button" phx-click="back">back</button>
  </div>
</form>
```
Switching the radio fires `form` (phx-change), so the mode-specific fields swap in/out from server state; the token input is not touched.

### Step :pick
```html
<form id="im-pattern" phx-submit="pattern" phx-change="pattern" class="mt-6">   <!-- submit does the same as change so Enter never does a native GET -->
  <span class="mg-label">Narrow this list</span>
  <div class="im-filter">
    <select name="how" class="mg-select sm"><option value="query" selected?>Query</option><option value="regex" selected?>Title regex</option></select>
    <input type="text" name="pattern" value="{pattern}" autocomplete="off" class="mg-input" phx-debounce="300"
           placeholder="{how=='regex' ? 'a regular expression — ^d+. or fix|revert' : 'is:pr state:closed created:>@today-30d'}"/>
  </div>
  <p :if={@pattern_error} class="cut-err mt-2">{@pattern_error}</p>
  <p :if={!@pattern_error and @how == "regex"} class="mg-meta mt-2">Case insensitive, matched against the title. Filters the list and selects what
    it matches — the boxes below still have the last word.</p>
  <p :if={!@pattern_error and @how != "regex"} class="mg-meta mt-2">Runs over the rows already fetched, so it costs nothing and does not have to be
    right first time. <code>state:</code> <code>is:</code> <code>draft:</code> <code>repo:</code> <code>base:</code> <code>head:</code> <code>number:</code>, the dates <code>created:</code>
    <code>updated:</code> <code>merged:</code>, and a bare word matches the title. Dates take
    <code>@today-30d</code> as well as <code>2025-08-05</code>, and <code>-</code> in front of anything takes it away.</p>
</form>
```
(The regex placeholder in source is the Elixir string `"a regular expression — ^\d+\. or fix|revert"`; Elixir drops the backslashes of unknown escapes, so the emitted attribute is `a regular expression — ^d+. or fix|revert`. Match the emitted text if byte parity matters.)

```html
<form id="im-order" phx-submit="order" phx-change="order" class="im-order">
  <span class="mg-label">Order</span>
  <select name="order" class="mg-select sm">
    <option value="oldest" selected?>Oldest first, by when it landed</option>
    <option value="newest" selected?>Newest first</option></select>
  <span class="mg-meta">This is the order they are created in, and the order the folder is read
    forwards in. For a release, oldest first.</span>
</form>

<div class="im-bar">
  <span>{count(len(shown),"pull request","pull requests")} shown{" of N" only if len(shown) != len(candidates)} ·
    <b>{chosen.size} selected</b></span>
  <button class="mg-btn sm ghost" type="button" phx-click="all">select all shown</button>
  <button class="mg-btn sm ghost" type="button" phx-click="none">clear shown</button>
</div>
```
`count(1, one, _) = "1 " + one`; `count(n, _, many) = "n " + many`.

```html
<ul class="im-list">
  <li :for={c <- @shown} class="im-row on?">           <!-- "on" iff key(c) in chosen -->
    <label>
      <input type="checkbox" checked={chosen?} phx-click="toggle" phx-value-key="{key(c)}"/>
      <span class="n">#{c.number}</span>
      <span class="t">{c.title}</span>
      <span :if={c.merged_at} class="d">{first 10 chars of merged_at}</span>
      <span class="s {c.state}">{c.state}</span>       <!-- "s open" | "s closed" | "s merged" -->
      <span :if={c.draft} class="s draft">draft</span>
      <span class="r">{c.repo}</span>
    </label>
  </li>
</ul>

<div :if={@shown == [] and not @working} class="mt-3">
  <p class="mg-meta">Nothing matches {how=="regex" ? "that pattern" : "that query"}.</p>
  <p :if={@hint} class="mg-meta mt-1"><code>{hint.was}</code> is that one day. For everything since it, write <code>{hint.try}</code>.</p>
</div>

<form id="im-settings" phx-submit="import" phx-change="settings" class="mt-6 space-y-4">
  <label class="mg-field"><span class="mg-label">Folder</span>
    <input type="text" name="folder" value="{folder}" placeholder="left empty, named for what the files have in common" autocomplete="off" class="mg-input"/></label>
  <label class="im-check"><input type="hidden" name="commits" value="false"/><input type="checkbox" name="commits" value="true" checked={commits}/>
    <span><b>Include the commit trail.</b> The description argues; the commits are what was done. One more request each.</span></label>
  <label class="im-check"><input type="hidden" name="files" value="false"/><input type="checkbox" name="files" value="true" checked={files}/>
    <span><b>Include the files changed.</b> Paths and line counts, not diffs — what the change is about, in one glance. One more request each.</span></label>
  <label class="im-check"><input type="hidden" name="number" value="false"/><input type="checkbox" name="number" value="true" checked={number}/>
    <span><b>Number the titles.</b> Only if these are a series meant to be read in order — that is where the stack reader looks for the order.</span></label>
  <div class="flex items-center gap-3">
    <button class="mg-btn" type="submit" disabled={chosen.size == 0}>Import {chosen.size}</button>
    <button class="mg-btn sm ghost" type="button" phx-click="back">back</button>
  </div>
</form>
```
Hidden + checkbox pairs of the same name: unchecked submits "false", checked submits "false" then "true" (last wins).

### Step :files
```html
<form id="im-files" phx-submit="import_files" phx-change="validate" class="mt-6 space-y-4">
  <div class="im-drop" phx-drop-target="{uploads.docs.ref}">
    <p class="mg-meta">Drop up to 40 markdown or text files here, or choose them. Each one
      becomes a draft named after the file.</p>
    <input type="file" name="docs" multiple accept=".txt,.md,.markdown,.text" .../>        <!-- live_file_input -->
  </div>
  <p :for={err <- upload_errors(@uploads.docs)} class="cut-err">{upload_error(err)}</p>     <!-- config-level errors -->
  <ul :if={entries != []} class="im-list">
    <li :for={entry} class="im-row on">
      <span class="t">{entry.client_name}</span>
      <span class="s">{entry.progress}%</span>
      <span :for={err <- upload_errors(@uploads.docs, entry)} class="cut-err">{upload_error(err)}</span>
      <button type="button" class="mg-btn sm ghost" phx-click="drop_file" phx-value-ref="{entry.ref}">remove</button>
    </li>
  </ul>
  <label class="mg-field"><span class="mg-label">Folder</span><input type="text" name="folder" value="{folder}" placeholder="left empty, named for what the files have in common" autocomplete="off" class="mg-input"/></label>
  <label class="im-check"><input type="hidden" name="number" value="false"/><input type="checkbox" name="number" value="true" checked={number}/>
    <span><b>Number the titles.</b> Only if these are a series meant to be read in order.</span></label>
  <div class="flex items-center gap-3">
    <button class="mg-btn" type="submit" disabled={entries == []}>Import {length(entries)}</button>
    <button class="mg-btn sm ghost" type="button" phx-click="back">back</button>
  </div>
</form>
```
`upload_error`: `:too_large` "over 8 MB"; `:not_accepted` "not a text or markdown file"; `:too_many_files` "more than 40 files"; else `to_string`. `entry.progress` is 0-100, live (auto_upload). `validate` is a no-op handler, so the folder/number inputs here are not server-controlled during typing (their values live in the DOM; `folder`/`number` assigns are updated only by `import_files`, or by `settings` on the pick form).

### Step :running
```html
<div class="mt-8">
  <p class="mg-label">{phase == :fetching ? "Reading them off GitHub" : "Filing them"}</p>
  <div class="im-progress"><span style="width:{percent(progress)}%"></span></div>
  <p class="mg-meta mt-2">{done} of {total}</p>
  <p class="mg-meta mt-6 leading-relaxed">Leave this page open. Fetching is six at a time and filing is one at a time,
    which is slower and is the half that writes to the database.</p>
</div>
```
`percent({_,0}) = 0`, else `round(done/total*100)`.

### Step :done
```html
<div :if={@result} class="mt-8">
  <p style="font-family:var(--mg-serif)" class="text-xl font-semibold">{count(len(result.created),"draft","drafts")} imported.</p>
  <p :if={result.skipped != []} class="mg-meta mt-2">{count(len(skipped),"was","were")} already in the folder under the
    same title and {len(skipped)==1 ? "was" : "were"} left alone.</p>
  <div :if={result.failed != []} class="mt-4"><p class="mg-label">Not imported</p>
    <ul class="im-bad"><li :for={{title, reason}}>{title} — {Bulk.explain(reason)}</li></ul></div>
  <div :if={@missed != []} class="mt-4"><p class="mg-label">Could not be fetched</p>
    <ul class="im-bad"><li :for={{c, reason}}>#{c.number} {c.title} — {GitHub.explain(reason)}</li></ul></div>
  <div class="mt-6 flex items-center gap-3">
    <a :if={result.folder} href="/stacks/{result.folder.id}" class="mg-btn">Open the folder</a>
    <a :if={result.folder == nil} href="/works" class="mg-btn">Every draft</a>
    <button class="mg-btn sm ghost" type="button" phx-click="restart">import some more</button>
  </div>
</div>
<div :if={is_nil(@result)} class="mt-8"><button class="mg-btn" type="button" phx-click="restart">start again</button></div>
```
The skipped sentence therefore reads "1 was already in the folder under the same title and was left alone." / "3 were already ... and were left alone."
This results page is now reached only when something failed, was not fetched, or the import was loose. `result == nil` occurs only when the import task crashed (`error` is then shown in the `cut-err` line).

### Events: moving between steps
| event | params | effect |
|---|---|---|
| `source` | `to: "github"` | `source: :github, step: :find, error: nil` |
| `source` | `to: "files"` | `source: :files, step: :files, error: nil` |
| `back` | - | `:pick`->`:find`, `:find`->`:source`, `:files`->`:source`, others unchanged; `error: nil`. Candidates, selection, token kept. |
| `restart` | - | `step: :source, source: nil, candidates: [], shown: [], chosen: empty, pattern: "", pattern_error: nil, result: nil, missed: [], error: nil, progress: {0,0}`. (repo/query/token/folder/flags/how/order preserved.) |

### Events: finding
`form` (phx-change on #im-find): `repo`, `query`, `mode`, `state` from params (falling back to current), `error: nil`. Token intentionally not captured.

`find` (submit): `token = trim(params["token"])`, `mode = params["mode"] || "repo"`, `repo`/`query` trimmed, `state = params["state"] || "all"`; assigns repo/query/mode/state/token; then:
- mode "search", query "" -> `error: "Write a search query first."`
- mode "repo": split `repo` on first "/" into two non-empty parts -> `working: true, phase: :finding, error: nil` + `start_async(:find, fn -> api().list(owner, name, token, state: state) end)`; else `error: "Write the repository as owner/name."`
- mode "search": `working: true, phase: :finding, error: nil` + `start_async(:find, fn -> api().search(query, token) end)`.
- any other mode value raises (CaseClauseError).

`handle_async(:find)`:
- `{:ok, {:ok, []}}` -> `working: false, phase: nil, error: "Nothing matched."` (stays on :find)
- `{:ok, {:ok, candidates}}` -> `working: false, phase: nil, step: :pick, candidates: sorted(candidates, order), folder: default_folder(assigns)`, then `refilter(socket.assigns.pattern)` which selects everything shown. `default_folder`: mode "repo" and repo != "" -> the repo string ("owner/name"); else query != "" -> `"Search: " <> first 60 chars of query`; else "Imported".
- `{:ok, {:error, reason}}` -> `working: false, phase: nil, error: GitHub.explain(reason)`
- `{:exit, reason}` -> `working: false, phase: nil, error: "The search crashed: {inspect(reason)}"`

### Events: choosing
- `pattern` (`how`, `pattern`): `how = params["how"] || current`; `refilter(pattern)`. `phx-debounce="300"` is on the text input only.
  `refilter`: `narrow = how == "regex" ? Bulk.by_title(candidates, pattern) : Query.filter(candidates, pattern)` (always over ALL candidates).
  - `{:ok, shown}` -> assign `pattern, pattern_error: nil, hint: (shown == [] ? Query.hint(pattern) : nil), shown, chosen: keys of every shown` (resets manual ticks).
  - `{:error, why}` -> assign `pattern, pattern_error: why`; `shown`/`chosen` unchanged (last good list stays).
- `toggle` (`key`): flip membership in `chosen`.
- `all`: `chosen = chosen ∪ keys(shown)`. `none`: `chosen = chosen − keys(shown)` (selection hidden by the filter is kept).
- `order` (`order`): `candidates = sorted(candidates, order)`, then `refilter(pattern)` (again resets selection to all shown). `sorted(_, "newest") = reverse(oldest_first(...))`; anything else = `GitHub.oldest_first`, which sorts ascending by `{merged_at || created_at || "", number || 0}` (string compare of ISO timestamps).
- `settings` (`folder`, `commits`, `files`, `number`): `folder = params["folder"] || current`; each flag `= (param == "true")`.

### Pattern languages
Regex mode, `Bulk.by_title(candidates, pattern)`: trimmed empty -> all; else compile PCRE with the `i` flag; compile error -> `{:error, "{reason} at character {n}"}` (PCRE reason text); keep candidates whose `String.slice(title, 0, 200)` matches.

Query mode, `Query.filter(candidates, text)`:
- Tokenise with `"[^"]*"|\S+`, dropping `""`. Terms ANDed. Leading `-` negates a term (`-is:pr` yields nothing).
- Term: no ":" -> bare word; token starting with ":" -> bare word; else `key:value` (key lowercased; surrounding `"` and spaces trimmed from value).
- Bare word: case-insensitive substring of title.
- `is:pr` no-op; `is:issue` error "`is:issue` — there are only pull requests here."; `is:draft` draft==true; `is:open|closed|merged` state equals; other `is:x` error "`is:x` — I know is:pr, is:draft, is:open, is:closed and is:merged."
- `state:open|closed|merged` equals `c.state` (nil counts as "open"); else error "`state:x` — a pull request here is open, closed or merged."
- `draft:true|yes`, `draft:false|no`; else error "`draft:x` — true or false."
- `repo:`, `base:`, `head:` -> case-insensitive equality with the candidate's repo/base/head.
- `number:` integer comparison: `>N >=N <N <=N`, `A..B`, `A..*`, `*..B`, or exact; error "`number:x` — a number, or >100, <100, 10..20."
- `created: updated: merged:` compare the date (first 10 chars -> Date) of `created_at / updated_at / merged_at`; a nil date never matches. Value syntax as above; dates are `YYYY-MM-DD` or `@today`, `@today±Nd|w|m|y` (w=7 days; m/y calendar-month shifts clamped to month end); a bare date means that exact day; `A..B` inclusive. Error: "`key:v` — {bad} is not a date. Write 2025-08-05, or @today, or @today-30d, and compare with > < >= <= or a .. range."
- Unknown key: "`key:v` — I do not know the qualifier `key`. I know is, state, draft, repo, base, head, number, created, updated, merged, and a bare word matches the title."
- Empty/blank query keeps everything.
- `Query.hint(text)`: first match of `\b(created|updated|merged):([^\s<>=]\S*)`; value contains ".." -> nil; else `%{was: "key:value", try: "key:>value"}`.
- `Query.expand(text)` (applied to GitHub search text only): replace each `@today(?:[+-]\d+[dwmy])?(?![\w-])` (case-insensitive) with the ISO date it denotes (UTC today); unparseable left as typed.

### Event `import` (submit of #im-settings)
Folder semantics here are unchanged: blank folder box = loose (`Bulk.land` gets no folder), even though the box's placeholder now reads "left empty, named for what the files have in common" (copy carried over from the files form; inaccurate for this path).
`picked = candidates.filter(key in chosen)` -- in `candidates` order (current sort), not click order.
- `[]` -> `error: "Nothing is selected."`
- `len > 200` -> `error: "That is {n} pull requests, and the ceiling is 200 in one go. Narrow it and run it again — importing twice into the same folder skips what is already there."`
- else capture `lv = self()`, `user_id`, `token`, `commits`, `files`; `opts = [folder: assigns.folder, number: assigns.number]`; assign `step: :running, working: true, phase: :fetching, error: nil, progress: {0, length(picked)}` and `start_async(:import, ...)` running:
  1. `%{documents: docs, failed: failed} = api().documents(picked, token, commits: commits, files: files, on_item: fn _c, total -> send(lv, {:tick, :fetching, total}) end)`
  2. `send(lv, {:phase, :landing, length(docs)})`
  3. `landed = Bulk.land(user_id, docs, folder: opts.folder, number: opts.number, on_item: fn _title, _i, total -> send(lv, {:tick, :landing, total}) end)`
  4. returns `{landed, failed}`.

### Events: files
- `validate`: no-op. `drop_file` (`ref`): `cancel_upload(:docs, ref)`.
- `import_files` (`folder`, `number`): `number = (params["number"] == "true")`. `docs = consume_uploaded_entries(:docs, ...)` -> `[%{title: Path.rootname(client_name), body: File.read!(path), source_url: nil}]` (completed uploads only), then `Bulk.in_name_order(docs)`.
  - Folder box semantics (changed): `folder = trim(params["folder"] || "")`; if blank, `folder = Bulk.folder_name_for(titles of docs)`. Dropped files are never loose any more.
  - `Bulk.in_name_order(docs)`: natural, case-insensitive sort on title. Split the lowercased title on `(\d+)` keeping the captures; a digit run becomes `{0, n, ""}` (compared as an integer), other text `{1, 0, text}`; lists compare elementwise. So "chapter-2" sorts before "chapter-10". Numbering (`number` ticked) follows this order, so chapter-01..07 become "1. chapter-01" .. "7. chapter-07" (previously they came out reversed, in browser order).
  - `Bulk.folder_name_for(titles, now)`: stem = longest common grapheme prefix of all titles (one title -> itself; none -> ""), then strip trailing characters matching `[\s\d._-]+$`, then trim. Stem length >= 3 -> the folder is the stem (chapter-01..07 -> "chapter"); else `"Imported " <> strftime(now UTC, "%Y-%m-%d %H:%M")`. A single file "notes.md" -> folder "notes".
  - `[]` -> `error: "No files yet — drop some in."` (the folder name is computed before this check; harmless)
  - else assign `step: :running, working: true, phase: :landing, error: nil, folder, number, progress: {0, length(docs)}` and `start_async(:import, fn -> landed = Bulk.land(user_id, docs, folder: folder, number: number, on_item: fn _t,_i,total -> send(lv, {:tick, :landing, total}) end); {landed, []} end)`.

### Progress messages (handle_info)
- `{:tick, phase, total}`: `{done,_} = progress; done = (assigns.phase == phase ? done+1 : 1)`; assign `phase`, `progress: {done, total}`. Fetch ticks come from up to 6 concurrent tasks, each adding 1.
- `{:phase, phase, total}`: assign `phase`, `progress: {0, total}`.
No polling or timers.

### handle_async(:import)
- Clean import (changed): `{:ok, {%{folder: %{id: id}, failed: []} = landed, []}}` (a folder exists, no landing failures, no fetch failures; skips do not count) -> flash info `"{count(created,"draft","drafts")} imported"` + (skipped > 0 ? `", {skipped} already there and left alone."` : `"."`), then `push_navigate("/stacks/{id}")`. No results page. The folder page (section 6) holds read / read each / relate / summarise / compose. A file import always has a folder, so a clean one always navigates; a clean GitHub import with a blank folder box (loose, `folder: nil`) still falls through to the results page.
- Otherwise (any `failed`, any `missed`, or no folder): `{:ok, {landed, missed}}` -> `step: :done, working: false, phase: nil, result: landed, missed: missed`.
- `{:exit, reason}` -> `step: :done, working: false, phase: nil, error: "The import crashed: {inspect(reason)}"` (result stays nil).
`start_async` is tied to the LiveView process: leaving the page kills the import mid-way (works already created remain; re-running skips them by title).

### Context function detail

`GitHub.list(owner, repo, token, state: s)`: owner and repo each must match `^[A-Za-z0-9._-]{1,100}$` else `{:error, :bad_name}`; `GET https://api.github.com/repos/{o}/{r}/pulls?state={s}&per_page=100&page={1..5}` (max 500 PRs; stops at an empty page or one shorter than 100). Returns `{:ok, [candidate("o/r", pull)]}`. Headers: `accept: application/vnd.github+json`, `x-github-api-version: 2022-11-28`, `user-agent: marginalia`, plus `authorization: Bearer <token>` only when the trimmed token is non-empty. Receive timeout 20s. Status mapping: 200 ok; 401 `:unauthorized`; 403 or 429 -> `{:rate_limited, x-ratelimit-reset}` when `x-ratelimit-remaining == "0"` else `:forbidden`; 404 `:not_found`; 422 `{:rejected, errors[0].message || message || nil}`; other `{:http, s}`; transport `{:transport, inspect}`.

`GitHub.search(query, token)`: trim; "" -> `{:error, :empty_query}`; `Query.expand`; append " is:pr" unless the text contains "is:pr"; `GET /search/issues?q={form-urlencoded q}&per_page=100&page={1..5}`; collects `items` (stops on empty / short page; body without "items" -> `:no_results_field`); each item -> `candidate(repo_of(item), item)` with repo = text after "/repos/" in `repository_url`; state "merged" from `pull_request.merged_at`.

`GitHub.documents(candidates, token, commits:, files:, on_item:)`: `Task.async_stream`, `max_concurrency 6`, `timeout 120_000`, `on_timeout: :kill_task`, `ordered: true`. Per candidate: split `repo` into owner/name (validated), `GET /repos/o/n/pulls/{number}` (title, body, html_url, changed_files); if `commits`: `GET .../pulls/{n}/commits?per_page=100` -> `[{sha: first 8 chars, message: trimmed}]` (a failure is stored as `{:error, other}` and written into the document text, not a batch failure); if `files`: `GET .../pulls/{n}/files?per_page=100` -> `[{path, was, status, added, removed}]` (same failure handling). `on_item(c, total)` is called when each candidate finishes (success or failure). Returns `%{documents: [%{number, repo, title, body: document(item), source_url: html_url}], failed: [{candidate, reason}]}` (reason may be `{:crashed, inspect}`), order preserved.

`GitHub.document(item)` = writeup + file_list + commit_trail:
- writeup: trimmed body, or if blank `"_This pull request (#N) has no description._\n\n{url}\n"`.
- file_list (only if files were requested): none -> ""; error -> `"\n\n---\n\n## Files changed\n\n_The file list could not be fetched ({inspect reason}), so this says nothing about what was touched._\n"`; else `"\n\n---\n\n## Files changed ({head})\n\n"` + up to 60 lines joined by "\n"; head = `total` (changed_files or listed count) or `"{total}, the first {shown} listed"` when truncated. Line forms: renamed `- \`was\` → \`path\`{counts}`; added `- \`path\`{counts} — new`; removed `- \`path\`{counts} — deleted`; else `- \`path\`{counts}`. counts: "" if 0/0; " +a" ; " −r" (U+2212); " +a −r".
- commit_trail (only if commits were requested): none -> ""; error -> `"\n\n---\n\n## Commits\n\n_The commit trail could not be fetched ({inspect reason}), so this chapter is its description alone._\n"`; else `"\n\n---\n\n## Commits ({n})\n\n"` + entries joined by "\n\n", each `### {subject}  ({sha})` (two spaces before the paren) plus `\n\n{rest of message}` when present, truncated to 7000 chars with `"\n\n_[commit trail truncated]_"`, then "\n".

`Bulk.land(user_id, docs, folder:, number:, on_item:)` -> `%{folder: %Folder{}|nil, created: [%Work{}], skipped: [title], failed: [{title, reason}]}`:
1. Folder: name trimmed; ""/nil -> no folder (works stay loose at root). Else look up a folder of this user whose `name` equals it exactly at ANY depth (`Repo.one`, no parent filter; raises if two folders share the name in different parents) or create it at root via `Folders.create_folder`; creation failure -> nil (loose).
2. `have` = set of titles of works already in that folder.
3. Sequentially for each doc (1-based index i): `title = number ? (clean(title) if it already matches ^\s*\d+\s*[.):-], else "#{i}. #{clean(title)}") : clean(title)`. `clean`: nil/blank -> "Untitled"; whitespace runs -> one space; trim; cut to 200 chars. Index i is the position among docs AFTER fetch failures were removed.
   - title in `have` -> skipped.
   - else `Upload.prepare(title, doc.body, nil)` (`:empty`, `{:too_long, n}` as failures), then `Works.create_work(user_id, attrs + "source_url" => doc.source_url)`; if a folder exists, `Folders.move_work(user_id, work.id, folder.id)`. A changeset error becomes the string `"{field} {msg}"`; `:no_sections` is a failure.
   - After each doc `on_item(title, i, total)` fires, whatever the outcome. `have` is not updated as it goes, so duplicate titles inside one batch are both created.
4. `Bulk.explain(reason)`: `:empty` "there is no text in it"; `{:too_long, w}` "{w} words, over the limit"; `:no_sections` "no text that could be split into sections"; binary as is; else `inspect`.

`GitHub.explain(reason)` copy: `{:many_roots, ns}` "N pull requests are based on the default branch (#a, #b). That is more than one stack, and this cannot tell which you meant."; `{:no_root, b}` "No open pull request is based on {b}, so there is no start to the chain."; `{:off_chain, ns}` "N pull request(s) are not on the chain: #a, #b. A stack is each one based on the one before it."; `{:duplicate_branches, refs}` "More than one open pull request comes from the same branch ({refs joined ', '}). A stack is one pull request per branch."; `:no_pull_requests` "That repository has no open pull requests."; `:empty_query` "Write a search query first."; `{:rejected,nil}` "GitHub would not run that search. Check the qualifiers and the dates."; `{:rejected,s}` "GitHub would not run that search: {s}"; `:no_results_field` "GitHub answered the search with something this does not recognise."; `{:crashed,_}` "That one crashed on the way in."; `:unauthorized` "GitHub rejected the token."; `:forbidden` "GitHub refused: the token may lack access, or you are rate limited. Without a token that is 60 requests an hour, and 10 searches a minute."; `{:rate_limited, reset}` "GitHub is rate limiting this. {back_at} Without a token the allowance is 60 requests an hour; with one it is 5000, and a hundred pull requests is three hundred requests." with back_at = "It comes back at HH:MM UTC, in {m}m{s}s." (from the unix `reset`, wait floored at 0) or "Give it a few minutes."; `:not_found` "No such repository, or the token cannot see it."; `:bad_name` "Owner and repository must look like GitHub names."; `{:http,s}` "GitHub answered {s}."; `{:transport,_}` "Could not reach GitHub."; else "Import failed: {inspect}".

---------------------------------------------------------------------------------------------------

## 4. /stacks -- StackLive.Index (live_action :index)

### Mount
`page_title: "Methods"`. `load`:
- `Folders.tree(user_id)` flattened depth-first (parent before its children, siblings in tree order) to `[{folder, depth}]`.
- Each becomes `%{folder, depth, stats: Stacks.stats(user_id, folder.id)}`; rows with `stats.documents == 0` are dropped. (`documents` counts works whose `folder_id` is exactly that folder, not subfolders.)
- `Stacks.stats/2` keys: `documents, read, stale, pitfalls, excerpts, links, dropped, summarised, mapped, related, deepened, deep_failed, revisions, deep_dropped` (defined in section 6).
Assign: `rows`.

### Render (`max-w-3xl`)
```html
<div class="mx-auto max-w-3xl px-6 py-10">
  <div class="flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4">
    <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">Methods</h1>
    <span class="mg-meta">{length(rows)} readable folders</span>
    <a href="/import" class="mg-btn sm ghost ml-auto">Import many</a>
    <a href="/stacks/new" class="mg-btn sm">Import a stack</a>
  </div>
  <p class="mg-meta mt-4 leading-relaxed">A folder of documents that build one thing, read <em>forwards</em>: each document told
    only what the ones before it established. What comes back is what somebody building
    the same thing would have to do, in order.</p>
  <p :if={rows == []} class="mg-empty mt-8">Nothing here yet. Put some drafts in a folder and it becomes readable.</p>
  <div class="mg-rows mt-2">
    <div :for={r <- rows} class="cut-row" style="padding-left:{r.depth*1.4}rem">
      <div class="min-w-0 flex-1">
        <a href="/stacks/{r.folder.id}" style="font-family:var(--mg-serif)" class="text-[1.05rem] hover:text-[var(--mg-accent)]">{r.folder.name}</a>
        <div class="mg-meta mt-0.5">{stats.documents} documents
          <span :if={stats.read > 0}>· {stats.read} read</span>
          <span :if={stats.pitfalls > 0}>· {stats.pitfalls} pitfalls</span>
          <span :if={stats.stale > 0} class="cut-err">· {stats.stale} stale</span></div>
      </div>
      <span :if={stats.read == stats.documents} class="mg-badge ink">read</span>
    </div>
  </div>
</div>
```
No events, no async. No pluralisation logic ("1 documents", "1 readable folders").

---------------------------------------------------------------------------------------------------

## 5. /stacks/new -- StackLive.New (live_action :new): import one strict PR chain

### Mount
Assigns: `page_title: "Import a stack"`, `repo: ""`, `token: ""` (never updated), `folder: ""`, `state: "open"`, `working: false`, `progress: nil`, `error: nil`.

### Render (`max-w-xl`)
```html
<div class="mx-auto max-w-xl px-6 py-10">
  <div class="mg-meta"><a href="/stacks">← every method</a></div>
  <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">Import a stack</h1>
  <p class="mg-meta mt-2 leading-relaxed">A stack is pull requests each based on the one before it, so the series reads in
    order. The order is taken from that chain, not from the numbers — and if the
    repository is not a stack, this says which pull requests break it rather than
    importing them in a guessed order.</p>
  <form phx-submit="import" phx-change="form" class="mt-6 space-y-4">
    <label class="mg-field"><span class="mg-label">Repository</span>
      <input type="text" name="repo" value="{repo}" placeholder="owner/name" autocomplete="off" class="mg-input"/></label>
    <label class="mg-field"><span class="mg-label">GitHub token</span>
      <input type="password" name="token" value="" autocomplete="off" placeholder="used for this fetch, never stored" class="mg-input"/>
      <span class="mg-meta">Needs only read access to the repository. It is used for the request and thrown away.</span></label>
    <label class="mg-field"><span class="mg-label">Folder name</span>
      <input type="text" name="folder" value="{folder}" placeholder="{repo == '' ? 'defaults to owner/name' : repo}" autocomplete="off" class="mg-input"/></label>
    <label class="mg-field"><span class="mg-label">Which pull requests</span>
      <select name="state" class="mg-select"><option value="open" selected?>Open</option><option value="all" selected?>All, open and closed</option></select></label>
    <p :if={@error} class="cut-err">{@error}</p>
    <div class="flex items-center gap-3">
      <button class="mg-btn" type="submit" disabled={@working}>{working ? "Importing…" : "Import"}</button>
      <span :if={working and progress} class="mg-meta">{done} document{done == 1 ? "" : "s"} saved</span>
    </div>
  </form>
  <p class="mg-meta mt-8 leading-relaxed">If the repository is not a stack, or you only want some of it,
    <a href="/import">import in bulk</a>
    instead: that lists the pull requests first and lets you pick, and asks nothing
    about the shape they are in.</p>
  <p class="mg-meta mt-4 leading-relaxed">Importing saves each pull request's description as a draft, in order, in a folder.
    Nothing is read yet — that is the next three buttons on the folder's page.</p>
</div>
```

### Events
- `form` (phx-change): `repo = params["repo"] || ""`, `folder`, `state = params["state"] || "open"`, `error: nil`. Token not stored.
- `import` (submit; params `repo, token, folder, state`): trim each; `lv = self()`. Split `repo` on the first "/":
  - two non-empty parts -> `working: true, error: nil, progress: {0, nil}, repo, folder`; `start_async(:import, fn -> GitHub.import_stack(user_id, owner, name, token, folder: (folder == "" ? nil : folder), state: params["state"] || "open", on_item: fn _item, total -> send(lv, {:imported, total}) end) end)`
  - else `error: "Write the repository as owner/name.", repo: repo`.
- `handle_info({:imported, total})`: `{done, _} = progress || {0, total}`; `progress = {done+1, total}`.
- `handle_async(:import)`:
  - `{:ok, {:ok, %{folder, created: made, total}}}` -> `working: false`, flash info (`made == total ? "Imported {made} documents." : "{made} new, {total-made} already there."`), `push_navigate("/stacks/{folder.id}")`.
  - `{:ok, {:error, reason}}` -> `working: false, progress: nil, error: GitHub.explain(reason)`
  - `{:exit, reason}` -> `working: false, progress: nil, error: "The import crashed: {inspect(reason)}"`

### `GitHub.import_stack(user_id, owner, repo, token, folder:, state:, on_item:)`
1. `stack/4`: validate owner/repo names; `GET /repos/o/r` -> `default_branch` (missing -> `:no_default_branch`); list pulls (`state` open|all; 100/page; <=5 pages); `order(pulls, default)`; then for EACH item `GET .../pulls/{n}/commits?per_page=100` sequentially (failure recorded in the document, not fatal).
   `order/2`: `[]` -> `:no_pull_requests`; two PRs with the same `head.ref` -> `{:duplicate_branches, sorted refs}`; roots = PRs whose `base.ref == default`: none -> `{:no_root, default}`, more than one -> `{:many_roots, [numbers]}`; walk from the root: next = PR whose `base.ref == current.head.ref` (map keyed by base ref), stopping on repeat; any PR not visited -> `{:off_chain, [numbers]}`; else items `%{ordinal: 1.., number, title, body: body || "", url: html_url}`.
2. Folder: the user's folder named `opts.folder || "owner/repo"` (exact name, any depth, `Repo.one`), else `Folders.create_folder(user_id, %{name: ...})` at root. A name error propagates as `{:error, changeset}` (page shows "Import failed: ...").
3. Existing titles in that folder are collected; for each item whose `title_for(item)` is not present (`title_for` = title if it already matches `^\s*\d+\s*[.):-]`, else `"#{ordinal}. #{title}"`): `Works.create_work(user_id, %{"title", "body" => document(item) (commit trail, no file list), "source_url" => url})` (asserted `{:ok,_}`; a failure crashes the task), `Folders.move_work(...)`, `on_item(item, total_items)`.
4. Returns `{:ok, %{folder, created: n_created, total: n_items}}`. Idempotent on title. `on_item` fires only for created items, so the "N documents saved" counter does not reach `total` on a re-import.

---------------------------------------------------------------------------------------------------

## 6. /stacks/:id and /stacks/:id/:ordinal -- StackLive.Show (actions :show, :step)

One LiveView, two renders: the first `render/1` clause matches when `assigns.ordinal` is an integer (step page), the second is the folder page.

### Mount (`%{"id" => id}`)
- `Folders.get_folder(user_id, id)` (id parsed strictly as an integer; non-integer or not owned -> nil). nil -> flash error "No such folder." + `push_navigate("/stacks")`.
- Else, if connected, `Runs.subscribe({:stack, folder.id})` (PubSub topic `"run:{:stack, ID}"` on `Marginalia.PubSub`). Assign `folder`; `from_run(socket, Runs.get({:stack, folder.id}))`; `load`.
- `Runs.get(key)`: ETS lookup of `%{kind, done, total, stage, pid, started_at}` or nil.
- `from_run(socket, run)` derives four assigns:
  - nil -> `reading: nil, running: nil, composing: false, stage: nil`
  - kind `:compose` -> `reading: nil, running: :compose, composing: true, stage: stage_of(run)`; `stage_of`: stage "outlining" -> "outlining"; stage "writing" with integer total -> "part {done} of {total}"; else nil.
  - kind in `[:read, :deepen, :summarise, :relate, :read_each]` -> `reading: {run.done, run.total || 0}, running: kind, composing: false, stage: nil`.
- `load/1` assigns: `page_title: folder.name`, `story: Stacks.get_story(folder.id)` (`%Story{title, opening, movements, closing, uncovered, dropped, fingerprint}` or nil), `guide: Stacks.guide(folder.id)`, `documents: Stacks.documents(user_id, folder.id)`, `stats: Stacks.stats(user_id, folder.id)`.
- `handle_params`: `ordinal = params["ordinal"] && String.to_integer(params["ordinal"])` (nil on :show; non-numeric raises). Links between steps are `navigate` (a fresh mount each).

Data shapes:
- `Stacks.documents(user_id, folder_id)`: works of the user with `folder_id` = this folder (direct children only), in `Stacks.order`: if EVERY title starts with `^\s*(\d+)\s*[.):-]` and the numbers are all distinct, sorted by that number; otherwise by work id ascending.
- `Stacks.list_steps(folder_id)`: `stack_steps` rows ordered by `ordinal`, `work` preloaded. Step fields: `ordinal, capability, requires [ordinals], lesson, pitfall, pitfall_quote, excerpts [%{"text","caption"}], fingerprint, dropped [str], mechanism, watch_for, revised_by (ordinal|nil), revision, revision_quote, deep_dropped [str], deepened_at, folder_id, work_id`.
- `Stacks.guide(folder_id)`: per step `%{step, requires: [steps whose ordinal in step.requires (existing only)], required_by: [steps whose requires include this ordinal, by ordinal], previous: step ordinal-1 | nil, next: step ordinal+1 | nil}`.
- `Stacks.stats(user_id, folder_id)`: `documents` = len(documents); `read` = number of steps; `stale` = documents with a step whose stored fingerprint != sha256-hex of the work's section bodies joined by "\n\n" cut to the body cap; `pitfalls` = steps with non-empty pitfall; `excerpts` = sum len(excerpts); `links` = sum len(requires); `dropped` = sum len(dropped); `summarised` = count of `document_summaries` rows for these works with non-empty summary; `mapped` = documents with `status == "read"`; `related` = count of `links` rows with both ends inside these documents; `deepened` = steps with `deepened_at`; `deep_failed` = steps with no `deepened_at` and some `deep_dropped` entry starting "the second pass failed"; `revisions` = steps with `revised_by`; `deep_dropped` = sum len.
- `Stacks.story_current?(story, folder_id)`: `story.fingerprint == sha256_hex(join("\n", steps.map("#{ordinal}|#{capability}|#{lesson}|#{mechanism}|#{pitfall}|#{revised_by}")))` (nil -> "").

### Folder page render (`max-w-3xl`)
```html
<div class="mx-auto max-w-3xl px-6 py-10">
  <div class="mg-meta"><a href="/stacks">← every method</a></div>
  <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">{folder.name}</h1>
  <div class="mg-meta mt-1">
    {documents} documents · {read} read · {summarised} summarised · {mapped} mapped · {related} related · {pitfalls} pitfalls · {links} dependencies
    <span :if={deepened > 0}>· {deepened} deepened · {revisions} revised later</span>
    <span :if={deep_failed > 0} class="cut-err">· {deep_failed} failed the second pass</span>
    <span :if={dropped > 0}>· {dropped} claims dropped</span>
  </div>

  <div class="mt-5 flex items-center gap-3">
    <button class="mg-btn" phx-click="read" disabled={reading != nil or composing}>{read > 0 ? "Read forwards again" : "Read forwards"}</button>
    <button :if={read > 0} class="mg-btn ghost" phx-click="deepen" disabled=D>
      {deep_failed > 0 ? "Retry {deep_failed} failed" : deepened > 0 ? "Deepen again" : "Second pass"}</button>
    <button :if={mapped < documents} class="mg-btn ghost" phx-click="read_each" disabled=D>
      Read each document{mapped > 0 ? " ({documents - mapped} left)" : ""}</button>
    <button :if={documents > 1 and mapped > 1} class="mg-btn ghost" phx-click="relate" disabled=D>
      {related > 0 ? "Relate them again" : "Relate the documents"}</button>
    <button :if={documents > summarised} class="mg-btn ghost" phx-click="summarise" disabled=D>
      {summarised > 0 ? "Summarise the other {documents - summarised}" : "Summarise each document"}</button>
    <button :if={read > 0} class="mg-btn ghost" phx-click="compose" disabled=D>
      {composing and stage ? "Composing — {stage}" : composing ? "Composing…" : story ? "Compose again" : "Compose the telling"}</button>
    <span :if={@reading} class="mg-meta">{done} of {total} — {pass_note(@running)}</span>
  </div>
  <!-- D = (reading != nil or composing) -->

  <p :if={@composing} class="mg-meta mt-2"><b :if={@stage}>Composing — {@stage}.</b>
    Composing runs on the server too. Leave, come back, open it on your phone — the
    page finds the pass still going. A deploy is the one thing that stops it.</p>

  <p :if={@reading} class="st-progress" style="--done:{pct}"><span></span></p>      <!-- pct = "NN%" = round(done/total*100) if total > 0, else "0%" -->

  <!-- if guide == [] -->
  <p class="mg-empty mt-8">Not read yet. Reading is one call per document, in order, because each one is told
    what the ones before it established.</p>
  <ol class="st-docs mt-4"><li :for={{w,i} <- documents, i from 1}><span class="n">{i}</span>{w.title}</li></ol>

  <!-- else -->
  <div :if={@story} class="st-story-card">
    <div class="mg-label">The telling</div>
    <a href="/stacks/{folder.id}/story" class="t">{story.title}</a>
    <div class="mg-meta">{length(story.movements)} parts
      <span :if={story.uncovered != []} class="cut-err">· {length(uncovered)} steps left out</span>
      <span :if={not story_current?} class="cut-err">· stale</span></div>
    <div class="mg-meta st-publish">
      <!-- folder.published_at set -->
      public at <a href="/reading/{folder.slug}">/reading/{folder.slug}</a>
      <button phx-click="unpublish" class="mg-btn sm ml-2">Make private</button>
      <!-- else -->
      <button phx-click="publish" data-confirm="Publish this stack? Anyone with the link will be able to read the telling and every step of it." class="mg-btn sm">Publish</button>
      <span class="ml-2">private — only you can read it</span>
    </div>
  </div>

  <h2 class="cut-h">The method</h2>
  <ol class="st-chain">
    <li :for={e <- guide} class="has-pitfall|(empty)">     <!-- "has-pitfall" iff step.pitfall is non-nil (Elixir truthiness: "" counts) -->
      <a href="/stacks/{folder.id}/{ordinal}"><span class="n">{ordinal}</span><span class="c">{capability}</span></a>
      <span :if={e.requires != []} class="dep">needs {requires ordinals joined ", "}</span>
      <span :if={e.step.revised_by} class="dep rev">revised by {revised_by}</span>
    </li>
  </ol>
  <p class="mg-meta mt-5">Start at step 1. Every step links back to what it stands on and forward to what
    stands on it.
    <span :if={stats.deepened == 0}>The second pass adds how each one works, what to get right now, and where a
      later step walks it back — none of which the first pass can see.</span></p>
</div>
```
`pass_note(kind)`:
- `:read_each` "the ordinary read of each one, sections at a time. This runs on the server: you can close the page."
- `:relate` "one call per pair, three at a time, over both their graphs. This runs on the server: you can close the page."
- `:summarise` "one whole-document summary each, sections six at a time. This runs on the server: you can close the page."
- anything else (`:read`, `:deepen`) "each document waits on the one before it. This runs on the server: you can close the page."
The "Composing" button label is built in one expression (do not wrap across lines: HEEx keeps the newline). The story card (with publish/unpublish) appears only when a story exists AND the folder has been read (guide non-empty).

### Step page render (`max-w-2xl`)
`entry = guide.find(e.step.ordinal == ordinal)`.
```html
<div class="mx-auto max-w-2xl px-6 py-10">
  <div class="mg-meta"><a href="/stacks/{folder.id}">← {folder.name}</a></div>
  <!-- if entry -->
  <div class="st-step-head">
    <span class="n">Step {ordinal} of {stats.read}</span>
    <h1 style="font-family:var(--mg-serif)">{step.capability}</h1>
    <div class="mg-meta">from <a href="/works/{step.work.slug}">{step.work.title}</a></div>
  </div>
  <h2 class="cut-h">What to do</h2><p class="st-lesson">{step.lesson}</p>
  <div :if={step.mechanism}><h2 class="cut-h">How it works</h2><p class="st-lesson">{step.mechanism}</p></div>
  <div :if={step.watch_for}><h2 class="cut-h">Get this right now</h2><p class="st-watch">{step.watch_for}</p></div>
  <div :if={step.revised_by}>
    <h2 class="cut-h">A later step walks this back</h2>
    <p class="st-pitfall">{step.revision}</p>
    <blockquote class="st-quote">{step.revision_quote}</blockquote>
    <p class="mg-meta mt-1"><a href="/stacks/{folder.id}/{step.revised_by}">read step {step.revised_by} →</a></p>
  </div>
  <div :if={step.pitfall}>
    <h2 class="cut-h">Why the obvious version is wrong</h2>
    <p class="st-pitfall">{step.pitfall}</p><blockquote class="st-quote">{step.pitfall_quote}</blockquote>
  </div>
  <div :if={step.excerpts != []}>
    <h2 class="cut-h">From the document</h2>
    <figure :for={x <- excerpts} class="st-excerpt"><pre><code>{x["text"]}</code></pre>
      <figcaption :if={x["caption"] not in [nil, ""]}>{x["caption"]}</figcaption></figure>
  </div>
  <div :if={entry.requires != []}><h2 class="cut-h">You need these first</h2><.chain items={entry.requires} folder={folder}/></div>
  <div :if={entry.required_by != []}><h2 class="cut-h">What this makes possible</h2><.chain items={entry.required_by} folder={folder}/></div>
  <nav class="st-nav">
    <a :if={entry.previous} href="/stacks/{folder.id}/{previous.ordinal}">← {previous.capability}</a>
    <span :if={no previous}></span>
    <a :if={entry.next} href="/stacks/{folder.id}/{next.ordinal}" class="next">{next.capability} →</a>
  </nav>
  <!-- else -->
  <p class="mg-empty mt-8">No step {ordinal} here.</p>
</div>
```
Elixir truthiness: `:if={step.mechanism}` etc. is true for any non-nil value including "" (a "" mechanism still renders its heading).
The step page has no events, but the same LiveView still gets `{:run, ...}` messages and calls `load` on progress.

Function component `chain/1` (private): attrs `items` (list of steps, required), `folder` (required).
```html
<ul class="st-links"><li :for={s <- items}><a href="/stacks/{folder.id}/{s.ordinal}"><span class="n">{s.ordinal}</span>{s.capability}</a></li></ul>
```

### Events (folder page)
All use `user_id = current_scope.user.id`, `id = folder.id`. The five passes (and compose) go through `run(socket, kind, fun)` -> `Runs.start({:stack, id}, kind, fun)`:
- `{:ok, _}` -> `from_run(socket, %{kind: kind, done: 0, total: (kind == :compose ? nil : stats.documents), stage: nil})` immediately (buttons disable at once).
- `{:error, {:already_running, other}}` -> `from_run(Runs.get(key))` and flash error `"A {other} pass is already running on this folder."`

`Runs.start` is a GenServer call: refuses if the key already has a run; otherwise `Task.Supervisor.async_nolink(Marginalia.TaskSupervisor, fun)` (not linked to the socket, survives the page closing), inserts `%{kind, done: 0, total: nil, stage: nil, pid, started_at}` into ETS, broadcasts `{:run, :started, run}`. The function's return value is broadcast as `{:run, :done, kind, result}` (keep it tiny); if the task dies, `{:run, :crashed, kind, reason}` (warning logged). The ETS entry is deleted in both cases. `Runs.progress(key, fields)` is an async cast that merges fields into the entry and broadcasts `{:run, :progress, run}`. `Runs.forget(key)` drops an entry.

| event | `total` captured | work function and return | progress |
|---|---|---|---|
| `read` | `stats.documents` | `Stacks.read_stack(user_id, id, on_step: fn _step, i, _t -> Runs.progress(key, done: i, total: total) end)` -> `{steps, errors}`; returns `{:errors, length(errors)}` | one model call per document, in order, each told the prior steps; writes `stack_steps` rows as it goes |
| `deepen` | `stats.read` | `Stacks.deepen_stack(id, on_step: fn _s, i, _t -> progress(done: i, total: total))` -> `{steps, errors}`; returns `{:errors, n}` | second pass over steps lacking `deepened_at` |
| `summarise` | `documents - summarised` | `Stacks.summarise_documents(user_id, id, on_step: fn _w,i,_t -> progress(done: i, total: total))` -> `{done, errors}`; `{:errors, n}` | skips already-summarised documents |
| `read_each` | `documents - mapped` | `Stacks.read_documents(user_id, id, on_step: ...)` -> `{done, errors}`; `{:errors, n}` | runs the ordinary read (`Analysis.run`) per unread document; a document with no nodes afterwards counts as an error |
| `relate` | - | `Links.Bulk.run(user_id, id, on_stage: fn stage -> progress(stage: stage) end, on_pair: fn _pair, total -> progress(done: bumped(key), total: total, stage: "relating") end)`; `{:ok, %{started, not_read}}` -> `{:related, len(started), len(not_read)}`; `{:error, r}` -> `{:error, r}` | `bumped` = current stored `done` + 1; first stage text "choosing the pairs" |
| `compose` | nil | `Stacks.compose(id, building: folder.name, on_stage: fn stage, done, total -> progress(stage:, done:, total:) end)`; `{:ok,_}` -> `:ok`, anything else passes through | stage "outlining" (done 0, total nil) then "writing" with done = parts finished, total = parts; `{:error, :not_read}` if no steps |

LLM prompts inside those context functions are outside this spec; the page needs only these contracts and the persisted shapes.

Other events:
- `publish`: `Folders.publish(user_id, folder.id)`: requires `Accounts.owner()` id == user_id (else `{:error, :not_owner}`); sets `published_at = now (UTC, second precision)` and `slug = existing slug || mint_slug(name)` (downcase; runs of non `[a-z0-9]` -> "-"; trim "-"; max 60; "stack" if empty; if that slug exists on another folder, append "-" + 6 url-safe-base64 chars of 3 random bytes). `{:ok, folder}` -> assign folder, flash info `"Published at /reading/{slug}"`. `:not_owner` -> flash error "Only the account this deploy belongs to can publish." Other -> "Could not publish: {inspect}".
- `unpublish`: `Folders.unpublish` (sets `published_at = nil`, keeps slug) -> assign folder, flash info "Taken off the public site."; error -> "Could not unpublish: {inspect}".

### handle_info (PubSub `{:run, ...}`)
- `{:run, :started, run}` -> `from_run(run)` (other tabs disable their buttons).
- `{:run, :progress, run}` -> `from_run(run)` then `load/1` (re-queries story/guide/documents/stats so new steps appear live). Fires once per `Runs.progress` call.
- `{:run, :done, :relate, {:related, made, 0}}` -> `from_run(nil)`, `load`, flash info `"Related {made} pair{s}."` (singular when made == 1).
- `{:run, :done, :relate, {:related, made, skipped}}` -> flash info `"Related {made}. {skipped} could not be: both documents have to have been read."`
- `{:run, :done, _kind, {:errors, 0}}` -> `from_run(nil)`, `load`, no flash.
- `{:run, :done, _kind, {:errors, n}}` -> flash error `"{n} document(s) did not read."`
- `{:run, :done, kind, {:error, reason}}` -> flash error `"The {kind} pass failed: {inspect(reason)}"` (kind as atom name, e.g. `compose`).
- `{:run, :done, _kind, _other}` (e.g. compose's `:ok`) -> `from_run(nil)`, `load`, no flash.
- `{:run, :crashed, kind, _}` -> `from_run(nil)`, `load`, flash error `"The {kind} pass crashed. What finished is saved."`
Flash set from a PubSub message appears on every open tab for that folder. No timers or polling. A page that mounts mid-run sees it via `Runs.get`, then follows broadcasts. At boot `Marginalia.Recovery` clears runs a deploy interrupted.

---------------------------------------------------------------------------------------------------

## 7. /stacks/:id/story -- StackLive.Story (live_action :story)

### Mount (`%{"id"}`)
- `folder = Folders.get_folder(user_id, id)`; `story = Stacks.get_story(folder.id)`. If either is nil: flash error "No telling for that folder yet." + `push_navigate("/stacks")`.
- Assigns: `page_title: story.title || folder.name`, `folder`, `story`, `steps: %{ordinal => step}` from `Stacks.list_steps(folder.id)`, `stale: not Stacks.story_current?(story, folder.id)`.
No PubSub or run state; static after mount.

### Render
```html
<article class="st-story">
  <div class="mg-meta"><a href="/stacks/{folder.id}">← {folder.name}</a></div>
  <h1>{story.title}</h1>
  <p class="mg-meta"><button phx-click="to-draft" class="mg-btn sm">Open as a draft</button>
     <span class="ml-2">a copy, read and annotated like any other manuscript</span></p>
  <p :if={@stale} class="cut-stale">The steps have been re-read since this was composed.</p>
  <p :if={story.uncovered != []} class="cut-stale">{n} step{n==1 ? "" : "s"} found no place in this telling: {uncovered joined ", "}. The composition
    is incomplete, not the stack.</p>
  <div class="lede md st-md">{Markdown.to_html(story.opening)}</div>
  <section :for={{m, i} <- movements, i from 1} class="st-move">
    <h2><span class="n">{i}</span>{m["heading"]}</h2>
    <div class="md st-md">{Markdown.to_html(m["prose"])}</div>
    <aside :if={m["turn"] not in [nil, ""]} class="st-turn md st-md">{Markdown.to_html(m["turn"])}</aside>
    <nav :if={m["steps"] != []} class="st-move-steps">
      <span class="mg-label">from</span>
      <a :for={n <- m["steps"]} href="/stacks/{folder.id}/{n}" title="{steps[n].capability, or 'step n' if missing}">{n}</a>
    </nav>
  </section>
  <div class="st-closing md st-md">{Markdown.to_html(story.closing)}</div>
  <p :if={story.dropped != []} class="mg-meta st-drops">{n} problem{n==1 ? "" : "s"} with the composition: {dropped joined "; "}</p>
</article>
```
Inside `Layouts.app`'s `main` padding; the article has no max-w utility (CSS class `st-story` supplies width). `story.movements` entries are maps with string keys `heading, prose, turn, steps (list of ordinals)`. Markdown uses hard line breaks here.

### Event `to-draft`
`Stacks.to_draft(user_id, folder.id)`: requires a story (else `{:error, :not_composed}`); `Works.create_work(user_id, attrs)` with `"title" => story.title || "A reading"`, `"intent" => "The method read out of {steps} documents, in {parts} parts. It is meant to tell somebody building the same thing what to do and in what order, so the test of any paragraph is whether it could be acted on."`, `"body" =>` `join("\n\n", [opening] ++ [for each movement i: join("\n", ["## {i}. {heading}", "", prose] ++ (turn non-empty ? ["\n> {turn}"] : []))] ++ ["## Closing", "", closing])` trimmed. The new work is deliberately NOT placed in the stack's folder (it would become document N+1 of the stack).
- `{:ok, work}` -> flash info "Opened as a draft. Read it the way you would anything else." + `push_navigate("/works/{work.slug}")`.
- `{:error, reason}` -> flash error `"Could not open it as a draft: {inspect(reason)}"`.

---------------------------------------------------------------------------------------------------

## 8. Hard to reproduce without LiveView

1. Server-owned UI state with diffed re-renders: `chosen`, `collapsed`, `renaming`, wizard `step`; no URL state or query params on any of these pages. Reloading ImportLive loses the wizard, fetched list, selection and token. Focused inputs are not overwritten by patches; unfocused ones are.
2. File uploads over the socket: `live_file_input`, `allow_upload`, `phx-drop-target`, `auto_upload` progress (ImportLive), submit-time upload (WorkLive.New), cancel by ref, per-entry and config-level error messages, `consume_uploaded_entries`.
3. `start_async` tasks plus `handle_info` progress ticks from background processes (ImportLive fetch/land, StackLive.New import, WorkLive.New URL fetch). Tasks die with the page.
4. PubSub run viewer (StackLive.Show): run state in ETS keyed `{:stack, folder_id}`, survives page close, shared across tabs, one run per key, each progress tick re-queries the DB, background messages raise flashes on every open tab.
5. Hook-driven drag and drop with server validation (`.Tree`) over a re-patched DOM.
6. Form semantics: `phx-change` per keystroke (300ms debounce on the pattern box), `phx-submit` fallbacks that stop native GETs, hidden+checkbox pairs, `phx-mounted={JS.focus()}`, `phx-window-keydown` + `phx-key`, `data-confirm`.
7. Flash + `push_navigate` across live navigations; guest minting on the HTTP pass; double mount.
8. Raw HTML only from sanitised comrak output (`Markdown.to_html`); all other interpolation is HTML-escaped.
