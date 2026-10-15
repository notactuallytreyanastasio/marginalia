# Marginalia web layer: cuts, links, user pages, endpoint

Scope: `CutLive.{Index,Show}`, `LinkLive.{Index,Read}`, `UserLive.{Login,Registration,Settings}`, `UserSessionController`, `Endpoint`, `MarginaliaWeb` (the `use` macros), `Telemetry`, `Gettext`, and the router entries for them. Source root: `lib/marginalia_web/`. Anything these pages render that lives elsewhere (`Layouts.app`, `LinkChat.bubble`, `LinkWaiting.waiting`, `Walk.overlay`, `CoreComponents.input/button/header/flash`) is specified here too, because the pages are not reproducible without it.

Blocks marked "verbatim" are copied by script from the source and are authoritative; prose around them is interpretation. HEEx reading notes: `{expr}` is an escaped interpolation; `:if`/`:for` are conditionals/loops; `class={[...]}` joins truthy entries with spaces; an attribute whose value is `nil` or `false` is omitted entirely (boolean `true` renders the bare attribute); `~p"/x"` is a path string; `<.link navigate=...>` renders `<a href=... data-phx-link="redirect" data-phx-link-state="push">` (a plain `<a href>` is the non-LiveView equivalent); `<.link patch=...>` is the same with `data-phx-link="patch"`; `<.link href=... method="delete">` renders `<a href data-method="delete" data-to=... data-csrf=...>`, which phoenix_html JS turns into a form submit with `_method=delete` and the CSRF token. Floats interpolated into attributes print Elixir-style (`260.0`, not `260`).

---

## 0. Cross-cutting

### 0.1 Pipeline, auth and layout per route

| Route | Module | live_action | Pipeline | Auth | live_session / on_mount |
|---|---|---|---|---|---|
| `GET /cuts` | `CutLive.Index` | `:index` | `:browser` + `:ensure_user_or_guest` | any user; guest minted if none | `:allow_guest` |
| `GET /cuts/:id` | `CutLive.Show` | `:show` | same | same | same |
| `GET /links` | `LinkLive.Index` | `:index` | same | same | same |
| `GET /links/:id` | `LinkLive.Read` | `:show` | same | same | same |
| `GET /links/:id/read` | `LinkLive.Read` | `:read` | same | same | same |
| `GET /users/log-in` | `UserLive.Login` | `:new` | `:browser` | none required | `:current_user` -> `:mount_current_scope` |
| `GET /users/register` | `UserLive.Registration` | `:new` | `:browser` | none required | `:current_user` |
| `POST /users/log-in` | `UserSessionController.create` | | `:browser` | none | |
| `DELETE /users/log-out` | `UserSessionController.delete` | | `:browser` | none | |
| `GET /users/settings` | `UserLive.Settings` | `:edit` | `:browser` + `:require_real_account` | non-guest account | live_session `:require_authenticated_user`, `on_mount: [{UserAuth, :require_real_account}]`, plus the module's own `on_mount {UserAuth, :require_sudo_mode}` |
| `GET /users/settings/confirm-email/:token` | `UserLive.Settings` | `:confirm_email` | same | same | same |
| `POST /users/update-password` | `UserSessionController.update_password` | | `:browser` + `:require_real_account` | non-guest account | |

`:browser` pipeline, in order: `accepts ["html"]`, `fetch_session`, `fetch_live_flash`, `put_root_layout html: {Layouts, :root}`, `protect_from_forgery` (CSRF check on every non-GET), `put_secure_browser_headers`, `fetch_current_scope_for_user`. (`:bare_browser` is identical but with root layout `:bare`; only the landing page uses it, so no page in this document does.)

The link/cut routes live in `scope "/"` with `pipe_through [:browser, :ensure_user_or_guest]`. Router comments worth keeping: the router takes the first match, not the most specific (`/stacks/new` is declared before `/stacks/:id`); `/links/:id` carries the comment "the split view is gone; /read stays an alias so links already sent to people keep working" (both routes mount the same LiveView).

**No ownership check on links.** `Links.get(id)` is a bare `Repo.get`, so any visitor (including a freshly minted guest) who knows a numeric link id can open `/links/:id`, `/links/:id/read`, subscribe to the PubSub topic and chat about it. `/cuts/:id` IS scoped: `Cuts.get_cut(user_id, id)` filters by user. Reproduce the asymmetry or close it deliberately. `Links.for_user` (the list page) is scoped to links where either work belongs to the user.

### 0.2 `ensure_user_or_guest` plug

If `conn.assigns.current_scope` has a user, pass through. Otherwise `Accounts.create_guest_user()` inserts a `users` row: `email = "guest-<22 url-safe-base64 chars>@guest.marginalia.local"`, random 32-byte password (bcrypt hashed), `confirmed_at = now`, `is_guest = true`. A session is created for it (session token row inserted, session cookie renewed) and the request continues with `current_scope = %Scope{user: guest}`. On failure: flash error `Something went wrong. Try logging in.`, redirect `/users/log-in`, halt. This runs on the dead (HTTP) render only; the websocket mount trusts the session.

### 0.3 `UserAuth.on_mount` variants used here

- `:allow_guest`: assigns `current_scope` from `session["user_token"]` (`Accounts.get_user_by_session_token`; `nil` scope when absent). If still no user: `redirect(to: "/users/log-in")`, halt, no flash.
- `:mount_current_scope`: assign only (scope may be `nil`).
- `:require_real_account`: no user -> redirect `/users/log-in`; `user.is_guest` -> flash info `Create an account to keep your drafts.`, redirect `/users/register`; else continue.
- `:require_sudo_mode`: `Accounts.sudo_mode?(user, -10)` (the session token's `authenticated_at` is within the last 10 minutes), else flash error `You must re-authenticate to access this page.`, redirect `/users/log-in`. No return-to is stored.

The HTTP plug `require_real_account` has the same logic, but the unauthenticated flash is `You must log in to access this page.` and (GET only) it stores `:user_return_to = current_path` in the session first.

`current_scope` is `nil` when logged out, else `%Scope{user: %User{}}`. `User` fields: `email, hashed_password, confirmed_at, is_admin, is_guest, seen_tours ([string]), llm_provider, authenticated_at (virtual; comes from the session-token row)`.

### 0.4 What `use MarginaliaWeb, :live_view` brings in

```
use Phoenix.LiveView
on_mount MarginaliaWeb.Freshness
use Gettext, backend: MarginaliaWeb.Gettext   # gettext/ngettext/dgettext
import Phoenix.HTML
import MarginaliaWeb.CoreComponents            # flash/1 button/1 input/1 header/1 table/1 list/1 icon/1 show/1 hide/1
alias Phoenix.LiveView.JS
alias MarginaliaWeb.Layouts                    # <Layouts.app>, <Layouts.flash_group>
use Phoenix.VerifiedRoutes                     # ~p sigil; statics = assets fonts images favicon.ico robots.txt
```

`:html` (used by `LinkChat`, `LinkWaiting`, `Walk`, `Layouts`) is `use Phoenix.Component` plus the same helpers. Every page here renders `<Layouts.app flash={@flash} current_scope={@current_scope}>`; the Read page adds `bleed`.

**Freshness** (on_mount for every LiveView): when the socket is connected and `static_changed?` (the `phx-track-static` asset URLs the page was rendered with differ from what the server serves now), it attaches a `handle_params` hook that does `redirect(socket, external: <current uri with _fresh=1 added to the query>)` unless the params already contain `_fresh` (a fuse against cache loops). Effect: a tab left open across a deploy hard-reloads once on its next live navigation/patch. Not needed without LiveView.

### 0.5 Root layout, head metadata, `Layouts.app`

Root layout (`components/layouts/root.html.heex`), verbatim:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <.head_meta
      page_title={assigns[:page_title]}
      page_description={assigns[:page_description]}
      page_robots={assigns[:page_robots]}
      page_image={assigns[:page_image]}
      page_image_alt={assigns[:page_image_alt]}
      page_url={assigns[:page_url]}
    />
    <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
    </script>
    <script>
      (() => {
        const systemTheme = () => matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

        const setTheme = (theme) => {
          if (theme === "system") {
            localStorage.removeItem("phx:theme");
            document.documentElement.setAttribute("data-theme", systemTheme());
            document.documentElement.setAttribute("data-theme-source", "system");
          } else {
            localStorage.setItem("phx:theme", theme);
            document.documentElement.setAttribute("data-theme", theme);
            document.documentElement.setAttribute("data-theme-source", "user");
          }
        };
        if (!document.documentElement.hasAttribute("data-theme")) {
          setTheme(localStorage.getItem("phx:theme") || "system");
        }
        window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "system"));
        window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme));

        matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
          if (document.documentElement.getAttribute("data-theme-source") === "system") {
            document.documentElement.setAttribute("data-theme", systemTheme());
          }
        });
      })();
    </script>
  </head>
  <body>
    <%!-- the account nav lives in the app layout's bar; the generated one
          here was a second, unstyled copy of it --%>
    {@inner_content}
  </body>
</html>
```

`head_meta/1` emits: `<title>` via `<.live_title default="Someone who has actually read the whole thing" suffix=" · Marginalia">{@page_title}</.live_title>`, so the title is `"<page_title> · Marginalia"`; `<meta name="robots" content=...>` only if `page_robots` is set; `description` (default: "Upload a draft. It reads end to end, maps what's on the page, and argues with you in the margin — a thread on any paragraph, anchored to your own sentences."); `og:type website`, `og:site_name Marginalia`, `og:title` (page_title or the tagline), `og:description`, `og:url` and `<link rel="canonical">` (default `Endpoint.url() <> "/"`), `og:image` (default `<url>/images/og.png`, width 2400, height 1260, long alt text beginning "Marginalia, a reader for drafts. A note in the margin reads: ..."), `twitter:card summary_large_image` plus title/description/image, `theme-color #fbfaf7`. The pages in this document only set `page_title`; `LinkLive.Read` also sets `page_robots: "noindex, nofollow"`. None sets `page_url`, so canonical/og:url is the site root on all of them.

`Layouts.app`, verbatim:

```heex
    <header class="mg-bar">
      <a href="/" class="mg-brand">Marginalia <span>a reader for drafts</span></a>
      <nav>
        <%!-- Cases is outside the branches: the collections are published
              deliberately and are readable by anyone, so hiding the way to
              them behind a login was hiding the only public thing here. --%>
        <.link navigate={~p"/cases"}>Cases</.link>

        <%!-- The scope exists for a signed-out visitor too, with no user
              in it. Testing the scope alone read as "logged in" and then
              dereferenced nil — which nothing hit only because every page
              using this layout minted a guest on arrival. --%>
        <%= cond do %>
          <% @current_scope && @current_scope.user && @current_scope.user.is_guest -> %>
            <.link navigate={~p"/works"}>Drafts</.link>
            <.link navigate={~p"/works/new"}>New draft</.link>
            <span class="text-[var(--mg-dim)] opacity-70">guest</span>
            <.link navigate={~p"/users/register"} class="mg-btn sm">Keep my drafts</.link>
          <% @current_scope && @current_scope.user -> %>
            <.link navigate={~p"/works"}>Drafts</.link>
            <%!-- a link belongs to two drafts and shows under both, so it
                  needs a place of its own to be listed --%>
            <.link navigate={~p"/links"}>Linked</.link>
            <.link navigate={~p"/cuts"}>Cuts</.link>
            <.link navigate={~p"/stacks"}>Methods</.link>
            <.link navigate={~p"/works/new"}>New draft</.link>
            <.link navigate={~p"/users/settings"}>{@current_scope.user.email}</.link>
            <.link href={~p"/users/log-out"} method="delete">Log out</.link>
          <% true -> %>
            <.link navigate={~p"/users/log-in"}>Log in</.link>
        <% end %>
      </nav>
    </header>

    <!--
      The generated layout pinned every page inside max-w-2xl, which is right
      for a settings form and wrong for a manuscript beside a chat panel: the
      work page was being squeezed into 640px and wrapping one word per line.
      Pages set their own width now; this only supplies the gutters.
    -->
    <main class={if @bleed, do: "", else: "px-4 py-8 sm:px-6 lg:px-8"}>
      <div class="space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
```

Nav by state. Logged out: `Cases`, `Log in`. Guest: `Cases`, `Drafts` (/works), `New draft` (/works/new), `<span class="text-[var(--mg-dim)] opacity-70">guest</span>`, `<a class="mg-btn sm">Keep my drafts</a>` (/users/register). Real user: `Cases`, `Drafts`, `Linked` (/links), `Cuts` (/cuts), `Methods` (/stacks), `New draft`, the user's email linking to /users/settings, `Log out` (DELETE /users/log-out). `<main>` gets classes `px-4 py-8 sm:px-6 lg:px-8` unless `bleed` (then `class=""`), and wraps the page in `<div class="space-y-4">`.

`flash_group`, verbatim:

```heex
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
```

`CoreComponents.flash/1` markup for a present flash of kind info/error:

```html
<div id="flash-info|flash-error" phx-click="(push lv:clear-flash key=kind, then hide #id)" role="alert" class="toast toast-top toast-end z-50">
  <div class="alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap alert-info|alert-error">
    <span class="hero-information-circle|hero-exclamation-circle size-5 shrink-0"></span>
    <div><p class="font-semibold">{title}</p> <p>{message}</p></div>   <!-- title paragraph only if a title -->
    <div class="flex-1"></div>
    <button type="button" class="group self-start cursor-pointer" aria-label="close"><span class="hero-x-mark size-5 opacity-40 group-hover:opacity-70"></span></button>
  </div>
</div>
```

Rendered only when a flash of that kind exists. Clicking it hides it and clears the key server-side. `#client-error` (title "We can't find the internet", body "Attempting to reconnect" + spinning `hero-arrow-path ml-1 size-3 motion-safe:animate-spin`) and `#server-error` (title "Something went wrong!", same body) start `hidden`; LiveView's `phx-disconnected` / `phx-connected` bindings show/hide them. `icon/1` renders `<span class="hero-NAME size-4"></span>` (Heroicons as CSS masks).

### 0.6 Form components used by the user pages

`<.input field={f[:x]} type=T label=L ...>` for ordinary types (text, email, password) renders:

```html
<div class="mg-field">
  <label for="{id}">
    <span class="mg-label block mb-1.5">{label}</span>              <!-- only if label -->
    <input type="{T}" name="{name}" id="{id}" value="{value}" class="mg-input [border-[var(--mg-accent)] when errors]" ...extra attrs/>
  </label>
  <p class="mt-1.5 flex gap-2 items-center text-sm text-error"><span class="hero-exclamation-circle size-5"></span> {msg}</p>  <!-- one per error -->
</div>
```

Pass-through attributes allowed on it: `accept autocomplete capture cols disabled form list max maxlength min minlength multiple pattern placeholder readonly required rows size step` plus global attrs (`phx-*`, `id`, etc.). `id`/`name` come from the form: for a form built from a changeset or `to_form(..., as: "user")` they are `user_email`/`user[email]`, `user_password`/`user[password]`, `user_password_confirmation`/`user[password_confirmation]`. Errors appear only once the field has been "used" (the client has sent a value for it via a `phx-change` or a submit). Password inputs always render `value=""`.

`<.button>`: no class, no variant -> `<button class="btn mg-btn ghost">`; `variant="primary"` -> `class="btn mg-btn"`; an explicit `class` replaces the default entirely. With `href`/`navigate`/`patch` it renders `<.link class=...>`. No `type` attribute is set (so it is a submit button inside a form).

`<.header>`:

```html
<header class="pb-4">   <!-- "flex items-center justify-between gap-6 pb-4" when an actions slot is given -->
  <div>
    <h1 class="text-lg font-semibold leading-8">{inner}</h1>
    <p class="text-sm text-base-content/70">{subtitle}</p>   <!-- only if subtitle slot -->
  </div>
  <div class="flex-none">{actions}</div>
</header>
```

### 0.7 Telemetry and Gettext

`MarginaliaWeb.Telemetry` is the stock Phoenix supervisor: a `:telemetry_poller` (period 10 s, no custom measurements) and `metrics/0` listing endpoint/router/socket/channel summaries, `marginalia.repo.query.*` summaries and `vm.memory.total` / run-queue summaries. It is only referenced by `/dev/dashboard` (LiveDashboard, `dev_routes` only). It renders nothing and can be dropped. `MarginaliaWeb.Gettext` is the stock backend (`use Gettext.Backend, otp_app: :marginalia`); the only gettext strings are framework ones ("We can't find the internet", "Attempting to reconnect", "Something went wrong!", aria-label "close", table "Actions"). No locale handling and no `.po` content to port: hard-code English.

### 0.8 Endpoint (`MarginaliaWeb.Endpoint`)

Plug order:

1. `socket "/live", Phoenix.LiveView.Socket` with `websocket: [connect_info: [session: @session_options]]` and `longpoll: [connect_info: [session: @session_options]]`. Client (`assets/js/app.js`): `new LiveSocket("/live", Socket, {longPollFallbackMs: 2500, params: {_csrf_token}, hooks: colocatedHooks})`, i.e. long-poll fallback if the websocket has not opened within 2.5 s; CSRF token read from `<meta name="csrf-token">`; topbar progress bar (colour `#29d`, shadow `rgba(0,0,0,.3)`) shown 300 ms after `phx:page-loading-start`.
2. `Plug.Static at: "/", from: :marginalia (priv/static), gzip: not code_reloading?, only: ~w(assets fonts images favicon.ico robots.txt)`. Anything whose first path segment is not in that list is never served statically. Present in `priv/static`: `favicon.ico`, `robots.txt`, `images/logo.svg`, `images/og.png`, `images/og-cases.png`. `assets/css/app.css` and `assets/js/app.js` are build outputs (esbuild + tailwind); `app.js` bundles `phoenix_html`, `phoenix`, `phoenix_live_view`, the colocated-hooks module `phoenix-colocated/marginalia` (every `<script :type={ColocatedHook}>` quoted below), and `vendor/topbar`. There is no `fonts/` directory at present.
3. dev only: LiveReloader, CodeReloader, `Phoenix.Ecto.CheckRepoStatus`.
4. `Phoenix.LiveDashboard.RequestLogger (param_key/cookie_key "request_logger")`, `Plug.RequestId`, `Plug.Telemetry [:phoenix, :endpoint]`.
5. `Plug.Parsers parsers: [:urlencoded, :multipart, :json], pass: ["*/*"]`, `Plug.MethodOverride` (so a POST with `_method=delete` is a DELETE), `Plug.Head`.
6. `Plug.Session`: `store: :cookie`, `key: "_marginalia_key"`, `signing_salt: "ZFoSjTaR"`, `same_site: "Lax"`. Signed, not encrypted (no `encryption_salt`): contents are readable but tamper-proof, keyed from `secret_key_base`. No `max_age` (browser-session cookie); no explicit `secure`/`http_only` (Plug default http_only true). Session keys in use: `_csrf_token`, `user_token` (raw 32-byte token), `live_socket_id` (`"users_sessions:" <> Base.url_encode64(token)`), `user_remember_me` (bool), `user_return_to` (path), `phoenix_flash`.
7. `MarginaliaWeb.Router`.

Other config to mirror: `live_view signing_salt: "DURe+zzB"` (LiveView's own token; irrelevant without LiveView); prod `force_ssl: [rewrite_on: [:x_forwarded_proto], exclude hosts localhost/127.0.0.1]` (redirect to https and HSTS header); prod public URL `https://<host>:443`; server adapter Bandit; dev `check_origin: false`.

Remember-me cookie (`UserAuth`): name `_marginalia_web_user_remember_me`, `sign: true` (value is the raw session token, signed with secret_key_base), `max_age` 14 days, `same_site: "Lax"`. Session-token DB validity is 14 days; a token older than 7 days seen on a request is replaced (new token row; session and remember-me cookie rewritten; `authenticated_at` carried over so sudo mode is not extended).

---

## 1. Cuts

A "cut" (shown to users as a "Reading") is one LLM reading of a folder of drafts: a thesis, through-lines, tensions, each backed by quotes from numbered members.

### 1.1 `/cuts` - `CutLive.Index`

**Mount** (`mount(_params, _session, socket)`): `assign(page_title: "Readings")` then `load/1`:

- `user_id = current_scope.user.id`
- `cuts = Cuts.list_cuts(user_id)` -> `[%Cut{}]`, this user's cuts, `updated_at` desc, `folder` preloaded. Cut fields: `id, title, question, status ("draft"|"reading"|"read"|"failed"), status_detail, thesis, threads [map], tensions [map], not_supported, dropped [string], content_sha, scope, members [map], user_id, folder_id`.
- `by_folder = %{folder_id => cut}`
- `Folders.tree(user_id)` -> `%{folders: [node], works: [work]}` where `node = %{folder: %Folder{id,name,parent_id}, folders: [node], works: [%Work{}], count: total drafts below}`. Folders are ordered by `lower(name), id`; the root's `works` are unfiled drafts.
- `rows(tree, by_folder, 0)` depth-first flatten (each folder, then its descendants), producing `%{folder, depth, works: length(f.works), subfolders: length(f.folders), count: f.count, cut: by_folder[f.folder.id] | nil}`.
- assigns: `rows`, `count = length(cuts)` (all cuts, any status).

There is no `handle_params`, no PubSub, no timers: the page does not refresh itself.

**Render**, verbatim:

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4">
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            Readings
          </h1>
          <span class="mg-meta">{@count} of {length(@rows)} folders read</span>
          <.link navigate={~p"/works"} class="mg-btn sm ghost ml-auto">Folders</.link>
        </div>

        <p :if={@rows == []} class="mg-empty mt-8">
          A reading is what a folder says that none of its drafts says alone. Make a folder
          on the drafts page and there will be something here to read.
        </p>

        <p :if={@rows != []} class="mg-meta mt-4 leading-relaxed">
          Read from the inside out. A folder of folders is read over what its children
          already found, so reading a case first makes the reading above it worth more.
        </p>

        <div class="mg-rows mt-2">
          <div :for={r <- @rows} class="cut-row" style={"padding-left:#{r.depth * 1.4}rem"}>
            <div class="min-w-0 flex-1">
              <span :if={r.cut} class="mg-badge ink mr-2">read</span>
              <.link
                :if={r.cut}
                navigate={~p"/cuts/#{r.cut.id}"}
                style="font-family:var(--mg-serif)"
                class="text-[1.05rem] hover:text-[var(--mg-accent)]"
              >{r.folder.name}</.link>
              <span
                :if={is_nil(r.cut)}
                style="font-family:var(--mg-serif)"
                class="text-[1.05rem] text-[var(--mg-dim)]"
              >{r.folder.name}</span>
              <div class="mg-meta mt-0.5">
                <%= if r.subfolders > 0 do %>
                  {r.subfolders} folders · {r.count} drafts below
                <% else %>
                  {r.works} drafts
                <% end %>
                <span :if={r.cut && r.cut.status == "read"}>
                  · {length(r.cut.threads)} through-lines
                </span>
                <span :if={r.cut && r.cut.status not in ["read", "draft"]}>· {r.cut.status}</span>
              </div>
            </div>
            <button class="mg-btn sm ghost" phx-click="read" phx-value-folder={r.folder.id}>
              {if r.cut, do: "read again", else: "read"}
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
```

Details: container `max-w-3xl`. Header counter reads `{count} of {total rows} folders read` (count is every cut row, including ones still `draft`/`failed`; kept as-is). Empty-state paragraph when no folders: "A reading is what a folder says that none of its drafts says alone. Make a folder on the drafts page and there will be something here to read." Otherwise the explanatory paragraph "Read from the inside out. A folder of folders is read over what its children already found, so reading a case first makes the reading above it worth more." Each row's left padding is `depth * 1.4` rem inline. Sub-line: if the folder has subfolders -> `"{n} folders · {count} drafts below"`, else `"{works} drafts"`; then ` · {k} through-lines` (k = length of `cut.threads`) only if the cut's status is `read`; then ` · {status}` if status is neither `read` nor `draft` (so `reading` or `failed`). The button reads `read again` if a cut exists, else `read`. Folder name links to `/cuts/:cut_id` only if a cut exists, otherwise it is dim non-link text.

**Events**

- `"read"` params `%{"folder" => id_string}`: `Cuts.open_folder_reading(user_id, String.to_integer(id))`. That looks up the user's folder (`Folders.get_folder`; nil -> `{:error, :not_found}`), then upserts the one cut for that folder with `title = folder.name, folder_id, scope "folder", status "draft"` (an existing cut is reset to status `draft`; previous results remain in the row until the next read overwrites them). On `{:ok, cut}` -> `push_navigate(to: "/cuts/<cut.id>")`. On error -> `put_flash(:error, "That folder is not yours.")`, stay. A non-integer id would raise (crash/remount).

### 1.2 `/cuts/:id` - `CutLive.Show`

**Mount** (`%{"id" => id}`): `Cuts.get_cut(user_id, id)` (scoped to user; preloads `folder`; a non-numeric id raises a cast error). Not found -> `put_flash(:error, "No such reading.")` + `push_navigate("/cuts")`. Found: assigns `page_title: cut.title`, `cut`, `focus: nil` (an integer member number or nil), then `assign_weave/1` (`members`, `links`), then `if cut.status == "draft", do: start_read(socket)`.

`start_read/1`: `Cuts.set_status(cut, "reading")` (persisted), assign the updated cut, and `start_async(:read, fn -> Cuts.read(cut, user_id) end)`. `Cuts.read` is one slow LLM call (effort high, max_tokens 8000): members = `Cuts.members(user_id, folder_id)` (empty -> sets status `failed`, detail "this folder holds nothing to read"); on LLM success it validates and stores `thesis, threads, tensions, not_supported, dropped, content_sha, members (maps with n,kind,id,label,read?), status "read"`; on LLM error it sets `failed` with `inspect(reason)`. It returns `{:ok, %Cut{}}` in both cases.

Hazard to be aware of: `start_async` only runs on a connected socket, but the `draft -> reading` DB write happens in mount on both the dead render and the connected mount. If a draft cut is opened by direct URL load (not via the Index's `push_navigate`, which mounts only once, connected), the dead render flips the row to `reading` and no task starts; the connected mount then sees `reading` and does not start one either, leaving "Reading this folder..." forever until the user presses nothing (there is no button in that state). The normal path (Index -> Read) is not affected.

`assign_weave/1`: `members` = `cut.members` if it is a non-empty list, else `Cuts.members(user_id, cut.folder_id)` mapped to string-key maps `%{"n","kind","id","label","read?"}`; `links = links(cut)`. `links/1`: only for `status == "read"`: for each group `{cut.threads, "thread"}`, `{cut.tensions, "tension"}`, for each item, take its distinct `evidence[*].member` numbers, and for every pair `a < b` emit `%{"a" => a, "b" => b, "kind" => "thread"|"tension"}`; any other status -> `[]`.

NB `render/1` re-assigns `members: cut.members || []` (the stored list), overriding what `assign_weave` computed. So while a cut has never completed (draft/reading/failed on first read) `cut.members` is `[]` and the weave and member list are NOT shown; they appear once a read has stored members and stay (stale) during a re-read. Also `render/1` computes `stale = cut.status == "read" and not Cuts.current?(cut, user_id)` on every render (`current?` recomputes the sha of the folder's current members: `sha256` hex of `"kind:id:text"` lines joined by `\n`; nil `content_sha` or no folder -> not current).

**Async**

- `handle_async(:read, {:ok, {:ok, _}})` -> `reload`: refetch `Cuts.get_cut`, reassign cut, weave.
- `handle_async(:read, {:ok, other})` -> `reload` + `put_flash(:error, "The read stopped: " <> inspect(other))`.
- `handle_async(:read, {:exit, reason})` -> `Cuts.set_status(cut, "failed", inspect(reason))`, assign it, `put_flash(:error, "The read crashed.")`.

**Events**

- `"again"` (no params): `start_read` (status -> `reading`, new task). Previous results remain on the cut but the `reading` branch hides them.
- `"focus"` `%{"n" => "3"}`: `n = String.to_integer`; toggles `focus` between `n` and `nil`.
- `"delete"`: `Cuts.delete_cut(cut)`, flash info `Reading deleted.`, `push_navigate("/cuts")`.

**Render**, verbatim (the colocated hook script is excluded here and quoted separately):

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="mg-meta"><.link navigate={~p"/cuts"}>← every reading</.link></div>
        <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">
          {@cut.title}
        </h1>
        <p :if={@cut.question not in [nil, ""]} class="cut-ask">{@cut.question}</p>

        <%!-- The read is asking whether anything holds across two or more of
              these, so while it runs the page draws pairs being tried, and
              when it lands the pairs that held stay drawn. Members first,
              because they are knowable before the answer is. --%>
        <div
          :if={@members != []}
          id={"weave-#{@cut.id}"}
          class="cut-weave"
          phx-hook=".Weave"
          phx-update="ignore"
          data-status={@cut.status}
          data-members={Jason.encode!(@members)}
          data-links={Jason.encode!(@links)}
        >
          <svg aria-hidden="true"></svg>
        </div>

        <%!-- who was read. Clicking one lights the claims that rest on it. --%>
        <div :if={@members != []} class="cut-members">
          <button
            :for={m <- @members}
            type="button"
            phx-click="focus"
            phx-value-n={m["n"]}
            class={"cut-member" <> if(@focus == m["n"], do: " on", else: "")}
          >
            <span class="i">{m["n"]}</span>
            <span class="l">{m["label"]}</span>
            <span :if={m["kind"] == "folder" and not m["read?"]} class="u">not read</span>
          </button>
        </div>
        <p :if={Enum.any?(@members, &(&1["kind"] == "folder" and not &1["read?"]))} class="cut-hole">
          Some of these have not been read yet, so this stands on their titles rather than
          on what they say. Read them first and this will be worth more.
        </p>

        <%= case @cut.status do %>
          <% "reading" -> %>
            <p class="cut-working">Reading this folder. One call, and it is the slow kind.</p>
          <% "failed" -> %>
            <p class="cut-err mt-6">
              {@cut.status_detail}
              <button class="mg-btn sm ghost ml-2" phx-click="again">try again</button>
            </p>
          <% "read" -> %>
            <p :if={@stale} class="cut-stale">
              This folder has changed since it was read.
              <button class="mg-btn sm ghost ml-2" phx-click="again">read again</button>
            </p>

            <h2 class="cut-h">Thesis</h2>
            <p class="cut-thesis">{@cut.thesis}</p>

            <.group title="Through-lines" items={@cut.threads} focus={@focus} />
            <.group title="Tensions" items={@cut.tensions} focus={@focus} />

            <div :if={@cut.not_supported not in [nil, ""]}>
              <h2 class="cut-h">What this does not show</h2>
              <p class="cut-body">{@cut.not_supported}</p>
            </div>
          <% _ -> %>
            <p class="cut-working">Queued.</p>
        <% end %>

        <div class="mt-10 flex flex-wrap items-center gap-2 border-t border-[var(--mg-rule)] pt-4">
          <button :if={@cut.status == "read"} class="mg-btn sm ghost" phx-click="again">
            read again
          </button>
          <span :if={@cut.dropped != []} class="mg-meta">
            {length(@cut.dropped)} claim{if length(@cut.dropped) == 1, do: "", else: "s"} dropped
            for quotes that could not be found
          </span>
          <button
            class="mg-btn sm ghost ml-auto"
            phx-click="delete"
            data-confirm="Delete this reading?"
          >delete</button>
        </div>
      </div>
```

`group/1` function component (private), with `shown/2`:

```heex
  defp group(assigns) do
    assigns = assign(assigns, :items, shown(assigns.items, assigns.focus))

    ~H"""
    <div :if={@items != []}>
      <h2 class="cut-h">{@title}</h2>
      <div :for={item <- @items} class="cut-claim">
        <p class="c">{item["claim"]}</p>
        <blockquote :for={ev <- item["evidence"] || []}>
          {ev["quote"]}
          <cite>{ev["label"] || "member #{ev["member"]}"}</cite>
        </blockquote>
      </div>
    </div>
```

`shown(items, nil)` -> `items || []`; `shown(items, n)` keeps items having at least one `evidence` entry whose `"member" == n`. The block renders nothing when the filtered list is empty. A claim item is `%{"claim" => text, "evidence" => [%{"member" => int, "quote" => text, "label" => text|nil}]}`; the cite line is `ev["label"]` or the literal `member <n>`.

Branch by `cut.status` under the members: `"reading"` -> `<p class="cut-working">Reading this folder. One call, and it is the slow kind.</p>`; `"failed"` -> `<p class="cut-err mt-6">{status_detail} <button class="mg-btn sm ghost ml-2" phx-click="again">try again</button></p>`; `"read"` -> optional stale notice ("This folder has changed since it was read." + `read again` button), `Thesis` h2/p, the two groups, optional "What this does not show"; anything else (`draft`) -> `<p class="cut-working">Queued.</p>`. Footer: `read again` button (read only), dropped-claims notice `"{n} claim(s) dropped for quotes that could not be found"` (singular when 1; hidden when empty), `delete` button with `data-confirm="Delete this reading?"`.

Member buttons carry `phx-click="focus" phx-value-n="<n>"`; class `cut-member` plus ` on` when focused. A "not read" tag (`span.u`) shows for `kind == "folder"` members that were not read; the warning paragraph `cut-hole` shows if any such member exists.

**Hook `.Weave`** (on `div#weave-<cut.id>.cut-weave`, `phx-update="ignore"`, attrs `data-status`, `data-members` JSON, `data-links` JSON). It has no pushEvent/handleEvent traffic: it is pure client rendering from data attributes into the inner `<svg>`. Full source, verbatim:

```js
// ===== hook .Weave =====
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

Behaviour notes: `members.length < 2` hides the whole div (`el.hidden = true`). SVG width fixed 280, height `24 + 26*members`. Settled arcs animate in via CSS keyframes `cw-draw` (staggered 90 ms); while `data-status == "reading"` and reduced-motion is off, a looping sequence tries each member pair (1250 ms apart, CSS keyframes `cw-try`, fixed order) lighting dots with class `lit`. Because the element is `phx-update="ignore"` its attributes never change after first insertion, so a re-read (`again` on an already-read cut) does not start the try-animation; only a cut whose members already exist at first render while `reading` would. CSS classes this expects: `cut-weave`, `cw-rule`, `cw-dot` (+`lit`), `cw-lbl`, `cw-arc` (+`k-thread`, `k-tension`), `cw-try`, keyframes `cw-draw`, `cw-try` (uses `--len`).

---

## 2. Links

A link is a symmetric relationship between two read drafts ("works"): `links(a_work_id < b_work_id, status "pending"|"linking"|"linked"|"failed", summary, error)` with directed `link_edges(from node, to node, edge_type, rationale, ordinal)`. Edge types: `develops pays_off requires tension answers echoes`. The model call is run by `Marginalia.Analysis.Linker` in a detached task.

### 2.1 `/links` - `LinkLive.Index`

**Mount:** assigns `page_title "Linked drafts"`, `a: nil`, `b: nil` (selected work ids), `folders: Folders.list_folders(user.id)` (`[%Folder{id,name}]`, name-sorted), `bulk_folder: nil`, `bulk: nil`, `bulk_running: false`, `filter: ""`, `limit: 40` (module attr `@page`). Then `load/2` assigns:

- `user`
- `links = Links.for_user(user.id)` -> `[%Link{a_work, b_work}]` newest `updated_at` first (links where either work is the user's)
- `clusters = Links.clusters(user.id)` -> `[%{works: [Work] sorted by title, links: [Link], missing: [{WorkA, WorkB}] (unlinked pairs a.id < b.id inside the group)}]`, connected components of the link graph, biggest first
- `drafts = Links.linkable(user.id)` -> the user's works with `status == "read"`, newest first
- `unread = count of the user's works whose status != "read"`
- `stats = %{link_id => Links.stats(link)}`; `stats = %{edges: n, by_type: %{"develops" => 4, ...}, a_nodes: n, b_nodes: n}` (one edges query per link)

`render/1` derives: `found = matching(links, filter)` (case-insensitive substring of either work title), `shown = Enum.take(found, limit)`, `webs = clusters with more than 2 works`, `page = 40`.

No PubSub on this page (a pair being linked is only visible after navigating to it, or when a bulk relate completes).

**Render**, verbatim:

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="lx">
        <h1>Linked drafts</h1>
        <p class="lede">
          A link relates two drafts' <strong>maps</strong> — every beat, the spine, the
          threads — and draws the edges between them: what develops what, what answers what,
          where they argue. Both drafts have to have been read first, because that is what
          produces the maps.
        </p>

        <%!-- Triage, then relate. A folder of 111 documents is 6,105 pairs, so
              the cheap pass runs alone and shows what it chose before
              anything is spent per pair. --%>
        <%!-- Folded. It is the tool you reach for once and then scroll past
              every time afterwards, and it sits between the page's title and
              the thing the page is actually for. --%>
        <details :if={@folders != []} class="lx-fold" open={@bulk != nil or @bulk_running}>
          <summary><span class="mg-label">relate a whole folder</span></summary>

          <form phx-submit="bulk_propose" class="lx-bulk-pick">
            <select name="folder" disabled={@bulk_running}>
              <option :for={f <- @folders} value={f.id}>{f.name}</option>
            </select>
            <button type="submit" class="mg-btn sm" disabled={@bulk_running}>
              {if @bulk_running, do: "Reading the folder…", else: "Work out what to relate"}
            </button>
          </form>

          <div :if={@bulk} class="lx-bulk-out">
            <p :if={@bulk.pairs == []} class="none">
              Nothing in that folder looked worth relating.
            </p>

            <ol :if={@bulk.pairs != []} class="mg-rows">
              <li :for={p <- @bulk.pairs}>
                <span class="n">{p.expect}</span>
                <strong>{p.a.title}</strong>
                ↔ <strong>{p.b.title}</strong>
                <p class="mg-meta">{p.why}</p>
              </li>
            </ol>

            <p :if={@bulk.skipped != ""} class="mg-meta">
              Left out: {@bulk.skipped}
            </p>

            <p :if={@bulk.dropped != []} class="cut-err">
              {length(@bulk.dropped)} proposal(s) discarded: {Enum.join(@bulk.dropped, "; ")}
            </p>

            <p :if={Bulk.ineligible(@bulk.pairs) != []} class="cut-err">
              {length(Bulk.ineligible(@bulk.pairs))} of these cannot be read yet — {Enum.join(
                Bulk.ineligible(@bulk.pairs),
                "; "
              )}
            </p>

            <button
              :if={@bulk.pairs != [] and Bulk.ineligible(@bulk.pairs) != @bulk.pairs}
              class="mg-btn sm"
              phx-click="bulk_relate"
              disabled={@bulk_running}
              data-confirm="Read each of these pairs against each other? That is one model call per pair."
            >
              Relate these {length(@bulk.pairs) - length(Bulk.ineligible(@bulk.pairs))}
            </button>
          </div>
        </details>

        <div class="lx-make">
          <span class="mg-label">relate two drafts</span>

          <%= if length(@drafts) < 2 do %>
            <p class="none">
              You need two drafts that have been read. <.link navigate={~p"/works/new"}>Upload another</.link>.
            </p>
          <% else %>
            <%!-- One form, two selects. It was two forms, one per select,
                  and neither carried an id — so every change appended a
                  fresh copy instead of patching the existing one and the
                  row filled up with dead dropdowns. --%>
            <form id="make-link" class="row" phx-change="pick" phx-submit="make">
              <select id="pick-a" name="a" class="lx-pick">
                <option value="">Choose a draft…</option>
                <option
                  :for={d <- @drafts}
                  value={d.id}
                  selected={@a == d.id}
                  disabled={@b == d.id}
                >
                  {d.title} · {d.word_count}w
                </option>
              </select>

              <span class="x" aria-hidden="true">↔</span>

              <select id="pick-b" name="b" class="lx-pick">
                <option value="">Choose a draft…</option>
                <option
                  :for={d <- @drafts}
                  value={d.id}
                  selected={@b == d.id}
                  disabled={@a == d.id}
                >
                  {d.title} · {d.word_count}w
                </option>
              </select>

              <button type="submit" class="mg-btn" disabled={is_nil(@a) or is_nil(@b)}>
                Link them
              </button>
            </form>
          <% end %>

          <%!-- shown whether or not the picker is: someone with a draft
                part-way through the read will otherwise just find it
                missing from the list and wonder --%>
          <p :if={@unread > 0} class="none pending">
            {@unread} {if @unread == 1, do: "draft is", else: "drafts are"} still being read.
            They can be linked once that finishes.
          </p>
        </div>

        <%= if @links == [] do %>
          <p class="none mt-8">Nothing linked yet.</p>
        <% else %>
          <%!-- Links are pairs, but pairs chain. Three documents with two
                links between them are one body of work, and a flat list of
                pairs is the one shape that cannot show that.

                Folded, because each of these is a 300px diagram and a
                writer with nine clusters had three screens of them between
                the top of the page and the first row of the list. --%>
          <details :if={@webs != []} class="lx-fold">
            <summary>
              <span class="mg-label">
                {length(@webs)} {if length(@webs) == 1, do: "web", else: "webs"} of three or more
              </span>
            </summary>

            <div :for={c <- @webs} class="lx-web">
              <span class="mg-label">{length(c.works)} drafts, {length(c.links)} links</span>
              <.constellation cluster={c} />
            </div>
          </details>

          <form phx-change="filter" id="lx-filter" class="lx-filter">
            <input
              type="text"
              name="q"
              value={@filter}
              placeholder="narrow by either draft's title"
              autocomplete="off"
              phx-debounce="150"
            />
            <span class="mg-label">
              {length(@found)} of {length(@links)} linked
            </span>
          </form>

          <p :if={@found == []} class="none">
            Nothing matches “{@filter}”.
          </p>

          <.link :for={l <- @shown} navigate={~p"/links/#{l.id}"} class="lx-row">
            <div class="min-w-0">
              <span class="pair">
                {l.a_work.title} <span class="x">↔</span> {l.b_work.title}
              </span>
              <p :if={l.summary} class="sum">{Links.summary(l)}</p>
              <p :if={l.status == "failed"} class="sum err">{l.error}</p>
            </div>

            <div class="right">
              <%= if l.status == "linked" do %>
                <span class="n">{@stats[l.id].edges} edges</span>
                <span :for={{t, n} <- top(@stats[l.id])} class={["k", t]}>{t} {n}</span>
              <% else %>
                <span class={["st", l.status]}>{l.status}</span>
              <% end %>
            </div>
          </.link>

          <div :if={length(@found) > length(@shown)} class="lx-more">
            <button class="mg-btn sm" phx-click="more">
              Show {min(@page, length(@found) - length(@shown))} more
              <span class="mg-meta">of {length(@found) - length(@shown)} left</span>
            </button>
          </div>
        <% end %>
      </div>
    </Layouts.app>
```

Notes on the markup:
- Whole page is `div.lx`. The folder tool is `<details class="lx-fold">`, rendered only when the user has folders, and `open` while `@bulk != nil or @bulk_running`.
- Folder form: `<form phx-submit="bulk_propose" class="lx-bulk-pick">` with `<select name="folder">` (disabled while running) and a submit button reading `Work out what to relate`, or `Reading the folder…` (with the ellipsis character) while running. No `phx-change`; `bulk_folder` is stored but never rendered.
- `@bulk` result shape: `%{pairs: [%{a: Work, b: Work, why: str, expect: str}] (max 24), skipped: str, dropped: [str], started: []}`. `Bulk.ineligible(pairs)` -> list of strings `"<A title> ↔ <B title>: <titles of unread works joined by ' and '> has not been read"` for pairs where either work's status != `read`. The "Relate these N" button is shown when there are pairs and not all are ineligible; N = pairs minus ineligible; `data-confirm="Read each of these pairs against each other? That is one model call per pair."`.
- Picker: shown only when `length(drafts) >= 2`; otherwise `<p class="none">You need two drafts that have been read. <a href="/works/new">Upload another</a>.</p>`. The picker form is `form#make-link.row` with `phx-change="pick"` and `phx-submit="make"`; selects `#pick-a` (`name="a"`) and `#pick-b` (`name="b"`) with class `lx-pick`; options are `"<title> · <word_count>w"` with `value=<work id>`, `selected` when it equals the current pick, and `disabled` when it equals the other select's pick. Submit button `Link them` is `disabled` until both are chosen.
- The pending line (`p.none.pending`): `"{unread} draft is still being read. They can be linked once that finishes."` / `"{unread} drafts are still being read. ..."` (grammar switches on 1; note the source text says "draft is"/"drafts are" then "still being read. They can be linked once that finishes.").
- No links at all: `<p class="none mt-8">Nothing linked yet.</p>` replaces everything below the picker.
- Otherwise: webs fold (summary label `"{n} web"`/`"{n} webs"` + ` of three or more`; each `div.lx-web` has `span.mg-label` `"{works} drafts, {links} links"` and the constellation), filter form `form#lx-filter.lx-filter` (`phx-change="filter"`, input `name="q" type="text" autocomplete="off" phx-debounce="150" placeholder="narrow by either draft's title"`, counter `"{found} of {all} linked"`), the no-match line `Nothing matches “{filter}”.` (curly quotes), the rows, and a `Show N more` button (`N = min(40, found - shown)`, with `span.mg-meta` `of {found - shown} left`).
- Row (`a.lx-row` to `/links/:id`): title pair `"{a title} ↔ {b title}"` (arrow inside `span.x`), optional `p.sum` = `Links.summary(link)` (summary with "Manuscript A"/"A's" replaced by the work names), and for failed links `p.sum.err` = `link.error`. Right side: linked -> `span.n` `"{edges} edges"` and up to three `span.k.<type>` `"<type> <n>"` (types sorted by count desc, then alphabetically; underscores NOT replaced here); not linked -> `span.st.<status>` with the raw status.

`constellation/1` (private function component), verbatim:

```heex
    <svg class="lx-svg" viewBox="0 0 520 300" preserveAspectRatio="xMidYMid meet">
      <%!-- the pairs nobody has related yet, drawn as the question they are --%>
      <line
        :for={{a, b} <- @cluster.missing}
        x1={elem(@at[a.id], 0)}
        y1={elem(@at[a.id], 1)}
        x2={elem(@at[b.id], 0)}
        y2={elem(@at[b.id], 1)}
        class="gap"
      />

      <.link :for={l <- @cluster.links} navigate={~p"/links/#{l.id}"} class="edge">
        <line
          x1={elem(@at[l.a_work_id], 0)}
          y1={elem(@at[l.a_work_id], 1)}
          x2={elem(@at[l.b_work_id], 0)}
          y2={elem(@at[l.b_work_id], 1)}
        />
        <text
          x={mid(@at[l.a_work_id], @at[l.b_work_id], 0)}
          y={mid(@at[l.a_work_id], @at[l.b_work_id], 1)}
        >
          {count(l)}
        </text>
      </.link>

      <.link :for={w <- @cluster.works} navigate={~p"/works/#{w.slug}"} class="node">
        <circle cx={elem(@at[w.id], 0)} cy={elem(@at[w.id], 1)} r="7" />
        <text
          x={elem(@at[w.id], 0)}
          y={label_y(@at[w.id])}
          text-anchor="middle"
        >
          {short(w.title)}
        </text>
      </.link>
    </svg>

    <p :if={@cluster.missing != []} class="lx-gap">
      Not related yet:
      <span :for={{a, b} <- @cluster.missing} class="pair">
        {short(a.title)} ↔ {short(b.title)}
      </span>
    </p>
```

with helpers (verbatim semantics): `point(i, n)`: angle = `2π·i/n − π/2`, `{260 + 170·cos, 150 + 105·sin}` (floats; viewBox 520x300); `mid` for the label x is `(x1+x2)/2`, y is `(y1+y2)/2 − 4`; `label_y(y) = y + 22 if y > 150 else y − 14`; `short(title)` = title if byte size <= 32, else first 30 characters + `…`; `count(link)` = number of edges (a query per link). Node links go to `/works/<slug>`, edge links to `/links/<id>`. Under the SVG: `p.lx-gap` `Not related yet:` followed by `span.pair` `"{short a} ↔ {short b}"` per missing pair.

**Events**

| Event | Params | Behaviour |
|---|---|---|
| `bulk_propose` | `%{"folder" => id}` | `Integer.parse`; on success `provider = Accounts.provider_for(user)` (nil unless the owner has chosen one; the default model applies when nil), assign `bulk_running: true, bulk: nil, bulk_folder: id`, `start_async(:bulk, Bulk.run(user.id, folder_id, provider:, propose_only: true))`. Unparseable -> no-op. `Bulk.run` returns `{:ok, %{pairs, dropped, skipped, started: []}}`, or `{:error, :no_folder | :empty_folder | reason}`. It makes ONE model call over the folder's titles (+ first-line summaries), validated by `Bulk.validate` (drops pairs that cite numbers not in the folder, pair with itself, duplicates (unordered), missing numbers). |
| `bulk_relate` | none | if `bulk.pairs != []`: `bulk_running: true`, `start_async(:relate, {:ok, Bulk.relate_pairs(pairs, provider:)})`. `relate_pairs` skips ineligible pairs, then for each eligible pair `Links.get_or_create` + `Linker.run` (synchronous inside the task; 3 concurrent, 300 s timeout per pair) and returns `%{started: [pair maps with :link_id or :error], not_read: [strings]}`. |
| `filter` | `%{"q" => text}` | `filter: q, limit: 40` |
| `more` | none | `limit: limit + 40` |
| `pick` | `%{"a" => id, "b" => id}` (from the `phx-change` form; either may be `""`) | `a`, `b` assigned as integers (`""`/nil/unparseable -> nil) |
| `make` | `%{"a","b"}` (form submit) | merges picks into `a`,`b` (falling back to the existing assign when a param is empty); if both are integers and different and `Links.get_or_create(a, b)` is `{:ok, link}`: `Linker.start(link)` (detached task) unless `link.status == "linking"`, then `push_navigate("/links/<link.id>")`. Otherwise `put_flash(:error, "Pick two different drafts.")`. `get_or_create` stores the pair lowest-id first; new pair -> insert `status "pending"` and invalidates the public caches. Note `Linker.start` is also invoked for an existing, already `linked` link (re-linking replaces its edges). |

Note: `make` does not verify that the drafts belong to the user or are read; the picker only offers the user's read drafts.

**Async**

- `:bulk` `{:ok, {:ok, result}}` -> `bulk_running: false, bulk: result`. `{:ok, {:error, reason}}` -> `bulk_running: false`, flash error `"Could not read that folder: " <> inspect(reason)`. `{:exit, reason}` -> `bulk_running: false`, flash error `"Crashed: " <> inspect(reason)`.
- `:relate` `{:ok, {:ok, out}}` -> `bulk_running: false, bulk: nil`, `load/2` again, flash info `"Started #{length(out.started)} readings."` (`started` includes pairs whose `get_or_create` errored). `{:exit, reason}` -> `bulk_running: false` + flash `"Crashed: ..."`. (`{:ok, other}` is not handled and would raise.)

### 2.2 `/links/:id` and `/links/:id/read` - `LinkLive.Read`

The "follow" view: two documents side by side; the left (the lead) is read by scrolling, and the right (the other) is scrolled automatically to the passage the paragraph in front of you is related to. Between them is a strip stating the relation and reason with a wire drawn through it; a chat bubble lets the reader ask about the pair.

**Params.** `id` (link id, path). Query: `lead=<work slug>` (which work is the left column; default is the link's `a_work`, i.e. the lower work id; if it equals the `b_work` slug the sides swap), `only=<edge_type>` (filter to one relation kind; absent/`""`/`"all"` -> all), `walk=1` (start the guided walkthrough and suppress the one-time tour). Both routes use the same handlers; `live_action` is not read.

**Mount** `(%{"id" => id})`: `Links.get(id)`; nil -> flash error `No such link.` and `push_navigate("/works")`. Else (when connected) subscribes to PubSub topic `"link:<id>"`, and assigns `link`, `page_robots: "noindex, nofollow"`, `chat_open: false`, `chat_thinking: false`, `chat_history: []` (list of `%{"role" => "user"|"assistant", "content" => str}`), `chat_cited: []` (edge ids), `walk: []`, then `maybe_tour/1`.

`maybe_tour/1` (public): `Accounts.seen_tour?(user, :follow)` (true if the user's `seen_tours` contains `"follow"`; also true for non-User) -> `tour: nil`. Otherwise, only when the socket is connected, `Accounts.mark_tour_seen(user, :follow)` (persists `"follow"` into `users.seen_tours`) and `tour: Tour.for_view(:follow)` with the updated user substituted in `current_scope`; on the dead render the tour is assigned but NOT marked seen (so it renders in both passes, and is marked on the connected pass). The tour map is `%{title: "Two documents, read as one", points: [6 strings]}`; text below.

**handle_params** (runs on mount and every patch):

1. `link = swap(socket, params["id"])`: if `id` parses to an integer different from the current link's id and `Links.get` finds it, return that link (and, if connected, unsubscribe from the old topic and subscribe to `link:<new id>`); otherwise keep the current link.
2. `{a, b} = Links.works(link)` (preloaded Works: `id, slug, title, collection, status, ...`). `{lead, other} = if params["lead"] == b.slug, do: {b, a}, else: {a, b}`.
3. `{page_a, page_b} = Links.pages(link)`; `lead_page`/`other_page` accordingly. A page is `[%{section: %Section{ordinal,title,body}, blocks: [block], unplaced: [...]}]`, `block = %{ref: "s<ordinal>p<index>", text: markdown paragraph, mark: matched quote span | nil, notes: [note]}`, `note = %{edge_id, kind (edge_type), title ("→ " or "← " + far node title; arrow shows the edge's direction relative to the near node), body (rationale with A/B replaced by work names), peer_ref (block ref of the far end on the other page, or nil if the far node has no anchored paragraph), quote, section_id, key, id, stale}`. Only edges whose near node is an anchored node with a section and quote become notes; blocks come from `Reading.split(section.body)`, quotes located via the anchoring matcher; the first located quote in a paragraph becomes its `mark` (one highlight per paragraph).
4. `{wait_a, wait_b} = waiting_nodes(link, lead, other)`: `{[], []}` when `link.status == "linked"`, else the `beat` nodes (`Works.list_nodes(work.id)` filtered `node_type == "beat"`; fields `title`, ...) of each.
5. `others = Links.for_work(lead.id)` (links either side of the lead, `updated_at` desc, id desc, works preloaded) minus the current link, each as `{link, Links.other(link, lead.id)}` (the work on the far side).
6. Assigns: `link`, `walk` (`Walkthrough.Cases.steps(:follow)` if `walk == "1"`, else unchanged), `tour` (nil if `walk == "1"`, else unchanged), `others`, `wait_a`, `wait_b`, `page_title: "<lead.title> · alongside <other.title>"`, `lead`, `other`, `lead_page`, `other_page`, `only: params["only"]` (raw string or nil), `stats: Links.stats(link)`.

Cost note: every patch and every PubSub message recomputes both pages (all sections, all paragraphs, all edges).

**PubSub / background work.** `Linker.start(link)` spawns a task under `Marginalia.TaskSupervisor`; `Linker.run` sets status `linking` (error nil), then broadcasts on `"link:<id>"`: `{:link, :start}`, `{:link, :stage, :reading}`, `{:link, :stage, :asking}`, `{:link, :stage, :checking}`, then on success clears and stores edges, sets `linked` + summary and broadcasts `{:link, :done}`; failures set `failed` with `error = inspect(reason)` (`:not_read` when either draft has no nodes, `:no_edges`, or the LLM error) and broadcast `{:link, :failed}`.

`handle_info({:link, _}, socket)`: refetch `Links.get(link.id)`, assign it, and re-run `handle_params` with `%{"lead" => lead.slug, "only" => only}` (so everything above is recomputed; `id` absent so the link is kept). IMPORTANT, probably a bug in the source: the pattern is the 2-tuple `{:link, _}` only. The three 3-tuple `{:link, :stage, _}` broadcasts match no clause and raise `FunctionClauseError`, crashing the LiveView process; the client reconnects and remounts from scratch (state such as chat history, tour dismissal and open chat is lost) and that remount shows the then-current status. In practice the page therefore refreshes via crash-and-remount at the stage messages, and via the normal path at `:start`, `:done`, `:failed`. A replacement should treat any `{:link, ...}` as "reload link and recompute".

`handle_async(:chat, ...)`: `{:ok, {:ok, reply}}` -> `chat_thinking: false`, append `%{"role" => "assistant", "content" => reply}`; `{:ok, {:error, reason}}` and `{:exit, reason}` -> `chat_thinking: false` and flash error `"That did not go through: " <> inspect(reason)`.

**Events** (all on this LiveView; several are pushed by hooks/overlays rather than `phx-click`):

| Event | Params | Effect |
|---|---|---|
| `dismiss_tour` | none | `tour: nil` (the veil background click, the "Got it" button, and `phx-click-away` on the card all send it) |
| `show_tour` | none | `tour: Tour.for_view(:follow)` (the `?` button) |
| `start_walk` | none | `tour: nil, walk: steps(:follow)` (no element on this page sends it) |
| `end_walk` | none | `walk: []` (Walk hook's `end`/Escape/finishing the last step) |
| `walk_hop` | `%{"to" => "case_read"}` | if `lead.collection` is nil -> `walk: []`; else `push_navigate("/cases/<Cases.slug(collection)>/read/<lead.slug>?walk=1")` |
| `toggle_chat` | none | flip `chat_open` |
| `close_chat` | none | `chat_open: false` (from the LinkChat hook: outside mousedown, Escape) |
| `cite_edge` | `%{"edge" => id_string}` | append id (integer) to `chat_cited` if absent; `chat_open: true`. Pushed by the Follow hook (clicking the drawn wire, the strip's "ask about this", a sheet card's ask). |
| `uncite` | `%{"edge" => id}` | remove id from `chat_cited` (chip `×` button) |
| `chat_send` | `%{"message" => text}` | trim; ignored if empty or `chat_thinking`. Else history += user turn; `chat_thinking: true`, `chat_cited: []` (cleared on send), `start_async(:chat, LinkChat.ask(link, history, cited: cited_ids))`. Sent by the form submit and by the opener buttons (`phx-value-message`). |
| `relink` | none | `Linker.start(link)` (detached) and set the assign's `link.status = "linking"` locally (so the waiting view shows). "Try again" button on the failed state. |
| `set_only` | `%{"only" => kind}` | `""`/`"all"` -> nil; `push_patch` to `read_path(only: kind)` = `/links/<id>/read?lead=<lead.slug>[&only=<kind>]`. Legend tabs and the walkthrough send it. |

Note `lead` is always carried: `read_path/2` yields `/links/:id/read?lead=<slug>` (+ `&only=<kind>`), and swap-sides links use `read_path(lead: other.slug)` which keeps the current `only`. The reference menu rows patch to `/links/<other link id>?lead=<lead.slug>` (path without `/read`; filter dropped).

`LinkChat.ask(link, history, cited:)` calls the LLM with: system prompt (a fixed ~25-line instruction text: answer about the pair, name nodes/edges, quote only what was given, short, never write prose for either), a system "card" of both maps and all edges, then the history, then (last, cache-friendly) a system message of the cited edges' full passages ("The reader is pointing at these connections and wants to talk about them. Both passages are given in full — quote from them freely." + per-edge sections `## <TYPE>` / `Why it was drawn:` / `### A|B — <node title>` + passage). Params: effort low, temperature 0.5, max_tokens 4000, provider nil (deploy default). Returns `{:ok, text}` or `{:error, reason}` (`:empty_reply` for empty content). The conversation is never persisted; it lives in the LiveView process (remount loses it).

**Render**, the full template, verbatim (the colocated `.Follow` script is excluded and quoted in the hooks section):

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope} bleed>
      <%!-- While the pass runs: both maps, and the pairs it is trying
            between them. The nodes are real; the arcs are not results and
            say so. --%>
      <MarginaliaWeb.LinkWaiting.waiting
        :if={@link.status != "linked"}
        a={@lead}
        b={@other}
        a_nodes={@wait_a}
        b_nodes={@wait_b}
        status={@link.status}
        error={@link.error}
      />

      <div :if={@link.status == "linked"} class="fl" id="follow" phx-hook=".Follow">
        <div class="fl-bar">
          <button class="fl-help" phx-click="show_tour" title="How this page works">?</button>
          <.link
            patch={read_path(assigns, lead: @other.slug)}
            class="fl-swap"
            title="Read the other one instead"
          >
            <span aria-hidden="true">⇄</span> swap sides
          </.link>

          <div class="fl-legend">
            <button
              :for={{id, label} <- [{"all", "Everything"} | types(@stats)]}
              class={"mg-tab" <> if((@only || "all") == id, do: " on", else: "")}
              phx-click="set_only"
              phx-value-only={id}
            >{label}</button>
          </div>

          <%!-- how much of the relationship you have actually been past --%>
          <%!-- The model's account of the relationship. It lived in the
                split view, and deleting that orphaned it — it was only
                visible on the index rows, which is not where you are when
                you want it. --%>
          <details :if={@link.summary} class="fl-sum">
            <summary>
              <span class="mg-label">why</span>
              <span class="peek">{Links.summary(@link)}</span>
              <span class="more" aria-hidden="true"></span>
            </summary>
            <p>{Links.summary(@link)}</p>
          </details>

          <span class="fl-count"><b>0</b> / {@stats.edges} addressed</span>
        </div>

        <div class="fl-split">
          <div class="fl-col lead" id="fl-lead" tabindex="0">
            <%!-- which column is which, kept in view: three screens down,
                  "the left one" is not something anyone is still tracking --%>
            <div class="fl-colhead">
              <span class="mg-label">Reading…</span>
              <a href={~p"/works/#{@lead.slug}"}>{@lead.title}</a>
            </div>
            <.side page={@lead_page} only={@only} side="lead" slug={@lead.slug} />
          </div>

          <%!-- the reason lives between the two documents, which is where it
                is about: it belongs to neither and points at both --%>
          <%!-- The line is drawn across the whole split, not just the
                gutter, so it can start and finish on the two passages
                themselves. It runs THROUGH the reason card rather than past
                it: left passage → why → right passage is the actual shape
                of the claim. --%>
          <svg class="fl-wire" hidden>
            <path class="w1" fill="none" />
            <path class="w2" fill="none" />
            <circle class="d1" r="4" />
            <circle class="d2" r="4" />
            <%!-- a 2.5px line is not a thing anyone can hit. These are the
                  same two curves, invisible and fourteen pixels wide, and
                  they are what actually takes the click. --%>
            <path class="h1 hit" fill="none" />
            <path class="h2 hit" fill="none" />
          </svg>

          <div class="fl-mid">
            <%!-- The phone's answer to "what does the other document say
                  about this paragraph". A paragraph can carry five
                  connections and the sheet was showing one of them —
                  whichever happened to be first in the DOM — with no
                  sign the other four existed. So: the stack, one card
                  per connection, built by the hook because only the
                  browser knows which paragraph was tapped.

                  The strip below it is the wide-screen version and
                  stays as it was: there, the drawn line points at one
                  connection at a time, so one is the right number. --%>
            <div class="fl-sheet" hidden>
              <div class="fl-sheet-head">
                <span class="n"></span>
                <button type="button" class="shut" aria-label="Back to the reading">×</button>
              </div>
              <div class="fl-stack"></div>
            </div>

            <div class="fl-strip" hidden>
              <%!-- This head was written when the strip *was* the phone
                    UI. It is not any more — the sheet above replaced it
                    there, and `.fl-strip` is display:none under 1100px — so
                    everything here is wide-screen markup now. It used to
                    carry a × as well, left over from the phone: nothing on
                    a wide screen dismisses the strip (it follows the
                    scroll), so the button sat there doing nothing. --%>
              <div class="fl-strip-head">
                <span class="rel"></span>
                <span class="nth"></span>
              </div>
              <p class="why"></p>
              <%!-- On a phone the right-hand document has nowhere to be,
                    so the strip carries the passage itself. The hook
                    copies it out of the column, which is still in the
                    DOM — hidden, not absent. --%>
              <blockquote class="far"></blockquote>
              <%!-- Last, not in the head: you decide to ask *after* reading
                    what the connection is, and a button wedged between the
                    relation and its reason reads as part of the sentence. --%>
              <button type="button" class="ask">ask about this</button>
            </div>
            <div class="fl-idle">
              Scroll. Where this draft touches the other, it will be shown here.
            </div>
          </div>

          <div class="fl-col other" id="fl-other" tabindex="0">
            <div class="fl-colhead">
              <%!-- A draft can be related to several others, and reading it
                    against each of them in turn is the point of having
                    more than one. Swapping is here rather than back on a
                    list page. --%>
              <%= if @others == [] do %>
                <span class="mg-label">Referencing…</span>
                <a href={~p"/works/#{@other.slug}"}>{@other.title}</a>
              <% else %>
                <details class="fl-pick">
                  <summary>
                    <span class="mg-label">Referencing…</span>
                    <span class="t">{@other.title}</span>
                    <span class="n">{length(@others) + 1}</span>
                  </summary>
                  <div class="fl-pick-menu">
                    <span class="here">
                      <span class="t">{@other.title}</span>
                      <span class="mg-label">reading against this</span>
                    </span>
                    <.link
                      :for={{l, w} <- @others}
                      patch={~p"/links/#{l.id}?lead=#{@lead.slug}"}
                      class="row"
                    >
                      <span class="t">{w.title}</span>
                      <span class={["st", l.status]}>
                        {if l.status == "linked", do: "#{edge_count(l)} edges", else: l.status}
                      </span>
                    </.link>
                    <.link navigate={~p"/links"} class="row more">Relate it to another…</.link>
                  </div>
                </details>
              <% end %>
            </div>
            <.side page={@other_page} only={@only} side="other" slug={@other.slug} />
          </div>
        </div>
      </div>

      <%!-- Over the page rather than beside it: the things it describes are
            the page, and a card in a corner is read after you have already
            failed to work out what the dimmed half is for. --%>
      <div :if={@tour} class="fl-tour-veil" phx-click="dismiss_tour">
        <div class="fl-tour" phx-click-away="dismiss_tour">
          <div class="fl-tour-head">
            <h2>{@tour.title}</h2>
            <button class="mg-btn sm ghost" phx-click="dismiss_tour">Got it</button>
          </div>
          <ul>
            <li :for={point <- @tour.points}>{point}</li>
          </ul>
          <p class="mg-hint">The <strong>?</strong> in the bar brings this back.</p>
        </div>
      </div>

      <MarginaliaWeb.Walk.overlay
        :if={@walk != []}
        steps={@walk}
        note="Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would."
      />

      <%!-- Not while the tour card is up. The card's veil covers the whole
            viewport at a higher z-index than the bubble, so a click on the
            bubble was landing on the veil: the tour dismissed and the chat
            did not open. Twice in a row looks exactly like a broken
            button, and it was — a control you can see, cannot press, and
            get no feedback from. --%>
      <MarginaliaWeb.LinkChat.bubble
        :if={is_nil(@tour)}
        open={@chat_open}
        history={@chat_history}
        thinking={@chat_thinking}
        count={length(@chat_history)}
        cited={cited_edges(@link, @chat_cited)}
      />
```

The walk overlay and chat bubble mount points are the last lines of that block. Key structure when `link.status == "linked"`:

```
div.fl#follow [phx-hook=".Follow"]
  div.fl-bar
    button.fl-help (title "How this page works", text "?", phx-click show_tour)
    a.fl-swap (patch -> read_path(lead: other.slug)) "⇄ swap sides"
    div.fl-legend
      button.mg-tab[.on] x N  phx-click=set_only phx-value-only=<id>   ("all" -> "Everything"; others "<type with _ as space> <count>", sorted by count desc then name)
    details.fl-sum (only when link.summary): summary [span.mg-label "why", span.peek summary, span.more], p summary
    span.fl-count  "<b>0</b> / {stats.edges} addressed"      (the hook rewrites the <b>)
  div.fl-split
    div.fl-col.lead#fl-lead[tabindex=0]
      div.fl-colhead: span.mg-label "Reading…" + a[href=/works/<lead.slug>] lead.title
      <.side side="lead">
    svg.fl-wire[hidden]: path.w1 path.w2 circle.d1(r4) circle.d2(r4) path.h1.hit path.h2.hit
    div.fl-mid
      div.fl-sheet[hidden]: div.fl-sheet-head(span.n, button.shut "×" aria-label "Back to the reading"), div.fl-stack
      div.fl-strip[hidden]: div.fl-strip-head(span.rel, span.nth), p.why, blockquote.far, button.ask "ask about this"
      div.fl-idle "Scroll. Where this draft touches the other, it will be shown here."
    div.fl-col.other#fl-other[tabindex=0]
      div.fl-colhead: (no other links) span.mg-label "Referencing…" + a[/works/<other.slug>]
                      or details.fl-pick > summary(span.mg-label "Referencing…", span.t other.title, span.n count+1) + div.fl-pick-menu
      <.side side="other">
```

When the status is not `linked` the page body is `<MarginaliaWeb.LinkWaiting.waiting a={lead} b={other} a_nodes b_nodes status error>` (section 2.4), and no `#follow` element exists.

`side/1` function component (private; one call per column), verbatim:

```heex
  defp side(assigns) do
    ~H"""
    <div class="fl-inner">
      <%= for section <- @page do %>
        <div class="fl-sec">
          <span class="mg-label">Section {section.section.ordinal}</span>
          <h2>{section.section.title}</h2>
        </div>

        <%= for run <- condense(section.blocks, @only) do %>
          <%= case run do %>
            <% {:gap, blocks} -> %>
              <%!-- The stretches where the two documents have nothing to say
                    to each other are folded away. This view is for an
                    editorial pass over the relationship, and prose with
                    nothing beside it is the part you are not here for —
                    still one click from being read, never deleted. --%>
              <details class="fl-gap">
                <summary>
                  <span class="n">{length(blocks)} paragraphs</span>
                  <span class="w">{words(blocks)} words</span>
                </summary>
                <div class="fl-gap-body">
                  <div :for={b <- blocks} class="fl-block quiet" id={"blk-#{@side}-#{b.ref}"}>
                    {Reading.render_block(b.text, nil, "#{@side}-#{b.ref}")}
                  </div>
                </div>
              </details>
            <% {:block, block} -> %>
              <% notes = Enum.filter(block.notes, &shown?(&1, @only)) %>
              <div class={["fl-block", notes != [] && "linked"]} id={"blk-#{@side}-#{block.ref}"}>
                <%!-- The anchor id is namespaced by side. Both columns
                      number their paragraphs from their own first one, so
                      an anchored quote at the same position in each
                      produced two elements with id "anchor-s1p1" — which
                      breaks DOM patching and means getElementById returns
                      whichever one happens to be first. --%>
                {Reading.render_block(block.text, notes != [] && block.mark, "#{@side}-#{block.ref}")}

                <%!-- This view is for reading the two against each other, and
                      the thing you want the moment you see the problem is to
                      fix it. The fragment is the block's id on the draft's own
                      page, so the browser lands on the paragraph rather than
                      at the top of a document you then have to find it in. --%>
                <a
                  class="fl-edit"
                  href={~p"/works/#{@slug}?view=read#block-#{block.ref}"}
                  title="Edit this paragraph in the draft"
                >edit</a>

                <%!-- the relation is carried on the paragraph as data; the strip
                  between the columns is what actually shows it --%>
                <span
                  :for={n <- notes}
                  hidden
                  data-peer-ref={n.peer_ref}
                  data-kind={n.kind}
                  data-why={n.body}
                  data-edge={n.edge_id}
                  data-src={n.title}
                ></span>

                <%!-- One chip, not one word per edge. A hub paragraph can
                      have a dozen edges pointing at it, and a dozen labels
                      in a row overflowed the column and sat behind the
                      prose. The count is the more useful fact anyway: it
                      says this passage is where the other document keeps
                      arriving.

                      "3 links" was a dead end, though: the strip and the
                      wire only ever showed the *first* of them, so the
                      other two were counted and then unreachable. Hovering
                      the chip opens the list, and each entry goes to the
                      paragraph at its own far end. --%>
                <div :if={notes != []} class={["fl-tagwrap", tag_kind(notes)]}>
                  <span class={["fl-tag", tag_kind(notes)]}>{tag_label(notes)}</span>

                  <div class="fl-links">
                    <button
                      :for={n <- notes}
                      type="button"
                      class={["fl-jump", "k-#{n.kind}"]}
                      disabled={is_nil(n.peer_ref)}
                      data-peer-ref={n.peer_ref}
                      data-edge={n.edge_id}
                      data-kind={n.kind}
                    >
                      <span class="rel">{String.replace(n.kind, "_", " ")}</span>
                      <span class="to">{n.title}</span>
                      <span class="why">{n.body}</span>
                      <%!-- An edge whose far end is a spine node has no
                            paragraph to land on. Saying so beats a control
                            that looks live and does nothing. --%>
                      <span :if={is_nil(n.peer_ref)} class="nowhere">whole draft — no passage to jump to</span>
                    </button>
                  </div>
                </div>
              </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
```

and its helpers, semantics exactly:
- `tag_label([n])` = `n.kind` with `_` -> space; for several notes `"<count> links"`.
- `tag_kind(notes)` = the shared kind if all notes agree, else `"mixed"`.
- `shown?(note, nil)` true; `shown?(note, only)` = `note.kind == only`.
- `condense(blocks, only)`: indices of blocks having at least one shown note are "linked"; `keep` = each linked index plus its neighbours (i-1, i+1). Blocks are chunked by membership in `keep`; a kept chunk yields `{:block, b}` for each; a non-kept chunk of exactly one block yields `{:block, b}`; a longer non-kept chunk yields one `{:gap, [blocks]}` (rendered as `details.fl-gap`, summary `span.n "<count> paragraphs"` and `span.w "<total words> words"`, body paragraphs `div.fl-block.quiet#blk-<side>-<ref>`). Words = whitespace-split token count of the raw markdown.
- `Reading.render_block(text, mark, ref)`: renders the paragraph's Markdown to sanitized HTML (MDEx/comrak with strikethrough, tables, autolink, tasklist, footnotes; `smart` off; unsafe off; ammonia sanitising; SOFT breaks, so a newline inside a paragraph is a space) and wraps the anchored span as `<mark id="anchor-<side>-<ref>">…</mark>` (the mark is trimmed inward past leading/trailing `*_`~` so emphasis still pairs). `mark` is passed only when the block has shown notes. Block ids: `blk-lead-s2p3` / `blk-other-s2p3`; section header `div.fl-sec` with `span.mg-label "Section <ordinal>"` and `<h2>title</h2>`.
- Each linked block gets hidden data spans (one per shown note) `<span hidden data-peer-ref data-kind data-why data-edge data-src>` with `data-why = rationale`, `data-src = note.title` (the arrow-prefixed far node title), `data-peer-ref` omitted when nil. These are the data the hooks read; the server never shows them directly.
- Each linked block also has `a.fl-edit` ("edit", href `/works/<slug>?view=read#block-<ref>`, title "Edit this paragraph in the draft") and the tag chip `div.fl-tagwrap.<kind>` containing `span.fl-tag.<kind>` and `div.fl-links` of `button.fl-jump.k-<kind>` (`disabled` if no peer_ref; data-peer-ref, data-edge, data-kind; children `span.rel`, `span.to`, `span.why`, and `span.nowhere` "whole draft — no passage to jump to" when no peer).
- The column head's `others` menu: `details.fl-pick-menu` rows: current (`span.here` with `span.t` title and `span.mg-label "reading against this"`), one `a.row` per other link (patch to `/links/<id>?lead=<lead slug>`; `span.t` = far work title, `span.st.<status>` = `"<edge count> edges"` when linked else the status), then `a.row.more` "Relate it to another…" (navigate `/links`).

Tour card (shown when `@tour`): `div.fl-tour-veil[phx-click=dismiss_tour] > div.fl-tour[phx-click-away=dismiss_tour]` containing `div.fl-tour-head` (`h2` title + `button.mg-btn.sm.ghost "Got it"`), `ul > li` per point, `p.mg-hint` `The <strong>?</strong> in the bar brings this back.`. Tour copy (title "Two documents, read as one"):

1. The left is what you are reading. The right is the reference, and it is dimmed on purpose — it lights up only where it has something to say about the passage you are on.
2. Scroll the left. The right is scrolled for you, and snaps to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again.
3. The line drawn between them runs through the reason in the middle — left passage, why, right passage, which is the actual shape of the claim. Click the line to carry both passages into the chat.
4. The filters leave one kind of relation in view: where the two documents disagree, where one answers the other, where one depends on the other.
5. Stretches where the two have nothing to say to each other are folded away, with their size on the label. Nothing is deleted — open one and read it.
6. Referencing… swaps which document sits in the margin, and swap sides reads the other one as the lead. The pair is symmetric and the two directions are genuinely different.

Walkthrough (`walk != []`): `<MarginaliaWeb.Walk.overlay steps={walk} note="Real documents, really read: these are the Court's own files and nothing here is a fixture. The tour presses the same controls you would." />`. The `:follow` steps (id: title / target selector / place / act):

1. `sides`: "Left is read. Right is the reference" - body "One document down the left at your own pace. The other is dimmed on purpose — it lights up only where it has something to say about the passage you are on." - `.fl-colhead`, bottom.
2. `follow`: "The right side follows you" - "Scroll the left and the right is scrolled for you, snapping to the passage your paragraph is talking to. Stop following whenever you like: scroll the right yourself, read it, and the left picks you up again." - `#fl-lead`, right.
3. `wire`: "The line runs through the reason" - "Left passage, why, right passage — the actual shape of the claim. The middle is the reason for drawing it, and it belongs to neither document." - `.fl-mid`, left.
4. `filter`: "One kind of relation at a time" - "Tension leaves only where the two genuinely pull apart. Answers leaves where one replies to the other. The filter changes what the page is about, not how much of it there is." - `.fl-legend`, bottom, act push `set_only {"only":"tension"}`.
5. `filter_back`: "Everything, again" - "Back to the whole relationship, which is how it opens." - `.fl-legend`, bottom, act push `set_only {"only":"all"}`.
6. `gaps`: "The quiet stretches are folded" - "Where the two have nothing to say to each other, the prose is folded away with its size on the label. Nothing is deleted — open one and read it." - `.fl-gap`, right.
7. `chat`: "You can argue with it" - "Click the line between two passages and both go into the question. The chat starts fresh on this page and holds whatever you cite into it." - `.lc`, left.
8. `onward`: "Two documents is the pair. Now the whole case" - "The same opinion, with every other document in the case beside it at once." - `.fl-colhead`, bottom, act hop `case_read`.

The chat bubble mounts via `<MarginaliaWeb.LinkChat.bubble :if={is_nil(@tour)} open history thinking count={length(history)} cited={cited_edges(link, chat_cited)}>` (not rendered while the tour card is up, so the veil cannot intercept clicks). `cited_edges` = `Links.edges(link)` filtered to the ids in `chat_cited` (each edge: `id, edge_type, rationale, from, to` with node `title`).

### 2.3 Chat bubble component (`MarginaliaWeb.LinkChat.bubble/1`)

Attrs (defaults): `open false`, `history []`, `thinking false`, `count 0`, `cited []`, `title "About this pair"`, `label "Talk about how these two relate"`, `placeholder "How do these two sit together?"`, `hint "This one holds both maps and every edge between them. Ask what the second draft already answers, where the disagreement is real, or which connection is doing the most work. It will not write for either of them."`, `openers ["What does the second document already answer?", "Which disagreement here is real, and which is vocabulary?", "Which connection is doing the most work?"]`.

Template, verbatim:

```heex
    <div class="lc" id="linkchat" phx-hook=".LinkChat">
      <button
        class={["lc-bubble", @open && "on"]}
        phx-click="toggle_chat"
        aria-label={@label}
        title={@label}
      >
        <span class="mark" aria-hidden="true">↔</span>
        <span :if={@count > 0 and not @open} class="n">{@count}</span>
      </button>

      <div :if={@open} class="lc-panel" role="dialog" aria-label={@title}>
        <div class="lc-head">
          <span class="mg-label">{@title}</span>
          <button class="lc-x" phx-click="toggle_chat" aria-label="Close">×</button>
        </div>

        <div class="lc-body" id="lc-body" phx-hook=".StickDown">
          <p :if={@history == []} class="lc-hint">
            {@hint}
          </p>

          <div :if={@history == [] and @openers != []} class="lc-openers">
            <button :for={q <- @openers} type="button" phx-click="chat_send" phx-value-message={q}>
              {q}
            </button>
          </div>

          <div :for={m <- @history} class={["lc-turn", m["role"]]}>
            <span class="who">{if m["role"] == "user", do: "you", else: "the reader"}</span>
            <div class="said md">
              {if m["role"] == "user",
                do: m["content"],
                else: Marginalia.Markdown.to_html(m["content"])}
            </div>
          </div>

          <div :if={@thinking} class="mg-dots" aria-label="reading">
            <span class="mg-dot"></span>
            <span class="mg-dot" style="animation-delay:.18s"></span>
            <span class="mg-dot" style="animation-delay:.36s"></span>
          </div>
        </div>

        <%!-- what the reader pointed at. Both passages go to the model in
              full, so these are not decoration — removing one removes it
              from the question. --%>
        <div :if={@cited != []} class="lc-cited">
          <span class="mg-label">pointing at</span>
          <div :for={e <- @cited} class={["chip", e.edge_type]}>
            <span class="rel">{String.replace(e.edge_type, "_", " ")}</span>
            <span class="t">{e.from.title} ↔ {e.to.title}</span>
            <button phx-click="uncite" phx-value-edge={e.id} aria-label="Remove">×</button>
          </div>
        </div>

        <form class="lc-foot" phx-submit="chat_send" id="lc-form" phx-hook=".Composer">
          <textarea
            name="message"
            rows="2"
            placeholder={@placeholder}
            disabled={@thinking}
          ></textarea>
          <div class="row">
            <span class="mg-hint mt-0">Enter to send</span>
            <button type="submit" class="mg-btn sm" disabled={@thinking}>Ask</button>
          </div>
        </form>
      </div>
```

The outer `<div class="lc" id="linkchat" phx-hook=".LinkChat">` is closed after the three script tags (the panel `div.lc-panel` closes at the end of the block above).

Assistant turns are rendered with `Marginalia.Markdown.to_html(content)` (hard breaks, sanitized); user turns are escaped text. Pointer: `form#lc-form` has `phx-submit="chat_send"`; the opener buttons send `chat_send` with `phx-value-message`.

Hooks (3), all colocated in this component. Contracts: `.LinkChat` pushes `close_chat`; `.Composer` triggers a DOM `submit` event on the form (which LiveView turns into `chat_send`); `.StickDown` is pure DOM. None use handleEvent.

```js
// ===== hook .LinkChat =====
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

// ===== hook .Composer =====
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

// ===== hook .StickDown =====
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

### 2.4 Waiting view (`MarginaliaWeb.LinkWaiting.waiting/1`)

Shown instead of `#follow` for `pending`, `linking` and `failed` links. Attrs: `a`, `b` (lead and other works), `a_nodes`, `b_nodes` (beat nodes), `status`, `error`. Computed: `pairs = |a_nodes| * |b_nodes|`; `a_dots`/`b_dots` = node titles, evenly sampled to at most 24 each (`trunc(i * n/24)`).

Template, verbatim:

```heex
    <div class="lw">
      <%= if @status == "failed" do %>
        <h2>That did not go through</h2>
        <p class="why">{@error}</p>
        <button class="mg-btn sm" phx-click="relink">Try again</button>
      <% else %>
        <div class="lw-head">
          <span class="mg-label">relating</span>
          <h2>{@a.title} <span class="x">↔</span> {@b.title}</h2>
          <p class="why">
            Reading both maps against each other — {length(@a_nodes)} nodes on one side, {length(
              @b_nodes
            )} on the other, {@pairs} possible pairs. A minute or two.
            This page fills in on its own.
          </p>
        </div>

        <div
          class="lw-stage"
          id="wiring"
          phx-hook=".Wiring"
          data-a={Jason.encode!(@a_dots)}
          data-b={Jason.encode!(@b_dots)}
        >
          <%!-- The nodes are rendered here rather than by the hook: the
                hook cannot run until the socket connects, and an empty box
                for six seconds is a worse loading state than the one it
                replaced. --%>
          <svg class="lw-svg" viewBox="0 0 680 360" preserveAspectRatio="xMidYMid meet">
            <g class="arcs"></g>
            <g class="dots">
              <circle
                :for={{_t, i} <- Enum.with_index(@a_dots)}
                cx="90"
                cy={y(i, length(@a_dots))}
                r="3.5"
                data-side="a"
                data-i={i}
                style={"animation-delay:#{i * 45}ms"}
              />
              <circle
                :for={{_t, i} <- Enum.with_index(@b_dots)}
                cx="590"
                cy={y(i, length(@b_dots))}
                r="3.5"
                data-side="b"
                data-i={i}
                style={"animation-delay:#{i * 45}ms"}
              />
            </g>
          </svg>

          <p class="lw-now">
            <span class="l"></span>
            <span class="arrow" aria-hidden="true">⇢</span>
            <span class="r"></span>
          </p>

          <p class="lw-fine">
            The nodes are yours. The lines are the pass trying pairs — none of them are
            findings yet, and they all fade. What it actually decides arrives at the end.
          </p>
        </div>
      <% end %>
```

The outer `<div class="lw">` closes after the script tag. `y(i, n) = 30 + i * (300 / max(n - 1, 1))` (float) is the dot y-coordinate; the hook mirrors it. Dot circles carry `data-side`, `data-i`, and an inline `animation-delay` of `i*45` ms, rendered server-side so the box is not empty before the socket connects. The failed state shows `h2 "That did not go through"`, `p.why` = error string (e.g. `:not_read`, `:no_edges`, or an inspected LLM error), and `button.mg-btn.sm "Try again"` -> `relink`.

Hook `.Wiring` (on `div#wiring.lw-stage`, data-a/data-b JSON arrays of titles): no push/handle events. Every 900 ms (unless reduced-motion or either list empty) it draws a random bezier arc between a random left and right dot (`M 90 y1 C 300 y1, 380 y2, 590 y2`), animates it on, fades it, removes it after 1.8 s, lights the two dots for 1.2 s and prints the two titles in `p.lw-now`. The server explicitly says on the page that these arcs are not findings. Source, verbatim:

```js
// ===== hook .Wiring =====
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

### 2.5 Walkthrough overlay (`MarginaliaWeb.Walk.overlay/1`)

Template, verbatim:

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
```

The outer `div#walk` closes after the script tag. Steps are passed as JSON in `data-steps` (each: `id, title, body, target (CSS selector or null), place ("top"|"bottom"|"left"|"right"|"centre"), act (optional)`). Act kinds: `push` (hook calls `pushEvent(event, params)`), `click` (hook clicks `document.querySelector(target)`), `hop` (hook sends `walk_hop {to}`), or a named client act (not used by this page). On this page `auto` is nil so the hook starts at step 0 on mount and the End button/Escape push `end_walk`; last step "Done" calls stop. Hook source, verbatim:

```js
// ===== hook .Walk =====
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

Its server contract: handleEvent none; pushes `end_walk {}`, `walk_hop {to}`, and for `push` acts any event the page defines (here only `set_only`). It also references events from other pages (`thread_send`, `edit_block`, `walk_reset`) that this page does not implement.

### 2.6 Hook `.Follow` (on `div#follow.fl`)

Contract with the server: it never receives pushed data from the server (no handleEvent). It reads everything from the DOM (the hidden `data-peer-ref/-kind/-why/-edge/-src` spans on each `.fl-block`, the `#blk-<side>-<ref>` ids, `.fl-block.linked`) and sends exactly one event, `cite_edge {edge: "<edge id string>"}`, from three places (clicking the wire's `.hit` paths; `.fl-strip .ask`; a `.fl-card .ask` in the phone sheet). It sets `.fl-count b` to the number of distinct edges viewed, and toggles classes `on`, `seen`, `peek` on blocks, `open` on `.fl-mid`, `fl-sheet-open` on `<html>`. Breakpoint for the "phone" mode is `max-width: 1100px` (below it there is no following, no wire; tapping a linked paragraph opens the sheet of cards). Reader scrolling drives the other column; wheel anywhere that is not a column scrolls the lead; scrolling the other column by hand sets `free` until the next paragraph crosses the focus line (33% down the lead column). Full source, verbatim:

```js
// ===== hook .Follow =====
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

CSS classes the hook and markup depend on (the stylesheet must define them): `fl, fl-bar, fl-help, fl-swap, fl-legend, mg-tab(.on), fl-sum (summary .peek .more), fl-count, fl-split, fl-col(.lead/.other), fl-colhead, fl-inner, fl-sec, fl-block(.linked .quiet .on .seen .peek), fl-edit, fl-tagwrap, fl-tag, fl-links, fl-jump (.rel .to .why .nowhere, k-<kind>), fl-gap (.n .w, fl-gap-body), fl-wire (.w1 .w2 .d1 .d2 .h1 .h2 .hit; data-kind), fl-mid(.open), fl-sheet (.n .shut), fl-stack, fl-card (k-<kind>, header .rel .src, .why, .far, .ask), fl-strip (data-kind, .fl-strip-head .rel .nth, .why, .far, .ask), fl-idle, fl-pick (.t .n), fl-pick-menu (.here .row .more .st), fl-tour-veil, fl-tour, fl-tour-head, lc*, lw*`, plus the edge-kind colour classes `develops pays_off requires tension answers echoes mixed`.
EOF

---

## 3. Accounts: log in, register, settings, session controller

Authentication is **email + password only**. There is no magic link, no confirmation email on registration (`confirmed_at` is set at insert), no OAuth. The only email the app ever sends is the "change email" confirmation. Passwords: bcrypt, 12 to 72 characters. There is no per-user provider choice on these pages: choosing the model backend (`Accounts.set_llm_provider/2`, owner-only; `Accounts.provider_for/1` returns the stored provider only for the owner account, else nil) lives in `WorkLive.Show` (event handler around `work_live/show.ex:950`), not in settings.

### 3.1 `/users/log-in` - `UserLive.Login`

**Mount:** `email = Phoenix.Flash.get(flash, :email) || current_scope.user.email (if any)`; `form = to_form(%{"email" => email}, as: "user")`; assigns `form`, `trigger_submit: false`. No `page_title` (title falls to the tagline). `current_scope` is whatever is in the session, which includes **guest** sessions: a guest visiting this page sees the "reauthenticate" copy and a read-only email field pre-filled with the guest placeholder address (`guest-...@guest.marginalia.local`), so a guest cannot type an existing account's email here. (Same logic in `Registration`: see 3.2.)

**Render**, verbatim:

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm px-6 py-16 space-y-5">
        <div>
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            Log in
          </h1>
          <p class="mg-hint mt-1.5">
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Don't have an account? <.link
                navigate={~p"/users/register"}
                class="font-semibold text-[var(--mg-accent)] hover:underline"
                phx-no-format
              >Sign up</.link> for an account now.
            <% end %>
          </p>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            spellcheck="false"
            required
          />
          <button class="mg-btn w-full mt-2" name={@form[:remember_me].name} value="true">
            Log in and stay logged in
          </button>
          <button class="mg-btn ghost w-full mt-2">Log in only this time</button>
        </.form>
      </div>
    </Layouts.app>
```

Element facts: container `mx-auto max-w-sm px-6 py-16 space-y-5`; `h1` styled `font-family:var(--mg-serif)` classes `text-2xl font-semibold tracking-tight`, text `Log in`; hint `p.mg-hint.mt-1.5`. Logged-out copy: `Don't have an account? [Sign up](/users/register) for an account now.` (link classes `font-semibold text-[var(--mg-accent)] hover:underline`). With a session user: `You need to reauthenticate to perform sensitive actions on your account.` and the email input gets `readonly`. Email input: `type=email`, label `Email`, `autocomplete="username"`, `spellcheck="false"`, `required`, focused on mount (`phx-mounted={JS.focus()}`; in plain HTML use `autofocus`). Password input: `type=password`, label `Password`, `autocomplete="current-password"`, `spellcheck="false"`, `required`. Buttons: `button.mg-btn.w-full.mt-2 name="user[remember_me]" value="true"` text `Log in and stay logged in`; `button.mg-btn.ghost.w-full.mt-2` text `Log in only this time`. Form `id="login_form_password"`, `action="/users/log-in"`, method POST, plus a hidden `_csrf_token`.

**Event** `submit_password` (any params): `trigger_submit: true`. There is no server-side validation in the LiveView. `phx-trigger-action` makes the browser then perform a native POST of the form (including the pressed button's `user[remember_me]=true`, if that was the one used) to `/users/log-in`. For a non-LiveView implementation this is simply a normal form POST. Server errors are reported by the controller redirecting back here with flashes.

### 3.2 `/users/register` - `UserLive.Registration`

Registration is open to anyone: no invite, no allow-list.

**Mount:** if `current_scope` has a user (including a guest!), `redirect(to: signed_in_path(socket))`. `signed_in_path/1` only special-cases a `Plug.Conn`; given a socket it returns `"/"`. So any visitor who holds a session (a guest included, which is who the "Keep my drafts" button and the `require_real_account` redirect send here) is bounced to `/`; as written, a guest cannot register from this page (`Accounts.claim_guest_account/2` exists to convert a guest in place but nothing calls it). Otherwise: `changeset = Accounts.change_user_registration(%User{})` (email changeset with `validate_unique: false` plus password changeset with `hash_password: false`), `form = to_form(changeset, as: "user")`, `temporary_assigns: [form: nil]` (the form assign is dropped after every render and rebuilt in the handlers). No `page_title`.

**Render**, verbatim:

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm px-6 py-16">
        <div class="text-center">
          <.header>
            Register for an account
            <:subtitle>
              Already registered?
              <.link
                navigate={~p"/users/log-in"}
                class="font-semibold text-[var(--mg-accent)] hover:underline"
              >
                Log in
              </.link>
              to your account now.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            spellcheck="false"
            required
          />

          <.button phx-disable-with="Creating account..." class="mg-btn w-full mt-2">
            Create an account
          </.button>
        </.form>
      </div>
    </Layouts.app>
```

Header: `h1.text-lg.font-semibold.leading-8` "Register for an account", subtitle `Already registered? [Log in](/users/log-in) to your account now.` (link classes `font-semibold text-[var(--mg-accent)] hover:underline`), the header block is wrapped in `div.text-center`. Form `id="registration_form"`, `phx-submit="save"`, `phx-change="validate"`; fields `user[email]` (type email, label `Email`, autocomplete `username`, required, focus on mount) and `user[password]` (type password, label `Password`, autocomplete `new-password`, required). There is NO password-confirmation field here. Submit: `.button phx-disable-with="Creating account..." class="mg-btn w-full mt-2"` text `Create an account` (the button's text is swapped to "Creating account..." and disabled while the event is in flight).

**Events**

- `validate` `%{"user" => %{"email","password"}}`: `change_user_registration(%User{}, params)`, action `:validate`; errors for touched fields are shown inline. No uniqueness check here.
- `save` `%{"user" => params}`: `Accounts.register_user(params)` inserts `email` (+ bcrypt `hashed_password`), `confirmed_at = now`, `is_guest false`, `seen_tours []`. `{:ok, user}` -> flash info `Account created. Log in to get started.`, a custom flash key `email` = `user.email` (consumed by the login page to prefill), `push_navigate("/users/log-in")` (no automatic login). `{:error, changeset}` -> form re-rendered with errors.

Validation errors, exact text (shown under the field in `p.text-error` with a leading `hero-exclamation-circle` icon):

| Field | Rule | Message |
|---|---|---|
| email | blank | `can't be blank` |
| email | not `^[^@,;\s]+@[^@,;\s]+$` | `must have the @ sign and no spaces` |
| email | > 160 chars | `should be at most 160 character(s)` |
| email | already used (on save only) | `has already been taken` |
| password | blank | `can't be blank` |
| password | < 12 chars | `should be at least 12 character(s)` |
| password | > 72 chars (or > 72 bytes, checked at hash time on save) | `should be at most 72 character(s)` (bytes variant: `should be at most 72 byte(s)`) |

### 3.3 `/users/settings` and `/users/settings/confirm-email/:token` - `UserLive.Settings`

Requires a non-guest account (router `require_real_account` plug and on_mount) AND sudo mode (`on_mount :require_sudo_mode`: the session token was authenticated within the last 10 minutes; see 0.3). A user restored from the 14-day remember-me cookie or session who logged in longer ago than 10 minutes is sent to `/users/log-in` with the error flash `You must re-authenticate to access this page.`, even for the confirm-email link.

**Mount, `:confirm_email` (params has "token"):** `Accounts.update_user_email(current_user, token)`. It looks up a stored email-change token for context `"change:<current email>"` (valid 7 days; the token's `sent_to` holds the new address), updates the email, deletes the user's tokens of that context, in one transaction. Success -> flash info `Email changed successfully.`; failure -> flash error `Email change link is invalid or it has expired.`. Either way `push_navigate("/users/settings")`.

**Mount, `:edit`:** assigns `current_email = user.email`; `email_form = to_form(change_user_email(user, %{}, validate_unique: false))`; `password_form = to_form(change_user_password(user, %{}, hash_password: false))`; `trigger_submit: false`. No `page_title`.

**Render**, verbatim:

```heex
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>
    </Layouts.app>
```

No container class: the content sits directly in `Layouts.app`'s padded `main`. Header text `Account Settings`, subtitle `Manage your account email address and password settings` (centered in `div.text-center`). Email form: `id="email_form"`, `phx-submit="update_email"`, `phx-change="validate_email"`; field `user[email]` (type email, label `Email`, autocomplete `username`, required) pre-filled with the current email; button `.button variant="primary" phx-disable-with="Changing..."` text `Change Email` (class `btn mg-btn`). Then `<div class="divider" />`. Password form: `id="password_form"`, `action="/users/update-password"`, `method="post"`, `phx-change="validate_password"`, `phx-submit="update_password"`, `phx-trigger-action={@trigger_submit}`; a hidden `<input name="user[email]" type="hidden" id="hidden_user_email" value={current_email}>`; `user[password]` (label `New password`, autocomplete `new-password`, required), `user[password_confirmation]` (label `Confirm new password`, autocomplete `new-password`, not required); button `variant="primary" phx-disable-with="Saving..."` text `Save Password`.

**Events**

- `validate_email` `%{"user" => params}`: validation changeset (no uniqueness), action `:validate`.
- `update_email` `%{"user" => params}`: asserts sudo mode (a `MatchError` crash if it has lapsed). `change_user_email(user, params)` (with uniqueness; error text `did not change` when the address equals the current one, `has already been taken` when used, plus the format/length messages from the registration table). Valid: `Accounts.deliver_user_update_email_instructions(user_with_new_email, old_email, url_fun)` stores a hashed token (context `change:<old email>`, `sent_to` new address; 7-day validity) and emails the NEW address a plain-text mail (from `"Marginalia" <contact@example.com>`, subject `Update email instructions`) with body:

  ```
  
  ==============================

  Hi <new email>,

  You can change your email by visiting the URL below:

  <absolute url of /users/settings/confirm-email/<token>>

  If you didn't request this change, please ignore this.

  ==============================
  ```

  then flash info `A link to confirm your email change has been sent to the new address.` (stay on page). Invalid: form re-rendered with errors (`action: :insert`). The email does NOT change until the link is visited.
- `validate_password` `%{"user" => params}`: password changeset without hashing, action `:validate` (live errors: `can't be blank`, `should be at least 12 character(s)`, `should be at most 72 character(s)`, and on the confirmation field `does not match password` whenever `password_confirmation` is submitted and differs from `password`, including as an empty string).
- `update_password` `%{"user" => params}`: asserts sudo mode; valid -> `trigger_submit: true` (browser then natively POSTs `password_form` to `/users/update-password`); invalid -> errors shown.

There is no delete-account, no 2FA, no session list, no provider selection here.

### 3.4 `UserSessionController`

**`POST /users/log-in` `create`**, params `%{"user" => %{"email", "password", "remember_me"? ("true")}}` (a request without `user[email]`/`user[password]` raises -> 500):

- `Accounts.get_user_by_email_and_password(email, password)` (exact-match email, `Bcrypt.verify_pass`; a timing-safe dummy verify runs when the user does not exist or has no password).
- Success: `put_flash(:info, "Welcome back!")`, then `UserAuth.log_in_user(conn, user, user_params)`:
  1. `user_return_to = get_session(:user_return_to)`.
  2. A new session-token row is inserted (`users_tokens`, context `"session"`, `authenticated_at = now`); the session is renewed unless the request is already authenticated as this same user (renew = new session id, cleared session data, CSRF token deleted; a previous guest session is simply discarded, its drafts are not moved).
  3. Session gets `user_token` and `live_socket_id`.
  4. The remember-me cookie `_marginalia_web_user_remember_me` (signed, 14 days, SameSite Lax, value = raw token) is written if `user[remember_me] == "true"` OR the session already has `user_remember_me == true` (which is then set again).
  5. `user_return_to` removed; redirect to `user_return_to`, else `/users/settings` if the incoming request already had a session user (a guest), else `/`.
- Failure: `put_flash(:error, "Invalid email or password")` (same message for unknown email and bad password), `put_flash(:email, first 160 chars of the submitted email)`, redirect `/users/log-in` (the login page prefills the email from that flash).

**`DELETE /users/log-out` `delete`**: `put_flash(:info, "Logged out successfully.")`; `log_out_user`: deletes the session-token row, broadcasts `"disconnect"` on the session's `live_socket_id` topic (closes the user's LiveViews in other tabs), clears the session and renews its id, deletes the remember-me cookie, redirects to `/`.

**`POST /users/update-password` `update_password`** (requires a non-guest user; CSRF-protected form post from the settings page, params `%{"user" => %{"email", "password", "password_confirmation"}}`): asserts sudo mode; `Accounts.update_user_password(user, params)` sets the new bcrypt hash and, in the same transaction, deletes ALL of the user's tokens (every session and remember-me token, i.e. every device); `disconnect_sessions(expired_tokens)` broadcasts `"disconnect"` to each token's `users_sessions:<b64 token>` topic; then `put_session(:user_return_to, "/users/settings")` and re-runs `create` with the submitted email/password and flash text `Password updated successfully!`, i.e. the user is logged in again on this device with a fresh token and lands on `/users/settings`. (`remember_me` is not in these params, so a remember-me cookie is re-issued only if the session already had `user_remember_me`.)

**Session lookup on every request** (`fetch_current_scope_for_user`): `user_token` from the session, else the signed remember-me cookie (then copied into the session with `user_remember_me = true`); `Accounts.get_user_by_session_token(token)` returns `{user (with authenticated_at from the token row), token.inserted_at}` only if the token row exists, context `"session"`, and is younger than 14 days; if it is 7 or more days old the session token is replaced (see 0.8). No user -> `current_scope = nil`.

---

## 4. Things that cannot be done with static HTML alone

1. The Read page's `.Follow` behaviour (scroll-synchronised column, drawn wire through the reason card, phone sheet, chip menu, peek) is wholly client code and ports as-is as long as the DOM contract (ids `fl-lead`, `fl-other`, `blk-lead-*`, `blk-other-*`, the hidden `data-*` spans, `.fl-*` classes) is emitted exactly; its single server dependency is the `cite_edge` event.
2. Live status of a link: the page must update when the background linker finishes (PubSub `link:<id>` -> recompute and re-render). A replacement needs a push channel (SSE/websocket) or polling.
3. Chat: asynchronous model call with in-memory history per page view, the "thinking" dots, the cited-edges chips that are added by the hook and cleared on send, and the replies rendered as sanitized Markdown.
4. Cut reading: a status machine (`draft -> reading -> read | failed`) with an in-process async task and the Weave SVG.
5. Forms that use `phx-change` for live validation (registration, settings) and `phx-trigger-action` (login, password change) to turn a LiveView event into a native POST; with plain forms these collapse to ordinary POST/redirect/flash flows.
6. Flash messages survive exactly one redirect and are cleared on click; session cookie is signed with a fixed salt and holds the DB token, so the replacement can share sessions with the old server only if it reads the same cookie format (Plug.Crypto signed term; Elixir external term format), otherwise users are logged out once.
